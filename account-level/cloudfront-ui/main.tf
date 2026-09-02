data "aws_caller_identity" "current" {}

data "aws_cloudfront_cache_policy" "caching_optimized" {
  name = "Managed-CachingOptimized"
}

data "aws_cloudfront_cache_policy" "caching_disabled" {
  name = "Managed-CachingDisabled"
}

data "aws_cloudfront_origin_request_policy" "all_viewer_except_host_header" {
  name = "Managed-AllViewerExceptHostHeader"
}

locals {
  ui_bucket_name         = var.ui_bucket_name != "" ? var.ui_bucket_name : "${var.project_name}-engops-ui-${data.aws_caller_identity.current.account_id}"
  has_aliases            = length(var.cloudfront_aliases) > 0
  has_api_origin         = var.engops_api_origin_domain_name != ""
  create_dns_records     = var.create_route53_records && local.has_aliases
  s3_origin_id           = "s3-ui"
  engops_api_origin_id   = "engops-api"
  placeholder_index_html = <<-HTML
    <!doctype html>
    <html lang="en">
      <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width,initial-scale=1">
        <title>EngOps UI</title>
      </head>
      <body>
        <main>
          <h1>EngOps UI origin is ready</h1>
          <p>Task 11.5 provisioned S3, CloudFront, and OAC.</p>
        </main>
      </body>
    </html>
  HTML
}

resource "aws_s3_bucket" "ui" {
  bucket = local.ui_bucket_name
}

resource "aws_s3_bucket_public_access_block" "ui" {
  bucket = aws_s3_bucket.ui.id

  block_public_acls       = true
  ignore_public_acls      = true
  block_public_policy     = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "ui" {
  bucket = aws_s3_bucket.ui.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_versioning" "ui" {
  bucket = aws_s3_bucket.ui.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "ui" {
  bucket = aws_s3_bucket.ui.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_object" "placeholder_index" {
  count = var.upload_placeholder_index ? 1 : 0

  bucket       = aws_s3_bucket.ui.id
  key          = "index.html"
  content_type = "text/html; charset=utf-8"
  content      = local.placeholder_index_html
  etag         = md5(local.placeholder_index_html)

  depends_on = [
    aws_s3_bucket_ownership_controls.ui,
    aws_s3_bucket_public_access_block.ui
  ]
}

resource "aws_cloudfront_origin_access_control" "ui" {
  name                              = "${var.project_name}-ui-oac"
  description                       = "Allow CloudFront to read ${local.ui_bucket_name}"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_cloudfront_function" "spa_rewrite" {
  name    = "${var.project_name}-engops-ui-spa-rewrite"
  runtime = "cloudfront-js-2.0"
  comment = "Rewrite EngOps UI deep links to index.html without masking API errors."
  publish = true
  code    = <<-JS
    function handler(event) {
      var request = event.request;
      var uri = request.uri;

      if (uri === "/api" || uri.indexOf("/api/") === 0) {
        return request;
      }

      var lastSegment = uri.split("/").pop();
      if (uri === "/" || lastSegment.indexOf(".") === -1) {
        request.uri = "/index.html";
      }

      return request;
    }
  JS
}

resource "aws_cloudfront_distribution" "ui" {
  enabled             = true
  is_ipv6_enabled     = true
  comment             = "${var.project_name} EngOps UI"
  default_root_object = "index.html"
  aliases             = var.cloudfront_aliases
  price_class         = "PriceClass_100"

  origin {
    domain_name              = aws_s3_bucket.ui.bucket_regional_domain_name
    origin_id                = local.s3_origin_id
    origin_access_control_id = aws_cloudfront_origin_access_control.ui.id

    s3_origin_config {
      origin_access_identity = ""
    }
  }

  dynamic "origin" {
    for_each = local.has_api_origin ? [1] : []

    content {
      domain_name = var.engops_api_origin_domain_name
      origin_id   = local.engops_api_origin_id

      custom_origin_config {
        http_port              = 80
        https_port             = 443
        origin_protocol_policy = var.engops_api_origin_protocol_policy
        origin_ssl_protocols   = ["TLSv1.2"]
      }

      custom_header {
        name  = var.engops_api_origin_verify_header_name
        value = var.engops_api_origin_verify_header_value
      }
    }
  }

  default_cache_behavior {
    target_origin_id       = local.s3_origin_id
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD", "OPTIONS"]
    cached_methods         = ["GET", "HEAD"]
    cache_policy_id        = data.aws_cloudfront_cache_policy.caching_optimized.id
    compress               = true

    function_association {
      event_type   = "viewer-request"
      function_arn = aws_cloudfront_function.spa_rewrite.arn
    }
  }

  dynamic "ordered_cache_behavior" {
    for_each = local.has_api_origin ? [1] : []

    content {
      path_pattern             = "/api/*"
      target_origin_id         = local.engops_api_origin_id
      viewer_protocol_policy   = "https-only"
      allowed_methods          = ["GET", "HEAD", "OPTIONS"]
      cached_methods           = ["GET", "HEAD", "OPTIONS"]
      cache_policy_id          = data.aws_cloudfront_cache_policy.caching_disabled.id
      origin_request_policy_id = data.aws_cloudfront_origin_request_policy.all_viewer_except_host_header.id
      compress                 = true
    }
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = !local.has_aliases
    acm_certificate_arn            = local.has_aliases ? var.acm_certificate_arn : null
    ssl_support_method             = local.has_aliases ? "sni-only" : null
    minimum_protocol_version       = local.has_aliases ? "TLSv1.2_2021" : null
  }

  lifecycle {
    precondition {
      condition     = !local.has_aliases || var.acm_certificate_arn != ""
      error_message = "acm_certificate_arn is required when cloudfront_aliases is not empty. CloudFront aliases require an ACM certificate in us-east-1."
    }

    precondition {
      condition     = !var.create_route53_records || (local.has_aliases && var.route53_zone_id != "")
      error_message = "route53_zone_id and cloudfront_aliases are required when create_route53_records is true."
    }

    precondition {
      condition     = !local.has_api_origin || var.engops_api_origin_verify_header_value != ""
      error_message = "engops_api_origin_verify_header_value is required when engops_api_origin_domain_name is set."
    }
  }
}

data "aws_iam_policy_document" "ui_bucket" {
  statement {
    sid     = "AllowCloudFrontServicePrincipalReadOnly"
    effect  = "Allow"
    actions = ["s3:GetObject"]

    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }

    resources = ["${aws_s3_bucket.ui.arn}/*"]

    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = [aws_cloudfront_distribution.ui.arn]
    }
  }
}

resource "aws_s3_bucket_policy" "ui" {
  bucket = aws_s3_bucket.ui.id
  policy = data.aws_iam_policy_document.ui_bucket.json
}

resource "aws_route53_record" "ui_a" {
  for_each = local.create_dns_records ? toset(var.cloudfront_aliases) : toset([])

  zone_id = var.route53_zone_id
  name    = each.value
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.ui.domain_name
    zone_id                = aws_cloudfront_distribution.ui.hosted_zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "ui_aaaa" {
  for_each = local.create_dns_records ? toset(var.cloudfront_aliases) : toset([])

  zone_id = var.route53_zone_id
  name    = each.value
  type    = "AAAA"

  alias {
    name                   = aws_cloudfront_distribution.ui.domain_name
    zone_id                = aws_cloudfront_distribution.ui.hosted_zone_id
    evaluate_target_health = false
  }
}
