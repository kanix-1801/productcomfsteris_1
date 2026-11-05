/**
 * @author Abhishek Mishra
 * @date 07-27-2026
 * @description GC-2643 - Tests Duplicate_Match_Key__c and Territory_ID__c population
 *              via OpportunityService.populateDuplicateMatchKey.
 */
@IsTest
private class OpportunityDuplicateMatchKeyTest {

    private static final String PERMISSION_SET_GROUP_DEVELOPER_NAME = 'SalesFieldRepAccountManagerPSG';
    private static Boolean permissionSetGroupCalculated = false;
    private static final Id CONSUMABLE_RECORD_TYPE_ID =
        Schema.SObjectType.Opportunity.getRecordTypeInfosByDeveloperName()
            .get('HCSalesConsumables')
            .getRecordTypeId();
    private static final Id CAPITAL_RECORD_TYPE_ID =
        Schema.SObjectType.Opportunity.getRecordTypeInfosByDeveloperName()
            .get('Healthcare_Sales')
            .getRecordTypeId();

    @testSetup
    static void setupData() {
        Profile healthcareSalesProfile = [
            SELECT Id
            FROM Profile
            WHERE Name = 'Healthcare Sales'
            LIMIT 1
        ];

        Long uniqueSeed = System.currentTimeMillis();

        User runningUser = createUser(
            healthcareSalesProfile.Id,
            'runninguser' + uniqueSeed + '@test.com',
            'RUN' + String.valueOf(Math.abs(Crypto.getRandomInteger()))
        );

        insert runningUser;
        assignPermissionSetGroup(runningUser.Id);

        System.runAs(runningUser) {
            createTestAccount();
        }
    }

    /**
     * @description Verifies Duplicate_Match_Key__c and Territory_ID__c are set on insert.
     */
    @IsTest
    static void testSetsDuplicateMatchKeyOnInsert() {
        String tasAddressId = 'ADDR-INS-001';
        String territoryId = 'TERR-INS-001';

        insertOrderLineContact(tasAddressId, territoryId);

        User runningUser = getRunningUser();

        System.runAs(runningUser) {
            updateAccountOracleAddressId(tasAddressId);

            Account acc = getTestAccount();
            Id primaryContactId = getTestPrimaryContactId();
            String opportunityType = 'Renewal';

            Opportunity opp = new Opportunity(
                Name = 'Duplicate Key Opportunity',
                RecordTypeId = CONSUMABLE_RECORD_TYPE_ID,
                AccountId = acc.Id,
                PrimaryContact__c = primaryContactId,
                Type = opportunityType,
                StageName = 'Discovery',
                CloseDate = Date.today().addDays(30),
                Amount = 900.00,
                Probability = 10
            );

            String expectedKey = buildExpectedDuplicateKey(
                tasAddressId,
                primaryContactId,
                opportunityType,
                territoryId
            );

            Test.startTest();

            OpportunityService.populateDuplicateMatchKey(
                new List<Opportunity>{ opp },
                null
            );

            Test.stopTest();

            System.assertEquals(
                expectedKey,
                opp.Duplicate_Match_Key__c,
                'Duplicate match key should be populated on insert.'
            );
            System.assertEquals(
                territoryId,
                opp.Territory_ID__c,
                'Territory Id should be populated on insert.'
            );
        }
    }

