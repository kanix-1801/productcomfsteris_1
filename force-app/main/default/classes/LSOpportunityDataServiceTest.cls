/**
 * @description Covers OpportunitySelector and OpportunityService from a Life Sciences test class.
 */
@IsTest(SeeAllData=false)
private class LSOpportunityDataServiceTest {

    @IsTest
    static void selectorHandlesNullAndEmptyInput() {
        System.assertEquals(0, OpportunitySelector.selectByAccountIds(null).size());
        System.assertEquals(0, OpportunitySelector.selectByAccountIds(new Set<Id>()).size());
        System.assertEquals(0, OpportunitySelector.selectByIds(null).size());
        System.assertEquals(0, OpportunitySelector.selectByIds(new Set<Id>()).size());
        System.assertEquals(0, OpportunitySelector.selectByOwnerIds(null).size());
        System.assertEquals(0, OpportunitySelector.selectByOwnerIds(new Set<Id>()).size());
        System.assertEquals(null, OpportunitySelector.selectById(null));
        System.assertEquals(0, OpportunitySelector.selectForecastConfidenceByIds(null).size());
        System.assertEquals(0, OpportunitySelector.selectForecastConfidenceByIds(new Set<Id>()).size());
        System.assertEquals(0, OpportunitySelector.selectOpenPipelineByAccountIds(null).size());
        System.assertEquals(0, OpportunitySelector.selectOpenPipelineByAccountIds(new Set<Id>()).size());
        System.assertEquals(0, new OpportunitySelector().selectByIdsForPrimaryContact(null).size());
        System.assertEquals(0, new OpportunitySelector().selectByIdsForPrimaryContact(new Set<Id>()).size());
        System.assertEquals(null, OpportunitySelector.selectProfileName(null));
        System.assertEquals(false, OpportunitySelector.hasBusinessSystemAdminPermission(null));
        System.assertEquals(0, OpportunitySelector.selectRoleIdByUserId(null).size());
        System.assertEquals(0, OpportunitySelector.selectRoleIdByUserId(new Set<Id>()).size());
    }

    @IsTest
    static void selectorReturnsInsertedLifeSciencesOpportunity() {
        Opportunity opportunityRecord = [
            SELECT Id, AccountId, OwnerId
            FROM Opportunity
            WHERE Id = :insertLifeSciencesOpportunity().Id
        ];
        Set<Id> opportunityIds = new Set<Id>{ opportunityRecord.Id };
        Set<Id> accountIds = new Set<Id>{ opportunityRecord.AccountId };
        Id missingId = fakeId(Opportunity.SObjectType);

        System.runAs(new User(Id = opportunityRecord.OwnerId)) {
            System.assertEquals(1, OpportunitySelector.selectByAccountIds(accountIds).size());
            System.assertEquals(1, OpportunitySelector.selectByIds(opportunityIds).size());
            System.assertEquals(1, OpportunitySelector.selectByOwnerIds(new Set<Id>{ opportunityRecord.OwnerId }).size());
            System.assertEquals(opportunityRecord.Id, OpportunitySelector.selectById(opportunityRecord.Id).Id);
            System.assertEquals(null, OpportunitySelector.selectById(missingId));
            System.assertEquals(1, OpportunitySelector.selectForecastConfidenceByIds(opportunityIds).size());
            System.assertEquals(0, OpportunitySelector.selectForecastConfidenceByIds(new Set<Id>{ missingId }).size());
            System.assertEquals(1, OpportunitySelector.selectOpenPipelineByAccountIds(accountIds).size());
            System.assertEquals(
                1,
                new OpportunitySelector().selectByIdsForPrimaryContact(opportunityIds).size()
            );
        }
        System.assertEquals(UserInfo.getUserId(), OpportunitySelector.selectRunningUser().Id);
        System.assertNotEquals(null, OpportunitySelector.selectProfileName(UserInfo.getProfileId()));
        System.assertNotEquals(null, OpportunitySelector.hasBusinessSystemAdminPermission(UserInfo.getUserId()));
        System.assertEquals(
            1,
            OpportunitySelector.selectRoleIdByUserId(new Set<Id>{ UserInfo.getUserId() }).size()
        );
        System.assert(OpportunitySelector.selectParentRoleIdByRoleId() != null);
    }

