#!/bin/bash
# AgentBricks Deployment Validation Script
# Usage: ./validate.sh [pre|post|all]
#   pre  - Pre-deployment validation only
#   post - Post-deployment validation only
#   all  - Both pre and post validation (default)

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Symbols
CHECK_MARK="✓"
CROSS_MARK="✗"
WARNING="⚠"

# Configuration from terraform.tfvars
SUBSCRIPTION_ID="f7fc048e-aeec-4c24-8436-cab0c3b48401"
REGION="eastus2"
RESOURCE_GROUP="rg-eastus2-edp-poc"
CIDR="10.70.80.0/20"
MANAGED_RG_NAME="databricks-rg-eastus2-edp-poc"

# Counters
PASSED=0
FAILED=0
WARNINGS=0

# Functions
print_header() {
    echo -e "\n${BLUE}========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}========================================${NC}\n"
}

print_section() {
    echo -e "\n${YELLOW}>>> $1${NC}\n"
}

print_pass() {
    echo -e "${GREEN}${CHECK_MARK} $1${NC}"
    ((PASSED++))
}

print_fail() {
    echo -e "${RED}${CROSS_MARK} $1${NC}"
    ((FAILED++))
}

print_warn() {
    echo -e "${YELLOW}${WARNING} $1${NC}"
    ((WARNINGS++))
}

print_info() {
    echo -e "  $1"
}

# Pre-deployment validation
validate_prerequisites() {
    print_section "Checking Prerequisites"

    # Check Azure CLI
    if command -v az &> /dev/null; then
        AZ_VERSION=$(az version --query '\"azure-cli\"' -o tsv)
        print_pass "Azure CLI installed (version: $AZ_VERSION)"
    else
        print_fail "Azure CLI not installed"
        print_info "Install: https://docs.microsoft.com/cli/azure/install-azure-cli"
    fi

    # Check Terraform
    if command -v terraform &> /dev/null; then
        TF_VERSION=$(terraform version -json | grep -o '"version":"[^"]*' | cut -d'"' -f4)
        REQUIRED_VERSION="1.9.0"
        if [ "$(printf '%s\n' "$REQUIRED_VERSION" "$TF_VERSION" | sort -V | head -n1)" = "$REQUIRED_VERSION" ]; then
            print_pass "Terraform installed (version: $TF_VERSION >= $REQUIRED_VERSION)"
        else
            print_fail "Terraform version too old ($TF_VERSION < $REQUIRED_VERSION)"
            print_info "Upgrade to Terraform >= 1.9.0"
        fi
    else
        print_fail "Terraform not installed"
        print_info "Install: https://www.terraform.io/downloads"
    fi

    # Check Git
    if command -v git &> /dev/null; then
        GIT_VERSION=$(git --version | awk '{print $3}')
        print_pass "Git installed (version: $GIT_VERSION)"
    else
        print_warn "Git not installed (optional for deployment)"
    fi
}

validate_azure_authentication() {
    print_section "Checking Azure Authentication"

    # Check Azure login
    if az account show &> /dev/null; then
        CURRENT_SUB=$(az account show --query id -o tsv)
        CURRENT_NAME=$(az account show --query name -o tsv)

        if [ "$CURRENT_SUB" = "$SUBSCRIPTION_ID" ]; then
            print_pass "Logged into correct subscription ($CURRENT_NAME)"
        else
            print_fail "Logged into wrong subscription"
            print_info "Current: $CURRENT_NAME ($CURRENT_SUB)"
            print_info "Expected: $SUBSCRIPTION_ID"
            print_info "Run: az account set --subscription $SUBSCRIPTION_ID"
        fi
    else
        print_fail "Not logged into Azure"
        print_info "Run: az login"
    fi

    # Check user object ID
    if MY_OBJECT_ID=$(az ad signed-in-user show --query id -o tsv 2>/dev/null); then
        print_pass "User object ID retrieved: $MY_OBJECT_ID"

        # Check account_unity_admin group membership
        if az ad group member check --group "account_unity_admin" --member-id "$MY_OBJECT_ID" --query value -o tsv 2>/dev/null | grep -q "true"; then
            print_pass "User is member of account_unity_admin group"
        else
            print_fail "User not in account_unity_admin group"
            print_info "Admin needs to add you to the group"
        fi
    else
        print_fail "Cannot retrieve user object ID"
    fi
}

