# 이론 강의용 draw.io 다이어그램 생성기 — 기본 도형만 사용(어디서 열어도 동일하게 보이도록)
import html
class D:
    def __init__(s, name): s.name=name; s.cells=[]; s.n=0
    def _id(s): s.n+=1; return f"c{s.n}"
    def box(s, label, x, y, w, h, style="", parent="1"):
        i=s._id()
        st="rounded=1;whiteSpace=wrap;html=1;arcSize=8;fontSize=13;"+style
        s.cells.append(f'<mxCell id="{i}" value="{html.escape(html.escape(label,quote=False)).replace(chr(10),"&lt;br&gt;")}" style="{st}" vertex="1" parent="{parent}"><mxGeometry x="{x}" y="{y}" width="{w}" height="{h}" as="geometry"/></mxCell>')
        return i
    def group(s, label, x, y, w, h, style=""):
        return s.box(label, x, y, w, h, "verticalAlign=top;align=left;spacingLeft=10;spacingTop=4;fontStyle=1;"+style)
    def text(s, label, x, y, w, h, style=""):
        return s.box(label, x, y, w, h, "text;strokeColor=none;fillColor=none;align=left;verticalAlign=middle;"+style)
    def edge(s, a, b, label="", style="", points=None):
        i=s._id()
        st="edgeStyle=orthogonalEdgeStyle;rounded=1;html=1;endArrow=block;endFill=1;strokeWidth=2;fontSize=12;labelBackgroundColor=#ffffff;"+style
        s.cells.append(f'<mxCell id="{i}" value="{html.escape(label)}" style="{st}" edge="1" parent="1" source="{a}" target="{b}"><mxGeometry relative="1" as="geometry">'+(('<Array as="points">'+''.join(f'<mxPoint x="{x}" y="{y}"/>' for x,y in points)+'</Array>') if points else '')+'</mxGeometry></mxCell>')
    def xml(s):
        return ('<mxfile host="opslab"><diagram name="'+s.name+'"><mxGraphModel dx="1200" dy="800" grid="1" gridSize="10" page="0"><root><mxCell id="0"/><mxCell id="1" parent="0"/>'
                + "".join(s.cells) + '</root></mxGraphModel></diagram></mxfile>')
    def save(s, path): open(path,"w").write(s.xml())

# 색
AWS="fillColor=#FFF4E5;strokeColor=#ED7100;"; VPC="fillColor=#F2F8EC;strokeColor=#7AA116;dashed=1;"
SUB="fillColor=#E9F3E6;strokeColor=#7AA116;"; NODE="fillColor=#EAF2FB;strokeColor=#2F6FB3;"
POD="fillColor=#326CE5;fontColor=#ffffff;strokeColor=#1F4FB0;fontStyle=1;"; SYS="fillColor=#DAE8FC;strokeColor=#6C8EBF;"
OK="fillColor=#D5E8D4;strokeColor=#82B366;"; BAD="fillColor=#F8CECC;strokeColor=#B85450;"; NOTE="fillColor=#FFF2CC;strokeColor=#D6B656;"
GRAY="fillColor=#F5F5F5;strokeColor=#666666;"; CP="fillColor=#FFE6CC;strokeColor=#D79B00;"






P="docs/diagrams/heal/"
SVC="fillColor=#E1D5E7;strokeColor=#9673A6;"

# ① 아키텍처
d=D("1. 오늘 만드는 자가 복구·무중단 구조")
d.group("AWS 가 운영",20,20,1140,110,AWS)
cw=d.box("CloudWatch\nALB 지표(오류율·응답시간)",40,60,260,55,AWS+"fontStyle=1;")
mg=d.box("관리형 노드 그룹 — 자동 복구\n(절반 넘게 아프면 멈춤 · 한 번에 1대)",330,60,380,55,AWS+"fontStyle=1;")
alb=d.box("ALB — stable·canary 파드에\n파드 수 비율대로 나눠 보냄",880,60,260,55,SVC)
zs=[("AZ-a",20),("AZ-b",410),("AZ-c",800)]
for i,(z,x) in enumerate(zs):
    d.group(z,x,160,360,330,SUB)
    d.group("노드 "+str(i+1)+" (kubelet = 현장 반장)",x+15,195,330,280,NODE)
s1=d.box("stable 파드 v2\nstartup·liveness·readiness",50,240,280,60,POD)
c1=d.box("canary 파드 v3 (50%)\n먼저 손님 일부에게",440,240,280,60,POD+"strokeColor=#D79B00;strokeWidth=2;")
s2=d.box("stable 파드 v2",830,240,280,60,POD)
ar=d.box("Argo Rollouts 컨트롤러\n(카나리 진행·판정)",440,325,280,55,SYS+"fontStyle=1;")
d.box("Argo CD (Git 감시원)\nselfHeal",50,325,280,55,SYS)
d.box("PostgreSQL · Vault",830,325,280,55,GRAY)
d.box("PDB: 최소 1개 유지(점검 중에도) · topology spread: AZ 마다 고르게",50,410,1060,45,NOTE+"fontStyle=1;")
d.edge(cw,ar,"분석(IRSA)","exitX=0.5;exitY=1;entryX=0;entryY=0.5;",points=[(170,145),(395,145),(395,352)])
d.save(P+"01-architecture.drawio")

