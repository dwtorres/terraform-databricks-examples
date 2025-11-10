# Databricks UI/API Private Endpoint
resource "azurerm_private_endpoint" "databricks_ui_api" {
  name                = "${local.prefix}-pe-databricks-uiapi"
  location            = local.rg_location
  resource_group_name = local.rg_name
  subnet_id           = azurerm_subnet.plsubnet.id

  private_service_connection {
    name                           = "psc-${local.prefix}-databricks-uiapi"
    private_connection_resource_id = azurerm_databricks_workspace.this.id
    is_manual_connection           = false
    subresource_names              = ["databricks_ui_api"]
  }

  private_dns_zone_group {
    name                 = "private-dns-zone-databricks"
    private_dns_zone_ids = [azurerm_private_dns_zone.databricks.id]
  }

  tags = local.tags
}

# Databricks DNS Zone
resource "azurerm_private_dns_zone" "databricks" {
  name                = "privatelink.azuredatabricks.net"
  resource_group_name = local.rg_name
  tags                = local.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "databricks" {
  name                  = "${local.prefix}-databricks-vnet-link"
  resource_group_name   = local.rg_name
  private_dns_zone_name = azurerm_private_dns_zone.databricks.name
  virtual_network_id    = azurerm_virtual_network.this.id
  tags                  = local.tags
}

# Databricks Browser Authentication Private Endpoint
resource "azurerm_private_endpoint" "databricks_auth" {
  name                = "${local.prefix}-pe-databricks-auth"
  location            = local.rg_location
  resource_group_name = local.rg_name
  subnet_id           = azurerm_subnet.plsubnet.id

  private_service_connection {
    name                           = "psc-${local.prefix}-databricks-auth"
    private_connection_resource_id = azurerm_databricks_workspace.this.id
    is_manual_connection           = false
    subresource_names              = ["browser_authentication"]
  }

  private_dns_zone_group {
    name                 = "private-dns-zone-databricks-auth"
    private_dns_zone_ids = [azurerm_private_dns_zone.databricks.id]
  }

  tags = local.tags
}

# DBFS Blob Private Endpoint
resource "azurerm_private_endpoint" "dbfs_blob" {
  name                = "${local.prefix}-pe-dbfs-blob"
  location            = local.rg_location
  resource_group_name = local.rg_name
  subnet_id           = azurerm_subnet.plsubnet.id

  private_service_connection {
    name                           = "psc-${local.prefix}-dbfs-blob"
    private_connection_resource_id = join("", [azurerm_databricks_workspace.this.managed_resource_group_id, "/providers/Microsoft.Storage/storageAccounts/${local.dbfsname}"])
    is_manual_connection           = false
    subresource_names              = ["blob"]
  }

  private_dns_zone_group {
    name                 = "private-dns-zone-blob"
    private_dns_zone_ids = [azurerm_private_dns_zone.storage_blob.id]
  }

  tags = local.tags

  depends_on = [azurerm_databricks_workspace.this]
}

# Storage Blob DNS Zone
resource "azurerm_private_dns_zone" "storage_blob" {
  name                = "privatelink.blob.core.windows.net"
  resource_group_name = local.rg_name
  tags                = local.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "storage_blob" {
  name                  = "${local.prefix}-blob-vnet-link"
  resource_group_name   = local.rg_name
  private_dns_zone_name = azurerm_private_dns_zone.storage_blob.name
  virtual_network_id    = azurerm_virtual_network.this.id
  tags                  = local.tags
}

# Storage DFS Private Endpoint (for Unity Catalog)
resource "azurerm_private_endpoint" "storage_dfs" {
  count               = var.create_storage_dfs_endpoint ? 1 : 0
  name                = "${local.prefix}-pe-storage-dfs"
  location            = local.rg_location
  resource_group_name = local.rg_name
  subnet_id           = azurerm_subnet.plsubnet.id

  private_service_connection {
    name                           = "psc-${local.prefix}-storage-dfs"
    private_connection_resource_id = join("", [azurerm_databricks_workspace.this.managed_resource_group_id, "/providers/Microsoft.Storage/storageAccounts/${local.dbfsname}"])
    is_manual_connection           = false
    subresource_names              = ["dfs"]
  }

  private_dns_zone_group {
    name                 = "private-dns-zone-dfs"
    private_dns_zone_ids = [azurerm_private_dns_zone.storage_dfs[0].id]
  }

  tags = local.tags

  depends_on = [azurerm_databricks_workspace.this]
}

# Storage DFS DNS Zone
resource "azurerm_private_dns_zone" "storage_dfs" {
  count               = var.create_storage_dfs_endpoint ? 1 : 0
  name                = "privatelink.dfs.core.windows.net"
  resource_group_name = local.rg_name
  tags                = local.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "storage_dfs" {
  count                 = var.create_storage_dfs_endpoint ? 1 : 0
  name                  = "${local.prefix}-dfs-vnet-link"
  resource_group_name   = local.rg_name
  private_dns_zone_name = azurerm_private_dns_zone.storage_dfs[0].name
  virtual_network_id    = azurerm_virtual_network.this.id
  tags                  = local.tags
}

# TEMPORARILY DISABLED: Key Vault Private Endpoint requires Key Vault resource
# # Key Vault Private Endpoint (optional)
# resource "azurerm_private_endpoint" "keyvault" {
#   count               = var.create_keyvault_endpoint ? 1 : 0
#   name                = "${local.prefix}-pe-keyvault"
#   location            = local.rg_location
#   resource_group_name = local.rg_name
#   subnet_id           = azurerm_subnet.plsubnet.id
#
#   private_service_connection {
#     name                           = "psc-${local.prefix}-keyvault"
#     private_connection_resource_id = azurerm_key_vault.this.id
#     is_manual_connection           = false
#     subresource_names              = ["vault"]
#   }
#
#   private_dns_zone_group {
#     name                 = "private-dns-zone-keyvault"
#     private_dns_zone_ids = [azurerm_private_dns_zone.keyvault[0].id]
#   }
#
#   tags = local.tags
# }
#
# # Key Vault DNS Zone
# resource "azurerm_private_dns_zone" "keyvault" {
#   count               = var.create_keyvault_endpoint ? 1 : 0
#   name                = "privatelink.vaultcore.azure.net"
#   resource_group_name = local.rg_name
#   tags                = local.tags
# }
#
# resource "azurerm_private_dns_zone_virtual_network_link" "keyvault" {
#   count                 = var.create_keyvault_endpoint ? 1 : 0
#   name                  = "${local.prefix}-keyvault-vnet-link"
#   resource_group_name   = local.rg_name
#   private_dns_zone_name = azurerm_private_dns_zone.keyvault[0].name
#   virtual_network_id    = azurerm_virtual_network.this.id
#   tags                  = local.tags
# }
