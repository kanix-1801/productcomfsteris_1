/**
 * @description Tests for Strategic Contract deal approval submit, add approver, approve, and reject.
 */
@IsTest
private class OppDealApprovalControllerTest {
    private static final String TEST_OPPORTUNITY_NAME = 'Deal Approval Test Opportunity';
    private static final String DEAL_DESK_USERNAME_PREFIX = 'dealdesk.approver.';
    private static final String ADDITIONAL_USERNAME_PREFIX = 'additional.approver.';
    private static final String OPPORTUNITY_RECORD_TYPE_DEVELOPER_NAME =
        OppDealApprovalService.RECORD_TYPE_DEVELOPER_NAME;

    @TestSetup
    static void setupData() {
        User dealDeskUser = buildUser('Deal', 'Desk', DEAL_DESK_USERNAME_PREFIX);
        User additionalUser = buildUser('Additional', 'Approver', ADDITIONAL_USERNAME_PREFIX);
        insert new List<User>{ dealDeskUser, additionalUser };

        PermissionSet dealApprovalPermissionSet = [
            SELECT Id
            FROM PermissionSet
            WHERE Name = 'SalesEnterpriseStrategicAccountDirector'
            LIMIT 1
        ];
        insert new List<PermissionSetAssignment>{
            new PermissionSetAssignment(
                AssigneeId = dealDeskUser.Id,
                PermissionSetId = dealApprovalPermissionSet.Id
            ),
            new PermissionSetAssignment(
                AssigneeId = additionalUser.Id,
                PermissionSetId = dealApprovalPermissionSet.Id
            )
        };

        System.runAs(new User(Id = UserInfo.getUserId())) {
            Automation_Setting_Flow__c flowSettings = Automation_Setting_Flow__c.getOrgDefaults();
            if (flowSettings.Id == null) {
                flowSettings.SetupOwnerId = UserInfo.getOrganizationId();
            }
            flowSettings.Opportunity_AfterSave_UpdateBULeader__c = true;
            flowSettings.OpportunityAfterSaveAddDealDeskLead__c = true;
            upsert flowSettings;
            Account gpoAccount = new Account(
                Name = 'Vizient',
                SourceSystemID__c = 'DA-TEST-GPO',
                OracleAddressId__c = '638267'
            );
            insert gpoAccount;

            Account accountRecord = new Account(
                Name = 'Deal Approval Test Account',
                SourceSystemID__c = 'DA-TEST-ACCT',
                OracleAddressId__c = '638266',
                GPO_Account__c = gpoAccount.Id
            );
            insert accountRecord;

            Contact contactRecord = new Contact(
                FirstName = 'Deal',
                LastName = 'Approval',
                AccountId = accountRecord.Id
            );
            insert contactRecord;

            Opportunity opportunityRecord = buildStrategicOpportunity(
                TEST_OPPORTUNITY_NAME,
                accountRecord.Id,
                contactRecord.Id
            );
            insert opportunityRecord;

            insert new OpportunityTeamMember(
                OpportunityId = opportunityRecord.Id,
                UserId = dealDeskUser.Id,
                TeamMemberRole = OppDealApprovalService.ROLE_DEAL_DESK,
                OpportunityAccessLevel = 'Edit'
            );
        }
    }

    @IsTest
    static void testPreviewBlocksSubmitWhenDealFieldsMissing() {
        Opportunity opportunityRecord = getTestOpportunity();

        OppDealApprovalService.FlowRequest previewRequest = new OppDealApprovalService.FlowRequest();
        previewRequest.actionType = OppDealApprovalService.ACTION_PREVIEW;
        previewRequest.opportunityId = opportunityRecord.Id;

        Test.startTest();
        OppDealApprovalService.FlowResult previewResult =
            OppDealApprovalService.processFlowRequest(
                new List<OppDealApprovalService.FlowRequest>{ previewRequest }
            )[0];
        OppDealApprovalService.ApprovalContext context =
            OppDealApprovalController.getApprovalContext(opportunityRecord.Id);
        Test.stopTest();

        System.assertEquals(false, previewResult.canSubmit);
        System.assertEquals(true, String.isNotBlank(previewResult.missingRequirements));
        System.assertEquals(true, context.showPanel);
        System.assertEquals(OppDealApprovalService.MODE_SUBMIT, context.mode);
    }

