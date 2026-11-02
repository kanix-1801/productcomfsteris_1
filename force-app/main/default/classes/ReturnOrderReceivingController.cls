/**
 * @author Uptima Development Team
 * @date 2026-06-14
 * @description Controller for Return Order Receiving LWC (bulk receive flow). Creates work orders, handles redirect, customer care cases.
 * @group Return Order Process
 * @see returnOrderReceiving
 */
public with sharing class ReturnOrderReceivingController {

    private static final String STATUS_CREATED = 'Created';
    private static final String STATUS_RECEIVED = 'Received';
    private static final String STATUS_CANCELED = 'Canceled';
    // --- START RELEVANT TO GW-3337 CONSTANTS ---
    private static final String WO_STATUS_EVALUATE = 'Evaluate';
    private static final String WO_SUB_STATUS_TRIAGE = 'Triage';
    private static final String PRODUCT_LINE_RIGID_SCOPE = 'RIGID SCOPE';
    // --- END RELEVANT TO GW-3337 CONSTANTS ---
    private static final Set<String> DISINFECTED_NO_VALUES = new Set<String>{
        'No, items has not been cleaned and disinfected or Sterilized',
        'No, Item is not Disinfected'
    };
    private static final String WO_RECORD_TYPE_REPAIR_CENTER_DEVICES = 'RepairCenterDevices';
    private static final String WO_RECORD_TYPE_REPAIR_CENTER_INSTRUMENTS = 'RepairCenterInstruments';
    private static final String WO_RECORD_TYPE_REPAIR_CENTER_VENDOR = 'RepairCenterVendor';
    private static final String WO_SUB_STATUS_CONTAMINATED = 'Contaminated';
    private static final String WO_SUB_STATUS_CUSTOMER_CARE = 'Customer Care';
    private static final String WO_SUB_STATUS_MOD_HOLD = 'Mod Hold';
    private static final String WO_SUB_STATUS_READY_FOR_EVAL = 'Ready for Eval';
    private static final String WO_SUB_STATUS_RESOLVED = 'Resolved';
    private static final String WO_SUB_STATUS_VERIFICATION = 'Verification';
    private static final Integer SERIAL_CHANGE_CUSTOMER_CARE_THRESHOLD = 2;
    private static final String WO_STATUS_RECEIVED = 'Received';
    private static final String ESTIMATE_REQUIRED_ESTIMATE_REQUIRED = 'Estimate Required';
    private static final String WOLI_STATUS_WAITING_FOR_APPROVAL = 'Waiting for Approval';
    private static final String WOLI_STATUS_APPROVED = 'Approved';
    private static final String RO_TYPE_SERIALIZED = 'Serialized';
    private static final String RO_TYPE_INSTRUMENTS = 'Instruments';
    private static final String RO_TYPE_OTHER = 'Other';
    private static final String STATUS_REDIRECTED = 'Redirected';
    private static final Integer RECENT_RETURN_ORDER_LIMIT = 10;
    private static final String LOCATION_TYPE_REPAIR_CENTER = 'Repair Center';
    private static final Set<String> INTERNAL_USER_TYPES = new Set<String>{ 'Standard', 'CsnOnly' };
    private static final Set<String> INTEGRATION_PROFILE_KEYWORDS = new Set<String>{
        'Integration',
        'API Only'
    };
    private static final String CASE_RECORD_TYPE_INBOX_SUPPORT = 'InboxSupport';
    private static final String CUSTOMER_CARE_QUEUE_DEVELOPER_NAME = 'QNAIMSCustCareCentralSupport';
    private static final String CUSTOMER_CARE_NOTIFICATION_DEVELOPER_NAME = 'CustomerCareWorkOrderCreated';
    private static final String CASE_STATUS_NEW = 'New';
    private static final String CASE_ORIGIN_CENTRAL_REPAIR_SUPPORT = 'Central Repair Support';
    // Single org-wide defaults row in RepairCenterDefaults__mdt. Add new default fields to that type/record as needed.
    private static final String REPAIR_CENTER_DEFAULTS_RECORD_DEVELOPER_NAME = 'Default';
    private static final String WOLI_RECORD_TYPE_PRODUCT_SERVICED = 'ProductServiced';
    private static final String WOLI_LINE_TYPE_PRODUCT_SERVICED = 'Product Serviced';
    private static final String WOLI_LINE_TYPE_ACCESSORY = 'Accessory';

    private static Boolean customerCareProcessing = false;
    private static RepairCenterDefaults__mdt cachedRepairCenterDefaults;
    private static Id cachedDefaultPricebookId;
    private static Id cachedProductServicedWorkOrderLineItemRecordTypeId;
    private static Id customerCareInboxSupportRecordTypeId;
    private static Id customerCareQueueIdCache;
    private static Id customerCareDefaultBusinessHoursId;
    private static Id customerCareNotificationTypeId;

    /**
     * @description Return order receiving screen context with header fields and line rows.
     */
    public class ReceivingContext {
        @AuraEnabled public String returnOrderId;
        @AuraEnabled public String returnOrderNumber;
        @AuraEnabled public String returnOrderType;
        @AuraEnabled public String accountId;
        @AuraEnabled public String accountName;
        @AuraEnabled public String repairCenterId;
        @AuraEnabled public String repairCenterName;
        @AuraEnabled public String repairCenterAddress;
        @AuraEnabled public String currentUserId;
        @AuraEnabled public Boolean defaultIsContaminated;
        @AuraEnabled public Decimal headerQuantityReturned;
        @AuraEnabled public Decimal headerQuantityReceived;
        @AuraEnabled public Decimal defaultInstrumentQuantityReceived;
        @AuraEnabled public Integer openLineItemCount;
        @AuraEnabled public List<ReceivingLineRow> lineItems;
        @AuraEnabled public List<PicklistOption> disinfectedOptions;
        @AuraEnabled public List<PicklistOption> estimateRequiredOptions;
    }

    /**
     * @description Single return order line row displayed on the receiving UI.
     */
    public class ReceivingLineRow {
        @AuraEnabled public String lineItemId;
        @AuraEnabled public String lineNumber;
        @AuraEnabled public String status;
        @AuraEnabled public String assetId;
        @AuraEnabled public String assetName;
        @AuraEnabled public String serialNumber;
        @AuraEnabled public String productId;
        @AuraEnabled public String productName;
        @AuraEnabled public String productLine;
        @AuraEnabled public String hospitalTrayName;
        @AuraEnabled public String itemDescription;
        @AuraEnabled public Decimal quantityReturned;
        @AuraEnabled public Decimal quantityReceived;
        @AuraEnabled public Boolean selectable;
        @AuraEnabled public String model;
        @AuraEnabled public String departmentId;
        @AuraEnabled public String lineType;
        @AuraEnabled public String itemType;
        @AuraEnabled public String rowClass;
        @AuraEnabled public String contactId;
        @AuraEnabled public String estimateRequired;
        @AuraEnabled public String estimateContactId;
        @AuraEnabled public String repairWarranty;
        @AuraEnabled public String warrantyNotes;
        @AuraEnabled public String previousReturnOrder;
        @AuraEnabled public String customerPo;
        @AuraEnabled public String customerReference;
        @AuraEnabled public String reportedProblem;
        @AuraEnabled public Boolean modRequest;
        @AuraEnabled public String disinfected;
        @AuraEnabled public Boolean isLoanerAsset;
        @AuraEnabled public Boolean loanerRequested;
    }

    /**
     * @description Picklist option for LWC comboboxes.
     */
    public class PicklistOption {
        @AuraEnabled public String label;
        @AuraEnabled public String value;
    }

    /**
     * @description Item type to product line mapping from custom metadata.
     */
    public class ItemTypeProductLineMapping {
        @AuraEnabled public String itemType;
        @AuraEnabled public String productLine;
    }

    /**
     * @description Accessory details captured during bulk receive.
     */
    public class AccessoryInput {
        @AuraEnabled public String accessoryType;
        @AuraEnabled public String condition;
        @AuraEnabled public String storageLocation;
        @AuraEnabled public Decimal quantity;
    }

    /**
     * @description Line-level receive input submitted from the LWC.
     */
    public class LineReceiveInput {
        @AuraEnabled public String lineItemId;
        @AuraEnabled public Boolean isAdHocSerializedLine;
        @AuraEnabled public String adHocLineKey;
        @AuraEnabled public Decimal quantityReceived;
        @AuraEnabled public Boolean hasCorrections;
        @AuraEnabled public String serialNumber;
        @AuraEnabled public String model;
        @AuraEnabled public Id departmentId;
        @AuraEnabled public String productLine;
        @AuraEnabled public Id selectedAssetId;
        @AuraEnabled public Id productId;
        @AuraEnabled public String itemType;
        @AuraEnabled public String hospitalTrayName;
        @AuraEnabled public Decimal quantityReturned;
        @AuraEnabled public List<AccessoryInput> accessories;
        @AuraEnabled public Id contactId;
        @AuraEnabled public String estimateRequired;
        @AuraEnabled public Id estimateContactId;
        @AuraEnabled public String repairWarranty;
        @AuraEnabled public String warrantyNotes;
        @AuraEnabled public String previousReturnOrder;
        @AuraEnabled public String customerPo;
        @AuraEnabled public String customerReference;
        @AuraEnabled public String reportedProblem;
        @AuraEnabled public Boolean modRequest;
        @AuraEnabled public String disinfected;
        @AuraEnabled public Boolean isLoanerAsset;
        @AuraEnabled public Boolean loanerRequested;
    }

    /**
     * @description Product option for line correction picklists.
     */
    public class ProductPicklistOption {
        @AuraEnabled public String label;
        @AuraEnabled public String value;
    }

    /**
     * @description Result of bulk receive including work order Ids and received status.
     */
    public class BulkReceiveResult {
        @AuraEnabled public String primaryWorkOrderId;
        @AuraEnabled public String navigationWorkOrderId;
        @AuraEnabled public List<String> workOrderIds;
        @AuraEnabled public Boolean returnOrderReceived;
        @AuraEnabled public Integer expectedSerializedChildCount;
    }

    /**
     * @description Summary row for recent return orders lookup list.
     */
    public class ReturnOrderSummaryRow {
        @AuraEnabled public String id;
        @AuraEnabled public String returnOrderNumber;
        @AuraEnabled public String repairCenterName;
        @AuraEnabled public String returnOrderType;
        @AuraEnabled public Datetime createdDate;
    }

    /**
     * @description Account asset option for line correction selection.
     */
    public class AccountAssetOption {
        @AuraEnabled public String id;
        @AuraEnabled public String label;
        @AuraEnabled public String serialNumber;
        @AuraEnabled public String model;
        @AuraEnabled public String departmentId;
        @AuraEnabled public String productLine;
    }

    /**
     * @description Result of redirect line item action with new return order details.
     */
    public class RedirectActionResult {
        @AuraEnabled public String returnOrderId;
        @AuraEnabled public String returnOrderNumber;
    }

    /**
     * @description Loads return order header, line items, and defaults for the receiving LWC.
     * @param returnOrderId Return order Id to load.
     * @return Receiving context with header fields and line rows.
     */
    @AuraEnabled(cacheable=true)
    public static ReceivingContext getReceivingContext(Id returnOrderId) {
        try {
            if (returnOrderId == null) {
                throw new AuraHandledException('Return order is required.');
            }

            ReturnOrder returnOrder = [
                SELECT
                    Id,
                    ReturnOrderNumber,
                    ReturnOrderType__c,
                    AccountId,
                    Account.Name,
                    DestinationLocationId,
                    DestinationLocation.Name,
                    QuantityReturned__c,
                    QuantityReceived__c
                FROM ReturnOrder
                WHERE Id = :returnOrderId
                WITH USER_MODE
                LIMIT 1
            ];

            List<ReturnOrderLineItem> lineItems = [
                SELECT
                    Id,
                    ReturnOrderLineItemNumber,
                    Status__c,
                    AssetId,
                    Asset.Name,
                    Asset.SerialNumber,
                    Product2Id,
                    Product2.Name,
                    ProductLine__c,
                    QuantityReturned,
                    QuantityReceived,
                    HospitalReferencedTrayName__c,
                    ItemDescription__c,
                    Disinfected__c,
                    Model__c,
                    Department__c,
                    LineType__c,
                    ItemType__c,
                    SerialNumber__c,
                    Contact__c,
                    EstimateRequired__c,
                    EstimateContact__c,
                    RepairWarranty__c,
                    WarrantyNotes__c,
                    PreviousReturnOrder__c,
                    CustomerPO__c,
                    CustomerReference__c,
                    ReportedProblem__c,
                    ModRequest__c,
                    IsLoanerAsset__c,
                    LoanerRequested__c
                FROM ReturnOrderLineItem
                WHERE ReturnOrderId = :returnOrderId
                WITH USER_MODE
                ORDER BY ReturnOrderLineItemNumber ASC
            ];

            ReceivingContext context = new ReceivingContext();
            context.returnOrderId = returnOrder.Id;
            context.returnOrderNumber = returnOrder.ReturnOrderNumber;
            context.returnOrderType = resolveReturnOrderType(returnOrder.ReturnOrderType__c);
            context.accountId = returnOrder.AccountId;
            context.accountName = returnOrder.Account?.Name;
            context.repairCenterId = returnOrder.DestinationLocationId;
            context.repairCenterName = returnOrder.DestinationLocation?.Name;
            context.repairCenterAddress = resolveLocationAddress(returnOrder.DestinationLocationId);
            context.currentUserId = UserInfo.getUserId();
            context.defaultIsContaminated = false;
            context.headerQuantityReturned = returnOrder.QuantityReturned__c;
            context.headerQuantityReceived = returnOrder.QuantityReceived__c;
            context.defaultInstrumentQuantityReceived = 0;
            context.openLineItemCount = 0;
            context.lineItems = new List<ReceivingLineRow>();
            context.disinfectedOptions = getDisinfectedPicklistOptions();
            context.estimateRequiredOptions = getEstimateRequiredPicklistOptions();

            for (ReturnOrderLineItem lineItem : lineItems) {
                if (DISINFECTED_NO_VALUES.contains(lineItem.Disinfected__c)) {
                    context.defaultIsContaminated = true;
                }
                if (lineItem.Status__c == STATUS_CREATED) {
                    context.openLineItemCount++;
                }

                Decimal lineQuantityReceived = resolveLineQuantityReceived(
                    lineItem,
                    context.returnOrderType
                );
                if (context.returnOrderType == RO_TYPE_INSTRUMENTS) {
                    context.defaultInstrumentQuantityReceived += lineQuantityReceived;
                }

                context.lineItems.add(mapReceivingLineRow(lineItem, context.returnOrderType));
            }

            if (context.returnOrderType == RO_TYPE_INSTRUMENTS) {
                context.defaultInstrumentQuantityReceived = resolveInstrumentHeaderQuantityDefault(
                    returnOrder.QuantityReceived__c,
                    context.defaultInstrumentQuantityReceived
                );
            }

            return context;
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw new AuraHandledException('Error loading receiving context: ' + e.getMessage());
        }
    }

    /**
     * @description Returns products available for line correction filtered by product line.
     * @param productLine Product line used to filter products.
     * @param additionalProductId Optional product Id to include even when outside the filter.
     * @param requireServiceAssetType When true, limits to service asset type products.
     * @return Product picklist options for line correction.
     */
    @AuraEnabled(cacheable=true)
    public static List<ProductPicklistOption> getProductsForLineCorrection(
        String productLine,
        Id additionalProductId,
        Boolean requireServiceAssetType
    ) {
        try {
            if (String.isBlank(productLine)) {
                return new List<ProductPicklistOption>();
            }

            Boolean requireServiceAsset = requireServiceAssetType != null
                ? requireServiceAssetType
                : true;

            Set<Id> productIds = new Set<Id>();
            if (additionalProductId != null) {
                productIds.add(additionalProductId);
            }

            List<ProductPicklistOption> options = new List<ProductPicklistOption>();
            List<Product2> products = Product2QueryUtil.queryProductsByProductLineForCorrection(
                productLine,
                requireServiceAsset
            );

            for (Product2 product : products) {
                productIds.add(product.Id);
                options.add(buildProductPicklistOption(product));
            }

            if (additionalProductId != null && !productIds.contains(additionalProductId)) {
                Product2 additionalProduct = Product2QueryUtil.queryProductByIdForCorrection(
                    additionalProductId
                );
                if (additionalProduct != null) {
                    options.add(0, buildProductPicklistOption(additionalProduct));
                }
            }

            return options;
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw new AuraHandledException('Error retrieving products: ' + e.getMessage());
        }
    }

    /**
     * @description Returns ItemType__c picklist options for return order line items.
     * @return Item type picklist options.
     */
    @AuraEnabled(cacheable=true)
    public static List<PicklistOption> getItemTypeOptions() {
        try {
            Map<String, Schema.SObjectField> lineFields =
                Schema.SObjectType.ReturnOrderLineItem.fields.getMap();
            if (!lineFields.containsKey('ItemType__c')) {
                return new List<PicklistOption>();
            }
            return buildPicklistOptions(lineFields.get('ItemType__c').getDescribe());
        } catch (Exception e) {
            throw new AuraHandledException('Error retrieving item type options: ' + e.getMessage());
        }
    }

    /**
     * @description Returns AccessoryType__c picklist options for work order line items.
     * @return Accessory type picklist options.
     */
    @AuraEnabled(cacheable=true)
    public static List<PicklistOption> getAccessoryTypeOptions() {
        return getWorkOrderLineItemPicklistOptions('AccessoryType__c');
    }

    /**
     * @description Returns Condition__c picklist options for accessory work order line items.
     * @return Accessory condition picklist options.
     */
    @AuraEnabled(cacheable=true)
    public static List<PicklistOption> getAccessoryConditionOptions() {
        return getWorkOrderLineItemPicklistOptions('Condition__c');
    }

    private static List<PicklistOption> getWorkOrderLineItemPicklistOptions(String fieldApiName) {
        try {
            Map<String, Schema.SObjectField> workOrderLineItemFields =
                Schema.SObjectType.WorkOrderLineItem.fields.getMap();
            if (!workOrderLineItemFields.containsKey(fieldApiName)) {
                return new List<PicklistOption>();
            }
            return buildPicklistOptions(workOrderLineItemFields.get(fieldApiName).getDescribe());
        } catch (Exception e) {
            throw new AuraHandledException(
                'Error retrieving accessory options: ' + e.getMessage()
            );
        }
    }

    /**
     * @description Returns item type to product line mappings from custom metadata.
     * @return Item type and product line mapping rows.
     */
    @AuraEnabled(cacheable=true)
    public static List<ItemTypeProductLineMapping> getItemTypeProductLineMappings() {
        try {
            List<ItemTypeProductLineMapping> mappings = new List<ItemTypeProductLineMapping>();
            for (ROLIItemTypeandProductLine__mdt mappingRecord : [
                SELECT ItemType__c, ProductLine__c
                FROM ROLIItemTypeandProductLine__mdt
                WHERE ItemType__c != NULL AND ProductLine__c != NULL
                WITH USER_MODE
            ]) {
                ItemTypeProductLineMapping mapping = new ItemTypeProductLineMapping();
                mapping.itemType = mappingRecord.ItemType__c;
                mapping.productLine = mappingRecord.ProductLine__c;
                mappings.add(mapping);
            }
            return mappings;
        } catch (Exception e) {
            throw new AuraHandledException(
                'Error retrieving item type mappings: ' + e.getMessage()
            );
        }
    }

    /**
     * @description Returns recently created return orders for lookup selection.
     * @return Summary rows for return orders in Created status.
     */
    @AuraEnabled(cacheable=true)
    public static List<ReturnOrderSummaryRow> getRecentCreatedReturnOrders() {
        try {
            List<ReturnOrderSummaryRow> rows = new List<ReturnOrderSummaryRow>();
            for (ReturnOrder returnOrder : [
                SELECT
                    Id,
                    ReturnOrderNumber,
                    ReturnOrderType__c,
                    CreatedDate,
                    DestinationLocation.Name
                FROM ReturnOrder
                WHERE Status = :STATUS_CREATED
                WITH USER_MODE
                ORDER BY CreatedDate DESC
                LIMIT :RECENT_RETURN_ORDER_LIMIT
            ]) {
                ReturnOrderSummaryRow row = new ReturnOrderSummaryRow();
                row.id = returnOrder.Id;
                row.returnOrderNumber = returnOrder.ReturnOrderNumber;
                row.repairCenterName = returnOrder.DestinationLocation?.Name;
                row.returnOrderType = returnOrder.ReturnOrderType__c;
                row.createdDate = returnOrder.CreatedDate;
                rows.add(row);
            }
            return rows;
        } catch (Exception e) {
            throw new AuraHandledException('Error retrieving return orders: ' + e.getMessage());
        }
    }

    /**
     * @description Finds a return order by number and validates it is eligible for receiving.
     * @param returnOrderNumber Return order number entered by the user.
     * @return Validated return order Id.
     */
    @AuraEnabled
    public static String findReturnOrderByNumber(String returnOrderNumber) {
        try {
            ReturnOrder returnOrder = resolveReturnOrderByNumber(returnOrderNumber);
            if (returnOrder == null) {
                throw new AuraHandledException('Return order was not found.');
            }

            return validateReturnOrderForReceiving(returnOrder.Id, returnOrder.Status);
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw new AuraHandledException('Error looking up return order: ' + e.getMessage());
        }
    }

    /**
     * @description Validates a return order Id is eligible for receiving.
     * @param returnOrderId Return order Id to validate.
     * @return Validated return order Id.
     */
    @AuraEnabled
    public static String validateReturnOrderForReceiving(Id returnOrderId) {
        try {
            if (returnOrderId == null) {
                throw new AuraHandledException('Return order is required.');
            }

            ReturnOrder returnOrder = queryReturnOrderForValidation(returnOrderId);
            return validateReturnOrderForReceiving(returnOrder.Id, returnOrder.Status);
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw new AuraHandledException(
                'Error validating return order: ' + e.getTypeName() + ': ' + e.getMessage()
            );
        }
    }

    /**
     * @description Returns account assets available for line correction selection.
     * @param accountId Account Id whose assets to query.
     * @return Account asset options for correction picklists.
     */
    @AuraEnabled(cacheable=true)
    public static List<AccountAssetOption> getAccountAssetsForCorrection(Id accountId) {
        try {
            if (accountId == null) {
                return new List<AccountAssetOption>();
            }

            List<AccountAssetOption> options = new List<AccountAssetOption>();
            for (Asset asset : [
                SELECT
                    Id,
                    Name,
                    SerialNumber,
                    ModelCalculated__c,
                    Department__c,
                    Product2.Name,
                    Product2.ProductLine__c
                FROM Asset
                WHERE AccountId = :accountId
                WITH USER_MODE
                ORDER BY Name ASC NULLS LAST, SerialNumber ASC NULLS LAST
            ]) {
                AccountAssetOption option = new AccountAssetOption();
                option.id = asset.Id;
                option.label = buildAccountAssetLabel(
                    asset.Name,
                    asset.Product2?.Name,
                    asset.ModelCalculated__c
                );
                option.serialNumber = asset.SerialNumber;
                option.model = asset.ModelCalculated__c;
                option.departmentId = asset.Department__c;
                option.productLine = asset.Product2?.ProductLine__c;
                options.add(option);
            }
            return options;
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw new AuraHandledException('Error retrieving account assets: ' + e.getMessage());
        }
    }

    /**
     * @description Returns active internal users for receiver selection.
     * @return Active internal user picklist options.
     */
    @AuraEnabled(cacheable=true)
    public static List<PicklistOption> getActiveInternalUsers() {
        try {
            List<PicklistOption> options = new List<PicklistOption>();
            for (User userRecord : [
                SELECT Id, Name
                FROM User
                WHERE IsActive = true
                AND UserType IN ('Standard', 'CsnOnly')
                WITH USER_MODE
                ORDER BY Name ASC
            ]) {
                PicklistOption option = new PicklistOption();
                option.label = userRecord.Name;
                option.value = userRecord.Id;
                options.add(option);
            }
            return options;
        } catch (Exception e) {
            throw new AuraHandledException('Error retrieving users: ' + e.getMessage());
        }
    }

    /**
     * @description Returns repair center locations for redirect selection.
     * @return Repair center location picklist options.
     */
    @AuraEnabled(cacheable=true)
    public static List<PicklistOption> getRepairCenterLocations() {
        try {
            List<PicklistOption> options = new List<PicklistOption>();
            for (Schema.Location locationRecord : [
                SELECT Id, Name
                FROM Location
                WHERE LocationType = :LOCATION_TYPE_REPAIR_CENTER
                WITH USER_MODE
                ORDER BY Name ASC
            ]) {
                PicklistOption option = new PicklistOption();
                option.label = locationRecord.Name;
                option.value = locationRecord.Id;
                options.add(option);
            }
            return options;
        } catch (Exception e) {
            throw new AuraHandledException('Error retrieving repair centers: ' + e.getMessage());
        }
    }

    /**
     * @description Links uploaded content documents to a work order.
     * @param workOrderId Work order Id to link photos to.
     * @param contentDocumentIds Content document Ids to link.
     */
    @AuraEnabled
    public static void linkPhotosToWorkOrder(Id workOrderId, List<Id> contentDocumentIds) {
        try {
            if (workOrderId == null || contentDocumentIds == null || contentDocumentIds.isEmpty()) {
                return;
            }

            List<ContentDocumentLink> links = new List<ContentDocumentLink>();
            for (Id contentDocumentId : contentDocumentIds) {
                if (contentDocumentId == null) {
                    continue;
                }
                ContentDocumentLink link = new ContentDocumentLink();
                link.ContentDocumentId = contentDocumentId;
                link.LinkedEntityId = workOrderId;
                link.ShareType = 'V';
                link.Visibility = 'AllUsers';
                links.add(link);
            }

            if (!links.isEmpty()) {
                executeInsertAsUser(
                    links,
                    'ReturnOrderReceivingController.linkPhotosToWorkOrder: content document links'
                );
            }
        } catch (DmlException e) {
            throw new AuraHandledException('Error linking photos to work order: ' + e.getDmlMessage(0));
        } catch (Exception e) {
            throw new AuraHandledException('Error linking photos to work order: ' + e.getMessage());
        }
    }

    /**
     * @description Redirects a line item or all open lines to a different repair center.
     * @param lineItemId Source return order line item Id.
     * @param repairCenterId Destination repair center location Id.
     * @param redirectAllOpenLines When true, redirects all open lines on the return order.
     * @return New return order Id and number after redirect.
     */
    @AuraEnabled
    public static RedirectActionResult redirectLineItem(
        Id lineItemId,
        Id repairCenterId,
        Boolean redirectAllOpenLines
    ) {
        try {
            if (lineItemId == null) {
                throw new AuraHandledException('Line item is required.');
            }
            if (repairCenterId == null) {
                throw new AuraHandledException('Repair center is required.');
            }

            ReturnOrderLineItem sourceLineItem = queryLineItemForRedirectClone(lineItemId);
            if (sourceLineItem.Status__c != STATUS_CREATED) {
                throw new AuraHandledException('Only line items with Created status can be redirected.');
            }

            ReturnOrder sourceReturnOrder = queryReturnOrderForRedirectClone(sourceLineItem.ReturnOrderId);
            if (repairCenterId == sourceReturnOrder.DestinationLocationId) {
                throw new AuraHandledException('Select a different repair center to redirect this line.');
            }

            if (redirectAllOpenLines == true) {
                return processBulkRedirect(sourceReturnOrder, repairCenterId);
            }

            ReturnOrder insertedReturnOrder = insertRedirectReturnOrder(sourceReturnOrder, repairCenterId);
            ReturnOrderLineItem newLineItem = cloneRedirectLineItem(
                sourceLineItem,
                insertedReturnOrder.Id,
                STATUS_CREATED,
                sourceLineItem.Id
            );
            executeInsertAsUser(
                Security.stripInaccessible(
                    AccessType.CREATABLE,
                    new List<ReturnOrderLineItem>{ newLineItem }
                ).getRecords(),
                'ReturnOrderReceivingController.redirectLineItem: redirected line item'
            );

            executeUpdateAsUser(
                Security.stripInaccessible(
                    AccessType.UPDATABLE,
                    new List<ReturnOrderLineItem>{
                        new ReturnOrderLineItem(
                            Id = sourceLineItem.Id,
                            Status__c = STATUS_REDIRECTED
                        )
                    }
                ).getRecords(),
                'ReturnOrderReceivingController.redirectLineItem: source line item status'
            );

            RedirectActionResult result = new RedirectActionResult();
            result.returnOrderId = insertedReturnOrder.Id;
            result.returnOrderNumber = insertedReturnOrder.ReturnOrderNumber;
            return result;
        } catch (AuraHandledException e) {
            throw e;
        } catch (DmlException e) {
            throw new AuraHandledException('Error redirecting line item: ' + e.getDmlMessage(0));
        } catch (Exception e) {
            throw new AuraHandledException(
                'Error redirecting line item: ' + e.getTypeName() + ': ' + e.getMessage()
            );
        }
    }

    /**
     * @description Performs bulk receive: creates work orders, updates lines, and handles customer care cases.
     * @param returnOrderId Return order Id to receive.
     * @param receiverId User Id of the receiver.
     * @param receivedDateTime Date and time items were received.
     * @param isContaminated When true, routes items through contaminated receive flow.
     * @param instrumentQuantityReceived Header quantity received for instrument return orders.
     * @param lineInputsJson JSON array of line receive inputs from the LWC.
     * @param contentDocumentIds Content document Ids to link to created work orders.
     * @return Bulk receive result with work order Ids and received status.
     */
    @AuraEnabled
    public static BulkReceiveResult receiveReturnOrder(
        Id returnOrderId,
        Id receiverId,
        Datetime receivedDateTime,
        Boolean isContaminated,
        Decimal instrumentQuantityReceived,
        String lineInputsJson,
        List<Id> contentDocumentIds
    ) {
        try {
            List<LineReceiveInput> lineInputs = parseLineInputsFromJson(lineInputsJson);
            validateBulkReceiveRequest(returnOrderId, receiverId, receivedDateTime, lineInputs);

            ReturnOrder returnOrder = queryReturnOrderForReceive(returnOrderId);
            String returnOrderType = resolveReturnOrderType(returnOrder.ReturnOrderType__c);
            Map<Id, ReturnOrderLineItem> lineItemsById = queryLineItemsForBulkReceive(
                returnOrderId,
                extractLineItemIds(lineInputs)
            );
            validateLineInputsResolved(lineInputs, lineItemsById, returnOrderType);
            validateAdHocSerializedLineInputs(lineInputs, returnOrderType);
            Map<Id, String> subStatusByLineItemId = buildSubStatusByLineItemId(
                lineInputs,
                lineItemsById,
                returnOrderType,
                isContaminated == true
            );
            applyLineCorrections(lineInputs, lineItemsById, returnOrderType);

            lineItemsById = queryLineItemsForBulkReceive(returnOrderId, extractLineItemIds(lineInputs));
            validateLineInputsResolved(lineInputs, lineItemsById, returnOrderType);

            BulkReceiveResult result;
            if (isContaminated == true) {
                result = processContaminatedBulkReceive(
                    returnOrder,
                    returnOrderType,
                    receiverId,
                    receivedDateTime,
                    lineInputs,
                    lineItemsById
                );
            } else if (returnOrderType == RO_TYPE_SERIALIZED) {
                result = processSerializedBulkReceive(
                    returnOrder,
                    receiverId,
                    receivedDateTime,
                    lineInputs,
                    lineItemsById,
                    subStatusByLineItemId
                );
            } else if (returnOrderType == RO_TYPE_INSTRUMENTS) {
                result = processInstrumentsBulkReceive(
                    returnOrder,
                    receiverId,
                    receivedDateTime,
                    instrumentQuantityReceived,
                    lineInputs,
                    lineItemsById,
                    subStatusByLineItemId
                );
            } else {
                result = processOtherBulkReceive(
                    returnOrder,
                    receiverId,
                    receivedDateTime,
                    lineInputs,
                    lineItemsById,
                    subStatusByLineItemId
                );
            }

            linkPhotos(result, contentDocumentIds);
            return result;
        } catch (AuraHandledException e) {
            throw e;
        } catch (DmlException e) {
            String dmlMessage = e.getNumDml() > 0 ? e.getDmlMessage(0) : e.getMessage();
            String dmlTargetId = e.getNumDml() > 0 ? String.valueOf(e.getDmlId(0)) : null;
            String detail = dmlMessage;
            if (String.isNotBlank(dmlTargetId) && dmlTargetId != 'null') {
                detail += ' (recordId=' + dmlTargetId + ')';
            }
            String message = 'Error receiving return order: ' + detail;
            AuraHandledException auraEx = new AuraHandledException(message);
            auraEx.setMessage(message);
            throw auraEx;
        } catch (Exception e) {
            String message =
                'Error receiving return order: ' + e.getTypeName() + ': ' + e.getMessage();
            AuraHandledException auraEx = new AuraHandledException(message);
            auraEx.setMessage(message);
            throw auraEx;
        }
    }

    private static BulkReceiveResult processContaminatedBulkReceive(
        ReturnOrder returnOrder,
        String returnOrderType,
        Id receiverId,
        Datetime receivedDateTime,
        List<LineReceiveInput> lineInputs,
        Map<Id, ReturnOrderLineItem> lineItemsById
    ) {
        markLinesReceived(lineInputs, lineItemsById, receiverId, receivedDateTime, returnOrderType);
        updateReturnOrderStatusIfComplete(returnOrder.Id);

        Id recordTypeId = resolveRecordTypeId(returnOrderType);
        String parentSubject = 'Contaminated Return Order ' + returnOrder.ReturnOrderNumber;

        if (returnOrderType == RO_TYPE_SERIALIZED) {
            return createSerializedWorkOrders(
                returnOrder,
                receiverId,
                recordTypeId,
                WO_SUB_STATUS_RESOLVED,
                lineInputs,
                lineItemsById,
                new Map<Id, String>(),
                parentSubject,
                true
            );
        }

        if (returnOrderType == RO_TYPE_INSTRUMENTS) {
            Decimal summarizedQuantityReceived = resolveInstrumentHeaderQuantityReceived(
                null,
                lineInputs,
                lineItemsById
            );
            syncReturnOrderInstrumentQuantityReceived(
                returnOrder.Id,
                summarizedQuantityReceived
            );
            return createSingleWorkOrderReceive(
                returnOrder,
                receiverId,
                receivedDateTime,
                recordTypeId,
                WO_SUB_STATUS_CONTAMINATED,
                'Contaminated Instrument Return Order ' + returnOrder.ReturnOrderNumber,
                summarizedQuantityReceived,
                lineInputs,
                lineItemsById,
                true
            );
        }

        return createOtherWorkOrderReceive(
            returnOrder,
            receiverId,
            recordTypeId,
            WO_SUB_STATUS_CONTAMINATED,
            parentSubject,
            lineInputs,
            lineItemsById,
            true
        );
    }

    private static BulkReceiveResult processSerializedBulkReceive(
        ReturnOrder returnOrder,
        Id receiverId,
        Datetime receivedDateTime,
        List<LineReceiveInput> lineInputs,
        Map<Id, ReturnOrderLineItem> lineItemsById,
        Map<Id, String> subStatusByLineItemId
    ) {
        markLinesReceived(lineInputs, lineItemsById, receiverId, receivedDateTime, RO_TYPE_SERIALIZED);
        updateReturnOrderStatusIfComplete(returnOrder.Id);

        Id recordTypeId = getRepairCenterDevicesRecordTypeId();
        return createSerializedWorkOrders(
            returnOrder,
            receiverId,
            recordTypeId,
            WO_SUB_STATUS_RESOLVED,
            lineInputs,
            lineItemsById,
            subStatusByLineItemId,
            'Return Order ' + returnOrder.ReturnOrderNumber,
            false
        );
    }

    private static BulkReceiveResult processInstrumentsBulkReceive(
        ReturnOrder returnOrder,
        Id receiverId,
        Datetime receivedDateTime,
        Decimal instrumentQuantityReceived,
        List<LineReceiveInput> lineInputs,
        Map<Id, ReturnOrderLineItem> lineItemsById,
        Map<Id, String> subStatusByLineItemId
    ) {
        markLinesReceived(lineInputs, lineItemsById, receiverId, receivedDateTime, RO_TYPE_INSTRUMENTS);

        Decimal summarizedQuantityReceived = resolveInstrumentHeaderQuantityReceived(
            instrumentQuantityReceived,
            lineInputs,
            lineItemsById
        );

        syncReturnOrderInstrumentQuantityReceived(
            returnOrder.Id,
            summarizedQuantityReceived
        );
        updateReturnOrderStatusIfComplete(returnOrder.Id);

        String workOrderSubStatus = resolveInstrumentWorkOrderSubStatus(
            lineInputs,
            lineItemsById
        );
        Id recordTypeId = getRepairCenterInstrumentsRecordTypeId();

        return createSingleWorkOrderReceive(
            returnOrder,
            receiverId,
            receivedDateTime,
            recordTypeId,
            workOrderSubStatus,
            'Instrument Return Order ' + returnOrder.ReturnOrderNumber,
            summarizedQuantityReceived,
            lineInputs,
            lineItemsById,
            false
        );
    }

    private static BulkReceiveResult processOtherBulkReceive(
        ReturnOrder returnOrder,
        Id receiverId,
        Datetime receivedDateTime,
        List<LineReceiveInput> lineInputs,
        Map<Id, ReturnOrderLineItem> lineItemsById,
        Map<Id, String> subStatusByLineItemId
    ) {
        markLinesReceived(lineInputs, lineItemsById, receiverId, receivedDateTime, RO_TYPE_OTHER);
        updateReturnOrderStatusIfComplete(returnOrder.Id);

        String workOrderSubStatus = resolveBulkWorkOrderSubStatus(lineInputs, subStatusByLineItemId);
        Id recordTypeId = getRepairCenterVendorRecordTypeId();

        return createOtherWorkOrderReceive(
            returnOrder,
            receiverId,
            recordTypeId,
            workOrderSubStatus,
            'Other Return Order ' + returnOrder.ReturnOrderNumber,
            lineInputs,
            lineItemsById,
            false
        );
    }

    private static BulkReceiveResult createSerializedWorkOrders(
        ReturnOrder returnOrder,
        Id receiverId,
        Id recordTypeId,
        String defaultSubStatus,
        List<LineReceiveInput> lineInputs,
        Map<Id, ReturnOrderLineItem> lineItemsById,
        Map<Id, String> subStatusByLineItemId,
        String parentSubject,
        Boolean isContaminated
    ) {
        ReturnOrderLineItem firstLineItem = resolveFirstLinkedLineItem(lineInputs, lineItemsById);
        WorkOrder parentWorkOrder = buildParentWorkOrder(
            returnOrder,
            receiverId,
            recordTypeId,
            defaultSubStatus,
            parentSubject,
            firstLineItem
        );
        parentWorkOrder.Contaminated__c = isContaminated;
        List<WorkOrder> insertableParentWorkOrders = Security.stripInaccessible(
            AccessType.CREATABLE,
            new List<WorkOrder>{ parentWorkOrder }
        ).getRecords();
        if (insertableParentWorkOrders.isEmpty()) {
            throw new AuraHandledException(
                'Unable to create parent work order due to field access restrictions.'
            );
        }
        insertWorkOrdersAsUser(insertableParentWorkOrders);
        Id parentWorkOrderId = insertableParentWorkOrders[0].Id;
        ensureWorkOrderReturnOrderReference(parentWorkOrderId, returnOrder.Id);
        linkReturnOrderToWorkOrder(returnOrder.Id, parentWorkOrderId, false);

        List<LineReceiveInput> childLineInputsInOrder = new List<LineReceiveInput>();
        for (LineReceiveInput lineInput : lineInputs) {
            if (isAdHocSerializedLineInput(lineInput)) {
                childLineInputsInOrder.add(lineInput);
                continue;
            }
            if (lineItemsById.get(resolveInputLineItemId(lineInput)) == null) {
                continue;
            }
            childLineInputsInOrder.add(lineInput);
        }
        if (childLineInputsInOrder.isEmpty()) {
            throw new AuraHandledException(
                'Unable to create child work orders for the selected line items.'
            );
        }

        // Parent plus the first child stay in this transaction. Each additional
        // child gets its own queued transaction so Work Order after-save
        // automation does not exceed the SOQL limit.
        Integer firstAdHocLineNumber = isAdHocSerializedLineInput(childLineInputsInOrder[0])
            ? 1
            : 0;
        Id firstChildId = insertOneSerializedChild(
            returnOrder,
            parentWorkOrderId,
            receiverId,
            recordTypeId,
            defaultSubStatus,
            childLineInputsInOrder[0],
            lineItemsById,
            subStatusByLineItemId,
            isContaminated,
            firstAdHocLineNumber
        );
        List<String> workOrderIds = new List<String>{ parentWorkOrderId, firstChildId };

        if (childLineInputsInOrder.size() > 1) {
            List<LineReceiveInput> deferredLineInputs = new List<LineReceiveInput>();
            for (Integer index = 1; index < childLineInputsInOrder.size(); index++) {
                deferredLineInputs.add(childLineInputsInOrder[index]);
            }
            Integer nextAdHocLineNumber = firstAdHocLineNumber == 1 ? 2 : 1;
            System.enqueueJob(
                new SerializedChildWorkOrderQueueable(
                    returnOrder.Id,
                    parentWorkOrderId,
                    receiverId,
                    recordTypeId,
                    defaultSubStatus,
                    JSON.serialize(deferredLineInputs),
                    serializeSubStatusByLineItemId(subStatusByLineItemId),
                    isContaminated == true,
                    nextAdHocLineNumber
                )
            );
        }

        BulkReceiveResult result = new BulkReceiveResult();
        result.primaryWorkOrderId = parentWorkOrderId;
        result.navigationWorkOrderId = parentWorkOrderId;
        result.workOrderIds = workOrderIds;
        result.returnOrderReceived = isReturnOrderFullyReceived(returnOrder.Id);
        result.expectedSerializedChildCount = childLineInputsInOrder.size();
        return result;
    }

    /**
     * @description Counts child Work Orders under a serialized parent so the receiving
     * page can wait until queued children exist before opening the parent.
     * @param parentWorkOrderId Parent Work Order created during receive.
     * @return Number of child Work Orders currently under that parent.
     */
    @AuraEnabled
    public static Integer getSerializedChildWorkOrderCount(Id parentWorkOrderId) {
        if (parentWorkOrderId == null) {
            return 0;
        }
        return [
            SELECT COUNT()
            FROM WorkOrder
            WHERE ParentWorkOrderId = :parentWorkOrderId
            WITH USER_MODE
        ];
    }

    /**
     * Creates one deferred serialized child Work Order per execution, then chains
     * the next child so each device gets a fresh SOQL limit.
     */
    public class SerializedChildWorkOrderQueueable implements Queueable {
        private Id returnOrderId;
        private Id parentWorkOrderId;
        private Id receiverId;
        private Id recordTypeId;
        private String defaultSubStatus;
        private String lineInputsJson;
        private String subStatusByLineItemIdJson;
        private Boolean isContaminated;
        private Integer adHocLineNumber;

        public SerializedChildWorkOrderQueueable(
            Id returnOrderId,
            Id parentWorkOrderId,
            Id receiverId,
            Id recordTypeId,
            String defaultSubStatus,
            String lineInputsJson,
            String subStatusByLineItemIdJson,
            Boolean isContaminated,
            Integer adHocLineNumber
        ) {
            this.returnOrderId = returnOrderId;
            this.parentWorkOrderId = parentWorkOrderId;
            this.receiverId = receiverId;
            this.recordTypeId = recordTypeId;
            this.defaultSubStatus = defaultSubStatus;
            this.lineInputsJson = lineInputsJson;
            this.subStatusByLineItemIdJson = subStatusByLineItemIdJson;
            this.isContaminated = isContaminated == true;
            this.adHocLineNumber = adHocLineNumber == null || adHocLineNumber < 1
                ? 1
                : adHocLineNumber;
        }

        public void execute(QueueableContext context) {
            try {
                List<LineReceiveInput> remainingLineInputs = deserializeLineInputs(lineInputsJson);
                if (remainingLineInputs.isEmpty()) {
                    return;
                }

                LineReceiveInput nextLineInput = remainingLineInputs.remove(0);
                ReturnOrder returnOrder = queryReturnOrderForReceive(returnOrderId);
                Set<Id> lineItemIds = new Set<Id>();
                Id lineItemId = resolveInputLineItemId(nextLineInput);
                if (lineItemId != null) {
                    lineItemIds.add(lineItemId);
                }
                Map<Id, ReturnOrderLineItem> lineItemsById = lineItemIds.isEmpty()
                    ? new Map<Id, ReturnOrderLineItem>()
                    : queryLineItemsForBulkReceive(returnOrderId, lineItemIds);

                insertOneSerializedChild(
                    returnOrder,
                    parentWorkOrderId,
                    receiverId,
                    recordTypeId,
                    defaultSubStatus,
                    nextLineInput,
                    lineItemsById,
                    deserializeSubStatusByLineItemId(subStatusByLineItemIdJson),
                    isContaminated,
                    adHocLineNumber
                );

                if (remainingLineInputs.isEmpty()) {
                    return;
                }

                Integer nextAdHocLineNumber = isAdHocSerializedLineInput(nextLineInput)
                    ? adHocLineNumber + 1
                    : adHocLineNumber;
                System.enqueueJob(
                    new SerializedChildWorkOrderQueueable(
                        returnOrderId,
                        parentWorkOrderId,
                        receiverId,
                        recordTypeId,
                        defaultSubStatus,
                        JSON.serialize(remainingLineInputs),
                        subStatusByLineItemIdJson,
                        isContaminated,
                        nextAdHocLineNumber
                    )
                );
            } catch (Exception e) {
                Logger.newEntry(
                    LoggingLevel.ERROR,
                    'SerializedChildWorkOrderQueueable failed for Return Order ' + returnOrderId
                ).setExceptionDetails(e);
                throw e;
            } finally {
                saveDmlLogs();
            }
        }
    }

    private static Id insertOneSerializedChild(
        ReturnOrder returnOrder,
        Id parentWorkOrderId,
        Id receiverId,
        Id recordTypeId,
        String defaultSubStatus,
        LineReceiveInput lineInput,
        Map<Id, ReturnOrderLineItem> lineItemsById,
        Map<Id, String> subStatusByLineItemId,
        Boolean isContaminated,
        Integer adHocLineNumber
    ) {
        WorkOrder childWorkOrder;
        ReturnOrderLineItem lineItem = null;
        LineReceiveInput productLineInput = null;
        if (isAdHocSerializedLineInput(lineInput)) {
            childWorkOrder = buildChildWorkOrderFromAdHocInput(
                parentWorkOrderId,
                returnOrder,
                lineInput,
                receiverId,
                recordTypeId,
                resolveAdHocSerializedSubStatus(lineInput, isContaminated),
                'Ad Hoc Item ' + adHocLineNumber,
                isContaminated
            );
            productLineInput = lineInput;
        } else {
            lineItem = lineItemsById == null
                ? null
                : lineItemsById.get(resolveInputLineItemId(lineInput));
            if (lineItem == null) {
                throw new AuraHandledException(
                    'Unable to create child work orders for the selected line items.'
                );
            }
            String childSubStatus = isContaminated == true
                ? WO_SUB_STATUS_CONTAMINATED
                : resolveSerializedChildSubStatus(lineInput, subStatusByLineItemId);
            childWorkOrder = buildChildWorkOrder(
                parentWorkOrderId,
                returnOrder,
                lineItem,
                receiverId,
                recordTypeId,
                childSubStatus,
                'Line ' + lineItem.ReturnOrderLineItemNumber
            );
            childWorkOrder.Contaminated__c = isContaminated == true;
        }

        List<WorkOrder> insertableChildWorkOrders = Security.stripInaccessible(
            AccessType.CREATABLE,
            new List<WorkOrder>{ childWorkOrder }
        ).getRecords();
        if (insertableChildWorkOrders.isEmpty()) {
            throw new AuraHandledException(
                'Unable to create work order due to field access restrictions.'
            );
        }
        insertWorkOrdersAsUser(insertableChildWorkOrders);
        WorkOrder insertedChild = insertableChildWorkOrders[0];
        insertSerializedProductServicedWorkOrderLineItem(
            insertedChild,
            parentWorkOrderId,
            returnOrder.Id,
            lineItem,
            productLineInput
        );
        insertAccessoryWorkOrderLineItems(insertedChild, null, lineInput.accessories);
        syncReturnOrderWorkOrderCount(returnOrder.Id);
        return insertedChild.Id;
    }

    private static String serializeSubStatusByLineItemId(Map<Id, String> subStatusByLineItemId) {
        Map<String, String> subStatusByLineItemIdString = new Map<String, String>();
        if (subStatusByLineItemId != null) {
            for (Id lineItemId : subStatusByLineItemId.keySet()) {
                subStatusByLineItemIdString.put(
                    String.valueOf(lineItemId),
                    subStatusByLineItemId.get(lineItemId)
                );
            }
        }
        return JSON.serialize(subStatusByLineItemIdString);
    }

    private static Map<Id, String> deserializeSubStatusByLineItemId(String subStatusJson) {
        Map<Id, String> subStatusByLineItemId = new Map<Id, String>();
        if (String.isBlank(subStatusJson) || subStatusJson == 'null' || subStatusJson == '{}') {
            return subStatusByLineItemId;
        }
        Map<String, String> parsed = (Map<String, String>) JSON.deserialize(
            subStatusJson,
            Map<String, String>.class
        );
        if (parsed == null) {
            return subStatusByLineItemId;
        }
        for (String lineItemIdValue : parsed.keySet()) {
            subStatusByLineItemId.put(Id.valueOf(lineItemIdValue), parsed.get(lineItemIdValue));
        }
        return subStatusByLineItemId;
    }

    private static List<LineReceiveInput> deserializeLineInputs(String lineInputsJson) {
        if (String.isBlank(lineInputsJson) || lineInputsJson == 'null' || lineInputsJson == '[]') {
            return new List<LineReceiveInput>();
        }
        List<LineReceiveInput> parsed = (List<LineReceiveInput>) JSON.deserialize(
            lineInputsJson,
            List<LineReceiveInput>.class
        );
        return parsed == null ? new List<LineReceiveInput>() : parsed;
    }

    private static BulkReceiveResult createSingleWorkOrderReceive(
        ReturnOrder returnOrder,
        Id receiverId,
        Datetime receivedDateTime,
        Id recordTypeId,
        String subStatus,
        String subject,
        Decimal quantityReceived,
        List<LineReceiveInput> lineInputs,
        Map<Id, ReturnOrderLineItem> lineItemsById,
        Boolean isContaminated
    ) {
        ReturnOrderLineItem firstLineItem = lineItemsById.get(
            resolveInputLineItemId(lineInputs[0])
        );
        WorkOrder workOrder = buildExtendedWorkOrder(
            returnOrder,
            firstLineItem,
            receiverId,
            recordTypeId,
            subStatus,
            subject,
            RO_TYPE_INSTRUMENTS
        );
        applyWorkOrderFieldMappings(
            workOrder,
            firstLineItem,
            quantityReceived,
            RO_TYPE_INSTRUMENTS
        );
        workOrder.Contaminated__c = isContaminated;

        List<WorkOrder> insertableWorkOrders = Security.stripInaccessible(
            AccessType.CREATABLE,
            new List<WorkOrder>{ workOrder }
        ).getRecords();
        if (insertableWorkOrders.isEmpty()) {
            throw new AuraHandledException(
                'Unable to create work order due to field access restrictions.'
            );
        }
        insertWorkOrdersAsUser(insertableWorkOrders);
        Id workOrderId = insertableWorkOrders[0].Id;
        linkReturnOrderToWorkOrder(returnOrder.Id, workOrderId, false);

        syncReturnOrderWorkOrderCount(returnOrder.Id);

        BulkReceiveResult result = new BulkReceiveResult();
        result.primaryWorkOrderId = workOrderId;
        result.navigationWorkOrderId = workOrderId;
        result.workOrderIds = new List<String>{ workOrderId };
        result.returnOrderReceived = isReturnOrderFullyReceived(returnOrder.Id);
        return result;
    }

    private static BulkReceiveResult createOtherWorkOrderReceive(
        ReturnOrder returnOrder,
        Id receiverId,
        Id recordTypeId,
        String subStatus,
        String subject,
        List<LineReceiveInput> lineInputs,
        Map<Id, ReturnOrderLineItem> lineItemsById,
        Boolean isContaminated
    ) {
        ReturnOrderLineItem firstLineItem = lineItemsById.get(
            resolveInputLineItemId(lineInputs[0])
        );
        WorkOrder workOrder = buildExtendedWorkOrder(
            returnOrder,
            firstLineItem,
            receiverId,
            recordTypeId,
            subStatus,
            subject,
            RO_TYPE_OTHER
        );
        applyWorkOrderFieldMappings(
            workOrder,
            firstLineItem,
            resolveLineQuantityReceived(firstLineItem, RO_TYPE_OTHER),
            RO_TYPE_OTHER
        );
        workOrder.Contaminated__c = isContaminated;

        List<WorkOrder> insertableWorkOrders = Security.stripInaccessible(
            AccessType.CREATABLE,
            new List<WorkOrder>{ workOrder }
        ).getRecords();
        if (insertableWorkOrders.isEmpty()) {
            throw new AuraHandledException(
                'Unable to create work order due to field access restrictions.'
            );
        }
        insertWorkOrdersAsUser(insertableWorkOrders);
        Id workOrderId = insertableWorkOrders[0].Id;
        linkReturnOrderToWorkOrder(returnOrder.Id, workOrderId, false);
        ensureWorkOrderReturnOrderReference(workOrderId, returnOrder.Id);

        List<String> workOrderIds = new List<String>{ workOrderId };
        for (LineReceiveInput lineInput : lineInputs) {
            ReturnOrderLineItem lineItem = lineItemsById.get(resolveInputLineItemId(lineInput));
            if (lineItem == null) {
                continue;
            }

            WorkOrderLineItem workOrderLineItem = buildOtherWorkOrderLineItem(
                insertableWorkOrders[0],
                lineItem,
                lineInput
            );
            insertCreatableWorkOrderLineItems(
                new List<WorkOrderLineItem>{ workOrderLineItem },
                workOrderId,
                'Unable to create work order line items due to field access restrictions.'
            );
        }

        syncReturnOrderWorkOrderCount(returnOrder.Id);

        BulkReceiveResult result = new BulkReceiveResult();
        result.primaryWorkOrderId = workOrderId;
        result.navigationWorkOrderId = workOrderId;
        result.workOrderIds = workOrderIds;
        result.returnOrderReceived = isReturnOrderFullyReceived(returnOrder.Id);
        return result;
    }

    private static WorkOrderLineItem buildOtherWorkOrderLineItem(
        WorkOrder workOrder,
        ReturnOrderLineItem lineItem,
        LineReceiveInput lineInput
    ) {
        WorkOrderLineItem workOrderLineItem = new WorkOrderLineItem();
        workOrderLineItem.WorkOrderId = workOrder.Id;
        workOrderLineItem.TopLevelWorkOrder__c = workOrder.Id;
        workOrderLineItem.RecordTypeId = getProductServicedWorkOrderLineItemRecordTypeId();
        workOrderLineItem.LineType__c = WOLI_LINE_TYPE_PRODUCT_SERVICED;
        workOrderLineItem.Subject = workOrder.Subject;
        workOrderLineItem.AssetId = lineItem.AssetId;
        workOrderLineItem.Model__c = lineItem.Model__c;
        workOrderLineItem.ModRequest__c = lineItem.ModRequest__c == true;
        workOrderLineItem.SerialNumber__c = resolveOtherScreenSerialNumber(lineInput, lineItem);
        workOrderLineItem.TrayName__c = resolveOtherScreenTrayName(lineInput, lineItem);

        Decimal quantity = resolveOtherScreenQuantity(lineInput, lineItem);
        if (quantity != null) {
            workOrderLineItem.Quantity = quantity;
        }

        Id product2Id = resolveOtherScreenProductId(lineInput, lineItem);
        if (product2Id != null) {
            Product2 productDetails = queryProductDetailsForWorkOrderLineItem(product2Id);
            Id pricebookId = workOrder.Pricebook2Id != null
                ? workOrder.Pricebook2Id
                : resolveDefaultPricebookId();
            Id pricebookEntryId = resolvePricebookEntryId(
                pricebookId,
                product2Id,
                workOrder.CurrencyIsoCode
            );
            if (pricebookEntryId != null) {
                workOrderLineItem.PricebookEntryId = pricebookEntryId;
            } else {
                workOrderLineItem.Product2Id = product2Id;
            }
            if (productDetails != null) {
                workOrderLineItem.ProductCodeWoli__c = productDetails.ProductCode;
                workOrderLineItem.ProductDescription__c = productDetails.Description;
            }
        }

        if (String.isNotBlank(lineItem.ReportedProblem__c)) {
            workOrderLineItem.Description = lineItem.ReportedProblem__c;
        }

        applyOtherReturnOrderLineItemFieldsToWorkOrderLineItem(workOrderLineItem, lineItem);

        return workOrderLineItem;
    }

    private static void applyOtherReturnOrderLineItemFieldsToWorkOrderLineItem(
        WorkOrderLineItem workOrderLineItem,
        ReturnOrderLineItem lineItem
    ) {
        if (workOrderLineItem == null || lineItem == null) {
            return;
        }

        workOrderLineItem.ReturnOrderLineItemId = lineItem.Id;
        if (Schema.SObjectType.WorkOrderLineItem.fields.getMap().containsKey('Contact__c')
            && Schema.SObjectType.WorkOrderLineItem.fields.Contact__c.isCreateable()) {
            workOrderLineItem.Contact__c = lineItem.Contact__c;
        }
        if (Schema.SObjectType.WorkOrderLineItem.fields.CustomerPO__c.isCreateable()) {
            workOrderLineItem.CustomerPO__c = lineItem.CustomerPO__c;
        }
        if (Schema.SObjectType.WorkOrderLineItem.fields.CustomerReference__c.isCreateable()) {
            workOrderLineItem.CustomerReference__c = lineItem.CustomerReference__c;
        }
        if (Schema.SObjectType.WorkOrderLineItem.fields.Department__c.isCreateable()) {
            workOrderLineItem.Department__c = lineItem.Department__c;
        }
        if (Schema.SObjectType.WorkOrderLineItem.fields.RepairWarranty__c.isCreateable()) {
            workOrderLineItem.RepairWarranty__c = lineItem.RepairWarranty__c;
        }
        if (Schema.SObjectType.WorkOrderLineItem.fields.WarrantyNotes__c.isCreateable()) {
            workOrderLineItem.WarrantyNotes__c = lineItem.WarrantyNotes__c;
        }
        if (Schema.SObjectType.WorkOrderLineItem.fields.EstimateRequired__c.isCreateable()) {
            workOrderLineItem.EstimateRequired__c = lineItem.EstimateRequired__c;
        }
        if (Schema.SObjectType.WorkOrderLineItem.fields.EstimateContact__c.isCreateable()) {
            workOrderLineItem.EstimateContact__c = lineItem.EstimateContact__c;
        }
        if (Schema.SObjectType.WorkOrderLineItem.fields.PreviousReturnOrder__c.isCreateable()) {
            workOrderLineItem.PreviousReturnOrder__c = lineItem.PreviousReturnOrder__c;
        }
    }

    private static void insertAccessoryWorkOrderLineItems(
        WorkOrder childWorkOrder,
        Id productServicedWorkOrderLineItemId,
        List<AccessoryInput> accessories
    ) {
        if (
            childWorkOrder == null ||
            childWorkOrder.Id == null ||
            accessories == null ||
            accessories.isEmpty()
        ) {
            return;
        }

        Id parentWorkOrderLineItemId = productServicedWorkOrderLineItemId;
        if (parentWorkOrderLineItemId == null) {
            parentWorkOrderLineItemId = resolveProductServicedWorkOrderLineItemId(
                childWorkOrder.Id,
                childWorkOrder.AssetId
            );
        }

        Product2 productDetails = queryProductDetailsForWorkOrderLineItem(childWorkOrder.Product__c);

        List<WorkOrderLineItem> accessoryLineItems = new List<WorkOrderLineItem>();
        for (AccessoryInput accessory : accessories) {
            WorkOrderLineItem accessoryLineItem = buildAccessoryWorkOrderLineItem(
                childWorkOrder.Id,
                parentWorkOrderLineItemId,
                childWorkOrder.Product__c,
                productDetails,
                accessory
            );
            if (accessoryLineItem != null) {
                accessoryLineItems.add(accessoryLineItem);
            }
        }

        if (accessoryLineItems.isEmpty()) {
            return;
        }

        insertCreatableWorkOrderLineItems(
            accessoryLineItems,
            childWorkOrder.Id,
            'Unable to create accessory work order line items due to field access restrictions. Confirm Work Order Line Item create access and accessory field permissions.'
        );
    }

    private static void insertCreatableWorkOrderLineItems(
        List<WorkOrderLineItem> lineItems,
        Id expectedWorkOrderId,
        String accessErrorMessage
    ) {
        if (lineItems == null || lineItems.isEmpty()) {
            return;
        }

        Map<Integer, Id> returnOrderLineItemIdsByIndex = new Map<Integer, Id>();
        for (Integer index = 0; index < lineItems.size(); index++) {
            if (lineItems[index].ReturnOrderLineItemId != null) {
                returnOrderLineItemIdsByIndex.put(
                    index,
                    lineItems[index].ReturnOrderLineItemId
                );
            }
        }

        prepareWorkOrderLineItemsForInsert(lineItems, expectedWorkOrderId);

        List<WorkOrderLineItem> insertableLineItems = Security.stripInaccessible(
            AccessType.CREATABLE,
            lineItems
        ).getRecords();
        if (insertableLineItems.isEmpty()) {
            throw new AuraHandledException(accessErrorMessage);
        }

        applyExpectedWorkOrderLineItemWorkOrder(insertableLineItems, expectedWorkOrderId);

        executeInsertAsUser(
            insertableLineItems,
            'ReturnOrderReceivingController.insertCreatableWorkOrderLineItems: work order line items'
        );
        correctWorkOrderLineItemWorkOrderAssignments(insertableLineItems, expectedWorkOrderId);
        syncReturnOrderLineItemLinksAfterInsert(
            insertableLineItems,
            returnOrderLineItemIdsByIndex
        );
    }

    private static void syncReturnOrderLineItemLinksAfterInsert(
        List<WorkOrderLineItem> insertedLineItems,
        Map<Integer, Id> returnOrderLineItemIdsByIndex
    ) {
        if (
            insertedLineItems == null ||
            insertedLineItems.isEmpty() ||
            returnOrderLineItemIdsByIndex == null ||
            returnOrderLineItemIdsByIndex.isEmpty()
        ) {
            return;
        }

        List<WorkOrderLineItem> lineItemsToUpdate = new List<WorkOrderLineItem>();
        for (Integer index = 0; index < insertedLineItems.size(); index++) {
            Id returnOrderLineItemId = returnOrderLineItemIdsByIndex.get(index);
            WorkOrderLineItem insertedLineItem = insertedLineItems[index];
            if (
                returnOrderLineItemId == null ||
                insertedLineItem == null ||
                insertedLineItem.Id == null ||
                insertedLineItem.ReturnOrderLineItemId == returnOrderLineItemId
            ) {
                continue;
            }

            lineItemsToUpdate.add(
                new WorkOrderLineItem(
                    Id = insertedLineItem.Id,
                    ReturnOrderLineItemId = returnOrderLineItemId
                )
            );
        }

        if (lineItemsToUpdate.isEmpty()) {
            return;
        }

        executeUpdateAsUser(
            Security.stripInaccessible(
                AccessType.UPDATABLE,
                lineItemsToUpdate
            ).getRecords(),
            'ReturnOrderReceivingController.syncReturnOrderLineItemLinksAfterInsert: work order line items'
        );
    }

    private static void prepareWorkOrderLineItemsForInsert(
        List<WorkOrderLineItem> lineItems,
        Id expectedWorkOrderId
    ) {
        applyExpectedWorkOrderLineItemWorkOrder(lineItems, expectedWorkOrderId);
    }

    private static void applyExpectedWorkOrderLineItemWorkOrder(
        List<WorkOrderLineItem> lineItems,
        Id expectedWorkOrderId
    ) {
        if (lineItems == null || lineItems.isEmpty()) {
            return;
        }

        for (WorkOrderLineItem lineItem : lineItems) {
            if (expectedWorkOrderId != null) {
                lineItem.WorkOrderId = expectedWorkOrderId;
            }
            lineItem.ReturnOrderLineItemId = null;
        }
    }

    private static void correctWorkOrderLineItemWorkOrderAssignments(
        List<WorkOrderLineItem> insertedLineItems,
        Id expectedWorkOrderId
    ) {
        if (expectedWorkOrderId == null || insertedLineItems == null || insertedLineItems.isEmpty()) {
            return;
        }

        Set<Id> insertedLineItemIds = new Set<Id>();
        for (WorkOrderLineItem lineItem : insertedLineItems) {
            if (lineItem.Id != null) {
                insertedLineItemIds.add(lineItem.Id);
            }
        }
        if (insertedLineItemIds.isEmpty()) {
            return;
        }

        List<WorkOrderLineItem> lineItemsToCorrect = new List<WorkOrderLineItem>();
        for (WorkOrderLineItem lineItem : [
            SELECT Id, WorkOrderId
            FROM WorkOrderLineItem
            WHERE Id IN :insertedLineItemIds
            WITH USER_MODE
        ]) {
            if (lineItem.WorkOrderId != expectedWorkOrderId) {
                lineItemsToCorrect.add(
                    new WorkOrderLineItem(
                        Id = lineItem.Id,
                        WorkOrderId = expectedWorkOrderId,
                        ReturnOrderLineItemId = null
                    )
                );
            }
        }

        if (lineItemsToCorrect.isEmpty()) {
            return;
        }

        List<WorkOrderLineItem> updatableLineItems = Security.stripInaccessible(
            AccessType.UPDATABLE,
            lineItemsToCorrect
        ).getRecords();
        if (updatableLineItems.isEmpty()) {
            throw new AuraHandledException(
                'Work order line items were created on the wrong work order and could not be reassigned due to field access restrictions.'
            );
        }

        applyExpectedWorkOrderLineItemWorkOrder(updatableLineItems, expectedWorkOrderId);
        executeUpdateAsUser(
            updatableLineItems,
            'ReturnOrderReceivingController.correctWorkOrderLineItemWorkOrderAssignments: work order line items'
        );
    }

    private static WorkOrderLineItem buildAccessoryWorkOrderLineItem(
        Id workOrderId,
        Id parentWorkOrderLineItemId,
        Id product2Id,
        Product2 productDetails,
        AccessoryInput accessory
    ) {
        if (
            workOrderId == null ||
            accessory == null ||
            String.isBlank(accessory.accessoryType) ||
            String.isBlank(accessory.storageLocation)
        ) {
            return null;
        }

        WorkOrderLineItem workOrderLineItem = new WorkOrderLineItem();
        workOrderLineItem.WorkOrderId = workOrderId;
        workOrderLineItem.RecordTypeId = getProductServicedWorkOrderLineItemRecordTypeId();
        workOrderLineItem.LineType__c = WOLI_LINE_TYPE_ACCESSORY;
        if (parentWorkOrderLineItemId != null) {
            workOrderLineItem.ParentWorkOrderLineItemId = parentWorkOrderLineItemId;
        }
        if (product2Id != null) {
            workOrderLineItem.Item__c = product2Id;
        }
        if (productDetails != null) {
            workOrderLineItem.ItemCode__c = productDetails.ProductCode;
            workOrderLineItem.ItemDescription__c = productDetails.Description;
        }
        workOrderLineItem.IsAccessory__c = true;
        workOrderLineItem.AccessoryType__c = accessory.accessoryType.trim();
        if (String.isNotBlank(accessory.condition)) {
            workOrderLineItem.Condition__c = accessory.condition.trim();
        }
        workOrderLineItem.StorageLocation__c = accessory.storageLocation.trim();

        Decimal quantity = accessory.quantity != null && accessory.quantity > 0
            ? accessory.quantity
            : 1;
        workOrderLineItem.UnitQty__c = quantity;
        return workOrderLineItem;
    }

    private static Decimal resolveOtherScreenQuantity(
        LineReceiveInput lineInput,
        ReturnOrderLineItem lineItem
    ) {
        if (lineInput != null && lineInput.quantityReturned != null) {
            return lineInput.quantityReturned;
        }
        if (lineInput != null && lineInput.quantityReceived != null) {
            return lineInput.quantityReceived;
        }
        return lineItem.QuantityReturned;
    }

    private static Id resolveOtherScreenProductId(
        LineReceiveInput lineInput,
        ReturnOrderLineItem lineItem
    ) {
        if (lineInput != null && lineInput.productId != null) {
            return lineInput.productId;
        }
        return lineItem.Product2Id;
    }

    private static String resolveOtherScreenTrayName(
        LineReceiveInput lineInput,
        ReturnOrderLineItem lineItem
    ) {
        if (lineInput != null && String.isNotBlank(lineInput.hospitalTrayName)) {
            return lineInput.hospitalTrayName.trim();
        }
        return lineItem.HospitalReferencedTrayName__c;
    }

    private static String resolveOtherScreenSerialNumber(
        LineReceiveInput lineInput,
        ReturnOrderLineItem lineItem
    ) {
        if (lineInput != null && String.isNotBlank(lineInput.serialNumber)) {
            return lineInput.serialNumber.trim();
        }
        return resolveLineItemSerialNumber(lineItem);
    }

    private static void applyWorkOrderSubStatus(WorkOrder workOrder, String subStatus) {
        if (workOrder == null) {
            return;
        }

        workOrder.SubStatus__c = subStatus;
        if (subStatus == WO_SUB_STATUS_MOD_HOLD) {
            workOrder.ModRequest__c = true;
        }
    }

    @TestVisible
    private static void resetRepairCenterDefaultsCacheForTest() {
        cachedRepairCenterDefaults = null;
        cachedDefaultPricebookId = null;
        cachedProductServicedWorkOrderLineItemRecordTypeId = null;
    }

    private static RepairCenterDefaults__mdt getRepairCenterDefaults() {
        if (cachedRepairCenterDefaults == null) {
            cachedRepairCenterDefaults = RepairCenterDefaults__mdt.getInstance(
                REPAIR_CENTER_DEFAULTS_RECORD_DEVELOPER_NAME
            );
        }
        return cachedRepairCenterDefaults;
    }

    private static String resolveRepairCenterDefaultPriceListName() {
        RepairCenterDefaults__mdt defaults = getRepairCenterDefaults();
        if (defaults == null || String.isBlank(defaults.PriceList__c)) {
            return null;
        }
        return defaults.PriceList__c.trim();
    }

    private static Id resolveDefaultPricebookId() {
        if (cachedDefaultPricebookId != null) {
            return cachedDefaultPricebookId;
        }

        String priceListName = resolveRepairCenterDefaultPriceListName();
        if (String.isBlank(priceListName)) {
            return null;
        }

        List<Pricebook2> pricebooks = [
            SELECT Id
            FROM Pricebook2
            WHERE Name = :priceListName
            AND IsActive = true
            WITH USER_MODE
            LIMIT 1
        ];
        if (!pricebooks.isEmpty()) {
            cachedDefaultPricebookId = pricebooks[0].Id;
        }
        return cachedDefaultPricebookId;
    }

    private static void applyDefaultPricebookToWorkOrder(WorkOrder workOrder) {
        if (workOrder == null || !Schema.SObjectType.WorkOrder.fields.Pricebook2Id.isCreateable()) {
            return;
        }

        Id pricebookId = resolveDefaultPricebookId();
        if (pricebookId != null) {
            workOrder.Pricebook2Id = pricebookId;
        }
    }

    private static Id getProductServicedWorkOrderLineItemRecordTypeId() {
        if (cachedProductServicedWorkOrderLineItemRecordTypeId != null) {
            return cachedProductServicedWorkOrderLineItemRecordTypeId;
        }

        cachedProductServicedWorkOrderLineItemRecordTypeId = getWorkOrderLineItemRecordTypeId(
            WOLI_RECORD_TYPE_PRODUCT_SERVICED,
            'Product Serviced work order line item record type is not available.'
        );
        return cachedProductServicedWorkOrderLineItemRecordTypeId;
    }

    private static Id getWorkOrderLineItemRecordTypeId(
        String developerName,
        String unavailableMessage
    ) {
        Schema.RecordTypeInfo recordTypeInfo = Schema.SObjectType.WorkOrderLineItem
            .getRecordTypeInfosByDeveloperName()
            .get(developerName);
        if (recordTypeInfo == null || !recordTypeInfo.isAvailable()) {
            throw new AuraHandledException(
                unavailableMessage +
                    ' Ask your administrator to grant access to the Return Order Line Items Access permission set.'
            );
        }
        return recordTypeInfo.getRecordTypeId();
    }

    private static Id resolvePricebookEntryId(
        Id pricebookId,
        Id product2Id,
        String currencyIsoCode
    ) {
        if (pricebookId == null || product2Id == null) {
            return null;
        }

        String resolvedCurrency = String.isNotBlank(currencyIsoCode)
            ? currencyIsoCode
            : UserInfo.getDefaultCurrency();

        List<PricebookEntry> pricebookEntries = [
            SELECT Id
            FROM PricebookEntry
            WHERE Pricebook2Id = :pricebookId
            AND Product2Id = :product2Id
            AND IsActive = true
            AND CurrencyIsoCode = :resolvedCurrency
            WITH USER_MODE
            LIMIT 1
        ];
        return pricebookEntries.isEmpty() ? null : pricebookEntries[0].Id;
    }

    private static Product2 queryProductDetailsForWorkOrderLineItem(Id product2Id) {
        if (product2Id == null) {
            return null;
        }

        List<Product2> products = [
            SELECT Id, ProductCode, Description
            FROM Product2
            WHERE Id = :product2Id
            WITH USER_MODE
            LIMIT 1
        ];
        return products.isEmpty() ? null : products[0];
    }

    private static WorkOrderLineItem buildSerializedProductServicedWorkOrderLineItem(
        WorkOrder childWorkOrder,
        Id parentWorkOrderId,
        Id returnOrderId,
        ReturnOrderLineItem lineItem,
        LineReceiveInput lineInput
    ) {
        if (childWorkOrder == null || childWorkOrder.Id == null || returnOrderId == null) {
            return null;
        }

        Id product2Id = childWorkOrder.Product__c;
        if (product2Id == null && lineItem != null) {
            product2Id = lineItem.Product2Id;
        }
        if (product2Id == null && lineInput != null) {
            product2Id = lineInput.productId;
        }
        if (product2Id == null) {
            return null;
        }

        Product2 productDetails = queryProductDetailsForWorkOrderLineItem(product2Id);
        Id pricebookId = childWorkOrder.Pricebook2Id != null
            ? childWorkOrder.Pricebook2Id
            : resolveDefaultPricebookId();
        Id pricebookEntryId = resolvePricebookEntryId(
            pricebookId,
            product2Id,
            childWorkOrder.CurrencyIsoCode
        );

        WorkOrderLineItem workOrderLineItem = new WorkOrderLineItem();
        workOrderLineItem.WorkOrderId = childWorkOrder.Id;
        workOrderLineItem.TopLevelWorkOrder__c = parentWorkOrderId;
        if (lineItem != null) {
            workOrderLineItem.ReturnOrderLineItemId = lineItem.Id;
        }
        workOrderLineItem.RecordTypeId = getProductServicedWorkOrderLineItemRecordTypeId();
        workOrderLineItem.LineType__c = WOLI_LINE_TYPE_PRODUCT_SERVICED;
        workOrderLineItem.Subject = childWorkOrder.Subject;
        workOrderLineItem.Description = childWorkOrder.Description;
        workOrderLineItem.AssetId = childWorkOrder.AssetId;
        workOrderLineItem.SerialNumber__c = childWorkOrder.SerialNumber__c;
        workOrderLineItem.Model__c = childWorkOrder.Model__c;
        workOrderLineItem.TrayName__c = childWorkOrder.TrayName__c;
        workOrderLineItem.Quantity = 1;
        if (pricebookEntryId != null) {
            workOrderLineItem.PricebookEntryId = pricebookEntryId;
        } else {
            workOrderLineItem.Product2Id = product2Id;
        }
        if (productDetails != null) {
            workOrderLineItem.ProductCodeWoli__c = productDetails.ProductCode;
            workOrderLineItem.ProductDescription__c = productDetails.Description;
        }
        applySerializedProductServicedEstimateContact(
            workOrderLineItem,
            childWorkOrder,
            lineItem,
            lineInput
        );
        applySerializedProductServicedWoliStatus(workOrderLineItem, childWorkOrder);
        return workOrderLineItem;
    }

    /**
     * @description GW-5715 Maps Estimate Contact onto Product Serviced WOLIs created for child Devices/Other WOs.
     */
    private static void applySerializedProductServicedEstimateContact(
        WorkOrderLineItem workOrderLineItem,
        WorkOrder childWorkOrder,
        ReturnOrderLineItem lineItem,
        LineReceiveInput lineInput
    ) {
        if (workOrderLineItem == null ||
            !Schema.SObjectType.WorkOrderLineItem.fields.EstimateContact__c.isCreateable()) {
            return;
        }

        Id estimateContactId = childWorkOrder != null ? childWorkOrder.EstimateContact__c : null;
        if (estimateContactId == null && lineItem != null) {
            estimateContactId = lineItem.EstimateContact__c;
        }
        if (estimateContactId == null && lineInput != null) {
            estimateContactId = lineInput.estimateContactId;
        }
        if (estimateContactId != null) {
            workOrderLineItem.EstimateContact__c = estimateContactId;
        }
    }

    private static void applySerializedProductServicedWoliStatus(
        WorkOrderLineItem workOrderLineItem,
        WorkOrder childWorkOrder
    ) {
        if (workOrderLineItem == null || childWorkOrder == null) {
            return;
        }
        if (!Schema.SObjectType.WorkOrderLineItem.fields.Status.isCreateable()) {
            return;
        }
        if (childWorkOrder.Status != WO_STATUS_RECEIVED) {
            return;
        }

        if (childWorkOrder.EstimateRequired__c == ESTIMATE_REQUIRED_ESTIMATE_REQUIRED) {
            workOrderLineItem.Status = WOLI_STATUS_WAITING_FOR_APPROVAL;
        } else {
            workOrderLineItem.Status = WOLI_STATUS_APPROVED;
        }
    }

    private static Id resolveProductServicedWorkOrderLineItemId(Id workOrderId, Id assetId) {
        if (workOrderId == null) {
            return null;
        }

        List<WorkOrderLineItem> lineItems;
        if (assetId != null) {
            lineItems = [
                SELECT Id
                FROM WorkOrderLineItem
                WHERE WorkOrderId = :workOrderId
                AND LineType__c = :WOLI_LINE_TYPE_PRODUCT_SERVICED
                AND IsAccessory__c = FALSE
                AND AssetId = :assetId
                WITH USER_MODE
                ORDER BY CreatedDate DESC
                LIMIT 1
            ];
        } else {
            lineItems = [
                SELECT Id
                FROM WorkOrderLineItem
                WHERE WorkOrderId = :workOrderId
                AND LineType__c = :WOLI_LINE_TYPE_PRODUCT_SERVICED
                AND IsAccessory__c = FALSE
                WITH USER_MODE
                ORDER BY CreatedDate DESC
                LIMIT 1
            ];
        }

        return lineItems.isEmpty() ? null : lineItems[0].Id;
    }

    private static void insertSerializedProductServicedWorkOrderLineItem(
        WorkOrder childWorkOrder,
        Id parentWorkOrderId,
        Id returnOrderId,
        ReturnOrderLineItem lineItem,
        LineReceiveInput lineInput
    ) {
        WorkOrderLineItem workOrderLineItem = buildSerializedProductServicedWorkOrderLineItem(
            childWorkOrder,
            parentWorkOrderId,
            returnOrderId,
            lineItem,
            lineInput
        );
        if (workOrderLineItem == null) {
            return;
        }

        insertCreatableWorkOrderLineItems(
            new List<WorkOrderLineItem>{ workOrderLineItem },
            childWorkOrder.Id,
            'Unable to create product serviced work order line items due to field access restrictions.'
        );
    }

    private static void applyWorkOrderFieldMappings(
        WorkOrder workOrder,
        ReturnOrderLineItem lineItem,
        Decimal quantityReceived,
        String returnOrderType
    ) {
        if (workOrder == null || lineItem == null) {
            return;
        }

        if (returnOrderType == RO_TYPE_INSTRUMENTS) {
            workOrder.QuantityReceived__c = quantityReceived;
            return;
        }

        if (lineItem.AssetId != null) {
            workOrder.AssetId = lineItem.AssetId;
        }
        if (returnOrderType != RO_TYPE_OTHER) {
            workOrder.Product__c = lineItem.Product2Id;
            workOrder.TrayName__c = lineItem.HospitalReferencedTrayName__c;
        }
        workOrder.Model__c = lineItem.Model__c;
        workOrder.SerialNumber__c = resolveLineItemSerialNumber(lineItem);
        applyWorkOrderWarrantyFields(workOrder, lineItem);
        workOrder.QuantityReceived__c = quantityReceived;
    }

    private static void applyWorkOrderWarrantyFields(
        WorkOrder workOrder,
        ReturnOrderLineItem lineItem
    ) {
        if (workOrder == null || lineItem == null) {
            return;
        }

        if (Schema.SObjectType.WorkOrder.fields.RepairWarranty__c.isCreateable()) {
            workOrder.RepairWarranty__c = lineItem.RepairWarranty__c;
        }
        if (Schema.SObjectType.WorkOrder.fields.WarrantyNotes__c.isCreateable()) {
            workOrder.WarrantyNotes__c = lineItem.WarrantyNotes__c;
        }
    }

    private static void applyRepairCenterFromReturnOrder(
        WorkOrder workOrder,
        ReturnOrder returnOrder
    ) {
        if (workOrder == null || returnOrder == null || returnOrder.DestinationLocationId == null) {
            return;
        }

        workOrder.RepairCenter__c = returnOrder.DestinationLocationId;
    }

    private static void applyWorkOrderHeaderFieldMappings(
        WorkOrder workOrder,
        ReturnOrder returnOrder,
        ReturnOrderLineItem lineItem,
        String returnOrderType
    ) {
        if (workOrder == null) {
            return;
        }

        if (returnOrder != null) {
            workOrder.AssignedSalesPerson__c = returnOrder.SalesRep__c;
        }

        if (returnOrderType == RO_TYPE_INSTRUMENTS) {
            applyInstrumentReturnOrderHeaderToWorkOrder(workOrder, returnOrder);
            return;
        }

        if (lineItem != null) {
            workOrder.CustomerPO__c = lineItem.CustomerPO__c;
            workOrder.Department__c = lineItem.Department__c;
            applyWorkOrderCustomerReferenceFromLineItem(workOrder, lineItem);
        }

        // GW-5715: Devices/Other style headers (non-Instruments) map Estimate Contact from RO, else ROLI.
        applyEstimateContactToWorkOrder(workOrder, returnOrder, lineItem);
    }

    /**
     * @description GW-5715 Sets WorkOrder.EstimateContact__c from Return Order, falling back to ROLI.
     */
    private static void applyEstimateContactToWorkOrder(
        WorkOrder workOrder,
        ReturnOrder returnOrder,
        ReturnOrderLineItem lineItem
    ) {
        if (workOrder == null ||
            !Schema.SObjectType.WorkOrder.fields.EstimateContact__c.isCreateable()) {
            return;
        }

        Id estimateContactId = null;
        if (returnOrder != null && returnOrder.EstimateContact__c != null) {
            estimateContactId = returnOrder.EstimateContact__c;
        } else if (lineItem != null) {
            estimateContactId = lineItem.EstimateContact__c;
        }
        if (estimateContactId != null) {
            workOrder.EstimateContact__c = estimateContactId;
        }
    }

    private static void applyWorkOrderCustomerReferenceFromLineItem(
        WorkOrder workOrder,
        ReturnOrderLineItem lineItem
    ) {
        if (workOrder == null || lineItem == null) {
            return;
        }

        if (Schema.SObjectType.WorkOrder.fields.CustomerReference__c.isCreateable()) {
            workOrder.CustomerReference__c = lineItem.CustomerReference__c;
        }
    }

    private static void applyInstrumentReturnOrderHeaderToWorkOrder(
        WorkOrder workOrder,
        ReturnOrder returnOrder
    ) {
        if (workOrder == null || returnOrder == null) {
            return;
        }

        workOrder.ContactId = returnOrder.ContactId;
        workOrder.CustomerPO__c = returnOrder.CustomerPO__c;
        workOrder.CaseId = returnOrder.CaseId;

        if (Schema.SObjectType.WorkOrder.fields.TrayName__c.isCreateable()) {
            workOrder.TrayName__c = returnOrder.HospitalReferencedTrayName__c;
        }
        if (Schema.SObjectType.WorkOrder.fields.RepairWarranty__c.isCreateable()) {
            workOrder.RepairWarranty__c = returnOrder.RepairWarranty__c;
        }
        if (Schema.SObjectType.WorkOrder.fields.WarrantyNotes__c.isCreateable()) {
            workOrder.WarrantyNotes__c = returnOrder.WarrantyNotes__c;
        }
        if (Schema.SObjectType.WorkOrder.fields.EstimateRequired__c.isCreateable()) {
            workOrder.EstimateRequired__c = returnOrder.EstimateRequired__c;
        }
        if (Schema.SObjectType.WorkOrder.fields.EstimateContact__c.isCreateable()) {
            workOrder.EstimateContact__c = returnOrder.EstimateContact__c;
        }
        if (Schema.SObjectType.WorkOrder.fields.PreviousReturnOrder__c.isCreateable()) {
            workOrder.PreviousReturnOrder__c = returnOrder.PreviousReturnOrder__c;
        }
        if (Schema.SObjectType.WorkOrder.fields.CustomerReference__c.isCreateable()) {
            workOrder.CustomerReference__c = returnOrder.CustomerReference__c;
        }
    }

    private static WorkOrder buildExtendedWorkOrder(
        ReturnOrder returnOrder,
        ReturnOrderLineItem lineItem,
        Id receiverId,
        Id recordTypeId,
        String subStatus,
        String subject,
        String returnOrderType
    ) {
        WorkOrder workOrder = new WorkOrder();
        workOrder.RecordTypeId = recordTypeId;
        workOrder.Status = WO_STATUS_RECEIVED;
        applyWorkOrderSubStatus(workOrder, subStatus);
        workOrder.AccountId = returnOrder.AccountId;
        if (returnOrderType != RO_TYPE_INSTRUMENTS) {
            workOrder.ContactId = lineItem.Contact__c != null
                ? lineItem.Contact__c
                : returnOrder.ContactId;
        }
        workOrder.LocationId = returnOrder.DestinationLocationId;
        applyRepairCenterFromReturnOrder(workOrder, returnOrder);
        workOrder.Receiver__c = receiverId;
        applyWorkOrderReturnOrderReference(workOrder, returnOrder.Id);
        workOrder.Subject = subject;
        applyWorkOrderHeaderFieldMappings(workOrder, returnOrder, lineItem, returnOrderType);
        applyDefaultPricebookToWorkOrder(workOrder);
        return workOrder;
    }

    private static WorkOrder buildParentWorkOrder(
        ReturnOrder returnOrder,
        Id receiverId,
        Id recordTypeId,
        String subStatus,
        String subject,
        ReturnOrderLineItem lineItem
    ) {
        WorkOrder parentWorkOrder = new WorkOrder();
        parentWorkOrder.RecordTypeId = recordTypeId;
        parentWorkOrder.Status = WO_STATUS_RECEIVED;
        applyWorkOrderSubStatus(parentWorkOrder, subStatus);
        parentWorkOrder.AccountId = returnOrder.AccountId;
        parentWorkOrder.ContactId = returnOrder.ContactId;
        parentWorkOrder.LocationId = returnOrder.DestinationLocationId;
        applyRepairCenterFromReturnOrder(parentWorkOrder, returnOrder);
        parentWorkOrder.Receiver__c = receiverId;
        applyWorkOrderReturnOrderReference(parentWorkOrder, returnOrder.Id);
        parentWorkOrder.Subject = subject;
        applyWorkOrderHeaderFieldMappings(
            parentWorkOrder,
            returnOrder,
            lineItem,
            RO_TYPE_SERIALIZED
        );
        applyDefaultPricebookToWorkOrder(parentWorkOrder);
        return parentWorkOrder;
    }

    private static WorkOrder buildChildWorkOrder(
        Id parentWorkOrderId,
        ReturnOrder returnOrder,
        ReturnOrderLineItem lineItem,
        Id receiverId,
        Id recordTypeId,
        String subStatus,
        String subject
    ) {
        WorkOrder childWorkOrder = new WorkOrder();
        childWorkOrder.RecordTypeId = recordTypeId;
        childWorkOrder.ParentWorkOrderId = parentWorkOrderId;
        childWorkOrder.Status = WO_STATUS_RECEIVED;
        applyWorkOrderSubStatus(childWorkOrder, subStatus);
        childWorkOrder.AccountId = returnOrder.AccountId;
        childWorkOrder.ContactId = lineItem.Contact__c != null
            ? lineItem.Contact__c
            : returnOrder.ContactId;
        childWorkOrder.ReturnOrderLineItemId = lineItem.Id;
        applyWorkOrderReturnOrderReference(childWorkOrder, returnOrder.Id);
        applyWorkOrderFieldMappings(childWorkOrder, lineItem, 1, RO_TYPE_SERIALIZED);
        applyWorkOrderCustomerReferenceFromLineItem(childWorkOrder, lineItem);
        applySerializedChildWorkOrderEstimateRequiredFromLineItem(childWorkOrder, returnOrder, lineItem);
        childWorkOrder.LocationId = returnOrder.DestinationLocationId;
        applyRepairCenterFromReturnOrder(childWorkOrder, returnOrder);
        childWorkOrder.Receiver__c = receiverId;
        childWorkOrder.Subject = subject;
        if (String.isNotBlank(lineItem.ReportedProblem__c)) {
            childWorkOrder.Description = lineItem.ReportedProblem__c.trim();
        }
        applyDefaultPricebookToWorkOrder(childWorkOrder);
        // --- START RELEVANT TO GW-3337 ---
        if (subStatus == WO_SUB_STATUS_READY_FOR_EVAL && lineItem.ProductLine__c == PRODUCT_LINE_RIGID_SCOPE) {
            childWorkOrder.Status = WO_STATUS_EVALUATE;
            applyWorkOrderSubStatus(childWorkOrder, WO_SUB_STATUS_TRIAGE);
        }
        // --- END RELEVANT TO GW-3337 ---
        return childWorkOrder;
    }

    private static void applySerializedChildWorkOrderEstimateRequiredFromLineItem(
        WorkOrder childWorkOrder,
        ReturnOrder returnOrder,
        ReturnOrderLineItem lineItem
    ) {
        if (childWorkOrder == null) {
            return;
        }
        if (lineItem != null &&
            Schema.SObjectType.WorkOrder.fields.EstimateRequired__c.isCreateable()) {
            childWorkOrder.EstimateRequired__c = lineItem.EstimateRequired__c;
        }
        // GW-5715: map Estimate Contact onto Devices/Other child Work Orders.
        applyEstimateContactToWorkOrder(childWorkOrder, returnOrder, lineItem);
    }

    private static WorkOrder buildChildWorkOrderFromAdHocInput(
        Id parentWorkOrderId,
        ReturnOrder returnOrder,
        LineReceiveInput lineInput,
        Id receiverId,
        Id recordTypeId,
        String subStatus,
        String subject,
        Boolean isContaminated
    ) {
        WorkOrder childWorkOrder = new WorkOrder();
        childWorkOrder.RecordTypeId = recordTypeId;
        childWorkOrder.ParentWorkOrderId = parentWorkOrderId;
        childWorkOrder.Status = WO_STATUS_RECEIVED;
        applyWorkOrderSubStatus(childWorkOrder, subStatus);
        childWorkOrder.AccountId = returnOrder.AccountId;
        childWorkOrder.ContactId = returnOrder.ContactId;
        childWorkOrder.LocationId = returnOrder.DestinationLocationId;
        applyWorkOrderReturnOrderReference(childWorkOrder, returnOrder.Id);
        applyRepairCenterFromReturnOrder(childWorkOrder, returnOrder);
        childWorkOrder.Receiver__c = receiverId;
        childWorkOrder.Subject = subject;
        childWorkOrder.Contaminated__c = isContaminated == true;

        if (lineInput.selectedAssetId != null) {
            childWorkOrder.AssetId = lineInput.selectedAssetId;
        }
        if (lineInput.productId != null) {
            childWorkOrder.Product__c = lineInput.productId;
        }
        if (String.isNotBlank(lineInput.hospitalTrayName)) {
            childWorkOrder.TrayName__c = lineInput.hospitalTrayName.trim();
        }
        if (String.isNotBlank(lineInput.model)) {
            childWorkOrder.Model__c = lineInput.model.trim();
        }
        if (String.isNotBlank(lineInput.serialNumber)) {
            childWorkOrder.SerialNumber__c = lineInput.serialNumber.trim();
        }
        childWorkOrder.QuantityReceived__c = lineInput.quantityReceived != null
            ? lineInput.quantityReceived
            : 1;

        applyAdHocLineInputToChildWorkOrder(childWorkOrder, returnOrder, lineInput);
        if (String.isNotBlank(lineInput.reportedProblem)) {
            childWorkOrder.Description = lineInput.reportedProblem.trim();
        }
        applyDefaultPricebookToWorkOrder(childWorkOrder);

        return childWorkOrder;
    }

    private static void applyAdHocLineInputToChildWorkOrder(
        WorkOrder childWorkOrder,
        ReturnOrder returnOrder,
        LineReceiveInput lineInput
    ) {
        if (childWorkOrder == null || lineInput == null) {
            return;
        }

        childWorkOrder.ContactId = lineInput.contactId != null
            ? lineInput.contactId
            : returnOrder.ContactId;

        if (lineInput.departmentId != null) {
            childWorkOrder.Department__c = lineInput.departmentId;
        }
        if (String.isNotBlank(lineInput.customerPo)) {
            childWorkOrder.CustomerPO__c = lineInput.customerPo.trim();
        }
        if (String.isNotBlank(lineInput.customerReference) &&
            Schema.SObjectType.WorkOrder.fields.CustomerReference__c.isCreateable()) {
            childWorkOrder.CustomerReference__c = lineInput.customerReference.trim();
        }
        if (Schema.SObjectType.WorkOrder.fields.RepairWarranty__c.isCreateable() &&
            String.isNotBlank(lineInput.repairWarranty)) {
            childWorkOrder.RepairWarranty__c = lineInput.repairWarranty;
        }
        if (Schema.SObjectType.WorkOrder.fields.WarrantyNotes__c.isCreateable() &&
            String.isNotBlank(lineInput.warrantyNotes)) {
            childWorkOrder.WarrantyNotes__c = lineInput.warrantyNotes.trim();
        }
        if (Schema.SObjectType.WorkOrder.fields.EstimateRequired__c.isCreateable() &&
            String.isNotBlank(lineInput.estimateRequired)) {
            childWorkOrder.EstimateRequired__c = lineInput.estimateRequired;
        }
        // GW-5715: prefer ad hoc line Estimate Contact, else Return Order header.
        if (Schema.SObjectType.WorkOrder.fields.EstimateContact__c.isCreateable()) {
            Id estimateContactId = lineInput.estimateContactId != null
                ? lineInput.estimateContactId
                : (returnOrder != null ? returnOrder.EstimateContact__c : null);
            if (estimateContactId != null) {
                childWorkOrder.EstimateContact__c = estimateContactId;
            }
        }
        if (Schema.SObjectType.WorkOrder.fields.PreviousReturnOrder__c.isCreateable() &&
            String.isNotBlank(lineInput.previousReturnOrder)) {
            childWorkOrder.PreviousReturnOrder__c = lineInput.previousReturnOrder.trim();
        }
    }

    private static List<PicklistOption> getDisinfectedPicklistOptions() {
        Map<String, Schema.SObjectField> lineFields =
            Schema.SObjectType.ReturnOrderLineItem.fields.getMap();
        if (!lineFields.containsKey('Disinfected__c')) {
            return new List<PicklistOption>();
        }
        return getPicklistOptions(lineFields.get('Disinfected__c').getDescribe());
    }

    private static List<PicklistOption> getEstimateRequiredPicklistOptions() {
        Map<String, Schema.SObjectField> lineFields =
            Schema.SObjectType.ReturnOrderLineItem.fields.getMap();
        if (lineFields.containsKey('EstimateRequired__c')) {
            return getPicklistOptions(lineFields.get('EstimateRequired__c').getDescribe());
        }
        if (lineFields.containsKey('EstReq__c')) {
            return getPicklistOptions(lineFields.get('EstReq__c').getDescribe());
        }
        return new List<PicklistOption>();
    }

    private static List<PicklistOption> getPicklistOptions(Schema.DescribeFieldResult fieldDescribe) {
        List<PicklistOption> options = new List<PicklistOption>();
        if (fieldDescribe == null) {
            return options;
        }

        for (Schema.PicklistEntry entry : fieldDescribe.getPicklistValues()) {
            if (!entry.isActive()) {
                continue;
            }
            PicklistOption option = new PicklistOption();
            option.label = entry.getLabel();
            option.value = entry.getValue();
            options.add(option);
        }
        return options;
    }

    private static ReturnOrderLineItem resolveFirstLinkedLineItem(
        List<LineReceiveInput> lineInputs,
        Map<Id, ReturnOrderLineItem> lineItemsById
    ) {
        for (LineReceiveInput lineInput : lineInputs) {
            if (isAdHocSerializedLineInput(lineInput)) {
                continue;
            }

            ReturnOrderLineItem lineItem = lineItemsById.get(resolveInputLineItemId(lineInput));
            if (lineItem != null) {
                return lineItem;
            }
        }

        return null;
    }

    private static String resolveAdHocSerializedSubStatus(
        LineReceiveInput lineInput,
        Boolean isContaminated
    ) {
        if (isContaminated == true) {
            return WO_SUB_STATUS_CONTAMINATED;
        }
        if (lineInput != null && lineInput.modRequest == true) {
            return WO_SUB_STATUS_MOD_HOLD;
        }
        return WO_SUB_STATUS_CUSTOMER_CARE;
    }

    private static Boolean isAdHocSerializedLineInput(LineReceiveInput lineInput) {
        return lineInput != null && lineInput.isAdHocSerializedLine == true;
    }

    private static Boolean containsAdHocSerializedLineInput(List<LineReceiveInput> lineInputs) {
        if (lineInputs == null) {
            return false;
        }

        for (LineReceiveInput lineInput : lineInputs) {
            if (isAdHocSerializedLineInput(lineInput)) {
                return true;
            }
        }

        return false;
    }

    private static void markLinesReceived(
        List<LineReceiveInput> lineInputs,
        Map<Id, ReturnOrderLineItem> lineItemsById,
        Id receiverId,
        Datetime receivedDateTime,
        String returnOrderType
    ) {
        if (!Schema.sObjectType.ReturnOrderLineItem.fields.Status__c.isUpdateable()) {
            throw new AuraHandledException(
                'You do not have permission to update Return Order Line Item status.'
            );
        }

        List<ReturnOrderLineItem> updates = new List<ReturnOrderLineItem>();
        for (LineReceiveInput lineInput : lineInputs) {
            if (isAdHocSerializedLineInput(lineInput)) {
                continue;
            }

            ReturnOrderLineItem lineItem = lineItemsById.get(resolveInputLineItemId(lineInput));
            if (lineItem == null || lineItem.Status__c != STATUS_CREATED) {
                continue;
            }

            ReturnOrderLineItem updateLineItem = new ReturnOrderLineItem(Id = lineItem.Id);
            updateLineItem.Receiver__c = receiverId;
            updateLineItem.Status__c = STATUS_RECEIVED;
            updateLineItem.ReceivedDateTime__c = receivedDateTime;
            Decimal quantityReceived = lineInput.quantityReceived != null
                ? lineInput.quantityReceived
                : resolveLineQuantityReceived(lineItem, returnOrderType);
            updateLineItem.QuantityReceived = quantityReceived;
            updates.add(updateLineItem);
        }

        if (updates.isEmpty()) {
            if (containsAdHocSerializedLineInput(lineInputs)) {
                return;
            }
            throw new AuraHandledException(
                'No eligible line items were found to receive. Confirm the selected lines are in Created status.'
            );
        }

        List<ReturnOrderLineItem> updatableLineItems = Security.stripInaccessible(
            AccessType.UPDATABLE,
            updates
        ).getRecords();
        if (updatableLineItems.isEmpty()) {
            throw new AuraHandledException(
                'Unable to update return order line items due to field access restrictions.'
            );
        }

        executeUpdateAsUser(
            updatableLineItems,
            'ReturnOrderReceivingController.markLinesReceived: return order line items'
        );
    }

    private static void applyLineCorrections(
        List<LineReceiveInput> lineInputs,
        Map<Id, ReturnOrderLineItem> lineItemsById,
        String returnOrderType
    ) {
        for (LineReceiveInput lineInput : lineInputs) {
            if (isAdHocSerializedLineInput(lineInput) || lineInput.hasCorrections != true) {
                continue;
            }

            ReturnOrderLineItem lineItem = lineItemsById.get(resolveInputLineItemId(lineInput));
            if (lineItem == null) {
                continue;
            }

            applyLineItemCorrections(lineItem, lineInput, returnOrderType);
        }
    }

    private static void applyLineItemCorrections(
        ReturnOrderLineItem lineItem,
        LineReceiveInput lineInput,
        String returnOrderType
    ) {
        if (isOtherLineItem(lineItem, returnOrderType)) {
            applyOtherLineItemCorrections(lineItem, lineInput);
            return;
        }

        applySerializedLineItemCorrections(
            lineItem,
            lineInput.serialNumber,
            lineInput.model,
            lineInput.departmentId,
            lineInput.productLine,
            lineInput.selectedAssetId,
            lineInput.productId
        );
    }

    private static void applyOtherLineItemCorrections(
        ReturnOrderLineItem lineItem,
        LineReceiveInput lineInput
    ) {
        ReturnOrderLineItem updateLineItem = new ReturnOrderLineItem(Id = lineItem.Id);
        Boolean requiresUpdate = false;

        if (String.isNotBlank(lineInput.itemType)) {
            updateLineItem.ItemType__c = lineInput.itemType.trim();
            String mappedProductLine = resolveProductLineForItemType(lineInput.itemType);
            if (String.isNotBlank(mappedProductLine)) {
                updateLineItem.ProductLine__c = mappedProductLine;
                if (
                    lineInput.productId == null &&
                    normalizeOptionalString(lineItem.ProductLine__c) !=
                    normalizeOptionalString(mappedProductLine)
                ) {
                    updateLineItem.Product2Id = null;
                }
            }
            requiresUpdate = true;
        } else if (String.isNotBlank(lineInput.productLine)) {
            updateLineItem.ProductLine__c = lineInput.productLine.trim();
            requiresUpdate = true;
        }
        if (lineInput.productId != null) {
            updateLineItem.Product2Id = lineInput.productId;
            requiresUpdate = true;
        }
        if (String.isNotBlank(lineInput.serialNumber)) {
            updateLineItem.SerialNumber__c = lineInput.serialNumber.trim();
            requiresUpdate = true;
        }
        if (String.isNotBlank(lineInput.hospitalTrayName)) {
            updateLineItem.HospitalReferencedTrayName__c = lineInput.hospitalTrayName.trim();
            requiresUpdate = true;
        }
        if (lineInput.quantityReturned != null) {
            updateLineItem.QuantityReturned = lineInput.quantityReturned;
            requiresUpdate = true;
        }

        if (!requiresUpdate) {
            return;
        }

        List<ReturnOrderLineItem> updatableLineItems = Security.stripInaccessible(
            AccessType.UPDATABLE,
            new List<ReturnOrderLineItem>{ updateLineItem }
        ).getRecords();
        if (updatableLineItems.isEmpty()) {
            return;
        }

        executeUpdateAsUser(
            updatableLineItems,
            'ReturnOrderReceivingController.applyOtherLineItemCorrections: return order line item'
        );
    }

    private static void applySerializedLineItemCorrections(
        ReturnOrderLineItem lineItem,
        String serialNumber,
        String model,
        Id departmentId,
        String productLine,
        Id selectedAssetId,
        Id productId
    ) {
        Id assetIdToUpdate = selectedAssetId != null ? selectedAssetId : lineItem.AssetId;

        ElevatedAccessService elevatedAccess = new ElevatedAccessService();

        if (assetIdToUpdate != null) {
            // Asset is Controlled by Parent (Account). Repair Center users often have
            // Account Read-only sharing, so elevate this master-data correction.
            elevatedAccess.updateAssetForReceivingCorrection(
                assetIdToUpdate,
                serialNumber,
                departmentId
            );
        }

        ReturnOrderLineItem updateLineItem = new ReturnOrderLineItem(
            Id = lineItem.Id,
            Model__c = model,
            Department__c = departmentId,
            ProductLine__c = productLine
        );
        if (productId != null) {
            updateLineItem.Product2Id = productId;
        }
        if (selectedAssetId != null) {
            updateLineItem.AssetId = selectedAssetId;
        }
        if (assetIdToUpdate == null) {
            updateLineItem.SerialNumber__c = serialNumber;
        }
        // Elevate ROLI correction write as well so AssetId/Product2Id lookups are not
        // blocked by the same Account Read-only sharing constraints.
        elevatedAccess.updateRecords(
            new List<ReturnOrderLineItem>{ updateLineItem },
            'ReturnOrderReceivingController.applySerializedLineItemCorrections: return order line item'
        );
    }

    private static String resolveSerializedChildSubStatus(
        LineReceiveInput lineInput,
        Map<Id, String> subStatusByLineItemId
    ) {
        Id lineItemId = resolveInputLineItemId(lineInput);
        String subStatus = subStatusByLineItemId.get(lineItemId);
        return String.isNotBlank(subStatus) ? subStatus : WO_SUB_STATUS_READY_FOR_EVAL;
    }

    private static Map<Id, String> buildSubStatusByLineItemId(
        List<LineReceiveInput> lineInputs,
        Map<Id, ReturnOrderLineItem> lineItemsById,
        String returnOrderType,
        Boolean isContaminated
    ) {
        Map<Id, String> subStatusByLineItemId = new Map<Id, String>();
        for (LineReceiveInput lineInput : lineInputs) {
            Id lineItemId = resolveInputLineItemId(lineInput);
            ReturnOrderLineItem lineItem = lineItemsById.get(lineItemId);
            if (lineItem == null) {
                continue;
            }

            if (returnOrderType == RO_TYPE_SERIALIZED) {
                subStatusByLineItemId.put(
                    lineItemId,
                    resolveSerializedLineSubStatus(lineItem, lineInput, isContaminated)
                );
            } else if (returnOrderType == RO_TYPE_OTHER) {
                subStatusByLineItemId.put(
                    lineItemId,
                    resolveOtherLineSubStatus(lineItem, lineInput, isContaminated)
                );
            } else {
                subStatusByLineItemId.put(
                    lineItemId,
                    resolveLineReceiveSubStatus(lineItem, lineInput)
                );
            }
        }
        return subStatusByLineItemId;
    }

    private static String resolveSerializedLineSubStatus(
        ReturnOrderLineItem lineItem,
        LineReceiveInput lineInput,
        Boolean isContaminated
    ) {
        if (isContaminated == true) {
            return WO_SUB_STATUS_CONTAMINATED;
        }
        if (lineItem.ModRequest__c == true) {
            return WO_SUB_STATUS_MOD_HOLD;
        }
        if (requiresCustomerCareForSerializedCorrection(lineItem, lineInput)) {
            return WO_SUB_STATUS_CUSTOMER_CARE;
        }
        return WO_SUB_STATUS_READY_FOR_EVAL;
    }

    private static Boolean requiresCustomerCareForSerializedCorrection(
        ReturnOrderLineItem lineItem,
        LineReceiveInput lineInput
    ) {
        if (lineInput.hasCorrections != true) {
            return false;
        }
        if (hasProductChange(lineItem, lineInput.productId)) {
            return true;
        }
        if (
            lineInput.selectedAssetId != null &&
            lineInput.selectedAssetId != lineItem.AssetId
        ) {
            return true;
        }
        if (
            normalizeOptionalString(lineItem.Model__c) !=
            normalizeOptionalString(lineInput.model)
        ) {
            return true;
        }
        if (
            normalizeOptionalString(lineItem.ProductLine__c) !=
            normalizeOptionalString(lineInput.productLine)
        ) {
            return true;
        }

        String originalSerial = normalizeOptionalString(resolveLineItemSerialNumber(lineItem));
        String correctedSerial = normalizeOptionalString(lineInput.serialNumber);
        if (
            originalSerial != correctedSerial &&
            !isSerialChangeWithinTwoCharacters(originalSerial, lineInput.serialNumber)
        ) {
            return true;
        }

        return false;
    }

    private static String resolveOtherLineSubStatus(
        ReturnOrderLineItem lineItem,
        LineReceiveInput lineInput,
        Boolean isContaminated
    ) {
        if (isContaminated == true) {
            return WO_SUB_STATUS_CONTAMINATED;
        }
        if (lineItem.ModRequest__c == true) {
            return WO_SUB_STATUS_MOD_HOLD;
        }
        if (requiresCustomerCareForOtherCorrection(lineItem, lineInput)) {
            return WO_SUB_STATUS_CUSTOMER_CARE;
        }
        return WO_SUB_STATUS_READY_FOR_EVAL;
    }

    private static Boolean requiresCustomerCareForOtherCorrection(
        ReturnOrderLineItem lineItem,
        LineReceiveInput lineInput
    ) {
        if (lineInput.hasCorrections != true) {
            return false;
        }
        if (hasProductChange(lineItem, lineInput.productId)) {
            return true;
        }

        String originalSerial = normalizeOptionalString(resolveLineItemSerialNumber(lineItem));
        String correctedSerial = normalizeOptionalString(lineInput.serialNumber);
        if (
            originalSerial != correctedSerial &&
            !isSerialChangeWithinTwoCharacters(originalSerial, lineInput.serialNumber)
        ) {
            return true;
        }

        return false;
    }

    private static String resolveLineReceiveSubStatus(
        ReturnOrderLineItem lineItem,
        LineReceiveInput lineInput
    ) {
        if (lineInput.hasCorrections != true) {
            return WO_SUB_STATUS_READY_FOR_EVAL;
        }

        if (hasProductChange(lineItem, lineInput.productId)) {
            return WO_SUB_STATUS_CUSTOMER_CARE;
        }

        if (
            !hasOtherLineCorrectionChanges(lineItem, lineInput) &&
            !hasSerialOrProductChanges(
                lineItem,
                lineInput.serialNumber,
                lineInput.model,
                lineInput.productLine,
                lineInput.selectedAssetId,
                lineInput.productId
            )
        ) {
            return isSerializedLineItem(lineItem)
                ? WO_SUB_STATUS_READY_FOR_EVAL
                : WO_SUB_STATUS_VERIFICATION;
        }

        if (
            isSerialChangeWithinTwoCharacters(
                resolveLineItemSerialNumber(lineItem),
                lineInput.serialNumber
            )
        ) {
            return WO_SUB_STATUS_CUSTOMER_CARE;
        }

        return WO_SUB_STATUS_VERIFICATION;
    }

    private static Boolean hasModRequestOnAnyLine(
        List<LineReceiveInput> lineInputs,
        Map<Id, ReturnOrderLineItem> lineItemsById
    ) {
        for (LineReceiveInput lineInput : lineInputs) {
            ReturnOrderLineItem lineItem = lineItemsById.get(resolveInputLineItemId(lineInput));
            if (lineItem != null && lineItem.ModRequest__c == true) {
                return true;
            }
        }
        return false;
    }

    private static String resolveInstrumentWorkOrderSubStatus(
        List<LineReceiveInput> lineInputs,
        Map<Id, ReturnOrderLineItem> lineItemsById
    ) {
        if (hasModRequestOnAnyLine(lineInputs, lineItemsById)) {
            return WO_SUB_STATUS_MOD_HOLD;
        }
        return WO_SUB_STATUS_READY_FOR_EVAL;
    }

    private static String resolveBulkWorkOrderSubStatus(
        List<LineReceiveInput> lineInputs,
        Map<Id, String> subStatusByLineItemId
    ) {
        String resolvedSubStatus = WO_SUB_STATUS_READY_FOR_EVAL;
        for (LineReceiveInput lineInput : lineInputs) {
            Id lineItemId = resolveInputLineItemId(lineInput);
            String lineSubStatus = subStatusByLineItemId.get(lineItemId);
            resolvedSubStatus = pickHigherPrioritySubStatus(resolvedSubStatus, lineSubStatus);
        }
        return resolvedSubStatus;
    }

    private static String pickHigherPrioritySubStatus(String currentStatus, String candidateStatus) {
        if (candidateStatus == WO_SUB_STATUS_MOD_HOLD) {
            return WO_SUB_STATUS_MOD_HOLD;
        }
        if (
            candidateStatus == WO_SUB_STATUS_CUSTOMER_CARE &&
            currentStatus != WO_SUB_STATUS_MOD_HOLD
        ) {
            return WO_SUB_STATUS_CUSTOMER_CARE;
        }
        return currentStatus;
    }

    private static Boolean isOtherLineItem(
        ReturnOrderLineItem lineItem,
        String returnOrderType
    ) {
        if (lineItem == null) {
            return false;
        }
        if (lineItem.LineType__c == RO_TYPE_OTHER) {
            return true;
        }
        return returnOrderType == RO_TYPE_OTHER;
    }

    private static Boolean hasOtherLineCorrectionChanges(
        ReturnOrderLineItem lineItem,
        LineReceiveInput lineInput
    ) {
        if (lineInput == null || lineInput.hasCorrections != true) {
            return false;
        }
        if (
            String.isNotBlank(lineInput.itemType) &&
            normalizeOptionalString(lineItem.ItemType__c) !=
            normalizeOptionalString(lineInput.itemType)
        ) {
            return true;
        }
        if (
            String.isNotBlank(lineInput.hospitalTrayName) &&
            normalizeOptionalString(lineItem.HospitalReferencedTrayName__c) !=
            normalizeOptionalString(lineInput.hospitalTrayName)
        ) {
            return true;
        }
        if (
            lineInput.quantityReturned != null &&
            lineItem.QuantityReturned != lineInput.quantityReturned
        ) {
            return true;
        }
        return false;
    }

    private static Map<String, String> itemTypeToProductLineCache;

    private static Map<String, String> getItemTypeToProductLineMappings() {
        if (itemTypeToProductLineCache != null) {
            return itemTypeToProductLineCache;
        }

        itemTypeToProductLineCache = new Map<String, String>();
        for (ROLIItemTypeandProductLine__mdt mappingRecord : [
            SELECT ItemType__c, ProductLine__c
            FROM ROLIItemTypeandProductLine__mdt
            WHERE ItemType__c != NULL AND ProductLine__c != NULL
        ]) {
            itemTypeToProductLineCache.put(
                mappingRecord.ItemType__c,
                mappingRecord.ProductLine__c
            );
        }
        return itemTypeToProductLineCache;
    }

    private static String resolveProductLineForItemType(String itemType) {
        if (String.isBlank(itemType)) {
            return null;
        }
        return getItemTypeToProductLineMappings().get(itemType.trim());
    }

    private static List<PicklistOption> buildPicklistOptions(Schema.DescribeFieldResult fieldDescribe) {
        List<PicklistOption> options = new List<PicklistOption>();
        for (Schema.PicklistEntry entry : fieldDescribe.getPicklistValues()) {
            if (!entry.isActive()) {
                continue;
            }
            PicklistOption option = new PicklistOption();
            option.label = entry.getLabel();
            option.value = entry.getValue();
            options.add(option);
        }
        return options;
    }

    private static Boolean isSerializedLineItem(ReturnOrderLineItem lineItem) {
        return lineItem.AssetId != null || String.isNotBlank(lineItem.SerialNumber__c);
    }

    private static Boolean hasProductChange(
        ReturnOrderLineItem lineItem,
        Id productId
    ) {
        return productId != null && productId != lineItem.Product2Id;
    }

    private static Boolean hasSerialOrProductChanges(
        ReturnOrderLineItem lineItem,
        String serialNumber,
        String model,
        String productLine,
        Id selectedAssetId,
        Id productId
    ) {
        if (selectedAssetId != null && selectedAssetId != lineItem.AssetId) {
            return true;
        }

        if (hasProductChange(lineItem, productId)) {
            return true;
        }

        String originalSerial = normalizeOptionalString(resolveLineItemSerialNumber(lineItem));
        String correctedSerial = normalizeOptionalString(serialNumber);
        if (originalSerial != correctedSerial) {
            return true;
        }

        if (normalizeOptionalString(lineItem.Model__c) != normalizeOptionalString(model)) {
            return true;
        }

        return normalizeOptionalString(lineItem.ProductLine__c) != normalizeOptionalString(productLine);
    }

    private static ProductPicklistOption buildProductPicklistOption(Product2 product) {
        ProductPicklistOption option = new ProductPicklistOption();
        option.value = product.Id;
        option.label = String.isNotBlank(product.ProductCode)
            ? product.Name + ' (' + product.ProductCode + ')'
            : product.Name;
        return option;
    }

    private static String normalizeOptionalString(String value) {
        return String.isBlank(value) ? '' : value.trim();
    }

    private static Boolean isSerialChangeWithinTwoCharacters(String originalSerial, String newSerial) {
        return computeEditDistance(
            String.isBlank(originalSerial) ? '' : originalSerial.trim(),
            String.isBlank(newSerial) ? '' : newSerial.trim()
        ) <= SERIAL_CHANGE_CUSTOMER_CARE_THRESHOLD;
    }

    private static Integer computeEditDistance(String source, String target) {
        if (source == target) {
            return 0;
        }

        Integer sourceLength = source == null ? 0 : source.length();
        Integer targetLength = target == null ? 0 : target.length();
        if (sourceLength == 0) {
            return targetLength;
        }
        if (targetLength == 0) {
            return sourceLength;
        }

        List<Integer> previousRow = new List<Integer>();
        List<Integer> currentRow = new List<Integer>();
        for (Integer columnIndex = 0; columnIndex <= targetLength; columnIndex++) {
            previousRow.add(columnIndex);
        }

        for (Integer rowIndex = 1; rowIndex <= sourceLength; rowIndex++) {
            currentRow.clear();
            currentRow.add(rowIndex);
            for (Integer columnIndex = 1; columnIndex <= targetLength; columnIndex++) {
                Integer substitutionCost = source.charAt(rowIndex - 1) == target.charAt(columnIndex - 1)
                    ? 0
                    : 1;
                Integer insertCost = currentRow[columnIndex - 1] + 1;
                Integer deleteCost = previousRow[columnIndex] + 1;
                Integer replaceCost = previousRow[columnIndex - 1] + substitutionCost;
                currentRow.add(
                    Math.min(insertCost, Math.min(deleteCost, replaceCost))
                );
            }
            previousRow = currentRow.clone();
        }

        return previousRow[targetLength];
    }

    private static void updateReturnOrderStatusIfComplete(Id returnOrderId) {
        if (!Schema.sObjectType.ReturnOrder.fields.Status.isUpdateable()) {
            throw new AuraHandledException(
                'You do not have permission to update Return Order status.'
            );
        }

        Integer openLineCount = [
            SELECT COUNT()
            FROM ReturnOrderLineItem
            WHERE ReturnOrderId = :returnOrderId
            AND Status__c = :STATUS_CREATED
            WITH USER_MODE
        ];
        if (openLineCount > 0) {
            return;
        }

        ReturnOrder returnOrderUpdate = new ReturnOrder(
            Id = returnOrderId,
            Status = STATUS_RECEIVED
        );
        executeUpdateAsUser(
            Security.stripInaccessible(
                AccessType.UPDATABLE,
                new List<ReturnOrder>{ returnOrderUpdate }
            ).getRecords(),
            'ReturnOrderReceivingController.updateReturnOrderStatusIfComplete: return order status'
        );
    }

    private static Boolean isReturnOrderFullyReceived(Id returnOrderId) {
        Integer openLineCount = [
            SELECT COUNT()
            FROM ReturnOrderLineItem
            WHERE ReturnOrderId = :returnOrderId
            AND Status__c = :STATUS_CREATED
            WITH USER_MODE
        ];
        return openLineCount == 0;
    }

    private static void syncReturnOrderWorkOrderCount(Id returnOrderId) {
        Set<Id> lineItemIds = new Map<Id, ReturnOrderLineItem>([
            SELECT Id
            FROM ReturnOrderLineItem
            WHERE ReturnOrderId = :returnOrderId
            WITH USER_MODE
        ]).keySet();

        Id linkedParentWorkOrderId = resolveLinkedParentWorkOrderId(returnOrderId);

        Integer workOrderCount = [
            SELECT COUNT()
            FROM WorkOrder
            WHERE ReturnOrderLineItemId IN :lineItemIds
            OR Id = :linkedParentWorkOrderId
            OR ParentWorkOrderId = :linkedParentWorkOrderId
            WITH USER_MODE
        ];

        ReturnOrder returnOrderUpdate = new ReturnOrder(
            Id = returnOrderId,
            WOCount__c = workOrderCount
        );
        executeUpdateAsUser(
            Security.stripInaccessible(
                AccessType.UPDATABLE,
                new List<ReturnOrder>{ returnOrderUpdate }
            ).getRecords(),
            'ReturnOrderReceivingController.syncReturnOrderWorkOrderCount: return order work order count'
        );
    }

    private static void linkReturnOrderToWorkOrder(Id returnOrderId, Id workOrderId) {
        linkReturnOrderToWorkOrder(returnOrderId, workOrderId, true);
    }

    private static void linkReturnOrderToWorkOrder(
        Id returnOrderId,
        Id workOrderId,
        Boolean syncWorkOrderReturnOrderReference
    ) {
        if (returnOrderId == null || workOrderId == null) {
            return;
        }

        if (
            Schema.sObjectType.ReturnOrder.fields.WorkOrder__c.isAccessible() &&
            Schema.sObjectType.ReturnOrder.fields.WorkOrder__c.isUpdateable()
        ) {
            executeUpdateAsUser(
                Security.stripInaccessible(
                    AccessType.UPDATABLE,
                    new List<ReturnOrder>{
                        new ReturnOrder(Id = returnOrderId, WorkOrder__c = workOrderId)
                    }
                ).getRecords(),
                'ReturnOrderReceivingController.linkReturnOrderToWorkOrder: return order work order link'
            );
        }

        if (syncWorkOrderReturnOrderReference == true) {
            syncWorkOrderReturnOrderReference(workOrderId, returnOrderId);
        }
    }

    private static void applyWorkOrderReturnOrderReference(WorkOrder workOrder, Id returnOrderId) {
        if (workOrder == null || returnOrderId == null) {
            return;
        }

        workOrder.ReturnOrder__c = returnOrderId;
    }

    private static void ensureWorkOrderReturnOrderReference(Id workOrderId, Id returnOrderId) {
        if (workOrderId == null || returnOrderId == null) {
            return;
        }

        WorkOrder existingWorkOrder = [
            SELECT ReturnOrder__c
            FROM WorkOrder
            WHERE Id = :workOrderId
            WITH USER_MODE
            LIMIT 1
        ];
        if (existingWorkOrder.ReturnOrder__c == returnOrderId) {
            return;
        }

        WorkOrder workOrderUpdate = new WorkOrder(Id = workOrderId);
        applyWorkOrderReturnOrderReference(workOrderUpdate, returnOrderId);
        List<WorkOrder> updatableWorkOrders = Security.stripInaccessible(
            AccessType.UPDATABLE,
            new List<WorkOrder>{ workOrderUpdate }
        ).getRecords();
        if (!updatableWorkOrders.isEmpty()) {
            executeUpdateAsUser(
                updatableWorkOrders,
                'ReturnOrderReceivingController.ensureWorkOrderReturnOrderReference: work order return order reference'
            );
        }
    }

    private static void syncWorkOrderReturnOrderReference(Id workOrderId, Id returnOrderId) {
        ensureWorkOrderReturnOrderReference(workOrderId, returnOrderId);
    }

    private static Decimal resolveInstrumentHeaderQuantityReceived(
        Decimal instrumentQuantityReceived,
        List<LineReceiveInput> lineInputs,
        Map<Id, ReturnOrderLineItem> lineItemsById
    ) {
        if (instrumentQuantityReceived != null) {
            return instrumentQuantityReceived;
        }
        return resolveSummarizedQuantityFromLineInputs(lineInputs, lineItemsById);
    }

    private static void syncReturnOrderInstrumentQuantityReceived(
        Id returnOrderId,
        Decimal quantityReceived
    ) {
        if (returnOrderId == null || quantityReceived == null) {
            return;
        }
        if (!Schema.sObjectType.ReturnOrder.fields.QuantityReceived__c.isUpdateable()) {
            return;
        }

        ReturnOrder returnOrderUpdate = new ReturnOrder(
            Id = returnOrderId,
            QuantityReceived__c = quantityReceived
        );
        executeUpdateAsUser(
            Security.stripInaccessible(
                AccessType.UPDATABLE,
                new List<ReturnOrder>{ returnOrderUpdate }
            ).getRecords(),
            'ReturnOrderReceivingController.syncReturnOrderInstrumentQuantityReceived: return order quantity received'
        );
    }

    private static Decimal resolveSummarizedQuantityFromLineInputs(
        List<LineReceiveInput> lineInputs,
        Map<Id, ReturnOrderLineItem> lineItemsById
    ) {
        Decimal totalQuantityReceived = 0;
        for (LineReceiveInput lineInput : lineInputs) {
            if (lineInput.quantityReceived != null) {
                totalQuantityReceived += lineInput.quantityReceived;
                continue;
            }

            ReturnOrderLineItem lineItem = lineItemsById.get(resolveInputLineItemId(lineInput));
            if (lineItem == null) {
                continue;
            }

            Decimal lineQuantityReceived = resolveLineQuantityReceived(
                lineItem,
                RO_TYPE_INSTRUMENTS
            );
            if (lineQuantityReceived != null) {
                totalQuantityReceived += lineQuantityReceived;
            }
        }
        return totalQuantityReceived;
    }

    private static void linkPhotos(BulkReceiveResult result, List<Id> contentDocumentIds) {
        if (
            result == null ||
            result.primaryWorkOrderId == null ||
            contentDocumentIds == null ||
            contentDocumentIds.isEmpty()
        ) {
            return;
        }

        linkPhotosToWorkOrder(result.primaryWorkOrderId, contentDocumentIds);
    }

    private static ReceivingLineRow mapReceivingLineRow(
        ReturnOrderLineItem lineItem,
        String returnOrderType
    ) {
        ReceivingLineRow row = new ReceivingLineRow();
        row.lineItemId = lineItem.Id;
        row.lineNumber = lineItem.ReturnOrderLineItemNumber;
        row.status = lineItem.Status__c;
        row.assetId = lineItem.AssetId;
        row.assetName = lineItem.Asset?.Name;
        row.serialNumber = resolveLineItemSerialNumber(lineItem);
        row.productId = lineItem.Product2Id;
        row.productName = lineItem.Product2?.Name;
        row.productLine = lineItem.ProductLine__c;
        row.hospitalTrayName = lineItem.HospitalReferencedTrayName__c;
        row.itemDescription = lineItem.ItemDescription__c;
        row.quantityReturned = lineItem.QuantityReturned;
        row.quantityReceived = resolveLineQuantityReceived(lineItem, returnOrderType);
        row.selectable = lineItem.Status__c == STATUS_CREATED;
        row.model = lineItem.Model__c;
        row.departmentId = lineItem.Department__c;
        row.lineType = lineItem.LineType__c;
        row.itemType = lineItem.ItemType__c;
        row.rowClass = resolveRowClass(lineItem.Status__c);
        row.contactId = lineItem.Contact__c;
        row.estimateRequired = lineItem.EstimateRequired__c;
        row.estimateContactId = lineItem.EstimateContact__c;
        row.repairWarranty = lineItem.RepairWarranty__c;
        row.warrantyNotes = lineItem.WarrantyNotes__c;
        row.previousReturnOrder = lineItem.PreviousReturnOrder__c;
        row.customerPo = lineItem.CustomerPO__c;
        row.customerReference = lineItem.CustomerReference__c;
        row.reportedProblem = lineItem.ReportedProblem__c;
        row.modRequest = lineItem.ModRequest__c == true;
        row.disinfected = lineItem.Disinfected__c;
        row.isLoanerAsset = lineItem.IsLoanerAsset__c == true;
        row.loanerRequested = lineItem.LoanerRequested__c == true;
        return row;
    }

    private static Decimal resolveInstrumentHeaderQuantityDefault(
        Decimal headerQuantityReceived,
        Decimal summedLineQuantityReceived
    ) {
        if (headerQuantityReceived != null) {
            return headerQuantityReceived;
        }
        return summedLineQuantityReceived != null ? summedLineQuantityReceived : 0;
    }

    private static Decimal resolveLineQuantityReceived(
        ReturnOrderLineItem lineItem,
        String returnOrderType
    ) {
        if (returnOrderType == RO_TYPE_SERIALIZED) {
            return 1;
        }
        if (lineItem.Status__c == STATUS_CREATED) {
            return lineItem.QuantityReturned != null ? lineItem.QuantityReturned : 0;
        }
        if (lineItem.QuantityReceived != null && lineItem.QuantityReceived > 0) {
            return lineItem.QuantityReceived;
        }
        return lineItem.QuantityReturned != null ? lineItem.QuantityReturned : 0;
    }

    private static String resolveReturnOrderType(String returnOrderType) {
        if (String.isBlank(returnOrderType)) {
            return RO_TYPE_SERIALIZED;
        }
        return returnOrderType;
    }

    private static Id resolveRecordTypeId(String returnOrderType) {
        if (returnOrderType == RO_TYPE_INSTRUMENTS) {
            return getRepairCenterInstrumentsRecordTypeId();
        }
        if (returnOrderType == RO_TYPE_OTHER) {
            return getRepairCenterVendorRecordTypeId();
        }
        return getRepairCenterDevicesRecordTypeId();
    }

    private static ReturnOrder queryReturnOrderForReceive(Id returnOrderId) {
        ReturnOrder returnOrder = [
            SELECT
                Id,
                ReturnOrderNumber,
                ReturnOrderType__c,
                AccountId,
                ContactId,
                CaseId,
                DestinationLocationId,
                Status,
                SalesRep__c,
                CustomerPO__c,
                RepairWarranty__c,
                WarrantyNotes__c,
                HospitalReferencedTrayName__c,
                EstimateRequired__c,
                EstimateContact__c,
                PreviousReturnOrder__c,
                CustomerReference__c
            FROM ReturnOrder
            WHERE Id = :returnOrderId
            WITH USER_MODE
            LIMIT 1
        ];
        if (returnOrder.Status == STATUS_CANCELED) {
            throw new AuraHandledException('This return order is canceled.');
        }
        return returnOrder;
    }

    private static Map<Id, ReturnOrderLineItem> queryLineItemsForBulkReceive(
        Id returnOrderId,
        Set<Id> lineItemIds
    ) {
        Map<Id, ReturnOrderLineItem> lineItemsById = new Map<Id, ReturnOrderLineItem>();
        for (ReturnOrderLineItem lineItem : [
            SELECT
                Id,
                ReturnOrderId,
                ReturnOrderLineItemNumber,
                Status__c,
                AssetId,
                Asset.SerialNumber,
                Product2Id,
                ProductLine__c,
                QuantityReturned,
                QuantityReceived,
                HospitalReferencedTrayName__c,
                Model__c,
                CustomerPO__c,
                CustomerReference__c,
                Department__c,
                LineType__c,
                ItemType__c,
                SerialNumber__c,
                Contact__c,
                EstimateRequired__c,
                EstimateContact__c,
                PreviousReturnOrder__c,
                ModRequest__c,
                ReportedProblem__c
            FROM ReturnOrderLineItem
            WHERE ReturnOrderId = :returnOrderId
            AND Id IN :lineItemIds
            WITH USER_MODE
        ]) {
            lineItemsById.put(lineItem.Id, lineItem);
        }
        applyWarrantyFieldsToLineItems(lineItemsById.values(), lineItemIds);
        return lineItemsById;
    }

    private static void applyWarrantyFieldsToLineItems(
        List<ReturnOrderLineItem> lineItems,
        Set<Id> lineItemIds
    ) {
        if (lineItems == null || lineItems.isEmpty() || lineItemIds == null || lineItemIds.isEmpty()) {
            return;
        }
        if (
            !Schema.SObjectType.ReturnOrderLineItem.fields.RepairWarranty__c.isAccessible() &&
            !Schema.SObjectType.ReturnOrderLineItem.fields.WarrantyNotes__c.isAccessible()
        ) {
            return;
        }

        Map<Id, ReturnOrderLineItem> warrantyValuesById = new Map<Id, ReturnOrderLineItem>();
        for (ReturnOrderLineItem warrantyLineItem : [
            SELECT Id, RepairWarranty__c, WarrantyNotes__c
            FROM ReturnOrderLineItem
            WHERE Id IN :lineItemIds
            WITH USER_MODE
        ]) {
            warrantyValuesById.put(warrantyLineItem.Id, warrantyLineItem);
        }

        for (ReturnOrderLineItem lineItem : lineItems) {
            ReturnOrderLineItem warrantyValues = warrantyValuesById.get(lineItem.Id);
            if (warrantyValues == null) {
                continue;
            }
            lineItem.RepairWarranty__c = warrantyValues.RepairWarranty__c;
            lineItem.WarrantyNotes__c = warrantyValues.WarrantyNotes__c;
        }
    }

    private static ReturnOrder queryReturnOrderForValidation(Id returnOrderId) {
        List<ReturnOrder> returnOrders = [
            SELECT Id, Status
            FROM ReturnOrder
            WHERE Id = :returnOrderId
            WITH USER_MODE
            LIMIT 1
        ];
        if (returnOrders.isEmpty()) {
            throw new AuraHandledException('Return order was not found.');
        }
        return returnOrders[0];
    }

    private static Set<Id> extractLineItemIds(List<LineReceiveInput> lineInputs) {
        Set<Id> lineItemIds = new Set<Id>();
        for (LineReceiveInput lineInput : lineInputs) {
            if (isAdHocSerializedLineInput(lineInput)) {
                continue;
            }
            Id lineItemId = resolveInputLineItemId(lineInput);
            if (lineItemId != null) {
                lineItemIds.add(lineItemId);
            }
        }
        return lineItemIds;
    }

    private static Id resolveInputLineItemId(LineReceiveInput lineInput) {
        if (lineInput == null || String.isBlank(lineInput.lineItemId)) {
            return null;
        }

        try {
            return Id.valueOf(lineInput.lineItemId.trim());
        } catch (Exception ex) {
            return null;
        }
    }

    private static List<LineReceiveInput> parseLineInputsFromJson(String lineInputsJson) {
        if (String.isBlank(lineInputsJson)) {
            return new List<LineReceiveInput>();
        }

        try {
            List<Object> rawInputs = (List<Object>) JSON.deserializeUntyped(lineInputsJson);
            List<LineReceiveInput> parsedInputs = new List<LineReceiveInput>();
            for (Object rawInput : rawInputs) {
                if (!(rawInput instanceof Map<String, Object>)) {
                    continue;
                }
                parsedInputs.add(parseLineReceiveInput((Map<String, Object>) rawInput));
            }
            return parsedInputs;
        } catch (Exception ex) {
            throw new AuraHandledException(
                'Unable to read selected line items. Refresh the page and try again.'
            );
        }
    }

    private static LineReceiveInput parseLineReceiveInput(Map<String, Object> inputMap) {
        LineReceiveInput lineInput = new LineReceiveInput();
        lineInput.lineItemId = stringifyInputValue(inputMap.get('lineItemId'));
        lineInput.isAdHocSerializedLine = parseBooleanInputValue(inputMap.get('isAdHocSerializedLine'));
        lineInput.adHocLineKey = stringifyInputValue(inputMap.get('adHocLineKey'));
        lineInput.quantityReceived = parseDecimalInputValue(inputMap.get('quantityReceived'));
        lineInput.quantityReturned = parseDecimalInputValue(inputMap.get('quantityReturned'));
        lineInput.hasCorrections = parseBooleanInputValue(inputMap.get('hasCorrections'));
        lineInput.serialNumber = stringifyInputValue(inputMap.get('serialNumber'));
        lineInput.model = stringifyInputValue(inputMap.get('model'));
        lineInput.productLine = stringifyInputValue(inputMap.get('productLine'));
        lineInput.itemType = stringifyInputValue(inputMap.get('itemType'));
        lineInput.hospitalTrayName = stringifyInputValue(inputMap.get('hospitalTrayName'));
        lineInput.departmentId = parseIdInputValue(inputMap.get('departmentId'));
        lineInput.selectedAssetId = parseIdInputValue(inputMap.get('selectedAssetId'));
        lineInput.productId = parseIdInputValue(inputMap.get('productId'));
        lineInput.accessories = parseAccessoryInputs(inputMap.get('accessories'));
        lineInput.contactId = parseIdInputValue(inputMap.get('contactId'));
        lineInput.estimateRequired = stringifyInputValue(inputMap.get('estimateRequired'));
        lineInput.estimateContactId = parseIdInputValue(inputMap.get('estimateContactId'));
        lineInput.repairWarranty = stringifyInputValue(inputMap.get('repairWarranty'));
        lineInput.warrantyNotes = stringifyInputValue(inputMap.get('warrantyNotes'));
        lineInput.previousReturnOrder = stringifyInputValue(inputMap.get('previousReturnOrder'));
        lineInput.customerPo = stringifyInputValue(inputMap.get('customerPo'));
        lineInput.customerReference = stringifyInputValue(inputMap.get('customerReference'));
        lineInput.reportedProblem = stringifyInputValue(inputMap.get('reportedProblem'));
        lineInput.modRequest = parseBooleanInputValue(inputMap.get('modRequest'));
        lineInput.disinfected = stringifyInputValue(inputMap.get('disinfected'));
        lineInput.isLoanerAsset = parseBooleanInputValue(inputMap.get('isLoanerAsset'));
        lineInput.loanerRequested = parseBooleanInputValue(inputMap.get('loanerRequested'));
        return lineInput;
    }

    private static List<AccessoryInput> parseAccessoryInputs(Object rawAccessories) {
        List<AccessoryInput> accessories = new List<AccessoryInput>();
        if (!(rawAccessories instanceof List<Object>)) {
            return accessories;
        }

        for (Object rawAccessory : (List<Object>) rawAccessories) {
            if (!(rawAccessory instanceof Map<String, Object>)) {
                continue;
            }

            Map<String, Object> accessoryMap = (Map<String, Object>) rawAccessory;
            AccessoryInput accessory = new AccessoryInput();
            accessory.accessoryType = stringifyInputValue(accessoryMap.get('accessoryType'));
            accessory.condition = stringifyInputValue(accessoryMap.get('condition'));
            accessory.storageLocation = stringifyInputValue(accessoryMap.get('storageLocation'));
            accessory.quantity = parseDecimalInputValue(accessoryMap.get('quantity'));

            if (String.isNotBlank(accessory.accessoryType) &&
                String.isNotBlank(accessory.storageLocation)) {
                accessories.add(accessory);
            }
        }

        return accessories;
    }

    private static String stringifyInputValue(Object value) {
        return value == null ? null : String.valueOf(value).trim();
    }

    private static Decimal parseDecimalInputValue(Object value) {
        if (value == null || String.isBlank(String.valueOf(value))) {
            return null;
        }
        return Decimal.valueOf(String.valueOf(value));
    }

    private static Boolean parseBooleanInputValue(Object value) {
        if (value == null) {
            return false;
        }
        if (value instanceof Boolean) {
            return (Boolean) value;
        }
        return 'true'.equalsIgnoreCase(String.valueOf(value));
    }

    private static Id parseIdInputValue(Object value) {
        String stringValue = stringifyInputValue(value);
        if (String.isBlank(stringValue)) {
            return null;
        }
        try {
            return Id.valueOf(stringValue);
        } catch (Exception ex) {
            return null;
        }
    }

    private static void validateBulkReceiveRequest(
        Id returnOrderId,
        Id receiverId,
        Datetime receivedDateTime,
        List<LineReceiveInput> lineInputs
    ) {
        if (returnOrderId == null) {
            throw new AuraHandledException('Return order is required.');
        }
        if (receiverId == null) {
            throw new AuraHandledException('Receiver is required.');
        }
        if (receivedDateTime == null) {
            throw new AuraHandledException('Received date and time is required.');
        }
        if (lineInputs == null || lineInputs.isEmpty()) {
            throw new AuraHandledException('Select at least one line item to receive.');
        }
        for (LineReceiveInput lineInput : lineInputs) {
            if (isAdHocSerializedLineInput(lineInput)) {
                continue;
            }
            if (resolveInputLineItemId(lineInput) == null) {
                throw new AuraHandledException(
                    'Each selected line item must include a valid line item Id.'
                );
            }
        }
    }

    private static void validateLineInputsResolved(
        List<LineReceiveInput> lineInputs,
        Map<Id, ReturnOrderLineItem> lineItemsById,
        String returnOrderType
    ) {
        for (LineReceiveInput lineInput : lineInputs) {
            if (isAdHocSerializedLineInput(lineInput)) {
                if (returnOrderType != RO_TYPE_SERIALIZED) {
                    throw new AuraHandledException(
                        'Ad hoc serialized items can only be received on serialized return orders.'
                    );
                }
                continue;
            }

            Id lineItemId = resolveInputLineItemId(lineInput);
            if (!lineItemsById.containsKey(lineItemId)) {
                throw new AuraHandledException(
                    'Unable to load one or more selected return order line items. Refresh the page and try again.'
                );
            }
        }
    }

    private static void validateAdHocSerializedLineInputs(
        List<LineReceiveInput> lineInputs,
        String returnOrderType
    ) {
        for (LineReceiveInput lineInput : lineInputs) {
            if (!isAdHocSerializedLineInput(lineInput)) {
                continue;
            }
            if (returnOrderType != RO_TYPE_SERIALIZED) {
                throw new AuraHandledException(
                    'Ad hoc serialized items can only be received on serialized return orders.'
                );
            }
            if (String.isBlank(lineInput.serialNumber)) {
                throw new AuraHandledException(
                    'Each ad hoc serialized item must include a serial number.'
                );
            }
            if (String.isBlank(lineInput.model)) {
                throw new AuraHandledException(
                    'Each ad hoc serialized item must include a model.'
                );
            }
        }
    }

    private static Id getRepairCenterDevicesRecordTypeId() {
        return getWorkOrderRecordTypeId(
            WO_RECORD_TYPE_REPAIR_CENTER_DEVICES,
            'Repair Center - Devices work order record type is not available.'
        );
    }

    private static Id getRepairCenterInstrumentsRecordTypeId() {
        return getWorkOrderRecordTypeId(
            WO_RECORD_TYPE_REPAIR_CENTER_INSTRUMENTS,
            'Repair Center - Instruments work order record type is not available.'
        );
    }

    private static Id getRepairCenterVendorRecordTypeId() {
        return getWorkOrderRecordTypeId(
            WO_RECORD_TYPE_REPAIR_CENTER_VENDOR,
            'Repair Center - Vendor work order record type is not available.'
        );
    }

    private static Id getWorkOrderRecordTypeId(String developerName, String unavailableMessage) {
        Schema.RecordTypeInfo recordTypeInfo = Schema.SObjectType.WorkOrder
            .getRecordTypeInfosByDeveloperName()
            .get(developerName);
        if (recordTypeInfo == null || !recordTypeInfo.isAvailable()) {
            throw new AuraHandledException(
                unavailableMessage +
                    ' Ask your administrator to grant access to the Return Order Line Items Access permission set.'
            );
        }
        return recordTypeInfo.getRecordTypeId();
    }

    private static Id resolveLinkedParentWorkOrderId(Id returnOrderId) {
        List<ReturnOrder> returnOrders = [
            SELECT WorkOrder__c
            FROM ReturnOrder
            WHERE Id = :returnOrderId
            WITH USER_MODE
            LIMIT 1
        ];
        return returnOrders.isEmpty() ? null : returnOrders[0].WorkOrder__c;
    }

    private static String resolveLineItemSerialNumber(ReturnOrderLineItem lineItem) {
        if (lineItem.AssetId != null && String.isNotBlank(lineItem.Asset?.SerialNumber)) {
            return lineItem.Asset.SerialNumber;
        }
        return lineItem.SerialNumber__c;
    }

    private static String resolveRowClass(String status) {
        if (status == STATUS_CANCELED) {
            return 'row-canceled';
        }
        if (status == STATUS_RECEIVED) {
            return 'row-received';
        }
        if (status == 'Redirected') {
            return 'row-redirected';
        }
        return '';
    }

    private static String resolveLocationAddress(Id locationId) {
        if (locationId == null) {
            return null;
        }

        try {
            List<SObject> addresses = Database.query(
                'SELECT AddressShipTo__c, Street, City, State, PostalCode, Country ' +
                'FROM Address ' +
                'WHERE ParentId = :locationId ' +
                'WITH USER_MODE ' +
                'LIMIT 1'
            );
            if (!addresses.isEmpty()) {
                SObject addressRecord = addresses[0];
                String formattedShipTo = (String) addressRecord.get('AddressShipTo__c');
                if (String.isNotBlank(formattedShipTo)) {
                    return formattedShipTo;
                }
                return formatAddress(
                    (String) addressRecord.get('Street'),
                    (String) addressRecord.get('City'),
                    (String) addressRecord.get('State'),
                    (String) addressRecord.get('PostalCode'),
                    (String) addressRecord.get('Country')
                );
            }

            List<Schema.Location> locations = [
                SELECT VisitorAddressId
                FROM Location
                WHERE Id = :locationId
                WITH USER_MODE
                LIMIT 1
            ];
            if (locations.isEmpty() || locations[0].VisitorAddressId == null) {
                return null;
            }

            Id visitorAddressId = locations[0].VisitorAddressId;
            List<SObject> visitorAddresses = Database.query(
                'SELECT AddressShipTo__c, Street, City, State, PostalCode, Country ' +
                'FROM Address ' +
                'WHERE Id = :visitorAddressId ' +
                'WITH USER_MODE ' +
                'LIMIT 1'
            );
            if (visitorAddresses.isEmpty()) {
                return null;
            }

            SObject visitorAddress = visitorAddresses[0];
            String formattedShipTo = (String) visitorAddress.get('AddressShipTo__c');
            if (String.isNotBlank(formattedShipTo)) {
                return formattedShipTo;
            }
            return formatAddress(
                (String) visitorAddress.get('Street'),
                (String) visitorAddress.get('City'),
                (String) visitorAddress.get('State'),
                (String) visitorAddress.get('PostalCode'),
                (String) visitorAddress.get('Country')
            );
        } catch (Exception e) {
            return null;
        }
    }

    private static String formatAddress(
        String street,
        String city,
        String state,
        String postalCode,
        String country
    ) {
        List<String> parts = new List<String>();
        if (String.isNotBlank(street)) {
            parts.add(street);
        }
        if (String.isNotBlank(city)) {
            parts.add(city);
        }
        if (String.isNotBlank(state)) {
            parts.add(state);
        }
        if (String.isNotBlank(postalCode)) {
            parts.add(postalCode);
        }
        if (String.isNotBlank(country)) {
            parts.add(country);
        }
        return parts.isEmpty() ? null : String.join(parts, ', ');
    }

    private static ReturnOrder resolveReturnOrderByNumber(String returnOrderNumber) {
        String trimmedNumber = returnOrderNumber?.trim();
        if (String.isBlank(trimmedNumber)) {
            throw new AuraHandledException('Return order number is required.');
        }

        Set<String> candidateNumbers = new Set<String>{ trimmedNumber };
        String upperNumber = trimmedNumber.toUpperCase();
        if (upperNumber.startsWith('RO')) {
            String suffix = trimmedNumber.substring(2).replaceFirst('^[-\\s]+', '');
            if (String.isNotBlank(suffix)) {
                candidateNumbers.add(suffix);
            }
        } else {
            candidateNumbers.add('RO' + trimmedNumber);
            candidateNumbers.add('RO-' + trimmedNumber);
        }

        List<ReturnOrder> returnOrders = [
            SELECT Id, Status, ReturnOrderNumber
            FROM ReturnOrder
            WHERE ReturnOrderNumber IN :candidateNumbers
            WITH USER_MODE
            ORDER BY CreatedDate DESC
        ];
        if (returnOrders.isEmpty()) {
            return null;
        }

        if (returnOrders.size() == 1) {
            return returnOrders[0];
        }

        for (ReturnOrder returnOrder : returnOrders) {
            if (returnOrder.ReturnOrderNumber == trimmedNumber) {
                return returnOrder;
            }
        }
        return returnOrders[0];
    }

    private static String validateReturnOrderForReceiving(
        Id returnOrderId,
        String returnOrderStatus
    ) {
        if (returnOrderStatus == STATUS_CANCELED) {
            throw new AuraHandledException(
                'This return order is canceled. Enter another return order number.'
            );
        }

        List<ReturnOrderLineItem> openLineItems = [
            SELECT Id
            FROM ReturnOrderLineItem
            WHERE ReturnOrderId = :returnOrderId
            AND Status__c = :STATUS_CREATED
            WITH USER_MODE
            LIMIT 1
        ];
        if (openLineItems.isEmpty()) {
            throw new AuraHandledException(
                'This return order has no open line items. Enter another return order number.'
            );
        }

        return returnOrderId;
    }

    private static String buildAccountAssetLabel(
        String assetName,
        String productName,
        String model
    ) {
        List<String> parts = new List<String>();
        if (String.isNotBlank(assetName)) {
            parts.add(assetName.trim());
        }
        if (String.isNotBlank(productName)) {
            parts.add(productName.trim());
        }
        if (String.isNotBlank(model)) {
            parts.add(model.trim());
        }
        return parts.isEmpty() ? '' : String.join(parts, ' · ');
    }

    private static Boolean isIntegrationUser(String profileName) {
        if (String.isBlank(profileName)) {
            return false;
        }
        for (String keyword : INTEGRATION_PROFILE_KEYWORDS) {
            if (profileName.contains(keyword)) {
                return true;
            }
        }
        return false;
    }

    private static ReturnOrderLineItem queryLineItemForRedirectClone(Id lineItemId) {
        return [
            SELECT
                Id,
                ReturnOrderId,
                Status__c,
                AssetId,
                Product2Id,
                ProductLine__c,
                LineType__c,
                QuantityReturned,
                CustomerPO__c,
                CustomerReference__c,
                Contact__c,
                Department__c,
                Description,
                Model__c,
                ReportedProblem__c,
                IsLoanerAsset__c,
                LoanerRequested__c,
                EstimateRequired__c,
                Disinfected__c,
                DestinationLocationId,
                SourceLocationId,
                QuantityExpected,
                QuantityUnitOfMeasure,
                ReasonForReturn,
                RepaymentMethod,
                ProcessingPlan,
                HospitalReferencedTrayName__c
            FROM ReturnOrderLineItem
            WHERE Id = :lineItemId
            WITH USER_MODE
            LIMIT 1
        ];
    }

    private static ReturnOrder queryReturnOrderForRedirectClone(Id returnOrderId) {
        return [
            SELECT
                Id,
                AccountId,
                CaseId,
                ContactId,
                OrderId,
                OperatingUnit__c,
                CreationSource__c,
                SalesRep__c,
                WorkOrder__c,
                ReturnOrderType__c,
                SourceLocationId,
                DestinationLocationId,
                Description,
                ShipmentType,
                ExpectedArrivalDate,
                ExpirationDate,
                ProductRequestId,
                ProductServiceCampaignId,
                ReturnedById,
                CreatedByContact__c
            FROM ReturnOrder
            WHERE Id = :returnOrderId
            WITH USER_MODE
            LIMIT 1
        ];
    }

    private static ReturnOrder cloneRedirectReturnOrder(ReturnOrder source, Id repairCenterId) {
        ReturnOrder target = new ReturnOrder();
        target.AccountId = source.AccountId;
        target.CaseId = source.CaseId;
        target.ContactId = source.ContactId;
        target.OrderId = source.OrderId;
        target.OperatingUnit__c = source.OperatingUnit__c;
        target.CreationSource__c = source.CreationSource__c;
        target.SalesRep__c = source.SalesRep__c;
        target.WorkOrder__c = source.WorkOrder__c;
        target.ReturnOrderType__c = source.ReturnOrderType__c;
        target.SourceLocationId = source.SourceLocationId;
        target.Description = source.Description;
        target.ShipmentType = source.ShipmentType;
        target.ExpectedArrivalDate = source.ExpectedArrivalDate;
        target.ExpirationDate = source.ExpirationDate;
        target.ProductRequestId = source.ProductRequestId;
        target.ProductServiceCampaignId = source.ProductServiceCampaignId;
        target.ReturnedById = source.ReturnedById;
        target.CreatedByContact__c = source.CreatedByContact__c;
        target.DestinationLocationId = repairCenterId;
        target.Status = STATUS_CREATED;
        return target;
    }

    private static ReturnOrder insertRedirectReturnOrder(
        ReturnOrder sourceReturnOrder,
        Id repairCenterId
    ) {
        ReturnOrder newReturnOrder = cloneRedirectReturnOrder(sourceReturnOrder, repairCenterId);
        List<SObject> insertableReturnOrders = Security.stripInaccessible(
            AccessType.CREATABLE,
            new List<ReturnOrder>{ newReturnOrder }
        ).getRecords();
        if (insertableReturnOrders.isEmpty()) {
            throw new AuraHandledException(
                'Unable to create return order due to field access restrictions.'
            );
        }
        executeInsertAsUser(
            insertableReturnOrders,
            'ReturnOrderReceivingController.insertRedirectReturnOrder: redirected return order'
        );
        Id returnOrderId = insertableReturnOrders[0].Id;
        List<ReturnOrder> insertedReturnOrders = [
            SELECT Id, ReturnOrderNumber
            FROM ReturnOrder
            WHERE Id = :returnOrderId
            LIMIT 1
        ];
        if (insertedReturnOrders.isEmpty()) {
            throw new AuraHandledException(
                'Unable to read redirected return order after insert.'
            );
        }
        return insertedReturnOrders[0];
    }

    private static RedirectActionResult processBulkRedirect(
        ReturnOrder sourceReturnOrder,
        Id repairCenterId
    ) {
        List<ReturnOrderLineItem> openLineItems = [
            SELECT
                Id,
                ReturnOrderId,
                Status__c,
                AssetId,
                Product2Id,
                ProductLine__c,
                LineType__c,
                QuantityReturned,
                CustomerPO__c,
                CustomerReference__c,
                Contact__c,
                Department__c,
                Description,
                Model__c,
                ReportedProblem__c,
                IsLoanerAsset__c,
                LoanerRequested__c,
                EstimateRequired__c,
                Disinfected__c,
                DestinationLocationId,
                SourceLocationId,
                QuantityExpected,
                QuantityUnitOfMeasure,
                ReasonForReturn,
                RepaymentMethod,
                ProcessingPlan,
                HospitalReferencedTrayName__c
            FROM ReturnOrderLineItem
            WHERE ReturnOrderId = :sourceReturnOrder.Id
            AND Status__c = :STATUS_CREATED
            WITH USER_MODE
        ];
        if (openLineItems.isEmpty()) {
            throw new AuraHandledException(
                'This return order has no open line items to redirect.'
            );
        }

        ReturnOrder insertedReturnOrder = insertRedirectReturnOrder(sourceReturnOrder, repairCenterId);
        List<ReturnOrderLineItem> clonedLineItems = new List<ReturnOrderLineItem>();
        List<ReturnOrderLineItem> redirectedSourceLineItems = new List<ReturnOrderLineItem>();
        for (ReturnOrderLineItem sourceLineItem : openLineItems) {
            clonedLineItems.add(
                cloneRedirectLineItem(
                    sourceLineItem,
                    insertedReturnOrder.Id,
                    STATUS_CREATED,
                    sourceLineItem.Id
                )
            );
            redirectedSourceLineItems.add(
                new ReturnOrderLineItem(
                    Id = sourceLineItem.Id,
                    Status__c = STATUS_REDIRECTED
                )
            );
        }

        executeInsertAsUser(
            Security.stripInaccessible(
                AccessType.CREATABLE,
                clonedLineItems
            ).getRecords(),
            'ReturnOrderReceivingController.processBulkRedirect: cloned line items'
        );
        executeUpdateAsUser(
            Security.stripInaccessible(
                AccessType.UPDATABLE,
                redirectedSourceLineItems
            ).getRecords(),
            'ReturnOrderReceivingController.processBulkRedirect: source line item status'
        );

        sourceReturnOrder.Status = STATUS_REDIRECTED;
        executeUpdateAsUser(
            Security.stripInaccessible(
                AccessType.UPDATABLE,
                new List<ReturnOrder>{ sourceReturnOrder }
            ).getRecords(),
            'ReturnOrderReceivingController.processBulkRedirect: source return order status'
        );

        RedirectActionResult result = new RedirectActionResult();
        result.returnOrderId = insertedReturnOrder.Id;
        result.returnOrderNumber = insertedReturnOrder.ReturnOrderNumber;
        return result;
    }

    private static ReturnOrderLineItem cloneRedirectLineItem(
        ReturnOrderLineItem source,
        Id returnOrderId,
        String status,
        Id parentRoliId
    ) {
        ReturnOrderLineItem target = new ReturnOrderLineItem();
        target.ReturnOrderId = returnOrderId;
        target.Status__c = status;
        target.ParentROLI__c = parentRoliId;
        target.AssetId = source.AssetId;
        target.Product2Id = source.Product2Id;
        target.ProductLine__c = source.ProductLine__c;
        target.LineType__c = source.LineType__c;
        target.QuantityReturned = source.QuantityReturned;
        target.CustomerPO__c = source.CustomerPO__c;
        target.CustomerReference__c = source.CustomerReference__c;
        target.Contact__c = source.Contact__c;
        target.Department__c = source.Department__c;
        target.Description = source.Description;
        target.Model__c = source.Model__c;
        target.ReportedProblem__c = source.ReportedProblem__c;
        target.IsLoanerAsset__c = source.IsLoanerAsset__c;
        target.LoanerRequested__c = source.LoanerRequested__c;
        target.EstimateRequired__c = source.EstimateRequired__c;
        target.Disinfected__c = source.Disinfected__c;
        target.DestinationLocationId = source.DestinationLocationId;
        target.SourceLocationId = source.SourceLocationId;
        target.QuantityExpected = source.QuantityExpected;
        target.QuantityUnitOfMeasure = source.QuantityUnitOfMeasure;
        target.ReasonForReturn = source.ReasonForReturn;
        target.RepaymentMethod = source.RepaymentMethod;
        target.ProcessingPlan = source.ProcessingPlan;
        target.HospitalReferencedTrayName__c = source.HospitalReferencedTrayName__c;
        return target;
    }

    private static List<WorkOrder> insertWorkOrdersAsUser(List<WorkOrder> insertableWorkOrders) {
        if (insertableWorkOrders == null || insertableWorkOrders.isEmpty()) {
            return insertableWorkOrders;
        }
        executeInsertAsUser(
            insertableWorkOrders,
            'ReturnOrderReceivingController.insertWorkOrdersAsUser: work orders'
        );
        processCustomerCareForInsertedWorkOrders(insertableWorkOrders);
        return insertableWorkOrders;
    }

    private static void processCustomerCareForInsertedWorkOrders(List<WorkOrder> insertedWorkOrders) {
        if (insertedWorkOrders == null || insertedWorkOrders.isEmpty()) {
            return;
        }

        Set<Id> customerCareWorkOrderIds = new Set<Id>();
        for (WorkOrder workOrder : insertedWorkOrders) {
            if (
                workOrder.SubStatus__c == WO_SUB_STATUS_CUSTOMER_CARE &&
                workOrder.CaseId == null &&
                workOrder.Id != null
            ) {
                customerCareWorkOrderIds.add(workOrder.Id);
            }
        }

        if (!customerCareWorkOrderIds.isEmpty()) {
            new CustomerCareCaseHandler().createCasesAndNotifyQueue(customerCareWorkOrderIds);
        }
    }

    private static void executeInsertAsUser(List<SObject> records, String logContext) {
        if (records == null || records.isEmpty()) {
            return;
        }
        try {
            insert as user records;
        } catch (Exception e) {
            Logger.newEntry(LoggingLevel.ERROR, logContext).setExceptionDetails(e);
            throw e;
        } finally {
            saveDmlLogs();
        }
    }

    private static void executeUpdateAsUser(List<SObject> records, String logContext) {
        if (records == null || records.isEmpty()) {
            return;
        }
        try {
            update as user records;
        } catch (Exception e) {
            Logger.newEntry(LoggingLevel.ERROR, logContext).setExceptionDetails(e);
            throw e;
        } finally {
            saveDmlLogs();
        }
    }

    private static void saveDmlLogs() {
        try {
            Logger.saveLog();
        } catch (Exception logException) {
            System.debug(
                LoggingLevel.WARN,
                'ReturnOrderReceivingController: unable to persist Nebula Logger entries: '
                    + logException.getMessage()
            );
        }
    }

    /**
     * Elevated query/DML for receive steps that must succeed when the running user
     * only has Account Read sharing (Asset Controlled by Parent) or cannot see
     * Customer Care Cases owned by queue.
     */
    private without sharing class ElevatedAccessService {
        void updateAssetForReceivingCorrection(
            Id assetId,
            String serialNumber,
            Id departmentId
        ) {
            if (assetId == null) {
                return;
            }

            Asset asset = [
                SELECT Id, SerialNumber, Department__c
                FROM Asset
                WHERE Id = :assetId
                LIMIT 1
            ];
            asset.SerialNumber = serialNumber;
            asset.Department__c = departmentId;
            updateRecords(
                new List<Asset>{ asset },
                'ReturnOrderReceivingController.ElevatedAccessService.updateAssetForReceivingCorrection'
            );
        }

        void insertRecords(List<SObject> records, String logContext) {
            if (records == null || records.isEmpty()) {
                return;
            }
            try {
                insert records;
            } catch (Exception e) {
                Logger.newEntry(LoggingLevel.ERROR, logContext).setExceptionDetails(e);
                throw e;
            } finally {
                saveDmlLogs();
            }
        }

        void updateRecords(List<SObject> records, String logContext) {
            if (records == null || records.isEmpty()) {
                return;
            }
            try {
                update records;
            } catch (Exception e) {
                Logger.newEntry(LoggingLevel.ERROR, logContext).setExceptionDetails(e);
                throw e;
            } finally {
                saveDmlLogs();
            }
        }
    }

    private without sharing class CustomerCareCaseHandler {
        void createCasesAndNotifyQueue(Set<Id> workOrderIds) {
            if (customerCareProcessing || workOrderIds == null || workOrderIds.isEmpty()) {
                return;
            }

            customerCareProcessing = true;
            try {
                List<WorkOrder> workOrders = [
                    SELECT
                        Id,
                        WorkOrderNumber,
                        Subject,
                        AccountId,
                        ContactId,
                        AssetId,
                        ReturnOrder__c
                    FROM WorkOrder
                    WHERE Id IN :workOrderIds
                ];

                if (workOrders.isEmpty()) {
                    return;
                }

                Id recordTypeId = resolveInboxSupportRecordTypeId();
                Id queueId = resolveCustomerCareQueueId();
                Id businessHoursId = resolveDefaultBusinessHoursId();

                List<Case> casesToInsert = new List<Case>();
                for (WorkOrder workOrder : workOrders) {
                    casesToInsert.add(
                        buildCustomerCareCase(workOrder, recordTypeId, queueId, businessHoursId)
                    );
                }

                ElevatedAccessService elevatedAccess = new ElevatedAccessService();
                elevatedAccess.insertRecords(
                    casesToInsert,
                    'ReturnOrderReceivingController.CustomerCareCaseHandler.createCasesAndNotifyQueue: customer care cases'
                );

                List<WorkOrder> workOrderUpdates = new List<WorkOrder>();
                for (Integer index = 0; index < workOrders.size(); index++) {
                    workOrderUpdates.add(
                        new WorkOrder(
                            Id = workOrders[index].Id,
                            CaseId = casesToInsert[index].Id
                        )
                    );
                }
                elevatedAccess.updateRecords(
                    workOrderUpdates,
                    'ReturnOrderReceivingController.CustomerCareCaseHandler.createCasesAndNotifyQueue: work order case links'
                );

                notifyQueueForWorkOrders(workOrders, queueId);
            } finally {
                customerCareProcessing = false;
            }
        }

        private Case buildCustomerCareCase(
            WorkOrder workOrder,
            Id recordTypeId,
            Id queueId,
            Id businessHoursId
        ) {
            Case customerCareCase = new Case();
            customerCareCase.RecordTypeId = recordTypeId;
            customerCareCase.OwnerId = queueId;
            customerCareCase.AccountId = workOrder.AccountId;
            customerCareCase.ContactId = workOrder.ContactId;
            customerCareCase.AssetId = workOrder.AssetId;
            customerCareCase.Status = CASE_STATUS_NEW;
            customerCareCase.Origin = CASE_ORIGIN_CENTRAL_REPAIR_SUPPORT;
            customerCareCase.BusinessHoursId = businessHoursId;
            customerCareCase.Subject = buildCaseSubject(workOrder);
            customerCareCase.Description = buildCaseDescription(workOrder);
            return customerCareCase;
        }

        private String buildCaseSubject(WorkOrder workOrder) {
            String workOrderLabel = String.isNotBlank(workOrder.WorkOrderNumber)
                ? workOrder.WorkOrderNumber
                : String.valueOf(workOrder.Id);
            return 'Customer Care - Work Order ' + workOrderLabel;
        }

        private String buildCaseDescription(WorkOrder workOrder) {
            List<String> descriptionLines = new List<String>{
                'A work order was created with Customer Care sub status.'
            };

            if (String.isNotBlank(workOrder.WorkOrderNumber)) {
                descriptionLines.add('Work Order Number: ' + workOrder.WorkOrderNumber);
            }
            if (String.isNotBlank(workOrder.Subject)) {
                descriptionLines.add('Work Order Subject: ' + workOrder.Subject);
            }
            if (workOrder.ReturnOrder__c != null) {
                descriptionLines.add('Return Order Id: ' + workOrder.ReturnOrder__c);
            }

            return String.join(descriptionLines, '\n');
        }

        private void notifyQueueForWorkOrders(List<WorkOrder> workOrders, Id queueId) {
            Id notificationTypeId = resolveCustomerCareNotificationTypeId();
            if (notificationTypeId == null || queueId == null) {
                return;
            }

            for (WorkOrder workOrder : workOrders) {
                sendQueueNotification(notificationTypeId, queueId, workOrder);
            }
        }

        private void sendQueueNotification(
            Id notificationTypeId,
            Id queueId,
            WorkOrder workOrder
        ) {
            try {
                String workOrderLabel = String.isNotBlank(workOrder.WorkOrderNumber)
                    ? workOrder.WorkOrderNumber
                    : String.valueOf(workOrder.Id);

                Messaging.CustomNotification notification = new Messaging.CustomNotification();
                notification.setTitle('New Customer Care Work Order');
                notification.setBody(
                    'Work Order ' +
                        workOrderLabel +
                        ' was created with Customer Care sub status.'
                );
                notification.setNotificationTypeId(notificationTypeId);
                notification.setTargetId(workOrder.Id);
                notification.send(new Set<String>{ String.valueOf(queueId) });
            } catch (Exception ex) {
                System.debug(
                    LoggingLevel.ERROR,
                    'Failed to send Customer Care queue notification for Work Order ' +
                        workOrder.Id +
                        ': ' +
                        ex.getMessage()
                );
            }
        }

        private Id resolveInboxSupportRecordTypeId() {
            if (customerCareInboxSupportRecordTypeId != null) {
                return customerCareInboxSupportRecordTypeId;
            }

            List<RecordType> recordTypes = [
                SELECT Id
                FROM RecordType
                WHERE SobjectType = 'Case'
                AND DeveloperName = :CASE_RECORD_TYPE_INBOX_SUPPORT
                LIMIT 1
            ];
            if (recordTypes.isEmpty()) {
                throw new AuraHandledException(
                    'Unable to create Customer Care case: Inbox Support record type was not found.'
                );
            }

            customerCareInboxSupportRecordTypeId = recordTypes[0].Id;
            return customerCareInboxSupportRecordTypeId;
        }

        private Id resolveCustomerCareQueueId() {
            if (customerCareQueueIdCache != null) {
                return customerCareQueueIdCache;
            }

            List<Group> queues = [
                SELECT Id
                FROM Group
                WHERE Type = 'Queue'
                AND DeveloperName = :CUSTOMER_CARE_QUEUE_DEVELOPER_NAME
                LIMIT 1
            ];
            if (queues.isEmpty()) {
                throw new AuraHandledException(
                    'Unable to create Customer Care case: Q-NA-IMS-CustCare-Central Support queue was not found.'
                );
            }

            customerCareQueueIdCache = queues[0].Id;
            return customerCareQueueIdCache;
        }

        private Id resolveDefaultBusinessHoursId() {
            if (customerCareDefaultBusinessHoursId != null) {
                return customerCareDefaultBusinessHoursId;
            }

            List<BusinessHours> businessHours = [
                SELECT Id
                FROM BusinessHours
                WHERE IsDefault = TRUE
                LIMIT 1
            ];
            if (businessHours.isEmpty()) {
                throw new AuraHandledException(
                    'Unable to create Customer Care case: default business hours were not found.'
                );
            }

            customerCareDefaultBusinessHoursId = businessHours[0].Id;
            return customerCareDefaultBusinessHoursId;
        }

        private Id resolveCustomerCareNotificationTypeId() {
            if (customerCareNotificationTypeId != null) {
                return customerCareNotificationTypeId;
            }

            List<CustomNotificationType> notificationTypes = [
                SELECT Id
                FROM CustomNotificationType
                WHERE DeveloperName = :CUSTOMER_CARE_NOTIFICATION_DEVELOPER_NAME
                LIMIT 1
            ];
            customerCareNotificationTypeId = notificationTypes.isEmpty()
                ? null
                : notificationTypes[0].Id;
            return customerCareNotificationTypeId;
        }
    }
}