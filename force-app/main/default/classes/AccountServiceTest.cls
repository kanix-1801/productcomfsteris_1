/**
 * @description GW-4786 - Covers AccountService from its own test class, including the
 *              ship-to lookup used by Create Return Order and the existing TAS paths.
 *              GC-3617 covers Dealer Customer partner enablement.
 */
@IsTest
    private class AccountServiceTest {

    private static Integer idSequence = 1;

    @IsTest
    static void testAssignTasToProspect_WhenInputMissingOrIneligible_DoesNotEnqueue() {
        // Given
        Integer before = queuedJobs('AccountProspectTasQueueable');
        Account ineligible = prospectAccount(false);

        // When
        AccountService.assignTAStoProspect(null);
        AccountService.assignTAStoProspect(new List<Account>());
        AccountService.assignTAStoProspect(new List<Account>{ null, ineligible });

        // Then
        Assert.areEqual(before, queuedJobs('AccountProspectTasQueueable'));
    }

    @IsTest
    static void testAssignTasToProspect_WhenOneEligible_Enqueues() {
        // Given
        Account eligible = prospectAccount(true);

        // When
        AccountService.assignTAStoProspect(new List<Account>{ eligible });

        // Then
        Assert.areEqual(1, queuedJobs('AccountProspectTasQueueable'));
    }

    @IsTest
    static void testAssignTasToProspect_WhenSeveralEligible_DoesNotEnqueue() {
        // Given
        Account firstEligible = prospectAccount(true);
        Account secondEligible = prospectAccount(true);

        // When
        AccountService.assignTAStoProspect(new List<Account>{ firstEligible, secondEligible });

        // Then
        Assert.areEqual(0, queuedJobs('AccountProspectTasQueueable'));
    }

    @IsTest
    static void testAssignTasToProspectUpdate_WhenInputMissing_DoesNotEnqueue() {
        // Given
        Account current = prospectAccount(true);
        Integer before = queuedJobs('AccountProspectTasQueueable');
	
        // When
        AccountService.assignTAStoProspectUpdate(null, null);
        AccountService.assignTAStoProspectUpdate(new List<Account>(), new Map<Id, Account>());
        AccountService.assignTAStoProspectUpdate(new List<Account>{ current }, null);
        AccountService.assignTAStoProspectUpdate(new List<Account>{ current }, new Map<Id, Account>());
        AccountService.assignTAStoProspectUpdate(
            new List<Account>{ current },
            new Map<Id, Account>{ nextId(Account.SObjectType) => prospectAccount(true) }
        );

        // Then
        Assert.areEqual(before, queuedJobs('AccountProspectTasQueueable'));
    }

    @IsTest
    static void testAssignTasToProspectUpdate_WhenFieldChanged_Enqueues() {
        // Given
        Account current = prospectAccount(true);
        Account previous = current.clone(true, true, true, true);
        previous.Name = 'Previous Prospect Name';

        // When
        AccountService.assignTAStoProspectUpdate(
            new List<Account>{ current },
            new Map<Id, Account>{ current.Id => previous }
        );

        // Then
        Assert.areEqual(1, queuedJobs('AccountProspectTasQueueable'));
    }

    @IsTest
    static void testAssignTasToCustomer_WhenInputMissingOrIneligible_DoesNotEnqueue() {
        // Given
        Account missingOracleId = customerAccount(true);
        missingOracleId.OracleAddressId__c = null;
        missingOracleId.AccountSource = 'Oracle';
        Integer before = queuedJobs('AccountCustomerTasQueueable');

        // When
        AccountService.assignTAStoCustomer(null);
        AccountService.assignTAStoCustomer(new List<Account>());
        AccountService.assignTAStoCustomer(new List<Account>{ null, missingOracleId });

        // Then
        Assert.areEqual(before, queuedJobs('AccountCustomerTasQueueable'));
    }

    @IsTest
    static void testAssignTasToCustomer_WhenOneEligible_Enqueues() {
        // Given
        Account eligible = customerAccount(true);

        // When
        AccountService.assignTAStoCustomer(new List<Account>{ eligible });

        // Then
        Assert.areEqual(1, queuedJobs('AccountCustomerTasQueueable'));
    }

    @IsTest
    static void testAssignTasToCustomerUpdate_WhenInputMissingOrUnchanged_DoesNotEnqueue() {
        // Given
        Account current = customerAccount(true);
        Integer before = queuedJobs('AccountCustomerTasQueueable');

        // When
        AccountService.assignTAStoCustomerUpdate(null, null);
        AccountService.assignTAStoCustomerUpdate(new List<Account>(), new Map<Id, Account>());
        AccountService.assignTAStoCustomerUpdate(new List<Account>{ current }, null);
        AccountService.assignTAStoCustomerUpdate(
            new List<Account>{ current },
            new Map<Id, Account>{ nextId(Account.SObjectType) => customerAccount(true) }
        );
        AccountService.assignTAStoCustomerUpdate(
            new List<Account>{ current },
            new Map<Id, Account>{ current.Id => current.clone(true, true, true, true) }
        );

        // Then
        Assert.areEqual(before, queuedJobs('AccountCustomerTasQueueable'));
    }

    @IsTest
    static void testAssignTasToCustomerUpdate_WhenFieldChanged_Enqueues() {
        // Given
        Account current = customerAccount(true);
        Account previous = current.clone(true, true, true, true);
        previous.BillingCity = 'Cleveland';

        // When
        AccountService.assignTAStoCustomerUpdate(
            new List<Account>{ current },
            new Map<Id, Account>{ current.Id => previous }
        );

        // Then
        Assert.areEqual(1, queuedJobs('AccountCustomerTasQueueable'));
    }

    @IsTest
    static void testAssignTasToCustomerUpdate_WhenAccountIsNull_Rethrows() {
        // Given
        Boolean threw = false;

        // When
        try {
            AccountService.assignTAStoCustomerUpdate(
                new List<Account>{ null },
                new Map<Id, Account>{ nextId(Account.SObjectType) => customerAccount(true) }
            );
        } catch (Exception ex) {
            threw = true;
            Assert.isTrue(String.isNotBlank(ex.getMessage()));
        }

        // Then
        Assert.isTrue(threw);
    }

    @IsTest
    static void testRetryTasAssignmentFromFlow_WhenRequestMissing_DoesNotEnqueue() {
        // Given
        AccountService.FlowRequest blankRequest = new AccountService.FlowRequest();
        Integer before = queuedJobs('AccountProspectTasQueueable');

        // When
        AccountService.retryTasAssignmentFromFlow(null);
        AccountService.retryTasAssignmentFromFlow(new List<AccountService.FlowRequest>());
        AccountService.retryTasAssignmentFromFlow(
            new List<AccountService.FlowRequest>{ null, blankRequest }
        );

        // Then
        Assert.areEqual(before, queuedJobs('AccountProspectTasQueueable'));
    }

    @IsTest
    static void testRetryTasAssignmentFromFlow_WhenProspectIsNotEligible_DoesNotEnqueue() {
        // Given
        bypassAccountTrigger();
        Account prospect = insertProspect(true, 'Assigned');
        AccountService.FlowRequest request = new AccountService.FlowRequest();
        request.accountId = prospect.Id;

        // When
        AccountService.retryTasAssignmentFromFlow(new List<AccountService.FlowRequest>{ request });

        // Then
        Assert.areEqual(0, queuedJobs('AccountProspectTasQueueable'));
    }

    @IsTest
    static void testRetryTasAssignmentFromFlow_WhenProspectIsEligible_Enqueues() {
        // Given
        bypassAccountTrigger();
        Account prospect = insertProspect(false, 'Assignment Missing');
        AccountService.FlowRequest request = new AccountService.FlowRequest();
        request.accountId = prospect.Id;

        // When
        AccountService.retryTasAssignmentFromFlow(new List<AccountService.FlowRequest>{ request });

        // Then
        Assert.areEqual(1, queuedJobs('AccountProspectTasQueueable'));
    }

    @IsTest
    static void testPopulateOrgIdOnNewProspect_WhenNoProspectNeedsOrgId_LeavesValue() {
        // Given
        Account alreadySet = prospectAccount(true);
        String originalOrgId = alreadySet.OrgIDs__c;
        Account customer = customerAccount(true);
        customer.OrgIDs__c = null;

        // When
        AccountService.populateOrgIdOnNewProspect(null);
        AccountService.populateOrgIdOnNewProspect(new List<Account>());
        AccountService.populateOrgIdOnNewProspect(new List<Account>{ customer, alreadySet });

        // Then
        Assert.areEqual(originalOrgId, alreadySet.OrgIDs__c);
        Assert.isTrue(String.isBlank(customer.OrgIDs__c));
    }

    @IsTest
    static void testPopulateOrgIdOnNewProspect_WhenOrgIdIsBlank_UsesRunningUserOrRethrows() {
        // Given
        Account prospect = prospectAccount(true);
        prospect.OrgIDs__c = null;
        String runningUserOrgId = [
            SELECT OrgId__c
            FROM User
            WHERE Id = :UserInfo.getUserId()
        ].OrgId__c;

        // When
        try {
            AccountService.populateOrgIdOnNewProspect(new List<Account>{ prospect });
        } catch (Exception ex) {
            Assert.isTrue(String.isNotBlank(ex.getMessage()));
            return;
        }

        // Then
        if (String.isBlank(runningUserOrgId)) {
            Assert.isTrue(String.isBlank(prospect.OrgIDs__c));
        } else {
            Assert.areEqual(runningUserOrgId, prospect.OrgIDs__c);
        }
    }

    @IsTest
    static void testGetShipToAddressAccounts_WhenParentMissing_ReturnsEmpty() {
        // Given / When
        List<Account> forNullParent = AccountService.getShipToAddressAccounts(null);
        List<Account> forUnknownParent = AccountService.getShipToAddressAccounts(
            nextId(Account.SObjectType)
        );

        // Then
        Assert.areEqual(0, forNullParent.size());
        Assert.areEqual(0, forUnknownParent.size());
    }

    @IsTest
    static void testGetShipToAddressAccounts_WhenAddressIsActive_ReturnsThatAccount() {
        // Given
        Account customer = new Account(
            Name = 'Ship To Customer',
            OrgIDs__c = '82',
            SourceSystemID__c = 'SHIPTO-PARENT-4786'
        );
        insert customer;
        Account activeShipTo = new Account(
            Name = 'Active Ship To',
            ParentId = customer.Id,
            Type = 'Address',
            ShiptoAddressStatus__c = 'Active',
            SourceSystemID__c = 'SHIPTO-ACTIVE-4786',
            BillingStreet = '200 Oak Ave',
            BillingCity = 'Cleveland',
            BillingState = 'OH',
            BillingPostalCode = '44114',
            BillingCountry = 'US'
        );
        Account inactiveShipTo = new Account(
            Name = 'Inactive Ship To',
            ParentId = customer.Id,
            Type = 'Address',
            ShiptoAddressStatus__c = 'Inactive',
            SourceSystemID__c = 'SHIPTO-INACTIVE-4786'
        );
        insert new List<Account>{ activeShipTo, inactiveShipTo };

        // When
        List<Account> matches = AccountService.getShipToAddressAccounts(customer.Id);

        // Then
        Assert.areEqual(1, matches.size());
        Assert.areEqual(activeShipTo.Id, matches[0].Id);
    }

    private static Account prospectAccount(Boolean eligible) {
        Account account = new Account(
            Id = nextId(Account.SObjectType),
            Name = eligible ? 'Eligible Prospect' : null,
            RecordTypeId = recordTypeId('Prospect'),
            CustomerClassCode__c = eligible ? 'HC' : null,
            OrgIDs__c = eligible ? '82' : null,
            BillingStreet = '1 Main St',
            BillingCity = 'Mentor',
            BillingState = 'OH',
            BillingPostalCode = '44060',
            BillingCountry = 'US',
            ShippingStreet = '1 Main St',
            ShippingCity = 'Mentor',
            ShippingState = 'Ohio',
            ShippingPostalCode = '44060',
            ShippingCountry = 'United States',
            Price_List__c = eligible ? nextId(Price_List__c.SObjectType) : null
        );
        return account;
    }

    private static Account customerAccount(Boolean eligible) {
        Account account = new Account(
            Id = nextId(Account.SObjectType),
            Name = 'Oracle Customer',
            RecordTypeId = recordTypeId('Customer'),
            SourceSystemID__c = 'Oracle-SRC-4786',
            OracleAddressId__c = eligible ? 'ORA-4786' : null,
            CustomerClassCode__c = eligible ? 'HC' : null,
            OrgIDs__c = eligible ? '82' : null,
            BillingStreet = '1 Main St',
            BillingCity = 'Mentor',
            BillingState = 'OH',
            BillingPostalCode = '44060',
            BillingCountry = 'US'
        );
        return account;
    }

    private static Account insertProspect(Boolean retryFlag, String assignmentStatus) {
        Price_List__c priceList = new Price_List__c(
            Name = 'GW-4786 TAS Price List',
            Status__c = 'Active'
        );
        insert priceList;

        Account prospect = new Account(
            Name = 'Inserted Prospect',
            RecordTypeId = recordTypeId('Prospect'),
            CustomerClassCode__c = 'HC',
            OrgIDs__c = '82',
            BillingStreet = '1 Main St',
            BillingCity = 'Mentor',
            BillingState = 'OH',
            BillingPostalCode = '44060',
            BillingCountry = 'US',
            Price_List__c = priceList.Id,
            TAS_Retry__c = retryFlag,
            TAS_Assignment_Status__c = assignmentStatus,
            SystemID__c = 'TAS-4786-' + String.valueOf(idSequence),
            SourceSystemID__c = 'SRC-4786-' + String.valueOf(idSequence)
        );
        insert prospect;
        return prospect;
    }

    private static Id recordTypeId(String developerName) {
        Schema.RecordTypeInfo info = Schema.SObjectType.Account
            .getRecordTypeInfosByDeveloperName()
            .get(developerName);
        Assert.isNotNull(info, developerName + ' record type is required');
        return info.getRecordTypeId();
    }

    private static void bypassAccountTrigger() {
        Automation_Setting_Trigger__c settings = Automation_Setting_Trigger__c.getInstance(
            UserInfo.getUserId()
        );
        settings.AccountTriggerByPass__c = true;
        upsert settings;
    }

    private static Integer queuedJobs(String className) {
        return [
            SELECT COUNT()
            FROM AsyncApexJob
            WHERE JobType = 'Queueable'
                AND ApexClass.Name = :className
        ];
    }

    private static Id nextId(Schema.SObjectType sobjectType) {
        String suffix = String.valueOf(idSequence).leftPad(12, '0');
        idSequence++;
        return (Id) (sobjectType.getDescribe().getKeyPrefix() + suffix);
    }

    /**
     * @description GC-3617. A Customer Account with Type Dealer becomes a partner
     *              account when the owner has a role.
     */
    @IsTest
    static void testEnableDealerAccounts_WhenDealerCustomerInserted() {
        User accountOwner = createDealerOwner();

        System.runAs(accountOwner) {
            Account dealerAccount = newDealerAccount('GC3617 Dealer Insert');
            Assert.areNotEqual(true, dealerAccount.IsPartner, 'Account is not a partner before insert');

            Test.startTest();
            insert dealerAccount;
            Test.stopTest();

            Account savedAccount = [
                SELECT IsPartner, Type, RecordType.DeveloperName
                FROM Account
                WHERE Id = :dealerAccount.Id
            ];
            Assert.areEqual(true, savedAccount.IsPartner, 'Dealer Customer should be enabled as a partner');
            Assert.areEqual('Dealer', savedAccount.Type);
            Assert.areEqual('Customer', savedAccount.RecordType.DeveloperName);
        }
    }

    /**
     * @description GC-3617. Changing Type to Dealer on an existing Customer enables the partner flag.
     */
    @IsTest
    static void testEnableDealerAccounts_WhenTypeChangesToDealer() {
        User accountOwner = createDealerOwner();

        System.runAs(accountOwner) {
            Account customerAccount = newDealerAccount('GC3617 Type Change');
            customerAccount.Type = 'Customer';
            insert customerAccount;

            Account beforeUpdate = [
                SELECT IsPartner
                FROM Account
                WHERE Id = :customerAccount.Id
            ];
            Assert.areNotEqual(true, beforeUpdate.IsPartner, 'Customer Type should not enable the partner flag');

            Test.startTest();
            customerAccount.Type = 'Dealer';
            update customerAccount;
            Test.stopTest();

            Account savedAccount = [
                SELECT IsPartner
                FROM Account
                WHERE Id = :customerAccount.Id
            ];
            Assert.areEqual(true, savedAccount.IsPartner, 'Updating Type to Dealer should enable the partner flag');
        }
    }

    /**
     * @description GC-3617. A bulk load enables every eligible Dealer Account in one update.
     */
    @IsTest
    static void testEnableDealerAccounts_WhenBulkDealerCustomersInserted() {
        User accountOwner = createDealerOwner();
        List<Account> dealerAccounts = new List<Account>();
        for (Integer index = 0; index < 200; index++) {
            dealerAccounts.add(newDealerAccount('GC3617 Bulk ' + index));
        }

        System.runAs(accountOwner) {
            Test.startTest();
            insert dealerAccounts;
            Test.stopTest();

            Integer partnerCount = [
                SELECT COUNT()
                FROM Account
                WHERE Id IN :dealerAccounts
                AND IsPartner = TRUE
            ];
            Assert.areEqual(200, partnerCount, 'Every Dealer Account in the bulk load should be a partner');
        }
    }

    /**
     * @description GC-3617. Customers that are not Dealers, and Dealer Prospects, stay non-partner.
     */
    @IsTest
    static void testEnableDealerAccounts_WhenAccountIsNotDealerCustomer() {
        User accountOwner = createDealerOwner();

        System.runAs(accountOwner) {
            Account customerAccount = newDealerAccount('GC3617 Customer');
            customerAccount.Type = 'Customer';
            Account prospectAccount = newDealerAccount('GC3617 Prospect');
            prospectAccount.RecordTypeId = recordTypeId('Prospect');
            prospectAccount.BillingStreet = '1 Main St';
            prospectAccount.BillingCity = 'Mentor';
            prospectAccount.BillingState = 'OH';
            prospectAccount.BillingPostalCode = '44060';
            prospectAccount.BillingCountry = 'US';

            Test.startTest();
            insert new List<Account>{ customerAccount, prospectAccount };
            Test.stopTest();

            Map<Id, Account> savedAccounts = new Map<Id, Account>([
                SELECT IsPartner
                FROM Account
                WHERE Id IN :new List<Id>{ customerAccount.Id, prospectAccount.Id }
            ]);
            Assert.areNotEqual(
                true,
                savedAccounts.get(customerAccount.Id).IsPartner,
                'A Customer that is not a Dealer should stay a non-partner'
            );
            Assert.areNotEqual(
                true,
                savedAccounts.get(prospectAccount.Id).IsPartner,
                'A Prospect Dealer should stay a non-partner'
            );
        }
    }

    /**
     * @description Creates a System Administrator with a role. Partner enablement
     *              requires the Account owner to have a role.
     * @return Inserted user.
     */
    private static User createDealerOwner() {
        Profile adminProfile = [
            SELECT Id
            FROM Profile
            WHERE Name = 'System Administrator'
            LIMIT 1
        ];
        String uniqueKey = String.valueOf(DateTime.now().getTime()) +
            String.valueOf(Math.abs(Crypto.getRandomInteger()));
        User userRecord = new User(
            FirstName = 'GC3617',
            LastName = 'Dealer Owner',
            Email = 'gc3617.' + uniqueKey + '@example.com',
            Username = 'gc3617.' + uniqueKey + '@example.com',
            Alias = 'd3617',
            TimeZoneSidKey = 'America/New_York',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            ProfileId = adminProfile.Id,
            UserRoleId = [
                SELECT Id
                FROM UserRole
                WHERE PortalType = 'None'
                LIMIT 1
            ].Id
        );
        insert userRecord;
        return userRecord;
    }

    /**
     * @description Builds an unsaved Customer Account with Type Dealer.
     * @param accountName Account name.
     * @return Unsaved Account.
     */
    private static Account newDealerAccount(String accountName) {
        return new Account(
            Name = accountName,
            RecordTypeId = recordTypeId('Customer'),
            Type = 'Dealer'
        );
    }
}