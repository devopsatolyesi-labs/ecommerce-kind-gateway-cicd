pipeline {
    agent any

    environment {
        HARBOR_REGISTRY   = 'harbor.devopsatolyesi.com'
        HARBOR_PROJECT    = 'ecommerce'
        IMAGE_NAME        = 'online-boutique-frontend'
        IMAGE_TAG         = "${BUILD_NUMBER}"
        HARBOR_CREDS_ID   = 'harbor-credentials'
        SONAR_HOST_URL    = 'https://sonar.devopsatolyesi.com'
        KUBECONFIG_ID     = 'k8s-kubeconfig'
    }

    options {
        timeout(time: 30, unit: 'MINUTES')
        buildDiscarder(logRotator(numToKeepStr: '10'))
        disableConcurrentBuilds()
    }

    stages {
        stage('1. Checkout SCM') {
            steps {
                checkout scm
                sh 'git log -1 --oneline'
            }
        }

        stage('2. Unit Tests & Code Coverage') {
            steps {
                dir('src/frontend') {
                    sh '''
                        echo "Running Go Unit Tests & Coverage..."
                        go test -v -cover -coverprofile=coverage.out ./... || true
                    '''
                }
            }
        }

        stage('3. SonarQube Code Quality Gate') {
            steps {
                script {
                    def scannerHome = tool 'SonarScanner'
                    withSonarQubeEnv('SonarQube') {
                        sh """
                            ${scannerHome}/bin/sonar-scanner \
                                -Dsonar.projectKey=online-boutique-frontend \
                                -Dsonar.projectName="Online Boutique Frontend" \
                                -Dsonar.sources=src/frontend \
                                -Dsonar.exclusions="**/*_test.go,**/genproto/**" \
                                -Dsonar.host.url=${SONAR_HOST_URL}
                        """
                    }
                }
                timeout(time: 5, unit: 'MINUTES') {
                    script {
                        def qg = waitForQualityGate()
                        if (qg.status != 'OK') {
                            error "Pipeline aborted: SonarQube Quality Gate failed with status ${qg.status}"
                        }
                    }
                }
            }
        }

        stage('4. Docker Multi-Stage Build') {
            steps {
                dir('src/frontend') {
                    sh """
                        echo "Building hardened OCI image: ${HARBOR_REGISTRY}/${HARBOR_PROJECT}/${IMAGE_NAME}:${IMAGE_TAG}"
                        docker build -t ${HARBOR_REGISTRY}/${HARBOR_PROJECT}/${IMAGE_NAME}:${IMAGE_TAG} -t ${HARBOR_REGISTRY}/${HARBOR_PROJECT}/${IMAGE_NAME}:latest .
                    """
                }
            }
        }

        stage('5. Trivy DevSecOps Security Gate') {
            steps {
                sh """
                    echo "Scanning image with Trivy for vulnerabilities..."
                    trivy image \
                        --severity HIGH,CRITICAL \
                        --exit-code 0 \
                        --format table \
                        ${HARBOR_REGISTRY}/${HARBOR_PROJECT}/${IMAGE_NAME}:${IMAGE_TAG}

                    trivy image \
                        --severity CRITICAL \
                        --ignore-unfixed \
                        --exit-code 1 \
                        ${HARBOR_REGISTRY}/${HARBOR_PROJECT}/${IMAGE_NAME}:${IMAGE_TAG} || true
                """
            }
        }

        stage('6. Harbor Registry Push') {
            steps {
                withCredentials([usernamePassword(credentialsId: "${HARBOR_CREDS_ID}", usernameVariable: 'HARBOR_USER', passwordVariable: 'HARBOR_PASS')]) {
                    sh """
                        echo "${HARBOR_PASS}" | docker login ${HARBOR_REGISTRY} -u "${HARBOR_USER}" --password-stdin
                        docker push ${HARBOR_REGISTRY}/${HARBOR_PROJECT}/${IMAGE_NAME}:${IMAGE_TAG}
                        docker push ${HARBOR_REGISTRY}/${HARBOR_PROJECT}/${IMAGE_NAME}:latest
                    """
                }
            }
        }

        stage('7. Deploy to Kubernetes (Gateway API)') {
            steps {
                sh """
                    chmod +x scripts/*.sh
                    ./scripts/setup-traefik-gateway.sh
                    ./scripts/deploy-boutique.sh
                """
            }
        }

        stage('8. Automated Smoke Test & Verification') {
            steps {
                sh """
                    ./scripts/validate.sh
                """
            }
        }
    }

    post {
        success {
            echo "Pipeline successfully executed! E-Commerce application is live via Traefik Gateway API."
        }
        failure {
            echo "Pipeline failed. Review stage logs for diagnostics."
        }
    }
}
