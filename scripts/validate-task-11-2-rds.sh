#!/usr/bin/env bash
set -euo pipefail

REGION="${REGION:-ap-northeast-1}"
PROJECT="${PROJECT:-platform}"
DB_IDENTIFIER="${DB_IDENTIFIER:-${PROJECT}-postgres}"
DEFAULT_NS="${DEFAULT_NS:-default}"
AI_AGENT_DEPLOY="${AI_AGENT_DEPLOY:-ai-agent}"
PLATFORM_SECRET="${PLATFORM_SECRET:-platform-secrets}"
BACKUP_RULE="${BACKUP_RULE:-${PROJECT}-rds-snapshot-backup}"
BACKUP_LAMBDA="${BACKUP_LAMBDA:-${PROJECT}-rds-snapshot-backup}"
BACKUP_BUCKET="${BACKUP_BUCKET:-}"

need() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "missing required command: $1" >&2
    exit 1
  fi
}

section() {
  printf '\n== %s ==\n' "$1"
}

need aws
need jq
need kubectl

section "RDS instance"
db_json="$(aws rds describe-db-instances \
  --region "$REGION" \
  --db-instance-identifier "$DB_IDENTIFIER" \
  --output json)"

db_status="$(jq -r '.DBInstances[0].DBInstanceStatus' <<<"$db_json")"
db_engine="$(jq -r '.DBInstances[0].Engine' <<<"$db_json")"
db_engine_version="$(jq -r '.DBInstances[0].EngineVersion' <<<"$db_json")"
db_encrypted="$(jq -r '.DBInstances[0].StorageEncrypted' <<<"$db_json")"
db_multi_az="$(jq -r '.DBInstances[0].MultiAZ' <<<"$db_json")"
db_endpoint="$(jq -r '.DBInstances[0].Endpoint.Address' <<<"$db_json")"
db_public="$(jq -r '.DBInstances[0].PubliclyAccessible' <<<"$db_json")"

printf 'identifier=%s\n' "$DB_IDENTIFIER"
printf 'status=%s\n' "$db_status"
printf 'engine=%s\n' "$db_engine"
printf 'engine_version=%s\n' "$db_engine_version"
printf 'storage_encrypted=%s\n' "$db_encrypted"
printf 'multi_az=%s\n' "$db_multi_az"
printf 'publicly_accessible=%s\n' "$db_public"
printf 'endpoint=%s\n' "$db_endpoint"

test "$db_status" = "available"
test "$db_engine" = "postgres"
test "$db_encrypted" = "true"
test "$db_public" = "false"

section "Backup schedule"
aws events describe-rule \
  --region "$REGION" \
  --name "$BACKUP_RULE" \
  --query '[Name,ScheduleExpression,State]' \
  --output table

section "Backup Lambda"
aws lambda get-function \
  --region "$REGION" \
  --function-name "$BACKUP_LAMBDA" \
  --query 'Configuration.[FunctionName,Runtime,State]' \
  --output table

section "Manual RDS snapshots"
snapshot_count="$(aws rds describe-db-snapshots \
  --region "$REGION" \
  --db-instance-identifier "$DB_IDENTIFIER" \
  --snapshot-type manual \
  --query 'length(DBSnapshots)' \
  --output text)"
printf 'manual_snapshot_count=%s\n' "$snapshot_count"
test "$snapshot_count" -ge 1

aws rds describe-db-snapshots \
  --region "$REGION" \
  --db-instance-identifier "$DB_IDENTIFIER" \
  --snapshot-type manual \
  --query 'sort_by(DBSnapshots,&SnapshotCreateTime)[-3:].[DBSnapshotIdentifier,Status,SnapshotCreateTime]' \
  --output table

section "Backup bucket"
if [ -z "$BACKUP_BUCKET" ] && command -v terraform >/dev/null 2>&1; then
  BACKUP_BUCKET="$(terraform output -raw backup_bucket_name 2>/dev/null || true)"
fi

if [ -z "$BACKUP_BUCKET" ]; then
  echo "BACKUP_BUCKET is not set and terraform output backup_bucket_name is unavailable; skipping S3 object listing"
else
  printf 'backup_bucket=%s\n' "$BACKUP_BUCKET"
  aws s3api head-bucket --region "$REGION" --bucket "$BACKUP_BUCKET"
  aws s3 ls "s3://${BACKUP_BUCKET}/w3/" | tail -5 || true
fi

section "Kubernetes Secret key presence"
kubectl get secret "$PLATFORM_SECRET" -n "$DEFAULT_NS" -o json \
  | jq -r '.data | keys[]'

kubectl get secret "$PLATFORM_SECRET" -n "$DEFAULT_NS" -o json \
  | jq -e '.data["postgres-password"] != null' >/dev/null

section "ai-agent RDS runtime wiring"
agent_pghost="$(kubectl exec deploy/"$AI_AGENT_DEPLOY" -n "$DEFAULT_NS" -- printenv PGHOST)"
printf 'ai_agent_pghost=%s\n' "$agent_pghost"
test "$agent_pghost" = "$db_endpoint"

kubectl exec deploy/"$AI_AGENT_DEPLOY" -n "$DEFAULT_NS" -- sh -c \
  'test -n "$PGPASSWORD" && test -n "$LITELLM_MASTER_KEY" && echo REQUIRED_SECRETS_LOADED'

section "pgvector availability from ai-agent"
kubectl exec -i deploy/"$AI_AGENT_DEPLOY" -n "$DEFAULT_NS" -- python - <<'PY'
import os
import psycopg2

conn = psycopg2.connect(
    host=os.environ["PGHOST"],
    user="postgres",
    password=os.environ["PGPASSWORD"],
    dbname="postgres",
    connect_timeout=10,
)
try:
    with conn.cursor() as cur:
        cur.execute("select version()")
        print("postgres_connection=ok")
        cur.execute("select default_version from pg_available_extensions where name = 'vector'")
        row = cur.fetchone()
        if not row:
            raise SystemExit("pg_available_extension.vector=missing")
        print(f"pg_available_extension.vector={row[0]}")
        cur.execute("select extname, extversion from pg_extension where extname = 'vector'")
        ext = cur.fetchone()
        if ext:
            print(f"pg_extension.vector={ext[1]}")
        else:
            print("pg_extension.vector=not_installed")
finally:
    conn.close()
PY

section "Task 11.2 result"
echo "PASS: RDS PostgreSQL is available, private, encrypted, backed up, and reachable from ai-agent without printing secrets."
