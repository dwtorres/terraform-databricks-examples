# Azure Databricks AgentBricks Deployment Runbook

**Date:** 2025-01-11
**Environment:** Bash/Unix (Azure Cloud Shell or local terminal)
**Purpose:** Deploy non-HIPAA AgentBricks workspace with enhanced security features

---

## ⚠️ IMPORTANT: AgentBricks Deployment Overview

**This workspace is specifically for AgentBricks - a non-HIPAA compatible AI agent framework.**

### What's Different from Standard Deployments?
- ✅ **Non-HIPAA:** AgentBricks requires non-HIPAA workspace (incompatible with HIPAA compliance)
- ✅ **Enhanced Security:** Production-grade security without HIPAA (encryption, CMK, private endpoints)
- ✅ **Single VNet:** Simplified architecture using one VNet instead of dual-VNet
- ✅ **Minimal RGs:** Uses existing RG for user resources, 1 managed RG (unavoidable)
- ✅ **Private Link:** Full private endpoint connectivity for workspace and storage

### When to Use This Deployment
- ✅ AgentBricks AI agent development
- ✅ Non-HIPAA data processing environments
- ✅ Secure but not HIPAA-regulated workloads
- ✅ Development and testing with production security patterns
- ❌ HIPAA-compliant workloads (use separate HIPAA workspace)
- ❌ Protected health information (PHI) processing

### Resource Group Strategy
**User Resources (Controllable):**
- **Existing RG:** rg-eastus2-edp-poc
- Contains: VNet, subnets, private endpoints, Key Vault, NSGs
- **Count:** 0 new user RGs created

**Managed Resources (Azure-Controlled):**
- **Managed RG:** databricks-rg-eastus2-edp-poc
- Contains: Databricks backend infrastructure (locked by Microsoft)
- **Count:** 1 managed RG (unavoidable, required by Azure platform)

**Total:** 1 new resource group (managed RG only)

---

## 🔑 IMPORTANT: Customer-Managed Keys Status

**Current Status:** Customer-Managed Keys (CMK) are **TEMPORARILY DISABLED** due to Key Vault permission requirements.

### What's Currently Disabled
- ❌ Azure Key Vault resource creation
- ❌ 3 customer-managed keys (managed services, managed disk, root DBFS)
- ❌ Key Vault private endpoint
- ❌ `customer_managed_key_enabled` workspace parameter

### What Still Works
- ✅ Databricks workspace deployment
- ✅ **Platform-managed encryption** (Microsoft manages keys automatically)
- ✅ Infrastructure encryption enabled
- ✅ DBFS firewall enabled
- ✅ Private endpoints for workspace, auth, blob, DFS
- ✅ No public IP for clusters
- ✅ All other security features

### Security Impact
**Encryption Status:**
- **Data at rest:** Encrypted with Microsoft platform-managed keys
- **Data in transit:** TLS encryption (unchanged)
- **Control:** Microsoft manages encryption keys instead of you
- **Compliance:** May not meet requirements if customer-managed keys are mandatory

### How to Re-Enable Customer-Managed Keys

**When you obtain Key Vault creation permissions:**

1. **Rename keys configuration back:**
   ```bash
   cd /Users/dwtorres/src/work/terraform-databricks-examples/examples/adb-agentbricks
   mv keys.tf.disabled keys.tf
   ```

2. **Uncomment workspace.tf CMK settings:**
   - Line 23-24: Uncomment `customer_managed_key_enabled = true`
   - Line 32-34: Uncomment `managed_services_cmk_key_vault_key_id` and `managed_disk_cmk_key_vault_key_id`
   - Line 50: Uncomment `azurerm_key_vault_access_policy.current_user` in depends_on
   - Lines 54-62: Uncomment entire `azurerm_databricks_workspace_root_dbfs_customer_managed_key` resource

3. **Uncomment outputs.tf Key Vault outputs:**
   - Lines 46-55: Uncomment `key_vault_id` and `key_vault_uri` outputs

4. **Uncomment privateendpoint.tf Key Vault endpoint (optional):**
   - Lines 141-180: Uncomment Key Vault private endpoint and DNS zone resources
   - Only if you want Key Vault accessible via private endpoint

