# =============================================================================
# EC2 Key Pair (TLS Provider)
# =============================================================================
# Generates key pair with Terraform - private key stored in state (sensitive)
# Output private key for GitHub Secrets: terraform output -raw ec2_private_key
# =============================================================================

resource "tls_private_key" "notes_app" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "notes_app" {
  key_name_prefix = "${var.environment}-notes-app-"
  public_key      = tls_private_key.notes_app.public_key_openssh

  tags = merge(
    local.common_tags,
    { Name = "${var.environment}-notes-app-key" }
  )
}
