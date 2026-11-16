/**
 * @description Selector for Address records used when a Product Request ships to the technician.
 */
public with sharing class AddressesSelector extends SoqlQueryBuilder {
    /** @description Address.ShipTo__c API value for the Inactive picklist entry. */
    private static final String SHIP_TO_INACTIVE = 'I';

    /**
     * @description Binds this selector to Address.
     */
    public AddressesSelector() {
        super('Address');
    }

    /**
     * @description Addresses whose parent is the Service Resource location.
     *              Addresses with Ship To set to Inactive are omitted. A blank Ship To stays.
     * @param parentId Location Id stored on Address.ParentId.
     * @return Address Id, auto-number, ship-to text, and Address ID, ordered by Name.
     * @example
     * AddressesSelector.selectByParentId(locationId);
     */
    public static List<Schema.Address> selectByParentId(Id parentId) {
        if (parentId == null) {
            return new List<Schema.Address>();
        }
        return (List<Schema.Address>) new AddressesSelector()
            .selectFields(new List<String>{ 'Id', 'Name', 'AddressShipTo__c', 'AddressID__c' })
            .whereEquals('ParentId', parentId)
            .whereField('ShipTo__c', '!=', SHIP_TO_INACTIVE)
            .whereEquals('ShipTo__c', null)
            .withFilterLogic('1 AND (2 OR 3)')
            .orderBy('Name')
            .execute();
    }
}