    @IsTest
    static void testSubmitApproveCompletesApproval() {
        Opportunity opportunityRecord = prepareDealForSubmit();
        User dealDeskUser = getUserByUsernamePrefix(DEAL_DESK_USERNAME_PREFIX);

        Test.startTest();
        OppDealApprovalService.ApprovalContext submittedContext =
            OppDealApprovalService.submitForApproval(opportunityRecord.Id, null, 'Ready for review');
        System.assertEquals(OppDealApprovalService.MODE_PENDING_VIEWER, submittedContext.mode);

        OppDealApprovalService.ApprovalContext approvedContext;
        System.runAs(dealDeskUser) {
            OppDealApprovalService.ApprovalContext approverContext =
                OppDealApprovalController.getApprovalContext(opportunityRecord.Id);
            System.assertEquals(true, approverContext.canDecide);
            approvedContext = OppDealApprovalController.decide(
                approverContext.currentApproverRecordId,
                OppDealApprovalService.DECISION_APPROVED,
                'Looks good'
            );
        }
        Test.stopTest();

        Opportunity updatedOpportunity = [
            SELECT DealApprovalStatus__c, DealApprovalSubmissionComments__c
            FROM Opportunity
            WHERE Id = :opportunityRecord.Id
        ];
        System.assertEquals(
            'Ready for review',
            submittedContext.submissionComments
        );
        System.assertEquals(
            'Ready for review',
            updatedOpportunity.DealApprovalSubmissionComments__c
        );
        System.assertEquals(OppDealApprovalService.OPP_STATUS_APPROVED, updatedOpportunity.DealApprovalStatus__c);
        System.assertEquals(OppDealApprovalService.MODE_APPROVED, approvedContext.mode);

        Integer currentApproverCount = [
            SELECT COUNT()
            FROM DealApprovalApprover__c
            WHERE Opportunity__c = :opportunityRecord.Id
            AND IsCurrent__c = true
            AND Decision__c = :OppDealApprovalService.DECISION_APPROVED
        ];
        System.assertEquals(1, currentApproverCount);
    }

    @IsTest
    static void testRejectCapturesReasonAndReturnsForRework() {
        Opportunity opportunityRecord = prepareDealForSubmit();
        User dealDeskUser = getUserByUsernamePrefix(DEAL_DESK_USERNAME_PREFIX);

        OppDealApprovalService.submitForApproval(opportunityRecord.Id, null, null);

        Test.startTest();
        OppDealApprovalService.ApprovalContext rejectedContext;
        System.runAs(dealDeskUser) {
            OppDealApprovalService.ApprovalContext approverContext =
                OppDealApprovalController.getApprovalContext(opportunityRecord.Id);
            rejectedContext = OppDealApprovalController.decide(
                approverContext.currentApproverRecordId,
                OppDealApprovalService.DECISION_REJECTED,
                'Missing customer timing commitment'
            );
        }
        Test.stopTest();

        Opportunity updatedOpportunity = [
            SELECT DealApprovalStatus__c, DealApprovalRejectionReason__c, StageName
            FROM Opportunity
            WHERE Id = :opportunityRecord.Id
        ];
        System.assertEquals(OppDealApprovalService.OPP_STATUS_REJECTED, updatedOpportunity.DealApprovalStatus__c);
        System.assertEquals('Missing customer timing commitment', updatedOpportunity.DealApprovalRejectionReason__c);
        System.assertEquals(OppDealApprovalService.STAGE_DEAL_DEVELOPMENT, updatedOpportunity.StageName);
        System.assertEquals(OppDealApprovalService.MODE_REJECTED, rejectedContext.mode);
    }

    @IsTest
    static void testSubmitIncludesAdditionalApprover() {
        Opportunity opportunityRecord = prepareDealForSubmit();
        User additionalUser = getUserByUsernamePrefix(ADDITIONAL_USERNAME_PREFIX);

        Test.startTest();
        OppDealApprovalService.submitForApproval(
            opportunityRecord.Id,
            new List<Id>{ additionalUser.Id },
            null
        );
        Test.stopTest();

        Boolean foundAdditional = false;
        for (DealApprovalApprover__c approverRecord : [
            SELECT Approver__c, ApproverRole__c
            FROM DealApprovalApprover__c
            WHERE Opportunity__c = :opportunityRecord.Id
            AND IsCurrent__c = true
        ]) {
            if (approverRecord.Approver__c == additionalUser.Id) {
                foundAdditional = true;
                System.assertEquals(OppDealApprovalService.ROLE_ADDITIONAL, approverRecord.ApproverRole__c);
            }
        }
        System.assertEquals(true, foundAdditional);
    }

