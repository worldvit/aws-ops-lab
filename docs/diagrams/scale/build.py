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

P="docs/diagrams/scale/"
SVC="fillColor=#E1D5E7;strokeColor=#9673A6;"

# ① 아키텍처
d=D("1. 오늘 만드는 확장·업그레이드·비용 구조")
d.group("AWS 가 운영",20,20,1140,120,AWS)
cp=d.box("EKS 컨트롤 플레인(관제탑)\n버전 1.36 → (scale-4) 1.37",40,60,300,60,CP+"fontStyle=1;")
asg=d.box("관리형 노드 그룹(오토스케일링 그룹)\n최소 2 · 최대 4 — 클러스터 오토스케일러가 원하는 수를 바꾼다",370,60,450,60,AWS)
ec2=d.box("EC2 API — Karpenter 가\n노드 그룹 없이 바로 만들고 지운다",850,60,290,60,AWS)
d.group("클러스터",20,160,1140,370,VPC)
d.group("관리형 노드 2대 (opslab/pool=default)",40,195,520,200,NODE)
app=d.box("샘플 앱 파드 ×2~8",60,305,230,50,POD)
hpa=d.box("HPA: CPU 50%(요청 100m 기준)\n넘으면 파드 늘림",310,235,230,50,SVC+"fontStyle=1;")
ms=d.box("metrics-server\n(CPU 사용량 공급)",60,235,230,50,SYS)
kp=d.box("Karpenter 컨트롤러\n(Pending 을 보고 노드 주문)",310,305,230,50,SYS+"fontStyle=1;")
d.group("Karpenter 노드 (NodePool default)",590,195,550,200,NODE+"dashed=1;")
np=d.box("NodePool: 무엇을\nc·m·r 6세대↑ large·xlarge · 한도 cpu 16\n비거나 덜 쓰면 합치기(consolidation)",610,235,510,70,SVC)
nc=d.box("EC2NodeClass: 어떻게\nAMI al2023@latest · 서브넷 태그 · 노드 역할",610,315,510,55,SVC)
db=d.box("PostgreSQL(pgvector) + EBS 디스크 → VolumeSnapshot(pg-baseline)   ·   Redis(캐시)",40,420,1100,45,GRAY+"fontStyle=1;")
d.box("배치 작업(CPU 1개 ×3) — 자리가 없으면 Pending → 노드가 늘어야 뜬다",40,475,1100,40,NOTE)
d.edge(ms,hpa,"","exitX=1;exitY=0.5;entryX=0;entryY=0.5;")
d.edge(kp,ec2,"주문(IRSA)","exitX=1;exitY=0.5;entryX=0.5;entryY=1;",points=[(570,330),(570,150),(995,150)])
d.save(P+"01-architecture.drawio")

# ② 늘어나는 순서
d=D("2. 늘어나는 순서 — 파드 먼저, 노드는 그다음")
a=d.box("① 트래픽 급증\nCPU 사용률 ↑",20,60,200,70,NOTE)
b=d.box("② HPA\n사용률 = 사용량 ÷ 요청(requests)\n목표 50% 넘으면 파드 수 ↑",250,60,250,70,SVC+"fontStyle=1;")
c=d.box("③ 스케줄러\n새 파드를 놓을 자리 찾기",530,60,220,70,SYS)
e=d.box("④ 자리 없음 → Pending\n(Insufficient cpu)",780,60,220,70,BAD)
f=d.box("⑤-1 클러스터 오토스케일러\n노드 그룹 원하는 수 +1\n(최대 크기까지만) · 3~5분",250,200,330,85,AWS)
g=d.box("⑤-2 Karpenter\nPending 파드에 맞는 EC2 를 골라 바로 생성\nNodePool 조건·한도 안에서 · 1~2분",620,200,380,85,SYS+"fontStyle=1;")
h=d.box("⑥ 새 노드 Ready → 파드 Running",450,330,330,50,OK)
d.edge(a,b,""); d.edge(b,c,""); d.edge(c,e,"")
d.edge(e,f,"","exitX=0.25;exitY=1;entryX=0.5;entryY=0;",points=[(835,160),(415,160)]); d.edge(e,g,"","exitX=0.75;exitY=1;entryX=0.8;entryY=0;",points=[(945,180),(924,180)])
d.edge(f,h,"",""); d.edge(g,h,"","")
d.box("멈추는 곳: 지표 없음(metrics-server) · 요청 없음 · 대상 이름 오타 · 최소=최대 | 노드 그룹 최대 · NodePool 한도·조건 · EC2NodeClass 서브넷",20,410,1000,50,NOTE+"fontStyle=1;")
d.save(P+"02-scaling.drawio")

