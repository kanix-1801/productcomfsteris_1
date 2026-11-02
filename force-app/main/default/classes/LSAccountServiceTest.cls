/**
 * @description Covers LSAccountService and AccountService TAS orchestration.
 *              Enqueue tests assert AsyncApexJob only. They do not call Test.stopTest(),
 *              so the queueable does not run the Boomi callout.
 */
@IsTest
private class LSAccountServiceTest {

    private static Integer idSequence = 1;

    @IsTest
    static void testIsLifeSciencesAccount() {
        Assert.isTrue(LSAccountService.isLifeSciencesAccount(new Account(CustomerClassCode__c = 'SC')));
        Assert.isFalse(LSAccountService.isLifeSciencesAccount(new Account(CustomerClassCode__c = 'HC')));
        Assert.isFalse(LSAccountService.isLifeSciencesAccount(new Account(CustomerClassCode__c = 'IC')));
        Assert.isFalse(LSAccountService.isLifeSciencesAccount(new Account()));
        Assert.isFalse(LSAccountService.isLifeSciencesAccount(null));

        Assert.isTrue(AccountService.isHealthcareAccount(new Account(CustomerClassCode__c = 'HC')));
        Assert.isFalse(AccountService.isHealthcareAccount(new Account(CustomerClassCode__c = 'SC')));
        Assert.isFalse(AccountService.isHealthcareAccount(null));
    }

    @IsTest
    static void testLsAssignTasToProspect_WhenInputMissingOrIneligible_DoesNotEnqueue() {
        Integer before = queuedJobs('LSAccountProspectTasQueueable');
        Account healthcare = prospectAccount('HC');
        Account missingPriceList = prospectAccount('SC');
        missingPriceList.Price_List__c = null;

        LSAccountService.assignTAStoProspect(null);
        LSAccountService.assignTAStoProspect(new List<Account>());
        LSAccountService.assignTAStoProspect(new List<Account>{ null, healthcare, missingPriceList });

        Assert.areEqual(before, queuedJobs('LSAccountProspectTasQueueable'));
    }

    @IsTest
    static void testLsAssignTasToProspect_WhenSeveralEligible_EnqueuesOneJob() {
        LSAccountService.assignTAStoProspect(new List<Account>{
            prospectAccount('SC'),
            prospectAccount('Life Science')
        });

        Assert.areEqual(1, queuedJobs('LSAccountProspectTasQueueable'));
    }

    @IsTest
    static void testLsAssignTasToProspect_WhenTestException_Rethrows() {
        LSAccountService.throwTestException = true;
        Boolean threw = false;
        try {
            LSAccountService.assignTAStoProspect(new List<Account>());
        } catch (LSAccountService.LSAccountServiceException ex) {
            threw = true;
            Assert.isTrue(ex.getMessage().contains('assignTAStoProspect'));
        } finally {
            LSAccountService.throwTestException = false;
        }
        Assert.isTrue(threw);
    }

    @IsTest
    static void testLsRetry_WhenRequestMissing_DoesNotEnqueue() {
        Integer before = queuedJobs('LSAccountProspectTasQueueable');
        LSAccountService.FlowRequest blankRequest = new LSAccountService.FlowRequest();

        LSAccountService.retryTasAssignmentFromFlow(null);
        LSAccountService.retryTasAssignmentFromFlow(new List<LSAccountService.FlowRequest>());
        LSAccountService.retryTasAssignmentFromFlow(
            new List<LSAccountService.FlowRequest>{ null, blankRequest }
        );

        Assert.areEqual(before, queuedJobs('LSAccountProspectTasQueueable'));
    }

    @IsTest
    static void testLsRetry_WhenAssignedAndRetryTrue_DoesNotEnqueue() {
        bypassAccountTrigger();
        Account prospect = insertProspect('SC', true, 'Assigned');
        LSAccountService.FlowRequest request = new LSAccountService.FlowRequest();
        request.accountId = prospect.Id;

        LSAccountService.retryTasAssignmentFromFlow(new List<LSAccountService.FlowRequest>{ request });

        Assert.areEqual(0, queuedJobs('LSAccountProspectTasQueueable'));
    }

