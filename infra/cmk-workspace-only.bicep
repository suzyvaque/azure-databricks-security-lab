// Targeted CMK update: intentionally does not redeploy the tagged vault or any network resources.
param workspaceName string
param location string
param tags object
param managedResourceGroupId string
param workspaceParameters object
param keyVaultUri string
param keyName string
param keyVersion string

resource workspace 'Microsoft.Databricks/workspaces@2024-05-01' = {
  name: workspaceName
  location: location
  tags: tags
  sku: {
    name: 'premium'
  }
  properties: {
    managedResourceGroupId: managedResourceGroupId
    parameters: workspaceParameters
    publicNetworkAccess: 'Disabled'
    requiredNsgRules: 'NoAzureDatabricksRules'
    encryption: {
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
  }
}