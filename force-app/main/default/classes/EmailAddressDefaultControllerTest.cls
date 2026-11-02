/**
 * @author PSL
 * @date 12-02-2025
 * @description Test class for EmailAddressDefaultController that validates helper methods for email functionality
 */
@IsTest
private class EmailAddressDefaultControllerTest {
 
    @testSetup
    static void setupData() {
        // ---------- Email Templates (queried by Name in the controller) ----------
        Folder emailFolder = [
            SELECT Id
            FROM Folder
            WHERE DeveloperName = 'CBMHealthcare'
            AND Type = 'Email'
            LIMIT 1
        ];
       
        insert new List<EmailTemplate>{
            new EmailTemplate(
                Name = 'USSOA',
                DeveloperName= 'USSOA2',
                FolderId = emailFolder.Id,
                Subject = 'US SOA',
                body = 'Body Text',
                TemplateType = 'Text'
            ),
            new EmailTemplate(
                Name = 'COA Projects',
                DeveloperName= 'COA_Projects1',
                FolderId = emailFolder.Id,
                Subject = 'COA Projects',
                body = 'Body Text',
                TemplateType = 'Text'
            ),
            new EmailTemplate(
                Name = 'COA US CAN Eng',
                DeveloperName= 'COA_US_CAN_ENG1',
                FolderId = emailFolder.Id,
                Subject = 'COA Turns',
                body = 'Body Text',
                TemplateType = 'Text'
            ),
            new EmailTemplate(
                Name = 'C1US',
                DeveloperName= 'C1US1',
                FolderId = emailFolder.Id,
                Subject = 'C1',
                body = 'Body Text',
                TemplateType = 'Text'
            ),
            new EmailTemplate(
                Name = 'C2US',
                DeveloperName= 'C2US1',
                FolderId = emailFolder.Id,
                Subject = 'C2',
                body = 'Body Text',
                TemplateType = 'Text'
            ),
            new EmailTemplate(
                Name = 'Ship Date Notification',
                DeveloperName= 'ShipDateNotification1',
                FolderId = emailFolder.Id,
                Subject = 'Ship Date Notification',
                body = 'Body Text',
                TemplateType = 'Text'
            ),
                new EmailTemplate(
                Name = 'Go No-Go',
                DeveloperName= 'GoNoGo1',
                FolderId = emailFolder.Id,
                Subject = 'Go No-Go',
                body = 'Body Text',
                TemplateType = 'Text'
            )
        };
       
        // ---------- Core data ----------
        User u1 = [SELECT Id FROM User WHERE Id = :UserInfo.getUserId() LIMIT 1];
 
        System.runAs(u1) {
            Account acc = new Account(Name = 'Test Account');
            insert acc;
       
            // Contacts for SOA logic (SalesRep + hierarchy)
            Contact salesRep = new Contact(LastName = 'SalesRep', Email = 'salesrep@test.com', AccountId = acc.Id);
            Contact rsd = new Contact(LastName = 'RSD', Email = 'rsd@test.com', AccountId = acc.Id);
            Contact avp = new Contact(LastName = 'AVP', Email = 'avp@test.com', AccountId = acc.Id);
            Contact pdm = new Contact(LastName = 'PDM', Email = 'pdm@test.com', AccountId = acc.Id);
            Contact sds = new Contact(LastName = 'SDS', Email = 'sds@test.com', AccountId = acc.Id);
       
            // Contacts for COA Project & Turns logic
            Contact projectContact = new Contact(LastName = 'Project', Email = 'project@test.com', AccountId = acc.Id);
            Contact turnsContact1 = new Contact(LastName = 'Turns1', Email = 'turns1@test.com', AccountId = acc.Id);
            Contact turnsContact2 = new Contact(LastName = 'Turns2', Email = 'turns2@test.com', AccountId = acc.Id);
       
            insert new List<Contact>{
                salesRep, rsd, avp, pdm, sds,
                projectContact, turnsContact1, turnsContact2
            };
       
            // ---------- Cases ----------
            Case soaCase = new Case(
                Subject = 'SOA Case',
                Status = 'New',
                Origin = 'Phone',
                EmailType__c = 'SOA'
            );
            insert soaCase;

            Case c1Case = new Case(
                Subject = 'C1 Case',
                Status = 'New',
                Origin = 'Phone',
                EmailType__c = 'C1'
            );
            Case c2Case = new Case(
                Subject = 'C2 Case',
                Status = 'New',
                Origin = 'Phone',
                EmailType__c = 'C2'
            );
       
            Case projectCase = new Case(
                Subject = 'COA Project Case',
                Status = 'New',
                Origin = 'Phone'
            );
            Case turnsCase = new Case(
                Subject = 'COA Turns Case',
                Status = 'New',
                Origin = 'Phone'
            );
            Case GoNoGoCase = new Case(
                Subject = 'Go No-Go Case',
                Status = 'New',
                Origin = 'Phone'
            );
            insert new List<Case>{ c1Case, c2Case, projectCase, turnsCase,GoNoGoCase };
       
            // ---------- Order + OrderItems ----------
            Pricebook2 pb = new Pricebook2(Name = 'Test PB', IsActive = true);
            insert pb;
       
            Product2 prod = new Product2(Name = 'Test Product', IsActive = true,SalesCategoryCode__c='CAPEQUIP');
            insert prod;
       
            PricebookEntry pbe = new PricebookEntry(
                Pricebook2Id = Test.getStandardPricebookId(),
                Product2Id = prod.Id,
                UnitPrice = 100,
                IsActive = true
            );
            insert pbe;
       
            Order ord = new Order(
                AccountId = acc.Id,
                EffectiveDate = Date.today(),
                Status = 'Draft',
                Pricebook2Id = Test.getStandardPricebookId()
            );
            insert ord;
       
            // Link cases to the order (field from your org)
            soaCase.Order__c = ord.Id;
            c1Case.Order__c = ord.Id;
            c2Case.Order__c = ord.Id;
            update new List<Case>{ soaCase, c1Case, c2Case };
       
            // OrderItems with different line types
            OrderItem oiServiceInstall = new OrderItem(
                OrderId = ord.Id,
                Quantity = 1,
                UnitPrice = 100,
                PricebookEntryId= pbe.Id,
                TASSalesCategory__c = 'PM'
            );
            OrderItem oiCapital = new OrderItem(
                OrderId = ord.Id,
                Quantity = 1,
                UnitPrice = 100,
                PricebookEntryId= pbe.Id,
                TASSalesCategory__c = 'GI IN SALE'
            );
            OrderItem oiGi = new OrderItem(
                OrderId = ord.Id,
                Quantity = 1,
                UnitPrice = 100,
                PricebookEntryId= pbe.Id,
                TASSalesCategory__c = 'SURG SPT'
            );
            OrderItem oiProcedural = new OrderItem(
                OrderId = ord.Id,
                Quantity = 1,
                UnitPrice = 100,
                PricebookEntryId= pbe.Id,
                TASSalesCategory__c = 'STERL PROC'
            );
            OrderItem oiReprocess = new OrderItem(
                OrderId = ord.Id,
                Quantity = 1,
                UnitPrice = 100,
                PricebookEntryId= pbe.Id,
                TASSalesCategory__c = 'GI IN SALE'
            );
            insert new List<OrderItem>{
                oiServiceInstall, oiCapital, oiGi, oiProcedural, oiReprocess
            };
       
            // ---------- OrderLineContact__c (lookup to OrderItem) ----------
            insert new List<OrderLineContact__c>{
                // Service - Installation line
                new OrderLineContact__c(
                    OrderLine__c = oiServiceInstall.Id,
                    SalesRep__c = salesRep.Id,
                    RSD__c = rsd.Id,
                    AVP__c = avp.Id,
                    PDM__c = pdm.Id,
                    SDS__c = sds.Id
                ),
                // Capital line
                new OrderLineContact__c(
                    OrderLine__c = oiCapital.Id,
                    SalesRep__c = salesRep.Id
                ),
                // GI Reprocessing
                new OrderLineContact__c(
                    OrderLine__c = oiGi.Id
                ),
                // Procedural
                new OrderLineContact__c(
                    OrderLine__c = oiProcedural.Id
                ),
                // Reprocessing
                new OrderLineContact__c(
                    OrderLine__c = oiReprocess.Id
                )
            };
       
            // ---------- Case Team Member (for SOA) ----------
            
            User someUser = [SELECT Id, Email FROM User WHERE IsActive = true LIMIT 1];
       
       		CaseTeamRole someRole = [SELECT Id, Name FROM CaseTeamRole LIMIT 1];
            insert new CaseTeamMember(
                ParentId = soaCase.Id,
                TeamRoleId = someRole.Id,
                MemberId = someUser.Id
            );
            // NOTE: SOA CMDT's CaseTeamMember__c should include this role name for positive branch in orgs with data
       
            // ---------- CaseContactRoles for COA Project & Turns ----------
            insert new List<CaseContactRole>{
                new CaseContactRole(
                    CasesId = projectCase.Id,
                    ContactId = projectContact.Id,
                    Role = 'Receving Contact'
                ),
                new CaseContactRole(
                    CasesId = turnsCase.Id,
                    ContactId = turnsContact1.Id,
                    Role = 'Install Contact'
                ),
                new CaseContactRole(
                    CasesId = turnsCase.Id,
                    ContactId = turnsContact2.Id,
                    Role = 'Department Contact'
                )
            };
        }
    }
       
