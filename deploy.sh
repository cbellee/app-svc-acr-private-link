RG_NAME='app-svc-acr-plink-rg'
LOCATION='australiaeast'
CONTAINER_IMAGE_NAME='go-web-api'
MY_EXTERNAL_IP=$(dig +short myip.opendns.com @resolver1.opendns.com)

# create resource group
az group create --name $RG_NAME --location $LOCATION

# create vnet
az deployment group create \
  --name vnetDeployment \
  --resource-group $RG_NAME \
  --template-file ./modules/vnet.bicep \
  --parameters @parameters.json

# create acr
az deployment group create \
  --name acrDeployment \
  --resource-group $RG_NAME \
  --template-file ./modules/acr.bicep \
  --parameters externalIp=$MY_EXTERNAL_IP \
  --parameters vnetId=$(az deployment group show --resource-group $RG_NAME --name vnetDeployment --query properties.outputs.vnetId.value --output tsv | tr -d '\r') \
  --parameters subnetId=$(az deployment group show --resource-group $RG_NAME --name vnetDeployment --query "[properties.outputs.subnetIds.value[?name=='ContainerRegistrySubnet'].id]" --output tsv | tr -d '\r')

DOCKER_REGISTRY_URL="https://${ACR_LOGIN_SERVER}"
ACR_ID=$(az deployment group show --resource-group $RG_NAME --name acrDeployment --query properties.outputs.acrId.value --output tsv | tr -d '\r')
ACR_LOGIN_SERVER=$(az deployment group show --resource-group $RG_NAME --name acrDeployment --query properties.outputs.acrLoginServer.value --output tsv | tr -d '\r')
ACR_NAME=$(az deployment group show --resource-group $RG_NAME --name acrDeployment --query properties.outputs.acrName.value --output tsv | tr -d '\r')
ACR_PASSWORD=$(az deployment group show --resource-group $RG_NAME --name acrDeployment --query properties.outputs.acrPassword.value -o tsv)

# upload container
docker login --username $ACR_NAME $ACR_LOGIN_SERVER --password $ACR_PASSWORD 
docker pull "belstarr/$CONTAINER_IMAGE_NAME:v1.0"
docker tag "belstarr/$CONTAINER_IMAGE_NAME:v1.0" "$ACR_LOGIN_SERVER/$CONTAINER_IMAGE_NAME:latest"
docker push "$ACR_LOGIN_SERVER/$CONTAINER_IMAGE_NAME:latest"

# deploy app service
az deployment group create \
  --name appSvcDeployment \
  --resource-group $RG_NAME \
  --template-file ./modules/appsvc.bicep \
  --parameters vnetId=$(az deployment group show --resource-group $RG_NAME --name vnetDeployment --query properties.outputs.vnetId.value -o tsv | tr -d '\r') \
  --parameters appSvcSubnetId=$(az deployment group show --resource-group $RG_NAME --name vnetDeployment --query "[properties.outputs.subnetIds.value[?name=='AppServiceIntegrationSubnet'].id]" -o tsv | tr -d '\r') \
  --parameters privateLinkSubnetId=$(az deployment group show --resource-group $RG_NAME --name vnetDeployment --query "[properties.outputs.subnetIds.value[?name=='PrivateLinkSubnet'].id]" -o tsv | tr -d '\r') \
  --parameters dockerRegistryUrl=$ACR_LOGIN_SERVER \
  --parameters acrUserName=$ACR_NAME \
  --parameters acrPassword=$ACR_PASSWORD \
  --parameters containerName="$ACR_LOGIN_SERVER/$CONTAINER_NAME:latest" \
  --verbose
