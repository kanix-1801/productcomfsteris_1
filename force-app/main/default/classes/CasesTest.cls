/**
 * @description Test class for Cases domain class
 *              Validates business logic, validation rules, and domain methods
 * @author STERIS
 * @date 2026-04-22
 */
@IsTest
private class CasesTest {
    
    /**
     * @description Test setup - creates test data for all tests
     */
    @TestSetup
    static void setupTestData() {
        // Create test Account (Customer validation requires Oracle Source System ID)
        Account testAccount = new Account(
            Name = 'Test Account',
            SourceSystemID__c = 'CASEST001',
            SystemID__c = 'CASESYS01'
        );
        insert testAccount;
        
        // Create test Order
        Order testOrder = new Order(
            AccountId = testAccount.Id,
            Status = 'Draft',
            EffectiveDate = Date.today(),
            OrderNumber__c = 'ORD-TEST-001'
        );
        insert testOrder;
    }
    
    /**
     * @description Jira GW-1279 — getRecords returns working list after filter (uses adb_Case rows in memory)
     */
    @IsTest
    static void testGetRecords_afterFilterOutNonInboxSupportRecords() {
        Id inboxRt = Schema.SObjectType.Case.getRecordTypeInfosByName().get('Inbox Support')?.getRecordTypeId();
        Id otherRtId = Schema.SObjectType.Case.getRecordTypeInfosByName().get('CBM Case')?.getRecordTypeId();
        if (inboxRt == null || otherRtId == null || otherRtId == inboxRt) {
            return;
        }
        Case inboxWithEmail = (Case) new adb_Case()
            .subject('GW1279')
            .suppliedEmail('inbox@example.com')
            .record;
        inboxWithEmail.RecordTypeId = inboxRt;
        Case nonInbox = (Case) new adb_Case().subject('Other').suppliedEmail('o@example.com').record;
        nonInbox.RecordTypeId = otherRtId;

        Cases domain = new Cases(new List<Case>{ inboxWithEmail, nonInbox });
        domain.filterOutNonInboxSupportRecords(inboxRt);
        List<Case> remaining = domain.getRecords();
        System.Assert.areEqual(1, remaining.size(), 'Non-matching record type should be filtered out');
        System.Assert.areEqual('GW1279', remaining[0].Subject);
    }

    /**
     * @description Jira GW-1279 — filterOutNonInboxSupportRecords removes blank SuppliedEmail
     */
    @IsTest
    static void testFilterOutNonInboxSupportRecords_excludesBlankSuppliedEmail() {
        Id inboxRt = Schema.SObjectType.Case.getRecordTypeInfosByName().get('Inbox Support')?.getRecordTypeId();
        if (inboxRt == null) {
            return;
        }
        Case withEmail = (Case) new adb_Case().subject('A').suppliedEmail('a@b.com').record;
        withEmail.RecordTypeId = inboxRt;
        Case blankEmail = (Case) new adb_Case().subject('B').record;
        blankEmail.RecordTypeId = inboxRt;
        blankEmail.SuppliedEmail = null;

        Cases domain = new Cases(new List<Case>{ withEmail, blankEmail });
        domain.filterOutNonInboxSupportRecords(inboxRt);
        System.Assert.areEqual(1, domain.getRecords().size());
        System.Assert.areEqual('A', domain.getRecords()[0].Subject);
    }

    /**
     * @description Jira GW-1279 — filterOutNonInboxSupportRecords clears working set when record type Id is null
     */
    @IsTest
    static void testFilterOutNonInboxSupportRecords_nullRecordTypeClearsList() {
        Id inboxRt = Schema.SObjectType.Case.getRecordTypeInfosByName().get('Inbox Support')?.getRecordTypeId();
        if (inboxRt == null) {
            return;
        }
        Case c = (Case) new adb_Case().subject('X').suppliedEmail('x@y.com').record;
        c.RecordTypeId = inboxRt;
        Cases domain = new Cases(new List<Case>{ c });
        domain.filterOutNonInboxSupportRecords(null);
        System.Assert.isTrue(domain.getRecords().isEmpty());
    }