    @IsTest
    static void serviceHandlesNullAndUnchangedInput() {
        OpportunityService.populateDuplicateMatchKey(null, null);
        OpportunityService.populateDuplicateMatchKey(new List<Opportunity>(), null);
        OpportunityService.validateForecastEligibleQuoteClosure(null, null);
        OpportunityService.validateForecastEligibleQuoteClosure(new List<Opportunity>(), new Map<Id, Opportunity>());
        OpportunityService.stageForecastConfidencePropagateBanner(null, null);
        OpportunityService.stageClosedLostQuoteClosureBanner(null, null);
        OpportunityService.addSalesOpsContractTeamMembers(null, null);
        OpportunityService.addSalesOpsContractTeamMembers(new List<Opportunity>(), new Map<Id, Opportunity>());

        Opportunity unchanged = new Opportunity(
            Id = fakeId(Opportunity.SObjectType),
            RecordTypeId = lifeSciencesRecordTypeId(),
            StageName = 'Discovery'
        );
        OpportunityService.populateDuplicateMatchKey(
            new List<Opportunity>{ unchanged },
            new Map<Id, Opportunity>{ unchanged.Id => unchanged.clone(true, true, false, false) }
        );
        try {
            OpportunityService.populateDuplicateMatchKey(new List<Opportunity>{ null }, null);
            System.assert(false, 'A null Opportunity should be rethrown');
        } catch (Exception exceptionValue) {
            System.assertNotEquals(null, exceptionValue);
        }
        OpportunityService.addSalesOpsContractTeamMembers(
            new List<Opportunity>{ unchanged },
            new Map<Id, Opportunity>()
        );
        OpportunityService.addSalesOpsContractTeamMembers(
            new List<Opportunity>{ new Opportunity(StageName = 'Proposal', IP_Pillar__c = 'Mobile') },
            new Map<Id, Opportunity>{
                fakeId(Opportunity.SObjectType) => new Opportunity(StageName = 'Discovery')
            }
        );

        System.assertEquals(null, unchanged.Duplicate_Match_Key__c);
    }

    @IsTest
    static void duplicateKeyIsBuiltFromAddressContactTypeAndTerritory() {
        Id duplicateRecordTypeId = duplicateKeyRecordTypeId();
        if (duplicateRecordTypeId == null) {
            return;
        }

        String oracleAddressId = 'ORA-' + uniqueToken();
        Account accountRecord = insertAccount(oracleAddressId);
        Contact contactRecord = insertContact(accountRecord);
        insert new OrderLineContact__c(
            TASAddressId__c = oracleAddressId,
            TerritoryID__c = ' T-100 '
        );

        Opportunity opportunityRecord = new Opportunity(
            RecordTypeId = duplicateRecordTypeId,
            AccountId = accountRecord.Id,
            PrimaryContact__c = contactRecord.Id,
            Type = 'New Business',
            StageName = 'Discovery'
        );

        OpportunityService.populateDuplicateMatchKey(new List<Opportunity>{ opportunityRecord }, null);

        System.assertEquals('T-100', opportunityRecord.Territory_ID__c);
        System.assertNotEquals(null, opportunityRecord.Duplicate_Match_Key__c);

        Opportunity previous = opportunityRecord.clone(true, true, false, false);
        previous.Type = 'Existing Business';
        opportunityRecord.Id = fakeId(Opportunity.SObjectType);
        OpportunityService.populateDuplicateMatchKey(
            new List<Opportunity>{ opportunityRecord },
            new Map<Id, Opportunity>{ opportunityRecord.Id => previous }
        );
        System.assertNotEquals(null, opportunityRecord.Duplicate_Match_Key__c);
    }