5. **Update terraform.tfvars (optional):**
   ```hcl
   create_keyvault_endpoint = true  # If you want Key Vault private endpoint
   ```

6. **Re-deploy with CMK:**
   ```bash
   terraform init
   terraform plan -out=tfplan
   terraform apply tfplan
   ```

**Expected Additional Resources:** +8-10 resources (Key Vault, 3 keys, 2 access policies, optional private endpoint + DNS)

**Note:** Enabling CMK after initial deployment will require workspace update. Test in non-production first.

---

## 📋 Environment Variables

Define these at the start:

```bash
# Azure Configuration
export SUBSCRIPTION_ID="f7fc048e-aeec-4c24-8436-cab0c3b48401"
export REGION="eastus2"
export RESOURCE_GROUP="rg-eastus2-edp-poc"
export OWNER_EMAIL="dtorres-admin@cnmc.org"

# Databricks Configuration
export DATABRICKS_ACCOUNT_ID="d4f37ccc-fcd2-4a0c-a566-1e39fd7b746a"

# Network Configuration (allocated CIDR: 10.70.80.0/20)
export CIDR="10.70.80.0/20"  # Single VNet: 4,096 IPs

# ⚠️ IMPORTANT: Individual subnet CIDRs are calculated AUTOMATICALLY by Terraform
# The configuration uses cidrsubnet() to create 3 subnets from the /20 VNet
# You do NOT configure subnet CIDRs - only VNet-level CIDR above
```

---

## ⚠️ ADMIN PRE-WORK SECTION

**Who runs this:** Azure administrator with subscription-level permissions
**When to run:** Once before user begins deployment
**Duration:** ~5 minutes
**Required roles:** Subscription Contributor + Azure AD permissions to manage groups

### 1. Register Required Resource Providers

```bash
# Register Microsoft.Databricks provider
az provider register --namespace Microsoft.Databricks --wait

# Register Microsoft.Network provider
az provider register --namespace Microsoft.Network --wait

# Register Microsoft.Storage provider
az provider register --namespace Microsoft.Storage --wait

# Register Microsoft.Compute provider
az provider register --namespace Microsoft.Compute --wait

# Register Microsoft.KeyVault provider
az provider register --namespace Microsoft.KeyVault --wait
```

**Expected Output:** Each command shows `"registrationState": "Registered"`

**Why this is needed:** User lacks subscription-level permissions to register providers. Admin pre-registers only the 5 required providers.

---

### 2. Verify Provider Registration

```bash
# Check all required providers are registered
az provider show --namespace Microsoft.Databricks --query "registrationState" -o tsv
az provider show --namespace Microsoft.Network --query "registrationState" -o tsv
az provider show --namespace Microsoft.Storage --query "registrationState" -o tsv
az provider show --namespace Microsoft.Compute --query "registrationState" -o tsv
az provider show --namespace Microsoft.KeyVault --query "registrationState" -o tsv
```

**Expected Output:** All five commands return `Registered`

---

### 3. Add User to account_unity_admin Group

```bash
# Get user's object ID
export USER_OBJECT_ID="<user-object-id>"  # User provides: az ad signed-in-user show --query id -o tsv

# Add user to account_unity_admin Azure AD group
az ad group member add \
  --group "account_unity_admin" \
  --member-id $USER_OBJECT_ID
```

**Expected Output:** Command completes without error.

**What this does:** Grants user Databricks account admin permissions via Azure AD group membership.

---

### 4. Verify User Group Membership

```bash
# Verify user is member of account_unity_admin
az ad group member check \
  --group "account_unity_admin" \
  --member-id $USER_OBJECT_ID
```

**Expected Output:**
```json
{
  "value": true
}
```

---

### 5. Verify User Has Resource Group Contributor Access

```bash
# Check if user has Contributor role on resource group
az role assignment list \
  --assignee $USER_OBJECT_ID \
  --resource-group rg-eastus2-edp-poc \
  --query "[?roleDefinitionName=='Contributor']" -o table
```

**Expected Output:** Shows Contributor role assignment on resource group scope.