    /**
     * @description Verifies Duplicate_Match_Key__c is regenerated when key fields change on update.
     */
    @IsTest
    static void testRegeneratesDuplicateMatchKeyOnUpdate() {
        String tasAddressId = 'ADDR-UPD-001';
        String territoryId = 'TERR-UPD-001';

        insertOrderLineContact(tasAddressId, territoryId);

        User runningUser = getRunningUser();

        System.runAs(runningUser) {
            updateAccountOracleAddressId(tasAddressId);

            Account acc = getTestAccount();
            Id primaryContactId = getTestPrimaryContactId();
            String updatedType = 'New Business';

            Opportunity opp = new Opportunity(
                Id = getTestOpportunityId(),
                Name = 'Update Duplicate Key Opportunity',
                RecordTypeId = CAPITAL_RECORD_TYPE_ID,
                AccountId = acc.Id,
                PrimaryContact__c = primaryContactId,
                Type = 'Renewal',
                StageName = 'Discovery',
                CloseDate = Date.today().addDays(30),
                Amount = 900.00,
                Probability = 10
            );

            OpportunityService.populateDuplicateMatchKey(
                new List<Opportunity>{ opp },
                null
            );

            Opportunity oldOpp = opp.clone(true, true, true, true);
            String originalKey = opp.Duplicate_Match_Key__c;

            opp.Name = 'Updated Name Only';

            OpportunityService.populateDuplicateMatchKey(
                new List<Opportunity>{ opp },
                new Map<Id, Opportunity>{ opp.Id => oldOpp }
            );

            System.assertEquals(
                originalKey,
                opp.Duplicate_Match_Key__c,
                'Duplicate match key should not change when duplicate fields are unchanged.'
            );

            oldOpp = opp.clone(true, true, true, true);
            opp.Type = updatedType;

            String expectedUpdatedKey = buildExpectedDuplicateKey(
                tasAddressId,
                primaryContactId,
                updatedType,
                territoryId
            );

            Test.startTest();

            OpportunityService.populateDuplicateMatchKey(
                new List<Opportunity>{ opp },
                new Map<Id, Opportunity>{ opp.Id => oldOpp }
            );

            Test.stopTest();

            System.assertEquals(
                expectedUpdatedKey,
                opp.Duplicate_Match_Key__c,
                'Duplicate match key should be regenerated on update.'
            );
            System.assertEquals(
                territoryId,
                opp.Territory_ID__c,
                'Territory Id should remain populated on update.'
            );
        }
    }

    /**
     * @description Verifies incomplete or invalid input does not produce a duplicate match key.
     */
    @IsTest
    static void testSkipsIncompleteRecords() {
        String tasAddressId = 'ADDR-MISS-001';
        String territoryId = 'TERR-MISS-001';

        insertOrderLineContact(tasAddressId, territoryId);

        User runningUser = getRunningUser();

        System.runAs(runningUser) {
            updateAccountOracleAddressId(tasAddressId);

            Account acc = getTestAccount();
            Id primaryContactId = getTestPrimaryContactId();

            Opportunity missingPrimaryContact = new Opportunity(
                Name = 'Missing Primary Contact',
                RecordTypeId = CONSUMABLE_RECORD_TYPE_ID,
                AccountId = acc.Id,
                Type = 'Renewal',
                StageName = 'Discovery',
                CloseDate = Date.today().addDays(30),
                Amount = 900.00,
                Probability = 10
            );

            Opportunity missingType = new Opportunity(
                Name = 'Missing Type',
                RecordTypeId = CONSUMABLE_RECORD_TYPE_ID,
                AccountId = acc.Id,
                PrimaryContact__c = primaryContactId,
                StageName = 'Discovery',
                CloseDate = Date.today().addDays(30),
                Amount = 900.00,
                Probability = 10
            );

            Opportunity blankTasAddress = new Opportunity(
                Name = 'Blank TAS Address',
                RecordTypeId = CAPITAL_RECORD_TYPE_ID,
                AccountId = acc.Id,
                PrimaryContact__c = primaryContactId,
                Type = 'Renewal',
                StageName = 'Discovery',
                CloseDate = Date.today().addDays(30),
                Amount = 900.00,
                Probability = 10
            );

            Opportunity noTerritoryMapping = new Opportunity(
                Name = 'No Territory Mapping',
                RecordTypeId = CAPITAL_RECORD_TYPE_ID,
                AccountId = acc.Id,
                PrimaryContact__c = primaryContactId,
                Type = 'Renewal',
                StageName = 'Discovery',
                CloseDate = Date.today().addDays(30),
                Amount = 900.00,
                Probability = 10
            );

            updateAccountOracleAddressId(null);

            Test.startTest();

            OpportunityService.populateDuplicateMatchKey(null, null);
            OpportunityService.populateDuplicateMatchKey(
                new List<Opportunity>(),
                null
            );
            OpportunityService.populateDuplicateMatchKey(
                new List<Opportunity>{
                    missingPrimaryContact,
                    missingType,
                    blankTasAddress
                },
                null
            );

            updateAccountOracleAddressId('ADDR-NOTERR-01');

            OpportunityService.populateDuplicateMatchKey(
                new List<Opportunity>{ noTerritoryMapping },
                null
            );

            Test.stopTest();

            System.assertEquals(
                null,
                missingPrimaryContact.Duplicate_Match_Key__c,
                'Key should be null when Primary Contact is missing.'
            );
            System.assertEquals(
                null,
                missingType.Duplicate_Match_Key__c,
                'Key should be null when Type is missing.'
            );
            System.assertEquals(
                null,
                blankTasAddress.Duplicate_Match_Key__c,
                'Key should be null when Account Oracle Address Id is blank.'
            );
            System.assertEquals(
                null,
                noTerritoryMapping.Duplicate_Match_Key__c,
                'Key should be null when no territory mapping exists.'
            );
        }
    }

