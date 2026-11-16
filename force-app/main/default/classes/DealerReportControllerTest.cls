/**
 * @author PWC Developer
 * @date 2026/11/13
 *
 * @group Dealer Portal
 *
 * @description
 * Dealer Portal - Tests for running a report from the Reports page.
 */
// Reports.ReportManager.runReport requires access to existing report records.
@IsTest(SeeAllData=true)
private class DealerReportControllerTest {

    @IsTest
    static void getReportReturnsNameColumnsAndRows() {
        List<Report> reports = [SELECT Id, Name FROM Report WHERE DeveloperName = 'Dealer_Opportunity_Pipeline' LIMIT 1];
        Assert.isFalse(reports.isEmpty(), 'The Dealer Opportunity Pipeline report must exist.');

        Test.startTest();
        DealerReportController.ReportData data = DealerReportController.getReport(reports[0].Id);
        Test.stopTest();

        Assert.areEqual(reports[0].Name, data.name, 'The report name should be returned.');
        Assert.isFalse(data.columns.isEmpty(), 'Detail column labels should be returned.');
        Assert.isFalse(data.rows.isEmpty(), 'Detail rows should be returned.');
    }

    @IsTest
    static void getReportThrowsForInvalidReport() {
        try {
            DealerReportController.getReport('00O000000000000AAA');
            Assert.fail('An invalid report should throw.');
        } catch (AuraHandledException exceptionValue) {
            Assert.isTrue(
                exceptionValue.getMessage().contains('Unable to load the report'),
                'A friendly message should be returned.'
            );
        }
    }

    @IsTest
    static void getReportThrowsWhenReportIdIsMissing() {
        try {
            DealerReportController.getReport(null);
            Assert.fail('A missing Report Id should throw.');
        } catch (AuraHandledException exceptionValue) {
            Assert.areEqual('Enter a Report Id.', exceptionValue.getMessage(), 'The validation message should be returned.');
        }
    }
}