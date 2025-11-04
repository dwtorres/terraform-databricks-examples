resource "azurerm_private_dns_zone" "dnsdpcp" {
  name                = "privatelink.azuredatabricks.net"
  resource_group_name = local.dp_rg_name
}

resource "azurerm_private_dns_zone_virtual_network_link" "dpcpdnszonevnetlink" {
  name                  = "dpcpspokevnetconnection"
  resource_group_name   = local.dp_rg_name
  private_dns_zone_name = azurerm_private_dns_zone.dnsdpcp.name
  virtual_network_id    = azurerm_virtual_network.dp_vnet.id
}

resource "azurerm_private_dns_zone" "dnsdbfs_dfs" {
  name                = "privatelink.dfs.core.windows.net"
  resource_group_name = local.dp_rg_name
}

resource "azurerm_private_dns_zone" "dnsdbfs_blob" {
  name                = "privatelink.blob.core.windows.net"
  resource_group_name = local.dp_rg_name
}

resource "azurerm_private_dns_zone_virtual_network_link" "dbfsdnszonevnetlink_dfs" {
  name                  = "dbfsspokevnetconnection-dfs"
  resource_group_name   = local.dp_rg_name
  private_dns_zone_name = azurerm_private_dns_zone.dnsdbfs_dfs.name
  virtual_network_id    = azurerm_virtual_network.dp_vnet.id
}

resource "azurerm_private_dns_zone_virtual_network_link" "dbfsdnszonevnetlink_blob" {
  name                  = "dbfsspokevnetconnection-blob"
  resource_group_name   = local.dp_rg_name
  private_dns_zone_name = azurerm_private_dns_zone.dnsdbfs_blob.name
  virtual_network_id    = azurerm_virtual_network.dp_vnet.id
}

# Priority 2 Fix (Issue #7): Add Transit VNet links for storage DNS zones
# Without these links, storage endpoints resolve to public IPs from Transit VNet
# causing workspace timeouts when accessed from Test VM

resource "azurerm_private_dns_zone_virtual_network_link" "dbfsdnszonevnetlink_dfs_transit" {
  name                  = "dfsspokevnetconnection-transit"
  resource_group_name   = local.dp_rg_name
  private_dns_zone_name = azurerm_private_dns_zone.dnsdbfs_dfs.name
  virtual_network_id    = azurerm_virtual_network.transit_vnet.id

  tags = local.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "dbfsdnszonevnetlink_blob_transit" {
  name                  = "blobspokevnetconnection-transit"
  resource_group_name   = local.dp_rg_name
  private_dns_zone_name = azurerm_private_dns_zone.dnsdbfs_blob.name
  virtual_network_id    = azurerm_virtual_network.transit_vnet.id

  tags = local.tags
}

