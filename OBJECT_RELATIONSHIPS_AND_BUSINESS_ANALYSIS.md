# STERIS Healthcare (CBM Dev): Object Relationships & Business Analysis

> **Scope:** the Salesforce DX project `force-app/main/default` (API v68.0). It contains about 1,060 Apex classes, 53 triggers, around 100 LWCs, Aura and Visualforce. There are no object or field metadata files in the repo (`objects/` is empty).
> **Method:** every relationship below was **inferred from Apex and LWC code**: SOQL `__r` traversals, sub-queries, DML field assignments and selector classes. Check field API names against the org (`sf sobject describe`) before relying on them for builds.
> **Generated:** 2026-11-02

---

## Table of Contents
1. [System Landscape](#1-system-landscape)
2. [Domain Map](#2-domain-map)
3. [Customer Master (Account / Address / Hierarchy)](#3-customer-master)
4. [Sales, Product & Pricing](#4-sales-product--pricing)
5. [Product Browser: Components, Connections & Data Flow](#5-product-browser)
6. [Quote, Contract Modifiers & Approvals](#6-quote-contract-modifiers--approvals)
7. [Order-to-Fulfilment (CBM Case Management)](#7-order-to-fulfilment-cbm)
8. [Repair Center (Depot Repair)](#8-repair-center-depot-repair)
9. [Field Service (ES / IMS)](#9-field-service-es--ims)
10. [CSC Visits, Team Members & Access (TAS / TAE)](#10-csc-visits-team-members--access)
11. [Integration Inventory](#11-integration-inventory)
12. [Master Relationship Reference Table](#12-master-relationship-reference-table)
13. [Business Analysis](#13-business-analysis)
14. [Technical Findings & Risks](#14-technical-findings--risks)
15. [Glossary](#15-glossary)

---

## 1. System Landscape

```mermaid
flowchart LR
    subgraph SF["Salesforce (CBM Org)"]
        SALES["Sales Cloud<br/>Lead · Opportunity · Quote"]
        RLM["Revenue Cloud<br/>Product Configurator"]
        SVC["Service Cloud<br/>Case · Return Order"]
        FSL["Field Service (FSL / FSSK)<br/>Work Order · Service Appointment"]
        CBM["CBM Order Mgmt<br/>Order · Holds · Tasks"]
        PORTAL["Experience Cloud<br/>STERIS Dealer Portal"]
    end

    ORACLE[("Oracle ERP<br/>Customers · Orders · Pricing")]
    BOOMI{{"Boomi iPaaS"}}
    TAS[("TAS<br/>Territory Assignment")]
    SC[("Sales Connection<br/>Quoting")]
    DPC[("Digital Parts Catalog")]
    FEDEX[("FedEx")]
    ZEBRA[("Zebra Printers")]
    CC[("ConnectCare")]
    SUMMIT[("Summit (HRIS Skills)")]

    ORACLE -- "Data migration / CreateCase__e" --> CBM
    ORACLE -- "Account / Address loads" --> SF
    SALES -- "Oracle_Pricing_API" --> ORACLE
    SALES <-- "SO_Callout" --> BOOMI
    BOOMI <--> TAS
    BOOMI <--> SC
    BOOMI <--> DPC
    CC -- "REST /connectcare/v1" --> SVC
    SVC -- "Labels" --> FEDEX
    FSL -- "Bin tags" --> ZEBRA
    SUMMIT -- "SummitSkill__c staging" --> FSL
    SC -- "/v1/opportunity-quote-context" --> SALES
    FSL -- "ProductRequest → Sales Order" --> ORACLE
```

---

## 2. Domain Map

| Domain | Core objects | Key UI / Apex entry points |
|---|---|---|
| **Customer Master** | Account, Address, Location, AccountAccountRelationship__c, Department__c, AccountDepartment__c, Price_List__c, Contact | `AccountTriggerHandler`, `AccountHierarchyResolutionService`, `AccountAccountRelationshipService` |
| **Sales** | Lead, LeadProduct__c, Lead_SLA__c, Opportunity, OpportunityLineItem, OpportunityContactRole, OpportunityTeamMember, Sample__c, Project__c | `OpportunityTriggerHandller`, `EPPProductController`, `LostBusinessProductController` |
| **Product & Pricing** | Product2, Pricebook2, PricebookEntry, PFCL__c, ServiceBOM__c, PFCLServiceBOM__c, PSAM__c, Price_List__c | `OraclePricingIntegrationService`, `OraclePricingGateway` |
| **Quote & Contract** | Quote, QuoteLineItem, ContractModifier__c, DealApprovalApprover__c | `GenerateQuoteController`, `ContractModifierService`, `OppDealApprovalService` |
| **Order Mgmt (CBM)** | Order, OrderItem, OrderAndOrderLineHold__c, HoldMatrix__c, OrderLineContact__c, Case, Task | `CreateCaseEventTrigger`, `CreateCaseHandler`, `HoldTriggerHelper`, `CreateTaskHelper` |
| **Repair Center** | Case, ReturnOrder, ReturnOrderLineItem, WorkOrder, WorkOrderLineItem, Location (Repair Center/Rack), RepairCenterRoutingRule__c, WarrantyRepairEvaluation__c, NonconformanceReport__c, WOAssignmentHistory__c, ServiceTeam__c | `CreateReturnOrderController`, `ReceivingFinishService`, `WorkOrdersService` |
| **Field Service** | ServiceAppointment, ServiceResource, ProductItem, ProductRequest, Asset, CustomerPreference__c, SummitSkill__c | `WoDebrief*Controller`, `ServiceAppointmentRealignmentService` |
| **Access & Visits** | TeamMember__c, TemporaryAccessException__c, TAEProcessingWorkItem__c, TAE_AssignedRecord__c, CSC_Visit_Request__c, CSCVisitAttendee__c | `TASService`, `TemporaryAccessExceptionService`, `CscVisitConfirmationService` |

---

## 3. Customer Master

```mermaid
erDiagram
    Account ||--o{ Account : "ParentId (Customer → Facility)"
    Account ||--o{ AccountAccountRelationship__c : "ParentAccount__c (IDN/GPO)"
    Account ||--o{ AccountAccountRelationship__c : "ChildAccount__c (Member)"
    Account }o--|| Account_IDN : "IDN_Account__c / GPO_Account__c"
    Price_List__c ||--o{ Account : "Price_List__c"
    Account ||--o{ AccountDepartment__c : "Account__c"
    Department__c ||--o{ AccountDepartment__c : "Department__c"
    Account ||--o{ Contact : "AccountId"
    Account ||--o{ Address : "Customer__c"
    Location ||--o{ Address : "ParentId"
    Address ||--o{ Opportunity : "Address__c"
    Account ||--o{ CustomerPreference__c : "Account__c"
    Account ||--o{ AccountTeamMember : "TAS Assigned / Temporary"
    Account ||--o{ Asset : "AccountId"
```

**Account model**
- **Record types:** `Customer`, `Prospect`, `HCSalesDealer`.
- **`Account.Type`:** `IDN` / `GPO` (contracting parents), `Customer`, and `Address` (ship-to or facility child).
- **External keys:**
  - `SourceSystemID__c` = `SystemID__c + 'Oracle'`
  - `OracleAddressId__c` matches `OrderLineContact__c.TASAddressId__c`
  - `OrgIDs__c` matches `User.OrgId__c`
- **Business line:** `CustomerClassCode__c` is `HC` (Healthcare) or `SC` (Life Sciences).

**Hierarchy roll-up (`AccountHierarchyResolutionService`)**

| Account level | Accounts included in the roll-up |
|---|---|
| Facility | Itself |
| Customer | Itself plus `ParentId` children that have `OracleAddressId__c` |
| IDN / GPO | Affiliated customers through `AccountAccountRelationship__c`, plus their facilities |

`AccountAccountRelationship__c` stores two labels: `RelationshipType__c` from the child's view ("Is IDN Member Of") and `InverseRelationshipType__c` from the parent's view ("Has IDN Member"). Its trigger stamps `Account.IDN_Account__c` / `GPO_Account__c` (the latest relationship wins) and syncs them onto open Opportunities.

---

## 4. Sales, Product & Pricing

```mermaid
erDiagram
    Lead ||--o{ LeadProduct__c : "Lead__c"
    Product2 ||--o{ LeadProduct__c : "Product__c"
    Lead ||--o{ Lead_SLA__c : "Lead__c"

    Account ||--o{ Opportunity : "AccountId"
    Contact ||--o{ Opportunity : "PrimaryContact__c"
    Opportunity ||--o{ Opportunity : "RelatedProjectOpportunity__c (Project → Commercial)"
    Pricebook2 ||--o{ Opportunity : "Pricebook2Id"
    Opportunity ||--o{ OpportunityLineItem : "OpportunityId"
    Opportunity ||--o{ OpportunityContactRole : "OpportunityId"
    Opportunity ||--o{ OpportunityTeamMember : "OpportunityId"
    Opportunity ||--o{ Sample__c : "RelatedOpportunity__c"
    Opportunity ||--o{ DealApprovalApprover__c : "Opportunity__c"
    User ||--o{ DealApprovalApprover__c : "Approver__c"
    Opportunity ||--o{ CSC_Visit_Request__c : "Opportunity__c"

    Product2 ||--o{ PricebookEntry : "Product2Id"
    Pricebook2 ||--o{ PricebookEntry : "Pricebook2Id"
    PricebookEntry ||--o{ OpportunityLineItem : "PricebookEntryId"
    Product2 ||--o{ OpportunityLineItem : "Product2Id"

    PFCL__c ||--o{ PFCL__c : "Parent__c"
    PFCL__c ||--o{ Product2 : "PFCL__c"
    PSAM__c ||--o{ Product2 : "PSAM__c"
    PFCL__c ||--o{ ServiceBOM__c : "PFCL__c"
    PFCL__c ||--o{ PFCLServiceBOM__c : "PFCL__c"
    ServiceBOM__c ||--o{ PFCLServiceBOM__c : "ServiceBOM__c"
    Product2 ||--o{ Asset : "Product2Id"

    Account ||--o{ Project__c : "Account__c"
    Project__c ||--o{ ProjectCases__c : "Project__c"
    Case ||--o{ ProjectCases__c : "Case__c"
    Account ||--o{ Free_Goods_Task_Product__c : "Account__c"
    Product2 ||--o{ Free_Goods_Task_Product__c : "Product__c"
```

**Notes**
- **PFCL hierarchy:** `PFCL__c` is a self-referencing product-family hierarchy. Products, Service BOMs, Assets (via Product2), QuoteLineItems and WOLIs all link to it.
- **Not objects:** `Model__c`, `ProductLine__c`, `SubProductLine__c` and `ProductType__c` are **fields**, not objects. They appear on ContractModifier__c, CustomerPreference__c, routing rules and Asset formulas.
- **Free goods:** `Free_Goods_Task_Product__c.TaskId__c` is a **text** key, not a lookup to Task.
- **Opportunity record types seen:** `Healthcare_Sales`, `HCSalesConsumables`, `HCSalesLostBusinessConsumables`, `HCSalesStrategicContract`, plus EPP and Project opportunities.

---

## 5. Product Browser

There is **no single "Product Browser" component**. Product search and selection is spread across **three groups of components**: the Revenue Cloud configurator, the Opportunity product pickers, and supporting pickers. They share the same catalogue objects (Product2, PricebookEntry, PFCL__c, Asset).

### 5.1 Component and connection map

```mermaid
flowchart TB
    subgraph CATALOG["Catalogue data layer"]
        P2[(Product2)]
        PBE[(PricebookEntry)]
        PB[(Pricebook2)]
        PFCL[(PFCL__c)]
        AST[(Asset)]
        AAR[(AccountAccountRelationship__c)]
        CTXA[(ContextAttribute)]
        PI[(ProductItem / Trunk Stock)]
    end

    subgraph A["A · Revenue Cloud Product Configurator (Quote)"]
        CFG{{"Revenue Cloud Configurator<br/>LMS: lightning__productConfigurator_notification"}}
        L1["configPocLauncher"] --> M1["configPocModal (POC)"]
        L2["esServiceProductConfigLauncher"] --> M2["esServiceProductConfigModal"] --> AL["esServiceProductConfigAssetLookup"]
        IMS["imsProductConfigurator / modelQtyCoverage"]
        M1 -. publish ContextFields .-> CFG
        M2 -. publish ContextFields .-> CFG
        IMS -. "QLI.ModelQtyCoverage__c (JSON)" .-> CFG
    end

    subgraph B["B · Opportunity Product Pickers"]
        EPP["eppOpportunityProducts<br/>(Capital / Consumables)"]
        LB["lostBusinessProductSelection<br/>(Flow screen)"]
    end

    subgraph C["C · Other Pickers"]
        LEAD["leadCreateWithProducts<br/>(aura leadNewOverride)"]
        FG["freeGoodTaskQuickAction / freeGoodsTaskProducts"]
        TS["findNearbyTrunkStock<br/>(GraphQL, map)"]
        RC["repairCenterProductCardGrid<br/>(used by instrumentEvaluation)"]
    end

    M2 --> ESC["EsServiceProductConfigController"]
    IMS --> IMSC["ImsProductConfiguratorController<br/>ModelQtyCoverageController"] --> CMS["ContractModifierService"]
    EPP --> EPPC["EPPProductController"]
    LB --> LBC["LostBusinessProductController"]
    LEAD --> LC["LeadCreateController"]
    FG --> FGC["FreeGoodTaskController"]

    ESC --> AST & PFCL & CTXA
    CMS --> AST & AAR
    EPPC --> PBE & PB & P2
    LBC --> P2 & PBE
    LC --> P2
    FGC --> P2
    TS --> PI

    CFG ==> QLI[(QuoteLineItem)]
    EPPC ==> OLI[(OpportunityLineItem)]
    LBC ==> OLI
    LC ==> LP[(LeadProduct__c)]
    FGC ==> FGP[(Free_Goods_Task_Product__c)]
    QLI ==> TRG["QuoteLineItemTrigger / EsServiceQuoteLineTrigger"]
    TRG ==> CM[(ContractModifier__c)]
    TRG ==> EXP["EsServiceLineExpansion (Queueable)<br/>1 line per selected asset"]
    OLI ==> ORA["OraclePricingIntegrationService → Oracle_Pricing_API"]
```

### 5.2 Group A: Revenue Cloud configurator (Quote line configuration)

These are **Flow-screen LWCs embedded in the Revenue Cloud Product Configurator**. They never save records themselves. They publish `{field:'ContextFields', attributeId, fieldName, value}` on the Lightning Message Channel `lightning__productConfigurator_notification`, and the configurator saves the QuoteLineItem.

| Component | Apex methods (`@AuraEnabled`) | Data read | Writes (via configurator) |
|---|---|---|---|
| `configPocLauncher` → `configPocModal` | none (POC, hard-coded attribute Id) | — | `Quantity`, `Asset_Name__c` |
| `esServiceProductConfigLauncher` → `esServiceProductConfigModal` → `esServiceProductConfigAssetLookup` | `EsServiceProductConfigController.getLineContext(quoteId, lineId)`, `searchAssets(accountId, text)` (LIKE on Name/Serial/PFCL, limit 20), `getAssetDetails(assetId)`, `getAttributeIds(fieldNames)` (cacheable) | Quote.AccountId, Asset, `Asset.Product2.PFCL__c`, ContextAttribute | QLI `Asset__c`, `PFCL__c`, `RequestedNumberofPMVisits__c`, demo `UnitPrice` |
| `imsProductConfigurator` / `modelQtyCoverage` | `getCoverage`, `getSubProductLines`, `getManufacturers`, `getAssetCatalog` | Assets of the quote account and its AAR parents, grouped by Product Line → Sub-line → Type → Manufacturer → Model | `QuoteLineItem.ModelQtyCoverage__c` (JSON) |

**Server-side hooks**
- **`QuoteLineItemTriggerHandler`:**
  - Calls `ContractModifierService.syncAdjustmentsFromQuoteLines`, which inserts, updates or deletes `ContractModifier__c` rows (types MODEL QTY and INC/EXC).
  - Stamps `ConstraintEngineNodeStatus__c` before insert.
- **`EsServiceQuoteLineTrigger`** runs the `EsServiceLineExpansion` queueable. It splits bundle lines that have `SelectedAssets__c` into one line per asset, with visits taken from `AssetVisits__c` (default 2).
- **Pricing hooks (`RevSignaling.SignalingApexProcessor`):**
  - `EsServiceOtCoveragePreHook` sets `OT_Coverage__c`.
  - `EsServiceDemoPricePostHook` is a demo that sets price from PM visits. The real pricing is planned as a "PFCL Pricing decision table".
- **`EsServiceAssetSelectionController`** lists assets across `AccountAccountRelationship__c` parents.

### 5.3 Group B: Opportunity product pickers (create OpportunityLineItem)

| Component | Apex | Search logic | Save logic |
|---|---|---|---|
| `eppOpportunityProducts` (record page, `productMode` = Capital / Consumables) | `EPPProductController.searchProducts`, `getOpportunityProducts`, `createOpportunityProducts` | Standard Pricebook entries where `Product2.IsActive`, `EPPEligible__c`, `IsConsumable__c` and currency match the Opportunity; LIKE on Name / ProductCode | Creates or reactivates a PBE on the Opportunity's own Pricebook2, then inserts OLIs with `EPPPrice__c`, `ElevatedEPPPricingApplicable__c`, placement/commitment dates and `ConsumptionFrequency__c`. Rejects duplicates and ineligible products. |
| `lostBusinessProductSelection` (Flow screen) | `LostBusinessProductController.getOriginatingProducts`, `searchProducts`, `getConsumptionFrequencyOptions`, `createLostBusinessProducts` | Copies OLIs from the originating Opportunity, or searches active Product2 (`Product2Selector.selectActiveBySearchKey`) | Price from the Opportunity Pricebook, falling back to Standard. Inserts OLIs with `Status__c`, `ConfidenceLevel__c`, `Contract__c`, `Product_Number_SKU__c`. Skips existing ones. |

After products are added, **Oracle pricing** (`OraclePricingIntegrationService`, invocable "Get Oracle Pricing" → `OraclePricingFlowQueueable` → `callout:Oracle_Pricing_API/getPricingDetail/`) prices the OLIs:
- The request uses `Account.OrgIDs__c`, `OracleAddressId__c` and `Price_List__r.Price_List_ID__c`.
- It sets price and `Contract__c`, deletes OLIs that Oracle did not price, and shows the `opportunityOliBanner` banner.

### 5.4 Group C: Other pickers

| Component | Purpose | Backend |
|---|---|---|
| `leadCreateWithProducts` (hosted by `aura/leadNewOverride`) | New Lead with interested products (`LeadProduct__c`: Product__c, ParentCategory__c, ProductCategory__c) | `LeadCreateController.previewLeadDuplicate`, `createLeadWithProducts` |
| `freeGoodTaskQuickAction` / `freeGoodsTaskProducts` | Attach free-goods products to a Task | `FreeGoodTaskController.searchProducts`, `createTaskProducts`, `getTaskProducts` |
| `findNearbyTrunkStock` | Find technicians' trunk stock (`ProductItem.QuantityOnHand > 0`) on a map | UI API GraphQL only (`c-mobile-map`, `c-locations-list`, `c-map-filters`) |
| `repairCenterProductCardGrid` | Presentational product card grid in instrument evaluation | none (events `cardselect` / `cardtoggle`) |

### 5.5 Product browser sequence (ES Service configuration)

```mermaid
sequenceDiagram
    actor Rep as Sales Rep
    participant CFG as Revenue Cloud Configurator
    participant L as esServiceProductConfigLauncher
    participant M as esServiceProductConfigModal
    participant AP as EsServiceProductConfigController
    participant DB as Salesforce DB
    participant T as QLI Triggers / Queueable

    Rep->>CFG: Configure ES Service bundle on Quote
    CFG->>L: Render (quoteId, lineId)
    L->>AP: getLineContext(quoteId, lineId)
    AP->>DB: Quote.AccountId + saved QLI (Asset__c, PFCL__c, PM visits)
    L->>M: open modal
    Rep->>M: type asset search
    M->>AP: searchAssets(accountId, text)
    AP->>DB: Asset LIKE Name/Serial/PFCL (limit 20)
    Rep->>M: pick asset
    M->>AP: getAssetDetails(assetId) → Product2.PFCL__c
    M->>AP: getAttributeIds(fieldNames)
    M-->>CFG: LMS publish ContextFields (Asset, PFCL, PM visits)
    CFG->>DB: save QuoteLineItem
    DB->>T: QuoteLineItemTrigger / EsServiceQuoteLineTrigger
    T->>DB: ContractModifier__c sync + EsServiceLineExpansion (1 line / asset)
```

---

## 6. Quote, Contract Modifiers & Approvals

```mermaid
erDiagram
    Opportunity ||--o{ Quote : "OpportunityId"
    Account ||--o{ Quote : "AccountId"
    Quote ||--o{ QuoteLineItem : "QuoteId"
    PricebookEntry ||--o{ QuoteLineItem : "PricebookEntryId"
    Asset ||--o{ QuoteLineItem : "Asset__c"
    PFCL__c ||--o{ QuoteLineItem : "PFCL__c"
    QuoteLineItem ||--o{ ContractModifier__c : "QuoteLineItem__c"
    Quote ||--o{ ContractModifier__c : "Quote__c"
    ContractModifier__c ||--o{ ContractModifier__c : "ParentContractModifier__c (Exclusion → Inclusion)"
    WorkOrder ||--o{ Quote : "WorkOrder__c (Repair quote)"
    WorkOrder ||--o| Quote : "ActiveQuote__c"
    WorkOrderLineItem ||--o{ QuoteLineItem : "WorkOrderLineItem__c"
```

**Quote lifecycle**
- **Created in Sales Connection.** `generateQuote` / `lsGenerateQuote` → `GenerateQuoteController` handles `createQuote`, `copyQuote`, `mergeQuote`, `refreshQuotes` and `getSalesConnectionQuoteUrl`.
- **URL:** `SalesConnectionUrlService` builds `#Quote|id=` URLs from `ExternalSystemEndpoint__mdt`, encrypted with AES-256.
- **Sync back:** `RefreshQuoteSyncService` upserts Quote and QLI on `Quote.SalesConnectionQuoteID__c`.
- **Forecast eligibility (`QuoteService`):** only the **first open HC_Sales quote** (earliest LastModified) is `Forecast_Eligible__c`. It is re-evaluated on update and delete, and can be overridden manually (`updateForecastEligibleQuotes`).

**Approval models**

| Approval | Service | Model |
|---|---|---|
| Deal Desk / BU Leader / Additional | `OppDealApprovalService` (GC-3235) | Parallel. `DealApprovalApprover__c` rows; status rolls up to `DealApprovalStatus__c` (Not Submitted → Pending → Approved / Rejected) with `ApprovalCycleNumber__c` |
| EPP regional | `EppApprovalService` | Sequential, driven by `EPP_Approval_Hierarchy__mdt` |
| Pay Per Click | `PpcCommercialApprovalService` | Commercial approval panel |
| Repair quote | `RepairCenterQuotePreApprovalService` | Auto-approves within the IMS CustomerPreference limit per product line |

---

## 7. Order-to-Fulfilment (CBM)

```mermaid
erDiagram
    Order ||--o{ OrderItem : "OrderId"
    Order ||--o| Case : "ParentCase__c"
    Case ||--o{ Order : "Order__c"
    Case ||--o{ OrderItem : "Subcase__c / Case__c"
    Order ||--o{ OrderAndOrderLineHold__c : "Order__c"
    OrderItem ||--o{ OrderAndOrderLineHold__c : "OrderLine__c"
    HoldMatrix__c ||--o{ OrderAndOrderLineHold__c : "HoldMatrix__c"
    Order ||--o{ OrderLineContact__c : "Order__c"
    OrderItem ||--o{ OrderLineContact__c : "OrderLine__c"
    Contact ||--o{ OrderLineContact__c : "SalesRep__c"
    User ||--o{ OrderLineContact__c : "AssignedSalesRep__c / RegionManager__c / ZoneManager__c"
    Order ||--o{ Task : "Order__c"
    OrderItem ||--o{ Task : "OrderLine__c"
    OrderAndOrderLineHold__c ||--o{ Task : "OrderAndOrderLineHold__c"
    User ||--o{ Order : "BLOwner__c / OMOwner__c / LogisticsOwner__c"
```

```mermaid
flowchart TD
    O["Oracle Order + Lines loaded"] --> E["CreateCase__e (OrderNumber__c)"]
    E --> C1["CreateCaseHandler.createCase<br/>1 CBMCase per Order · Status 'Order Entry'"]
    C1 -->|RMA / No Charge| U["UrgentOrder__c = true<br/>Status 'Order Preparation'"]
    C1 --> TM["Assign Case Team → stamp BL / OM / Logistics owners on Order"]
    C1 --> SC{"OrderItem.CreateSubcase__c"}
    SC -->|Capital line| S1["New Capital Line Sub-case"]
    SC -->|Service Installation| S2["One active sub-case per Order (reused)"]
    SC -->|SC Capital line| S3["Single shared Life Sciences capital case"]
    S1 & S2 & S3 --> ST["UpdateCaseHandler: stage rules (CBM_Generic_Configuration__mdt)"]
    ST --> TK["CreateTaskHelper: Order / Line / Hold tasks<br/>(TaskSLAConfig__mdt) + SLA"]
    H["OrderAndOrderLineHold__c changes"] --> HR["HoldTriggerHelper<br/>Order.ReasonProcessHold__c · OtherHolds__c"]
    HR --> TK
    OI["OrderItem update"] --> AC["CBMCaseAutoCloserHandler → auto-close"]
    B["Fallback batches: CreateCasesBatch, CreateSubCaseBatch,<br/>CreateTaskFor*Batch, PopulateSLAForTasksBatch, CBMCaseAutoCloseBatch"] -.-> C1
```

**`OrderLineContact__c` has two roles:**
- **(a) Order-line sales rep.** It rolls up rep names to `Order.SalesRepsAM__c` (Capital), `SalesRepsIPM__c` (Install) and `SalesRepsASM__c` (Service), and region names to `Region__c`.
- **(b) TAS staging row.** It holds `TASAddressId__c`, `TerritoryID__c`, `HRISSalesRepId__c` and `DeltaScenario__c`. `TASTeamAccessBatch` matches the row to `Account.OracleAddressId__c` and adds or removes "TAS Assigned" AccountTeamMembers.

---

## 8. Repair Center (Depot Repair)

> `RepairCenter__c` and `Rack__c` are **lookups to the standard `Location` object** (`LocationType` = Repair Center / Rack), not custom objects. `Vendor__c` is a lookup to Account, and `VendorWorkOrder__c` is a self-lookup on WorkOrder.

```mermaid
erDiagram
    Case ||--o{ ReturnOrder : "CaseId"
    Account ||--o{ ReturnOrder : "AccountId / ShipToAddressAccount__c"
    User ||--o{ ReturnOrder : "SalesRep__c"
    ReturnOrder ||--o{ ReturnOrder : "ParentReturnOrder__c (Redirect / Vendor)"
    Location ||--o{ ReturnOrder : "DestinationLocationId (Repair Center)"
    ReturnOrder ||--o{ ReturnOrderLineItem : "ReturnOrderId"
    Asset ||--o{ ReturnOrderLineItem : "AssetId"
    Department__c ||--o{ ReturnOrderLineItem : "Department__c"
    Location ||--o{ RepairCenterRoutingRule__c : "RepairCenter__c"

    ReturnOrder ||--o{ WorkOrder : "ReturnOrder__c / ReturnOrderId"
    ReturnOrderLineItem ||--o| WorkOrder : "ReturnOrderLineItemId"
    WorkOrder ||--o{ WorkOrder : "ParentWorkOrderId / VendorWorkOrder__c"
    Location ||--o{ WorkOrder : "RepairCenter__c / Rack__c"
    Account ||--o{ WorkOrder : "Vendor__c / BillTo__c / ShipTo__c"
    ServiceTeam__c ||--o{ WorkOrder : "ServiceTeam__c"
    User ||--o{ WorkOrder : "Evaluator__c / Receiver__c"
    Case ||--o{ WorkOrder : "CaseId"
    WorkOrder ||--o{ WorkOrderLineItem : "WorkOrderId"
    PFCL__c ||--o{ WorkOrderLineItem : "PFCL__c"
    ServiceBOM__c ||--o{ WorkOrderLineItem : "ServiceBOM__c"

    WorkOrder ||--o{ WOAssignmentHistory__c : "WorkOrder__c"
    WorkOrder ||--o{ WarrantyRepairEvaluation__c : "WorkOrder__c"
    WorkOrder ||--o{ NonconformanceReport__c : "WorkOrder__c"
    NonconformanceReport__c ||--o{ NonconformanceReportLineItem__c : "NonconformanceReport__c"
    WorkOrder ||--o{ RepairCenterTeamMember__c : "WorkOrder__c"
    Location ||--o{ ServiceTeam__c : "Location__c"
```

**Work order status lifecycle**

```mermaid
stateDiagram-v2
    [*] --> Created: Return Order created (Case)
    Created --> Received: Receiving (ROLI Received)
    Created --> Redirected: Redirect → cloned RO
    Received --> Evaluate: Open evaluation (Evaluator__c)
    Received --> Divide: Instrument tray
    Divide --> Evaluate_Quote
    Evaluate --> Quote: Estimate required
    Evaluate_Quote --> Quote
    Evaluate --> WarrantyInspection: Warranty claim
    Quote --> WaitingForApproval
    WaitingForApproval --> PORequired: Approved, no PO
    WaitingForApproval --> CustomerCare: Customer replies Help
    PORequired --> ReadyForRepair: PO file linked
    Evaluate --> ReadyForRepair: No estimate needed
    Evaluate --> ShipToVendor: Vendor repair
    ReadyForRepair --> Repair: Rack / Technician assigned
    Repair --> QC: Ready for QC
    QC --> Repair: QC Fail (NCR required)
    QC --> Ship: QC Pass (no open NCR lines)
    Ship --> [*]
```

**Key rules**
- **Routing.** `RepairCenterRoutingRule__c` matches on Operating Unit, Product Line, Sub-line, Manufacturer, Device Type, Model and Ship State to pick the repair center.
- **Return Order split.** Return Orders are split by repair center, non-sterilized items, Mod Request, `MaxItemsPerReturn__c` and `ReturnOrderType__c` (Serialized / Instruments / Other).
- **Shop-floor blocks.** Rack and technician assignment are blocked in Received, Divide, Evaluate, Evaluate & Quote and Quote. Each assignment is logged in `WOAssignmentHistory__c`.
- **Ship date.** `ScheduledShipDate__c` = `TurnTime__c` + the Repair Center's `OperatingHours` holidays.
- **Customer preferences.** "Photos required" is enforced at evaluation. "Carrier Service level" sets the FedEx service level.

---

## 9. Field Service (ES / IMS)

```mermaid
erDiagram
    WorkOrder ||--o{ ServiceAppointment : "ParentRecordId / FSSK__FSK_Work_Order__c"
    ServiceResource ||--o{ ServiceAppointment : "FSSK__FSK_Assigned_Service_Resource__c / Truck__c"
    ServiceTerritory ||--o{ ServiceAppointment : "ServiceTerritoryId"
    Account ||--o{ AddressResourcePreference__c : "AddressAccount__c"
    ServiceResource ||--o{ AddressResourcePreference__c : "ServiceResource__c"
    Location ||--o{ ProductItem : "LocationId (Trunk stock)"
    Product2 ||--o{ ProductItem : "Product2Id"
    WorkOrder ||--o{ ProductRequest : "WorkOrderId"
    Case ||--o{ ProductRequest : "CaseId"
    ServiceResource ||--o{ ProductRequest : "ServiceResource__c"
    WorkOrderLineItem ||--o{ Case : "WorkOrderLineItem__c (Part Exception)"
    ServiceResource ||--o{ WorkOrderLineItem : "AssignedResource__c"
    ProductItem ||--o{ WorkOrderLineItem : "ProductItem__c"
```

- **IMS debrief** (`WoDebriefIMSController`):
  - Creates a truck ServiceAppointment linked by a "Same Start" dependency.
  - Site visit review is blocked while any child WO is open or any line is still flagged `SendToRepairCenter__c`.
  - Flagged lines feed a site-visit Return Order.
- **ES debrief:**
  - Allowed units and billing type.
  - Trunk-stock ProductItem lookup.
  - Skill check.
  - Rate list and regional expenses.
  - Asset inspection.
  - Part exception Cases.
- **Photos.** `MobileDevicePictureLink__e` attaches photos, and microscope capture attaches images to WOLIs.
- **Realignment.** `ServiceAppointmentRealignmentBatch` flags territory and preferred-resource conflicts.
- **Skills.** `SummitSkill__c` staging records sync to WorkType, Skill and SkillRequirement.
- **Assets.** `AssetPendingInactivationTrigger` blocks inactivation while open WOs or active contract lines exist.

---

## 10. CSC Visits, Team Members & Access

```mermaid
erDiagram
    Account ||--o{ CSC_Visit_Request__c : "AccountFacility__c"
    Opportunity ||--o{ CSC_Visit_Request__c : "Opportunity__c"
    User ||--o{ CSC_Visit_Request__c : "VisitRequestor__c"
    CSC_Visit_Request__c ||--o{ CSCVisitAttendee__c : "CSCVisit__c"
    User ||--o{ CSCVisitAttendee__c : "STERISAttendee__c"
    Contact ||--o{ CSCVisitAttendee__c : "Contact__c"
    CSC_Visit_Request__c ||--o{ TeamMember__c : "CSCVisitRequest__c (generic parent)"
    User ||--o{ TeamMember__c : "User__c"
    Account ||--o{ TemporaryAccessException__c : "Account__c"
    Opportunity ||--o{ TemporaryAccessException__c : "Opportunity__c"
    User ||--o{ TemporaryAccessException__c : "Requester__c / CoverageRep__c"
    TemporaryAccessException__c ||--o{ TAE_AssignedRecord__c : "TemporaryAccessException__c"
    TemporaryAccessException__c ||--o{ TAEProcessingWorkItem__c : "TemporaryAccessException__c"
```

- **CSC visit statuses:** Requested → Approved → Confirmed, with side states Postponed and Cancelled.
- **CSC visit rules:**
  - Each location (ORC / IMS / OSV) has its own calendar.
  - An Approved visit holds its date for 10 days.
  - A Confirmed visit sends a confirmation email and creates an all-day Event.
  - `Opportunity.CSCVisitRequestCount__c` is recounted on insert, delete and undelete.
- **TeamMember__c** works with any parent object: the parent lookup is found by describe. Only one user is allowed per parent, and access is given through Apex sharing (row cause `TeamMember__c`).
- **TAE pipeline:**
  - Steps: Orchestrator → Creation → Grant/Revoke → HandbackDraft → Cleanup.
  - Grant happens on the start date: the CoverageRep is added as a "Temporary Assignment" team member.
  - Revoke happens on the end date.
- **Inactive sales users.** `InactiveUserTeamCleanup` writes assignment history and removes ATM/OTM records.

---

## 11. Integration Inventory

| # | Class / Entry point | Direction | Endpoint / Setting | Objects |
|---|---|---|---|---|
| 1 | `OraclePricingGateway` ← `OraclePricingService`, `OraclePricingFlowQueueable` | Out | `callout:Oracle_Pricing_API/getPricingDetail/` | OLI, QLI, WorkOrder pricing |
| 2 | `OracleUnitPricingGateway` (+Part2) | Out (Boomi) | `SF_GET_UNIT_PRICE`, `SF_GET_PROSPECT_PRICE` | QLI, `Contract__c` (prospect path mocked) |
| 3 | `GenerateQuoteRefreshGateway`, `RefreshQuoteSyncService` | Out/In | `SF_REFRESH_QUOTE` | Quote, QLI |
| 4 | `SalesConnectionUrlService` / `EncryptionService` | Out (deep link) | `ExternalSystemEndpoint__mdt` | Quote |
| 5 | `OpportunityQuoteContextService` | **In** REST | `POST /v1/opportunity-quote-context` | Opportunity, Quote |
| 6 | `ScOpportunityQuoteEventGateway` | Out | `SF_SC_OPPORTUNITY_QUOTE_EVENTS` | Opportunity / Quote forecast |
| 7 | `ProspectAccountScSyncGateway` | Out | `SF_PROSPECT_ACCOUNT_SC_SYNC` | Prospect Account |
| 8 | `TasAssignmentGateway`, `AccountCustomerTasGateway` (+ Queueables) | Out (Boomi TAS) | `SF_PROSPECT_TAS`, `SF_CUSTOMER_TAS` | Account, Lead, OrderLineContact__c, AccountTeamMember |
| 9 | `TASTeamAccessBatch` / `LSTASTeamAccessBatch` | Batch | — | OrderLineContact__c → AccountTeamMember |
| 10 | `ProductRequestsService` | Out | `ORACLE_CREATESALESORDER_DEV` | ProductRequest → Oracle Sales Order |
| 11 | `ProductRequestsDpcService` | Out | `DPC_GETPRODUCTINSTANCE_DEV` | Asset / product instance |
| 12 | `FedExService`, `VendorFedExShipmentService` | Out | `FEDEX_LABEL` | ReturnOrder, WorkOrder tracking |
| 13 | `PrinterService` | Out | `STERIS_PRINT_LABEL_ZEBRA_DEV` | WorkOrder bin tags |
| 14 | `ConnectCareRestService` | **In** REST | `/connectcare/v1/return-orders` (POST), `/assets` (GET) | Account, Asset, ReturnOrder |
| 15 | `WorkOrderLineItemFileThumbnailRest` | **In** REST | `GET /woli/v1/file-thumbnail/*` | WOLI files |
| 16 | `CreateCase__e` → `CreateCaseEventTrigger` | **In** Platform Event | — | Order → Case / Task |
| 17 | `DataMigrationTriggerOn*` (gated by label `ExecuteTrigger`) | **In** data load | — | Account, Address → Location, Order, OrderItem, Product |
| 18 | `SummitSkillProcessor` | In (staging, Batch + Schedulable) | `SummitSkill__c` | WorkType, Skill |
| 19 | `EmailInboundHandler` / `EmailInboundService` | In (Email Service) | — | WorkOrder (repair quote replies) |
| 20 | `BoomiTasClient` | Out (unused) | `callout:Boomi_TAS_Named_Credential` | — (returns a mock, no callers) |

Most outbound calls go through the **ShoutOut `SO_Callout` framework**, where each operation name above is a setting. That framework and Nebula `Logger` are **not in this repo**.

---

## 12. Master Relationship Reference Table

| Child object | Lookup field | Parent object |
|---|---|---|
| Account | ParentId | Account |
| Account | Price_List__c | Price_List__c |
| Account | IDN_Account__c, GPO_Account__c | Account |
| AccountAccountRelationship__c | ParentAccount__c, ChildAccount__c | Account |
| AccountDepartment__c | Account__c, Department__c | Account, Department__c |
| Address | ParentId / Customer__c | Location / Account |
| Contact | AccountId | Account |
| CustomerPreference__c | Account__c | Account |
| Lead_SLA__c | Lead__c | Lead |
| LeadProduct__c | Lead__c, Product__c | Lead, Product2 |
| Opportunity | AccountId, Pricebook2Id, PrimaryContact__c, Address__c, RelatedProjectOpportunity__c | Account, Pricebook2, Contact, Address, Opportunity |
| OpportunityLineItem | OpportunityId, PricebookEntryId, Product2Id | Opportunity, PricebookEntry, Product2 |
| OpportunityContactRole / OpportunityTeamMember | OpportunityId | Opportunity |
| Sample__c | RelatedOpportunity__c | Opportunity |
| DealApprovalApprover__c | Opportunity__c, Approver__c | Opportunity, User |
| Project__c | Account__c, PrimaryCase__c, ProjectTemplate__c | Account, Case, template |
| ProjectCases__c | Project__c, Case__c | Project__c, Case |
| Free_Goods_Task_Product__c | Account__c, Product__c (TaskId__c = text) | Account, Product2 |
| Product2 | PFCL__c, PSAM__c | PFCL__c, PSAM__c |
| PricebookEntry | Pricebook2Id, Product2Id | Pricebook2, Product2 |
| PFCL__c | Parent__c | PFCL__c |
| ServiceBOM__c | PFCL__c | PFCL__c |
| PFCLServiceBOM__c | PFCL__c, ServiceBOM__c | PFCL__c, ServiceBOM__c |
| Asset | AccountId, Product2Id | Account, Product2 |
| Quote | OpportunityId, AccountId, WorkOrder__c | Opportunity, Account, WorkOrder |
| QuoteLineItem | QuoteId, PricebookEntryId, Asset__c, PFCL__c, WorkOrderLineItem__c, TopLevelWorkOrder__c | Quote, PBE, Asset, PFCL__c, WOLI, WorkOrder |
| ContractModifier__c | QuoteLineItem__c, Quote__c, ParentContractModifier__c | QLI, Quote, ContractModifier__c |
| Order | ParentCase__c, BLOwner__c, OMOwner__c, LogisticsOwner__c | Case, User |
| OrderItem | OrderId, Subcase__c, Case__c | Order, Case |
| OrderAndOrderLineHold__c | Order__c, OrderLine__c, HoldMatrix__c | Order, OrderItem, HoldMatrix__c |
| OrderLineContact__c | Order__c, OrderLine__c, SalesRep__c, AssignedSalesRep__c, RegionManager__c, ZoneManager__c | Order, OrderItem, Contact, User |
| Case | Order__c, WorkOrderLineItem__c | Order, WOLI |
| Task | WhatId, Order__c, OrderLine__c, OrderAndOrderLineHold__c | Case, Order, OrderItem, Hold |
| ReturnOrder | CaseId, AccountId, ContactId, SalesRep__c, DestinationLocationId, ParentReturnOrder__c, ShipToAddressAccount__c | Case, Account, Contact, User, Location, ReturnOrder, Account |
| ReturnOrderLineItem | ReturnOrderId, AssetId, Product2Id, Department__c, Contact__c | ReturnOrder, Asset, Product2, Department__c, Contact |
| RepairCenterRoutingRule__c | RepairCenter__c | Location |
| WorkOrder | ReturnOrder__c, ReturnOrderLineItemId, ParentWorkOrderId, VendorWorkOrder__c, RepairCenter__c, Rack__c, Vendor__c, BillTo__c, ShipTo__c, ServiceTeam__c, Evaluator__c, Receiver__c, EstimateContact__c, Department__c, AssetId, CaseId, ActiveQuote__c | ReturnOrder, ROLI, WorkOrder, Location, Account, ServiceTeam__c, User, Contact, Department__c, Asset, Case, Quote |
| WorkOrderLineItem | WorkOrderId, VendorWorkOrder__c, Vendor__c, Product__c, ProductItem__c, AssignedResource__c, PFCL__c, ServiceBOM__c, TopLevelWorkOrder__c | WorkOrder, Account, Product2, ProductItem, ServiceResource, PFCL__c, ServiceBOM__c |
| WOAssignmentHistory__c | WorkOrder__c, Rack__c, Technician__c | WorkOrder, Location, User |
| WarrantyRepairEvaluation__c | WorkOrder__c, WorkOrderLineItem__c, ParentWorkOrder__c, RelatedReturnOrder__c, TechnicianPerformingWork__c | WorkOrder, WOLI, ReturnOrder, User |
| NonconformanceReport__c | WorkOrder__c, WorkOrderLineItem__c, Account__c, RepairCenter__c, Asset__c, Product__c | WorkOrder, WOLI, Account, Location, Asset, Product2 |
| NonconformanceReportLineItem__c | NonconformanceReport__c, InitiatedBy__c, QualityInspector__c | NCR, User |
| RepairCenterTeamMember__c | WorkOrder__c, WorkOrderLineItem__c, Person__c | WorkOrder, WOLI, User |
| ServiceTeam__c | Location__c | Location |
| ServiceAppointment | ParentRecordId, FSSK__FSK_Work_Order__c, FSSK__FSK_Assigned_Service_Resource__c, Truck__c | WorkOrder, ServiceResource |
| AddressResourcePreference__c | AddressAccount__c, ServiceResource__c | Account, ServiceResource |
| ProductRequest | WorkOrderId, CaseId, AssetId, ServiceResource__c | WorkOrder, Case, Asset, ServiceResource |
| ProductItem | LocationId, Product2Id | Location, Product2 |
| CSC_Visit_Request__c | AccountFacility__c, Opportunity__c, VisitRequestor__c | Account, Opportunity, User |
| CSCVisitAttendee__c | CSCVisit__c, STERISAttendee__c, Contact__c | CSC_Visit_Request__c, User, Contact |
| TeamMember__c | User__c + dynamic parent lookup | User, any |
| TemporaryAccessException__c | Account__c, Opportunity__c, Requester__c, CoverageRep__c | Account, Opportunity, User |
| TAE_AssignedRecord__c / TAEProcessingWorkItem__c | TemporaryAccessException__c, Account__c, Opportunity__c | TAE, Account, Opportunity |

---

## 13. Business Analysis

### 13.1 Business capabilities

| Capability | Business value | Primary users | Maturity (from code) |
|---|---|---|---|
| Customer master and IDN/GPO hierarchy | One view of contracting entities, facilities and ship-tos; drives pricing and territory | Sales Ops, Contracting | **High:** relationship engine and roll-ups built |
| Territory assignment (TAS) | Automatic account and lead ownership, plus coverage for reps and managers | Sales Ops | **High:** delta-based, with retry and failure notifications |
| Opportunity and forecasting | Pipeline accuracy: one forecast-eligible quote, confidence banners, closure gates | Sales Reps, Managers | **High** |
| Product selection and pricing | Faster, compliant line entry with Oracle contract pricing | Sales Reps | **Medium:** split across many pickers; real-time Oracle pricing |
| Service contract configuration (ES/IMS) | Asset-based coverage quoting (model quantity, inclusions and exclusions, PM visits) | Service Sales | **Low–Medium:** POC/demo pricing hooks remain |
| Deal and EPP approvals | Margin governance | Deal Desk, BU Leaders | **High** |
| Order-to-Case orchestration (CBM) | Every Oracle order is tracked with SLA tasks, hold visibility and auto-close | Customer Care, Order Mgmt, Logistics | **High:** event-driven with batch fallback |
| Depot repair | Inbound logistics, evaluation, quoting, shop-floor routing, QC and shipping | Repair Center techs, coordinators | **High:** largest code area (`WorkOrdersService` is over 7k lines) |
| Field service debrief | Accurate billing, parts consumption and skills compliance | Field Engineers | **Medium–High** |
| Customer Solutions Center visits | Customer experience and pipeline influence | Sales, CSC coordinators | **High** |
| Temporary access (TAE) | Controlled, time-boxed record access | Sales Ops | **High** |
| Dealer portal | Partner opportunity registration | Dealers | **Medium** |

### 13.2 Value stream: Lead to Cash to Service

```mermaid
flowchart LR
    L[Lead<br/>SLA clock] --> O[Opportunity<br/>Products · Samples · CSC Visit]
    O --> Q[Quote<br/>Sales Connection · Configurator]
    Q --> AP[Deal / EPP Approval]
    AP --> W[Closed Won]
    W --> OR[Oracle Order]
    OR --> CBM[CBM Case + Sub-cases<br/>Tasks · Holds · SLA]
    CBM --> INST[Installation Project / Service Install]
    INST --> AS[Installed Asset]
    AS --> FS[Field Service PM / Repair]
    AS --> RC[Depot Repair<br/>Return Order → WO → QC → Ship]
    FS --> REN[Service Contract Quote<br/>ContractModifier__c]
    RC --> REN
    REN --> O
```

### 13.3 Key business rules (summary)

1. **Forecasting:** only one open HC_Sales quote per opportunity is forecast-eligible. An opportunity cannot close while forecast-eligible quotes are still open.
2. **Project opportunities:**
   - Proposal and Commit need at least one linked commercial opportunity.
   - The project cannot close while child opportunities are open.
   - Closed Won needs a Closed Won child.
   - Closed Lost is blocked if any child is Closed Won.
3. **EPP:**
   - An EPP opportunity cannot leave Draft while an elevated consumable has no EPP price.
   - Only EPP-eligible, active products in the right currency can be selected.
4. **Primary contact:** each opportunity has exactly one primary contact role, kept in sync with `PrimaryContact__c`.
5. **Samples:** only the opportunity owner or a team member can create them.
6. **Order holds:** active hold reason codes roll up to the Order and drive hold tasks. Inactive holds close their tasks.
7. **Repair:**
   - QC Fail requires an NCR.
   - QC Pass is blocked while any NCR line is open.
   - Shop-floor actions are locked during evaluation and quoting.
8. **Asset inactivation** is blocked while open work orders or active contract lines exist.
9. **TAS outcome** is Assigned, Assignment Missing (creates a Sales Ops task and notification) or Technical Failure (retry).
10. **Lead SLA:** a queue has 8h, Sales Development 2h, and an assigned user 24h (reminder at 48h).

### 13.4 KPIs the data model supports

| Area | KPI | Source fields |
|---|---|---|
| Sales | Win rate, forecast accuracy, quote-to-close time | Opportunity.StageName, Quote.Forecast_Eligible__c, ForecastConfidenceLevel__c |
| Lead management | SLA compliance % | Lead_SLA__c |
| Order mgmt | Order entry to invoice cycle time, hold ageing, task SLA breach | Case status, OrderAndOrderLineHold__c, Task SLA fields |
| Depot repair | Turnaround time vs `TurnTime__c`, quote approval rate, QC first-pass yield, NCR rate | WorkOrder status history, ScheduledShipDate__c / ActualShipDate__c, NonconformanceReport__c |
| Warranty | Repeat-repair rate | WarrantyRepairEvaluation__c |
| Field service | First-time fix, parts usage, realignment conflicts | ServiceAppointment, ProductItem, RealignmentConflict*__c |
| CSC | Visit-to-win influence | CSC_Visit_Request__c ↔ Opportunity |

### 13.5 Gaps and opportunities

- **Unified Product Browser.** Product search is implemented about 6 times with different filters (EPP, lost business, lead, free goods, configurator, trunk stock). A shared `productSearch` service plus one reusable LWC would keep eligibility rules consistent and cut maintenance.
- **Configurator pricing.** `EsServiceDemoPricePostHook` and `configPocModal` are POC/demo code. The PFCL pricing decision table is still to be built.
- **Ship / close step.** No Apex sets a final ship or close status for repair WOs. Confirm whether Flow or Oracle owns it.
- **Stub services.** The Product2, PFCL, ServiceBOM, Account, Department and Asset handlers are stubs. Either remove them or implement the planned logic.

---

## 14. Technical Findings & Risks

| Severity | Finding | Location |
|---|---|---|
| High | `OrderLineContactTrigger1` (marked "To be deleted") duplicates `OrderLineContactTrigger`, so the handler runs **twice** per DML | `triggers/OrderLineContactTrigger1.trigger` |
| High | `AutomationControl.isTriggerEnabled` is called, but **no `AutomationControl` class exists** in the repo; it fails to compile unless it lives elsewhere in the org | `OrderLineContactTriggerHandler`, `AccountDepartmentTriggerHandler`, service handlers |
| Medium | `AccountTriggerHandler` branches HC vs LS on `newAccounts[0].CustomerClassCode__c` only, so mixed batches are misrouted | `classes/AccountTriggerHandler.cls` |
| Medium | Field-name mismatch: the LWC uses `PFCL_Name__c` / `Requested_Number_of_PM_Visits__c` but Apex uses `PFCLName__c` / `RequestedNumberofPMVisits__c`. Check whether these are context-attribute names or a bug | `lwc/esServiceProductConfigLauncher` |
| Medium | Several triggers have no bypass guard (`OrderItemTrigger`, `CreateCaseEventTrigger`, `ContactDuplicatePrevention`), and EmailMessage has 4 triggers | `triggers/` |
| Medium | PO-link automation in `RepairCenterCdlTrigger` is commented out (GW-375) | `triggers/RepairCenterCdlTrigger.trigger` |
| Low | Unused or dead code: `BoomiTasClient` (mock, no callers), `FreeGoodsTaskProductController`, `configPocModal` (hard-coded attribute Id `11nOu00000ODPpBIAX`) | `classes/`, `lwc/` |
| Low | `imsProductConfigurator` and `modelQtyCoverage` are near-duplicates | `lwc/` |
| Info | External dependencies not in the repo: ShoutOut `SO_Callout`, Nebula `Logger`, FSSK / FSL managed packages, custom metadata types | — |

**Trigger framework.** Kevin O'Hara `TriggerHandler` with `TriggerControl` (recursion guard per object and context). Bypass comes from the hierarchy setting `Automation_Setting_Trigger__c` (`<Object>TriggerByPass__c`, `disableAll__c`). Layering is fflib-style (Selector / Service / Domain).

---

## 15. Glossary

| Term | Meaning |
|---|---|
| **CBM** | Customer / Case-Based Management: the Oracle order-tracking case model |
| **PFCL** | Product Family Classification: the hierarchical product family (`PFCL__c`) |
| **PSAM** | Product sub-group classification used to derive `ProductSubGroupDetailName__c` |
| **Service BOM** | Bill of materials for service parts per PFCL |
| **IDN / GPO** | Integrated Delivery Network / Group Purchasing Organization (contracting parents) |
| **EPP** | Equipment Placement Program (capital placed against a consumables commitment) |
| **TAS** | Territory Assignment System (via Boomi) |
| **TAE** | Temporary Access Exception |
| **CSC** | Customer Solutions Center (visit program) |
| **ES / IMS** | Equipment Service / Instrument Management Services (field service lines) |
| **NCR** | Nonconformance Report (quality) |
| **OLI / QLI / WOLI / ROLI** | Opportunity / Quote / Work Order / Return Order Line Item |
| **HC / SC (LS)** | Healthcare / Life Sciences customer class |
| **DPC** | Digital Parts Catalog |
