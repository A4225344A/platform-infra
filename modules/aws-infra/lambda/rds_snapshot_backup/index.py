import os
from datetime import datetime, timedelta, timezone

import boto3
from botocore.exceptions import ClientError


rds = boto3.client("rds")


DB_INSTANCE_ID = os.environ["DB_INSTANCE_ID"]
RETENTION_DAYS = int(os.environ.get("RETENTION_DAYS", "7"))


def _snapshot_id(today):
    return f"{DB_INSTANCE_ID}-manual-{today}"


def lambda_handler(event, context):
    now = datetime.now(timezone.utc)
    snapshot_id = _snapshot_id(now.strftime("%Y-%m-%d"))

    db = rds.describe_db_instances(DBInstanceIdentifier=DB_INSTANCE_ID)[
        "DBInstances"
    ][0]
    status = db["DBInstanceStatus"]

    created = None
    skipped = None
    if status == "available":
        try:
            response = rds.create_db_snapshot(
                DBSnapshotIdentifier=snapshot_id,
                DBInstanceIdentifier=DB_INSTANCE_ID,
                Tags=[
                    {"Key": "Project", "Value": "W3"},
                    {"Key": "Purpose", "Value": "task10-backup"},
                    {"Key": "ManagedBy", "Value": "terraform-lambda"},
                ],
            )
            created = response["DBSnapshot"]["DBSnapshotIdentifier"]
        except ClientError as exc:
            code = exc.response.get("Error", {}).get("Code")
            if code == "DBSnapshotAlreadyExists":
                skipped = f"snapshot already exists: {snapshot_id}"
            else:
                raise
    else:
        skipped = f"db instance status is {status}; snapshot requires available"

    cutoff = now - timedelta(days=RETENTION_DAYS)
    deleted = []
    snapshots = rds.describe_db_snapshots(
        DBInstanceIdentifier=DB_INSTANCE_ID,
        SnapshotType="manual",
    )["DBSnapshots"]

    for snapshot in snapshots:
        sid = snapshot["DBSnapshotIdentifier"]
        create_time = snapshot["SnapshotCreateTime"]
        if not sid.startswith(f"{DB_INSTANCE_ID}-manual-"):
            continue
        if sid == snapshot_id:
            continue
        if create_time >= cutoff:
            continue
        if snapshot["Status"] != "available":
            continue

        rds.delete_db_snapshot(DBSnapshotIdentifier=sid)
        deleted.append(sid)

    return {
        "db_instance": DB_INSTANCE_ID,
        "db_status": status,
        "created": created,
        "skipped": skipped,
        "deleted": deleted,
    }
