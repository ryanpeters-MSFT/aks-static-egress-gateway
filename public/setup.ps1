$group = "rg-aks-static-egress"
$cluster = "staticegresscluster"
$location = "eastus2"
$gatewayPool = "gateway"
$prefixSize = 31
$nodeCount = 2

# create resource group
az group create -n $group -l $location

# create aks cluster with static egress gateway enabled
az aks create -n $cluster -g $group `
  --node-count 1 `
  --enable-static-egress-gateway `
  --generate-ssh-keys

# add a gateway node pool
az aks nodepool add --cluster-name $cluster -g $group `
  -n $gatewayPool `
  --mode gateway `
  --node-count $nodeCount `
  --gateway-prefix-size $prefixSize

# get credentials
az aks get-credentials -n $cluster -g $group --overwrite-existing

# apply the static gateway configuration
kubectl apply -f .\static-gateway-config.yaml