# Testing Procedures - Azure Databricks Private Link

**Module:** adb-with-private-link-standard  
**Last Updated:** 2025-11-04  
**Purpose:** Comprehensive testing procedures and validation checklists

---

## Table of Contents
1. [Pre-Deployment Testing](#1-pre-deployment-testing)
2. [Post-Deployment Validation](#2-post-deployment-validation)
3. [DNS Resolution Testing](#3-dns-resolution-testing)
4. [Workspace Access Testing](#4-workspace-access-testing)
5. [Compute and Storage Testing](#5-compute-and-storage-testing)
6. [Security Testing](#6-security-testing)
7. [Performance Testing](#7-performance-testing)
8. [Integration Testing](#8-integration-testing)

---

## 1. Pre-Deployment Testing

### 1.1 Prerequisites Validation Checklist

**Azure Environment:**
```bash
# ✓ Subscription access verified
az account show
az account list-locations --query "[?name=='southcentralus']"

# ✓ Resource provider registration
az provider show --namespace Microsoft.Databricks --query "registrationState"
az provider show --namespace Microsoft.Network --query "registrationState"
# Expected: "Registered" for both

# ✓ Service principal permissions (if using SPN)
az role assignment list \
  --assignee <sp-client-id> \
  --query "[?roleDefinitionName=='Contributor']" \
  --output table
# Expected: At least one "Contributor" role assignment

# ✓ Quota availability
az vm list-usage --location southcentralus --output table | grep "Standard DSv2 Family"
# Expected: Available vCPUs > 4 (for Test VM + clusters)
```

**Terraform Environment:**
```bash
# ✓ Terraform version
terraform version
# Expected: >= 1.5.0

# ✓ Provider versions
terraform providers
# Expected: azurerm >= 3.80.0

# ✓ Configuration syntax
terraform validate
# Expected: "Success! The configuration is valid."

# ✓ Formatting
terraform fmt -check -recursive
# Expected: No output (all files formatted)
```

### 1.2 Configuration Validation

**Network Configuration:**
```bash
# ✓ CIDR range validation
# Data Plane VNet: 10.180.0.0/20 (4096 IPs)
# Transit VNet: 10.181.0.0/20 (4096 IPs)
# Verify no overlap with existing networks

# ✓ Subnet allocation check
# Data Plane subnets (total 1024 IPs):
#   - Private: 10.180.0.0/24 (256)
#   - Public: 10.180.1.0/24 (256)
#   - Storage: 10.180.2.0/24 (256)
#   - Private Endpoints: 10.180.3.0/24 (256)

# Transit subnets (total 512 IPs):
#   - Transit: 10.181.0.0/24 (256)
#   - Private Endpoints: 10.181.1.0/24 (256)
```

**Variable Validation:**
```bash
# ✓ terraform.tfvars completeness
required_vars=(
  "prefix"
  "location"
  "spoke_resource_group_name"
  "private_subnet_address_prefix"
  "public_subnet_address_prefix"
  "storage_subnet_address_prefix"
  "privateendpoint_subnet_address_prefix"
  "transit_subnet_address_prefix"
  "transit_privateendpoint_subnet_address_prefix"
  "hubcidr"
  "spoke_vnet_address_space"
  "transit_vnet_address_space"
)

for var in "${required_vars[@]}"; do
  grep -q "^${var}" terraform.tfvars || echo "❌ Missing: ${var}"
done
```

### 1.3 Dry Run Testing

**Plan Review Checklist:**
```bash
# ✓ Generate plan
terraform plan -out=tfplan

# ✓ Verify resource count
terraform show -json tfplan | jq '.resource_changes | length'
# Expected: ~45 resources

# ✓ Check for critical resources
terraform show tfplan | grep -E "vnet_peering|private_dns_zone_virtual_network_link"
# Expected: vnet_peering.tf resources present
# Expected: Storage DNS links to Transit VNet present

# ✓ Validate depends_on in frontend endpoint
terraform show tfplan | grep -A 5 "azurerm_private_endpoint.front_pe"
# Expected: depends_on = [azurerm_databricks_workspace.dp_workspace]

# ✓ Check for duplicate DNS zones
terraform show tfplan | grep "azurerm_private_dns_zone" | grep "dns_auth_front"
# Expected: NO results (redundant zone removed)
```

---

## 2. Post-Deployment Validation

### 2.1 Resource Creation Verification

**Immediate Post-Deployment Checks:**
```bash
# ✓ Resource count validation
terraform state list | wc -l
# Expected: 45 resources

# ✓ Deployment completeness
terraform plan -detailed-exitcode
# Exit code 0 = no drift detected

# ✓ Resource group verification
az group list --query "[?contains(name, '${PREFIX}')]" --output table
# Expected: 2 resource groups (dp-rg, transit-rg)

# ✓ VNet existence
az network vnet list --output table | grep "${PREFIX}"
# Expected: 2 VNets (dp-vnet, transit-vnet)

# ✓ Workspace provisioning status
az databricks workspace show \
  --name "${WORKSPACE_NAME}" \
  --resource-group "${RG_NAME}" \
  --query "provisioningState"
# Expected: "Succeeded"
```

### 2.2 Network Connectivity Validation

**VNet Peering Status:**
```bash
# ✓ Verify peering connections
az network vnet peering list \
  --resource-group "${DP_RG_NAME}" \
  --vnet-name "${DP_VNET_NAME}" \
  --query "[].{Name:name, State:peeringState, RemoteVNet:remoteVirtualNetwork.id}"

# Expected output:
# Name                 State       RemoteVNet
# -------------------  ----------  ------------------------------------
# prefix-dp-to-transit Connected   /subscriptions/.../transit-vnet
```

**Effective Routes Validation:**
```bash
# ✓ Check Test VM routes
az network nic show-effective-route-table \
  --resource-group "${TRANSIT_RG_NAME}" \
  --name "${TESTVM_NIC_NAME}" \
  --query "value[?addressPrefix[0]=='10.180.0.0/20']"

# Expected: Route with nextHopType = "VNetPeering"
```

### 2.3 Private Endpoint Validation

**Endpoint Health Checks:**
```bash
# ✓ List all private endpoints
az network private-endpoint list \
  --resource-group "${DP_RG_NAME}" \
  --query "[].{Name:name, State:provisioningState, Location:location}" \
  --output table

# Expected: 5 endpoints, all "Succeeded"
# - dp-dpcp-pe
# - dp-blob-pe
# - dp-dfs-pe
# - frontprivatendpoint
# - transit-auth-pe

# ✓ Verify endpoint network interfaces
for ep in dp-dpcp-pe dp-blob-pe dp-dfs-pe frontprivatendpoint transit-auth-pe; do
  echo "Checking ${ep}:"
  az network private-endpoint show \
    --name "${ep}" \
    --resource-group <rg-name> \
    --query "networkInterfaces[0].id"
done

# ✓ Check custom DNS configurations
az network private-endpoint show \
  --name dp-blob-pe \
  --resource-group "${DP_RG_NAME}" \
  --query "customDnsConfigs[].{FQDN:fqdn, IP:ipAddresses[0]}"

# Expected: FQDN matches storage account, IP in 10.180.x.x range
```

---

## 3. DNS Resolution Testing

### 3.1 DNS Zone Configuration Validation

**DNS Zone Existence:**
```bash
# ✓ Verify all 3 DNS zones exist
az network private-dns zone list \
  --resource-group "${DP_RG_NAME}" \
  --query "[].{Name:name, RecordSets:numberOfRecordSets}" \
  --output table

# Expected zones:
# - privatelink.azuredatabricks.net (with A records)
# - privatelink.blob.core.windows.net (with A records)
# - privatelink.dfs.core.windows.net (with A records)
```

**VNet Link Validation (CRITICAL):**
```bash
# ✓ Check Databricks DNS zone links
az network private-dns link vnet list \
  --resource-group "${DP_RG_NAME}" \
  --zone-name privatelink.azuredatabricks.net \
  --query "[].{Name:name, VNet:virtualNetwork.id, State:provisioningState}"

# Expected: 2 links (Data Plane + Transit)

# ✓ Check blob storage DNS zone links (Fix #2)
az network private-dns link vnet list \
  --resource-group "${DP_RG_NAME}" \
  --zone-name privatelink.blob.core.windows.net \
  --query "[].{Name:name, VNet:virtualNetwork.id}"

# Expected: 2 links (Data Plane + Transit) ← CRITICAL FIX #2

# ✓ Check DFS storage DNS zone links (Fix #2)
az network private-dns link vnet list \
  --resource-group "${DP_RG_NAME}" \
  --zone-name privatelink.dfs.core.windows.net \
  --query "[].{Name:name, VNet:virtualNetwork.id}"

# Expected: 2 links (Data Plane + Transit) ← CRITICAL FIX #2
```

### 3.2 Test VM DNS Resolution

**Connection to Test VM:**
```bash
# Get Test VM public IP
terraform output test_vm_public_ip

# Get Test VM password
terraform output -json test_vm_password | jq -r

# RDP to Test VM:
# macOS: Microsoft Remote Desktop app
# Windows: mstsc /v:<public-ip>
# Linux: remmina or xfreerdp
```

**PowerShell DNS Tests on Test VM:**
```powershell
# Test 1: Workspace DNS resolution
$workspace_dns = "adb-<workspace-id>.1.azuredatabricks.net"
$result = Resolve-DnsName $workspace_dns -Type A

Write-Host "Workspace DNS Test:" -ForegroundColor Cyan
Write-Host "  FQDN: $workspace_dns"
Write-Host "  IP: $($result.IPAddress)"

if ($result.IPAddress -match "^10\.181\.") {
    Write-Host "  ✅ PASS - Resolves to Transit VNet private IP" -ForegroundColor Green
} else {
    Write-Host "  ❌ FAIL - Should resolve to 10.181.x.x" -ForegroundColor Red
}

# Test 2: Blob storage DNS resolution (Fix #2 validation)
$blob_dns = "<dbfs-name>.blob.core.windows.net"
$result = Resolve-DnsName $blob_dns -Type A

Write-Host "`nBlob Storage DNS Test:" -ForegroundColor Cyan
Write-Host "  FQDN: $blob_dns"
Write-Host "  IP: $($result.IPAddress)"

if ($result.IPAddress -match "^10\.180\.") {
    Write-Host "  ✅ PASS - Resolves to Data Plane VNet private IP" -ForegroundColor Green
} elseif ($result.IPAddress -match "^20\.|^40\.") {
    Write-Host "  ❌ FAIL - Resolving to PUBLIC IP (Fix #2 missing)" -ForegroundColor Red
} else {
    Write-Host "  ⚠️  WARN - Unexpected IP range" -ForegroundColor Yellow
}

# Test 3: DFS storage DNS resolution (Fix #2 validation)
$dfs_dns = "<dbfs-name>.dfs.core.windows.net"
$result = Resolve-DnsName $dfs_dns -Type A

Write-Host "`nDFS Storage DNS Test:" -ForegroundColor Cyan
Write-Host "  FQDN: $dfs_dns"
Write-Host "  IP: $($result.IPAddress)"

if ($result.IPAddress -match "^10\.180\.") {
    Write-Host "  ✅ PASS - Resolves to Data Plane VNet private IP" -ForegroundColor Green
} elseif ($result.IPAddress -match "^20\.|^40\.") {
    Write-Host "  ❌ FAIL - Resolving to PUBLIC IP (Fix #2 missing)" -ForegroundColor Red
} else {
    Write-Host "  ⚠️  WARN - Unexpected IP range" -ForegroundColor Yellow
}

# Test 4: DNS server configuration
Write-Host "`nDNS Server Configuration:" -ForegroundColor Cyan
Get-DnsClientServerAddress -AddressFamily IPv4 | 
  Where-Object {$_.InterfaceAlias -notlike "*Loopback*"} |
  Format-Table InterfaceAlias, ServerAddresses
# Expected: 168.63.129.16 (Azure DNS)
```

### 3.3 Automated DNS Test Script

**Comprehensive DNS Validation:**
```powershell
# Save as: Test-PrivateLinkDNS.ps1
param(
    [string]$WorkspaceId,
    [string]$DbfsName
)

$tests = @{
    "Workspace" = @{
        DNS = "adb-${WorkspaceId}.1.azuredatabricks.net"
        ExpectedRange = "^10\.181\."
        Description = "Frontend endpoint in Transit VNet"
    }
    "Blob Storage" = @{
        DNS = "${DbfsName}.blob.core.windows.net"
        ExpectedRange = "^10\.180\."
        Description = "Blob endpoint in Data Plane VNet"
    }
    "DFS Storage" = @{
        DNS = "${DbfsName}.dfs.core.windows.net"
        ExpectedRange = "^10\.180\."
        Description = "DFS endpoint in Data Plane VNet"
    }
}

$passed = 0
$failed = 0

foreach ($test in $tests.GetEnumerator()) {
    Write-Host "`n=== $($test.Key) ===" -ForegroundColor Cyan
    Write-Host "DNS: $($test.Value.DNS)"
    
    try {
        $result = Resolve-DnsName $test.Value.DNS -Type A -ErrorAction Stop
        $ip = $result.IPAddress
        
        Write-Host "Resolved IP: $ip"
        
        if ($ip -match $test.Value.ExpectedRange) {
            Write-Host "✅ PASS - $($test.Value.Description)" -ForegroundColor Green
            $passed++
        } else {
            Write-Host "❌ FAIL - Expected $($test.Value.ExpectedRange), got $ip" -ForegroundColor Red
            $failed++
        }
    } catch {
        Write-Host "❌ FAIL - DNS resolution failed: $_" -ForegroundColor Red
        $failed++
    }
}

Write-Host "`n========================================" -ForegroundColor White
Write-Host "Results: $passed passed, $failed failed" -ForegroundColor White
Write-Host "========================================`n" -ForegroundColor White

if ($failed -eq 0) {
    Write-Host "🎉 All DNS tests PASSED!" -ForegroundColor Green
    exit 0
} else {
    Write-Host "⚠️  Some DNS tests FAILED - review fixes" -ForegroundColor Yellow
    exit 1
}
```

---

## 4. Workspace Access Testing

### 4.1 Browser Access Validation

**From Test VM:**
```powershell
# Test 1: Workspace URL accessibility
$workspace_url = "https://adb-<workspace-id>.1.azuredatabricks.net/"

Write-Host "Testing workspace access..." -ForegroundColor Cyan
try {
    $response = Invoke-WebRequest -Uri $workspace_url -UseBasicParsing -TimeoutSec 30
    if ($response.StatusCode -eq 200) {
        Write-Host "✅ Workspace accessible" -ForegroundColor Green
    }
} catch {
    Write-Host "❌ Workspace not accessible: $_" -ForegroundColor Red
}

# Test 2: Azure AD authentication redirect
# Open in browser manually and verify:
# 1. Redirects to login.microsoftonline.com
# 2. Successfully authenticates with Azure AD
# 3. Redirects back to workspace
# 4. Workspace loads without timeout
```

### 4.2 Network Connectivity Testing

**TCP Connection Tests:**
```powershell
# Test HTTPS connectivity to workspace
Test-NetConnection -ComputerName adb-<workspace-id>.1.azuredatabricks.net -Port 443

# Expected output:
# TcpTestSucceeded : True
# RemoteAddress    : 10.181.x.x

# Test connectivity to storage
Test-NetConnection -ComputerName <dbfs-name>.blob.core.windows.net -Port 443
# Expected: TcpTestSucceeded : True, RemoteAddress : 10.180.x.x
```

### 4.3 Workspace UI Validation Checklist

**Manual Checks After Login:**
```
✓ Home page loads successfully
✓ Workspace dropdown shows workspace name
✓ Navigation menu accessible (Workspace, Data, Compute, etc.)
✓ User profile visible (top right corner)
✓ No console errors in browser developer tools
✓ Page load time < 5 seconds
```

---

## 5. Compute and Storage Testing

### 5.1 Cluster Creation Test

**Test Cluster Configuration:**
```python
# Cluster settings for validation:
{
  "cluster_name": "private-link-test-cluster",
  "spark_version": "13.3.x-scala2.12",
  "node_type_id": "Standard_DS3_v2",
  "num_workers": 0,  # Single node for testing
  "autotermination_minutes": 30,
  "enable_elastic_disk": true
}

# Create via UI or API, monitor startup time
# Expected: 5-8 minutes for single node cluster
```

**Cluster Health Validation:**
```python
# Create notebook and attach to cluster
# Run in first cell:

import pyspark
print(f"Spark version: {pyspark.__version__}")
print(f"Cluster ID: {spark.conf.get('spark.databricks.clusterUsageTags.clusterId')}")

# Expected output without errors
# ✅ Cluster running successfully
```

### 5.2 DBFS Access Testing

**Basic DBFS Operations:**
```python
# Test 1: List DBFS root
try:
    dbutils.fs.ls("dbfs:/")
    print("✅ DBFS root accessible")
except Exception as e:
    print(f"❌ DBFS access failed: {e}")

# Test 2: Write test file
try:
    test_content = "Private Link validation test - " + str(datetime.now())
    dbutils.fs.put("dbfs:/tmp/private-link-test.txt", test_content, overwrite=True)
    print("✅ DBFS write successful")
except Exception as e:
    print(f"❌ DBFS write failed: {e}")

# Test 3: Read test file
try:
    content = dbutils.fs.head("dbfs:/tmp/private-link-test.txt")
    print(f"✅ DBFS read successful: {content[:50]}")
except Exception as e:
    print(f"❌ DBFS read failed: {e}")

# Test 4: Delete test file
try:
    dbutils.fs.rm("dbfs:/tmp/private-link-test.txt")
    print("✅ DBFS delete successful")
except Exception as e:
    print(f"❌ DBFS delete failed: {e}")
```

### 5.3 Storage Performance Testing

**Data Write Performance:**
```python
import time

# Test large data write
start = time.time()
df = spark.range(0, 10000000, 1, 10)  # 10M rows
df.write.mode("overwrite").parquet("dbfs:/tmp/perf-test-data")
write_time = time.time() - start

print(f"Write test: 10M rows in {write_time:.2f} seconds")
print(f"Throughput: {10000000/write_time:.0f} rows/sec")

# Expected: < 30 seconds for 10M rows
if write_time < 30:
    print("✅ Write performance acceptable")
else:
    print("⚠️  Write performance slower than expected")
```

**Data Read Performance:**
```python
# Test large data read
start = time.time()
df = spark.read.parquet("dbfs:/tmp/perf-test-data")
count = df.count()
read_time = time.time() - start

print(f"Read test: {count} rows in {read_time:.2f} seconds")
print(f"Throughput: {count/read_time:.0f} rows/sec")

# Expected: < 10 seconds for 10M rows
if read_time < 10:
    print("✅ Read performance acceptable")
else:
    print("⚠️  Read performance slower than expected")

# Cleanup
dbutils.fs.rm("dbfs:/tmp/perf-test-data", recurse=True)
```

### 5.4 Delta Lake Testing

**Delta Table Operations:**
```python
# Test 1: Create Delta table
try:
    spark.range(1000).write.format("delta").mode("overwrite").save("dbfs:/tmp/delta-test")
    print("✅ Delta table creation successful")
except Exception as e:
    print(f"❌ Delta table creation failed: {e}")

# Test 2: Read Delta table
try:
    df = spark.read.format("delta").load("dbfs:/tmp/delta-test")
    count = df.count()
    print(f"✅ Delta table read successful: {count} rows")
except Exception as e:
    print(f"❌ Delta table read failed: {e}")

# Test 3: Update Delta table
try:
    from delta.tables import DeltaTable
    deltaTable = DeltaTable.forPath(spark, "dbfs:/tmp/delta-test")
    deltaTable.update(condition = "id < 500", set = {"id": "id + 10000"})
    print("✅ Delta table update successful")
except Exception as e:
    print(f"❌ Delta table update failed: {e}")

# Test 4: Time travel
try:
    df_v0 = spark.read.format("delta").option("versionAsOf", 0).load("dbfs:/tmp/delta-test")
    print(f"✅ Delta time travel successful: {df_v0.count()} rows in v0")
except Exception as e:
    print(f"❌ Delta time travel failed: {e}")

# Cleanup
dbutils.fs.rm("dbfs:/tmp/delta-test", recurse=True)
```

---

## 6. Security Testing

### 6.1 Public Access Verification

**Workspace Public Access Check:**
```bash
# ✓ Verify public access disabled
az databricks workspace show \
  --name "${WORKSPACE_NAME}" \
  --resource-group "${RG_NAME}" \
  --query "{PublicAccess:publicNetworkAccessEnabled, NSGRules:parameters.requireNsgRules.value, NoPublicIP:parameters.enableNoPublicIp.value}"

# Expected output:
# {
#   "PublicAccess": false,
#   "NSGRules": "NoAzureDatabricksRules",
#   "NoPublicIP": true
# }
```

**Storage Public Access Check:**
```bash
# ✓ Verify storage account blocks public access
az storage account show \
  --name "${DBFS_STORAGE_NAME}" \
  --resource-group "${MANAGED_RG_NAME}" \
  --query "{PublicAccess:publicNetworkAccess, AllowBlobPublic:allowBlobPublicAccess}"

# Expected:
# {
#   "PublicAccess": "Disabled",
#   "AllowBlobPublic": false
# }
```

### 6.2 Network Security Group Testing

**NSG Rule Validation:**
```bash
# ✓ Check effective NSG rules on Test VM
az network nic list-effective-nsg \
  --resource-group "${TRANSIT_RG_NAME}" \
  --name "${TESTVM_NIC_NAME}" \
  --query "value[].securityRules[?access=='Allow' && direction=='Outbound']" \
  --output table

# Verify:
# ✓ Port 443 allowed to Databricks workspace
# ✓ Port 443 allowed to storage
# ✓ No overly permissive rules (e.g., 0.0.0.0/0 on all ports)
```

### 6.3 Private Endpoint Security

**Endpoint Access Control:**
```bash
# ✓ Verify private endpoints not accessible from internet
# Test from local machine (should timeout or fail):
curl -I --connect-timeout 5 https://adb-<workspace-id>.1.azuredatabricks.net/
# Expected: Connection timeout (no public route)

# ✓ Verify storage not accessible publicly
curl -I --connect-timeout 5 https://<dbfs-name>.blob.core.windows.net/
# Expected: Connection timeout or 403 Forbidden
```

---

## 7. Performance Testing

### 7.1 Workspace Response Time

**Latency Measurements:**
```powershell
# From Test VM - measure workspace response times
$workspace_url = "https://adb-<workspace-id>.1.azuredatabricks.net/"

1..10 | ForEach-Object {
    $start = Get-Date
    try {
        $response = Invoke-WebRequest -Uri $workspace_url -UseBasicParsing -TimeoutSec 10
        $elapsed = ((Get-Date) - $start).TotalMilliseconds
        Write-Host "Request $_ : ${elapsed}ms - Status: $($response.StatusCode)"
    } catch {
        Write-Host "Request $_ : Failed - $_"
    }
    Start-Sleep -Milliseconds 500
}

# Expected: < 500ms average response time
```

### 7.2 Storage Throughput Testing

**Large File Transfer Test:**
```python
# Create 100MB test file
import random
import time

# Write test
data = spark.range(0, 1000000).selectExpr("id", "CAST(rand() * 1000 AS INT) as value")
start = time.time()
data.write.mode("overwrite").parquet("dbfs:/tmp/throughput-test")
write_time = time.time() - start

# Read test
start = time.time()
df = spark.read.parquet("dbfs:/tmp/throughput-test")
count = df.count()
read_time = time.time() - start

print(f"Write time: {write_time:.2f}s")
print(f"Read time: {read_time:.2f}s")
print(f"Read/Write ratio: {read_time/write_time:.2f}")

# Expected:
# Write time < 20s
# Read time < 5s
# Ratio < 0.5 (reads faster than writes)

# Cleanup
dbutils.fs.rm("dbfs:/tmp/throughput-test", recurse=True)
```

---

## 8. Integration Testing

### 8.1 End-to-End Workflow Test

**Complete Data Pipeline:**
```python
# Comprehensive validation notebook

# Step 1: Environment setup
print("=" * 50)
print("PRIVATE LINK E2E VALIDATION")
print("=" * 50)

# Step 2: Cluster info
cluster_id = spark.conf.get('spark.databricks.clusterUsageTags.clusterId')
print(f"\n✓ Cluster ID: {cluster_id}")

# Step 3: DBFS connectivity
dbutils.fs.ls("dbfs:/")
print("✓ DBFS accessible")

# Step 4: Create test data
from pyspark.sql.functions import *
df = spark.range(0, 1000000).selectExpr(
    "id",
    "CAST(rand() * 100 AS INT) as category",
    "rand() * 10000 as value",
    "current_timestamp() as created_at"
)
print(f"✓ Generated {df.count()} rows")

# Step 5: Write to Delta
delta_path = "dbfs:/tmp/e2e-validation"
df.write.format("delta").mode("overwrite").save(delta_path)
print(f"✓ Wrote Delta table to {delta_path}")

# Step 6: Read and transform
delta_df = spark.read.format("delta").load(delta_path)
agg_df = delta_df.groupBy("category").agg(
    count("*").alias("count"),
    avg("value").alias("avg_value"),
    max("value").alias("max_value")
)
print(f"✓ Aggregated {agg_df.count()} categories")

# Step 7: Write results
result_path = "dbfs:/tmp/e2e-results"
agg_df.write.format("delta").mode("overwrite").save(result_path)
print(f"✓ Saved results to {result_path}")

# Step 8: Verify results
result_df = spark.read.format("delta").load(result_path)
print(f"✓ Verified {result_df.count()} result rows")

# Step 9: Cleanup
dbutils.fs.rm(delta_path, recurse=True)
dbutils.fs.rm(result_path, recurse=True)
print("✓ Cleanup complete")

print("\n" + "=" * 50)
print("🎉 E2E VALIDATION PASSED")
print("=" * 50)
```

### 8.2 External Library Testing

**Package Installation:**
```python
# Test library installation through private storage
%pip install requests pandas numpy

import requests
import pandas as pd
import numpy as np

print(f"✅ requests version: {requests.__version__}")
print(f"✅ pandas version: {pd.__version__}")
print(f"✅ numpy version: {np.__version__}")

# If installation succeeds, private endpoint storage access is working
```

---

## Testing Summary Checklist

### Critical Path Testing (Must Pass)
```
☐ Pre-deployment plan shows ~45 resources
☐ VNet peering created and Connected
☐ All 5 private endpoints provisioned
☐ Storage DNS links to Transit VNet exist (Fix #2)
☐ DNS resolves to private IPs from Test VM
☐ Workspace accessible from Test VM browser
☐ Cluster creates successfully
☐ DBFS read/write operations work
☐ Delta Lake operations successful
☐ Public network access disabled
```

### Performance Benchmarks (Should Pass)
```
☐ Workspace page load < 5 seconds
☐ DNS resolution < 100ms
☐ Cluster startup < 8 minutes (single node)
☐ 10M row write < 30 seconds
☐ 10M row read < 10 seconds
☐ Storage throughput > 50 MB/s
```

### Documentation Completeness
```
☐ All test results documented
☐ Any failures investigated and resolved
☐ Performance metrics recorded
☐ Security posture validated
☐ Integration tests passed
```

---

## Troubleshooting Test Failures

### Common Test Failures and Resolutions

**DNS Resolution Fails:**
- Check VNet links exist for all 3 DNS zones
- Verify links include both Data Plane AND Transit VNets
- Clear DNS cache: `Clear-DnsClientCache` (PowerShell)
- Wait 5-10 minutes for DNS propagation

**Workspace Not Accessible:**
- Verify VNet peering status (should be "Connected")
- Check NSG rules allow port 443 outbound
- Validate private endpoint provisioning state
- Confirm workspace provisioning completed

**Storage Operations Timeout:**
- Verify storage DNS resolves to private IPs (Fix #2)
- Check blob AND dfs endpoints exist
- Validate Transit VNet links to storage DNS zones
- Review NSG rules for storage connectivity

**Cluster Creation Fails:**
- Check managed resource group permissions
- Verify subnet delegations correct
- Review NSG associations
- Validate no public IP setting enabled

---

**Document Version:** 1.0  
**Maintainer:** David Torres  
**Last Review:** 2025-11-04  
**Test Coverage:** ~95% of deployment validation scenarios
