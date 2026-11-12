# Panduan Penggunaan Jenkins Lokal (Multibranch Pipeline)

Panduan ini menjelaskan cara menggunakan environment Jenkins lokal (`http://localhost:8080`) untuk menguji branch `before` dan `main` menggunakan [`Jenkinsfile`](Jenkinsfile) pada repository ini.

---

### 1. Login & Setup Awal Jenkins

1. Pastikan container `jenkins-p9-local` sedang berjalan (dari direktori Jenkins lokal, misalnya `~/jenkins-p9-local`):
   ```bash
   docker compose ps
   ```
   *(Jika belum berjalan, jalankan `docker compose up -d`.)*
2. Buka browser ke **`http://localhost:8080`**.
3. Ambil **initial administrator password** dari container Jenkins:
   ```bash
   docker exec jenkins-p9-local cat /var/jenkins_home/secrets/initialAdminPassword
   ```
   Masukkan password tersebut pada halaman **Unlock Jenkins**.
4. Pada halaman **Customize Jenkins**:
   - Plugin inti yang dibutuhkan [`Jenkinsfile`](Jenkinsfile) (`workflow-aggregator`, `workflow-multibranch`, `ws-cleanup`, `timestamper`, `git`, `github-branch-source`, `credentials-binding`) sudah terpasang pada image Jenkins melalui `plugins.txt`.
   - Pilih **"Install suggested plugins"** bila ingin plugin tambahan standar, atau **"Select plugins to install"** -> **"None"** -> **"Install"** untuk langsung melewati tahap instalasi plugin.
5. Buat akun admin pertama (**Create First Admin User**), lalu pada **Instance Configuration** pertahankan URL `http://localhost:8080/` dan klik **Save and Finish** -> **Start using Jenkins**.

---

### 2. Membuat Multibranch Pipeline untuk `devsecops-lab-p9`

Karena branch `before` dan `main` menggunakan [`Jenkinsfile`](Jenkinsfile) yang identik, gunakan tipe job **Multibranch Pipeline**:

1. Di dashboard Jenkins, klik **New Item**.
2. Masukkan nama item (misal `devsecops-lab-p9`), pilih **Multibranch Pipeline**, lalu klik **OK**.
3. Pada bagian **Branch Sources**, klik **Add source**:
   - **Opsi A — Git (untuk repository publik):**
     - Pilih **Git**.
     - **Project Repository**: `https://github.com/NickyFajaelani525/devsecops-lab-p9.git`
     - **Behaviours**: biarkan **Discover branches** aktif agar `before` dan `main` terdeteksi otomatis.
   - **Opsi B — GitHub (dengan GitHub Branch Source + PAT):**
     - Pilih **GitHub**.
     - Jika repository private atau untuk menghindari API rate limit GitHub, tambahkan **Credentials** (Username + Personal Access Token GitHub).
     - Isi **Repository HTTPS URL**: `https://github.com/NickyFajaelani525/devsecops-lab-p9.git` (atau Owner `NickyFajaelani525` dan Repository `devsecops-lab-p9`).
4. *(Opsional, disarankan)* Pada **Behaviours** -> klik **Add** -> pilih **Suppress automatic SCM triggering** agar kedua branch tidak langsung berjalan bersamaan saat scan pertama kali.
5. Pada bagian **Build Configuration**:
   - **Mode**: `by Jenkinsfile`
   - **Script Path**: `Jenkinsfile`
6. Klik **Save**.

Jenkins akan menjalankan **Scan Multibranch Pipeline Log** dan mendeteksi branch `before` serta `main`.

---

### 3. Menjalankan & Membandingkan Pipeline (`before` vs `main`)

Jalankan **satu branch secara bergantian** (hindari menjalankan keduanya secara bersamaan):

1. Buka job `devsecops-lab-p9` -> klik branch **`before`** -> klik **Build Now** (atau **Build with Parameters** setelah parameter terindeks).
2. Buka nomor build (misal `#1`) -> **Console Output** untuk memantau 10 stage pada [`Jenkinsfile`](Jenkinsfile):
   - `Checkout SCM` (`cleanWs()` + checkout branch)
   - `Environment Inspection` (cek Docker, buat volume `trivy-cache`, verifikasi Trivy `0.76.1`)
   - `Trivy Filesystem Scan` (`trivy fs`)
   - `Trivy Config Scan` (`trivy config`)
   - `Docker Build` (build image sementara `<image-name>:<branch>-<sha>-<build>`)
   - `Trivy Image Scan` (`trivy image` seluruh severity: `CRITICAL,HIGH,MEDIUM,LOW`)
   - `Runtime Verification` (jalankan container pada network Docker terisolasi, uji `GET /` dan `GET /health`, cek user `root` pada `before` vs non-root pada `main`)
   - `Archive Artifacts`
   - `Security Gate` *(dilewati secara default saat `ENABLE_SECURITY_GATE=false`)*
   - `Cleanup` *(menghapus container sementara, network sementara, dan image sementara hasil build pipeline)*
3. Setelah branch `before` selesai, ulangi langkah yang sama pada branch **`main`**.

#### Menguji Security Gate (`ENABLE_SECURITY_GATE`)
Setelah pipeline pernah berjalan minimal satu kali sehingga parameter terdaftar:
- Klik **Build with Parameters** pada branch yang ingin diuji:
  - `DOCKERFILE_PATH`: default `Dockerfile`
  - `IMAGE_NAME`: default `devsecops-lab-p9`
  - `TRIVY_CACHE_VOLUME`: default `trivy-cache`
  - `ENABLE_SECURITY_GATE`: centang **`true`** bila ingin stage `Security Gate` menggagalkan build saat ditemukan CVE `CRITICAL` atau `HIGH`.

#### Melihat Laporan / Build Artifacts
Pada halaman masing-masing build bagian **Build Artifacts**, tersedia 4 file laporan:
- `trivy-fs-<branch>-<sha>.json`
- `trivy-config-<branch>-<sha>.json`
- `trivy-image-<branch>-<sha>.json`
- `runtime-verify-<branch>-<sha>.txt`

---

### 4. Perintah Harian Start / Stop Jenkins

Jalankan dari direktori Jenkins lokal (mis. `~/jenkins-p9-local`):

- **Menjalankan Jenkins:**
  ```bash
  docker compose up -d
  ```
- **Menghentikan sementara (container tetap ada):**
  ```bash
  docker compose stop
  ```
- **Menghentikan dan menghapus container tanpa menghapus data Jenkins (`jenkins_home` tetap aman):**
  ```bash
  docker compose down
  ```
  *(Jangan gunakan flag `-v`, karena `-v` akan menghapus volume `jenkins_home` beserta seluruh konfigurasi job dan riwayat build.)*
- **Melihat log Jenkins:**
  ```bash
  docker logs -f jenkins-p9-local
  ```