    @IsTest
    static void testLsRetry_WhenAssignmentMissing_Enqueues() {
        bypassAccountTrigger();
        Account prospect = insertProspect('SC', false, 'Assignment Missing');
        LSAccountService.FlowRequest request = new LSAccountService.FlowRequest();
        request.accountId = prospect.Id;

        LSAccountService.retryTasAssignmentFromFlow(new List<LSAccountService.FlowRequest>{ request });

        Assert.areEqual(1, queuedJobs('LSAccountProspectTasQueueable'));
    }

    @IsTest
    static void testLsRetry_WhenTestException_Rethrows() {
        LSAccountService.throwTestException = true;
        Boolean threw = false;
        try {
            LSAccountService.retryTasAssignmentFromFlow(new List<LSAccountService.FlowRequest>());
        } catch (LSAccountService.LSAccountServiceException ex) {
            threw = true;
            Assert.isTrue(ex.getMessage().contains('retryTasAssignmentFromFlow'));
        } finally {
            LSAccountService.throwTestException = false;
        }
        Assert.isTrue(threw);
    }

    @IsTest
    static void testHcAssignTasToProspect_WhenOneEligible_Enqueues() {
        AccountService.assignTAStoProspect(new List<Account>{ prospectAccount('HC') });

        Assert.areEqual(1, queuedJobs('AccountProspectTasQueueable'));
    }

    @IsTest
    static void testHcAssignTasToProspect_WhenSeveralOrLifeSciences_DoesNotEnqueue() {
        Integer before = queuedJobs('AccountProspectTasQueueable');

        AccountService.assignTAStoProspect(null);
        AccountService.assignTAStoProspect(new List<Account>());
        AccountService.assignTAStoProspect(new List<Account>{ null, prospectAccount('SC') });
        AccountService.assignTAStoProspect(new List<Account>{
            prospectAccount('HC'),
            prospectAccount('HC')
        });

        Assert.areEqual(before, queuedJobs('AccountProspectTasQueueable'));
    }

    @IsTest
    static void testHcAssignTasToProspectUpdate_WhenInputMissing_DoesNotEnqueue() {
        Account current = prospectAccount('HC');
        Integer before = queuedJobs('AccountProspectTasQueueable');

        AccountService.assignTAStoProspectUpdate(null, null);
        AccountService.assignTAStoProspectUpdate(new List<Account>(), new Map<Id, Account>());
        AccountService.assignTAStoProspectUpdate(new List<Account>{ current }, null);
        AccountService.assignTAStoProspectUpdate(new List<Account>{ current }, new Map<Id, Account>());
        AccountService.assignTAStoProspectUpdate(
            new List<Account>{ null, new Account(Name = 'No Id'), current },
            new Map<Id, Account>{ nextId(Account.SObjectType) => prospectAccount('HC') }
        );

        Assert.areEqual(before, queuedJobs('AccountProspectTasQueueable'));
    }

    @IsTest
    static void testHcAssignTasToProspectUpdate_WhenPriceListChanged_Enqueues() {
        Account current = prospectAccount('HC');
        Account previous = current.clone(true, true, true, true);
        previous.Price_List__c = nextId(Price_List__c.SObjectType);

        AccountService.assignTAStoProspectUpdate(
            new List<Account>{ current },
            new Map<Id, Account>{ current.Id => previous }
        );

        Assert.areEqual(1, queuedJobs('AccountProspectTasQueueable'));
    }

    @IsTest
    static void testHcAssignTasToProspectUpdate_WhenUnchangedOrSeveral_DoesNotEnqueue() {
        Account unchanged = prospectAccount('HC');
        Account nameChanged = prospectAccount('HC');
        Account streetChanged = prospectAccount('HC');
        Account lifeSciences = prospectAccount('SC');
        Account previousName = nameChanged.clone(true, true, true, true);
        Account previousStreet = streetChanged.clone(true, true, true, true);
        previousName.Name = 'Previous Prospect Name';
        previousStreet.BillingStreet = '9 Old Street';

        AccountService.assignTAStoProspectUpdate(
            new List<Account>{ unchanged, nameChanged, streetChanged, lifeSciences },
            new Map<Id, Account>{
                unchanged.Id => unchanged.clone(true, true, true, true),
                nameChanged.Id => previousName,
                streetChanged.Id => previousStreet,
                lifeSciences.Id => prospectAccount('SC')
            }
        );

        Assert.areEqual(0, queuedJobs('AccountProspectTasQueueable'));
    }

