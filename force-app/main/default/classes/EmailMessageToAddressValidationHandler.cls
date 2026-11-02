public class EmailMessageToAddressValidationHandler {

    public static void handleBeforeInsert(List<EmailMessage> newEmails) {
        EmailMessageToAddressValidationService.validateToAddress(newEmails);
    }
}