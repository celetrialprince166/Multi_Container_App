# =============================================================================
# ECR Repositories for Container Images
# =============================================================================
# Purpose: Store built Docker images for deployment
# =============================================================================

resource "aws_ecr_repository" "backend" {
  name                 = "notes-backend"
  image_tag_mutability = "MUTABLE"
  force_delete = true
  image_scanning_configuration {
    scan_on_push = true
  }

  tags = merge(
    local.common_tags,
    { Name = "notes-backend" }
  )
}

resource "aws_ecr_repository" "frontend" {
  name                 = "notes-frontend"
  image_tag_mutability = "MUTABLE"
  force_delete = true
  image_scanning_configuration {
    scan_on_push = true
  }

  tags = merge(
    local.common_tags,
    { Name = "notes-frontend" }
  )
}

resource "aws_ecr_repository" "proxy" {
  name                 = "notes-proxy"
  image_tag_mutability = "MUTABLE"
  force_delete = true
  image_scanning_configuration {
    scan_on_push = true
  }

  tags = merge(
    local.common_tags,
    { Name = "notes-proxy" }
  )
}
