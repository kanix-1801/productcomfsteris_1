/**
 * @author PSL
 * @date 12-31-2025
 * @description Trigger for Order object to handle before insert operations during data migration, setting the standard pricebook ID for orders.
 */
trigger DataMigrationTriggerOnOrder on Order (before insert) {
if(System.Label.ExecuteTrigger=='true'){
   List<Pricebook2> listpricebook=[select id from Pricebook2 where Name='Standard Price Book' limit 1];
    if(listpricebook.size()>0){
    for(Order ord : Trigger.New){
      ord.Pricebook2Id=listpricebook[0].id;
      ord.isMigrated__c=true;
      }
    }
    }
}