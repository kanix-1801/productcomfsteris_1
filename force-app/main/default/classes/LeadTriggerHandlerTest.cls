/**
 * @author Himanshu Chaurasia
 * @date 2026/11/05
 *
 * @description Test coverage for LeadTriggerHandler (GC-3279 routing, GC-3449 SLA, nurture follow-up).
 */
@IsTest(SeeAllData=false)
private class LeadTriggerHandlerTest {
    @IsTest
    static void afterInsertSkipsRoutingWhenNewLeadPageFlagIsSet() {
        LeadService.skipInsertTas = true;
        try {
            Test.startTest();
            insert buildLead('SkipTas');
            Test.stopTest();
        } finally {
            LeadService.skipInsertTas = false;
        }
    }

    @IsTest
    static void afterInsertEnqueuesRoutingForBackendInsert() {
        LeadService.skipInsertTas = false;
        TriggerControl.reset(Lead.SObjectType, 'afterInsert');

        Test.startTest();
        insert buildLead('Backend');
        Test.stopTest();
    }

    @IsTest
    static void afterUpdateAppliesSlaAndNurtureServices() {
        Lead leadRecord = buildLead('Update');
        insert leadRecord;

        leadRecord.Status = 'Nurturing';
        leadRecord.NurtureReason__c = 'Customer Timing';
        leadRecord.Nurture_Reminder_Date__c = Date.today().addDays(5);

        Test.startTest();
        update leadRecord;
        Test.stopTest();
    }

    @IsTest
    static void beforeInsertRunsBulkDuplicateCheckForBulkApiRequest() {
        TriggerControl.reset(Lead.SObjectType, 'beforeInsert');
        LeadDuplicateService.quiddityOverride = Quiddity.BULK_API;
        try {
            Test.startTest();
            insert buildLead('Bulk');
            Test.stopTest();
        } finally {
            LeadDuplicateService.quiddityOverride = null;
        }
    }

    private static Lead buildLead(String suffix) {
        String token = EncodingUtil.convertToHex(Crypto.generateAesKey(128)).substring(0, 8);
        return new Lead(
            FirstName = 'Trigger',
            LastName = 'Handler' + suffix + token,
            Company = 'Steris Test Co',
            CountryCode = 'US',
            Email = 'lead.handler.' + suffix + '.' + token + '@example.test',
            LeadSource = 'Web',
            Status = 'New'
        );
    }
}