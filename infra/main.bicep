// Azure Databricks private-only CMK PoC - resource-group scope.
// Region is locked to koreacentral. Deploy via scripts/deploy/Deploy-Poc.ps1.
targetScope = 'resourceGroup'

@description('Short lowercase run identifier used in names.')
@minLength(3)
@maxLength(8)
param runId string

@description('Region for all regional resources. Intentionally restricted.')
@allowed([
  'koreacentral'
])
param location string = 'koreacentral'

@description('CIDR of the new workspace VNet (/24). Must not overlap any peered network.')
param workspaceVnetCidr string

@description('CIDR of the new transit/auth VNet (/24). Must not overlap any peered network.')
param transitVnetCidr string

@description('Tenant-specific object ID of the AzureDatabricks enterprise application (appId 2ff814a6-3304-4ab8-85cb-cd0e6f879c1d).')
param databricksServicePrincipalObjectId string

@description('Key Vault trusted-services bypass. Defaults to None (the lab requirement).')
@allowed([
  'None'
  'AzureServices'
])
param vaultBypass string = 'None'

@description('Key Vault public network access. Defaults to Disabled (the lab requirement).')
@allowed([
  'Disabled'
  'Enabled'
])
param vaultPublicNetworkAccess string = 'Disabled'

@description('Public IPv4 addresses or CIDRs allowed through the vault firewall. Defaults to none.')
param vaultAllowedIps array = []

@description('Apply Managed Services CMK to the target workspace. False for the baseline stage.')
param enableCmk bool = false

@description('Exact key version (not latest). Required when enableCmk is true; the key is created from a private-path client.')
param keyVersion string = ''

@description('Existing VM subnet ID that receives a private endpoint for the vault (one IP). Empty disables it.')
param vmSubnetId string = ''

@description('Existing VM VNet ID linked to the vault-specific private DNS zone. Required with vmSubnetId.')
param vmVnetId string = ''

@description('Tags applied to every taggable resource.')
param tags object

var prefix = 'dbxcmk-krc-${runId}'

module network 'modules/network.bicep' = {
  name: 'network'
  params: {
    location: location
    prefix: prefix
    tags: tags
    workspaceVnetCidr: workspaceVnetCidr
    transitVnetCidr: transitVnetCidr
  }
}

module keyvault 'modules/keyvault.bicep' = {
  name: 'keyvault'
  params: {
    location: location
    prefix: prefix
    tags: tags
    databricksServicePrincipalObjectId: databricksServicePrincipalObjectId
    bypass: vaultBypass
    publicNetworkAccess: vaultPublicNetworkAccess
    allowedIps: vaultAllowedIps
  }
}

// Workspaces deploy only after the VNets, subnets, NSGs and NAT gateway exist.
module workspaces 'modules/workspaces.bicep' = {
  name: 'workspaces'
  params: {
    location: location
    prefix: prefix
    tags: tags
    workspaceVnetId: network.outputs.workspaceVnetId
    workspaceHostSubnetName: network.outputs.workspaceHostSubnetName
    workspaceContainerSubnetName: network.outputs.workspaceContainerSubnetName
    authVnetId: network.outputs.transitVnetId
    authHostSubnetName: network.outputs.authHostSubnetName
    authContainerSubnetName: network.outputs.authContainerSubnetName
    enableCmk: enableCmk
    keyVaultUri: keyvault.outputs.vaultUri
    keyName: keyvault.outputs.keyName
    keyVersion: keyVersion
  }
}

module privatelink 'modules/privatelink.bicep' = {
  name: 'privatelink'
  params: {
    location: location
    prefix: prefix
    tags: tags
    workspaceId: workspaces.outputs.workspaceId
    authWorkspaceId: workspaces.outputs.authWorkspaceId
    vaultId: keyvault.outputs.vaultId
    workspacePeSubnetId: network.outputs.workspacePeSubnetId
    transitPeSubnetId: network.outputs.transitPeSubnetId
    workspaceVnetId: network.outputs.workspaceVnetId
    transitVnetId: network.outputs.transitVnetId
  }
}

module vmAccess 'modules/vmaccess.bicep' = if (!empty(vmSubnetId)) {
  name: 'vmaccess'
  params: {
    location: location
    prefix: prefix
    tags: tags
    vaultId: keyvault.outputs.vaultId
    vaultName: keyvault.outputs.vaultName
    vmSubnetId: vmSubnetId
    vmVnetId: vmVnetId
  }
}

output workspaceName string = workspaces.outputs.workspaceName
output authWorkspaceName string = workspaces.outputs.authWorkspaceName
output vaultName string = keyvault.outputs.vaultName
output keyName string = keyvault.outputs.keyName
output workspaceVnetName string = network.outputs.workspaceVnetName
output transitVnetName string = network.outputs.transitVnetName