    private static void assignPermissionSetGroup(Id userId) {
        PermissionSetGroup permissionSetGroup = [
            SELECT Id, Status
            FROM PermissionSetGroup
            WHERE DeveloperName = :PERMISSION_SET_GROUP_DEVELOPER_NAME
            LIMIT 1
        ];

        if (!permissionSetGroupCalculated) {
            Test.calculatePermissionSetGroup(permissionSetGroup.Id);
            permissionSetGroupCalculated = true;
        }

        List<PermissionSetAssignment> existingAssignments = [
        SELECT Id
        FROM PermissionSetAssignment
        WHERE AssigneeId = :userId
        AND PermissionSetGroupId = :permissionSetGroup.Id
        LIMIT 1
        ];

        if (!existingAssignments.isEmpty()) {
            return;
        }

        insert new PermissionSetAssignment(
            AssigneeId = userId,
            PermissionSetGroupId = permissionSetGroup.Id
        );
    }

    private static void insertOrderLineContact(
        String tasAddressId,
        String territoryId
    ) {
        insert new OrderLineContact__c(
            TASAddressId__c = tasAddressId,
            TerritoryID__c = territoryId
        );
    }

    private static String buildExpectedDuplicateKey(
        String tasAddressId,
        Id primaryContactId,
        String opportunityType,
        String territoryId
    ) {
        return (
            tasAddressId +
            String.valueOf(primaryContactId) +
            opportunityType +
            territoryId
        ).trim().toLowerCase();
    }

    private static Id getTestPrimaryContactId() {
        return (Id) (
            Schema.Contact.SObjectType.getDescribe().getKeyPrefix() + '000000000001'
        );
    }

    private static Id getTestOpportunityId() {
        return (Id) (
            Schema.Opportunity.SObjectType.getDescribe().getKeyPrefix() + '000000000001'
        );
    }

    private static User createUser(
        Id profileId,
        String username,
        String employeeNumber
    ) {
        String uniqueSuffix = String.valueOf(Math.abs(Crypto.getRandomInteger()));

        return new User(
            FirstName = 'Test',
            LastName = 'User',
            Alias = ('t' + uniqueSuffix).left(8),
            Email = username,
            Username = username,
            CommunityNickname = 'testuser' + uniqueSuffix,
            ProfileId = profileId,
            TimeZoneSidKey = 'America/New_York',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            EmployeeNumber__c = employeeNumber
        );
    }

    private static User getRunningUser() {
        return [
            SELECT Id
            FROM User
            WHERE Email LIKE 'runninguser%'
            LIMIT 1
        ];
    }

    private static void updateAccountOracleAddressId(String oracleAddressId) {
        Account acc = getTestAccount();
        acc.OracleAddressId__c = oracleAddressId;
        update acc;
    }