**If missing:** Grant Contributor role:
```bash
az role assignment create \
  --assignee $USER_OBJECT_ID \
  --role Contributor \
  --scope "/subscriptions/f7fc048e-aeec-4c24-8436-cab0c3b48401/resourceGroups/rg-eastus2-edp-poc"
```

---

**📬 HANDOFF TO USER:** Admin should notify user that:
- ✅ Resource providers are registered
- ✅ User added to account_unity_admin group
- ✅ Resource Group Contributor role verified
- ✅ User can proceed with deployment

---

## 👤 USER PRE-DEPLOYMENT VERIFICATION

**Who runs this:** Deployment user
**Duration:** ~5 minutes

### 1. Verify Azure Login and Subscription

```bash
# Login to Azure (if not already logged in)
az login

# Set subscription context
az account set --subscription $SUBSCRIPTION_ID

# Confirm subscription is active
az account show --query "{Name:name, SubscriptionId:id, State:state}" -o table
```

**Expected Output:** Should show your subscription with `State: Enabled`

---

### 2. Get Your Object ID (for admin verification)

```bash
# Get your Azure AD object ID
az ad signed-in-user show --query id -o tsv
```

**Action:** Provide this Object ID to admin for group membership (Pre-Work Step 3).

---

### 3. Verify Account Admin Permissions

```bash
# Get your object ID
export MY_OBJECT_ID=$(az ad signed-in-user show --query id -o tsv)

# Verify you're in account_unity_admin group
az ad group member check \
  --group "account_unity_admin" \
  --member-id $MY_OBJECT_ID
```

**Expected Output:** `"value": true`

**⚠️ If false:** Admin needs to complete Pre-Work Step 3.

---

### 4. Check Tool Versions

```bash
# Check Azure CLI version
az --version | head -1

# Check Terraform version (must be >= 1.9.0)
terraform --version

# Check Git version
git --version
```

**Expected Output:**
- azure-cli: 2.77.0 or higher
- Terraform: v1.9.0 or higher (required minimum)
- git: 2.51.0 or higher

---

### 5. Check Existing VNets for CIDR Conflicts

```bash
# List all VNets in subscription
az network vnet list \
  --subscription $SUBSCRIPTION_ID \
  --query "[].{Name:name, ResourceGroup:resourceGroup, AddressSpace:addressSpace.addressPrefixes}" \
  -o table
```

**Action:** Verify your planned CIDR range (10.70.80.0/20) doesn't conflict with existing VNets.

---

### 6. Verify Resource Group Access

```bash
# Verify resource group exists
az group show --name $RESOURCE_GROUP \
  --query "{Name:name, Location:location, ProvisioningState:properties.provisioningState}" -o table

# Verify you have Contributor permissions on it
az role assignment list \
  --assignee $MY_OBJECT_ID \
  --resource-group $RESOURCE_GROUP \
  --query "[?roleDefinitionName=='Contributor']" -o table
```

**Expected Output:**
- Resource group shows `ProvisioningState: Succeeded`
- Your Contributor role assignment is listed

**⚠️ If you don't have Contributor:** Contact admin to complete Pre-Work Step 5.

---

## 👤 USER DEPLOYMENT - INFRASTRUCTURE

**Duration:** 45-60 minutes
**Required permission:** Resource Group Contributor + account_unity_admin group membership

### 1. Navigate to AgentBricks Example Directory

```bash
# Navigate to repository location
cd /Users/dwtorres/src/work/terraform-databricks-examples/examples/adb-agentbricks

# Verify you're in correct directory
pwd
ls -la
```

**Expected Output:** Should show terraform files (main.tf, variables.tf, etc.)

---

### 2. Verify Terraform Variables File

```bash
# Display terraform.tfvars for review
echo -e "\n📋 Reviewing terraform.tfvars configuration:"
cat terraform.tfvars
```

**Expected Configuration:**
```hcl
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
```

**⚠️ CRITICAL:** Verify all values are correct before proceeding. Do NOT modify unless necessary.

---

### 2a. Subnet Allocation Reference (Informational)

