/**
 * @description GC-3521. Commercial-opportunity gates for an HC Project Opportunity.
 *              Reads child opportunities and does not change their stage, owner, or forecast.
 *              Other opportunity record types are ignored.
 */
public with sharing class ProjectOpportunityCommercialGateService {
    @TestVisible
    private static final String RECORD_TYPE_DEVELOPER_NAME = 'HCProjectOpportunity';
    private static final String STAGE_PROPOSAL = 'Proposal';
    private static final String STAGE_COMMIT = 'Commit';
    private static final String STAGE_CLOSED_WON = 'Closed Won';
    private static final String STAGE_CLOSED_LOST = 'Closed Lost';
    private static final String STAGE_CANCELLED = 'Cancelled';
    private static final String LOGGER_TAG = 'GC-3521';
    private static final String OPEN_CHILD_MESSAGE =
        'The Project Opportunity cannot be closed while related Commercial Opportunities remain open. Please close all associated Commercial Opportunities before proceeding.';

    public static void applyBeforeSave(List<Opportunity> opportunities, Map<Id, Opportunity> priorById) {
        if (opportunities == null || opportunities.isEmpty() || isGloballyBypassed()) {
            return;
        }
        try {
            Id projectRecordTypeId = projectRecordTypeId();
            if (projectRecordTypeId == null) {
                return;
            }
            List<Opportunity> projectOpportunities = new List<Opportunity>();
            Set<Id> childCheckIds = new Set<Id>();
            for (Opportunity opportunity : opportunities) {
                if (opportunity.RecordTypeId != projectRecordTypeId) {
                    continue;
                }
                projectOpportunities.add(opportunity);
                applyClosureProbability(opportunity);
                if (opportunity.BypassValidations__c == true || opportunity.Id == null) {
                    continue;
                }
                if (needsChildCheck(opportunity, priorStage(opportunity, priorById))) {
                    childCheckIds.add(opportunity.Id);
                }
            }
            if (projectOpportunities.isEmpty()) {
                return;
            }
            Map<Id, ChildCounts> countsByProjectId = summarizeChildren(childCheckIds);
            for (Opportunity opportunity : projectOpportunities) {
                if (opportunity.BypassValidations__c == true) {
                    continue;
                }
                applyChildGates(
                    opportunity,
                    priorStage(opportunity, priorById),
                    countsFor(opportunity, countsByProjectId)
                );
            }
        } catch (Exception exceptionValue) {
            Logger.setScenario(LOGGER_TAG);
            Logger.error('Unable to apply project commercial gates.', exceptionValue).addTag(LOGGER_TAG);
            Logger.saveLog();
            throw exceptionValue;
        }
    }

    private static void applyClosureProbability(Opportunity opportunity) {
        if (opportunity.StageName == STAGE_CLOSED_WON) {
            opportunity.Probability = 100;
        } else if (opportunity.StageName == STAGE_CLOSED_LOST || opportunity.StageName == STAGE_CANCELLED) {
            opportunity.Probability = 0;
        }
    }

    private static void applyChildGates(Opportunity opportunity, String priorStage, ChildCounts counts) {
        if (isEntering(opportunity.StageName, priorStage, STAGE_PROPOSAL) && counts.activeOrWon == 0) {
            opportunity.addError(
                'Associate at least one active or Closed Won Commercial Opportunity before moving the project to Proposal.'
            );
        } else if (opportunity.StageName == STAGE_PROPOSAL && counts.total == 0) {
            opportunity.addError(
                'Associate at least one Commercial Opportunity while the project is in Proposal.'
            );
        }
        if (isEntering(opportunity.StageName, priorStage, STAGE_COMMIT) && counts.commitOrWon == 0) {
            opportunity.addError(
                'At least one related Commercial Opportunity must be in Commit or Closed Won before moving the project to Commit.'
            );
        } else if (opportunity.StageName == STAGE_COMMIT && counts.total == 0) {
            opportunity.addError(
                'Associate at least one Commercial Opportunity while the project is in Commit.'
            );
        }
        if (!isEntering(opportunity.StageName, priorStage, STAGE_CLOSED_WON)
            && !isEntering(opportunity.StageName, priorStage, STAGE_CLOSED_LOST)) {
            return;
        }
        if (counts.openCount > 0) {
            opportunity.addError(OPEN_CHILD_MESSAGE);
            return;
        }
        if (opportunity.StageName == STAGE_CLOSED_WON && counts.wonCount == 0) {
            opportunity.addError(
                'At least one related Commercial Opportunity must be Closed Won before the Project Opportunity can be Closed Won.'
            );
            return;
        }
        if (opportunity.StageName == STAGE_CLOSED_LOST && counts.wonCount > 0) {
            opportunity.addError(
                'The Project Opportunity cannot be Closed Lost while a related Commercial Opportunity is Closed Won.'
            );
        }
    }

    private static Boolean needsChildCheck(Opportunity opportunity, String priorStage) {
        return opportunity.StageName == STAGE_PROPOSAL
            || opportunity.StageName == STAGE_COMMIT
            || isEntering(opportunity.StageName, priorStage, STAGE_CLOSED_WON)
            || isEntering(opportunity.StageName, priorStage, STAGE_CLOSED_LOST);
    }

    private static Map<Id, ChildCounts> summarizeChildren(Set<Id> projectIds) {
        Map<Id, ChildCounts> countsByProjectId = new Map<Id, ChildCounts>();
        if (projectIds.isEmpty()) {
            return countsByProjectId;
        }
        for (Opportunity child : [
            SELECT StageName, RelatedProjectOpportunity__c
            FROM Opportunity
            WHERE RelatedProjectOpportunity__c IN :projectIds
        ]) {
            ChildCounts counts = countsByProjectId.get(child.RelatedProjectOpportunity__c);
            if (counts == null) {
                counts = new ChildCounts();
                countsByProjectId.put(child.RelatedProjectOpportunity__c, counts);
            }
            counts.add(child.StageName);
        }
        return countsByProjectId;
    }

    private static ChildCounts countsFor(Opportunity opportunity, Map<Id, ChildCounts> countsByProjectId) {
        if (opportunity.Id == null || !countsByProjectId.containsKey(opportunity.Id)) {
            return new ChildCounts();
        }
        return countsByProjectId.get(opportunity.Id);
    }

    private static Boolean isEntering(String stageName, String priorStage, String targetStage) {
        return stageName == targetStage && priorStage != targetStage;
    }

    private static String priorStage(Opportunity opportunity, Map<Id, Opportunity> priorById) {
        if (priorById == null || opportunity.Id == null || !priorById.containsKey(opportunity.Id)) {
            return null;
        }
        return priorById.get(opportunity.Id).StageName;
    }

    private static Boolean isGloballyBypassed() {
        Automation_Setting_Global__c globalSetting = Automation_Setting_Global__c.getInstance();
        if (globalSetting != null && globalSetting.disableAll__c == true) {
            return true;
        }
        Automation_Setting_Validation_Rule__c validationSetting = Automation_Setting_Validation_Rule__c.getInstance();
        return validationSetting != null
            && (validationSetting.disableAll__c == true || validationSetting.Opp_089_ProjectCommercialGates__c == true);
    }

    private static Id projectRecordTypeId() {
        Schema.RecordTypeInfo recordType = Schema.SObjectType.Opportunity
            .getRecordTypeInfosByDeveloperName()
            .get(RECORD_TYPE_DEVELOPER_NAME);
        return recordType == null ? null : recordType.getRecordTypeId();
    }

    private class ChildCounts {
        private Integer total = 0;
        private Integer activeOrWon = 0;
        private Integer commitOrWon = 0;
        private Integer openCount = 0;
        private Integer wonCount = 0;

        private void add(String stageName) {
            total++;
            if (stageName != STAGE_CLOSED_LOST && stageName != STAGE_CANCELLED) {
                activeOrWon++;
            }
            if (stageName == STAGE_COMMIT || stageName == STAGE_CLOSED_WON) {
                commitOrWon++;
            }
            if (stageName != STAGE_CLOSED_WON && stageName != STAGE_CLOSED_LOST && stageName != STAGE_CANCELLED) {
                openCount++;
            }
            if (stageName == STAGE_CLOSED_WON) {
                wonCount++;
            }
        }
    }
}