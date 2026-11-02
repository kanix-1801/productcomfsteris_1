@IsTest
private class PpcCommercialApprovalControllerTest {
    @IsTest
    static void submitAndApproveRecordsDecision() {
        User approver = setupApprover();
        Opportunity opportunityRecord = createProposal();

        PpcCommercialApprovalService.ApprovalContext beforeSubmit =
            PpcCommercialApprovalService.getApprovalContext(opportunityRecord.Id);
        System.assertEquals(true, beforeSubmit.showPanel);

        Test.startTest();
        submitFromFlow(opportunityRecord.Id, approver.Id, 'Please review the financial assessment.');
        PpcCommercialApprovalService.ApprovalContext pending =
            PpcCommercialApprovalService.getApprovalContext(opportunityRecord.Id);
        System.assertEquals('Pending Approval', pending.dealApprovalStatus);
        System.assertEquals(false, pending.canDecide);
        System.assertNotEquals(null, pending.financialAssessmentLink);

        PpcCommercialApprovalService.ApprovalContext approved;
        System.runAs(approver) {
            approved = PpcCommercialApprovalService.decide(
                pending.approvers[0].id,
                'Approved',
                'Commercial terms accepted.'
            );
        }
        Test.stopTest();

        System.assertEquals('Approved', approved.dealApprovalStatus);
        System.assertEquals('Approved', approved.approvers[0].decision);
    }

    @IsTest
    static void rejectKeepsHistoryWhenResubmitted() {
        User approver = setupApprover();
        Opportunity opportunityRecord = createProposal();

        submitFromFlow(opportunityRecord.Id, approver.Id, 'First submit');
        PpcCommercialApprovalService.ApprovalContext pending =
            PpcCommercialApprovalService.getApprovalContext(opportunityRecord.Id);
        System.runAs(approver) {
            PpcCommercialApprovalService.decide(pending.approvers[0].id, 'Rejected', 'Pricing is incomplete.');
        }

        Test.startTest();
        submitFromFlow(opportunityRecord.Id, approver.Id, 'Updated pricing');
        PpcCommercialApprovalService.ApprovalContext resubmitted =
            PpcCommercialApprovalService.getApprovalContext(opportunityRecord.Id);
        Test.stopTest();

        System.assertEquals('Pending Approval', resubmitted.dealApprovalStatus);
        System.assertEquals(1, resubmitted.history.size());
        System.assertEquals('Rejected', resubmitted.history[0].decision);
    }

    @IsTest
    static void missingCommercialCommitmentBlocksSubmit() {
        User approver = setupApprover();
        Opportunity opportunityRecord = createProposal();
        opportunityRecord.Commercial_Commitment__c = null;
        update opportunityRecord;

        PpcCommercialApprovalService.FlowSubmitRequest request = new PpcCommercialApprovalService.FlowSubmitRequest();
        request.opportunityId = opportunityRecord.Id;
        request.approverUser1 = approver.Id;
        List<PpcCommercialApprovalService.FlowSubmitResult> results =
            PpcCommercialApprovalService.submitFromFlow(
                new List<PpcCommercialApprovalService.FlowSubmitRequest>{ request }
            );
        System.assertEquals(false, results[0].success);
        System.assert(results[0].message.contains('Commercial Commitment'));
    }

    @IsTest
    static void flowSubmitReportsAMissingOpportunity() {
        PpcCommercialApprovalService.FlowSubmitRequest request = new PpcCommercialApprovalService.FlowSubmitRequest();
        List<PpcCommercialApprovalService.FlowSubmitResult> results =
            PpcCommercialApprovalService.submitFromFlow(new List<PpcCommercialApprovalService.FlowSubmitRequest>{ request });
        System.assertEquals(false, results[0].success);
        System.assert(results[0].message.contains('Opportunity Id'));
    }

