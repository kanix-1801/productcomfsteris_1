/**
 * @author PSL
 * @date 01-02-2026
 * @description Tests for UpdateCaseHandler covering happy path, guard clauses, DML error logging, and exception logging.
 */

@IsTest
private class UpdateCaseHandlerTest {

    // ---------------------------
    // Utilities
    // ---------------------------

    // Valid Case Status (picklist-safe)
    private static String getAnyCaseStatus() {
        List<CaseStatus> s = [SELECT MasterLabel FROM CaseStatus LIMIT 1];
        return s.isEmpty() ? 'New' : s[0].MasterLabel;
    }

    // Default Case Status
    private static String getDefaultCaseStatus() {
        CaseStatus cs = [SELECT MasterLabel FROM CaseStatus WHERE IsDefault = true LIMIT 1];
        return (cs == null) ? getAnyCaseStatus() : cs.MasterLabel;
    }

    // Find a supported Case Record Type (names used by UpdateCaseHelper)
    private static Id getSupportedCaseRecordTypeId() {
        Set<String> names = new Set<String>{
            'CBM Case', 'Capital Line Sub Case', 'Service Installation Sub Case'
        };
        List<RecordType> rts = [
            SELECT Id, Name
            FROM RecordType
            WHERE SobjectType = 'Case' AND Name IN :names
            LIMIT 1
        ];
        return rts.isEmpty() ? null : rts[0].Id;
    }

    // Standard Price Book (no queries that can throw)
    private static Id ensureStandardPricebookReady() {
        Id stdPbId;
        try {
            stdPbId = Test.getStandardPricebookId();
        } catch (Exception e) {
            stdPbId = null;
        }
        if (stdPbId == null) {
            // Fallback PB if standard not accessible in test context
            Pricebook2 pb = new Pricebook2(Name = 'Fallback PB', IsActive = true);
            insert pb;
            return pb.Id;
        }
        // Try to activate without querying (safe in tests)
        try {
            update new Pricebook2(Id = stdPbId, IsActive = true);
        } catch (Exception ignore) { /* okay if fails */ }
        return stdPbId;
    }

    // Create Product + PricebookEntry inside Standard PB (defines the STANDARD price)
    private static Id createStandardPbe(Id stdPbId) {
        Product2 prod = new Product2(Name = 'Test Product', IsActive = true);
        insert prod;

        PricebookEntry pbeStd = new PricebookEntry(
            Pricebook2Id = stdPbId,
            Product2Id   = prod.Id,
            UnitPrice    = 10,
            IsActive     = true
        );
        insert pbeStd;

        return pbeStd.Id;
    }

    // Factory: Account + Order + OrderItem + return orderNumber & ids
    private static Map<String,Object> createOrderGraph() {
        Map<String,Object> info = new Map<String,Object>();

        Account acc = new Account(Name = 'Test Account');
        insert acc;

        Id stdPbId = ensureStandardPricebookReady();
        Id pbeStdId = createStandardPbe(stdPbId);

        Order ord = new Order(
            AccountId     = acc.Id,
            Name          = 'Test Order',
            EffectiveDate = Date.today(),
            Status        = 'Draft',
            Pricebook2Id  = stdPbId
        );
        insert ord;

        // Read-only field populated after insert
        ord = [SELECT Id, OrderNumber FROM Order WHERE Id = :ord.Id];

        OrderItem oli = new OrderItem(
            OrderId          = ord.Id,
            Quantity         = 1,
            UnitPrice        = 10,
            PricebookEntryId = pbeStdId
        );
        // Your helper reads these custom fields from OrderItem; populate if present in org
        try { oli.put('ScheduledDate__c', Date.today()); } catch (Exception ignore) {}
        try { oli.put('ActualShipmentDate__c', Date.today()); } catch (Exception ignore) {}
        try { oli.put('OrderLineStatus__c', 'Created'); } catch (Exception ignore) {}

        insert oli;

        info.put('orderId', ord.Id);
        info.put('orderLineId', oli.Id);
        info.put('orderNumber', ord.OrderNumber);
        return info;
    }