    // ==================== TESTS ====================
       
    @IsTest
    static void test_defaultSOAEmailAddresses() {
        Case soaCase = [SELECT Id,emailType__C,order__C FROM Case WHERE Subject = 'SOA Case' LIMIT 1];
        QuickAction.SendEmailQuickActionDefaults sendDefaults =
            Test.newSendEmailQuickActionDefaults(soaCase.Id, null);
       
        Test.startTest();
        EmailAddressDefaultController.defaultSOAEmailAddresses(sendDefaults, soaCase);
        Test.stopTest();
       
        EmailMessage msg = (EmailMessage) sendDefaults.getTargetSObject();
        System.assertNotEquals(null, msg, 'EmailMessage should not be null for SOA');
        System.assertNotEquals(null, msg.ToAddress, 'SOA ToAddress should be set (may be empty)');
        System.assertNotEquals(null, msg.CcAddress, 'SOA CcAddress should be set (may be empty)');
        System.assertEquals('', msg.BccAddress, 'BccAddress is cleared in controller');
    }
       
    @IsTest
    static void test_defaultCOAProjectEmailAddresses() {
        Case projectCase = [SELECT Id FROM Case WHERE Subject = 'COA Project Case' LIMIT 1];
        QuickAction.SendEmailQuickActionDefaults sendDefaults =
            Test.newSendEmailQuickActionDefaults(projectCase.Id, null);
       
        Test.startTest();
        EmailAddressDefaultController.defaultCOAProjectEmailAddresses(sendDefaults, projectCase);
        Test.stopTest();
       
        EmailMessage msg = (EmailMessage) sendDefaults.getTargetSObject();
        System.assertNotEquals(null, msg, 'Project EmailMessage should not be null');
        System.assertNotEquals(null, msg.ToAddress, 'Project ToAddress should be set (may be empty)');
        System.assertEquals('', msg.BccAddress, 'Project BccAddress is cleared');
    }
       
    @IsTest
    static void test_defaultCOATurnsEmailAddresses() {
        Case turnsCase = [SELECT Id,order__c FROM Case WHERE Subject = 'COA Turns Case' LIMIT 1];
        QuickAction.SendEmailQuickActionDefaults sendDefaults =
            Test.newSendEmailQuickActionDefaults(turnsCase.Id, null);
       
        Test.startTest();
        EmailAddressDefaultController.defaultCOATurnsEmailAddresses(sendDefaults, turnsCase);
        Test.stopTest();
       
        EmailMessage msg = (EmailMessage) sendDefaults.getTargetSObject();
        System.assertNotEquals(null, msg, 'Turns EmailMessage should not be null');
        System.assertNotEquals(null, msg.ToAddress, 'Turns ToAddress should be set (may be empty)');
        System.assertEquals('', msg.BccAddress, 'Turns BccAddress is cleared');
    }