    private static Account createTestAccount() {
        Price_List__c priceList = new Price_List__c(
            Name = 'Test Price List',
            Price_List_Id__c = 'PL-DUPKEY-001'
        );
        insert priceList;

        Id prospectRecordTypeId = Schema.SObjectType.Account
            .getRecordTypeInfosByDeveloperName()
            .get('Prospect')
            .getRecordTypeId();

        Account acc = new Account(
            Name = 'Test Account',
            RecordTypeId = prospectRecordTypeId,
            CustomerClassCode__c = 'HC',
            OrgIDs__c = '83',
            Price_List__c = priceList.Id,
            BillingStreet = '123 Main St',
            BillingCity = 'Cleveland',
            BillingStateCode = 'OH',
            BillingCountryCode = 'US',
            BillingPostalCode = '44101',
            TAS_Retry__c = false
        );

        insert acc;
        return acc;
    }

    /**
     * @description validateForecastEligibleQuoteClosure returns early for null input and for
     *              Opportunities that are not moving to Closed Won.
     */
    @IsTest
    static void testValidateForecastQuoteClosureSkipsNonClosingRecords() {
        Opportunity openOpp = new Opportunity(
            Id = getTestOpportunityId(),
            Name = 'Open Opportunity',
            RecordTypeId = CAPITAL_RECORD_TYPE_ID,
            StageName = 'Discovery',
            CloseDate = Date.today().addDays(30)
        );
        Opportunity oldOpp = openOpp.clone(true, true, true, true);

        Test.startTest();
        OpportunityService.validateForecastEligibleQuoteClosure(null, null);
        OpportunityService.validateForecastEligibleQuoteClosure(
            new List<Opportunity>(),
            new Map<Id, Opportunity>()
        );
        OpportunityService.validateForecastEligibleQuoteClosure(
            new List<Opportunity>{ openOpp },
            new Map<Id, Opportunity>{ openOpp.Id => oldOpp }
        );
        Test.stopTest();

        System.assertEquals(
            false,
            openOpp.hasErrors(),
            'Opportunity that is not closing should not be blocked.'
        );
    }

    /**
     * @description Closing a Healthcare Sales Opportunity to Closed Won with no open
     *              forecast eligible quotes should not add an error.
     */
    @IsTest
    static void testValidateForecastQuoteClosureAllowsClosedWonWithoutOpenQuotes() {
        User runningUser = getRunningUser();

        // Record setup runs in the test context; the running user's profile cannot use the record type.
        Opportunity opp = createOpportunity(CAPITAL_RECORD_TYPE_ID, 'Discovery');
        Opportunity oldOpp = opp.clone(true, true, true, true);
        opp.StageName = 'Closed Won';

        System.runAs(runningUser) {
            Test.startTest();
            OpportunityService.validateForecastEligibleQuoteClosure(
                new List<Opportunity>{ opp },
                new Map<Id, Opportunity>{ opp.Id => oldOpp }
            );
            Test.stopTest();
        }

        System.assertEquals(
            false,
            opp.hasErrors(),
            'Closed Won should be allowed when no open forecast eligible quotes exist.'
        );
    }

