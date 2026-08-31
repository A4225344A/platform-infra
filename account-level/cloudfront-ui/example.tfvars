project_name = "platform"
aws_region   = "ap-northeast-1"

# Optional. Defaults to platform-engops-ui-<account-id>.
# ui_bucket_name = "platform-engops-ui-029099141993"

# Start without aliases to validate the CloudFront default domain first.
# Later, set aliases plus an ACM certificate issued in us-east-1.
cloudfront_aliases     = []
acm_certificate_arn    = ""
create_route53_records = false
route53_zone_id        = ""

# Optional. Leave empty until engops-api has a stable ALB/Gateway DNS origin.
engops_api_origin_domain_name     = ""
engops_api_origin_protocol_policy = "https-only"

upload_placeholder_index = true
