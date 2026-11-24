/**
 * @description #GC-3598 Unit tests for DealerReferencePickerController.
 */
@IsTest(SeeAllData=false)
private class DealerReferencePickerControllerTest {
    private static final String DEALER_KEY = 'references';

    @TestSetup
    static void setupData() {
        User dealer = createPortalDealer();
        System.runAs(dealer) {
            insert new List<DealerReferenceValue__c>{
                new DealerReferenceValue__c(Name = 'Alpha Architect', Type__c = 'Architect'),
                new DealerReferenceValue__c(Name = 'Beta Competitor', Type__c = 'Competitor'),
                new DealerReferenceValue__c(Name = 'Gamma Competitor', Type__c = 'Competitor')
            };
        }
    }

    private static User dealer() {
        return [
            SELECT Id, Contact.AccountId
            FROM User
            WHERE Username = :portalDealerUsername()
            LIMIT 1
        ];
    }

    @IsTest
    static void search_returnsMatchingRowsForType() {
        Test.startTest();
        List<DealerReferencePickerController.Option> results;
        System.runAs(dealer()) {
            results = DealerReferencePickerController.search('Competitor', 'Beta');
        }
        Test.stopTest();

        System.assertEquals(1, results.size(), 'Expected one competitor match');
        System.assertEquals('Beta Competitor', results[0].name);
    }

    @IsTest
    static void search_blankTerm_returnsRowsForType() {
        Test.startTest();
        List<DealerReferencePickerController.Option> results;
        System.runAs(dealer()) {
            results = DealerReferencePickerController.search('Competitor', null);
        }
        Test.stopTest();

        System.assertEquals(2, results.size(), 'Expected both competitor rows');
    }

    @IsTest
    static void create_insertsNewValue() {
        Test.startTest();
        DealerReferencePickerController.Option created;
        System.runAs(dealer()) {
            created = DealerReferencePickerController.create('EndCustomer', 'New Hospital');
        }
        Test.stopTest();

        System.assertNotEquals(null, created.id);
        System.assertEquals('New Hospital', created.name);
        System.assertEquals(
            1,
            [SELECT COUNT() FROM DealerReferenceValue__c WHERE Type__c = 'EndCustomer' AND Name = 'New Hospital']
        );
    }

    @IsTest
    static void create_returnsExistingWhenDuplicate() {
        Test.startTest();
        DealerReferencePickerController.Option created;
        System.runAs(dealer()) {
            created = DealerReferencePickerController.create('Architect', 'Alpha Architect');
        }
        Test.stopTest();

        System.assertEquals(
            [SELECT Id FROM DealerReferenceValue__c WHERE Name = 'Alpha Architect' LIMIT 1].Id,
            created.id
        );
        System.assertEquals(
            1,
            [SELECT COUNT() FROM DealerReferenceValue__c WHERE Type__c = 'Architect' AND Name = 'Alpha Architect']
        );
    }

    @IsTest
    static void create_blankName_throws() {
        Boolean threw = false;
        try {
            System.runAs(dealer()) {
                DealerReferencePickerController.create('Architect', '  ');
            }
        } catch (AuraHandledException ex) {
            threw = true;
        }
        System.assertEquals(true, threw, 'Blank name should throw');
    }

    @IsTest
    static void resolve_createsPendingNameAndKeepsExistingId() {
        Id existingId = [SELECT Id FROM DealerReferenceValue__c WHERE Name = 'Alpha Architect' LIMIT 1].Id;
        DealerReferencePickerController.ResolveRequest request = new DealerReferencePickerController.ResolveRequest();
        request.endCustomerId = 'pending:' + EncodingUtil.urlEncode('City Hospital', 'UTF-8');
        request.architectId = existingId;
        request.competitorIds = 'pending:' + EncodingUtil.urlEncode('New Rival', 'UTF-8');

        Test.startTest();
        List<DealerReferencePickerController.ResolveResult> results;
        System.runAs(dealer()) {
            results = DealerReferencePickerController.resolve(new List<DealerReferencePickerController.ResolveRequest>{ request });
        }
        Test.stopTest();

        System.assertEquals(existingId, results[0].architectId);
        DealerReferenceValue__c hospital = [
            SELECT Id FROM DealerReferenceValue__c WHERE Type__c = 'EndCustomer' AND Name = 'City Hospital' LIMIT 1
        ];
        System.assertEquals(hospital.Id, results[0].endCustomerId);
        DealerReferenceValue__c rival = [
            SELECT Id FROM DealerReferenceValue__c WHERE Type__c = 'Competitor' AND Name = 'New Rival' LIMIT 1
        ];
        System.assertEquals(rival.Id, results[0].competitorId);
    }