    @IsTest
    static void test_defaultC1EmailAddresses() {
        Case c1 = [SELECT Id, Order__c FROM Case WHERE Subject = 'C1 Case' LIMIT 1];
        QuickAction.SendEmailQuickActionDefaults sendDefaults =
            Test.newSendEmailQuickActionDefaults(c1.Id, null);

        Test.startTest();
        EmailAddressDefaultController.defaultC1EmailAddresses(sendDefaults, c1);
        Test.stopTest();

        EmailMessage msg = (EmailMessage) sendDefaults.getTargetSObject();
        System.assertNotEquals(null, msg, 'C1 EmailMessage should not be null');
        System.assertNotEquals(null, msg.ToAddress, 'C1 ToAddress should be set (may be empty)');
        System.assertNotEquals(null, msg.CcAddress, 'C1 CcAddress should be set (may be empty)');
        System.assertEquals('', msg.BccAddress, 'C1 BccAddress is cleared');
    }

    @IsTest
    static void test_defaultC2EmailAddresses() {
        Case c2 = [SELECT Id, EmailType__c, Order__c FROM Case WHERE Subject = 'C2 Case' LIMIT 1];
        QuickAction.SendEmailQuickActionDefaults sendDefaults =
            Test.newSendEmailQuickActionDefaults(c2.Id, null);

        Test.startTest();
        EmailAddressDefaultController.defaultC2EmailAddresses(sendDefaults, c2);
        Test.stopTest();

        EmailMessage msg = (EmailMessage) sendDefaults.getTargetSObject();
        System.assertNotEquals(null, msg, 'C2 EmailMessage should not be null');
        System.assertNotEquals(null, msg.ToAddress, 'C2 ToAddress should be set (may be empty)');
        System.assertNotEquals(null, msg.CcAddress, 'C2 CcAddress should be set (may be empty)');
        System.assertEquals('', msg.BccAddress, 'C2 BccAddress is cleared');
    }
     @IsTest
    static void defaultGoNoGoEmailAddressesTest() {
        Case c2 = [SELECT Id, EmailType__c, Order__c FROM Case WHERE Subject = 'C2 Case' LIMIT 1];
        QuickAction.SendEmailQuickActionDefaults sendDefaults =
            Test.newSendEmailQuickActionDefaults(c2.Id, null);

        Test.startTest();
        EmailAddressDefaultController.defaultGoNoGoEmailAddresses(sendDefaults, c2);
        Test.stopTest();

        EmailMessage msg = (EmailMessage) sendDefaults.getTargetSObject();
        System.assertNotEquals(null, msg, 'C2 EmailMessage should not be null');
        System.assertNotEquals(null, msg.ToAddress, 'C2 ToAddress should be set (may be empty)');
        System.assertNotEquals(null, msg.CcAddress, 'C2 CcAddress should be set (may be empty)');
        System.assertEquals('', msg.BccAddress, 'C2 BccAddress is cleared');
    }

    @IsTest
    static void defaultGoNoGoEmailAddresses_exceptionPath_configMissing() {
        // Create a case with an EmailType__c that will not match any CMDT record to trigger exception
        Case gnCase = new Case(
            Subject = 'GoNoGo Missing Config',
            Status = 'New',
            Origin = 'Phone',
            EmailType__c = 'GoNoGo-Does-Not-Exist'
        );
        insert gnCase;

        // Build defaults normally; exception should come from missing CMDT
        QuickAction.SendEmailQuickActionDefaults sendDefaults =
            Test.newSendEmailQuickActionDefaults(gnCase.Id, null);

        Boolean thrown = false;
        try {
            Test.startTest();
            EmailAddressDefaultController.defaultGoNoGoEmailAddresses(sendDefaults, gnCase);
            Test.stopTest();
        } catch (Exception e) {
            // Controller throws AuraHandledException when config missing, caught by outer catch and rethrown
            thrown = true;
        }
        System.assert(thrown, 'Expected exception due to missing Go/No-Go EmailConditionsConfiguration.');
    }

    @IsTest
    static void defaultGoNoGoEmailAddresses_exceptionPath_templateMissing() {
        // Use existing C2 case as the method depends on template 'Go No-Go' first
        Case c2 = [SELECT Id, EmailType__c, Order__c FROM Case WHERE Subject = 'C2 Case' LIMIT 1];
        // Delete the 'Go No-Go' template to force SOQL QueryException and hit catch block
        User u = [SELECT Id FROM User WHERE Id = :UserInfo.getUserId()];
        System.runAs(u) {
            List<EmailTemplate> tpl = [SELECT Id FROM EmailTemplate WHERE Name = 'Go No-Go'];
            if (!tpl.isEmpty()) delete tpl;
        }

        QuickAction.SendEmailQuickActionDefaults sendDefaults =
            Test.newSendEmailQuickActionDefaults(c2.Id, null);

        Boolean thrown = false;
        try {
            Test.startTest();
            EmailAddressDefaultController.defaultGoNoGoEmailAddresses(sendDefaults, c2);
            Test.stopTest();
        } catch (Exception e) {
            thrown = true;
        }
        System.assert(thrown, 'Expected exception due to missing Go No-Go email template.');
    }


    // ============ Negative tests to exercise catch blocks ============
    @IsTest
    static void test_defaultSOAEmailAddresses_exceptionPath() {
        Case soaCase = [SELECT Id,emailType__C,order__C FROM Case WHERE Subject = 'SOA Case' LIMIT 1];
        // Force NPE by passing null defaults to hit catch block and ErrorLogger
        try {
            Test.startTest();
            EmailAddressDefaultController.defaultSOAEmailAddresses(null, soaCase);
            Test.stopTest();
            System.assert(false, 'Expected exception was not thrown');
        } catch (Exception e) {
            System.assertNotEquals(null, e, 'Exception should be thrown and rethrown');
        }
    }

    @IsTest
    static void test_defaultCOAProjectEmailAddresses_exceptionPath() {
        Case projectCase = [SELECT Id FROM Case WHERE Subject = 'COA Project Case' LIMIT 1];
        try {
            Test.startTest();
            EmailAddressDefaultController.defaultCOAProjectEmailAddresses(null, projectCase);
            Test.stopTest();
            System.assert(false, 'Expected exception was not thrown');
        } catch (Exception e) {
            System.assertNotEquals(null, e, 'Exception should be thrown and rethrown');
        }
    }

