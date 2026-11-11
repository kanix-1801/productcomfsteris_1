/**
 * @description Selector class for the ReturnOrder SObject.
 *              Extends SoqlQueryBuilder for generic queries; legacy selectBy* methods remain.
 */
public with sharing class ReturnOrdersSelector extends SoqlQueryBuilder {
    /**
     * @description GW-5492 - Binds this selector to ReturnOrder for SoqlQueryBuilder queries.
     */
    public ReturnOrdersSelector() {
        this.objectName = 'ReturnOrder';
    }

    private static final String BASE_FIELDS =
        'Id, ReturnOrderNumber, Status, ReturnedById, AccountId, CaseId, ContactId, ' +
        'Description, OwnerId, CreatedDate, LastModifiedDate';

    /**
     * @description Retrieves ReturnOrder records by their Ids.
     * @param ids Set of ReturnOrder Ids to query.
     * @return List of ReturnOrder records matching the given Ids.
     */
    public static List<ReturnOrder> selectById(Set<Id> ids) {
        if (ids == null || ids.isEmpty()) {
            return new List<ReturnOrder>();
        }
        return Database.query(
            'SELECT ' + BASE_FIELDS +
            ' FROM ReturnOrder' +
            ' WHERE Id IN :ids' +
            ' WITH USER_MODE'
        );
    }

    /**
     * @description Retrieves ReturnOrder records by Account Id.
     * @param accountIds Set of Account Ids to filter by.
     * @return List of ReturnOrder records for the given Accounts.
     */
    public static List<ReturnOrder> selectByAccountId(Set<Id> accountIds) {
        if (accountIds == null || accountIds.isEmpty()) {
            return new List<ReturnOrder>();
        }
        return Database.query(
            'SELECT ' + BASE_FIELDS +
            ' FROM ReturnOrder' +
            ' WHERE AccountId IN :accountIds' +
            ' WITH USER_MODE' +
            ' ORDER BY CreatedDate DESC'
        );
    }

    /**
     * @description Retrieves ReturnOrder records with their line items.
     * @param ids Set of ReturnOrder Ids to query.
     * @return List of ReturnOrder records with child ReturnOrderLineItem records.
     */
    public static List<ReturnOrder> selectByIdWithLineItems(Set<Id> ids) {
        if (ids == null || ids.isEmpty()) {
            return new List<ReturnOrder>();
        }
        return Database.query(
            'SELECT ' + BASE_FIELDS +
            ', (SELECT Id, ReturnOrderId, QuantityExpected, QuantityReturned, QuantityRejected, ' +
            '   ReasonForReturn, Description FROM ReturnOrderLineItems)' +
            ' FROM ReturnOrder' +
            ' WHERE Id IN :ids' +
            ' WITH USER_MODE'
        );
    }

    /**
     * @description GW-2793 - Return Order fields needed to build an inbound FedEx shipping-label request.
     * @param returnOrderId Return Order Id
     * @return Matching ReturnOrder, or empty list when not found / null Id
     */
    public static List<ReturnOrder> selectForInboundShippingLabel(Id returnOrderId) {
        if (returnOrderId == null) {
            return new List<ReturnOrder>();
        }
        return (List<ReturnOrder>) SoqlQueryBuilder.fromObject('ReturnOrder')
            .selectFields(
                new List<String>{
                    'Id',
                    'ReturnOrderNumber',
                    'AccountId',
                    'Account.Name',
                    'ContactId',
                    'Contact.Name',
                    'CustomerPO__c',
                    'CustomerReference__c',
                    'DestinationLocationId',
                    'ShipToAddress__Street__s',
                    'ShipToAddress__City__s',
                    'ShipToAddress__StateCode__s',
                    'ShipToAddress__PostalCode__s',
                    'ShipToAddress__CountryCode__s'
                }
            )
            .whereEquals('Id', returnOrderId)
            .limitTo(1)
            .execute();
    }

    /**
     * @description GW-3880 - Parent Return Orders copied onto new Vendor Return Orders.
     * @param parentReturnOrderIds Parent Return Order Ids from source Work Orders
     * @param additionalFieldNames Extra field API names to include in the query
     * @return Parent Return Order rows
     */
    public static List<ReturnOrder> selectParentReturnOrdersForVendorConsolidation(
        Set<Id> parentReturnOrderIds,
        List<String> additionalFieldNames
    ) {
        if (parentReturnOrderIds == null || parentReturnOrderIds.isEmpty()) {
            return new List<ReturnOrder>();
        }
        List<String> fieldNames = new List<String>{
            'Id',
            'AccountId',
            'OperatingUnit__c',
            'DestinationLocationId',
            'SourceLocationId'
        };
        if (additionalFieldNames != null) {
            for (String fieldName : additionalFieldNames) {
                if (String.isNotBlank(fieldName) && !fieldNames.contains(fieldName)) {
                    fieldNames.add(fieldName);
                }
            }
        }
        String soql =
            'SELECT ' +
            String.join(fieldNames, ', ') +
            ' FROM ReturnOrder WHERE Id IN :parentReturnOrderIds WITH USER_MODE';
        return Database.query(soql);
    }

    /**
     * @description GW-3880 - Vendor Return Orders for outbound FedEx label creation.
     * @param returnOrderIds Vendor Return Order Ids
     * @return Return Order rows with account, contact, and source location context
     */
    public static List<ReturnOrder> selectForVendorFedExShipment(Set<Id> returnOrderIds) {
        if (returnOrderIds == null || returnOrderIds.isEmpty()) {
            return new List<ReturnOrder>();
        }
        return [
            SELECT
                Id,
                ReturnOrderNumber,
                AccountId,
                Account.Name,
                Account.AccountNumber,
                ContactId,
                Contact.Name,
                CustomerPO__c,
                SourceLocationId,
                SalesRep__c,
                SalesRep__r.Name
            FROM ReturnOrder
            WHERE Id IN :returnOrderIds
            WITH USER_MODE
        ];
    }

    private static final List<String> RECEIVING_FINISH_FIELDS = new List<String>{
        'Id',
        'ReturnOrderNumber',
        'Status',
        'AccountId',
        'Account.AccountNumber',
        'CaseId',
        'Case.Category__c',
        'ContactId',
        'OrderId',
        'OperatingUnit__c',
        'CreationSource__c',
        'SalesRep__c',
        'WorkOrder__c',
        'ReturnOrderType__c',
        'SourceLocationId',
        'DestinationLocationId',
        'DestinationLocation.Name',
        'Description',
        'ShipmentType',
        'ExpectedArrivalDate',
        'ExpirationDate',
        'ProductRequestId',
        'ReturnedById',
        'CreatedByContact__c',
        'ShipToAddressAccount__c',
        'ShipToAddress__Street__s',
        'ShipToAddress__City__s',
        'ShipToAddress__StateCode__s',
        'ShipToAddress__PostalCode__s',
        'ShipToAddress__CountryCode__s',
        'CustomerPO__c',
        'CustomerReference__c',
        'RepairWarranty__c',
        'WarrantyNotes__c',
        'EstimateContact__c',
        'PreviousReturnOrder__c',
        'ModRequestContact__c',
        'ShipFromStreet',
        'ShipFromCity',
        'ShipFromState',
        'ShipFromStateCode',
        'ShipFromPostalCode',
        'ShipFromCountry',
        'ShipFromCountryCode',
        'RecordTypeId',
        'WOCount__c'
    };

    /**
     * @description GW-5492 - Return Order fields required for Finish Receiving.
     * @param returnOrderId Return Order Id
     * @return Matching Return Orders
     */
    public static List<ReturnOrder> selectForReceivingFinish(Id returnOrderId) {
        if (returnOrderId == null) {
            return new List<ReturnOrder>();
        }
        return (List<ReturnOrder>) new ReturnOrdersSelector()
            .selectFields(RECEIVING_FINISH_FIELDS)
            .whereEquals('Id', returnOrderId)
            .limitTo(1)
            .execute();
    }

}