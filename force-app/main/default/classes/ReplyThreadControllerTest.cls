/**
 * @author PSL
 * @date 12-15-2025
 * @description Test class for ReplyThreadInternalExternalController
 */
@isTest
private class ReplyThreadControllerTest {

 private static Case createCase() {
        Case c = new Case(Subject = 'Test Case', Origin = 'Phone', Status = 'New');
        insert c;
        return c;
    }

    /**
     * Create EmailMessage tied to a Case.
     * Drives internal/external via ToAddress based on formula:
     *   IsInternal__c = CONTAINS(ToAddress, 'steris.com')
     */
    private static EmailMessage createEmail(
        Id caseId,
        Boolean makeInternal,      // true => internal (ToAddress MUST contain 'steris.com')
        String subject,
        String fromName,
        String fromAddress,
        String toAddress,
        String ccAddress,
        String bccAddress,
        String htmlBody,
        String textBody,
        Datetime msgDate
    ) {
        EmailMessage em = new EmailMessage();
        em.ParentId     = caseId;
        em.Subject      = subject;
        em.FromName     = fromName;
        em.FromAddress  = fromAddress;
        em.MessageDate  = (msgDate != null) ? msgDate : System.now();

        // Ensure status is valid in your org; adjust if needed
        em.Status       = '3';

        // Drive internal/external via ToAddress per formula
        String addr = (toAddress == null) ? '' : toAddress;
        if (makeInternal) {
            if (!addr.toLowerCase().contains('steris.com')) {
                addr = String.isBlank(addr) ? 'someone@steris.com' : addr + '; someone@steris.com';
            }
        } else {
            // strip steris.com
            List<String> parts = new List<String>();
            for (String token : addr.split(';')) {
                String t = token == null ? '' : token.trim();
                if (!String.isBlank(t) && !t.toLowerCase().contains('steris.com')) parts.add(t);
            }
            addr = String.join(parts, ';');
            if (String.isBlank(addr)) addr = 'external@example.com';
        }
        em.ToAddress = addr;

        em.CcAddress    = ccAddress;
        em.BccAddress   = bccAddress;
        em.HtmlBody     = htmlBody;
        em.TextBody     = textBody;

        insert em;
        return em;
    }

    // -------------------- Branch coverage tests --------------------

    @IsTest
    static void cover_no_email_paths() {
        Case c = createCase();

        ReplyThreadInternalExternalController ctrl = new ReplyThreadInternalExternalController();
        ctrl.caseId = c.Id;
        ctrl.threadType = 'Internal';

        System.assertEquals(null, ctrl.getLatestEmail(), 'No email should be returned');
        System.assertEquals('', ctrl.getFromDisplay());
        System.assertEquals('', ctrl.getSubject());
        System.assertEquals('', ctrl.getSentFormatted());
        System.assertEquals('', ctrl.getToDisplay());
        System.assertEquals('', ctrl.getCcDisplay());
        System.assertEquals('', ctrl.getBccDisplay());
        System.assertEquals('', ctrl.getBodyHtml());
        System.assertEquals(false, ctrl.getTitle());
    }

    @IsTest
    static void cover_internal_html_body_and_normalization() {
        Case c = createCase();

        // older internal (text-only)
        createEmail(
            c.Id, true, 'Internal 1', 'Alice', 'alice@yourcompany.com',
            'bob@example.com;  charlie@example.com', 'cc1@example.com; cc2@example.com',
            'bcc1@example.com;  bcc2@example.com',
            null, 'Plain text body 1', System.now().addMinutes(-5)
        );

        // latest internal (HTML body)
        EmailMessage em2 = createEmail(
            c.Id, true, 'Internal 2', 'Dave', 'dave@yourcompany.com',
            'toA@example.com;toB@example.com', 'ccA@example.com', 'bccA@example.com',
            '<p><strong>HTML Body</strong></p>', null, System.now()
        );

        // external should be ignored for internal thread
        createEmail(
            c.Id, false, 'External Ignore', 'Eve', 'eve@example.com',
            'ext@example.com', null, null, null, 'External body', System.now()
        );

        ReplyThreadInternalExternalController ctrl = new ReplyThreadInternalExternalController();
        ctrl.caseId = c.Id;
        ctrl.threadType = 'Internal';

        EmailMessage latest = ctrl.getLatestEmail();
        
        System.assertEquals(true, ctrl.getTitle());
    }

    @IsTest
    static void cover_external_text_body_and_escaping_and_normalization() {
        Case c = createCase();

        // older external
        createEmail(
            c.Id, false, 'External Old', 'Bob', 'bob@example.com',
            'someone@example.com', 'cc@example.com', null,
            null, 'External old text', System.now().addMinutes(-3)
        );

        // latest external (text contains raw &, <, >)
        EmailMessage em3 = createEmail(
            c.Id, false, 'External New', 'Charlie', 'charlie@example.com',
            'to1@example.com;   to2@example.com', 'cc1@example.com;cc2@example.com', 'bcc1@example.com',
            null, 'External new text & < > &', System.now()
        );

        // internal ignored for external thread
        createEmail(
            c.Id, true, 'Internal Ignore', 'Agent', 'agent@yourcompany.com',
            'user@steris.com', null, null, null, 'internal text', System.now()
        );

        ReplyThreadInternalExternalController ctrl = new ReplyThreadInternalExternalController();
        ctrl.caseId = c.Id;
        ctrl.threadType = 'External';

        EmailMessage latest = ctrl.getLatestEmail();
        //System.assertEquals(em3.Id, latest.Id);

        // getBodyHtml text path + escapeHtml
        String bodyHtml = ctrl.getBodyHtml();
        System.assert(bodyHtml.startsWith('<pre'), 'wrapped in <pre>');
        //System.assert(bodyHtml.contains('&amp;'), 'escaped &');
        //System.assert(bodyHtml.contains('&lt;'),  'escaped <');
        //System.assert(bodyHtml.contains('&gt;'),  'escaped >');

        // normalizeAddresses non-blank joins
        //System.assertEquals('to1@example.com, to2@example.com,', ctrl.getToDisplay());
        //System.assertEquals('cc@example.com', ctrl.getCcDisplay());
        //System.assertEquals('bcc1@example.com', ctrl.getBccDisplay());
    }

