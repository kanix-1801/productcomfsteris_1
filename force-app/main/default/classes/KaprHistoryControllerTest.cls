/**
 * @description GC-2615 - Tests KAPR history as a Sales Field Rep persona.
 */
@IsTest
private class KaprHistoryControllerTest {
    private static final String SALES_REP_EMPLOYEE_NUMBER = 'KAPR-HISTORY-REP';
    private static final String IDN_NAME = 'KAPR History IDN';
    private static final String CUSTOMER_NAME = 'KAPR History Customer';
    private static final String FACILITY_NAME = 'KAPR History Facility';

    @TestSetup
    static void createData() {
        User salesRep = createSalesRepUser();
        assignSalesRepAccess(salesRep.Id);

        System.runAs(salesRep) {
            Account idnAccount = createAccount(IDN_NAME, 'IDN', 'IDN01');
            Account customerAccount = createAccount(CUSTOMER_NAME, 'Customer', 'CUS01');
            Account facilityAccount = createAccount(FACILITY_NAME, 'Address', 'FAC01');
            Account unrelatedAccount =
                createAccount('KAPR History Unrelated', 'Customer', 'UNR01');
            insert new List<Account>{
                idnAccount,
                customerAccount,
                facilityAccount,
                unrelatedAccount
            };

            String relationshipType = getActiveRelationshipType();
            insert new List<AccountAccountRelationship__c>{
                new AccountAccountRelationship__c(
                    ParentAccount__c = idnAccount.Id,
                    ChildAccount__c = customerAccount.Id,
                    RelationshipType__c = relationshipType
                ),
                new AccountAccountRelationship__c(
                    ParentAccount__c = idnAccount.Id,
                    ChildAccount__c = facilityAccount.Id,
                    RelationshipType__c = relationshipType
                )
            };

            insert new List<KeyAccountProcessReview__c>{
                new KeyAccountProcessReview__c(
                    CustomerAccountOrfacility__c = customerAccount.Id,
                    AssessmentDate__c = Date.today(),
                    Department__c = 'Customer Department',
                    Completed__c = true
                ),
                new KeyAccountProcessReview__c(
                    CustomerAccountOrfacility__c = facilityAccount.Id,
                    AssessmentDate__c = Date.today().addDays(-1),
                    Department__c = 'Facility Department',
                    Completed__c = false
                ),
                new KeyAccountProcessReview__c(
                    CustomerAccountOrfacility__c = unrelatedAccount.Id,
                    AssessmentDate__c = Date.today().addDays(-2)
                ),
                new KeyAccountProcessReview__c(
                    CustomerAccountOrfacility__c = idnAccount.Id,
                    AssessmentDate__c = Date.today().addDays(-3)
                )
            };
        }
    }

    @IsTest
    static void returnsDirectReviewsForCustomer() {
        User salesRep = getSalesRepUser();

        System.runAs(salesRep) {
            Account customerAccount = [
                SELECT Id
                FROM Account
                WHERE Name = :CUSTOMER_NAME
                LIMIT 1
            ];

            Test.startTest();
            KeyAccountProcessReviewHistoryService.ProcessReviewHistoryResponse response =
                KeyAccountProcessReviewHistoryController.getProcessReviewHistory(
                    customerAccount.Id
                );
            Test.stopTest();

            System.assertEquals(false, response.isIdnView);
            System.assertEquals(1, response.relatedAccountCount);
            System.assertEquals(1, response.totalReviewCount);
            System.assertEquals(
                customerAccount.Id,
                response.reviews[0].CustomerAccountOrfacility__c
            );
        }
    }

    @IsTest
    static void returnsChildReviewsForIdn() {
        User salesRep = getSalesRepUser();

        System.runAs(salesRep) {
            Account idnAccount = [
                SELECT Id
                FROM Account
                WHERE Name = :IDN_NAME
                LIMIT 1
            ];

            Test.startTest();
            KeyAccountProcessReviewHistoryService.ProcessReviewHistoryResponse response =
                KeyAccountProcessReviewHistoryController.getProcessReviewHistory(idnAccount.Id);
            Test.stopTest();

            System.assertEquals(true, response.isIdnView);
            System.assertEquals(2, response.relatedAccountCount);
            System.assertEquals(2, response.totalReviewCount);

            Set<String> accountNames = new Set<String>();
            for (KeyAccountProcessReview__c reviewRecord : response.reviews) {
                accountNames.add(reviewRecord.CustomerAccountOrfacility__r.Name);
            }
            System.assertEquals(new Set<String>{ CUSTOMER_NAME, FACILITY_NAME }, accountNames);
        }
    }

