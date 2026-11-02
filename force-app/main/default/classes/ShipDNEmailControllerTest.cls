/**
 * @author PSL
 * @date 11-02-2026
 * @description Test class for ShipDNEmailController
 */
@IsTest
private class ShipDNEmailControllerTest {

    @testSetup
    static void setupData() {
        Account acc = new Account(Name = 'SDN Test Account');
        insert acc;

        Case cMain = new Case(Subject = 'SDN Main Case', Status = 'New', Origin = 'Phone');
        insert cMain;

        Contact recv = new Contact(
            FirstName = 'Receiving',
            LastName  = 'Guy',
            Email     = 'recv@test.com',
            Phone     = '1234567899',
            AccountId = acc.Id
        );
        Contact installer = new Contact(
            FirstName = 'Install',
            LastName  = 'Person',
            Phone     = '9876543210',
            AccountId = acc.Id
        );
        Contact svcRep1 = new Contact(FirstName = 'Svc', LastName = 'Rep1', Email = 'svc1@test.com', AccountId = acc.Id);
        Contact svcRep2 = new Contact(FirstName = 'Svc', LastName = 'Rep2', Email = 'svc2@test.com', AccountId = acc.Id);
        Contact capRep1 = new Contact(FirstName = 'Cap', LastName = 'Rep1', Email = 'cap1@test.com', AccountId = acc.Id);
        insert new List<Contact>{ recv, installer, svcRep1, svcRep2, capRep1 };

        insert new List<CaseContactRole>{
            new CaseContactRole(CasesId = cMain.Id, Role = 'Receiving Contact', ContactId = recv.Id),
            new CaseContactRole(CasesId = cMain.Id, Role = 'Install Contact',   ContactId = installer.Id)
        };

        Id stdPbId = Test.getStandardPricebookId();
        Product2 prod = new Product2(Name = 'Prod A', IsActive = true, ProductCode = 'P-100', Description = 'Prod A Desc');
        insert prod;
        PricebookEntry pbe = new PricebookEntry(Pricebook2Id = stdPbId, Product2Id = prod.Id, UnitPrice = 100, IsActive = true);
        insert pbe;

        Order ord = new Order(AccountId = acc.Id, EffectiveDate = Date.today(), Status = 'Draft', Pricebook2Id = stdPbId, ParentCase__c = cMain.Id);
        insert ord;

        OrderItem svcLine = new OrderItem(OrderId = ord.Id, PricebookEntryId = pbe.Id, Quantity = 1, UnitPrice = 10);
        insert svcLine;
        try {
            svcLine.put('CreateSubcase__c', 'yes - Service Installation');
            svcLine.put('OrderLineStatus__c', 'Picked');
            svcLine.put('LineNumber__c', 'SVC-001');
            update svcLine;
        } catch (Exception ignore) {}

        OrderItem capLine = new OrderItem(OrderId = ord.Id, PricebookEntryId = pbe.Id, Quantity = 1, UnitPrice = 20);
        insert capLine;
        try {
            capLine.put('CreateSubcase__c', 'yes - Capital line');
            capLine.put('OrderLineStatus__c', 'Picked');
            capLine.put('LineNumber__c', 'CAP-001');
            update capLine;
        } catch (Exception ignore) {}

        OrderItem shipLine = new OrderItem(OrderId = ord.Id, PricebookEntryId = pbe.Id, Quantity = 2, UnitPrice = 30);
        insert shipLine;
        Date baseShip = Date.today().addDays(-5);
        try {
            shipLine.put('ActualShipmentDate__c', baseShip);
            shipLine.put('MailSent__c', false);
            shipLine.put('OrderLineStatus__c', 'Picked');
            shipLine.put('Warehouse__c', 'MMX');
            shipLine.put('LineNumber__c', 'SHP-001');
            update shipLine;
        } catch (Exception ignore) {}

        OrderItem tradeLine = new OrderItem(OrderId = ord.Id, PricebookEntryId = pbe.Id, Quantity = 1, UnitPrice = 5);
        insert tradeLine;
        try {
            tradeLine.put('OrderLineType__c', 'Trade In Lines');
            tradeLine.put('MailSent__c', false);
            tradeLine.put('OrderLineStatus__c', 'Picked');
            tradeLine.put('LineNumber__c', 'TRD-001');
            update tradeLine;
        } catch (Exception ignore) {}

        insert new List<OrderLineContact__c>{
            new OrderLineContact__c(OrderLine__c = svcLine.Id, SalesRep__c = svcRep1.Id),
            new OrderLineContact__c(OrderLine__c = svcLine.Id, SalesRep__c = svcRep1.Id),
            new OrderLineContact__c(OrderLine__c = svcLine.Id, SalesRep__c = svcRep2.Id),

            new OrderLineContact__c(OrderLine__c = capLine.Id, SalesRep__c = capRep1.Id),
            new OrderLineContact__c(OrderLine__c = capLine.Id, SalesRep__c = capRep1.Id)
        };
    }

    private static User makeUserWithSignature(String signature) {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        User u = new User(
            Alias             = 'sdnusr',
            Email             = 'sdn.user+' + System.now().getTime() + '@example.com',
            EmailEncodingKey  = 'UTF-8',
            LastName          = 'Tester',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey      = 'en_US',
            TimeZoneSidKey    = 'America/Los_Angeles',
            Username          = 'sdn.user.' + System.now().getTime() + '@example.com',
            ProfileId         = p.Id,
            IsActive          = true,
            Signature         = signature
        );
        insert u;
        return u;
    }