    @IsTest
    static void resolve_reusesExistingName() {
        DealerReferencePickerController.ResolveRequest request = new DealerReferencePickerController.ResolveRequest();
        request.architectId = 'pending:' + EncodingUtil.urlEncode('Alpha Architect', 'UTF-8');

        Test.startTest();
        List<DealerReferencePickerController.ResolveResult> results;
        System.runAs(dealer()) {
            results = DealerReferencePickerController.resolve(new List<DealerReferencePickerController.ResolveRequest>{ request });
        }
        Test.stopTest();

        System.assertEquals(
            [SELECT Id FROM DealerReferenceValue__c WHERE Name = 'Alpha Architect' LIMIT 1].Id,
            results[0].architectId
        );
        System.assertEquals(
            1,
            [SELECT COUNT() FROM DealerReferenceValue__c WHERE Type__c = 'Architect' AND Name = 'Alpha Architect']
        );
    }

    @IsTest
    static void saveOpportunityReferences_createsOnceAndUpdatesTwoOpportunities() {
        User portalUser = dealer();
        List<Opportunity> opportunities = new List<Opportunity>();
        System.runAs(portalUser) {
            opportunities.add(dealerOpportunity(portalUser.Contact.AccountId, 'Dealer One', 30));
            opportunities.add(dealerOpportunity(portalUser.Contact.AccountId, 'Dealer Two', 40));
            insert opportunities;
        }
        Id architectId = [SELECT Id FROM DealerReferenceValue__c WHERE Name = 'Alpha Architect' LIMIT 1].Id;

        DealerReferencePickerController.ReferenceUpdate first = new DealerReferencePickerController.ReferenceUpdate();
        first.opportunityId = opportunities[0].Id;
        first.architectToken = architectId;
        first.architectName = 'Alpha Architect';
        first.endCustomerToken = 'pending:' + EncodingUtil.urlEncode('Shared Hospital', 'UTF-8');
        first.endCustomerName = 'Shared Hospital';
        first.competitorTokens = 'pending:' + EncodingUtil.urlEncode('Shared Rival', 'UTF-8');
        first.competitorNames = 'Shared Rival';

        DealerReferencePickerController.ReferenceUpdate second = new DealerReferencePickerController.ReferenceUpdate();
        second.opportunityId = opportunities[1].Id;
        second.architectToken = 'pending:' + EncodingUtil.urlEncode('Shared Hospital', 'UTF-8');
        second.architectName = 'Shared Hospital';
        second.endCustomerToken = 'pending:' + EncodingUtil.urlEncode('Shared Hospital', 'UTF-8');
        second.endCustomerName = 'Shared Hospital';

        Test.startTest();
        System.runAs(dealer()) {
            DealerReferencePickerController.saveReferenceUpdates(new List<DealerReferencePickerController.ReferenceUpdate>{
                first,
                second
            });
        }
        Test.stopTest();

        System.assertEquals(
            1,
            [SELECT COUNT() FROM DealerReferenceValue__c WHERE Type__c = 'EndCustomer' AND Name = 'Shared Hospital']
        );
        Id hospitalId = [SELECT Id FROM DealerReferenceValue__c WHERE Type__c = 'EndCustomer' AND Name = 'Shared Hospital' LIMIT 1].Id;
        Map<Id, Opportunity> saved = new Map<Id, Opportunity>([
            SELECT EndCustomerName__c, ArchitectName__c, DealerCompetitors__c
            FROM Opportunity
            WHERE Id IN :opportunities
        ]);
        System.assertEquals('Shared Hospital', saved.get(opportunities[0].Id).EndCustomerName__c);
        System.assertEquals('Alpha Architect', saved.get(opportunities[0].Id).ArchitectName__c);
        System.assertEquals('Shared Rival', saved.get(opportunities[0].Id).DealerCompetitors__c);
        System.assertEquals('Shared Hospital', saved.get(opportunities[1].Id).EndCustomerName__c);
        System.assertEquals('Shared Hospital', saved.get(opportunities[1].Id).ArchitectName__c);

        DealerReferencePickerController.OpportunityReferences loaded;
        System.runAs(dealer()) {
            loaded = DealerReferencePickerController.loadOpportunityReferences(opportunities[0].Id);
        }
        System.assertEquals('Shared Hospital', loaded.endCustomerName);
        System.assertEquals(String.valueOf(hospitalId), loaded.endCustomerId);
        System.assertEquals('Alpha Architect', loaded.architectName);
        System.assertEquals(String.valueOf(architectId), loaded.architectId);
        System.assertEquals('Shared Rival', loaded.competitorNames);
    }