**The Terraform configuration calculates subnet CIDRs automatically using `cidrsubnet()` function.**

Based on your VNet CIDR (10.70.80.0/20), the following subnets will be created:

```
VNet: 10.70.80.0/20 (4,096 IPs available)
├── Public Subnet:       10.70.80.0/24   (256 IPs) - Databricks delegation
├── Private Subnet:      10.70.81.0/24   (256 IPs) - Databricks delegation
└── Private Link Subnet: 10.70.82.0/24   (256 IPs) - Private endpoints
```

**Formula:** `cidrsubnet(var.cidr, 4, index)` where:
- `/20` VNet + 4 bits = `/24` subnets (256 IPs each)
- index 0, 1, 2 for public, private, private link

**Note:** You cannot customize these subnet CIDRs without modifying the Terraform code.

---

### 3. Initialize Terraform

```bash
terraform init
```

**Expected Output:** `"Terraform has been successfully initialized!"`

**⏳ Duration:** 2-3 minutes (downloads Azure and Databricks providers)

---

### 4. Create and Review Terraform Plan

```bash
# Create execution plan
terraform plan -out=tfplan
```

**Expected Resources:** ~30-35 resources to create
- 1 Databricks workspace
- 1 VNet + 3 subnets
- 1 Access connector (Unity Catalog)
- ~~1 Key Vault + 3 customer-managed keys~~ (TEMPORARILY DISABLED)
- 4 Private endpoints (UI/API, Auth, DBFS Blob, Storage DFS)
- 3 Private DNS zones + VNet links
- 2 NSGs + security rules
- 1 Random string (naming)

**Key Security Features:**
- ✅ Public network access disabled
- ✅ Infrastructure encryption enabled (platform-managed keys)
- ✅ DBFS firewall enabled
- ✅ No public IP for clusters
- ⚠️ ~~3 customer-managed keys~~ (TEMPORARILY DISABLED - using platform-managed keys)
- ✅ Private endpoints for workspace and storage

**Resource Group Summary:**
- **User RGs:** 0 new (uses existing rg-eastus2-edp-poc)
- **Managed RG:** 1 new (databricks-rg-eastus2-edp-poc - unavoidable)

**Action:** Review the plan carefully. Terraform will use your Azure CLI credentials automatically.

---

### 5. Apply Infrastructure Deployment

```bash
# Deploy infrastructure
terraform apply tfplan
```

**⏳ Duration:** 45-60 minutes

**Progress Timeline:**
- **0-10 min:** Networking (VNet, subnets, NSGs)
- **10-15 min:** Key Vault + customer-managed keys
- **15-50 min:** Databricks workspace (longest wait - 25-35 minutes)
- **50-60 min:** Private endpoints, DNS zones, Access connector

**Expected Output:**
```
Apply complete! Resources: 40 added, 0 changed, 0 destroyed.

Outputs:
workspace_url = "https://adb-XXXXXXXXXXXX.2.azuredatabricks.net"
workspace_name = "agentbricks-xxxxx-workspace"
managed_resource_group_name = "databricks-rg-eastus2-edp-poc"
```

---

### 6. Save Deployment Outputs

```bash
# Save all outputs to timestamped file
terraform output -json > deployment-outputs-$(date +%Y%m%d).json

# Extract and display critical outputs
export WORKSPACE_URL=$(terraform output -raw workspace_url)
export WORKSPACE_NAME=$(terraform output -raw workspace_name)
export MANAGED_RG=$(terraform output -raw managed_resource_group_name)
export KEY_VAULT_URI=$(terraform output -raw key_vault_uri)

echo ""
echo "🎯 DEPLOYMENT OUTPUTS:"
echo "Workspace URL: $WORKSPACE_URL"
echo "Workspace Name: $WORKSPACE_NAME"
echo "Managed RG: $MANAGED_RG"
echo "Key Vault URI: $KEY_VAULT_URI"
echo ""
echo "📝 Save these for future reference!"
```

**🔒 SECURITY NOTE:** Save outputs to secure location. Key Vault contains encryption keys for workspace.

---

## 👤 VALIDATION TESTING

**Duration:** ~10 minutes
**Purpose:** Verify AgentBricks workspace deployment and security

