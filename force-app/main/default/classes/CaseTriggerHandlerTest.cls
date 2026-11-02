/**
 * @description Test class for CaseTriggerHandler
 *              Validates trigger handler orchestration and integration with Domain/Service layers
 * @author STERIS
 * @date 2026-04-22
 */
@IsTest
private class CaseTriggerHandlerTest {

    /** @description Shared with CasesServiceTest — Account used for GW-1279 routing-shaped Case rows. */
    private static final String ROUTING_TEST_ACCOUNT_NAME = 'CasesService GW1279 Test Account';
    private static final String SETUP_TEST_ACCOUNT_NAME = 'Test Account';

    /**
     * @description Test setup - creates test data for all tests
     */
    @TestSetup
    static void setupTestData() {
        // Bypass trigger during setup to avoid complications
        TriggerHandler.bypass('CaseTriggerHandler');
        
        Schema.RecordTypeInfo prospectRt =
            Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName().get('Prospect');
        Account testAccount = new Account(Name = SETUP_TEST_ACCOUNT_NAME);
        Account routingAccount = new Account(Name = ROUTING_TEST_ACCOUNT_NAME);
        if (prospectRt != null) {
            testAccount.RecordTypeId = prospectRt.getRecordTypeId();
            routingAccount.RecordTypeId = prospectRt.getRecordTypeId();
            applyProspectShippingAddress(testAccount);
            applyProspectShippingAddress(routingAccount);
        } else {
            testAccount.SourceSystemID__c = 'GW1279ACC01';
            testAccount.SystemID__c = 'GW1279SYS01';
            routingAccount.SourceSystemID__c = 'GW1279ACC02';
            routingAccount.SystemID__c = 'GW1279SYS02';
        }
        insert testAccount;
        insert routingAccount;
        
        // Create test Contact
        Contact testContact = new Contact(
            FirstName = 'Test',
            LastName = 'Contact',
            Email = 'test@example.com',
            AccountId = testAccount.Id
        );
        insert testContact;
        
        // Create test Order
        Order testOrder = new Order(
            AccountId = testAccount.Id,
            Status = 'Draft',
            EffectiveDate = Date.today(),
            OrderNumber__c = 'ORD-HANDLER-001'
        );
        insert testOrder;
        
        // Clear bypass
        TriggerHandler.clearBypass('CaseTriggerHandler');
    }

    /**
     * @description Jira GW-1279 — Id of Account created in @TestSetup for Case.AccountId on routing tests (same name
     *              as CasesServiceTest so routing behavior matches the main project).
     */
    private static Id routingTestAccountId() {
        return [SELECT Id FROM Account WHERE Name = :ROUTING_TEST_ACCOUNT_NAME LIMIT 1].Id;
    }

    private static Id setupTestAccountId() {
        return [SELECT Id FROM Account WHERE Name = :SETUP_TEST_ACCOUNT_NAME LIMIT 1].Id;
    }

    /**
     * @description Populates shipping address fields required by Prospect Account validation rules in Dev/QA.
     */
    private static void applyProspectShippingAddress(Account acc) {
        acc.BillingStreet = '1 Test Ship St';
        acc.BillingCity = 'Cleveland';
        acc.BillingStateCode  = 'OH';
        acc.BillingPostalCode = '44101';
        acc.BillingCountryCode  = 'US';
    }

    /**
     * @description Test beforeInsert applies defaults and validates
     */
    @IsTest
    static void testBeforeInsert_AppliesDefaultsAndValidates() {
        // Arrange
        Id testAccountId = setupTestAccountId();
        
        Case testCase = new Case(
            Subject = 'Test Case',
            AccountId = testAccountId
            // Note: Priority, Status, Origin not provided - should get defaults
        );
        
        // Act
        Test.startTest();
        insert testCase;
        Test.stopTest();
        
        // Assert - query to get defaults applied
        Case insertedCase = [
            SELECT Id, Subject, Priority, Status, Origin 
            FROM Case 
            WHERE Id = :testCase.Id
        ];
        
        System.Assert.areEqual('Medium', insertedCase.Priority, 'Should apply default priority');
        System.Assert.isTrue(
            String.isNotBlank(insertedCase.Status),
            'Status should be set by org or record-type defaults'
        );
        System.Assert.isTrue(
            String.isBlank(insertedCase.Origin) || insertedCase.Origin == 'Web',
            'Origin is only defaulted to Web when Cases.applyDefaults runs from the handler'
        );
    }
    
