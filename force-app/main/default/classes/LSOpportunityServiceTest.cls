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

    /**
     * @description GCL-23 - A Life Sciences clone clears bypass and the Sales Connection quote link.
     *              Apex cannot create a real clone, so the test flag stands in for isClone.
     *              getCloneSourceId stays null until the standard Clone button runs.
     */
    @IsTest
    static void stampClonedFromStampsLifeSciencesClone() {
        Opportunity clonedOpportunity = buildOpportunity(lifeSciencesRecordTypeId());
        clonedOpportunity.BypassValidations__c = true;
        clonedOpportunity.QuoteLinkageToSalesConnection__c = QUOTE_LINK;
        LSOpportunityService.treatAsCloneForTest = true;

        Test.startTest();
        LSOpportunityService.stampClonedFrom(new List<Opportunity>{ clonedOpportunity, null });
        Test.stopTest();

        System.assertEquals(null, clonedOpportunity.ClonedFrom__c, 'Clone source Id is only available from the Clone button');
        System.assertEquals(false, clonedOpportunity.BypassValidations__c, 'Bypass must be cleared on a clone');
        System.assertEquals(null, clonedOpportunity.QuoteLinkageToSalesConnection__c, 'Quote link must be cleared on a clone');
    }

    /**
     * @description GCL-23 - A clone of another record type is not stamped.
     */
    @IsTest
    static void stampClonedFromSkipsOtherRecordTypes() {
        Opportunity otherOpportunity = buildOpportunity(otherRecordTypeId());
        otherOpportunity.BypassValidations__c = true;
        otherOpportunity.QuoteLinkageToSalesConnection__c = QUOTE_LINK;
        LSOpportunityService.treatAsCloneForTest = true;

        Test.startTest();
        LSOpportunityService.stampClonedFrom(new List<Opportunity>{ otherOpportunity });
        Test.stopTest();

        System.assertEquals(true, otherOpportunity.BypassValidations__c, 'Bypass must stay on a non Life Sciences clone');
        System.assertEquals(QUOTE_LINK, otherOpportunity.QuoteLinkageToSalesConnection__c, 'Quote link must stay on a non Life Sciences clone');
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

    private static Id otherRecordTypeId() {
        for (Schema.RecordTypeInfo info : Opportunity.SObjectType.getDescribe().getRecordTypeInfos()) {
            if (info.getDeveloperName() != 'LSEquipmentService'
                && info.getDeveloperName() != 'LSSalesConsumables'
                && info.getDeveloperName() != 'Master') {
                return info.getRecordTypeId();
            }
        }
        return null;
    }
}