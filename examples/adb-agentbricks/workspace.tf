resource "azurerm_databricks_access_connector" "this" {
  name                = "${local.prefix}-access-connector"
  resource_group_name = local.rg_name
  location            = local.rg_location

  identity {
    type = "SystemAssigned"
  }

  tags = local.tags
}

resource "azurerm_databricks_workspace" "this" {
  name                = "${local.prefix}-workspace"
  resource_group_name = local.rg_name
  location            = local.rg_location
  sku                 = "premium"
  tags                = local.tags

  # Enhanced Security Features (from production infrastructure)
  public_network_access_enabled         = false
  network_security_group_rules_required = "NoAzureDatabricksRules"
  # TEMPORARILY DISABLED: Requires Key Vault permissions
  # customer_managed_key_enabled          = true
  infrastructure_encryption_enabled     = var.enable_infrastructure_encryption
  default_storage_firewall_enabled      = var.enable_dbfs_firewall
  access_connector_id                   = azurerm_databricks_access_connector.this.id

  # Managed RG naming control
  managed_resource_group_name = var.managed_resource_group_name != "" ? var.managed_resource_group_name : null

  # TEMPORARILY DISABLED: Customer-Managed Keys require Key Vault
  # managed_services_cmk_key_vault_key_id = azurerm_key_vault_key.managed_services.id
  # managed_disk_cmk_key_vault_key_id     = azurerm_key_vault_key.managed_disk.id

  custom_parameters {
    virtual_network_id                                   = azurerm_virtual_network.this.id
    private_subnet_name                                  = azurerm_subnet.private.name
    public_subnet_name                                   = azurerm_subnet.public.name
    public_subnet_network_security_group_association_id  = azurerm_subnet_network_security_group_association.public.id
    private_subnet_network_security_group_association_id = azurerm_subnet_network_security_group_association.private.id
    storage_account_name                                 = local.dbfsname
    no_public_ip                                         = var.enable_no_public_ip
  }

  depends_on = [
    azurerm_subnet_network_security_group_association.public,
    azurerm_subnet_network_security_group_association.private
    # TEMPORARILY DISABLED: Key Vault dependency
    # azurerm_key_vault_access_policy.current_user
  ]
}

# TEMPORARILY DISABLED: Root DBFS Customer-Managed Key requires Key Vault
# resource "azurerm_databricks_workspace_root_dbfs_customer_managed_key" "this" {
#   workspace_id     = azurerm_databricks_workspace.this.id
#   key_vault_key_id = azurerm_key_vault_key.root_dbfs.id
#
#   depends_on = [
#     azurerm_key_vault_access_policy.dbx_managed_services
#   ]
# }
