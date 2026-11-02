/**
 * @description Domain class for Case object - handles object-specific business logic,
 *              validation, and defaults. Registers DML operations but does not commit.
 *              Follows STERIS enterprise architecture standards.
 * @author STERIS
 * @date 2026-04-22
 */
public with sharing class Cases {

    /**
     * GW-1279 - Working set of Case records (not final so filter methods can replace the list reference, same pattern as
     * EmailMessagesDomain).
     */
    private List<Case> records;
    
    /**
     * @description Constructor that accepts a list of Case records
     * @param records List of Case records to operate on
     */
    public Cases(List<Case> records) {
        this.records = records != null ? records : new List<Case>();
    }
    
    /**
     * @description GW-1279 - Filters out Case records whose RecordTypeId does not match the Inbox Support record type,
     *              and records with blank SuppliedEmail (routing requires a supplied address).
     *              Replaces the domain working list so only matching records remain for downstream routing logic.
     * @param inboxSupportRecordTypeId Case RecordType Id for Inbox Support (from CasesService resolution).
     * @remarks When inboxSupportRecordTypeId is null, the working set is cleared so routing does not run against
     *          an unknown record type. Does not remove rows from the caller list; only the domain reference is replaced.
     */
    public void filterOutNonInboxSupportRecords(Id inboxSupportRecordTypeId) {
        if (records.isEmpty()) {
            return;
        }

        if (inboxSupportRecordTypeId == null) {
            records = new List<Case>();
            return;
        }

        List<Case> filtered = new List<Case>();
        for (Case caseRecord : records) {
            if (caseRecord.RecordTypeId == inboxSupportRecordTypeId && !String.isBlank(caseRecord.SuppliedEmail)) {
                filtered.add(caseRecord);
            }
        }
        records = filtered;
    }

    /**
     * @description GW-1279 - Returns the current list of Case records in the domain, which may have been narrowed by
     *              filterOutNonInboxSupportRecords.
     * @return List of Case records in the domain working set
     */
    public List<Case> getRecords() {
        return records;
    }

    /**
     * @description Performs security checks before DML operations
     * @param operation String indicating the DML operation ('insert', 'update', 'delete')
     * @throws SecurityException if user lacks necessary permissions
     */
    public void checkSecurity(String operation) {
        if (operation == 'insert') {
            if (!Schema.sObjectType.Case.isCreateable()) {
                throw new SecurityException('User does not have permission to create Case records');
            }
        } else if (operation == 'update') {
            if (!Schema.sObjectType.Case.isUpdateable()) {
                throw new SecurityException('User does not have permission to update Case records');
            }
        } else if (operation == 'delete') {
            if (!Schema.sObjectType.Case.isDeletable()) {
                throw new SecurityException('User does not have permission to delete Case records');
            }
        }
    }
    
    /**
     * @description Custom exception for security violations
     */
    public class SecurityException extends Exception {}

    /**
     * @description GW-3997 - Related window size in days around Case Created/Closed dates for FCR matching.
     */
    @TestVisible
    private static final Integer FCR_RELATED_WINDOW_DAYS = 7;

    /**
     * @description GW-3997 - Evaluates IsFCR__c for domain Cases using activity and related-case counts.
     *              FCR is true when sent emails + voice calls + related matching cases (excluding self) equals 1.
     * @param sentEmailCountByCaseIdMap Sent EmailMessage counts by Case Id
     * @param voiceCallCountByCaseIdMap VoiceCall counts by Case Id
     * @param relatedCaseList Candidate related Cases for identifier/category matching
     * @return Cases whose IsFCR__c value changed and should be updated
     */
    public List<Case> applyFcrEvaluation(
        Map<Id, Integer> sentEmailCountByCaseIdMap,
        Map<Id, Integer> voiceCallCountByCaseIdMap,
        List<Case> relatedCaseList
    ) {
        List<Case> caseToUpdateList = new List<Case>();
        if (records.isEmpty()) {
            return caseToUpdateList;
        }

        Map<Id, Integer> emailCountMap =
            sentEmailCountByCaseIdMap != null ? sentEmailCountByCaseIdMap : new Map<Id, Integer>();
        Map<Id, Integer> callCountMap =
            voiceCallCountByCaseIdMap != null ? voiceCallCountByCaseIdMap : new Map<Id, Integer>();
        List<Case> relatedList = relatedCaseList != null ? relatedCaseList : new List<Case>();

        // Evaluate each Case against the three FCR query counts.
        for (Case currentCase : records) {
            if (currentCase.ClosedDate == null || String.isBlank(currentCase.Category__c)) {
                continue;
            }

            Integer emailCount = emailCountMap.containsKey(currentCase.Id)
                ? emailCountMap.get(currentCase.Id)
                : 0;
            Integer callCount = callCountMap.containsKey(currentCase.Id)
                ? callCountMap.get(currentCase.Id)
                : 0;
            Integer matchingCaseCount = countRelatedMatches(currentCase, relatedList);
            Integer totalCount = emailCount + callCount + matchingCaseCount;
            Boolean newFcrStatus = (totalCount == 1);

            if (currentCase.IsFCR__c != newFcrStatus) {
                currentCase.IsFCR__c = newFcrStatus;
                caseToUpdateList.add(currentCase);
            }
        }
        return caseToUpdateList;
    }

    /**
     * @description GW-3997 - Counts related Cases that share category and at least one identifier
     *              within the CreatedDate window of [CreatedDate - 7d, ClosedDate + 7d].
     *              The Case being evaluated is excluded (Id != $Record.Id).
     * @param currentCase Case being evaluated
     * @param relatedCaseList Candidate related Cases
     * @return Number of matching related Cases excluding the current Case
     */
    @TestVisible
    private static Integer countRelatedMatches(Case currentCase, List<Case> relatedCaseList) {
        if (currentCase == null || relatedCaseList == null || relatedCaseList.isEmpty()) {
            return 0;
        }
        if (currentCase.CreatedDate == null || currentCase.ClosedDate == null) {
            return 0;
        }

        Datetime minCreatedDate = currentCase.CreatedDate.addDays(-FCR_RELATED_WINDOW_DAYS);
        Datetime maxCreatedDate = currentCase.ClosedDate.addDays(FCR_RELATED_WINDOW_DAYS);
        Integer matchingCaseCount = 0;

        // Count other Cases that match category, date window, and at least one identifier.
        for (Case matchCase : relatedCaseList) {
            if (matchCase.Id == currentCase.Id) {
                continue;
            }
            if (
                matchCase.CreatedDate < minCreatedDate
                || matchCase.CreatedDate > maxCreatedDate
                || matchCase.Category__c != currentCase.Category__c
            ) {
                continue;
            }

            Boolean matchesIdentifier =
                (currentCase.ContactId != null && matchCase.ContactId == currentCase.ContactId)
                || (currentCase.AssetId != null && matchCase.AssetId == currentCase.AssetId)
                || (
                    String.isNotBlank(currentCase.SerialNumber__c)
                    && matchCase.SerialNumber__c == currentCase.SerialNumber__c
                )
                || (
                    String.isNotBlank(currentCase.SuppliedEmail)
                    && matchCase.SuppliedEmail == currentCase.SuppliedEmail
                );

            if (matchesIdentifier) {
                matchingCaseCount++;
            }
        }
        return matchingCaseCount;
    }
}