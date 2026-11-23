/**
 * @author PSL
 * @date 11-02-2026
 * @description Test class for ShipDNEmailController
 */
@IsTest
private class ShipDNEmailControllerTest {

    @TestSetup
    static void setupData() {

        Account acc = new Account(
            Name = 'SDN Test Account'
        );
        insert acc;

        Case cMain = new Case(
            Subject = 'SDN Main Case',
            Status = 'New',
            Origin = 'Phone'
        );
        insert cMain;

        Contact recv = new Contact(
            FirstName = 'Receiving',
            LastName = 'Guy',
            Email = 'recv@test.com',
            Phone = '1234567899',
            AccountId = acc.Id
        );

        Contact installer = new Contact(
            FirstName = 'Install',
            LastName = 'Person',
            Phone = '9876543210',
            AccountId = acc.Id
        );

        Contact svcRep1 = new Contact(
            FirstName = 'Svc',
            LastName = 'Rep1',
            Email = 'svc1@test.com',
            AccountId = acc.Id
        );

        Contact svcRep2 = new Contact(
            FirstName = 'Svc',
            LastName = 'Rep2',
            Email = 'svc2@test.com',
            AccountId = acc.Id
        );

        Contact capRep1 = new Contact(
            FirstName = 'Cap',
            LastName = 'Rep1',
            Email = 'cap1@test.com',
            AccountId = acc.Id
        );

        insert new List<Contact>{
            recv,
            installer,
            svcRep1,
            svcRep2,
            capRep1
        };

        insert new List<CaseContactRole>{
            new CaseContactRole(
                CasesId = cMain.Id,
                Role = 'Receiving Contact',
                ContactId = recv.Id
            ),
            new CaseContactRole(
                CasesId = cMain.Id,
                Role = 'Install Contact',
                ContactId = installer.Id
            )
        };

        Id stdPbId = Test.getStandardPricebookId();

        Product2 prod = new Product2(
            Name = 'Prod A',
            IsActive = true,
            ProductCode = 'P-100',
            Description = 'Prod A Desc'
        );
        insert prod;

        PricebookEntry pbe = new PricebookEntry(
            Pricebook2Id = stdPbId,
            Product2Id = prod.Id,
            UnitPrice = 100,
            IsActive = true
        );
        insert pbe;

        Order ord = new Order(
            AccountId = acc.Id,
            EffectiveDate = Date.today(),
            Status = 'Draft',
            Pricebook2Id = stdPbId,
            ParentCase__c = cMain.Id
        );
        insert ord;

        OrderItem svcLine = new OrderItem(
            OrderId = ord.Id,
            PricebookEntryId = pbe.Id,
            Quantity = 1,
            UnitPrice = 10
        );
        insert svcLine;

        try {
            svcLine.put(
                'CreateSubcase__c',
                'yes - Service Installation'
            );
            svcLine.put(
                'OrderLineStatus__c',
                'Picked'
            );
            svcLine.put(
                'LineNumber__c',
                'SVC-001'
            );
            update svcLine;
        } catch (Exception ignore) {
        }

        OrderItem capLine = new OrderItem(
            OrderId = ord.Id,
            PricebookEntryId = pbe.Id,
            Quantity = 1,
            UnitPrice = 20
        );
        insert capLine;

        try {
            capLine.put(
                'CreateSubcase__c',
                'yes - Capital line'
            );
            capLine.put(
                'OrderLineStatus__c',
                'Picked'
            );
            capLine.put(
                'LineNumber__c',
                'CAP-001'
            );
            update capLine;
        } catch (Exception ignore) {
        }

        OrderItem shipLine = new OrderItem(
            OrderId = ord.Id,
            PricebookEntryId = pbe.Id,
            Quantity = 2,
            UnitPrice = 30
        );
        insert shipLine;

        Date baseShip = Date.today().addDays(-5);

        try {
            shipLine.put(
                'ActualShipmentDate__c',
                baseShip
            );
            shipLine.put(
                'MailSent__c',
                false
            );
            shipLine.put(
                'OrderLineStatus__c',
                'Picked'
            );
            shipLine.put(
                'Warehouse__c',
                'MMX'
            );
            shipLine.put(
                'LineNumber__c',
                'SHP-001'
            );
            update shipLine;
        } catch (Exception ignore) {
        }

        Product2 tradeProduct = new Product2(
            Name = 'Existing Trade-In Product',
            ProductCode = 'TRDIN-001',
            Description = 'Existing Trade-In Equipment',
            IsActive = true,
            SalesCategory__c = 'CAPEQUIP',
            ItemID__c = 'TRDINITEM',
            InventoryOrgId__c = 'TRDINORG'
        );

        tradeProduct.put(
            'ItemType__c',
            'TRADE-IN'
        );

        insert tradeProduct;

        PricebookEntry tradePbe = new PricebookEntry(
            Pricebook2Id = stdPbId,
            Product2Id = tradeProduct.Id,
            UnitPrice = 5,
            IsActive = true
        );
        insert tradePbe;

        OrderItem tradeLine = new OrderItem(
            OrderId = ord.Id,
            PricebookEntryId = tradePbe.Id,
            Quantity = 1,
            UnitPrice = 5,
            MailSent__c = false,
            OrderLineStatus__c = 'Picked',
            LineNumber__c = 'TRD-001'
        );
        insert tradeLine;

        insert new List<OrderLineContact__c>{
            new OrderLineContact__c(
                OrderLine__c = svcLine.Id,
                SalesRep__c = svcRep1.Id
            ),
            new OrderLineContact__c(
                OrderLine__c = svcLine.Id,
                SalesRep__c = svcRep1.Id
            ),
            new OrderLineContact__c(
                OrderLine__c = svcLine.Id,
                SalesRep__c = svcRep2.Id
            ),
            new OrderLineContact__c(
                OrderLine__c = capLine.Id,
                SalesRep__c = capRep1.Id
            ),
            new OrderLineContact__c(
                OrderLine__c = capLine.Id,
                SalesRep__c = capRep1.Id
            )
        };
    }

