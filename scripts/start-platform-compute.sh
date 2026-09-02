#!/usr/bin/env bash
set -euo pipefail

REGION="${REGION:-ap-northeast-1}"
CONTROL_TAG_NAME="${CONTROL_TAG_NAME:-Name}"
CONTROL_TAG_VALUE="${CONTROL_TAG_VALUE:-platform-control}"
ASG_NAME="${ASG_NAME:-platform-worker}"
DEFAULT_NS="${DEFAULT_NS:-default}"

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
    --filters "Name=tag:${CONTROL_TAG_NAME},Values=${CONTROL_TAG_VALUE}" "Name=instance-state-name,Values=pending,running,stopping,stopped" \
    --query 'Reservations[].Instances[].InstanceId' \
    --output text \
    | awk '{print $1}'
}

control_state() {
  aws ec2 describe-instances \
    --region "$REGION" \
    --instance-ids "$CONTROL_ID" \
    --query 'Reservations[0].Instances[0].State.Name' \
    --output text
}

wait_ssm_online() {
  for _ in $(seq 1 60); do
    ping_status="$(aws ssm describe-instance-information \
      --region "$REGION" \
      --filters "Key=InstanceIds,Values=$CONTROL_ID" \
      --query 'InstanceInformationList[0].PingStatus' \
      --output text 2>/dev/null || true)"
    echo "ssm_ping_status=$ping_status"
    if [ "$ping_status" = "Online" ]; then
      return 0
    fi
    sleep 10
  done
  return 1
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

section "Find control instance"
CONTROL_ID="$(find_control_id)"
if [ -z "$CONTROL_ID" ] || [ "$CONTROL_ID" = "None" ]; then
  echo "no control instance found for tag ${CONTROL_TAG_NAME}=${CONTROL_TAG_VALUE}" >&2
  exit 1
fi
echo "control_instance_id=$CONTROL_ID"

state="$(control_state)"
echo "control_state=$state"

case "$state" in
  stopped)
    section "Start control instance"
    aws ec2 start-instances --region "$REGION" --instance-ids "$CONTROL_ID"
    aws ec2 wait instance-running --region "$REGION" --instance-ids "$CONTROL_ID"
    ;;
  stopping)
    section "Wait for control to stop, then start it"
    aws ec2 wait instance-stopped --region "$REGION" --instance-ids "$CONTROL_ID"
    aws ec2 start-instances --region "$REGION" --instance-ids "$CONTROL_ID"
    aws ec2 wait instance-running --region "$REGION" --instance-ids "$CONTROL_ID"
    ;;
  pending)
    section "Wait for control to become running"
    aws ec2 wait instance-running --region "$REGION" --instance-ids "$CONTROL_ID"
    ;;
  running)
    echo "control already running"
    ;;
  *)
    echo "unsupported control state: $state" >&2
    exit 1
    ;;
esac

section "Wait for SSM online"
wait_ssm_online

section "Scale worker ASG to desired capacity"
aws autoscaling update-auto-scaling-group \
  --region "$REGION" \
  --auto-scaling-group-name "$ASG_NAME" \
  --min-size 2 \
  --desired-capacity 2 \
  --max-size 4

section "Wait for ASG healthy InService workers"
for _ in $(seq 1 60); do
  ready_count="$(aws autoscaling describe-auto-scaling-groups \
    --region "$REGION" \
    --auto-scaling-group-names "$ASG_NAME" \
    --query 'length(AutoScalingGroups[0].Instances[?LifecycleState==`InService` && HealthStatus==`Healthy`])' \
    --output text)"
  echo "healthy_inservice_workers=$ready_count"
  if [ "$ready_count" -ge 2 ]; then
    break
  fi
  sleep 10
done

if [ "$ready_count" -lt 2 ]; then
  echo "worker ASG did not reach two healthy InService instances" >&2
  exit 1
fi

verify_script="$(mktemp)"
cat > "$verify_script" <<REMOTE
#!/usr/bin/env bash
set -euo pipefail
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

command -v kubectl >/dev/null
command -v jq >/dev/null
command -v curl >/dev/null

echo "== Wait for Kubernetes Ready nodes =="
for _ in \$(seq 1 60); do
  ready_nodes="\$(kubectl get nodes -o json | jq '[.items[] | select(.status.conditions[]? | select(.type=="Ready" and .status=="True"))] | length')"
  echo "ready_nodes=\$ready_nodes"
  if [ "\$ready_nodes" -ge 3 ]; then
    break
  fi
  sleep 10
done

if [ "\$ready_nodes" -lt 3 ]; then
  kubectl get nodes -o wide
  echo "Kubernetes did not reach control + 2 Ready workers" >&2
  exit 1
fi

echo "== Remove stale NotReady workers =="
mapfile -t stale_nodes < <(
  kubectl get nodes -o json | jq -r '.items[]
    | select((.metadata.labels["node-role.kubernetes.io/control-plane"] // "") != "true")
    | select([.status.conditions[]? | select(.type=="Ready" and .status=="True")] | length == 0)
    | .metadata.name'
)
if [ "\${#stale_nodes[@]}" -gt 0 ]; then
  kubectl delete node "\${stale_nodes[@]}" --ignore-not-found
else
  echo "no stale NotReady worker nodes found"
fi

echo "== Nodes =="
kubectl get nodes -o wide

echo "== Wait for default deployments =="
kubectl wait --for=condition=Available deploy --all -n "${DEFAULT_NS}" --timeout=300s
kubectl get pods -n "${DEFAULT_NS}" -o wide

echo "== Wait for monitoring deployments =="
kubectl wait --for=condition=Available deploy --all -n monitoring --timeout=300s
kubectl get pods -n monitoring

echo "== Kube-system pods =="
kubectl get pods -n kube-system

echo "== Gateway and HTTPRoute =="
kubectl get gateway platform-gateway -n "${DEFAULT_NS}"
kubectl get httproute -n "${DEFAULT_NS}" -o json \
  | jq -r '.items[] | [.metadata.name, (.status.parents[0].conditions[]? | select(.type=="Accepted").status // "-")] | @tsv'

echo "== EngOps API =="
kubectl rollout status deploy/engops-api -n "${DEFAULT_NS}" --timeout=180s
kubectl port-forward deploy/engops-api 18000:8000 -n "${DEFAULT_NS}" >/tmp/engops-api-pf.log 2>&1 &
pf_pid=\$!
trap 'kill "\$pf_pid" >/dev/null 2>&1 || true' EXIT
sleep 3
curl -fsS http://127.0.0.1:18000/healthz
printf '\n'
curl -fsS http://127.0.0.1:18000/readyz
printf '\n'

echo "== ArgoCD =="
kubectl get applications -n argocd || true

echo "PASS: start verification completed"
REMOTE

section "Verify Kubernetes runtime through SSM"
send_ssm_script "verify k3s platform after compute start" "$verify_script"
rm -f "$verify_script"

section "Start result"
echo "PASS: control is running, worker ASG is healthy, stale nodes are removed, and platform runtime is verified."
