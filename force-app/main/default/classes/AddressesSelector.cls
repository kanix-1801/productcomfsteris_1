/**
 * @description Selector for Address records used when a Product Request ships to the technician.
 */
public with sharing class AddressesSelector extends SoqlQueryBuilder {
    /**
     * @description Binds this selector to Address.
     */
    public AddressesSelector() {
        super('Address');
    }

    /**
     * @description Addresses whose parent is the Service Resource location.
     * @param parentId Location Id stored on Address.ParentId.
     * @return Address Id, auto-number, and ship-to text, ordered by Name.
     * @example
     * AddressesSelector.selectByParentId(locationId);
     */
    public static List<Schema.Address> selectByParentId(Id parentId) {
        if (parentId == null) {
            return new List<Schema.Address>();
        }
        return (List<Schema.Address>) new AddressesSelector()
            .selectFields(new List<String>{ 'Id', 'Name', 'AddressShipTo__c' })
            .whereEquals('ParentId', parentId)
            .orderBy('Name')
            .execute();
    }
}