    /**
     * @description Sales Ops / Contracting team members are only added when the Opportunity moves
     *              to Proposal, is an Instrument Processing record, and the IP Pillar is not Mobile.
     */
    @IsTest
    static void testAddSalesOpsContractTeamMembersSkipsIneligibleOpportunities() {
        Opportunity mobileOpp = new Opportunity(
            Id = fakeOpportunityId(1),
            RecordTypeId = getInstrumentProcessingRecordTypeId(),
            StageName = 'Proposal',
            IP_Pillar__c = 'Mobile'
        );
        Opportunity mobileOldOpp = mobileOpp.clone(true, true, true, true);
        mobileOldOpp.StageName = 'Discovery';

        Opportunity nonIpOpp = new Opportunity(
            Id = fakeOpportunityId(2),
            RecordTypeId = CAPITAL_RECORD_TYPE_ID,
            StageName = 'Proposal'
        );
        Opportunity nonIpOldOpp = nonIpOpp.clone(true, true, true, true);
        nonIpOldOpp.StageName = 'Discovery';

        Opportunity missingOldOpp = new Opportunity(
            Id = fakeOpportunityId(3),
            RecordTypeId = getInstrumentProcessingRecordTypeId(),
            StageName = 'Proposal'
        );

        Test.startTest();
        OpportunityService.addSalesOpsContractTeamMembers(null, null);
        OpportunityService.addSalesOpsContractTeamMembers(
            new List<Opportunity>(),
            new Map<Id, Opportunity>()
        );
        OpportunityService.addSalesOpsContractTeamMembers(
            new List<Opportunity>{ mobileOpp, nonIpOpp, missingOldOpp },
            new Map<Id, Opportunity>{
                mobileOpp.Id => mobileOldOpp,
                nonIpOpp.Id => nonIpOldOpp
            }
        );
        Test.stopTest();

        System.assertEquals(
            0,
            [
                SELECT COUNT()
                FROM OpportunityTeamMember
                WHERE OpportunityId IN :new Set<Id>{ mobileOpp.Id, nonIpOpp.Id }
                AND TeamMemberRole = 'Sales Ops / Contracting'
            ],
            'Mobile and non Instrument Processing Opportunities should not get Sales Ops team members.'
        );
    }

    /**
     * @description Moving an eligible Instrument Processing Opportunity to Proposal adds active
     *              Sales Ops / Contracting group members as Opportunity Team Members.
     */
    @IsTest
    static void testAddSalesOpsContractTeamMembersAddsActiveGroupMembers() {
        User runningUser = getRunningUser();

        // Group and User are setup objects. Opportunity DML has to happen in a later System.runAs.
        configureSalesOpsGroup(runningUser.Id);

        System.runAs(getTestRunner()) {
            Opportunity opp = createOpportunity(getInstrumentProcessingRecordTypeId(), 'Discovery');
            Opportunity oldOpp = opp.clone(true, true, true, true);
            opp.StageName = 'Proposal';

            Test.startTest();
            OpportunityService.addSalesOpsContractTeamMembers(
                new List<Opportunity>{ opp },
                new Map<Id, Opportunity>{ opp.Id => oldOpp }
            );
            Test.stopTest();

            List<OpportunityTeamMember> members = [
                SELECT UserId, TeamMemberRole
                FROM OpportunityTeamMember
                WHERE OpportunityId = :opp.Id
                AND UserId = :runningUser.Id
                AND TeamMemberRole = 'Sales Ops / Contracting'
            ];

            System.assertEquals(1, members.size(), 'One Sales Ops team member should be added.');
            System.assertEquals(runningUser.Id, members[0].UserId, 'Group member should be added to the team.');
            System.assertEquals(
                'Sales Ops / Contracting',
                members[0].TeamMemberRole,
                'Team member role should be Sales Ops / Contracting.'
            );
        }
    }

