resource "aws_security_group" "web" {
  name        = "${var.project_name}-web-sg"
  description = "HTTP/HTTPS; no SSH (SSM)"
  vpc_id      = aws_vpc.main.id
  tags = { Name = "${var.project_name}-web-sg" }
}
resource "aws_vpc_security_group_ingress_rule" "http" {
  security_group_id = aws_security_group.web.id
  from_port   = 80
  to_port     = 80
  ip_protocol = "tcp"
  cidr_ipv4   = var.allowed_web_cidrs[0]
}
resource "aws_vpc_security_group_ingress_rule" "https" {
  security_group_id = aws_security_group.web.id
  from_port   = 443
  to_port     = 443
  ip_protocol = "tcp"
  cidr_ipv4   = var.allowed_web_cidrs[0]
}
resource "aws_vpc_security_group_egress_rule" "all" {
  security_group_id = aws_security_group.web.id
  ip_protocol = "-1"
  cidr_ipv4   = "0.0.0.0/0"
}
