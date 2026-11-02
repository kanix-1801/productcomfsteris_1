/**
 * @description GW-5102 - Contract for inbound email processors resolved from EmailInboundRoute__mdt.
 */
public interface EmailInboundProcessor {
    /**
     * @description Applies object-specific updates after the generic handler logs activity.
     * @param request Inbound email context including the related record
     */
    void process(EmailInboundService.Request request);
}