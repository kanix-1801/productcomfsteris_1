/**
 * EmailMessagesService
 *
 * Service layer entry point for EmailMessage processing.
 * - Orchestrates domain logic for after-insert scenarios.
 * - Creates no SOQL/DML directly; delegates to Domain per STERIS standards.
 * - Uses Nebula Logger for error reporting.
 *
 * Layering:
 *   Controller/Trigger -> Service (this class) -> Domain (EmailMessagesDomain)
 *
 * @author STERIS
 * @since 1.0
 */
public with sharing class EmailMessagesService {
    /**
     * Entry point for EmailMessage after-insert processing.
     * Orchestrates domain logic.
     *
     * @param newRecords List of EmailMessage records from trigger.new
     */
    public static void outboundEmailSDNProcessing(List<EmailMessage> newRecords) {
        if (newRecords == null || newRecords.isEmpty()) {
            return;
        }

        try {
            // Domain encapsulates object-specific logic
            EmailMessagesDomain domain = new EmailMessagesDomain(newRecords);
            // Apply trigger-specific business rules migrated from legacy trigger
            domain.filterOutProjectRelated();
            // CBM Logic
            EmailMessageHandler.EmAfterInsertHandler(domain.getRecords());
        } catch (Exception e) {
            Logger.error('EmailMessagesService.handleAfterInsert', e);
            throw e;
        }
    }

    /**
     * @description GW-5102 - Inserts inbound EmailMessage rows related to a parent record (e.g. Work Order).
     * @param emailMessages EmailMessage records to insert
     * @return Inserted EmailMessage records
     */
    public static List<EmailMessage> createInboundEmailMessages(List<EmailMessage> emailMessages) {
        if (emailMessages == null || emailMessages.isEmpty()) {
            return new List<EmailMessage>();
        }
        Logger.setScenario('Inbound Email');
        try {
            insert emailMessages;
            return emailMessages;
        } catch (Exception e) {
            Logger.error('EmailMessagesService.createInboundEmailMessages', e);
            throw e;
        } finally {
            Logger.saveLog();
        }
    }
}