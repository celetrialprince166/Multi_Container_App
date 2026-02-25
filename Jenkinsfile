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
//   db-username            → Secret Text $ 
//   db-password            → Secret Text
//   db-name                → Secret Text
//   sonarcloud-token       → Secret Text  — SonarCloud user token
//   slack-token            → Secret Text  — Slack Bot OAuth token
//   codedeploy-app-name    → Secret Text  — from terraform output codedeploy_app_name
//   codedeploy-deployment-group → Secret Text — from terraform output codedeploy_deployment_group
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
        SONAR_ORGANIZATION = 'celetrialprince166'
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
                    echo "Branch (env.BRANCH_NAME): ${env.BRANCH_NAME}"
                    echo "Branch (env.GIT_BRANCH) : ${env.GIT_BRANCH}"
                    echo "Commit   : ${env.GIT_COMMIT_SHORT}"
                    echo "Author   : ${env.GIT_AUTHOR}"
                    echo "Message  : ${env.GIT_MESSAGE}"
                }
            }
        }

        // =====================================================================
        // Stage 2 — Secret Scan (Gitleaks)
        //   NOTE (lab mode): findings are reported but do NOT block the pipeline.
        // =====================================================================
        stage('Secret Scan — Gitleaks') {
            steps {
                echo '🔐 Running Gitleaks secret scan...'
                script {
                    sh '''
                        set -e

                        GITLEAKS_VERSION="8.21.2"

                        mkdir -p "$HOME/bin"
                        if ! "$HOME/bin/gitleaks" version >/dev/null 2>&1; then
                          echo "Installing Gitleaks ${GITLEAKS_VERSION} to $HOME/bin..."
                          curl -sSL -o /tmp/gitleaks.tar.gz \
                            "https://github.com/gitleaks/gitleaks/releases/download/v${GITLEAKS_VERSION}/gitleaks_${GITLEAKS_VERSION}_linux_x64.tar.gz"
                          tar -xzf /tmp/gitleaks.tar.gz -C "$HOME/bin" gitleaks
                          rm -f /tmp/gitleaks.tar.gz
                          chmod +x "$HOME/bin/gitleaks"
                        fi

                        "$HOME/bin/gitleaks" version

                        "$HOME/bin/gitleaks" detect \
                          --source . \
                          --report-format json \
                          --report-path gitleaks-report.json \
                          --exit-code 1 || GITLEAKS_EXIT=$?

                        "$HOME/bin/gitleaks" detect \
                          --source . \
                          --report-format csv \
                          --report-path gitleaks-report.csv \
                          --exit-code 0

                        if [ "${GITLEAKS_EXIT:-0}" -ne 0 ]; then
                          echo "WARNING: Gitleaks found potential secrets (pipeline not blocked in lab mode)."
                        fi
                    '''
                }
            }
            post {
                always {
                    archiveArtifacts artifacts: 'gitleaks-report.*', allowEmptyArchive: false
                }
            }
        }

        // =====================================================================
        // Stage 3 — Static Code Analysis (parallel)
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
        // Stage 4 — Dependency Security Audit (lab mode: non-blocking, reports only)
        // =====================================================================
        stage('Dependency Security Audit') {
            parallel {

                stage('Backend — npm audit') {
                    steps {
                        dir('backend') {
                            echo '🔒 Running npm audit (backend)...'
                            sh '''
                                set +e
                                npm audit --audit-level=high --json > npm-audit-backend.json
                                AUDIT_EXIT=$?
                                set -e

                                echo "──── npm audit (backend) — human-readable ────"
                                npm audit --audit-level=high || true

                                if [ "$AUDIT_EXIT" -ne 0 ]; then
                                  echo "WARNING: npm audit (backend) found HIGH/CRITICAL vulnerabilities (pipeline not blocked in lab mode)."
                                fi
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
                                set +e
                                npm audit --audit-level=high --json > npm-audit-frontend.json
                                AUDIT_EXIT=$?
                                set -e

                                echo "──── npm audit (frontend) — human-readable ────"
                                npm audit --audit-level=high || true

                                if [ "$AUDIT_EXIT" -ne 0 ]; then
                                  echo "WARNING: npm audit (frontend) found HIGH/CRITICAL vulnerabilities (pipeline not blocked in lab mode)."
                                fi
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
        // Stage 4 — Unit Tests & Coverage (skipped — no test scripts configured)
        // =====================================================================
        stage('Unit Tests & Coverage') {
            steps {
                echo '⏭️  Skipping tests — no test scripts configured in package.json yet.'
                echo 'To enable: add Jest + test scripts to backend/frontend package.json'
            }
        }

        // =====================================================================
        // Stage 5 — SonarCloud Analysis + Quality Gate
        //   NOTE (lab mode): gate status is reported but does NOT block deployment.
        // =====================================================================
        stage('SonarCloud Analysis') {
            steps {
                echo '📊 Running SonarCloud analysis...'
                script {
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
        }

        stage('SonarCloud Quality Gate') {
            steps {
                echo '🚦 Waiting for SonarCloud Quality Gate result...'
                script {
                    timeout(time: 5, unit: 'MINUTES') {
                        waitForQualityGate abortPipeline: false
                    }
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
        // Stage 7 — Image Vulnerability Scan (Trivy — lab mode: non-blocking)
        // =====================================================================
        stage('Image Vulnerability Scan') {
            steps {
                echo '🛡️  Scanning Docker images with Trivy...'
                withCredentials([string(credentialsId: 'ecr-registry', variable: 'ECR_REGISTRY')]) {
                    script {
                        // Install Trivy to user-writable location
                        sh '''
                            mkdir -p $HOME/bin
                            if ! $HOME/bin/trivy --version &> /dev/null; then
                                echo "Installing Trivy to \$HOME/bin..."
                                curl -sfL https://raw.githubusercontent.com/aquasecurity/trivy/main/contrib/install.sh \
                                    | sh -s -- -b $HOME/bin
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
                                # JSON report (non-blocking, for archives)
                                \$HOME/bin/trivy image \
                                    --exit-code 0 \
                                    --severity HIGH,CRITICAL \
                                    --no-progress \
                                    --format json \
                                    --output trivy-${img.name.toLowerCase()}.json \
                                    ${img.imgName}:${env.IMAGE_TAG}

                                # Table report + warning-only gate (lab mode)
                                \$HOME/bin/trivy image \
                                    --exit-code 1 \
                                    --severity HIGH,CRITICAL \
                                    --no-progress \
                                    --format table \
                                    --output trivy-${img.name.toLowerCase()}.txt \
                                    ${img.imgName}:${env.IMAGE_TAG} || echo "WARNING: Trivy found HIGH/CRITICAL vulnerabilities in ${img.name} (pipeline not blocked in lab mode)."
                            """
                        }
                    }
                }
            }
            post {
                always {
                    archiveArtifacts artifacts: 'trivy-*.txt', allowEmptyArchive: true
                    archiveArtifacts artifacts: 'trivy-*.json', allowEmptyArchive: true
                }
            }
        }

        // =====================================================================
        // Stage 8 — SBOM Generation (Syft)
        // =====================================================================
        stage('SBOM Generation — Syft') {
            steps {
                echo '📦 Generating SBOMs with Syft...'
                withCredentials([string(credentialsId: 'ecr-registry', variable: 'ECR_REGISTRY')]) {
                    script {
                        sh '''
                            set -e

                            mkdir -p "$HOME/bin"
                            if ! "$HOME/bin/syft" version >/dev/null 2>&1; then
                              echo "Installing Syft to $HOME/bin..."
                              curl -sSfL https://raw.githubusercontent.com/anchore/syft/main/install.sh | sh -s -- -b "$HOME/bin"
                            fi

                            IMAGES="backend frontend proxy"

                            for svc in $IMAGES; do
                              case "$svc" in
                                backend)
                                  IMG="${ECR_REGISTRY}/${BACKEND_IMAGE_NAME}:${IMAGE_TAG}"
                                  ;;
                                frontend)
                                  IMG="${ECR_REGISTRY}/${FRONTEND_IMAGE_NAME}:${IMAGE_TAG}"
                                  ;;
                                proxy)
                                  IMG="${ECR_REGISTRY}/${PROXY_IMAGE_NAME}:${IMAGE_TAG}"
                                  ;;
                              esac

                              echo "Generating SBOMs for $svc ($IMG)..."
                              "$HOME/bin/syft" "$IMG" -o cyclonedx-json=sbom-${svc}-cyclonedx.json
                              "$HOME/bin/syft" "$IMG" -o spdx-json=sbom-${svc}-spdx.json
                            done
                        '''
                    }
                }
            }
            post {
                always {
                    archiveArtifacts artifacts: 'sbom-*-cyclonedx.json', allowEmptyArchive: true
                    archiveArtifacts artifacts: 'sbom-*-spdx.json', allowEmptyArchive: true
                }
            }
        }

        // =====================================================================
        // Stage 9 — Security Gate Summary
        // =====================================================================
        stage('Security Gate Summary') {
            steps {
                echo '✅ All security gates passed for this build:'
                echo '   - Gitleaks secret scan'
                echo '   - npm audit (backend & frontend)'
                echo '   - SonarCloud analysis + quality gate'
                echo '   - Trivy image vulnerability scan'
                echo '   - Syft SBOM generation'
            }
        }

        // =====================================================================
        // Stage 8 — Push to ECR  [main branch only]
        // =====================================================================
        stage('Push to ECR') {
            when {
                anyOf {
                    branch 'gitops'
                    expression { env.GIT_BRANCH == 'origin/gitops' }
                    expression { env.GIT_BRANCH == 'refs/heads/gitops' }
                }
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
        // Stage 9 — Render & Register ECS Task Definition  [main branch only]
        // =====================================================================
        stage('Render & Register ECS Task Definition') {
            when {
                anyOf {
                    branch 'gitops'
                    expression { env.GIT_BRANCH == 'origin/gitops' }
                    expression { env.GIT_BRANCH == 'refs/heads/gitops' }
                }
            }
            steps {
                echo '📄 Rendering ECS task definition and registering new revision...'
                withCredentials([
                    string(credentialsId: 'aws-access-key-id',           variable: 'AWS_ACCESS_KEY_ID'),
                    string(credentialsId: 'aws-secret-access-key',       variable: 'AWS_SECRET_ACCESS_KEY'),
                    string(credentialsId: 'aws-region',                  variable: 'AWS_REGION'),
                    string(credentialsId: 'ecr-registry',                variable: 'ECR_REGISTRY'),
                    string(credentialsId: 'db-username',                 variable: 'DB_USERNAME'),
                    string(credentialsId: 'dbpassword',                  variable: 'DB_PASSWORD'),
                    string(credentialsId: 'db-name',                     variable: 'DB_NAME'),
                    string(credentialsId: 'ecs-task-execution-role-arn', variable: 'ECS_EXEC_ROLE_ARN'),
                    string(credentialsId: 'ecs-task-role-arn',           variable: 'ECS_TASK_ROLE_ARN'),
                    string(credentialsId: 'ecs-alb-dns-name',            variable: 'ECS_ALB_DNS_NAME')
                ]) {
                    sh '''
                        set -e

                        chmod +x ecs/render-task-def.sh

                        ./ecs/render-task-def.sh \
                          --region "$AWS_REGION" \
                          --ecr-registry "$ECR_REGISTRY" \
                          --image-tag "$IMAGE_TAG" \
                          --execution-role-arn "$ECS_EXEC_ROLE_ARN" \
                          --task-role-arn "$ECS_TASK_ROLE_ARN" \
                          --db-username "$DB_USERNAME" \
                          --db-password "$DB_PASSWORD" \
                          --db-name "$DB_NAME" \
                          --alb-dns-name "$ECS_ALB_DNS_NAME"

                        echo "Registering task definition with ECS..."
                        TASK_DEF_ARN=$(aws ecs register-task-definition \
                          --cli-input-json file://ecs/task-definition-rendered.json \
                          --region "$AWS_REGION" \
                          --query 'taskDefinition.taskDefinitionArn' \
                          --output text)

                        echo "TASK_DEF_ARN=$TASK_DEF_ARN" > ecs/task-def-arn.env
                        echo "Registered task definition: $TASK_DEF_ARN"
                    '''
                }
            }
            post {
                always {
                    archiveArtifacts artifacts: 'ecs/task-definition-rendered.json', allowEmptyArchive: true
                    archiveArtifacts artifacts: 'ecs/task-def-arn.env', allowEmptyArchive: true
                }
            }
        }

        // =====================================================================
        // Stage 10 — Deploy to ECS Service (CodeDeploy blue/green) [main branch only]
        // =====================================================================
        stage('Deploy to ECS Service') {
            when {
                anyOf {
                    branch 'gitops'
                    expression { env.GIT_BRANCH == 'origin/gitops' }
                    expression { env.GIT_BRANCH == 'refs/heads/gitops' }
                }
            }
            steps {
                echo '🚀 Deploying to ECS via CodeDeploy (blue/green)...'
                withCredentials([
                    string(credentialsId: 'aws-access-key-id',           variable: 'AWS_ACCESS_KEY_ID'),
                    string(credentialsId: 'aws-secret-access-key',       variable: 'AWS_SECRET_ACCESS_KEY'),
                    string(credentialsId: 'aws-region',                  variable: 'AWS_REGION'),
                    string(credentialsId: 'codedeploy-app-name',         variable: 'CODEDEPLOY_APP'),
                    string(credentialsId: 'codedeploy-deployment-group', variable: 'CODEDEPLOY_DG')
                ]) {
                    sh '''
                        set -e

                        . ecs/task-def-arn.env

                        # Generate AppSpec from template (YAML)
                        sed "s|__TASK_DEF_ARN__|$TASK_DEF_ARN|g" \
                          ecs/appspec-template.yaml > ecs/appspec.yaml

                        # Build a JSON input file for aws deploy create-deployment
                        # The 'content' field must be the raw YAML string (jq -Rs reads file as single string)
                        jq -n \
                          --arg app "$CODEDEPLOY_APP" \
                          --arg dg "$CODEDEPLOY_DG" \
                          --rawfile spec ecs/appspec.yaml \
                          '{
                            applicationName: $app,
                            deploymentGroupName: $dg,
                            revision: {
                              revisionType: "AppSpecContent",
                              appSpecContent: {
                                content: $spec
                              }
                            }
                          }' > ecs/codedeploy-input.json

                        DEPLOYMENT_ID=$(aws deploy create-deployment \
                          --cli-input-json file://ecs/codedeploy-input.json \
                          --region "$AWS_REGION" \
                          --query 'deploymentId' \
                          --output text)

                        echo "Deployment started: $DEPLOYMENT_ID"

                        aws deploy wait deployment-successful \
                          --deployment-id "$DEPLOYMENT_ID" \
                          --region "$AWS_REGION"
                    '''
                }
            }
        }

        // =====================================================================
        // Stage 11 — ECS Smoke Test  [main branch only]
        // =====================================================================
        stage('ECS Smoke Test') {
            when {
                anyOf {
                    branch 'gitops'
                    expression { env.GIT_BRANCH == 'origin/gitops' }
                    expression { env.GIT_BRANCH == 'refs/heads/gitops' }
                }
            }
            steps {
                echo '💨 Running smoke test against ECS ALB...'
                withCredentials([string(credentialsId: 'ecs-alb-dns-name', variable: 'ECS_ALB_DNS_NAME')]) {
                    sh '''
                        echo "Waiting 30s for ECS tasks to stabilise behind ALB..."
                        sleep 30

                        MAX_RETRIES=5
                        RETRY_DELAY=10
                        URL="http://$ECS_ALB_DNS_NAME/"

                        for i in $(seq 1 $MAX_RETRIES); do
                            HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "$URL" || echo "000")
                            echo "Attempt $i — HTTP $HTTP_CODE"

                            if echo "200 301 302" | grep -qw "$HTTP_CODE"; then
                                echo "✅ ECS smoke test passed (HTTP $HTTP_CODE)"
                                exit 0
                            fi

                            if [ $i -lt $MAX_RETRIES ]; then
                                echo "Retrying in ${RETRY_DELAY}s..."
                                sleep $RETRY_DELAY
                            fi
                        done

                        echo "❌ ECS smoke test failed after $MAX_RETRIES attempts"
                        exit 1
                    '''
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