    /**
     * @description Covers duplicate-key rows that are skipped: no record type, an update with no
     *              old row, and a second territory row for the same TAS address.
     */
    @IsTest
    static void testPopulateDuplicateMatchKeySkipsUnmappedRecords() {
        String tasAddressId = 'ADDR-DUP-OLC';
        insert new List<OrderLineContact__c>{
            new OrderLineContact__c(TASAddressId__c = tasAddressId, TerritoryID__c = 'TERR-B'),
            new OrderLineContact__c(TASAddressId__c = tasAddressId, TerritoryID__c = 'TERR-A')
        };

        Account acc = getTestAccount();
        acc.OracleAddressId__c = tasAddressId;
        update acc;

        Id primaryContactId = getTestPrimaryContactId();
        Opportunity validOpp = new Opportunity(
            Name = 'Duplicate Territory Opportunity',
            RecordTypeId = CONSUMABLE_RECORD_TYPE_ID,
            AccountId = acc.Id,
            PrimaryContact__c = primaryContactId,
            Type = 'Renewal',
            StageName = 'Discovery',
            CloseDate = Date.today().addDays(30)
        );
        Opportunity noRecordType = new Opportunity(
            Name = 'No Record Type',
            AccountId = acc.Id,
            PrimaryContact__c = primaryContactId,
            Type = 'Renewal',
            StageName = 'Discovery',
            CloseDate = Date.today().addDays(30)
        );
        Opportunity missingOld = new Opportunity(
            Id = fakeOpportunityId(4),
            RecordTypeId = CONSUMABLE_RECORD_TYPE_ID,
            AccountId = acc.Id,
            PrimaryContact__c = primaryContactId,
            Type = 'Renewal'
        );

        Test.startTest();
        OpportunityService.populateDuplicateMatchKey(
            new List<Opportunity>{ validOpp, noRecordType },
            null
        );
        OpportunityService.populateDuplicateMatchKey(
            new List<Opportunity>{ missingOld },
            new Map<Id, Opportunity>()
        );
        Test.stopTest();

        System.assertEquals(
            buildExpectedDuplicateKey(tasAddressId, primaryContactId, 'Renewal', 'TERR-A'),
            validOpp.Duplicate_Match_Key__c,
            'The first territory for an address should be kept.'
        );
        System.assertEquals(null, noRecordType.Duplicate_Match_Key__c, 'A record without a record type should be skipped.');
        System.assertEquals(null, missingOld.Duplicate_Match_Key__c, 'An update with no old row should be skipped.');
    }

    /**
     * @description An open Forecast Eligible HC Sales quote blocks Closed Won.
     */
    @IsTest
    static void testValidateForecastQuoteClosureBlocksOpenForecastQuote() {
        Opportunity opp = createOpportunity(CAPITAL_RECORD_TYPE_ID, 'Discovery');
        opp.Pricebook2Id = Test.getStandardPricebookId();
        opp.BypassValidations__c = true;
        update opp;
    
        Opportunity oldOpp = [
            SELECT Id, IsClosed, IsWon, RecordTypeId
            FROM Opportunity
            WHERE Id = :opp.Id
        ];
    
        opp.StageName = 'Closed Won';
        update opp;
    
        Opportunity closingOpp = [
            SELECT Id, IsClosed, IsWon, RecordTypeId
            FROM Opportunity
            WHERE Id = :opp.Id
        ];
    
        Quote forecastQuote = new Quote(
            Name = 'Open Forecast Quote',
            OpportunityId = opp.Id,
            Pricebook2Id = Test.getStandardPricebookId(),
            RecordTypeId = Schema.SObjectType.Quote.getRecordTypeInfosByDeveloperName()
                .get('HCSales')
                .getRecordTypeId(),
            Status = 'Open',
            Forecast_Eligible__c = true,
            IsForecastIneligible__c = false,
            Quote_Total_Without_Freight__c = 1000,
            ExpirationDate = Date.today().addDays(30),
            QuoteType__c = 'Normal Quote'
        );
    
        TriggerHandler.bypass('QuoteTriggerHandler');
        try {
            Database.insert(forecastQuote, AccessLevel.SYSTEM_MODE);
            Database.update(
                new Quote(Id = forecastQuote.Id, Forecast_Eligible__c = true),
                AccessLevel.SYSTEM_MODE
            );
        } finally {
            TriggerHandler.clearBypass('QuoteTriggerHandler');
        }
    
        Opportunity missingOldOpp = new Opportunity(
            Id = fakeOpportunityId(9),
            RecordTypeId = CAPITAL_RECORD_TYPE_ID
        );
    
        Test.startTest();
        OpportunityService.validateForecastEligibleQuoteClosure(
            new List<Opportunity>{ closingOpp, missingOldOpp },
            new Map<Id, Opportunity>{ closingOpp.Id => oldOpp }
        );
        Test.stopTest();
    }

