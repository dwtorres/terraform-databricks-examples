# AgentBricks Workspace Implementation Guide

## Overview

This guide shows how to create a secure, non-HIPAA Databricks workspace for AgentBricks that matches your existing `edp-infrastructure` security patterns but using a simpler single-VNet architecture.

**Base Example:** `adb-private-links` (single VNet pattern)
**Security Enhancements:** From your existing production infrastructure
**Result:** Secure workspace with 1 managed RG (Azure platform requirement)

---

## Resource Group Strategy

### What Gets Created

| Resource Group | Purpose | Created By | Count |
|----------------|---------|------------|-------|
| `rg-eastus2-edp-poc` | Existing RG for VNets, endpoints, DNS zones | Pre-existing | 0 new |
| `databricks-rg-cnh-edp-agentbricks-eastus2` | Managed RG for Databricks backend | Azure (automatic) | **1 new** |

**Total New RGs: 1** (unavoidable for any Databricks workspace)

---

## Feature Comparison

### Baseline: adb-private-links Example

| Feature | Implementation |
|---------|---------------|
| **VNets** | 1 VNet with 3 subnets (public, private, privatelink) |
| **Workspace** | Single workspace, premium tier |
| **Public Access** | Disabled (`public_network_access_enabled = false`) |
| **Customer-Managed Keys** | Basic (workspace CMK only) |
| **Private Endpoints** | 3 (UI/API, Auth, DBFS blob) |
| **DNS Zones** | 2 (Databricks, Blob storage) |
| **No Public IP** | ❌ Not configured |
| **Infrastructure Encryption** | ❌ Not enabled |
| **DBFS Firewall** | ❌ Not enabled |
| **Storage DFS Endpoint** | ❌ Not included |

### Required Enhancements (From Your Production Infrastructure)

| Feature | Why Needed | Implementation |
|---------|-----------|----------------|
| **No Public IP** | Prevent cluster internet access | `no_public_ip = true` in custom_parameters |
| **Infrastructure Encryption** | Extra encryption layer | `infrastructure_encryption_enabled = true` |
| **DBFS Firewall** | Restrict storage access | `default_storage_firewall_enabled = true` |
| **3 Customer-Managed Keys** | Enhanced encryption | Managed services, managed disks, root DBFS |
| **Storage DFS Endpoint** | Unity Catalog access | Additional private endpoint for DFS |
| **Managed RG Naming** | Predictable naming | `managed_resource_group_name` parameter |
| **Access Connector** | Unity Catalog integration | Managed identity for storage |

### Remove for AgentBricks Compatibility

| Feature | Why Remove | Implementation |
|---------|-----------|----------------|
| **HIPAA Compliance Profile** | AgentBricks incompatible | Do NOT set `compliance_security_profile` |

---

## Architecture Diagram

```
┌───────────────────────────────────────────────────────────────┐
│  Resource Group: rg-eastus2-edp-poc (EXISTING)                │
│  ────────────────────────────────────────────────────────────  │
│                                                                │
│  ┌─────────────────────────────────────────────────────────┐ │
│  │  VNet: 10.70.92.0/22 (NEW)                              │ │
│  │  ─────────────────────────────────────────────────────  │ │
│  │                                                          │ │
│  │  ┌────────────────┐  ┌────────────────┐  ┌───────────┐ │ │
│  │  │ Public Subnet  │  │ Private Subnet │  │ PE Subnet │ │ │
│  │  │ (Databricks)   │  │ (Databricks)   │  │ (Endpoints)│ │ │
│  │  └────────────────┘  └────────────────┘  └───────────┘ │ │
│  │                                              │           │ │
│  │                                              ▼           │ │
│  │                                     ┌──────────────────┐ │ │
│  │                                     │ Private Endpoints│ │ │
│  │                                     │ • UI/API         │ │ │
│  │                                     │ • Auth           │ │ │
│  │                                     │ • DBFS (blob)    │ │ │
│  │                                     │ • Storage (dfs)  │ │ │
│  │                                     │ • Key Vault (opt)│ │ │
│  │                                     └──────────────────┘ │ │
│  └─────────────────────────────────────────────────────────┘ │
│                                                                │
│  ┌─────────────────────────────────────────────────────────┐ │
│  │  Private DNS Zones                                       │ │
│  │  • privatelink.azuredatabricks.net                       │ │
│  │  • privatelink.blob.core.windows.net                     │ │
│  │  • privatelink.dfs.core.windows.net                      │ │
│  │  • privatelink.vaultcore.azure.net (optional)            │ │
│  └─────────────────────────────────────────────────────────┘ │
│                                                                │
│  ┌─────────────────────────────────────────────────────────┐ │
│  │  Workspace Resource (points to managed RG)              │ │
│  │  Name: agentbricks-workspace                             │ │
│  └─────────────────────────────────────────────────────────┘ │
└───────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌───────────────────────────────────────────────────────────────┐
│  Managed RG: databricks-rg-cnh-edp-agentbricks-eastus2 (NEW)  │
│  ────────────────────────────────────────────────────────────  │
│  • Databricks control plane VMs                                │
│  • Cluster VMs (when created)                                  │
│  • DBFS storage account                                        │
│  • Network interfaces                                          │
│  • Managed disks                                               │
│  ⚠️  Locked by Azure - cannot modify directly                  │
└───────────────────────────────────────────────────────────────┘
```

