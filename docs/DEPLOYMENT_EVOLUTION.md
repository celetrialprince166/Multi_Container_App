# Deployment Evolution: From Manual EC2 to Blue/Green ECS

## Executive Summary

This documentation chronicles the architectural evolution of the Notes Application deployment pipeline—a journey from manual, error-prone EC2 deployments to a fully automated, zero-downtime blue/green deployment strategy on AWS ECS Fargate. This transformation represents industry best practices in modern DevOps, incorporating Infrastructure as Code (IaC), comprehensive security scanning, and sophisticated deployment orchestration.

![Secure CI/CD Pipeline – ECS + SAST/SCA](../images/gitops_labarch_diagram.png)

*High-level architecture of the secure CI/CD lab, showing Jenkins security gates, ECR, ECS Fargate, CodeDeploy blue/green, and CloudWatch monitoring.*

---

## Phase 1: The Starting Point — Manual EC2 Deployment

### The Challenge

Initially, the Notes Application was deployed on a single EC2 instance using Docker Compose. While functional for development, this approach presented several critical limitations:

- **Manual intervention required**: Every deployment required SSH access and manual command execution
- **No rollback capability**: Failed deployments meant manual recovery or instance rebuilds
- **Security exposure**: Direct EC2 access increased attack surface
- **Scalability constraints**: Vertical scaling only; no horizontal scaling capabilities
- **Downtime during deployments**: Application unavailable during updates

### Architecture Overview

![Manual EC2 Deployment Architecture](../images/manual_diagram.png)

### The Deployment Process (Pre-Automation)

```bash
# The manual deployment workflow:
ssh -i key.pem ubuntu@<ec2-ip>
cd /opt/notes-app
git pull origin main
docker-compose down
docker-compose up -d --build
# Pray nothing breaks
```

**Pain Points Identified:**
- No version control on infrastructure
- No automated testing before deployment
- No health checks or monitoring integration
- Secrets management through environment files
- Rollback process: "Restore from backup and hope"

---

## Phase 2: Foundation Building — Security-First CI/CD Pipeline

### The Transformation Begins

Before migrating to ECS, we established a robust CI/CD pipeline with comprehensive security scanning. This phase focused on implementing industry-standard DevSecOps practices.

### Security Scanning Integration

The Jenkins pipeline now includes seven critical security gates:

| Stage | Tool | Purpose | Gate Behavior |
|-------|------|---------|---------------|
| Secret Scanning | Gitleaks | Detect hardcoded credentials | Report only (lab mode) |
| Static Analysis | SonarCloud | Code quality & vulnerabilities | Report only (lab mode) |
| Dependency Audit | npm audit | Known vulnerabilities in dependencies | Report only (lab mode) |
| Image Scanning | Trivy | Container CVE detection | Report only (lab mode) |
| SBOM Generation | Syft | Software Bill of Materials | Archive artifacts |
| Cloud Security | Checkov | IaC security scanning | Report only (lab mode) |
| Dynamic Testing | OWASP ZAP | Runtime vulnerability detection | Report only (lab mode) |

### Pipeline Architecture

![Jenkins Build Architecture](../images/jenkins_pipeline.png)

*Figure 1: The comprehensive Jenkins pipeline architecture showing parallel security scanning stages and the progression from build to deployment.*

### Key Implementation Details

```groovy
// Example: Parallel security scanning in Jenkins
stage('Security Scanning') {
    parallel {
        stage('Secret Scan') {
            steps {
                sh '''
                    gitleaks detect --source . \
                      --report-format json \
                      --report-path gitleaks-report.json
                '''
            }
        }
        stage('Image Vulnerability Scan') {
            steps {
                sh '''
                    trivy image --severity HIGH,CRITICAL \
                      --exit-code 0 \
                      --format json \
                      --output trivy-report.json \
                      $ECR_REGISTRY/notes-backend:$IMAGE_TAG
                '''
            }
        }
        // Additional security stages...
    }
}
```

### Artifact Management

All security reports are archived for audit compliance:

![Build Archives](../images/buildachives.png)

*Figure 2: Jenkins build artifacts showing security reports, SBOMs, and deployment configurations stored for each build.*

---

## Phase 3: Migration to ECS Fargate

### Strategic Decision: Why ECS Fargate?

The migration from EC2 to ECS Fargate was driven by several strategic objectives:

