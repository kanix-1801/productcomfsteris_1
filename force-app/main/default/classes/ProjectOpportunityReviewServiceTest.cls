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

    @IsTest
    static void appliesForecastAndCommercialGates() {
        Id projectTypeId = projectRecordTypeId();
        Id projectId = '006000000000010AAA';
        Opportunity prior = new Opportunity(Id = projectId, StageName = 'Discovery', Probability = 40);
        Map<Id, Opportunity> priorById = new Map<Id, Opportunity>{ projectId => prior };
        Opportunity deferred = new Opportunity(
            Id = projectId,
            RecordTypeId = projectTypeId,
            StageName = 'Deferred / On Hold',
            Probability = 10
        );

        ProjectOpportunityForecastService.applyBeforeSave(
            new List<Opportunity>{ deferred, new Opportunity(RecordTypeId = projectTypeId, StageName = 'Discovery') },
            priorById
        );
        ProjectOpportunityForecastService.applyBeforeSave(null, null);

        System.assertEquals('Omitted', deferred.ForecastCategoryName);
        System.assertEquals(null, deferred.ForecastConfidenceLevel__c);
        System.assertEquals(40, deferred.Probability);

        Opportunity bypassed = new Opportunity(
            Id = projectId,
            RecordTypeId = projectTypeId,
            StageName = 'Proposal',
            BypassValidations__c = true
        );
        ProjectOpportunityCommercialGateService.applyBeforeSave(new List<Opportunity>{ bypassed }, null);
        ProjectOpportunityCommercialGateService.applyBeforeSave(
            new List<Opportunity>{ new Opportunity() },
            null
        );
        ProjectOpportunityCommercialGateService.applyBeforeSave(null, null);

        for (String stageName : new List<String>{ 'Proposal', 'Commit', 'Closed Won', 'Closed Lost', 'Cancelled' }) {
            for (String priorStage : new List<String>{ 'Discovery', stageName }) {
                Opportunity project = new Opportunity(
                    Id = projectId,
                    RecordTypeId = projectTypeId,
                    StageName = stageName
                );
                ProjectOpportunityCommercialGateService.applyBeforeSave(
                    new List<Opportunity>{ project },
                    new Map<Id, Opportunity>{
                        projectId => new Opportunity(Id = projectId, StageName = priorStage)
                    }
                );
                if (stageName == 'Closed Won') {
                    System.assertEquals(100, project.Probability);
                }
                if (stageName == 'Closed Lost' || stageName == 'Cancelled') {
                    System.assertEquals(0, project.Probability);
                }
            }
        }

        assertRethrown(ProjectOpportunityForecastService.class);
        assertRethrown(ProjectOpportunityCommercialGateService.class);
    }

    @IsTest
    static void rollsUpLinkedCommercialAmounts() {
        insert new Automation_Setting_Validation_Rule__c(
            SetupOwnerId = UserInfo.getUserId(),
            disableAll__c = true
        );
        TriggerHandler.bypass('OpportunityTriggerHandller');
        Id projectTypeId = projectRecordTypeId();
        Opportunity project = new Opportunity(
            Name = 'HC Project',
            RecordTypeId = projectTypeId,
            StageName = 'Discovery',
            CloseDate = Date.today().addDays(30),
            BypassValidations__c = true
        );
        insert project;

        List<Opportunity> children = new List<Opportunity>();
        for (String stageName : new List<String>{ 'Closed Won', 'Closed Lost', 'Discovery', 'Cancelled' }) {
            children.add(new Opportunity(
                Name = stageName,
                RecordTypeId = projectTypeId,
                StageName = stageName,
                CloseDate = Date.today().addDays(20),
                Amount = stageName == 'Cancelled' ? null : 10,
                RelatedProjectOpportunity__c = project.Id,
                BypassValidations__c = true
            ));
        }
        insert children;

        ProjectOpportunityValueRollupService.applyAfterSave(null, null);
        ProjectOpportunityValueRollupService.applyAfterSave(
            new List<Opportunity>{ new Opportunity(RelatedProjectOpportunity__c = '006000000000099AAA') },
            null
        );
        ProjectOpportunityValueRollupService.applyAfterSave(
            new List<Opportunity>{
                project,
                new Opportunity(
                    Id = children[0].Id,
                    RelatedProjectOpportunity__c = project.Id,
                    StageName = 'Closed Won',
                    Amount = 10
                )
            },
            new Map<Id, Opportunity>{
                children[0].Id => new Opportunity(
                    Id = children[0].Id,
                    RelatedProjectOpportunity__c = '006000000000012AAA',
                    StageName = 'Proposal',
                    Amount = 1
                )
            }
        );

        project = [
            SELECT Amount, OpenValue__c, ClosedWonValue__c, ClosedLostValue__c, TotalAssociatedValue__c
            FROM Opportunity
            WHERE Id = :project.Id
        ];
        System.assertEquals(30, project.TotalAssociatedValue__c);
        System.assertEquals(10, project.OpenValue__c);
        System.assertEquals(10, project.ClosedWonValue__c);
        System.assertEquals(10, project.ClosedLostValue__c);
        System.assertEquals(30, project.Amount);

        Exception thrownException;
        try {
            ProjectOpportunityValueRollupService.applyAfterSave(new List<Opportunity>{ null }, null);
        } catch (Exception exceptionValue) {
            thrownException = exceptionValue;
        }
        System.assertNotEquals(null, thrownException);
        TriggerHandler.clearBypass('OpportunityTriggerHandller');
    }

    private static Id projectRecordTypeId() {
        return Schema.SObjectType.Opportunity.getRecordTypeInfosByDeveloperName()
            .get('HCProjectOpportunity')
            .getRecordTypeId();
    }

    private static void assertRethrown(Type serviceType) {
        Exception thrownException;
        try {
            if (serviceType == ProjectOpportunityForecastService.class) {
                ProjectOpportunityForecastService.applyBeforeSave(new List<Opportunity>{ null }, null);
            } else {
                ProjectOpportunityCommercialGateService.applyBeforeSave(new List<Opportunity>{ null }, null);
            }
        } catch (Exception exceptionValue) {
            thrownException = exceptionValue;
        }
        System.assertNotEquals(null, thrownException);
    }
}