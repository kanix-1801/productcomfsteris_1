/**
 * @description GW-6257 - Tests for the CRSS On Location End of Day Report controller and template choice.
 * @see OnLocationCrssEndOfDayReportController
 * @see OnLocationEndOfDayReportAction
 */
@IsTest
private class OnLocationCrssEndOfDayReportTest {
    private static final Id PRODUCT_SERVICED_RECORD_TYPE_ID = Schema.SObjectType.WorkOrderLineItem
        .getRecordTypeInfosByDeveloperName()
        .get('ProductServiced')
        .getRecordTypeId();

    /**
     * @description CRSS site visit with Passed, Recommended for Repair, Do Not Use(P0), and no outcome lines.
     */
    @TestSetup
    static void setup() {
        String token = String.valueOf(Crypto.getRandomInteger()).replace('-', '');
        Account account = new Account(Name = 'CRSS EOD ' + token, SourceSystemID__c = 'ORACLE-CRSS-EOD-' + token);
        insert account;
        insert new Contact(AccountId = account.Id, LastName = 'CRSS Contact', Email = 'crss.' + token + '@example.com');
        List<Asset> assets = new List<Asset>{
            new Asset(Name = 'SCOPE PASSED', AccountId = account.Id, SerialNumber = 'SN-PASSED-' + token),
            new Asset(Name = 'SCOPE DNU', AccountId = account.Id, SerialNumber = 'SN-DNU-' + token),
            new Asset(Name = 'SCOPE DNU P0', AccountId = account.Id, SerialNumber = 'SN-P0-' + token),
            new Asset(Name = 'SCOPE NOT INSPECTED', AccountId = account.Id)
        };
        insert assets;
        WorkOrder siteVisit = new WorkOrder(
            AccountId = account.Id,
            Subject = 'CRSS EOD Site Visit',
            RecordTypeId = Schema.SObjectType.WorkOrder
                .getRecordTypeInfosByDeveloperName()
                .get(OnLocationEndOfDayReportAction.CRSS_RECORD_TYPE_DEVELOPER_NAME)
                .getRecordTypeId()
        );
        insert siteVisit;
        insert new List<WorkOrderLineItem>{
            buildLine(siteVisit.Id, assets[0].Id, 'Passed', null),
            buildLine(siteVisit.Id, assets[1].Id, 'Recommended for Repair', 'Cracked lens'),
            buildLine(siteVisit.Id, assets[2].Id, OnLocationCrssEndOfDayReportController.OUTCOME_DO_NOT_USE_P0, 'Fluid invasion'),
            buildLine(siteVisit.Id, assets[3].Id, null, null)
        };
    }

    private static WorkOrderLineItem buildLine(Id workOrderId, Id assetId, String outcome, String problem) {
        return new WorkOrderLineItem(
            WorkOrderId = workOrderId,
            RecordTypeId = PRODUCT_SERVICED_RECORD_TYPE_ID,
            LineType__c = 'Product Serviced',
            AssetId = assetId,
            InspectionOutcome__c = outcome,
            ReportedProblem__c = problem
        );
    }

    private static Id siteVisitId() {
        return [SELECT Id FROM WorkOrder WHERE Subject = 'CRSS EOD Site Visit' LIMIT 1].Id;
    }

    /**
     * @description Do Not Use(P0) lines only show in the Do Not Use table, every other outcome shows
     *              in the Inspected table, and lines without an outcome are left out.
     */
    @IsTest
    static void controller_splitsInspectedAndDoNotUseRows() {
        OnLocationCrssEndOfDayReportController controller = new OnLocationCrssEndOfDayReportController();
        controller.siteVisitWorkOrderId = siteVisitId();

        Test.startTest();
        List<OnLocationCrssEndOfDayReportController.ReportRow> inspectedRows = controller.getInspectedRows();
        List<OnLocationCrssEndOfDayReportController.ReportRow> doNotUseRows = controller.getDoNotUseRows();
        Test.stopTest();

        Set<String> inspectedAssets = new Set<String>();
        for (OnLocationCrssEndOfDayReportController.ReportRow row : inspectedRows) {
            inspectedAssets.add(row.assetName);
            System.assert(row.serialNumber.startsWith('SN-'), row.serialNumber);
        }
        System.assertEquals(new Set<String>{ 'SCOPE PASSED', 'SCOPE DNU' }, inspectedAssets);
        System.assertEquals(1, doNotUseRows.size());
        System.assertEquals('SCOPE DNU P0', doNotUseRows[0].assetName);
        System.assert(doNotUseRows[0].serialNumber.startsWith('SN-P0-'), doNotUseRows[0].serialNumber);
        System.assertEquals('Fluid invasion', doNotUseRows[0].reportedProblem);
        System.assertEquals(true, controller.getHasInspectedRows());
        System.assertEquals(true, controller.getHasDoNotUseRows());
    }

    /**
     * @description Without a site visit both tables are hidden.
     */
    @IsTest
    static void controller_noSiteVisit_hidesTables() {
        OnLocationCrssEndOfDayReportController controller = new OnLocationCrssEndOfDayReportController();
        System.assertEquals(false, controller.getHasInspectedRows());
        System.assertEquals(false, controller.getHasDoNotUseRows());
    }

    /**
     * @description A CRSS site visit sends the CRSS template.
     */
    @IsTest
    static void sendReport_crssSiteVisit_usesCrssTemplate() {
        OnLocationEndOfDayReportAction.Request request = new OnLocationEndOfDayReportAction.Request();
        request.siteVisitWorkOrderId = siteVisitId();
        request.contactId = [SELECT Id FROM Contact WHERE LastName = 'CRSS Contact' LIMIT 1].Id;

        Test.startTest();
        List<OnLocationEndOfDayReportAction.Result> results =
            OnLocationEndOfDayReportAction.sendReport(new List<OnLocationEndOfDayReportAction.Request>{ request });
        Test.stopTest();

        System.assertEquals(1, results.size());
        System.assert(String.isNotBlank(results[0].message));
        System.assert(!results[0].message.contains('template is missing'), results[0].message);
    }
}