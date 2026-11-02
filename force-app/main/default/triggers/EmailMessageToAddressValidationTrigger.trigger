trigger EmailMessageToAddressValidationTrigger on EmailMessage (before insert) {
    EmailMessageToAddressValidationHandler.handleBeforeInsert(Trigger.new);
}