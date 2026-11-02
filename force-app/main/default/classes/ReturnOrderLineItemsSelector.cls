/**
 * @description Selector class for the ReturnOrderLineItem SObject.
 *              Extends SoqlQueryBuilder for generic queries; legacy selectBy* methods remain.
 */
public with sharing class ReturnOrderLineItemsSelector extends SoqlQueryBuilder {
    /**
     * @description GW-5492 - Binds this selector to ReturnOrderLineItem for SoqlQueryBuilder queries.
     */
    public ReturnOrderLineItemsSelector() {
        this.objectName = 'ReturnOrderLineItem';
    }

    private static final String BASE_FIELDS =
        'Id, ReturnOrderId, QuantityExpected, QuantityReturned, QuantityRejected, ' +
        'ReasonForReturn, Description, CreatedDate, LastModifiedDate';

    /**
     * @description Retrieves ReturnOrderLineItem records by their Ids.
     * @param ids Set of ReturnOrderLineItem Ids to query.
     * @return List of ReturnOrderLineItem records matching the given Ids.
     */
    public static List<ReturnOrderLineItem> selectById(Set<Id> ids) {
        if (ids == null || ids.isEmpty()) {
            return new List<ReturnOrderLineItem>();
        }
        return Database.query(
            'SELECT ' + BASE_FIELDS +
            ' FROM ReturnOrderLineItem' +
            ' WHERE Id IN :ids' +
            ' WITH USER_MODE'
        );
    }

    /**
     * @description Retrieves ReturnOrderLineItem records by Return Order Id.
     * @param returnOrderIds Set of ReturnOrder Ids to filter by.
     * @return List of ReturnOrderLineItem records for the given ReturnOrders.
     */
    public static List<ReturnOrderLineItem> selectByReturnOrderId(Set<Id> returnOrderIds) {
        if (returnOrderIds == null || returnOrderIds.isEmpty()) {
            return new List<ReturnOrderLineItem>();
        }
        return Database.query(
            'SELECT ' + BASE_FIELDS +
            ' FROM ReturnOrderLineItem' +
            ' WHERE ReturnOrderId IN :returnOrderIds' +
            ' WITH USER_MODE' +
            ' ORDER BY CreatedDate ASC'
        );
    }

    private static final List<String> RECEIVING_FINISH_FIELDS = new List<String>{
        'Id',
        'ReturnOrderId',
        'ReturnOrderLineItemNumber',
        'Status__c',
        'AssetId',
        'Product2Id',
        'Product2.ProductCode',
        'Product2.Description',
        'Product2.DeviceType__c',
        'ProductLine__c',
        'LineType__c',
        'QuantityReturned',
        'QuantityReceived',
        'SerialNumber__c',
        'Model__c',
        'CustomerPO__c',
        'CustomerReference__c',
        'PreviousReturnOrder__c',
        'Contact__c',
        'Department__c',
        'Description',
        'ReportedProblem__c',
        'IsLoanerAsset__c',
        'LoanerRequested__c',
        'EstimateRequired__c',
        'EstimateContact__c',
        'Disinfected__c',
        'DestinationLocationId',
        'SourceLocationId',
        'QuantityExpected',
        'QuantityUnitOfMeasure',
        'ReasonForReturn',
        'RepaymentMethod',
        'ProcessingPlan',
        'HospitalReferencedTrayName__c',
        'RepairWarranty__c',
        'WarrantyNotes__c',
        'IsPriorityRepair__c',
        'ModRequest__c',
        'ParentROLI__c'
    };

    /**
     * @description GW-5492 - Line items for Finish Receiving WO creation.
     * @param ids Return Order Line Item Ids
     * @return Matching line items
     */
    public static List<ReturnOrderLineItem> selectForReceivingFinish(Set<Id> ids) {
        if (ids == null || ids.isEmpty()) {
            return new List<ReturnOrderLineItem>();
        }
        return (List<ReturnOrderLineItem>) new ReturnOrderLineItemsSelector()
            .selectFields(RECEIVING_FINISH_FIELDS)
            .whereIn('Id', new List<Id>(ids))
            .execute();
    }

    /**
     * @description GW-4348 / GW-5996 - All Finish-Receiving fields for lines on a Return Order.
     * @param returnOrderId Return Order Id
     * @return Line items ordered by line number
     */
    public static List<ReturnOrderLineItem> selectForReceivingFinishByReturnOrderId(
        Id returnOrderId
    ) {
        if (returnOrderId == null) {
            return new List<ReturnOrderLineItem>();
        }
        return (List<ReturnOrderLineItem>) new ReturnOrderLineItemsSelector()
            .selectFields(RECEIVING_FINISH_FIELDS)
            .whereEquals('ReturnOrderId', returnOrderId)
            .orderBy('ReturnOrderLineItemNumber')
            .execute();
    }

    /**
     * @description GW-5324 - Loads Return Order lines available for Instrument Evaluation mapping.
     * @param returnOrderId Customer Return Order Id
     * @return Return Order lines with fields required by the assignment modal and auto-selection
     */
    public static List<ReturnOrderLineItem> selectForInstrumentEvaluation(Id returnOrderId) {
        if (returnOrderId == null) {
            return new List<ReturnOrderLineItem>();
        }
        return [
            SELECT
                Id,
                ReturnOrderId,
                ReturnOrder.ReturnOrderNumber,
                ReturnOrderLineItemNumber,
                AssetId,
                SerialNumber__c,
                Product2Id,
                Product2.Name,
                ItemDescription__c,
                Model__c,
                QuantityReceived
            FROM ReturnOrderLineItem
            WHERE ReturnOrderId = :returnOrderId
            WITH USER_MODE
            ORDER BY ReturnOrderLineItemNumber
        ];
    }

    /**
     * @description GW-3880 - Outbound ROLIs on Vendor Return Orders for packing slips.
     * @param returnOrderIds Vendor Return Order Ids
     * @param outboundRecordTypeId Outbound RecordType Id
     * @return Outbound line items ordered by CreatedDate
     */
    public static List<ReturnOrderLineItem> selectOutboundByReturnOrderIds(
        Set<Id> returnOrderIds,
        Id outboundRecordTypeId
    ) {
        if (
            returnOrderIds == null ||
            returnOrderIds.isEmpty() ||
            outboundRecordTypeId == null
        ) {
            return new List<ReturnOrderLineItem>();
        }
        return [
            SELECT
                Id,
                ReturnOrderId,
                QuantityReturned,
                SerialNumber__c,
                Model__c,
                Product2Id,
                Product2.Description
            FROM ReturnOrderLineItem
            WHERE ReturnOrderId IN :returnOrderIds AND RecordTypeId = :outboundRecordTypeId
            WITH USER_MODE
            ORDER BY CreatedDate
        ];
    }

    /**
     * @description GW-5492 - Counts open Created line items for a Return Order.
     * @param returnOrderId Return Order Id
     * @return Count of Created lines
     */
    public static Integer countCreatedByReturnOrderId(Id returnOrderId) {
        if (returnOrderId == null) {
            return 0;
        }
        return new ReturnOrderLineItemsSelector()
            .whereEquals('ReturnOrderId', returnOrderId)
            .whereEquals('Status__c', 'Created')
            .count();
    }

}