# ③ 드레인과 업그레이드
d=D("3. 노드 교체(드레인)와 클러스터 업그레이드 절차")
d.group("노드 교체 — 비우고(drain) 바꾸기",20,20,560,440,NODE)
d.box("cordon: 새 손님 받지 마",40,60,520,40,GRAY)
d.box("drain 거부 ①: emptyDir(노드 임시 디스크) 파드\n→ --delete-emptydir-data (데이터가 사라져도 되는지 확인)",40,115,520,60,BAD)
d.box("drain 거부 ②: DaemonSet 파드(aws-node·kube-proxy 등 노드마다 1개)\n→ --ignore-daemonsets (노드와 함께 사라지는 게 정상)",40,190,520,60,BAD)
d.box("drain 대기: PDB 가 막으면 새 파드가 뜰 때까지 기다림",40,265,520,45,NOTE)
d.box("교체: 오토스케일링 그룹에서 종료(원하는 수 유지)\n→ 새 노드가 자동으로 들어옴",40,325,520,60,OK)
d.group("업그레이드 — 한 마이너씩, 이 순서로",610,20,550,440,CP)
s1=d.box("1 사전 점검\n업그레이드 인사이트 · 폐기된 API 매니페스트 · 애드온 호환",630,60,510,65,NOTE+"fontStyle=1;")
s2=d.box("2 컨트롤 플레인 1.36 → 1.37 (약 10분)",630,145,510,45,CP)
s3=d.box("3 애드온: vpc-cni · kube-proxy · coredns · ebs-csi … 기본 버전으로",630,210,510,50,SYS)
s4=d.box("4 노드: 관리형 노드 그룹 1대씩 교체(PDB 지킴)\nKarpenter 노드는 AMI 가 바뀌어 드리프트로 자동 교체",630,280,510,65,NODE)
s5=d.box("되돌릴 수 없다 — 컨트롤 플레인은 다운그레이드 불가",630,365,510,45,BAD+"fontStyle=1;")
d.edge(s1,s2,""); d.edge(s2,s3,""); d.edge(s3,s4,"")
d.save(P+"03-drain-upgrade.drawio")

# ④ 진단 순서
d=D("4. 진단 순서 — 왜 안 늘어나나, 왜 안 비워지나")
q=d.box("① 증상: 파드 수가 안 늘어남? 파드가 Pending? 노드 작업이 멈춤? DB 가 비었거나 안 뜸?",20,20,1140,50,NOTE+"fontStyle=1;")
b1=d.box("파드 수가 안 늘어남\nkubectl describe hpa\n→ Conditions·Events\n→ metrics-server·요청·대상",20,110,270,115,BAD)
b2=d.box("Pending\nkubectl describe pod (이벤트)\n→ kubectl get nodeclaim\n→ Karpenter 로그\n→ NodePool·EC2NodeClass",310,110,270,115,BAD)
b3=d.box("노드 작업이 멈춤\nkubectl get nodes (cordon)\n→ drain 메시지\n→ emptyDir·DaemonSet·PDB",600,110,270,115,BAD)
b4=d.box("DB 이상\nkubectl get pvc,volumesnapshot\n→ describe pod(볼륨 AZ)\n→ 스냅샷 복원",890,110,270,115,BAD)
for x in (b1,b2,b3,b4): d.edge(q,x,"","exitX=0.5;exitY=1;entryX=0.5;entryY=0;")
d.box("② 바꾼 것 찾기: kubectl get … -o yaml 과 기준 파일 비교 · EKS 감사 로그(누가 patch 했나)",20,255,1140,45,GRAY)
d.box("③ 고치기: 기준값으로 되돌리기 → 1~2분 지켜보기(HPA 15초 주기·Karpenter 즉시·노드 Ready 1~3분)",20,320,1140,45,SYS)
d.box("④ 재발 방지: 요청은 실제 사용량에서 · HPA 최소<최대 · NodePool 한도·조건은 근거와 함께 · 드레인 옵션은 의미를 알고 · 스냅샷 주기",20,385,1140,50,OK+"fontStyle=1;")
d.save(P+"04-diagnosis.drawio")
print("saved")
