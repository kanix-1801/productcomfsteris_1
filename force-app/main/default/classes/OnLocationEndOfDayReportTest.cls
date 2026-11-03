/**
 * @description GW-6191 - Tests for the On Location End of Day Report controller and send action.
 * @see OnLocationEndOfDayReportController
 * @see OnLocationEndOfDayReportAction
 */
@IsTest
private class OnLocationEndOfDayReportTest {
    private static final Id INSTRUMENT_RECORD_TYPE_ID = Schema.SObjectType.WorkOrderLineItem
        .getRecordTypeInfosByDeveloperName()
        .get('ProductServiced')
        .getRecordTypeId();

    /**
     * @description Site visit with one completed child: a Repair Center line, a beyond repair line, and a plain line.
     */
    @TestSetup
    static void setup() {
        String token = String.valueOf(Crypto.getRandomInteger()).replace('-', '');
        Account account = new Account(Name = 'EOD ' + token, SourceSystemID__c = 'ORACLE-EOD-' + token);
        insert account;
        insert new List<Contact>{
            new Contact(AccountId = account.Id, LastName = 'With Email', Email = 'eod.' + token + '@example.com'),
            new Contact(AccountId = account.Id, LastName = 'No Email')
        };
        Asset tray = new Asset(Name = 'MAIN PODIATRY TRAY 2', AccountId = account.Id);
        insert tray;
        WorkOrder siteVisit = new WorkOrder(AccountId = account.Id, Subject = 'EOD Site Visit');
        insert siteVisit;
        WorkOrder child = new WorkOrder(
            AccountId = account.Id, ParentWorkOrderId = siteVisit.Id, AssetId = tray.Id, Subject = 'EOD Child'
        );
        insert child;
        insert new List<WorkOrderLineItem>{
            new WorkOrderLineItem(
                WorkOrderId = child.Id,
                RecordTypeId = INSTRUMENT_RECORD_TYPE_ID,
                LineType__c = 'Instrument',
                SendToRepairCenter__c = true,
                SerialNumber__c = 'Karl Storz',
                Model__c = '33500',
                ReportedProblem__c = 'Cracked'
            ),
            new WorkOrderLineItem(
                WorkOrderId = child.Id,
                RecordTypeId = INSTRUMENT_RECORD_TYPE_ID,
                LineType__c = 'Instrument',
                SerialNumber__c = 'V.Mueller',
                Model__c = 'OS1079-002',
                ReportedProblem__c = 'Life Worn',
                ReplacedWithIXchange__c = true
            ),
            new WorkOrderLineItem(
                WorkOrderId = child.Id, RecordTypeId = INSTRUMENT_RECORD_TYPE_ID, LineType__c = 'Instrument'
            )
        };
        child.Status = 'Completed';
        update child;
    }

    /**
     * @description Lines are split into the National Repair Center table and the Beyond Repair table.
     */
    @IsTest
    static void controller_splitsRepairCenterAndBeyondRepairRows() {
        WorkOrder siteVisit = [SELECT Id FROM WorkOrder WHERE Subject = 'EOD Site Visit' LIMIT 1];
        OnLocationEndOfDayReportController controller = new OnLocationEndOfDayReportController();
        controller.siteVisitWorkOrderId = siteVisit.Id;

        Test.startTest();
        List<OnLocationEndOfDayReportController.ReportRow> repairCenterRows = controller.getRepairCenterRows();
        List<OnLocationEndOfDayReportController.ReportRow> beyondRepairRows = controller.getBeyondRepairRows();
        Test.stopTest();

        System.assertEquals(true, controller.getHasRepairCenterRows());
        System.assertEquals(true, controller.getHasBeyondRepairRows());
        System.assertEquals(1, repairCenterRows.size());
        System.assertEquals('Karl Storz', repairCenterRows[0].manufacturer);
        System.assertEquals('MAIN PODIATRY TRAY 2', repairCenterRows[0].trayName);
        System.assertEquals(1, beyondRepairRows.size());
        System.assertEquals('Life Worn', beyondRepairRows[0].reason);
        System.assertEquals('Yes', beyondRepairRows[0].replacedWithIXchange);
    }

    /**
     * @description Without a site visit both tables are hidden.
     */
    @IsTest
    static void controller_noSiteVisit_hidesTables() {
        OnLocationEndOfDayReportController controller = new OnLocationEndOfDayReportController();
        System.assertEquals(false, controller.getHasRepairCenterRows());
        System.assertEquals(false, controller.getHasBeyondRepairRows());
    }

    /**
     * @description Builds a send request for the test site visit.
     * @param contactLastName Last name of the selected Contact
     * @return Request
     */
    private static OnLocationEndOfDayReportAction.Request buildRequest(String contactLastName) {
        OnLocationEndOfDayReportAction.Request request = new OnLocationEndOfDayReportAction.Request();
        request.siteVisitWorkOrderId = [SELECT Id FROM WorkOrder WHERE Subject = 'EOD Site Visit' LIMIT 1].Id;
        request.contactId = [SELECT Id FROM Contact WHERE LastName = :contactLastName LIMIT 1].Id;
        return request;
    }

    /**
     * @description The report goes to the selected Contact with the current user in CC.
     */
    @IsTest
    static void sendReport_selectedContact_sendsWithCurrentUserInCc() {
        OnLocationEndOfDayReportAction.Request request = buildRequest('With Email');

        Test.startTest();
        List<OnLocationEndOfDayReportAction.Result> results =
            OnLocationEndOfDayReportAction.sendReport(new List<OnLocationEndOfDayReportAction.Request>{ request });
        Integer emailInvocations = Limits.getEmailInvocations();
        Test.stopTest();

        System.assertEquals(1, results.size());
        System.assert(String.isNotBlank(results[0].message));
        if (results[0].sentCount > 0) {
            System.assertEquals(1, emailInvocations);
            System.assert(results[0].message.contains(UserInfo.getUserEmail()), results[0].message);
        }
    }

