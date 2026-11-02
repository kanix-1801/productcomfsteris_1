/**
 * @author PSL
 * @date 12-31-2025
 * @description Trigger for Account object to handle before insert operations during data migration, setting SourceSystemID__c, AccountSource, and record type fields.
 */
trigger DataMigrationTriggerOnAccount on Account (before insert) {

Id recordTypeId = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName().get('Customer').getRecordTypeId();

if(System.Label.ExecuteTrigger=='true'){
for(Account acc :Trigger.New)
    {
    acc.SourceSystemID__c=acc.SystemID__c+'Oracle';
    acc.AccountSource='Oracle';
    acc.recordtypeid=recordTypeId;
    }
   }

}