1. **Serverless Container Management**: Eliminate instance management overhead
2. **Cost Optimization**: Pay per use, not per provisioned instance
3. **Security Posture**: Reduced attack surface with AWS-managed infrastructure
4. **Scalability**: Native auto-scaling capabilities
5. **High Availability**: Multi-AZ deployment with health checks

### Architecture Transformation

![ECS Fargate Architecture](../images/fargatearch.png)

### Infrastructure as Code Implementation

All ECS infrastructure is provisioned through Terraform:

```hcl
# terraform/ecs.tf
resource "aws_ecs_service" "notes_app" {
  name            = "${var.environment}-notes-app-service"
  cluster         = aws_ecs_cluster.notes_app.id
  task_definition = aws_ecs_task_definition.notes_app_bootstrap.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  deployment_controller {
    type = "ECS"  # Initial rolling deployment
  }

  network_configuration {
    subnets          = data.aws_subnets.default_vpc.ids
    security_groups  = [aws_security_group.ecs_tasks.id]
    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.notes_app.arn
    container_name   = "proxy"
    container_port   = 80
  }

  lifecycle {
    ignore_changes = [task_definition]  # Managed by CI/CD
  }
}
```

### ECS Resource Mapping

![ECS Resource Map](../images/awsco_alb_res_map.png)

*Figure 3: AWS Console resource map showing the complete ECS infrastructure topology—ALB, target groups, ECS service, and associated CloudWatch resources.*

---

## Phase 4: The Evolution — Blue/Green Deployment with CodeDeploy

### Why Blue/Green?

After achieving ECS migration success, the next evolution focused on deployment strategy. Rolling deployments, while better than manual, still presented risks:

- **Gradual exposure**: Traffic shifts incrementally, meaning some users hit new code before it's validated
- **Rollback complexity**: Reverting requires redeploying previous version
- **No pre-validation**: New version receives production traffic immediately
- **Session disruption**: Existing connections may be interrupted

### Blue/Green Deployment Strategy

Blue/green deployment provides:

- **Zero downtime**: New version (green) runs alongside stable version (blue)
- **Pre-shift validation**: Test traffic validates green before production cutover
- **Instant rollback**: Switch traffic back to blue if issues detected
- **Complete environment parity**: Full stack tested, not just containers

### Blue/Green Architecture

![Blue/Green Deployment Architecture](../images/codedeployarch.png)

### Implementation: Terraform Configuration

```hcl
# terraform/codedeploy.tf
resource "aws_codedeploy_deployment_group" "notes_app" {
  app_name              = aws_codedeploy_app.notes_app.name
  deployment_group_name = "${var.environment}-notes-app-dg"
  service_role_arn      = aws_iam_role.codedeploy_ecs.arn

  deployment_config_name = "CodeDeployDefault.ECSLinear10PercentEvery1Minutes"

  ecs_service {
    cluster_name = aws_ecs_cluster.notes_app.name
    service_name = aws_ecs_service.notes_app.name
  }

  auto_rollback_configuration {
    enabled = true
    events  = ["DEPLOYMENT_FAILURE", "DEPLOYMENT_STOP_ON_ALARM"]
  }

  alarm_configuration {
    enabled = true
    alarms  = [aws_cloudwatch_metric_alarm.alb_5xx.alarm_name]
  }

  blue_green_deployment_config {
    deployment_ready_option {
      action_on_timeout = "CONTINUE_DEPLOYMENT"
    }

    terminate_blue_instances_on_deployment_success {
      action                           = "TERMINATE"
      termination_wait_time_in_minutes = 5
    }
  }

  deployment_style {
    deployment_option = "WITH_TRAFFIC_CONTROL"
    deployment_type   = "BLUE_GREEN"
  }

  load_balancer_info {
    target_group_pair_info {
      prod_traffic_route {
        listener_arns = [aws_lb_listener.http.arn]
      }

      test_traffic_route {
        listener_arns = [aws_lb_listener.test.arn]
      }

      target_group {
        name = aws_lb_target_group.notes_app.name      # Blue
      }

      target_group {
        name = aws_lb_target_group.notes_app_green.name # Green
      }
    }
  }
}
```

### Jenkins Pipeline Integration

The deployment stage was completely restructured to use CodeDeploy:

