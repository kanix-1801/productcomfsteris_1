/**
 * @author PSL
 * @date 12-31-2025
 * @description Trigger to link Address records to Location records based on OrgId__c during data migration
 */
trigger DataMigrationTriggerOnAddress on Schema.Address (before insert) {
if(System.Label.ExecuteTrigger=='true'){
        Set<String> keys = new Set<String>();
        for (Schema.Address a : Trigger.New) {
            if (a.OrgId_Temp__c!= null) {
                keys.add(a.OrgId_Temp__c+ '-Oracle');
            }
        }
        if (keys.isEmpty()) return;

        // Query all Locations by external id
        Map<String, Id> keyToLocId = new Map<String, Id>();
        for (Schema.Location loc : [
            SELECT Id, ExternalId__c
            FROM Location
            WHERE ExternalId__c IN :keys
        ]) {
            keyToLocId.put(loc.ExternalId__c, loc.Id);
        }

        // Assign ParentId when found
        for (Schema.Address a : Trigger.New) {
            if (a.OrgId_Temp__c == null) continue;
            String k = a.OrgId_Temp__c + '-Oracle';
            if (keyToLocId.containsKey(k)) {
               a.ParentId = keyToLocId.get(k);
                 if(a.OracleStateValue__c!=null)
            {
                if(a.OracleStateValue__c.length()==2)
                     a.StateCode=a.OracleStateValue__c;
                else
                    a.State=a.OracleStateValue__c;
                    
             }
            } else {
                // Optional: clear ParentId if no match or leave as-is
                // a.ParentId = null;
            }
        }
        }
        }