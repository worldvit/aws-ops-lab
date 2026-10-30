#!/bin/bash
# verify.sh — 정상 상태 지표를 측정하고 기준값과 비교해 판정한다.
# 실행 위치: CloudShell   사용법: SID=s01 bash verify.sh
# 부하 도구(load.sh)가 5분 이상 돌고 있어야 지표 판정이 정확하다.
set -uo pipefail
: "${SID:?SID 환경변수에 학번을 넣으세요. 예) export SID=s01}"
export AWS_REGION="${AWS_REGION:-ap-northeast-2}"
PASS=0; FAIL=0
ok()   { echo "  [PASS] $*"; PASS=$((PASS+1)); }
ng()   { echo "  [FAIL] $*"; FAIL=$((FAIL+1)); }

ALB_ARN=$(aws elbv2 describe-load-balancers --names "$SID-d1-alb" --query 'LoadBalancers[0].LoadBalancerArn' --output text 2>/dev/null)
TG_ARN=$(aws elbv2 describe-target-groups --names "$SID-d1-tg" --query 'TargetGroups[0].TargetGroupArn' --output text 2>/dev/null)
ASG="$SID-d1-asg"
[ -z "$ALB_ARN" ] || [ "$ALB_ARN" = "None" ] && { echo "ALB $SID-d1-alb 을 찾을 수 없습니다"; exit 2; }
[ -z "$TG_ARN" ]  || [ "$TG_ARN" = "None" ]  && { echo "타깃 그룹 $SID-d1-tg 을 찾을 수 없습니다"; exit 2; }
LB_DIM=${ALB_ARN#*:loadbalancer/}
TG_DIM=${TG_ARN##*:}

metric_sum() {  # $1=지표명 $2=추가차원(옵션) — 최근 5분 합계
  local dims="Name=LoadBalancer,Value=$LB_DIM"; [ -n "${2:-}" ] && dims="$dims $2"
  aws cloudwatch get-metric-statistics --namespace AWS/ApplicationELB --metric-name "$1" \
    --dimensions $dims --start-time "$(date -u -d '-5 min' +%FT%TZ)" --end-time "$(date -u +%FT%TZ)" \
    --period 300 --statistics Sum --query 'sum(Datapoints[].Sum)' --output text 2>/dev/null | sed 's/None/0/'
}
metric_avg() {
  aws cloudwatch get-metric-statistics --namespace AWS/ApplicationELB --metric-name "$1" \
    --dimensions Name=LoadBalancer,Value="$LB_DIM" Name=TargetGroup,Value="$TG_DIM" \
    --start-time "$(date -u -d '-5 min' +%FT%TZ)" --end-time "$(date -u +%FT%TZ)" \
    --period 300 --statistics Average --query 'Datapoints[0].Average' --output text 2>/dev/null | sed 's/None/0/'
}

echo "== $(date '+%F %T') 정상 상태 판정: $SID / Day1 asg-no-scale =="

echo "[1] 타깃 상태"
DESIRED=$(aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names "$ASG" --query 'AutoScalingGroups[0].DesiredCapacity' --output text)
HEALTHY=$(aws elbv2 describe-target-health --target-group-arn "$TG_ARN" --query 'length(TargetHealthDescriptions[?TargetHealth.State==`healthy`])' --output text)
TOTAL=$(aws elbv2 describe-target-health --target-group-arn "$TG_ARN" --query 'length(TargetHealthDescriptions)' --output text)
[ "$HEALTHY" -ge "$DESIRED" ] && [ "$HEALTHY" -eq "$TOTAL" ] && ok "healthy $HEALTHY / 등록 $TOTAL / 희망 용량 $DESIRED" \
  || ng "healthy $HEALTHY / 등록 $TOTAL / 희망 용량 $DESIRED (기준: 전부 healthy, 희망 용량 이상)"

echo "[2] Auto Scaling 그룹"
INSVC=$(aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names "$ASG" --query 'length(AutoScalingGroups[0].Instances[?LifecycleState==`InService` && HealthStatus==`Healthy`])' --output text)
[ "$INSVC" -eq "$DESIRED" ] && ok "InService·Healthy 인스턴스 $INSVC = 희망 용량 $DESIRED" || ng "InService·Healthy $INSVC ≠ 희망 용량 $DESIRED"
SUSP=$(aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names "$ASG" --query 'join(`,`, AutoScalingGroups[0].SuspendedProcesses[].ProcessName)' --output text)
[ -z "$SUSP" ] && ok "중지된 프로세스 없음" || ng "중지된 프로세스: $SUSP (실습 종료 시 모두 재개해야 함)"
REFRESH=$(aws autoscaling describe-instance-refreshes --auto-scaling-group-name "$ASG" --query 'length(InstanceRefreshes[?Status==`InProgress` || Status==`Pending` || Status==`Cancelling`])' --output text)
[ "$REFRESH" -eq 0 ] && ok "진행 중인 인스턴스 새로 고침 없음" || ng "진행 중인 인스턴스 새로 고침 $REFRESH 건"

echo "[3] 최근 5분 지표 (부하 도구 실행 중이어야 함)"
REQ=$(metric_sum RequestCount)
[ "${REQ%.*}" -gt 0 ] && ok "요청 수 ${REQ%.*}건" || ng "요청 수 0건 — load.sh 가 실행 중인지 확인"
E5=$(metric_sum HTTPCode_ELB_5XX_Count); T5=$(metric_sum HTTPCode_Target_5XX_Count)
[ "${E5%.*}" -eq 0 ] && ok "ALB(ELB) 5xx 0건" || ng "ALB(ELB) 5xx ${E5%.*}건 (기준 0건)"
[ "${T5%.*}" -eq 0 ] && ok "타깃 5xx 0건" || ng "타깃 5xx ${T5%.*}건 (기준 0건)"
RT=$(metric_avg TargetResponseTime)
awk "BEGIN{exit !($RT <= 0.2)}" && ok "평균 응답시간 $(awk "BEGIN{printf \"%.0f\", $RT*1000}")ms (기준 200ms 이하)" \
  || ng "평균 응답시간 $(awk "BEGIN{printf \"%.0f\", $RT*1000}")ms (기준 200ms 이하)"

echo "[4] 확장 가능 상태"
read -r MIN MAX <<<"$(aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names "$ASG" --query 'AutoScalingGroups[0].[MinSize,MaxSize]' --output text)"
[ "$MAX" -gt "$MIN" ] && ok "최대 용량 $MAX > 최소 용량 $MIN (확장 여유가 설계되어 있음, 현재 희망 $DESIRED)" || ng "최대 용량 $MAX = 최소 용량 $MIN (확장할 수 없는 설정)"
POL=$(aws autoscaling describe-policies --auto-scaling-group-name "$ASG" --query 'length(ScalingPolicies[?PolicyType==`TargetTrackingScaling` && Enabled])' --output text)
[ "$POL" -ge 1 ] && ok "활성화된 대상 추적 정책 $POL개" || ng "활성화된 대상 추적 정책 없음"
read -r LT_ID LT_VER <<<"$(aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names "$ASG" --query 'AutoScalingGroups[0].LaunchTemplate.[LaunchTemplateId,Version]' --output text)"
PROFILE=$(aws ec2 describe-launch-template-versions --launch-template-id "$LT_ID" --versions "$LT_VER" --query 'LaunchTemplateVersions[0].LaunchTemplateData.IamInstanceProfile.Name' --output text)
aws iam get-instance-profile --instance-profile-name "$PROFILE" >/dev/null 2>&1 \
  && ok "시작 템플릿 $LT_VER 의 인스턴스 프로파일 $PROFILE 존재" || ng "시작 템플릿 $LT_VER 의 인스턴스 프로파일 $PROFILE 없음"
FAILED=$(aws autoscaling describe-scaling-activities --auto-scaling-group-name "$ASG" --max-items 5 --query 'length(Activities[?StatusCode==`Failed`] || `[]`)' --output text | head -1)
[ "${FAILED:-0}" -eq 0 ] && ok "최근 활동 5건 중 실패 0건" || ng "최근 활동 5건 중 실패 ${FAILED}건"

echo "== 결과: PASS $PASS / FAIL $FAIL =="
if [ "$FAIL" -eq 0 ]; then echo "판정: 정상 (verify 통과) — 기록표에 '복구 완료 시각'과 '통과'를 적으세요"; exit 0
else echo "판정: 비정상"; exit 1; fi
