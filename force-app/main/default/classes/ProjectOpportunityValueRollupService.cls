/**
 * @description GC-3521. Rolls commercial opportunity Amount onto the HC Project Opportunity.
 *              Open, Closed Won, Closed Lost, and Total Associated Value are stored on the project.
 *              Opportunity Amount on the project is not changed. Other record types are not updated.
 *              Runs without sharing and in system mode so a commercial user can link a project
 *              without edit access to the calculated value fields or to the project record.
 */
public without sharing class ProjectOpportunityValueRollupService {
    private static final String RECORD_TYPE_DEVELOPER_NAME = 'HCProjectOpportunity';
    private static final String STAGE_CLOSED_WON = 'Closed Won';
    private static final String STAGE_CLOSED_LOST = 'Closed Lost';
    private static final String STAGE_CANCELLED = 'Cancelled';
    private static final String LOGGER_TAG = 'GC-3521';
    private static Boolean isApplying = false;

    public static void applyAfterSave(List<Opportunity> opportunities, Map<Id, Opportunity> priorById) {
        if (isApplying || opportunities == null || opportunities.isEmpty() || isGloballyBypassed()) {
            return;
        }
        try {
            Set<Id> projectIds = affectedProjectIds(opportunities, priorById);
            if (projectIds.isEmpty()) {
                return;
            }
            Map<Id, Opportunity> projectsById = new Map<Id, Opportunity>([
                SELECT Id,
                    OpenValue__c,
                    ClosedWonValue__c,
                    ClosedLostValue__c,
                    TotalAssociatedValue__c
                FROM Opportunity
                WHERE Id IN :projectIds
                AND RecordType.DeveloperName = :RECORD_TYPE_DEVELOPER_NAME
                WITH SYSTEM_MODE
            ]);
            if (projectsById.isEmpty()) {
                return;
            }
            Map<Id, Decimal> openByProject = new Map<Id, Decimal>();
            Map<Id, Decimal> wonByProject = new Map<Id, Decimal>();
            Map<Id, Decimal> lostByProject = new Map<Id, Decimal>();
            Map<Id, Decimal> totalByProject = new Map<Id, Decimal>();
            for (Id projectId : projectsById.keySet()) {
                openByProject.put(projectId, 0);
                wonByProject.put(projectId, 0);
                lostByProject.put(projectId, 0);
                totalByProject.put(projectId, 0);
            }
            for (Opportunity child : [
                SELECT StageName, Amount, RelatedProjectOpportunity__c
                FROM Opportunity
                WHERE RelatedProjectOpportunity__c IN :projectsById.keySet()
                WITH SYSTEM_MODE
            ]) {
                Id projectId = child.RelatedProjectOpportunity__c;
                Decimal amount = child.Amount == null ? 0 : child.Amount;
                totalByProject.put(projectId, totalByProject.get(projectId) + amount);
                if (child.StageName == STAGE_CLOSED_WON) {
                    wonByProject.put(projectId, wonByProject.get(projectId) + amount);
                } else if (child.StageName == STAGE_CLOSED_LOST) {
                    lostByProject.put(projectId, lostByProject.get(projectId) + amount);
                } else if (child.StageName != STAGE_CANCELLED) {
                    openByProject.put(projectId, openByProject.get(projectId) + amount);
                }
            }
            List<Opportunity> updates = new List<Opportunity>();
            for (Opportunity project : projectsById.values()) {
                if (sameAmount(project.OpenValue__c, openByProject.get(project.Id))
                    && sameAmount(project.ClosedWonValue__c, wonByProject.get(project.Id))
                    && sameAmount(project.ClosedLostValue__c, lostByProject.get(project.Id))
                    && sameAmount(project.TotalAssociatedValue__c, totalByProject.get(project.Id))) {
                    continue;
                }
                updates.add(new Opportunity(
                    Id = project.Id,
                    OpenValue__c = openByProject.get(project.Id),
                    ClosedWonValue__c = wonByProject.get(project.Id),
                    ClosedLostValue__c = lostByProject.get(project.Id),
                    TotalAssociatedValue__c = totalByProject.get(project.Id)
                ));
            }
            if (updates.isEmpty()) {
                return;
            }
            isApplying = true;
            update as system updates;
        } catch (Exception exceptionValue) {
            Logger.setScenario(LOGGER_TAG);
            Logger.error('Unable to roll up commercial opportunity values.', exceptionValue).addTag(LOGGER_TAG);
            Logger.saveLog();
            throw exceptionValue;
        } finally {
            isApplying = false;
        }
    }

    private static Set<Id> affectedProjectIds(List<Opportunity> opportunities, Map<Id, Opportunity> priorById) {
        Set<Id> projectIds = new Set<Id>();
        Id projectRecordTypeId = projectRecordTypeId();
        for (Opportunity opportunity : opportunities) {
            Opportunity prior = priorById == null || opportunity.Id == null
                ? null
                : priorById.get(opportunity.Id);
            if (projectRecordTypeId != null && opportunity.RecordTypeId == projectRecordTypeId && opportunity.Id != null) {
                projectIds.add(opportunity.Id);
            }
            if (opportunity.RelatedProjectOpportunity__c != null
                && (prior == null
                    || opportunity.RelatedProjectOpportunity__c != prior.RelatedProjectOpportunity__c
                    || opportunity.StageName != prior.StageName
                    || opportunity.Amount != prior.Amount)) {
                projectIds.add(opportunity.RelatedProjectOpportunity__c);
            }
            if (prior != null
                && prior.RelatedProjectOpportunity__c != null
                && prior.RelatedProjectOpportunity__c != opportunity.RelatedProjectOpportunity__c) {
                projectIds.add(prior.RelatedProjectOpportunity__c);
            }
        }
        return projectIds;
    }

    private static Boolean sameAmount(Decimal currentValue, Decimal nextValue) {
        Decimal currentAmount = currentValue == null ? 0 : currentValue;
        Decimal nextAmount = nextValue == null ? 0 : nextValue;
        return currentAmount == nextAmount;
    }

    private static Boolean isGloballyBypassed() {
        Automation_Setting_Global__c globalSetting = Automation_Setting_Global__c.getInstance();
        return globalSetting != null && globalSetting.disableAll__c == true;
    }

    private static Id projectRecordTypeId() {
        Schema.RecordTypeInfo recordType = Schema.SObjectType.Opportunity
            .getRecordTypeInfosByDeveloperName()
            .get(RECORD_TYPE_DEVELOPER_NAME);
        return recordType == null ? null : recordType.getRecordTypeId();
    }
}