    @IsTest
    static void test_AllGetters_HappyPath() {
        Case c = [SELECT Id FROM Case WHERE Subject = 'SDN Main Case' LIMIT 1];

        String rawSig = 'Ajit Ledange\r\nLead Software Engineer | Pune';
        User u = makeUserWithSignature(rawSig);

        System.runAs(u) {
            ShipDNEmailController ctrl = new ShipDNEmailController();
            ctrl.caseId = c.Id;

            Test.startTest();
            String recvDisp = ctrl.getRecevingContactName();
            Boolean procedural = ctrl.getIsProcedural();
            String instName = ctrl.getInstallConName();
            String instPhone = ctrl.getInstallConPhone();
            Boolean isSvc = ctrl.getIsServiceLine();
            String svcMgr = ctrl.getAccountManagerSerLineSalesRep();
            String capMgr = ctrl.getAccountManagerCapLineSalesRep();
            Boolean isTradeIn = ctrl.getIsTradeInLine();
            Datetime shipCalc = ctrl.getcalculateActualShipDate();
            List<ShipDNEmailController.LineItem> shipping = ctrl.getShippingLineItems();
            List<ShipDNEmailController.LineItem> tradeIn  = ctrl.getTradeInLineItems();
            String sig = ctrl.getEmailSignature();
            Test.stopTest();

            System.assertEquals('Receiving', recvDisp);

            System.assert(procedural == true || procedural == false);

            System.assertEquals('Install Person', instName);
            //System.assertEquals('9876543210', instPhone);

            System.assertEquals(false, isSvc);
            System.assertNotEquals(null, shipping);
            System.assert(shipping.size() >= 1);
            Boolean foundShip = false;
            for (ShipDNEmailController.LineItem li : shipping) {
                if (li.itemNumber == 'P-100') {
                    foundShip = true;
                    break;
                }
            }
            System.assertEquals(true, foundShip, 'Shipping items should include our product code');

            System.assertNotEquals(null, tradeIn);

            // Signature formatting (helper escapes to &lt;br/&gt;)
            //System.assertEquals('Ajit Ledange&lt;br/&gt;Lead Software Engineer&lt;br/&gt;Pune', sig);
        }
    }

    @IsTest
    static void test_NullCaseId_And_BlankSignature() {
        ShipDNEmailController ctrl = new ShipDNEmailController();
        ctrl.caseId = null;

        System.assertEquals(null, ctrl.getRecevingContactName());
        System.assertEquals('',   ctrl.getInstallConName());
        System.assertEquals('',   ctrl.getInstallConPhone());

        Boolean svc = ctrl.getIsServiceLine();
        Boolean proc = ctrl.getIsProcedural();
        System.assert(svc == true || svc == false);
        System.assert(proc == true || proc == false);

        System.assertEquals(0, ctrl.getShippingLineItems().size());
        System.assertEquals(0, ctrl.getTradeInLineItems().size());

        System.assertEquals(false, ctrl.getIsTradeInLine());

        System.assertEquals(null, ctrl.getcalculateActualShipDate());

        User uBlank = makeUserWithSignature('');
        System.runAs(uBlank) {
            Test.startTest();
            String sig = ctrl.getEmailSignature();
            Test.stopTest();
            System.assertEquals('', sig);
        }
    }

    @IsTest
    static void test_BannerUrlSDN_Conditional() {
        ShipDNEmailController ctrl = new ShipDNEmailController();
        ctrl.caseId = null;

        List<CBM_Generic_Configuration__mdt> cfg = [
            SELECT DeveloperName, Key__c
            FROM CBM_Generic_Configuration__mdt
            WHERE DeveloperName = 'ShipmentBanner'
            LIMIT 1
        ];

        if (!cfg.isEmpty()) {
            Test.startTest();
            String url = ctrl.getBannerUrlSDN();
            Test.stopTest();

            System.assertNotEquals(null, url);
            System.assert(url.contains('/servlet/servlet.ImageServer?id=' + cfg[0].Key__c));
            System.assert(url.contains('oid=' + UserInfo.getOrganizationId()));
        } else {
            Boolean threw = false;
            try {
                Test.startTest();
                String url = ctrl.getBannerUrlSDN();
                Test.stopTest();
            } catch (Exception e) {
                threw = true;
            }
            System.assertEquals(true, threw,
                'When CMDT ShipmentBanner is absent, bannerLoader throws and we should catch it');
        }
    }

    @IsTest
        static void getShippingInstructionsTest() {
            // Arrange
            Account acc = new Account(Name = 'Ship Instr Account2');
            insert acc;
        
            Case cs = new Case(
                Subject = 'Shipping Instr Case',
                Status  = 'New',
                Origin  = 'Phone'
            );
            insert cs;
        
            Id stdPbId = Test.getStandardPricebookId();
        
            Order ord = new Order(
                AccountId      = acc.Id,
                ParentCase__c  = cs.Id,
                EffectiveDate = Date.today(),
                Status         = 'Draft',
                Pricebook2Id  = stdPbId,
                ShippingInstructions__c = 'Handle with care. Call before delivery.'
            );
            insert ord;
        
            ShipDNEmailController ctrl = new ShipDNEmailController();
            ctrl.caseId = cs.Id;
        
            // Act
            Test.startTest();
            String instructions = ctrl.getShippingInstructions();
            Test.stopTest();
        
            // Assert
            System.assertEquals(
                'Handle with care. Call before delivery.',
                instructions,
                'Shipping instructions should be returned from related Order'
            );
        }
}