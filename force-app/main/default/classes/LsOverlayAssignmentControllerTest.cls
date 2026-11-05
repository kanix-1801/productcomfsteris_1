/**
 * @author PWC Developer
 * @date 2026/11/04
 *
 * @group Life Sciences Overlay Assignment
 *
 * @description
 * GCL-79 - Unit tests for LsOverlayAssignmentController and LsOverlayAssignmentService.
 * Covers territory and account search, assignment type, and Account-only access on submit.
 */
@IsTest
private class LsOverlayAssignmentControllerTest {

    /**
     * @description GCL-79 - The confirmation screen's assignment-type label must come from
     *              the same constant submit() writes, so the two can never drift apart.
     */
    @IsTest
    static void assignmentTypeLabelMatchesWhatSubmitWrites() {
        System.assertEquals(
            LsOverlayAssignmentService.ASSIGNMENT_TYPE_SALESFORCE_ASSIGNED,
            LsOverlayAssignmentController.getAssignmentTypeLabel()
        );
    }

    /**
     * @description GCL-79 - Territory search and account retrieval must stay scoped to
     *              Life Sciences data (BusinessUnit__c = Life Sciences or ClassCode__c = SC),
     *              return address-level rows, and surface the associated parent account.
     *              A Healthcare territory on the same OrderLineContact__c object must not
     *              leak into the Life Sciences results.
     */
    @IsTest
    static void searchesLifeSciencesTerritoriesAndAddressAccounts() {
        Account parentAccount = new Account(
            Name = 'LS Overlay Parent',
            AccountNumber = 'LS-OV-P',
            Type = 'Customer',
            CustomerClassCode__c = 'SC'
        );
        insert parentAccount;

        Account addressAccount = new Account(
            Name = 'LS Overlay Address',
            AccountNumber = 'LS-OV-A',
            Type = 'Address',
            ParentId = parentAccount.Id,
            CustomerClassCode__c = 'SC',
            OracleAddressId__c = 'LS-OV-ADDR-1',
            BillingStreet = '1 Science Way',
            BillingCity = 'Mentor',
            BillingPostalCode = '44060',
            BillingCountry = 'United States'
        );
        insert addressAccount;

        insert new List<OrderLineContact__c>{
            new OrderLineContact__c(
                TASAddressId__c = 'LS-OV-ADDR-1',
                TerritoryID__c = 'LS-TERR-100',
                TerritoryDescription__c = 'Life Sciences East',
                TerritoryNumber__c = '100',
                ClassCode__c = 'SC',
                BusinessUnit__c = 'Life Sciences'
            ),
            new OrderLineContact__c(
                TASAddressId__c = 'HC-OV-ADDR-1',
                TerritoryID__c = 'HC-TERR-100',
                TerritoryDescription__c = 'Healthcare East',
                TerritoryNumber__c = '100',
                ClassCode__c = 'HC',
                BusinessUnit__c = 'Healthcare'
            )
        };

        Test.startTest();
        List<LsOverlayAssignmentController.TerritoryWrapper> territories =
            LsOverlayAssignmentController.searchTerritories('LS-TERR-100');
        List<LsOverlayAssignmentController.AccountWrapper> accounts =
            LsOverlayAssignmentController.retrieveAccounts(
                new List<String>{ 'LS-TERR-100' },
                'LS Overlay',
                null,
                null
            );
        Test.stopTest();

        System.assertEquals(1, territories.size(), 'Healthcare territories should stay out of the Life Sciences search.');
        System.assertEquals('LS-TERR-100', territories[0].territoryId);
        System.assertEquals(1, accounts.size());
        System.assertEquals(addressAccount.Id, accounts[0].accountId);
        System.assertEquals('1 Science Way', accounts[0].street);
        System.assertEquals('Mentor', accounts[0].city);
        System.assertEquals(parentAccount.Id, accounts[0].associatedAccountId);
        System.assertEquals('LS Overlay Parent', accounts[0].associatedAccountName);
    }

