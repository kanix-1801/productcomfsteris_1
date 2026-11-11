/**
 * @description Selector class for the ReturnOrderLineItem SObject.
 *              Extends SoqlQueryBuilder for invoker-built queries; legacy selectBy* methods
 *              remain for QACBM parity.
 */
public with sharing class ReturnOrderLineItemsSelector extends SoqlQueryBuilder {
    /**
     * @description Binds this selector to ReturnOrderLineItem for SoqlQueryBuilder queries.
     */
    public ReturnOrderLineItemsSelector() {
        super('ReturnOrderLineItem');
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
     * @description GW-1509 - Open Return Order lines for an Asset (Create Return Order warning).
     * @param assetId Asset Id
     * @param closedStatuses Return Order statuses treated as closed
     * @return Matching ReturnOrderLineItem rows
     */
    public static List<ReturnOrderLineItem> selectOpenByAssetId(
        Id assetId,
        Set<String> closedStatuses
    ) {
        if (assetId == null) {
            return new List<ReturnOrderLineItem>();
        }
        List<String> closedStatusList = closedStatuses == null
            ? new List<String>()
            : new List<String>(closedStatuses);
        return (List<ReturnOrderLineItem>) SoqlQueryBuilder.fromObject('ReturnOrderLineItem')
            .selectFields(
                new List<String>{
                    'ReturnOrderId',
                    'ReturnOrder.ReturnOrderNumber',
                    'ReturnOrder.Status'
                }
            )
            .whereEquals('AssetId', assetId)
            .whereField('ReturnOrder.Status', 'NOT IN', closedStatusList)
            .orderBy('ReturnOrder.ReturnOrderNumber', false, true)
            .execute();
    }

    /**
     * @description GW-5677 - Return Order lines used to build Additional Services Requested.
     * @param returnOrderId Return Order Id
     * @return All lines on the Return Order, ordered by line number
     */
    public static List<ReturnOrderLineItem> selectAdditionalServicesByReturnOrderId(Id returnOrderId) {
        if (returnOrderId == null) {
            return new List<ReturnOrderLineItem>();
        }
        return [
            SELECT
                Id,
                ReturnOrderLineItemNumber,
                ItemDescription__c,
                AdditionalServiceRepair__c,
                ColorDipping__c,
                NumberOfRings__c,
                InsulationPowderCoating__c,
                LaserMarking__c,
                LegPositionersStirrup__c
            FROM ReturnOrderLineItem
            WHERE ReturnOrderId = :returnOrderId
            WITH USER_MODE
            ORDER BY ReturnOrderLineItemNumber
        ];
    }
}