    @IsTest
    static void save_textareaCompetitors_storesSemicolonSeparatedNames() {
        User portalUser = dealer();
        Opportunity opportunity;
        System.runAs(portalUser) {
            opportunity = dealerOpportunity(portalUser.Contact.AccountId, 'Competitor Text', 15);
            insert opportunity;
        }

        DealerReferencePickerController.ReferenceUpdate updateRow = new DealerReferencePickerController.ReferenceUpdate();
        updateRow.opportunityId = opportunity.Id;
        updateRow.competitorNames = 'Beta Competitor\nNew Rival; Beta Competitor';

        Test.startTest();
        System.runAs(dealer()) {
            DealerReferencePickerController.saveReferenceUpdates(
                new List<DealerReferencePickerController.ReferenceUpdate>{ updateRow }
            );
        }
        Test.stopTest();

        Opportunity saved = [
            SELECT DealerCompetitors__c
            FROM Opportunity
            WHERE Id = :opportunity.Id
        ];
        System.assertEquals('Beta Competitor;New Rival', saved.DealerCompetitors__c);
        System.assertEquals(
            1,
            [SELECT COUNT() FROM DealerReferenceValue__c WHERE Type__c = 'Competitor' AND Name = 'Beta Competitor']
        );
        System.assertEquals(
            1,
            [SELECT COUNT() FROM DealerReferenceValue__c WHERE Type__c = 'Competitor' AND Name = 'New Rival']
        );
    }

    @IsTest
    static void resolve_textareaCompetitors_returnsSemicolonNames() {
        DealerReferencePickerController.ResolveRequest request = new DealerReferencePickerController.ResolveRequest();
        request.competitorNames = 'Acme\nBeta Competitor; Acme';

        Test.startTest();
        List<DealerReferencePickerController.ResolveResult> results;
        System.runAs(dealer()) {
            results = DealerReferencePickerController.resolve(new List<DealerReferencePickerController.ResolveRequest>{ request });
        }
        Test.stopTest();

        System.assertEquals('Acme;Beta Competitor', results[0].competitorNames);
        System.assertEquals(
            1,
            [SELECT COUNT() FROM DealerReferenceValue__c WHERE Type__c = 'Competitor' AND Name = 'Acme']
        );
        System.assertEquals(
            1,
            [SELECT COUNT() FROM DealerReferenceValue__c WHERE Type__c = 'Competitor' AND Name = 'Beta Competitor']
        );
    }

