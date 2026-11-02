/**
 * @description Tests for EsServiceProductConfigController (ES Service Product Configurator,
 *              Asset & PM Visits modal).
 */
@IsTest
private class EsServiceProductConfigControllerTest {

    private static final String ASSET_NAME = 'ESPC Test Asset';
    private static final String SERIAL_NUMBER = 'SN-ESPC-0001';
    private static final String PFCL_NAME = 'ESPC Test PFCL';
    private static final Decimal REQUESTED_VISITS = 3;

    /**
     * @description Returns the first active picklist value so tests stay org-configuration safe.
     * @param fieldDescribe Picklist field describe
     * @return First active value, or null
     */
    private static String getFirstActiveValue(Schema.DescribeFieldResult fieldDescribe) {
        for (Schema.PicklistEntry picklistEntry : fieldDescribe.getPicklistValues()) {
            if (picklistEntry.isActive()) {
                return picklistEntry.getValue();
            }
        }
        return null;
    }

    @TestSetup
    static void setupTestData() {
        AutomationControl.setAllDisabled(true);

        adb_Account accountBuilder = new adb_Account().name('ESPC Test Account');
        accountBuilder.persist();

        Contact primaryContact = new Contact(FirstName = 'ESPC', LastName = 'Contact', AccountId = accountBuilder.id);
        insert primaryContact;

        Id pricebookId = Test.getStandardPricebookId();
        Opportunity opportunityRecord = new Opportunity(
            Name = 'ESPC Test Opportunity',
            AccountId = accountBuilder.id,
            StageName = getFirstActiveValue(Opportunity.StageName.getDescribe()),
            ForecastConfidenceLevel__c = getFirstActiveValue(Opportunity.ForecastConfidenceLevel__c.getDescribe()),
            Type = getFirstActiveValue(Opportunity.Type.getDescribe()),
            PrimaryContact__c = primaryContact.Id,
            CloseDate = Date.today().addDays(30),
            Amount = 1000,
            Probability = 10,
            Pricebook2Id = pricebookId
        );
        insert opportunityRecord;

        adb_PFCL pfclBuilder = new adb_PFCL().name(PFCL_NAME).pfcl('ESPC-PFCL');
        pfclBuilder.persist();

        Product2 productRecord = new Product2(Name = 'ESPC Test Product', IsActive = true, PFCL__c = pfclBuilder.id);
        insert productRecord;
        PricebookEntry pricebookEntryRecord = new PricebookEntry(
            Pricebook2Id = pricebookId,
            Product2Id = productRecord.Id,
            UnitPrice = 100,
            IsActive = true
        );
        insert pricebookEntryRecord;

        Asset assetRecord = new Asset(
            Name = ASSET_NAME,
            SerialNumber = SERIAL_NUMBER,
            AccountId = accountBuilder.id,
            Product2Id = productRecord.Id,
            Status = 'Purchased',
            Quantity = 1
        );
        insert assetRecord;

        Quote quoteRecord = new Quote(
            Name = 'ESPC Test Quote',
            OpportunityId = opportunityRecord.Id,
            Pricebook2Id = pricebookId
        );
        insert quoteRecord;

        insert new QuoteLineItem(
            QuoteId = quoteRecord.Id,
            PricebookEntryId = pricebookEntryRecord.Id,
            Quantity = 1,
            UnitPrice = 100,
            Asset__c = assetRecord.Id,
            PFCL__c = pfclBuilder.id,
            RequestedNumberofPMVisits__c = REQUESTED_VISITS
        );

        AutomationControl.setAllDisabled(false);
    }

    /**
     * @description A saved line returns the quote's account and the line's asset, PFCL and visits.
     */
    @IsTest
    static void testGetLineContextSavedLine() {
        User contextUser = new User(Id = UserInfo.getUserId());
        QuoteLineItem line = [SELECT Id, QuoteId, Quote.AccountId, Asset__c, PFCL__c FROM QuoteLineItem LIMIT 1];

        Assert.isNotNull(line.Quote.AccountId, 'The quote should have an account');

        EsServiceProductConfigController.LineContext ctx;
        Test.startTest();
        System.runAs(contextUser) {
            ctx = EsServiceProductConfigController.getLineContext(line.QuoteId, line.Id);
        }
        Test.stopTest();

        Assert.areEqual(line.Quote.AccountId, ctx.accountId, 'Account should come from the quote');
        Assert.isNotNull(ctx.line, 'Saved line values should be returned');
        Assert.areEqual(line.Asset__c, ctx.line.assetId, 'Asset Id should match the line');
        Assert.areEqual(ASSET_NAME, ctx.line.assetName, 'Asset name should match the line');
        Assert.areEqual(line.PFCL__c, ctx.line.pfclId, 'PFCL Id should match the line');
        Assert.areEqual(PFCL_NAME, ctx.line.pfclName, 'PFCL name should match the line');
        Assert.areEqual(REQUESTED_VISITS, ctx.line.requestedVisits, 'Requested visits should match the line');
    }

