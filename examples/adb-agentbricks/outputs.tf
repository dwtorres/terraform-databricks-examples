output "workspace_id" {
  description = "The ID of the Databricks workspace"
  value       = azurerm_databricks_workspace.this.id
}

output "workspace_url" {
  description = "The workspace URL for accessing Databricks"
  value       = "https://${azurerm_databricks_workspace.this.workspace_url}/"
}

output "databricks_host" {
  description = "The workspace host (without https://)"
  value       = azurerm_databricks_workspace.this.workspace_url
}

output "workspace_name" {
  description = "The name of the Databricks workspace"
  value       = azurerm_databricks_workspace.this.name
}

output "managed_resource_group_id" {
  description = "The ID of the managed resource group created by Azure"
  value       = azurerm_databricks_workspace.this.managed_resource_group_id
}

output "managed_resource_group_name" {
  description = "The name of the managed resource group created by Azure"
  value       = split("/", azurerm_databricks_workspace.this.managed_resource_group_id)[4]
}

output "vnet_id" {
  description = "The ID of the VNet"
  value       = azurerm_virtual_network.this.id
}

output "vnet_cidr" {
  description = "The CIDR range of the VNet"
  value       = var.cidr
}

output "access_connector_id" {
  description = "The ID of the Databricks access connector for Unity Catalog"
  value       = azurerm_databricks_access_connector.this.id
}

# TEMPORARILY DISABLED: Key Vault outputs require Key Vault resources
# output "key_vault_id" {
#   description = "The ID of the Key Vault"
#   value       = azurerm_key_vault.this.id
# }
#
# output "key_vault_uri" {
#   description = "The URI of the Key Vault"
#   value       = azurerm_key_vault.this.vault_uri
# }