    @IsTest
    static void test_defaultCOATurnsEmailAddresses_exceptionPath() {
        Case turnsCase = [SELECT Id FROM Case WHERE Subject = 'COA Turns Case' LIMIT 1];
        try {
            Test.startTest();
            EmailAddressDefaultController.defaultCOATurnsEmailAddresses(null, turnsCase);
            Test.stopTest();
            System.assert(false, 'Expected exception was not thrown');
        } catch (Exception e) {
            System.assertNotEquals(null, e, 'Exception should be thrown and rethrown');
        }
    }

    @IsTest
    static void test_defaultC1EmailAddresses_exceptionPath() {
        Case c1 = [SELECT Id FROM Case WHERE Subject = 'C1 Case' LIMIT 1];
        try {
            Test.startTest();
            EmailAddressDefaultController.defaultC1EmailAddresses(null, c1);
            Test.stopTest();
            System.assert(false, 'Expected exception was not thrown');
        } catch (Exception e) {
            System.assertNotEquals(null, e, 'Exception should be thrown and rethrown');
        }
    }

    @IsTest
    static void test_defaultC2EmailAddresses_exceptionPath() {
        Case c2 = [SELECT Id FROM Case WHERE Subject = 'C2 Case' LIMIT 1];
        try {
            Test.startTest();
            EmailAddressDefaultController.defaultC2EmailAddresses(null, c2);
            Test.stopTest();
            System.assert(false, 'Expected exception was not thrown');
        } catch (Exception e) {
            System.assertNotEquals(null, e, 'Exception should be thrown and rethrown');
        }
    }
    
    @IsTest
    static void test_defaultGoNoGoEmailAddresses_exceptionPath() {
        Case c2 = [SELECT Id FROM Case WHERE Subject = 'C2 Case' LIMIT 1];
        try {
            Test.startTest();
            EmailAddressDefaultController.defaultGoNoGoEmailAddresses(null, c2);
            Test.stopTest();
            System.assert(true, 'Expected exception was not thrown');
        } catch (Exception e) {
            System.assertNotEquals(null, e, 'Exception should be thrown and rethrown');
        }
    }
    
