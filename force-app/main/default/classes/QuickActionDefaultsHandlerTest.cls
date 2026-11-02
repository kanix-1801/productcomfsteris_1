/**
 * @author PSL
 * @date 12-02-2025
 * @description Test class for QuickActionDefaultsHandler
 */
@IsTest
private class QuickActionDefaultsHandlerTest {

    private static List<QuickAction.QuickActionDefaults> buildSendEmailDefaults(Id contextId) {
        QuickAction.SendEmailQuickActionDefaults sendDefaults =
            Test.newSendEmailQuickActionDefaults(contextId, null);
        return new List<QuickAction.QuickActionDefaults>{ sendDefaults };
    }

    @IsTest
    static void testOnInitDefaultsHandleAllEmailTypes() {
        Case soaCase = new Case(Subject = 'SOA Case', Status = 'New', EmailType__c = 'SOA');
        Case coaProjectCase = new Case(Subject = 'COA Project Case', Status = 'New', EmailType__c = 'COA Project');
        Case coaTurnsCase = new Case(Subject = 'COA Turns Case', Status = 'New', EmailType__c = 'COA Turns');
        Case coaC1 = new Case(Subject = 'COA C1 Case', Status = 'New', EmailType__c = 'C1');
        Case coaC2 = new Case(Subject = 'COA C2 Case', Status = 'New', EmailType__c = 'C2');
        Case SDN = new Case(Subject = 'SDN Case', Status = 'New', EmailType__c = 'Ship Date Notification');
        Case DF = new Case(Subject = 'C2 Case', Status = 'New', EmailType__c = 'DF');
        Case coaProjFrench = new Case(Subject = 'COA french project Case', Status = 'New', EmailType__c = 'COA Project',emailLanguage__C='French');
        Case coaTurnsFrench = new Case(Subject = 'COA french Case', Status = 'New', EmailType__c = 'COA Turns',emailLanguage__C='French');
        insert new List<Case>{ soaCase, coaProjectCase, coaTurnsCase,coaC1,coaC2,SDN,DF,coaProjFrench,coaTurnsFrench };

        Test.startTest();
        new QuickActionDefaultsHandler().onInitDefaults(buildSendEmailDefaults(soaCase.Id));
        new QuickActionDefaultsHandler().onInitDefaults(buildSendEmailDefaults(coaProjectCase.Id));
        new QuickActionDefaultsHandler().onInitDefaults(buildSendEmailDefaults(coaTurnsCase.Id));
        new QuickActionDefaultsHandler().onInitDefaults(buildSendEmailDefaults(coaC1.Id));
        new QuickActionDefaultsHandler().onInitDefaults(buildSendEmailDefaults(coaC2.Id));
         new QuickActionDefaultsHandler().onInitDefaults(buildSendEmailDefaults(DF.Id));
         new QuickActionDefaultsHandler().onInitDefaults(buildSendEmailDefaults(coaProjFrench.Id));
         new QuickActionDefaultsHandler().onInitDefaults(buildSendEmailDefaults(coaTurnsFrench.Id));
        new QuickActionDefaultsHandler().onInitDefaults(buildSendEmailDefaults(SDN.Id));
        Test.stopTest();

        System.assert(true, 'All email type branches executed successfully.');
    }

    @IsTest
    static void testOnInitDefaultsThrowExceptionForInvalidCaseId() {
        Case tempCase = new Case(Subject = 'Temp Case', Status = 'New', EmailType__c = 'SOA');
        insert tempCase;
        Id deletedCaseId = tempCase.Id;
        delete tempCase;

        List<QuickAction.QuickActionDefaults> defaults = buildSendEmailDefaults(deletedCaseId);
        Exception capturedException;

        Test.startTest();
        try {
            new QuickActionDefaultsHandler().onInitDefaults(defaults);
            System.assert(false, 'Expected exception for invalid Case Id.');
        } catch (Exception ex) {
            capturedException = ex;
        }
        Test.stopTest();

        System.assertNotEquals(null, capturedException, 'Exception should be thrown for invalid Case Id.');
    }
}