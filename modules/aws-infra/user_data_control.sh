#!/bin/bash
set -euxo pipefail
exec > >(tee /var/log/k3s-bootstrap.log) 2>&1

REGION="${AWS_REGION}"
PROJECT="${PROJECT_NAME}"
GWAPI_VERSION=v1.3.0
CILIUM_VERSION=1.17.6

# 外部下載(GitHub/dl.k8s.io release CDN)偶爾會單次瞬斷,曾經在實測中讓
# 整個 user_data 死在下載這一步(hash 檔案抓得到、幾十 MB 的 binary 抓不到)。
# set -e 底下一次失敗就整份腳本中止,補上重試比人工進 Session Manager 手動接續划算。
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

# --- 1. eBPF 前置條件 ---
mount bpffs -t bpf /sys/fs/bpf
echo "bpffs /sys/fs/bpf bpf defaults 0 0" >> /etc/fstab
echo "* soft memlock unlimited" >> /etc/security/limits.conf
echo "* hard memlock unlimited" >> /etc/security/limits.conf

# --- 2. 裝 k3s(關掉要替換的預設) ---
install_k3s() {
  curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="\
    --flannel-backend=none \
    --disable-network-policy \
    --disable-kube-proxy \
    --disable=traefik \
    --disable=servicelb" sh -
}
retry install_k3s

export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
echo 'export KUBECONFIG=/etc/rancher/k3s/k3s.yaml' >> /root/.bashrc

# --- 3. 把 node-token 放進 SSM,讓 worker 自己來拿 ---
TOKEN=$(cat /var/lib/rancher/k3s/server/node-token)
aws ssm put-parameter --region "$REGION" \
  --name "/$PROJECT/k3s/node-token" --type SecureString \
  --value "$TOKEN" --overwrite

# --- 4. 等 API server 真的可以服務(節點此時仍 NotReady,不能用 wait node Ready) ---
until kubectl get --raw /readyz >/dev/null 2>&1; do sleep 3; done

# --- 5. 裝工具鏈 ---
install_kubectl() {
  curl -LO "https://dl.k8s.io/release/$(curl -Ls https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
  chmod +x kubectl && mv kubectl /usr/local/bin/
}
retry install_kubectl

install_cilium_cli() {
  CILIUM_CLI_VERSION=$(curl -s https://raw.githubusercontent.com/cilium/cilium-cli/main/stable.txt)
  curl -L --fail --remote-name-all \
    "https://github.com/cilium/cilium-cli/releases/download/$${CILIUM_CLI_VERSION}/cilium-linux-amd64.tar.gz"
  tar xzvfC cilium-linux-amd64.tar.gz /usr/local/bin
}
retry install_cilium_cli

# W3 任務 1.2 起要用 helm 裝 kube-prometheus-stack,原本這裡沒裝過。
install_helm() {
  curl -fsSL -o /tmp/get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
  chmod +x /tmp/get_helm.sh
  /tmp/get_helm.sh
}
retry install_helm

# --- 6. Gateway API CRD(必須在 Cilium 之前,且要等 Established) ---
apply_gwapi_crds() {
  kubectl apply -f "https://github.com/kubernetes-sigs/gateway-api/releases/download/$${GWAPI_VERSION}/standard-install.yaml"
  kubectl apply -f "https://raw.githubusercontent.com/kubernetes-sigs/gateway-api/$${GWAPI_VERSION}/config/crd/experimental/gateway.networking.k8s.io_tlsroutes.yaml"
}
retry apply_gwapi_crds

for crd in gateways httproutes tlsroutes; do
  kubectl wait --for=condition=Established \
    "crd/$${crd}.gateway.networking.k8s.io" --timeout=120s
done

# --- 7. 裝 Cilium,內網 IP 現場取得(這行就是自動化的價值:永遠不會填到舊 IP) ---
CONTROL_IP=$(hostname -I | awk '{print $1}')
cat > /root/cilium-values.yaml << EOF
kubeProxyReplacement: true
k8sServiceHost: $${CONTROL_IP}
k8sServicePort: 6443
ipam: { mode: kubernetes }
resources:
  requests: { memory: 256Mi }
  limits:   { memory: 512Mi }
operator: { replicas: 1 }
gatewayAPI:
  enabled: true
  hostNetwork: { enabled: true }
envoy:
  enabled: true
  securityContext:
    capabilities:
      keepCapNetBindService: true
      envoy: [NET_ADMIN, PERFMON, BPF, NET_BIND_SERVICE]
EOF

# cilium install 本身不重試——Helm install 失敗到一半再重跑,可能撞上
# "cannot re-use a name that is still in use" 這種殘留 release 衝突,
# 比原本的失敗更難清。上面幾個外部下載才是實測會瞬斷的環節,已經重試過了,
# 走到這裡網路多半是穩的;真的失敗了直接讓腳本中止,交給人工判斷比較安全。
cilium install --version "$${CILIUM_VERSION}" -f /root/cilium-values.yaml
cilium status --wait

echo "=== k3s + Cilium bootstrap 完成 ==="
