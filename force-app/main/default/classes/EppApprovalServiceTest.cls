/**
 * @description Tests for EPP sequential approval and EppApprovalSelector (GC-3432).
 */
@IsTest
private class EppApprovalServiceTest {
    private static final String EPP_RT = 'HCSalesEquipmentPlacementProgram';
    private static final String OTHER_RT = 'Healthcare_Sales';
    private static final String SECOND_USERNAME = 'epp.approver2@eppservice.test';
    private static final String INACTIVE_USERNAME = 'epp.inactive@eppservice.test';

    @TestSetup
    static void setupData() {
        Profile adminProfile = [
            SELECT Id
            FROM Profile
            WHERE Name = 'System Administrator'
            LIMIT 1
        ];
        insert new List<User>{
            buildUser(adminProfile.Id, SECOND_USERNAME, 'eppapr2', true),
            buildUser(adminProfile.Id, INACTIVE_USERNAME, 'eppinact', false)
        };

        System.runAs(new User(Id = UserInfo.getUserId())) {
            Account acc = new Account(Name = 'EPP Approval Account');
            insert acc;
            Contact primaryContact = new Contact(
                LastName = 'EPP Approval Contact',
                AccountId = acc.Id
            );
            insert primaryContact;

            Id eppRecordTypeId = recordTypeId(EPP_RT);
            Id otherRecordTypeId = recordTypeId(OTHER_RT);
            List<Opportunity> opportunities = new List<Opportunity>{
                buildEppOpportunity('EPP Ready Approve', acc.Id, primaryContact.Id, eppRecordTypeId, 'Washer Approve'),
                buildEppOpportunity('EPP Ready Reject', acc.Id, primaryContact.Id, eppRecordTypeId, 'Washer Reject'),
                buildEppOpportunity('EPP Ready Resubmit', acc.Id, primaryContact.Id, eppRecordTypeId, 'Washer Resubmit'),
                buildEppOpportunity('EPP Missing Product', acc.Id, primaryContact.Id, eppRecordTypeId, null),
                buildEppOpportunity('EPP File Link', acc.Id, primaryContact.Id, eppRecordTypeId, 'Washer File'),
                new Opportunity(
                    Name = 'EPP Other Record Type',
                    AccountId = acc.Id,
                    RecordTypeId = otherRecordTypeId,
                    Type = 'New Business',
                    Amount = 1000,
                    Probability = 10,
                    PrimaryContact__c = primaryContact.Id,
                    StageName = 'Discovery',
                    ForecastConfidenceLevel__c = 'Pipeline',
                    CloseDate = Date.today().addDays(30)
                )
            };
            opportunities[3].Placement_Start_Date__c = Date.today().addDays(10);
            opportunities[3].Placement_End_Date__c = Date.today();
            opportunities[4].Financial_Link__c = null;
            insert opportunities;

            ContentVersion version = new ContentVersion(
                Title = 'EPP Financial Analysis',
                PathOnClient = 'EPPFinancial.txt',
                VersionData = Blob.valueOf('financial analysis'),
                FirstPublishLocationId = opportunities[4].Id
            );
            insert version;
        }
    }

    @IsTest
    static void financialLinkIsRequiredForSubmission() {
        Opportunity opportunityRecord = new Opportunity();
        opportunityRecord.Region__c = 'APAC';
        opportunityRecord.Financial_Link__c = null;

        List<String> missingRequirements = EppApprovalService.collectMissingRequirements(opportunityRecord);

        System.assert(contains(missingRequirements, 'Financial Link'), 'Financial Link must block submission.');
    }

