/**
 * @author PSL
 * @date 01-02-2026
 * @description Trigger handler for EmailMessage. Coordinates post-insert processing and delegates
 *              to EmailMessageHelper to evaluate outbound SDN emails and update related records.
 */
public with sharing class EmailMessageHandler {

    /**
             * @description handler engine to evaluate EmailMessage based on trigger  and call the helper engine to perform 
             * @EmailMessage
             * @author PSL
             * @date 01-02-2026
             * @notes
             * - Loads active mail sent on case.
             * - supports email Message
        */   
         public static void EmAfterInsertHandler(List<EmailMessage> em) {
        EmailMessageHelper.orderLineFlagSet(em);
        EmailMessageHelper.setCaseGoNoGoDecision(em);
        EmailMessageHelper.goNoGoReminderDates(em);
    }

}