#!/bin/bash
# auto 모듈 verify 공통. verify.sh 들이 source 한다.
AUTO_NO_LAB=1 source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/lib.sh"
PASS=0; FAIL=0
ok() { echo "  [PASS] $*"; PASS=$((PASS+1)); }
ng() { echo "  [FAIL] $*"; FAIL=$((FAIL+1)); }
start() { echo "== $(date '+%F %T') 정상 상태 판정: $SID / auto $1 =="; }

chk_online() {  # ASG 의 모든 앱 서버가 SSM 에 연결(Online)
  local i p bad=""; for i in $(asg_ids); do p=$(ping_of "$i"); [ "$p" = Online ] || bad="$bad $i:${p:-미등록}"; done
  [ -z "$bad" ] && ok "앱 서버 $(wc -w <<<"$(asg_ids)")대 모두 SSM 연결 Online" || ng "SSM 연결 끊김:$bad"
}
chk_session() {  # 세션 접속 + 접속 기록(로그 그룹에 남는지)
  local g i tok out n=0; g=$(pref_group)
  [ "$g" = "$LOGG" ] && ok "접속 기록 설정: CloudWatch Logs $g" || ng "접속 기록 설정 로그 그룹 '${g:-없음}' (기대 $LOGG)"
  local enc; enc=$(aws ssm get-document --name "$PREF" --query Content --output text 2>/dev/null | jq -r '.inputs.cloudWatchEncryptionEnabled')
  [ "$enc" = false ] && ok "로그 암호화 요구 꺼짐(로그 그룹이 KMS 암호화가 아님)" || ng "cloudWatchEncryptionEnabled=$enc — 암호화되지 않은 로그 그룹이면 세션이 거부됨"
  i=$(asg_ids | awk '{print $1}'); tok="opslab-probe-$(date +%s)"
  out=$(session_probe "$i" "$tok")
  if grep -q "$tok" <<<"$out"; then ok "세션 접속 $i: 명령 실행됨"
  else ng "세션 접속 $i 실패: $(grep -v '^$' <<<"$out" | grep -v "$tok" | tail -2 | tr '\n' ' ' | cut -c1-200)"; return; fi
  for _ in $(seq 1 12); do
    n=$(aws logs filter-log-events --log-group-name "$LOGG" --filter-pattern "\"$tok\"" --query 'events[].eventId' --output text 2>/dev/null | wc -w); [ "$n" -ge 1 ] && break; sleep 5
  done
  [ "${n:-0}" -ge 1 ] && ok "접속 기록이 $LOGG 에 남음" || ng "세션은 됐지만 접속 기록이 $LOGG 에 60초 안에 남지 않음"
}
chk_runcmd() {  # 태그 대상 Run Command 가 ASG 의 모든 서버에서 성공
  local want c t s; want=$(wc -w <<<"$(asg_ids)")
  read -r c t s <<<"$(run_tag 'hostname')"
  [ "$t" = "$want" ] && [ "$s" = "$want" ] && ok "Run Command(태그 Name=$APP_TAG) 대상 $t대 / 성공 $s대 (ASG $want대)" \
    || ng "Run Command 대상 ${t:-0}대 / 성공 ${s:-0}대 — ASG 는 ${want}대 (명령 $c)"
}
chk_runbook() {  # 안전 스위치 on + 런북 실행 성공
  local sw e r; sw=$(aws ssm get-parameter --name "$SWITCH" --query Parameter.Value --output text 2>/dev/null)
  [ "$sw" = on ] && ok "안전 스위치 $SWITCH = on" || ng "안전 스위치 $SWITCH = ${sw:-없음}"
  e=$(run_runbook); [[ "$e" =~ ^[0-9a-f-]{36}$ ]] || { ng "런북 시작 실패: ${e:0:150}"; return; }
  r=$(wait_runbook "$e")
  [ "$r" = Success ] && ok "런북 $RUNBOOK 실행 Success ($e)" || ng "런북 실행 $r: $(failed_step "$e" | tr '\t\n' '  ' | cut -c1-220)"
}
chk_chain() {  # 알람 → 규칙 → 런북 구성 + 실패 알림 규칙
  local a r t
  a=$(aws cloudwatch describe-alarms --alarm-names "$ALARM" --query 'MetricAlarms[0].[MetricName,Threshold,Dimensions[0].Value,ComparisonOperator]' --output text 2>/dev/null)
  [ "$a" = "HTTPCode_Target_5XX_Count	10.0	$(alb_full)	GreaterThanOrEqualToThreshold" ] && ok "알람 $ALARM: 5xx 1분 10건 이상, 내 ALB" || ng "알람 $ALARM 설정: ${a:-없음}"
  r=$(aws events describe-rule --name "$RULE" --query State --output text 2>/dev/null)
  [ "$r" = ENABLED ] && ok "규칙 $RULE ENABLED" || ng "규칙 $RULE ${r:-없음}"
  t=$(aws events list-targets-by-rule --rule "$RULE" --query 'Targets[0].[Arn,RoleArn]' --output text 2>/dev/null)
  [ "$t" = "$RUNBOOK_ARN	$EVENTS_ROLE_ARN" ] && ok "규칙 대상: 런북 $RUNBOOK, 역할 $SID-auto-events-role" || ng "규칙 대상: ${t:-없음}"
  aws iam get-role-policy --role-name "$SID-auto-events-role" --policy-name start-automation >/dev/null 2>&1 \
    && ok "EventBridge 역할에 런북 시작 권한(start-automation)" || ng "EventBridge 역할 $SID-auto-events-role 에 start-automation 정책 없음"
  r=$(aws events describe-rule --name "$FRULE" --query State --output text 2>/dev/null)
  [ "$r" = ENABLED ] && ok "실패 알림 규칙 $FRULE ENABLED" || ng "실패 알림 규칙 $FRULE ${r:-없음}"
}
chk_e2e() {  # 연결 시험: 알람을 ALARM 으로 바꾸면 런북이 시작되는가
  local t0 e; t0=$(date +%s)
  aws cloudwatch set-alarm-state --alarm-name "$ALARM" --state-value OK --state-reason "opslab verify reset" 2>/dev/null; sleep 3
  aws cloudwatch set-alarm-state --alarm-name "$ALARM" --state-value ALARM --state-reason "opslab verify: 자동 복구 연결 시험" 2>/dev/null
  e=$(runbook_since "$t0" 90)
  [ "$e" != None ] && ok "연결 시험: 알람 ALARM → 런북 시작됨 ($e, $(wait_runbook "$e"))" || ng "연결 시험: 알람을 ALARM 으로 바꿨지만 90초 안에 런북이 시작되지 않음"
}
chk_service() {  # /api 20번 모두 200 (재시작 직후의 순간 오류를 피하려고 한 번 더 시도)
  local n; n=$(api_ok 20); [ "$n" = 20 ] || { sleep 15; n=$(api_ok 20); }
  [ "$n" = 20 ] && ok "/api 20/20 정상(200)" || ng "/api 정상 $n/20 — 오류 응답이 섞임"
}
chk_mw() {  # 유지관리 기간: 켜짐 + 대상 태그 + 패치 작업
  local w e t k; w=$(aws ssm describe-maintenance-windows --filters Key=Name,Values="$MW" --query 'WindowIdentities[0].WindowId' --output text 2>/dev/null)
  [ -n "$w" ] && [ "$w" != None ] || { ng "유지관리 기간 $MW 없음"; return; }
  e=$(aws ssm get-maintenance-window --window-id "$w" --query Enabled --output text)
  [ "$e" = True ] && ok "유지관리 기간 $MW 켜짐($(aws ssm get-maintenance-window --window-id "$w" --query Schedule --output text))" || ng "유지관리 기간 $MW Enabled=$e"
  t=$(aws ssm describe-maintenance-window-targets --window-id "$w" --query 'Targets[0].Targets[0].[Key,Values[0]]' --output text)
  [ "$t" = "tag:Name	$APP_TAG" ] && ok "대상: 태그 Name=$APP_TAG (실행 중 $(wc -w <<<"$(app_ids)")대)" || ng "대상 태그 ${t:-없음} (기대 tag:Name $APP_TAG)"
  k=$(aws ssm describe-maintenance-window-tasks --window-id "$w" --query 'Tasks[0].TaskArn' --output text)
  [ "$k" = AWS-RunPatchBaseline ] && ok "작업: AWS-RunPatchBaseline" || ng "작업 ${k:-없음}"
  echo "  (참고) 최근 실행: $(aws ssm describe-maintenance-window-executions --window-id "$w" --max-results 1 --query 'WindowExecutions[0].[Status,StartTime]' --output text 2>/dev/null)"
}
chk_failover() {  # 헬스 체크 설정·판정 + 주 레코드 연결 + DNS 응답이 주(ALB)
  local h c hs rr ans sb
  h=$(hc_id); [ -n "$h" ] && [ "$h" != None ] || { ng "ALB($(alb_dns))를 보는 헬스 체크 없음"; return; }
  c=$(aws route53 get-health-check --health-check-id "$h" --query 'HealthCheck.HealthCheckConfig.[Type,Port,ResourcePath,Inverted,Disabled]' --output text)
  [ "$c" = "HTTP	80	/health	False	False" ] && ok "헬스 체크 $h: HTTP :80 /health" || ng "헬스 체크 설정: $c (기대 HTTP 80 /health False False)"
  hs=$(hc_healthy "$h"); [ "${hs%/*}" -gt $(( ${hs#*/} / 2 )) ] 2>/dev/null && ok "헬스 체커 정상 $hs" || ng "헬스 체커 정상 ${hs:-?} (과반 미달 = 주 서비스 비정상 판정)"
  rr=$(aws route53 list-resource-record-sets --hosted-zone-id "$(zone_id)" --query "ResourceRecordSets[?Name=='$REC.' && SetIdentifier=='primary'].HealthCheckId | [0]" --output text)
  [ "$rr" = "$h" ] && ok "주(PRIMARY) 레코드에 헬스 체크 연결됨" || ng "주(PRIMARY) 레코드의 헬스 체크: ${rr:-없음} (기대 $h)"
  sb=$(env_out StandbyIp); ans=$(dns_answer | tr '\t' ' ')
  [ -n "$ans" ] && ! grep -qw "$sb" <<<"$ans" && ok "DNS $REC → 주 서비스(ALB) $ans" || ng "DNS $REC → '${ans:-응답 없음}' (예비 서버 $sb 로 전환되어 있음)"
  c=$(curl -s -o /dev/null -m 5 -w '%{http_code}' "http://$(alb_dns)/health")
  [ "$c" = 200 ] && ok "주 서비스 ALB /health 200" || ng "주 서비스 ALB /health $c"
}
finish() {
  echo "== 결과: PASS $PASS / FAIL $FAIL =="
  if [ "$FAIL" -eq 0 ]; then echo "판정: 정상 (verify 통과) — 기록표에 '복구 완료 시각'과 '통과'를 적으세요"; exit 0
  else echo "판정: 비정상"; exit 1; fi
}