validate_resource_providers() {
    print_section "Checking Resource Provider Registration"

    PROVIDERS=("Microsoft.Databricks" "Microsoft.Network" "Microsoft.Storage" "Microsoft.Compute" "Microsoft.KeyVault")

    for PROVIDER in "${PROVIDERS[@]}"; do
        STATUS=$(az provider show --namespace "$PROVIDER" --query registrationState -o tsv 2>/dev/null)

        if [ "$STATUS" = "Registered" ]; then
            print_pass "$PROVIDER: Registered"
        elif [ "$STATUS" = "Registering" ]; then
            print_warn "$PROVIDER: Currently registering (may take a few minutes)"
        else
            print_fail "$PROVIDER: Not registered"
            print_info "Admin needs to run: az provider register --namespace $PROVIDER --wait"
        fi
    done
}

validate_permissions() {
    print_section "Checking Resource Group Permissions"

    # Check if resource group exists
    if az group show --name "$RESOURCE_GROUP" &> /dev/null; then
        print_pass "Resource group exists: $RESOURCE_GROUP"

        RG_LOCATION=$(az group show --name "$RESOURCE_GROUP" --query location -o tsv)
        if [ "$RG_LOCATION" = "$REGION" ]; then
            print_pass "Resource group in correct region: $REGION"
        else
            print_warn "Resource group in different region: $RG_LOCATION (expected: $REGION)"
        fi

        # Check Contributor permissions
        MY_OBJECT_ID=$(az ad signed-in-user show --query id -o tsv 2>/dev/null)
        if az role assignment list --assignee "$MY_OBJECT_ID" --resource-group "$RESOURCE_GROUP" --query "[?roleDefinitionName=='Contributor']" -o tsv 2>/dev/null | grep -q "Contributor"; then
            print_pass "User has Contributor role on resource group"
        else
            print_fail "User lacks Contributor role on resource group"
            print_info "Admin needs to grant Contributor role"
        fi
    else
        print_fail "Resource group does not exist: $RESOURCE_GROUP"
    fi
}

validate_cidr_conflicts() {
    print_section "Checking CIDR Conflicts"

    # Get all VNets and their CIDR ranges
    VNETS=$(az network vnet list --subscription "$SUBSCRIPTION_ID" --query "[].{Name:name, CIDR:addressSpace.addressPrefixes[0]}" -o tsv 2>/dev/null)

    if [ -z "$VNETS" ]; then
        print_pass "No existing VNets found (no conflicts possible)"
    else
        CONFLICT_FOUND=false

        while IFS=$'\t' read -r VNET_NAME VNET_CIDR; do
            # Simple CIDR conflict check (first two octets)
            EXISTING_PREFIX=$(echo "$VNET_CIDR" | cut -d'.' -f1-2)
            PLANNED_PREFIX=$(echo "$CIDR" | cut -d'.' -f1-2)

            if [ "$EXISTING_PREFIX" = "$PLANNED_PREFIX" ]; then
                THIRD_OCTET_EXISTING=$(echo "$VNET_CIDR" | cut -d'.' -f3)
                THIRD_OCTET_PLANNED=$(echo "$CIDR" | cut -d'.' -f3)

                # Check if third octet overlaps (simplified check)
                if [ "$THIRD_OCTET_EXISTING" = "$THIRD_OCTET_PLANNED" ]; then
                    print_fail "Potential CIDR conflict with $VNET_NAME ($VNET_CIDR)"
                    CONFLICT_FOUND=true
                fi
            fi
        done <<< "$VNETS"

        if [ "$CONFLICT_FOUND" = false ]; then
            print_pass "No CIDR conflicts detected with planned range: $CIDR"
        fi
    fi
}