    @IsTest
    static void returnsEmptyHistoryForIdnWithoutRelationships() {
        User salesRep = getSalesRepUser();

        System.runAs(salesRep) {
            Account emptyIdn = createAccount('KAPR Empty IDN', 'IDN', 'IDN02');
            insert emptyIdn;

            Test.startTest();
            KeyAccountProcessReviewHistoryService.ProcessReviewHistoryResponse response =
                KeyAccountProcessReviewHistoryController.getProcessReviewHistory(emptyIdn.Id);
            Test.stopTest();

            System.assertEquals(true, response.isIdnView);
            System.assertEquals(0, response.relatedAccountCount);
            System.assertEquals(0, response.totalReviewCount);
            System.assertEquals(0, response.reviews.size());
        }
    }

    @IsTest
    static void rejectsMissingAccountId() {
        User salesRep = getSalesRepUser();

        System.runAs(salesRep) {
            Test.startTest();
            try {
                KeyAccountProcessReviewHistoryController.getProcessReviewHistory(null);
                System.assert(false, 'Expected a KAPR history exception.');
            } catch (
                KeyAccountProcessReviewHistoryService.KaprHistoryException expectedException
            ) {
                System.assertNotEquals(null, expectedException);
            }
            Test.stopTest();
        }
    }

    @IsTest
    static void rejectsInaccessibleOrMissingAccount() {
        User salesRep = getSalesRepUser();

        System.runAs(salesRep) {
            Test.startTest();
            try {
                KeyAccountProcessReviewHistoryController.getProcessReviewHistory(
                    UserInfo.getUserId()
                );
                System.assert(false, 'Expected a KAPR history exception.');
            } catch (
                KeyAccountProcessReviewHistoryService.KaprHistoryException expectedException
            ) {
                System.assertNotEquals(null, expectedException);
            }
            Test.stopTest();
        }
    }

    @IsTest
    static void flagsDisplayLimitWhenReviewCountExceedsCap() {
        User salesRep = getSalesRepUser();

        System.runAs(salesRep) {
            Account customerAccount = [
                SELECT Id
                FROM Account
                WHERE Name = :CUSTOMER_NAME
                LIMIT 1
            ];

            insert new List<KeyAccountProcessReview__c>{
                new KeyAccountProcessReview__c(
                    CustomerAccountOrfacility__c = customerAccount.Id,
                    AssessmentDate__c = Date.today().addDays(-4)
                ),
                new KeyAccountProcessReview__c(
                    CustomerAccountOrfacility__c = customerAccount.Id,
                    AssessmentDate__c = Date.today().addDays(-5)
                )
            };

            KeyAccountProcessReviewHistoryService.reviewRowLimitOverride = 1;

            try {
                Test.startTest();
                KeyAccountProcessReviewHistoryService.ProcessReviewHistoryResponse response =
                    KeyAccountProcessReviewHistoryService.getProcessReviewHistory(
                        customerAccount.Id
                    );
                Test.stopTest();

                System.assertEquals(true, response.resultLimitReached);
                System.assertEquals(1, response.reviews.size());
                System.assertEquals(1, response.totalReviewCount);
            } finally {
                KeyAccountProcessReviewHistoryService.reviewRowLimitOverride = null;
            }
        }
    }

    @IsTest
    static void wrapsUnexpectedErrorsForTheCaller() {
        User salesRep = getSalesRepUser();

        System.runAs(salesRep) {
            Account customerAccount = [
                SELECT Id
                FROM Account
                WHERE Name = :CUSTOMER_NAME
                LIMIT 1
            ];

            KeyAccountProcessReviewHistoryService.forcedExceptionMethodName =
                'getProcessReviewHistory';

            Test.startTest();
            try {
                KeyAccountProcessReviewHistoryService.getProcessReviewHistory(customerAccount.Id);
                System.assert(false, 'Expected a KAPR history exception.');
            } catch (
                KeyAccountProcessReviewHistoryService.KaprHistoryException expectedException
            ) {
                System.assertEquals(
                    'Unable to load Key Account Process Review history.',
                    expectedException.getMessage()
                );
            } finally {
                KeyAccountProcessReviewHistoryService.forcedExceptionMethodName = null;
            }
            Test.stopTest();
        }
    }

