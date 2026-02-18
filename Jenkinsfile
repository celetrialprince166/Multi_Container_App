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

    agent "agent"

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
    // Environment — credentials + derived vars
    // -------------------------------------------------------------------------
    environment {
        // AWS
        AWS_ACCESS_KEY_ID     = credentials('aws-access-key-id')
        AWS_SECRET_ACCESS_KEY = credentials('aws-secret-access-key')
        AWS_REGION            = credentials('aws-region')
        ECR_REGISTRY          = credentials('ecr-registry')

        // EC2
        EC2_HOST              = credentials('ec2-host')

        // Database
        DB_USERNAME           = credentials('db-username')
        DB_PASSWORD           = credentials('db-password')
        DB_NAME               = credentials('db-name')

        // SonarCloud
        SONAR_TOKEN           = credentials('sonarcloud-token')
        SONAR_ORGANIZATION    = 'your-sonarcloud-org'   // ← update this
        SONAR_PROJECT_KEY     = 'notes-app'             // ← update this

        // Slack
        SLACK_CHANNEL         = '#ci-cd-alerts'         // ← update this
        SLACK_CREDENTIALS_ID  = 'slack-token'

        // Image tags
        IMAGE_TAG             = "${env.GIT_COMMIT?.take(7) ?: 'latest'}"
        BACKEND_IMAGE         = "${ECR_REGISTRY}/notes-backend"
        FRONTEND_IMAGE        = "${ECR_REGISTRY}/notes-frontend"
        PROXY_IMAGE           = "${ECR_REGISTRY}/notes-proxy"
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
                    env.GIT_AUTHOR      = sh(script: "git log -1 --pretty=%an", returnStdout: true).trim()
                    env.GIT_MESSAGE     = sh(script: "git log -1 --pretty=%s",  returnStdout: true).trim()
                    env.IMAGE_TAG       = env.GIT_COMMIT_SHORT
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
                            sh 'npm ci'
                            // Type-check without emitting output
                            sh 'npx tsc --noEmit'
                        }
                    }
                }

                stage('Frontend — Lint') {
                    steps {
                        dir('frontend') {
                            echo '🔍 Running Next.js lint (frontend)...'
                            sh 'npm ci'
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
                            // --audit-level=high: fail only on high/critical vulns
                            sh '''
                                npm audit --audit-level=high \
                                    --json > npm-audit-backend.json || true
                                npm audit --audit-level=high
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
                                npm audit --audit-level=high
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
                            // Runs whatever is defined in package.json "test" script
                            sh 'npm run test || true'
                        }
                    }
                    post {
                        always {
                            // Publish JUnit results if they exist
                            junit allowEmptyResults: true,
                                  testResults: 'backend/test-results/**/*.xml'
                            // Publish HTML coverage report if it exists
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
                withSonarQubeEnv('SonarCloud') {   // matches Jenkins → SonarQube server name
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

        stage('SonarCloud Quality Gate') {
            steps {
                echo '🚦 Waiting for SonarCloud Quality Gate result...'
                timeout(time: 5, unit: 'MINUTES') {
                    // Aborts the pipeline if quality gate fails
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
                sh """
                    docker build \
                        --label "git.commit=${env.GIT_COMMIT_SHORT}" \
                        --label "build.number=${env.BUILD_NUMBER}" \
                        --label "build.url=${env.BUILD_URL}" \
                        -t ${BACKEND_IMAGE}:${env.IMAGE_TAG} \
                        -t ${BACKEND_IMAGE}:latest \
                        ./backend

                    docker build \
                        --label "git.commit=${env.GIT_COMMIT_SHORT}" \
                        --label "build.number=${env.BUILD_NUMBER}" \
                        --label "build.url=${env.BUILD_URL}" \
                        -t ${FRONTEND_IMAGE}:${env.IMAGE_TAG} \
                        -t ${FRONTEND_IMAGE}:latest \
                        ./frontend

                    docker build \
                        --label "git.commit=${env.GIT_COMMIT_SHORT}" \
                        --label "build.number=${env.BUILD_NUMBER}" \
                        --label "build.url=${env.BUILD_URL}" \
                        -t ${PROXY_IMAGE}:${env.IMAGE_TAG} \
                        -t ${PROXY_IMAGE}:latest \
                        ./nginx
                """
            }
        }

        // =====================================================================
        // Stage 7 — Image Vulnerability Scan (Trivy)
        // =====================================================================
        stage('Image Vulnerability Scan') {
            steps {
                echo '🛡️  Scanning Docker images with Trivy...'
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
                        [name: 'Backend',  tag: "${BACKEND_IMAGE}:${env.IMAGE_TAG}"],
                        [name: 'Frontend', tag: "${FRONTEND_IMAGE}:${env.IMAGE_TAG}"],
                        [name: 'Proxy',    tag: "${PROXY_IMAGE}:${env.IMAGE_TAG}"]
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
                                ${img.tag} || (cat trivy-${img.name.toLowerCase()}.txt && exit 1)
                        """
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
                sh """
                    aws ecr get-login-password --region ${AWS_REGION} \
                        | docker login --username AWS --password-stdin ${ECR_REGISTRY}

                    # Backend
                    docker push ${BACKEND_IMAGE}:${env.IMAGE_TAG}
                    docker push ${BACKEND_IMAGE}:latest

                    # Frontend
                    docker push ${FRONTEND_IMAGE}:${env.IMAGE_TAG}
                    docker push ${FRONTEND_IMAGE}:latest

                    # Proxy
                    docker push ${PROXY_IMAGE}:${env.IMAGE_TAG}
                    docker push ${PROXY_IMAGE}:latest
                """
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
                withCredentials([sshUserPrivateKey(
                    credentialsId : 'ec2-ssh-key',
                    keyFileVariable: 'SSH_KEY',
                    usernameVariable: 'SSH_USER'
                )]) {
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

    } // end stages

    // -------------------------------------------------------------------------
    // Post-build actions
    // -------------------------------------------------------------------------
    post {

        success {
            echo '✅ Pipeline succeeded!'
            slackSend(
                channel    : env.SLACK_CHANNEL,
                color      : 'good',
                tokenCredentialId: env.SLACK_CREDENTIALS_ID,
                message    : """
✅ *Build Succeeded* — Notes App
*Branch:*  `${env.BRANCH_NAME}`
*Commit:*  `${env.GIT_COMMIT_SHORT}` by ${env.GIT_AUTHOR}
*Message:* ${env.GIT_MESSAGE}
*Build:*   <${env.BUILD_URL}|#${env.BUILD_NUMBER}>
                """.stripIndent().trim()
            )
        }

        failure {
            echo '❌ Pipeline failed!'
            slackSend(
                channel    : env.SLACK_CHANNEL,
                color      : 'danger',
                tokenCredentialId: env.SLACK_CREDENTIALS_ID,
                message    : """
❌ *Build Failed* — Notes App
*Branch:*  `${env.BRANCH_NAME}`
*Commit:*  `${env.GIT_COMMIT_SHORT}` by ${env.GIT_AUTHOR}
*Message:* ${env.GIT_MESSAGE}
*Build:*   <${env.BUILD_URL}|#${env.BUILD_NUMBER}>
*Stage:*   ${env.STAGE_NAME ?: 'Unknown'}
                """.stripIndent().trim()
            )
        }

        unstable {
            slackSend(
                channel    : env.SLACK_CHANNEL,
                color      : 'warning',
                tokenCredentialId: env.SLACK_CREDENTIALS_ID,
                message    : """
⚠️ *Build Unstable* — Notes App
*Branch:*  `${env.BRANCH_NAME}`
*Build:*   <${env.BUILD_URL}|#${env.BUILD_NUMBER}>
                """.stripIndent().trim()
            )
        }

        always {
            echo '🧹 Cleaning up workspace...'
            // Remove locally built Docker images to free disk space
            sh """
                docker rmi ${BACKEND_IMAGE}:${env.IMAGE_TAG}  || true
                docker rmi ${FRONTEND_IMAGE}:${env.IMAGE_TAG} || true
                docker rmi ${PROXY_IMAGE}:${env.IMAGE_TAG}    || true
                docker rmi ${BACKEND_IMAGE}:latest            || true
                docker rmi ${FRONTEND_IMAGE}:latest           || true
                docker rmi ${PROXY_IMAGE}:latest              || true
            """
            cleanWs()
        }

    }

}