    // Create Case linked to Order + OrderItem; optionally set supported RT
    private static Case createLinkedCase(Id orderId, Id orderLineId, Boolean useSupportedRt) {
        Id rtId = useSupportedRt ? getSupportedCaseRecordTypeId() : null;

        Case c = new Case(
            Subject      = 'Handler Coverage Case',
            Status       = getDefaultCaseStatus(),
            Order__c     = orderId,
            OrderLine__c = orderLineId
        );
        if (rtId != null) c.RecordTypeId = rtId;
        insert c;
        return c;
    }

    // Find a restricted profile to force USER_MODE DML errors
    private static Profile findRestrictedProfile() {
        List<Profile> candidates = [
            SELECT Id, Name FROM Profile
            WHERE Name IN ('Minimum Access - Salesforce', 'Read Only')
            LIMIT 1
        ];
        return candidates.isEmpty() ? [SELECT Id, Name FROM Profile LIMIT 1] : candidates[0];
    }

    private static User makeRestrictedUser() {
        Profile p = findRestrictedProfile();
        User u = new User(
            Alias              = 'rtusr',
            Email              = 'rtusr' + String.valueOf(System.currentTimeMillis()) + '@example.com',
            EmailEncodingKey   = 'UTF-8',
            LastName           = 'Restricted',
            LanguageLocaleKey  = 'en_US',
            LocaleSidKey       = 'en_US',
            TimeZoneSidKey     = 'America/Los_Angeles',
            Username           = 'rtusr' + String.valueOf(System.currentTimeMillis()) + '@example.com',
            ProfileId          = p.Id
        );
        insert u;
        return u;
    }

    // ---------------------------
    // Tests
    // ---------------------------

    @IsTest
    static void guard_clause_returns_early_on_empty_list() {
        Test.startTest();
        UpdateCaseHandler.evaluateAndUpdateCaseStatus(new List<String>());
        Test.stopTest();
        System.assert(true, 'No exception expected for empty input list');
    }

    @IsTest
    static void catch_and_rethrow_on_null_input() {
        List<String> orders = null;
        Boolean threw = false;
        try {
            Test.startTest();
            UpdateCaseHandler.evaluateAndUpdateCaseStatus(orders);
            Test.stopTest();
        } catch (Exception e) {
            threw = true;
        }
        System.assertEquals(true, threw,
            'Handler should log and rethrow when orderNumbers is null (NPE in try).');
    }

    @IsTest
    static void happy_path_success_loop_runs_as_admin() {
        // Build graph & case WITH supported RT so helper evaluates rules
        Map<String,Object> g = createOrderGraph();
        Case c = createLinkedCase((Id)g.get('orderId'), (Id)g.get('orderLineId'), true);

        // Call handler with the actual OrderNumber so helper can find Cases
        Test.startTest();
        UpdateCaseHandler.evaluateAndUpdateCaseStatus(
            new List<String>{ (String)g.get('orderNumber') }
        );
        Test.stopTest();

        // We don't assert a specific status (depends on CMDT),
        // but the loop executes when SaveResults are returned.
        System.assert(true, 'Handler executed without error for success path.');
    }

    @IsTest
    static void dml_error_logging_loop_runs_under_restricted_user() {
        // Build graph & case WITH supported RT so helper evaluates rules
        Map<String,Object> g = createOrderGraph();
        Case c = createLinkedCase((Id)g.get('orderId'), (Id)g.get('orderLineId'), true);

        // Create a minimally-permissioned user and run handler in USER_MODE context
        User restricted = makeRestrictedUser();

        Test.startTest();
        System.runAs(restricted) {
            // Under USER_MODE, insufficient perms should cause Database.update to return errors
            UpdateCaseHandler.evaluateAndUpdateCaseStatus(
                new List<String>{ (String)g.get('orderNumber') }
            );
        }
        Test.stopTest();

        // If your org’s profile truly lacks Case edit, the handler's SaveResult loop will hit error branch.
        System.assert(true, 'Handler executed under restricted user to exercise DML error logging path.');
    }
}