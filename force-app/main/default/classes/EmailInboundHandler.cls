/**
 * @description GW-5102 - Thin Apex Email Service entry point (Messaging.InboundEmailHandler).
 *              Parses the envelope via EmailInboundService only. No SOQL, no Quote/QLI/WOLI rules.
 */
public with sharing class EmailInboundHandler implements Messaging.InboundEmailHandler {
    /**
     * @description Processes one inbound email from the Email Service.
     * @param email Inbound email payload
     * @param envelope Inbound envelope
     * @return Result indicating the message was accepted
     */
    public Messaging.InboundEmailResult handleInboundEmail(
        Messaging.InboundEmail email,
        Messaging.InboundEnvelope envelope
    ) {
        return EmailInboundService.handleInboundEmail(email, envelope);
    }
}