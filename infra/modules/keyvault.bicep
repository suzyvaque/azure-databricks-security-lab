param location string
param prefix string
param tags object
param databricksServicePrincipalObjectId string

@description('Trusted-services firewall bypass. None is the required lab posture; AzureServices is used only for the documented control experiment.')
@allowed([
  'None'
  'AzureServices'
])
param bypass string = 'None'

var keyNameValue = 'cmk-managed-services'
// Key Vault Crypto Service Encryption User
var cryptoServiceEncryptionUserRoleId = 'e147488a-f6f5-4113-8e2d-b22465e65bf6'

resource law 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: 'law-${prefix}'
  location: location
  tags: tags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: 30
  }
}

// Public access disabled and trusted-services bypass None from creation.
resource vault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: 'kv${uniqueString(resourceGroup().id, prefix)}'
  location: location
  tags: tags
  properties: {
    tenantId: subscription().tenantId
    sku: {
      family: 'A'
      name: 'standard'
    }
    enableRbacAuthorization: true
    enableSoftDelete: true
    softDeleteRetentionInDays: 7
    enablePurgeProtection: true
    publicNetworkAccess: 'Disabled'
    networkAcls: {
      defaultAction: 'Deny'
      bypass: bypass
      ipRules: []
      virtualNetworkRules: []
    }
  }
}

// The key is NOT created here: with public access disabled and bypass None, even ARM key
// creation is rejected (ForbiddenByConnection). Create it from a private-path client after the PEs exist.
// Role is scoped to the vault, which holds only the single CMK key.
resource cryptoRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(vault.id, databricksServicePrincipalObjectId, cryptoServiceEncryptionUserRoleId)
  scope: vault
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', cryptoServiceEncryptionUserRoleId)
    principalId: databricksServicePrincipalObjectId
    principalType: 'ServicePrincipal'
  }
}

resource audit 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'audit-to-law'
  scope: vault
  properties: {
    workspaceId: law.id
    logAnalyticsDestinationType: 'Dedicated'
    logs: [
      {
        category: 'AuditEvent'
        enabled: true
      }
    ]
  }
}

output vaultId string = vault.id
output vaultName string = vault.name
output vaultUri string = vault.properties.vaultUri
output keyName string = keyNameValue
output lawName string = law.name