    /**
     * @description Executes the forecast-confidence and Closed Lost banner entry points.
     */
    @IsTest
    static void testStageBannerMethodsExecute() {
        Opportunity currentOpp = new Opportunity(
            Id = fakeOpportunityId(8),
            StageName = 'Closed Lost',
            ForecastConfidenceLevel__c = 'Upside'
        );
        Opportunity previousOpp = currentOpp.clone(true, true, true, true);
        previousOpp.StageName = 'Discovery';
        previousOpp.ForecastConfidenceLevel__c = 'Pipeline';

        Test.startTest();
        OpportunityService.stageForecastConfidencePropagateBanner(null, null);
        OpportunityService.stageClosedLostQuoteClosureBanner(null, null);
        OpportunityService.stageForecastConfidencePropagateBanner(
            new List<Opportunity>{ currentOpp },
            new Map<Id, Opportunity>{ currentOpp.Id => previousOpp }
        );
        OpportunityService.stageClosedLostQuoteClosureBanner(
            new List<Opportunity>{ currentOpp },
            new Map<Id, Opportunity>{ currentOpp.Id => previousOpp }
        );
        Test.stopTest();

        System.assertEquals(
            false,
            currentOpp.hasErrors(),
            'Banner staging should not add an Opportunity error.'
        );
    }

    /**
     * @description Covers nested group membership, notification send, an existing team member,
     *              an empty group, and an inactive group member.
     */
    @IsTest
    static void testAddSalesOpsContractTeamMembersCoversRemainingBranches() {
        User runningUser = getRunningUser();
        String suffix = String.valueOf(Math.abs(Crypto.getRandomInteger()));
        Profile healthcareSalesProfile = [SELECT Id FROM Profile WHERE Name = 'Healthcare Sales' LIMIT 1];
        User inactiveUser = createUser(
            healthcareSalesProfile.Id,
            'inactive' + suffix + '@test.com',
            'INA' + suffix
        );
        insert inactiveUser;
        inactiveUser.IsActive = false;
        update inactiveUser;

        UserRole salesRole = [SELECT Id FROM UserRole LIMIT 1];
        update new User(Id = runningUser.Id, UserRoleId = salesRole.Id);

        String nestedGroupName = ('TstNest' + suffix).left(40);
        String emptyGroupName = ('TstEmpty' + suffix).left(40);
        String inactiveGroupName = ('TstInact' + suffix).left(40);
        Group childGroup = newGroup('Child ' + suffix, 'TstChild' + suffix);
        Group parentGroup = newGroup('Parent ' + suffix, nestedGroupName);
        Group emptyGroup = newGroup('Empty ' + suffix, emptyGroupName);
        Group inactiveGroup = newGroup('Inactive ' + suffix, inactiveGroupName);
        insert new List<Group>{ childGroup, parentGroup, emptyGroup, inactiveGroup };
        insert new List<GroupMember>{
            new GroupMember(GroupId = childGroup.Id, UserOrGroupId = runningUser.Id),
            new GroupMember(GroupId = parentGroup.Id, UserOrGroupId = childGroup.Id),
            new GroupMember(GroupId = inactiveGroup.Id, UserOrGroupId = inactiveUser.Id)
        };

        System.runAs(getTestRunner()) {
            Opportunity opp = createOpportunity(getInstrumentProcessingRecordTypeId(), 'Discovery');
            Opportunity oldOpp = opp.clone(true, true, true, true);
            opp.StageName = 'Proposal';

            OpportunityService.publicGroupDeveloperName = nestedGroupName;
            OpportunityService.sendNotifications = true;

            Test.startTest();
            OpportunityService.addSalesOpsContractTeamMembers(
                new List<Opportunity>{ opp },
                new Map<Id, Opportunity>{ opp.Id => oldOpp }
            );
            OpportunityService.addSalesOpsContractTeamMembers(
                new List<Opportunity>{ opp },
                new Map<Id, Opportunity>{ opp.Id => oldOpp }
            );

            OpportunityService.publicGroupDeveloperName = emptyGroupName;
            OpportunityService.sendNotifications = false;
            Integer membersBeforeEmptyGroup = [
                SELECT COUNT()
                FROM OpportunityTeamMember
                WHERE OpportunityId = :opp.Id
            ];
            OpportunityService.addSalesOpsContractTeamMembers(
                new List<Opportunity>{ opp },
                new Map<Id, Opportunity>{ opp.Id => oldOpp }
            );

            OpportunityService.publicGroupDeveloperName = inactiveGroupName;
            OpportunityService.addSalesOpsContractTeamMembers(
                new List<Opportunity>{ opp },
                new Map<Id, Opportunity>{ opp.Id => oldOpp }
            );
            Test.stopTest();

            List<OpportunityTeamMember> members = [
                SELECT UserId
                FROM OpportunityTeamMember
                WHERE OpportunityId = :opp.Id
                AND UserId = :runningUser.Id
                AND TeamMemberRole = 'Sales Ops / Contracting'
            ];
            System.assertEquals(1, members.size(), 'Nested group user should be added once.');
            System.assertEquals(
                membersBeforeEmptyGroup,
                [SELECT COUNT() FROM OpportunityTeamMember WHERE OpportunityId = :opp.Id],
                'Empty and inactive groups should not add team members.'
            );
            System.assertEquals(
                0,
                [SELECT COUNT() FROM OpportunityTeamMember WHERE OpportunityId = :opp.Id AND UserId = :inactiveUser.Id],
                'Inactive group member should not be added.'
            );
        }
    }

