# Task 11.2 RDS Validation Runbook

## Scope

Task 11.2 is already migrated to RDS PostgreSQL. This runbook validates the
current state instead of recreating the database.

The validation checks:

- RDS instance status, engine, encryption, public access, and endpoint
- EventBridge rule for daily manual snapshots
- RDS snapshot backup Lambda state
- Recent manual snapshots
- Backup S3 bucket visibility

## Standard Command

Run from CloudShell / management shell:

```bash
cd ~/platform-infra
git pull --ff-only
bash scripts/validate-task-11-2-rds.sh
```

Optional overrides:

```bash
REGION=ap-northeast-1 \
PROJECT=platform \
DB_IDENTIFIER=platform-postgres \
BACKUP_BUCKET=platform-w3-backup-029099141993-apne1 \
bash scripts/validate-task-11-2-rds.sh
```

## Expected Result

The final line should be:

```text
PASS: AWS/RDS layer is available, private, encrypted, and backed up.
```

Expected RDS properties:

```text
status=available
engine=postgres
storage_encrypted=true
publicly_accessible=false
```

## Kubernetes Runtime Validation

Run the Kubernetes runtime layer separately from the EC2 control node, where
`kubectl` is already connected to K3s:

```bash
cd ~/platform-gitops
git pull --ff-only
bash scripts/validate-task-11-2-k8s-runtime.sh
```

Expected Kubernetes runtime result:

```text
REQUIRED_SECRETS_LOADED
postgres_connection=ok
pg_available_extension.vector=<version>
```

`pg_extension.vector=not_installed` is acceptable when the extension is available
but not installed in the `postgres` database yet. It becomes a follow-up only if
the application requires vector columns in that database.

## Security Notes

The CloudShell AWS/RDS script does not read or print Kubernetes Secret values.
The EC2 runtime script prints only Secret key names and boolean/runtime checks.

Do not run:

```bash
kubectl exec deploy/ai-agent -- printenv
```

That can expose `PGPASSWORD`, `LITELLM_MASTER_KEY`, and webhook tokens.

## Known Decisions

`multi_az=false` is intentional for the lab cost profile. Treat it as a known
cost decision, not a failed validation, unless the task scope changes to a
production HA posture.

RDS has `prevent_destroy = true` in Terraform and is not part of daily node
destroy.
