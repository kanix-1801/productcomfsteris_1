/**
 * @description One-time backfill of Contracting Entered Date for Opportunities already in Contracting.
 */
public with sharing class ContractingEnteredDateBackfill {
    /**
     * @description Sets Contracting Entered Date from the latest entry into Contracting.
     */
    public static void run() {
        List<Opportunity> opportunities = [
            SELECT Id, CreatedDate, LastStageChangeDate
            FROM Opportunity
            WHERE RecordType.DeveloperName = 'HCSalesStrategicContract'
            AND StageName = 'Contracting'
            AND ContractingEnteredDate__c = null
        ];
        if (opportunities.isEmpty()) {
            return;
        }

        Map<Id, Opportunity> opportunitiesById = new Map<Id, Opportunity>(opportunities);
        Map<Id, Datetime> enteredOnByOpportunity = new Map<Id, Datetime>();
        Map<Id, String> priorStageByOpportunity = new Map<Id, String>();
        for (OpportunityHistory historyRow : [
            SELECT OpportunityId, StageName, CreatedDate
            FROM OpportunityHistory
            WHERE OpportunityId IN :opportunitiesById.keySet()
            ORDER BY CreatedDate ASC, Id ASC
        ]) {
            String priorStage = priorStageByOpportunity.get(historyRow.OpportunityId);
            if (historyRow.StageName == 'Contracting' && priorStage != 'Contracting') {
                enteredOnByOpportunity.put(historyRow.OpportunityId, historyRow.CreatedDate);
            }
            priorStageByOpportunity.put(historyRow.OpportunityId, historyRow.StageName);
        }

        for (Opportunity opportunityRecord : opportunities) {
            Datetime enteredOn = enteredOnByOpportunity.get(opportunityRecord.Id);
            if (enteredOn == null) {
                enteredOn = opportunityRecord.LastStageChangeDate == null
                    ? opportunityRecord.CreatedDate
                    : opportunityRecord.LastStageChangeDate;
            }
            opportunityRecord.ContractingEnteredDate__c = enteredOn.date();
        }
        Database.update(opportunities, false);
    }
}