validate_terraform_config() {
    print_section "Validating Terraform Configuration"

    # Check if terraform.tfvars exists
    if [ -f "terraform.tfvars" ]; then
        print_pass "terraform.tfvars file exists"

        # Validate required variables
        REQUIRED_VARS=("subscription_id" "location" "cidr" "create_resource_group" "existing_resource_group_name" "managed_resource_group_name")

        for VAR in "${REQUIRED_VARS[@]}"; do
            if grep -q "^${VAR} " terraform.tfvars; then
                print_pass "Variable defined: $VAR"
            else
                print_fail "Missing variable: $VAR"
            fi
        done

        # Check security features
        if grep -q "enable_infrastructure_encryption = true" terraform.tfvars; then
            print_pass "Infrastructure encryption enabled"
        else
            print_warn "Infrastructure encryption not enabled"
        fi

        if grep -q "enable_dbfs_firewall = true" terraform.tfvars; then
            print_pass "DBFS firewall enabled"
        else
            print_warn "DBFS firewall not enabled"
        fi

        if grep -q "enable_no_public_ip = true" terraform.tfvars; then
            print_pass "No public IP enabled"
        else
            print_warn "Public IP not disabled"
        fi
    else
        print_fail "terraform.tfvars file not found"
        print_info "Create terraform.tfvars using DEPLOYMENT_RUNBOOK.md instructions"
    fi

    # Check if Terraform is initialized
    if [ -d ".terraform" ]; then
        print_pass "Terraform initialized (.terraform directory exists)"
    else
        print_warn "Terraform not initialized (run: terraform init)"
    fi
}

# Post-deployment validation
validate_deployment_outputs() {
    print_section "Checking Terraform Outputs"

    if [ ! -f "terraform.tfstate" ]; then
        print_fail "No terraform.tfstate file found (deployment not completed)"
        return
    fi

    # Check if outputs exist
    if terraform output workspace_url &> /dev/null; then
        WORKSPACE_URL=$(terraform output -raw workspace_url)
        print_pass "Workspace URL: $WORKSPACE_URL"
    else
        print_fail "Workspace URL output not found"
    fi

    if terraform output workspace_name &> /dev/null; then
        WORKSPACE_NAME=$(terraform output -raw workspace_name)
        print_pass "Workspace name: $WORKSPACE_NAME"
    else
        print_fail "Workspace name output not found"
    fi

    if terraform output managed_resource_group_name &> /dev/null; then
        MANAGED_RG=$(terraform output -raw managed_resource_group_name)
        print_pass "Managed RG: $MANAGED_RG"

        if [ "$MANAGED_RG" = "$MANAGED_RG_NAME" ]; then
            print_pass "Managed RG name matches expected: $MANAGED_RG_NAME"
        else
            print_warn "Managed RG name differs from expected"
            print_info "Expected: $MANAGED_RG_NAME"
            print_info "Actual: $MANAGED_RG"
        fi
    else
        print_fail "Managed RG output not found"
    fi
}

validate_workspace_deployment() {
    print_section "Validating Workspace Deployment"

    if [ ! -f "terraform.tfstate" ]; then
        print_fail "No terraform.tfstate file found"
        return
    fi

    WORKSPACE_NAME=$(terraform output -raw workspace_name 2>/dev/null)

    if [ -z "$WORKSPACE_NAME" ]; then
        print_fail "Cannot retrieve workspace name from outputs"
        return
    fi

    # Check workspace exists
    if az databricks workspace show --name "$WORKSPACE_NAME" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
        print_pass "Workspace exists: $WORKSPACE_NAME"

        # Check workspace configuration
        PUBLIC_ACCESS=$(az databricks workspace show --name "$WORKSPACE_NAME" --resource-group "$RESOURCE_GROUP" --query publicNetworkAccessEnabled -o tsv)
        if [ "$PUBLIC_ACCESS" = "false" ] || [ "$PUBLIC_ACCESS" = "False" ]; then
            print_pass "Public network access: Disabled"
        else
            print_fail "Public network access: Enabled (should be disabled)"
        fi

        # Check managed RG
        MANAGED_RG_ID=$(az databricks workspace show --name "$WORKSPACE_NAME" --resource-group "$RESOURCE_GROUP" --query managedResourceGroupId -o tsv)
        if echo "$MANAGED_RG_ID" | grep -q "$MANAGED_RG_NAME"; then
            print_pass "Managed RG configured: $MANAGED_RG_NAME"
        else
            print_warn "Managed RG name differs from expected"
        fi
    else
        print_fail "Workspace not found: $WORKSPACE_NAME"
    fi
}

