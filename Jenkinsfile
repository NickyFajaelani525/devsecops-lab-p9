pipeline {
    agent any

    options {
        skipDefaultCheckout(true)
        disableConcurrentBuilds()
        timestamps()
    }

    parameters {
        string(
            name: 'DOCKERFILE_PATH',
            defaultValue: 'Dockerfile',
            description: 'Path Dockerfile relatif terhadap root repository'
        )

        string(
            name: 'IMAGE_NAME',
            defaultValue: 'devsecops-lab-p9',
            description: 'Nama repository Docker image untuk eksperimen'
        )

        string(
            name: 'TRIVY_CACHE_VOLUME',
            defaultValue: 'trivy-cache',
            description: 'Nama Docker volume untuk menyimpan cache DB Trivy'
        )

        booleanParam(
            name: 'ENABLE_SECURITY_GATE',
            defaultValue: false,
            description: 'Aktifkan fail gate bila ada CVE CRITICAL atau HIGH (default false untuk reporting BEFORE vs AFTER)'
        )
    }

    environment {
        TRIVY_IMAGE      = 'aquasec/trivy:0.76.1'
        BASE_PROBE_IMAGE = 'python:3.12-alpine@sha256:e064671ca452259bab50e8e2c7bd896e39e9a343bb06ca25234adf6fe18d0fc7'
    }

    stages {

        // ==========================================
        // 1. CHECKOUT SCM
        // ==========================================
        stage('Checkout SCM') {
            steps {
                cleanWs()
                checkout scm

                script {
                    def rawBranch = (env.BRANCH_NAME ?: 'local').trim()
                    def branchSlug = rawBranch.toLowerCase()
                        .replaceAll(/[^a-z0-9._-]/, '-')
                        .replaceAll(/^[.-]+|[.-]+$/, '')
                    if (!branchSlug) {
                        branchSlug = 'branch'
                    }
                    if (branchSlug.length() > 48) {
                        branchSlug = branchSlug.substring(0, 48).replaceAll(/[.-]+$/, '')
                    }

                    def shortSha = sh(
                        script: 'git rev-parse --short=7 HEAD',
                        returnStdout: true
                    ).trim()

                    def imageRepo = (params.IMAGE_NAME ?: 'devsecops-lab-p9').trim()
                    def dockerfileRel = (params.DOCKERFILE_PATH ?: 'Dockerfile').trim()
                    def cacheVol = (params.TRIVY_CACHE_VOLUME ?: 'trivy-cache').trim()

                    env.RAW_BRANCH     = rawBranch
                    env.BRANCH_SLUG    = branchSlug
                    env.SHORT_SHA      = shortSha
                    env.IMAGE_REPO     = imageRepo
                    env.DOCKERFILE_REL = dockerfileRel
                    env.CACHE_VOL      = cacheVol
                    env.IMAGE_TAG      = "${branchSlug}-${shortSha}-${env.BUILD_NUMBER}"
                    env.FULL_IMAGE     = "${imageRepo}:${env.IMAGE_TAG}"
                    env.RUN_ID         = "${branchSlug}-${shortSha}-${env.BUILD_NUMBER}"
                    env.FS_REPORT      = "trivy-fs-${branchSlug}-${shortSha}.json"
                    env.CONFIG_REPORT  = "trivy-config-${branchSlug}-${shortSha}.json"
                    env.IMAGE_REPORT   = "trivy-image-${branchSlug}-${shortSha}.json"
                    env.RUNTIME_REPORT = "runtime-verify-${branchSlug}-${shortSha}.txt"
                }

                echo "Checkout selesai: branch=${env.RAW_BRANCH}, slug=${env.BRANCH_SLUG}, sha=${env.SHORT_SHA}"
            }
        }

        // ==========================================
        // 2. ENVIRONMENT INSPECTION
        // ==========================================
        stage('Environment Inspection') {
            steps {
                sh '''
                    set -eu

                    echo "===== PIPELINE METADATA ====="
                    echo "Branch        : $RAW_BRANCH (slug: $BRANCH_SLUG)"
                    echo "Commit SHA    : $SHORT_SHA"
                    echo "Image Target  : $FULL_IMAGE"
                    echo "Run ID        : $RUN_ID"
                    echo "Dockerfile    : $DOCKERFILE_REL"
                    echo "Trivy Image   : $TRIVY_IMAGE"
                    echo "Cache Volume  : $CACHE_VOL"
                    echo "Security Gate : ${ENABLE_SECURITY_GATE:-false}"

                    echo "===== REQUIRED REPOSITORY FILES ====="
                    for req in "$DOCKERFILE_REL" "app.py" "requirements.txt"; do
                        if [ ! -f "$WORKSPACE/$req" ]; then
                            echo "[ERROR] File wajib tidak ditemukan: $req"
                            exit 1
                        fi
                        echo "[OK] $req"
                    done

                    echo "===== DOCKER & TRIVY CHECK ====="
                    docker --version
                    docker info --format 'ServerVersion={{.ServerVersion}} OSType={{.OSType}} Arch={{.Architecture}}'
                    docker volume create "$CACHE_VOL" >/dev/null
                    docker run --rm -v "${CACHE_VOL}:/root/.cache/trivy" "$TRIVY_IMAGE" --version
                '''
            }
        }

        // ==========================================
        // 3. TRIVY FILESYSTEM SCAN
        // ==========================================
        stage('Trivy Filesystem Scan') {
            steps {
                sh '''
                    set -eu

                    FS_CTR="p9-fs-${RUN_ID}"
                    STAGE_DIR="$(mktemp -d)"

                    cleanup_fs() {
                        rm -rf "$STAGE_DIR"
                        docker rm -f "$FS_CTR" >/dev/null 2>&1 || true
                    }
                    trap cleanup_fs EXIT

                    # Salin isi workspace selain .git dan report sementara ke staging
                    find "$WORKSPACE" -mindepth 1 -maxdepth 1 \
                        ! -name '.git' \
                        ! -name 'trivy-*.json' \
                        ! -name 'runtime-verify-*.txt' \
                        -exec cp -a {} "$STAGE_DIR/" \\;

                    docker create \
                        --name "$FS_CTR" \
                        -v "${CACHE_VOL}:/root/.cache/trivy" \
                        "$TRIVY_IMAGE" \
                        fs \
                        --scanners vuln,misconfig,secret \
                        --severity CRITICAL,HIGH,MEDIUM,LOW \
                        --format json \
                        --output /tmp/trivy-fs-report.json \
                        --exit-code 0 \
                        /work >/dev/null

                    docker cp "$STAGE_DIR" "${FS_CTR}:/work"
                    docker start -a "$FS_CTR"
                    docker cp "${FS_CTR}:/tmp/trivy-fs-report.json" "${WORKSPACE}/${FS_REPORT}"

                    echo "===== FILESYSTEM SCAN SUMMARY ====="
                    docker run --rm -i "$BASE_PROBE_IMAGE" python3 -c '
import json, sys
from collections import Counter

data = json.load(sys.stdin)
counts = Counter()
for res in data.get("Results", []):
    for item in res.get("Vulnerabilities") or []:
        counts[("vuln", item.get("Severity", "UNKNOWN"))] += 1
    for item in res.get("Misconfigurations") or []:
        counts[("misconfig", item.get("Severity", "UNKNOWN"))] += 1
    for item in res.get("Secrets") or []:
        counts[("secret", item.get("Severity", "UNKNOWN"))] += 1

for kind in ("vuln", "misconfig", "secret"):
    summary = " ".join(f"{s}={counts[(kind, s)]}" for s in ("CRITICAL", "HIGH", "MEDIUM", "LOW"))
    print(f"{kind}: {summary}")
' < "${WORKSPACE}/${FS_REPORT}"
                '''
            }
        }

        // ==========================================
        // 4. TRIVY CONFIG SCAN
        // ==========================================
        stage('Trivy Config Scan') {
            steps {
                sh '''
                    set -eu

                    CFG_CTR="p9-cfg-${RUN_ID}"
                    STAGE_DIR="$(mktemp -d)"

                    cleanup_cfg() {
                        rm -rf "$STAGE_DIR"
                        docker rm -f "$CFG_CTR" >/dev/null 2>&1 || true
                    }
                    trap cleanup_cfg EXIT

                    find "$WORKSPACE" -mindepth 1 -maxdepth 1 \
                        ! -name '.git' \
                        ! -name 'trivy-*.json' \
                        ! -name 'runtime-verify-*.txt' \
                        -exec cp -a {} "$STAGE_DIR/" \\;

                    docker create \
                        --name "$CFG_CTR" \
                        -v "${CACHE_VOL}:/root/.cache/trivy" \
                        "$TRIVY_IMAGE" \
                        config \
                        --severity CRITICAL,HIGH,MEDIUM,LOW \
                        --format json \
                        --output /tmp/trivy-config-report.json \
                        --exit-code 0 \
                        /work >/dev/null

                    docker cp "$STAGE_DIR" "${CFG_CTR}:/work"
                    docker start -a "$CFG_CTR"
                    docker cp "${CFG_CTR}:/tmp/trivy-config-report.json" "${WORKSPACE}/${CONFIG_REPORT}"

                    echo "===== CONFIG SCAN SUMMARY ====="
                    docker run --rm -i "$BASE_PROBE_IMAGE" python3 -c '
import json, sys
from collections import Counter

data = json.load(sys.stdin)
counts = Counter()
for res in data.get("Results", []):
    for item in res.get("Misconfigurations") or []:
        counts[item.get("Severity", "UNKNOWN")] += 1

print("config:", " ".join(f"{s}={counts[s]}" for s in ("CRITICAL", "HIGH", "MEDIUM", "LOW")))
' < "${WORKSPACE}/${CONFIG_REPORT}"
                '''
            }
        }

        // ==========================================
        // 5. DOCKER BUILD
        // ==========================================
        stage('Docker Build') {
            steps {
                sh '''
                    set -eu

                    echo "===== BUILDING IMAGE: $FULL_IMAGE ====="
                    docker build \
                        --pull \
                        -f "${WORKSPACE}/${DOCKERFILE_REL}" \
                        -t "$FULL_IMAGE" \
                        "$WORKSPACE"

                    echo "===== IMAGE METADATA ====="
                    docker images "$FULL_IMAGE"
                    docker image inspect "$FULL_IMAGE" --format 'ID={{.Id}} Size={{.Size}} User={{.Config.User}} Workdir={{.Config.WorkingDir}} Exposed={{.Config.ExposedPorts}} Healthcheck={{if .Config.Healthcheck}}ENABLED{{else}}NONE{{end}} Cmd={{.Config.Cmd}}'
                '''
            }
        }

        // ==========================================
        // 6. TRIVY IMAGE SCAN (REPORTING MODE)
        // ==========================================
        stage('Trivy Image Scan') {
            steps {
                sh '''
                    set -eu

                    IMG_CTR="p9-img-${RUN_ID}"

                    cleanup_img() {
                        docker rm -f "$IMG_CTR" >/dev/null 2>&1 || true
                    }
                    trap cleanup_img EXIT

                    docker create \
                        --name "$IMG_CTR" \
                        -v /var/run/docker.sock:/var/run/docker.sock \
                        -v "${CACHE_VOL}:/root/.cache/trivy" \
                        "$TRIVY_IMAGE" \
                        image \
                        --severity CRITICAL,HIGH,MEDIUM,LOW \
                        --format json \
                        --output /tmp/trivy-image-report.json \
                        --exit-code 0 \
                        "$FULL_IMAGE" >/dev/null

                    docker start -a "$IMG_CTR"
                    docker cp "${IMG_CTR}:/tmp/trivy-image-report.json" "${WORKSPACE}/${IMAGE_REPORT}"

                    echo "===== IMAGE SCAN SUMMARY (ALL SEVERITIES, INCLUDING UNFIXED) ====="
                    docker run --rm -i "$BASE_PROBE_IMAGE" python3 -c '
import json, sys
from collections import Counter

data = json.load(sys.stdin)
counts = Counter()
for res in data.get("Results", []):
    for item in res.get("Vulnerabilities") or []:
        counts[item.get("Severity", "UNKNOWN")] += 1

print("image_cve:", " ".join(f"{s}={counts[s]}" for s in ("CRITICAL", "HIGH", "MEDIUM", "LOW")))
' < "${WORKSPACE}/${IMAGE_REPORT}"
                '''
            }
        }

        // ==========================================
        // 7. RUNTIME VERIFICATION
        // ==========================================
        stage('Runtime Verification') {
            steps {
                sh '''
                    set -eu

                    RT_CTR="p9-rt-${RUN_ID}"
                    RT_NET="p9-net-${RUN_ID}"
                    REPORT_FILE="${WORKSPACE}/${RUNTIME_REPORT}"

                    cleanup_rt() {
                        docker rm -f "$RT_CTR" >/dev/null 2>&1 || true
                        docker network rm "$RT_NET" >/dev/null 2>&1 || true
                    }
                    trap cleanup_rt EXIT

                    docker network create "$RT_NET" >/dev/null
                    docker run -d \
                        --name "$RT_CTR" \
                        --network "$RT_NET" \
                        -p 127.0.0.1::5000 \
                        "$FULL_IMAGE" >/dev/null

                    # Verifikasi HTTP / dan /health lewat jaringan Docker terisolasi
                    PROBE_OUT=$(docker run --rm --network "$RT_NET" "$BASE_PROBE_IMAGE" python3 -c "
import time, urllib.request, sys

base = 'http://${RT_CTR}:5000'
last_err = None
for _ in range(20):
    try:
        r_health = urllib.request.urlopen(base + '/health', timeout=2)
        b_health = r_health.read().decode().strip()
        r_root = urllib.request.urlopen(base + '/', timeout=2)
        b_root = r_root.read().decode().strip()
        print(f'GET / -> {r_root.status} {b_root}')
        print(f'GET /health -> {r_health.status} {b_health}')
        if r_root.status != 200 or r_health.status != 200:
            sys.exit(1)
        sys.exit(0)
    except Exception as exc:
        last_err = exc
        time.sleep(1)

print(f'ERROR: Endpoint tidak merespons: {last_err}', file=sys.stderr)
sys.exit(1)
")

                    PORT_MAP=$(docker port "$RT_CTR" 5000/tcp)
                    ACTUAL_ID=$(docker exec "$RT_CTR" id)
                    ACTUAL_UID=$(docker exec "$RT_CTR" id -u)
                    ACTUAL_GID=$(docker exec "$RT_CTR" id -g)
                    ACTUAL_PS=$(docker exec "$RT_CTR" ps -ef)

                    # Validasi user runtime sesuai peran branch eksperimen
                    USER_CHECK="INFO: branch=${RAW_BRANCH} uid=${ACTUAL_UID} gid=${ACTUAL_GID}"
                    if [ "$RAW_BRANCH" = "main" ]; then
                        if [ "$ACTUAL_UID" = "0" ] || [ "$ACTUAL_GID" = "0" ]; then
                            echo "[ERROR] Branch main (AFTER) tidak boleh berjalan sebagai root: $ACTUAL_ID"
                            exit 1
                        fi
                        USER_CHECK="PASS: non-root runtime terverifikasi (${ACTUAL_ID})"
                    elif [ "$RAW_BRANCH" = "before" ]; then
                        if [ "$ACTUAL_UID" != "0" ] || [ "$ACTUAL_GID" != "0" ]; then
                            echo "[ERROR] Branch before (BEFORE) diharapkan berjalan sebagai root: $ACTUAL_ID"
                            exit 1
                        fi
                        USER_CHECK="PASS: root runtime baseline terverifikasi (${ACTUAL_ID})"
                    fi

                    {
                        echo "Branch        : $RAW_BRANCH"
                        echo "Commit        : $SHORT_SHA"
                        echo "Image         : $FULL_IMAGE"
                        echo "PublishedPort : $PORT_MAP"
                        echo "RuntimeID     : $ACTUAL_ID"
                        echo "UserCheck     : $USER_CHECK"
                        echo "----- HTTP CHECKS -----"
                        echo "$PROBE_OUT"
                        echo "----- PROCESSES -----"
                        echo "$ACTUAL_PS"
                    } > "$REPORT_FILE"

                    cat "$REPORT_FILE"
                '''
            }
        }

        // ==========================================
        // 8. ARCHIVE ARTIFACTS
        // ==========================================
        stage('Archive Artifacts') {
            steps {
                archiveArtifacts(
                    artifacts: "${env.FS_REPORT},${env.CONFIG_REPORT},${env.IMAGE_REPORT},${env.RUNTIME_REPORT}",
                    allowEmptyArchive: false,
                    fingerprint: true
                )
            }
        }

        // ==========================================
        // 9. OPTIONAL SECURITY GATE (TERPISAH DARI REPORTING)
        // ==========================================
        stage('Security Gate') {
            when {
                expression { return params.ENABLE_SECURITY_GATE == true }
            }
            steps {
                sh '''
                    set -eu

                    echo "===== EVALUATING SECURITY GATE (THRESHOLD: CRITICAL=0, HIGH=0) ====="
                    docker run --rm -i "$BASE_PROBE_IMAGE" python3 -c '
import json, sys

data = json.load(sys.stdin)
crit = 0
high = 0
for res in data.get("Results", []):
    for item in res.get("Vulnerabilities") or []:
        sev = item.get("Severity", "")
        if sev == "CRITICAL":
            crit += 1
        elif sev == "HIGH":
            high += 1

print(f"Gate evaluation: CRITICAL={crit}, HIGH={high}")
if crit > 0 or high > 0:
    print("SECURITY GATE FAILED: ditemukan vulnerability CRITICAL atau HIGH.")
    sys.exit(1)
print("SECURITY GATE PASSED.")
' < "${WORKSPACE}/${IMAGE_REPORT}"
                '''
            }
        }

        // ==========================================
        // 10. CLEANUP
        // ==========================================
        stage('Cleanup') {
            steps {
                sh '''
                    set -eu

                    echo "===== CLEANING TEMPORARY CONTAINERS, NETWORK & IMAGE ====="
                    docker rm -f "p9-fs-${RUN_ID}" "p9-cfg-${RUN_ID}" "p9-img-${RUN_ID}" "p9-rt-${RUN_ID}" >/dev/null 2>&1 || true
                    docker network rm "p9-net-${RUN_ID}" >/dev/null 2>&1 || true
                    docker rmi -f "$FULL_IMAGE" >/dev/null 2>&1 || true
                '''
            }
        }
    }

    post {
        always {
            archiveArtifacts(
                artifacts: 'trivy-*.json,runtime-verify-*.txt',
                allowEmptyArchive: true,
                fingerprint: true
            )

            sh '''
                if [ -n "${RUN_ID:-}" ]; then
                    docker rm -f "p9-fs-${RUN_ID}" "p9-cfg-${RUN_ID}" "p9-img-${RUN_ID}" "p9-rt-${RUN_ID}" >/dev/null 2>&1 || true
                    docker network rm "p9-net-${RUN_ID}" >/dev/null 2>&1 || true
                fi
                if [ -n "${FULL_IMAGE:-}" ]; then
                    docker rmi -f "$FULL_IMAGE" >/dev/null 2>&1 || true
                fi
            '''
        }

        success {
            echo "Pipeline selesai dengan status SUCCESS untuk branch ${env.RAW_BRANCH ?: 'unknown'} (${env.SHORT_SHA ?: 'unknown'})."
        }

        failure {
            echo "Pipeline FAILED untuk branch ${env.RAW_BRANCH ?: 'unknown'} (${env.SHORT_SHA ?: 'unknown'}). Periksa log dan artifact JSON."
        }
    }
}
