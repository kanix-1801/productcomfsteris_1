/**
 * @description Tests for routing more than one Lead, and for a Lead that cannot be routed.
 * @author      Vinay
 * @date        2026-10-23
 */
@IsTest(SeeAllData=false)
private class LeadRoutingQueueableTest {

    /**
     * @description An empty job does not route and does not chain another job.
     */
    @IsTest
    static void emptyListDoesNotRoute() {
        new LeadRoutingQueueable(new List<Id>()).execute(null);

        Assert.areEqual(0, Limits.getQueueableJobs());
    }

    /**
     * @description A Lead that cannot be routed is logged, and the next Lead is chained.
     */
    @IsTest
    static void failedLeadIsLoggedAndTheNextLeadIsChained() {
        List<Id> leadIds = new List<Id>{ fakeLeadId(1), null, fakeLeadId(2) };

        Test.startTest();
        new LeadRoutingQueueable(leadIds).execute(null);
        Assert.areEqual(1, Limits.getQueueableJobs());
        Test.stopTest();

        Assert.areEqual(0, [SELECT COUNT() FROM Lead]);
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