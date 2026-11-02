/**
 * @description Temporary probe — verifies ConnectApi picklists work inside @IsTest (GW-1279).
 */
@IsTest
private class ConnectApiPicklistProbeTest {
    @IsTest
    static void testConnectApiPicklistValuesInTestContext() {
        List<RecordType> recordTypes = [
            SELECT Id
            FROM RecordType
            WHERE SObjectType = 'Case' AND DeveloperName = 'InboxSupport'
            LIMIT 1
        ];
        System.Assert.isFalse(recordTypes.isEmpty(), 'Inbox Support record type required');
        Id inboxRt = recordTypes[0].Id;

        ConnectApi.PicklistValuesCollection collection =
            ConnectApi.RecordUi.getPicklistValuesByRecordType('Case', String.valueOf(inboxRt));
        ConnectApi.PicklistValues categoryPicklist = collection.picklistFieldValues.get('Category__c');
        System.Assert.isNotNull(categoryPicklist, 'Category__c picklist metadata required');
        System.Assert.isTrue(categoryPicklist.values.size() > 0, 'Category values required');
        System.Assert.isTrue(
            categoryPicklist.controllerValues != null && !categoryPicklist.controllerValues.isEmpty(),
            'Origin controller values required'
        );
    }
}