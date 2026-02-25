 # =============================================================================
 # AWS Cloud Map Service Discovery for ECS
 # =============================================================================
 # Purpose:
 #   Provide a stable DNS name for the ECS backend tasks so Prometheus on the
 #   monitoring server can scrape /metrics without relying on static IPs.
 #   ECS Fargate tasks have dynamic IPs, so we use Cloud Map + DNS SD.
 # =============================================================================

 resource "aws_service_discovery_private_dns_namespace" "notes" {
   name = "notes.local"
   vpc  = data.aws_vpc.default.id

   tags = merge(
     local.common_tags,
     {
       Name = "${var.environment}-notes-namespace"
       Role = "service-discovery-namespace"
     }
   )
 }

 resource "aws_service_discovery_service" "notes_backend" {
   name = "${var.environment}-notes-backend"

   dns_config {
     namespace_id  = aws_service_discovery_private_dns_namespace.notes.id
     routing_policy = "MULTIVALUE"

     dns_records {
       ttl  = 10
       type = "A"
     }
   }

   health_check_custom_config {
     failure_threshold = 1
   }

   tags = merge(
     local.common_tags,
     {
       Name = "${var.environment}-notes-backend-sd"
       Role = "service-discovery-backend"
     }
   )
 }