    @IsTest
    static void load_returnsStoredName() {
        User portalUser = dealer();
        Opportunity opportunity;
        DealerReferencePickerController.OpportunityReferences loaded;
        System.runAs(portalUser) {
            opportunity = dealerOpportunity(portalUser.Contact.AccountId, 'Named Dealer', 20);
            opportunity.EndCustomerName__c = 'Rahul';
            insert opportunity;
            Test.startTest();
            loaded = DealerReferencePickerController.loadOpportunityReferences(opportunity.Id);
            Test.stopTest();
        }

        System.assertEquals('Rahul', loaded.endCustomerName);
        System.assert(loaded.endCustomerId.startsWith('pending:'), 'Stored name should be shown on the picker');
    }

    @IsTest
    static void search_stripsWildcardCharacters() {
        Test.startTest();
        List<DealerReferencePickerController.Option> results;
        System.runAs(dealer()) {
            results = DealerReferencePickerController.search('Competitor', '%Beta_');
        }
        Test.stopTest();

        System.assertEquals(1, results.size(), 'Wildcard characters are removed before the name search');
        System.assertEquals('Beta Competitor', results[0].name);
    }

    @IsTest
    static void create_trimsTheName() {
        Test.startTest();
        DealerReferencePickerController.Option created;
        System.runAs(dealer()) {
            created = DealerReferencePickerController.create('EndCustomer', '  Trim Hospital  ');
        }
        Test.stopTest();

        System.assertEquals('Trim Hospital', created.name);
    }

    @IsTest
    static void resolve_handlesBlankDuplicateAndRemainingTypes() {
        Id architectId = [SELECT Id FROM DealerReferenceValue__c WHERE Name = 'Alpha Architect' LIMIT 1].Id;
        String hospital = 'pending:' + EncodingUtil.urlEncode('Cache Hospital', 'UTF-8');
        String rival = 'pending:' + EncodingUtil.urlEncode('Cache Rival', 'UTF-8');
        DealerReferencePickerController.ResolveRequest first = new DealerReferencePickerController.ResolveRequest();
        first.mainContractorId = hospital;
        first.equipmentPlannerId = 'pending:' + EncodingUtil.urlEncode('Cache Planner', 'UTF-8');
        first.competitorIds = rival + ';;' + rival + ';pending:%20;' + architectId;
        DealerReferencePickerController.ResolveRequest second = new DealerReferencePickerController.ResolveRequest();
        second.architectId = architectId;
        second.mainContractorId = hospital;
        second.competitorNames = 'Beta;;Gamma Rival';

        Test.startTest();
        List<DealerReferencePickerController.ResolveResult> results;
        System.runAs(dealer()) {
            results = DealerReferencePickerController.resolve(new List<DealerReferencePickerController.ResolveRequest>{
                first,
                second
            });
        }
        Test.stopTest();

        System.assertEquals(
            [SELECT Id FROM DealerReferenceValue__c WHERE Type__c = 'MainContractor' AND Name = 'Cache Hospital' LIMIT 1].Id,
            results[0].mainContractorId
        );
        System.assertEquals(results[0].mainContractorId, results[1].mainContractorId);
        System.assertEquals('Gamma Rival', results[1].competitorNames.substringAfter(';'));
        System.assertEquals(
            1,
            [SELECT COUNT() FROM DealerReferenceValue__c WHERE Type__c = 'Competitor' AND Name = 'Cache Rival']
        );
    }

