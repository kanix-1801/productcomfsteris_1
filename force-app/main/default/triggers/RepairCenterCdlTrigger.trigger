/**
 * @description GW-5830 - Repair Center ContentDocumentLink trigger. Separate from the
 *              platform ContentDocumentLinkTrigger so quote-email automation stays untouched.
 *              Delegates to RepairCenterCdlTriggerHandler.
 */
trigger RepairCenterCdlTrigger on ContentDocumentLink(after insert) {
    new RepairCenterCdlTriggerHandler().run();
}