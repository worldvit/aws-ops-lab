# aws-ops-lab — Ops Lab (AWS 인프라 운영 장애 대응 실습)

수강생이 자기 AWS 계정에서 장애를 직접 주입·관찰·복구하며 운영 절차를 익히는 실습 모듈 모음입니다.
모듈은 과정·고객사·Day 번호와 무관하게 만들고, 과정마다 `courses/<과정ID>.yaml` 하나로 조립합니다.

| 경로 | 내용 |
|---|---|
| `courses/<과정ID>.yaml` | 과정 파일: 고객사·계정 제공사·Notion·도메인, Day↔모듈 순서 |
| `modules/<모듈ID>/module.yaml` | 모듈 정의: 제목, 필요한 환경 층(requires), 직접 구축하는 층(builds), Lab 목록 |
| `modules/<모듈ID>/faults/<장애명>/{inject,verify,rollback}.sh` | 장애별 3종 세트 |
| `modules/<모듈ID>/baseline/verify.sh` | 정상 상태 정의(2단계) 판정 |
| `modules/<모듈ID>/{lib,cleanup}.sh` | 모듈 공통 함수, 매일 정리 훅(CLI로 직접 만든 리소스 삭제) |
| `modules/<모듈ID>/{env,done}.yaml` | (선택) 모듈 주변 구성 템플릿, 직접 구축하는 것의 완료 상태 템플릿(따라잡기·시험용) |
| `layers/l0-guard.yaml` | L0 보호 장치(Day 0에 1회): 강사 읽기 전용 역할, FIS 역할, Budgets, 하위 도메인, 권한 경계 |
| `layers/l1-network.yaml`, `l2-app.yaml`, `l3-data.yaml`, `l4-secret.yaml` … | 환경 층 L1(네트워크 기반)·L2(앱 계층 = cmp 완료 상태)·L3(데이터 계층 = data 완료 상태)·L4(시크릿 계층 = sec 완료 상태) … `<층>.init.sh` 가 있으면 배포 뒤 실행 |
| `common/start.sh <모듈ID> [full]` | 모듈에 필요한 환경 층 배포(full: 직접 구축할 층까지 = 따라잡기) |
| `common/inject.sh <Lab ID>` | 장애 주입·해결 기록(done)·원복(rollback)·현황(status) |
| `common/{load,cleanup}.sh` | 부하 도구, 매일 정리(L0 층을 뺀 전부 삭제) |
| `tools/test-module.sh <모듈ID>` | 모듈 독립 시험(층 배포 → verify → 모든 변형 주입·원복 → 정리). `DEEP=<초>` 주입 후 증상·원복 후 판정까지 검사 |
| `tools/build/<모듈ID>.sh` | 따라하기 1단계 명령 모음(작성자 검증용) |
| `app/` | Flask 샘플 앱 (/health · /api · /db · /slow) |
| `runbook/TEMPLATE.md` | 런북 양식 |

| 모듈 ID | 모듈 | requires | builds |
|---|---|---|---|
| cmp | 컴퓨팅과 로드밸런싱 장애 | L1 | L2 |
| net | 네트워크 연결 장애 (주변 구성 env.yaml, 완료 상태 done.yaml, 경로 점검 probe.sh) | L2 | — |
| data | 데이터 계층 운영 (Aurora PostgreSQL, 점검 probe.sh, L3 초기화 layers/l3-data.init.sh) | L2 | L3 |
| sec | 시크릿과 인증 운영 (KMS·Secrets Manager·Vault — 동적 자격증명·PKI·Transit, 점검 probe.sh, L4 초기화 layers/l4-secret.init.sh) | L3 | L4 |
| sec · iac · cicd · auto · rel | (작성 예정) | | |

이름: `<학번>-<모듈ID|base>-<역할>` · 태그: `Course=opslab`, `Module=<모듈ID|base>`, `Owner=<학번>` · Lab ID: `<모듈ID>-<번호>` · 주입 기록: SSM `/opslab/injections/<Lab ID>`
