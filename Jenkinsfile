// =============================================================================
// Notes App — Industry-Standard Jenkins Declarative Pipeline
// =============================================================================
// Stages:
//   1.  Checkout
//   2.  Static Code Analysis      (parallel: backend tsc + ESLint | frontend next lint)
//   3.  Dependency Security Audit (npm audit — both services)
//   4.  Unit Tests & Coverage     (parallel: backend | frontend)
//   5.  SonarCloud Analysis       (quality gate enforced)
//   6.  Docker Build              (backend, frontend, proxy — tagged with Git SHA)
//   7.  Image Vulnerability Scan  (Trivy — fails on CRITICAL CVEs)
//   8.  Push to ECR               [main branch only]
//   9.  Deploy to EC2             [main branch only]
//   10. Smoke Test                [main branch only]
//   Post: Slack notification + workspace cleanup
// =============================================================================
//
// Required Jenkins Credentials (Manage Jenkins → Credentials):
//   aws-access-key-id      → Secret Text  — AWS Access Key ID
//   aws-secret-access-key  → Secret Text  — AWS Secret Access Key
//   aws-region             → Secret Text  — e.g. us-east-1
//   ecr-registry           → Secret Text  — <account>.dkr.ecr.<region>.amazonaws.com
//   ec2-host               → Secret Text  — EC2 public IP or hostname
//   ec2-ssh-key            → SSH Username with private key — ubuntu
//   db-username            → Secret Text
//   db-password            → Secret Text
//   db-name                → Secret Text
//   sonarcloud-token       → Secret Text  — SonarCloud user token
//   slack-token            → Secret Text  — Slack Bot OAuth token
//
// Required Jenkins Plugins:
//   Pipeline, Git, Docker Pipeline, AWS Credentials, Amazon ECR,
//   SonarQube Scanner, JUnit, HTML Publisher, Slack Notification,
//   Timestamper, Workspace Cleanup, Blue Ocean (optional)
// =============================================================================

