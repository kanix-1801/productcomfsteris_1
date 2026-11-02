/**
 * EmailMessagesDomain encapsulates business rules and utilities for working with EmailMessage records.
 * It centralizes domain logic such as filtering out records related to Project__c and exposes a clean API
 * for service-layer orchestration (for example, EmailMessagesService) to keep code organized and maintainable.
 *
 * @author Dana Wolfe
 * @date 2026-03-18
 */
public with sharing class EmailMessagesDomain {
    private List<EmailMessage> records;

    /**
    * @description Populates the domain with a list of EmailMessage records. The records are deep cloned to handle scenarios where a non-modifiable
    * list is passed in, ensuring that the domain has its own copy to work with.
    * @param records List of EmailMessage records to be processed by the domain.
    * @remarks If null is passed, it initializes with an empty list to avoid null pointer exceptions in subsequent processing.
    */
    public EmailMessagesDomain(List<EmailMessage> records) {
        this.records = (records == null) ? new List<EmailMessage>() : records.deepClone(true, true, true);
    }

    /**
     * @description Filters out EmailMessage records whose RelatedToId is a Project__c. This method modifies the internal list of records
     * to only include those that are not related to Project__c.
     * @remarks This method is designed to be called before any processing that should exclude Project__c-related EmailMessages,
     * ensuring that the domain's working set of records is appropriately filtered for downstream logic.
     */
    public void filterOutProjectRelated() {
        if (records.isEmpty()) { return; }

        List<EmailMessage> filtered = new List<EmailMessage>();
        for (EmailMessage em : records) {
            if (em.RelatedToId == null) {
                filtered.add(em);
                continue;
            }
            // Use SObjectType compare without queries; bulk-safe
            if (em.RelatedToId.getSObjectType() != Project__c.SObjectType) {
                filtered.add(em);
            }
        }
        records = filtered;
    }

    // Expose the working set when needed by services/selectors
    /**
     * @description Returns the current list of EmailMessage records in the domain, which may have been filtered by the filterOutProjectRelated method.
     * @return  `List<EmailMessage>`
     */
    public List<EmailMessage> getRecords() {
        return records;
    }
}