    /**
     * @description Unsaved ("ref_") and malformed line Ids return the account but no line values.
     */
    @IsTest
    static void testGetLineContextUnsavedAndInvalidLine() {
        User contextUser = new User(Id = UserInfo.getUserId());
        Quote quoteRecord = [SELECT Id, AccountId FROM Quote LIMIT 1];

        Assert.isNotNull(quoteRecord.AccountId, 'The quote should have an account');

        EsServiceProductConfigController.LineContext unsavedCtx;
        EsServiceProductConfigController.LineContext invalidCtx;
        Test.startTest();
        System.runAs(contextUser) {
            unsavedCtx = EsServiceProductConfigController.getLineContext(quoteRecord.Id, 'ref_12345');
            invalidCtx = EsServiceProductConfigController.getLineContext(quoteRecord.Id, '0QLnotAValidId');
        }
        Test.stopTest();

        Assert.areEqual(quoteRecord.AccountId, unsavedCtx.accountId, 'Account should be returned for an unsaved line');
        Assert.isNull(unsavedCtx.line, 'An unsaved line has no stored values');
        Assert.areEqual(quoteRecord.AccountId, invalidCtx.accountId, 'Account should be returned for an invalid Id');
        Assert.isNull(invalidCtx.line, 'A malformed line Id has no stored values');
    }

    /**
     * @description Search matches the asset's serial number on the given account.
     */
    @IsTest
    static void testSearchAssetsBySerialNumber() {
        User contextUser = new User(Id = UserInfo.getUserId());
        Asset assetRecord = [SELECT Id, AccountId FROM Asset WHERE SerialNumber = :SERIAL_NUMBER];

        Assert.isNotNull(assetRecord.AccountId, 'The asset should be on an account');

        List<EsServiceProductConfigController.AssetOption> results;
        Test.startTest();
        System.runAs(contextUser) {
            results = EsServiceProductConfigController.searchAssets(assetRecord.AccountId, 'espc-0001');
        }
        Test.stopTest();

        Assert.areEqual(1, results.size(), 'One asset should match the serial number');
        Assert.areEqual(assetRecord.Id, results[0].id, 'The matching asset should be returned');
        Assert.areEqual(SERIAL_NUMBER, results[0].serialNumber, 'Serial number should be returned');
        Assert.areEqual(ASSET_NAME, results[0].name, 'Asset name should be returned');
    }

    /**
     * @description Search returns nothing without an account or with fewer than two characters.
     */
    @IsTest
    static void testSearchAssetsInvalidInput() {
        User contextUser = new User(Id = UserInfo.getUserId());
        Asset assetRecord = [SELECT Id, AccountId FROM Asset WHERE SerialNumber = :SERIAL_NUMBER];

        Assert.isNotNull(assetRecord.AccountId, 'The asset should be on an account');

        List<EsServiceProductConfigController.AssetOption> noAccount;
        List<EsServiceProductConfigController.AssetOption> shortText;
        Test.startTest();
        System.runAs(contextUser) {
            noAccount = EsServiceProductConfigController.searchAssets(null, SERIAL_NUMBER);
            shortText = EsServiceProductConfigController.searchAssets(assetRecord.AccountId, ' S ');
        }
        Test.stopTest();

        Assert.isTrue(noAccount.isEmpty(), 'No results without an account');
        Assert.isTrue(shortText.isEmpty(), 'No results for fewer than two characters');
    }

    /**
     * @description Asset details include the PFCL record from the asset's product.
     */
    @IsTest
    static void testGetAssetDetailsReturnsPfcl() {
        User contextUser = new User(Id = UserInfo.getUserId());
        Asset assetRecord = [SELECT Id, Product2.PFCL__c FROM Asset WHERE SerialNumber = :SERIAL_NUMBER];

        Assert.isNotNull(assetRecord.Product2.PFCL__c, 'The asset product should have a PFCL');

        EsServiceProductConfigController.LineValues details;
        Test.startTest();
        System.runAs(contextUser) {
            details = EsServiceProductConfigController.getAssetDetails(assetRecord.Id);
        }
        Test.stopTest();

        Assert.areEqual(assetRecord.Id, details.assetId, 'Asset Id should be returned');
        Assert.areEqual(ASSET_NAME, details.assetName, 'Asset name should be returned');
        Assert.areEqual(assetRecord.Product2.PFCL__c, details.pfclId, 'PFCL Id should come from the product');
        Assert.areEqual(PFCL_NAME, details.pfclName, 'PFCL name should come from the product');
    }

    /**
     * @description Unknown titles return an empty map (the LWC falls back to its configured Ids).
     */
    @IsTest
    static void testGetAttributeIdsReturnsEmptyMap() {
        User contextUser = new User(Id = UserInfo.getUserId());
        List<String> fieldNames = new List<String>{ 'ESPC_Not_A_Context_Attribute__c' };

        Assert.areEqual(1, fieldNames.size(), 'One title to look up');

        Map<String, String> noMatch;
        Test.startTest();
        System.runAs(contextUser) {
            noMatch = EsServiceProductConfigController.getAttributeIds(fieldNames);
        }
        Test.stopTest();

        Assert.isTrue(noMatch.isEmpty(), 'No attribute Ids for unknown titles');
    }

    /**
     * @description A failure is logged and surfaced to the LWC as an AuraHandledException with a readable message.
     */
    @IsTest
    static void testToAuraException() {
        Asset assetRecord = [SELECT Id FROM Asset WHERE SerialNumber = :SERIAL_NUMBER];
        DmlException cause = new DmlException('Simulated failure');

        Assert.areEqual(0, Logger.getBufferSize(), 'Nothing logged yet');

        Test.startTest();
        AuraHandledException result = EsServiceProductConfigController.toAuraException(
            'getAssetDetails: unable to load asset', assetRecord.Id, cause, 'Unable to load the asset details.'
        );
        Test.stopTest();

        Assert.areEqual('Unable to load the asset details.', result.getMessage(), 'Message shown in the LWC');
        Assert.areEqual(1, Logger.getBufferSize(), 'The failure should be logged');
    }
}