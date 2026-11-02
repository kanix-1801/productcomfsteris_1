/**
 * @author Akash Dahinde PWC
 * GC-3194
 * @date 07-23-2026
 * @description Test class for OpportunityOliBannerController.
 * Warning: Deleted_Opportunity_Product__c is not blank AND IsOliBannerToBeShown__c is false.
 * Success: IsOliBannerToBeShown__c is true.
 * Product names are parsed from brace-delimited groups: {Product A} {Product B}.
 */
@IsTest
private class OpportunityOliBannerControllerTest {
    @TestSetup
    static void setupData() {
        insert new Automation_Setting_Validation_Rule__c(
            SetupOwnerId = UserInfo.getOrganizationId(),
            disableAll__c = true
        );

        Id prospectRtId = queryRecordTypeId('Account', 'Prospect');
        System.assertNotEquals(
            null,
            prospectRtId,
            'Prospect Account Record Type must exist.'
        );

        String suffix =
            String.valueOf(Math.abs(Crypto.getRandomInteger()));

        Account prospectAcc = new Account(
            Name = 'Test Prospect Account ' + suffix,
            RecordTypeId = prospectRtId,
            CustomerClassCode__c = 'HC',
            OrgIDs__c = '82',
            BillingStreet = '123 Main St',
            BillingCity = 'Cleveland',
            BillingStateCode = 'OH',
            BillingCountryCode = 'US',
            BillingPostalCode = '44101',
            TAS_Retry__c = false
        );
        Database.insert(prospectAcc, AccessLevel.SYSTEM_MODE);

        Contact primaryContact = new Contact(
            FirstName = 'OLI',
            LastName = 'Banner',
            AccountId = prospectAcc.Id,
            Email = 'oli.banner.' + suffix + '@example.com'
        );
        Database.insert(primaryContact, AccessLevel.SYSTEM_MODE);

        Opportunity opp = new Opportunity(
            Name = 'Test Opportunity',
            AccountId = prospectAcc.Id,
            RecordTypeId = queryRecordTypeId('Opportunity', 'Healthcare_Sales'),
            StageName = 'Discovery',
            Type = 'New Business',
            Amount = 1000,
            Probability = 10,
            CloseDate = Date.today().addDays(30),
            PrimaryContact__c = primaryContact.Id,
            BypassValidations__c = true,
            Pricebook2Id = Test.getStandardPricebookId()
        );
        Database.insert(opp, AccessLevel.SYSTEM_MODE);
    }