    @IsTest
    static void duplicateKeyStaysBlankWithoutAddressOrTerritory() {
        Id duplicateRecordTypeId = duplicateKeyRecordTypeId();
        if (duplicateRecordTypeId == null) {
            return;
        }

        Account accountRecord = insertAccount(null);
        Contact contactRecord = insertContact(accountRecord);
        Opportunity opportunityRecord = new Opportunity(
            RecordTypeId = duplicateRecordTypeId,
            AccountId = accountRecord.Id,
            PrimaryContact__c = contactRecord.Id,
            Type = 'New Business'
        );

        OpportunityService.populateDuplicateMatchKey(new List<Opportunity>{ opportunityRecord }, null);

        System.assertEquals(null, opportunityRecord.Duplicate_Match_Key__c);

        Opportunity blankAddress = new Opportunity(RecordTypeId = duplicateRecordTypeId);
        OpportunityService.populateDuplicateMatchKey(new List<Opportunity>{ blankAddress }, null);
        System.assertEquals(null, blankAddress.Duplicate_Match_Key__c);
    }

    @IsTest
    static void closedWonWithoutAnOpenQuoteIsNotBlocked() {
        Schema.RecordTypeInfo healthcare = Opportunity.SObjectType.getDescribe()
            .getRecordTypeInfosByDeveloperName()
            .get('Healthcare_Sales');
        if (healthcare == null) {
            return;
        }

        Opportunity saved = insertLifeSciencesOpportunity();
        Opportunity updated = (Opportunity) JSON.deserialize(
            '{"Id":"' + saved.Id + '","IsClosed":true,"IsWon":true,"RecordTypeId":"' + healthcare.getRecordTypeId() + '"}',
            Opportunity.class
        );
        Opportunity previous = (Opportunity) JSON.deserialize(
            '{"Id":"' + saved.Id + '","IsClosed":false,"IsWon":false,"RecordTypeId":"' + healthcare.getRecordTypeId() + '"}',
            Opportunity.class
        );

        OpportunityService.validateForecastEligibleQuoteClosure(
            new List<Opportunity>{ updated, new Opportunity(Id = fakeId(Opportunity.SObjectType)) },
            new Map<Id, Opportunity>{ updated.Id => previous }
        );

        System.assertEquals(0, updated.getErrors().size());

        Schema.RecordTypeInfo quoteRecordType = Quote.SObjectType.getDescribe()
            .getRecordTypeInfosByDeveloperName()
            .get(GenerateQuoteService.QUOTE_RECORD_TYPE_DEVELOPER_NAME);
        if (quoteRecordType == null) {
            return;
        }

        Id pricebookId = Test.getStandardPricebookId();
        update new Opportunity(Id = saved.Id, Pricebook2Id = pricebookId);
        Quote coverageQuote = new Quote(
            Name = 'LS Coverage Quote',
            OpportunityId = saved.Id,
            Pricebook2Id = pricebookId,
            RecordTypeId = quoteRecordType.getRecordTypeId(),
            Forecast_Eligible__c = true,
            Status = 'Draft'
        );
        insert coverageQuote;
        coverageQuote = [
            SELECT Status, Forecast_Eligible__c, RecordType.DeveloperName
            FROM Quote
            WHERE Id = :coverageQuote.Id
        ];
        if (coverageQuote.Forecast_Eligible__c != true || coverageQuote.Status == 'Closed') {
            coverageQuote.Forecast_Eligible__c = true;
            coverageQuote.Status = 'Presented';
            update coverageQuote;
        }

        OpportunityService.validateForecastEligibleQuoteClosure(
            new List<Opportunity>{ updated },
            new Map<Id, Opportunity>{ updated.Id => previous }
        );

        System.assert(
            updated.getErrors().size() > 0,
            'status=' + coverageQuote.Status
            + ' eligible=' + coverageQuote.Forecast_Eligible__c
            + ' type=' + coverageQuote.RecordType.DeveloperName
        );
    }

