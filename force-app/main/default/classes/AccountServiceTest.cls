/**
 * @description GW-4786 - Covers AccountService from its own test class, including the
 *              ship-to lookup used by Create Return Order and the existing TAS paths.
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
}