#!/usr/bin/env bash
set -euo pipefail

#
# Render ECS task definition from template by substituting image tags and ARNs.
# Usage:
#   ./ecs/render-task-def.sh \
#     --region eu-west-1 \
#     --ecr-registry 123456789012.dkr.ecr.eu-west-1.amazonaws.com \
#     --image-tag abc123 \
#     --execution-role-arn arn:aws:iam::123456789012:role/ecsTaskExecutionRole \
#     --task-role-arn arn:aws:iam::123456789012:role/ecsTaskRole \
#     --db-username dbadmin \
#     --db-password changeme \
#     --db-name notesdb \
#     --alb-dns-name my-notes-alb-123.eu-west-1.elb.amazonaws.com
#

TEMPLATE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE_FILE="${TEMPLATE_DIR}/task-definition-template.json"
OUTPUT_FILE="${TEMPLATE_DIR}/task-definition-rendered.json"

AWS_REGION=""
ECR_REGISTRY=""
IMAGE_TAG=""
EXECUTION_ROLE_ARN=""
TASK_ROLE_ARN=""
DB_USERNAME=""
DB_PASSWORD=""
DB_NAME=""
ALB_DNS_NAME=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --region)
      AWS_REGION="$2"; shift 2;;
    --ecr-registry)
      ECR_REGISTRY="$2"; shift 2;;
    --image-tag)
      IMAGE_TAG="$2"; shift 2;;
    --execution-role-arn)
      EXECUTION_ROLE_ARN="$2"; shift 2;;
    --task-role-arn)
      TASK_ROLE_ARN="$2"; shift 2;;
    --db-username)
      DB_USERNAME="$2"; shift 2;;
    --db-password)
      DB_PASSWORD="$2"; shift 2;;
    --db-name)
      DB_NAME="$2"; shift 2;;
    --alb-dns-name)
      ALB_DNS_NAME="$2"; shift 2;;
    *)
      echo "Unknown argument: $1" >&2
      exit 1;;
  esac
done

if [[ -z "$AWS_REGION" || -z "$ECR_REGISTRY" || -z "$IMAGE_TAG" || -z "$EXECUTION_ROLE_ARN" || -z "$TASK_ROLE_ARN" ]]; then
  echo "Missing required arguments." >&2
  exit 1
fi

BACKEND_IMAGE="${ECR_REGISTRY}/notes-backend:${IMAGE_TAG}"
FRONTEND_IMAGE="${ECR_REGISTRY}/notes-frontend:${IMAGE_TAG}"
PROXY_IMAGE="${ECR_REGISTRY}/notes-proxy:${IMAGE_TAG}"

NEXT_PUBLIC_API_URL="http://${ALB_DNS_NAME}/api"

sed \
  -e "s#__EXECUTION_ROLE_ARN__#${EXECUTION_ROLE_ARN}#g" \
  -e "s#__TASK_ROLE_ARN__#${TASK_ROLE_ARN}#g" \
  -e "s#__BACKEND_IMAGE__#${BACKEND_IMAGE}#g" \
  -e "s#__FRONTEND_IMAGE__#${FRONTEND_IMAGE}#g" \
  -e "s#__PROXY_IMAGE__#${PROXY_IMAGE}#g" \
  -e "s#__AWS_REGION__#${AWS_REGION}#g" \
  -e "s#__DB_USERNAME__#${DB_USERNAME}#g" \
  -e "s#__DB_PASSWORD__#${DB_PASSWORD}#g" \
  -e "s#__DB_NAME__#${DB_NAME}#g" \
  -e "s#__NEXT_PUBLIC_API_URL__#${NEXT_PUBLIC_API_URL}#g" \
  "${TEMPLATE_FILE}" > "${OUTPUT_FILE}"

echo "Rendered task definition written to ${OUTPUT_FILE}"

