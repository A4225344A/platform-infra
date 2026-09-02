variable "aws_region" {
  type    = string
  default = "ap-northeast-1"
}

variable "project_name" {
  type    = string
  default = "platform"
}

variable "ui_bucket_name" {
  type        = string
  default     = ""
  description = "Optional S3 bucket name for UI static assets. Defaults to <project>-engops-ui-<account-id>."
}

variable "cloudfront_aliases" {
  type        = list(string)
  default     = []
  description = "Optional custom domains, such as engops.example.com. Leave empty to use the CloudFront domain."
}

variable "route53_zone_id" {
  type        = string
  default     = ""
  description = "Optional Route53 hosted zone ID. Required only when creating alias records."
}

variable "acm_certificate_arn" {
  type        = string
  default     = ""
  description = "ACM certificate ARN in us-east-1. Required when cloudfront_aliases is not empty."
}

variable "engops_api_origin_domain_name" {
  type        = string
  default     = ""
  description = "Optional ALB/Gateway DNS name for /api/* routing. Leave empty until engops-api has a stable origin."
}

variable "engops_api_origin_protocol_policy" {
  type        = string
  default     = "https-only"
  description = "CloudFront protocol policy for the engops-api custom origin."

  validation {
    condition     = contains(["http-only", "https-only", "match-viewer"], var.engops_api_origin_protocol_policy)
    error_message = "engops_api_origin_protocol_policy must be one of: http-only, https-only, match-viewer."
  }
}

variable "engops_api_origin_verify_header_name" {
  type        = string
  default     = "X-EngOps-Origin-Verify"
  description = "Custom header CloudFront adds when forwarding /api/* requests to the EngOps API origin."
}

variable "engops_api_origin_verify_header_value" {
  type        = string
  default     = ""
  sensitive   = true
  description = "Secret custom header value CloudFront adds when forwarding /api/* requests. Required when engops_api_origin_domain_name is set."
}

variable "create_route53_records" {
  type        = bool
  default     = false
  description = "Create A/AAAA alias records for cloudfront_aliases in route53_zone_id."
}

variable "upload_placeholder_index" {
  type        = bool
  default     = true
  description = "Upload a minimal index.html so CloudFront/OAC can be verified before the real UI is deployed."
}
