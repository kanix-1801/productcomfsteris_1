/**
 * Trigger handler for EmailMessage.
 *
 * Responsibilities:
 * - Orchestrates domain/service logic only. No SOQL/DML in this handler per standards.
 * - Delegates after-insert processing to EmailMessagesService.
 *
 * Trigger contexts implemented:
 * - afterInsert: Processes outbound email SDN handling for newly inserted EmailMessage records.
 *
 * Notes:
 * - Uses TriggerHandler framework for recursion control and consistency.
 * - Keep this class free of business logic; use Services/Domains for implementation.
 *
 * @author STERIS
 */
public class EmailMessageTriggerHandler extends TriggerHandler {
    
    /**
     * @description Constructor - optionally configure recursion control
     */
    public EmailMessageTriggerHandler() {
        super();
        
    }

    // Per standards: no SOQL/DML here. Orchestrates Domain/Service only.

    @TestVisible
    protected override void afterInsert() {
        if (!AutomationControl.isTriggerEnabled('EmailMessageTrigger')) return;
        // Delegate to Service entry point for business orchestration
        EmailMessagesService.outboundEmailSDNProcessing((List<EmailMessage>) Trigger.new);
        EmailMessageHelper.orderLineFlagSet((List<EmailMessage>) Trigger.new);
        EmailMessageHelper.setCaseGoNoGoDecision((List<EmailMessage>) Trigger.new);
        EmailMessageHelper.goNoGoReminderDates((List<EmailMessage>) Trigger.new);
        Set<Id> emailMessageIds = new Set<Id>();
        for (EmailMessage em : (List<EmailMessage>) Trigger.new) {
            emailMessageIds.add(em.Id);
        }
        EmailMessageHelper.nullifyRelationId(emailMessageIds);
    }
}