    @IsTest
    static void saveOpportunityReferences_writesEveryPickerField() {
        User portalUser = dealer();
        Opportunity opportunity;
        System.runAs(portalUser) {
            opportunity = dealerOpportunity(portalUser.Contact.AccountId, 'All References', 12);
            insert opportunity;
        }
        Id architectId = [SELECT Id FROM DealerReferenceValue__c WHERE Name = 'Alpha Architect' LIMIT 1].Id;

        Test.startTest();
        System.runAs(dealer()) {
            DealerReferencePickerController.saveOpportunityReferences(
                opportunity.Id,
                'pending:' + EncodingUtil.urlEncode('Portal Hospital', 'UTF-8'),
                'Portal Hospital',
                architectId,
                'Alpha Architect',
                'pending:' + EncodingUtil.urlEncode('Portal Contractor', 'UTF-8'),
                'Portal Contractor',
                'pending:' + EncodingUtil.urlEncode('Portal Planner', 'UTF-8'),
                'Portal Planner',
                null,
                'Beta Competitor;Portal Rival'
            );
        }
        Test.stopTest();

        Opportunity saved = [
            SELECT EndCustomerName__c, ArchitectName__c, MainContractorName__c,
                EquipmentPlannerName__c, DealerCompetitors__c
            FROM Opportunity
            WHERE Id = :opportunity.Id
        ];
        System.assertEquals('Portal Hospital', saved.EndCustomerName__c);
        System.assertEquals('Alpha Architect', saved.ArchitectName__c);
        System.assertEquals('Portal Contractor', saved.MainContractorName__c);
        System.assertEquals('Portal Planner', saved.EquipmentPlannerName__c);
        System.assertEquals('Beta Competitor;Portal Rival', saved.DealerCompetitors__c);
    }

    @IsTest
    static void load_returnsEveryStoredReference() {
        User portalUser = dealer();
        DealerReferencePickerController.OpportunityReferences loaded;
        System.runAs(portalUser) {
            DealerReferencePickerController.create('EndCustomer', 'Known Hospital');
            DealerReferencePickerController.create('EquipmentPlanner', 'Known Planner');
            Opportunity opportunity = dealerOpportunity(portalUser.Contact.AccountId, 'Loaded References', 18);
            opportunity.EndCustomerName__c = 'Known Hospital';
            opportunity.ArchitectName__c = 'Alpha Architect';
            opportunity.MainContractorName__c = 'New Contractor';
            opportunity.EquipmentPlannerName__c = 'Known Planner';
            opportunity.DealerCompetitors__c = 'Beta Competitor;Missing Rival';
            insert opportunity;
            Test.startTest();
            loaded = DealerReferencePickerController.loadOpportunityReferences(opportunity.Id);
            Test.stopTest();
        }

        System.assertEquals('Known Hospital', loaded.endCustomerName);
        System.assertEquals(false, loaded.endCustomerId.startsWith('pending:'));
        System.assertEquals('Alpha Architect', loaded.architectName);
        System.assert(loaded.mainContractorId.startsWith('pending:'), 'A name without a reference row stays pending');
        System.assertEquals('Known Planner', loaded.equipmentPlannerName);
        System.assertEquals(false, loaded.equipmentPlannerId.startsWith('pending:'));
        System.assert(loaded.competitorIds.contains('pending:'), 'A missing competitor stays pending');
        System.assertEquals('Beta Competitor;Missing Rival', loaded.competitorNames);
    }

    @IsTest
    static void load_blankOpportunity_returnsEmptyReferences() {
        User portalUser = dealer();
        DealerReferencePickerController.OpportunityReferences loaded;
        System.runAs(portalUser) {
            Opportunity opportunity = dealerOpportunity(portalUser.Contact.AccountId, 'Blank References', 8);
            insert opportunity;
            loaded = DealerReferencePickerController.loadOpportunityReferences(opportunity.Id);
        }

        System.assertEquals(null, loaded.endCustomerName);
        System.assertEquals(null, loaded.competitorNames);
    }

    @IsTest
    static void load_nullOpportunity_throws() {
        Boolean threw = false;
        try {
            System.runAs(dealer()) {
                DealerReferencePickerController.loadOpportunityReferences(null);
            }
        } catch (AuraHandledException ex) {
            threw = true;
        }
        System.assertEquals(true, threw, 'An opportunity is required');
    }