### 1. Verify Resource Group Resources

```bash
# List all resources in user resource group
az resource list \
  --resource-group $RESOURCE_GROUP \
  --query "[?contains(name, 'agentbricks')].{Name:name, Type:type, Location:location}" \
  -o table
```

**Expected Resources in rg-eastus2-edp-poc:**
- Virtual network (agentbricks-xxxxx-vnet)
- Databricks workspace (agentbricks-xxxxx-workspace)
- Access connector (agentbricks-xxxxx-access-connector)
- ~~Key Vault (agentbricks-xxxxx-kv)~~ (TEMPORARILY DISABLED)
- Private endpoints (4 endpoints: UI/API, Auth, Blob, DFS)
- Private DNS zones (3 zones: azuredatabricks, blob, dfs)

---

### 2. Verify Managed Resource Group Creation

```bash
# Verify managed RG exists with correct name
az group show --name databricks-rg-eastus2-edp-poc \
  --query "{Name:name, Location:location, ManagedBy:managedBy}" -o table
```

**Expected Output:**
- Name: databricks-rg-eastus2-edp-poc
- ManagedBy: `/subscriptions/.../resourceGroups/rg-eastus2-edp-poc/providers/Microsoft.Databricks/workspaces/...`

**Note:** This managed RG is locked by Microsoft and contains Databricks backend infrastructure.

---

### 3. Verify Private Endpoint Configuration

```bash
# List private endpoints
az network private-endpoint list \
  --resource-group $RESOURCE_GROUP \
  --query "[?contains(name, 'agentbricks')].{Name:name, PrivateIP:privateLinkServiceConnections[0].privateLinkServiceConnectionState.status, Subnet:subnet.id}" \
  -o table
```

**Expected Output:** 4-5 private endpoints with status "Approved"

---

### 4. ~~Verify Key Vault and Customer-Managed Keys~~ (SKIPPED - CMK Disabled)

**⚠️ This validation step is skipped because Customer-Managed Keys are temporarily disabled.**

**Current Encryption Status:**
- Data at rest: Encrypted with **platform-managed keys** (Microsoft-managed)
- CMK (customer-managed keys): Temporarily disabled
- Key Vault: Not deployed

**To re-enable:** See "How to Re-Enable Customer-Managed Keys" section at the top of this runbook.

---

### 5. Workspace Access Test

**From local machine or Azure Cloud Shell:**

1. Navigate to workspace URL: `https://<WORKSPACE_URL>`
2. Click "Sign in with Azure AD"
3. Enter your Azure AD credentials
4. Verify workspace UI loads successfully

**Expected Result:** Workspace loads with AgentBricks configuration, confirming deployment success.

---

### 6. Verify Security Configuration

```bash
# Check workspace security settings
az databricks workspace show \
  --resource-group $RESOURCE_GROUP \
  --name $WORKSPACE_NAME \
  --query "{PublicNetworkAccess:publicNetworkAccessEnabled, CustomerManagedKey:parameters.enableCustomerManagedKey.value, InfrastructureEncryption:parameters.enableInfrastructureEncryption.value}" \
  -o table
```

**Expected Output:**
- PublicNetworkAccess: False
- CustomerManagedKey: ~~True~~ **False** (CMK temporarily disabled)
- InfrastructureEncryption: True (platform-managed keys)

---

### 7. (Optional) Compute Test

**In Databricks Workspace UI:**
1. Navigate to **Compute** → **Create Compute**
2. Configure: Single Node, Standard_DS3_v2, DBR 15.x or higher
3. Click **Create**
4. Wait for cluster to start (~5 minutes)

**Create test notebook:**
```python
# Test 1: Basic compute
print(f"Cluster ID: {spark.conf.get('spark.databricks.clusterUsageTags.clusterId')}")
print(f"Workspace: AgentBricks Non-HIPAA Environment")

# Test 2: Storage access via private endpoint
dbutils.fs.ls("dbfs:/")

# Test 3: Write and read from DBFS (encrypted with CMK)
df = spark.createDataFrame([(1, "AgentBricks"), (2, "Test")], ["id", "value"])
df.write.mode("overwrite").parquet("dbfs:/tmp/agentbricks-test")
test_df = spark.read.parquet("dbfs:/tmp/agentbricks-test")
test_df.show()

print("✅ All AgentBricks validation tests passed!")
```

