/**
 * @description Selector for EmailMessage queries.
 * Centralizes a consistent field set via BASE_FIELDS and provides guarded query methods with sharing and security enforced.
 *
 * @group Selectors
 * @see EmailMessage
 * @since 1.0
 * @author STERIS
 *
 * @remarks
 * - Class declared with sharing to respect record visibility.
 * - All SOQL uses WITH SECURITY_ENFORCED to honor FLS and sharing.
 * - Avoid SOQL/DML in loops; methods are bulk-safe.
 *
 * @usage
 * List<EmailMessage> emails = EmailMessagesSelector.selectByIds(new Set<Id>{ someId1, someId2 });
 */
public with sharing class EmailMessagesSelector {
    // Centralized base fields for EmailMessage queries
    public static final String BASE_FIELDS =
        'Id, Subject, FromAddress, ToAddress, CcAddress, BccAddress, Status, ' +
        'MessageDate, Incoming, RelatedToId, ParentId, CreatedById, CreatedDate, LastModifiedDate';

    /**
     * @description Retrieves EmailMessage records by Id using a consistent field set.
     * Guards against null or empty input to avoid non-selective queries.
     *
     * @param ids Set<Id> The EmailMessage record Ids to retrieve.
     * @return List<EmailMessage> The matching EmailMessage records with fields defined in BASE_FIELDS.
     * @example
     * List<EmailMessage> emails = EmailMessagesSelector.selectByIds(new Set<Id>{ someId1, someId2 });
     */
    // Guarded select by Ids with WITH SECURITY_ENFORCED
    public static List<EmailMessage> selectByIds(Set<Id> ids) {
        if (ids == null || ids.isEmpty()) {
            return new List<EmailMessage>();
        }
        return Database.query('SELECT ' + BASE_FIELDS + // NOPMD, the field is defined in this file
            ' FROM EmailMessage WHERE Id IN :ids WITH SECURITY_ENFORCED');
    }

    /**
     * @description GW-3997 - Counts sent EmailMessages (Status = 3) grouped by Case ParentId.
     * @param parentCaseIdSet Case Ids to count against
     * @return Map of Case Id to sent email count
     */
    public static Map<Id, Integer> countSentByParentCaseIds(Set<Id> parentCaseIdSet) {
        Map<Id, Integer> sentCountByCaseIdMap = new Map<Id, Integer>();
        if (parentCaseIdSet == null || parentCaseIdSet.isEmpty()) {
            return sentCountByCaseIdMap;
        }

        for (AggregateResult aggregateRow : [
            SELECT ParentId parentId, COUNT(Id) total
            FROM EmailMessage
            WHERE ParentId IN :parentCaseIdSet
                AND Status = '3'
            WITH SECURITY_ENFORCED
            GROUP BY ParentId
        ]) {
            sentCountByCaseIdMap.put(
                (Id) aggregateRow.get('parentId'),
                (Integer) aggregateRow.get('total')
            );
        }
        return sentCountByCaseIdMap;
    }

    /**
     * @description GW-5102 - EmailMessage rows related to the given records (Work Order activity).
     * @param relatedToIds RelatedToId values
     * @return Matching EmailMessage records
     */
    public static List<EmailMessage> selectByRelatedToIds(Set<Id> relatedToIds) {
        if (relatedToIds == null || relatedToIds.isEmpty()) {
            return new List<EmailMessage>();
        }
        return [
            SELECT Id, Subject, FromAddress, ToAddress, Incoming, RelatedToId, TextBody, MessageDate
            FROM EmailMessage
            WHERE RelatedToId IN :relatedToIds
            WITH SYSTEM_MODE
            ORDER BY CreatedDate DESC
        ];
    }

    /**
     * @description GW-5102 - Outbound EmailMessage rows whose Message-ID matches In-Reply-To / References.
     * @param messageIdentifiers Normalized and bracketed Message-ID values
     * @return Matching EmailMessage records, newest first
     */
    public static List<EmailMessage> selectByMessageIdentifiers(Set<String> messageIdentifiers) {
        if (messageIdentifiers == null || messageIdentifiers.isEmpty()) {
            return new List<EmailMessage>();
        }
        return [
            SELECT Id, RelatedToId, MessageIdentifier, CreatedDate
            FROM EmailMessage
            WHERE MessageIdentifier IN :messageIdentifiers
            WITH SYSTEM_MODE
            ORDER BY CreatedDate DESC
        ];
    }
}