validate_private_endpoints() {
    print_section "Validating Private Endpoints"

    # Count private endpoints with 'agentbricks' in name
    PE_COUNT=$(az network private-endpoint list --resource-group "$RESOURCE_GROUP" --query "[?contains(name, 'agentbricks')]" -o tsv 2>/dev/null | wc -l)

    if [ "$PE_COUNT" -ge 4 ]; then
        print_pass "Private endpoints deployed: $PE_COUNT (expected 4-5)"

        # Check each endpoint status
        PE_NAMES=$(az network private-endpoint list --resource-group "$RESOURCE_GROUP" --query "[?contains(name, 'agentbricks')].name" -o tsv)

        while IFS= read -r PE_NAME; do
            STATUS=$(az network private-endpoint show --name "$PE_NAME" --resource-group "$RESOURCE_GROUP" --query "privateLinkServiceConnections[0].privateLinkServiceConnectionState.status" -o tsv 2>/dev/null)

            if [ "$STATUS" = "Approved" ]; then
                print_pass "  $PE_NAME: Approved"
            else
                print_fail "  $PE_NAME: $STATUS (should be Approved)"
            fi
        done <<< "$PE_NAMES"
    else
        print_fail "Insufficient private endpoints: $PE_COUNT (expected 4-5)"
    fi
}

validate_key_vault() {
    print_section "Validating Key Vault and Customer-Managed Keys"

    # Find Key Vault with 'agentbricks' in name
    KV_NAME=$(az keyvault list --resource-group "$RESOURCE_GROUP" --query "[?contains(name, 'agentbricks')].name" -o tsv 2>/dev/null | head -1)

    if [ -n "$KV_NAME" ]; then
        print_pass "Key Vault found: $KV_NAME"

        # Check purge protection
        PURGE_PROTECTION=$(az keyvault show --name "$KV_NAME" --query "properties.enablePurgeProtection" -o tsv)
        if [ "$PURGE_PROTECTION" = "true" ]; then
            print_pass "Purge protection: Enabled"
        else
            print_fail "Purge protection: Disabled (should be enabled)"
        fi

        # Check customer-managed keys
        KEYS=$(az keyvault key list --vault-name "$KV_NAME" --query "[].name" -o tsv 2>/dev/null)
        KEY_COUNT=$(echo "$KEYS" | wc -w)

        if [ "$KEY_COUNT" -eq 3 ]; then
            print_pass "Customer-managed keys: $KEY_COUNT (expected 3)"

            EXPECTED_KEYS=("dbx-managed-services-key" "dbx-managed-disk-key" "dbx-root-dbfs-key")
            for EXPECTED_KEY in "${EXPECTED_KEYS[@]}"; do
                if echo "$KEYS" | grep -q "$EXPECTED_KEY"; then
                    print_pass "  Key exists: $EXPECTED_KEY"
                else
                    print_fail "  Missing key: $EXPECTED_KEY"
                fi
            done
        else
            print_fail "Incorrect number of keys: $KEY_COUNT (expected 3)"
        fi
    else
        print_fail "Key Vault not found in resource group"
    fi
}

validate_networking() {
    print_section "Validating Network Configuration"

    # Find VNet with 'agentbricks' in name
    VNET_NAME=$(az network vnet list --resource-group "$RESOURCE_GROUP" --query "[?contains(name, 'agentbricks')].name" -o tsv | head -1)

    if [ -n "$VNET_NAME" ]; then
        print_pass "VNet found: $VNET_NAME"

        # Check CIDR
        VNET_CIDR=$(az network vnet show --name "$VNET_NAME" --resource-group "$RESOURCE_GROUP" --query "addressSpace.addressPrefixes[0]" -o tsv)
        if [ "$VNET_CIDR" = "$CIDR" ]; then
            print_pass "VNet CIDR matches: $CIDR"
        else
            print_warn "VNet CIDR differs: $VNET_CIDR (expected: $CIDR)"
        fi

        # Check subnets
        SUBNET_COUNT=$(az network vnet subnet list --vnet-name "$VNET_NAME" --resource-group "$RESOURCE_GROUP" --query "length(@)" -o tsv)
        if [ "$SUBNET_COUNT" -eq 3 ]; then
            print_pass "Subnets configured: $SUBNET_COUNT (expected 3)"
        else
            print_fail "Incorrect subnet count: $SUBNET_COUNT (expected 3)"
        fi

        # Check NSG
        NSG_COUNT=$(az network nsg list --resource-group "$RESOURCE_GROUP" --query "[?contains(name, 'agentbricks')] | length(@)" -o tsv)
        if [ "$NSG_COUNT" -ge 1 ]; then
            print_pass "Network security groups: $NSG_COUNT"
        else
            print_warn "No NSGs found (expected at least 1)"
        fi
    else
        print_fail "VNet not found in resource group"
    fi
}