    @IsTest
    static void testSubmitIncludesMoreThanThreeAdditionalApprovers() {
        Opportunity opportunityRecord = prepareDealForSubmit();
        List<User> additionalUsers = new List<User>();
        for (Integer index = 0; index < 4; index++) {
            additionalUsers.add(buildUser('Extra', 'Approver' + index, 'extra.approver.' + index + '.'));
        }
        insert additionalUsers;

        List<Id> additionalApproverIds = new List<Id>();
        for (User additionalUser : additionalUsers) {
            additionalApproverIds.add(additionalUser.Id);
        }

        Test.startTest();
        OppDealApprovalService.submitForApproval(
            opportunityRecord.Id,
            additionalApproverIds,
            null
        );
        Test.stopTest();

        Set<Id> submittedApproverIds = new Set<Id>();
        for (DealApprovalApprover__c approverRecord : [
            SELECT Approver__c
            FROM DealApprovalApprover__c
            WHERE Opportunity__c = :opportunityRecord.Id
            AND ApproverRole__c = :OppDealApprovalService.ROLE_ADDITIONAL
            AND IsCurrent__c = true
        ]) {
            submittedApproverIds.add(approverRecord.Approver__c);
        }
        System.assertEquals(4, submittedApproverIds.size());
        System.assert(submittedApproverIds.containsAll(new Set<Id>(additionalApproverIds)));
    }

    @IsTest
    static void testRejectWithoutReasonFails() {
        Opportunity opportunityRecord = prepareDealForSubmit();
        User dealDeskUser = getUserByUsernamePrefix(DEAL_DESK_USERNAME_PREFIX);
        OppDealApprovalService.submitForApproval(opportunityRecord.Id, null, null);

        Boolean threwException = false;
        System.runAs(dealDeskUser) {
            OppDealApprovalService.ApprovalContext approverContext =
                OppDealApprovalController.getApprovalContext(opportunityRecord.Id);
            try {
                OppDealApprovalController.decide(
                    approverContext.currentApproverRecordId,
                    OppDealApprovalService.DECISION_REJECTED,
                    ''
                );
            } catch (Exception exceptionValue) {
                threwException = true;
            }
        }
        System.assertEquals(true, threwException);
    }

    @IsTest
    static void testGetApprovalContextRethrowsAuraHandledException() {
        Boolean threwException = false;

        try {
            OppDealApprovalController.getApprovalContext(null);
        } catch (AuraHandledException exceptionValue) {
            threwException = true;
            //System.assertEquals('Opportunity Id is required.', exceptionValue.getMessage());
        }

        System.assertEquals(true, threwException);
    }

    @IsTest
    static void testGetApprovalContextWrapsUnexpectedErrors() {
        Boolean threwException = false;

        try {
            OppDealApprovalController.getApprovalContext(UserInfo.getUserId());
        } catch (AuraHandledException exceptionValue) {
            threwException = true;
            //System.assertEquals('Unable to load deal approval details.', exceptionValue.getMessage());
        }

        System.assertEquals(true, threwException);
    }

    @IsTest
    static void testDecideRethrowsAuraHandledException() {
        Boolean threwException = false;

        try {
            OppDealApprovalController.decide(null, OppDealApprovalService.DECISION_APPROVED, null);
        } catch (AuraHandledException exceptionValue) {
            threwException = true;
            //System.assertEquals('Approver record and decision are required.', exceptionValue.getMessage());
        }

        System.assertEquals(true, threwException);
    }

    @IsTest
    static void testDecideWrapsUnexpectedErrors() {
        Boolean threwException = false;

        try {
            OppDealApprovalController.decide(
                UserInfo.getUserId(),
                OppDealApprovalService.DECISION_APPROVED,
                'Approval note'
            );
        } catch (AuraHandledException exceptionValue) {
            threwException = true;
            //System.assertEquals('Unable to record the approval decision.', exceptionValue.getMessage());
        }

        System.assertEquals(true, threwException);
    }

    private static Opportunity prepareDealForSubmit() {
        Opportunity opportunityRecord = getTestOpportunity();
        opportunityRecord.Dealstrategy__c = 'Pursue competitive displacement with bundled pricing.';
        opportunityRecord.FinancialAssessment__c = 'Projected margin supports the proposed incentives.';
        update opportunityRecord;
        return opportunityRecord;
    }

