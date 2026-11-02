/**
 * @description GW-5102 - Flow action that sends Repair Center quote emails with From and
 *              Reply-To as separate addresses. Standard Flow Send Email cannot set Reply-To
 *              independently of From.
 */
public with sharing class RepairCenterQuoteEmailSendAction {
    private static final String SCENARIO_NAME = 'Repair Center Quote Email';
    private static final String DEFAULT_SENDER_ADDRESS = 'gwftest_no-reply@steris.com';

    @TestVisible
    private static List<Messaging.SingleEmailMessage> lastMessages;
    @TestVisible
    private static Id orgWideEmailAddressIdOverride;

    /**
     * @description Flow inputs for one quote email send.
     */
    public class Request {
        @InvocableVariable(label='Recipient Id' required=true)
        public Id recipientId;

        @InvocableVariable(label='Recipient Addresses')
        public List<String> recipientAddresses;

        @InvocableVariable(label='Related Record Id' required=true)
        public Id relatedRecordId;

        @InvocableVariable(label='Email Template Id' required=true)
        public Id emailTemplateId;

        @InvocableVariable(label='Attachment Ids')
        public List<String> attachmentIds;

        @InvocableVariable(label='Sender Address')
        public String senderAddress;

        @InvocableVariable(label='Log Email On Send')
        public Boolean logEmailOnSend;
    }

    public class RepairCenterQuoteEmailSendException extends Exception {
    }

    /**
     * @description Sends templated quote emails. From uses the org-wide address; Reply-To is
     *              the inbound email service from ExternalSystemEndpoint.RepairCenterQuoteEmail.
     * @param requests Flow send requests
     */
    @InvocableMethod(
        label='Send Quote Email with Reply-To'
        description='Sends the Repair Center quote email using a template. From is the org-wide address; Reply-To is the inbound email service.'
    )
    public static void send(List<Request> requests) {
        if (requests == null || requests.isEmpty()) {
            return;
        }

        Logger.setScenario(SCENARIO_NAME);
        try {
            Map<Id, Contact> contactsById = queryContacts(requests);
            Map<String, Id> orgWideEmailAddressIdsByAddress = queryOrgWideEmailAddressIds(
                collectSenderAddresses(requests)
            );
            List<Messaging.SingleEmailMessage> messages = new List<Messaging.SingleEmailMessage>();
            for (Request request : requests) {
                messages.add(
                    buildMessage(request, contactsById, orgWideEmailAddressIdsByAddress)
                );
            }
            lastMessages = messages;
            if (Test.isRunningTest()) {
                return;
            }
            sendMessages(messages);
        } catch (RepairCenterQuoteEmailSendException e) {
            Logger.error('RepairCenterQuoteEmailSendAction.send', e);
            throw e;
        } catch (Exception e) {
            Logger.error('RepairCenterQuoteEmailSendAction.send', e);
            throw new RepairCenterQuoteEmailSendException(
                'Quote email could not be sent: ' + e.getMessage(),
                e
            );
        } finally {
            Logger.saveLog();
        }
    }

    private static Messaging.SingleEmailMessage buildMessage(
        Request request,
        Map<Id, Contact> contactsById,
        Map<String, Id> orgWideEmailAddressIdsByAddress
    ) {
        if (request == null || request.recipientId == null) {
            throw new RepairCenterQuoteEmailSendException('A recipient Contact is required.');
        }
        if (request.relatedRecordId == null) {
            throw new RepairCenterQuoteEmailSendException('A related Work Order is required.');
        }
        if (request.emailTemplateId == null) {
            throw new RepairCenterQuoteEmailSendException('An email template is required.');
        }

        Contact recipient = contactsById.get(request.recipientId);
        if (recipient == null || String.isBlank(recipient.Email)) {
            throw new RepairCenterQuoteEmailSendException(
                'The recipient Contact must have an email address.'
            );
        }

        String senderAddress = String.isBlank(request.senderAddress)
            ? DEFAULT_SENDER_ADDRESS
            : request.senderAddress.trim();
        Id orgWideEmailAddressId = orgWideEmailAddressIdsByAddress.get(senderAddress.toLowerCase());
        if (orgWideEmailAddressId == null) {
            throw new RepairCenterQuoteEmailSendException(
                'No org-wide email address was found for ' + senderAddress + '.'
            );
        }

        List<String> toAddresses = collectToAddresses(recipient.Email, request.recipientAddresses);
        Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
        mail.setTemplateId(request.emailTemplateId);
        mail.setTargetObjectId(request.recipientId);
        mail.setTreatTargetObjectAsRecipient(false);
        mail.setToAddresses(toAddresses);
        mail.setWhatId(request.relatedRecordId);
        mail.setSaveAsActivity(request.logEmailOnSend != false);
        mail.setUseSignature(false);
        mail.setOrgWideEmailAddressId(orgWideEmailAddressId);
        mail.setReplyTo(ExternalSystemEndpointSelector.repairCenterQuoteInboundEmail());

        List<String> entityAttachmentIds = resolveAttachmentIds(request.attachmentIds);
        if (!entityAttachmentIds.isEmpty()) {
            mail.setEntityAttachments(entityAttachmentIds);
        }
        return mail;
    }

    private static void sendMessages(List<Messaging.SingleEmailMessage> messages) {
        Messaging.SendEmailResult[] results = Messaging.sendEmail(messages, false);
        List<String> errors = new List<String>();
        for (Messaging.SendEmailResult result : results) {
            if (result.isSuccess()) {
                continue;
            }
            for (Messaging.SendEmailError error : result.getErrors()) {
                errors.add(error.getMessage());
            }
        }
        if (!errors.isEmpty()) {
            throw new RepairCenterQuoteEmailSendException(String.join(errors, '; '));
        }
    }

    private static Map<Id, Contact> queryContacts(List<Request> requests) {
        Set<Id> contactIds = new Set<Id>();
        for (Request request : requests) {
            if (request != null && request.recipientId != null) {
                contactIds.add(request.recipientId);
            }
        }
        if (contactIds.isEmpty()) {
            return new Map<Id, Contact>();
        }
        return new Map<Id, Contact>([SELECT Id, Email FROM Contact WHERE Id IN :contactIds]);
    }

    private static Set<String> collectSenderAddresses(List<Request> requests) {
        Set<String> addresses = new Set<String>();
        for (Request request : requests) {
            String senderAddress = request == null || String.isBlank(request.senderAddress)
                ? DEFAULT_SENDER_ADDRESS
                : request.senderAddress.trim();
            addresses.add(senderAddress);
        }
        return addresses;
    }

    private static Map<String, Id> queryOrgWideEmailAddressIds(Set<String> addresses) {
        Map<String, Id> idsByAddress = new Map<String, Id>();
        if (addresses == null || addresses.isEmpty()) {
            return idsByAddress;
        }
        if (orgWideEmailAddressIdOverride != null) {
            for (String address : addresses) {
                idsByAddress.put(address.toLowerCase(), orgWideEmailAddressIdOverride);
            }
            return idsByAddress;
        }

        for (OrgWideEmailAddress orgWideEmailAddress : [
            SELECT Id, Address
            FROM OrgWideEmailAddress
            WHERE Address IN :addresses
        ]) {
            if (String.isBlank(orgWideEmailAddress.Address)) {
                continue;
            }
            idsByAddress.put(orgWideEmailAddress.Address.toLowerCase(), orgWideEmailAddress.Id);
        }
        return idsByAddress;
    }

    private static List<String> collectToAddresses(
        String primaryEmail,
        List<String> recipientAddresses
    ) {
        List<String> toAddresses = new List<String>();
        Set<String> seen = new Set<String>();
        addToAddress(toAddresses, seen, primaryEmail);
        if (recipientAddresses == null) {
            return toAddresses;
        }
        for (String recipientAddress : recipientAddresses) {
            addToAddress(toAddresses, seen, recipientAddress);
        }
        return toAddresses;
    }

    private static void addToAddress(
        List<String> toAddresses,
        Set<String> seen,
        String emailAddress
    ) {
        if (String.isBlank(emailAddress)) {
            return;
        }
        String trimmed = emailAddress.trim();
        String key = trimmed.toLowerCase();
        if (seen.contains(key)) {
            return;
        }
        seen.add(key);
        toAddresses.add(trimmed);
    }

    private static List<String> resolveAttachmentIds(List<String> attachmentIds) {
        List<String> resolved = new List<String>();
        if (attachmentIds == null) {
            return resolved;
        }
        for (String attachmentId : attachmentIds) {
            if (String.isBlank(attachmentId)) {
                continue;
            }
            try {
                resolved.add(String.valueOf(Id.valueOf(attachmentId.trim())));
            } catch (Exception e) {
                Logger.warn(
                    'RepairCenterQuoteEmailSendAction: skipped invalid attachment id ' +
                    attachmentId
                );
            }
        }
        return resolved;
    }
}