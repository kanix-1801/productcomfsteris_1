/**
 * @description GW-5981 - Repair Center parts requests from Device and Instrument Evaluation.
 *              Creates a Submitted Product Request and one line per part so the stockroom
 *              can fulfill the repair. Oracle move-order submission is a separate integration;
 *              this service sets the record mapping from the story and does not call the
 *              Field Service SubmissionToERP path.
 */
public with sharing class RepairCenterPartsRequestService {
    public static final String STATUS_REPAIR = 'Repair';
    public static final String STATUS_SUBMITTED = 'Submitted';
    public static final String REQUEST_TYPE_PARTS = 'Parts';
    public static final String SHIPMENT_TYPE_PICK_UP = 'Pick Up';
    public static final String RECORD_TYPE_REPAIR_CENTER = 'RepairCenter';
    public static final String COMPONENT_TYPE_PART = 'Part';
    public static final String PART_NOT_FOUND =
        'No Product could be identified for the provided Part Number: {0}.';

    /**
     * @description Active Part BOM components for the Work Order product.
     *              Uses Work Order Product, then the Asset product when Product is blank.
     * @param workOrderId Work Order Id
     * @return One row per active part, in component sequence
     */
    public static List<PartOption> getBomParts(Id workOrderId) {
        WorkOrder workOrder = requireWorkOrder(workOrderId);
        Id parentProductId = parentProductId(workOrder);
        if (parentProductId == null) {
            return new List<PartOption>();
        }

        List<PartOption> parts = new List<PartOption>();
        Set<Id> seenProductIds = new Set<Id>();
        for (ProductRelatedMaterial component : ProductRelatedMaterialsSelector.selectActivePartComponents(
            parentProductId
        )) {
            if (component.ProductComponentId == null || seenProductIds.contains(component.ProductComponentId)) {
                continue;
            }
            seenProductIds.add(component.ProductComponentId);
            parts.add(toPartOption(component.ProductComponent));
        }
        return parts;
    }

    /**
     * @description Resolves a scanned Product Code (Item Number) or Product2 Id.
     * @param scanValue Barcode or typed value
     * @return The matching product
     * @throws RepairCenterPartsRequestException when no product matches
     */
    public static PartOption findScannedPart(String scanValue) {
        String enteredValue = scanValue == null ? '' : scanValue.trim();
        if (String.isBlank(enteredValue)) {
            throw new RepairCenterPartsRequestException('Enter a part number.');
        }

        Product2 product = productFromScan(enteredValue);
        if (product == null) {
            throw new RepairCenterPartsRequestException(
                String.format(PART_NOT_FOUND, new List<String>{ enteredValue })
            );
        }
        return toPartOption(product);
    }

    /**
     * @description Product Requests linked to the Work Order, with one display line per line item.
     * @param workOrderId Work Order Id
     * @return Request rows for the Product Requests table
     */
    public static List<RequestRow> getProductRequests(Id workOrderId) {
        if (workOrderId == null) {
            return new List<RequestRow>();
        }
        List<RequestRow> rows = new List<RequestRow>();
        for (ProductRequest request : ProductRequestsSelector.selectWithLinesByWorkOrderId(
            new Set<Id>{ workOrderId }
        )) {
            rows.add(toRequestRow(request));
        }
        return rows;
    }

    /**
     * @description Creates the Repair Center parts request and its line items.
     * @param workOrderId Work Order Id
     * @param lines Selected parts and quantities
     * @return The new Product Request Id and number
     * @throws RepairCenterPartsRequestException when the Work Order cannot accept the request
     */
    public static CreateResult createPartsRequest(Id workOrderId, List<PartLineInput> lines) {
        WorkOrder workOrder = requireWorkOrder(workOrderId);
        if (workOrder.Status != STATUS_REPAIR) {
            throw new RepairCenterPartsRequestException(
                'Parts can only be requested when the Work Order Status is Repair.'
            );
        }
        if (workOrder.RepairCenter__c == null) {
            throw new RepairCenterPartsRequestException(
                'This Work Order does not have a Repair Center.'
            );
        }

        Map<Id, Decimal> quantityByProductId = quantitiesByProductId(lines);
        Map<Id, Product2> productsById = new Map<Id, Product2>(
            ProductsSelector.selectForRepairPartsRequest(quantityByProductId.keySet())
        );
        if (productsById.size() != quantityByProductId.size()) {
            throw new RepairCenterPartsRequestException('A selected part could not be found.');
        }

        Id headerTypeId = recordTypeId(ProductRequest.SObjectType);
        Id lineTypeId = recordTypeId(ProductRequestLineItem.SObjectType);
        if (headerTypeId == null || lineTypeId == null) {
            throw new RepairCenterPartsRequestException(
                'Repair Center record type is not available for Product Request.'
            );
        }

        ProductRequest header = new ProductRequest();
        header.RecordTypeId = headerTypeId;
        header.RequestType__c = REQUEST_TYPE_PARTS;
        header.WorkOrderId = workOrder.Id;
        header.DestinationLocationId = workOrder.RepairCenter__c;
        header.Status = STATUS_SUBMITTED;
        header.ShipmentType = SHIPMENT_TYPE_PICK_UP;

        List<ProductRequestLineItem> requestLines = new List<ProductRequestLineItem>();
        try {
            insert header;
            for (Id productId : quantityByProductId.keySet()) {
                Product2 product = productsById.get(productId);
                ProductRequestLineItem line = new ProductRequestLineItem();
                line.ParentId = header.Id;
                line.RecordTypeId = lineTypeId;
                line.Product2Id = product.Id;
                line.QuantityRequested = quantityByProductId.get(productId);
                line.Status = STATUS_SUBMITTED;
                if (String.isNotBlank(product.QuantityUnitOfMeasure)) {
                    line.QuantityUnitOfMeasure = product.QuantityUnitOfMeasure;
                }
                if (String.isNotBlank(product.Description)) {
                    line.Description = product.Description;
                }
                requestLines.add(line);
            }
            insert requestLines;
        } catch (DmlException e) {
            throw new RepairCenterPartsRequestException(e.getDmlMessage(0));
        }

        CreateResult result = new CreateResult();
        result.productRequestId = header.Id;
        result.productRequestNumber = ProductRequestsSelector.selectNumberById(header.Id);
        return result;
    }

    private static WorkOrder requireWorkOrder(Id workOrderId) {
        List<WorkOrder> workOrders = WorkOrdersSelector.selectForRepairCenterPartsRequest(workOrderId);
        if (workOrders.isEmpty()) {
            throw new RepairCenterPartsRequestException('Work Order was not found.');
        }
        return workOrders[0];
    }

    private static Id parentProductId(WorkOrder workOrder) {
        if (workOrder.Product__c != null) {
            return workOrder.Product__c;
        }
        return workOrder.Asset == null ? null : workOrder.Asset.Product2Id;
    }

    private static Product2 productFromScan(String enteredValue) {
        Id productId = productIdFromScan(enteredValue);
        if (productId != null) {
            List<Product2> byId = ProductsSelector.selectForRepairPartsRequest(new Set<Id>{ productId });
            return byId.isEmpty() ? null : byId[0];
        }
        List<Product2> byCode = ProductsSelector.selectByExactProductCode(enteredValue);
        return byCode.isEmpty() ? null : byCode[0];
    }

    private static Id productIdFromScan(String enteredValue) {
        if (enteredValue.length() != 15 && enteredValue.length() != 18) {
            return null;
        }
        try {
            Id value = (Id) enteredValue;
            return value.getSObjectType() == Product2.SObjectType ? value : null;
        } catch (Exception e) {
            return null;
        }
    }

    private static Map<Id, Decimal> quantitiesByProductId(List<PartLineInput> lines) {
        Map<Id, Decimal> quantityByProductId = new Map<Id, Decimal>();
        if (lines != null) {
            for (PartLineInput line : lines) {
                if (line == null || line.productId == null) {
                    continue;
                }
                if (line.quantity == null || line.quantity <= 0) {
                    throw new RepairCenterPartsRequestException(
                        'Enter a quantity greater than zero for each part.'
                    );
                }
                quantityByProductId.put(line.productId, line.quantity);
            }
        }
        if (quantityByProductId.isEmpty()) {
            throw new RepairCenterPartsRequestException('Add at least one part before saving.');
        }
        return quantityByProductId;
    }

    private static Id recordTypeId(Schema.SObjectType sobjectType) {
        Schema.RecordTypeInfo info = sobjectType
            .getDescribe()
            .getRecordTypeInfosByDeveloperName()
            .get(RECORD_TYPE_REPAIR_CENTER);
        if (info == null || !info.isActive()) {
            return null;
        }
        return info.getRecordTypeId();
    }

    private static PartOption toPartOption(Product2 product) {
        PartOption option = new PartOption();
        option.productId = product.Id;
        option.productCode = product.ProductCode;
        option.productDescription = String.isNotBlank(product.Description)
            ? product.Description
            : product.Name;
        option.label = partLabel(option.productCode, option.productDescription);
        return option;
    }

    private static String partLabel(String productCode, String productDescription) {
        if (String.isBlank(productCode)) {
            return productDescription;
        }
        if (String.isBlank(productDescription)) {
            return productCode;
        }
        return productCode + ' ' + productDescription;
    }

    private static RequestRow toRequestRow(ProductRequest request) {
        RequestRow row = new RequestRow();
        row.id = request.Id;
        row.productRequestNumber = request.ProductRequestNumber;
        row.status = request.Status;
        row.requestType = request.RequestType__c;
        row.recordUrl = '/' + request.Id;
        row.lines = new List<LineDisplay>();
        if (request.ProductRequestLineItems != null) {
            for (ProductRequestLineItem line : request.ProductRequestLineItems) {
                LineDisplay display = new LineDisplay();
                display.id = line.Id;
                Product2 product = line.Product2;
                String description = product == null
                    ? null
                    : (String.isNotBlank(product.Description) ? product.Description : product.Name);
                String label = partLabel(product == null ? null : product.ProductCode, description);
                display.displayText = label + ' (' + quantityText(line.QuantityRequested) + ')';
                row.lines.add(display);
            }
        }
        return row;
    }

    private static String quantityText(Decimal quantity) {
        return quantity == null ? '' : quantity.stripTrailingZeros().toPlainString();
    }

    /**
     * @description Part shown in the create popup.
     */
    public class PartOption {
        @AuraEnabled public Id productId;
        @AuraEnabled public String productCode;
        @AuraEnabled public String productDescription;
        @AuraEnabled public String label;
    }

    /**
     * @description Quantity captured for one part.
     */
    public class PartLineInput {
        @AuraEnabled public Id productId { get; set; }
        @AuraEnabled public Decimal quantity { get; set; }
    }

    /**
     * @description One Product Request row in the Work Order table.
     */
    public class RequestRow {
        @AuraEnabled public Id id;
        @AuraEnabled public String productRequestNumber;
        @AuraEnabled public String status;
        @AuraEnabled public String requestType;
        @AuraEnabled public String recordUrl;
        @AuraEnabled public List<LineDisplay> lines;
    }

    /**
     * @description One Product Request line, formatted for the Products Requested column.
     */
    public class LineDisplay {
        @AuraEnabled public Id id;
        @AuraEnabled public String displayText;
    }

    /**
     * @description Result of a saved parts request.
     */
    public class CreateResult {
        @AuraEnabled public Id productRequestId;
        @AuraEnabled public String productRequestNumber;
    }

    /**
     * @description Business-rule failure for a Repair Center parts request.
     */
    public class RepairCenterPartsRequestException extends Exception {}
}