**Expected Result:** All operations succeed, confirming:
- Compute works with no public IP
- Storage accessible via private endpoints
- Customer-managed keys working for DBFS encryption

---

## 👤 CLEANUP & DESTRUCTION

### Important Notes

⚠️ **Managed Resource Group:** Databricks managed RG will be automatically cleaned up when workspace is destroyed.

📋 **Backup First:** Always backup Terraform state before destruction.

---

### 1. Terminate Active Resources

**In Databricks workspace UI:**
1. Navigate to **Compute**
2. Select all running clusters
3. Click **Terminate**
4. Wait for termination (~2 minutes)

**Why needed:** Active clusters hold locks on infrastructure resources, preventing clean deletion.

---

### 2. Create Terraform State Backup

```bash
# Navigate to deployment directory
cd /Users/dwtorres/src/work/terraform-databricks-examples/examples/adb-agentbricks

# Create timestamped backup
cp terraform.tfstate terraform.tfstate.backup-$(date +%Y%m%d-%H%M%S)

# Verify backup created
ls -lh terraform.tfstate.backup-*
```

---

### 3. Preview Destruction

```bash
# Review what will be destroyed
terraform plan -destroy -out=tfplan-destroy
```

**Expected:** ~40 resources to destroy

**Action:** Review the destruction plan carefully. Managed RG will be destroyed automatically.

---

### 4. Execute Infrastructure Destruction

```bash
# Destroy infrastructure
terraform apply "tfplan-destroy"
```

**⏳ Duration:** 10-15 minutes

**Expected Behavior:**
- ✅ All resources destroyed successfully
- ✅ Managed RG (databricks-rg-eastus2-edp-poc) automatically deleted by Azure
- ✅ User RG (rg-eastus2-edp-poc) remains intact with other resources

---

### 5. Verify Complete Cleanup

```bash
# Check AgentBricks resources are removed from user RG
az resource list \
  --resource-group $RESOURCE_GROUP \
  --query "[?contains(name, 'agentbricks')].{name:name, type:type}" -o table

# Verify managed RG is deleted
az group show --name databricks-rg-eastus2-edp-poc 2>&1
```

**Expected Output:**
- Empty table (no agentbricks resources found in user RG)
- "ResourceGroupNotFound" error for managed RG (confirms deletion)

**Verification Checklist:**
- [ ] No AgentBricks resources in rg-eastus2-edp-poc
- [ ] Managed RG databricks-rg-eastus2-edp-poc deleted
- [ ] Terraform state contains only data sources

---

## ⚠️ ADMIN PERMISSION CLEANUP

**Who runs this:** Azure administrator
**When:** After user completes infrastructure destruction
**Duration:** ~2 minutes

### 1. Remove User from account_unity_admin Group

```bash
# Get user's object ID
export USER_OBJECT_ID="<user-object-id>"

# Remove user from account_unity_admin group
az ad group member remove \
  --group "account_unity_admin" \
  --member-id $USER_OBJECT_ID
```

**Expected Output:** Command completes without error.

---

### 2. Verify User Removed from Group

```bash
# Verify user is no longer member
az ad group member check \
  --group "account_unity_admin" \
  --member-id $USER_OBJECT_ID
```

**Expected Output:** `"value": false`

---

### 3. (Optional) Remove User Resource Group Contributor Role

**Only if you want to revoke user's infrastructure access:**

```bash
# Remove user's Contributor role
az role assignment delete \
  --assignee $USER_OBJECT_ID \
  --role Contributor \
  --scope "/subscriptions/f7fc048e-aeec-4c24-8436-cab0c3b48401/resourceGroups/rg-eastus2-edp-poc"
```

---

## 🔧 TROUBLESHOOTING

### Issue: Workspace Creation Timeout

**Symptom:** Terraform times out during workspace creation after 25-30 minutes.

