/**
 * @author PSL
 * @date 12-31-2025
 * @description Trigger for Product2 object to handle before insert operations during data migration, setting Name and ProductExternalId__c fields based on product codes and descriptions.
 */
trigger DataMigrationTriggerOnProduct on Product2 (before insert) {
if(System.Label.ExecuteTrigger=='true'){
 for(Product2 prd : Trigger.New){
       prd.Name=prd.ProductCode+'-'+prd.Description;
       prd.ProductExternalId__c=prd.ItemID__c+prd.InventoryOrgId__c;
       }

}
}