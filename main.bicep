targetScope = 'subscription'

@description('Name of the resource group that will contain the static website storage account.')
param resourceGroupName string = 'b2b2carchitecture'

@description('Azure region for the resource group and storage account.')
param location string = 'westus'

@description('Globally unique storage account name. The default keeps the name deterministic per subscription and resource group.')
param storageAccountName string = 'b2b2carch${uniqueString(subscription().id, resourceGroupName)}'

resource siteResourceGroup 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: resourceGroupName
  location: location
}

module staticSiteStorage 'storage.bicep' = {
  name: 'static-site-storage'
  scope: siteResourceGroup
  params: {
    location: location
    storageAccountName: storageAccountName
  }
}

output resourceGroupName string = siteResourceGroup.name
output storageAccountName string = staticSiteStorage.outputs.storageAccountName
output storageAccountId string = staticSiteStorage.outputs.storageAccountId