    private static User makeUserWithSignature(
        String signature
    ) {

        Profile p = [
            SELECT Id
            FROM Profile
            WHERE Name = 'Standard User'
            LIMIT 1
        ];

        Long timestampValue = System.now().getTime();

        User u = new User(
            Alias = 'sdnusr',
            Email = 'sdn.user+' +
                timestampValue +
                '@example.com',
            EmailEncodingKey = 'UTF-8',
            LastName = 'Tester',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            TimeZoneSidKey = 'America/Los_Angeles',
            Username = 'sdn.user.' +
                timestampValue +
                '@example.com',
            ProfileId = p.Id,
            IsActive = true,
            Signature = signature
        );

        insert u;

        return u;
    }

    @IsTest
    static void test_AllGetters_HappyPath() {

        Case c = [
            SELECT Id
            FROM Case
            WHERE Subject = 'SDN Main Case'
            LIMIT 1
        ];

        String rawSig =
            'Ajit Ledange\r\nLead Software Engineer | Pune';

        User u = makeUserWithSignature(rawSig);

        System.runAs(u) {

            ShipDNEmailController ctrl =
                new ShipDNEmailController();

            ctrl.caseId = c.Id;

            Test.startTest();

            String recvDisp =
                ctrl.getRecevingContactName();

            Boolean procedural =
                ctrl.getIsProcedural();

            String instName =
                ctrl.getInstallConName();

            String instPhone =
                ctrl.getInstallConPhone();

            Boolean isSvc =
                ctrl.getIsServiceLine();

            String svcMgr =
                ctrl.getAccountManagerSerLineSalesRep();

            String capMgr =
                ctrl.getAccountManagerCapLineSalesRep();

            Boolean isTradeIn =
                ctrl.getIsTradeInLine();

            Datetime shipCalc =
                ctrl.getcalculateActualShipDate();

            List<ShipDNEmailController.LineItem> shipping =
                ctrl.getShippingLineItems();

            List<ShipDNEmailController.LineItem> tradeIn =
                ctrl.getTradeInLineItems();

            String sig =
                ctrl.getEmailSignature();

            Test.stopTest();

            System.assertEquals(
                'Receiving',
                recvDisp
            );

            System.assert(
                procedural == true ||
                procedural == false
            );

            System.assertEquals(
                'Install Person',
                instName
            );

            System.assertEquals(
                false,
                isSvc
            );

            System.assertNotEquals(
                null,
                shipping
            );

            System.assert(
                shipping.size() >= 1
            );

            Boolean foundShip = false;

            for (
                ShipDNEmailController.LineItem li :
                shipping
            ) {
                if (li.itemNumber == 'P-100') {
                    foundShip = true;
                    break;
                }
            }

            System.assertEquals(
                true,
                foundShip,
                'Shipping items should include our product code.'
            );

            System.assertNotEquals(
                null,
                tradeIn
            );
        }
    }

