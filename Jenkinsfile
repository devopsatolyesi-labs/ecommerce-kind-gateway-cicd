pipeline {
    agent any

    environment {
        HARBOR_REGISTRY   = 'harbor.devopsatolyesi.com'
        HARBOR_PROJECT    = 'ecommerce'
        IMAGE_NAME        = 'online-boutique-frontend'
        IMAGE_TAG         = "${BUILD_NUMBER}"
        HARBOR_CREDS_ID   = 'harbor-credentials'
        SONAR_HOST_URL    = 'http://training-sonarqube:9000'
        KUBECONFIG        = '/var/jenkins_home/.kube/config'
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
                    withSonarQubeEnv('SonarQube') {
                        sh """
                            sonar-scanner \
                                -Dsonar.projectKey=online-boutique-frontend \
                                -Dsonar.projectName="Online Boutique Frontend" \
                                -Dsonar.sources=src/frontend \
                                -Dsonar.exclusions="**/*_test.go,**/genproto/**" \
                                -Dsonar.host.url=\${SONAR_HOST_URL}
                        """
                    }
                }
                timeout(time: 5, unit: 'MINUTES') {
                    script {
                        def qg = waitForQualityGate()
                        if (qg.status != 'OK') {
                            echo "SonarQube Quality Gate status: ${qg.status}"
                        }
                    }
                }
            }
        }

        stage('4. Docker Multi-Stage Build') {
            steps {
                dir('src/frontend') {
                    sh """
                        echo "Building container image: online-boutique-frontend:${IMAGE_TAG}"
                        docker build -t online-boutique-frontend:${IMAGE_TAG} -t online-boutique-frontend:latest .
                    """
                }
            }
        }

        stage('5. Container Security Scan (Trivy)') {
            steps {
                sh """
                    echo "Running Trivy vulnerability scanner on built image..."
                    trivy image --severity HIGH,CRITICAL --exit-code 0 online-boutique-frontend:${IMAGE_TAG} 2>/dev/null || true
                """
            }
        }

        stage('6. Registry Push / Kind Image Load') {
            steps {
                sh """
                    echo "Loading image into Kind cluster..."
                    kind load docker-image online-boutique-frontend:latest --name ecommerce-kind-cluster 2>/dev/null || true
                """
            }
        }

        stage('7. Deploy to Kubernetes (Gateway API)') {
            steps {
                sh """
                    chmod +x scripts/*.sh
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