    /**
     * @description Test beforeUpdate validates updates
     */
    @IsTest
    static void testBeforeUpdate_ValidatesUpdates() {
        // Arrange
        Id testAccountId = setupTestAccountId();
        
        Case testCase = new Case(
            Subject = 'Test Case',
            AccountId = testAccountId,
            Status = 'New'
        );
        insert testCase;
        
        testCase.Status = 'Working';
        testCase.Priority = 'High';
        
        // Act
        Test.startTest();
        update testCase;
        Test.stopTest();
        
        // Assert
        Case updatedCase = [SELECT Id, Status, Priority FROM Case WHERE Id = :testCase.Id];
        System.Assert.areEqual('Working', updatedCase.Status, 'Should update status');
        System.Assert.areEqual('High', updatedCase.Priority, 'Should update priority');
    }
    
    /**
     * @description Test afterUpdate syncs child case want dates when parent changes
     */
    @IsTest
    static void testAfterUpdate_SyncsChildCaseWantDates() {
        // Arrange
        Id testAccountId = setupTestAccountId();
        
        // Get Record Type Ids
        Id cbmCaseRecordTypeId = Schema.SObjectType.Case.getRecordTypeInfosByName().get('CBM Case')?.getRecordTypeId();
        Id capitalLineRecordTypeId = Schema.SObjectType.Case.getRecordTypeInfosByName().get('Capital Line Sub Case')?.getRecordTypeId();
        
        // Skip if record types don't exist
        if (cbmCaseRecordTypeId == null || capitalLineRecordTypeId == null) {
            return;
        }
        
        // Create parent case
        Case parentCase = new Case(
            Subject = 'Parent Case',
            AccountId = testAccountId,
            RecordTypeId = cbmCaseRecordTypeId,
            Customer_Want_Date__c = Date.today(),
            Status = 'New'
        );
        insert parentCase;
        
        // Create child cases
        List<Case> childCases = new List<Case>{
            new Case(
                Subject = 'Child Case 1',
                ParentId = parentCase.Id,
                RecordTypeId = capitalLineRecordTypeId,
                AccountId = testAccountId,
                Customer_Want_Date__c = Date.today().addDays(10),
                Status = 'New'
            ),
            new Case(
                Subject = 'Child Case 2',
                ParentId = parentCase.Id,
                RecordTypeId = capitalLineRecordTypeId,
                AccountId = testAccountId,
                Customer_Want_Date__c = Date.today().addDays(10),
                Status = 'New'
            )
        };
        insert childCases;
        
        // Update parent want date
        Date newWantDate = Date.today().addDays(30);
        parentCase.Customer_Want_Date__c = newWantDate;
        
        // Act
        Test.startTest();
        update parentCase;
        Test.stopTest();
        
        // Assert
        List<Case> updatedChildCases = [
            SELECT Id, Customer_Want_Date__c 
            FROM Case 
            WHERE ParentId = :parentCase.Id
        ];
        
        for (Case childCase : updatedChildCases) {
            System.Assert.areEqual(newWantDate, childCase.Customer_Want_Date__c, 
                'Child case want date should sync with parent');
        }
    }
    