# ② probe 역할
d=D("2. 건강검진(probe) 역할 — 느린 앱의 하루")
d.text("시간 →",20,20,100,30,"fontStyle=1;")
d.box("0~35초: 프로세스 기동 중\n(포트 닫힘)",20,60,300,70,BAD)
d.box("35~50초: 캐시 데우기\n/health 200 · /ready 503",340,60,300,70,NOTE)
d.box("50초~: 손님 받음\n/health 200 · /ready 200",660,60,300,70,OK)
d.box("startup /health — \"아직 출근 준비 중\"\n성공할 때까지 liveness·readiness 를 쉬게 함 (최대 90초)",20,160,620,60,SYS)
d.box("readiness /ready — \"손님 받을 준비?\" 아니면 트래픽에서 뺌(재시작 X)",340,240,620,55,POD)
d.box("liveness /health — \"살아 있나?\" 아니면 재시작\n얕게: 프로세스만. DB 같은 바깥 의존성은 보지 않는다",660,315,480,65,CP)
d.box("✗ liveness 가 DB 까지 보면: DB 3분 장애 → 모든 파드 재시작 → 재시작 대기(백오프)로 더 길게 → 자동화가 장애를 키움",20,410,1120,50,BAD+"fontStyle=1;")
d.save(P+"02-probes.drawio")

# ③ 카나리와 드레인
d=D("3. 카나리 판정과 점검(드레인)")
d.group("카나리 배포 (Rollout)",20,20,560,420,SYS)
a=d.box("새 커밋(v3)",40,60,160,45,NOTE)
b=d.box("setWeight 50\ncanary 파드 1개",230,60,160,55,POD)
c=d.box("pause 60초",420,60,140,45,GRAY)
e=d.box("analysis\nCloudWatch: 오류율·응답시간\n3번 재고 2번 실패면 중단",230,150,330,70,CP+"fontStyle=1;")
f=d.box("성공 → setWeight 100\nv3 가 stable",40,260,240,60,OK)
g=d.box("실패 → abort\ncanary 내리고 v2 유지",320,260,240,60,BAD)
d.edge(a,b,""); d.edge(b,c,""); d.edge(c,e,"","exitX=0.5;exitY=1;entryX=0.8;entryY=0;"); d.edge(e,f,"",""); d.edge(e,g,"","")
d.box("주의: 판정 조건이 '데이터 없음'을 통과로 보면 결함 버전도 끝까지 나간다",40,350,520,60,NOTE)
d.group("노드 점검 — drain(이사)",610,20,550,420,NODE)
d.box("PDB 없음 + 노드 2대 동시 drain\n→ 파드 2개가 한꺼번에 축출 → 새 파드가 뜰 때까지(약 50초) 서비스 중단",630,60,510,70,BAD)
d.box("PDB minAvailable 1\n→ 두 번째 축출은 첫 파드가 새로 뜰 때까지 기다림 → 중단 없음",630,150,510,70,OK)
d.box("PDB minAvailable = 파드 수(2)\n→ 축출이 영원히 거절 → 점검이 끝나지 않음",630,240,510,70,NOTE)
d.box("모든 파드를 한 AZ 에 고정 → 그 AZ 가 끊기면 전부 중단\n→ topology spread 로 AZ 마다 고르게",630,330,510,70,BAD)
d.save(P+"03-canary-drain.drawio")

# ④ 진단 순서
d=D("4. 진단 순서 — 무중단 장치가 제 역할을 하나")
q=d.box("① 증상: 재시작 반복? 배포가 안 끝남? 점검이 안 끝남? 한꺼번에 중단?",20,20,1140,50,NOTE+"fontStyle=1;")
b1=d.box("재시작 반복\nkubectl describe pod\n→ Liveness/Startup probe failed\n→ probe 경로·시간 vs 앱 시작 시간",20,110,270,110,BAD)
b2=d.box("배포가 안 끝남·결함이 나감\nkubectl argo rollouts get rollout\n→ AnalysisRun 측정값·판정\n→ 분석 템플릿 지표·기준",310,110,270,110,BAD)
b3=d.box("점검이 안 끝남\nkubectl get pdb (ALLOWED)\n→ drain 이벤트(evict 거부)\n→ minAvailable vs 파드 수",600,110,270,110,BAD)
b4=d.box("한꺼번에 중단\n파드의 노드·AZ 분포\n→ PDB·spread·nodeSelector\n→ FIS·노드 상태",890,110,270,110,BAD)
for x in (b1,b2,b3,b4): d.edge(q,x,"","exitX=0.5;exitY=1;entryX=0.5;entryY=0;")
d.box("② 바꾼 것 찾기: git log -p gitops/envs/prod/values.yaml · CloudTrail(UpdateNodegroupConfig)",20,250,1140,45,GRAY)
d.box("③ 고치기: Git 커밋(revert)으로 — 클러스터를 손으로 고치면 자동 치유가 되돌린다 · 점검 끝난 노드는 uncordon",20,315,1140,45,SYS)
d.box("④ 재발 방지: probe 역할 구분 · 판정 조건은 '데이터 없음 = 실패' · PDB 는 파드 수보다 작게 · AZ 분산 · 자동 복구 범위 제한",20,380,1140,50,OK+"fontStyle=1;")
d.save(P+"04-diagnosis.drawio")
print("saved")
