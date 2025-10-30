# Azure Databricks PoC Deployment Guide

## Step-by-Step Instructions with Expected Key Results

---

## Table of Contents
1. [Prerequisites Checklist](#prerequisites-checklist)
2. [Phase 1: Service Principal Setup](#phase-1-service-principal-setup)
3. [Phase 2: Deploy PoC Infrastructure](#phase-2-deploy-poc-infrastructure)
4. [Phase 3: Configure Active Directory Integration](#phase-3-configure-active-directory-integration)
5. [Phase 4: Validate Connectivity](#phase-4-validate-connectivity)
6. [Phase 5: Cleanup](#phase-5-cleanup)
7. [Troubleshooting](#troubleshooting)

---

## Prerequisites Checklist

Before starting, ensure you have:

- [ ] Azure subscription with Contributor access
- [ ] Azure AD Global Administrator role (temporary, for SPN creation)
- [ ] Databricks Account ID (from Databricks representative)
- [ ] Azure CLI installed (`az --version`)
- [ ] Terraform >= 1.9.0 installed (`terraform --version`)
- [ ] Git installed
- [ ] Network connectivity to Azure
- [ ] Approval for the following Azure resources:
  - 2 Resource Groups
  - 2 VNets (CIDR ranges: 10.180.0.0/20 and 10.181.0.0/20)
  - 2 Azure Databricks Workspaces (Premium SKU)
  - 5 Private Endpoints
  - 3 Private DNS Zones
  - 1 Windows Test VM

**Estimated Total Time**: 2-3 hours
**Estimated Monthly Cost**: $2,000-3,000 USD (workspace + compute)

---

## Phase 1: Service Principal Setup

### Step 1.1: Clone Repository and Navigate to Stage 1

```bash
# Clone the repository if not already done
git clone https://github.com/databricks/terraform-databricks-examples.git
cd terraform-databricks-examples/examples/adb-uc/stage_1_spawn_global_admin_spn/
```

**Expected Result**: You should be in the `stage_1_spawn_global_admin_spn/` directory.

---

### Step 1.2: Authenticate to Azure

```bash
# Login interactively with an account that has Global Admin privileges
az login

# Verify your login
az account show
```

**Expected Key Results**:
```json
{
  "environmentName": "AzureCloud",
  "id": "<your-subscription-id>",
  "isDefault": true,
  "name": "<your-subscription-name>",
  "state": "Enabled",
  "tenantId": "<your-tenant-id>",
  "user": {
    "name": "<your-email>",
    "type": "user"
  }
}
```

**Verify**: Confirm the subscription ID and tenant ID are correct.

---

### Step 1.3: Review and Deploy Stage 1 (Create Global Admin SPN)

```bash
# Review the Terraform configuration
cat spn.tf

# Initialize Terraform
terraform init

# Review the plan
terraform plan

# Apply to create the Global Admin SPN
terraform apply
```

**Expected Key Results**:

**During `terraform init`**:
```
Initializing the backend...
Initializing provider plugins...
- Finding latest version of hashicorp/azuread...
- Finding latest version of hashicorp/azurerm...
- Installing hashicorp/azuread...
- Installed hashicorp/azuread (signed by HashiCorp)

Terraform has been successfully initialized!
```

**During `terraform apply`**:
```
Terraform will perform the following actions:

  # azuread_application.this will be created
  # azuread_application_password.this will be created
  # azuread_directory_role_assignment.global_admin will be created
  # azuread_service_principal.this will be created

Plan: 4 to add, 0 to change, 0 to destroy.

Do you want to perform these actions?
  Terraform will perform the actions described above.
  Only 'yes' will be accepted to approve.

  Enter a value: yes

Apply complete! Resources: 4 added, 0 changed, 0 destroyed.

Outputs:

spn_application_id = "<application-id>"
spn_client_secret = <sensitive>
spn_object_id = "<object-id>"
tenant_id = "<tenant-id>"
```

**Important**: Save these outputs securely:
```bash
# Save the outputs to a secure location
terraform output -json > ../spn-stage1-outputs.json
terraform output spn_client_secret
```

**Verify in Azure Portal**:
1. Navigate to **Azure Active Directory** > **Roles and administrators**
2. Click on **Global Administrator**
3. Verify you see the newly created Service Principal listed

---

### Step 1.4: Deploy Stage 2 (Make SPN a Databricks Account Admin)

```bash
# Navigate to Stage 2
cd ../stage_2_getting_first_second_account_admin/

# Review the provider configuration
cat providers.tf
```

**Action Required**: Edit `providers.tf` and update the `account_id`:

```hcl
provider "databricks" {
  alias      = "azure_account"
  host       = "https://accounts.azuredatabricks.net"
  account_id = "<YOUR-DATABRICKS-ACCOUNT-ID>"  # Update this!
  auth_type  = "azure-cli"
}
```

**Login as the Service Principal**:
```bash
# Get the credentials from Stage 1 output
APP_ID=$(cd ../stage_1_spawn_global_admin_spn && terraform output -raw spn_application_id)
CLIENT_SECRET=$(cd ../stage_1_spawn_global_admin_spn && terraform output -raw spn_client_secret)
TENANT_ID=$(cd ../stage_1_spawn_global_admin_spn && terraform output -raw tenant_id)

# Login as the SPN
az login --service-principal -u $APP_ID -p $CLIENT_SECRET --tenant $TENANT_ID
```

**Expected Key Results**:
```json
[
  {
    "cloudName": "AzureCloud",
    "homeTenantId": "<tenant-id>",
    "id": "<subscription-id>",
    "isDefault": true,
    "name": "<subscription-name>",
    "state": "Enabled",
    "tenantId": "<tenant-id>",
    "user": {
      "name": "<app-id>",
      "type": "servicePrincipal"
    }
  }
]
```

**Deploy Stage 2**:
```bash
# Create a variable file with the SPN ID
cat > terraform.tfvars <<EOF
long_lasting_spn_id = "$APP_ID"
EOF

# Initialize and apply
terraform init
terraform apply
```

**Expected Key Results**:
```
Apply complete! Resources: 1 added, 0 changed, 0 destroyed.

Outputs:

account_admin_spn_id = "<app-id>"
```

**Verify**: The SPN is now a Databricks Account Admin. At this point, you can remove the Global Admin role from the SPN.

---

### Step 1.5: (Optional) Remove Global Admin Role

Since the SPN is now a Databricks Account Admin, you can remove the AAD Global Admin role to minimize privilege exposure:

```bash
# Switch back to your user account
az login

# Navigate back to Stage 1
cd ../stage_1_spawn_global_admin_spn/

# You can optionally remove the global admin role assignment
# Or keep it if you need it for future operations
```

---

## Phase 2: Deploy PoC Infrastructure

### Step 2.1: Navigate to Private Link Standard Example

```bash
cd ../../adb-with-private-link-standard/
```

---

### Step 2.2: Configure Variables

Create or edit `terraform.tfvars`:

```bash
cat > terraform.tfvars <<EOF
# Azure Configuration
subscription_id = "<YOUR-AZURE-SUBSCRIPTION-ID>"
location        = "eastus"  # or your preferred region

# Network Configuration
cidr_dp      = "10.180.0.0/20"  # Data Plane VNet
cidr_transit = "10.181.0.0/20"  # Transit VNet

# Resource Group Configuration
create_data_plane_resource_group     = true
create_transit_resource_group        = true
existing_data_plane_resource_group_name = ""
existing_transit_resource_group_name    = ""
EOF
```

**Expected Result**: The `terraform.tfvars` file is created with your specific values.

---

### Step 2.3: Review Provider Configuration

```bash
# Review the providers
cat providers.tf
```

**Expected Content**:
```hcl
terraform {
  required_version = ">= 1.9.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">=4.0.0"
    }
  }
}

provider "azurerm" {
  subscription_id = var.subscription_id
  features {}
}
```

---

### Step 2.4: Initialize Terraform

```bash
# Login with your user account or the SPN
az login  # OR az login --service-principal -u $APP_ID -p $CLIENT_SECRET --tenant $TENANT_ID

# Initialize Terraform
terraform init
```

**Expected Key Results**:
```
Initializing modules...
- adb-with-private-link-standard in ../../modules/adb-with-private-link-standard

Initializing the backend...

Initializing provider plugins...
- Finding hashicorp/azurerm versions matching ">=4.0.0"...
- Finding latest version of hashicorp/random...
- Finding latest version of hashicorp/external...
- Finding latest version of hashicorp/http...
- Installing hashicorp/azurerm v4.x.x...
- Installed hashicorp/azurerm v4.x.x (signed by HashiCorp)

Terraform has been successfully initialized!
```

---

### Step 2.5: Plan the Deployment

```bash
# Review what will be created
terraform plan -out=tfplan
```

**Expected Key Results**:
```
Terraform will perform the following actions:

  # module.adb-with-private-link-standard.azurerm_databricks_workspace.dp_workspace will be created
  # module.adb-with-private-link-standard.azurerm_databricks_workspace.transit_workspace will be created
  # module.adb-with-private-link-standard.azurerm_virtual_network.dp_vnet will be created
  # module.adb-with-private-link-standard.azurerm_virtual_network.transit_vnet will be created
  # module.adb-with-private-link-standard.azurerm_private_endpoint.dp_dpcp will be created
  # module.adb-with-private-link-standard.azurerm_private_endpoint.front_pe will be created
  # module.adb-with-private-link-standard.azurerm_private_endpoint.transit_auth will be created
  # module.adb-with-private-link-standard.azurerm_private_endpoint.dp_dbfspe_blob will be created
  # module.adb-with-private-link-standard.azurerm_private_endpoint.dp_dbfspe_dfs will be created
  # ... (and many more resources)

Plan: 50-60 to add, 0 to change, 0 to destroy.

Changes to Outputs:
  + test_vm_password  = (sensitive value)
  + test_vm_public_ip = (known after apply)
  + workspace_id      = (known after apply)
  + workspace_url     = (known after apply)
```

**Review**: Verify the resource count and types look correct.

---

### Step 2.6: Apply the Configuration

```bash
# Deploy the infrastructure
terraform apply tfplan
```

**Expected Duration**: 45-60 minutes

**Expected Key Results** (Progressive output):

**Phase 1 - Resource Groups** (2-3 minutes):
```
module.adb-with-private-link-standard.azurerm_resource_group.dp_rg: Creating...
module.adb-with-private-link-standard.azurerm_resource_group.transit_rg: Creating...
module.adb-with-private-link-standard.azurerm_resource_group.dp_rg: Creation complete
module.adb-with-private-link-standard.azurerm_resource_group.transit_rg: Creation complete
```

**Phase 2 - Networking** (5-10 minutes):
```
module.adb-with-private-link-standard.azurerm_virtual_network.dp_vnet: Creating...
module.adb-with-private-link-standard.azurerm_virtual_network.transit_vnet: Creating...
module.adb-with-private-link-standard.azurerm_network_security_group.dp_sg: Creating...
module.adb-with-private-link-standard.azurerm_subnet.dp_public: Creating...
module.adb-with-private-link-standard.azurerm_subnet.dp_private: Creating...
```

**Phase 3 - Databricks Workspaces** (30-40 minutes):
```
module.adb-with-private-link-standard.azurerm_databricks_workspace.dp_workspace: Creating...
module.adb-with-private-link-standard.azurerm_databricks_workspace.transit_workspace: Creating...
module.adb-with-private-link-standard.azurerm_databricks_workspace.dp_workspace: Still creating... [10m0s elapsed]
module.adb-with-private-link-standard.azurerm_databricks_workspace.dp_workspace: Still creating... [20m0s elapsed]
module.adb-with-private-link-standard.azurerm_databricks_workspace.dp_workspace: Creation complete after 25m15s
```

**Phase 4 - Private Endpoints** (10-15 minutes):
```
module.adb-with-private-link-standard.azurerm_private_dns_zone.dnsdpcp: Creating...
module.adb-with-private-link-standard.azurerm_private_endpoint.dp_dpcp: Creating...
module.adb-with-private-link-standard.azurerm_private_endpoint.front_pe: Creating...
module.adb-with-private-link-standard.azurerm_private_endpoint.transit_auth: Creating...
module.adb-with-private-link-standard.azurerm_private_endpoint.dp_dbfspe_blob: Creating...
```

**Final Output**:
```
Apply complete! Resources: 55 added, 0 changed, 0 destroyed.

Outputs:

test_vm_password = <sensitive>
test_vm_public_ip = "20.xxx.xxx.xxx"
workspace_id = "/subscriptions/<sub-id>/resourceGroups/<rg-name>/providers/Microsoft.Databricks/workspaces/<workspace-name>"
workspace_url = "adb-1234567890123456.7.azuredatabricks.net"
```

---

### Step 2.7: Save Critical Information

```bash
# Save outputs to a file
terraform output -json > deployment-outputs.json

# Display the workspace URL
echo "Workspace URL: $(terraform output -raw workspace_url)"

# Display test VM information
echo "Test VM IP: $(terraform output -raw test_vm_public_ip)"
echo "Test VM Password: $(terraform output -raw test_vm_password)"
```

**Expected Key Results**:
```
Workspace URL: adb-1234567890123456.7.azuredatabricks.net
Test VM IP: 20.xxx.xxx.xxx
Test VM Password: <complex-password>
```

**Action**: Save these credentials securely (e.g., password manager, Azure Key Vault).

---

### Step 2.8: Verify Resources in Azure Portal

**Navigate to Azure Portal** (https://portal.azure.com):

1. **Resource Groups**: Verify two new resource groups exist:
   - `rg-<random>-poc-dp` (Data Plane)
   - `rg-<random>-poc-transit` (Transit)

2. **Databricks Workspaces**:
   - Data Plane workspace: `adb-<random>-poc-dp`
   - Transit workspace: `adb-<random>-poc-transit` (for browser auth)

3. **Virtual Networks**:
   - `vnet-<random>-poc-dp` (10.180.0.0/20)
   - `vnet-<random>-poc-transit` (10.181.0.0/20)

4. **Private Endpoints** (should see 5 total):
   - `pe-dpcp-<random>` (back-end connectivity)
   - `pe-front-<random>` (front-end connectivity)
   - `pe-auth-<random>` (browser authentication)
   - `pe-dbfs-blob-<random>` (DBFS blob storage)
   - `pe-dbfs-dfs-<random>` (DBFS DFS storage)

5. **Private DNS Zones** (should see 3):
   - `privatelink.azuredatabricks.net`
   - `privatelink.blob.core.windows.net`
   - `privatelink.dfs.core.windows.net`

**Expected Result**: All resources are created successfully with "Succeeded" provisioning state.

---

## Phase 3: Configure Active Directory Integration

### Step 3.1: Access Databricks Workspace Admin Console

**From the Test VM** (since public access is disabled):

1. RDP to the Test VM:
   - IP: `<test_vm_public_ip>`
   - Username: `testadmin`
   - Password: `<test_vm_password>`

2. Open a web browser inside the VM

3. Navigate to: `https://<workspace_url>`

**Expected Key Result**: The Databricks login page loads successfully through the private endpoint.

---

### Step 3.2: Initial Login

Use one of these methods:

**Option A**: Azure AD User (if you have workspace access)
- Click "Sign in with Azure AD"
- Authenticate with your Azure AD credentials

**Option B**: Databricks Admin (first-time setup)
- Use the Account Admin SPN credentials to grant access to your user account

**Expected Key Result**: You successfully log into the Databricks workspace.

---

### Step 3.3: Enable SCIM Provisioning

**In the Databricks Workspace**:

1. Click on your username (top right) → **Admin Settings**
2. Navigate to **Identity and access** → **SCIM provisioning**
3. Click **Generate new token**
4. Copy the token (you won't see it again)

**Expected Key Result**:
```
Token: dapi<YOUR-GENERATED-TOKEN-HERE>
SCIM URL: https://<workspace_url>/api/2.0/account/scim/v2
```

**Action**: Save the SCIM token securely.

---

### Step 3.4: Configure Azure AD Enterprise Application

**In Azure Portal**:

1. Navigate to **Azure Active Directory** → **Enterprise applications**
2. Click **+ New application**
3. Search for "Azure Databricks SCIM Provisioning"
4. Click **Create**

5. Once created, navigate to **Provisioning**:
   - Set Provisioning Mode: **Automatic**
   - Tenant URL: `https://<workspace_url>/api/2.0/account/scim/v2`
   - Secret Token: `<SCIM-token-from-step-3.3>`
   - Click **Test Connection**

**Expected Key Result**:
```
✓ The supplied credentials are authorized to enable provisioning
```

6. Click **Save**
7. Set Provisioning Status: **On**

---

### Step 3.5: Assign Users and Groups

**In the Enterprise Application**:

1. Navigate to **Users and groups**
2. Click **+ Add user/group**
3. Select users/groups to sync to Databricks
4. Click **Assign**

**Expected Key Result**: Users and groups are assigned to the application.

---

### Step 3.6: Trigger Initial Sync

1. Navigate back to **Provisioning**
2. Click **Start provisioning**

**Expected Duration**: 5-10 minutes for initial sync

**Expected Key Result** (in Provisioning logs):
```
Action: Create
Status: Success
User: john.doe@company.com
Details: Successfully created user in Databricks
```

---

### Step 3.7: Verify Users in Databricks

**Back in Databricks Workspace**:

1. Navigate to **Admin Settings** → **Identity and access** → **Users**
2. Verify synced users appear in the list

**Expected Key Result**: All assigned Azure AD users are visible in the Databricks user list.

---

## Phase 4: Validate Connectivity

### Step 4.1: Test Private Endpoint Connectivity

**From the Test VM**:

```powershell
# Test workspace connectivity
nslookup <workspace_url>
# Expected: Should resolve to a private IP in the 10.181.x.x range

# Test DBFS blob storage
$workspaceId = "<workspace-id-from-url>"
nslookup "$workspaceId.blob.core.windows.net"
# Expected: Should resolve to a private IP in the 10.180.x.x range

# Test DBFS DFS storage
nslookup "$workspaceId.dfs.core.windows.net"
# Expected: Should resolve to a private IP in the 10.180.x.x range
```

**Expected Key Results**:
```
Server:  UnKnown
Address:  168.63.129.16

Name:    adb-1234567890123456.7.azuredatabricks.net
Addresses:  10.181.2.4  ← Private IP from Transit VNet
```

**Verify**: All DNS resolutions point to private IPs, not public IPs.

---

### Step 4.2: Create a Test Cluster

**In Databricks Workspace**:

1. Click **Compute** in the left sidebar
2. Click **+ Create Cluster**
3. Configure:
   - Cluster name: `poc-test-cluster`
   - Cluster mode: **Single Node**
   - Databricks runtime: **13.3 LTS (Scala 2.12, Spark 3.4.1)** (or latest LTS)
   - Node type: **Standard_DS3_v2**
   - Auto termination: **30 minutes**
4. Click **Create Cluster**

**Expected Duration**: 5-7 minutes

**Expected Key Result**:
```
Cluster State: Running
Driver IP: 10.180.0.x (private IP from Data Plane VNet)
```

---

### Step 4.3: Create and Run a Test Notebook

**In Databricks Workspace**:

1. Click **Workspace** → **Create** → **Notebook**
2. Name: `PoC Connectivity Test`
3. Default Language: **Python**
4. Cluster: Select `poc-test-cluster`

**Add and run the following cells**:

**Cell 1: Test Spark**
```python
# Test Spark functionality
df = spark.range(1000)
print(f"Created DataFrame with {df.count()} rows")
```

**Expected Output**:
```
Created DataFrame with 1000 rows
```

**Cell 2: Test DBFS Access**
```python
# Test DBFS connectivity
dbutils.fs.ls("dbfs:/")
```

**Expected Output**:
```
[FileInfo(path='dbfs:/FileStore/', name='FileStore/', size=0),
 FileInfo(path='dbfs:/databricks-datasets/', name='databricks-datasets/', size=0),
 FileInfo(path='dbfs:/databricks-results/', name='databricks-results/', size=0),
 ...]
```

**Cell 3: Test External Connectivity**
```python
# Test outbound connectivity
import requests
response = requests.get('https://httpbin.org/ip')
print(f"Status: {response.status_code}")
print(f"Response: {response.text}")
```

**Expected Output**:
```
Status: 200
Response: {"origin": "<azure-ip-address>"}
```

**Cell 4: Write and Read from DBFS**
```python
# Test DBFS write/read through private endpoint
test_data = spark.range(100).selectExpr("id", "id * 2 as value")
test_path = "dbfs:/tmp/poc-test.parquet"

# Write
test_data.write.mode("overwrite").parquet(test_path)
print(f"Successfully wrote to {test_path}")

# Read
read_data = spark.read.parquet(test_path)
print(f"Successfully read {read_data.count()} rows from {test_path}")
```

**Expected Output**:
```
Successfully wrote to dbfs:/tmp/poc-test.parquet
Successfully read 100 rows from dbfs:/tmp/poc-test.parquet
```

**Expected Key Result**: All cells execute successfully, confirming:
- Spark compute works
- DBFS access through private endpoints works
- External connectivity works
- Data can be written/read through private storage endpoints

---

### Step 4.4: Test Azure AD SSO

**Test from Your Local Machine** (not the test VM):

1. Open an incognito/private browser window
2. Navigate to `https://<workspace_url>`

**Expected Behavior**:
- Since your machine doesn't have access to the private endpoint, the connection should fail or timeout
- This confirms that public access is properly disabled

**Expected Result**:
```
Connection timed out or refused
```

**This is the correct behavior** - the workspace is only accessible through private endpoints.

---

### Step 4.5: Test Azure AD SSO from Test VM

**From the Test VM**:

1. Open a new browser (or new incognito window)
2. Navigate to `https://<workspace_url>`
3. Click **Sign in with Azure AD**
4. Enter Azure AD user credentials (synced via SCIM)
5. Complete MFA if required

**Expected Key Result**:
```
✓ Successfully logged in
✓ Redirected to Databricks workspace home page
✓ Username displayed in top-right matches Azure AD user
```

---

### Step 4.6: Verify Network Security

**Check that traffic flows through private endpoints**:

1. In Azure Portal, navigate to **Resource Group** → `rg-<random>-poc-dp`
2. Click on Private Endpoint `pe-dpcp-<random>`
3. Click **Metrics** (under Monitoring)
4. Add metric: **Bytes In** and **Bytes Out**
5. Time range: **Last 30 minutes**

**Expected Key Result**: You should see network traffic metrics showing data flowing through the private endpoint.

---

## Phase 5: Cleanup

### Step 5.1: Terminate Clusters

**In Databricks Workspace**:

1. Navigate to **Compute**
2. Select `poc-test-cluster`
3. Click **Terminate**

**Expected Key Result**:
```
Cluster State: Terminated
```

---

### Step 5.2: Destroy Infrastructure with Terraform

```bash
# From the adb-with-private-link-standard directory
cd ~/terraform-databricks-examples/examples/adb-with-private-link-standard/

# Review what will be destroyed
terraform plan -destroy

# Destroy all resources
terraform destroy
```

**Expected Duration**: 20-30 minutes

**Expected Key Results**:
```
Plan: 0 to add, 0 to change, 55 to destroy.

Do you really want to destroy all resources?
  Terraform will destroy all your managed infrastructure, as shown above.
  There is no undo. Only 'yes' will be accepted to confirm.

  Enter a value: yes

module.adb-with-private-link-standard.azurerm_private_endpoint.front_pe: Destroying...
module.adb-with-private-link-standard.azurerm_databricks_workspace.dp_workspace: Destroying...
...
Destroy complete! Resources: 55 destroyed.
```

---

### Step 5.3: (Optional) Clean Up Service Principal

If you no longer need the Service Principal:

```bash
# Navigate to Stage 1
cd ../../adb-uc/stage_1_spawn_global_admin_spn/

# Login with your user account (with Global Admin)
az login

# Destroy the SPN
terraform destroy
```

**Expected Key Result**:
```
Destroy complete! Resources: 4 destroyed.
```

---

### Step 5.4: Verify Cleanup in Azure Portal

**Check Resource Groups**:
1. Navigate to **Resource Groups**
2. Verify the PoC resource groups are deleted:
   - `rg-<random>-poc-dp` → **Deleted**
   - `rg-<random>-poc-transit` → **Deleted**

**Check Azure AD Enterprise Application**:
1. Navigate to **Azure Active Directory** → **Enterprise applications**
2. Find the Databricks SCIM app
3. Delete it manually if needed

**Expected Result**: All PoC resources are removed from your subscription.

---

## Troubleshooting

### Issue 1: Workspace Creation Fails

**Symptom**:
```
Error: creating Databricks Workspace: network configuration is invalid
```

**Resolution**:
- Verify CIDR ranges don't overlap with existing VNets
- Ensure subnets are delegated to `Microsoft.Databricks/workspaces`
- Check NSG rules allow required Databricks traffic

---

### Issue 2: Private Endpoint DNS Not Resolving

**Symptom**:
```
nslookup returns public IP instead of private IP
```

**Resolution**:
- Verify Private DNS Zone is linked to the VNet
- Check that the test VM is using Azure-provided DNS (168.63.129.16)
- Flush DNS cache: `ipconfig /flushdns` (Windows) or `sudo systemd-resolve --flush-caches` (Linux)

---

### Issue 3: SCIM Provisioning Test Connection Fails

**Symptom**:
```
✗ The supplied credentials are not authorized
```

**Resolution**:
- Verify the SCIM token is correct (regenerate if needed)
- Ensure the SCIM URL uses `https://` and includes `/api/2.0/account/scim/v2`
- Check that the user generating the token has Admin privileges

---

### Issue 4: Cluster Fails to Start

**Symptom**:
```
Cluster State: Terminated
Error: Network connectivity issues
```

**Resolution**:
- Check NSG rules on Data Plane subnets
- Verify private endpoint for DBFS is properly configured
- Ensure route tables allow traffic to Azure services
- Check that the managed resource group has required permissions

---

### Issue 5: Can't Access Workspace from Test VM

**Symptom**:
```
Browser shows: "This site can't be reached"
```

**Resolution**:
- Verify test VM is in the Transit VNet
- Check that the front-end private endpoint is in "Succeeded" state
- Confirm DNS resolution points to private IP
- Verify NSG on test VM subnet allows outbound HTTPS (port 443)

---

### Issue 6: Terraform Apply Times Out

**Symptom**:
```
Error: context deadline exceeded
```

**Resolution**:
- Workspace creation can take 30-40 minutes - this is normal
- If timeout occurs, check Azure Portal for resource status
- Run `terraform apply` again if resources partially created
- Use `terraform import` for resources that were created but not tracked

---

## Validation Checklist

After completing all phases, verify:

- [ ] Two resource groups created in separate Azure regions (optional) or same region
- [ ] Two Databricks workspaces deployed (Data Plane + Transit/Auth)
- [ ] Five private endpoints configured and in "Succeeded" state
- [ ] Three private DNS zones created and linked to VNets
- [ ] Test VM can access workspace URL via private endpoint
- [ ] DNS resolution returns private IPs (not public)
- [ ] Azure AD users synced to Databricks workspace
- [ ] SSO login works with Azure AD credentials
- [ ] Test cluster created and started successfully
- [ ] Test notebook executed successfully
- [ ] DBFS read/write operations work through private endpoints
- [ ] Network traffic flows through private endpoints (verified in metrics)
- [ ] Public access to workspace is blocked (tested from local machine)

**If all items are checked**: Your PoC environment is successfully deployed and validated!

---

## Next Steps After Validation

1. **Document Findings**: Capture performance, user experience, and any issues
2. **Cost Analysis**: Review Azure Cost Management for actual spend
3. **Security Review**: Validate with security team that all requirements are met
4. **Plan Production**: Identify any gaps between PoC and production requirements
5. **Knowledge Transfer**: Document architecture and share with operations team
6. **Schedule Cleanup**: Set a calendar reminder for PoC expiration date

---

## Additional Resources

- **Azure Databricks Documentation**: https://learn.microsoft.com/en-us/azure/databricks/
- **Private Link Documentation**: https://learn.microsoft.com/en-us/azure/databricks/security/network/classic/private-link
- **Terraform Registry - Databricks Provider**: https://registry.terraform.io/providers/databricks/databricks/latest/docs
- **Repository Examples**: https://github.com/databricks/terraform-databricks-examples

---

## Support

For issues with:
- **Azure Resources**: Azure Support Portal
- **Databricks Platform**: Databricks Support (support@databricks.com)
- **Terraform Examples**: GitHub Issues (terraform-databricks-examples repository)

---

**Document Version**: 1.0
**Last Updated**: 2025-10-30
**Estimated Deployment Time**: 2-3 hours
**Skill Level Required**: Intermediate to Advanced