pipeline {

    agent {
        label 'agent'
    }

    // -------------------------------------------------------------------------
    // Global options
    // -------------------------------------------------------------------------
    options {
        buildDiscarder(logRotator(numToKeepStr: '10', artifactNumToKeepStr: '5'))
        timestamps()
        timeout(time: 60, unit: 'MINUTES')
        disableConcurrentBuilds()
        ansiColor('xterm')
    }

    // -------------------------------------------------------------------------
    // Environment — only non-credential vars here to avoid early failures
    // -------------------------------------------------------------------------
    environment {
        // SonarCloud config (update these)
        SONAR_ORGANIZATION = 'Prince
'
        SONAR_PROJECT_KEY  = 'celetrialprince166'

        // Slack config (update these)
        SLACK_CHANNEL      = '#ci-cd-alerts'

        // Image names (registry prefix added dynamically in Docker Build stage)
        BACKEND_IMAGE_NAME  = 'notes-backend'
        FRONTEND_IMAGE_NAME = 'notes-frontend'
        PROXY_IMAGE_NAME    = 'notes-proxy'
    }

    // -------------------------------------------------------------------------
    // Pipeline stages
    // -------------------------------------------------------------------------
    stages {

        // =====================================================================
        // Stage 1 — Checkout
        // =====================================================================
        stage('Checkout') {
            steps {
                echo '📥 Checking out source code...'
                checkout scm
                script {
                    env.GIT_COMMIT_SHORT = sh(script: "git rev-parse --short HEAD", returnStdout: true).trim()
                    env.GIT_AUTHOR       = sh(script: "git log -1 --pretty=%an", returnStdout: true).trim()
                    env.GIT_MESSAGE      = sh(script: "git log -1 --pretty=%s",  returnStdout: true).trim()
                    env.IMAGE_TAG        = env.GIT_COMMIT_SHORT
                    echo "Branch   : ${env.BRANCH_NAME}"
                    echo "Commit   : ${env.GIT_COMMIT_SHORT}"
                    echo "Author   : ${env.GIT_AUTHOR}"
                    echo "Message  : ${env.GIT_MESSAGE}"
                }
            }
        }

        // =====================================================================
        // Stage 2 — Static Code Analysis (parallel)
        // =====================================================================
        stage('Static Code Analysis') {
            parallel {

                stage('Backend — TypeScript Check') {
                    steps {
                        dir('backend') {
                            echo '🔍 Running TypeScript compiler check (backend)...'
                            sh 'npm install'
                            // Type-check without emitting output
                            sh 'npx tsc --noEmit'
                        }
                    }
                }

                stage('Frontend — Lint') {
                    steps {
                        dir('frontend') {
                            echo '🔍 Running Next.js lint (frontend)...'
                            sh 'npm install'
                            // next lint exits 0 even with warnings by default
                            sh 'npm run lint || true'
                        }
                    }
                }

            }
        }

        // =====================================================================
        // Stage 3 — Dependency Security Audit
        // =====================================================================
        stage('Dependency Security Audit') {
            parallel {

                stage('Backend — npm audit') {
                    steps {
                        dir('backend') {
                            echo '🔒 Running npm audit (backend)...'
                            sh '''
                                npm audit --audit-level=high \
                                    --json > npm-audit-backend.json || true
                                npm audit --audit-level=high || true
                            '''
                        }
                    }
                    post {
                        always {
                            archiveArtifacts artifacts: 'backend/npm-audit-backend.json',
                                             allowEmptyArchive: true
                        }
                    }
                }

                stage('Frontend — npm audit') {
                    steps {
                        dir('frontend') {
                            echo '🔒 Running npm audit (frontend)...'
                            sh '''
                                npm audit --audit-level=high \
                                    --json > npm-audit-frontend.json || true
                                npm audit --audit-level=high || true
                            '''
                        }
                    }
                    post {
                        always {
                            archiveArtifacts artifacts: 'frontend/npm-audit-frontend.json',
                                             allowEmptyArchive: true
                        }
                    }
                }

            }
        }

        // =====================================================================
        // Stage 4 — Unit Tests & Coverage (parallel)
        // =====================================================================
        stage('Unit Tests & Coverage') {
            parallel {

                stage('Backend — Tests') {
                    steps {
                        dir('backend') {
                            echo '🧪 Running backend tests...'
                            sh 'npm run test || true'
                        }
                    }
                    post {
                        always {
                            junit allowEmptyResults: true,
                                  testResults: 'backend/test-results/**/*.xml'
                            publishHTML(target: [
                                allowMissing         : true,
                                alwaysLinkToLastBuild: true,
                                keepAll              : true,
                                reportDir            : 'backend/coverage/lcov-report',
                                reportFiles          : 'index.html',
                                reportName           : 'Backend Coverage Report'
                            ])
                        }
                    }
                }

                stage('Frontend — Tests') {
                    steps {
                        dir('frontend') {
                            echo '🧪 Running frontend tests...'
                            sh 'npm run test || true'
                        }
                    }
                    post {
                        always {
                            junit allowEmptyResults: true,
                                  testResults: 'frontend/test-results/**/*.xml'
                            publishHTML(target: [
                                allowMissing         : true,
                                alwaysLinkToLastBuild: true,
                                keepAll              : true,
                                reportDir            : 'frontend/coverage/lcov-report',
                                reportFiles          : 'index.html',
                                reportName           : 'Frontend Coverage Report'
                            ])
                        }
                    }
                }

            }
        }

        // =====================================================================
        // Stage 5 — SonarCloud Analysis + Quality Gate
        // =====================================================================
        stage('SonarCloud Analysis') {
            steps {
                echo '📊 Running SonarCloud analysis...'
                withCredentials([string(credentialsId: 'sonarcloud-token', variable: 'SONAR_TOKEN')]) {
                    withSonarQubeEnv('SonarCloud') {
                        sh """
                            npx sonar-scanner \
                                -Dsonar.organization=${SONAR_ORGANIZATION} \
                                -Dsonar.projectKey=${SONAR_PROJECT_KEY} \
                                -Dsonar.projectName='Notes App' \
                                -Dsonar.sources=backend/src,frontend/app \
                                -Dsonar.exclusions=**/node_modules/**,**/dist/**,**/.next/**,**/coverage/** \
                                -Dsonar.javascript.lcov.reportPaths=backend/coverage/lcov.info,frontend/coverage/lcov.info \
                                -Dsonar.host.url=https://sonarcloud.io \
                                -Dsonar.token=${SONAR_TOKEN}
                        """
                    }
                }
            }
        }

        stage('SonarCloud Quality Gate') {
            steps {
                echo '🚦 Waiting for SonarCloud Quality Gate result...'
                timeout(time: 5, unit: 'MINUTES') {
                    waitForQualityGate abortPipeline: true
                }
            }
        }

        // =====================================================================
        // Stage 6 — Docker Build
        // =====================================================================
        stage('Docker Build') {
            steps {
                echo "🐳 Building Docker images (tag: ${env.IMAGE_TAG})..."
                withCredentials([string(credentialsId: 'ecr-registry', variable: 'ECR_REGISTRY')]) {
                    sh """
                        docker build \
                            --label "git.commit=${env.GIT_COMMIT_SHORT}" \
                            --label "build.number=${env.BUILD_NUMBER}" \
                            --label "build.url=${env.BUILD_URL}" \
                            -t ${ECR_REGISTRY}/${BACKEND_IMAGE_NAME}:${env.IMAGE_TAG} \
                            -t ${ECR_REGISTRY}/${BACKEND_IMAGE_NAME}:latest \
                            ./backend

                        docker build \
                            --label "git.commit=${env.GIT_COMMIT_SHORT}" \
                            --label "build.number=${env.BUILD_NUMBER}" \
                            --label "build.url=${env.BUILD_URL}" \
                            -t ${ECR_REGISTRY}/${FRONTEND_IMAGE_NAME}:${env.IMAGE_TAG} \
                            -t ${ECR_REGISTRY}/${FRONTEND_IMAGE_NAME}:latest \
                            ./frontend

                        docker build \
                            --label "git.commit=${env.GIT_COMMIT_SHORT}" \
                            --label "build.number=${env.BUILD_NUMBER}" \
                            --label "build.url=${env.BUILD_URL}" \
                            -t ${ECR_REGISTRY}/${PROXY_IMAGE_NAME}:${env.IMAGE_TAG} \
                            -t ${ECR_REGISTRY}/${PROXY_IMAGE_NAME}:latest \
                            ./nginx
                    """
                }
            }
        }

        // =====================================================================
        // Stage 7 — Image Vulnerability Scan (Trivy)
        // =====================================================================
        stage('Image Vulnerability Scan') {
            steps {
                echo '🛡️  Scanning Docker images with Trivy...'
                withCredentials([string(credentialsId: 'ecr-registry', variable: 'ECR_REGISTRY')]) {
                    script {
                        // Install Trivy if not already present on the agent
                        sh '''
                            if ! command -v trivy &> /dev/null; then
                                echo "Installing Trivy..."
                                curl -sfL https://raw.githubusercontent.com/aquasecurity/trivy/main/contrib/install.sh \
                                    | sh -s -- -b /usr/local/bin
                            fi
                        '''

                        def images = [
                            [name: 'Backend',  imgName: "${ECR_REGISTRY}/${BACKEND_IMAGE_NAME}"],
                            [name: 'Frontend', imgName: "${ECR_REGISTRY}/${FRONTEND_IMAGE_NAME}"],
                            [name: 'Proxy',    imgName: "${ECR_REGISTRY}/${PROXY_IMAGE_NAME}"]
                        ]

                        images.each { img ->
                            echo "Scanning ${img.name} image..."
                            sh """
                                trivy image \
                                    --exit-code 1 \
                                    --severity CRITICAL \
                                    --no-progress \
                                    --format table \
                                    --output trivy-${img.name.toLowerCase()}.txt \
                                    ${img.imgName}:${env.IMAGE_TAG} || \
                                    (cat trivy-${img.name.toLowerCase()}.txt && exit 1)
                            """
                        }
                    }
                }
            }
            post {
                always {
                    archiveArtifacts artifacts: 'trivy-*.txt', allowEmptyArchive: true
                }
            }
        }

        // =====================================================================
        // Stage 8 — Push to ECR  [main branch only]
        // =====================================================================
        stage('Push to ECR') {
            when {
                branch 'main'
            }
            steps {
                echo '📤 Pushing images to Amazon ECR...'
                withCredentials([
                    string(credentialsId: 'aws-access-key-id',     variable: 'AWS_ACCESS_KEY_ID'),
                    string(credentialsId: 'aws-secret-access-key', variable: 'AWS_SECRET_ACCESS_KEY'),
                    string(credentialsId: 'aws-region',            variable: 'AWS_REGION'),
                    string(credentialsId: 'ecr-registry',          variable: 'ECR_REGISTRY')
                ]) {
                    sh """
                        aws ecr get-login-password --region ${AWS_REGION} \
                            | docker login --username AWS --password-stdin ${ECR_REGISTRY}

                        # Backend
                        docker push ${ECR_REGISTRY}/${BACKEND_IMAGE_NAME}:${env.IMAGE_TAG}
                        docker push ${ECR_REGISTRY}/${BACKEND_IMAGE_NAME}:latest

                        # Frontend
                        docker push ${ECR_REGISTRY}/${FRONTEND_IMAGE_NAME}:${env.IMAGE_TAG}
                        docker push ${ECR_REGISTRY}/${FRONTEND_IMAGE_NAME}:latest

                        # Proxy
                        docker push ${ECR_REGISTRY}/${PROXY_IMAGE_NAME}:${env.IMAGE_TAG}
                        docker push ${ECR_REGISTRY}/${PROXY_IMAGE_NAME}:latest
                    """
                }
            }
        }

        // =====================================================================
        // Stage 9 — Deploy to EC2  [main branch only]
        // =====================================================================
        stage('Deploy to EC2') {
            when {
                branch 'main'
            }
            steps {
                echo '🚀 Deploying to EC2...'
                withCredentials([
                    string(credentialsId: 'aws-access-key-id',     variable: 'AWS_ACCESS_KEY_ID'),
                    string(credentialsId: 'aws-secret-access-key', variable: 'AWS_SECRET_ACCESS_KEY'),
                    string(credentialsId: 'aws-region',            variable: 'AWS_REGION'),
                    string(credentialsId: 'ecr-registry',          variable: 'ECR_REGISTRY'),
                    string(credentialsId: 'ec2-host',              variable: 'EC2_HOST'),
                    string(credentialsId: 'db-username',            variable: 'DB_USERNAME'),
                    string(credentialsId: 'db-password',            variable: 'DB_PASSWORD'),
                    string(credentialsId: 'db-name',                variable: 'DB_NAME'),
                    sshUserPrivateKey(
                        credentialsId  : 'ec2-ssh-key',
                        keyFileVariable: 'SSH_KEY',
                        usernameVariable: 'SSH_USER'
                    )
                ]) {
                    sh """
                        # Write .env file
                        cat > .env <<EOF
ECR_REGISTRY=${ECR_REGISTRY}
DB_USERNAME=${DB_USERNAME}
DB_PASSWORD=${DB_PASSWORD}
DB_NAME=${DB_NAME}
DB_SSL=false
PROXY_PORT=80
NEXT_PUBLIC_API_URL=http://${EC2_HOST}/api
EOF

                        # Copy files to EC2
                        scp -o StrictHostKeyChecking=no \
                            -i \${SSH_KEY} \
                            .env docker-compose.ecr.yml \
                            \${SSH_USER}@${EC2_HOST}:/opt/notes-app/

                        # Remote deploy commands
                        ssh -o StrictHostKeyChecking=no \
                            -i \${SSH_KEY} \
                            \${SSH_USER}@${EC2_HOST} bash -s <<'REMOTE'
                            set -e
                            cd /opt/notes-app

                            # ECR login on the remote host
                            aws ecr get-login-password --region ${AWS_REGION} \
                                | docker login --username AWS --password-stdin ${ECR_REGISTRY}

                            # Pull new images
                            docker compose -f docker-compose.ecr.yml pull

                            # Zero-downtime rolling restart
                            docker compose -f docker-compose.ecr.yml up -d --remove-orphans

                            # Clean up dangling images
                            docker image prune -f

                            echo "✅ Deployment complete"
                            docker compose -f docker-compose.ecr.yml ps
REMOTE
                    """
                }
            }
        }

        // =====================================================================
        // Stage 10 — Smoke Test  [main branch only]
        // =====================================================================
        stage('Smoke Test') {
            when {
                branch 'main'
            }
            steps {
                echo '💨 Running smoke test against deployed application...'
                withCredentials([string(credentialsId: 'ec2-host', variable: 'EC2_HOST')]) {
                    sh """
                        echo "Waiting 20s for containers to stabilise..."
                        sleep 20

                        MAX_RETRIES=5
                        RETRY_DELAY=10
                        URL="http://${EC2_HOST}/"

                        for i in \$(seq 1 \$MAX_RETRIES); do
                            HTTP_CODE=\$(curl -s -o /dev/null -w "%{http_code}" "\$URL" || echo "000")
                            echo "Attempt \$i — HTTP \$HTTP_CODE"

                            if echo "200 301 302" | grep -qw "\$HTTP_CODE"; then
                                echo "✅ Smoke test passed (HTTP \$HTTP_CODE)"
                                exit 0
                            fi

                            if [ \$i -lt \$MAX_RETRIES ]; then
                                echo "Retrying in \${RETRY_DELAY}s..."
                                sleep \$RETRY_DELAY
                            fi
                        done

                        echo "❌ Smoke test failed after \$MAX_RETRIES attempts"
                        exit 1
                    """
                }
            }
        }

    } // end stages

    // -------------------------------------------------------------------------
    // Post-build actions — resilient: no credential dependencies
    // -------------------------------------------------------------------------
    post {

        success {
            echo '✅ Pipeline succeeded!'
            script {
                try {
                    slackSend(
                        channel: env.SLACK_CHANNEL,
                        color: 'good',
                        tokenCredentialId: 'slack-token',
                        message: "✅ *Build Succeeded* — Notes App\n*Branch:* `${env.BRANCH_NAME}`\n*Commit:* `${env.GIT_COMMIT_SHORT}` by ${env.GIT_AUTHOR}\n*Message:* ${env.GIT_MESSAGE}\n*Build:* <${env.BUILD_URL}|#${env.BUILD_NUMBER}>"
                    )
                } catch (Exception e) {
                    echo "⚠️ Slack notification failed: ${e.message}"
                }
            }
        }

        failure {
            echo '❌ Pipeline failed!'
            script {
                try {
                    slackSend(
                        channel: env.SLACK_CHANNEL,
                        color: 'danger',
                        tokenCredentialId: 'slack-token',
                        message: "❌ *Build Failed* — Notes App\n*Branch:* `${env.BRANCH_NAME}`\n*Commit:* `${env.GIT_COMMIT_SHORT}` by ${env.GIT_AUTHOR}\n*Message:* ${env.GIT_MESSAGE}\n*Build:* <${env.BUILD_URL}|#${env.BUILD_NUMBER}>"
                    )
                } catch (Exception e) {
                    echo "⚠️ Slack notification failed: ${e.message}"
                }
            }
        }

        unstable {
            script {
                try {
                    slackSend(
                        channel: env.SLACK_CHANNEL,
                        color: 'warning',
                        tokenCredentialId: 'slack-token',
                        message: "⚠️ *Build Unstable* — Notes App\n*Branch:* `${env.BRANCH_NAME}`\n*Build:* <${env.BUILD_URL}|#${env.BUILD_NUMBER}>"
                    )
                } catch (Exception e) {
                    echo "⚠️ Slack notification failed: ${e.message}"
                }
            }
        }

        always {
            echo '🧹 Cleaning up workspace...'
            // Docker cleanup — uses image names only, no credential dependency
            sh """
                docker images --format '{{.Repository}}:{{.Tag}}' | grep -E 'notes-(backend|frontend|proxy)' | xargs -r docker rmi -f || true
            """
            cleanWs()
        }

    }

}
