# AKS Static Egress Gateway Demo

This repository demonstrates a minimal Azure Kubernetes Service (AKS) setup using **Static Egress Gateway** so selected workloads can egress with predictable source IPs.

## Repo Contents

- `setup.ps1`: Provisions AKS, creates a gateway node pool, applies Kubernetes manifests, and validates outbound IP.
- `static-gateway-config.yaml`: Defines a `StaticGatewayConfiguration` named `gateway-config` in `default` namespace.
- `egress-sample-deployment.yaml`: Deploys a sample pod annotated to use `gateway-config`.

## What This Demo Deploys

1. A resource group and AKS cluster with Static Egress Gateway enabled.
2. A dedicated gateway node pool (`gateway`) in `gateway` mode.
3. A `StaticGatewayConfiguration` custom resource bound to that gateway node pool.
4. A sample deployment (`egress-sample`) that routes outbound traffic through the gateway.

## Quick Start

From the repo root, run:

```powershell
./setup.ps1
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
kubectl describe StaticGatewayConfiguration gateway-config -n default
```

Get sample pod and verify egress IP:

```powershell
$pod = kubectl get pod -l app=egress-sample -o jsonpath="{.items[0].metadata.name}"
kubectl exec $pod -- curl -s https://ifconfig.me
```

The returned IP should match the egress IP/prefix shown on the gateway configuration status.

## Notes and Limitations

- Pods can use a `StaticGatewayConfiguration` only if they are in the same namespace as that configuration.
- Gateway node pools should be dedicated to egress traffic.
- Host-network pods cannot be annotated to use the gateway.
- Plan node count and prefix size together, because capacity is constrained by prefix size.

## Reference

- AKS Static Egress Gateway docs:
  `https://learn.microsoft.com/azure/aks/configure-static-egress-gateway`
