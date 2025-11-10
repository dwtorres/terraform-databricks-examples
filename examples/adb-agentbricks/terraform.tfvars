# Azure Configuration
subscription_id = "f7fc048e-aeec-4c24-8436-cab0c3b48401"
location        = "eastus2"

# Network Configuration - Your Allocated CIDR
cidr = "10.70.80.0/20"

# Resource Group Configuration (Using existing RG)
create_resource_group        = false
existing_resource_group_name = "rg-eastus2-edp-poc"

# Managed Resource Group Naming (Clear ownership)
managed_resource_group_name = "databricks-rg-eastus2-edp-poc"

# Workspace Naming
workspace_prefix = "agentbricks"
dbfs_prefix      = "dbfsagent"
environment      = "PoC"

# Security Features (Enhanced from production infrastructure)
enable_infrastructure_encryption = true
enable_dbfs_firewall            = true
enable_no_public_ip             = true
create_storage_dfs_endpoint     = true
create_keyvault_endpoint        = false