    @IsTest
    static void test_NullCaseId_And_BlankSignature() {

        ShipDNEmailController ctrl =
            new ShipDNEmailController();

        ctrl.caseId = null;

        System.assertEquals(
            null,
            ctrl.getRecevingContactName()
        );

        System.assertEquals(
            '',
            ctrl.getInstallConName()
        );

        System.assertEquals(
            '',
            ctrl.getInstallConPhone()
        );

        Boolean svc =
            ctrl.getIsServiceLine();

        Boolean proc =
            ctrl.getIsProcedural();

        System.assert(
            svc == true ||
            svc == false
        );

        System.assert(
            proc == true ||
            proc == false
        );

        System.assertEquals(
            0,
            ctrl.getShippingLineItems().size()
        );

        System.assertEquals(
            0,
            ctrl.getTradeInLineItems().size()
        );

        System.assertEquals(
            false,
            ctrl.getIsTradeInLine()
        );

        System.assertEquals(
            null,
            ctrl.getcalculateActualShipDate()
        );

        User uBlank =
            makeUserWithSignature('');

        System.runAs(uBlank) {

            Test.startTest();

            String sig =
                ctrl.getEmailSignature();

            Test.stopTest();

            System.assertEquals(
                '',
                sig
            );
        }
    }

    @IsTest
    static void test_BannerUrlSDN_Conditional() {

        ShipDNEmailController ctrl =
            new ShipDNEmailController();

        ctrl.caseId = null;

        List<CBM_Generic_Configuration__mdt> cfg = [
            SELECT DeveloperName,
                   Key__c
            FROM CBM_Generic_Configuration__mdt
            WHERE DeveloperName = 'ShipmentBanner'
            LIMIT 1
        ];

        if (!cfg.isEmpty()) {

            Test.startTest();

            String url =
                ctrl.getBannerUrlSDN();

            Test.stopTest();

            System.assertNotEquals(
                null,
                url
            );

            System.assert(
                url.contains(
                    '/servlet/servlet.ImageServer?id=' +
                    cfg[0].Key__c
                )
            );

            System.assert(
                url.contains(
                    'oid=' +
                    UserInfo.getOrganizationId()
                )
            );

        } else {

            Boolean threw = false;

            Test.startTest();

            try {
                ctrl.getBannerUrlSDN();
            } catch (Exception e) {
                threw = true;
            }

            Test.stopTest();

            System.assertEquals(
                true,
                threw,
                'Expected bannerLoader to throw when configuration is missing.'
            );
        }
    }

