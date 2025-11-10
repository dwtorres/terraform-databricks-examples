resource "azurerm_key_vault" "this" {
  name                       = "${local.prefix}-kv"
  location                   = local.rg_location
  resource_group_name        = local.rg_name
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  sku_name                   = "premium"
  purge_protection_enabled   = true
  soft_delete_retention_days = 7

  tags = local.tags
}

resource "azurerm_key_vault_access_policy" "current_user" {
  key_vault_id = azurerm_key_vault.this.id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = data.azurerm_client_config.current.object_id

  key_permissions = [
    "Get", "List", "Create", "Delete", "Update", "Recover", "Purge",
    "GetRotationPolicy", "SetRotationPolicy"
  ]
}

resource "azurerm_key_vault_access_policy" "dbx_managed_services" {
  key_vault_id = azurerm_key_vault.this.id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = azurerm_databricks_workspace.this.storage_account_identity[0].principal_id

  key_permissions = [
    "Get", "WrapKey", "UnwrapKey"
  ]

  depends_on = [azurerm_databricks_workspace.this]
}

resource "azurerm_key_vault_key" "managed_services" {
  name         = "dbx-managed-services-key"
  key_vault_id = azurerm_key_vault.this.id
  key_type     = "RSA"
  key_size     = 2048

  key_opts = [
    "decrypt", "encrypt", "sign", "unwrapKey", "verify", "wrapKey"
  ]

  depends_on = [azurerm_key_vault_access_policy.current_user]
}

resource "azurerm_key_vault_key" "managed_disk" {
  name         = "dbx-managed-disk-key"
  key_vault_id = azurerm_key_vault.this.id
  key_type     = "RSA"
  key_size     = 2048

  key_opts = [
    "decrypt", "encrypt", "sign", "unwrapKey", "verify", "wrapKey"
  ]

  depends_on = [azurerm_key_vault_access_policy.current_user]
}

resource "azurerm_key_vault_key" "root_dbfs" {
  name         = "dbx-root-dbfs-key"
  key_vault_id = azurerm_key_vault.this.id
  key_type     = "RSA"
  key_size     = 2048

  key_opts = [
    "decrypt", "encrypt", "sign", "unwrapKey", "verify", "wrapKey"
  ]

  depends_on = [azurerm_key_vault_access_policy.current_user]
}