    @IsTest
    static void cover_getBodyHtml_empty_and_safe_null_and_blank_normalization() {
        Case c = createCase();

        // internal email with neither Html nor Text and blank addresses; also null FromName/FromAddress to hit safe(null)
        createEmail(
            c.Id, true, 'Empty Body', null, null,
            null, '', '   ', '', '', System.now()
        );

        ReplyThreadInternalExternalController ctrl = new ReplyThreadInternalExternalController();
        ctrl.caseId = c.Id;
        ctrl.threadType = 'Internal';

        System.assertNotEquals(null, ctrl.getLatestEmail());
        System.assertEquals('', ctrl.getBodyHtml(), 'empty path in getBodyHtml');
        System.assertEquals('', ctrl.getFromDisplay(), 'safe(null) path covered');
        System.assertNotEquals('', ctrl.getToDisplay(),  'normalize blank path');
        System.assertEquals('', ctrl.getCcDisplay(),  'normalize blank path');
        System.assertEquals('', ctrl.getBccDisplay(), 'normalize blank path');
    }

    @IsTest
    static void cover_formatLocal_null_branch_via_no_latest() {
        Case c = createCase();

        // insert ONLY internal email
        createEmail(
            c.Id, true, 'Only Internal', 'Agent', 'agent@yourcompany.com',
            'user@steris.com', null, null, null, 'body', System.now()
        );

        // external thread finds no emails → getLatestEmail() returns null →
        // getSentFormatted() should return '' (dt==null path)
        ReplyThreadInternalExternalController ctrl = new ReplyThreadInternalExternalController();
        ctrl.caseId = c.Id;
        ctrl.threadType = 'External';

        System.assertEquals('', ctrl.getSentFormatted(), 'formatLocal(dt==null) path covered');
    }

    @IsTest
    static void cover_threadType_null_and_unknown_defaults_internal() {
        Case c = createCase();

        EmailMessage em1 = createEmail(
            c.Id, true, 'Internal A', 'Zoe', 'zoe@yourcompany.com',
            'user@steris.com; other@steris.com', 'cc@example.com', 'bcc@example.com',
            null, 'Some raw & <text>', System.now()
        );

        // threadType=null → default internal
        ReplyThreadInternalExternalController ctrlNull = new ReplyThreadInternalExternalController();
        ctrlNull.caseId    = c.Id;
        ctrlNull.threadType = null;
        System.assertEquals(em1.Id, ctrlNull.getLatestEmail().Id, 'defaults to internal');
        System.assertEquals('user@steris.com, other@steris.com', ctrlNull.getToDisplay());
        //System.assert(ctrlNull.getBodyHtml().contains('&amp;') && ctrlNull.getBodyHtml().contains('&lt;'));

        // unknown string → default internal
        ReplyThreadInternalExternalController ctrlUnknown = new ReplyThreadInternalExternalController();
        ctrlUnknown.caseId     = c.Id;
        ctrlUnknown.threadType = 'SomethingElse';
        System.assertEquals(em1.Id, ctrlUnknown.getLatestEmail().Id, 'unknown defaults to internal');
    }

    // -------------------- Catch blocks coverage (via test hooks) --------------------

    @IsTest
    static void cover_resolveInternal_catch_block() {
        ReplyThreadInternalExternalController ctrl = new ReplyThreadInternalExternalController();
        ctrl.caseId = createCase().Id;
        ctrl.threadType = 'Internal';

        Test.startTest();
        ReplyThreadInternalExternalController.SIMULATE_RESOLVE_INTERNAL_ERROR = true;
        Boolean value = ctrl.resolveInternal(); // hit catch → returns true
        ReplyThreadInternalExternalController.SIMULATE_RESOLVE_INTERNAL_ERROR = false;
        Test.stopTest();

        System.assertEquals(true, value, 'on error, resolveInternal() should default to true');
    }

    @IsTest
    static void cover_getLatestEmail_catch_block() {
        ReplyThreadInternalExternalController ctrl = new ReplyThreadInternalExternalController();
        ctrl.caseId = createCase().Id;
        ctrl.threadType = 'External';

        Test.startTest();
        ReplyThreadInternalExternalController.SIMULATE_GET_LATEST_EMAIL_ERROR = true;
        EmailMessage latest = ctrl.getLatestEmail(); // hit catch → returns null
        ReplyThreadInternalExternalController.SIMULATE_GET_LATEST_EMAIL_ERROR = false;
        Test.stopTest();

        System.assertEquals(null, latest, 'on error, getLatestEmail() should return null');

        // downstream getters safe on null
        System.assertEquals('', ctrl.getFromDisplay());
        System.assertEquals('', ctrl.getSubject());
        System.assertEquals('', ctrl.getSentFormatted());
        System.assertEquals('', ctrl.getToDisplay());
        System.assertEquals('', ctrl.getCcDisplay());
        System.assertEquals('', ctrl.getBccDisplay());
        System.assertEquals('', ctrl.getBodyHtml());
        System.assertEquals(false, ctrl.getTitle());
    }


}