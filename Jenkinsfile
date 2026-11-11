pipeline {
    agent any

    environment {
        IMAGE_NAME = 'devsecops-lab4-app'
        IMAGE_TAG  = ''
    }

    stages {

        // ==========================================
        // STAGE 0: CLEAN WORKSPACE
        // ==========================================
        stage('Clean Workspace') {
            steps {
                cleanWs()
            }
        }


        // ==========================================
        // STAGE 1: CHECKOUT SOURCE CODE
        // ==========================================
        stage('Checkout SCM') {
            steps {
                checkout scm

                sh '''
                    echo "===== SOURCE CODE ====="
                    ls -la

                    echo "===== REQUIRED FILES ====="

                    for file in app.py requirements.txt Dockerfile .dockerignore; do
                        if [ ! -f "$file" ]; then
                            echo "[ERROR] File $file tidak ditemukan!"
                            exit 1
                        fi

                        echo "[OK] $file"
                    done
                '''
            }
        }


        // ==========================================
        // STAGE 2: TRIVY FILESYSTEM SCAN
        // ==========================================
        stage('SCA - Trivy Filesystem') {
            steps {
                sh '''
                    set -eu

                    SCAN_PATH="${WORKSPACE#/var/jenkins_home}"
                    TRIVY_PATH="/jenkins_home${SCAN_PATH}"
                    TRIVY_CACHE="/jenkins_home/trivy-cache"

                    SCAN_TARGET="$TRIVY_PATH/.trivy-scan-target"

                    # Validasi workspace
                    if [ "$SCAN_PATH" = "$WORKSPACE" ]; then
                        echo "[ERROR] Workspace tidak berada di /var/jenkins_home"
                        exit 1
                    fi

                    # Siapkan direktori
                    mkdir -p "$TRIVY_CACHE"
                    mkdir -p "$SCAN_TARGET"

                    # Salin hanya file yang akan di-scan
                    cp app.py requirements.txt Dockerfile .dockerignore "$SCAN_TARGET/"

                    echo "===== TRIVY FILESYSTEM SCAN ====="

                    docker run --rm \
                        -v jenkins_home:/jenkins_home \
                        aquasec/trivy:latest \
                        fs "$SCAN_TARGET" \
                        --cache-dir "$TRIVY_CACHE" \
                        --scanners vuln,misconfig,secret \
                        --severity MEDIUM,HIGH,CRITICAL \
                        --format json \
                        --output "$TRIVY_PATH/trivy-fs-report.json" \
                        --exit-code 0

                    # Hapus direktori sementara
                    rm -rf "$SCAN_TARGET"

                    echo "Filesystem scan completed."
                '''
            }
        }


        // ==========================================
        // STAGE 3: BUILD DOCKER IMAGE
        // ==========================================
        stage('Build Image') {
            steps {
                script {
                    env.IMAGE_TAG = sh(
                        script: 'git rev-parse --short HEAD',
                        returnStdout: true
                    ).trim()
                }

                sh '''
                    echo "===== BUILD DOCKER IMAGE ====="

                    docker build --pull --no-cache \
                        -f Dockerfile \
                        -t "${IMAGE_NAME}:${IMAGE_TAG}" \
                        "${WORKSPACE}"

                    echo "===== IMAGE INFORMATION ====="

                    docker images "${IMAGE_NAME}:${IMAGE_TAG}"
                '''
            }
        }


        // ==========================================
        // STAGE 4: TRIVY CONTAINER IMAGE SCAN
        // ==========================================
        stage('Container Scan - Trivy Image') {
            steps {
                sh '''
                    set -eu

                    SCAN_PATH="${WORKSPACE#/var/jenkins_home}"
                    TRIVY_PATH="/jenkins_home${SCAN_PATH}"
                    TRIVY_CACHE="/jenkins_home/trivy-cache"

                    echo "===== TRIVY CONTAINER SCAN ====="

                    docker run --rm \
                        -v /var/run/docker.sock:/var/run/docker.sock \
                        -v jenkins_home:/jenkins_home \
                        aquasec/trivy:latest \
                        image "${IMAGE_NAME}:${IMAGE_TAG}" \
                        --cache-dir "$TRIVY_CACHE" \
                        --severity CRITICAL,HIGH \
                        --ignore-unfixed \
                        --format json \
                        --output "$TRIVY_PATH/trivy-image-report.json" \
                        --exit-code 1

                    echo "Container image scan passed!"
                '''
            }
        }
    }


    // ==========================================
    // POST BUILD
    // ==========================================
    post {

        always {
            echo '===== ARCHIVING TRIVY REPORTS ====='

            archiveArtifacts(
                artifacts: 'trivy-*-report.json',
                allowEmptyArchive: true,
                fingerprint: true
            )
        }

        success {
            echo 'Pipeline SUCCESS: Security checks passed.'
        }

        failure {
            echo 'Pipeline FAILED: Check the security scan results.'
        }
    }
}