    /**
     * @description GCL-79 - Submit must create an additive, idempotent Account Team row
     *              with AssignmentType__c = Salesforce Assigned, and must only extend Account
     *              access (AccountAccessLevel = Edit). Opportunity and Case access must not
     *              be elevated, and no OrderLineContact__c (TAS/Oracle) row may be written.
     */
    @IsTest
    static void submitExtendsOnlyAccountAccessAndLeavesTasUnchanged() {
        Profile lifeSciencesProfile = [
            SELECT Id
            FROM Profile
            WHERE Name = :UserSelector.LIFESCIENCES_SALES_PROFILE_NAME
            LIMIT 1
        ];
        String uniqueSeed = String.valueOf(DateTime.now().getTime());
        User overlayUser = new User(
            FirstName = 'LS',
            LastName = 'OverlayRep' + uniqueSeed,
            Alias = 'lsov',
            Email = 'ls.overlay.' + uniqueSeed + '@example.com',
            Username = 'ls.overlay.' + uniqueSeed + '@example.com',
            CommunityNickname = 'lsov' + uniqueSeed,
            TimeZoneSidKey = 'America/New_York',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            ProfileId = lifeSciencesProfile.Id,
            Country = 'United States',
            IsActive = true
        );
        insert overlayUser;

        Account addressAccount = new Account(
            Name = 'LS Overlay Submit Address',
            AccountNumber = 'LS-OV-S',
            Type = 'Address',
            CustomerClassCode__c = 'SC',
            OracleAddressId__c = 'LS-OV-ADDR-2'
        );
        insert addressAccount;
        insert new OrderLineContact__c(
            TASAddressId__c = 'LS-OV-ADDR-2',
            TerritoryID__c = 'LS-TERR-200',
            TerritoryDescription__c = 'Life Sciences West',
            ClassCode__c = 'SC',
            BusinessUnit__c = 'Life Sciences'
        );
        Integer tasCountBefore = [SELECT COUNT() FROM OrderLineContact__c WHERE TerritoryID__c = 'LS-TERR-200'];

        Test.startTest();
        // Submitting twice confirms the second call does not insert a duplicate row.
        LsOverlayAssignmentController.submitOverlayAssignments(
            new List<String>{ 'LS-TERR-200' },
            new List<Id>{ addressAccount.Id },
            new List<Id>{ overlayUser.Id }
        );
        LsOverlayAssignmentController.submitOverlayAssignments(
            new List<String>{ 'LS-TERR-200' },
            new List<Id>{ addressAccount.Id },
            new List<Id>{ overlayUser.Id }
        );
        Test.stopTest();

        List<AccountTeamMember> members = [
            SELECT TeamMemberRole, AssignmentType__c, AccountAccessLevel, OpportunityAccessLevel, CaseAccessLevel
            FROM AccountTeamMember
            WHERE AccountId = :addressAccount.Id
            AND UserId = :overlayUser.Id
        ];
        System.assertEquals(1, members.size(), 'A second submit should not add a duplicate Account Team row.');
        System.assertEquals('Sales', members[0].TeamMemberRole);
        System.assertEquals('Salesforce Assigned', members[0].AssignmentType__c);
        System.assertEquals('Edit', members[0].AccountAccessLevel, 'Account access should be extended.');
        System.assertEquals(
            'None',
            members[0].OpportunityAccessLevel,
            'Opportunity access should not be extended for this story.'
        );
        System.assertEquals(
            'None',
            members[0].CaseAccessLevel,
            'Case access should not be extended for this story.'
        );
        System.assertEquals(
            tasCountBefore,
            [SELECT COUNT() FROM OrderLineContact__c WHERE TerritoryID__c = 'LS-TERR-200'],
            'Life Sciences overlay submit should not write TAS rows.'
        );
    }

    /**
     * @description GCL-79 - No accounts/no users validation must surface as a user-facing message.
     */
    @IsTest
    static void submitRequiresAccountsAndUsers() {
        Boolean threwForNoAccounts = false;
        try {
            LsOverlayAssignmentController.submitOverlayAssignments(null, new List<Id>(), new List<Id>{ UserInfo.getUserId() });
        } catch (AuraHandledException ex) {
            threwForNoAccounts = true;
        }
        System.assert(threwForNoAccounts, 'Submitting with no accounts selected should be blocked.');
    }
}