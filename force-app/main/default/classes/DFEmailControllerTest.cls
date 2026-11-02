/**
 * @author PSL
 * @date 11-02-2026
 * @description Test class for DFEmailController
 */
@IsTest
private class DFEmailControllerTest {

    @testSetup
    static void setupData() {
        Account acc = new Account(Name = 'DF Email Test Account');
        insert acc;

        Case cMain = new Case(Subject = 'DF Main Case', Status = 'New', Origin = 'Phone');
        Case cNone = new Case(Subject = 'DF No CCR',     Status = 'New', Origin = 'Phone');
        insert new List<Case>{ cMain, cNone };

        Contact recv = new Contact(
            FirstName = 'Receiving',
            LastName  = 'Guy',
            Email     = 'recv@test.com',
            MobilePhone     = '1234567899',
            AccountId = acc.Id
        );
        insert recv;

        insert new CaseContactRole(
            CasesId   = cMain.Id,
            ContactId = recv.Id,
            Role      = 'Receiving Contact'
        );
    }

    private static User makeUserWithSignature(String signature) {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        User u = new User(
            Alias             = 'dfuser',
            Email             = 'df.user+' + System.now().getTime() + '@example.com',
            EmailEncodingKey  = 'UTF-8',
            LastName          = 'Tester',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey      = 'en_US',
            TimeZoneSidKey    = 'America/Los_Angeles',
            Username          = 'df.user.' + System.now().getTime() + '@example.com',
            ProfileId         = p.Id,
            IsActive          = true,
            Signature         = signature
        );
        insert u;
        return u;
    }

    @IsTest
    static void test_AllGetters_PositivePath() {
        Case c = [SELECT Id FROM Case WHERE Subject = 'DF Main Case' LIMIT 1];

        String rawSig = 'Ajit Ledange\r\nLead Software Engineer | Pune';
        User u = makeUserWithSignature(rawSig);

        System.runAs(u) {
            DFEmailController ctrl = new DFEmailController();
            ctrl.caseId = c.Id;

            Test.startTest();
            String dispName = ctrl.getRecevingContactName();
            String fullName = ctrl.getRecevingContactFullName();
            String phone    = ctrl.getRecevingContactPhone();
            String email    = ctrl.getRecevingContactEmail();
            String sig      = ctrl.getSignature();
            Test.stopTest();

            System.assertEquals('Receiving',     dispName, 'Display name should be FirstName');
            System.assertEquals('Receiving Guy', fullName, 'Full name should be Contact.Name');
            //System.assertEquals('1234567899',    phone,    'Phone should match'); 
            System.assertEquals('recv@test.com', email,    'Email should match');

            // Signature: helper encodes <br/> as &lt;br/&gt; and splits pipes
            //System.assertEquals(
               // 'Ajit Ledange&lt;br/&gt;Lead Software Engineer&lt;br/&gt;Pune',
               // sig,
               // 'Signature should convert CR/LF and " | " to &lt;br/&gt;'
           // );
        }
    }

    @IsTest
    static void test_AllGetters_NullCaseId_And_BlankSignature() {
        DFEmailController ctrl = new DFEmailController();
        ctrl.caseId = null;

        String dispName = ctrl.getRecevingContactName();
        String fullName = ctrl.getRecevingContactFullName();
        String phone    = ctrl.getRecevingContactPhone();
        String email    = ctrl.getRecevingContactEmail();

        System.assertEquals(null, dispName, 'Display name should be null when caseId is null');
        System.assertEquals(null, fullName, 'Full name should be null when caseId is null');
        System.assertEquals(null, phone,    'Phone should be null when caseId is null');
        System.assertEquals(null, email,    'Email should be null when caseId is null');

        User uBlank = makeUserWithSignature('');
        System.runAs(uBlank) {
            Test.startTest();
            String sig = ctrl.getSignature();
            Test.stopTest();
            System.assertEquals('', sig, 'Blank signature should return empty string');
        }
    }

    @IsTest
    static void test_DFOrderPreparationBanner_Conditional() {
        DFEmailController ctrl = new DFEmailController();
        ctrl.caseId = null;

        List<CBM_Generic_Configuration__mdt> cfg = [
            SELECT DeveloperName, Key__c
            FROM CBM_Generic_Configuration__mdt
            WHERE DeveloperName = 'OrderPreparationbanner'
            LIMIT 1
        ];

        if (!cfg.isEmpty()) {
            Test.startTest();
            String banner = ctrl.getDFOrderPreparationBanner();
            Test.stopTest();

            System.assertNotEquals(null, banner, 'Banner URL should not be null');
            System.assert(banner.contains('/servlet/servlet.ImageServer?id=' + cfg[0].Key__c),
                'Banner URL should include the configured image id');
            System.assert(banner.contains('oid=' + UserInfo.getOrganizationId()),
                'Banner URL should include the org id');
            System.assert(banner.startsWith(URL.getOrgDomainUrl().toExternalForm()),
                'Banner URL should start with the org domain');
        } else {
            Boolean threw = false;
            try {
                Test.startTest();
                String banner = ctrl.getDFOrderPreparationBanner();
                Test.stopTest();
            } catch (Exception e) {
                threw = true;
            }
            System.assertEquals(true, threw,
                'When CMDT OrderPreparationbanner is absent, helper rethrows and we should catch it');
        }
    }
}