```groovy
stage('Deploy to ECS Service') {
    steps {
        echo '🚀 Deploying to ECS via CodeDeploy (blue/green)...'
        withCredentials([
            string(credentialsId: 'aws-access-key-id', variable: 'AWS_ACCESS_KEY_ID'),
            string(credentialsId: 'aws-secret-access-key', variable: 'AWS_SECRET_ACCESS_KEY'),
            string(credentialsId: 'aws-region', variable: 'AWS_REGION'),
            string(credentialsId: 'codedeploy-app-name', variable: 'CODEDEPLOY_APP'),
            string(credentialsId: 'codedeploy-deployment-group', variable: 'CODEDEPLOY_DG')
        ]) {
            sh '''
                set -e

                . ecs/task-def-arn.env

                # Generate AppSpec from template
                sed "s|__TASK_DEF_ARN__|$TASK_DEF_ARN|g" \
                  ecs/appspec-template.yaml > ecs/appspec.yaml

                # Build deployment input JSON
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

                # Trigger blue/green deployment
                DEPLOYMENT_ID=$(aws deploy create-deployment \
                  --cli-input-json file://ecs/codedeploy-input.json \
                  --region "$AWS_REGION" \
                  --query 'deploymentId' \
                  --output text)

                echo "Deployment started: $DEPLOYMENT_ID"

                # Wait for deployment completion
                aws deploy wait deployment-successful \
                  --deployment-id "$DEPLOYMENT_ID" \
                  --region "$AWS_REGION"
            '''
        }
    }
}
```

### Blue/Green Resource Architecture

![Blue/Green Resource Map](../images/aswcon_res_map_bg.png)

*Figure 4: Complete blue/green deployment topology—ALB with production and test listeners, blue and green target groups, and the CodeDeploy deployment group orchestrating traffic shifting.*

### Deployment Flow Visualization

![Blue/Green Deployment Preview](../images/awscon_blue-green20pre.png)

*Figure 5: CodeDeploy deployment preview showing the blue (original) task set and green (replacement) task set during a deployment, with traffic distribution controls.*

### Successful Deployment State

![100% Traffic Shift](../images/awscon_bg100per.png)

*Figure 6: Deployment completion state showing 100% traffic successfully shifted to the green environment, with the blue task set marked for termination after the 5-minute wait period.*

---

## Monitoring and Observability

### CloudWatch Integration

The ECS deployment integrates with CloudWatch for comprehensive monitoring:

![CloudWatch Monitoring](../images/awscon_cloudwatch.png)

*Figure 7: CloudWatch dashboard showing ECS service metrics, ALB target group health, and the 5xx error alarm configured for automatic rollback triggers.*

### Key Metrics Tracked

| Metric | Source | Purpose |
|--------|--------|---------|
| HTTPCode_Target_5XX_Count | ALB Target Group | Auto-rollback trigger |
| CPUUtilization | ECS Service | Resource optimization |
| MemoryUtilization | ECS Service | Capacity planning |
| RunningTaskCount | ECS Service | Deployment progress |
| TargetResponseTime | ALB Target Group | Performance monitoring |

---

## Challenges and Solutions

### Challenge 1: Task Definition Synchronization

**Problem**: Terraform-managed ECS services conflicted with CI/CD task definition updates, causing state drift.

**Solution**: Implemented `lifecycle { ignore_changes = [task_definition] }` in the ECS service resource, allowing Jenkins to manage task definition revisions while Terraform manages the service infrastructure.

```hcl
resource "aws_ecs_service" "notes_app" {
  # ... other configuration ...
  
  lifecycle {
    ignore_changes = [task_definition]
  }
}
```

### Challenge 2: Inter-Container Communication in Fargate

**Problem**: Backend container couldn't connect to database using Docker Compose service names (`database:5432`).

**Solution**: Fargate uses `awsvpc` network mode, where all containers in a task share the same network namespace. Updated the backend to use `localhost:5432` for database connections within the same task.

```yaml
# In task definition
environment:
  - name: DB_HOST
    value: "localhost"  # Changed from "database"
```

### Challenge 3: AppSpec File Format for CodeDeploy

**Problem**: CodeDeploy rejected YAML AppSpec files when passed through CLI, expecting properly formatted JSON-wrapped content.

**Solution**: Used `jq` to construct a properly formatted deployment input JSON with raw YAML content embedded:

```bash
jq -n \
  --arg app "$CODEDEPLOY_APP" \
  --arg dg "$CODEDEPLOY_DG" \
  --rawfile spec ecs/appspec.yaml \
  '{
    applicationName: $app,
    deploymentGroupName: $dg,
    revision: {
      revisionType: "AppSpecContent",
      appSpecContent: { content: $spec }
    }
  }' > ecs/codedeploy-input.json
```

