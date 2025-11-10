# Azure Configuration
subscription_id = "f7fc048e-aeec-4c24-8436-cab0c3b48401"
location        = "eastus2"

# Network Configuration (VNet-level CIDRs)
cidr_dp      = "10.70.80.0/21"
cidr_transit = "10.70.88.0/22"

# Resource Group Configuration (Using existing RG for both VNets)
create_data_plane_resource_group        = false
create_transit_resource_group           = false
existing_data_plane_resource_group_name = "rg-eastus2-edp-poc"
existing_transit_resource_group_name    = "rg-eastus2-edp-poc"
