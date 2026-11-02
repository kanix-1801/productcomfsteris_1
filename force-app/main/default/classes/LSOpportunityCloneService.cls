/**
 * @description #GCL-23 Stamps Cloned From when a Life Sciences Opportunity
 *              is created with the standard Clone action.
 */
public with sharing class LSOpportunityCloneService {
    @TestVisible
    private static final Set<String> LIFE_SCIENCES_RECORD_TYPES = new Set<String>{
        'LSEquipmentService',
        'LSSalesConsumables'
    };

    public static void stampClonedFrom(List<Opportunity> opportunities) {
        if (opportunities == null || opportunities.isEmpty()) {
            return;
        }

        Set<Id> lifeSciencesRecordTypeIds = lifeSciencesRecordTypeIds();
        for (Opportunity opportunity : opportunities) {
            if (opportunity == null
                || !opportunity.isClone()
                || !lifeSciencesRecordTypeIds.contains(opportunity.RecordTypeId)) {
                continue;
            }
            opportunity.ClonedFrom__c = opportunity.getCloneSourceId();
            opportunity.BypassValidations__c = false;
            opportunity.QuoteLinkageToSalesConnection__c = null;
        }
    }

    private static Set<Id> lifeSciencesRecordTypeIds() {
        Set<Id> recordTypeIds = new Set<Id>();
        Map<String, Schema.RecordTypeInfo> recordTypesByName =
            Opportunity.SObjectType.getDescribe(SObjectDescribeOptions.DEFERRED)
                .getRecordTypeInfosByDeveloperName();
        for (String developerName : LIFE_SCIENCES_RECORD_TYPES) {
            Schema.RecordTypeInfo recordTypeInfo = recordTypesByName.get(developerName);
            if (recordTypeInfo != null) {
                recordTypeIds.add(recordTypeInfo.getRecordTypeId());
            }
        }
        return recordTypeIds;
    }
}