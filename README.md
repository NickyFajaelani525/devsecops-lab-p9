# Praktikum 9 DevSecOps — Container Security (Docker, Trivy, Jenkins)

Eksperimen perbandingan keamanan Docker container **BEFORE (`before`)** vs **AFTER (`main`)** hardening menggunakan **Docker**, **Trivy (`0.76.1`)**, dan **Jenkins Multibranch Pipeline**.

---

## 1. Deskripsi Aplikasi & Endpoint

Aplikasi web HTTP berbasis Python **Flask** yang dijalankan dengan server WSGI **Gunicorn** pada port **`5000`**.

| Method | Path | Deskripsi | Contoh Respons |
|---|---|---|---|
| `GET` | `/` | Status layanan utama | `{"message":"Hello from Flask App!","status":"running"}` |
| `GET` | `/health` | Endpoint *healthcheck* container | `{"status":"ok"}` (`200 OK`) |

---

## 2. Verifikasi Dependency & Base Image

- **Base image utama (reproducible digest):**
  `python:3.12-alpine@sha256:e064671ca452259bab50e8e2c7bd896e39e9a343bb06ca25234adf6fe18d0fc7`
- **Dependency (`requirements.txt`):**
  - `Flask==3.1.3` — dipilih bukan sekadar karena versi terbaru, melainkan karena hasil pemindaian Trivy `0.76.1` terhadap `Flask 3.0.0` menunjukkan `CVE-2026-27205` (`LOW`) yang diperbaiki pada `3.1.3`.
  - `gunicorn==27.0.0` — diverifikasi kompatibel dengan Python `3.12` (Alpine musl) saat instalasi, pengujian runtime (`gunicorn` + Flask pada port `5000`), dan scan Trivy `0.76.1`.
  - Seluruh paket transitif ikut di-pin (`blinker==1.9.0`, `click==8.5.1`, `itsdangerous==2.2.0`, `Jinja2==3.1.6`, `MarkupSafe==3.0.4`, `Werkzeug==3.1.9`) untuk menjaga kesetaraan build antara `before` dan `main`.

---

## 3. Desain Eksperimen BEFORE vs AFTER

Kedua branch (`before` dan `main`) menggunakan **base image digest**, **`app.py`**, **`requirements.txt`**, **port (`5000`)**, dan **`Jenkinsfile`** yang identik. Perbedaan hanya terletak pada aspek container hardening:

| Aspek | Branch `before` (Baseline) | Branch `main` (Hardened / AFTER) |
|---|---|---|
| Base image | `python:3.12-alpine@sha256:e064671c...` | `python:3.12-alpine@sha256:e064671c...` |
| Build stage | Single-stage | Multi-stage (`builder` -> `runtime`) |
| OS package patching | Tidak ada `apk upgrade` | `apk upgrade --no-cache` *(perlakuan patching OS terpisah)* |
| Package manager runtime | `pip` & cache tetap tertinggal | `pip`, `setuptools`, `wheel` dihapus dari `/opt/venv` & `runtime` |
| User runtime | `root` | Non-root `webuser:webgroup` (`UID/GID 10001`) |
| Virtualenv & ownership | Global `/usr/local`, tanpa `--chown` | `/opt/venv` terisolasi, `--chown=root:webgroup` |
| `.dockerignore` | Tetap mengecualikan `.env`, `.env.*`, `.git`, credential, file sensitif; tidak mengecualikan file non-sensitif lain | Optimal (mengecualikan `.git/`, `.env*`, credential, `Jenkinsfile`, `README.md`, `Dockerfile*`, cache, report JSON) |
| `HEALTHCHECK` | Tidak ada | Ada (`urllib.request` ke `http://127.0.0.1:5000/health`) |
| Env Python | Default | `PYTHONDONTWRITEBYTECODE=1`, `PYTHONUNBUFFERED=1` |

> **Catatan Metodologis `apk upgrade --no-cache`:**
> Penurunan CVE OS pada branch `main` (mis. pembaruan `krb5-libs` dan `zlib` pada Alpine 3.24) berasal secara spesifik dari perlakuan `apk upgrade --no-cache` dan penghapusan `pip` dari runtime, bukan dari instruksi `USER`, `HEALTHCHECK`, atau `.dockerignore`. Pemisahan ini dicatat agar analisis hasil scan tetap objektif.

---

## 4. Cara Build dan Menjalankan Secara Lokal

### Menjalankan dengan Python lokal
```bash
python3 -m venv .venv
. .venv/bin/activate
pip install -r requirements.txt
gunicorn --bind 0.0.0.0:5000 --workers 2 app:app
```

### Build & Jalankan dengan Docker
```bash
docker build -t devsecops-lab-p9:after .
docker run -d --name app-after -p 127.0.0.1::5000 devsecops-lab-p9:after
```
*(Gunakan `docker port app-after 5000/tcp` untuk melihat port host dinamis jika port `5000` pada host Windows/WSL terbentur port reserved.)*