    @IsTest
    static void serviceCommitmentRequiresItsFields() {
        Opportunity opportunityRecord = new Opportunity();
        opportunityRecord.Region__c = 'APAC';
        opportunityRecord.Financial_Link__c = 'https://example.com/financial';
        opportunityRecord.ServiceCommitment__c = true;
        opportunityRecord.ServiceType__c = 'Other';

        String combined = String.join(EppApprovalService.collectMissingRequirements(opportunityRecord), ' ');

        System.assert(combined.contains('Product/Equipment'), 'Equipment is required before submission.');
        System.assert(combined.contains('Placement Start Date'), 'Placement start date is required.');
        System.assert(combined.contains('Placement End Date'), 'Placement end date is required.');
        System.assertEquals(
            false,
            combined.contains('Customer Commercial Commitment Type'),
            'Service commitment satisfies the customer commercial commitment type.'
        );
    }

    @IsTest
    static void missingRequirementsCoverRegionDatesAndCommitment() {
        Opportunity opportunityRecord = new Opportunity();
        opportunityRecord.Financial_Link__c = 'https://example.com/financial';
        opportunityRecord.Product_Equipment__c = 'Washer';
        opportunityRecord.Placement_Start_Date__c = Date.today().addDays(5);
        opportunityRecord.Placement_End_Date__c = Date.today();

        String combined = String.join(EppApprovalService.collectMissingRequirements(opportunityRecord), ' ');

        System.assert(combined.contains('Region'), 'Region is required.');
        System.assert(combined.contains('Customer Commercial Commitment Type'), 'A commitment type is required.');
        System.assert(
            combined.contains('Placement End Date on or after the Placement Start Date'),
            'The placement date range should be reported.'
        );
    }

    @IsTest
    static void normalizeRegionMapsKnownAliases() {
        System.assertEquals('APAC', EppApprovalService.normalizeRegion(' apac '));
        System.assertEquals('APAC', EppApprovalService.normalizeRegion('Asia Pacific'));
        System.assertEquals('LATAM', EppApprovalService.normalizeRegion('Latin America'));
        System.assertEquals('US & Canada', EppApprovalService.normalizeRegion('United States'));
        System.assertEquals('US & Canada', EppApprovalService.normalizeRegion('US'));
        System.assertEquals('US & Canada', EppApprovalService.normalizeRegion('US and Canada'));
        System.assertEquals('US & Canada', EppApprovalService.normalizeRegion('North America'));
        System.assertEquals('EMEA', EppApprovalService.normalizeRegion(' EMEA '));
        System.assertEquals(null, EppApprovalService.normalizeRegion('   '));
    }

    @IsTest
    static void hierarchySelectorFiltersTestRowsAndQueriesMetadata() {
        EppApprovalSelector.testHierarchy = new List<EPP_Approval_Hierarchy__mdt>{
            new EPP_Approval_Hierarchy__mdt(
                Region__c = 'APAC',
                Sequence__c = 1,
                Approver_Role__c = 'APAC VP',
                Approver_Username__c = null,
                Active__c = true
            ),
            new EPP_Approval_Hierarchy__mdt(
                Region__c = 'APAC',
                Sequence__c = 2,
                Approver_Role__c = 'VP',
                Active__c = false
            ),
            new EPP_Approval_Hierarchy__mdt(
                Region__c = 'LATAM',
                Sequence__c = 1,
                Approver_Role__c = 'VP',
                Active__c = true
            )
        };

        List<EPP_Approval_Hierarchy__mdt> apacRows = EppApprovalSelector.selectHierarchy('apac');
        System.assertEquals(1, apacRows.size(), 'Only the active APAC row should match.');
        System.assertEquals(0, EppApprovalSelector.selectHierarchy(null).size(), 'A blank region matches nothing.');

        EppApprovalSelector.testHierarchy = null;
        System.assertNotEquals(null, EppApprovalSelector.selectHierarchy('APAC'), 'Metadata query should return a list.');
    }

