/**
 * @author Uptima Development Team
 * @date 2026-10-26
 * @description GW-6191 - Sends the On Location End of Day Report to the selected Contact, with the
 *              current user and their manager in CC. Called from ServiceAppointment_Updated_AfterSave
 *              when the IMS completion mobile flow requests the report, before the completed child Work Orders
 *              are closed, so the report still finds them.
 *              GW-6257 - CRSS site visits use the CRSS template with the inspected asset tables. The Contact is
 *              optional, and the report can go to several emails separated by ;.
 *              GW-6191 - CRSS site visits no longer get a report; only the IMS template is used.
 * @group Service Appointment
 * @see OnLocationEndOfDayReportController
 */
public without sharing class OnLocationEndOfDayReportAction {
    /** @description Developer name of the IMS Visualforce email template. */
    public static final String TEMPLATE_DEVELOPER_NAME = 'OnLocationEndOfDayReport';
    /** @description GW-6257 - Basic email shape check for each typed address. */
    private static final Pattern EMAIL_PATTERN = Pattern.compile('^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$');

    /**
     * @description Flow input.
     */
    public class Request {
        /** @description Site visit Work Order the report is about. */
        @InvocableVariable(label='Site Visit Work Order Id' required=true)
        public Id siteVisitWorkOrderId;

        /** @description Contact the technician picked to receive the report, if any. */
        @InvocableVariable(label='Contact Id')
        public Id contactId;

        /** @description Emails the technician approved or typed, separated by ;. The Contact email is used when blank. */
        @InvocableVariable(label='Recipient Email')
        public String recipientEmail;
    }

    /**
     * @description Flow output.
     */
    public class Result {
        /** @description Number of recipients, including CC. */
        @InvocableVariable(label='Sent Count')
        public Integer sentCount;

        /** @description Message shown to the technician. */
        @InvocableVariable(label='Message')
        public String message;
    }

    /**
     * @description Sends the report for each site visit.
     * @param requests Site visit Work Order Ids
     * @return One result per request
     */
    @InvocableMethod(
        label='Send On Location End of Day Report'
        description='GW-6191: Emails the End of Day Report to the selected Contact, the current user, and their manager.'
        category='Service Appointment'
    )
    public static List<Result> sendReport(List<Request> requests) {
        List<EmailTemplate> templates = [
            SELECT Id
            FROM EmailTemplate
            WHERE DeveloperName = :TEMPLATE_DEVELOPER_NAME
            LIMIT 1
        ];
        Id templateId = templates.isEmpty() ? null : templates[0].Id;

        List<Result> results = new List<Result>();
        for (Request request : requests) {
            results.add(templateId == null
                ? failure('The End of Day Report email template is missing.')
                : sendForSiteVisit(templateId, request));
        }
        return results;
    }

    /**
     * @description Emails of the current user and their active manager.
     * @return CC addresses, current user first
     */
    private static List<String> selectCcAddresses() {
        List<String> ccAddresses = new List<String>();
        for (User user : [
            SELECT Email, Manager.Email, Manager.IsActive
            FROM User
            WHERE Id = :UserInfo.getUserId()
            LIMIT 1
        ]) {
            if (String.isNotBlank(user.Email)) {
                ccAddresses.add(user.Email);
            }
            if (user.Manager != null && user.Manager.IsActive && String.isNotBlank(user.Manager.Email)) {
                ccAddresses.add(user.Manager.Email);
            }
        }
        return ccAddresses;
    }

    /**
     * @description Splits typed emails on ; or , and drops blanks.
     * @param emails Emails as typed
     * @return Trimmed addresses
     */
    private static List<String> splitEmails(String emails) {
        List<String> addresses = new List<String>();
        if (String.isBlank(emails)) {
            return addresses;
        }
        for (String address : emails.split('[;,]')) {
            if (String.isNotBlank(address)) {
                addresses.add(address.trim());
            }
        }
        return addresses;
    }

    /**
     * @description Renders the report and sends it to the approved emails with the user and manager in CC.
     *              The Contact, when selected, is the template recipient. The Contact record is not updated.
     * @param templateId End of Day Report template
     * @param request Site visit, optional selected Contact, and approved emails
     * @return Send result
     */
    private static Result sendForSiteVisit(Id templateId, Request request) {
        if (request?.siteVisitWorkOrderId == null) {
            return failure('The site visit work order could not be identified.');
        }
        Contact contact;
        if (request.contactId != null) {
            List<Contact> contacts = [
                SELECT Id, Name, Email
                FROM Contact
                WHERE Id = :request.contactId
                LIMIT 1
            ];
            if (contacts.isEmpty()) {
                return failure('The selected contact could not be found. The End of Day Report was not sent.');
            }
            contact = contacts[0];
        }
        List<String> toAddresses = splitEmails(
            String.isNotBlank(request.recipientEmail) ? request.recipientEmail : contact?.Email
        );
        if (toAddresses.isEmpty()) {
            return failure(contact == null
                ? 'No email was entered. The End of Day Report was not sent.'
                : 'The selected contact has no email. The End of Day Report was not sent.');
        }
        List<String> invalidAddresses = new List<String>();
        for (String address : toAddresses) {
            if (!EMAIL_PATTERN.matcher(address).matches()) {
                invalidAddresses.add(address);
            }
        }
        if (!invalidAddresses.isEmpty()) {
            return failure('These emails are not valid: ' + String.join(invalidAddresses, ', ')
                + '. The End of Day Report was not sent.');
        }

        try {
            Messaging.SingleEmailMessage rendered = Messaging.renderStoredEmailTemplate(
                templateId,
                contact?.Id,
                request.siteVisitWorkOrderId
            );
            List<String> ccAddresses = selectCcAddresses();
            Messaging.SingleEmailMessage message = new Messaging.SingleEmailMessage();
            message.setToAddresses(toAddresses);
            message.setCcAddresses(ccAddresses);
            message.setSubject(rendered.getSubject());
            message.setHtmlBody(rendered.getHtmlBody());
            message.setPlainTextBody(rendered.getPlainTextBody());
            message.setSaveAsActivity(false);

            Messaging.SendEmailResult sendResult = Messaging.sendEmail(
                new List<Messaging.SingleEmailMessage>{ message },
                false
            )[0];
            if (!sendResult.isSuccess()) {
                return failure('The End of Day Report was not sent. '
                    + (sendResult.getErrors().isEmpty() ? '' : sendResult.getErrors()[0].getMessage()));
            }
            Result result = new Result();
            result.sentCount = toAddresses.size() + ccAddresses.size();
            result.message = 'The End of Day Report was sent to '
                + (contact == null ? '' : contact.Name + ' ')
                + '(' + String.join(toAddresses, ', ') + ')'
                + (ccAddresses.isEmpty() ? '.' : ' with a copy to ' + String.join(ccAddresses, ', ') + '.');
            return result;
        } catch (Exception ex) {
            return failure('The End of Day Report was not sent. ' + ex.getMessage());
        }
    }

    /**
     * @description Result for a report that was not sent.
     * @param message Reason shown to the technician
     * @return Failed result
     */
    private static Result failure(String message) {
        Result result = new Result();
        result.sentCount = 0;
        result.message = message;
        return result;
    }
}