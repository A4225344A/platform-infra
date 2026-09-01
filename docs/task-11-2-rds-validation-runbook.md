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
- Kubernetes Secret key presence without printing values
- `ai-agent` `PGHOST` wiring to the RDS endpoint
- pgvector availability through an in-cluster connection

## Standard Command

Run from the EC2 control node:

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
PASS: RDS PostgreSQL is available, private, encrypted, backed up, and reachable from ai-agent without printing secrets.
```

Expected RDS properties:

```text
status=available
engine=postgres
storage_encrypted=true
publicly_accessible=false
```

Expected Kubernetes runtime check:

```text
REQUIRED_SECRETS_LOADED
postgres_connection=ok
pg_available_extension.vector=<version>
```

`pg_extension.vector=not_installed` is acceptable when the extension is available
but not installed in the `postgres` database yet. It becomes a follow-up only if
the application requires vector columns in that database.

## Security Notes

The script does not print secret values. It prints only key names and runtime
boolean checks.

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