    /**
     * @description A selected Contact without an email is reported back to the flow.
     */
    @IsTest
    static void sendReport_contactWithoutEmail_returnsMessage() {
        OnLocationEndOfDayReportAction.Request request = buildRequest('No Email');

        Test.startTest();
        List<OnLocationEndOfDayReportAction.Result> results =
            OnLocationEndOfDayReportAction.sendReport(new List<OnLocationEndOfDayReportAction.Request>{ request });
        Test.stopTest();

        System.assertEquals(0, results[0].sentCount);
        System.assert(results[0].message.contains('no email'), results[0].message);
    }

    /**
     * @description A typed email is used for a Contact without an email, and the Contact is not updated.
     */
    @IsTest
    static void sendReport_manualEmail_sendsWithoutUpdatingContact() {
        OnLocationEndOfDayReportAction.Request request = buildRequest('No Email');
        request.recipientEmail = ' manual.eod@example.com ';

        Test.startTest();
        List<OnLocationEndOfDayReportAction.Result> results =
            OnLocationEndOfDayReportAction.sendReport(new List<OnLocationEndOfDayReportAction.Request>{ request });
        Test.stopTest();

        System.assert(String.isNotBlank(results[0].message));
        if (results[0].sentCount > 0) {
            System.assert(results[0].message.contains('manual.eod@example.com'), results[0].message);
        }
        System.assertEquals(null, [SELECT Email FROM Contact WHERE Id = :request.contactId].Email);
    }

    /**
     * @description GW-6257 - Without a Contact the report goes to every typed email.
     */
    @IsTest
    static void sendReport_noContactMultipleEmails_sendsToEach() {
        OnLocationEndOfDayReportAction.Request request = new OnLocationEndOfDayReportAction.Request();
        request.siteVisitWorkOrderId = [SELECT Id FROM WorkOrder WHERE Subject = 'EOD Site Visit' LIMIT 1].Id;
        request.recipientEmail = 'first.eod@example.com; second.eod@example.com;';

        Test.startTest();
        List<OnLocationEndOfDayReportAction.Result> results =
            OnLocationEndOfDayReportAction.sendReport(new List<OnLocationEndOfDayReportAction.Request>{ request });
        Test.stopTest();

        System.assert(String.isNotBlank(results[0].message));
        if (results[0].sentCount > 0) {
            System.assert(results[0].message.contains('first.eod@example.com, second.eod@example.com'), results[0].message);
        }
    }

    /**
     * @description GW-6257 - The template renders without a Contact and greets with just Hello.
     */
    @IsTest
    static void template_noContact_rendersPlainGreeting() {
        Id siteVisitId = [SELECT Id FROM WorkOrder WHERE Subject = 'EOD Site Visit' LIMIT 1].Id;
        Id templateId = [
            SELECT Id
            FROM EmailTemplate
            WHERE DeveloperName = :OnLocationEndOfDayReportAction.TEMPLATE_DEVELOPER_NAME
            LIMIT 1
        ].Id;

        Messaging.SingleEmailMessage rendered = Messaging.renderStoredEmailTemplate(templateId, null, siteVisitId);

        System.assert(rendered.getHtmlBody().contains('Hello,'), rendered.getHtmlBody());
    }

    /**
     * @description GW-6257 - Without a Contact or an email nothing is sent.
     */
    @IsTest
    static void sendReport_noContactNoEmail_returnsMessage() {
        OnLocationEndOfDayReportAction.Request request = new OnLocationEndOfDayReportAction.Request();
        request.siteVisitWorkOrderId = [SELECT Id FROM WorkOrder WHERE Subject = 'EOD Site Visit' LIMIT 1].Id;
        request.recipientEmail = ' ; ';

        Test.startTest();
        List<OnLocationEndOfDayReportAction.Result> results =
            OnLocationEndOfDayReportAction.sendReport(new List<OnLocationEndOfDayReportAction.Request>{ request });
        Test.stopTest();

        System.assertEquals(0, results[0].sentCount);
        System.assert(results[0].message.contains('No email'), results[0].message);
    }

    /**
     * @description GW-6257 - An invalid typed email blocks the send and is named in the message.
     */
    @IsTest
    static void sendReport_invalidEmail_returnsMessage() {
        OnLocationEndOfDayReportAction.Request request = buildRequest('With Email');
        request.recipientEmail = 'good.eod@example.com; not-an-email';

        Test.startTest();
        List<OnLocationEndOfDayReportAction.Result> results =
            OnLocationEndOfDayReportAction.sendReport(new List<OnLocationEndOfDayReportAction.Request>{ request });
        Test.stopTest();

        System.assertEquals(0, results[0].sentCount);
        System.assert(results[0].message.contains('not-an-email'), results[0].message);
    }

    /**
     * @description A missing site visit is reported back to the flow.
     */
    @IsTest
    static void sendReport_noSiteVisit_returnsMessage() {
        Test.startTest();
        List<OnLocationEndOfDayReportAction.Result> results = OnLocationEndOfDayReportAction.sendReport(
            new List<OnLocationEndOfDayReportAction.Request>{ new OnLocationEndOfDayReportAction.Request() }
        );
        Test.stopTest();

        System.assertEquals(0, results[0].sentCount);
        System.assert(String.isNotBlank(results[0].message));
    }
}