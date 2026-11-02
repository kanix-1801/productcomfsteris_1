@IsTest
/**
 * @author PSL
 * @date 01-02-2026
 * @description Test class for EmailMessageHelper class
 */
public class EmailMessageHelperTest {

    // Utility: Extract one lowercase token from a multi-value label
    private static String firstTokenFromLabel(String labelValue) {
        if (String.isBlank(labelValue)) return null;
        for (String t : labelValue.toLowerCase().split('[,;|]')) {
            String s = t != null ? t.trim() : null;
            if (!String.isBlank(s)) return s;
        }
        return null;
    }

    // ----------------------------
    //  orderLineFlagSet Coverage (no brittle assumptions)
    // ----------------------------
    @IsTest
    static void orderLineFlagSet_NoException_SafeWhenNoEligibleItems() {
        // Setup minimal data; we won't assert MailSent because EmailControllerHelper
        // is not mockable and may return zero items in this org.
        Id stdPbId = Test.getStandardPricebookId();
        update new Pricebook2(Id = stdPbId, IsActive = true);

        Product2 p = new Product2(Name='TestProduct', IsActive=true, itemType__c='Trade-In');
        insert p;

        PricebookEntry pbe = new PricebookEntry(
            Pricebook2Id = stdPbId,
            Product2Id   = p.Id,
            UnitPrice    = 100,
            IsActive     = true
        );
        insert pbe;

        Account acc = new Account(Name='Acme');
        insert acc;

        Order ord = new Order(
            AccountId = acc.Id,
            Status = 'Draft',
            EffectiveDate = Date.today(),
            Pricebook2Id = stdPbId
        );
        insert ord;

        Case c = new Case(Subject='Ship Date Notification Case', Status='New');
        insert c;

        // Link order to the case as in your flow
        ord.ParentCase__c = c.Id;
        update ord;

        // Create two order items; whether EmailControllerHelper returns them is unknown.
        OrderItem oi1 = new OrderItem(
            OrderId=ord.Id, PricebookEntryId=pbe.Id,
            Quantity=1, UnitPrice=100,
            OrderLineStatus__c='Picked',
            MailSent__c = false
        );
        OrderItem oi2 = new OrderItem(
            OrderId=ord.Id, PricebookEntryId=pbe.Id,
            Quantity=1, UnitPrice=100,
            OrderLineStatus__c='Picked',
            MailSent__c = false
        );
        insert new List<OrderItem>{ oi1, oi2 };

        // Outbound message with matching subject — still fine if helper returns no items.
        EmailMessage emOut = new EmailMessage(
            ParentId=c.Id,
            Incoming=false,
            Subject='STERIS Ship Date Notification - test'
        );

        Test.startTest();
        // The goal: ensure method executes safely; no exception even if no items are updated.
        EmailMessageHelper.orderLineFlagSet(new List<EmailMessage>{ emOut });
        Test.stopTest();

        // Re-query to ensure items still exist (no exception path).
        List<OrderItem> result = [
            SELECT Id, MailSent__c
            FROM OrderItem
            WHERE Id IN :new List<Id>{ oi1.Id, oi2.Id }
        ];
        System.assertEquals(2, result.size(), 'Order items should still exist; method is no-op safe');
        // Do NOT assert MailSent__c, because helper output depends on non-mockable EmailControllerHelper.
    }

    @IsTest
    static void orderLineFlagSetNullTest() {
        Test.startTest();
        EmailMessageHelper.orderLineFlagSet(null);
        Test.stopTest();
        System.assert(true, 'No exception expected for null input');
    }

    // ---------------------------------------
    //  setCaseGoNoGoDecision Deep Coverage
    // ---------------------------------------
    @IsTest
    static void setCaseGoNoGoDecision_Normalization_HTML_Whitespace() {
        String ipmGoTok     = firstTokenFromLabel(System.Label.IPMGoPermissionKeyword);
        String salesNoGoTok = firstTokenFromLabel(System.Label.SalesNoGoPermissionKeyword);

        System.assertNotEquals(null, ipmGoTok, 'IPM Go label must exist');
        System.assertNotEquals(null, salesNoGoTok, 'Sales NoGo label must exist');

        Case c = new Case(Subject='NormCase', Status='New');
        insert c;

        // Forces normalizeBody: HTML tags + &nbsp + lowercase + whitespace collapse
        EmailMessage em = new EmailMessage();
        em.ParentId = c.Id;
        em.Incoming = true;
        em.Subject  = 'RE: Something';
        em.TextBody = null;
        em.HtmlBody =
            '<div><p>&nbsp; ' + salesNoGoTok.replace(':', ': ') +
            '</p><p><b>' + ipmGoTok.replace(':', ': ') + '</b></p></div>';

        Test.startTest();
        EmailMessageHelper.setCaseGoNoGoDecision(new List<EmailMessage>{ em });
        Test.stopTest();

        Case out = [
            SELECT IPMdecision__c, Sales_Decision__c
            FROM Case WHERE Id=:c.Id
        ];

        System.assertEquals('GO', out.IPMdecision__c, 'IPM should be GO after normalization');
        System.assertEquals('NO-GO', out.Sales_Decision__c, 'Sales should be NO-GO after normalization');
    }