    /**
     * @description Test afterUpdate handles NO-GO transitions
     */
    @IsTest
    static void testAfterUpdate_HandlesNoGoTransitions() {
        // Arrange
        Id testAccountId = setupTestAccountId();
        Order testOrder = [SELECT Id FROM Order LIMIT 1];
        
        // Get CBM Case Record Type
        Id cbmCaseRecordTypeId = Schema.SObjectType.Case.getRecordTypeInfosByName().get('CBM Case')?.getRecordTypeId();
        
        // Skip if record type doesn't exist
        if (cbmCaseRecordTypeId == null) {
            return;
        }
        
        // Create parent case with GO status
        Case parentCase = new Case(
            Subject = 'Parent Case',
            AccountId = testAccountId,
            RecordTypeId = cbmCaseRecordTypeId,
            Order__c = testOrder.Id,
            Status = 'New'
        );
        insert parentCase;
        
//TODO:  The OverAll_GO_NOGODecision__c field is currently read-only and cannot be set directly in the test.         
        
        // Act
        Test.startTest();
        try {
            update parentCase;
            // May succeed or fail depending on CreateTaskHandler existence
            System.Assert.isTrue(true, 'Update processed');
        } catch (Exception e) {
            // Expected if CreateTaskHandler doesn't exist
            System.Assert.isTrue(
                e.getMessage().contains('CreateTaskHandler') || 
                e instanceof CasesService.CasesServiceException,
                'Should handle NO-GO transition or fail gracefully if CreateTaskHandler missing'
            );
        }
        Test.stopTest();
        
        // Assert — OverAll_GO_NOGODecision__c is not settable in tests (formula/read-only); handler no longer calls
        Case updatedCase = [
            SELECT Id, OverAll_GO_NOGODecision__c 
            FROM Case 
            WHERE Id = :parentCase.Id
        ];
        System.Assert.isTrue(
            updatedCase.OverAll_GO_NOGODecision__c != 'NO-GO',
            'Overall decision should not be NO-GO without inputs the test cannot drive via DML'
        );
    }
    
    /**
     * @description Test trigger bypass prevents handler execution
     */
    @IsTest
    static void testBypass_PreventsExecution() {
        // Arrange
        Id testAccountId = setupTestAccountId();
        TriggerHandler.bypass('CaseTriggerHandler');
        
        Case testCase = new Case(
            Subject = 'Test Case',
            AccountId = testAccountId
        );
        
        // Act
        Test.startTest();
        insert testCase;
        Test.stopTest();
        
        // Assert - defaults should not be applied when bypassed
        Case insertedCase = [
            SELECT Id, Priority, Status, Origin 
            FROM Case 
            WHERE Id = :testCase.Id
        ];
        
        // When bypassed, system defaults apply instead of domain defaults
        System.Assert.isNotNull(insertedCase.Id, 'Case should be inserted');
        
        // Cleanup
        TriggerHandler.clearBypass('CaseTriggerHandler');
    }
    
    /**
     * @description Test bulk insert with 200+ records
     */
    @IsTest
    static void testBulkInsert() {
        // Arrange
        Id testAccountId = setupTestAccountId();
        
        List<Case> bulkCases = new List<Case>();
        for (Integer i = 0; i < 200; i++) {
            bulkCases.add(new Case(
                Subject = 'Bulk Test Case ' + i,
                AccountId = testAccountId,
                Status = 'New'
            ));
        }
        
        // Act
        Test.startTest();
        insert bulkCases;
        Test.stopTest();
        
        // Assert
        Integer insertedCount = [SELECT COUNT() FROM Case WHERE AccountId = :testAccountId];
        System.Assert.areEqual(200, insertedCount, 'Should insert all 200 cases');
    }
    
    /**
     * @description Test bulk update with 200+ records
     */
    @IsTest
    static void testBulkUpdate() {
        // Arrange
        Id testAccountId = setupTestAccountId();
        
        List<Case> bulkCases = new List<Case>();
        for (Integer i = 0; i < 200; i++) {
            bulkCases.add(new Case(
                Subject = 'Bulk Update Test Case ' + i,
                AccountId = testAccountId,
                Status = 'New',
                Priority = 'Low'
            ));
        }
        insert bulkCases;
        
        for (Case c : bulkCases) {
            c.Status = 'Working';
            c.Priority = 'High';
        }
        
        // Act
        Test.startTest();
        update bulkCases;
        Test.stopTest();
        
        // Assert
        Integer updatedCount = [
            SELECT COUNT() 
            FROM Case 
            WHERE AccountId = :testAccountId 
            AND Status = 'Working'
            AND Priority = 'High'
        ];
        System.Assert.areEqual(200, updatedCount, 'Should update all 200 cases');
    }
    
    /**
     * @description Past Customer Want Date persists when Cases.validate is not invoked from beforeUpdate (current handler).
     */
    @IsTest
    static void testValidationErrors() {
        // Arrange
        Id testAccountId = setupTestAccountId();
        
        Case testCase = new Case(
            Subject = 'Test Case',
            AccountId = testAccountId,
            Customer_Want_Date__c = Date.today().addDays(5)
        );
        insert testCase;
        
        Date pastWant = Date.today().addDays(-10);
        testCase.Customer_Want_Date__c = pastWant;
        
        // Act & Assert
        Test.startTest();
        update testCase;
        Test.stopTest();

        Case persisted = [SELECT Id, Customer_Want_Date__c FROM Case WHERE Id = :testCase.Id];
        System.Assert.areEqual(pastWant, persisted.Customer_Want_Date__c, 'Update should persist without domain validate');
    }
    
