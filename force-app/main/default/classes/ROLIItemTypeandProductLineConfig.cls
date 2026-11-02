/**
 * @description Wrapper providing the single point of access to the
 *              ROLIItemTypeandProductLine__mdt Custom Metadata Type, which maps a return
 *              order line item type to its product line and RO category. No code outside
 *              this class may query the metadata type directly; callers read the public
 *              cmdtList property and iterate it. The metadata type must include an
 *              isActive__c field, and only records where isActive__c is true are returned.
 * @author Dana Wolfe
 * @date 2026-07-29
 * @group Configuration Data
 */
public inherited sharing class ROLIItemTypeandProductLineConfig {
    @testVisible
    private static List<ROLIItemTypeandProductLine__mdt> cmdtList_mock = new List<ROLIItemTypeandProductLine__mdt>();
    private static List<ROLIItemTypeandProductLine__mdt> cmdtList_cached;

    @testVisible
    private static Boolean overrideIsRunningTest = false;

    /**
     * @description The full list of active ROLIItemTypeandProductLine__mdt records. Cached
     *              for the lifetime of the transaction. In test context, returns the
     *              injectable mock list unless overrideIsRunningTest is set.
     * @return List of active ROLIItemTypeandProductLine__mdt records.
     */
    public static List<ROLIItemTypeandProductLine__mdt> cmdtList {
        get {
            return getRecordList();
        }
    }

    /**
     * @description Resolves the active-record list, honoring the transaction cache and the
     *              test mock path. Holds the only SOQL against the metadata type.
     * @return List of active ROLIItemTypeandProductLine__mdt records.
     */
    private static List<ROLIItemTypeandProductLine__mdt> getRecordList() {
        if (cmdtList_cached != null) {
            return cmdtList_cached;
        }
        if (Test.isRunningTest() && !overrideIsRunningTest) {
            return cmdtList_mock;
        }
        cmdtList_cached = [
            SELECT Id, DeveloperName, ItemType__c, ProductLine__c, ROCategory__c
              FROM ROLIItemTypeandProductLine__mdt
             WHERE IsActive__c = true
        ];
        return cmdtList_cached;
    }
}