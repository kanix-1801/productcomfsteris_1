/**
 * @author Uptima Development Team
 * @date 2026-10-26
 * @description GW-6191 - Sends the On Location End of Day Report to the selected Contact, with the
 *              current user and their manager in CC. Called from ServiceAppointment_Updated_AfterSave
 *              when the IMS completion mobile flow requests the report, before the completed child Work Orders
 *              are closed, so the report still finds them.
 *              GW-6257 - CRSS site visits use the CRSS template with the inspected asset tables.
 * @group Service Appointment
 * @see OnLocationEndOfDayReportController
 * @see OnLocationCrssEndOfDayReportController
 */
public without sharing class OnLocationEndOfDayReportAction {
    /** @description Developer name of the IMS Visualforce email template. */
    public static final String TEMPLATE_DEVELOPER_NAME = 'OnLocationEndOfDayReport';
    /** @description GW-6257 - Developer name of the CRSS Visualforce email template. */
    public static final String CRSS_TEMPLATE_DEVELOPER_NAME = 'OnLocationCrssEndOfDayReport';
    /** @description GW-6257 - Site visit Work Order record type that uses the CRSS template. */
    public static final String CRSS_RECORD_TYPE_DEVELOPER_NAME = 'CRSSFieldRepair';

    /**
     * @description Flow input.
     */
    public class Request {
        /** @description Site visit Work Order the report is about. */
        @InvocableVariable(label='Site Visit Work Order Id' required=true)
        public Id siteVisitWorkOrderId;

        /** @description Contact the technician picked to receive the report. */
        @InvocableVariable(label='Contact Id' required=true)
        public Id contactId;

        /** @description Email the technician approved or typed; the Contact email is used when blank. */
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
        Map<String, Id> templateIdByName = new Map<String, Id>();
        for (EmailTemplate template : [
            SELECT Id, DeveloperName
            FROM EmailTemplate
            WHERE DeveloperName IN (:TEMPLATE_DEVELOPER_NAME, :CRSS_TEMPLATE_DEVELOPER_NAME)
        ]) {
            templateIdByName.put(template.DeveloperName, template.Id);
        }
        Set<Id> siteVisitIds = new Set<Id>();
        for (Request request : requests) {
            if (request?.siteVisitWorkOrderId != null) {
                siteVisitIds.add(request.siteVisitWorkOrderId);
            }
        }
        Map<Id, WorkOrder> siteVisitById = new Map<Id, WorkOrder>([
            SELECT Id, RecordType.DeveloperName
            FROM WorkOrder
            WHERE Id IN :siteVisitIds
        ]);

        List<Result> results = new List<Result>();
        for (Request request : requests) {
            WorkOrder siteVisit = request == null ? null : siteVisitById.get(request.siteVisitWorkOrderId);
            String templateName = siteVisit?.RecordType?.DeveloperName == CRSS_RECORD_TYPE_DEVELOPER_NAME
                ? CRSS_TEMPLATE_DEVELOPER_NAME
                : TEMPLATE_DEVELOPER_NAME;
            Id templateId = templateIdByName.get(templateName);
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
     * @description Renders the report for the selected Contact and sends it to the approved email with the
     *              user and manager in CC. The Contact record is not updated.
     * @param templateId End of Day Report template
     * @param request Site visit, selected Contact, and approved email
     * @return Send result
     */
    private static Result sendForSiteVisit(Id templateId, Request request) {
        if (request?.siteVisitWorkOrderId == null) {
            return failure('The site visit work order could not be identified.');
        }
        List<Contact> contacts = [
            SELECT Id, Name, Email
            FROM Contact
            WHERE Id = :request.contactId
            LIMIT 1
        ];
        if (contacts.isEmpty()) {
            return failure('The selected contact could not be found. The End of Day Report was not sent.');
        }
        String recipientEmail = String.isNotBlank(request.recipientEmail)
            ? request.recipientEmail.trim()
            : contacts[0].Email;
        if (String.isBlank(recipientEmail)) {
            return failure('The selected contact has no email. The End of Day Report was not sent.');
        }

        try {
            Messaging.SingleEmailMessage rendered = Messaging.renderStoredEmailTemplate(
                templateId,
                contacts[0].Id,
                request.siteVisitWorkOrderId
            );
            List<String> ccAddresses = selectCcAddresses();
            Messaging.SingleEmailMessage message = new Messaging.SingleEmailMessage();
            message.setToAddresses(new List<String>{ recipientEmail });
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
            result.sentCount = 1 + ccAddresses.size();
            result.message = 'The End of Day Report was sent to ' + contacts[0].Name + ' (' + recipientEmail + ')'
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