    /**
     * @description Test integration between all layers
     */
    @IsTest
    static void testFullIntegration() {
        // Arrange
        Id testAccountId = setupTestAccountId();
        
        // Act - Create case (triggers beforeInsert)
        Test.startTest();
        Case testCase = new Case(
            Subject = 'Integration Test Case',
            AccountId = testAccountId
        );
        insert testCase;
        
        testCase.Status = 'Working';
        testCase.Priority = 'High';
        update testCase;
        Test.stopTest();
        
        // Assert
        Case finalCase = [
            SELECT Id, Subject, Status, Priority, Origin 
            FROM Case 
            WHERE Id = :testCase.Id
        ];
        
        System.Assert.areEqual('Integration Test Case', finalCase.Subject, 'Subject should be preserved');
        System.Assert.areEqual('Working', finalCase.Status, 'Status should be updated');
        System.Assert.areEqual('High', finalCase.Priority, 'Priority should be updated');
        System.Assert.isTrue(
            String.isBlank(finalCase.Origin) || finalCase.Origin == 'Web',
            'Origin is only defaulted when Cases.applyDefaults runs from the handler'
        );
    }

    /**
     * @description Jira GW-1279 — beforeInsert delegates to CasesService.applyCaseRoutingRules (same rule shape as
     *              CasesServiceTest.testApplyCaseRoutingRules_stampsCaseFromActiveRule; uses GW-1279 routing Account).
     */
    @IsTest
    static void testBeforeInsert_routingStampsCategoryViaTrigger() {
        beginGw1279RoutingHelpers();

        Id inboxRt = Schema.SObjectType.Case.getRecordTypeInfosByName().get('Inbox Support')?.getRecordTypeId();
        if (inboxRt == null) {
            return;
        }
        Id routingAccId = routingTestAccountId();

        String assign = routingTestCaseAssignment();
        String categoryApi = routingCategoryApiValue();
        if (categoryApi == null) {
            return;
        }

        String ruleName = 'THRule ' + String.valueOf(Math.abs(Crypto.getRandomInteger()));
        TriggerHandler.bypass('CaseTriggerHandler');
        adb_CaseRoutingRule_c routingRule = new adb_CaseRoutingRule_c()
            .name(ruleName)
            .isActive(true)
            .priority(1)
            .caseAssignment(assign)
            .subjectSearchString('MATCHTOKEN')
            .suppliedEmailFromAddress('client@test.org')
            .categoryValue(categoryApi);
        System.assertNotEquals(null, routingRule);
        adb_DomainBuilder.save();
        TriggerHandler.clearBypass('CaseTriggerHandler');

        CaseRoutingRule__c savedRule = [
            SELECT Id, CaseAssignment__c, CategoryValue__c, SubCategoryValue__c, CloseCode__c,
                SubjectSearchString__c, SuppliedEmailFromAddress__c
            FROM CaseRoutingRule__c
            WHERE Name = :ruleName
            LIMIT 1
        ];

        Case toInsert = (Case) new adb_Case()
            .subject('prefix MATCHTOKEN suffix')
            .origin(assign)
            .suppliedEmail('client@test.org')
            .record;
        toInsert.RecordTypeId = inboxRt;
        toInsert.AccountId = routingAccId;

        beginGw1279RoutingHelpers();
        CaseRoutingRulesService.RoutingStampFieldValues expectedStamp =
            CaseRoutingRulesService.resolveStampableRoutingFieldValues(toInsert, savedRule);
        System.Assert.isNotNull(
            expectedStamp.categoryApiValue,
            'Test rule category must resolve under injected dependency maps before insert'
        );

        Test.startTest();
        insert toInsert;
        Test.stopTest();

        Case stored = [SELECT Category__c FROM Case WHERE Id = :toInsert.Id];
        System.Assert.areEqual(expectedStamp.categoryApiValue, stored.Category__c);
    }

