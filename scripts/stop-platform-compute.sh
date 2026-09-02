#!/usr/bin/env bash
set -euo pipefail

REGION="${REGION:-ap-northeast-1}"
CONTROL_TAG_NAME="${CONTROL_TAG_NAME:-Name}"
CONTROL_TAG_VALUE="${CONTROL_TAG_VALUE:-platform-control}"
ASG_NAME="${ASG_NAME:-platform-worker}"
DRAIN_TIMEOUT="${DRAIN_TIMEOUT:-180s}"
STOP_CONTROL="${STOP_CONTROL:-true}"

need() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "missing required command: $1" >&2
    exit 1
  fi
}

section() {
  printf '\n== %s ==\n' "$1"
}

find_control_id() {
  aws ec2 describe-instances \
    --region "$REGION" \
    --filters "Name=tag:${CONTROL_TAG_NAME},Values=${CONTROL_TAG_VALUE}" "Name=instance-state-name,Values=running" \
    --query 'Reservations[].Instances[].InstanceId' \
    --output text \
    | awk '{print $1}'
}

send_ssm_script() {
  local comment="$1"
  local script_file="$2"
  local payload_file command_id status

  payload_file="$(mktemp)"
  jq -n \
    --arg instance_id "$CONTROL_ID" \
    --arg comment "$comment" \
    --rawfile script "$script_file" \
    '{
      DocumentName: "AWS-RunShellScript",
      InstanceIds: [$instance_id],
      Comment: $comment,
      Parameters: {
        commands: ($script | split("\n") | map(select(length > 0)))
      }
    }' > "$payload_file"

  command_id="$(aws ssm send-command \
    --region "$REGION" \
    --cli-input-json "file://$payload_file" \
    --query 'Command.CommandId' \
    --output text)"

  aws ssm wait command-executed \
    --region "$REGION" \
    --command-id "$command_id" \
    --instance-id "$CONTROL_ID" || true

  aws ssm get-command-invocation \
    --region "$REGION" \
    --command-id "$command_id" \
    --instance-id "$CONTROL_ID" \
    --query '{Status:Status,Stdout:StandardOutputContent,Stderr:StandardErrorContent}' \
    --output text

  status="$(aws ssm get-command-invocation \
    --region "$REGION" \
    --command-id "$command_id" \
    --instance-id "$CONTROL_ID" \
    --query 'Status' \
    --output text)"

  rm -f "$payload_file"

  if [ "$status" != "Success" ]; then
    echo "SSM command failed: $comment ($status)" >&2
    exit 1
  fi
}

need aws
need jq
need mktemp

section "Find running control instance"
CONTROL_ID="$(find_control_id)"
if [ -z "$CONTROL_ID" ] || [ "$CONTROL_ID" = "None" ]; then
  echo "no running control instance found for tag ${CONTROL_TAG_NAME}=${CONTROL_TAG_VALUE}" >&2
  exit 1
fi
echo "control_instance_id=$CONTROL_ID"

drain_script="$(mktemp)"
cat > "$drain_script" <<REMOTE
#!/usr/bin/env bash
set -euo pipefail
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

command -v kubectl >/dev/null
command -v jq >/dev/null

kubectl get nodes -o wide
mapfile -t worker_nodes < <(
  kubectl get nodes -o json | jq -r '.items[]
    | select((.metadata.labels["node-role.kubernetes.io/control-plane"] // "") != "true")
    | .metadata.name'
)

printf '%s\n' "\${worker_nodes[@]}" > /tmp/platform-worker-nodes-to-delete

if [ "\${#worker_nodes[@]}" -eq 0 ]; then
  echo "no worker nodes found to drain"
  exit 0
fi

for node in "\${worker_nodes[@]}"; do
  echo "cordon \$node"
  kubectl cordon "\$node" || true
  echo "drain \$node"
  kubectl drain "\$node" --ignore-daemonsets --delete-emptydir-data --force --timeout="${DRAIN_TIMEOUT}"
done
REMOTE

section "Drain worker nodes on control"
send_ssm_script "drain k3s worker nodes before ASG scale-down" "$drain_script"
rm -f "$drain_script"

section "Scale worker ASG to zero"
aws autoscaling update-auto-scaling-group \
  --region "$REGION" \
  --auto-scaling-group-name "$ASG_NAME" \
  --min-size 0 \
  --desired-capacity 0

section "Wait for ASG instances to reach zero"
for _ in $(seq 1 60); do
  instance_count="$(aws autoscaling describe-auto-scaling-groups \
    --region "$REGION" \
    --auto-scaling-group-names "$ASG_NAME" \
    --query 'length(AutoScalingGroups[0].Instances)' \
    --output text)"
  echo "asg_instance_count=$instance_count"
  if [ "$instance_count" = "0" ]; then
    break
  fi
  sleep 10
done

if [ "$instance_count" != "0" ]; then
  echo "ASG still has instances; refusing to stop control" >&2
  exit 1
fi

delete_nodes_script="$(mktemp)"
cat > "$delete_nodes_script" <<'REMOTE'
#!/usr/bin/env bash
set -euo pipefail
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

if [ -s /tmp/platform-worker-nodes-to-delete ]; then
  xargs -r kubectl delete node --ignore-not-found < /tmp/platform-worker-nodes-to-delete
else
  echo "no saved worker nodes to delete"
fi

kubectl get nodes -o wide
REMOTE

section "Delete drained worker node objects"
send_ssm_script "delete drained k3s worker node objects" "$delete_nodes_script"
rm -f "$delete_nodes_script"

if [ "$STOP_CONTROL" = "true" ]; then
  section "Stop control instance"
  aws ec2 stop-instances \
    --region "$REGION" \
    --instance-ids "$CONTROL_ID"

  aws ec2 wait instance-stopped \
    --region "$REGION" \
    --instance-ids "$CONTROL_ID"

  aws ec2 describe-instances \
    --region "$REGION" \
    --instance-ids "$CONTROL_ID" \
    --query 'Reservations[0].Instances[0].[InstanceId,State.Name,PrivateIpAddress,PublicIpAddress]' \
    --output table
fi

section "Stop result"
echo "PASS: workers drained, worker ASG is zero, worker node objects are removed, and control stop path completed."