    private static Opportunity getTestOpportunity() {
        return [
            SELECT Id, StageName, DealApprovalStatus__c
            FROM Opportunity
            WHERE Name = :TEST_OPPORTUNITY_NAME
            LIMIT 1
        ];
    }

    private static User getUserByUsernamePrefix(String usernamePrefix) {
        return [
            SELECT Id, Username
            FROM User
            WHERE Username LIKE :(usernamePrefix + '%')
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
    }

    private static User buildUser(String firstName, String lastName, String usernamePrefix) {
        User currentUser = [
            SELECT ProfileId
            FROM User
            WHERE Id = :UserInfo.getUserId()
            LIMIT 1
        ];

        String uniqueSuffix = String.valueOf(Math.abs(Crypto.getRandomInteger()));
        return new User(
            FirstName = firstName,
            LastName = lastName,
            Alias = uniqueSuffix.left(8),
            Email = usernamePrefix + uniqueSuffix + '@example.com',
            Username = usernamePrefix + uniqueSuffix + '@example.com.steris',
            CommunityNickname = (firstName + uniqueSuffix).left(40),
            TimeZoneSidKey = 'America/New_York',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            ProfileId = currentUser.ProfileId
        );
    }

    private static Opportunity buildStrategicOpportunity(
        String opportunityName,
        Id accountId,
        Id contactId
    ) {
        Opportunity opportunityRecord = new Opportunity(
            Name = opportunityName,
            AccountId = accountId,
            StageName = OppDealApprovalService.STAGE_DEAL_DEVELOPMENT,
            CloseDate = Date.today().addDays(30),
            Amount = 1000,
            Probability = 10,
            PrimaryContact__c = contactId,
            StrategicAccountsContact__c = contactId,
            STERISIDNDirector__c = UserInfo.getUserId(),
            DateofRequest__c = Date.today(),
            CustomerPurchasingCommitment__c = 5000000,
            StrategicDealIntent__c = 'Pursue a strategic agreement.',
            StrategicDealValue__c = 'Expected growth across the IDN.',
            DealApprovalStatus__c = OppDealApprovalService.OPP_STATUS_NOT_SUBMITTED
        );

        Id recordTypeId = resolveOpportunityRecordTypeId();
        System.assertNotEquals(
            null,
            recordTypeId,
            'HCSalesStrategicContract opportunity record type is required.'
        );
        opportunityRecord.RecordTypeId = recordTypeId;

        assignFirstPicklistValue(opportunityRecord, Opportunity.Type);
        assignFirstPicklistValue(opportunityRecord, Opportunity.ContractType__c);
        assignFirstPicklistValue(opportunityRecord, Opportunity.DesiredContractTerm__c);
        assignFirstPicklistValue(opportunityRecord, Opportunity.AutomaticRenewal__c);
        assignFirstPicklistValue(opportunityRecord, Opportunity.PartnershipLevel__c);
        assignFirstPicklistValue(opportunityRecord, Opportunity.ContractPaper__c);
        assignFirstPicklistValue(opportunityRecord, Opportunity.ContractRequestOrigin__c);
        assignFirstPicklistValue(opportunityRecord, Opportunity.CustomerGPOAffiliation__c);
        assignFirstPicklistValue(opportunityRecord, Opportunity.HighComplianceMember__c);
        assignFirstPicklistValue(opportunityRecord, Opportunity.AccountClassification__c);
        assignFirstPicklistValue(opportunityRecord, Opportunity.ThirdPartyFinancingOpportunity__c);
        return opportunityRecord;
    }

    private static void assignFirstPicklistValue(Opportunity opportunityRecord, Schema.SObjectField fieldToken) {
        String fieldName = fieldToken.getDescribe().getName();
        for (Schema.PicklistEntry picklistEntry : fieldToken.getDescribe().getPicklistValues()) {
            if (picklistEntry.isActive()) {
                opportunityRecord.put(fieldName, picklistEntry.getValue());
                return;
            }
        }
    }

    private static Id resolveOpportunityRecordTypeId() {
        Map<String, Schema.RecordTypeInfo> recordTypesByDeveloperName =
            Schema.SObjectType.Opportunity.getRecordTypeInfosByDeveloperName();
        if (!recordTypesByDeveloperName.containsKey(OPPORTUNITY_RECORD_TYPE_DEVELOPER_NAME)) {
            return null;
        }
        return recordTypesByDeveloperName.get(OPPORTUNITY_RECORD_TYPE_DEVELOPER_NAME).getRecordTypeId();
    }
}