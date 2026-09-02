# Task 11.5 CloudFront UI Entry

This is an account-level Terraform stack for:

- S3 UI static asset bucket
- CloudFront Origin Access Control
- CloudFront distribution
- Optional `/api/*` routing to an `engops-api` ALB/Gateway origin
- Optional Route53 A/AAAA alias records

It is intentionally separate from the root `platform-infra` daily stack. Do not add this directory to the daily apply/destroy workflow.

## First Apply

```bash
cd ~/platform-infra/account-level/cloudfront-ui
cp example.tfvars terraform.tfvars
terraform init
terraform plan
terraform apply
```

The default `example.tfvars` creates a CloudFront distribution with only the S3 UI origin and the CloudFront default certificate. This is enough to validate S3 + OAC before the real UI pipeline exists.

## GitHub Actions

Use the dedicated workflow instead of the root daily Terraform workflow:

```text
CloudFront UI Terraform
```

Recommended first run:

```text
cloudfront_aliases_json: []
create_route53_records: false
engops_api_origin_domain_name: leave empty
upload_placeholder_index: true
```

The workflow always runs `plan` first. After the plan job succeeds, the `apply`
job waits for approval on the `production` environment and then runs apply with
the same workflow inputs and GitHub secrets. It intentionally does not upload a
saved `tfplan` artifact because API origin custom headers are sensitive.

The plan job uses the plan role. The apply job uses the apply role after manual approval.

## Enable Custom Domain

CloudFront aliases require an ACM certificate in `us-east-1`.

```hcl
cloudfront_aliases     = ["engops.example.com"]
acm_certificate_arn    = "arn:aws:acm:us-east-1:123456789012:certificate/..."
route53_zone_id        = "Z..."
create_route53_records = true
```

## Enable API Routing

Set this only after `engops-api` has a stable external origin.

```hcl
engops_api_origin_domain_name     = "example-alb.ap-northeast-1.elb.amazonaws.com"
engops_api_origin_protocol_policy = "https-only"
```

When API routing is enabled, set the GitHub Actions secret
`ENGOPS_API_ORIGIN_VERIFY_TOKEN` to the same value loaded by the `engops-api`
deployment as `ENGOPS_API_ORIGIN_VERIFY_TOKEN`. CloudFront adds it as
`X-EngOps-Origin-Verify` when forwarding `/api/*` requests, and the backend
rejects direct-origin requests without that header or the internal machine
Bearer token.

If the Gateway/ALB only supports HTTP internally, set:

```hcl
engops_api_origin_protocol_policy = "http-only"
```

## Verification

```bash
terraform output cloudfront_distribution_domain_name
terraform output ui_bucket_name
```

After CloudFront is deployed:

```bash
CF_DOMAIN=$(terraform output -raw cloudfront_distribution_domain_name)
UI_BUCKET=$(terraform output -raw ui_bucket_name)

curl -I "https://${CF_DOMAIN}/"
curl -I "https://${UI_BUCKET}.s3.ap-northeast-1.amazonaws.com/index.html"
```

Expected:

- CloudFront URL returns `200` or `304` with CloudFront headers.
- Direct S3 URL returns `403 Forbidden`.
- UI deep links are handled by a CloudFront Function viewer-request rewrite, not by global 403/404 error mapping. This keeps `/api/*` errors from being masked as `index.html`.

If `engops_api_origin_domain_name` is set:

```bash
curl -I "https://${CF_DOMAIN}/api/v1/overview"
```

Expected:

- Request reaches the API origin.
- Do not count a distribution status of `Deployed` as sufficient validation. Test `/` and `/api/*` paths separately.
- Disallowed API methods must remain errors. For example, `POST /api/v1/approvals` should return `403` or `405`, not the UI `index.html`.
- Direct requests to the origin without `X-EngOps-Origin-Verify` or the
  internal Bearer token must return `403`.