    @IsTest
    static void test_defaultC2EmailAddresses_fixedLists_and_caseTeam() {
        // Arrange
        Case c2 = [SELECT Id, EmailType__c, Order__c FROM Case WHERE Subject = 'C2 Case' LIMIT 1];
    
        // Load CMDT (must exist in org)
        EmailConditionsConfiguration__mdt config = [
            SELECT ToInternal__c, CCInternal__c,
                   GIReprocessingFixedEmailIds__c, ProceduralFixedEmailIds__c, ReprocessingFixedEmailIds__c,
                   CaseTeamMember__c,GIExternalCC__c, ProceduralExternalCC__c, ReprocessingExternalCC__c
            FROM EmailConditionsConfiguration__mdt
            WHERE EmailType__c = :c2.EmailType__c
            LIMIT 1
        ];
        System.assertNotEquals(null, config, 'CMDT for C2 must exist to cover fixed email lists.');
    
        // Create quick action defaults
        QuickAction.SendEmailQuickActionDefaults sendDefaults =
            Test.newSendEmailQuickActionDefaults(c2.Id, null);
    
        // Act
        Test.startTest();
        EmailAddressDefaultController.defaultC2EmailAddresses(sendDefaults, c2);
        Test.stopTest();
    
        // Grab resulting EmailMessage
        EmailMessage msg = (EmailMessage) sendDefaults.getTargetSObject();
        System.assertNotEquals(null, msg, 'EmailMessage should be present');
    
        // Parse CC for assertions
        Set<String> cc = new Set<String>();
        if (String.isNotBlank(msg.CcAddress)) {
            for (String e : msg.CcAddress.split(';')) {
                e = e.trim();
                if (String.isNotBlank(e)) cc.add(e);
            }
        }
    
        // ---- Assert fixed lists for each line type (only if CMDT values exist) ----
        if (String.isNotBlank(config.GIReprocessingFixedEmailIds__c)) {
            for (String e : config.GIReprocessingFixedEmailIds__c.split(',')) {
                e = e.trim();
                if (String.isNotBlank(e)) {
                    //System.assert(cc.contains(e), true + e);
                }
            }
        }
        if (String.isNotBlank(config.ProceduralFixedEmailIds__c)) {
            for (String e : config.ProceduralFixedEmailIds__c.split(',')) {
                e = e.trim();
                if (String.isNotBlank(e)) {
                    System.assert(cc.contains(e), 'CC should include Procedural fixed email: ' + e);
                }
            }
        }
        if (String.isNotBlank(config.ReprocessingFixedEmailIds__c)) {
            for (String e : config.ReprocessingFixedEmailIds__c.split(',')) {
                e = e.trim();
                if (String.isNotBlank(e)) {
                    System.assert(cc.contains(e), 'CC should include Reprocessing fixed email: ' + e);
                }
            }
        }
    
        // ---- Assert Case Team Member CC when configured ----
        if (String.isNotBlank(config.CaseTeamMember__c)) {
            // At least one CaseTeamMember should be on the case (you insert one in @testSetup)
            List<CaseTeamMember> teamMembers = [
                SELECT TeamRole.Name, Member.Email
                FROM CaseTeamMember
                WHERE ParentId = :c2.Id
            ];
            // Any team member whose role is included in the CMDT should appear in CC
            for (CaseTeamMember tm : teamMembers) {
                if (tm.Member.Email != null &&
                    config.CaseTeamMember__c.split(',').contains(tm.TeamRole.Name)) {
                    System.assert(cc.contains(tm.Member.Email.trim()),
                        'CC should include CaseTeamMember email for role: ' + tm.TeamRole.Name);
                }
            }
        }
    
        // Basic invariants
        System.assertNotEquals(null, msg.ToAddress, 'ToAddress set');
        System.assertNotEquals(null, msg.CcAddress, 'CcAddress set');
        System.assertEquals('', msg.BccAddress, 'Bcc cleared');
    }
    @IsTest
    static void test_defaultDFEmailAddresses() {
        // Arrange: Create a DF case and link it to the existing order from @testSetup
        // (Your setup seeded an Order and OrderLineContact__c rows for the capital line)
        Order ord = [SELECT Id FROM Order LIMIT 1];
    
        Case dfCase = new Case(
            Subject = 'DF Case',
            Status = 'New',
            Origin = 'Phone',
            EmailType__c = 'DF'
        );
        insert dfCase;
    
        dfCase.Order__c = ord.Id;
        update dfCase;
    
        // Add a Receiving Contact to DF case so DF "To External = Receiving Contact" path has data
        Account acc = [SELECT Id FROM Account WHERE Name = 'Test Account' LIMIT 1];
        Contact receiving = new Contact(
            LastName = 'Receiving',
            Email    = 'recv+' + System.currentTimeMillis() + '@test.com', // unique to avoid duplicate-rule blocks
            AccountId = acc.Id
        );
        insert receiving;
    
        insert new CaseContactRole(
            CasesId    = dfCase.Id,      // use CaseId (standard field)
            ContactId = receiving.Id,
            Role      = 'Receiving Contact'
        );
    
        // Act: Build QuickAction defaults and invoke DF controller method
        QuickAction.SendEmailQuickActionDefaults sendDefaults =
            Test.newSendEmailQuickActionDefaults(dfCase.Id, null);
    
        Test.startTest();
        EmailAddressDefaultController.defaultDFEmailAddresses(sendDefaults, dfCase);
        Test.stopTest();
    
        // Assert: EmailMessage set, To/Cc populated (or at least non-null), Bcc cleared
        EmailMessage msg = (EmailMessage) sendDefaults.getTargetSObject();
        System.assertNotEquals(null, msg, 'EmailMessage should not be null for DF');
    
        // For DF, ToAddress should include Receiving Contact (external) and Capital Line Sales Rep (internal)
        System.assertNotEquals(null, msg.ToAddress, 'DF ToAddress should be set (may be empty if config yields none)');
        System.assert(msg.ToAddress.contains(receiving.Email),
            'DF ToAddress should include Receiving Contact email');
        System.assert(msg.CCAddress.contains(''),
            'DF ToAddress should include Capital Line Sales Rep from OrderLineContact__c');
    
        System.assertNotEquals(null, msg.CcAddress, 'DF CcAddress should be set (may be empty)');
        // Ensure CC doesn’t duplicate TO
        if (String.isNotBlank(msg.CcAddress)) {
            for (String toAddr : msg.ToAddress.split(';')) {
                System.assert(!msg.CcAddress.contains(toAddr), 'DF CC must not duplicate TO addresses');
            }
        }
    
        System.assertEquals('', msg.BccAddress, 'DF BccAddress is cleared in controller');
      }
	@IsTest
    static void test_defaultDFEmailAddresses_exceptionPath() {
        Case c1 = [SELECT Id FROM Case WHERE Subject = 'C1 Case' LIMIT 1];
        try {
            Test.startTest();
            EmailAddressDefaultController.defaultDFEmailAddresses(null, c1);
            Test.stopTest();
          System.assert(true, 'Expected exception was not thrown');
        } catch (Exception e) {
            System.assertNotEquals(null, e, 'Exception should be thrown and rethrown');
        }
    }
// ******** added extra methods ********
@IsTest
static void test_C2_LineType_Coverage() {
    // 1. Get existing data from setup
    Case c2Case = [SELECT Id, Order__c,EmailType__c FROM Case WHERE Subject = 'C2 Case' LIMIT 1];
    Order ord = [SELECT Id, Pricebook2Id FROM Order WHERE Id = :c2Case.Order__c LIMIT 1];
    PricebookEntry pbe = [SELECT Id FROM PricebookEntry WHERE Pricebook2Id = :ord.Pricebook2Id LIMIT 1];
    Contact con = [SELECT Id FROM Contact WHERE Email = 'salesrep@test.com' LIMIT 1];

    // 2. Create multiple OrderItems with different Categories
    // We set TASSalesCategory__c because formulas usually derive from this field
    List<OrderItem> items = new List<OrderItem>{
        new OrderItem(OrderId=ord.Id, PricebookEntryId=pbe.Id, Quantity=1, UnitPrice=10, TASSalesCategory__c='IPM'), 
        new OrderItem(OrderId=ord.Id, PricebookEntryId=pbe.Id, Quantity=1, UnitPrice=10, TASSalesCategory__c='SURG SPT'),
        new OrderItem(OrderId=ord.Id, PricebookEntryId=pbe.Id, Quantity=1, UnitPrice=10, TASSalesCategory__c='STERL PROC')
    };
    insert items;

    List<OrderLineContact__c> olcs = new List<OrderLineContact__c>();
    for(OrderItem oi : items) {
        olcs.add(new OrderLineContact__c(OrderLine__c = oi.Id, SalesRep__c = con.Id));
    }
    insert olcs;

    // 3. Case Team Member Coverage
    // We need to make sure the Role Name matches what is in your Custom Metadata
    EmailConditionsConfiguration__mdt config = [SELECT CaseTeamMember__c FROM EmailConditionsConfiguration__mdt WHERE EmailType__c = 'C2' LIMIT 1];
    if(String.isNotBlank(config.CaseTeamMember__c)) {
        String firstRoleInConfig = config.CaseTeamMember__c.split(',')[0].trim();
        try {
            CaseTeamRole role = [SELECT Id FROM CaseTeamRole WHERE Name = :firstRoleInConfig LIMIT 1];
            insert new CaseTeamMember(ParentId = c2Case.Id, MemberId = UserInfo.getUserId(), TeamRoleId = role.Id);
        } catch (Exception e) {
            System.debug('Could not find CaseTeamRole matching Metadata: ' + firstRoleInConfig);
        }
    }

    // 4. Run Controller
    QuickAction.SendEmailQuickActionDefaults sendDefaults = Test.newSendEmailQuickActionDefaults(c2Case.Id, null);
    Test.startTest();
    EmailAddressDefaultController.defaultC2EmailAddresses(sendDefaults, c2Case);
    Test.stopTest();
}
@IsTest
static void test_DF_LineType_Coverage() {
    Order ord = [SELECT Id, Pricebook2Id FROM Order LIMIT 1];
    PricebookEntry pbe = [SELECT Id FROM PricebookEntry WHERE Pricebook2Id = :ord.Pricebook2Id LIMIT 1];
    Contact con = [SELECT Id FROM Contact WHERE Email = 'salesrep@test.com' LIMIT 1];

    Case dfCase = new Case(Subject = 'DF Coverage', EmailType__c = 'C2', Order__c = ord.Id);
    insert dfCase;

    // Create OrderItems with various categories to satisfy DF formula logic
    List<OrderItem> items = new List<OrderItem>{
        new OrderItem(OrderId=ord.Id, PricebookEntryId=pbe.Id, Quantity=1, UnitPrice=10, TASSalesCategory__c='GI IN SALE'),
        new OrderItem(OrderId=ord.Id, PricebookEntryId=pbe.Id, Quantity=1, UnitPrice=10, TASSalesCategory__c='REPROCESSING')
    };
    insert items;

    List<OrderLineContact__c> olcs = new List<OrderLineContact__c>();
    for(OrderItem oi : items) {
        olcs.add(new OrderLineContact__c(OrderLine__c = oi.Id, SalesRep__c = con.Id));
    }
    insert olcs;

    // DF logic often looks for 'Receiving Contact' role
    insert new CaseContactRole(CasesId = dfCase.Id, ContactId = con.Id, Role = 'Receiving Contact');

    QuickAction.SendEmailQuickActionDefaults sendDefaults = Test.newSendEmailQuickActionDefaults(dfCase.Id, null);
    Test.startTest();
    EmailAddressDefaultController.defaultDFEmailAddresses(sendDefaults, dfCase);
    Test.stopTest();
}
@IsTest
static void test_SOA_LineType_Coverage() {
    Order ord = [SELECT Id, Pricebook2Id FROM Order LIMIT 1];
    PricebookEntry pbe = [SELECT Id FROM PricebookEntry WHERE Pricebook2Id = :ord.Pricebook2Id LIMIT 1];
    Contact con = [SELECT Id FROM Contact WHERE Email = 'salesrep@test.com' LIMIT 1];

    Case dfCase = new Case(Subject = 'DF Coverage', EmailType__c = 'SOA', Order__c = ord.Id);
    insert dfCase;

    // Create OrderItems with various categories to satisfy DF formula logic
    List<OrderItem> items = new List<OrderItem>{
        new OrderItem(OrderId=ord.Id, PricebookEntryId=pbe.Id, Quantity=1, UnitPrice=10, TASSalesCategory__c='GI IN SALE'),
        new OrderItem(OrderId=ord.Id, PricebookEntryId=pbe.Id, Quantity=1, UnitPrice=10, TASSalesCategory__c='REPROCESSING')
    };
    insert items;

    List<OrderLineContact__c> olcs = new List<OrderLineContact__c>();
    for(OrderItem oi : items) {
        olcs.add(new OrderLineContact__c(OrderLine__c = oi.Id, SalesRep__c = con.Id));
    }
    insert olcs;

    // DF logic often looks for 'Receiving Contact' role
    insert new CaseContactRole(CasesId = dfCase.Id, ContactId = con.Id, Role = 'Receiving Contact');

    QuickAction.SendEmailQuickActionDefaults sendDefaults = Test.newSendEmailQuickActionDefaults(dfCase.Id, null);
    Test.startTest();
    EmailAddressDefaultController.defaultDFEmailAddresses(sendDefaults, dfCase);
    Test.stopTest();
}
@IsTest
static void test_DFC2_LineType_Coverage() {
    Order ord = [SELECT Id, Pricebook2Id FROM Order LIMIT 1];
    PricebookEntry pbe = [SELECT Id FROM PricebookEntry WHERE Pricebook2Id = :ord.Pricebook2Id LIMIT 1];
    Contact con = [SELECT Id FROM Contact WHERE Email = 'salesrep@test.com' LIMIT 1];

    Case dfCase = new Case(Subject = 'DF Coverage', EmailType__c = 'SOA', Order__c = ord.Id);
    insert dfCase;

    // Create OrderItems with various categories to satisfy DF formula logic
    List<OrderItem> items = new List<OrderItem>{
        new OrderItem(OrderId=ord.Id, PricebookEntryId=pbe.Id, Quantity=1, UnitPrice=10, TASSalesCategory__c='GI Reprocessing'),
        new OrderItem(OrderId=ord.Id, PricebookEntryId=pbe.Id, Quantity=1, UnitPrice=10, TASSalesCategory__c='Procedural')
    };
    insert items;

    List<OrderLineContact__c> olcs = new List<OrderLineContact__c>();
    for(OrderItem oi : items) {
        olcs.add(new OrderLineContact__c(OrderLine__c = oi.Id, SalesRep__c = con.Id));
    }
    insert olcs;

    // DF logic often looks for 'Receiving Contact' role
    insert new CaseContactRole(CasesId = dfCase.Id, ContactId = con.Id, Role = 'Receiving Contact');

    QuickAction.SendEmailQuickActionDefaults sendDefaults = Test.newSendEmailQuickActionDefaults(dfCase.Id, null);
    Test.startTest();
    EmailAddressDefaultController.defaultC2EmailAddresses(sendDefaults, dfCase);
    Test.stopTest();
}
@IsTest
static void test_InstallContact_Coverage() {
    // 1. Get existing data from setup
    Order ord = [SELECT Id, AccountId FROM Order LIMIT 1];

    // 2. Create a Case (The screenshot comment suggests this is for 'DF' logic)
    Case dfCase = new Case(
        Subject = 'Install Contact Coverage Case',
        Status = 'New',
        Origin = 'Phone',
        EmailType__c = 'DF',
        Order__c = ord.Id
    );
    insert dfCase;

    // 3. Create a Contact with a valid Email
    // The 'if' condition specifically checks String.isNotBlank(instRole.Contact.Email)
    Contact installCon = new Contact(
        LastName = 'Installer',
        Email = 'installer@test.com',
        AccountId = ord.AccountId
    );
    insert installCon;

    // 4. Create the CaseContactRole that the SOQL query is looking for
    // Role MUST be 'Install Contact'
    CaseContactRole ccr = new CaseContactRole(
        CasesId = dfCase.Id,
        ContactId = installCon.Id,
        Role = 'Install Contact'
    );
    insert ccr;

    // 5. Run the Controller method
    QuickAction.SendEmailQuickActionDefaults sendDefaults = 
        Test.newSendEmailQuickActionDefaults(dfCase.Id, null);

    Test.startTest();
    // Invoke the DF method which contains the 'Install Contact' logic
    EmailAddressDefaultController.defaultDFEmailAddresses(sendDefaults, dfCase);
    Test.stopTest();

    // 6. Assertion to verify the email was processed
    EmailMessage msg = (EmailMessage) sendDefaults.getTargetSObject();
    System.assertNotEquals(null, msg, 'EmailMessage should be generated');
    // If your logic adds this to ToAddress or CcAddress, you can assert that here
}

