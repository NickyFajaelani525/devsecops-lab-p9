# ==========================================
# 1. Base Image Minimal & Specific Tag
# ==========================================
FROM python:3.12-alpine AS builder

WORKDIR /build

# ==========================================
# 2. Minimal Dependency Copy & Cache Cleared
# ==========================================
COPY requirements.txt .
RUN pip install --no-cache-dir --prefix=/install -r requirements.txt

# ==========================================
# 3. Multi-Stage Build (Runtime Stage)
# ==========================================
FROM python:3.12-alpine AS runtime

# ==========================================
# 4. Least Privilege: Create Non-Root User
# ==========================================
RUN addgroup -g 10001 -S webgroup && \
    adduser -u 10001 -S webuser -G webgroup

WORKDIR /app

# Salin hanya library yang sudah jadi dari builder stage
COPY --from=builder /install /usr/local
COPY --chown=webuser:webgroup app.py .

# ==========================================
# 5. Enforce Non-Root Execution & Production Server
# ==========================================
USER 10001:10001

EXPOSE 5000

# Tidak menyimpan secret via ENV, gunakan gunicorn production server
CMD ["gunicorn", "--bind", "0.0.0.0:5000", "--workers", "2", "app:app"]
