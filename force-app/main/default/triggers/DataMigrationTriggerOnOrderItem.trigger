/**
 * @author PSL
 * @date 12-31-2025
 * @description Trigger for OrderItem object to handle before insert operations during data migration, mapping PricebookEntry and Product2 records based on external IDs.
 */
trigger DataMigrationTriggerOnOrderItem on OrderItem (before insert) {
    if(System.Label.ExecuteTrigger=='true'){
    List<Pricebook2> listpricebook=[select id from Pricebook2 where Name='Standard Price Book' limit 1];
    Set<String> setPricebookentryId= new Set<String>();
    Set<String> setProductId= new Set<String>();

     for(OrderItem oli : Trigger.New){
      if(listpricebook.size()>0){
      setPricebookentryId.add(oli.ItemId__c+'203'+listpricebook[0].id+oli.Currency__c);
      setProductId.add(oli.ItemId__c+'203');
      }
      }
      
      Map<String, Id> keyToPriebookId = new Map<String, Id>();
        for (PriceBookEntry pbe: [
            SELECT Id, ExternalId__c
            FROM PriceBookEntry 
            WHERE ExternalId__c IN :setPricebookentryId
        ]) {
            keyToPriebookId.put(pbe.ExternalId__c, pbe.Id);
           
        }
        
        
         Map<String, Id> productids= new Map<String, Id>();
        for (Product2 prd: [
            SELECT Id, ProductExternalId__c
            FROM Product2
            WHERE ProductExternalId__c IN :setProductId
        ]) {
            productids.put(prd.ProductExternalId__c , prd.Id);
           
        }

     for (OrderItem oli : Trigger.New) {
          
           if(listpricebook.size()>0){ 
          String k= oli.ItemId__c+'203'+listpricebook[0].id+oli.Currency__c;
        
         if(keyToPriebookId.containsKey(k)) {
                oli.PricebookEntryID= keyToPriebookId.get(k);
              }
              
               if(productids.containsKey(k)) {
                oli.Product2id= productids.get(k);
              }
           
         
           }
           }
      
      
      
      
     
    }  
 }