/**
 * @description Shared helpers for Summit skill integration: PFCL-derived Skill MasterLabel segments and related lookups.
 *              Platform exceptions are caught specifically, logged at ERROR with related SummitSkill__c rows when provided,
 *              then rethrown as SummitSkillIntegrationException (Nebula Logger: https://github.com/jongpie/NebulaLogger).
 */
public with sharing class SummitSkillsUtil {
    /**
     * @description Returns the PFCL prefix segment before the first slash, or the full value when no slash is present (blank PFCL unchanged).
     * @param pfclValue Raw SummitSkill__c.PFCL__c value.
     * @return Prefix used in Skill MasterLabel composition.
     */
    public static String getPfclPrefixForSkillMasterLabel(String pfclValue) {
        if (String.isBlank(pfclValue)) {
            return pfclValue;
        }
        return pfclValue.contains('/') ? pfclValue.substringBefore('/') : pfclValue;
    }

    /**
     * @description Builds the composite Skill MasterLabel used by SummitSkillProcessor (prefix + ' - ' + Work Type name).
     * @param pfclValue Raw PFCL__c value.
     * @param workTypeName WorkType__c name.
     * @return Composite label; mirrors processor concatenation when either field is null.
     */
    public static String buildCompositeSkillMasterLabel(String pfclValue, String workTypeName) {
        return getPfclPrefixForSkillMasterLabel(pfclValue) + ' - ' + workTypeName;
    }

    /** Active resources and inactive HRIS external ids from one ServiceResource query per batch chunk. */
    public class ServiceResourceByExternalIdLookup {
        public Map<String, ServiceResource> activeByExternalId = new Map<String, ServiceResource>();
        public Set<String> inactiveExternalIds = new Set<String>();
    }

    /**
     * @description Resolves ServiceResource rows by ExternalID__c; only active rows are returned for skill assignment.
     * @param externalIds Distinct ExternalID__c values from SummitSkill__c.HRISID__c.
     * @return Active resources keyed by ExternalID__c and external ids for inactive matches.
     */
    public static ServiceResourceByExternalIdLookup lookupServiceResourcesByExternalId(Set<String> externalIds) {
        return lookupServiceResourcesByExternalId(externalIds, null);
    }

    /**
     * @description Resolves ServiceResource rows by ExternalID__c; only active rows are returned for skill assignment.
     * @param externalIds Distinct ExternalID__c values from SummitSkill__c.HRISID__c.
     * @param relatedSummitSkills Optional SummitSkill__c rows for Nebula Logger record context on query failure.
     * @return Active resources keyed by ExternalID__c and external ids for inactive matches.
     */
    public static ServiceResourceByExternalIdLookup lookupServiceResourcesByExternalId(
        Set<String> externalIds,
        List<SummitSkill__c> relatedSummitSkills
    ) {
        ServiceResourceByExternalIdLookup result = new ServiceResourceByExternalIdLookup();
        if (externalIds == null || externalIds.isEmpty()) {
            return result;
        }
        try {
            for (ServiceResource sr : [
                SELECT Id, ExternalID__c, IsActive
                FROM ServiceResource
                WHERE ExternalID__c IN :externalIds
            ]) {
                if (sr.IsActive) {
                    result.activeByExternalId.put(sr.ExternalID__c, sr);
                } else {
                    result.inactiveExternalIds.add(sr.ExternalID__c);
                }
            }
        } catch (QueryException e) {
            LogEntryEventBuilder logEntry = Logger.newEntry(
                LoggingLevel.ERROR,
                'SummitSkillsUtil: query ServiceResource by ExternalID__c failed'
            ).setExceptionDetails(e);
            if (relatedSummitSkills != null && !relatedSummitSkills.isEmpty()) {
                logEntry.setRecord(relatedSummitSkills[0]);
            }
            throw new SummitSkillIntegrationException(
                'Summit skill integration: failed to query ServiceResource rows for HRIS external ids '
                    + String.join(new List<String>(externalIds), ', ')
                    + '. '
                    + e.getMessage()
            );
        } finally {
            Logger.saveLog();
        }
        return result;
    }

    /**
     * @description Loads active ServiceResource rows keyed by ExternalID__c for Summit HRIS identifiers.
     * @param externalIds Distinct ExternalID__c values from SummitSkill__c.HRISID__c.
     * @return Map of ExternalID__c to active ServiceResource.
     */
    public static Map<String, ServiceResource> mapServiceResourcesByExternalId(Set<String> externalIds) {
        return lookupServiceResourcesByExternalId(externalIds).activeByExternalId;
    }
}