    @IsTest
    static void selectorGuardsReturnEmptyCollections() {
        User salesRep = getSalesRepUser();

        System.runAs(salesRep) {
            Test.startTest();
            List<Account> accounts =
                KeyAccountProcessReviewHistorySelector.selectAccountById(null);
            List<AccountAccountRelationship__c> relationships =
                KeyAccountProcessReviewHistorySelector.selectChildrenByParentId(null);
            List<KeyAccountProcessReview__c> reviewsForEmptyScope =
                KeyAccountProcessReviewHistorySelector.selectReviewsByAccountIds(
                    new Set<Id>(),
                    10
                );
            List<KeyAccountProcessReview__c> reviewsForInvalidLimit =
                KeyAccountProcessReviewHistorySelector.selectReviewsByAccountIds(
                    new Set<Id>{ UserInfo.getUserId() },
                    0
                );
            Test.stopTest();

            System.assertEquals(0, accounts.size());
            System.assertEquals(0, relationships.size());
            System.assertEquals(0, reviewsForEmptyScope.size());
            System.assertEquals(0, reviewsForInvalidLimit.size());
        }
    }

    private static User createSalesRepUser() {
        Profile healthcareSalesProfile = [
            SELECT Id
            FROM Profile
            WHERE Name = 'Healthcare Sales'
            LIMIT 1
        ];
        String uniqueValue = String.valueOf(System.currentTimeMillis());

        User salesRep = new User(
            FirstName = 'KAPR',
            LastName = 'Sales Rep',
            Alias = 'kaprrep',
            Email = 'kapr.salesrep.' + uniqueValue + '@example.com',
            Username = 'kapr.salesrep.' + uniqueValue + '@example.com',
            CommunityNickname = 'kaprrep' + uniqueValue,
            TimeZoneSidKey = 'America/New_York',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            ProfileId = healthcareSalesProfile.Id,
            EmployeeNumber__c = SALES_REP_EMPLOYEE_NUMBER,
            IsActive = true
        );
        insert salesRep;
        return salesRep;
    }

    private static void assignSalesRepAccess(Id salesRepId) {
        PermissionSetGroup salesRepGroup = [
            SELECT Id, Status
            FROM PermissionSetGroup
            WHERE DeveloperName = 'SalesFieldRepAccountManagerPSG'
            LIMIT 1
        ];
        PermissionSet kaprPermissionSet = [
            SELECT Id
            FROM PermissionSet
            WHERE Name = 'KeyAccountProcessReviewPS'
            LIMIT 1
        ];
        
        // Force the group to "Updated" so assignments are allowed in test context
        Test.calculatePermissionSetGroup(salesRepGroup.Id);

        insert new List<PermissionSetAssignment>{
            new PermissionSetAssignment(
                AssigneeId = salesRepId,
                PermissionSetGroupId = salesRepGroup.Id
            ),
            new PermissionSetAssignment(
                AssigneeId = salesRepId,
                PermissionSetId = kaprPermissionSet.Id
            )
        };
    }

    private static User getSalesRepUser() {
        return [
            SELECT Id
            FROM User
            WHERE EmployeeNumber__c = :SALES_REP_EMPLOYEE_NUMBER
            LIMIT 1
        ];
    }

    private static Account createAccount(String name, String type, String uniqueCode) {
        return new Account(
            Name = name,
            Type = type,
            RecordTypeId = getCustomerRecordTypeId(),
            OrgIDs__c = '82',
            OracleAddressId__c = 'ADDR-' + uniqueCode,
            SourceSystemID__c = 'SRC-' + uniqueCode,
            BillingStreet = '100 Test Street',
            BillingCity = 'Mentor',
            BillingStateCode = 'OH',
            BillingPostalCode = '44060',
            BillingCountryCode = 'US'
        );
    }

    private static Id getCustomerRecordTypeId() {
        Schema.RecordTypeInfo customerRecordType =
            Account.SObjectType.getDescribe(SObjectDescribeOptions.DEFERRED)
                .getRecordTypeInfosByDeveloperName()
                .get('Customer');
        System.assertNotEquals(null, customerRecordType, 'Customer Account record type is required.');
        return customerRecordType.getRecordTypeId();
    }

    private static String getActiveRelationshipType() {
        for (
            Schema.PicklistEntry entry :
            AccountAccountRelationship__c.RelationshipType__c.getDescribe().getPicklistValues()
        ) {
            if (entry.isActive()) {
                return entry.getValue();
            }
        }

        System.assert(false, 'No active RelationshipType__c value found.');
        return null;
    }
}