# Transit VNet Link to Shared DNS Zone
# Fix for Issue #5: Reference shared DNS zone from private_dns_zone_dp.tf
# instead of creating redundant zone resource

resource "azurerm_private_dns_zone_virtual_network_link" "transitdnszonevnetlink" {
  name                  = "dpcpspokevnetconnection-transit"
  resource_group_name   = local.dp_rg_name
  private_dns_zone_name = azurerm_private_dns_zone.dnsdpcp.name
  virtual_network_id    = azurerm_virtual_network.transit_vnet.id
}