    @IsTest
    static void flowSubmitUsesSelectedApproverUsers() {
        User approver = setupApprover();
        Opportunity opportunityRecord = createProposal();
        PpcCommercialApprovalService.FlowSubmitRequest request =
            new PpcCommercialApprovalService.FlowSubmitRequest();
        request.opportunityId = opportunityRecord.Id;
        request.comments = 'Selected on the Pay Per Click submit screen.';
        request.approverUser1 = approver.Id;

        Test.startTest();
        List<PpcCommercialApprovalService.FlowSubmitResult> results =
            PpcCommercialApprovalService.submitFromFlow(
                new List<PpcCommercialApprovalService.FlowSubmitRequest>{ request }
            );
        Test.stopTest();

        System.assertEquals(true, results[0].success, results[0].message);
        DealApprovalApprover__c approvalRecord = [
            SELECT Approver__c, ApproverRole__c, Decision__c
            FROM DealApprovalApprover__c
            WHERE Opportunity__c = :opportunityRecord.Id
            AND IsCurrent__c = true
            LIMIT 1
        ];
        System.assertEquals(approver.Id, approvalRecord.Approver__c);
        System.assertEquals('Additional Approver', approvalRecord.ApproverRole__c);
        System.assertEquals('Pending', approvalRecord.Decision__c);
    }

    @IsTest
    static void nullInputsAreRejected() {
        try {
            PpcCommercialApprovalService.getApprovalContext(null);
            System.assert(false, 'A null Opportunity Id should be rejected.');
        } catch (AuraHandledException exceptionValue) {
            System.assert(exceptionValue.getMessage().contains('Opportunity Id'));
        }

        try {
            PpcCommercialApprovalService.decide(null, null, null);
            System.assert(false, 'A null approver record should be rejected.');
        } catch (AuraHandledException exceptionValue) {
            System.assert(exceptionValue.getMessage().contains('Approver record'));
        }
    }

    private static User setupApprover() {
        User approver;
        System.runAs(new User(Id = UserInfo.getUserId())) {
            bypassValidations();
            approver = createApprover();
        }
        return approver;
    }

    private static void bypassValidations() {
        Automation_Setting_Validation_Rule__c setting = Automation_Setting_Validation_Rule__c.getInstance(
            UserInfo.getUserId()
        );
        setting.SetupOwnerId = UserInfo.getUserId();
        setting.disableAll__c = true;
        upsert setting;
    }

    private static Opportunity createProposal() {
        Id prospectRecordTypeId = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName()
            .get('Prospect')
            .getRecordTypeId();
        Account accountRecord = new Account(Name = 'PPC Approval Account', RecordTypeId = prospectRecordTypeId);
        insert accountRecord;

        Opportunity opportunityRecord = new Opportunity(
            Name = 'PPC Approval',
            AccountId = accountRecord.Id,
            StageName = 'Proposal',
            CloseDate = Date.today().addDays(30),
            RecordTypeId = Schema.SObjectType.Opportunity.getRecordTypeInfosByDeveloperName()
                .get('HCSalesPayPerClick')
                .getRecordTypeId(),
            Commercial_Commitment__c = 'Consumable commitment for the placement term.',
            PPC_Pricing_Notes__c = 'Elevated consumable price.',
            FinancialAssessment__c = 'External model supports the placement.',
            Financial_Assessment_Link__c = 'https://example.com/financial-assessment'
        );
        insert opportunityRecord;
        return opportunityRecord;
    }

    private static User createApprover() {
        Profile adminProfile = [SELECT Id FROM Profile WHERE Name = 'System Administrator' LIMIT 1];
        String uniqueName = 'ppc.approver.' + String.valueOf(DateTime.now().getTime()) + '@example.com';
        User approver = new User(
            Alias = 'ppcapp',
            Email = 'ppc.approver@example.com',
            EmailEncodingKey = 'UTF-8',
            LastName = 'PPC Approver',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = adminProfile.Id,
            TimeZoneSidKey = 'America/Los_Angeles',
            Username = uniqueName
        );
        insert approver;
        return approver;
    }

    private static void submitFromFlow(Id opportunityId, Id approverId, String comments) {
        PpcCommercialApprovalService.FlowSubmitRequest request = new PpcCommercialApprovalService.FlowSubmitRequest();
        request.opportunityId = opportunityId;
        request.approverUser1 = approverId;
        request.comments = comments;
        List<PpcCommercialApprovalService.FlowSubmitResult> results =
            PpcCommercialApprovalService.submitFromFlow(
                new List<PpcCommercialApprovalService.FlowSubmitRequest>{ request }
            );
        System.assertEquals(true, results[0].success, results[0].message);
    }
}