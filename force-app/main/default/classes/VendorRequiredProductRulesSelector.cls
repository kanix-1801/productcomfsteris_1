/**
 * @description Selector for VendorRequiredProductRule__mdt. Queries use SoqlQueryBuilder.
 */
public with sharing class VendorRequiredProductRulesSelector extends SoqlQueryBuilder {
    /**
     * @description Binds this selector to VendorRequiredProductRule__mdt.
     */
    public VendorRequiredProductRulesSelector() {
        this.objectName = 'VendorRequiredProductRule__mdt';
    }

    /**
     * @description GW-5492 - Active vendor-required product rules.
     * @return Active custom metadata rows
     */
    public static List<VendorRequiredProductRule__mdt> selectActive() {
        return (List<VendorRequiredProductRule__mdt>) new VendorRequiredProductRulesSelector()
            .selectFields(
                new List<String>{
                    'ProductLine__c',
                    'SubProductLine__c',
                    'DeviceType__c',
                    'IsActive__c'
                }
            )
            .whereEquals('IsActive__c', true)
            .execute();
    }
}