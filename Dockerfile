# ==========================================
# STAGE 1: Build Stage (Isolated Virtualenv)
# ==========================================
FROM python:3.12-alpine@sha256:e064671ca452259bab50e8e2c7bd896e39e9a343bb06ca25234adf6fe18d0fc7 AS builder

WORKDIR /build

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

RUN python3 -m venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt && \
    rm -rf /opt/venv/lib/python*/site-packages/pip* \
           /opt/venv/lib/python*/site-packages/setuptools* \
           /opt/venv/bin/pip*

# ==========================================
# STAGE 2: Runtime Stage (Hardened Minimal)
# ==========================================
FROM python:3.12-alpine@sha256:e064671ca452259bab50e8e2c7bd896e39e9a343bb06ca25234adf6fe18d0fc7 AS runtime

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PORT=5000 \
    PATH="/opt/venv/bin:$PATH"

# Perlakuan hardening OS package (terpisah dari pemilihan base image):
# Upgrade package Alpine yang memiliki perbaikan CVE & hapus pip bawaan runtime
RUN apk upgrade --no-cache && \
    python3 -m pip uninstall -y pip setuptools wheel 2>/dev/null || true

# Least privilege: non-root user & group (UID/GID 10001)
RUN addgroup -g 10001 -S webgroup && \
    adduser -u 10001 -S webuser -G webgroup

WORKDIR /app

# Salin virtualenv & aplikasi dengan ownership read-only bagi webuser
COPY --from=builder --chown=root:webgroup /opt/venv /opt/venv
COPY --chown=root:webgroup app.py .

USER 10001:10001

EXPOSE 5000

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD ["python3", "-c", "import urllib.request; urllib.request.urlopen('http://127.0.0.1:5000/health', timeout=3)"]

CMD ["gunicorn", "--bind", "0.0.0.0:5000", "--workers", "2", "app:app"]