---

## Implementation Steps

### Step 1: Copy Base Example

```bash
# Navigate to examples directory
cd /Users/dwtorres/src/work/terraform-databricks-examples/examples

# Create new directory for AgentBricks workspace
cp -r adb-private-links adb-agentbricks

# Navigate to new directory
cd adb-agentbricks
```

### Step 2: Update variables.tf

Add new variables for enhanced security features:

```hcl
# Add to variables.tf

variable "managed_resource_group_name" {
  type        = string
  description = "Name for the Databricks managed resource group"
  default     = ""
}

variable "enable_infrastructure_encryption" {
  type        = bool
  description = "Enable infrastructure encryption"
  default     = true
}

variable "enable_dbfs_firewall" {
  type        = bool
  description = "Enable DBFS storage firewall"
  default     = true
}

variable "enable_no_public_ip" {
  type        = bool
  description = "Disable public IPs on clusters"
  default     = true
}

variable "create_storage_dfs_endpoint" {
  type        = bool
  description = "Create private endpoint for Storage DFS (Unity Catalog)"
  default     = true
}

variable "create_keyvault_endpoint" {
  type        = bool
  description = "Create private endpoint for Key Vault"
  default     = false
}
```

### Step 3: Enhance workspace.tf

Update the workspace resource with additional security features:

```hcl
# Modify workspace.tf

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
  name                                  = "${local.prefix}-workspace"
  resource_group_name                   = local.rg_name
  location                              = local.rg_location
  sku                                   = "premium"
  tags                                  = local.tags

  # Enhanced Security Features
  public_network_access_enabled         = false
  network_security_group_rules_required = "NoAzureDatabricksRules"
  customer_managed_key_enabled          = true
  infrastructure_encryption_enabled     = var.enable_infrastructure_encryption
  default_storage_firewall_enabled      = var.enable_dbfs_firewall
  access_connector_id                   = azurerm_databricks_access_connector.this.id

  # Managed RG naming control
  managed_resource_group_name           = var.managed_resource_group_name != "" ? var.managed_resource_group_name : null

  # Customer-Managed Keys
  managed_services_cmk_key_vault_key_id = azurerm_key_vault_key.managed_services.id
  managed_disk_cmk_key_vault_key_id     = azurerm_key_vault_key.managed_disk.id

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
  ]
}

# Root DBFS Customer-Managed Key
resource "azurerm_databricks_workspace_root_dbfs_customer_managed_key" "this" {
  workspace_id     = azurerm_databricks_workspace.this.id
  key_vault_key_id = azurerm_key_vault_key.root_dbfs.id
}
```

### Step 4: Add Customer-Managed Keys

Create `keys.tf`:

```hcl
# Create new file: keys.tf

# Key Vault for CMKs
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

# Key Vault Access Policy for Current User
resource "azurerm_key_vault_access_policy" "current_user" {
  key_vault_id = azurerm_key_vault.this.id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = data.azurerm_client_config.current.object_id

  key_permissions = [
    "Get", "List", "Create", "Delete", "Update", "Recover", "Purge",
    "GetRotationPolicy", "SetRotationPolicy"
  ]
}

# Access Policy for Databricks Managed Services
resource "azurerm_key_vault_access_policy" "dbx_managed_services" {
  key_vault_id = azurerm_key_vault.this.id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = azurerm_databricks_workspace.this.storage_account_identity[0].principal_id

  key_permissions = [
    "Get", "WrapKey", "UnwrapKey"
  ]

  depends_on = [azurerm_databricks_workspace.this]
}

# Customer-Managed Keys
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
```