**Solution:** Normal behavior. Workspace creation takes 25-40 minutes. Check Azure Portal:
1. Portal → Resource Groups → rg-eastus2-edp-poc
2. Find Databricks workspace resource
3. Check provisioning state

Re-run `terraform apply tfplan` to sync state after workspace completes.

---

### Issue: Key Vault Access Denied During Workspace Creation

**Symptom:**
```
Error: waiting for creation of Customer Managed Key
Key Vault operations are not permitted
```

**Root Cause:** Workspace identity not granted Key Vault access yet.

**Solution:** This is handled automatically by `depends_on` relationships in code. If error persists:
1. Wait 5 minutes for Azure AD replication
2. Re-run `terraform apply tfplan`

---

### Issue: CIDR Conflicts

**Symptom:** Terraform fails with "address space overlaps" error.

**Solution:** Update network CIDR range:
```bash
# Edit terraform.tfvars
# Change cidr to non-conflicting range (e.g., 10.70.92.0/20)

# Recreate plan
terraform plan -out=tfplan
```

---

### Issue: Not Member of account_unity_admin Group

**Symptom:** Pre-Deployment Step 3 shows `"value": false`.

**Solution:** Contact admin to complete Pre-Work Step 3. Verify with:
```bash
# List all members of account_unity_admin group
az ad group member list --group "account_unity_admin" \
  --query "[].{displayName:displayName, objectId:id}" -o table
```

Your account should appear in the list.

---

### Issue: Resource Provider Registration Denied

**Symptom:** Terraform fails with "does not have authorization to perform action 'Microsoft.Databricks/register/action'".

**Root Cause:** Admin didn't complete pre-work.

**Solution:** Verify admin completed provider registration:
```bash
az provider show --namespace Microsoft.Databricks --query "registrationState" -o tsv
# Should return: Registered

az provider show --namespace Microsoft.KeyVault --query "registrationState" -o tsv
# Should return: Registered
```

If not registered, contact admin to complete Pre-Work Step 1.

---

### Issue: Managed Resource Group Already Exists

**Symptom:**
```
Error: A resource with the ID ".../databricks-rg-eastus2-edp-poc" already exists
```

**Root Cause:** Previous workspace deployment used same managed RG name.

**Solution:** Either destroy the previous workspace or choose a different managed RG name:
```bash
# Option 1: Destroy previous workspace
az databricks workspace list --query "[?managedResourceGroupId.contains(@, 'databricks-rg-eastus2-edp-poc')]"

# Option 2: Use different name in terraform.tfvars
managed_resource_group_name = "databricks-rg-eastus2-edp-poc-v2"
```

---

### Issue: Authentication Fails During Terraform Apply

**Symptom:** Terraform fails with authentication errors.

**Root Cause:** Azure CLI session expired or using wrong account.

**Solution:**
```bash
# Verify you're logged in
az account show

# If expired, login again
az login

# Verify correct subscription
az account set --subscription f7fc048e-aeec-4c24-8436-cab0c3b48401
az account show

# Retry terraform apply
terraform apply tfplan
```

---

### Issue: Private Endpoint DNS Resolution Fails

**Symptom:** Cannot access workspace, DNS resolves to public IP instead of private IP.

**Root Cause:** Private DNS zones not properly configured or VNet links missing.

**Solution:**
```bash
# Verify private DNS zones exist
az network private-dns zone list \
  --resource-group $RESOURCE_GROUP \
  --query "[].name" -o table

# Verify VNet links exist for each zone
az network private-dns link vnet list \
  --resource-group $RESOURCE_GROUP \
  --zone-name privatelink.azuredatabricks.net \
  -o table
```

Expected DNS zones: privatelink.azuredatabricks.net, privatelink.blob.core.windows.net, privatelink.dfs.core.windows.net

---

## 📝 Environment-Specific Variables Summary

**Your Configuration:**
- **Subscription ID:** f7fc048e-aeec-4c24-8436-cab0c3b48401
- **Region:** eastus2
- **Resource Group:** rg-eastus2-edp-poc (pre-existing)
- **Managed RG:** databricks-rg-eastus2-edp-poc (created by deployment)
- **Owner Email:** dtorres-admin@cnmc.org
- **Databricks Account ID:** d4f37ccc-fcd2-4a0c-a566-1e39fd7b746a
- **VNet CIDR:** 10.70.80.0/20 (4,096 IPs)