    @IsTest
    static void save_rejectsMissingAndOversizedValues() {
        User portalUser = dealer();
        Opportunity opportunity;
        System.runAs(portalUser) {
            opportunity = dealerOpportunity(portalUser.Contact.AccountId, 'Validation Dealer', 9);
            insert opportunity;
        }
        String tooLong = 'N'.leftPad(81, 'N');
        Boolean missingOpportunity = false;
        Boolean longToken = false;
        Boolean longName = false;
        Boolean longCompetitor = false;
        Boolean longCompetitorList = false;

        System.runAs(dealer()) {
            DealerReferencePickerController.saveReferenceUpdates(null);
            DealerReferencePickerController.saveReferenceUpdates(new List<DealerReferencePickerController.ReferenceUpdate>());
            try {
                DealerReferencePickerController.ReferenceUpdate missing = new DealerReferencePickerController.ReferenceUpdate();
                DealerReferencePickerController.saveReferenceUpdates(new List<DealerReferencePickerController.ReferenceUpdate>{ missing });
            } catch (AuraHandledException ex) {
                missingOpportunity = true;
            }
            try {
                DealerReferencePickerController.ReferenceUpdate tokenRow = new DealerReferencePickerController.ReferenceUpdate();
                tokenRow.opportunityId = opportunity.Id;
                tokenRow.endCustomerToken = 'pending:' + EncodingUtil.urlEncode(tooLong, 'UTF-8');
                tokenRow.endCustomerName = 'Short Hospital';
                DealerReferencePickerController.saveReferenceUpdates(new List<DealerReferencePickerController.ReferenceUpdate>{ tokenRow });
            } catch (AuraHandledException ex) {
                longToken = true;
            }
            try {
                DealerReferencePickerController.ReferenceUpdate nameRow = new DealerReferencePickerController.ReferenceUpdate();
                nameRow.opportunityId = opportunity.Id;
                nameRow.endCustomerName = tooLong;
                DealerReferencePickerController.saveReferenceUpdates(new List<DealerReferencePickerController.ReferenceUpdate>{ nameRow });
            } catch (AuraHandledException ex) {
                longName = true;
            }
            try {
                DealerReferencePickerController.ReferenceUpdate competitorRow = new DealerReferencePickerController.ReferenceUpdate();
                competitorRow.opportunityId = opportunity.Id;
                competitorRow.competitorNames = tooLong;
                DealerReferencePickerController.saveReferenceUpdates(new List<DealerReferencePickerController.ReferenceUpdate>{ competitorRow });
            } catch (AuraHandledException ex) {
                longCompetitor = true;
            }
            try {
                DealerReferencePickerController.ReferenceUpdate listRow = new DealerReferencePickerController.ReferenceUpdate();
                listRow.opportunityId = opportunity.Id;
                listRow.competitorNames = String.join(new List<String>{
                    'A'.leftPad(70, 'A'),
                    'B'.leftPad(70, 'B'),
                    'C'.leftPad(70, 'C'),
                    'D'.leftPad(70, 'D')
                }, ';');
                DealerReferencePickerController.saveReferenceUpdates(new List<DealerReferencePickerController.ReferenceUpdate>{ listRow });
            } catch (AuraHandledException ex) {
                longCompetitorList = true;
            }
        }

        System.assertEquals(true, missingOpportunity, 'An opportunity is required');
        System.assertEquals(true, longToken, 'A reference token longer than 80 characters is rejected');
        System.assertEquals(true, longName, 'A reference name longer than 80 characters is rejected');
        System.assertEquals(true, longCompetitor, 'A competitor name longer than 80 characters is rejected');
        System.assertEquals(true, longCompetitorList, 'Competitor names longer than 255 characters are rejected');
    }

    @IsTest
    static void save_competitorTokensWithoutNames_keepsTheStoredFieldBlank() {
        User portalUser = dealer();
        Opportunity opportunity;
        System.runAs(portalUser) {
            opportunity = dealerOpportunity(portalUser.Contact.AccountId, 'Token Only', 11);
            insert opportunity;
        }
        DealerReferencePickerController.ReferenceUpdate updateRow = new DealerReferencePickerController.ReferenceUpdate();
        updateRow.opportunityId = opportunity.Id;
        updateRow.competitorTokens = 'pending:' + EncodingUtil.urlEncode('Token Rival', 'UTF-8');
        updateRow.endCustomerName = '   ';

        Test.startTest();
        System.runAs(dealer()) {
            DealerReferencePickerController.saveReferenceUpdates(new List<DealerReferencePickerController.ReferenceUpdate>{ updateRow });
        }
        Test.stopTest();

        Opportunity saved = [
            SELECT EndCustomerName__c, DealerCompetitors__c
            FROM Opportunity
            WHERE Id = :opportunity.Id
        ];
        System.assertEquals(null, saved.EndCustomerName__c);
        System.assertEquals(null, saved.DealerCompetitors__c);
        System.assertEquals(
            1,
            [SELECT COUNT() FROM DealerReferenceValue__c WHERE Type__c = 'Competitor' AND Name = 'Token Rival']
        );
    }

