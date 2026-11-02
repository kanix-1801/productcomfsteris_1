/**
 * @description Service class for Case object - handles business orchestration and transaction management.
 *              Entry point for all Case-related business operations; GW-1279 - CaseTriggerHandler.beforeInsert calls
 *              applyCaseRoutingRules for CaseRoutingRule__c routing on new Cases.
 *              Follows STERIS enterprise architecture standards (without UnitOfWork per requirement).
 * @author STERIS
 * @date 2026-04-22
 */
public with sharing class CasesService {

    /**
     * GW-1279 - Case record type name for Inbox Support (matches keys from getRecordTypeInfosByName()).
     * TODO Temporary: hardcoded label lookup; replace with Custom Metadata, DeveloperName, or another
     * org-standard approach when routing configuration is finalized.
     */
    private static final String INBOX_SUPPORT_RECORD_TYPE_NAME = 'Inbox Support';

    /** GW-1279 - Value for Case.CaseSource__c when routing rule IsSystemGenerated__c is true. */
    private static final String CASE_ROUTING_SOURCE_SYSTEM = 'System';

    /**
     * @description GW-1279 - Applies active routing rules to each new Case before insert.
     * @param newRecords Case records from Trigger.new
     * @return Cases in the domain working set after Inbox Support filtering (same instances as in newRecords where
     *         included); empty when none qualify
     */
    public static List<Case> applyCaseRoutingRules(List<Case> newRecords) {
        if (newRecords == null || newRecords.isEmpty()) {
            return new List<Case>();
        }

        try {
            Cases casesDomain = new Cases(newRecords);
            casesDomain.checkSecurity('insert');

            // Temporary: resolve RecordTypeId by label; routing logic will use this when implemented.
            Id inboxSupportRecordTypeId = Schema.SObjectType.Case.getRecordTypeInfosByName()
                .get(INBOX_SUPPORT_RECORD_TYPE_NAME)
                ?.getRecordTypeId();
            casesDomain.filterOutNonInboxSupportRecords(inboxSupportRecordTypeId);
            List<Case> routingCases = casesDomain.getRecords();
            Set<String> caseAssignmentOrigins = getCaseAssignmentOrigins(routingCases);
            Logger.fine(new LogMessage('Case routing: {0} distinct Case Assignment (Origin) values', caseAssignmentOrigins.size()));
            List<CaseRoutingRule__c> activeRoutingRules = CaseRoutingRulesService.getActiveRulesForCaseAssignments(caseAssignmentOrigins);
            Logger.fine(new LogMessage('Case routing: {0} active routing rule(s) loaded', activeRoutingRules.size()));

            for (Case currentCase : routingCases) {
                findMatchingRulesAndPopulateCase(currentCase, activeRoutingRules);
            }

            return routingCases;
        } catch (Cases.SecurityException e) {
            Logger.error('Security check failed during Case routing', e);
            throw e;
        } catch (CaseRoutingRulesService.CaseRoutingRulesServiceException e) {
            Logger.error('Case routing rules retrieval failed', e);
            throw e;
        } catch (Exception e) {
            Logger.error('CasesService.applyCaseRoutingRules failed', e);
            throw new CasesServiceException('Failed to apply case routing rules: ' + e.getMessage(), e);
        }
    }

    /**
     * @description GW-1279 - Finds the first matching routing rule for the Case (by design priority), then calls
     *              populateCaseFromRule and stops.
     * @param currentCase Case to evaluate and populate in memory (before insert)
     * @param activeRoutingRules Active rules for relevant Case Assignment values, ordered by priority
     */
    private static void findMatchingRulesAndPopulateCase(
        Case currentCase,
        List<CaseRoutingRule__c> activeRoutingRules
    ) {
        if (currentCase == null || activeRoutingRules == null || activeRoutingRules.isEmpty()) {
            return;
        }

        for (CaseRoutingRule__c rule : activeRoutingRules) {
            if (rule.CaseAssignment__c != currentCase.Origin) {
                continue;
            }

            if (String.isNotBlank(rule.SuppliedEmailFromAddress__c)) {
                String ruleEmail = rule.SuppliedEmailFromAddress__c.trim();
                String caseEmail = String.isBlank(currentCase.SuppliedEmail)
                    ? ''
                    : currentCase.SuppliedEmail.trim();
                if (!caseEmail.equalsIgnoreCase(ruleEmail)) {
                    continue;
                }
            }

            if (String.isNotBlank(rule.SubjectSearchString__c)) {
                Pattern subjectPattern = CaseRoutingRulesService.getPattern(rule.SubjectSearchString__c);
                if (String.isBlank(currentCase.Subject) || subjectPattern == null
                    || !subjectPattern.matcher(currentCase.Subject).find()) {
                    continue;
                }
            }

            if (String.isNotBlank(rule.DescriptionSearchString__c)) {
                Pattern descriptionPattern = CaseRoutingRulesService.getPattern(rule.DescriptionSearchString__c);
                if (String.isBlank(currentCase.Description) || descriptionPattern == null
                    || !descriptionPattern.matcher(currentCase.Description).find()) {
                    continue;
                }
            }

            populateCaseFromRule(currentCase, rule);
            break;
        }
    }

    /**
     * @description GW-1279 - Stamps Case fields from a matched CaseRoutingRule__c (category, subcategory, label,
     *              close reason, optional Status Closed when a close reason is applied, optional CaseSource when
     *              system-generated). Dependent picklist values are sanitized via CaseRoutingRulesService.
     * @param currentCase Case row to update in memory (before insert)
     * @param rule First matching routing rule for this Case
     */
    private static void populateCaseFromRule(Case currentCase, CaseRoutingRule__c rule) {
        if (currentCase == null || rule == null) {
            return;
        }

        CaseRoutingRulesService.RoutingStampFieldValues stamp =
            CaseRoutingRulesService.resolveStampableRoutingFieldValues(currentCase, rule);

        if (String.isNotBlank(stamp.categoryApiValue)) {
            currentCase.Category__c = stamp.categoryApiValue;
        }
        if (String.isNotBlank(stamp.subCategoryApiValue)) {
            currentCase.SubCategory__c = stamp.subCategoryApiValue;
        }
        if (String.isNotBlank(stamp.closeReasonApiValue)) {
            currentCase.CloseReason__c = stamp.closeReasonApiValue;
            if (String.isNotBlank(rule.CloseCode__c)) {
                currentCase.Status = 'Closed';
            }
        }

        currentCase.Label__c = rule.LabelValue__c;

        if (rule.IsSystemGenerated__c == true) {
            currentCase.CaseSource__c = CASE_ROUTING_SOURCE_SYSTEM;
        }
    }

    /**
     * @description GW-1279 - Collects distinct Case Assignment values from Cases. Case Assignment corresponds to Case.Origin
     *              (aligned with CaseRoutingRule__c.CaseAssignment__c).
     * @param cases Case records to read Origin from (typically Inbox Support routing candidates)
     * @return Distinct non-blank Origin strings
     */
    public static Set<String> getCaseAssignmentOrigins(List<Case> cases) {
        Set<String> caseAssignmentOrigins = new Set<String>();
        if (cases == null || cases.isEmpty()) {
            return caseAssignmentOrigins;
        }
        for (Case caseRecord : cases) {
            if (String.isNotBlank(caseRecord.Origin)) {
                caseAssignmentOrigins.add(caseRecord.Origin);
            }
        }
        return caseAssignmentOrigins;
    }

    /**
     * @description Custom exception for Cases Service operations
     */
    public class CasesServiceException extends Exception {}
}