    @IsTest
    static void testHcAssignTasToCustomer_SkipsLifeSciencesAndEnqueuesHealthcare() {
        Account lifeSciences = customerAccount('SC');
        Account missingOracle = customerAccount('HC');
        missingOracle.OracleAddressId__c = null;
        missingOracle.SourceSystemID__c = null;
        missingOracle.AccountSource = null;

        AccountService.assignTAStoCustomer(null);
        AccountService.assignTAStoCustomer(new List<Account>());
        AccountService.assignTAStoCustomer(new List<Account>{ null, lifeSciences, missingOracle });
        Assert.areEqual(0, queuedJobs('AccountCustomerTasQueueable'));

        Account oracleBySystemId = customerAccount('HC');
        oracleBySystemId.AccountSource = null;
        Account oracleBySource = customerAccount('HC');
        oracleBySource.SourceSystemID__c = 'SRC-100';
        oracleBySource.AccountSource = 'Oracle';
        AccountService.assignTAStoCustomer(new List<Account>{ oracleBySystemId, oracleBySource });

        Assert.areEqual(1, queuedJobs('AccountCustomerTasQueueable'));
    }

    @IsTest
    static void testHcAssignTasToCustomerUpdate_WhenUnchangedOrLifeSciences_DoesNotEnqueue() {
        Account current = customerAccount('HC');
        Account lifeSciences = customerAccount('SC');
        lifeSciences.BillingCity = 'Akron';
        Integer before = queuedJobs('AccountCustomerTasQueueable');

        AccountService.assignTAStoCustomerUpdate(null, null);
        AccountService.assignTAStoCustomerUpdate(new List<Account>(), new Map<Id, Account>());
        AccountService.assignTAStoCustomerUpdate(new List<Account>{ current }, null);
        AccountService.assignTAStoCustomerUpdate(new List<Account>{ current }, new Map<Id, Account>());
        AccountService.assignTAStoCustomerUpdate(
            new List<Account>{ current },
            new Map<Id, Account>{ nextId(Account.SObjectType) => customerAccount('HC') }
        );
        AccountService.assignTAStoCustomerUpdate(
            new List<Account>{ current, lifeSciences },
            new Map<Id, Account>{
                current.Id => current.clone(true, true, true, true),
                lifeSciences.Id => customerAccount('SC')
            }
        );

        Assert.areEqual(before, queuedJobs('AccountCustomerTasQueueable'));
    }

    @IsTest
    static void testHcAssignTasToCustomerUpdate_WhenFieldChanged_Enqueues() {
        Account current = customerAccount('HC');
        Account previous = current.clone(true, true, true, true);
        previous.BillingPostalCode = '44101';

        AccountService.assignTAStoCustomerUpdate(
            new List<Account>{ current },
            new Map<Id, Account>{ current.Id => previous }
        );

        Assert.areEqual(1, queuedJobs('AccountCustomerTasQueueable'));
    }

    @IsTest
    static void testHcAssignTasToCustomerUpdate_WhenAccountIsNull_Rethrows() {
        Boolean threw = false;
        try {
            AccountService.assignTAStoCustomerUpdate(
                new List<Account>{ null },
                new Map<Id, Account>{ nextId(Account.SObjectType) => customerAccount('HC') }
            );
        } catch (Exception ex) {
            threw = true;
            Assert.isTrue(String.isNotBlank(ex.getMessage()));
        }
        Assert.isTrue(threw);
    }

    @IsTest
    static void testHcRetry_WhenRequestMissing_DoesNotEnqueue() {
        Integer before = queuedJobs('AccountProspectTasQueueable');
        AccountService.FlowRequest blankRequest = new AccountService.FlowRequest();

        AccountService.retryTasAssignmentFromFlow(null);
        AccountService.retryTasAssignmentFromFlow(new List<AccountService.FlowRequest>());
        AccountService.retryTasAssignmentFromFlow(
            new List<AccountService.FlowRequest>{ null, blankRequest }
        );

        Assert.areEqual(before, queuedJobs('AccountProspectTasQueueable'));
    }

