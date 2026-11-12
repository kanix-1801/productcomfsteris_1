/**
 * @description Selector class for the ProductRequest SObject.
 *              Centralizes all SOQL queries for ProductRequests.
 *              Enforces security via WITH USER_MODE.
 */
public with sharing class ProductRequestsSelector {

    private static final String BASE_FIELDS =
        'Id, Status, Description, ' +
        'DestinationLocationId, ' +
        'WorkOrderId, WorkOrderLineItemId, ' +
        'OwnerId, CreatedDate, LastModifiedDate';

    /**
     * @description Retrieves ProductRequest records by their Ids.
     * @param ids Set of ProductRequest Ids to query.
     * @return List of ProductRequest records matching the given Ids.
     */
    public static List<ProductRequest> selectById(Set<Id> ids) {
        if (ids == null || ids.isEmpty()) {
            return new List<ProductRequest>();
        }
        return Database.query(
            'SELECT ' + BASE_FIELDS +
            ' FROM ProductRequest' +
            ' WHERE Id IN :ids' +
            ' WITH USER_MODE'
        );
    }

    /**
     * @description Retrieves ProductRequest records by Status.
     * @param statuses Set of Status values to filter by.
     * @return List of ProductRequest records matching the given statuses.
     */
    public static List<ProductRequest> selectByStatus(Set<String> statuses) {
        if (statuses == null || statuses.isEmpty()) {
            return new List<ProductRequest>();
        }
        return Database.query(
            'SELECT ' + BASE_FIELDS +
            ' FROM ProductRequest' +
            ' WHERE Status IN :statuses' +
            ' WITH USER_MODE' +
            ' ORDER BY CreatedDate DESC'
        );
    }

    /**
     * @description Retrieves ProductRequest records by WorkOrder Id.
     * @param workOrderIds Set of WorkOrder Ids to filter by.
     * @return List of ProductRequest records linked to the given WorkOrders.
     */
    public static List<ProductRequest> selectByWorkOrderId(Set<Id> workOrderIds) {
        if (workOrderIds == null || workOrderIds.isEmpty()) {
            return new List<ProductRequest>();
        }
        return Database.query(
            'SELECT ' + BASE_FIELDS +
            ' FROM ProductRequest' +
            ' WHERE WorkOrderId IN :workOrderIds' +
            ' WITH USER_MODE' +
            ' ORDER BY CreatedDate DESC'
        );
    }

    /**
     * @description Retrieves ProductRequest records with their related ProductRequestLineItems.
     * @param ids Set of ProductRequest Ids to query.
     * @return List of ProductRequest records with child ProductRequestLineItem records.
     */
    public static List<ProductRequest> selectByIdWithLineItems(Set<Id> ids) {
        if (ids == null || ids.isEmpty()) {
            return new List<ProductRequest>();
        }
        return Database.query(
            'SELECT ' + BASE_FIELDS +
            ', (SELECT Id, Product2Id, QuantityRequested, QuantityUnitOfMeasure, ParentId FROM ProductRequestLineItems)' +
            ' FROM ProductRequest' +
            ' WHERE Id IN :ids' +
            ' WITH USER_MODE'
        );
    }

    /**
     * @description GW-580: Product Request header fields for the DPC GetProductInstance launch.
     * @param ids Set of ProductRequest Ids to query.
     * @return Product Requests with Work Order and Asset fields used in the DPC payload.
     */
    public static List<ProductRequest> selectForDpcLaunch(Set<Id> ids) {
        if (ids == null || ids.isEmpty()) {
            return new List<ProductRequest>();
        }
        return Database.query(
            'SELECT Id, ProductRequestNumber, PONumber__c, DPCOrderNumber__c, ' +
            'WorkOrderId, WorkOrder.CustomerPO__c, WorkOrder.AssetId, ' +
            'WorkOrder.Asset.SerialNumber, WorkOrder.Asset.PFCL__c ' +
            'FROM ProductRequest ' +
            'WHERE Id IN :ids ' +
            'WITH USER_MODE'
        );
    }

    /**
     * @description GW-5981 - Product Request number after insert.
     * @param productRequestId Product Request Id
     * @return Product Request Number, or null
     */
    public static String selectNumberById(Id productRequestId) {
        if (productRequestId == null) {
            return null;
        }
        List<ProductRequest> rows = Database.query(
            'SELECT ProductRequestNumber' +
            ' FROM ProductRequest' +
            ' WHERE Id = :productRequestId' +
            ' WITH USER_MODE' +
            ' LIMIT 1'
        );
        return rows.isEmpty() ? null : rows[0].ProductRequestNumber;
    }

    /**
     * @description GW-5981 - Product Requests on a Work Order, including line display fields.
     * @param workOrderIds Work Order Ids
     * @return Product Requests and their line items
     */
    public static List<ProductRequest> selectWithLinesByWorkOrderId(Set<Id> workOrderIds) {
        if (workOrderIds == null || workOrderIds.isEmpty()) {
            return new List<ProductRequest>();
        }
        return Database.query(
            'SELECT Id, ProductRequestNumber, Status, RequestType__c, WorkOrderId,' +
            ' DestinationLocationId, ShipmentType, RecordType.DeveloperName,' +
            ' (SELECT Id, QuantityRequested, Status, Product2Id, RecordType.DeveloperName,' +
            ' Product2.ProductCode, Product2.Description, Product2.Name' +
            ' FROM ProductRequestLineItems ORDER BY ProductRequestLineItemNumber)' +
            ' FROM ProductRequest' +
            ' WHERE WorkOrderId IN :workOrderIds' +
            ' WITH USER_MODE' +
            ' ORDER BY CreatedDate DESC'
        );
    }

    /**
     * @description Header, integration result, and one line for the Oracle submit screen.
     * @param ids Product Request Ids.
     * @return Product Requests the running user can read.
     */
    public static List<ProductRequest> selectForOracleSubmit(Set<Id> ids) {
        if (ids == null || ids.isEmpty()) {
            return new List<ProductRequest>();
        }
        return Database.query(
            'SELECT Id, ProductRequestNumber, Status, SubmissionToERP__c, ' +
            'IntegrationStatus__c, IntegrationMessage__c, ERPOrderNumber__c, ' +
            '(SELECT Id FROM ProductRequestLineItems LIMIT 1) ' +
            'FROM ProductRequest ' +
            'WHERE Id IN :ids ' +
            'WITH USER_MODE'
        );
    }
}