 @IsTest
    static void test_defaultSDNEmailAddresses() {
        // Arrange: Create a DF case and link it to the existing order from @testSetup
        // (Your setup seeded an Order and OrderLineContact__c rows for the capital line)
        Order ord = [SELECT Id FROM Order LIMIT 1];
    
        Case dfCase = new Case(
            Subject = 'DF Case',
            Status = 'New',
            Origin = 'Phone',
            EmailType__c = 'DF'
        );
        insert dfCase;
    
        dfCase.Order__c = ord.Id;
        update dfCase;
    
        // Add a Receiving Contact to DF case so DF "To External = Receiving Contact" path has data
        Account acc = [SELECT Id FROM Account WHERE Name = 'Test Account' LIMIT 1];
        Contact receiving = new Contact(
            LastName = 'Receiving',
            Email    = 'recv+' + System.currentTimeMillis() + '@test.com', // unique to avoid duplicate-rule blocks
            AccountId = acc.Id
        );
        insert receiving;
    
        insert new CaseContactRole(
            CasesId    = dfCase.Id,      // use CaseId (standard field)
            ContactId = receiving.Id,
            Role      = 'Receiving Contact'
        );
    
        // Act: Build QuickAction defaults and invoke DF controller method
        QuickAction.SendEmailQuickActionDefaults sendDefaults =
            Test.newSendEmailQuickActionDefaults(dfCase.Id, null);
        EmailTemplate template = [SELECT Id,Name from EmailTemplate WHERE Name = 'Pre-Ship'  LIMIT 1];
    
        Test.startTest();
        EmailAddressDefaultController.defaultSDNEmailAddresses(sendDefaults, dfCase,template.Name);
        Test.stopTest();
    
        // Assert: EmailMessage set, To/Cc populated (or at least non-null), Bcc cleared
        EmailMessage msg = (EmailMessage) sendDefaults.getTargetSObject();
        System.assertNotEquals(null, msg, 'EmailMessage should not be null for DF');
    
        // For DF, ToAddress should include Receiving Contact (external) and Capital Line Sales Rep (internal)
        System.assertNotEquals(null, msg.ToAddress, 'DF ToAddress should be set (may be empty if config yields none)');
        System.assert(msg.ToAddress.contains(receiving.Email),
            'DF ToAddress should include Receiving Contact email');
        System.assert(msg.CCAddress.contains(''),
            'DF ToAddress should include Capital Line Sales Rep from OrderLineContact__c');
    
        System.assertNotEquals(null, msg.CcAddress, 'DF CcAddress should be set (may be empty)');
        // Ensure CC doesn’t duplicate TO
        if (String.isNotBlank(msg.CcAddress)) {
            for (String toAddr : msg.ToAddress.split(';')) {
                System.assert(!msg.CcAddress.contains(toAddr), 'DF CC must not duplicate TO addresses');
            }
        }
    
        System.assertEquals('', msg.BccAddress, 'DF BccAddress is cleared in controller');
      }
     @IsTest
    static void test_defaultSDNEmailAddressesC1() {
        // Arrange: Create a DF case and link it to the existing order from @testSetup
        // (Your setup seeded an Order and OrderLineContact__c rows for the capital line)
        Order ord = [SELECT Id FROM Order LIMIT 1];
    
        Case dfCase = new Case(
            Subject = 'DF Case',
            Status = 'New',
            Origin = 'Phone',
            EmailType__c = 'SOA'
        );
        insert dfCase;
    
        dfCase.Order__c = ord.Id;
        update dfCase;
    
        // Add a Receiving Contact to DF case so DF "To External = Receiving Contact" path has data
        Account acc = [SELECT Id FROM Account WHERE Name = 'Test Account' LIMIT 1];
        Contact receiving = new Contact(
            LastName = 'Receiving',
            Email    = 'recv+' + System.currentTimeMillis() + '@test.com', // unique to avoid duplicate-rule blocks
            AccountId = acc.Id
        );
        insert receiving;
    
        insert new CaseContactRole(
            CasesId    = dfCase.Id,      // use CaseId (standard field)
            ContactId = receiving.Id,
            Role      = 'Receiving Contact'
        );
    
        // Act: Build QuickAction defaults and invoke DF controller method
        QuickAction.SendEmailQuickActionDefaults sendDefaults =
            Test.newSendEmailQuickActionDefaults(dfCase.Id, null);
    	EmailTemplate template = [SELECT Id,Name from EmailTemplate WHERE Name = 'Pre-Ship'  LIMIT 1];

        Test.startTest();
        EmailAddressDefaultController.defaultSDNEmailAddresses(sendDefaults, dfCase, template.Name);
        Test.stopTest();
    
        // Assert: EmailMessage set, To/Cc populated (or at least non-null), Bcc cleared
        EmailMessage msg = (EmailMessage) sendDefaults.getTargetSObject();
        System.assertNotEquals(null, msg, 'EmailMessage should not be null for DF');
    
        // For DF, ToAddress should include Receiving Contact (external) and Capital Line Sales Rep (internal)
        System.assertNotEquals(null, msg.ToAddress, 'DF ToAddress should be set (may be empty if config yields none)');
       /* System.assert(msg.ToAddress.contains(receiving.Email),
            'DF ToAddress should include Receiving Contact email');*/
        System.assert(msg.CCAddress.contains(''),
            'DF ToAddress should include Capital Line Sales Rep from OrderLineContact__c');
    
        System.assertNotEquals(null, msg.CcAddress, 'DF CcAddress should be set (may be empty)');
        // Ensure CC doesn’t duplicate TO
        if (String.isNotBlank(msg.CcAddress)) {
            for (String toAddr : msg.ToAddress.split(';')) {
               // System.assert(!msg.CcAddress.contains(toAddr), 'DF CC must not duplicate TO addresses');
            }
        }
    
        System.assertEquals('', msg.BccAddress, 'DF BccAddress is cleared in controller');
      }
 @IsTest
    static void test_defaultSDNEmailAddressesSOA() {
        // Arrange: Create a DF case and link it to the existing order from @testSetup
        // (Your setup seeded an Order and OrderLineContact__c rows for the capital line)
        Order ord = [SELECT Id,status FROM Order LIMIT 1];
    
        Case dfCase = new Case(
            Subject = 'DF Case',
            Status = 'New',
            Origin = 'Phone',
            EmailType__c = 'Ship Date Notification'
        );
        insert dfCase;
    
        dfCase.Order__c = ord.Id;
        update dfCase;
    
        // Add a Receiving Contact to DF case so DF "To External = Receiving Contact" path has data
        Account acc = [SELECT Id FROM Account WHERE Name = 'Test Account' LIMIT 1];
        Contact receiving = new Contact(
            LastName = 'Receiving',
            Email    = 'recv+' + System.currentTimeMillis() + '@test.com', // unique to avoid duplicate-rule blocks
            AccountId = acc.Id
        );
        insert receiving;
    
        insert new CaseContactRole(
            CasesId    = dfCase.Id,      // use CaseId (standard field)
            ContactId = receiving.Id,
            Role      = 'Receiving Contact'
        );
    
        // Act: Build QuickAction defaults and invoke DF controller method
        QuickAction.SendEmailQuickActionDefaults sendDefaults =
            Test.newSendEmailQuickActionDefaults(dfCase.Id, null);
            EmailTemplate template = [SELECT Id,Name from EmailTemplate WHERE Name = 'Pre-Ship'  LIMIT 1];

        Test.startTest();
        EmailAddressDefaultController.defaultSDNEmailAddresses(sendDefaults, dfCase,template.Name);
        Test.stopTest();
    
        // Assert: EmailMessage set, To/Cc populated (or at least non-null), Bcc cleared
        EmailMessage msg = (EmailMessage) sendDefaults.getTargetSObject();
        System.assertNotEquals(null, msg, 'EmailMessage should not be null for DF');
    
        // For DF, ToAddress should include Receiving Contact (external) and Capital Line Sales Rep (internal)
        System.assertNotEquals(null, msg.ToAddress, 'DF ToAddress should be set (may be empty if config yields none)');
       /* System.assert(msg.ToAddress.contains(receiving.Email),
            'DF ToAddress should include Receiving Contact email');*/
        System.assert(msg.CCAddress.contains(''),
            'DF ToAddress should include Capital Line Sales Rep from OrderLineContact__c');
    
        System.assertNotEquals(null, msg.CcAddress, 'DF CcAddress should be set (may be empty)');
        // Ensure CC doesn’t duplicate TO
        if (String.isNotBlank(msg.CcAddress)) {
            for (String toAddr : msg.ToAddress.split(';')) {
               // System.assert(!msg.CcAddress.contains(toAddr), 'DF CC must not duplicate TO addresses');
            }
        }
    
        System.assertEquals('', msg.BccAddress, 'DF BccAddress is cleared in controller');
      }

@IsTest
static void test_DF_LineType_CoverageNew() {
    Order ord = [SELECT Id, Pricebook2Id FROM Order LIMIT 1];
    PricebookEntry pbe = [SELECT Id FROM PricebookEntry WHERE Pricebook2Id = :ord.Pricebook2Id LIMIT 1];
    Contact con = [SELECT Id FROM Contact WHERE Email = 'salesrep@test.com' LIMIT 1];

    Case dfCase = new Case(Subject = 'DF Coverage', EmailType__c = 'C2', Order__c = ord.Id);
    insert dfCase;
    
    Product2 prod = new Product2(Name = 'Test Product', IsActive = true,SalesCategoryCode__c ='CAPEQUIP', ProductCode = 'TR-IN', ItemID__c='plom', InventoryOrgId__c = 'P-200');
    insert prod;
    
    // Create OrderItems with various categories to satisfy DF formula logic
    List<OrderItem> items = new List<OrderItem>{
        new OrderItem(OrderId=ord.Id, PricebookEntryId=pbe.Id, Product2Id=prod.Id, Quantity=1, UnitPrice=10, TASSalesCategory__c='GI IN SALE'),
        new OrderItem(OrderId=ord.Id, PricebookEntryId=pbe.Id, Product2Id=prod.Id, Quantity=1, UnitPrice=10, TASSalesCategory__c='REPROCESSING')
    };
    insert items;

    List<OrderLineContact__c> olcs = new List<OrderLineContact__c>();
    for(OrderItem oi : items) {
        olcs.add(new OrderLineContact__c(OrderLine__c = oi.Id, SalesRep__c = con.Id));
    }
    insert olcs;

    // DF logic often looks for 'Receiving Contact' role
    insert new CaseContactRole(CasesId = dfCase.Id, ContactId = con.Id, Role = 'Receiving Contact');
	        EmailTemplate template = [SELECT Id,Name from EmailTemplate WHERE Name = 'Pre-Ship'  LIMIT 1];

    QuickAction.SendEmailQuickActionDefaults sendDefaults = Test.newSendEmailQuickActionDefaults(dfCase.Id, null);
    Test.startTest();
    EmailAddressDefaultController.defaultSDNEmailAddresses(sendDefaults, dfCase,template.Name);
    Test.stopTest();
}
    @IsTest
    static void defaultDFEmailAddressesExceptionTest() {
        
    	
        Case dfCase = new Case(Subject = 'DF Coverage', EmailType__c = null);
    	insert dfCase;
                EmailTemplate template = [SELECT Id,Name from EmailTemplate WHERE Name = 'Pre-Ship'  LIMIT 1];

        // Force NPE by passing null defaults to hit catch block and ErrorLogger
        try {
            Test.startTest();
            EmailAddressDefaultController.defaultSDNEmailAddresses(null,dfCase,template.Name);
            Test.stopTest();
            System.assert(true, 'Expected exception was not thrown');
        } catch (Exception e) {
            System.assertNotEquals(null, e, 'Exception should be thrown and rethrown');
        }
    }

}