**Network Architecture:**
- Single VNet: Private endpoints for UI/API, Auth, Blob, DFS, Key Vault
- 3 Subnets: Public (Databricks), Private (Databricks), Private Link (endpoints)
- Private DNS: 3-4 zones for workspace and storage
- No Public IP: Clusters run without public IPs

**Security Features:**
- Public network access: Disabled
- Customer-managed keys: 3 keys (managed services, managed disk, root DBFS)
- Infrastructure encryption: Enabled
- DBFS firewall: Enabled
- Private endpoints: All services (workspace, blob, DFS, Key Vault)

---

## 🔄 Deployment Workflow Summary

### Phase 1: Admin Pre-Work (~5 minutes)
1. Register 5 resource providers (Databricks, Network, Storage, Compute, KeyVault)
2. Add user to account_unity_admin Azure AD group
3. Verify user has RG Contributor access

### Phase 2: User Deployment (~60 minutes)
1. Verify prerequisites and permissions
2. Navigate to adb-agentbricks directory
3. Verify terraform.tfvars configuration
4. Initialize Terraform
5. Create and review execution plan (~40 resources)
6. Apply infrastructure deployment (45-60 minutes)
7. Save deployment outputs

### Phase 3: Validation (~10 minutes)
1. Verify resource group resources
2. Confirm managed RG creation
3. Check private endpoint configuration
4. Verify Key Vault and customer-managed keys
5. Test workspace access
6. Verify security configuration
7. Optional compute test

### Phase 4: Cleanup (~15 minutes)
1. Terminate active resources
2. Backup Terraform state
3. Preview destruction plan
4. Execute infrastructure destruction
5. Verify complete cleanup (managed RG auto-deleted)
6. Admin removes user from group

---

## ⚠️ Key Differences from Standard Deployment

| Aspect | AgentBricks | Standard HIPAA Workspace |
|--------|-------------|--------------------------|
| **HIPAA Compliance** | ❌ Not HIPAA compliant | ✅ HIPAA compliant |
| **AgentBricks Support** | ✅ Fully supported | ❌ Incompatible |
| **Architecture** | Single VNet | Dual VNet (PoC example) |
| **Resource Groups** | 1 managed RG only | 2+ RGs (data plane + transit) |
| **Security** | Enhanced (CMK, encryption, private endpoints) | Maximum (HIPAA + all features) |
| **Complexity** | 6/10 (simplified) | 9/10 (dual workspace) |
| **Setup Time** | ~60 minutes | ~90 minutes |
| **Best For** | AgentBricks AI development, non-PHI data | HIPAA data, protected health information |

---

## 📚 Additional Resources

- **terraform.tfvars** - Pre-configured variable values
- **validate.sh** - Automated validation script
- **main.tf** - Core infrastructure definition
- **workspace.tf** - Workspace configuration with enhanced security
- **privateendpoint.tf** - Private endpoint definitions
- **keys.tf** - Customer-managed key configuration

---

## 🎯 Success Criteria

**Deployment is successful when:**
- [ ] 1 Databricks workspace created (agentbricks-xxxxx-workspace)
- [ ] 1 managed RG created (databricks-rg-eastus2-edp-poc)
- [ ] 0 new user RGs created (uses existing rg-eastus2-edp-poc)
- [ ] 4-5 private endpoints configured and approved
- [ ] 3 customer-managed keys created and enabled in Key Vault
- [ ] Public network access disabled
- [ ] Infrastructure encryption enabled
- [ ] Workspace accessible via Azure AD authentication
- [ ] DBFS operations work via private endpoints
- [ ] Compute clusters start without public IPs

---

**Document Version:** 1.0
**Environment:** Bash/Unix (Azure Cloud Shell or local terminal)
**Last Updated:** 2025-01-11
**For HIPAA Workloads:** Do NOT use this workspace - deploy separate HIPAA-compliant workspace
