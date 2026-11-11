# ==========================================
# BASELINE BEFORE HARDENING (Eksperimen P9)
# ==========================================
# Base image & digest identik dengan branch main untuk kontrol eksperimen
FROM python:3.12-alpine@sha256:e064671ca452259bab50e8e2c7bd896e39e9a343bb06ca25234adf6fe18d0fc7

WORKDIR /app

# Single-stage, copy seluruh context, install global tanpa --no-cache-dir
# Tanpa apk upgrade, tanpa virtualenv terisolasi, dan menyisakan pip + cache di runtime
COPY . /app
RUN pip install -r requirements.txt

# Berjalan sebagai root (tanpa directive USER non-root) dan tanpa HEALTHCHECK
EXPOSE 5000

CMD ["gunicorn", "--bind", "0.0.0.0:5000", "--workers", "2", "app:app"]
