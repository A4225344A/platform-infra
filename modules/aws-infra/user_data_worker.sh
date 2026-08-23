#!/bin/bash
set -euxo pipefail
exec > >(tee /var/log/k3s-bootstrap.log) 2>&1

REGION="${AWS_REGION}"
PROJECT="${PROJECT_NAME}"
CONTROL_IP="${CONTROL_PRIVATE_IP}"

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

curl -sfL https://get.k3s.io | \
  K3S_URL="https://$${CONTROL_IP}:6443" K3S_TOKEN="$TOKEN" sh -

echo "=== worker join 完成 ==="