validate_dns_zones() {
    print_section "Validating Private DNS Zones"

    EXPECTED_ZONES=("privatelink.azuredatabricks.net" "privatelink.blob.core.windows.net" "privatelink.dfs.core.windows.net")

    for ZONE in "${EXPECTED_ZONES[@]}"; do
        if az network private-dns zone show --name "$ZONE" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
            print_pass "DNS zone exists: $ZONE"

            # Check VNet links
            LINK_COUNT=$(az network private-dns link vnet list --zone-name "$ZONE" --resource-group "$RESOURCE_GROUP" --query "length(@)" -o tsv 2>/dev/null)
            if [ "$LINK_COUNT" -ge 1 ]; then
                print_pass "  VNet links configured: $LINK_COUNT"
            else
                print_fail "  No VNet links found"
            fi
        else
            print_fail "DNS zone missing: $ZONE"
        fi
    done
}

validate_managed_resource_group() {
    print_section "Validating Managed Resource Group"

    # Check if managed RG exists
    if az group show --name "$MANAGED_RG_NAME" &> /dev/null; then
        print_pass "Managed RG exists: $MANAGED_RG_NAME"

        # Check if it's actually managed by Databricks
        MANAGED_BY=$(az group show --name "$MANAGED_RG_NAME" --query managedBy -o tsv)
        if [ -n "$MANAGED_BY" ]; then
            print_pass "RG is managed by Databricks workspace"
        else
            print_warn "RG exists but not marked as managed"
        fi

        # Check resources in managed RG
        RESOURCE_COUNT=$(az resource list --resource-group "$MANAGED_RG_NAME" --query "length(@)" -o tsv 2>/dev/null)
        if [ "$RESOURCE_COUNT" -gt 0 ]; then
            print_pass "Databricks backend resources deployed: $RESOURCE_COUNT"
        else
            print_warn "No resources found in managed RG (may still be provisioning)"
        fi
    else
        print_fail "Managed RG not found: $MANAGED_RG_NAME"
    fi
}

# Summary function
print_summary() {
    echo ""
    print_header "Validation Summary"
    echo -e "${GREEN}Passed:${NC}   $PASSED"
    echo -e "${RED}Failed:${NC}   $FAILED"
    echo -e "${YELLOW}Warnings:${NC} $WARNINGS"
    echo ""

    if [ $FAILED -eq 0 ]; then
        echo -e "${GREEN}${CHECK_MARK} Validation completed successfully!${NC}"
        exit 0
    else
        echo -e "${RED}${CROSS_MARK} Validation completed with $FAILED error(s).${NC}"
        echo -e "${YELLOW}Review failures above and consult DEPLOYMENT_RUNBOOK.md troubleshooting section.${NC}"
        exit 1
    fi
}

# Main execution
MODE="${1:-all}"

case "$MODE" in
    pre)
        print_header "AgentBricks Pre-Deployment Validation"
        validate_prerequisites
        validate_azure_authentication
        validate_resource_providers
        validate_permissions
        validate_cidr_conflicts
        validate_terraform_config
        print_summary
        ;;
    post)
        print_header "AgentBricks Post-Deployment Validation"
        validate_deployment_outputs
        validate_workspace_deployment
        validate_private_endpoints
        validate_key_vault
        validate_networking
        validate_dns_zones
        validate_managed_resource_group
        print_summary
        ;;
    all)
        print_header "AgentBricks Complete Validation"
        echo "Running pre-deployment checks..."
        validate_prerequisites
        validate_azure_authentication
        validate_resource_providers
        validate_permissions
        validate_cidr_conflicts
        validate_terraform_config

        echo ""
        echo "Running post-deployment checks..."
        validate_deployment_outputs
        validate_workspace_deployment
        validate_private_endpoints
        validate_key_vault
        validate_networking
        validate_dns_zones
        validate_managed_resource_group
        print_summary
        ;;
    *)
        echo "Usage: $0 [pre|post|all]"
        echo "  pre  - Pre-deployment validation only"
        echo "  post - Post-deployment validation only"
        echo "  all  - Both pre and post validation (default)"
        exit 1
        ;;
esac