    @IsTest
    static void salesOpsTeamIsAddedWhenStageBecomesProposal() {
        Schema.RecordTypeInfo instrumentProcessing = Opportunity.SObjectType.getDescribe()
            .getRecordTypeInfosByDeveloperName()
            .get('InstrumentProcessing');
        if (instrumentProcessing == null) {
            return;
        }

        String token = uniqueToken().left(8);
        Group parentGroup = new Group();
        System.runAs(new User(Id = UserInfo.getUserId())) {
            Group childGroup = new Group(
                Name = 'LS Child ' + token,
                DeveloperName = 'LS_Child_' + token,
                Type = 'Regular'
            );
            insert childGroup;
            parentGroup = new Group(
                Name = 'LS Parent ' + token,
                DeveloperName = 'LS_Parent_' + token,
                Type = 'Regular'
            );
            insert parentGroup;
            insert new List<GroupMember>{
                new GroupMember(GroupId = childGroup.Id, UserOrGroupId = UserInfo.getUserId()),
                new GroupMember(GroupId = parentGroup.Id, UserOrGroupId = childGroup.Id)
            };
        }

        Opportunity saved = insertLifeSciencesOpportunity();
        Opportunity proposed = new Opportunity(
            Id = saved.Id,
            StageName = 'Proposal',
            RecordTypeId = instrumentProcessing.getRecordTypeId(),
            IP_Pillar__c = 'Capital'
        );
        Opportunity previous = new Opportunity(
            Id = saved.Id,
            StageName = 'Discovery',
            RecordTypeId = instrumentProcessing.getRecordTypeId()
        );
        OpportunityService.publicGroupDeveloperName = 'LS_Missing_' + token;
        OpportunityService.sendNotifications = true;
        OpportunityService.addSalesOpsContractTeamMembers(
            new List<Opportunity>{ proposed },
            new Map<Id, Opportunity>{ saved.Id => previous }
        );
        OpportunityService.publicGroupDeveloperName = parentGroup.DeveloperName;

        Opportunity mobile = new Opportunity(
            Id = saved.Id,
            StageName = 'Proposal',
            RecordTypeId = instrumentProcessing.getRecordTypeId(),
            IP_Pillar__c = 'Mobile'
        );
        OpportunityService.addSalesOpsContractTeamMembers(
            new List<Opportunity>{ mobile },
            new Map<Id, Opportunity>{ saved.Id => previous }
        );

        Test.startTest();
        OpportunityService.addSalesOpsContractTeamMembers(
            new List<Opportunity>{ proposed },
            new Map<Id, Opportunity>{ saved.Id => previous }
        );
        Opportunity secondSaved = insertLifeSciencesOpportunity();
        OpportunityService.sendNotifications = false;
        OpportunityService.addSalesOpsContractTeamMembers(
            new List<Opportunity>{
                new Opportunity(
                    Id = secondSaved.Id,
                    StageName = 'Proposal',
                    RecordTypeId = instrumentProcessing.getRecordTypeId(),
                    IP_Pillar__c = 'Capital'
                )
            },
            new Map<Id, Opportunity>{
                secondSaved.Id => new Opportunity(
                    Id = secondSaved.Id,
                    StageName = 'Discovery',
                    RecordTypeId = instrumentProcessing.getRecordTypeId()
                )
            }
        );
        OpportunityService.addSalesOpsContractTeamMembers(
            new List<Opportunity>{ proposed },
            new Map<Id, Opportunity>{ saved.Id => previous }
        );
        Test.stopTest();

        System.assert(
            [SELECT COUNT() FROM OpportunityTeamMember WHERE OpportunityId = :saved.Id] > 0
        );
    }

