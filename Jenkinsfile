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
            defaultValue: 'my-app',
            description: 'Nama Docker image'
        )
    }

    environment {
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
        stage('Trivy Filesystem Scan') {
            steps {
                sh '''
                    set -eu

                    TRIVY_PATH="/var/jenkins_home/trivy-workspace/${BUILD_NUMBER}"
                    TRIVY_CACHE="/var/jenkins_home/trivy-cache"
                    SCAN_TARGET="$TRIVY_PATH/target"

                    echo "===== PREPARING FILESYSTEM SCAN ====="

                    mkdir -p "$SCAN_TARGET"
                    mkdir -p "$TRIVY_CACHE"

                    # Salin seluruh isi repository ke named volume
                    cp -a "$WORKSPACE/." "$SCAN_TARGET/"

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

                    # Salin laporan ke Jenkins workspace
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

                    DOCKERFILE_PATH="${DOCKERFILE_PATH}"
                    IMAGE_TAG="${BUILD_NUMBER}"

                    echo "===== VALIDATING DOCKERFILE ====="

                    if [ ! -f "$WORKSPACE/$DOCKERFILE_PATH" ]; then
                        echo "ERROR: Dockerfile tidak ditemukan: $DOCKERFILE_PATH"
                        exit 1
                    fi

                    echo "Dockerfile: $DOCKERFILE_PATH"
                    echo "Image: ${IMAGE_NAME}:${IMAGE_TAG}"

                    echo "===== BUILDING DOCKER IMAGE ====="

                    docker build \
                        --pull \
                        -f "$DOCKERFILE_PATH" \
                        -t "${IMAGE_NAME}:${IMAGE_TAG}" \
                        "$WORKSPACE"

                    echo "===== DOCKER IMAGE BUILT ====="

                    docker images "${IMAGE_NAME}:${IMAGE_TAG}"
                '''
            }
        }

        // ==========================================
        // 5. TRIVY IMAGE SCAN
        // ==========================================
        stage('Trivy Image Scan') {
            steps {
                sh '''
                    set -eu

                    IMAGE_TAG="${BUILD_NUMBER}"

                    TRIVY_PATH="/var/jenkins_home/trivy-workspace/${BUILD_NUMBER}"
                    TRIVY_REPORT="$TRIVY_PATH/trivy-image-report.json"

                    echo "===== RUNNING TRIVY IMAGE SCAN ====="

                    set +e

                    docker run --rm \
                        -v /var/run/docker.sock:/var/run/docker.sock \
                        -v jenkins_home:/jenkins_home \
                        "$TRIVY_IMAGE" \
                        image "${IMAGE_NAME}:${IMAGE_TAG}" \
                        --cache-dir /jenkins_home/trivy-cache \
                        --severity HIGH,CRITICAL \
                        --ignore-unfixed \
                        --format json \
                        --output "$TRIVY_REPORT" \
                        --exit-code 1

                    TRIVY_STATUS=$?

                    set -e

                    # Simpan laporan sebelum mengembalikan exit code
                    if [ -f "$TRIVY_REPORT" ]; then
                        cp "$TRIVY_REPORT" \
                           "$WORKSPACE/trivy-image-report.json"

                        echo "Image scan report copied successfully."
                    else
                        echo "WARNING: Image scan report was not generated."
                    fi

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
    // 6. POST BUILD
    // ==========================================
    post {
        always {
            echo '===== ARCHIVING TRIVY REPORTS ====='

            archiveArtifacts(
                artifacts: 'trivy-*-report.json',
                allowEmptyArchive: true,
                fingerprint: true
            )

            echo '===== CLEANING TEMPORARY FILES ====='

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
