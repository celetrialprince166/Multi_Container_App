# =============================================================================
# GuardDuty — Intelligent Threat Detection
# =============================================================================
# Purpose: Continuously analyse CloudTrail, VPC Flow Logs, and DNS logs using
#          AWS threat intelligence and ML to detect malicious activity.
#
# What GuardDuty detects (examples):
#   - Cryptocurrency mining on EC2 instances
#   - Unusual API calls from Tor exit nodes
#   - Port scanning from/to your instances
#   - Compromised IAM credentials being used from unusual locations
#   - Anomalous S3 data access (exfiltration attempts)
#   - Malware on EBS volumes (with malware protection enabled)
#
# Cost: ~$1–3/month for a small account in a lab environment.
# Free trial: 30 days free when first enabled.
#
# Note: GuardDuty is PASSIVE — it only detects and alerts, it does NOT block.
# For automated remediation, you would add EventBridge rules + Lambda.
# =============================================================================

resource "aws_guardduty_detector" "main" {
  enable = true

  # How frequently GuardDuty publishes updated findings
  # FIFTEEN_MINUTES is the most responsive option (default is SIX_HOURS)
  finding_publishing_frequency = "FIFTEEN_MINUTES"

  datasources {
    # S3 protection: detect anomalous access to S3 buckets
    # (e.g., someone exfiltrating data from the CloudTrail bucket)
    s3_logs {
      enable = true
    }

    # Kubernetes audit logs — disabled (we're not using EKS)
    kubernetes {
      audit_logs {
        enable = false
      }
    }

    # Malware protection: scan EBS volumes of flagged EC2 instances
    # Triggers when GuardDuty detects suspicious process behaviour
    malware_protection {
      scan_ec2_instance_with_findings {
        ebs_volumes {
          enable = true
        }
      }
    }
  }

  tags = merge(
    local.common_tags,
    {
      Name    = "notes-app-guardduty"
      Purpose = "Threat detection"
    }
  )
}
