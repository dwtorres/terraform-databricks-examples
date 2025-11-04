# Azure Databricks Private Link Architecture

**Module:** adb-with-private-link-standard  
**Last Updated:** 2025-11-04  
**Purpose:** Visual reference for dual-VNet private link architecture

---

## Table of Contents
1. [Network Topology](#1-network-topology)
2. [DNS Resolution Flow](#2-dns-resolution-flow)
3. [Private Endpoint Architecture](#3-private-endpoint-architecture)
4. [Traffic Flow Patterns](#4-traffic-flow-patterns)

---

## 1. Network Topology

### Overview
Dual-VNet architecture with Data Plane (compute resources) and Transit (user access) networks connected via VNet peering.

### Diagram

```
┌────────────────────────────────────────────────────────────────────────────┐
│                         Azure Subscription                                  │
│                                                                             │
│  ┌──────────────────────────────────────────────────────────────────────┐  │
│  │  Resource Group: {prefix}-{random}-dp-rg                             │  │
│  │                                                                       │  │
│  │  ┌─────────────────────────────────────────────────────────────┐    │  │
│  │  │  Data Plane VNet: 10.180.0.0/20                             │    │  │
│  │  │                                                              │    │  │
│  │  │  ┌────────────────────────────────────────────────────┐    │    │  │
│  │  │  │  Private Subnet: 10.180.0.0/24                    │    │    │  │
│  │  │  │  • Databricks cluster VMs                         │    │    │  │
│  │  │  │  • Delegated to Microsoft.Databricks/workspaces   │    │    │  │
│  │  │  └────────────────────────────────────────────────────┘    │    │  │
│  │  │                                                              │    │  │
│  │  │  ┌────────────────────────────────────────────────────┐    │    │  │
│  │  │  │  Public Subnet: 10.180.1.0/24                     │    │    │  │
│  │  │  │  • Databricks secure cluster connectivity         │    │    │  │
│  │  │  │  • Delegated to Microsoft.Databricks/workspaces   │    │    │  │
│  │  │  └────────────────────────────────────────────────────┘    │    │  │
│  │  │                                                              │    │  │
│  │  │  ┌────────────────────────────────────────────────────┐    │    │  │
│  │  │  │  Storage Subnet: 10.180.2.0/24                    │    │    │  │
│  │  │  │  • Managed DBFS storage accounts                  │    │    │  │
│  │  │  │  • Service endpoints enabled                      │    │    │  │
│  │  │  └────────────────────────────────────────────────────┘    │    │  │
│  │  │                                                              │    │  │
│  │  │  ┌────────────────────────────────────────────────────┐    │    │  │
│  │  │  │  Private Endpoint Subnet: 10.180.3.0/24           │    │    │  │
│  │  │  │  • dpcp-pe (Control Plane: 10.180.3.4)           │    │    │  │
│  │  │  │  • blob-pe (Blob Storage: 10.180.3.5)            │    │    │  │
│  │  │  │  • dfs-pe (DFS Storage: 10.180.3.6)              │    │    │  │
│  │  │  └────────────────────────────────────────────────────┘    │    │  │
│  │  └──────────────────────────────────────────────────────────────┘    │  │
│  └───────────────────────────────────────────────────────────────────────┘  │
│                                                                             │
│                        ⬍══════ VNet Peering ══════⬎                         │
│                        (Fix #1 - CRITICAL)                                  │
│                                                                             │
│  ┌──────────────────────────────────────────────────────────────────────┐  │
│  │  Resource Group: {prefix}-{random}-transit-rg                        │  │
│  │                                                                       │  │
│  │  ┌─────────────────────────────────────────────────────────────┐    │  │
│  │  │  Transit VNet: 10.181.0.0/20                                │    │  │
│  │  │                                                              │    │  │
│  │  │  ┌────────────────────────────────────────────────────┐    │    │  │
│  │  │  │  Transit Subnet: 10.181.0.0/24                    │    │    │  │
│  │  │  │  • User/admin connectivity                        │    │    │  │
│  │  │  │  • Test VM: 10.181.0.4 (public IP: x.x.x.x)      │    │    │  │
│  │  │  └────────────────────────────────────────────────────┘    │    │  │
│  │  │                                                              │    │  │
│  │  │  ┌────────────────────────────────────────────────────┐    │    │  │
│  │  │  │  Private Endpoint Subnet: 10.181.1.0/24           │    │    │  │
│  │  │  │  • frontend-pe (UI/API: 10.181.1.4)              │    │    │  │
│  │  │  │  • auth-pe (Browser Auth: 10.181.1.5)            │    │    │  │
│  │  │  └────────────────────────────────────────────────────┘    │    │  │
│  │  └──────────────────────────────────────────────────────────────┘    │  │
│  └───────────────────────────────────────────────────────────────────────┘  │
│                                                                             │
│  ┌──────────────────────────────────────────────────────────────────────┐  │
│  │  Private DNS Zones (Data Plane RG)                                   │  │
│  │                                                                       │  │
│  │  • privatelink.azuredatabricks.net                                   │  │
│  │    ├─ Linked to Data Plane VNet                                     │  │
│  │    └─ Linked to Transit VNet (Fix #3)                               │  │
│  │                                                                       │  │
│  │  • privatelink.blob.core.windows.net                                 │  │
│  │    ├─ Linked to Data Plane VNet                                     │  │
│  │    └─ Linked to Transit VNet (Fix #2 - HIGH PRIORITY)               │  │
│  │                                                                       │  │
│  │  • privatelink.dfs.core.windows.net                                  │  │
│  │    ├─ Linked to Data Plane VNet                                     │  │
│  │    └─ Linked to Transit VNet (Fix #2 - HIGH PRIORITY)               │  │
│  └───────────────────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Key Resources

**Data Plane VNet (10.180.0.0/20):**
- **Purpose:** Databricks compute and storage resources
- **Subnets:** 4 (private, public, storage, private endpoints)
- **NSG:** Databricks-managed rules
- **Peering:** Bidirectional to Transit VNet

**Transit VNet (10.181.0.0/20):**
- **Purpose:** User and admin access to workspace
- **Subnets:** 2 (transit, private endpoints)
- **NSG:** Standard rules for RDP/SSH access
- **Peering:** Bidirectional to Data Plane VNet

**VNet Peering Configuration:**
```hcl
allow_virtual_network_access = true
allow_forwarded_traffic      = true
```

---

## 2. DNS Resolution Flow

### Overview
Private DNS zones ensure all Databricks and storage traffic resolves to private IPs within the VNets.

### Diagram

```
┌─────────────────────────────────────────────────────────────────────────┐
│  DNS Resolution Flow - Before and After Fixes                           │
└─────────────────────────────────────────────────────────────────────────┘

BEFORE FIX #2 (BROKEN - Storage resolves to public IPs from Transit):
┌────────────────┐
│  Test VM       │  nslookup dbfsxxx.blob.core.windows.net
│  10.181.0.4    │
└────────┬───────┘
         │
         ├─ Query: dbfsxxx.blob.core.windows.net
         │
         v
┌────────────────────────────────────────────────────────────────────────┐
│  Azure DNS (168.63.129.16)                                             │
│  • Transit VNet NOT linked to blob/dfs DNS zones                       │
│  • Falls back to public Azure DNS                                      │
└────────┬───────────────────────────────────────────────────────────────┘
         │
         v
  Returns: 20.150.73.68 (PUBLIC IP ❌)
  • NSG blocks access
  • Storage operations timeout


AFTER FIX #2 (WORKING - Storage resolves to private IPs):
┌────────────────┐
│  Test VM       │  nslookup dbfsxxx.blob.core.windows.net
│  10.181.0.4    │
└────────┬───────┘
         │
         ├─ Query: dbfsxxx.blob.core.windows.net
         │
         v
┌────────────────────────────────────────────────────────────────────────┐
│  Azure DNS (168.63.129.16)                                             │
│  • Transit VNet now linked to blob/dfs DNS zones                       │
│  • Queries privatelink.blob.core.windows.net zone                      │
└────────┬───────────────────────────────────────────────────────────────┘
         │
         v
┌────────────────────────────────────────────────────────────────────────┐
│  Private DNS Zone: privatelink.blob.core.windows.net                   │
│  • VNet Links:                                                         │
│    ├─ Data Plane VNet (10.180.0.0/20)                                 │
│    └─ Transit VNet (10.181.0.0/20) ← Fix #2                           │
│  • A Records:                                                          │
│    └─ dbfsxxx → 10.180.2.5 (blob private endpoint)                    │
└────────┬───────────────────────────────────────────────────────────────┘
         │
         v
  Returns: 10.180.2.5 (PRIVATE IP ✅)
  • Traffic flows through VNet peering
  • Reaches blob private endpoint
  • Storage operations succeed
```

### DNS Zone VNet Link Matrix

| DNS Zone                            | Data Plane Link | Transit Link | Fix Reference |
|-------------------------------------|-----------------|--------------|---------------|
| privatelink.azuredatabricks.net     | ✅ Always      | ✅ Fix #3    | Issue #5      |
| privatelink.blob.core.windows.net   | ✅ Always      | ✅ Fix #2    | Issue #7      |
| privatelink.dfs.core.windows.net    | ✅ Always      | ✅ Fix #2    | Issue #7      |

### Resolution Examples

**Workspace URL Resolution:**
```
User: adb-2003219232620501.1.azuredatabricks.net
├─ Query privatelink.azuredatabricks.net zone
├─ Returns: 10.181.1.4 (frontend-pe in Transit VNet)
└─ User connects via browser ✅
```

**Blob Storage Resolution:**
```
Cluster: dbfsxxx.blob.core.windows.net
├─ Query privatelink.blob.core.windows.net zone
├─ Returns: 10.180.2.5 (blob-pe in Data Plane VNet)
└─ Storage access succeeds ✅
```

**DFS Storage Resolution:**
```
Cluster: dbfsxxx.dfs.core.windows.net
├─ Query privatelink.dfs.core.windows.net zone
├─ Returns: 10.180.2.6 (dfs-pe in Data Plane VNet)
└─ Delta Lake operations succeed ✅
```

---

## 3. Private Endpoint Architecture

### Overview
Five private endpoints across two VNets provide complete private connectivity for all Databricks operations.

### Diagram

```
┌─────────────────────────────────────────────────────────────────────────┐
│  Private Endpoint Architecture - All 5 Endpoints                        │
└─────────────────────────────────────────────────────────────────────────┘

DATA PLANE VNET (10.180.0.0/20):
┌─────────────────────────────────────────────────────────────────────────┐
│  Private Endpoint Subnet: 10.180.3.0/24                                 │
│                                                                          │
│  ┌────────────────────────────────────────────────────────────────┐    │
│  │  dpcp-pe (Data Plane Control Plane)                           │    │
│  │  • IP: 10.180.3.4                                              │    │
│  │  • Target: Databricks Data Plane Workspace                    │    │
│  │  • Subresource: databricks_ui_api                             │    │
│  │  • DNS: privatelink.azuredatabricks.net                        │    │
│  │  • Purpose: Control plane API for cluster management          │    │
│  └────────────────────────────────────────────────────────────────┘    │
│                                                                          │
│  ┌────────────────────────────────────────────────────────────────┐    │
│  │  blob-pe (Blob Storage)                                        │    │
│  │  • IP: 10.180.2.5                                              │    │
│  │  • Target: DBFS Managed Storage Account                       │    │
│  │  • Subresource: blob                                           │    │
│  │  • DNS: privatelink.blob.core.windows.net                      │    │
│  │  • Purpose: DBFS blob storage access                          │    │
│  └────────────────────────────────────────────────────────────────┘    │
│                                                                          │
│  ┌────────────────────────────────────────────────────────────────┐    │
│  │  dfs-pe (DFS Storage)                                          │    │
│  │  • IP: 10.180.2.6                                              │    │
│  │  • Target: DBFS Managed Storage Account                       │    │
│  │  • Subresource: dfs                                            │    │
│  │  • DNS: privatelink.dfs.core.windows.net                       │    │
│  │  • Purpose: Delta Lake hierarchical namespace operations      │    │
│  └────────────────────────────────────────────────────────────────┘    │
└──────────────────────────────────────────────────────────────────────────┘

TRANSIT VNET (10.181.0.0/20):
┌─────────────────────────────────────────────────────────────────────────┐
│  Private Endpoint Subnet: 10.181.1.0/24                                 │
│                                                                          │
│  ┌────────────────────────────────────────────────────────────────┐    │
│  │  frontend-pe (Frontend/UI API)                                 │    │
│  │  • IP: 10.181.1.4                                              │    │
│  │  • Target: Databricks Data Plane Workspace                    │    │
│  │  • Subresource: databricks_ui_api                             │    │
│  │  • DNS: privatelink.azuredatabricks.net                        │    │
│  │  • Purpose: Workspace UI and REST API access                  │    │
│  │  • depends_on: dp_workspace (Fix #4 - CRITICAL)               │    │
│  └────────────────────────────────────────────────────────────────┘    │
│                                                                          │
│  ┌────────────────────────────────────────────────────────────────┐    │
│  │  auth-pe (Browser Authentication)                              │    │
│  │  • IP: 10.181.1.5                                              │    │
│  │  • Target: Databricks Transit Workspace                       │    │
│  │  • Subresource: browser_authentication                        │    │
│  │  • DNS: privatelink.azuredatabricks.net                        │    │
│  │  • Purpose: Azure AD authentication flow                      │    │
│  └────────────────────────────────────────────────────────────────┘    │
└──────────────────────────────────────────────────────────────────────────┘
```

### Endpoint Configuration Details

**Control Plane Endpoint (dpcp-pe):**
```hcl
resource "azurerm_private_endpoint" "dp_dbcp_pe" {
  name                = "dp-dpcp-pe"
  location            = local.dp_rg_location
  resource_group_name = local.dp_rg_name
  subnet_id           = azurerm_subnet.plsubnet.id

  private_service_connection {
    name                           = "ple-${local.prefix}-dp-dbcp"
    private_connection_resource_id = azurerm_databricks_workspace.dp_workspace.id
    is_manual_connection           = false
    subresource_names              = ["databricks_ui_api"]
  }

  private_dns_zone_group {
    name                 = "private-dns-zone-dpcp"
    private_dns_zone_ids = [azurerm_private_dns_zone.dnsdpcp.id]
  }
}
```

**Frontend Endpoint with Race Condition Fix:**
```hcl
resource "azurerm_private_endpoint" "front_pe" {
  # ... configuration ...

  # Fix #4: Prevent race condition
  depends_on = [
    azurerm_databricks_workspace.dp_workspace
  ]
}
```

---

## 4. Traffic Flow Patterns

### Overview
End-to-end traffic flows for user access, cluster operations, and storage access.

### User Access Flow

```
┌──────────────────────────────────────────────────────────────────────────┐
│  User → Workspace UI Access Flow                                         │
└──────────────────────────────────────────────────────────────────────────┘

Step 1: User initiates browser connection
┌─────────────┐
│  User       │  https://adb-2003219232620501.1.azuredatabricks.net
│  Browser    │
└──────┬──────┘
       │
       ├─ DNS Query: adb-2003219232620501.1.azuredatabricks.net
       │
       v
┌──────────────────────────────────────────────────────────────┐
│  Corporate DNS / Azure DNS                                   │
│  • Resolves to privatelink.azuredatabricks.net zone          │
│  • Returns: 10.181.1.4 (frontend-pe)                         │
└──────┬───────────────────────────────────────────────────────┘
       │
       v
Step 2: HTTPS connection to private endpoint
┌──────────────────────────────────────────────────────────────┐
│  Transit VNet: 10.181.0.0/20                                 │
│  • frontend-pe: 10.181.1.4                                   │
│  • Accepts HTTPS connection (port 443)                       │
└──────┬───────────────────────────────────────────────────────┘
       │
       ├─ VNet Peering (Fix #1)
       │
       v
┌──────────────────────────────────────────────────────────────┐
│  Data Plane VNet: 10.180.0.0/20                              │
│  • Databricks Data Plane Workspace                           │
│  • Processes UI requests                                     │
│  • Returns workspace interface                               │
└──────┬───────────────────────────────────────────────────────┘
       │
       v
┌─────────────┐
│  User       │  ✅ Workspace UI loads successfully
│  Browser    │
└─────────────┘
```

### Cluster Storage Access Flow

```
┌──────────────────────────────────────────────────────────────────────────┐
│  Cluster → DBFS Storage Access Flow                                      │
└──────────────────────────────────────────────────────────────────────────┘

Step 1: Cluster reads from DBFS
┌──────────────────────────────────────────────────────────────┐
│  Databricks Cluster                                          │
│  • Private Subnet: 10.180.0.4                                │
│  • Runs: df = spark.read.parquet("dbfs:/data/...")          │
└──────┬───────────────────────────────────────────────────────┘
       │
       ├─ Storage API call to dbfsxxx.blob.core.windows.net
       │
       v
Step 2: DNS resolution
┌──────────────────────────────────────────────────────────────┐
│  Azure DNS (168.63.129.16)                                   │
│  • Queries privatelink.blob.core.windows.net zone            │
│  • Zone linked to Data Plane VNet                            │
│  • Returns: 10.180.2.5 (blob-pe)                             │
└──────┬───────────────────────────────────────────────────────┘
       │
       v
Step 3: Storage access via private endpoint
┌──────────────────────────────────────────────────────────────┐
│  Data Plane VNet: 10.180.0.0/20                              │
│  • blob-pe: 10.180.2.5                                       │
│  • Routes to DBFS Managed Storage                            │
└──────┬───────────────────────────────────────────────────────┘
       │
       v
┌──────────────────────────────────────────────────────────────┐
│  DBFS Managed Storage Account                                │
│  • dbfsxxx.blob.core.windows.net                             │
│  • Returns parquet data                                      │
└──────┬───────────────────────────────────────────────────────┘
       │
       v
┌──────────────────────────────────────────────────────────────┐
│  Databricks Cluster                                          │
│  • Receives data via private endpoint                        │
│  • ✅ df.show() displays data successfully                   │
└──────────────────────────────────────────────────────────────┘
```

### Cross-VNet Communication Flow

```
┌──────────────────────────────────────────────────────────────────────────┐
│  Test VM → Workspace → Storage (Full Path)                               │
└──────────────────────────────────────────────────────────────────────────┘

1. Test VM makes workspace request
   Transit VNet (10.181.0.4) → frontend-pe (10.181.1.4)

2. Frontend endpoint routes via VNet peering
   Transit VNet → Data Plane VNet (Fix #1 enables this)

3. Workspace processes request, needs storage
   Data Plane Workspace → blob-pe (10.180.2.5)

4. Storage DNS resolution (Fix #2 critical here)
   ┌─ WITHOUT Fix #2: Resolves to public IP → TIMEOUT ❌
   └─ WITH Fix #2: Resolves to 10.180.2.5 → SUCCESS ✅

5. Storage returns data
   DBFS Storage → blob-pe → Workspace → frontend-pe → Test VM

All traffic stays within Azure private network ✅
```

### Traffic Matrix

| Source | Destination | Via | DNS Resolution Required | Fix Dependencies |
|--------|-------------|-----|------------------------|------------------|
| User Browser | Workspace UI | frontend-pe | privatelink.azuredatabricks.net | #1, #3 |
| Cluster | DBFS Blob | blob-pe | privatelink.blob.core.windows.net | #2 |
| Cluster | DBFS DFS | dfs-pe | privatelink.dfs.core.windows.net | #2 |
| Workspace | Control Plane | dpcp-pe | privatelink.azuredatabricks.net | #1 |
| Test VM | Workspace | frontend-pe → peering | privatelink.azuredatabricks.net | #1, #2, #3 |

---

## Key Architectural Decisions

### Why Dual-VNet Design?

**Rationale:**
- **Separation of Concerns:** User access (Transit) separate from compute (Data Plane)
- **Security Isolation:** Different security policies for user and compute networks
- **Flexibility:** Easier to integrate with hub-spoke topologies
- **Azure Requirements:** Databricks managed resources need dedicated VNet

### Why VNet Peering is Critical (Fix #1)

**Without Peering:**
```
Transit VNet ❌ No Route ❌ Data Plane VNet
- DNS works (zones linked to both VNets)
- Private endpoints exist
- BUT: No network path for traffic
- Result: 100% non-functional despite successful deployment
```

**With Peering:**
```
Transit VNet ⇄ VNet Peering ⇄ Data Plane VNet
- DNS works ✅
- Private endpoints exist ✅
- Network connectivity established ✅
- Result: Fully functional architecture
```

### Why Storage DNS Links to Transit VNet (Fix #2)

**Scenario:** Test VM in Transit VNet accessing workspace

**Without Transit VNet Links:**
```
Test VM queries: dbfsxxx.blob.core.windows.net
├─ Transit VNet NOT linked to blob DNS zone
├─ Falls back to public Azure DNS
├─ Returns public IP: 20.150.73.68
└─ NSG blocks public access → TIMEOUT ❌
```

**With Transit VNet Links:**
```
Test VM queries: dbfsxxx.blob.core.windows.net
├─ Transit VNet linked to blob DNS zone
├─ Queries private DNS zone
├─ Returns private IP: 10.180.2.5
├─ Traffic flows via VNet peering
└─ Storage access succeeds ✅
```

---

## Enterprise Integration Patterns

### Hub-Spoke Integration

```
┌──────────────────────────────────────────────────────────┐
│  Hub VNet (10.178.0.0/20)                                │
│  • Azure Firewall                                        │
│  • Azure Bastion                                         │
│  • VPN Gateway                                           │
│  • Centralized services                                  │
└────────┬──────────────────────────────┬──────────────────┘
         │                              │
         │ Peering                      │ Peering
         │                              │
┌────────v──────────┐          ┌────────v──────────┐
│  Data Plane VNet  │          │  Transit VNet     │
│  10.180.0.0/20    │ ⇄ Peer ⇄ │  10.181.0.0/20    │
│  (Compute)        │          │  (User Access)    │
└───────────────────┘          └───────────────────┘
```

### On-Premises Integration

```
On-Premises Network
     │
     │ VPN/ExpressRoute
     │
     v
Hub VNet (10.178.0.0/20)
     │
     ├─ Peering → Data Plane VNet (10.180.0.0/20)
     │
     └─ Peering → Transit VNet (10.181.0.0/20)
     
DNS:
  • On-prem DNS forwards Azure queries to Hub VNet
  • Hub VNet linked to all private DNS zones
  • Conditional forwarding for privatelink.* domains
```

---

## References

- **Module Path:** modules/adb-with-private-link-standard
- **FIXES.md:** Complete fix documentation
- **RUNBOOKS.md:** Operational procedures
- **TESTING.md:** Validation procedures
- **Azure Documentation:** [Databricks Private Link](https://learn.microsoft.com/en-us/azure/databricks/security/network/classic/private-link)

---

**Document Version:** 1.0  
**Maintainer:** David Torres  
**Last Review:** 2025-11-04
