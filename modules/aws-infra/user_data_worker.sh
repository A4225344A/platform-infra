#!/bin/bash
set -euxo pipefail
exec > >(tee /var/log/k3s-bootstrap.log) 2>&1

REGION="${AWS_REGION}"
PROJECT="${PROJECT_NAME}"
CONTROL_IP="${CONTROL_PRIVATE_IP}"

IMDS_TOKEN=$(curl -sS -X PUT "http://169.254.169.254/latest/api/token" \
  -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
INSTANCE_ID=$(curl -sS -H "X-aws-ec2-metadata-token: $IMDS_TOKEN" \
  http://169.254.169.254/latest/meta-data/instance-id)
AZ=$(curl -sS -H "X-aws-ec2-metadata-token: $IMDS_TOKEN" \
  http://169.254.169.254/latest/meta-data/placement/availability-zone)

# 同 user_data_control.sh:get.k3s.io 的下載偶爾單次瞬斷,值得重試而不是讓整個
# join 腳本直接死掉。
retry() {
  local n=1 max=5 delay=15
  until "$@"; do
    if [ "$n" -ge "$max" ]; then
      echo "重試 $max 次後仍失敗: $*" >&2
      return 1
    fi
    echo "第 $n 次失敗,$${delay}s 後重試: $*" >&2
    n=$((n + 1))
    sleep "$delay"
  done
}

# eBPF 前置(worker 也要,漏掉會讓這台的 Cilium agent CrashLoop)
mount bpffs -t bpf /sys/fs/bpf
echo "bpffs /sys/fs/bpf bpf defaults 0 0" >> /etc/fstab
echo "* soft memlock unlimited" >> /etc/security/limits.conf
echo "* hard memlock unlimited" >> /etc/security/limits.conf

# 等 control 把 token 寫進 SSM(最多等 10 分鐘)
for i in $(seq 1 60); do
  if TOKEN=$(aws ssm get-parameter --region "$REGION" \
       --name "/$PROJECT/k3s/node-token" --with-decryption \
       --query Parameter.Value --output text 2>/dev/null); then
    break
  fi
  echo "等待 control 節點產生 token... ($i/60)"
  sleep 10
done
[ -n "$${TOKEN:-}" ] || { echo "取不到 token,放棄"; exit 1; }

join_k3s() {
  curl -sfL https://get.k3s.io | \
    K3S_URL="https://$${CONTROL_IP}:6443" \
    K3S_TOKEN="$TOKEN" \
    INSTALL_K3S_EXEC="agent --kubelet-arg=provider-id=aws:///$${AZ}/$${INSTANCE_ID} --node-label=topology.kubernetes.io/region=$${REGION} --node-label=topology.kubernetes.io/zone=$${AZ}" \
    sh -
}
retry join_k3s

echo "=== worker join 完成 ==="