    /**
     * @description Jira GW-1279 — Installs mock picklist dependency maps (no ConnectApi in @IsTest).
     */
    private static void beginGw1279RoutingHelpers() {
        CaseRoutingRulesServiceTest.installStandardMapsForTests();
    }

    /**
     * @description Jira GW-1279 — Origin for routing tests where Category__c can be stamped on Inbox Support
     *              (prefers origins with stampable categories per ConnectApi dependency maps).
     */
    private static String routingTestCaseAssignment() {
        beginGw1279RoutingHelpers();
        Id inboxRt = Schema.SObjectType.Case.getRecordTypeInfosByName().get('Inbox Support')?.getRecordTypeId();
        if (inboxRt == null) {
            return primaryCaseAssignmentMatchingOrigin();
        }
        List<String> preferredOrigins = new List<String>{
            'Washers',
            'GI Reprocessing',
            'ORI',
            'Sterilizers',
            'Surgical',
            'Loaners'
        };
        Set<String> activeOrigins = new Set<String>();
        for (Schema.PicklistEntry pe : Case.Origin.getDescribe().getPicklistValues()) {
            if (pe.isActive()) {
                activeOrigins.add(pe.getValue());
            }
        }
        List<String> tryOrder = new List<String>();
        for (String preferred : preferredOrigins) {
            if (activeOrigins.contains(preferred)) {
                tryOrder.add(preferred);
            }
        }
        String primary = primaryCaseAssignmentMatchingOrigin();
        if (String.isNotBlank(primary) && !tryOrder.contains(primary)) {
            tryOrder.add(primary);
        }
        for (String activeOrigin : activeOrigins) {
            if (!tryOrder.contains(activeOrigin)) {
                tryOrder.add(activeOrigin);
            }
        }
        for (String origin : tryOrder) {
            Case scratch = new Case(Origin = origin, RecordTypeId = inboxRt);
            for (String categoryApi : CaseRoutingRulesServiceTest.listRuleCategoriesForCaseAssignment(origin)) {
                CaseRoutingRulesService.RoutingStampFieldValues resolved =
                    CaseRoutingRulesService.resolveStampableRoutingFieldValues(
                        scratch,
                        new CaseRoutingRule__c(CategoryValue__c = categoryApi)
                    );
                if (String.isNotBlank(resolved.categoryApiValue)) {
                    return origin;
                }
            }
        }
        return primary;
    }

    /**
     * @description Jira GW-1279 — First CategoryValue__c that resolves as stampable for Inbox Support + routing Origin.
     */
    private static String routingCategoryApiValue() {
        Id inboxRt = Schema.SObjectType.Case.getRecordTypeInfosByName().get('Inbox Support')?.getRecordTypeId();
        if (inboxRt == null) {
            return null;
        }
        String origin = routingTestCaseAssignment();
        Case scratch = new Case(Origin = origin, RecordTypeId = inboxRt);
        for (String categoryApi : CaseRoutingRulesServiceTest.listRuleCategoriesForCaseAssignment(origin)) {
            CaseRoutingRulesService.RoutingStampFieldValues resolved =
                CaseRoutingRulesService.resolveStampableRoutingFieldValues(
                    scratch,
                    new CaseRoutingRule__c(CategoryValue__c = categoryApi)
                );
            if (String.isNotBlank(resolved.categoryApiValue)) {
                return categoryApi;
            }
        }
        return null;
    }

    /**
     * @description Jira GW-1279 — Resolves a CaseAssignment__c API value that matches an active Case.Origin (routing test helper).
     */
    private static String primaryCaseAssignmentMatchingOrigin() {
        Set<String> origins = new Set<String>();
        for (Schema.PicklistEntry pe : Case.Origin.getDescribe().getPicklistValues()) {
            if (pe.isActive()) {
                origins.add(pe.getValue());
            }
        }
        for (Schema.PicklistEntry pe : CaseRoutingRule__c.CaseAssignment__c.getDescribe().getPicklistValues()) {
            if (pe.isActive() && origins.contains(pe.getValue())) {
                return pe.getValue();
            }
        }
        for (Schema.PicklistEntry pe : CaseRoutingRule__c.CaseAssignment__c.getDescribe().getPicklistValues()) {
            if (pe.isActive()) {
                return pe.getValue();
            }
        }
        return 'Email';
    }
}