# cicd 모듈 — ECS(Fargate)용 앱 이미지. 저장소 최상위에서 빌드한다: docker build -f cicd/Dockerfile .
FROM public.ecr.aws/docker/library/python:3.12-slim
RUN pip install --no-cache-dir flask==3.0.3 gunicorn==22.0.0 psycopg2-binary==2.9.9 boto3==1.35.36
WORKDIR /opt/app
COPY app/app.py .
EXPOSE 8080
CMD ["gunicorn", "-w", "2", "--threads", "4", "--timeout", "35", "-b", "0.0.0.0:8080", "--access-logfile", "-", "app:app"]