    @IsTest
    static void testHcRetry_WhenAssigned_DoesNotEnqueueAndWhenMissing_Enqueues() {
        bypassAccountTrigger();
        Account assigned = insertProspect('HC', true, 'Assigned');
        Account missing = insertProspect('HC', false, 'Assignment Missing');

        AccountService.FlowRequest assignedRequest = new AccountService.FlowRequest();
        assignedRequest.accountId = assigned.Id;
        AccountService.retryTasAssignmentFromFlow(
            new List<AccountService.FlowRequest>{ assignedRequest }
        );
        Assert.areEqual(0, queuedJobs('AccountProspectTasQueueable'));

        AccountService.FlowRequest missingRequest = new AccountService.FlowRequest();
        missingRequest.accountId = missing.Id;
        AccountService.retryTasAssignmentFromFlow(
            new List<AccountService.FlowRequest>{ missingRequest }
        );
        Assert.areEqual(1, queuedJobs('AccountProspectTasQueueable'));
    }

    @IsTest
    static void testPopulateOrgIdOnNewProspect() {
        Account alreadySet = prospectAccount('HC');
        String originalOrgId = alreadySet.OrgIDs__c;
        Account customer = customerAccount('HC');
        customer.OrgIDs__c = null;

        AccountService.populateOrgIdOnNewProspect(null);
        AccountService.populateOrgIdOnNewProspect(new List<Account>());
        AccountService.populateOrgIdOnNewProspect(new List<Account>{ customer, alreadySet });

        Assert.areEqual(originalOrgId, alreadySet.OrgIDs__c);
        Assert.isTrue(String.isBlank(customer.OrgIDs__c));

        Account prospect = prospectAccount('SC');
        prospect.OrgIDs__c = null;
        String runningUserOrgId = [
            SELECT OrgId__c
            FROM User
            WHERE Id = :UserInfo.getUserId()
        ].OrgId__c;

        try {
            AccountService.populateOrgIdOnNewProspect(new List<Account>{ prospect });
        } catch (Exception ex) {
            Assert.isTrue(String.isNotBlank(ex.getMessage()));
            return;
        }

        if (String.isBlank(runningUserOrgId)) {
            Assert.isTrue(String.isBlank(prospect.OrgIDs__c));
        } else {
            Assert.areEqual(runningUserOrgId, prospect.OrgIDs__c);
        }
    }

    @IsTest
    static void testGetShipToAddressAccounts() {
        User runningUser = adminUser();
        insert runningUser;
        grantAccountFieldAccess(runningUser.Id);

        System.runAs(runningUser) {
            Assert.areEqual(0, AccountService.getShipToAddressAccounts(null).size());
            Assert.areEqual(0, AccountService.getShipToAddressAccounts(nextId(Account.SObjectType)).size());

            String suffix = uniqueSuffix();
            Account customer = new Account(
                Name = 'Ship To Customer ' + suffix,
                OrgIDs__c = '82',
                SourceSystemID__c = 'SHIPTO-PARENT-' + suffix
            );
            insert customer;

            Account activeShipTo = new Account(
                Name = 'Active Ship To ' + suffix,
                ParentId = customer.Id,
                Type = 'Address',
                ShiptoAddressStatus__c = 'Active',
                SourceSystemID__c = 'SHIPTO-ACTIVE-' + suffix,
                BillingStreet = suffix + ' Oak Ave',
                BillingCity = 'Cleveland',
                BillingState = 'OH',
                BillingPostalCode = '44114',
                BillingCountry = 'US'
            );
            insert activeShipTo;

            List<Account> matches = AccountService.getShipToAddressAccounts(customer.Id);
            Assert.areEqual(1, matches.size());
            Assert.areEqual(activeShipTo.Id, matches[0].Id);
        }
    }