    @IsTest
    static void selectorReadsOpportunityUsersApproversAndNotificationType() {
        Opportunity ready = opportunityByProduct('Washer Approve');
        User secondApprover = [SELECT Id, Username FROM User WHERE Username = :SECOND_USERNAME];

        System.assertEquals(null, EppApprovalSelector.selectOpportunity(ready.AccountId), 'A non-opportunity Id returns no row.');
        Opportunity loaded = EppApprovalSelector.selectOpportunity(ready.Id);
        System.assertEquals(EPP_RT, loaded.RecordType.DeveloperName, 'The EPP record type should be loaded.');

        System.assertEquals(0, EppApprovalSelector.selectEquipmentLines(null).size());
        System.assertEquals(0, EppApprovalSelector.selectConsumableLines(null).size());
        System.assertEquals(0, EppApprovalSelector.selectEquipmentLines(ready.Id).size());
        System.assertEquals(0, EppApprovalSelector.selectConsumableLines(ready.Id).size());
        System.assertEquals(0, EppApprovalSelector.selectCurrentApprovers(ready.Id).size());

        System.assertEquals(0, EppApprovalSelector.selectUsersByUsername(null).size());
        System.assertEquals(0, EppApprovalSelector.selectUsersByUsername(new Set<String>()).size());
        Map<String, User> users = EppApprovalSelector.selectUsersByUsername(
            new Set<String>{ secondApprover.Username, 'missing.user@eppservice.test' }
        );
        System.assertEquals(secondApprover.Id, users.get(SECOND_USERNAME).Id, 'The active approver should be resolved.');
        System.assertEquals(null, EppApprovalSelector.selectNotificationTypeId('Missing_EPP_Notification'));
        EppApprovalSelector.selectNotificationTypeId('EPP_Approval_Required');
    }

    @IsTest
    static void financialFileSatisfiesFinancialLink() {
        Opportunity withFile = EppApprovalSelector.selectOpportunity(opportunityByProduct('Washer File').Id);

        System.assertEquals(
            false,
            contains(EppApprovalService.collectMissingRequirements(withFile), 'Financial Link'),
            'A linked financial file satisfies the financial link requirement.'
        );
    }

    @IsTest
    static void previewReportsMissingFieldsAndAReadyPath() {
        useHierarchy(new List<String>{ UserInfo.getUserName() });

        EppApprovalService.FlowResult missing = invoke('Preview', opportunityByProduct(null).Id, null);
        System.assertEquals(false, missing.canContinue, missing.message);
        System.assert(missing.missingRequirements.contains('Please fill Product/Equipment'), missing.missingRequirements);
        System.assert(
            missing.missingRequirements.contains('Placement End Date on or after the Placement Start Date'),
            missing.missingRequirements
        );
        System.assert(missing.approvalPathSummary.contains('APAC: 1. APAC VP'), missing.approvalPathSummary);

        EppApprovalService.FlowResult ready = invoke('Preview', opportunityByProduct('Washer Approve').Id, null);
        System.assertEquals(true, ready.canContinue, ready.message);
        System.assertEquals('Review the regional approval path, then submit.', ready.message);
    }

    @IsTest
    static void processFlowRequestIgnoresEmptyInputAndUnknownRecords() {
        System.assertEquals(0, EppApprovalService.processFlowRequest(null).size());
        System.assertEquals(0, EppApprovalService.processFlowRequest(new List<EppApprovalService.FlowRequest>()).size());

        EppApprovalService.FlowResult missing = invoke('Preview', null, null);
        System.assertEquals(false, missing.canContinue);
        System.assert(missing.missingRequirements.contains('Opportunity Id is required.'), missing.message);

        EppApprovalService.FlowResult wrongType = invoke(
            'Preview',
            [SELECT Id FROM Opportunity WHERE RecordType.DeveloperName = :OTHER_RT LIMIT 1].Id,
            null
        );
        System.assertEquals(false, wrongType.canContinue);
        System.assert(
            wrongType.message.contains('Equipment Placement Program'),
            wrongType.message
        );

        EppApprovalService.FlowResult notFound = invoke('Submit', opportunityByProduct('Washer Approve').AccountId, null);
        System.assertEquals(false, notFound.canContinue);
        System.assert(notFound.message.contains('Opportunity was not found.'), notFound.message);
    }