### Challenge 4: Blue/Green Configuration Constraints

**Problem**: CodeDeploy rejected deployment group configuration due to incompatible settings—specifically `action_on_timeout = "CONTINUE_DEPLOYMENT"` cannot coexist with `wait_time_in_minutes`.

**Solution**: Corrected the Terraform configuration by removing the timeout when using `CONTINUE_DEPLOYMENT`:

```hcl
blue_green_deployment_config {
  deployment_ready_option {
    action_on_timeout = "CONTINUE_DEPLOYMENT"
    # wait_time_in_minutes removed—cannot be specified with CONTINUE_DEPLOYMENT
  }
  
  terminate_blue_instances_on_deployment_success {
    action                           = "TERMINATE"
    termination_wait_time_in_minutes = 5
  }
}
```

---

## Security Hardening

### IAM Least Privilege

All IAM roles follow the principle of least privilege:

- **CodeDeploy Service Role**: Uses `AWSCodeDeployRoleForECS` managed policy
- **Jenkins IAM User**: Minimal permissions for ECR push, ECS task registration, and CodeDeploy deployment creation
- **ECS Task Execution Role**: ECR pull, CloudWatch Logs write only
- **ECS Task Role**: No permissions (application containers don't need AWS API access)

### Secrets Management

All sensitive data is managed through Jenkins credentials:

- Database credentials
- AWS access keys
- SonarCloud tokens
- ECR registry URLs

No secrets are committed to the repository.

---

## Lessons Learned

### Technical Insights

1. **Infrastructure as Code is non-negotiable**: Manual resource creation leads to drift and unreproducible environments. Terraform ensures consistency across environments.

2. **Security scanning must be integrated, not bolted on**: Running security tools after deployment is too late. Pipeline-integrated scanning catches issues before they reach production.

3. **Container orchestration changes networking paradigms**: Moving from Docker Compose to ECS Fargate required understanding `awsvpc` mode and localhost-based inter-container communication.

4. **Deployment strategies matter**: Rolling deployments are incrementally better than manual, but blue/green provides the confidence needed for production systems.

5. **CloudWatch alarms are deployment gates**: The 5xx alarm doesn't just monitor—it actively protects production by triggering automatic rollbacks.

### Process Insights

1. **Evolution over revolution**: Each phase built upon the previous, ensuring stability while progressing toward modern practices.

2. **Documentation as you go**: Capturing architectural decisions and troubleshooting steps prevented knowledge loss and accelerated future development.

3. **Visual evidence**: Screenshots of working infrastructure serve as both documentation and proof of implementation.

---

## Future Enhancements

- [ ] Implement GitOps workflow with ArgoCD for Kubernetes migration
- [ ] Add service mesh (Istio) for advanced traffic management
- [ ] Implement canary deployments with feature flags
- [ ] Add chaos engineering tests (AWS Fault Injection Simulator)
- [ ] Implement cross-region disaster recovery
- [ ] Add cost optimization policies (scheduled task scaling)

---

## Conclusion

This deployment evolution represents a complete transformation from manual, error-prone processes to automated, secure, and resilient infrastructure. The journey demonstrates:

- **Technical growth**: From EC2 to ECS Fargate to blue/green deployments
- **Security maturity**: Integrated DevSecOps practices throughout the pipeline
- **Operational excellence**: Zero-downtime deployments with automatic rollback
- **Industry alignment**: Modern cloud-native patterns and AWS best practices

The architecture now supports:
- **Scalability**: Auto-scaling ECS tasks based on demand
- **Reliability**: Multi-AZ deployment with health checks and automatic recovery
- **Security**: Defense in depth with scanning at every stage
- **Agility**: Full deployments in under 10 minutes with confidence

---

## References

- [Jenkinsfile](../Jenkinsfile) - Complete CI/CD pipeline configuration
- [terraform/](../terraform/) - Infrastructure as Code definitions
- [ecs/](../ecs/) - ECS task definitions and AppSpec templates
- [Main README](../README.md) - Project overview and setup instructions

---

## Author

**DevOps Implementation Journey**  
*From manual deployments to cloud-native automation*

- Repository: [docker_lab](https://github.com/yourusername/docker_lab)
- Documentation: This evolution story
- Status: Production-ready with blue/green deployment