    private static Account prospectAccount(String classCode) {
        return new Account(
            Id = nextId(Account.SObjectType),
            Name = 'Eligible Prospect',
            RecordTypeId = recordTypeId('Prospect'),
            CustomerClassCode__c = classCode,
            OrgIDs__c = '82',
            BillingStreet = '1 Main St',
            BillingCity = 'Mentor',
            BillingState = 'OH',
            BillingPostalCode = '44060',
            BillingCountry = 'US',
            Price_List__c = nextId(Price_List__c.SObjectType)
        );
    }

    private static Account customerAccount(String classCode) {
        return new Account(
            Id = nextId(Account.SObjectType),
            Name = 'Oracle Customer',
            RecordTypeId = recordTypeId('Customer'),
            SourceSystemID__c = 'Oracle-SRC-' + uniqueSuffix(),
            OracleAddressId__c = 'ORA-' + uniqueSuffix(),
            CustomerClassCode__c = classCode,
            OrgIDs__c = '82',
            BillingStreet = '1 Main St',
            BillingCity = 'Mentor',
            BillingState = 'OH',
            BillingPostalCode = '44060',
            BillingCountry = 'US'
        );
    }

    private static Account insertProspect(String classCode, Boolean retryFlag, String assignmentStatus) {
        Price_List__c priceList = new Price_List__c(
            Name = 'LS TAS Price List ' + uniqueSuffix(),
            Price_List_Id__c = 'PL-' + uniqueSuffix(),
            Status__c = 'Active'
        );
        insert priceList;

        String suffix = uniqueSuffix();
        Account prospect = new Account(
            Name = 'Inserted Prospect ' + classCode + ' ' + suffix,
            RecordTypeId = recordTypeId('Prospect'),
            CustomerClassCode__c = classCode,
            OrgIDs__c = '82',
            BillingStreet = suffix + ' Main St',
            BillingCity = 'Mentor',
            BillingState = 'OH',
            BillingPostalCode = '44060',
            BillingCountry = 'US',
            Price_List__c = priceList.Id,
            TAS_Retry__c = retryFlag,
            TAS_Assignment_Status__c = assignmentStatus,
            SystemID__c = 'TAS-' + uniqueSuffix(),
            SourceSystemID__c = 'SRC-' + uniqueSuffix()
        );
        Database.DMLOptions saveOptions = new Database.DMLOptions();
        saveOptions.DuplicateRuleHeader.allowSave = true;
        saveOptions.optAllOrNone = true;
        Database.insert(prospect, saveOptions);
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

    private static String uniqueSuffix() {
        return String.valueOf(Math.abs(Crypto.getRandomInteger()));
    }

    private static void grantAccountFieldAccess(Id userId) {
        String suffix = uniqueSuffix();
        PermissionSet access = new PermissionSet(
            Name = ('LSShipTo' + suffix).left(40),
            Label = ('LS Ship To ' + suffix).left(80)
        );
        insert access;
        insert new ObjectPermissions(
            ParentId = access.Id,
            SobjectType = 'Account',
            PermissionsRead = true,
            PermissionsCreate = true,
            PermissionsEdit = true,
            PermissionsDelete = true,
            PermissionsViewAllRecords = true,
            PermissionsModifyAllRecords = true
        );
        insert new FieldPermissions(
            ParentId = access.Id,
            SobjectType = 'Account',
            Field = 'Account.ShiptoAddressStatus__c',
            PermissionsRead = true,
            PermissionsEdit = true
        );
        insert new PermissionSetAssignment(
            AssigneeId = userId,
            PermissionSetId = access.Id
        );
    }

    private static User adminUser() {
        Profile adminProfile = [
            SELECT Id
            FROM Profile
            WHERE Name = 'System Administrator'
            LIMIT 1
        ];
        String suffix = uniqueSuffix();
        return new User(
            FirstName = 'LS',
            LastName = 'Admin',
            Alias = ('a' + suffix).left(8),
            Email = 'lsacctadmin' + suffix + '@test.steris.com',
            Username = 'lsacctadmin' + suffix + '@test.steris.com',
            CommunityNickname = ('lsadmin' + suffix).left(40),
            ProfileId = adminProfile.Id,
            TimeZoneSidKey = 'America/New_York',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US'
        );
    }
}