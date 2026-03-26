# AKS Static Egress Gateway Demo

This repository demonstrates two Azure Kubernetes Service (AKS) Static Egress Gateway deployment patterns:

1. Public static egress IPs, where annotated pods leave the cluster through gateway nodes backed by a public IP prefix.
2. Private static egress IPs, where annotated pods leave through gateway nodes using stable private IPs instead of public IPs.

The repo is split so each scenario has its own deployment script and gateway configuration.

## Repo Layout

- `public/setup.ps1`: Creates a public AKS cluster, enables Static Egress Gateway, adds a gateway node pool, and applies the public `StaticGatewayConfiguration`.
- `public/static-gateway-config.yaml`: Public gateway configuration named `gateway-config`.
- `private/setup.ps1`: Creates a private AKS cluster, a jumpbox VM, a dedicated egress subnet, and a gateway node pool for the private IP scenario.
- `private/static-gateway-config.yaml`: Private gateway configuration named `gateway-config-private` with `provisionPublicIps: false`.
- `curl.yaml`: Sample pod manifest. As written, it targets the public gateway configuration (`gateway-config`).

## What Each Deployment Creates

### Public deployment

The public deployment in [public/setup.ps1](public/setup.ps1) creates:

1. A resource group named `rg-aks-static-egress`.
2. An AKS cluster named `staticegresscluster` with Static Egress Gateway enabled.
3. A dedicated gateway node pool named `gateway` in `gateway` mode.
4. A `StaticGatewayConfiguration` named `gateway-config` in the `default` namespace.

### Private deployment

The private deployment in [private/setup.ps1](private/setup.ps1) creates:

1. A resource group named `rg-aks-static-egress-private`.
2. A virtual network with separate subnets for AKS nodes, a jumpbox VM, and gateway egress nodes.
3. A user-assigned managed identity used by the cluster and jumpbox.
4. A private AKS cluster named `staticprivateegresscluster` with Static Egress Gateway enabled.
5. A dedicated gateway node pool named `gateway` attached to the egress subnet.
6. A jumpbox VM that you can use to connect to the private cluster and apply manifests.

## Public Static Egress Flow

From the repo root, run:

```powershell
.\public\setup.ps1
```

Then run:

```powershell
kubectl apply -f .\curl.yaml
kubectl exec -it curl -- curl https://api.ipify.org
```

Expected result:

- The `curl` pod is annotated to use `gateway-config`.
- The outbound IP reported by `api.ipify.org` should be one of the IPs from `gateway-config`.

### Public verification

```powershell
kubectl describe StaticGatewayConfiguration gateway-config -n default
kubectl get staticgatewayconfiguration gateway-config -n default -o jsonpath='{.status.egressIpPrefix}'
kubectl exec -it curl -- curl https://api.ipify.org
```

### Public bypass behavior

The public configuration in [public/static-gateway-config.yaml](public/static-gateway-config.yaml) defines `excludeCidrs`.

Traffic to those CIDRs bypasses the gateway and uses the cluster's normal outbound path instead. In this repo, the excluded ranges are:

- `10.0.0.0/8`
- `172.16.0.0/12`
- `169.254.169.254/32`

If you also exclude a public destination range, traffic to that destination will no longer use the gateway IP.

## Private Static Egress Flow

The private deployment is intentionally separate because it needs different infrastructure and operational steps.

### What is different in the private scenario

- The AKS cluster uses a private API endpoint.
- The gateway node pool is placed on a dedicated subnet.
- The gateway configuration is a different manifest: [private/static-gateway-config.yaml](private/static-gateway-config.yaml).
- The private gateway configuration name is `gateway-config-private`, not `gateway-config`.
- [curl.yaml](curl.yaml) does not target the private gateway configuration, so you must update the pod annotation or apply a private-specific test manifest.

### Deploy the private infrastructure

From the repo root, run:

```powershell
.\private\setup.ps1
```

The script creates the private cluster and prints the SSH command for the jumpbox. Because the cluster is private, the usual workflow is to connect through that VM before applying Kubernetes manifests and validating outbound traffic.

### Connect through the jumpbox and apply the private gateway config

After SSHing to the jumpbox, install the required tools and connect to the cluster:

```bash
curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl && rm kubectl

az login --identity
az aks get-credentials -n staticprivateegresscluster -g rg-aks-static-egress-private
kubectl get nodes
```

Then apply the private gateway configuration:

```bash
kubectl apply -f private/static-gateway-config.yaml
kubectl describe StaticGatewayConfiguration gateway-config-private -n default
kubectl get staticgatewayconfiguration gateway-config-private -n default -o jsonpath='{.status.egressIpPrefix}'
```

To test pod egress, use a pod annotated with the private configuration name:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: curl-private
  namespace: default
  annotations:
    kubernetes.azure.com/static-gateway-configuration: gateway-config-private
spec:
  containers:
  - name: curl
    image: curlimages/curl:latest
    command: ["sleep", "infinity"]
```

## How Private Static Egress IPs Work

AKS private static egress support uses the same Static Egress Gateway feature, but instead of provisioning public IPs for the gateway configuration, it keeps stable private IPs attached to the gateway nodes.

Based on the Microsoft AKS documentation:

- Private static IP support requires Kubernetes version `1.34` or later.
- The gateway node pool still runs in `gateway` mode, but private IP support is intended for gateway nodes that keep traffic on private addresses.
- The `StaticGatewayConfiguration` sets `provisionPublicIps: false`, which tells AKS not to allocate public IPs for that configuration.
- AKS reserves the private IPs assigned to the gateway nodes for the lifetime of the `StaticGatewayConfiguration`.
- The `status.egressIpPrefix` field on the `StaticGatewayConfiguration` shows the resulting static private IPs as a comma-separated list.
- Annotated pods use the same pod annotation model as the public scenario. The difference is the source IPs seen downstream are the gateway nodes' private IPs instead of public addresses.

Operationally, this means the gateway gives you predictable private source IPs for outbound traffic to private destinations, which is useful when downstream systems are reachable over private networking and need stable allowlist entries.

## Gateway Node Pool Flags

### `--mode gateway`

`az aks nodepool add --mode gateway` creates a dedicated gateway node pool for Static Egress Gateway.

- It is not intended for general application workloads.
- Annotated pods route outbound traffic through this pool.
- Windows node pools can't be used as gateway node pools.

### `--gateway-prefix-size <28-31>`

This controls the IP prefix size associated with the gateway node pool.

- Allowed range is `/28` to `/31`.
- Smaller prefix numbers provide more address capacity.
- The gateway node count must fit inside the selected prefix size.
- This repo uses `--gateway-prefix-size 31` with `--node-count 2`.

## Notes and Limitations

- Pods can use a `StaticGatewayConfiguration` only if they are in the same namespace as that configuration.
- Gateway node pools should be dedicated to egress traffic.
- `hostNetwork` pods can't be annotated to use Static Egress Gateway.
- Kubernetes network policies don't apply to traffic once it leaves through the gateway node pool.
- Static Egress Gateway isn't supported with Azure CNI Pod Subnet.
- Gateway node pools don't support autoscaling.

## Reference

- AKS Static Egress Gateway documentation: https://learn.microsoft.com/azure/aks/configure-static-egress-gateway
- Static private IP support reference: https://learn.microsoft.com/en-us/azure/aks/configure-static-egress-gateway#static-private-ip-support