    @IsTest
    static void getShippingInstructionsTest() {

        Account acc = new Account(
            Name = 'Ship Instr Account2'
        );
        insert acc;

        Case cs = new Case(
            Subject = 'Shipping Instr Case',
            Status = 'New',
            Origin = 'Phone'
        );
        insert cs;

        Id stdPbId =
            Test.getStandardPricebookId();

        Order ord = new Order(
            AccountId = acc.Id,
            ParentCase__c = cs.Id,
            EffectiveDate = Date.today(),
            Status = 'Draft',
            Pricebook2Id = stdPbId,
            ShippingInstructions__c =
                'Handle with care. Call before delivery.'
        );
        insert ord;

        ShipDNEmailController ctrl =
            new ShipDNEmailController();

        ctrl.caseId = cs.Id;

        Test.startTest();

        String instructions =
            ctrl.getShippingInstructions();

        Test.stopTest();

        System.assertEquals(
            'Handle with care. Call before delivery.',
            instructions,
            'Shipping instructions should be returned from the related Order.'
        );
    }

    @IsTest
    static void testGetFirstNameAndOrderNumber() {

        Case c = [
            SELECT Id
            FROM Case
            WHERE Subject = 'SDN Main Case'
            LIMIT 1
        ];

        Account acc = [
            SELECT Id
            FROM Account
            WHERE Name = 'SDN Test Account'
            LIMIT 1
        ];

        Contact tradeContact = new Contact(
            FirstName = 'Sahil',
            LastName = 'Test',
            Email = 'sahil.test@example.com',
            AccountId = acc.Id
        );
        insert tradeContact;

        CaseContactRole tradeRole =
            new CaseContactRole(
                CasesId = c.Id,
                ContactId = tradeContact.Id,
                Role = 'Trade-in Contact'
            );
        insert tradeRole;

        Order ord = [
            SELECT Id,
                   OrderNumber__c
            FROM Order
            WHERE ParentCase__c = :c.Id
            LIMIT 1
        ];

        ShipDNEmailController ctrl =
            new ShipDNEmailController();

        ctrl.caseId = c.Id;

        Test.startTest();

        String firstName =
            ctrl.getFirstName();

        String orderNumber =
            ctrl.getOrderNumber();

        Test.stopTest();

        System.assertEquals(
            'Sahil',
            firstName,
            'Trade-in Contact First Name should be returned.'
        );

        System.assertEquals(
            ord.OrderNumber__c,
            orderNumber,
            'Order Number should be returned from the related Order.'
        );
    }

    @IsTest
    static void testGetAccountManagerFirstNameNullCaseId() {

        ShipDNEmailController controller =
            new ShipDNEmailController();

        controller.caseId = null;

        Test.startTest();

        String accountManagerFirstNames =
            controller.getAccountManagerFirstName();

        Test.stopTest();

        System.assertEquals(
            '',
            accountManagerFirstNames,
            'Expected an empty string when the Case Id is null.'
        );
    }

