@IsTest
private class ProjectOpportunityReviewServiceTest {
    @IsTest
    static void clearsFlagWhenDecisionIsSavedAsNotAProject() {
        Opportunity opportunity = new Opportunity(
            ProjectOpportunity__c = true,
            PDMReviewDecision__c = 'Not a Project Opportunity'
        );

        ProjectOpportunityReviewService.applyBeforeSave(new List<Opportunity>{ opportunity }, null);

        System.assertEquals(false, opportunity.ProjectOpportunity__c);
    }

    @IsTest
    static void leavesFlagForMonitorDecisionAndClearsNotAProjectDetails() {
        Opportunity opportunity = new Opportunity(
            ProjectOpportunity__c = true,
            PDMReviewDecision__c = 'Potential Project – Monitor',
            NoProjectReason__c = 'Standalone Commercial Opportunity',
            NoProjectComments__c = 'Reviewed earlier'
        );

        ProjectOpportunityReviewService.applyBeforeSave(new List<Opportunity>{ opportunity }, null);

        System.assertEquals(true, opportunity.ProjectOpportunity__c);
        System.assertEquals(null, opportunity.NoProjectReason__c);
        System.assertEquals(null, opportunity.NoProjectComments__c);
    }

    @IsTest
    static void clearsCommentsWhenReasonIsNotOther() {
        Opportunity opportunity = new Opportunity(
            ProjectOpportunity__c = true,
            PDMReviewDecision__c = 'Not a Project Opportunity',
            NoProjectReason__c = 'Standalone Commercial Opportunity',
            NoProjectComments__c = 'Not needed'
        );

        ProjectOpportunityReviewService.applyBeforeSave(new List<Opportunity>{ opportunity }, null);

        System.assertEquals('Standalone Commercial Opportunity', opportunity.NoProjectReason__c);
        System.assertEquals(null, opportunity.NoProjectComments__c);
    }

    @IsTest
    static void keepsCommentsWhenReasonIsOther() {
        Opportunity opportunity = new Opportunity(
            Id = '006000000000002AAA',
            ProjectOpportunity__c = false,
            PDMReviewDecision__c = 'Not a Project Opportunity',
            NoProjectReason__c = 'Other',
            NoProjectComments__c = 'Duplicate of an existing sale'
        );
        Opportunity prior = new Opportunity(
            Id = opportunity.Id,
            PDMReviewDecision__c = 'Not a Project Opportunity'
        );

        ProjectOpportunityReviewService.applyBeforeSave(
            new List<Opportunity>{ opportunity },
            new Map<Id, Opportunity>{ opportunity.Id => prior }
        );

        System.assertEquals('Other', opportunity.NoProjectReason__c);
        System.assertEquals('Duplicate of an existing sale', opportunity.NoProjectComments__c);
        System.assertEquals(false, opportunity.ProjectOpportunity__c);
    }

    @IsTest
    static void leavesFlagOnLaterSaveAfterDecisionWasAlreadyRecorded() {
        Opportunity current = new Opportunity(
            Id = '006000000000001AAA',
            ProjectOpportunity__c = true,
            PDMReviewDecision__c = 'Not a Project Opportunity'
        );
        Opportunity prior = new Opportunity(
            Id = current.Id,
            ProjectOpportunity__c = false,
            PDMReviewDecision__c = 'Not a Project Opportunity'
        );

        ProjectOpportunityReviewService.applyBeforeSave(
            new List<Opportunity>{ current },
            new Map<Id, Opportunity>{ current.Id => prior }
        );

        System.assertEquals(true, current.ProjectOpportunity__c);
    }

    @IsTest
    static void skipsWhenThereAreNoOpportunities() {
        ProjectOpportunityReviewService.applyBeforeSave(null, null);
        ProjectOpportunityReviewService.applyBeforeSave(new List<Opportunity>(), null);

        System.assertEquals(0, Limits.getDmlStatements());
    }

    @IsTest
    static void logsAndRethrowsWhenReviewCannotBeApplied() {
        Exception thrownException;

        try {
            ProjectOpportunityReviewService.applyBeforeSave(new List<Opportunity>{ null }, null);
        } catch (Exception exceptionValue) {
            thrownException = exceptionValue;
        }

        System.assertNotEquals(null, thrownException);
    }
}