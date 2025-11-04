# Azure Databricks Private Link - Quick Deployment Guide

**Purpose:** Streamlined deployment guide for PoC environments
**Last Updated:** 2025-11-04
**Module Version:** 1.0.0 (with critical fixes applied)

---

## Overview

This guide provides a fast track to deploying Azure Databricks with Private Link in a PoC environment. For detailed operational procedures, refer to the comprehensive documentation listed below.

**Deployment Time:** ~30-45 minutes (plus 15-20 minutes validation)

---

## Essential Documentation Checklist

Read these documents in order for successful deployment:

### Must Read Before Deployment
1. ✅ **[README.md](README.md)** - Module overview and fixes summary
2. ✅ **[FIXES.md](FIXES.md)** - Critical issues resolved (MUST READ)
3. ✅ **THIS DOCUMENT** - Quick start deployment workflow

### Reference During Deployment
4. 📖 **[RUNBOOKS.md](RUNBOOKS.md)** - Detailed operational procedures
5. 📖 **[TESTING.md](TESTING.md)** - Post-deployment validation procedures

### Reference For Troubleshooting
6. 🔍 **[ARCHITECTURE.md](ARCHITECTURE.md)** - Network architecture and diagrams
7. 🔍 **[RUNBOOKS.md Section 2](RUNBOOKS.md#2-troubleshooting-guide)** - Troubleshooting procedures

---

## Pre-Flight Validation

**Run these commands before starting deployment to verify prerequisites:**

```bash
# 1. Verify Azure CLI authentication
az account show --output table
# Expected: Active subscription details

# 2. Verify Terraform installation
terraform version
# Expected: Terraform v1.0.0 or newer

# 3. Verify required permissions
az role assignment list \
  --assignee $(az account show --query user.name -o tsv) \
  --scope /subscriptions/$(az account show --query id -o tsv) \
  --query "[?roleDefinitionName=='Contributor' || roleDefinitionName=='Owner'].{Role:roleDefinitionName}" \
  --output table
# Expected: Contributor or Owner role

# 4. Check available quota for VMs
az vm list-usage --location southcentralus \
  --query "[?name.localizedValue=='Total Regional vCPUs'].{Resource:name.localizedValue, Current:currentValue, Limit:limit}" \
  --output table
# Expected: Sufficient vCPU quota (minimum 16 vCPUs)

# 5. Verify service principal (if using SPN authentication)
az login --service-principal \
  -u $ARM_CLIENT_ID \
  -p $ARM_CLIENT_SECRET \
  --tenant $ARM_TENANT_ID
# Expected: Successful authentication
```

**Pre-Flight Checklist:**
- [ ] Azure CLI authenticated (interactive or service principal)
- [ ] Terraform v1.0.0+ installed
- [ ] Contributor or Owner role on target subscription
- [ ] Sufficient regional vCPU quota (16+ vCPUs)
- [ ] `terraform.tfvars` file configured with deployment values

---

## 5-Step Deployment Workflow

### Step 1: Clone and Prepare

```bash
# Clone the repository
git clone https://github.com/dwtorres/terraform-databricks-examples.git
cd terraform-databricks-examples

# Checkout fix branch (contains all critical fixes)
git checkout fix/private-link-issues

# Navigate to deployment directory
cd modules/adb-with-private-link-standard
```

### Step 2: Configure Deployment

Create `terraform.tfvars` with your deployment-specific values:

```hcl
# Required Configuration
prefix                        = "mypocdemo"  # Must be unique (3-7 chars, lowercase)
location                      = "southcentralus"
spoke_resource_group_name     = "rg-databricks-poc"

# Network Configuration
spoke_vnet_address_space      = "10.180.0.0/20"
transit_vnet_address_space    = "10.181.0.0/20"
private_subnet_address_prefix = "10.180.0.0/24"
public_subnet_address_prefix  = "10.180.1.0/24"
storage_subnet_address_prefix = "10.180.2.0/24"
privateendpoint_subnet_address_prefix = "10.180.3.0/24"
transit_subnet_address_prefix = "10.181.0.0/24"
transit_privateendpoint_subnet_address_prefix = "10.181.1.0/24"

# Hub Configuration (for enterprise deployments)
hubcidr                       = "10.178.0.0/20"

# Optional: Tags
tags = {
  Environment = "PoC"
  Project     = "Databricks-PrivateLink"
  Owner       = "your-name"
}
```

### Step 3: Initialize and Plan

```bash
# Initialize Terraform
terraform init
# Expected: "Terraform has been successfully initialized!"

# Review deployment plan
terraform plan -out=tfplan
# Expected: "Plan: 45 to add, 0 to change, 0 to destroy"

# Review specific resource changes (optional)
terraform show tfplan | less
```

**Critical Resources to Verify in Plan:**
- ✅ 2 Databricks workspaces (Data Plane + Transit)
- ✅ 2 VNets with VNet peering (CRITICAL FIX #1)
- ✅ 5 Private endpoints (dpcp, blob, dfs, frontend, auth)
- ✅ 3 Private DNS zones with VNet links (CRITICAL FIX #2)
- ✅ 1 Windows Test VM

### Step 4: Deploy Infrastructure

```bash
# Apply deployment
terraform apply tfplan

# Deployment progress indicators:
# - VNet creation: ~2 minutes
# - Databricks workspaces: ~15-20 minutes
# - Private endpoints: ~5-8 minutes
# - Test VM: ~3-5 minutes
# Total: ~30-45 minutes

# Monitor deployment (in separate terminal)
watch -n 30 'terraform show | grep -A 2 "Apply complete"'
```

**Deployment Completion Indicators:**
```
Apply complete! Resources: 45 added, 0 changed, 0 destroyed.

Outputs:
workspace_id = "2003219232620501"
workspace_url = "https://adb-2003219232620501.1.azuredatabricks.net/"
test_vm_public_ip = "x.x.x.x"
dbfs_storage_name = "{prefix}storage{random}"
```

### Step 5: Extract Deployment Values

**IMPORTANT:** Run these commands immediately after deployment to populate values for testing and validation:

```bash
# Extract and set all deployment values (from RUNBOOKS.md Section 1.3)
export PREFIX=$(terraform output -raw prefix 2>/dev/null || echo "mypocdemo")
export WORKSPACE_ID=$(terraform output -raw workspace_id)
export WORKSPACE_NAME=$(terraform output -raw workspace_name 2>/dev/null || terraform output -raw dp_workspace_name)
export WORKSPACE_URL=$(terraform output -raw workspace_url)
export DP_RG_NAME=$(terraform output -raw dp_rg_name)
export TRANSIT_RG_NAME=$(terraform output -raw transit_rg_name)
export DP_VNET_NAME=$(terraform output -raw dp_vnet_name)
export TRANSIT_VNET_NAME=$(terraform output -raw transit_vnet_name)
export DBFS_NAME=$(terraform output -raw dbfs_storage_name)
export TEST_VM_IP=$(terraform output -raw test_vm_public_ip)
export TEST_VM_PASSWORD=$(terraform output -json test_vm_password | jq -r '.value')

# Display values for verification
echo "=== Deployment Values ==="
echo "WORKSPACE_ID: ${WORKSPACE_ID}"
echo "WORKSPACE_URL: ${WORKSPACE_URL}"
echo "TEST_VM_IP: ${TEST_VM_IP}"
echo "========================="

# Save values to file for later reference
cat > deployment_values.env <<EOF
export PREFIX="${PREFIX}"
export WORKSPACE_ID="${WORKSPACE_ID}"
export WORKSPACE_NAME="${WORKSPACE_NAME}"
export WORKSPACE_URL="${WORKSPACE_URL}"
export DP_RG_NAME="${DP_RG_NAME}"
export TRANSIT_RG_NAME="${TRANSIT_RG_NAME}"
export DP_VNET_NAME="${DP_VNET_NAME}"
export TRANSIT_VNET_NAME="${TRANSIT_VNET_NAME}"
export DBFS_NAME="${DBFS_NAME}"
export TEST_VM_IP="${TEST_VM_IP}"
export TEST_VM_PASSWORD="${TEST_VM_PASSWORD}"
EOF

echo "✅ Deployment values saved to deployment_values.env"
echo "   To reload: source deployment_values.env"
```

---

## Post-Deployment Validation Checklist

**Quick validation to verify deployment success:**

### 1. Infrastructure Validation

```bash
# Verify resource count
az resource list --resource-group ${DP_RG_NAME} --query "length([*])"
# Expected: ~30 resources in Data Plane RG

# Verify Databricks workspace provisioning
az databricks workspace show \
  --name ${WORKSPACE_NAME} \
  --resource-group ${DP_RG_NAME} \
  --query "{Name:name, State:provisioningState, PublicAccess:publicNetworkAccess}" \
  --output table
# Expected: State=Succeeded, PublicAccess=Disabled

# Verify VNet peering (CRITICAL FIX #1)
az network vnet peering list \
  --resource-group ${DP_RG_NAME} \
  --vnet-name ${DP_VNET_NAME} \
  --query "[].{Name:name, State:peeringState, RemoteVNet:remoteVirtualNetwork.id}" \
  --output table
# Expected: 1 peering with State=Connected

# Verify private endpoints
az network private-endpoint list \
  --resource-group ${DP_RG_NAME} \
  --query "[].{Name:name, ConnectionState:privateLinkServiceConnections[0].privateLinkServiceConnectionState.status}" \
  --output table
# Expected: 5 endpoints with ConnectionState=Approved
```

### 2. DNS Resolution Validation (from Test VM)

**Access Test VM:**
```bash
# Option 1: RDP from macOS
open rdp://azureuser:${TEST_VM_PASSWORD}@${TEST_VM_IP}

# Option 2: Azure Bastion (if configured)
az network bastion rdp \
  --name ${PREFIX}-bastion \
  --resource-group ${DP_RG_NAME} \
  --target-resource-id $(az vm show -g ${DP_RG_NAME} -n ${PREFIX}-testvm --query id -o tsv)
```

**Run DNS tests from Test VM PowerShell:**
```powershell
# Test workspace DNS resolution
nslookup adb-${env:WORKSPACE_ID}.1.azuredatabricks.net
# Expected: Resolves to 10.181.x.x (Transit VNet private IP)

# Test blob storage DNS resolution
nslookup ${env:DBFS_NAME}.blob.core.windows.net
# Expected: Resolves to 10.180.x.x (Data Plane VNet private IP)

# Test DFS storage DNS resolution
nslookup ${env:DBFS_NAME}.dfs.core.windows.net
# Expected: Resolves to 10.180.x.x (Data Plane VNet private IP)
```

**✅ Success Criteria:**
- All DNS names resolve to private IPs (10.x.x.x)
- No public IPs (20.x.x.x) in DNS responses
- Workspace accessible via browser from Test VM

### 3. Workspace Access Validation

From Test VM browser:
1. Navigate to workspace URL: `https://adb-${WORKSPACE_ID}.1.azuredatabricks.net/`
2. Sign in with Azure AD credentials
3. Verify workspace UI loads successfully
4. Create test cluster (Single Node, Standard_DS3_v2)
5. Create notebook and run simple command:
   ```python
   print(f"Workspace ID: {spark.conf.get('spark.databricks.clusterUsageTags.clusterId')}")
   dbutils.fs.ls("dbfs:/")
   ```

**✅ Success Criteria:**
- Workspace accessible via HTTPS
- Azure AD authentication successful
- Cluster creation succeeds
- DBFS storage accessible

---

## Troubleshooting Quick Links

If validation fails, consult these sections:

| Issue | Quick Reference | Detailed Guide |
|-------|----------------|----------------|
| **DNS resolves to public IPs** | [RUNBOOKS.md Section 2.2](RUNBOOKS.md#22-dns-resolution-issues) | [FIXES.md Issue #7](FIXES.md#issue-7-high-missing-storage-dns-vnet-links-for-transit-vnet) |
| **Workspace timeout/unreachable** | [RUNBOOKS.md Section 2.3](RUNBOOKS.md#23-workspace-connectivity-issues) | [FIXES.md Issue #8](FIXES.md#issue-8-critical-missing-vnet-peering-between-data-plane-and-transit-vnets) |
| **Deployment fails at 44/45** | [RUNBOOKS.md Section 2.4](RUNBOOKS.md#24-deployment-race-conditions) | [FIXES.md Issue #9](FIXES.md#issue-9-critical-race-condition-in-frontend-endpoint-creation) |
| **Terraform state issues** | [RUNBOOKS.md Section 2.1](RUNBOOKS.md#21-terraform-state-issues) | [FIXES.md Issue #5](FIXES.md#issue-5-high-incorrect-dns-zone-reference-pattern) |
| **Network connectivity** | [ARCHITECTURE.md Traffic Flow](ARCHITECTURE.md#4-traffic-flow-patterns) | [RUNBOOKS.md Section 2.3](RUNBOOKS.md#23-workspace-connectivity-issues) |

---

## Common Deployment Issues and Quick Fixes

### Issue: "Error creating VNet Peering"
**Cause:** Insufficient permissions or quota
**Fix:**
```bash
# Verify permissions
az role assignment list --assignee $(az account show --query user.name -o tsv) --query "[].roleDefinitionName"
# Ensure Contributor or Owner role
```

### Issue: "Workspace provisioning stuck"
**Cause:** Azure backend delays (normal)
**Fix:** Wait 20-25 minutes. Monitor with:
```bash
watch -n 30 'az databricks workspace show --name ${WORKSPACE_NAME} --resource-group ${DP_RG_NAME} --query provisioningState'
```

### Issue: "Test VM RDP connection refused"
**Cause:** NSG rule not configured for your IP
**Fix:**
```bash
# Update NSG rule with your public IP
MY_IP=$(curl -s ifconfig.me)
az network nsg rule update \
  --resource-group ${DP_RG_NAME} \
  --nsg-name ${PREFIX}-testvm-nsg \
  --name RDP \
  --source-address-prefixes "${MY_IP}/32"
```

---

## Clean Up (Destroy Deployment)

**⚠️ WARNING:** This will destroy ALL resources. Data will be permanently lost.

```bash
# Create destroy plan
terraform plan -destroy -out=tfplan-destroy

# Review what will be destroyed
terraform show tfplan-destroy

# Execute destruction
terraform apply tfplan-destroy

# Verify complete removal
az resource list --resource-group ${DP_RG_NAME}
# Expected: Empty list or "ResourceGroupNotFound"
```

**Destruction Time:** ~15-20 minutes

---

## Next Steps After Successful Deployment

1. **Security Hardening:** Review [RUNBOOKS.md Section 4](RUNBOOKS.md#4-disaster-recovery-procedures)
2. **Performance Testing:** Follow [TESTING.md Section 5](TESTING.md#5-performance-testing)
3. **Enterprise Integration:** Review [ARCHITECTURE.md Section 5](ARCHITECTURE.md#5-enterprise-integration-patterns)
4. **Operational Runbooks:** Familiarize with [RUNBOOKS.md](RUNBOOKS.md) for day-2 operations

---

## Support and Additional Resources

- **Comprehensive Runbooks:** [RUNBOOKS.md](RUNBOOKS.md)
- **Testing Procedures:** [TESTING.md](TESTING.md)
- **Architecture Details:** [ARCHITECTURE.md](ARCHITECTURE.md)
- **Known Issues:** [FIXES.md](FIXES.md)
- **Module README:** [README.md](README.md)

**Documentation Version:** 1.0.0
**Last Updated:** 2025-11-04