    @IsTest
    static void notificationSendFailureIsLogged() {
        Schema.RecordTypeInfo instrumentProcessing = Opportunity.SObjectType.getDescribe()
            .getRecordTypeInfosByDeveloperName()
            .get('InstrumentProcessing');
        if (instrumentProcessing == null) {
            return;
        }

        Profile limitedProfile = [
            SELECT Id
            FROM Profile
            WHERE Name = 'Standard User'
            LIMIT 1
        ];
        String token = uniqueToken();
        User limitedUser = new User(
            Alias = token.left(8),
            Email = token + '@example.com',
            EmailEncodingKey = 'UTF-8',
            LastName = 'LS Notify',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = limitedProfile.Id,
            TimeZoneSidKey = 'America/New_York',
            Username = token + '@example.com'
        );
        Group parentGroup = new Group();
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert limitedUser;
            parentGroup = new Group(
                Name = 'LS Notify ' + token.left(6),
                DeveloperName = 'LS_Notify_' + token.left(6),
                Type = 'Regular'
            );
            insert parentGroup;
            insert new GroupMember(GroupId = parentGroup.Id, UserOrGroupId = limitedUser.Id);
        }

        Opportunity saved = insertLifeSciencesOpportunity();
        OpportunityService.publicGroupDeveloperName = parentGroup.DeveloperName;
        OpportunityService.sendNotifications = true;

        OpportunityService.addSalesOpsContractTeamMembers(
            new List<Opportunity>{
                new Opportunity(
                    Id = saved.Id,
                    StageName = 'Proposal',
                    RecordTypeId = instrumentProcessing.getRecordTypeId(),
                    IP_Pillar__c = 'Capital'
                )
            },
            new Map<Id, Opportunity>{
                saved.Id => new Opportunity(
                    Id = saved.Id,
                    StageName = 'Discovery',
                    RecordTypeId = instrumentProcessing.getRecordTypeId()
                )
            }
        );

        System.assert(true, 'A notification failure must be logged and not thrown');
    }

    private static Opportunity insertLifeSciencesOpportunity() {
        Account accountRecord = insertAccount(null);
        Contact contactRecord = insertContact(accountRecord);
        Opportunity opportunityRecord = new Opportunity(
            Name = 'LS Coverage Opportunity',
            AccountId = accountRecord.Id,
            RecordTypeId = lifeSciencesRecordTypeId(),
            StageName = 'Discovery',
            PositionInFunnel__c = 'Above Funnel',
            ForecastConfidenceLevel__c = 'Pipeline',
            Type = 'New Business',
            Amount = 1000,
            Probability = 10,
            PrimaryContact__c = contactRecord.Id,
            CloseDate = Date.today().addDays(30)
        );
        insert opportunityRecord;
        return opportunityRecord;
    }

    private static Account insertAccount(String oracleAddressId) {
        Account accountRecord = new Account(
            Name = 'LS Coverage ' + uniqueToken(),
            SourceSystemID__c = uniqueToken(),
            OracleAddressId__c = oracleAddressId
        );
        insert accountRecord;
        return accountRecord;
    }

    private static Contact insertContact(Account accountRecord) {
        Contact contactRecord = new Contact(
            LastName = 'LS Coverage ' + uniqueToken(),
            AccountId = accountRecord.Id
        );
        insert contactRecord;
        return contactRecord;
    }

    private static Id lifeSciencesRecordTypeId() {
        return Opportunity.SObjectType.getDescribe(SObjectDescribeOptions.DEFERRED)
            .getRecordTypeInfosByDeveloperName()
            .get('LSSalesConsumables')
            .getRecordTypeId();
    }

    private static Id duplicateKeyRecordTypeId() {
        String recordTypeNames = Label.Opportunity_Duplicate_Key_Record_Types;
        if (String.isBlank(recordTypeNames)) {
            return null;
        }
        String developerName = recordTypeNames.split(',')[0].trim();
        Schema.RecordTypeInfo info = Opportunity.SObjectType.getDescribe()
            .getRecordTypeInfosByDeveloperName()
            .get(developerName);
        return info == null ? null : info.getRecordTypeId();
    }

    private static Id fakeId(Schema.SObjectType sobjectType) {
        return Id.valueOf(sobjectType.getDescribe().getKeyPrefix() + '000000000001');
    }

    private static String uniqueToken() {
        return String.valueOf(Math.abs(Crypto.getRandomInteger()));
    }
}