# VNet Peering Configuration
# Fix for Issue #8: Missing VNet Peering between Data Plane and Transit VNets
# Severity: CRITICAL - Architecture is completely non-functional without this fix
#
# Without this peering:
# - DNS resolution works (zones linked to both VNets)
# - BUT no network route exists between VNets
# - Result: Workspace 100% unreachable despite successful Terraform deployment

resource "azurerm_virtual_network_peering" "dp_to_transit" {
  name                         = "${local.prefix}-dp-to-transit"
  resource_group_name          = local.dp_rg_name
  virtual_network_name         = azurerm_virtual_network.dp_vnet.name
  remote_virtual_network_id    = azurerm_virtual_network.transit_vnet.id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
}

resource "azurerm_virtual_network_peering" "transit_to_dp" {
  name                         = "${local.prefix}-transit-to-dp"
  resource_group_name          = local.transit_rg_name
  virtual_network_name         = azurerm_virtual_network.transit_vnet.name
  remote_virtual_network_id    = azurerm_virtual_network.dp_vnet.id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
}