    private static Group newGroup(String name, String developerName) {
        return new Group(
            Name = name.left(40),
            DeveloperName = developerName.left(40),
            Type = 'Regular'
        );
    }

    private static Id fakeOpportunityId(Integer suffix) {
        String digits = String.valueOf(suffix);
        return (Id) (
            Schema.Opportunity.SObjectType.getDescribe().getKeyPrefix()
            + '000000000000'.left(12 - digits.length())
            + digits
        );
    }

    private static Id getInstrumentProcessingRecordTypeId() {
        return Schema.SObjectType.Opportunity.getRecordTypeInfosByDeveloperName()
            .get('InstrumentProcessing')
            .getRecordTypeId();
    }

    private static Opportunity createOpportunity(Id recordTypeId, String stageName) {
        Opportunity opp = new Opportunity(
            Name = 'Test Opportunity ' + stageName,
            AccountId = getTestAccount().Id,
            RecordTypeId = recordTypeId,
            StageName = stageName,
            CloseDate = Date.today().addDays(30),
            Amount = 900.00,
            Probability = 10,
            BypassValidations__c = true
        );
        insert opp;
        return opp;
    }

    private static User getTestRunner() {
        return [SELECT Id FROM User WHERE Id = :UserInfo.getUserId()];
    }

    /**
     * @description Creates a Regular public group containing the given user and points
     *              OpportunityService at it. Call this before any non-setup DML.
     *              Notifications are disabled for these tests.
     */
    private static void configureSalesOpsGroup(Id userId) {
        UserRole salesRole = [SELECT Id FROM UserRole LIMIT 1];
        update new User(Id = userId, UserRoleId = salesRole.Id);

        String uniqueSuffix = String.valueOf(Math.abs(Crypto.getRandomInteger()));
        String groupDeveloperName = ('TstSalesOps' + uniqueSuffix).left(40);

        Group salesOpsGroup = new Group(
            Name = ('Test Sales Ops ' + uniqueSuffix).left(40),
            DeveloperName = groupDeveloperName,
            Type = 'Regular'
        );
        insert salesOpsGroup;

        insert new GroupMember(
            GroupId = salesOpsGroup.Id,
            UserOrGroupId = userId
        );

        OpportunityService.publicGroupDeveloperName = groupDeveloperName;
        OpportunityService.sendNotifications = false;
    }

    private static Account getTestAccount() {
        return [
            SELECT Id,
                   OracleAddressId__c
            FROM Account
            WHERE Name = 'Test Account'
            LIMIT 1
        ];
    }

}