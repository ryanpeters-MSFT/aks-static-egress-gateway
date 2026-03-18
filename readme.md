# AKS Static Egress Gateway Demo

This repository demonstrates a minimal Azure Kubernetes Service (AKS) setup using **Static Egress Gateway** so selected workloads can egress with predictable source IPs.

## Repo Contents

- `setup.ps1`: Provisions AKS, creates a gateway node pool, applies Kubernetes manifests, and validates outbound IP.
- `static-gateway-config.yaml`: Defines a `StaticGatewayConfiguration` named `gateway-config` in `default` namespace.
- `curl.yaml`: Defines a sample pod named `curl` annotated to use `gateway-config`.

## What This Demo Deploys

1. A resource group and AKS cluster with Static Egress Gateway enabled.
2. A dedicated gateway node pool (`gateway`) in `gateway` mode.
3. A `StaticGatewayConfiguration` custom resource bound to that gateway node pool.
4. A sample pod (`curl`) that routes outbound traffic through the gateway.

## Quick Start

From the repo root, run:

```powershell
# deploy AKS cluster with static gateway enabled
./setup.ps1

# deploy curl test pod
kubectl apply -f .\curl.yaml
```

## Flag Details

### `--mode gateway`

When creating a node pool with `az aks nodepool add`, `--mode gateway` makes that node pool a **gateway node pool** for Static Egress Gateway.

- The pool is intended for egress gateway functionality, not general application workloads.
- Annotated pods are routed through this gateway pool for outbound traffic.
- This is different from regular node pool modes used for app scheduling.

### `--gateway-prefix-size <28-31>`

This sets the **public IP prefix size** allocated for the gateway node pool.

- Allowed range is `/28` to `/31`.
- Smaller prefix number means more IP capacity:
  - `/28` = 16 addresses
  - `/29` = 8 addresses
  - `/30` = 4 addresses
  - `/31` = 2 addresses
- The gateway node count must fit within the selected prefix capacity.
- Your script uses `--gateway-prefix-size 31` and `--node-count 2`, which aligns to the `/31` capacity.

## Verify the Deployment

Check gateway configuration status:

```powershell
# verify the gateway configuration status
kubectl describe StaticGatewayConfiguration gateway-config -n default

# retrieve the egress IP CIDR for gateway-config
kubectl get staticgatewayconfiguration gateway-config -o jsonpath='{.status.egressIpPrefix}'

# should return the IP of the static egress gateway
kubectl exec -it curl -- curl https://api.ipify.org
```

### Destination CIDR Routing

If a destination matches `spec.excludeCidrs` on the `StaticGatewayConfiguration`, traffic to that CIDR bypasses the Static Egress Gateway and uses the cluster's normal outbound routing instead.

In this demo, the private ranges `10.0.0.0/8` and `172.16.0.0/12`, plus `169.254.169.254/32`, are excluded so they don't use the gateway's static egress IPs.

```powershell
# should return the IP of the default load balancer
kubectl exec -it curl -- curl https://ifconfig.me
```

## Notes and Limitations

- Pods can use a `StaticGatewayConfiguration` only if they are in the same namespace as that configuration.
- Gateway node pools should be dedicated to egress traffic.
- Host-network pods cannot be annotated to use the gateway.
- Plan node count and prefix size together, because capacity is constrained by prefix size.

## Reference

- AKS Static Egress Gateway docs:
  `https://learn.microsoft.com/azure/aks/configure-static-egress-gateway`
