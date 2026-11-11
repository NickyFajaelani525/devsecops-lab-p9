
pipeline {
    agent any

    options {
        skipDefaultCheckout(true)
        disableConcurrentBuilds()
        timestamps()
    }

    environment {
        IMAGE_NAME = 'my-app'
        TRIVY_IMAGE = 'aquasec/trivy:latest'
    }

    stages {

        // ==========================================
        // 1. CLEAN WORKSPACE
        // ==========================================
        stage('Clean Workspace') {
            steps {
                cleanWs()
            }
        }

        // ==========================================
        // 2. CHECKOUT SOURCE CODE
        // ==========================================
        stage('Checkout SCM') {
            steps {
                checkout scm

                echo 'Source code checkout completed.'
            }
        }

        // ==========================================
        // 3. TRIVY FILESYSTEM SCAN
        // ==========================================
        stage('SCA - Trivy Filesystem') {
            steps {
                sh '''
                    set -eu

                    IMAGE_TAG="${BUILD_NUMBER}"

                    TRIVY_PATH="/var/jenkins_home/trivy-workspace/${BUILD_NUMBER}"
                    TRIVY_CACHE="/var/jenkins_home/trivy-cache"
                    SCAN_TARGET="$TRIVY_PATH/target"

                    echo "===== PREPARING FILESYSTEM SCAN ====="

                    mkdir -p "$SCAN_TARGET"
                    mkdir -p "$TRIVY_CACHE"

                    # Pastikan file yang dibutuhkan tersedia
                    for FILE in app.py requirements.txt Dockerfile.secure .dockerignore
                    do
                        if [ ! -f "$WORKSPACE/$FILE" ]; then
                            echo "ERROR: File $FILE tidak ditemukan!"
                            exit 1
                        fi
                    done

                    # Salin source ke named volume Jenkins
                    cp app.py requirements.txt Dockerfile.secure .dockerignore "$SCAN_TARGET/"

                    echo "===== RUNNING TRIVY FILESYSTEM SCAN ====="

                    docker run --rm \
                        -v jenkins_home:/jenkins_home \
                        "$TRIVY_IMAGE" \
                        fs "/jenkins_home/trivy-workspace/${BUILD_NUMBER}/target" \
                        --cache-dir /jenkins_home/trivy-cache \
                        --scanners vuln,misconfig,secret \
                        --severity HIGH,CRITICAL \
                        --format json \
                        --output "/jenkins_home/trivy-workspace/${BUILD_NUMBER}/trivy-fs-report.json" \
                        --exit-code 0

                    # Salin laporan kembali ke workspace Jenkins
                    cp "$TRIVY_PATH/trivy-fs-report.json" \
                       "$WORKSPACE/trivy-fs-report.json"

                    echo "===== FILESYSTEM SCAN COMPLETED ====="
                '''
            }
        }

        // ==========================================
        // 4. BUILD DOCKER IMAGE
        // ==========================================
        stage('Build Docker Image') {
            steps {
                sh '''
                    set -eu

                    IMAGE_TAG="${BUILD_NUMBER}"

                    echo "===== BUILDING DOCKER IMAGE ====="

                    docker build \
                        --pull \
                        --no-cache \
                        -f Dockerfile.secure \
                        -t "${IMAGE_NAME}:${IMAGE_TAG}" \
                        .

                    echo "===== DOCKER IMAGE BUILT ====="

                    docker images "${IMAGE_NAME}:${IMAGE_TAG}"
                '''
            }
        }

        // ==========================================
        // 5. TRIVY CONTAINER IMAGE SCAN
        // ==========================================
        stage('SCA - Trivy Image Scan') {
            steps {
                sh '''
                    set -eu

                    IMAGE_TAG="${BUILD_NUMBER}"

                    TRIVY_PATH="/var/jenkins_home/trivy-workspace/${BUILD_NUMBER}"
                    TRIVY_CACHE="/jenkins_home/trivy-cache"
                    TRIVY_REPORT="$TRIVY_PATH/trivy-image-report.json"

                    echo "===== RUNNING TRIVY IMAGE SCAN ====="

                    # Jangan langsung menghentikan shell ketika Trivy
                    # mengembalikan exit code 1 karena vulnerability.
                    set +e

                    docker run --rm \
                        -v /var/run/docker.sock:/var/run/docker.sock \
                        -v jenkins_home:/jenkins_home \
                        "$TRIVY_IMAGE" \
                        image "${IMAGE_NAME}:${IMAGE_TAG}" \
                        --cache-dir "$TRIVY_CACHE" \
                        --severity HIGH,CRITICAL \
                        --ignore-unfixed \
                        --format json \
                        --output "$TRIVY_REPORT" \
                        --exit-code 1

                    TRIVY_STATUS=$?

                    set -e

                    # Simpan laporan ke workspace meskipun scan gagal
                    if [ -f "$TRIVY_REPORT" ]; then
                        cp "$TRIVY_REPORT" \
                           "$WORKSPACE/trivy-image-report.json"

                        echo "Trivy image report copied to workspace."
                    else
                        echo "WARNING: Trivy image report was not generated."
                    fi

                    # Kembalikan status Trivy ke Jenkins
                    if [ "$TRIVY_STATUS" -ne 0 ]; then
                        echo "===== IMAGE SCAN FAILED ====="
                        echo "Vulnerability ditemukan atau proses scan mengalami error."
                        exit "$TRIVY_STATUS"
                    fi

                    echo "===== IMAGE SCAN COMPLETED ====="
                '''
            }
        }
    }

    // ==========================================
    // 6. POST BUILD ACTIONS
    // ==========================================
    post {
        always {
            echo '===== ARCHIVING TRIVY REPORTS ====='

            archiveArtifacts(
                artifacts: 'trivy-*-report.json',
                allowEmptyArchive: true,
                fingerprint: true
            )

            echo '===== CLEANING TRIVY TEMPORARY FILES ====='

            sh '''
                rm -rf "/var/jenkins_home/trivy-workspace/${BUILD_NUMBER}"
            '''

            echo '===== PIPELINE FINISHED ====='
        }

        success {
            echo 'Pipeline completed successfully.'
        }

        failure {
            echo 'Pipeline failed. Check the console output and Trivy reports.'
        }
    }
}