    @IsTest
    static void search_invalidType_throws() {
        Boolean threw = false;
        try {
            System.runAs(dealer()) {
                DealerReferencePickerController.search('NotAType', 'x');
            }
        } catch (AuraHandledException ex) {
            threw = true;
        }
        System.assertEquals(true, threw, 'Invalid type should throw');
    }

    private static Opportunity dealerOpportunity(Id accountId, String name, Integer daysAhead) {
        return new Opportunity(
            Name = name,
            AccountId = accountId,
            StageName = 'Discovery',
            CloseDate = Date.today().addDays(daysAhead),
            BypassValidations__c = true
        );
    }

    private static User createPortalDealer() {
        User accountOwner;
        System.runAs(new User(Id = UserInfo.getUserId())) {
            UserRole dealerRole = new UserRole(Name = 'Dealer Test ' + DEALER_KEY, DeveloperName = 'DealerTst' + DEALER_KEY);
            insert dealerRole;
            accountOwner = new User(
                Alias = 'downer',
                Email = 'dealer.owner.' + DEALER_KEY + '@example.com',
                EmailEncodingKey = 'UTF-8',
                LastName = 'Dealer Owner',
                LanguageLocaleKey = 'en_US',
                LocaleSidKey = 'en_US',
                ProfileId = UserInfo.getProfileId(),
                TimeZoneSidKey = 'America/New_York',
                UserRoleId = dealerRole.Id,
                Username = 'dealer.owner.' + DEALER_KEY + '.' + UserInfo.getOrganizationId() + '@example.com'
            );
            insert accountOwner;
        }
        Account dealerAccount;
        Contact dealerContact;
        System.runAs(accountOwner) {
            dealerAccount = new Account(Name = 'Dealer Portal ' + DEALER_KEY);
            insert dealerAccount;
            dealerAccount.IsPartner = true;
            update dealerAccount;
            dealerContact = new Contact(
                LastName = 'Portal Dealer',
                AccountId = dealerAccount.Id,
                Email = 'portal.dealer@example.com'
            );
            insert dealerContact;
        }
        User dealer;
        System.runAs(new User(Id = UserInfo.getUserId())) {
            Profile dealerProfile = [SELECT Id FROM Profile WHERE Name = 'Healthcare Dealer' LIMIT 1];
            dealer = new User(
                Alias = 'dport',
                Email = 'portal.dealer.' + DEALER_KEY + '@example.com',
                EmailEncodingKey = 'UTF-8',
                LastName = 'Portal Dealer',
                LanguageLocaleKey = 'en_US',
                LocaleSidKey = 'en_US',
                ProfileId = dealerProfile.Id,
                TimeZoneSidKey = 'America/New_York',
                Username = portalDealerUsername(),
                ContactId = dealerContact.Id,
                CommunityNickname = 'dport' + DEALER_KEY + UserInfo.getOrganizationId().right(6)
            );
            insert dealer;
            insert new PermissionSetAssignment(
                AssigneeId = dealer.Id,
                PermissionSetId = [SELECT Id FROM PermissionSet WHERE Name = 'DealerPortalUser' LIMIT 1].Id
            );
        }
        return dealer;
    }

    private static String portalDealerUsername() {
        return 'dealer.' + DEALER_KEY + '.' + UserInfo.getOrganizationId() + '@example.com';
    }
}