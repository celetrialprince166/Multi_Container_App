# =============================================================================
# EC2 Instance Configuration
# =============================================================================
# Purpose: Define EC2 instance for hosting the Notes application
# =============================================================================

resource "aws_instance" "notes_app" {
  ami           = data.aws_ami.ubuntu.id
  instance_type = var.instance_type

  # Network configuration
  vpc_security_group_ids = [aws_security_group.notes_app.id]
  iam_instance_profile   = aws_iam_instance_profile.ec2_profile.name

  # SSH key (Terraform-generated via TLS provider)
  key_name = aws_key_pair.notes_app.key_name

  # Root volume configuration
  root_block_device {
    volume_type           = var.root_volume_type
    volume_size           = var.root_volume_size
    delete_on_termination = true
    encrypted             = true

    tags = merge(
      local.common_tags,
      {
        Name = "${var.environment}-notes-app-root-volume"
      }
    )
  }

  # User data script (runs on first boot)
  user_data = templatefile("${path.module}/user_data.sh", {
    app_directory = var.app_directory
    environment   = var.environment
    git_repo_url  = var.git_repo_url
  })

  # Enable detailed monitoring (optional)
  monitoring = var.enable_monitoring

  # Metadata options (IMDSv2)
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required" # Require IMDSv2
    http_put_response_hop_limit = 1
    instance_metadata_tags      = "enabled"
  }

  # Tags
  tags = merge(
    local.common_tags,
    {
      Name = "${var.environment}-notes-app-server"
    }
  )

  # Lifecycle
  lifecycle {
    ignore_changes = [
      ami, # Don't recreate instance when AMI updates
      user_data,
      # user_data intentionally NOT ignored here — removing it from ignore_changes
      # forces Terraform to replace the instance when user_data.sh changes.
      # After the replacement is confirmed working, add user_data back to
      # ignore_changes to prevent accidental future replacements.
    ]
  }

  # Wait for instance to be ready
  depends_on = [
    aws_iam_instance_profile.ec2_profile,
    aws_security_group.notes_app,
    aws_key_pair.notes_app
  ]
}

