#!/bin/bash
# Cleanup Script for AgentBricks and Old Deployments
# Purpose: Clean up orphaned resources from partial deployments

set -e

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
SUBSCRIPTION_ID="f7fc048e-aeec-4c24-8436-cab0c3b48401"
RESOURCE_GROUP="rg-eastus2-edp-poc"
AGENTBRICKS_PREFIX="agentbricks-7b3ff5"
MANAGED_RG_AGENTBRICKS="databricks-rg-eastus2-edp-poc"
MANAGED_RG_OLD="databricks-rg-rg-eastus2-edp-poc"

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Databricks Deployment Cleanup Script${NC}"
echo -e "${BLUE}========================================${NC}\n"

# Verify Azure login
echo -e "${YELLOW}>>> Verifying Azure authentication...${NC}"
if ! az account show &> /dev/null; then
    echo -e "${RED}Not logged into Azure. Run: az login${NC}"
    exit 1
fi

CURRENT_SUB=$(az account show --query id -o tsv)
if [ "$CURRENT_SUB" != "$SUBSCRIPTION_ID" ]; then
    echo -e "${YELLOW}Switching to subscription: $SUBSCRIPTION_ID${NC}"
    az account set --subscription "$SUBSCRIPTION_ID"
fi
echo -e "${GREEN}✓ Authenticated to subscription: $SUBSCRIPTION_ID${NC}\n"

# Function to delete resource with error handling
delete_resource() {
    local resource_id=$1
    local resource_name=$2

    echo -e "${YELLOW}Deleting: $resource_name${NC}"
    if az resource delete --ids "$resource_id" 2>/dev/null; then
        echo -e "${GREEN}✓ Deleted: $resource_name${NC}"
        return 0
    else
        echo -e "${RED}✗ Failed to delete: $resource_name (may not exist)${NC}"
        return 1
    fi
}

# =============================================================================
# PART 1: Clean Up Orphaned AgentBricks Resources
# =============================================================================

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}PART 1: AgentBricks Orphaned Resources${NC}"
echo -e "${BLUE}========================================${NC}\n"

echo -e "${YELLOW}>>> Searching for orphaned AgentBricks resources...${NC}\n"

# Delete orphaned UI/API private endpoint
PE_UIAPI_NAME="${AGENTBRICKS_PREFIX}-pe-databricks-uiapi"
echo -e "${YELLOW}Checking for: $PE_UIAPI_NAME${NC}"
if az network private-endpoint show --name "$PE_UIAPI_NAME" --resource-group "$RESOURCE_GROUP" &> /dev/null; then
    echo -e "${YELLOW}Found orphaned private endpoint: $PE_UIAPI_NAME${NC}"
    if az network private-endpoint delete --name "$PE_UIAPI_NAME" --resource-group "$RESOURCE_GROUP" --yes; then
        echo -e "${GREEN}✓ Deleted: $PE_UIAPI_NAME${NC}"
    else
        echo -e "${RED}✗ Failed to delete: $PE_UIAPI_NAME${NC}"
    fi
else
    echo -e "${GREEN}✓ No orphaned UI/API endpoint found${NC}"
fi

# Check for any other orphaned agentbricks resources
echo -e "\n${YELLOW}>>> Checking for other orphaned AgentBricks resources...${NC}"
ORPHANED_RESOURCES=$(az resource list --resource-group "$RESOURCE_GROUP" --query "[?contains(name, '$AGENTBRICKS_PREFIX')].[id,name,type]" -o tsv)

if [ -z "$ORPHANED_RESOURCES" ]; then
    echo -e "${GREEN}✓ No other orphaned AgentBricks resources found${NC}"
else
    echo -e "${YELLOW}Found orphaned resources:${NC}"
    echo "$ORPHANED_RESOURCES"
    echo -e "\n${YELLOW}Do you want to delete these resources? (yes/no)${NC}"
    read -r response
    if [ "$response" = "yes" ]; then
        while IFS=$'\t' read -r resource_id resource_name resource_type; do
            delete_resource "$resource_id" "$resource_name ($resource_type)"
        done <<< "$ORPHANED_RESOURCES"
    else
        echo -e "${YELLOW}Skipping orphaned resource cleanup${NC}"
    fi
fi

echo -e "\n${GREEN}✓ AgentBricks orphaned resource cleanup complete${NC}\n"

# =============================================================================
# PART 2: Clean Up Old adb-with-private-link-standard Deployment
# =============================================================================

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}PART 2: Old Deployment Cleanup${NC}"
echo -e "${BLUE}========================================${NC}\n"

echo -e "${YELLOW}>>> Searching for old deployment resources...${NC}\n"

