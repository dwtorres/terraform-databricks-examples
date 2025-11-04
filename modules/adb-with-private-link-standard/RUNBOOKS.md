# Operational Runbooks - Azure Databricks Private Link

**Module:** adb-with-private-link-standard  
**Last Updated:** 2025-11-04  
**Purpose:** Operational procedures for deployment, troubleshooting, validation, and disaster recovery

---

## Table of Contents
1. [Deployment Procedures](#1-deployment-procedures)
2. [Troubleshooting Guide](#2-troubleshooting-guide)
3. [Validation Procedures](#3-validation-procedures)
4. [Disaster Recovery](#4-disaster-recovery)

---

## 1. Deployment Procedures

### 1.1 Pre-Deployment Checklist

**Prerequisites Verification:**
```bash
# 1. Azure CLI authentication
az login
az account show

# 2. Set correct subscription
az account set --subscription "<subscription-id>"

# 3. Verify service principal permissions (if using SPN)
az role assignment list --assignee <sp-client-id> \
  --query "[?roleDefinitionName=='Contributor' || roleDefinitionName=='Owner']"

# 4. Check Terraform version
terraform version  # Should be >= 1.5.0

# 5. Verify AzureRM provider version
grep azurerm terraform.tf  # Should be >= 3.80.0

# 6. Check resource provider registration
az provider show --namespace Microsoft.Databricks --query "registrationState"
az provider show --namespace Microsoft.Network --query "registrationState"
```

**Configuration Review:**
```bash
# Review terraform.tfvars
cat terraform.tfvars

# Required variables checklist:
# ✓ prefix (unique identifier)
# ✓ location (Azure region)
# ✓ spoke_resource_group_name
# ✓ All CIDR ranges (no overlaps)
# ✓ Transit subnet ranges
```

### 1.2 Initial Deployment

**Step-by-Step Deployment:**

```bash
# Step 1: Navigate to example directory
cd terraform-databricks-examples/examples/adb-with-private-link-standard

# Step 2: Initialize Terraform
terraform init
# Expected: "Terraform has been successfully initialized!"

# Step 3: Validate configuration
terraform validate
# Expected: "Success! The configuration is valid."

# Step 4: Create deployment plan
terraform plan -out=tfplan
# Review output carefully - should show ~45 resources to create

# Step 5: Review plan for issues
terraform show tfplan | less
# Check for:
# - Resource naming conflicts
# - CIDR overlaps
# - Proper VNet peering configuration
# - All 3 DNS zones with correct VNet links

# Step 6: Apply deployment
terraform apply tfplan
# Duration: 25-30 minutes
# Expected: "Apply complete! Resources: 45 added, 0 changed, 0 destroyed."
```

**Monitoring Deployment Progress:**

```bash
# In separate terminal - watch resource creation
watch -n 10 'az resource list \
  --resource-group rg-databricks-poc \
  --query "length([*])"'

# Monitor workspace provisioning
watch -n 30 'az databricks workspace show \
  --name <workspace-name> \
  --resource-group rg-databricks-poc \
  --query "provisioningState"'
```

### 1.3 Post-Deployment Validation

**Immediate Validation Steps:**

```bash
# 1. Verify resource count
terraform state list | wc -l
# Expected: 45 resources

# 2. Check for drift
terraform plan -detailed-exitcode
# Exit code 0 = no drift, 2 = drift detected

# 3. Verify VNet peering
az network vnet peering list \
  --resource-group <dp-rg-name> \
  --vnet-name <dp-vnet-name> \
  --query "[].{Name:name, State:peeringState}"
# Expected: 2 peerings, both "Connected"

# 4. Verify private endpoints
az network private-endpoint list \
  --resource-group <dp-rg-name> \
  --query "[].{Name:name, ProvisioningState:provisioningState}" -o table
# Expected: 5 endpoints, all "Succeeded"

# 5. Check private DNS zones
az network private-dns zone list \
  --resource-group <dp-rg-name> \
  --query "[].{Name:name, NumberOfRecordSets:numberOfRecordSets}" -o table
# Expected: 3 zones with A records

# 6. Verify DNS VNet links
az network private-dns link vnet list \
  --resource-group <dp-rg-name> \
  --zone-name privatelink.blob.core.windows.net \
  --query "length([*])"
# Expected: 2 (Data Plane + Transit)
```

### 1.4 Configuration Validation

**DNS Configuration Check:**

```bash
# 1. Test DNS resolution from Test VM
# RDP to Test VM (IP from terraform output)

# PowerShell on Test VM:
# Workspace DNS
nslookup adb-<workspace-id>.1.azuredatabricks.net
# Expected: 10.181.x.x (Transit VNet private endpoint)

# Blob storage DNS
nslookup <dbfs-name>.blob.core.windows.net
# Expected: 10.180.x.x (Data Plane private endpoint)

# DFS storage DNS
nslookup <dbfs-name>.dfs.core.windows.net
# Expected: 10.180.x.x (Data Plane private endpoint)
```

### 1.5 Workspace Activation

**Enable Workspace Access:**

```bash
# 1. Get workspace URL
terraform output workspace_url
# Example: https://adb-2003219232620501.1.azuredatabricks.net/

# 2. Access from Test VM browser
# Should load login page without timeout

# 3. Sign in with Azure AD
# Should redirect to Azure AD and back successfully

# 4. Create test cluster
# Single Node, Standard_DS3_v2, DBR 13.3 LTS

# 5. Run validation notebook (see Section 3.3)
```

---

## 2. Troubleshooting Guide

### 2.1 Common Deployment Issues

#### Issue: VNet Peering Not Established

**Symptoms:**
- Workspace accessible but shows errors
- Unable to create clusters
- DNS resolves correctly but connections timeout

**Diagnosis:**
```bash
# Check peering status
az network vnet peering list \
  --resource-group <dp-rg-name> \
  --vnet-name <dp-vnet-name> \
  --query "[].{Name:name, State:peeringState, SyncLevel:peeringSyncLevel}"
```

**Resolution:**
```bash
# If missing, this is Fix #1 issue
# Verify vnet_peering.tf exists in module
ls -la modules/adb-with-private-link-standard/vnet_peering.tf

# If missing, apply Fix #1:
# See FIXES.md for details

# Recreate peering manually if needed:
az network vnet peering create \
  --name dp-to-transit \
  --resource-group <dp-rg-name> \
  --vnet-name <dp-vnet-name> \
  --remote-vnet <transit-vnet-id> \
  --allow-vnet-access true \
  --allow-forwarded-traffic true
```

#### Issue: Storage Resolving to Public IPs

**Symptoms:**
- DNS returns 20.x.x.x addresses for storage
- "LibraryInstallationFailed" errors
- Workspace operations timeout
- Test VM can't access workspace

**Diagnosis:**
```powershell
# From Test VM PowerShell:
nslookup <dbfs-name>.blob.core.windows.net
# If returns public IP (20.x.x.x), this is Fix #2 issue
```

**Resolution:**
```bash
# Check storage DNS VNet links to Transit VNet
az network private-dns link vnet list \
  --resource-group <dp-rg-name> \
  --zone-name privatelink.blob.core.windows.net

# If only 1 link (should be 2), apply Fix #2:
az network private-dns link vnet create \
  --resource-group <dp-rg-name> \
  --zone-name privatelink.blob.core.windows.net \
  --name transit-vnet-blob-link \
  --virtual-network <transit-vnet-id> \
  --registration-enabled false

# Repeat for dfs zone
az network private-dns link vnet create \
  --resource-group <dp-rg-name> \
  --zone-name privatelink.dfs.core.windows.net \
  --name transit-vnet-dfs-link \
  --virtual-network <transit-vnet-id> \
  --registration-enabled false
```

#### Issue: 44/45 Resources Created (Race Condition)

**Symptoms:**
- Frontend private endpoint fails
- "Resource not ready" error during deployment
- Must run terraform apply twice

**Diagnosis:**
```bash
# Check failed resource
terraform state list | grep front_pe
# If missing, this is Fix #4 issue
```

**Resolution:**
```bash
# Verify endpoint_frontend.tf has depends_on
grep -A 3 "depends_on" \
  modules/adb-with-private-link-standard/endpoint_frontend.tf

# If missing, apply Fix #4:
# See FIXES.md section on Fix #4

# Immediate workaround:
terraform apply -auto-approve
# Should create the missing frontend endpoint
```

### 2.2 DNS Resolution Issues

#### Troubleshooting DNS from Test VM

**Diagnostic Commands:**

```powershell
# PowerShell on Test VM

# 1. Check DNS server configuration
Get-DnsClientServerAddress -AddressFamily IPv4

# 2. Clear DNS cache
Clear-DnsClientCache

# 3. Test DNS resolution with details
Resolve-DnsName adb-<workspace-id>.1.azuredatabricks.net -Type A -Server 168.63.129.16

# 4. Trace DNS query
nslookup -debug adb-<workspace-id>.1.azuredatabricks.net

# 5. Check if using Azure DNS
Test-NetConnection -ComputerName 168.63.129.16 -Port 53
```

#### Fixing DNS Resolution

**Scenario: DNS returns public IPs**

```bash
# 1. Verify private DNS zone exists
az network private-dns zone show \
  --resource-group <dp-rg-name> \
  --name privatelink.azuredatabricks.net

# 2. Check A records in zone
az network private-dns record-set a list \
  --resource-group <dp-rg-name> \
  --zone-name privatelink.azuredatabricks.net

# 3. Verify VNet link exists
az network private-dns link vnet list \
  --resource-group <dp-rg-name> \
  --zone-name privatelink.azuredatabricks.net

# 4. If VNet link missing, create it
az network private-dns link vnet create \
  --resource-group <dp-rg-name> \
  --zone-name privatelink.azuredatabricks.net \
  --name <vnet-link-name> \
  --virtual-network <vnet-id> \
  --registration-enabled false
```

### 2.3 Connectivity Issues

#### Test VM Cannot Access Workspace

**Diagnostic Flow:**

```powershell
# Step 1: Verify DNS resolution
nslookup adb-<workspace-id>.1.azuredatabricks.net
# Should return 10.181.x.x

# Step 2: Test TCP connectivity
Test-NetConnection -ComputerName adb-<workspace-id>.1.azuredatabricks.net -Port 443
# TcpTestSucceeded should be True

# Step 3: Check NSG rules
# Azure Portal: Test VM → Networking → Effective security rules
# Look for rules blocking 443 outbound

# Step 4: Verify VNet peering
# Azure Portal: Data Plane VNet → Peerings
# Should show "Connected" status
```

**Resolution Steps:**

```bash
# 1. If DNS fails, fix DNS (see 2.2)

# 2. If TCP fails but DNS works, check NSG
az network nsg rule list \
  --resource-group <transit-rg-name> \
  --nsg-name <testvm-nsg-name> \
  --query "[?destinationPortRange=='443'].{Name:name, Priority:priority, Access:access}"

# 3. If peering disconnected, recreate
az network vnet peering delete \
  --resource-group <dp-rg-name> \
  --vnet-name <dp-vnet-name> \
  --name dp-to-transit

terraform apply -auto-approve  # Recreates peering
```

#### Cluster Cannot Access Storage

**Diagnostic Commands:**

```python
# Run in Databricks notebook:

# Test 1: DBFS access
display(dbutils.fs.ls("dbfs:/"))
# Should list directories without error

# Test 2: Write test
dbutils.fs.put("dbfs:/tmp/test.txt", "test", overwrite=True)
# Should succeed

# Test 3: Read test
dbutils.fs.head("dbfs:/tmp/test.txt")
# Should return "test"

# Test 4: Delta Lake
df = spark.range(10)
df.write.format("delta").mode("overwrite").save("dbfs:/tmp/delta-test")
# Should complete without timeout
```

**Resolution:**

```bash
# 1. Check blob private endpoint
az network private-endpoint show \
  --resource-group <dp-rg-name> \
  --name dp-blob-pe \
  --query "provisioningState"

# 2. Verify storage DNS resolution
# Should be handled by Fix #2

# 3. Check storage account network rules
az storage account show \
  --name <dbfs-storage-name> \
  --resource-group <managed-rg-name> \
  --query "networkRuleSet.defaultAction"
# Should be "Deny" (private access only)
```

### 2.4 Performance Issues

#### Workspace Slow or Timing Out

**Diagnostic Steps:**

```bash
# 1. Check workspace health
az databricks workspace show \
  --name <workspace-name> \
  --resource-group <rg-name> \
  --query "{State:provisioningState, SKU:sku.name, PublicAccess:publicNetworkAccess}"

# 2. Verify private endpoint health
az network private-endpoint show \
  --resource-group <dp-rg-name> \
  --name frontprivatendpoint \
  --query "{State:provisioningState, CustomDnsConfigs:customDnsConfigs}"

# 3. Check for DNS propagation delays
# Wait 5-10 minutes for DNS propagation
# Clear DNS cache on client machines
```

---

## 3. Validation Procedures

### 3.1 Network Validation

**VNet Connectivity Tests:**

```bash
# 1. Verify effective routes from Test VM
az network nic show-effective-route-table \
  --resource-group <transit-rg-name> \
  --name <testvm-nic-name> \
  --query "value[?addressPrefix[0]=='10.180.0.0/20'].{Prefix:addressPrefix[0], NextHop:nextHopType}"
# Should show VNetPeering for Data Plane VNet

# 2. Check NSG effective rules
az network nic list-effective-nsg \
  --resource-group <transit-rg-name> \
  --name <testvm-nic-name> \
  --query "value[].securityRules[?destinationPortRange=='443' && access=='Allow']"

# 3. Verify private endpoint network interfaces
az network private-endpoint show \
  --resource-group <dp-rg-name> \
  --name dp-blob-pe \
  --query "networkInterfaces[].id"
```

### 3.2 DNS Validation

**Comprehensive DNS Check:**

```powershell
# Run from Test VM PowerShell

# Test all required DNS entries:
$dnsTests = @(
    "adb-<workspace-id>.1.azuredatabricks.net",
    "<dbfs-name>.blob.core.windows.net",
    "<dbfs-name>.dfs.core.windows.net"
)

foreach ($dns in $dnsTests) {
    Write-Host "`nTesting: $dns" -ForegroundColor Cyan
    $result = Resolve-DnsName $dns -Type A -ErrorAction SilentlyContinue
    
    if ($result.IPAddress -match "^10\.") {
        Write-Host "✅ PASS - Private IP: $($result.IPAddress)" -ForegroundColor Green
    } elseif ($result.IPAddress -match "^20\.|^40\.") {
        Write-Host "❌ FAIL - Public IP: $($result.IPAddress)" -ForegroundColor Red
    } else {
        Write-Host "⚠️  WARN - Unexpected IP: $($result.IPAddress)" -ForegroundColor Yellow
    }
}
```

### 3.3 Workspace Functionality Validation

**Validation Notebook:**

```python
# Databricks Notebook: Private Link Validation

# Test 1: Cluster Configuration
print("Cluster ID:", spark.conf.get("spark.databricks.clusterUsageTags.clusterId"))
print("✅ Cluster running successfully")

# Test 2: DBFS Root Access
try:
    dbutils.fs.ls("dbfs:/")
    print("✅ DBFS root accessible")
except Exception as e:
    print(f"❌ DBFS access failed: {e}")

# Test 3: Write Test
try:
    test_path = "dbfs:/tmp/private-link-validation"
    spark.range(1000).write.mode("overwrite").parquet(test_path)
    print(f"✅ Write test passed: {test_path}")
except Exception as e:
    print(f"❌ Write test failed: {e}")

# Test 4: Read Test
try:
    df = spark.read.parquet(test_path)
    count = df.count()
    print(f"✅ Read test passed: {count} rows")
except Exception as e:
    print(f"❌ Read test failed: {e}")

# Test 5: Delta Lake
try:
    delta_path = "dbfs:/tmp/private-link-delta"
    spark.range(100).write.format("delta").mode("overwrite").save(delta_path)
    delta_df = spark.read.format("delta").load(delta_path)
    print(f"✅ Delta Lake test passed: {delta_df.count()} rows")
except Exception as e:
    print(f"❌ Delta Lake test failed: {e}")

# Test 6: External Library Installation
try:
    %pip install requests
    import requests
    print("✅ Library installation successful")
except Exception as e:
    print(f"❌ Library installation failed: {e}")

print("\n" + "="*50)
print("VALIDATION COMPLETE")
print("="*50)
```

### 3.4 Security Validation

**Security Posture Check:**

```bash
# 1. Verify public network access disabled
az databricks workspace show \
  --name <workspace-name> \
  --resource-group <rg-name> \
  --query "publicNetworkAccessEnabled"
# Expected: false

# 2. Check NSG rules (should be NoAzureDatabricksRules)
az databricks workspace show \
  --name <workspace-name> \
  --resource-group <rg-name> \
  --query "parameters.requireNsgRules.value"
# Expected: NoAzureDatabricksRules

# 3. Verify no public IPs on clusters
az databricks workspace show \
  --name <workspace-name> \
  --resource-group <rg-name> \
  --query "parameters.enableNoPublicIp.value"
# Expected: true

# 4. Check storage account public access
az storage account show \
  --name <dbfs-storage-name> \
  --resource-group <managed-rg-name> \
  --query "allowBlobPublicAccess"
# Expected: false
```

---

## 4. Disaster Recovery

### 4.1 Backup Procedures

**Pre-Disaster Backup:**

```bash
# 1. Export Terraform state
terraform state pull > terraform.tfstate.backup.$(date +%Y%m%d-%H%M%S)

# 2. Export all resource configurations
az resource list \
  --resource-group <dp-rg-name> \
  --output json > dp-resources-backup.json

az resource list \
  --resource-group <transit-rg-name> \
  --output json > transit-resources-backup.json

# 3. Document custom configurations
az network private-dns zone list \
  --resource-group <dp-rg-name> \
  --output json > dns-zones-backup.json

# 4. Export workspace configuration (if possible)
# Databricks CLI or API calls to export notebooks, jobs, clusters

# 5. Store backups securely
# Upload to Azure Blob Storage with versioning enabled
```

### 4.2 Recovery Procedures

#### Scenario 1: Accidental Resource Deletion

**Single Resource Recovery:**

```bash
# 1. Identify deleted resource
terraform plan
# Shows resources to be created

# 2. Import existing resource if still in Azure
terraform import <resource-type>.<resource-name> <azure-resource-id>

# Example: Import frontend endpoint
terraform import \
  module.adb-with-private-link-standard.azurerm_private_endpoint.front_pe \
  /subscriptions/<sub-id>/resourceGroups/<rg-name>/providers/Microsoft.Network/privateEndpoints/frontprivatendpoint

# 3. Re-create if completely deleted
terraform apply -target=<resource-type>.<resource-name>
```

#### Scenario 2: Complete Infrastructure Loss

**Full Recovery:**

```bash
# 1. Restore Terraform state
cp terraform.tfstate.backup.<timestamp> terraform.tfstate

# 2. Verify state matches reality
terraform plan -detailed-exitcode

# 3. If state doesn't match, rebuild from scratch
terraform destroy -auto-approve  # Clean slate
terraform apply -auto-approve     # Full redeploy

# 4. Restore workspace data (if backed up)
# Use Databricks APIs or CLI to restore notebooks, jobs, etc.
```

#### Scenario 3: DNS Resolution Failure

**Emergency DNS Fix:**

```bash
# 1. Check DNS zone status
az network private-dns zone list \
  --resource-group <dp-rg-name>

# 2. If zone deleted, recreate
az network private-dns zone create \
  --resource-group <dp-rg-name> \
  --name privatelink.azuredatabricks.net

# 3. Recreate VNet links
az network private-dns link vnet create \
  --resource-group <dp-rg-name> \
  --zone-name privatelink.azuredatabricks.net \
  --name dp-vnet-link \
  --virtual-network <dp-vnet-id> \
  --registration-enabled false

# 4. Re-run Terraform to restore A records
terraform apply -target=module.adb-with-private-link-standard
```

### 4.3 Rollback Procedures

**Safe Rollback Strategy:**

```bash
# 1. Capture current state
terraform state pull > pre-rollback-state.json

# 2. Restore previous Terraform code
git checkout <previous-commit-or-tag>

# 3. Plan rollback
terraform plan -out=rollback.tfplan
# Review changes carefully

# 4. Execute rollback
terraform apply rollback.tfplan

# 5. Validate post-rollback
# Run validation procedures from Section 3
```

### 4.4 Emergency Contacts

**Escalation Path:**

1. **Level 1:** Infrastructure Team
   - Initial troubleshooting
   - Standard runbook procedures

2. **Level 2:** Azure Networking Team
   - Complex VNet issues
   - DNS resolution problems
   - Private endpoint failures

3. **Level 3:** Databricks Support
   - Workspace-specific issues
   - API failures
   - Cluster problems

4. **Level 4:** Microsoft Azure Support
   - Azure platform issues
   - Resource provider failures

---

## Appendix A: Quick Reference Commands

### Essential Commands

```bash
# Status checks
terraform state list
terraform show
az resource list --resource-group <rg-name> --output table

# Workspace status
az databricks workspace show --name <ws-name> --resource-group <rg-name>

# Network status
az network vnet peering list --resource-group <rg-name> --vnet-name <vnet-name>
az network private-endpoint list --resource-group <rg-name> --output table

# DNS status
az network private-dns zone list --resource-group <rg-name> --output table
az network private-dns link vnet list --resource-group <rg-name> --zone-name <zone-name>
```

### Emergency Recovery

```bash
# Force unlock state
terraform force-unlock <lock-id>

# Refresh state
terraform refresh

# Target specific resource
terraform apply -target=<resource>

# Import existing resource
terraform import <resource-type>.<name> <azure-resource-id>
```

---

**Document Version:** 1.0  
**Maintainer:** David Torres  
**Last Review:** 2025-11-04  
**Next Review:** 2025-12-04
