/**
 * @description Controller for the Create Return Order LWC wizard (GW-1509).
 */
public with sharing class CreateReturnOrderController {

    private static final String STATUS_CREATED = 'Created';
    private static final String LOCATION_TYPE_REPAIR_CENTER = 'Repair Center';
    private static final Set<String> CLOSED_RETURN_ORDER_STATUSES = new Set<String>{
        'Canceled',
        'Closed'
    };
    private static final String UNASSIGNED_REPAIR_CENTER_GROUP = 'UNASSIGNED';
    private static final String NON_STERILIZED_GROUP_SUFFIX = '|NOSTERIL';
    private static final String MOD_REQUEST_GROUP_SUFFIX = '|MODREQUEST';
    private static final String MAX_ITEMS_GROUP_SUFFIX = '|MAXITEMS';
    private static final String PRODUCT_LINE_GROUP_SUFFIX = '|PRODUCTLINE|';
    private static final String SHIP_TO_GROUP_SUFFIX = '|SHIPTO|';
    private static final String CUSTOMER_PO_GROUP_SUFFIX = '|CUSTOMERPO|';
    private static final String UNSPECIFIED_SPLIT_SEGMENT = 'UNSPECIFIED';
    private static final String FLEXIBLE_SCOPE_PRODUCT_LINE = 'FLEXIBLE SCOPE';
    private static final Set<String> DISINFECTED_NO_VALUES = new Set<String>{
        'No, items has not been cleaned and disinfected or Sterilized',
        'No, Item is not Disinfected'
    };
    private static final String INSTRUMENT_PRODUCT_LINE = 'INSTRUMENT';
    private static final String DEFAULT_PRODUCT_NAME = 'Default Product';
    private static final String YES_NO_DEFAULT = 'No';
    private static final Decimal QUANTITY_RETURNED_DEFAULT = 1;
    private static final String ROLI_LINE_TYPE_SERIALIZED = 'Serialized';
    private static final String ROLI_LINE_TYPE_INSTRUMENT = 'Instrument';
    private static final String ROLI_LINE_TYPE_OTHER_SERIALIZED = 'Other (Serialized)';
    private static final String ROLI_LINE_TYPE_OTHER_NON_SERIALIZED = 'Other (Non-Serialized)';
    private static final String RETURN_ORDER_TYPE_SERIALIZED = 'Serialized';
    private static final String RETURN_ORDER_TYPE_INSTRUMENTS = 'Instruments';
    private static final String RETURN_ORDER_TYPE_OTHER_SERIALIZED = 'Other (Serialized)';
    private static final String RETURN_ORDER_TYPE_OTHER_NON_SERIALIZED = 'Other (Non-Serialized)';
    private static final String RETURN_ORDER_GROUP_KEY_DELIMITER = '::';
    private static final String ESTIMATE_REQUIRED_QUOTE_VALUE = 'Estimate Required';
    private static final String RETURN_ORDER_TYPE_FIELD = 'ReturnOrderType__c';
    private static final String STIRRUP_ITEM_TYPE = 'Stirrup';
    private static final String STIRRUP_GROUP_SUFFIX = '|STIRRUP|';
    private static final String ENDOCAM_ITEM_TYPE = 'Endocam';

    /**
     * @description Picklist option for LWC comboboxes.
     */
    public class PicklistOption {
        @AuraEnabled public String label;
        @AuraEnabled public String value;
    }

    /**
     * @description Launch context resolved from record, list selection, or home page.
     */
    public class InitContext {
        @AuraEnabled public String accountId;
        @AuraEnabled public String accountName;
        @AuraEnabled public String caseId;
        @AuraEnabled public String caseLabel;
        @AuraEnabled public Boolean lockCase;
        @AuraEnabled public Boolean lockAccount;
        @AuraEnabled public String workOrderId;
        @AuraEnabled public String workOrderLabel;
        @AuraEnabled public Boolean lockWorkOrder;
        @AuraEnabled public String contactId;
        @AuraEnabled public String contactName;
        @AuraEnabled public Boolean lockContact;
        @AuraEnabled public List<String> assetIds;
        @AuraEnabled public String legacyCustomerId;
        @AuraEnabled public String defaultOperatingUnit;
        @AuraEnabled public List<PicklistOption> operatingUnitOptions;
        @AuraEnabled public List<PicklistOption> creationSourceOptions;
        @AuraEnabled public List<PicklistOption> disinfectedOptions;
        @AuraEnabled public List<PicklistOption> itemTypeOptions;
        @AuraEnabled public List<PicklistOption> estimateRequiredOptions;
        @AuraEnabled public Map<String, String> itemTypeToProductLine;
        @AuraEnabled public Map<String, String> itemTypeToROCategory;
        @AuraEnabled public String defaultProductId;
    }

    /**
     * @description Repair center location option (avoids System.Location name clash).
     */
    public class LocationOption {
        @AuraEnabled public String id;
        @AuraEnabled public String name;
    }

    /**
     * @description GW-5320 - Ship-To Address account option for Create Return Order.
     */
    public class ShipToAddressOption {
        @AuraEnabled public String id;
        @AuraEnabled public String name;
        @AuraEnabled public String status;
        @AuraEnabled public String addressDisplay;
        @AuraEnabled public Boolean isPrimary;
        @AuraEnabled public String label;
    }

    /**
     * @description Asset row data for return order lines.
     */
    public class AssetLineData {
        @AuraEnabled public String id;
        @AuraEnabled public String serialNumber;
        @AuraEnabled public String model;
        @AuraEnabled public String make;
        @AuraEnabled public String departmentId;
        @AuraEnabled public String product2Id;
        @AuraEnabled public String productLine;
        @AuraEnabled public String productName;
    }

/**
     * @description Instrument line prefilled from a child work order line (GW-1353).
     */
    public class SiteVisitInstrumentLine {
        @AuraEnabled public String workOrderLineItemId;
        @AuraEnabled public String product2Id;
        @AuraEnabled public String productName;
        @AuraEnabled public String itemDescription;
        @AuraEnabled public String serialNumber;
        @AuraEnabled public String model;
        @AuraEnabled public String departmentId;
        @AuraEnabled public String reportedProblem;
        @AuraEnabled public Boolean additionalServices;
        @AuraEnabled public String insulationPowderCoating;
        @AuraEnabled public Decimal quantityReturned;
    }

    /**
     * @description Asset match returned from serial scan search.
     */
    public class ScanSerialAssetResult {
        @AuraEnabled public String id;
        @AuraEnabled public String serialNumber;
        @AuraEnabled public String model;
        @AuraEnabled public String departmentId;
        @AuraEnabled public String product2Id;
        @AuraEnabled public String productLine;
        @AuraEnabled public String productName;
        @AuraEnabled public String accountId;
        @AuraEnabled public String accountName;
    }

    /**
     * @description Whether an account has the header data required to start a return order line.
     */
    public class AccountReadinessResult {
        @AuraEnabled public Boolean isReady;
        @AuraEnabled public List<String> missingFields;
        @AuraEnabled public String accountId;
        @AuraEnabled public String accountName;
        @AuraEnabled public String operatingUnit;
        @AuraEnabled public String message;
    }

    /**
     * @description Product option for return order line product picklists.
     */
    public class ProductPicklistOption {
        @AuraEnabled public String value;
        @AuraEnabled public String label;
        @AuraEnabled public String name;
        @AuraEnabled public String productCode;
        @AuraEnabled public String model;
        @AuraEnabled public String description;
    }

    /**
     * @description Result of return order creation.
     */
    public class CreateResult {
        @AuraEnabled public String returnOrderId;
        @AuraEnabled public String returnOrderNumber;
        @AuraEnabled public String returnOrderType;
        @AuraEnabled public String repairCenterName;
        @AuraEnabled public Integer lineCount;
    }

    /**
     * @description Summary line shown on the review screen before create.
     */
    public class ProposedReturnOrderLineSummary {
        @AuraEnabled public String lineKey;
        @AuraEnabled public String serialNumber;
        @AuraEnabled public String model;
        @AuraEnabled public String itemDescription;
        @AuraEnabled public String productLine;
        @AuraEnabled public String contactName;
        @AuraEnabled public String departmentName;
        @AuraEnabled public Decimal quantityReturned;
        @AuraEnabled public String reportedProblem;
    }

    /**
     * @description Proposed return order grouped by repair center routing.
     */
    public class ProposedReturnOrderGroup {
        @AuraEnabled public String groupKey;
        @AuraEnabled public String returnOrderType;
        @AuraEnabled public String repairCenterId;
        @AuraEnabled public String repairCenterName;
        @AuraEnabled public Boolean requiresRepairCenterSelection;
        @AuraEnabled public Integer lineCount;
        @AuraEnabled public List<ProposedReturnOrderLineSummary> lineSummaries;
        @AuraEnabled public String lineItemsJson;
    }

    /**
     * @description Result of creating multiple return orders from the summary screen.
     */
    public class CreateOrdersResult {
        @AuraEnabled public List<CreateResult> returnOrders;
    }

    /**
     * @description Routing validation result for line items before summary.
     */
    public class LineRoutingValidation {
        @AuraEnabled public Boolean isValid;
        @AuraEnabled public List<String> messages;
    }

    /**
     * @description Result of inline contact creation on a return order line.
     */
    public class CreateContactResult {
        @AuraEnabled public String contactId;
        @AuraEnabled public String contactName;
        @AuraEnabled public String contactEmail;
    }

    /**
     * @description Open return order matched to an asset on an existing line.
     */
    public class OpenReturnOrderMatch {
        @AuraEnabled public String returnOrderId;
        @AuraEnabled public String returnOrderNumber;
        @AuraEnabled public String status;
    }

    /**
     * @description Result of duplicate open return order check for an asset.
     */
    public class AssetReturnOrderCheckResult {
        @AuraEnabled public Boolean hasOpenReturnOrders;
        @AuraEnabled public List<OpenReturnOrderMatch> returnOrders;
    }

    @AuraEnabled
    public static AssetReturnOrderCheckResult checkOpenReturnOrdersForAsset(Id assetId) {
        try {
            AssetReturnOrderCheckResult result = new AssetReturnOrderCheckResult();
            result.hasOpenReturnOrders = false;
            result.returnOrders = new List<OpenReturnOrderMatch>();

            if (assetId == null) {
                return result;
            }

            Map<Id, OpenReturnOrderMatch> matchesByReturnOrderId = new Map<Id, OpenReturnOrderMatch>();
            // List query (not SOQL for-loop): multiple binds in a for-loop SOQL can throw tmpVar1.
            List<ReturnOrderLineItem> openLineItems = [
                SELECT
                    ReturnOrderId,
                    ReturnOrder.ReturnOrderNumber,
                    ReturnOrder.Status
                FROM ReturnOrderLineItem
                WHERE AssetId = :assetId
                AND ReturnOrder.Status NOT IN :CLOSED_RETURN_ORDER_STATUSES
                WITH USER_MODE
                ORDER BY ReturnOrder.ReturnOrderNumber ASC NULLS LAST
            ];
            for (ReturnOrderLineItem lineItem : openLineItems) {
                if (lineItem.ReturnOrderId == null) {
                    continue;
                }

                if (!matchesByReturnOrderId.containsKey(lineItem.ReturnOrderId)) {
                    OpenReturnOrderMatch match = new OpenReturnOrderMatch();
                    match.returnOrderId = lineItem.ReturnOrderId;
                    match.returnOrderNumber = lineItem.ReturnOrder.ReturnOrderNumber;
                    match.status = lineItem.ReturnOrder.Status;
                    matchesByReturnOrderId.put(lineItem.ReturnOrderId, match);
                }
            }

            result.returnOrders = matchesByReturnOrderId.values();
            result.hasOpenReturnOrders = !result.returnOrders.isEmpty();
            return result;
        } catch (Exception e) {
            throw new AuraHandledException(
                'Error checking open return orders for asset: ' + e.getMessage()
            );
        }
    }

    @AuraEnabled(cacheable=true)
    public static InitContext getInitialContext(String recordId, String objectApiName, List<String> recordIds) {
        try {
            InitContext ctx = new InitContext();
            ctx.assetIds = new List<String>();
            ctx.lockCase = false;
            ctx.lockAccount = false;
            ctx.lockWorkOrder = false;
            ctx.lockContact = false;
            ctx.operatingUnitOptions = getOperatingUnitPicklistOptions();
            ctx.creationSourceOptions = getPicklistOptions(
                ReturnOrder.CreationSource__c.getDescribe()
            );
            ctx.disinfectedOptions = getDisinfectedPicklistOptions();
            ctx.itemTypeOptions = getItemTypePicklistOptions();
            ctx.estimateRequiredOptions = getEstimateRequiredPicklistOptions();
            ctx.itemTypeToProductLine = getItemTypeToProductLineMappings();
            ctx.itemTypeToROCategory = getItemTypeToROCategoryMappings();
            ctx.defaultProductId = resolveDefaultProductId();

            List<String> selectedIds = normalizeRecordIds(recordIds);
            String sObjectName = resolveSObjectName(recordId, objectApiName, selectedIds);

            if (String.isNotBlank(sObjectName)) {
                resolveContextFromObject(ctx, recordId, sObjectName, selectedIds);
            } else if (!selectedIds.isEmpty()) {
                resolveContextFromAssets(ctx, selectedIds);
            }

            if (String.isNotBlank(ctx.accountId)) {
                populateAccountDefaults(ctx, ctx.accountId);
            }

            return ctx;
        } catch (Exception e) {
            throw new AuraHandledException('Error resolving launch context: ' + e.getMessage());
        }
    }

    @AuraEnabled(cacheable=true)
    public static Account getAccountDetails(Id accountId) {
        try {
            if (accountId == null) {
                return null;
            }

            List<Account> accounts = [
                SELECT
                    Id,
                    Name,
                    SystemID__c,
                    OrgIDs__c,
                    BillingState
                FROM Account
                WHERE Id = :accountId
                WITH USER_MODE
                LIMIT 1
            ];
            return accounts.isEmpty() ? null : accounts[0];
        } catch (Exception e) {
            throw new AuraHandledException('Error retrieving account: ' + e.getMessage());
        }
    }

    /**
     * @description GW-5320 - Ship-To Address accounts for the Return Order customer.
     * @param accountId Customer Account Id
     * @return Eligible Ship-To options, Primary first
     */
    @AuraEnabled
    public static List<ShipToAddressOption> getShipToAddressesForAccount(Id accountId) {
        try {
            List<ShipToAddressOption> options = new List<ShipToAddressOption>();
            for (Account shipTo : AccountService.getShipToAddressAccounts(accountId)) {
                options.add(toShipToAddressOption(shipTo));
            }
            return options;
        } catch (Exception e) {
            throw new AuraHandledException(
                'Error retrieving Ship-To addresses: ' + e.getMessage()
            );
        }
    }

    private static String resolveDefaultProductId() {
        Product2 defaultProduct = queryDefaultProduct();
        return defaultProduct == null ? null : String.valueOf(defaultProduct.Id);
    }

    @AuraEnabled(cacheable=true)
    public static Product2 getDefaultProduct() {
        try {
            return queryDefaultProduct();
        } catch (Exception e) {
            throw new AuraHandledException('Error retrieving default product: ' + e.getMessage());
        }
    }

    private static Product2 queryDefaultProduct() {
        List<Product2> products = [
            SELECT Id, Name, Description, ProductLine__c, ProductCode, Model__c
            FROM Product2
            WHERE Name = :DEFAULT_PRODUCT_NAME AND IsActive = TRUE
            WITH USER_MODE
            ORDER BY CreatedDate ASC
            LIMIT 1
        ];
        return products.isEmpty() ? null : products[0];
    }

    @AuraEnabled(cacheable=true)
    public static Product2 getProductDetails(Id productId, Boolean requireServiceAssetType) {
        try {
            if (productId == null) {
                return null;
            }

            Boolean requireServiceAsset = requireServiceAssetType == null
                ? true
                : requireServiceAssetType;

            List<Product2> products;
            if (requireServiceAsset) {
                products = [
                    SELECT
                        Id,
                        Name,
                        Description,
                        ProductLine__c,
                        ProductType__c,
                        ProductCode,
                        Model__c,
                        Manufacturer__c
                    FROM Product2
                    WHERE
                        Id = :productId
                        AND ProductType__c = 'Service Asset'
                        AND IsActive = TRUE
                    WITH USER_MODE
                    LIMIT 1
                ];
            } else {
                products = [
                    SELECT
                        Id,
                        Name,
                        Description,
                        ProductLine__c,
                        ProductType__c,
                        ProductCode,
                        Model__c,
                        Manufacturer__c
                    FROM Product2
                    WHERE Id = :productId AND IsActive = TRUE
                    WITH USER_MODE
                    LIMIT 1
                ];
            }
            return products.isEmpty() ? null : products[0];
        } catch (Exception e) {
            throw new AuraHandledException('Error retrieving product: ' + e.getMessage());
        }
    }

    /**
     * @description Apex overload without device-type filter (tests / internal callers).
     */
    public static List<ProductPicklistOption> getProductsForReturnOrderLine(
        String productLine,
        Boolean requireServiceAssetType,
        String searchTerm
    ) {
        return getProductsForReturnOrderLine(productLine, requireServiceAssetType, searchTerm, null);
    }

    @AuraEnabled(cacheable=true)
    public static List<ProductPicklistOption> getProductsForReturnOrderLine(
        String productLine,
        Boolean requireServiceAssetType,
        String searchTerm,
        String deviceType
    ) {
        try {
            Boolean requireServiceAsset = requireServiceAssetType == null
                ? true
                : requireServiceAssetType;
            Boolean filterByProductLine = String.isNotBlank(productLine);

            if (!filterByProductLine && !requireServiceAsset) {
                return new List<ProductPicklistOption>();
            }

            String normalizedProductLine = filterByProductLine ? productLine.trim() : null;
            String normalizedSearchTerm = String.isBlank(searchTerm) ? null : searchTerm.trim();
            String searchLikeTerm = normalizedSearchTerm == null
                ? null
                : '%' + normalizedSearchTerm + '%';
            String normalizedDeviceType = String.isBlank(deviceType) ? null : deviceType.trim();

            List<Product2> products;
            if (requireServiceAsset && !filterByProductLine) {
                if (searchLikeTerm == null) {
                    products = [
                        SELECT Id, Name, ProductCode, Model__c, Description, DeviceType__c
                        FROM Product2
                        WHERE IsActive = TRUE AND ProductType__c = 'Service Asset'
                        WITH USER_MODE
                        ORDER BY Name ASC
                        LIMIT 200
                    ];
                } else {
                    products = [
                        SELECT Id, Name, ProductCode, Model__c, Description, DeviceType__c
                        FROM Product2
                        WHERE
                            IsActive = TRUE
                            AND ProductType__c = 'Service Asset'
                            AND (Name LIKE :searchLikeTerm
                            OR ProductCode LIKE :searchLikeTerm
                            OR Model__c LIKE :searchLikeTerm)
                        WITH USER_MODE
                        ORDER BY Name ASC
                        LIMIT 200
                    ];
                }
            } else if (requireServiceAsset) {
                if (searchLikeTerm == null) {
                    products = [
                        SELECT Id, Name, ProductCode, Model__c, Description, DeviceType__c
                        FROM Product2
                        WHERE
                            IsActive = TRUE
                            AND ProductLine__c = :normalizedProductLine
                            AND ProductType__c = 'Service Asset'
                        WITH USER_MODE
                        ORDER BY Name ASC
                        LIMIT 200
                    ];
                } else {
                    products = [
                        SELECT Id, Name, ProductCode, Model__c, Description, DeviceType__c
                        FROM Product2
                        WHERE
                            IsActive = TRUE
                            AND ProductLine__c = :normalizedProductLine
                            AND ProductType__c = 'Service Asset'
                            AND (Name LIKE :searchLikeTerm
                            OR ProductCode LIKE :searchLikeTerm
                            OR Model__c LIKE :searchLikeTerm)
                        WITH USER_MODE
                        ORDER BY Name ASC
                        LIMIT 200
                    ];
                }
            } else if (searchLikeTerm == null) {
                products = [
                    SELECT Id, Name, ProductCode, Model__c, Description, DeviceType__c
                    FROM Product2
                    WHERE IsActive = TRUE AND ProductLine__c = :normalizedProductLine
                    WITH USER_MODE
                    ORDER BY Name ASC
                    LIMIT 200
                ];
            } else {
                products = [
                    SELECT Id, Name, ProductCode, Model__c, Description, DeviceType__c
                    FROM Product2
                    WHERE
                        IsActive = TRUE
                        AND ProductLine__c = :normalizedProductLine
                        AND (Name LIKE :searchLikeTerm
                        OR ProductCode LIKE :searchLikeTerm
                        OR Model__c LIKE :searchLikeTerm)
                    WITH USER_MODE
                    ORDER BY Name ASC
                    LIMIT 200
                ];
            }

            List<ProductPicklistOption> options = new List<ProductPicklistOption>();
            for (Product2 product : products) {
                if (
                    normalizedDeviceType != null &&
                    (String.isBlank(product.DeviceType__c) ||
                    !product.DeviceType__c.equalsIgnoreCase(normalizedDeviceType))
                ) {
                    continue;
                }
                ProductPicklistOption option = new ProductPicklistOption();
                option.value = product.Id;
                option.name = product.Name;
                option.productCode = product.ProductCode;
                option.model = product.Model__c;
                option.description = product.Description;
                option.label = buildProductOptionLabel(product);
                options.add(option);
            }
            return options;
        } catch (Exception e) {
            throw new AuraHandledException('Error retrieving products: ' + e.getMessage());
        }
    }

    private static String buildProductOptionLabel(Product2 product) {
        List<String> parts = new List<String>();
        if (String.isNotBlank(product.Name)) {
            parts.add(product.Name.trim());
        }
        if (String.isNotBlank(product.ProductCode)) {
            parts.add(product.ProductCode.trim());
        }
        if (String.isNotBlank(product.Model__c)) {
            parts.add(product.Model__c.trim());
        }
        return parts.isEmpty() ? String.valueOf(product.Id) : String.join(parts, ' · ');
    }

    @AuraEnabled
    public static List<Contact> getContactsForAccount(Id accountId) {
        try {
            Set<Id> contactIds = getAccountRelatedContactIds(accountId);
            if (contactIds.isEmpty()) {
                return new List<Contact>();
            }

            return [
                SELECT Id, Name, Email
                FROM Contact
                WHERE Id IN :contactIds
                WITH USER_MODE
                ORDER BY Name ASC
            ];
        } catch (Exception e) {
            throw new AuraHandledException('Error retrieving contacts: ' + e.getMessage());
        }
    }

    @AuraEnabled
    public static CreateContactResult createAccountContact(
        Id accountId,
        String firstName,
        String lastName,
        String email,
        String phone,
        String title,
        Boolean requireEmail
    ) {
        try {
            if (accountId == null) {
                throw new AuraHandledException('Account is required to create a contact.');
            }
            if (String.isBlank(firstName)) {
                throw new AuraHandledException('First Name is required.');
            }
            if (String.isBlank(lastName)) {
                throw new AuraHandledException('Last Name is required.');
            }
            if (requireEmail == true && String.isBlank(email)) {
                throw new AuraHandledException('Email is required.');
            }

            String trimmedFirstName = firstName.trim();
            String trimmedLastName = lastName.trim();
            Contact duplicateContact = findDuplicateContactOnAccount(
                accountId,
                trimmedFirstName,
                trimmedLastName
            );
            if (duplicateContact != null) {
                throw new AuraHandledException(
                    'A contact named ' +
                        duplicateContact.FirstName +
                        ' ' +
                        duplicateContact.LastName +
                        ' already exists on this account. Select the existing contact from the list.'
                );
            }

            Contact newContact = new Contact(
                AccountId = accountId,
                FirstName = trimmedFirstName,
                LastName = trimmedLastName,
                Email = String.isNotBlank(email) ? email.trim() : null,
                Phone = String.isNotBlank(phone) ? phone.trim() : null,
                Title = String.isNotBlank(title) ? title.trim() : null
            );
            insert newContact;
            ensureAccountContactRelation(accountId, newContact.Id);

            Contact created = [
                SELECT Id, Name, Email
                FROM Contact
                WHERE Id = :newContact.Id
                WITH USER_MODE
                LIMIT 1
            ];

            CreateContactResult result = new CreateContactResult();
            result.contactId = created.Id;
            result.contactName = created.Name;
            result.contactEmail = created.Email;
            return result;
        } catch (AuraHandledException e) {
            throw e;
        } catch (DmlException e) {
            throw new AuraHandledException(
                'Error creating contact: ' + e.getDmlMessage(0)
            );
        } catch (Exception e) {
            throw new AuraHandledException('Error creating contact: ' + e.getMessage());
        }
    }

    @AuraEnabled
    public static void updateContactEmail(Id contactId, String email) {
        try {
            if (contactId == null) {
                throw new AuraHandledException('Contact is required.');
            }
            if (String.isBlank(email)) {
                throw new AuraHandledException('Email is required.');
            }

            Contact contactToUpdate = new Contact(
                Id = contactId,
                Email = email.trim()
            );
            update contactToUpdate;
        } catch (AuraHandledException e) {
            throw e;
        } catch (DmlException e) {
            throw new AuraHandledException(
                'Error updating contact email: ' + e.getDmlMessage(0)
            );
        } catch (Exception e) {
            throw new AuraHandledException(
                'Error updating contact email: ' + e.getMessage()
            );
        }
    }

    @AuraEnabled(cacheable=true)
    public static List<Case> getOpenCasesForAccount(Id accountId) {
        try {
            if (accountId == null) {
                return new List<Case>();
            }

            return [
                SELECT Id, CaseNumber, Subject
                FROM Case
                WHERE AccountId = :accountId
                AND IsClosed = false
                WITH USER_MODE
                ORDER BY CaseNumber ASC
            ];
        } catch (Exception e) {
            throw new AuraHandledException('Error retrieving cases: ' + e.getMessage());
        }
    }

    @AuraEnabled(cacheable=true)
    public static List<LocationOption> getRepairCenterLocations() {
        try {
            List<LocationOption> options = new List<LocationOption>();
            for (Schema.Location loc : [
                SELECT Id, Name
                FROM Location
                WHERE LocationType = :LOCATION_TYPE_REPAIR_CENTER
                WITH USER_MODE
                ORDER BY Name ASC
            ]) {
                LocationOption option = new LocationOption();
                option.id = loc.Id;
                option.name = loc.Name;
                options.add(option);
            }
            return options;
        } catch (Exception e) {
            throw new AuraHandledException('Error retrieving repair centers: ' + e.getMessage());
        }
    }

    @AuraEnabled(cacheable=true)
    public static List<User> getActiveInternalUsers() {
        try {
            return [
                SELECT Id, Name
                FROM User
                WHERE IsActive = true
                AND UserType IN ('Standard', 'CsnOnly')
                WITH USER_MODE
                ORDER BY Name ASC
            ];
        } catch (Exception e) {
            throw new AuraHandledException('Error retrieving users: ' + e.getMessage());
        }
    }

    @AuraEnabled(cacheable=true)
    public static List<AssetLineData> getAssetsForAccount(Id accountId) {
        try {
            if (accountId == null) {
                return new List<AssetLineData>();
            }

            List<Asset> assets = [
                SELECT
                    Id,
                    SerialNumber,
                    ModelCalculated__c,
                    Department__c,
                    Product2Id,
                    Product2.ProductLine__c,
                    Product2.Name,
                    Product2.Manufacturer__c
                FROM Asset
                WHERE AccountId = :accountId
                WITH USER_MODE
                ORDER BY SerialNumber ASC NULLS LAST, Name ASC
            ];

            return mapAssetsToLineData(assets);
        } catch (Exception e) {
            throw new AuraHandledException('Error retrieving assets: ' + e.getMessage());
        }
    }

    @AuraEnabled(cacheable=true)
    public static List<PicklistOption> getDepartmentsForAccount(
        Id accountId,
        List<String> additionalDepartmentIds
    ) {
        try {
            if (accountId == null) {
                return new List<PicklistOption>();
            }

            List<PicklistOption> options = new List<PicklistOption>();
            Set<Id> includedDepartmentIds = new Set<Id>();

            for (AccountDepartment__c accountDepartment : [
                SELECT Department__c, Department__r.Name
                FROM AccountDepartment__c
                WHERE Account__c = :accountId AND Department__c != NULL
                WITH USER_MODE
                ORDER BY Department__r.Name ASC NULLS LAST
            ]) {
                if (includedDepartmentIds.add(accountDepartment.Department__c)) {
                    PicklistOption option = new PicklistOption();
                    option.label = accountDepartment.Department__r.Name;
                    option.value = accountDepartment.Department__c;
                    options.add(option);
                }
            }

            Set<Id> additionalIds = toIdSet(additionalDepartmentIds);
            additionalIds.removeAll(includedDepartmentIds);
            if (!additionalIds.isEmpty()) {
                for (Department__c department : [
                    SELECT Id, Name
                    FROM Department__c
                    WHERE Id IN :additionalIds
                    WITH USER_MODE
                    ORDER BY Name ASC
                ]) {
                    PicklistOption option = new PicklistOption();
                    option.label = department.Name;
                    option.value = department.Id;
                    options.add(option);
                    includedDepartmentIds.add(department.Id);
                }
            }

            return options;
        } catch (Exception e) {
            throw new AuraHandledException('Error retrieving account departments: ' + e.getMessage());
        }
    }

    @AuraEnabled
    public static List<AssetLineData> getAssetsByIds(List<String> assetIds) {
        try {
            List<String> normalizedAssetIds = normalizeRecordIds(assetIds);
            Set<Id> idSet = toIdSet(normalizedAssetIds);
            if (idSet.isEmpty()) {
                return new List<AssetLineData>();
            }

            Map<Id, Asset> assetsById = new Map<Id, Asset>([
                SELECT
                    Id,
                    SerialNumber,
                    ModelCalculated__c,
                    Department__c,
                    Product2Id,
                    Product2.ProductLine__c,
                    Product2.Name,
                    Product2.Manufacturer__c
                FROM Asset
                WHERE Id IN :idSet
                WITH USER_MODE
            ]);

            List<AssetLineData> rows = new List<AssetLineData>();
            for (String assetIdValue : normalizedAssetIds) {
                Id assetId = parseId(assetIdValue);
                if (assetId == null || !assetsById.containsKey(assetId)) {
                    continue;
                }
                rows.add(mapAssetToLineData(assetsById.get(assetId)));
            }

            return rows;
        } catch (Exception e) {
            throw new AuraHandledException('Error retrieving selected assets: ' + e.getMessage());
        }
    }

    @AuraEnabled
    public static List<ScanSerialAssetResult> findAssetsBySerial(String serialNumber) {
        try {
            String normalizedSerial = serialNumber == null ? '' : serialNumber.trim();
            if (String.isBlank(normalizedSerial)) {
                return new List<ScanSerialAssetResult>();
            }

            List<Asset> assets = [
                SELECT
                    Id,
                    SerialNumber,
                    ModelCalculated__c,
                    Department__c,
                    Product2Id,
                    Product2.ProductLine__c,
                    Product2.Name,
                    AccountId,
                    Account.Name
                FROM Asset
                WHERE SerialNumber = :normalizedSerial
                WITH USER_MODE
                ORDER BY Account.Name ASC NULLS LAST, SerialNumber ASC NULLS LAST
                LIMIT 50
            ];

            List<ScanSerialAssetResult> rows = new List<ScanSerialAssetResult>();
            for (Asset asset : assets) {
                rows.add(mapAssetToScanSerialResult(asset));
            }
            return rows;
        } catch (Exception e) {
            throw new AuraHandledException('Error searching assets by serial: ' + e.getMessage());
        }
    }

    @AuraEnabled(cacheable=true)
    public static AccountReadinessResult validateAccountForReturnOrder(Id accountId) {
        AccountReadinessResult result = new AccountReadinessResult();
        result.isReady = false;
        result.missingFields = new List<String>();

        if (accountId == null) {
            result.message = 'Account is required.';
            result.missingFields.add('Account');
            return result;
        }

        Account account = getAccountDetails(accountId);
        if (account == null) {
            result.message = 'Account could not be found.';
            result.missingFields.add('Account');
            return result;
        }

        result.accountId = account.Id;
        result.accountName = account.Name;
        result.operatingUnit = readAccountOperatingUnit(account);

        if (String.isBlank(result.operatingUnit)) {
            result.missingFields.add('Operating Unit');
        }

        result.isReady = result.missingFields.isEmpty();
        if (!result.isReady) {
            result.message =
                'Account data is incomplete. Update the account before creating a return order: ' +
                String.join(result.missingFields, ', ') +
                '.';
        }
        return result;
    }

    @AuraEnabled
    public static LineRoutingValidation validateLineRoutingMatches(
        String headerJson,
        String lineItemsJson
    ) {
        LineRoutingValidation validation = new LineRoutingValidation();
        validation.isValid = true;
        validation.messages = new List<String>();

        try {
            Map<String, Object> header = (Map<String, Object>) JSON.deserializeUntyped(headerJson);
            List<Object> lineObjects = lineItemsJson != null
                ? (List<Object>) JSON.deserializeUntyped(lineItemsJson)
                : new List<Object>();

            Id accountId = parseId((String) header.get('accountId'));
            if (accountId == null) {
                throw new AuraHandledException('Account is required.');
            }

            String operatingUnit = resolveOperatingUnit(header);
            if (String.isBlank(operatingUnit)) {
                throw new AuraHandledException('Operating Unit is required.');
            }
            if (lineObjects.isEmpty()) {
                throw new AuraHandledException('Add at least one line item.');
            }

            Map<Id, String> shipStateCodeByShipToId = loadShipToStateCodes(accountId);
            List<RepairCenterRoutingRule__c> routingRules = loadRoutingRulesForOperatingUnit(operatingUnit);
            Map<Id, Product2> productsById = loadProductsForRouting(lineObjects);

            for (Integer index = 0; index < lineObjects.size(); index++) {
                Map<String, Object> line = (Map<String, Object>) lineObjects[index];
                RepairCenterRoutingRule__c matchedRule = findMatchingRoutingRule(
                    line,
                    productsById.get(parseId(String.valueOf(line.get('product2Id')))),
                    resolveLineShipStateCode(line, shipStateCodeByShipToId),
                    routingRules
                );

                if (matchedRule == null || matchedRule.RepairCenter__c == null) {
                    validation.isValid = false;
                    validation.messages.add(
                        buildMissingRoutingRuleMessage(
                            line,
                            operatingUnit,
                            resolveDisplayLineNumber(line, index + 1)
                        )
                    );
                }
            }

            return validation;
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw new AuraHandledException(
                'Error validating routing rules: ' + e.getMessage()
            );
        }
    }

    @AuraEnabled
    public static List<ProposedReturnOrderGroup> buildReturnOrderPlan(
        String headerJson,
        String lineItemsJson
    ) {
        try {
            Map<String, Object> header = (Map<String, Object>) JSON.deserializeUntyped(headerJson);
            List<Object> lineObjects = lineItemsJson != null
                ? (List<Object>) JSON.deserializeUntyped(lineItemsJson)
                : new List<Object>();

            Id accountId = parseId((String) header.get('accountId'));
            if (accountId == null) {
                throw new AuraHandledException('Account is required.');
            }

            String operatingUnit = resolveOperatingUnit(header);
            if (String.isBlank(operatingUnit)) {
                throw new AuraHandledException('Operating Unit is required.');
            }
            if (lineObjects.isEmpty()) {
                throw new AuraHandledException('Add at least one line item.');
            }

            Map<Id, String> shipStateCodeByShipToId = loadShipToStateCodes(accountId);
            List<RepairCenterRoutingRule__c> routingRules = loadRoutingRulesForOperatingUnit(operatingUnit);
            Map<Id, Product2> productsById = loadProductsForRouting(lineObjects);

            Map<String, Integer> nonSterilizedCountByRepairCenter =
                countNonSterilizedLinesByRepairCenter(
                    lineObjects,
                    shipStateCodeByShipToId,
                    routingRules,
                    productsById
                );

            Map<String, Integer> maxItemsLineCounters = new Map<String, Integer>();
            Map<String, List<Object>> linesByGroupKey = new Map<String, List<Object>>();
            Map<String, String> baseGroupKeyByGroupKey = new Map<String, String>();
            Map<String, Set<String>> splitGroupKeysByBaseGroupKey =
                new Map<String, Set<String>>();
            for (Object lineObj : lineObjects) {
                Map<String, Object> line = (Map<String, Object>) lineObj;
                Product2 product = productsById.get(parseId(String.valueOf(line.get('product2Id'))));
                String shipToStateCode = resolveLineShipStateCode(line, shipStateCodeByShipToId);
                String repairCenterKey = resolveRepairCenterGroupKey(
                    line,
                    product,
                    shipToStateCode,
                    routingRules
                );
                String baseGroupKey = resolveFinalGroupKey(
                    line,
                    product,
                    repairCenterKey,
                    nonSterilizedCountByRepairCenter,
                    shipToStateCode,
                    routingRules,
                    maxItemsLineCounters
                );
                String groupKey = buildSplitAttributesGroupKey(baseGroupKey, line, product);
                if (!linesByGroupKey.containsKey(groupKey)) {
                    linesByGroupKey.put(groupKey, new List<Object>());
                }
                linesByGroupKey.get(groupKey).add(line);
                baseGroupKeyByGroupKey.put(groupKey, baseGroupKey);
                if (!splitGroupKeysByBaseGroupKey.containsKey(baseGroupKey)) {
                    splitGroupKeysByBaseGroupKey.put(baseGroupKey, new Set<String>());
                }
                splitGroupKeysByBaseGroupKey.get(baseGroupKey).add(groupKey);
            }

            Map<Id, String> contactNamesById = loadContactNames(lineObjects);
            Map<Id, String> departmentNamesById = loadDepartmentNames(lineObjects);

            List<ProposedReturnOrderGroup> groups = new List<ProposedReturnOrderGroup>();
            for (String groupKey : sortGroupKeys(linesByGroupKey.keySet())) {
                List<Object> groupedLines = linesByGroupKey.get(groupKey);
                String baseGroupKey = baseGroupKeyByGroupKey.get(groupKey);
                ProposedReturnOrderGroup proposedGroup = new ProposedReturnOrderGroup();
                proposedGroup.groupKey =
                    splitGroupKeysByBaseGroupKey.get(baseGroupKey).size() > 1
                        ? groupKey
                        : baseGroupKey;
                proposedGroup.returnOrderType = resolveReturnOrderTypeFromLine(
                    (Map<String, Object>) groupedLines[0]
                );
                proposedGroup.lineCount = groupedLines.size();
                proposedGroup.lineItemsJson = JSON.serialize(groupedLines);
                proposedGroup.lineSummaries = buildLineSummaries(
                    groupedLines,
                    contactNamesById,
                    departmentNamesById
                );

                String baseRepairCenterKey = extractBaseRepairCenterKey(baseGroupKey);
                if (baseRepairCenterKey == UNASSIGNED_REPAIR_CENTER_GROUP) {
                    proposedGroup.requiresRepairCenterSelection = true;
                    proposedGroup.repairCenterName = 'Repair center required';
                } else {
                    proposedGroup.requiresRepairCenterSelection = false;
                    proposedGroup.repairCenterId = baseRepairCenterKey;
                    proposedGroup.repairCenterName = resolveRepairCenterName(
                        baseRepairCenterKey,
                        routingRules
                    );
                }
                groups.add(proposedGroup);
            }

            return groups;
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw new AuraHandledException(
                'Error building return order plan: ' + e.getMessage()
            );
        }
    }

    @AuraEnabled
    public static CreateOrdersResult createReturnOrders(String headerJson, String groupsJson) {
        try {
            CreateOrdersResult ordersResult = new CreateOrdersResult();
            ordersResult.returnOrders = new List<CreateResult>();
            for (ReturnOrdersService.GroupedReturnOrderResult created :
                ReturnOrdersService.createGroupedReturnOrders(headerJson, groupsJson)
            ) {
                ordersResult.returnOrders.add(toCreateResult(created));
            }
            clearSendToRepairCenter(lineObjectsFromGroupsJson(groupsJson));
            return ordersResult;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    @AuraEnabled
    public static CreateResult createReturnOrder(String headerJson, String lineItemsJson) {
        try {
            CreateResult result = toCreateResult(
                ReturnOrdersService.createSingleReturnOrder(headerJson, lineItemsJson)
            );
            List<Object> lineObjects = String.isNotBlank(lineItemsJson)
                ? (List<Object>) JSON.deserializeUntyped(lineItemsJson)
                : new List<Object>();
            clearSendToRepairCenter(lineObjects);
            return result;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    /**
     * @description GW-1353 - Child work order lines marked Send to Repair Center for a site visit.
     *              The site visit work order header still comes from the work order launch path.
     *              Sharing applies. Field permissions do not block the prefill.
     * @param workOrderId Site visit work order Id
     * @return Instrument lines the technician confirms in Create Return Order
     */
    @AuraEnabled
    public static List<SiteVisitInstrumentLine> getSiteVisitRepairCenterLines(Id workOrderId) {
        try {
            List<SiteVisitInstrumentLine> lines = new List<SiteVisitInstrumentLine>();
            if (workOrderId == null) {
                return lines;
            }

            for (WorkOrderLineItem lineItem : [
                SELECT
                    Id,
                    Quantity,
                    Description,
                    Product2Id,
                    Product2.Name,
                    Product2.Description,
                    Product2.Model__c,
                    SerialNumber__c,
                    Model__c,
                    Department__c,
                    ReportedProblem__c,
                    AdditionalServices__c,
                    InsulationPowderCoating__c
                FROM WorkOrderLineItem
                WHERE WorkOrder.ParentWorkOrderId = :workOrderId
                    AND SendToRepairCenter__c = TRUE
                ORDER BY WorkOrder.WorkOrderNumber ASC, LineItemNumber ASC NULLS LAST
            ]) {
                lines.add(toSiteVisitInstrumentLine(lineItem));
            }
            return lines;
        } catch (Exception e) {
            throw new AuraHandledException(
                'Error loading repair center lines: ' + e.getMessage()
            );
        }
    }

    private static CreateResult toCreateResult(
        ReturnOrdersService.GroupedReturnOrderResult created
    ) {
        CreateResult result = new CreateResult();
        result.returnOrderId = created.returnOrderId;
        result.returnOrderNumber = created.returnOrderNumber;
        result.returnOrderType = created.returnOrderType;
        result.repairCenterName = created.repairCenterName;
        result.lineCount = created.lineCount;
        return result;
    }

    

    private static void resolveContextFromObject(
        InitContext ctx,
        String recordId,
        String sObjectName,
        List<String> selectedIds
    ) {
        if (sObjectName == 'Case' && String.isNotBlank(recordId)) {
            Case c = [
                SELECT AccountId, CaseNumber, Subject
                FROM Case
                WHERE Id = :recordId
                WITH USER_MODE
                LIMIT 1
            ];
            ctx.accountId = c.AccountId;
            ctx.caseId = recordId;
            ctx.caseLabel = formatCaseLabel(c);
            ctx.lockCase = true;
            ctx.lockAccount = c.AccountId != null;
        } else if (sObjectName == 'WorkOrder' && String.isNotBlank(recordId)) {
            resolveContextFromWorkOrder(ctx, recordId);
        } else if (sObjectName == 'Account' && String.isNotBlank(recordId)) {
            ctx.accountId = recordId;
        } else if (sObjectName == 'Asset') {
            if (!selectedIds.isEmpty()) {
                resolveContextFromAssets(ctx, selectedIds);
            } else if (String.isNotBlank(recordId)) {
                Asset asset = [
                    SELECT Id, AccountId
                    FROM Asset
                    WHERE Id = :recordId
                    WITH USER_MODE
                    LIMIT 1
                ];
                ctx.accountId = asset.AccountId;
                ctx.assetIds.add(asset.Id);
            }
        }
    }

    private static void resolveContextFromAssets(InitContext ctx, List<String> assetIds) {
        Set<Id> idSet = toIdSet(assetIds);
        if (idSet.isEmpty()) {
            return;
        }

        Map<Id, Asset> assetsById = new Map<Id, Asset>([
            SELECT Id, AccountId
            FROM Asset
            WHERE Id IN :idSet
            WITH USER_MODE
        ]);

        // Preserve list-view selection order: account and lines use the first selected asset.
        for (String assetIdValue : assetIds) {
            if (String.isBlank(assetIdValue)) {
                continue;
            }

            Id assetId;
            try {
                assetId = Id.valueOf(assetIdValue.trim());
            } catch (Exception e) {
                continue;
            }

            Asset asset = assetsById.get(assetId);
            if (asset == null) {
                continue;
            }

            ctx.assetIds.add(asset.Id);
            if (ctx.accountId == null) {
                ctx.accountId = asset.AccountId;
            }
        }
    }

    private static void resolveContextFromWorkOrder(InitContext ctx, String workOrderIdValue) {
        Id workOrderId = parseId(workOrderIdValue);
        if (workOrderId == null) {
            return;
        }

        WorkOrder workOrder = [
            SELECT
                AccountId,
                ContactId,
                Contact.Name,
                AssetId,
                WorkOrderNumber
            FROM WorkOrder
            WHERE Id = :workOrderId
            WITH USER_MODE
            LIMIT 1
        ];

        ctx.accountId = workOrder.AccountId;
        ctx.lockAccount = workOrder.AccountId != null;
        ctx.contactId = workOrder.ContactId;
        ctx.contactName = workOrder.Contact != null ? workOrder.Contact.Name : null;
        ctx.lockContact = workOrder.ContactId != null;
        ctx.workOrderId = workOrderId;
        ctx.workOrderLabel = workOrder.WorkOrderNumber;
        ctx.lockWorkOrder = true;

        addWorkOrderAssetIds(ctx, workOrderId, workOrder.AssetId);
    }

    private static void addWorkOrderAssetIds(
        InitContext ctx,
        Id workOrderId,
        Id headerAssetId
    ) {
        Set<Id> addedAssetIds = new Set<Id>();

        if (headerAssetId != null) {
            ctx.assetIds.add(String.valueOf(headerAssetId));
            addedAssetIds.add(headerAssetId);
        }

        for (WorkOrderLineItem lineItem : [
            SELECT AssetId
            FROM WorkOrderLineItem
            WHERE WorkOrderId = :workOrderId AND AssetId != NULL
            WITH USER_MODE
            ORDER BY LineItemNumber ASC NULLS LAST, CreatedDate ASC
        ]) {
            if (lineItem.AssetId != null && !addedAssetIds.contains(lineItem.AssetId)) {
                ctx.assetIds.add(String.valueOf(lineItem.AssetId));
                addedAssetIds.add(lineItem.AssetId);
            }
        }
    }

    private static String resolveSObjectName(
        String recordId,
        String objectApiName,
        List<String> recordIds
    ) {
        if (String.isNotBlank(objectApiName)) {
            return objectApiName.trim();
        }
        if (String.isNotBlank(recordId)) {
            try {
                return Id.valueOf(recordId).getSobjectType().getDescribe().getName();
            } catch (Exception e) {
                return null;
            }
        }
        if (recordIds != null && !recordIds.isEmpty()) {
            try {
                return Id.valueOf(recordIds[0]).getSobjectType().getDescribe().getName();
            } catch (Exception e) {
                return null;
            }
        }
        return null;
    }

    private static void populateAccountDefaults(InitContext ctx, String accountId) {
        Account account = getAccountDetails(accountId);
        if (account == null) {
            return;
        }

        ctx.accountName = account.Name;
        ctx.legacyCustomerId = account.SystemID__c;
        ctx.defaultOperatingUnit = readAccountOperatingUnit(account);
    }

    private static String readAccountOperatingUnit(Account account) {
        if (account == null) {
            return null;
        }

        if (String.isNotBlank(account.OrgIDs__c)) {
            return account.OrgIDs__c.trim();
        }

        return null;
    }

    private static String resolveOperatingUnit(Map<String, Object> header) {
        if (header == null) {
            return null;
        }

        String operatingUnit = (String) header.get('operatingUnit');
        if (String.isNotBlank(operatingUnit)) {
            return operatingUnit.trim();
        }

        Id accountId = parseId((String) header.get('accountId'));
        if (accountId == null) {
            return null;
        }

        return readAccountOperatingUnit(getAccountDetails(accountId));
    }

    

    

    

    private static Boolean isSerializedLine(Map<String, Object> line) {
        if (line == null) {
            return true;
        }
        if (line.containsKey('lineType')) {
            return 'serialized'.equalsIgnoreCase((String) line.get('lineType'));
        }
        if (line.containsKey('serialized')) {
            return toBoolean(line.get('serialized'));
        }
        return true;
    }

    private static Boolean isInstrumentsLine(Map<String, Object> line) {
        if (isOtherLine(line)) {
            return false;
        }
        if (line != null && line.containsKey('lineType')) {
            return 'instruments'.equalsIgnoreCase((String) line.get('lineType'));
        }
        return !isSerializedLine(line);
    }

    private static String resolveReturnOrderTypeFromLine(Map<String, Object> line) {
        if (isOtherSerializedLine(line)) {
            return RETURN_ORDER_TYPE_OTHER_SERIALIZED;
        }
        if (isOtherNonSerializedLine(line)) {
            return RETURN_ORDER_TYPE_OTHER_NON_SERIALIZED;
        }
        if (isOtherLine(line)) {
            return toBoolean(line.get('serialized'))
                ? RETURN_ORDER_TYPE_OTHER_SERIALIZED
                : RETURN_ORDER_TYPE_OTHER_NON_SERIALIZED;
        }
        if (isInstrumentsLine(line)) {
            return RETURN_ORDER_TYPE_INSTRUMENTS;
        }
        return RETURN_ORDER_TYPE_SERIALIZED;
    }

    

    

    

    private static String wrapGroupKeyWithReturnOrderType(
        Map<String, Object> line,
        String innerGroupKey
    ) {
        return resolveReturnOrderTypeFromLine(line) +
            RETURN_ORDER_GROUP_KEY_DELIMITER +
            innerGroupKey;
    }

    private static String extractInnerGroupKey(String finalGroupKey) {
        if (String.isBlank(finalGroupKey)) {
            return UNASSIGNED_REPAIR_CENTER_GROUP;
        }

        Integer delimiterIndex = finalGroupKey.indexOf(RETURN_ORDER_GROUP_KEY_DELIMITER);
        if (delimiterIndex > 0) {
            return finalGroupKey.substring(
                delimiterIndex + RETURN_ORDER_GROUP_KEY_DELIMITER.length()
            );
        }
        return finalGroupKey;
    }

    

    

    private static Boolean isOtherLine(Map<String, Object> line) {
        if (line == null) {
            return false;
        }
        if (line.containsKey('lineType')) {
            String lineType = ((String) line.get('lineType')).toLowerCase();
            return lineType == 'other' ||
                lineType == 'other-serialized' ||
                lineType == 'other-non-serialized';
        }
        return false;
    }

    private static Boolean isOtherNonSerializedLine(Map<String, Object> line) {
        if (line == null || !line.containsKey('lineType')) {
            return false;
        }
        String lineType = ((String) line.get('lineType')).toLowerCase();
        if (lineType == 'other-non-serialized') {
            return true;
        }
        return lineType == 'other' && !toBoolean(line.get('serialized'));
    }

    private static Boolean isOtherSerializedLine(Map<String, Object> line) {
        if (line == null || !line.containsKey('lineType')) {
            return false;
        }
        String lineType = ((String) line.get('lineType')).toLowerCase();
        if (lineType == 'other-serialized') {
            return true;
        }
        return lineType == 'other' && toBoolean(line.get('serialized'));
    }

    

    private static Decimal parseQuantityReturned(Object value) {
        if (value == null) {
            return QUANTITY_RETURNED_DEFAULT;
        }
        if (value instanceof Decimal) {
            return ((Decimal) value) > 0 ? (Decimal) value : QUANTITY_RETURNED_DEFAULT;
        }
        if (value instanceof Integer) {
            Integer intValue = (Integer) value;
            return intValue > 0 ? Decimal.valueOf(intValue) : QUANTITY_RETURNED_DEFAULT;
        }
        if (value instanceof Long) {
            Long longValue = (Long) value;
            return longValue > 0 ? Decimal.valueOf(longValue) : QUANTITY_RETURNED_DEFAULT;
        }

        String text = String.valueOf(value);
        if (String.isBlank(text)) {
            return QUANTITY_RETURNED_DEFAULT;
        }

        Decimal parsed = Decimal.valueOf(text);
        return parsed > 0 ? parsed : QUANTITY_RETURNED_DEFAULT;
    }

    private static String defaultYesNo(String value) {
        return String.isNotBlank(value) ? value : YES_NO_DEFAULT;
    }

    private static void ensureAccountContactRelation(Id accountId, Id contactId) {
        if (accountId == null || contactId == null) {
            return;
        }

        for (AccountContactRelation existingRelation : [
            SELECT Id
            FROM AccountContactRelation
            WHERE AccountId = :accountId AND ContactId = :contactId
            WITH USER_MODE
            LIMIT 1
        ]) {
            if (existingRelation != null) {
                return;
            }
        }

        try {
            insert new AccountContactRelation(
                AccountId = accountId,
                ContactId = contactId,
                IsActive = true
            );
        } catch (DmlException e) {
            // When Contact.AccountId is set, Salesforce may already maintain the direct relationship.
            if (isExistingDirectRelationshipError(e)) {
                return;
            }
            throw e;
        }
    }

    private static Boolean isExistingDirectRelationshipError(DmlException e) {
        if (e == null) {
            return false;
        }
        for (Integer i = 0; i < e.getNumDml(); i++) {
            String message = e.getDmlMessage(i);
            if (message != null && message.contains('direct relationship')) {
                return true;
            }
        }
        return e.getMessage() != null && e.getMessage().contains('direct relationship');
    }

    private static Set<Id> getAccountRelatedContactIds(Id accountId) {
        Set<Id> contactIds = new Set<Id>();
        if (accountId == null) {
            return contactIds;
        }

        for (Contact directContact : [
            SELECT Id
            FROM Contact
            WHERE AccountId = :accountId
            WITH USER_MODE
        ]) {
            contactIds.add(directContact.Id);
        }

        for (AccountContactRelation relation : [
            SELECT ContactId
            FROM AccountContactRelation
            WHERE AccountId = :accountId AND IsActive = true AND ContactId != NULL
            WITH USER_MODE
        ]) {
            contactIds.add(relation.ContactId);
        }

        return contactIds;
    }

    private static Contact findDuplicateContactOnAccount(
        Id accountId,
        String firstName,
        String lastName
    ) {
        Set<Id> contactIds = getAccountRelatedContactIds(accountId);
        if (contactIds.isEmpty()) {
            return null;
        }

        for (Contact existingContact : [
            SELECT Id, Name, FirstName, LastName
            FROM Contact
            WHERE Id IN :contactIds
            WITH USER_MODE
        ]) {
            if (
                contactNamesMatch(existingContact.FirstName, firstName) &&
                contactNamesMatch(existingContact.LastName, lastName)
            ) {
                return existingContact;
            }
        }
        return null;
    }

    private static Boolean contactNamesMatch(String existingName, String newName) {
        if (String.isBlank(existingName) || String.isBlank(newName)) {
            return false;
        }
        return existingName.trim().equalsIgnoreCase(newName.trim());
    }

    private static List<AssetLineData> mapAssetsToLineData(List<Asset> assets) {
        List<AssetLineData> rows = new List<AssetLineData>();
        for (Asset asset : assets) {
            rows.add(mapAssetToLineData(asset));
        }
        return rows;
    }

    private static AssetLineData mapAssetToLineData(Asset asset) {
        AssetLineData row = new AssetLineData();
        row.id = asset.Id;
        row.serialNumber = asset.SerialNumber;
        row.model = asset.ModelCalculated__c;
        row.make = asset.Product2 != null ? asset.Product2.Manufacturer__c : null;
        row.departmentId = asset.Department__c;
        row.product2Id = asset.Product2Id;
        row.productLine = asset.Product2 != null ? asset.Product2.ProductLine__c : null;
        row.productName = asset.Product2 != null ? asset.Product2.Name : null;
        return row;
    }

    private static ScanSerialAssetResult mapAssetToScanSerialResult(Asset asset) {
        ScanSerialAssetResult row = new ScanSerialAssetResult();
        row.id = asset.Id;
        row.serialNumber = asset.SerialNumber;
        row.model = asset.ModelCalculated__c;
        row.departmentId = asset.Department__c;
        row.product2Id = asset.Product2Id;
        row.productLine = asset.Product2 != null ? asset.Product2.ProductLine__c : null;
        row.productName = asset.Product2 != null ? asset.Product2.Name : null;
        row.accountId = asset.AccountId;
        row.accountName = asset.Account != null ? asset.Account.Name : null;
        return row;
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

    private static List<PicklistOption> getDisinfectedPicklistOptions() {
        Map<String, Schema.SObjectField> lineFields =
            Schema.SObjectType.ReturnOrderLineItem.fields.getMap();
        if (!lineFields.containsKey('Disinfected__c')) {
            return new List<PicklistOption>();
        }
        return getPicklistOptions(lineFields.get('Disinfected__c').getDescribe());
    }

    private static Map<String, String> itemTypeToProductLineCache;
    private static Map<String, String> itemTypeToROCategoryCache;

    private static Map<String, String> getItemTypeToProductLineMappings() {
        if (itemTypeToProductLineCache != null) {
            return itemTypeToProductLineCache;
        }

        itemTypeToProductLineCache = new Map<String, String>();
        for (ROLIItemTypeandProductLine__mdt mapping : [
            SELECT ItemType__c, ProductLine__c
            FROM ROLIItemTypeandProductLine__mdt
            WHERE ItemType__c != NULL AND ProductLine__c != NULL AND IsActive__c = TRUE
        ]) {
            itemTypeToProductLineCache.put(mapping.ItemType__c, mapping.ProductLine__c);
        }
        return itemTypeToProductLineCache;
    }

    private static Map<String, String> getItemTypeToROCategoryMappings() {
        if (itemTypeToROCategoryCache != null) {
            return itemTypeToROCategoryCache;
        }

        itemTypeToROCategoryCache = new Map<String, String>();
        for (ROLIItemTypeandProductLine__mdt mapping : [
            SELECT ItemType__c, ROCategory__c
            FROM ROLIItemTypeandProductLine__mdt
            WHERE ItemType__c != NULL AND ROCategory__c != NULL AND IsActive__c = TRUE
        ]) {
            itemTypeToROCategoryCache.put(mapping.ItemType__c, mapping.ROCategory__c);
        }
        return itemTypeToROCategoryCache;
    }

    

    private static List<PicklistOption> getItemTypePicklistOptions() {
        List<PicklistOption> options = new List<PicklistOption>();
        for (ROLIItemTypeandProductLine__mdt mapping : [
            SELECT ItemType__c
            FROM ROLIItemTypeandProductLine__mdt
            WHERE
                ItemType__c != NULL
                AND IsActive__c = TRUE
                AND ItemType__c != :ENDOCAM_ITEM_TYPE
            ORDER BY ItemType__c ASC
        ]) {
            PicklistOption option = new PicklistOption();
            option.label = mapping.ItemType__c;
            option.value = mapping.ItemType__c;
            options.add(option);
        }
        return options;
    }

    

    

    

    

    

    

    

    private static ShipToAddressOption toShipToAddressOption(Account shipTo) {
        ShipToAddressOption option = new ShipToAddressOption();
        option.id = shipTo.Id;
        option.name = shipTo.Name;
        option.status = shipTo.ShiptoAddressStatus__c;
        option.addressDisplay = formatBillingAddress(shipTo);
        option.isPrimary = shipTo.ShiptoAddressStatus__c == 'Primary';
        List<String> labelParts = new List<String>{ shipTo.Name };
        if (String.isNotBlank(option.addressDisplay)) {
            labelParts.add(option.addressDisplay);
        }
        option.label = String.join(labelParts, ' - ');
        return option;
    }

    private static String formatBillingAddress(Account shipTo) {
        List<String> parts = new List<String>();
        if (String.isNotBlank(shipTo.BillingStreet)) {
            parts.add(shipTo.BillingStreet);
        }
        List<String> cityState = new List<String>();
        if (String.isNotBlank(shipTo.BillingCity)) {
            cityState.add(shipTo.BillingCity);
        }
        if (String.isNotBlank(shipTo.BillingState)) {
            cityState.add(shipTo.BillingState);
        }
        if (!cityState.isEmpty()) {
            parts.add(String.join(cityState, ', '));
        }
        if (String.isNotBlank(shipTo.BillingPostalCode)) {
            parts.add(shipTo.BillingPostalCode);
        }
        if (String.isNotBlank(shipTo.BillingCountry)) {
            parts.add(shipTo.BillingCountry);
        }
        return String.join(parts, ', ');
    }

    

    

    

    

    

    

    

    

    

    

    

    

    

    

    

    

    

    private static List<PicklistOption> getYesNoFallbackOptions() {
        List<PicklistOption> options = new List<PicklistOption>();
        for (String value : new List<String>{ 'Yes', 'No' }) {
            PicklistOption option = new PicklistOption();
            option.label = value;
            option.value = value;
            options.add(option);
        }
        return options;
    }

    private static Boolean toBoolean(Object value) {
        if (value == null) {
            return false;
        }
        if (value instanceof Boolean) {
            return (Boolean) value;
        }
        String text = String.valueOf(value);
        return 'true'.equalsIgnoreCase(text) || '1'.equals(text) || 'yes'.equalsIgnoreCase(text);
    }

    private static List<PicklistOption> getOperatingUnitPicklistOptions() {
        Map<String, Schema.SObjectField> returnOrderFields = Schema.SObjectType.ReturnOrder.fields.getMap();
        if (!returnOrderFields.containsKey('OperatingUnit__c')) {
            return new List<PicklistOption>();
        }
        return getPicklistOptions(returnOrderFields.get('OperatingUnit__c').getDescribe());
    }

    private static List<PicklistOption> getPicklistOptions(Schema.DescribeFieldResult fieldDescribe) {
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

    private static List<String> normalizeRecordIds(List<String> recordIds) {
        List<String> normalized = new List<String>();
        if (recordIds == null) {
            return normalized;
        }
        for (String recordId : recordIds) {
            if (String.isNotBlank(recordId)) {
                normalized.add(recordId);
            }
        }
        return normalized;
    }

    private static Set<Id> toIdSet(List<String> recordIds) {
        Set<Id> idSet = new Set<Id>();
        if (recordIds == null) {
            return idSet;
        }
        for (String recordId : recordIds) {
            Id parsed = parseId(recordId);
            if (parsed != null) {
                idSet.add(parsed);
            }
        }
        return idSet;
    }

    private static String formatCaseLabel(Case c) {
        String subject = String.isNotBlank(c.Subject) ? c.Subject : '';
        return String.isNotBlank(subject)
            ? c.CaseNumber + ' - ' + subject
            : c.CaseNumber;
    }

    private static Id parseId(String value) {
        if (String.isBlank(value)) {
            return null;
        }
        try {
            return (Id) value;
        } catch (Exception e) {
            return null;
        }
    }

    /**
     * @description State codes from the Ship-To Address accounts selected on return lines.
     *              Uses BillingStateCode only. A state name is never shortened into a code.
     */
    private static Map<Id, String> loadShipToStateCodes(Id customerAccountId) {
        Map<Id, String> stateCodeByShipToId = new Map<Id, String>();
        for (Account shipTo : AccountService.getShipToAddressAccounts(customerAccountId)) {
            stateCodeByShipToId.put(shipTo.Id, normalizeStateCode(shipTo.BillingStateCode));
        }
        return stateCodeByShipToId;
    }

    /**
     * @description BillingStateCode of the line's selected Ship-To. Blank when the line has no
     *              eligible Ship-To or that account has no state code.
     */
    private static String resolveLineShipStateCode(
        Map<String, Object> line,
        Map<Id, String> stateCodeByShipToId
    ) {
        if (line == null || stateCodeByShipToId == null || stateCodeByShipToId.isEmpty()) {
            return null;
        }
        Id shipToAccountId = parseId((String) line.get('shipToAccountId'));
        if (shipToAccountId == null) {
            return null;
        }
        return stateCodeByShipToId.get(shipToAccountId);
    }

    /**
     * @description Normalizes a stored state code for comparison. Does not derive a code from a name.
     */
    private static String normalizeStateCode(String stateCode) {
        if (String.isBlank(stateCode)) {
            return null;
        }
        return stateCode.trim().toUpperCase();
    }

    private static List<RepairCenterRoutingRule__c> loadRoutingRulesForOperatingUnit(String operatingUnit) {
        if (String.isBlank(operatingUnit)) {
            return new List<RepairCenterRoutingRule__c>();
        }

        return [
            SELECT
                Id,
                OperatingUnit__c,
                ProductLine__c,
                SubProductLine__c,
                Manufacturer__c,
                DeviceType__c,
                Model__c,
                ShipState__c,
                RepairCenter__c,
                RepairCenter__r.Name,
                MaxItemsPerReturn__c
            FROM RepairCenterRoutingRule__c
            WHERE OperatingUnit__c = :operatingUnit
            WITH USER_MODE
        ];
    }

    private static Map<Id, Product2> loadProductsForRouting(List<Object> lineObjects) {
        Set<Id> productIds = new Set<Id>();
        if (lineObjects != null) {
            for (Object lineObj : lineObjects) {
                Map<String, Object> line = (Map<String, Object>) lineObj;
                Id productId = parseId(String.valueOf(line.get('product2Id')));
                if (productId != null) {
                    productIds.add(productId);
                }
            }
        }
        if (productIds.isEmpty()) {
            return new Map<Id, Product2>();
        }

        return new Map<Id, Product2>([
            SELECT
                Id,
                ProductLine__c,
                SubProductLine__c,
                Manufacturer__c,
                DeviceType__c,
                Model__c
            FROM Product2
            WHERE Id IN :productIds
            WITH USER_MODE
        ]);
    }

    /**
     * @description Item-side routing segments for Oracle-style rule matching (GW-4134).
     */
    private class LineRoutingSegments {
        String productLine;
        String subProductLine;
        String manufacturer;
        String deviceType;
        String model;
    }

    private static LineRoutingSegments resolveLineRoutingSegments(
        Map<String, Object> line,
        Product2 product
    ) {
        LineRoutingSegments segments = new LineRoutingSegments();
        if (product != null) {
            segments.productLine = normalizeSegmentValue(product.ProductLine__c);
            segments.subProductLine = normalizeSegmentValue(product.SubProductLine__c);
            segments.manufacturer = normalizeSegmentValue(product.Manufacturer__c);
            segments.deviceType = normalizeSegmentValue(product.DeviceType__c);
            segments.model = normalizeSegmentValue(product.Model__c);
        }

        // Serialized (and any line with wizard Model): prefer Model from the line payload.
        if (line != null) {
            String lineModel = normalizeSegmentValue((String) line.get('model'));
            if (String.isNotBlank(lineModel)) {
                segments.model = lineModel;
            }
        }
        return segments;
    }

    private static String normalizeSegmentValue(String value) {
        if (String.isBlank(value)) {
            return null;
        }
        return value.trim();
    }

    

    private static Map<String, Integer> countNonSterilizedLinesByRepairCenter(
        List<Object> lineObjects,
        Map<Id, String> shipStateCodeByShipToId,
        List<RepairCenterRoutingRule__c> routingRules,
        Map<Id, Product2> productsById
    ) {
        Map<String, Integer> countsByRepairCenter = new Map<String, Integer>();

        for (Object lineObj : lineObjects) {
            Map<String, Object> line = (Map<String, Object>) lineObj;
            if (!isSterilizedNo(line)) {
                continue;
            }

            Product2 product = productsById.get(parseId(String.valueOf(line.get('product2Id'))));
            String repairCenterKey = resolveRepairCenterGroupKey(
                line,
                product,
                resolveLineShipStateCode(line, shipStateCodeByShipToId),
                routingRules
            );
            String splitCountKey = buildSplitAttributesGroupKey(repairCenterKey, line, product);
            Integer currentCount = countsByRepairCenter.get(splitCountKey);
            countsByRepairCenter.put(
                splitCountKey,
                currentCount == null ? 1 : currentCount + 1
            );
        }

        return countsByRepairCenter;
    }

    private static String resolveFinalGroupKey(
        Map<String, Object> line,
        Product2 product,
        String repairCenterKey,
        Map<String, Integer> nonSterilizedCountByRepairCenter,
        String shipToStateCode,
        List<RepairCenterRoutingRule__c> routingRules,
        Map<String, Integer> maxItemsLineCounters
    ) {
        String innerGroupKey;
        if (isStirrupLine(line, product)) {
            // GW-5867: only one Stirrup per Return Order.
            innerGroupKey = repairCenterKey + STIRRUP_GROUP_SUFFIX + resolveLineKey(line);
        } else if (isModRequestLine(line)) {
            innerGroupKey = buildModRequestGroupKey(repairCenterKey, resolveLineKey(line));
        } else if (!isSterilizedNo(line)) {
            innerGroupKey = repairCenterKey;
        } else {
            String splitCountKey = buildSplitAttributesGroupKey(repairCenterKey, line, product);
            Integer nonSterilizedCount = nonSterilizedCountByRepairCenter.get(splitCountKey);
            if (nonSterilizedCount != null && nonSterilizedCount > 1) {
                innerGroupKey = buildNonSterilizedBatchGroupKey(repairCenterKey);
            } else {
                innerGroupKey = buildNonSterilizedGroupKey(repairCenterKey, resolveLineKey(line));
            }
        }

        innerGroupKey = applyMaxItemsPerReturnGroupKey(
            line,
            product,
            innerGroupKey,
            shipToStateCode,
            routingRules,
            maxItemsLineCounters
        );

        return wrapGroupKeyWithReturnOrderType(line, innerGroupKey);
    }

    private static Boolean isStirrupLine(Map<String, Object> line, Product2 product) {
        String itemType = line == null ? null : (String) line.get('itemType');
        if (String.isNotBlank(itemType) && itemType.trim().equalsIgnoreCase(STIRRUP_ITEM_TYPE)) {
            return true;
        }
        return product != null &&
            String.isNotBlank(product.DeviceType__c) &&
            product.DeviceType__c.equalsIgnoreCase(STIRRUP_ITEM_TYPE);
    }

    private static String applyMaxItemsPerReturnGroupKey(
        Map<String, Object> line,
        Product2 product,
        String innerGroupKey,
        String shipToStateCode,
        List<RepairCenterRoutingRule__c> routingRules,
        Map<String, Integer> maxItemsLineCounters
    ) {
        RepairCenterRoutingRule__c matchedRule = findMatchingRoutingRule(
            line,
            product,
            shipToStateCode,
            routingRules
        );
        if (
            matchedRule == null ||
            matchedRule.MaxItemsPerReturn__c == null ||
            matchedRule.MaxItemsPerReturn__c <= 0
        ) {
            return innerGroupKey;
        }

        Integer maxItems = matchedRule.MaxItemsPerReturn__c.intValue();
        String counterKey =
            buildSplitAttributesGroupKey(innerGroupKey, line, product) +
            MAX_ITEMS_GROUP_SUFFIX;
        Integer currentCount = maxItemsLineCounters.get(counterKey);
        if (currentCount == null) {
            currentCount = 0;
        }

        Integer bucketIndex = currentCount / maxItems;
        maxItemsLineCounters.put(counterKey, currentCount + 1);
        return innerGroupKey + MAX_ITEMS_GROUP_SUFFIX + '|' + bucketIndex;
    }

    /**
     * @description GW-5553 — a return order may hold only one Product Line, one Ship-To,
     *              and one Customer PO, so all three are appended to the routing group key.
     */
    private static String buildSplitAttributesGroupKey(
        String baseGroupKey,
        Map<String, Object> line,
        Product2 product
    ) {
        String productLine = line == null ? null : (String) line.get('productLine');
        if (String.isBlank(productLine) && product != null) {
            productLine = product.ProductLine__c;
        }
        String shipToAccountId = line == null ? null : (String) line.get('shipToAccountId');
        String customerPo = line == null ? null : (String) line.get('customerPo');

        return baseGroupKey +
            PRODUCT_LINE_GROUP_SUFFIX +
            normalizeSplitSegment(productLine, true) +
            SHIP_TO_GROUP_SUFFIX +
            normalizeSplitSegment(shipToAccountId, false) +
            CUSTOMER_PO_GROUP_SUFFIX +
            normalizeSplitSegment(customerPo, true);
    }

    /**
     * @description Ids stay case-sensitive so two distinct 15-character Ids cannot collapse
     *              into one group key.
     */
    private static String normalizeSplitSegment(String value, Boolean ignoreCase) {
        if (String.isBlank(value)) {
            return UNSPECIFIED_SPLIT_SEGMENT;
        }
        return ignoreCase ? value.trim().toUpperCase() : value.trim();
    }

    

    private static String resolveLineKey(Map<String, Object> line) {
        String lineKey = (String) line.get('lineKey');
        if (String.isBlank(lineKey)) {
            lineKey = String.valueOf(Crypto.getRandomLong());
        }
        return lineKey;
    }

    private static String buildModRequestGroupKey(String repairCenterKey, String lineKey) {
        return repairCenterKey + MOD_REQUEST_GROUP_SUFFIX + '|' + lineKey;
    }

    private static String buildNonSterilizedBatchGroupKey(String repairCenterKey) {
        return repairCenterKey + NON_STERILIZED_GROUP_SUFFIX;
    }

    private static String buildNonSterilizedGroupKey(String repairCenterKey, String lineKey) {
        return repairCenterKey + NON_STERILIZED_GROUP_SUFFIX + '|' + lineKey;
    }

    private static String extractBaseRepairCenterKey(String finalGroupKey) {
        String innerGroupKey = extractInnerGroupKey(finalGroupKey);
        if (String.isBlank(innerGroupKey)) {
            return UNASSIGNED_REPAIR_CENTER_GROUP;
        }

        if (
            innerGroupKey == UNASSIGNED_REPAIR_CENTER_GROUP ||
            innerGroupKey.startsWith(UNASSIGNED_REPAIR_CENTER_GROUP + '|')
        ) {
            return UNASSIGNED_REPAIR_CENTER_GROUP;
        }

        Integer nonSterilizedSuffixIndex = innerGroupKey.indexOf(NON_STERILIZED_GROUP_SUFFIX);
        if (nonSterilizedSuffixIndex > 0) {
            return innerGroupKey.substring(0, nonSterilizedSuffixIndex);
        }

        Integer modRequestSuffixIndex = innerGroupKey.indexOf(MOD_REQUEST_GROUP_SUFFIX);
        if (modRequestSuffixIndex > 0) {
            return innerGroupKey.substring(0, modRequestSuffixIndex);
        }

        // GW-5867: Stirrup 1-per-RO keys are repairCenterId|STIRRUP|<lineKey>
        Integer stirrupSuffixIndex = innerGroupKey.indexOf(STIRRUP_GROUP_SUFFIX);
        if (stirrupSuffixIndex > 0) {
            return innerGroupKey.substring(0, stirrupSuffixIndex);
        }

        Integer maxItemsSuffixIndex = innerGroupKey.indexOf(MAX_ITEMS_GROUP_SUFFIX);
        if (maxItemsSuffixIndex > 0) {
            return innerGroupKey.substring(0, maxItemsSuffixIndex);
        }

        return innerGroupKey;
    }

    private static Boolean isModRequestLine(Map<String, Object> line) {
        return toBoolean(line.get('modRequest'));
    }

    /**
     * @description Non-disinfected split applies to Serialized, Other, and Instruments lines.
     *              Instruments Disinfected=No must not share an RO with Disinfected=Yes.
     */
    private static Boolean isSterilizedNo(Map<String, Object> line) {
        if (line == null) {
            return false;
        }
        if (
            !isSerializedLine(line) &&
            !isOtherLine(line) &&
            !isInstrumentsLine(line)
        ) {
            return false;
        }

        String disinfected = (String) line.get('disinfected');
        return String.isNotBlank(disinfected) &&
            DISINFECTED_NO_VALUES.contains(disinfected);
    }

    private static Integer resolveDisplayLineNumber(Map<String, Object> line, Integer fallback) {
        if (line == null || !line.containsKey('lineNumber') || line.get('lineNumber') == null) {
            return fallback;
        }

        Object lineNumberValue = line.get('lineNumber');
        if (lineNumberValue instanceof Integer) {
            return (Integer) lineNumberValue;
        }
        if (lineNumberValue instanceof Decimal) {
            return ((Decimal) lineNumberValue).intValue();
        }

        try {
            return Integer.valueOf(String.valueOf(lineNumberValue));
        } catch (Exception e) {
            return fallback;
        }
    }

    private static String buildMissingRoutingRuleMessage(
        Map<String, Object> line,
        String operatingUnit,
        Integer lineNumber
    ) {
        String productLine = (String) line.get('productLine');
        String productLineLabel = String.isNotBlank(productLine) ? productLine : 'the line Product Line';

        return 'Line ' +
            lineNumber +
            ': No routing rule found for Operating Unit ' +
            operatingUnit +
            ' and Product Line ' +
            productLineLabel +
            '. Update the line data or routing rules before continuing.';
    }

    private static String resolveRepairCenterGroupKey(
        Map<String, Object> line,
        Product2 product,
        String shipToStateCode,
        List<RepairCenterRoutingRule__c> routingRules
    ) {
        RepairCenterRoutingRule__c matchedRule = findMatchingRoutingRule(
            line,
            product,
            shipToStateCode,
            routingRules
        );
        if (matchedRule != null && matchedRule.RepairCenter__c != null) {
            return String.valueOf(matchedRule.RepairCenter__c);
        }
        return UNASSIGNED_REPAIR_CENTER_GROUP;
    }

    /**
     * @description GW-4134 — Oracle GET_SHIP_TO_LAB style match: 8 specificity tiers, ship-state
     *              wildcard when rule Ship State is blank, LIKE patterns on rule segments.
     *              Ship state is the selected Ship-To Account BillingStateCode.
     */
    private static RepairCenterRoutingRule__c findMatchingRoutingRule(
        Map<String, Object> line,
        Product2 product,
        String shipToStateCode,
        List<RepairCenterRoutingRule__c> routingRules
    ) {
        if (routingRules == null || routingRules.isEmpty()) {
            return null;
        }

        LineRoutingSegments item = resolveLineRoutingSegments(line, product);
        RepairCenterRoutingRule__c bestRule = null;
        Integer bestSortOrder = -1;
        String bestTieBreak = null;

        for (RepairCenterRoutingRule__c rule : routingRules) {
            if (!matchesShipState(rule.ShipState__c, shipToStateCode)) {
                continue;
            }

            Integer sortOrder = resolveRoutingRuleSortOrder(item, rule);
            if (sortOrder == null) {
                continue;
            }

            String tieBreak = buildRoutingTieBreakKey(rule);
            if (
                bestRule == null ||
                sortOrder > bestSortOrder ||
                (sortOrder == bestSortOrder &&
                    (bestTieBreak == null || tieBreak.compareTo(bestTieBreak) < 0))
            ) {
                bestRule = rule;
                bestSortOrder = sortOrder;
                bestTieBreak = tieBreak;
            }
        }

        return bestRule;
    }

    private static Boolean matchesShipState(String ruleShipState, String shipToStateCode) {
        String normalizedRuleState = normalizeStateCode(ruleShipState);
        if (String.isBlank(normalizedRuleState)) {
            return true;
        }
        if (String.isBlank(shipToStateCode)) {
            return false;
        }
        return normalizedRuleState.equalsIgnoreCase(shipToStateCode);
    }

    private static Integer resolveRoutingRuleSortOrder(
        LineRoutingSegments item,
        RepairCenterRoutingRule__c rule
    ) {
        String ruleProductLine = normalizeSegmentValue(rule.ProductLine__c);
        String ruleSubProductLine = normalizeSegmentValue(rule.SubProductLine__c);
        String ruleManufacturer = normalizeSegmentValue(rule.Manufacturer__c);
        String ruleDeviceType = normalizeSegmentValue(rule.DeviceType__c);
        String ruleModel = normalizeSegmentValue(rule.Model__c);

        // SORT_ORDER 8 — all 5 exact
        if (
            matchesExact(item.productLine, ruleProductLine) &&
            matchesExact(item.subProductLine, ruleSubProductLine) &&
            matchesExact(item.manufacturer, ruleManufacturer) &&
            matchesExact(item.deviceType, ruleDeviceType) &&
            matchesExact(item.model, ruleModel)
        ) {
            return 8;
        }

        // SORT_ORDER 7 — model LIKE (rule model required as pattern)
        if (
            matchesExact(item.productLine, ruleProductLine) &&
            matchesExact(item.subProductLine, ruleSubProductLine) &&
            matchesExact(item.manufacturer, ruleManufacturer) &&
            matchesExact(item.deviceType, ruleDeviceType) &&
            String.isNotBlank(ruleModel) &&
            matchesLike(item.model, ruleModel)
        ) {
            return 7;
        }

        // SORT_ORDER 6 — device type LIKE (rule device type required)
        if (
            matchesExact(item.productLine, ruleProductLine) &&
            matchesExact(item.subProductLine, ruleSubProductLine) &&
            matchesExact(item.manufacturer, ruleManufacturer) &&
            String.isNotBlank(ruleDeviceType) &&
            matchesLike(item.deviceType, ruleDeviceType) &&
            matchesLikeOrBlankRule(item.model, ruleModel)
        ) {
            return 6;
        }

        // SORT_ORDER 5 — device type / model COALESCE LIKE
        if (
            matchesExact(item.productLine, ruleProductLine) &&
            matchesExact(item.subProductLine, ruleSubProductLine) &&
            matchesExact(item.manufacturer, ruleManufacturer) &&
            matchesLikeOrBlankRule(item.deviceType, ruleDeviceType) &&
            matchesLikeOrBlankRule(item.model, ruleModel)
        ) {
            return 5;
        }

        // SORT_ORDER 4 — manufacturer LIKE
        if (
            matchesExact(item.productLine, ruleProductLine) &&
            matchesExact(item.subProductLine, ruleSubProductLine) &&
            String.isNotBlank(ruleManufacturer) &&
            matchesLike(item.manufacturer, ruleManufacturer) &&
            matchesLikeOrBlankRule(item.deviceType, ruleDeviceType) &&
            matchesLikeOrBlankRule(item.model, ruleModel)
        ) {
            return 4;
        }

        // SORT_ORDER 3 — sub product line LIKE
        if (
            matchesExact(item.productLine, ruleProductLine) &&
            String.isNotBlank(ruleSubProductLine) &&
            matchesLike(item.subProductLine, ruleSubProductLine) &&
            matchesLikeOrBlankRule(item.manufacturer, ruleManufacturer) &&
            matchesLikeOrBlankRule(item.deviceType, ruleDeviceType) &&
            matchesLikeOrBlankRule(item.model, ruleModel)
        ) {
            return 3;
        }

        // SORT_ORDER 2 — product line LIKE (rule product line required)
        if (
            String.isNotBlank(ruleProductLine) &&
            matchesLike(item.productLine, ruleProductLine) &&
            matchesLikeOrBlankRule(item.subProductLine, ruleSubProductLine) &&
            matchesLikeOrBlankRule(item.manufacturer, ruleManufacturer) &&
            matchesLikeOrBlankRule(item.deviceType, ruleDeviceType) &&
            matchesLikeOrBlankRule(item.model, ruleModel)
        ) {
            return 2;
        }

        // SORT_ORDER 1 — all COALESCE LIKE
        if (
            matchesLikeOrBlankRule(item.productLine, ruleProductLine) &&
            matchesLikeOrBlankRule(item.subProductLine, ruleSubProductLine) &&
            matchesLikeOrBlankRule(item.manufacturer, ruleManufacturer) &&
            matchesLikeOrBlankRule(item.deviceType, ruleDeviceType) &&
            matchesLikeOrBlankRule(item.model, ruleModel)
        ) {
            return 1;
        }

        return null;
    }

    private static String buildRoutingTieBreakKey(RepairCenterRoutingRule__c rule) {
        return nullSafeUpper(rule.Model__c) +
            '|' +
            nullSafeUpper(rule.DeviceType__c) +
            '|' +
            nullSafeUpper(rule.Manufacturer__c) +
            '|' +
            nullSafeUpper(rule.SubProductLine__c) +
            '|' +
            String.valueOf(rule.Id);
    }

    private static String nullSafeUpper(String value) {
        return String.isBlank(value) ? '' : value.trim().toUpperCase();
    }

    /**
     * @description Exact segment match (Oracle '='). Blank+blank = match.
     *              Blank rule with populated item = no match (not a wildcard on exact tiers).
     */
    private static Boolean matchesExact(String itemValue, String ruleValue) {
        if (String.isBlank(ruleValue) && String.isBlank(itemValue)) {
            return true;
        }
        if (String.isBlank(ruleValue) || String.isBlank(itemValue)) {
            return false;
        }
        return itemValue.equalsIgnoreCase(ruleValue);
    }

    /**
     * @description LIKE match where the rule value is the pattern (%foo%, foo%, %foo, or exact).
     *              Blank rule is not treated as a match here (use matchesLikeOrBlankRule).
     */
    private static Boolean matchesLike(String itemValue, String ruleValue) {
        if (String.isBlank(ruleValue) || String.isBlank(itemValue)) {
            return false;
        }
        return matchesSegmentPattern(itemValue, ruleValue);
    }

    /**
     * @description COALESCE-style LIKE: blank rule = wildcard; blank+blank = match.
     */
    private static Boolean matchesLikeOrBlankRule(String itemValue, String ruleValue) {
        if (String.isBlank(ruleValue)) {
            return true;
        }
        if (String.isBlank(itemValue)) {
            return false;
        }
        return matchesSegmentPattern(itemValue, ruleValue);
    }

    private static Boolean matchesSegmentPattern(String itemValue, String rulePattern) {
        String item = itemValue.trim();
        String pattern = rulePattern.trim();
        Boolean startsWithPercent = pattern.startsWith('%');
        Boolean endsWithPercent = pattern.endsWith('%');

        if (startsWithPercent && endsWithPercent) {
            if (pattern.length() == 1) {
                return true;
            }
            String needle = pattern.substring(1, pattern.length() - 1);
            return containsIgnoreCase(item, needle);
        }
        if (startsWithPercent) {
            String suffix = pattern.substring(1);
            return endsWithIgnoreCase(item, suffix);
        }
        if (endsWithPercent) {
            String prefix = pattern.substring(0, pattern.length() - 1);
            return startsWithIgnoreCase(item, prefix);
        }
        return item.equalsIgnoreCase(pattern);
    }

    private static Boolean containsIgnoreCase(String value, String needle) {
        if (needle == null) {
            return false;
        }
        if (needle.length() == 0) {
            return true;
        }
        return value.toUpperCase().contains(needle.toUpperCase());
    }

    private static Boolean startsWithIgnoreCase(String value, String prefix) {
        if (prefix == null) {
            return false;
        }
        if (prefix.length() == 0) {
            return true;
        }
        return value.toUpperCase().startsWith(prefix.toUpperCase());
    }

    private static Boolean endsWithIgnoreCase(String value, String suffix) {
        if (suffix == null) {
            return false;
        }
        if (suffix.length() == 0) {
            return true;
        }
        return value.toUpperCase().endsWith(suffix.toUpperCase());
    }

    private static Boolean fieldValuesMatch(String left, String right) {
        if (String.isBlank(left) || String.isBlank(right)) {
            return false;
        }
        return left.trim().equalsIgnoreCase(right.trim());
    }

    private static List<String> sortGroupKeys(Set<String> groupKeys) {
        List<String> sortedKeys = new List<String>(groupKeys);
        sortedKeys.sort();
        if (sortedKeys.contains(UNASSIGNED_REPAIR_CENTER_GROUP)) {
            sortedKeys.remove(sortedKeys.indexOf(UNASSIGNED_REPAIR_CENTER_GROUP));
            sortedKeys.add(UNASSIGNED_REPAIR_CENTER_GROUP);
        }
        return sortedKeys;
    }

    private static String resolveRepairCenterName(
        String repairCenterId,
        List<RepairCenterRoutingRule__c> routingRules
    ) {
        Id locationId = parseId(repairCenterId);
        if (locationId == null) {
            return 'Repair Center';
        }

        for (RepairCenterRoutingRule__c rule : routingRules) {
            if (rule.RepairCenter__c == locationId && rule.RepairCenter__r != null) {
                return rule.RepairCenter__r.Name;
            }
        }

        List<Schema.Location> locations = [
            SELECT Name
            FROM Location
            WHERE Id = :locationId
            WITH USER_MODE
            LIMIT 1
        ];
        return locations.isEmpty() ? 'Repair Center' : locations[0].Name;
    }

    private static Map<Id, String> loadContactNames(List<Object> lineObjects) {
        Set<Id> contactIds = new Set<Id>();
        for (Object lineObj : lineObjects) {
            Map<String, Object> line = (Map<String, Object>) lineObj;
            Id contactId = parseId((String) line.get('contactId'));
            if (contactId != null) {
                contactIds.add(contactId);
            }
        }

        Map<Id, String> namesById = new Map<Id, String>();
        if (contactIds.isEmpty()) {
            return namesById;
        }

        for (Contact contact : [
            SELECT Id, Name
            FROM Contact
            WHERE Id IN :contactIds
            WITH USER_MODE
        ]) {
            namesById.put(contact.Id, contact.Name);
        }
        return namesById;
    }

    private static Map<Id, String> loadDepartmentNames(List<Object> lineObjects) {
        Set<Id> departmentIds = new Set<Id>();
        for (Object lineObj : lineObjects) {
            Map<String, Object> line = (Map<String, Object>) lineObj;
            Id departmentId = parseId((String) line.get('departmentId'));
            if (departmentId != null) {
                departmentIds.add(departmentId);
            }
        }

        Map<Id, String> namesById = new Map<Id, String>();
        if (departmentIds.isEmpty()) {
            return namesById;
        }

        for (Department__c department : [
            SELECT Id, Name
            FROM Department__c
            WHERE Id IN :departmentIds
            WITH USER_MODE
        ]) {
            namesById.put(department.Id, department.Name);
        }
        return namesById;
    }

    private static List<ProposedReturnOrderLineSummary> buildLineSummaries(
        List<Object> groupedLines,
        Map<Id, String> contactNamesById,
        Map<Id, String> departmentNamesById
    ) {
        List<ProposedReturnOrderLineSummary> summaries = new List<ProposedReturnOrderLineSummary>();
        for (Object lineObj : groupedLines) {
            Map<String, Object> line = (Map<String, Object>) lineObj;
            ProposedReturnOrderLineSummary summary = new ProposedReturnOrderLineSummary();
            summary.lineKey = (String) line.get('lineKey');
            summary.serialNumber = (String) line.get('serialNumber');
            summary.model = (String) line.get('model');
            summary.itemDescription = (String) line.get('itemDescription');
            summary.productLine = (String) line.get('productLine');

            Id contactId = parseId((String) line.get('contactId'));
            summary.contactName = contactId != null
                ? contactNamesById.get(contactId)
                : null;

            Id departmentId = parseId((String) line.get('departmentId'));
            summary.departmentName = departmentId != null
                ? departmentNamesById.get(departmentId)
                : null;

            summary.quantityReturned = parseQuantityReturned(line.get('quantityReturned'));

            String reportedProblem = (String) line.get('reportedProblem');
            summary.reportedProblem = String.isNotBlank(reportedProblem)
                ? reportedProblem.trim()
                : null;

            summaries.add(summary);
        }
        return summaries;
    }

    /**
     * @description Maps a child work order line onto the instrument return order line fields.
     * @param lineItem Child work order line marked Send to Repair Center
     * @return Values Create Return Order shows for confirmation
     */
    private static SiteVisitInstrumentLine toSiteVisitInstrumentLine(WorkOrderLineItem lineItem) {
        SiteVisitInstrumentLine line = new SiteVisitInstrumentLine();
        line.workOrderLineItemId = lineItem.Id;
        line.product2Id = lineItem.Product2Id;
        line.productName = lineItem.Product2Id == null ? null : lineItem.Product2.Name;
        line.itemDescription = firstNonBlank(
            lineItem.Description,
            lineItem.Product2Id == null ? null : lineItem.Product2.Description,
            line.productName
        );
        line.serialNumber = lineItem.SerialNumber__c;
        line.model = firstNonBlank(
            lineItem.Model__c,
            lineItem.Product2Id == null ? null : lineItem.Product2.Model__c,
            null
        );
        line.departmentId = lineItem.Department__c;
        line.reportedProblem = lineItem.ReportedProblem__c;
        line.additionalServices = lineItem.AdditionalServices__c == true;
        line.insulationPowderCoating = line.additionalServices
            ? firstInsulationValue(lineItem.InsulationPowderCoating__c)
            : null;
        line.quantityReturned = lineItem.Quantity != null && lineItem.Quantity > 0
            ? lineItem.Quantity
            : QUANTITY_RETURNED_DEFAULT;
        return line;
    }

    /**
     * @description Collects line payloads from grouped create JSON.
     * @param groupsJson Grouped create payload from the LWC
     * @return Flat list of line maps
     */
    private static List<Object> lineObjectsFromGroupsJson(String groupsJson) {
        List<Object> lineObjects = new List<Object>();
        if (String.isBlank(groupsJson)) {
            return lineObjects;
        }
        List<Object> groupObjects = (List<Object>) JSON.deserializeUntyped(groupsJson);
        for (Object groupObj : groupObjects) {
            if (!(groupObj instanceof Map<String, Object>)) {
                continue;
            }
            Map<String, Object> groupPayload = (Map<String, Object>) groupObj;
            String lineItemsJson = (String) groupPayload.get('lineItemsJson');
            if (String.isBlank(lineItemsJson)) {
                continue;
            }
            List<Object> groupLines = (List<Object>) JSON.deserializeUntyped(lineItemsJson);
            if (groupLines != null) {
                lineObjects.addAll(groupLines);
            }
        }
        return lineObjects;
    }

    /**
     * @description GW-1353 - Clears Send to Repair Center on the lines that were placed on a return order.
     *              Lines the technician removed stay checked for the next return order.
     *              The return order is already linked to the site visit through WorkOrder__c.
     * @param lineObjects Line payloads from the create request
     */
    private static void clearSendToRepairCenter(List<Object> lineObjects) {
        Set<Id> workOrderLineItemIds = sourceWorkOrderLineItemIds(lineObjects);
        if (workOrderLineItemIds.isEmpty()) {
            return;
        }

        List<WorkOrderLineItem> updates = new List<WorkOrderLineItem>();
        for (WorkOrderLineItem lineItem : [
            SELECT Id
            FROM WorkOrderLineItem
            WHERE Id IN :workOrderLineItemIds AND SendToRepairCenter__c = TRUE
        ]) {
            updates.add(new WorkOrderLineItem(
                Id = lineItem.Id,
                SendToRepairCenter__c = false
            ));
        }
        if (!updates.isEmpty()) {
            update updates;
        }
    }

    private static Set<Id> sourceWorkOrderLineItemIds(List<Object> lineObjects) {
        Set<Id> workOrderLineItemIds = new Set<Id>();
        if (lineObjects == null) {
            return workOrderLineItemIds;
        }

        for (Object lineObj : lineObjects) {
            if (!(lineObj instanceof Map<String, Object>)) {
                continue;
            }
            Map<String, Object> line = (Map<String, Object>) lineObj;
            Object rawId = line.get('sourceWorkOrderLineItemId');
            Id workOrderLineItemId = parseId(rawId == null ? null : String.valueOf(rawId));
            if (workOrderLineItemId != null
                && workOrderLineItemId.getSobjectType() == WorkOrderLineItem.SObjectType) {
                workOrderLineItemIds.add(workOrderLineItemId);
            }
        }
        return workOrderLineItemIds;
    }

    private static String firstNonBlank(String firstValue, String secondValue, String thirdValue) {
        if (String.isNotBlank(firstValue)) {
            return firstValue.trim();
        }
        if (String.isNotBlank(secondValue)) {
            return secondValue.trim();
        }
        if (String.isNotBlank(thirdValue)) {
            return thirdValue.trim();
        }
        return null;
    }

    private static String firstInsulationValue(String value) {
        if (String.isBlank(value)) {
            return null;
        }
        for (String part : value.split(';')) {
            if (String.isNotBlank(part)) {
                return part.trim();
            }
        }
        return null;
    }
}