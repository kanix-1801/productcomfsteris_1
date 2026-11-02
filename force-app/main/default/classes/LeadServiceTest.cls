/**
 * @description Tests for the Lead TAS eligibility check.
 *              Leads are not inserted. The queued TAS job is not run.
 * @author      Vinay
 * @date        2026-10-23
 */
@IsTest(SeeAllData=false)
private class LeadServiceTest {

    /**
     * @description A null or empty list does not queue TAS.
     */
    @IsTest
    static void emptyListDoesNotQueueTas() {
        LeadService.skipInsertTas = false;

        LeadService.assignTAStoLead(null);
        LeadService.assignTAStoLead(new List<Lead>());

        Assert.areEqual(0, Limits.getQueueableJobs());
    }

    /**
     * @description A Lead missing the TAS fields is not queued.
     */
    @IsTest
    static void incompleteLeadDoesNotQueueTas() {
        LeadService.skipInsertTas = false;
        Lead leadRecord = new Lead(
            Id = fakeLeadId(1),
            LastName = 'Incomplete',
            Country = 'United States'
        );

        LeadService.assignTAStoLead(new List<Lead>{ leadRecord });

        Assert.areEqual(0, Limits.getQueueableJobs());
    }

    /**
     * @description One complete Lead is handed to the TAS job.
     */
    @IsTest
    static void oneCompleteLeadQueuesTas() {
        LeadService.skipInsertTas = false;

        LeadService.assignTAStoLead(new List<Lead>{ completeLead(1) });

        Assert.areEqual(1, Limits.getQueueableJobs());
    }

    /**
     * @description More than one complete Lead is not handed to TAS.
     */
    @IsTest
    static void severalCompleteLeadsDoNotQueueTas() {
        LeadService.skipInsertTas = false;

        LeadService.assignTAStoLead(new List<Lead>{ completeLead(1), completeLead(2) });

        Assert.areEqual(0, Limits.getQueueableJobs());
    }

    /**
     * @description Builds a Lead that has every field the TAS check requires.
     * @param seed Value used to keep the Lead Id unique.
     * @return Unsaved Lead.
     */
    private static Lead completeLead(Integer seed) {
        return new Lead(
            Id = fakeLeadId(seed),
            PostalCode = '44101',
            Country = 'United States',
            Org_ID__c = '100',
            Class_Code__c = 'Healthcare',
            Sales_Category__c = 'Capital'
        );
    }

    /**
     * @description A Lead Id that is not inserted.
     * @param seed Value used to keep the Id unique.
     * @return Lead Id.
     */
    private static Id fakeLeadId(Integer seed) {
        return (Id) (
            Lead.SObjectType.getDescribe().getKeyPrefix()
            + String.valueOf(seed).leftPad(12, '0')
        );
    }
}