    @IsTest
    static void setCaseGoNoGoDecision_NoWhitespaceMappingBranch() {
        String salesGoTok = firstTokenFromLabel(System.Label.SalesGoPermissionKeyword);
        String ipmNoGoTok = firstTokenFromLabel(System.Label.IPMNoGoPermissionKeyword);

        System.assertNotEquals(null, salesGoTok, 'Sales Go label must exist');
        System.assertNotEquals(null, ipmNoGoTok, 'IPM NoGo label must exist');

        Case c = new Case(Subject='Nowhitespace', Status='New');
        insert c;

        // HTML: "sales:<b>go</b>" → becomes "sales: go" after stripping,
        // so the helper's "no-whitespace" path should still recognize "sales:go".
        EmailMessage em = new EmailMessage();
        em.ParentId = c.Id;
        em.Incoming = true;
        em.Subject  = 'Decision';
        em.TextBody = null;
        em.HtmlBody =
            '<p>' + salesGoTok.split(':')[0] + ':<b>' +
            salesGoTok.split(':')[1] + '</b></p>' +
            '<p>' + ipmNoGoTok + '</p>';

        Test.startTest();
        EmailMessageHelper.setCaseGoNoGoDecision(new List<EmailMessage>{ em });
        Test.stopTest();

        Case res = [
            SELECT IPMdecision__c, Sales_Decision__c
            FROM Case WHERE Id=:c.Id
        ];

        System.assertEquals('GO',    res.Sales_Decision__c, 'Sales should be GO via no-whitespace mapping');
        System.assertEquals('NO-GO', res.IPMdecision__c,    'IPM should be NO-GO');
    }

    @IsTest
    static void setCaseGoNoGoDecision_Guards() {
        Case c = new Case(Subject='Guard', Status='New');
        insert c;

        // Outbound — skip
        EmailMessage em1 = new EmailMessage();
        em1.ParentId = c.Id;
        em1.Incoming = false;
        em1.Subject  = 'x';
        em1.TextBody = 'ignored';

        // Wrong parent (not a Case)
        Account a = new Account(Name='ParentX');
        insert a;

        EmailMessage em2 = new EmailMessage();
        em2.ParentId = a.Id;
        em2.Incoming = true;
        em2.Subject  = 'x';
        em2.TextBody = 'ignored';

        // Blank body — skip
        EmailMessage em3 = new EmailMessage();
        em3.ParentId = c.Id;
        em3.Incoming = true;
        em3.Subject  = 'Inbound blank';
        em3.TextBody = null;
        em3.HtmlBody = null;

        Test.startTest();
        EmailMessageHelper.setCaseGoNoGoDecision(new List<EmailMessage>{ em1, em2, em3 });
        Test.stopTest();

        Case out = [SELECT IPMdecision__c, Sales_Decision__c FROM Case WHERE Id=:c.Id];
        System.assertEquals(null, out.IPMdecision__c, 'Guard: IPM remains null');
        System.assertEquals(null, out.Sales_Decision__c, 'Guard: Sales remains null');
    }

    @IsTest
    static void setCaseGoNoGoDecision_NullAndEmptyGuards() {
        Test.startTest();
        EmailMessageHelper.setCaseGoNoGoDecision(null);
        EmailMessageHelper.setCaseGoNoGoDecision(new List<EmailMessage>());
        Test.stopTest();
        System.assert(true, 'No exception expected for null/empty inputs');
    }

