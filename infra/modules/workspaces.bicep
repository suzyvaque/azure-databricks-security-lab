param location string
param prefix string
param tags object
param workspaceVnetId string
param workspaceHostSubnetName string
param workspaceContainerSubnetName string
param authVnetId string
param authHostSubnetName string
param authContainerSubnetName string
param enableCmk bool
param keyVaultUri string
param keyName string
param keyVersion string

var cmkEncryption = {
  entities: {
    managedServices: {
      keySource: 'Microsoft.Keyvault'
      keyVaultProperties: {
        keyVaultUri: keyVaultUri
        keyName: keyName
        keyVersion: keyVersion
      }
    }
  }
}

// Target workspace: Premium, VNet injection, SCC, public access disabled from creation.
resource workspace 'Microsoft.Databricks/workspaces@2024-05-01' = {
  name: 'dbw-${prefix}'
  location: location
  tags: tags
  sku: {
    name: 'premium'
  }
  properties: {
    managedResourceGroupId: subscriptionResourceId('Microsoft.Resources/resourceGroups', 'rg-managed-${prefix}-ws')
    publicNetworkAccess: 'Disabled'
    requiredNsgRules: 'NoAzureDatabricksRules'
    parameters: {
      customVirtualNetworkId: {
        value: workspaceVnetId
      }
      customPublicSubnetName: {
        value: workspaceHostSubnetName
      }
      customPrivateSubnetName: {
        value: workspaceContainerSubnetName
      }
      enableNoPublicIp: {
        value: true
      }
    }
    encryption: enableCmk ? cmkEncryption : null
  }
}

// Isolated browser-authentication workspace: no compute, no other endpoints.
resource authWorkspace 'Microsoft.Databricks/workspaces@2024-05-01' = {
  name: 'dbw-${prefix}-auth'
  location: location
  tags: tags
  sku: {
    name: 'premium'
  }
  properties: {
    managedResourceGroupId: subscriptionResourceId('Microsoft.Resources/resourceGroups', 'rg-managed-${prefix}-auth')
    publicNetworkAccess: 'Disabled'
    requiredNsgRules: 'NoAzureDatabricksRules'
    parameters: {
      customVirtualNetworkId: {
        value: authVnetId
      }
      customPublicSubnetName: {
        value: authHostSubnetName
      }
      customPrivateSubnetName: {
        value: authContainerSubnetName
      }
      enableNoPublicIp: {
        value: true
      }
    }
  }
}

output workspaceId string = workspace.id
output workspaceName string = workspace.name
output authWorkspaceId string = authWorkspace.id
output authWorkspaceName string = authWorkspace.name
