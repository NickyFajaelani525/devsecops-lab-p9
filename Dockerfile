# ❌ BAD: Menggunakan base image besar (full OS) dengan banyak package tidak diperlukan
FROM ubuntu:22.04

# ❌ BAD: Menjalankan apt-get update dan install terpisah tanpa --no-install-recommends dan tanpa cleanup cache
RUN apt-get update
RUN apt-get install -y python3 python3-pip curl wget

# ❌ BAD: Meng-copy seluruh direktori tanpa .dockerignore (termasuk .git atau file sensitif)
COPY . /app

# ❌ BAD: Tidak set WORKDIR, menggunakan cd di dalam RUN
RUN cd /app && pip3 install -r requirements.txt

# ❌ BAD: Berjalan sebagai root (tidak ada USER directive)

# ❌ BAD: Menyimpan credential/secret secara hardcoded di ENV
ENV DB_PASSWORD=supersecret123
ENV API_KEY=abc123xyz

EXPOSE 8080

CMD ["python3", "/app/app.py"]
