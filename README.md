# aws-ops-lab — Ops Lab (AWS 인프라 운영 장애 대응 실습)

수강생이 자기 AWS 계정에서 장애를 직접 주입·관찰·복구하며 운영 절차를 익히는 8일 실습 자료입니다.
고객사·계정 제공사와 관계없이 쓰도록 공통 이름(`opslab`)을 사용합니다.

| 경로 | 내용 |
|---|---|
| `app/` | Flask 샘플 앱 (/health · /api · /db · /slow) |
| `cfn/day0-student.yaml` | Day 0 스택: 강사 읽기 전용 역할, FIS 실험 역할, Budgets 알람, 권한 경계 정책 |
| `cfn/dayN-*.yaml` | Day별 주변 구성 템플릿 |
| `start/dayN.yaml` | Day별 시작 템플릿(앞 Day 완료 상태를 한 스택으로) — `start/day2.yaml` 은 Day 1 따라잡기로도 사용 |
| `common/inject.sh` | 장애 주입·해결 기록·원복·현황 도구 (`bash ~/opslab/common/inject.sh 1-1`) |
| `common/labs.csv` | Lab 번호 ↔ 장애 디렉터리 ↔ 장애 유형 |
| `common/{load,cleanup}.sh` | 부하 도구, 매일 정리(Day 0 스택을 뺀 전부 삭제) |
| `dayN/<장애명>/{inject,verify,rollback}.sh` | 장애별 3종 세트 |
| `runbook/TEMPLATE.md` | 런북 양식 |

모든 리소스 태그: `Course=opslab`, `Day=<n>`, `Owner=<학번>` · 주입 기록: SSM `/opslab/injections/<Lab>`