# Check for malformed managed RG
echo -e "${YELLOW}Checking for malformed managed RG: $MANAGED_RG_OLD${NC}"
if az group show --name "$MANAGED_RG_OLD" &> /dev/null; then
    echo -e "${RED}Found malformed managed RG: $MANAGED_RG_OLD${NC}"

    # List resources in the managed RG
    echo -e "\n${YELLOW}Resources in malformed managed RG:${NC}"
    az resource list --resource-group "$MANAGED_RG_OLD" --query "[].{Name:name, Type:type}" -o table

    echo -e "\n${RED}⚠️  WARNING: This is a Databricks managed resource group${NC}"
    echo -e "${RED}⚠️  Deleting it may orphan Databricks backend resources${NC}"
    echo -e "${YELLOW}Do you want to force delete this resource group? (yes/no)${NC}"
    read -r response
    if [ "$response" = "yes" ]; then
        echo -e "${YELLOW}Force deleting managed RG: $MANAGED_RG_OLD${NC}"
        if az group delete --name "$MANAGED_RG_OLD" --yes --no-wait; then
            echo -e "${GREEN}✓ Deletion initiated for: $MANAGED_RG_OLD (async)${NC}"
            echo -e "${YELLOW}Note: Deletion will continue in background. Check status with:${NC}"
            echo -e "  az group show --name $MANAGED_RG_OLD"
        else
            echo -e "${RED}✗ Failed to delete: $MANAGED_RG_OLD${NC}"
        fi
    else
        echo -e "${YELLOW}Skipping managed RG deletion${NC}"
    fi
else
    echo -e "${GREEN}✓ No malformed managed RG found${NC}"
fi

# Look for tfdemo resources (from error message)
echo -e "\n${YELLOW}>>> Checking for tfdemo workspace resources...${NC}"
TFDEMO_RESOURCES=$(az resource list --resource-group "$RESOURCE_GROUP" --query "[?contains(name, 'tfdemo')].[id,name,type]" -o tsv)

if [ -z "$TFDEMO_RESOURCES" ]; then
    echo -e "${GREEN}✓ No tfdemo resources found${NC}"
else
    echo -e "${YELLOW}Found tfdemo resources:${NC}"
    echo "$TFDEMO_RESOURCES"
    echo -e "\n${YELLOW}Do you want to delete these resources? (yes/no)${NC}"
    read -r response
    if [ "$response" = "yes" ]; then
        while IFS=$'\t' read -r resource_id resource_name resource_type; do
            # Special handling for Databricks workspaces
            if [[ "$resource_type" == *"Databricks/workspaces"* ]]; then
                echo -e "${YELLOW}Deleting Databricks workspace: $resource_name${NC}"
                WORKSPACE_RG=$(echo "$resource_id" | grep -oP 'resourceGroups/\K[^/]+')
                if az databricks workspace delete --name "$resource_name" --resource-group "$WORKSPACE_RG" --yes --no-wait; then
                    echo -e "${GREEN}✓ Deletion initiated for workspace: $resource_name${NC}"
                else
                    echo -e "${RED}✗ Failed to delete workspace: $resource_name${NC}"
                fi
            else
                delete_resource "$resource_id" "$resource_name ($resource_type)"
            fi
        done <<< "$TFDEMO_RESOURCES"
    else
        echo -e "${YELLOW}Skipping tfdemo resource cleanup${NC}"
    fi
fi

echo -e "\n${GREEN}✓ Old deployment cleanup complete${NC}\n"

# =============================================================================
# SUMMARY
# =============================================================================

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Cleanup Summary${NC}"
echo -e "${BLUE}========================================${NC}\n"

echo -e "${GREEN}Cleanup tasks completed:${NC}"
echo -e "  ✓ Checked for orphaned AgentBricks resources"
echo -e "  ✓ Checked for malformed managed RG"
echo -e "  ✓ Checked for old tfdemo deployment resources"

echo -e "\n${YELLOW}Next Steps:${NC}"
echo -e "  1. Navigate to AgentBricks directory:"
echo -e "     cd /Users/dwtorres/src/work/terraform-databricks-examples/examples/adb-agentbricks"
echo -e ""
echo -e "  2. Re-run Terraform:"
echo -e "     terraform plan -out=tfplan"
echo -e "     terraform apply tfplan"
echo -e ""
echo -e "  3. After deployment, manually approve storage private endpoints:"
echo -e "     - Navigate to Azure Portal"
echo -e "     - Go to managed RG → DBFS storage account"
echo -e "     - Networking → Private endpoint connections"
echo -e "     - Approve 2 pending connections (blob + dfs)"

echo -e "\n${GREEN}Cleanup script complete!${NC}\n"