    /**
     * @description Jira GW-1279 — filterOutNonInboxSupportRecords no-op on empty list
     */
    @IsTest
    static void testFilterOutNonInboxSupportRecords_emptyList() {
        Cases domain = new Cases(new List<Case>());
        domain.filterOutNonInboxSupportRecords(UserInfo.getOrganizationId());
        System.Assert.isTrue(domain.getRecords().isEmpty());
    }

    /**
     * @description Jira GW-1279 — checkSecurity for delete on in-memory adb_Case rows
     */
    @IsTest
    static void testCheckSecurity_Delete() {
        Cases casesDomain = new Cases(new List<Case>{ (Case) new adb_Case().subject('Del').record });
        Test.startTest();
        try {
            casesDomain.checkSecurity('delete');
            System.Assert.isTrue(true, 'Security check should pass for standard test user');
        } catch (Cases.SecurityException e) {
            System.Assert.fail('Should not throw security exception: ' + e.getMessage());
        }
        Test.stopTest();
    }

    /**
     * @description GW-1279 - checkSecurity for insert and update; null list constructor.
     */
    @IsTest
    static void testCheckSecurity_InsertUpdateAndNullConstructor() {
        Cases casesDomain = new Cases(null);
        Assert.areEqual(0, casesDomain.getRecords().size(), 'Null list should become empty working set');

        Test.startTest();
        casesDomain.checkSecurity('insert');
        casesDomain.checkSecurity('update');
        casesDomain.checkSecurity('other');
        Test.stopTest();
        Assert.isTrue(true, 'Insert/update/unknown operation should not throw for standard test user');
    }

    /**
     * @description GW-3997 - applyFcrEvaluation covers empty, skip, and matching related-case paths.
     */
    @IsTest
    static void testApplyFcrEvaluation_WhenCountsAndRelatedCases_UpdatesIsFcr() {
        Datetime createdAt = Datetime.newInstance(2026, 1, 10, 12, 0, 0);
        Datetime closedAt = Datetime.newInstance(2026, 1, 15, 12, 0, 0);
        Case currentCase = (Case) JSON.deserialize(
            '{"attributes":{"type":"Case"},'
                + '"Id":"500000000000001AAA",'
                + '"Category__c":"Repair",'
                + '"CreatedDate":"'
                + createdAt.formatGmt('yyyy-MM-dd\'T\'HH:mm:ss.SSS\'Z\'')
                + '",'
                + '"ClosedDate":"'
                + closedAt.formatGmt('yyyy-MM-dd\'T\'HH:mm:ss.SSS\'Z\'')
                + '",'
                + '"IsFCR__c":false,'
                + '"SuppliedEmail":"fcr@example.com"}',
            Case.class
        );
        Case relatedMatch = (Case) JSON.deserialize(
            '{"attributes":{"type":"Case"},'
                + '"Id":"500000000000002AAA",'
                + '"Category__c":"Repair",'
                + '"CreatedDate":"'
                + createdAt.formatGmt('yyyy-MM-dd\'T\'HH:mm:ss.SSS\'Z\'')
                + '",'
                + '"SuppliedEmail":"fcr@example.com"}',
            Case.class
        );
        Case skippedNoClose = (Case) JSON.deserialize(
            '{"attributes":{"type":"Case"},"Id":"500000000000003AAA","Category__c":"Repair","IsFCR__c":false}',
            Case.class
        );

        Cases domain = new Cases(new List<Case>{ currentCase, skippedNoClose });
        Map<Id, Integer> emailCounts = new Map<Id, Integer>{ currentCase.Id => 0 };
        Map<Id, Integer> callCounts = new Map<Id, Integer>{ currentCase.Id => 0 };

        Test.startTest();
        Assert.areEqual(
            0,
            new Cases(new List<Case>()).applyFcrEvaluation(null, null, null).size(),
            'Empty domain returns no updates'
        );
        List<Case> updated = domain.applyFcrEvaluation(emailCounts, callCounts, new List<Case>{ relatedMatch });
        Test.stopTest();

        Assert.areEqual(1, updated.size(), 'Only the closed categorized Case should update');
        Assert.isTrue(updated[0].IsFCR__c, 'One related match and zero activity should set IsFCR__c true');
        Assert.areEqual(0, Cases.countRelatedMatches(null, new List<Case>{ relatedMatch }));
        Assert.areEqual(0, Cases.countRelatedMatches(currentCase, null));
    }
}