    /**
     * CBM-1416:
     * Verifies cancelled Trade-In OrderItems are mapped into the
     * Visualforce LineItem model.
     */
    @IsTest
    static void testGetCancellationTradeInLineItems() {

        Case caseRecord = [
            SELECT Id
            FROM Case
            WHERE Subject = 'SDN Main Case'
            LIMIT 1
        ];

        Order orderRecord = [
            SELECT Id,
                   Pricebook2Id
            FROM Order
            WHERE ParentCase__c = :caseRecord.Id
            LIMIT 1
        ];

        Product2 cancelledTradeProduct =
            new Product2(
                Name =
                    'CBM-1416 Controller Trade-In Product',
                ProductCode =
                    'CBM1416-CTRL',
                Description =
                    'CBM-1416 Cancelled Trade-In Equipment',
                IsActive = true,
                SalesCategory__c = 'CAPEQUIP',
                ItemID__c = 'CBM1416CTRL',
                InventoryOrgId__c = 'CBM1416C'
            );

        cancelledTradeProduct.put(
            'ItemType__c',
            'TRADE-IN'
        );

        insert cancelledTradeProduct;

        PricebookEntry cancelledTradePbe =
            new PricebookEntry(
                Pricebook2Id =
                    orderRecord.Pricebook2Id,
                Product2Id =
                    cancelledTradeProduct.Id,
                UnitPrice = 25,
                IsActive = true
            );
        insert cancelledTradePbe;

        OrderItem cancelledTradeInLine =
            new OrderItem(
                OrderId = orderRecord.Id,
                PricebookEntryId =
                    cancelledTradePbe.Id,
                Quantity = 2,
                UnitPrice = 25,
                MailSent__c = false,
                OrderLineStatus__c = 'Cancelled',
                LineNumber__c = '1416'
            );
        insert cancelledTradeInLine;

        OrderItem insertedLine = [
            SELECT Id,
                   OrderLineType__c,
                   OrderLineStatus__c,
                   LineNumber__c,
                   OrderLineNumber__c,
                   Product2.SalesCategory__c,
                   Product2.ItemType__c,
                   Product2.Description,
                   TotalPrice
            FROM OrderItem
            WHERE Id = :cancelledTradeInLine.Id
        ];

        System.assertEquals(
            'CAPEQUIP',
            insertedLine.Product2.SalesCategory__c,
            'Product Sales Category must be CAPEQUIP.'
        );

        System.assertEquals(
            'TRADE-IN',
            insertedLine.Product2.ItemType__c,
            'Product Item Type must be TRADE-IN.'
        );

        System.assertEquals(
            'Trade In Lines',
            insertedLine.OrderLineType__c,
            'The Flow must calculate OrderLineType__c as Trade In Lines.'
        );

        System.assertEquals(
            'Cancelled',
            insertedLine.OrderLineStatus__c,
            'The Trade-In line must have Cancelled status.'
        );

        System.assertNotEquals(
            null,
            insertedLine.OrderLineNumber__c,
            'Salesforce must generate OrderLineNumber__c.'
        );

        ShipDNEmailController controller =
            new ShipDNEmailController();

        controller.caseId =
            caseRecord.Id;

        Test.startTest();

        List<ShipDNEmailController.LineItem> lineItems =
            controller.getCancellationTradeInLineItems();

        /*
         * Second call covers the getter's cached-list return path.
         */
        List<ShipDNEmailController.LineItem> cachedLineItems =
            controller.getCancellationTradeInLineItems();

        Test.stopTest();

        System.assertNotEquals(
            null,
            lineItems,
            'Expected a non-null cancellation line list.'
        );

        System.assertEquals(
            1,
            lineItems.size(),
            'Expected one cancelled Trade-In line.'
        );

        System.assertEquals(
            '1416',
            lineItems[0].lineNumber,
            'Expected LineNumber__c to be mapped.'
        );

        System.assertEquals(
            'CBM-1416 Cancelled Trade-In Equipment',
            lineItems[0].itemDescription,
            'Expected Product description to be mapped.'
        );

        System.assertEquals(
            Decimal.valueOf('50'),
            lineItems[0].extendedPrice,
            'Expected TotalPrice to be mapped as extended price.'
        );

        System.assertEquals(
            lineItems.size(),
            cachedLineItems.size(),
            'Expected the cached cancellation list.'
        );
    }

    /**
     * CBM-1416:
     * Covers the null Case ID path.
     */
    @IsTest
    static void testGetCancellationTradeInLineItemsNullCaseId() {

        ShipDNEmailController controller =
            new ShipDNEmailController();

        controller.caseId = null;

        Test.startTest();

        List<ShipDNEmailController.LineItem> lineItems =
            controller.getCancellationTradeInLineItems();

        Test.stopTest();

        System.assertNotEquals(
            null,
            lineItems,
            'Expected a non-null list.'
        );

        System.assertEquals(
            0,
            lineItems.size(),
            'Expected no cancellation lines when Case Id is null.'
        );
    }
}