resource "aws_ecr_repository" "service" {
  name                 = "${var.project_name}-service"
  image_tag_mutability = "IMMUTABLE"
  image_scanning_configuration { scan_on_push = true }
}
