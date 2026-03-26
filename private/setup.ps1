$group = "rg-aks-static-egress-private"
$vnet = "vnet"
$aksSubnet = "aks"
$vmSubnet = "vm"
$vmName = "jumpbox"
$vmNsg = "vmnsg"
$identity = "aksuser"
$cluster = "staticprivateegresscluster"
$location = "eastus2"
$gatewayPool = "gateway"
$prefixSize = 31
$nodeCount = 2

# get subscription ID
$subscriptionId = az account show --query id -o tsv

# create resource group
az group create -n $group -l $location

# create vnet with subnets
az network vnet create `
  --resource-group $group `
  --name $vnet `
  --address-prefix 192.168.0.0/16

# create AKS subnet
$aksSubnetId = az network vnet subnet create `
  --resource-group $group `
  --vnet-name $vnet `
  --name $aksSubnet `
  --address-prefixes 192.168.0.0/24 `
  --query id -o tsv

# create VMs subnet
$vmSubnetId = az network vnet subnet create `
  --resource-group $group `
  --vnet-name $vnet `
  --name $vmSubnet `
  --address-prefixes 192.168.1.0/24 `
  --query id -o tsv

# create egress node subnet
$egressSubnetId = az network vnet subnet create `
  --resource-group $group `
  --vnet-name $vnet `
  --name "egress" `
  --address-prefixes 192.168.2.0/24 `
  --query id -o tsv

# create a managed identity
$identityId = az identity create `
  --resource-group $group `
  --name $identity `
  -o tsv --query id

# get client ID of the identity
$identityClientId = az identity show `
  --resource-group $group `
  --name $identity `
  -o tsv --query clientId

# make identity contributor to the resource group
az role assignment create `
  --assignee $identityClientId `
  --role "Contributor" `
  --scope /subscriptions/$subscriptionId/resourceGroups/$group

# create aks cluster with static egress gateway enabled
az aks create -n $cluster -g $group `
  --node-count 1 `
  --enable-private-cluster `
  --enable-static-egress-gateway `
  --vnet-subnet-id $aksSubnetId `
  --assign-identity $identityId

# add a gateway node pool
az aks nodepool add --cluster-name $cluster -g $group `
  -n $gatewayPool `
  --mode gateway `
  --node-count $nodeCount `
  --gateway-prefix-size $prefixSize `
  --vnet-subnet-id $egressSubnetId

# get credentials
az aks get-credentials -n $cluster -g $group --overwrite-existing

# create public IP for the VM
$vmIp = az network public-ip create `
  --resource-group $group `
  --name "pip-$vmName" `
  --sku Standard `
  --allocation-method Static `
  --location $location `
  -o tsv --query publicIp.ipAddress

# create the ubuntu VM
az vm create `
  --resource-group $group `
  --name $vmName `
  --image "Ubuntu2204" `
  --size "Standard_D2s_v3" `
  --admin-username vmuser `
  --nsg $vmNsg `
  --nsg-rule SSH `
  --public-ip-address "pip-$vmName" `
  --subnet $vmSubnetId `
  --location $location `
  --assign-identity $identityId

"`nSSH: ssh vmuser@$vmIp"

# apply the static gateway configuration
#kubectl apply -f .\static-gateway-config.yaml