    @IsTest
    static void submitApproveAndCompleteRegionalPath() {
        User secondApprover = [SELECT Id, Username FROM User WHERE Username = :SECOND_USERNAME];
        useHierarchy(new List<String>{ secondApprover.Username, UserInfo.getUserName() });
        Opportunity ready = opportunityByProduct('Washer Approve');

        Test.startTest();
        EppApprovalService.FlowResult submitted = invoke('Submit', ready.Id, null);
        System.assertEquals(true, submitted.canContinue, submitted.message);

        EppApprovalService.FlowResult wrongApprover = invoke('Approve', ready.Id, null);
        System.assertEquals(false, wrongApprover.canContinue, wrongApprover.message);
        System.assert(wrongApprover.message.contains('not the current sequential approver'), wrongApprover.message);

        EppApprovalService.FlowResult firstDecision;
        System.runAs(secondApprover) {
            firstDecision = invoke('Approve', ready.Id, 'First approval');
        }
        System.assertEquals(true, firstDecision.canContinue, firstDecision.message);

        EppApprovalService.FlowResult finalDecision = invoke('Approve', ready.Id, 'Final approval');
        Test.stopTest();

        System.assertEquals(true, finalDecision.canContinue, finalDecision.message);
        Opportunity completed = [
            SELECT StageName, EPP_Approval_Status__c, EPP_All_Approvals_Complete__c, EPP_Current_Approver__c
            FROM Opportunity
            WHERE Id = :ready.Id
        ];
        System.assertEquals('Approved', completed.EPP_Approval_Status__c);
        System.assertEquals('Contracting', completed.StageName);
        System.assertEquals(true, completed.EPP_All_Approvals_Complete__c);
        System.assertEquals(null, completed.EPP_Current_Approver__c);

        EppApprovalService.FlowResult alreadyApproved = invoke('Submit', ready.Id, null);
        System.assert(alreadyApproved.message.contains('already approved'), alreadyApproved.message);
    }

    @IsTest
    static void rejectReturnsToDraftAndAllowsResubmit() {
        useHierarchy(new List<String>{ UserInfo.getUserName() });
        Opportunity ready = opportunityByProduct('Washer Reject');

        Test.startTest();
        System.assertEquals(true, invoke('Submit', ready.Id, null).canContinue);

        EppApprovalService.FlowResult missingReason = invoke('Reject', ready.Id, null);
        System.assert(missingReason.message.contains('Enter a rejection reason.'), missingReason.message);

        EppApprovalService.FlowResult rejected = invoke('Reject', ready.Id, 'Pricing needs revision');
        System.assertEquals(true, rejected.canContinue, rejected.message);

        EppApprovalService.FlowResult resubmitted = invoke('Submit', ready.Id, null);
        Test.stopTest();

        System.assertEquals(true, resubmitted.canContinue, resubmitted.message);
        Opportunity current = [
            SELECT StageName, EPP_Approval_Status__c, EPP_Current_Approver__c
            FROM Opportunity
            WHERE Id = :ready.Id
        ];
        System.assertEquals('Submitted for Approval', current.EPP_Approval_Status__c);
        System.assertEquals('Approval', current.StageName);
        System.assertEquals(UserInfo.getUserId(), current.EPP_Current_Approver__c);
        System.assertEquals(
            1,
            [SELECT COUNT() FROM DealApprovalApprover__c WHERE Opportunity__c = :ready.Id AND IsCurrent__c = TRUE]
        );
    }