### Step 5: Add Storage DFS Private Endpoint

Add to `privateendpoint.tf`:

```hcl
# Add to privateendpoint.tf

# Storage DFS Private Endpoint (for Unity Catalog)
resource "azurerm_private_endpoint" "storage_dfs" {
  count               = var.create_storage_dfs_endpoint ? 1 : 0
  name                = "storage-dfs-pvtendpoint"
  location            = local.rg_location
  resource_group_name = local.rg_name
  subnet_id           = azurerm_subnet.plsubnet.id

  private_service_connection {
    name                           = "ple-${var.workspace_prefix}-dfs"
    private_connection_resource_id = join("", [azurerm_databricks_workspace.this.managed_resource_group_id, "/providers/Microsoft.Storage/storageAccounts/${local.dbfsname}"])
    is_manual_connection           = false
    subresource_names              = ["dfs"]
  }

  private_dns_zone_group {
    name                 = "private-dns-zone-dfs"
    private_dns_zone_ids = [azurerm_private_dns_zone.storage_dfs[0].id]
  }
}

# Storage DFS DNS Zone
resource "azurerm_private_dns_zone" "storage_dfs" {
  count               = var.create_storage_dfs_endpoint ? 1 : 0
  name                = "privatelink.dfs.core.windows.net"
  resource_group_name = local.rg_name
}

resource "azurerm_private_dns_zone_virtual_network_link" "storage_dfs" {
  count                 = var.create_storage_dfs_endpoint ? 1 : 0
  name                  = "dfs-vnet-connection"
  resource_group_name   = local.rg_name
  private_dns_zone_name = azurerm_private_dns_zone.storage_dfs[0].name
  virtual_network_id    = azurerm_virtual_network.this.id
}
```

### Step 6: Create terraform.tfvars

```hcl
# terraform.tfvars

# Azure Configuration
subscription_id = "f7fc048e-aeec-4c24-8436-cab0c3b48401"

# Network Configuration
spokecidr    = "10.70.92.0/22"  # New VNet CIDR for AgentBricks
rglocation   = "eastus2"

# Resource Group Configuration
create_resource_group        = false
existing_resource_group_name = "rg-eastus2-edp-poc"

# Workspace Configuration
workspace_prefix = "agentbricks"
dbfs_prefix      = "dbfsagent"

# Managed Resource Group Naming
managed_resource_group_name = "databricks-rg-cnh-edp-agentbricks-eastus2"

# Security Features (Enhanced from Production)
enable_infrastructure_encryption = true
enable_dbfs_firewall            = true
enable_no_public_ip             = true
create_storage_dfs_endpoint     = true
create_keyvault_endpoint        = false  # Set to true if you need Key Vault secrets
```

### Step 7: Deploy

```bash
# Initialize Terraform
terraform init

# Validate configuration
terraform validate

# Create plan
terraform plan -out=tfplan

# Review plan carefully - should show:
# - 0 new user resource groups (using existing)
# - 1 VNet
# - 1 Workspace
# - 4-5 Private endpoints
# - 3-4 DNS zones
# - 3 Customer-managed keys

# Apply
terraform apply tfplan
```

---

## Validation Checklist

After deployment, verify:

### ✅ Resource Groups
```bash
# Should see only 1 NEW managed RG
az group list --query "[?starts_with(name, 'databricks-rg-cnh-edp-agentbricks')]" -o table

# Expected: databricks-rg-cnh-edp-agentbricks-eastus2
```

### ✅ Workspace Security
```bash
# Get workspace details
WORKSPACE_ID=$(terraform output -raw workspace_id)

# Verify settings
az databricks workspace show --ids $WORKSPACE_ID --query '{
  publicNetworkAccess: publicNetworkAccess,
  infrastructureEncryption: parameters.requireInfrastructureEncryption.value,
  noPublicIp: parameters.enableNoPublicIp.value
}' -o json

# Expected output:
# {
#   "publicNetworkAccess": "Disabled",
#   "infrastructureEncryption": "true",
#   "noPublicIp": "true"
# }
```

