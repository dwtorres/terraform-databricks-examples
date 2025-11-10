variable "subscription_id" {
  type        = string
  description = "(Required) The Azure Subscription ID"
}

variable "location" {
  type        = string
  description = "(Required) The Azure region for resources"
  default     = "eastus2"
}

variable "cidr" {
  type        = string
  description = "(Required) The CIDR range for the VNet"
}

variable "create_resource_group" {
  type        = bool
  description = "Set to true to create a new Resource Group. Set to false to use an existing one."
  default     = false
}

variable "existing_resource_group_name" {
  type        = string
  description = "Name of existing Resource Group if create_resource_group is false"
  default     = ""
}

variable "workspace_prefix" {
  type        = string
  description = "Prefix for workspace naming"
  default     = "agentbricks"
}

variable "dbfs_prefix" {
  type        = string
  description = "Prefix for DBFS storage account naming (no special characters)"
  default     = "dbfsagent"
}

variable "environment" {
  type        = string
  description = "Environment tag (e.g., PoC, Dev, Test, Prod)"
  default     = "PoC"
}

variable "managed_resource_group_name" {
  type        = string
  description = "Name for the Databricks managed resource group"
  default     = ""
}

variable "enable_infrastructure_encryption" {
  type        = bool
  description = "Enable infrastructure encryption for enhanced security"
  default     = true
}

variable "enable_dbfs_firewall" {
  type        = bool
  description = "Enable DBFS storage account firewall"
  default     = true
}

variable "enable_no_public_ip" {
  type        = bool
  description = "Disable public IPs on Databricks clusters"
  default     = true
}

variable "create_storage_dfs_endpoint" {
  type        = bool
  description = "Create private endpoint for Storage DFS (required for Unity Catalog)"
  default     = true
}

variable "create_keyvault_endpoint" {
  type        = bool
  description = "Create private endpoint for Key Vault"
  default     = false
}