Verifikasi runtime:
```bash
docker exec app-after id
docker exec app-after python3 -c "import urllib.request; print(urllib.request.urlopen('http://127.0.0.1:5000/health').read().decode())"
docker stop app-after && docker rm app-after
```

---

## 5. Cara Menjalankan Scan Trivy (`0.76.1`)

Gunakan versi spesifik `aquasec/trivy:0.76.1` (bukan `:latest`):

```bash
# 1. Image Scan (semua severity)
docker run --rm \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v ~/.cache/trivy:/root/.cache/trivy \
  aquasec/trivy:0.76.1 image --severity CRITICAL,HIGH,MEDIUM,LOW devsecops-lab-p9:after

# 2. Filesystem Scan
docker run --rm \
  -v "$(pwd)":/work:ro \
  -v ~/.cache/trivy:/root/.cache/trivy \
  aquasec/trivy:0.76.1 fs --scanners vuln,misconfig,secret --severity CRITICAL,HIGH,MEDIUM,LOW --skip-dirs .git /work

# 3. Config / Dockerfile Scan
docker run --rm \
  -v "$(pwd)":/work:ro \
  -v ~/.cache/trivy:/root/.cache/trivy \
  aquasec/trivy:0.76.1 config --severity CRITICAL,HIGH,MEDIUM,LOW /work
```

---

## 6. Arsitektur Jenkins Multibranch Pipeline

Pipeline pada [`Jenkinsfile`](Jenkinsfile) dirancang untuk dijalankan oleh **Jenkins Multibranch Pipeline** pada server tim (`main` dan `before`).
Tahapan yang ditargetkan pada integrasi penuh (Checkpoint 4):
1. `Checkout SCM`
2. `Environment Inspection`
3. `Trivy Filesystem Scan` (`trivy fs`)
4. `Trivy Config Scan` (`trivy config`)
5. `Docker Build` (tag berdasarkan sanitasi `BRANCH_NAME` dan short SHA)
6. `Trivy Image Scan` (`trivy image`, mode reporting vs security gate terpisah)
7. `Runtime Verification` (`/health`, port, dan user runtime)
8. `Archive Artifacts` (`trivy-*-<branch>.json` & bukti runtime)
9. `Cleanup`

**Checklist Verifikasi Read-Only di Server Jenkins Teman:**
- Pastikan mount path `/var/jenkins_home` dan nama named volume `jenkins_home` sesuai pada container Jenkins (`docker inspect <jenkins-container>`).
- Pastikan `docker` CLI dan `/var/run/docker.sock` dapat diakses user di dalam container Jenkins.
- Pastikan plugin **GitHub Branch Source**, **Pipeline**, dan credential PAT GitHub sudah dikonfigurasi di Jenkins.

Untuk panduan langkah demi langkah setup Jenkins lokal, pembuatan Multibranch Pipeline, pengujian parameter `ENABLE_SECURITY_GATE`, dan pembacaan artifact hasil scan, lihat [`guide.md`](guide.md).

---

## 7. Ringkasan Hasil Pengujian Terobservasi

*Catatan: Hasil di bawah ini berasal dari eksekusi Jenkins Multibranch Pipeline dengan Trivy `0.76.1` pada branch `before` (Build `#1`, commit `d998094`) dan branch `main` (Build `#2`, commit `ba61506`).*

| Parameter | BEFORE (`before`) | AFTER (`main`) |
|---|---|---|
| Base image | `python:3.12-alpine` | `python:3.12-alpine` |
| Base image digest | `sha256:e064671ca452259bab50e8e2c7bd896e39e9a343bb06ca25234adf6fe18d0fc7` | `sha256:e064671ca452259bab50e8e2c7bd896e39e9a343bb06ca25234adf6fe18d0fc7` |
| Image size | `65.1 MB` (`65114271` bytes) | `57.8 MB` (`57765934` bytes) |
| Runtime user | `uid=0(root) gid=0(root)` | `uid=10001(webuser) gid=10001(webgroup)` |
| HEALTHCHECK | Tidak ada (`NONE`) | Aktif (`urllib.request` -> `/health` HTTP `200`) |
| CRITICAL CVE | `0` | `0` |
| HIGH CVE | `16` | `0` |
| MEDIUM CVE | `11` | `0` |
| LOW CVE | `1` | `0` |
| Filesystem findings | `2` (`misconfig: HIGH=1, LOW=1`; `vuln=0`, `secret=0`) | `0` |
| Config findings | `2` (`HIGH=1, LOW=1`) | `0` |
| Runtime status | Gunicorn `27.0.0` listening `0.0.0.0:5000`, `/` & `/health` HTTP `200` | Gunicorn `27.0.0` listening `0.0.0.0:5000`, `/` & `/health` HTTP `200` |