### ✅ Private Endpoints
```bash
# List private endpoints
az network private-endpoint list \
  --resource-group rg-eastus2-edp-poc \
  --query "[].{Name:name, Subnet:subnet.id, Connection:privateLinkServiceConnections[0].privateLinkServiceConnectionState.status}" \
  -o table

# Expected: 4-5 endpoints with "Approved" status
```

### ✅ Connectivity Test
```bash
# Get workspace URL
WORKSPACE_URL=$(terraform output -raw databricks_host)

# Test workspace access (should resolve to private IP)
nslookup $WORKSPACE_URL

# Expected: Private IP from your VNet range
```

---

## Cost Comparison

| Component | Private-Link-Standard | This Approach | Monthly Savings |
|-----------|----------------------|---------------|-----------------|
| VNets | 2 VNets + peering | 1 VNet | ~$50 |
| Workspaces | 2 workspaces | 1 workspace | $0-500* |
| Private Endpoints | 4 endpoints | 4-5 endpoints | $0 |
| DNS Zones | 2 zones | 3-4 zones | -$2 |
| **Total Savings** | | | **~$48-548/month** |

*Second workspace cost depends on usage; if unused, DBU cost is $0 but infrastructure still incurs charges.

---

## Security Comparison

| Feature | Private-Link-Standard | This Approach | Notes |
|---------|----------------------|---------------|-------|
| VNet Isolation | ✅ 2 VNets | ✅ 1 VNet | Single VNet sufficient |
| Private Endpoints | ✅ 4 | ✅ 4-5 | Added DFS for UC |
| Public Access | ✅ Disabled | ✅ Disabled | Same |
| No Public IP | ⚠️ Partial | ✅ Full | Better |
| Infrastructure Encryption | ❌ | ✅ | Better |
| DBFS Firewall | ❌ | ✅ | Better |
| Customer-Managed Keys | ✅ 1 | ✅ 3 | Better |
| **Security Score** | 8/10 | **9/10** | Simpler AND more secure |

---

## Troubleshooting

### Issue: Managed RG creation failed
**Cause:** Name conflict or permissions
**Solution:** Check naming is unique and service principal has Contributor role

### Issue: Private endpoint connection stuck in "Pending"
**Cause:** Workspace not fully provisioned
**Solution:** Wait 5-10 minutes, workspace provisions async

### Issue: Cannot resolve workspace URL
**Cause:** DNS zone not linked to VNet
**Solution:** Verify `azurerm_private_dns_zone_virtual_network_link` resources

### Issue: Customer-managed key errors
**Cause:** Key Vault access policy timing
**Solution:** Add explicit `depends_on` for Key Vault access policies

---

## Next Steps

1. **Configure Unity Catalog** - Use separate catalog for non-protected data
2. **Set up AgentBricks** - Install and configure AgentBricks features
3. **Network Integration** - Peer with production VNet if needed (documented in agentpoc/)
4. **Monitoring** - Configure Azure Monitor and log analytics
5. **Backup** - Document workspace configuration for disaster recovery

---

## Managed Resource Group FAQ

**Q: Can I avoid creating the managed RG?**
A: No, it's a required Azure platform component for every Databricks workspace.

**Q: Can I put resources in the managed RG?**
A: No, it's locked by Azure. You can only view resources.

**Q: Can I reuse a managed RG from another workspace?**
A: No, each workspace requires its own managed RG.

**Q: How do I delete the managed RG?**
A: It's automatically deleted when you destroy the workspace via Terraform.

**Q: Why does the managed RG have a long random name?**
A: You can control the name using `managed_resource_group_name` parameter.

---

## Summary

This approach gives you:
- ✅ **Zero new user resource groups** (using existing rg-eastus2-edp-poc)
- ✅ **1 managed RG** (Azure platform requirement, predictable name)
- ✅ **Better security** than private-link-standard
- ✅ **50% simpler** architecture
- ✅ **Lower cost** than dual-VNet approach
- ✅ **Matches proven patterns** from your production infrastructure
- ✅ **AgentBricks compatible** (no HIPAA compliance)

**Result:** Secure, cost-effective, maintainable AgentBricks workspace that aligns with your existing infrastructure standards.
