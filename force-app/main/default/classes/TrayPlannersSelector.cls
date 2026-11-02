/**
 * @description Selector for TrayPlanner__c. Queries run through SoqlQueryBuilder.
 */
public with sharing class TrayPlannersSelector extends SoqlQueryBuilder {
    /**
     * @description Binds this selector to TrayPlanner__c.
     */
    public TrayPlannersSelector() {
        this.objectName = 'TrayPlanner__c';
    }

    /**
     * @description Tray Planner rows for one asset, ordered by name.
     * @param assetId Asset Id
     * @return Matching Tray Planner records
     */
    public static List<TrayPlanner__c> selectByAssetId(Id assetId) {
        if (assetId == null) {
            return new List<TrayPlanner__c>();
        }
        return (List<TrayPlanner__c>) new TrayPlannersSelector()
            .selectFields(new List<String>{
                'Name',
                'Quantity__c',
                'SupplierMake__c',
                'CatalogNumber__c',
                'VMuellerNumber__c',
                'DeviceType__r.Name',
                'DeviceType__r.ProductCode'
            })
            .whereEquals('Asset__c', assetId)
            .orderBy('Name')
            .execute();
    }
}