output "ui_bucket_name" {
  value = aws_s3_bucket.ui.bucket
}

output "cloudfront_distribution_id" {
  value = aws_cloudfront_distribution.ui.id
}

output "cloudfront_distribution_domain_name" {
  value = aws_cloudfront_distribution.ui.domain_name
}

output "cloudfront_distribution_arn" {
  value = aws_cloudfront_distribution.ui.arn
}

output "cloudfront_hosted_zone_id" {
  value = aws_cloudfront_distribution.ui.hosted_zone_id
}

output "cloudfront_aliases" {
  value = var.cloudfront_aliases
}

output "api_origin_enabled" {
  value = local.has_api_origin
}