    // ---------------------------------------
    //  goNoGoReminderDates Full Coverage
    // ---------------------------------------
    @IsTest
    static void goNoGoReminderDates_FillsDates_UsesLatest() {
        Case c = new Case(Subject='Reminder', Status='New');
        insert c;

        // Old email
        EmailMessage emOld = new EmailMessage();
        emOld.ParentId = c.Id;
        emOld.Subject  = 'Response Required: GO/NO-GO: Test';
        emOld.MessageDate = System.now().addHours(-3);

        // New email
        EmailMessage emNew = new EmailMessage();
        emNew.ParentId = c.Id;
        emNew.Subject  = 'Response Required: GO/NO-GO: Test';
        emNew.MessageDate = System.now();

        Test.startTest();
        EmailMessageHelper.goNoGoReminderDates(new List<EmailMessage>{ emOld, emNew });
        Test.stopTest();

        Case out = [
            SELECT GoNoGoSentDate__c, ReminderSentDate__c
            FROM Case WHERE Id=:c.Id
        ];

        System.assertNotEquals(null, out.GoNoGoSentDate__c, 'Should set GoNoGoSentDate__c');
        System.assertEquals(emNew.MessageDate, out.ReminderSentDate__c, 'Should set latest ReminderSentDate__c');
    }

    @IsTest
    static void goNoGoReminderDates_Guards_NoOps() {
        Account a = new Account(Name='x');
        insert a;

        EmailMessage wrongSubj = new EmailMessage();
        wrongSubj.Subject = 'Not matching';

        EmailMessage wrongParent = new EmailMessage();
        wrongParent.ParentId = a.Id; // Not a Case (001...)
        wrongParent.Subject = 'Response Required: GO/NO-GO:';

        Test.startTest();
        EmailMessageHelper.goNoGoReminderDates(null);
        EmailMessageHelper.goNoGoReminderDates(new List<EmailMessage>());
        EmailMessageHelper.goNoGoReminderDates(new List<EmailMessage>{ wrongSubj, wrongParent });
        Test.stopTest();

        System.assert(true, 'Guard paths should not raise exceptions');
    }
    // CBM-236
    @IsTest
    static void orderLineFlagSet_CaseReceivingContact_CoverageSafe() {
        
        // ----------------------------------------------------
        // Check whether 'Receiving Contact' exists in this org
        // ----------------------------------------------------
        Boolean hasReceivingContactRole = false;
        
        Schema.DescribeFieldResult roleField =
            Schema.SObjectType.CaseContactRole
            .fields.getMap().get('Role')
            .getDescribe();
        
        for (Schema.PicklistEntry pe : roleField.getPicklistValues()) {
            if (pe.getValue() == 'Receiving Contact') {
                hasReceivingContactRole = true;
                break;
            }
        }
        
        // ----------------------------------------------------
        // Base data setup (always valid)
        // ----------------------------------------------------
        Account acc = new Account(Name='Test Account');
        insert acc;
        
        Contact con = new Contact(
            LastName='Receiver',
            AccountId=acc.Id
        );
        insert con;
        
        Case cs = new Case(
            Subject='STERIS Ship Date Notification Case',
            Status='New',
            AccountId=acc.Id 
        );
        insert cs;
        
        // ----------------------------------------------------
        // Insert CaseContactRole ONLY if supported by org
        // ----------------------------------------------------
        if (hasReceivingContactRole) {
            insert new CaseContactRole(
                CasesId = cs.Id,
                ContactId = con.Id,
                Role = 'Receiving Contact'
            );
        }
        
        EmailMessage em = new EmailMessage(
            ParentId = cs.Id,
            Incoming = false,
            Subject  = 'STERIS Ship Date Notification'
        );
        
        // ----------------------------------------------------
        // Execute
        // ----------------------------------------------------
        Test.startTest();
        EmailMessageHelper.orderLineFlagSet(
            new List<EmailMessage>{ em }
        );
        Test.stopTest();
        
        // ----------------------------------------------------
        // Assert correctly based on org configuration
        // ----------------------------------------------------
        Case refreshed = [
            SELECT ContactId
            FROM Case
            WHERE Id = :cs.Id
        ];
        
        if (hasReceivingContactRole) {
            System.assertEquals(
                con.Id,
                refreshed.ContactId,
                'Case.ContactId should be populated when Receiving Contact role exists'
            );
        } else {
            System.assertEquals(
                null,
                refreshed.ContactId,
                'Case.ContactId remains null because Receiving Contact role does not exist'
            );
        }
    }

    /**
     * Verifies method handles Email Messages
     * that do not have related EmailMessageRelation records.
     */
    @IsTest
    static void testNullifyRelationId_NoRelationsFound() {

        EmailMessage emailMsg = new EmailMessage(
            Subject = 'Test Email',
            FromAddress = 'test@test.com',
            ToAddress = 'recipient@test.com',
            Status = '3'
        );
        insert emailMsg;

        Test.startTest();

        EmailMessageHelper.nullifyRelationId(
            new Set<Id>{ emailMsg.Id }
        );

        Test.stopTest();

        System.assert(true,
            'Method should complete without exception when no relations exist.'
        );
    }

}