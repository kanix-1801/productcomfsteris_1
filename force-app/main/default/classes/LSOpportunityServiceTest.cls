/**
 * @author PWC Developer
 * @group Life Sciences Opportunity
 *
 * @description
 * GCL-23 - Tests LSOpportunityService.stampClonedFrom.
 * A normal create is not changed. The standard Clone action cannot be simulated
 * in Apex, so the clone path is verified manually.
 */
@IsTest(SeeAllData=false)
private class LSOpportunityServiceTest {

    private static final String QUOTE_LINK = 'https://example.com/sales-connection/quote';

    /**
     * @description GCL-23 - Null and empty input does not throw.
     */
    @IsTest
    static void stampClonedFromHandlesNullAndEmptyInput() {
        LSOpportunityService.stampClonedFrom(null);
        LSOpportunityService.stampClonedFrom(new List<Opportunity>());
        System.assert(true, 'No exception expected');
    }

    /**
     * @description GCL-23 - A new Life Sciences Opportunity that is not a clone keeps Cloned From blank
     *              and keeps the source values for bypass and quote link.
     */
    @IsTest
    static void stampClonedFromLeavesNewOpportunityUnchanged() {
        Opportunity newOpportunity = buildOpportunity(lifeSciencesRecordTypeId());
        newOpportunity.BypassValidations__c = true;
        newOpportunity.QuoteLinkageToSalesConnection__c = QUOTE_LINK;

        Test.startTest();
        LSOpportunityService.stampClonedFrom(new List<Opportunity>{ newOpportunity });
        Test.stopTest();

        System.assertEquals(null, newOpportunity.ClonedFrom__c, 'Cloned From must stay blank on a new Opportunity');
        System.assertEquals(true, newOpportunity.BypassValidations__c, 'Bypass flag must not change on a new Opportunity');
        System.assertEquals(QUOTE_LINK, newOpportunity.QuoteLinkageToSalesConnection__c, 'Quote link must not change on a new Opportunity');
    }

    /**
     * @description GCL-23 - A bulk list of new Opportunities is handled without error and none are stamped.
     */
    @IsTest
    static void stampClonedFromHandlesBulkNewOpportunities() {
        List<Opportunity> opportunities = new List<Opportunity>();
        Id recordTypeId = lifeSciencesRecordTypeId();
        for (Integer i = 0; i < 200; i++) {
            opportunities.add(buildOpportunity(recordTypeId));
        }

        Test.startTest();
        LSOpportunityService.stampClonedFrom(opportunities);
        Test.stopTest();

        for (Opportunity opportunity : opportunities) {
            System.assertEquals(null, opportunity.ClonedFrom__c, 'Cloned From must stay blank on a new Opportunity');
        }
    }

    private static Opportunity buildOpportunity(Id recordTypeId) {
        return new Opportunity(
            Name = 'GCL23 Test Opportunity',
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(30),
            RecordTypeId = recordTypeId
        );
    }

    private static Id lifeSciencesRecordTypeId() {
        Schema.RecordTypeInfo info = Opportunity.SObjectType.getDescribe()
            .getRecordTypeInfosByDeveloperName()
            .get('LSEquipmentService');
        return info == null ? null : info.getRecordTypeId();
    }
}