    @IsTest
    static void submitGuardsDuplicateMissingHierarchyAndInactiveApprover() {
        Opportunity ready = opportunityByProduct('Washer Resubmit');
        useHierarchy(new List<String>{ UserInfo.getUserName() });

        Test.startTest();
        System.assertEquals(true, invoke('Submit', ready.Id, null).canContinue);
        EppApprovalService.FlowResult duplicate = invoke('Submit', ready.Id, null);
        System.assert(duplicate.message.contains('already submitted'), duplicate.message);

        try {
            EppApprovalService.decide(ready.Id, 'Hold', null);
            System.assert(false, 'An unknown decision should be rejected.');
        } catch (EppApprovalService.EppApprovalException expectedException) {
            System.assert(expectedException.getMessage().contains('Approved or Rejected'), expectedException.getMessage());
        }

        EppApprovalSelector.testHierarchy = new List<EPP_Approval_Hierarchy__mdt>();
        EppApprovalService.FlowResult noHierarchy = invoke('Submit', opportunityByProduct('Washer File').Id, null);
        System.assert(noHierarchy.message.contains('No active EPP approval hierarchy'), noHierarchy.message);

        useHierarchy(new List<String>{ INACTIVE_USERNAME });
        EppApprovalService.FlowResult inactive = invoke('Submit', opportunityByProduct('Washer Reject').Id, null);
        Test.stopTest();

        System.assert(inactive.message.contains('No active approver user'), inactive.message);
    }

    private static Boolean contains(List<String> values, String fragment) {
        for (String value : values) {
            if (value != null && value.contains(fragment)) {
                return true;
            }
        }
        return false;
    }

    private static EppApprovalService.FlowResult invoke(String actionType, Id opportunityId, String comments) {
        EppApprovalService.FlowRequest request = new EppApprovalService.FlowRequest();
        request.actionType = actionType;
        request.opportunityId = opportunityId;
        request.comments = comments;
        return EppApprovalService.processFlowRequest(
            new List<EppApprovalService.FlowRequest>{ request }
        )[0];
    }

    private static void useHierarchy(List<String> usernamesInSequence) {
        List<EPP_Approval_Hierarchy__mdt> rows = new List<EPP_Approval_Hierarchy__mdt>();
        for (Integer index = usernamesInSequence.size() - 1; index >= 0; index--) {
            rows.add(new EPP_Approval_Hierarchy__mdt(
                Region__c = 'APAC',
                Sequence__c = index + 1,
                Approver_Role__c = 'APAC VP',
                Approver_Username__c = usernamesInSequence[index],
                Active__c = true
            ));
        }
        EppApprovalSelector.testHierarchy = rows;
    }

    private static Opportunity opportunityByProduct(String productName) {
        return [
            SELECT Id, AccountId, Name
            FROM Opportunity
            WHERE RecordType.DeveloperName = :EPP_RT
            AND Product_Equipment__c = :productName
            LIMIT 1
        ];
    }

    private static Id recordTypeId(String developerName) {
        return Schema.SObjectType.Opportunity.getRecordTypeInfosByDeveloperName()
            .get(developerName)
            .getRecordTypeId();
    }

    private static Opportunity buildEppOpportunity(
        String name,
        Id accountId,
        Id contactId,
        Id eppRecordTypeId,
        String productName
    ) {
        return new Opportunity(
            Name = name,
            AccountId = accountId,
            RecordTypeId = eppRecordTypeId,
            Type = 'New Business',
            Amount = 1000,
            Probability = 0,
            PrimaryContact__c = contactId,
            StageName = 'Draft',
            CloseDate = Date.today().addDays(30),
            Region__c = 'APAC',
            Financial_Link__c = 'https://example.com/financial',
            Product_Equipment__c = productName,
            Placement_Start_Date__c = Date.today(),
            Placement_End_Date__c = Date.today().addDays(30),
            InstallationCommitment__c = true
        );
    }

    private static User buildUser(Id profileId, String username, String alias, Boolean isActive) {
        return new User(
            ProfileId = profileId,
            Username = username,
            Email = username,
            LastName = 'Approver ' + alias,
            Alias = alias,
            TimeZoneSidKey = 'America/New_York',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            IsActive = isActive
        );
    }
}