    private static Id queryRecordTypeId(String sobjectType, String developerName) {
        List<RecordType> recordTypes = [
            SELECT Id
            FROM RecordType
            WHERE SobjectType = :sobjectType
              AND DeveloperName = :developerName
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        return recordTypes.isEmpty() ? null : recordTypes[0].Id;
    }

    private static Opportunity getTestOpportunity() {
        return [
            SELECT Id,
                   AccountId,
                   IsOliBannerToBeShown__c,
                   Deleted_Opportunity_Product__c
            FROM Opportunity
            WHERE Name = 'Test Opportunity'
            LIMIT 1
        ];
    }

    @IsTest
    static void testGetBannerContext_NoBannerWhenFieldsAreDefault() {
        Opportunity opp = getTestOpportunity();

        Test.startTest();
        OpportunityOliBannerController.BannerContext context =
            OpportunityOliBannerController.getBannerContext(opp.Id);
        Test.stopTest();

        System.assertNotEquals(null, context);
        System.assertEquals(false, context.showBanner);
        System.assertEquals(null, context.bannerType);
        System.assertEquals(null, context.message);
        System.assertEquals(0, context.productNames.size());
    }

    @IsTest
    static void testGetBannerContext_WarningBanner() {
        Opportunity opp = getTestOpportunity();

        opp.Deleted_Opportunity_Product__c =
            '{00000011FTBOM A SERIES TDM-11GV} {00000011GTBOM A-SERIES-11GV-KADJ TD}';
        opp.IsOliBannerToBeShown__c = false;
        update opp;

        Test.startTest();
        OpportunityOliBannerController.BannerContext context =
            OpportunityOliBannerController.getBannerContext(opp.Id);
        Test.stopTest();

        System.assertEquals(true, context.showBanner);
        System.assertEquals(
            OpportunityOliBannerController.BANNER_TYPE_WARNING,
            context.bannerType
        );
        System.assertEquals(
            System.Label.OLI_Banner_Warning_Message,
            context.message
        );
        System.assertEquals(2, context.productNames.size());
        System.assertEquals(
            '00000011FTBOM A SERIES TDM-11GV',
            context.productNames[0]
        );
        System.assertEquals(
            '00000011GTBOM A-SERIES-11GV-KADJ TD',
            context.productNames[1]
        );
    }

    @IsTest
    static void testGetBannerContext_SuccessBanner() {
        Opportunity opp = getTestOpportunity();

        opp.IsOliBannerToBeShown__c = true;
        update opp;

        Test.startTest();
        OpportunityOliBannerController.BannerContext context =
            OpportunityOliBannerController.getBannerContext(opp.Id);
        Test.stopTest();

        System.assertEquals(true, context.showBanner);
        System.assertEquals(
            OpportunityOliBannerController.BANNER_TYPE_SUCCESS,
            context.bannerType
        );
        System.assertEquals(
            System.Label.OLI_Banner_Success_Message,
            context.message
        );
        System.assertEquals(0, context.productNames.size());
    }

    @IsTest
    static void testSuccessBannerTakesPriorityOverDeletedProducts() {
        Opportunity opp = getTestOpportunity();

        opp.IsOliBannerToBeShown__c = true;
        opp.Deleted_Opportunity_Product__c = '{Test Pro 01} {Test Pro 02}';
        update opp;

        Test.startTest();
        OpportunityOliBannerController.BannerContext context =
            OpportunityOliBannerController.getBannerContext(opp.Id);
        Test.stopTest();

        System.assertEquals(true, context.showBanner);
        System.assertEquals(
            OpportunityOliBannerController.BANNER_TYPE_SUCCESS,
            context.bannerType
        );
        System.assertEquals(
            System.Label.OLI_Banner_Success_Message,
            context.message
        );

        // Success scenario returns before deleted products are parsed.
        System.assertEquals(0, context.productNames.size());
    }

    @IsTest
    static void testParseProductNames_TrimsAndIgnoresBlankValues() {
        Test.startTest();
        List<String> productNames =
            OpportunityOliBannerController.parseProductNames(
                '{ Product A } { Product B } { } { Product C }'
            );
        Test.stopTest();

        System.assertEquals(3, productNames.size());
        System.assertEquals('Product A', productNames[0]);
        System.assertEquals('Product B', productNames[1]);
        System.assertEquals('Product C', productNames[2]);
    }

    @IsTest
    static void testParseProductNames_BlankValue() {
        Test.startTest();

        List<String> nullResult =
            OpportunityOliBannerController.parseProductNames(null);

        List<String> blankResult =
            OpportunityOliBannerController.parseProductNames('');

        Test.stopTest();

        System.assertEquals(0, nullResult.size());
        System.assertEquals(0, blankResult.size());
    }

    @IsTest
    static void testBuildWarningMessage() {
        Test.startTest();

        String message =
            OpportunityOliBannerController.buildWarningMessage();

        Test.stopTest();

        System.assertEquals(
            System.Label.OLI_Banner_Warning_Message,
            message
        );
    }

    @IsTest
    static void testBuildSuccessMessage() {
        Test.startTest();

        String message =
            OpportunityOliBannerController.buildSuccessMessage();

        Test.stopTest();

        System.assertEquals(
            System.Label.OLI_Banner_Success_Message,
            message
        );
    }

    @IsTest
    static void testDismissBanner_ClearsFields() {
        Opportunity opp = getTestOpportunity();

        opp.IsOliBannerToBeShown__c = true;
        opp.Deleted_Opportunity_Product__c =
            '{Test Pro 01} {Test Pro 02}';
        update opp;

        Test.startTest();

        OpportunityOliBannerController.dismissBanner(opp.Id);

        Test.stopTest();

        Opportunity updatedOpp = [
            SELECT IsOliBannerToBeShown__c,
                   Deleted_Opportunity_Product__c
            FROM Opportunity
            WHERE Id = :opp.Id
        ];

        System.assertEquals(
            false,
            updatedOpp.IsOliBannerToBeShown__c
        );

        /*
         * Salesforce normally stores '' as null for text fields,
         * therefore String.isBlank() is safer than assertEquals('').
         */
        System.assertEquals(
            true,
            String.isBlank(
                updatedOpp.Deleted_Opportunity_Product__c
            )
        );
    }

    @IsTest
    static void testDismissBanner_ThenContextDoesNotShowBanner() {
        Opportunity opp = getTestOpportunity();

        opp.IsOliBannerToBeShown__c = false;
        opp.Deleted_Opportunity_Product__c = '{Test Pro 01}';
        update opp;

        OpportunityOliBannerController.BannerContext beforeDismiss =
            OpportunityOliBannerController.getBannerContext(opp.Id);

        System.assertEquals(true, beforeDismiss.showBanner);
        System.assertEquals(
            OpportunityOliBannerController.BANNER_TYPE_WARNING,
            beforeDismiss.bannerType
        );

        Test.startTest();

        OpportunityOliBannerController.dismissBanner(opp.Id);

        OpportunityOliBannerController.BannerContext afterDismiss =
            OpportunityOliBannerController.getBannerContext(opp.Id);

        Test.stopTest();

        System.assertEquals(false, afterDismiss.showBanner);
        System.assertEquals(null, afterDismiss.bannerType);
        System.assertEquals(null, afterDismiss.message);
        System.assertEquals(0, afterDismiss.productNames.size());
    }

    @IsTest
    static void testGetBannerContext_NullOpportunityId() {
        Test.startTest();

        OpportunityOliBannerController.BannerContext context =
            OpportunityOliBannerController.getBannerContext(null);

        Test.stopTest();

        System.assertNotEquals(null, context);
        System.assertEquals(false, context.showBanner);
        System.assertEquals(0, context.productNames.size());
    }

    @IsTest
    static void testDismissBanner_NullOpportunityId() {
        Test.startTest();

        OpportunityOliBannerController.dismissBanner(null);

        Test.stopTest();

        System.assert(true);
    }

    @IsTest
    static void testGetBannerContext_InvalidOpportunityId() {
        Account accountRecord = [
            SELECT Id
            FROM Account
            LIMIT 1
        ];

        Boolean exceptionThrown = false;

        Test.startTest();

        try {
            OpportunityOliBannerController.getBannerContext(
                accountRecord.Id
            );
        } catch (AuraHandledException e) {
            exceptionThrown = true;
        }

        Test.stopTest();

        System.assertEquals(
            true,
            exceptionThrown,
            'Invalid Opportunity Id should be handled.'
        );
    }

    @IsTest
    static void testDismissBanner_InvalidOpportunityId() {
        Account accountRecord = [
            SELECT Id
            FROM Account
            LIMIT 1
        ];

        Boolean exceptionThrown = false;

        Test.startTest();

        try {
            OpportunityOliBannerController.dismissBanner(
                accountRecord.Id
            );
        } catch (AuraHandledException e) {
            exceptionThrown = true;
        }

        Test.stopTest();

        System.assertEquals(
            true,
            exceptionThrown,
            'Invalid Opportunity Id should be handled.'
        );
    }
}