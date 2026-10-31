#!/bin/bash
# sec 모듈 1단계 따라하기 명령 모음 — Notion 페이지의 명령과 같다. 작성자가 따라하기 명령을 한 번에 검증할 때 쓴다.
#   source ~/opslab-env.sh && bash ~/opslab/common/start.sh sec && source ~/opslab-env.sh && bash ~/opslab/tools/build/sec.sh
# (Vault 초기화·엔진 설정은 Notion 에서는 수강생이 Session Manager 로 한 줄씩 하지만, 여기서는 layers/l4-secret.init.sh 로 한 번에 한다)
set -euo pipefail
source ~/opslab-env.sh
ACCT=$(aws sts get-caller-identity --query Account --output text)
T="Key=Course,Value=opslab Key=Module,Value=sec Key=Owner,Value=$SID"
TT="TagKey=Course,TagValue=opslab TagKey=Module,TagValue=sec TagKey=Owner,TagValue=$SID"

echo "== 1-2 KMS 키(관리 문장과 사용 문장 분리)와 별칭"
cat > /tmp/sec-key-policy.json <<EOF
{"Version":"2012-10-17","Id":"opslab-sec-key","Statement":[
 {"Sid":"Admin","Effect":"Allow","Principal":{"AWS":"arn:aws:iam::$ACCT:root"},
  "Action":["kms:Create*","kms:Describe*","kms:Enable*","kms:List*","kms:Put*","kms:Update*","kms:Revoke*","kms:Disable*",
            "kms:Get*","kms:Delete*","kms:TagResource","kms:UntagResource","kms:ScheduleKeyDeletion","kms:CancelKeyDeletion","kms:RotateKeyOnDemand"],"Resource":"*"},
 {"Sid":"AccountUseViaSecretsManager","Effect":"Allow","Principal":{"AWS":"arn:aws:iam::$ACCT:root"},
  "Action":["kms:Encrypt","kms:Decrypt","kms:GenerateDataKey*","kms:ReEncrypt*","kms:DescribeKey"],"Resource":"*",
  "Condition":{"StringEquals":{"kms:ViaService":"secretsmanager.$AWS_REGION.amazonaws.com"}}},
 {"Sid":"AppUse","Effect":"Allow","Principal":{"AWS":"arn:aws:iam::$ACCT:role/$SID-base-ec2-role"},
  "Action":["kms:Decrypt","kms:DescribeKey"],"Resource":"*"}]}
EOF
KEY_ID=$(aws kms create-key --description "opslab sec - Secrets Manager key" --policy file:///tmp/sec-key-policy.json \
  --tags $TT --query KeyMetadata.KeyId --output text)
aws kms enable-key-rotation --key-id $KEY_ID
aws kms create-alias --alias-name alias/$SID-sec-key --target-key-id $KEY_ID
echo "KEY_ID=$KEY_ID"

echo "== 1-3 Secrets Manager 비밀(앱의 외부 연동 키)"
aws secretsmanager create-secret --name $SID/sec/app --kms-key-id alias/$SID-sec-key \
  --description "partner API key used by the sample app (/secret)" \
  --secret-string "{\"partner\":\"opslab-partner\",\"api_key\":\"$(openssl rand -hex 16)\"}" --tags $T --query ARN --output text

echo "== 1-4 앱 역할에 비밀 읽기 권한(인라인 정책)"
ARN=$(aws secretsmanager describe-secret --secret-id $SID/sec/app --query ARN --output text)
aws iam put-role-policy --role-name $SID-base-ec2-role --policy-name $SID-sec-app-access --policy-document \
  "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Sid\":\"ReadAppSecret\",\"Effect\":\"Allow\",\"Action\":\"secretsmanager:GetSecretValue\",\"Resource\":\"$ARN\"}]}"

echo "== 1-5 앱 서버 내부 HTTPS(8443) 허용"
APP_SG=$(aws ec2 describe-security-groups --filters Name=group-name,Values=$SID-cmp-app-sg --query 'SecurityGroups[0].GroupId' --output text)
aws ec2 authorize-security-group-ingress --group-id $APP_SG --ip-permissions \
  'IpProtocol=tcp,FromPort=8443,ToPort=8443,IpRanges=[{CidrIp=10.0.0.0/16,Description="internal HTTPS (Vault PKI cert)"}]' >/dev/null

echo "== 1-6 Vault 서버(보안 그룹 + EC2)"
SG=$(aws ec2 create-security-group --group-name $SID-sec-vault-sg --description "Vault API 8200 from base VPC" --vpc-id $VPC_ID \
  --tag-specifications "ResourceType=security-group,Tags=[{Key=Name,Value=$SID-sec-vault-sg},{Key=Course,Value=opslab},{Key=Module,Value=sec},{Key=Owner,Value=$SID}]" \
  --query GroupId --output text)
aws ec2 authorize-security-group-ingress --group-id $SG --protocol tcp --port 8200 --cidr 10.0.0.0/16 >/dev/null
AMI=$(aws ssm get-parameter --name /aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64 --query Parameter.Value --output text)
printf '#!/bin/bash\ncurl -fsSL https://raw.githubusercontent.com/worldvit/aws-ops-lab/main/app/vault-server.sh | bash\n' > /tmp/vault-ud.sh
aws ec2 run-instances --image-id $AMI --instance-type t3.small --subnet-id ${APP_SUBNETS%%,*} --security-group-ids $SG \
  --iam-instance-profile Name=$SID-base-ec2-profile --user-data file:///tmp/vault-ud.sh \
  --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$SID-sec-vault},{Key=Course,Value=opslab},{Key=Module,Value=sec},{Key=Owner,Value=$SID}]" \
  --query 'Instances[0].InstanceId' --output text
sleep 30

echo "== 1-7 ~ 1-11 Vault 초기화·잠금 해제·엔진 설정·앱 서버 Agent (Notion 에서는 단계별로 직접)"
bash ~/opslab/layers/l4-secret.init.sh

echo "== 1-12 동작 확인"
sleep 10
for p in /db /note /secret; do curl -s http://$ALB_DNS$p; echo; done
echo "✅ 1단계 명령 완료"
