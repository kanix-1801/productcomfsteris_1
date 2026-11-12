/**
 * @description Creates a Field Service Product Request and its lines from the mobile screen,
 *              then optionally marks the request for Oracle submission.
 */
public with sharing class CreateProductRequestService {
    /** @description Ship To value when the technician address is selected. */
    public static final String SHIP_TO_MY_LOCATION = 'MyLocation';
    /** @description Ship To value when a customer address account is selected. */
    public static final String SHIP_TO_CUSTOMER = 'Customer';

    private static final String STATUS_DRAFT = 'Draft';
    private static final String RECORD_TYPE_FIELD_SERVICE = 'FieldService';
    private static final String TECHNICIAN_TYPE_TRUCK = 'Truck';
    private static final String PRODUCT_TYPE_PART = 'Part';
    private static final String SUBMISSION_SUBMIT_CREATE = 'Submit Create';
    private static final String SUBMISSION_SUBMITTED = 'Submitted';
    private static final String INTEGRATION_SUCCESS_CREATE = 'Success Create';
    private static final String INTEGRATION_FAIL_PREFIX = 'Fail';
    private static final Integer PART_SEARCH_LIMIT = 25;
    private static final String LOG_SCENARIO = 'Product Request Management';

    private static Id productRequestRecordTypeId;
    private static Id lineRecordTypeId;

    /**
     * @description Screen context for a Work Order Product Request or a standalone replenishment.
     * @param workOrderId Work Order Id. Blank for a standalone request.
     * @param userId Running user. Blank uses the current user.
     * @return Screen context, including a block message when the user cannot continue.
     * @example
     * CreateProductRequestService.getContext(workOrderId, UserInfo.getUserId());
     */
    public static ContextResult getContext(Id workOrderId, Id userId) {
        if (isServiceResourceId(workOrderId)) {
            return serviceResourceContext(workOrderId);
        }
        ContextResult context = new ContextResult();
        Id runningUserId = userId == null ? UserInfo.getUserId() : userId;
        context.productRequestRecordTypeId = productRequestTypeId();
        context.lineRecordTypeId = lineItemRecordTypeId();
        if (context.productRequestRecordTypeId == null || context.lineRecordTypeId == null) {
            context.blockMessage = Label.CreateProductRequest_RecordTypeMissing;
            return context;
        }

        WorkOrder workOrder = loadWorkOrder(workOrderId, context);
        if (context.blockMessage != null) {
            return context;
        }

        List<ServiceResource> resources = workOrder == null
            ? technicianResources(runningUserId)
            : assignedTechnicians(workOrder.Id);
        if (resources.isEmpty()) {
            context.blockMessage = workOrder == null
                ? Label.CreateProductRequest_NoServiceResource
                : Label.CreateProductRequest_NoAssignedTechnician;
            return context;
        }

        context.serviceResources = toResourceOptions(resources);
        context.selectedServiceResourceId = resources[0].Id;
        applyLocation(context, resources[0]);
        if (workOrder != null) {
            applyCustomerAddresses(context, workOrder);
            context.requiredParts = toRequiredParts(
                ProductsRequiredSelector.selectByParentRecordId(workOrder.Id)
            );
        }
        return context;
    }

    /**
     * @description Addresses for a Service Resource the screen is allowed to use.
     * @param serviceResourceId Service Resource selected on the screen.
     * @param userId Running user. Blank uses the current user.
     * @param workOrderId Work Order Id when the resource was chosen from that Work Order's appointments.
     * @return Location address choices and the visitor-address default.
     * @example
     * CreateProductRequestService.getAddresses(serviceResourceId, UserInfo.getUserId(), workOrderId);
     */
    public static AddressResult getAddresses(Id serviceResourceId, Id userId, Id workOrderId) {
        Id runningUserId = userId == null ? UserInfo.getUserId() : userId;
        ServiceResource resource = findSelectedResource(runningUserId, serviceResourceId, workOrderId);
        if (resource == null) {
            throw new CreateProductRequestException(Label.CreateProductRequest_ServiceResourceInvalid);
        }
        AddressResult result = new AddressResult();
        result.defaultAddressId = resource.Location == null ? null : resource.Location.VisitorAddressId;
        result.addresses = toNamedRecords(AddressesSelector.selectByParentId(resource.LocationId));
        if (result.defaultAddressId != null && !containsId(result.addresses, result.defaultAddressId)) {
            result.defaultAddressId = null;
        }
        return result;
    }

    /**
     * @description Active Part products whose name or product code contains the search text.
     * @param searchTerm Text or number entered by the technician.
     * @return Matching parts. An empty search returns no rows.
     * @example
     * CreateProductRequestService.searchParts('PC-4471');
     */
    public static List<PartRow> searchParts(String searchTerm) {
        List<PartRow> rows = new List<PartRow>();
        if (String.isBlank(searchTerm)) {
            return rows;
        }
        for (Product2 product : Product2Selector.selectActivePartsBySearchKey(searchTerm.trim(), PART_SEARCH_LIMIT)) {
            rows.add(toPartRow(product, null, null, false));
        }
        return rows;
    }

    /**
     * @description Inserts one Draft Product Request from the JSON posted by the mobile screen.
     * @param requestJson Screen values, including each part and quantity.
     * @return The new Product Request Id and number.
     * @throws CreateProductRequestException when the request cannot be saved.
     * @example
     * CreateProductRequestService.createRequest(requestJson);
     */
    public static CreateResult createRequest(String requestJson) {
        return createRequest(deserializeRequest(requestJson));
    }

    /**
     * @description Inserts one Draft Product Request and its lines.
     * @param request Values entered on the mobile screen.
     * @return The new Product Request Id and number.
     * @throws CreateProductRequestException when the request cannot be saved.
     * @example
     * CreateProductRequestService.createRequest(request);
     */
    public static CreateResult createRequest(CreateRequest request) {
        if (request == null) {
            throw new CreateProductRequestException(Label.CreateProductRequest_Unexpected);
        }
        applyLines(request);
        Id runningUserId = request.userId == null ? UserInfo.getUserId() : request.userId;
        Id contextId = request.workOrderId;
        if (isServiceResourceId(contextId)) {
            request.workOrderId = null;
        }
        ServiceResource resource = findSelectedResource(
            runningUserId,
            request.serviceResourceId,
            contextId
        );
        if (resource == null) {
            throw new CreateProductRequestException(Label.CreateProductRequest_ServiceResourceInvalid);
        }
        WorkOrder workOrder = request.workOrderId == null
            ? null
            : WorkOrderSelector.selectForProductRequest(request.workOrderId);
        if (request.workOrderId != null && workOrder == null) {
            throw new CreateProductRequestException(Label.CreateProductRequest_WorkOrderNotFound);
        }

        Datetime needByDate = parseNeedByDate(request.needByDate);
        validateHeader(request, resource, workOrder, needByDate);
        List<ProductRequestLineItem> lines = buildLines(request, resource, workOrder, needByDate);

        ProductRequest productRequest = buildHeader(request, resource, workOrder, needByDate);
        Logger.setScenario(LOG_SCENARIO);
        Savepoint savepoint = Database.setSavepoint();
        try {
            insert productRequest;
            for (ProductRequestLineItem line : lines) {
                line.ParentId = productRequest.Id;
            }
            insert lines;
        } catch (DmlException e) {
            Database.rollback(savepoint);
            Logger.error('CreateProductRequestService.createRequest failed.', productRequest, e);
            throw new CreateProductRequestException(e.getDmlMessage(0));
        } catch (Exception e) {
            Database.rollback(savepoint);
            Logger.error('CreateProductRequestService.createRequest failed.', productRequest, e);
            throw new CreateProductRequestException(Label.CreateProductRequest_Unexpected);
        } finally {
            Logger.saveLog();
        }

        CreateResult result = new CreateResult();
        result.productRequestId = productRequest.Id;
        result.productRequestNumber = productRequestNumber(productRequest.Id);
        return result;
    }

    /**
     * @description Sets Submission to ERP to Submit Create for a Product Request the user can see.
     * @param productRequestId Product Request created by this screen.
     * @throws CreateProductRequestException when the update fails.
     * @example
     * CreateProductRequestService.submitToErp(productRequestId);
     */
    public static void submitToErp(Id productRequestId) {
        ProductRequest currentRow = requireForOracleSubmit(productRequestId);
        String blockMessage = oracleSubmitBlockMessage(currentRow);
        if (blockMessage != null) {
            throw new CreateProductRequestException(blockMessage);
        }
        ProductRequest updateRow = new ProductRequest(
            Id = productRequestId,
            SubmissionToERP__c = SUBMISSION_SUBMIT_CREATE
        );
        Logger.setScenario(LOG_SCENARIO);
        try {
            update updateRow;
        } catch (DmlException e) {
            Logger.error('CreateProductRequestService.submitToErp failed.', updateRow, e);
            throw new CreateProductRequestException(e.getDmlMessage(0));
        } catch (Exception e) {
            Logger.error('CreateProductRequestService.submitToErp failed.', updateRow, e);
            throw new CreateProductRequestException(Label.CreateProductRequest_Unexpected);
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description Eligibility and prior integration text for the Oracle confirm screen.
     * @param productRequestId Product Request created by this screen.
     * @return Whether Submit Create is allowed, and the prior integration result.
     * @throws CreateProductRequestException when the Product Request cannot be read.
     * @example
     * CreateProductRequestService.getOracleSubmitPreview(productRequestId);
     */
    public static OracleSubmitPreview getOracleSubmitPreview(Id productRequestId) {
        ProductRequest currentRow = requireForOracleSubmit(productRequestId);
        OracleSubmitPreview preview = new OracleSubmitPreview();
        preview.productRequestNumber = currentRow.ProductRequestNumber;
        preview.integrationStatus = currentRow.IntegrationStatus__c;
        preview.integrationMessage = currentRow.IntegrationMessage__c;
        preview.showPriorResult = String.isNotBlank(currentRow.IntegrationStatus__c)
            && currentRow.IntegrationStatus__c.startsWith(INTEGRATION_FAIL_PREFIX);
        preview.blockMessage = oracleSubmitBlockMessage(currentRow);
        preview.eligible = preview.blockMessage == null;
        return preview;
    }

    private static ProductRequest requireForOracleSubmit(Id productRequestId) {
        if (productRequestId == null) {
            throw new CreateProductRequestException(Label.CreateProductRequest_NotFound);
        }
        List<ProductRequest> rows = ProductRequestsSelector.selectForOracleSubmit(
            new Set<Id>{ productRequestId }
        );
        if (rows.isEmpty()) {
            throw new CreateProductRequestException(Label.CreateProductRequest_NotFound);
        }
        return rows[0];
    }

    private static String oracleSubmitBlockMessage(ProductRequest productRequest) {
        if (productRequest.Status != STATUS_DRAFT) {
            return Label.CreateProductRequest_CannotSubmit;
        }
        if (productRequest.SubmissionToERP__c == SUBMISSION_SUBMITTED
            && String.isBlank(productRequest.IntegrationStatus__c)) {
            return Label.CreateProductRequest_SubmitInFlight;
        }
        if (productRequest.IntegrationStatus__c == INTEGRATION_SUCCESS_CREATE
            && String.isNotBlank(productRequest.ERPOrderNumber__c)) {
            return Label.CreateProductRequest_AlreadyInErp.replace('{0}', productRequest.ERPOrderNumber__c);
        }
        if (productRequest.ProductRequestLineItems == null
            || productRequest.ProductRequestLineItems.isEmpty()) {
            return Label.CreateProductRequest_NoLinesForErp;
        }
        return null;
    }

    private static WorkOrder loadWorkOrder(Id workOrderId, ContextResult context) {
        if (workOrderId == null) {
            context.hasWorkOrder = false;
            return null;
        }
        WorkOrder workOrder = WorkOrderSelector.selectForProductRequest(workOrderId);
        if (workOrder == null) {
            context.blockMessage = Label.CreateProductRequest_WorkOrderNotFound;
            return null;
        }
        context.hasWorkOrder = true;
        context.workOrderId = workOrder.Id;
        context.workOrderNumber = workOrder.WorkOrderNumber;
        context.subject = workOrder.Subject;
        return workOrder;
    }

    private static void applyLocation(ContextResult context, ServiceResource resource) {
        context.defaultAddressId = resource.Location == null ? null : resource.Location.VisitorAddressId;
        context.addresses = toNamedRecords(AddressesSelector.selectByParentId(resource.LocationId));
        if (context.defaultAddressId != null && !containsId(context.addresses, context.defaultAddressId)) {
            context.defaultAddressId = null;
        }
    }

    private static void applyCustomerAddresses(ContextResult context, WorkOrder workOrder) {
        Map<Id, Account> accountsById = new Map<Id, Account>();
        if (workOrder.ShipToAddressAccount__c != null) {
            for (Account shipToAccount : addressAccountsByIds(
                new Set<Id>{ workOrder.ShipToAddressAccount__c }
            )) {
                accountsById.put(shipToAccount.Id, shipToAccount);
            }
        }
        for (Account childAccount : shipToAccountsByParentId(workOrder.AccountId)) {
            accountsById.put(childAccount.Id, childAccount);
        }
        context.shipToAccounts = toNamedRecords(accountsById.values());
        if (workOrder.ShipToAddressAccount__c != null
            && accountsById.containsKey(workOrder.ShipToAddressAccount__c)) {
            context.defaultShipToAccountId = workOrder.ShipToAddressAccount__c;
        }
    }

    private static void validateHeader(
        CreateRequest request,
        ServiceResource resource,
        WorkOrder workOrder,
        Datetime needByDate
    ) {
        if (needByDate == null) {
            throw new CreateProductRequestException(Label.CreateProductRequest_DeliveryDateRequired);
        }
        if (String.isBlank(request.shipmentType) || !isActiveShipmentType(request.shipmentType)) {
            throw new CreateProductRequestException(Label.CreateProductRequest_ShipmentTypeRequired);
        }
        if (request.shipToMode == SHIP_TO_CUSTOMER && workOrder == null) {
            throw new CreateProductRequestException(Label.CreateProductRequest_CustomerNeedsWorkOrder);
        }
        if (request.shipToMode == SHIP_TO_MY_LOCATION) {
            Set<Id> addressIds = new Map<Id, Schema.Address>(
                AddressesSelector.selectByParentId(resource.LocationId)
            ).keySet();
            if (request.addressId == null || !addressIds.contains(request.addressId)) {
                throw new CreateProductRequestException(Label.CreateProductRequest_AddressRequired);
            }
            return;
        }
        if (request.shipToMode == SHIP_TO_CUSTOMER) {
            if (request.shipToAccountId == null || !customerAccountIds(workOrder).contains(request.shipToAccountId)) {
                throw new CreateProductRequestException(Label.CreateProductRequest_CustomerRequired);
            }
            return;
        }
        throw new CreateProductRequestException(Label.CreateProductRequest_AddressRequired);
    }

    private static Set<Id> customerAccountIds(WorkOrder workOrder) {
        Set<Id> accountIds = new Set<Id>();
        if (workOrder.ShipToAddressAccount__c != null) {
            for (Account shipToAccount : addressAccountsByIds(
                new Set<Id>{ workOrder.ShipToAddressAccount__c }
            )) {
                accountIds.add(shipToAccount.Id);
            }
        }
        for (Account childAccount : shipToAccountsByParentId(workOrder.AccountId)) {
            accountIds.add(childAccount.Id);
        }
        return accountIds;
    }

    private static ProductRequest buildHeader(
        CreateRequest request,
        ServiceResource resource,
        WorkOrder workOrder,
        Datetime needByDate
    ) {
        ProductRequest productRequest = new ProductRequest();
        productRequest.NeedByDate = needByDate;
        productRequest.ShipmentType = request.shipmentType;
        productRequest.ShipSet__c = request.shipSet == true;
        productRequest.ServiceResource__c = resource.Id;
        productRequest.DestinationLocationId = resource.LocationId;
        productRequest.Status = STATUS_DRAFT;
        productRequest.RecordTypeId = productRequestTypeId();
        if (request.shipToMode == SHIP_TO_MY_LOCATION) {
            productRequest.ShipToTechnicianAddress__c = request.addressId;
        } else {
            productRequest.ShipToAddressAccount__c = request.shipToAccountId;
        }
        if (workOrder != null) {
            productRequest.WorkOrderId = workOrder.Id;
            productRequest.AccountId = workOrder.AccountId;
            productRequest.CaseId = workOrder.CaseId;
        }
        return productRequest;
    }

    private static List<ProductRequestLineItem> buildLines(
        CreateRequest request,
        ServiceResource resource,
        WorkOrder workOrder,
        Datetime needByDate
    ) {
        Map<Id, Decimal> quantityByProductId = new Map<Id, Decimal>();
        Map<Id, Boolean> shipSetByProductId = new Map<Id, Boolean>();
        Boolean headerShipSet = request.shipSet == true;
        if (request.lines != null) {
            for (LineRequest line : request.lines) {
                if (line == null || line.productId == null || line.quantity == null || line.quantity <= 0) {
                    continue;
                }
                Decimal quantity = quantityByProductId.containsKey(line.productId)
                    ? quantityByProductId.get(line.productId)
                    : 0;
                quantityByProductId.put(line.productId, quantity + line.quantity);
                Boolean lineShipSet = headerShipSet || line.shipSet == true;
                if (shipSetByProductId.containsKey(line.productId)) {
                    lineShipSet = shipSetByProductId.get(line.productId) || lineShipSet;
                }
                shipSetByProductId.put(line.productId, lineShipSet);
            }
        }
        if (quantityByProductId.isEmpty()) {
            throw new CreateProductRequestException(Label.CreateProductRequest_PartsRequired);
        }

        Map<Id, Product2> productsById = new Map<Id, Product2>(
            Product2Selector.selectActivePartsByIds(quantityByProductId.keySet())
        );
        if (productsById.size() != quantityByProductId.size()) {
            throw new CreateProductRequestException(Label.CreateProductRequest_PartNotFound);
        }

        Id lineTypeId = lineItemRecordTypeId();
        if (lineTypeId == null || productRequestTypeId() == null) {
            throw new CreateProductRequestException(Label.CreateProductRequest_RecordTypeMissing);
        }

        List<ProductRequestLineItem> lines = new List<ProductRequestLineItem>();
        for (Id productId : quantityByProductId.keySet()) {
            Product2 product = productsById.get(productId);
            ProductRequestLineItem line = new ProductRequestLineItem();
            line.Product2Id = product.Id;
            line.QuantityRequested = quantityByProductId.get(productId);
            line.QuantityUnitOfMeasure = product.QuantityUnitOfMeasure;
            line.Description = product.Description;
            line.NeedByDate = needByDate;
            line.ShipmentType = request.shipmentType;
            line.ShipSet__c = shipSetByProductId.get(productId) == true;
            line.DestinationLocationId = resource.LocationId;
            line.Status = STATUS_DRAFT;
            line.RecordTypeId = lineTypeId;
            if (workOrder != null) {
                line.WorkOrderId = workOrder.Id;
                line.AccountId = workOrder.AccountId;
                line.CaseId = workOrder.CaseId;
            }
            lines.add(line);
        }
        return lines;
    }

    private static Boolean isServiceResourceId(Id recordId) {
        return recordId != null && recordId.getSObjectType() == ServiceResource.SObjectType;
    }

    private static ContextResult serviceResourceContext(Id serviceResourceId) {
        ContextResult context = new ContextResult();
        context.productRequestRecordTypeId = productRequestTypeId();
        context.lineRecordTypeId = lineItemRecordTypeId();
        if (context.productRequestRecordTypeId == null || context.lineRecordTypeId == null) {
            context.blockMessage = Label.CreateProductRequest_RecordTypeMissing;
            return context;
        }
        context.hasWorkOrder = false;
        List<ServiceResource> resources = ServiceResourcesSelector.selectActiveTechniciansByIds(
            new Set<Id>{ serviceResourceId }
        );
        if (resources.isEmpty()) {
            context.blockMessage = Label.CreateProductRequest_NoServiceResource;
            return context;
        }
        context.serviceResources = toResourceOptions(resources);
        context.selectedServiceResourceId = resources[0].Id;
        applyLocation(context, resources[0]);
        return context;
    }

    private static List<ServiceResource> technicianResources(Id userId) {
        List<ServiceResource> resources = new List<ServiceResource>();
        for (ServiceResource resource : ServiceResourcesSelector.selectActiveByUserId(userId)) {
            if (resource.TechnicianType__c != TECHNICIAN_TYPE_TRUCK) {
                resources.add(resource);
            }
        }
        return resources;
    }

    private static List<ServiceResource> assignedTechnicians(Id workOrderId) {
        Set<Id> resourceIds = new Set<Id>();
        for (AssignedResource assignment : AssignedResourcesSelector.selectByWorkOrderId(workOrderId)) {
            if (assignment.ServiceResourceId != null) {
                resourceIds.add(assignment.ServiceResourceId);
            }
        }
        return ServiceResourcesSelector.selectActiveTechniciansByIds(resourceIds);
    }

    private static ServiceResource findSelectedResource(Id userId, Id serviceResourceId, Id workOrderId) {
        List<ServiceResource> resources;
        if (isServiceResourceId(workOrderId)) {
            resources = ServiceResourcesSelector.selectActiveTechniciansByIds(new Set<Id>{ workOrderId });
        } else if (workOrderId == null) {
            resources = technicianResources(userId);
        } else {
            resources = assignedTechnicians(workOrderId);
        }
        for (ServiceResource resource : resources) {
            if (resource.Id == serviceResourceId) {
                return resource;
            }
        }
        return null;
    }

    private static List<Account> addressAccountsByIds(Set<Id> accountIds) {
        if (accountIds == null || accountIds.isEmpty()) {
            return new List<Account>();
        }
        return (List<Account>) SoqlQueryBuilder.fromObject('Account')
            .selectFields(new List<String>{ 'Id', 'Name', 'Type', 'BillingStreet', 'BillingCity' })
            .whereField('Id', 'IN', new List<Id>(accountIds))
            .whereEquals('Type', 'Address')
            .execute();
    }

    private static List<Account> shipToAccountsByParentId(Id parentAccountId) {
        if (parentAccountId == null) {
            return new List<Account>();
        }
        return (List<Account>) SoqlQueryBuilder.fromObject('Account')
            .selectFields(new List<String>{
                'Id', 'Name', 'Type', 'ShiptoAddressStatus__c', 'BillingStreet', 'BillingCity'
            })
            .whereEquals('ParentId', parentAccountId)
            .whereEquals('Type', 'Address')
            .whereField('ShiptoAddressStatus__c', 'IN', new List<String>{ 'Active', 'Primary' })
            .orderBy('Name')
            .execute();
    }

    private static String productRequestNumber(Id productRequestId) {
        ProductRequest stored = (ProductRequest) SoqlQueryBuilder.fromObject('ProductRequest')
            .selectField('ProductRequestNumber')
            .whereEquals('Id', productRequestId)
            .first();
        return stored == null ? null : stored.ProductRequestNumber;
    }

    private static Id productRequestTypeId() {
        if (productRequestRecordTypeId == null) {
            productRequestRecordTypeId = availableRecordTypeId(
                Schema.SObjectType.ProductRequest.getRecordTypeInfosByDeveloperName()
                    .get(RECORD_TYPE_FIELD_SERVICE)
            );
        }
        return productRequestRecordTypeId;
    }

    private static Id lineItemRecordTypeId() {
        if (lineRecordTypeId == null) {
            lineRecordTypeId = availableRecordTypeId(
                Schema.SObjectType.ProductRequestLineItem.getRecordTypeInfosByDeveloperName()
                    .get(RECORD_TYPE_FIELD_SERVICE)
            );
        }
        return lineRecordTypeId;
    }

    private static Id availableRecordTypeId(Schema.RecordTypeInfo info) {
        if (info == null || !info.isActive()) {
            return null;
        }
        return info.getRecordTypeId();
    }

    private static Boolean isActiveShipmentType(String shipmentType) {
        for (Schema.PicklistEntry entry : ProductRequest.ShipmentType.getDescribe().getPicklistValues()) {
            if (entry.isActive() && entry.getValue() == shipmentType) {
                return true;
            }
        }
        return false;
    }

    private static Datetime parseNeedByDate(String value) {
        if (String.isBlank(value)) {
            return null;
        }
        String normalized = value.trim().replace('T', ' ').replace('Z', '');
        Integer decimalPoint = normalized.indexOf('.');
        if (decimalPoint > 0) {
            normalized = normalized.substring(0, decimalPoint);
        }
        try {
            if (!normalized.contains(' ')) {
                return Datetime.newInstance(Date.valueOf(normalized), Time.newInstance(0, 0, 0, 0));
            }
            return Datetime.valueOfGmt(normalized);
        } catch (TypeException e) {
            return null;
        }
    }

    private static CreateRequest deserializeRequest(String requestJson) {
        if (String.isBlank(requestJson)) {
            throw new CreateProductRequestException(Label.CreateProductRequest_Unexpected);
        }
        try {
            return (CreateRequest) JSON.deserialize(requestJson, CreateRequest.class);
        } catch (JSONException e) {
            throw new CreateProductRequestException(Label.CreateProductRequest_Unexpected);
        }
    }

    private static void applyLines(CreateRequest request) {
        if (String.isBlank(request.linesJson)) {
            return;
        }
        try {
            request.lines = (List<LineRequest>) JSON.deserialize(request.linesJson, List<LineRequest>.class);
        } catch (JSONException e) {
            throw new CreateProductRequestException(Label.CreateProductRequest_PartsRequired);
        }
    }

    private static List<ResourceOption> toResourceOptions(List<ServiceResource> resources) {
        List<ResourceOption> options = new List<ResourceOption>();
        for (ServiceResource resource : resources) {
            ResourceOption option = new ResourceOption();
            option.recordId = resource.Id;
            option.name = resource.Name;
            options.add(option);
        }
        return options;
    }

    private static List<NamedRecord> toNamedRecords(List<Schema.Address> addresses) {
        List<NamedRecord> options = new List<NamedRecord>();
        for (Schema.Address addressRecord : addresses) {
            options.add(namedRecord(addressRecord.Id, addressLabel(addressRecord)));
        }
        options.sort();
        return options;
    }

    private static List<NamedRecord> toNamedRecords(List<Account> accounts) {
        List<NamedRecord> options = new List<NamedRecord>();
        for (Account accountRecord : accounts) {
            options.add(namedRecord(accountRecord.Id, accountLabel(accountRecord)));
        }
        options.sort();
        return options;
    }

    private static String addressLabel(Schema.Address addressRecord) {
        if (String.isNotBlank(addressRecord.AddressShipTo__c)) {
            return addressRecord.AddressShipTo__c;
        }
        return addressRecord.Name;
    }

    private static String accountLabel(Account accountRecord) {
        List<String> parts = new List<String>();
        addLabelPart(parts, accountRecord.Name);
        addLabelPart(parts, accountRecord.BillingStreet);
        addLabelPart(parts, accountRecord.BillingCity);
        return String.join(parts, ', ');
    }

    private static void addLabelPart(List<String> parts, String value) {
        if (String.isBlank(value)) {
            return;
        }
        String trimmed = value.trim();
        for (String existing : parts) {
            if (existing.equalsIgnoreCase(trimmed)) {
                return;
            }
        }
        parts.add(trimmed);
    }

    private static NamedRecord namedRecord(Id recordId, String name) {
        NamedRecord option = new NamedRecord();
        option.recordId = recordId;
        option.name = name;
        return option;
    }

    private static List<PartRow> toRequiredParts(List<ProductRequired> requiredRows) {
        List<PartRow> rows = new List<PartRow>();
        for (ProductRequired requiredRow : requiredRows) {
            if (requiredRow.Product2Id == null) {
                continue;
            }
            Decimal quantity = requiredRow.QuantityRequired == null ? 0 : requiredRow.QuantityRequired;
            rows.add(toPartRow(requiredRow.Product2, requiredRow, quantity, true));
        }
        return rows;
    }

    private static PartRow toPartRow(
        Product2 product,
        ProductRequired requiredRow,
        Decimal quantity,
        Boolean requiredOnWorkOrder
    ) {
        PartRow row = new PartRow();
        row.key = requiredRow == null ? String.valueOf(product.Id) : String.valueOf(requiredRow.Id);
        row.productId = product == null ? requiredRow.Product2Id : product.Id;
        row.name = product == null || String.isBlank(product.Name) ? requiredRow.ProductName : product.Name;
        row.productCode = product == null ? null : product.ProductCode;
        row.quantityUnitOfMeasure = product == null || String.isBlank(product.QuantityUnitOfMeasure)
            ? (requiredRow == null ? null : requiredRow.QuantityUnitOfMeasure)
            : product.QuantityUnitOfMeasure;
        row.quantity = quantity;
        row.requiredOnWorkOrder = requiredOnWorkOrder;
        row.substitutePart = substitutePartName(product);
        return row;
    }

    private static String substitutePartName(Product2 product) {
        if (product == null || product.SubstitutePart__r == null
            || String.isBlank(product.SubstitutePart__r.Name)) {
            return null;
        }
        return product.SubstitutePart__r.Name;
    }

    private static Boolean containsId(List<NamedRecord> records, Id recordId) {
        for (NamedRecord record : records) {
            if (record.recordId == recordId) {
                return true;
            }
        }
        return false;
    }

    /**
     * @description Values the mobile screen needs before the technician enters a request.
     */
    public class ContextResult {
        /** @description True when the screen was opened from a Work Order. */
        @AuraEnabled public Boolean hasWorkOrder = false;
        /** @description Shown instead of the form when the user cannot continue. */
        @AuraEnabled public String blockMessage;
        /** @description Work Order Id, when the screen was opened from a Work Order. */
        @AuraEnabled public Id workOrderId;
        /** @description Work Order number shown on the card. */
        @AuraEnabled public String workOrderNumber;
        /** @description Work Order subject shown on the card. */
        @AuraEnabled public String subject;
        /** @description Field Service Product Request record type, used for the shipment picklist. */
        @AuraEnabled public Id productRequestRecordTypeId;
        /** @description Field Service Product Request Line Item record type. */
        @AuraEnabled public Id lineRecordTypeId;
        /** @description Active technician Service Resources for the running user. */
        @AuraEnabled public List<ResourceOption> serviceResources = new List<ResourceOption>();
        /** @description Service Resource selected when the screen opens. */
        @AuraEnabled public Id selectedServiceResourceId;
        /** @description Visitor address on the selected Service Resource location. */
        @AuraEnabled public Id defaultAddressId;
        /** @description Addresses for the selected Service Resource location. */
        @AuraEnabled public List<NamedRecord> addresses = new List<NamedRecord>();
        /** @description Work Order ship-to account when it is an eligible address account. */
        @AuraEnabled public Id defaultShipToAccountId;
        /** @description Customer ship-to accounts. Empty for a standalone request. */
        @AuraEnabled public List<NamedRecord> shipToAccounts = new List<NamedRecord>();
        /** @description Product Required rows for the Work Order. */
        @AuraEnabled public List<PartRow> requiredParts = new List<PartRow>();
    }

    /**
     * @description Address choices after the technician changes Service Resource.
     */
    public class AddressResult {
        /** @description Visitor address when it belongs to the location. */
        @AuraEnabled public Id defaultAddressId;
        /** @description Addresses whose parent is the Service Resource location. */
        @AuraEnabled public List<NamedRecord> addresses = new List<NamedRecord>();
    }

    /**
     * @description Id and name shown in a mobile picklist. The Id is submitted with the request.
     */
    public class NamedRecord implements Comparable {
        /** @description Record Id kept for the Product Request mapping. */
        @AuraEnabled public Id recordId;
        /** @description Name shown to the technician. */
        @AuraEnabled public String name;

        /**
         * @description Sorts address and account choices by name.
         * @param other The other choice.
         * @return Comparison result for List.sort.
         */
        public Integer compareTo(Object other) {
            NamedRecord otherRecord = (NamedRecord) other;
            String thisName = name == null ? '' : name;
            String otherName = otherRecord.name == null ? '' : otherRecord.name;
            return thisName.toLowerCase().compareTo(otherName.toLowerCase());
        }
    }

    /**
     * @description Service Resource choice.
     */
    public class ResourceOption {
        /** @description Service Resource Id. */
        @AuraEnabled public Id recordId;
        /** @description Service Resource name. */
        @AuraEnabled public String name;
    }

    /**
     * @description One part row returned to the screen.
     */
    public class PartRow {
        /** @description Stable key for the row. */
        @AuraEnabled public String key;
        /** @description Product2 Id. */
        @AuraEnabled public Id productId;
        /** @description Product name. */
        @AuraEnabled public String name;
        /** @description Product code. */
        @AuraEnabled public String productCode;
        /** @description Quantity unit of measure from the product. */
        @AuraEnabled public String quantityUnitOfMeasure;
        /** @description Quantity requested. Blank until the technician adds the part. */
        @AuraEnabled public Decimal quantity;
        /** @description True when the row came from Product Required. */
        @AuraEnabled public Boolean requiredOnWorkOrder;
        /** @description Name of Product2.SubstitutePart__c when the product has one. */
        @AuraEnabled public String substitutePart;
    }

    /**
     * @description Values posted when the technician saves the screen.
     */
    public class CreateRequest {
        /** @description Work Order Id. Blank for a standalone request. */
        @AuraEnabled public Id workOrderId;
        /** @description Running user. Blank uses the current user. */
        @AuraEnabled public Id userId;
        /** @description Selected Service Resource. */
        @AuraEnabled public Id serviceResourceId;
        /** @description Required delivery date. A date, or an ISO datetime. */
        @AuraEnabled public String needByDate;
        /** @description ProductRequest.ShipmentType value. */
        @AuraEnabled public String shipmentType;
        /** @description ProductRequest.ShipSet__c. True checks every line. */
        @AuraEnabled public Boolean shipSet;
        /** @description MyLocation or Customer. */
        @AuraEnabled public String shipToMode;
        /** @description Address Id when Ship To is My location. */
        @AuraEnabled public Id addressId;
        /** @description Account Id when Ship To is Customer. */
        @AuraEnabled public Id shipToAccountId;
        /** @description Parts and quantities to create as line items. */
        @AuraEnabled public List<LineRequest> lines;
        /** @description Same lines as JSON, so the quantities survive the mobile save. */
        @AuraEnabled public String linesJson;
    }

    /**
     * @description One part and quantity on the save request.
     */
    public class LineRequest {
        /** @description Product2 Id. */
        @AuraEnabled public Id productId;
        /** @description Quantity requested. */
        @AuraEnabled public Decimal quantity;
        /** @description ProductRequestLineItem.ShipSet__c. Defaults to false. */
        @AuraEnabled public Boolean shipSet;
    }

    /**
     * @description Product Request created by the screen.
     */
    public class CreateResult {
        /** @description New Product Request Id. */
        @AuraEnabled public Id productRequestId;
        /** @description Product Request number. */
        @AuraEnabled public String productRequestNumber;
    }

    /**
     * @description Oracle confirm-screen values for a Product Request.
     */
    public class OracleSubmitPreview {
        /** @description True when Submission to ERP can be set to Submit Create. */
        @AuraEnabled public Boolean eligible;
        /** @description Why the request cannot be submitted. Blank when eligible is true. */
        @AuraEnabled public String blockMessage;
        /** @description Product Request number shown on the confirm screen. */
        @AuraEnabled public String productRequestNumber;
        /** @description Integration Status from the last Oracle attempt. */
        @AuraEnabled public String integrationStatus;
        /** @description Integration Message from the last Oracle attempt. */
        @AuraEnabled public String integrationMessage;
        /** @description True when a failed integration result should be shown. */
        @AuraEnabled public Boolean showPriorResult;
    }
}