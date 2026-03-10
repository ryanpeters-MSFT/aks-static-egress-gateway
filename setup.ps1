$group       = "rg-aks-static-egress"
$cluster     = "staticegresscluster"
$location    = "eastus2"
$gatewayPool = "gateway"
$prefixSize  = 31
$nodeCount   = 2

# create resource group
az group create -n $group -l $location

# create aks cluster with static egress gateway enabled
az aks create -n $cluster -g $group -l $location `
  --enable-static-egress-gateway `
  --generate-ssh-keys

# get credentials
az aks get-credentials -n $cluster -g $group --overwrite-existing

# add a gateway node pool
az aks nodepool add --cluster-name $cluster -g $group `
  -n $gatewayPool `
  --mode gateway `
  --node-count $nodeCount `
  --gateway-prefix-size $prefixSize

# apply the static gateway configuration
kubectl apply -f .\static-gateway-config.yaml

# deploy a sample workload annotated to use the gateway
kubectl apply -f .\egress-sample-deployment.yaml

# verify the gateway configuration status
kubectl describe StaticGatewayConfiguration gateway-config -n default

# verify egress ip from the sample pod
$pod = kubectl get pod -l app=egress-sample -o jsonpath="{.items[0].metadata.name}"
kubectl exec $pod -- curl -s https://ifconfig.me