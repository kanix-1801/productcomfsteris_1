/**
 * @description Tests for EsServiceAssetSelectionController (ES Service Product Configurator,
 *              "Assets Selected" launcher, "Choose Assets" picker and PM Visits card).
 */
@IsTest
private class EsServiceAssetSelectionControllerTest {

    private static final String CHILD_ASSET_NAME = 'ESPC Child Account Asset';
    private static final String CHILD_SERIAL = 'SN-ESPC-CHILD';
    private static final String PARENT_SERIAL = 'SN-ESPC-PARENT';
    private static final String PFCL_NAME = 'ESPC Test PFCL';
    private static final String ASSET_VISITS_JSON = '{"02i000000000001AAA":2}';
    private static final Decimal REQUESTED_VISITS = 4;
    private static final String UNSAVED_LINE_ID = 'ref_12345';
    private static final String INVALID_LINE_ID = '0QLnotAValidId';

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
        EsServiceTestDataFactory.grantAccess();
        // The test permission set applies inside runAs, so the data is created as the test user.
        System.runAs(new User(Id = UserInfo.getUserId())) {
            AutomationControl.setAllDisabled(true);

            adb_Account parentBuilder = new adb_Account().name('ESPC Parent Account');
            parentBuilder.persist();
            adb_Account childBuilder = new adb_Account().name('ESPC Child Account');
            childBuilder.persist();

            insert new AccountAccountRelationship__c(
                ChildAccount__c = childBuilder.id,
                ParentAccount__c = parentBuilder.id,
                RelationshipType__c = getFirstActiveValue(
                    AccountAccountRelationship__c.RelationshipType__c.getDescribe()
                )
            );

            Contact primaryContact = new Contact(FirstName = 'ESPC', LastName = 'Contact', AccountId = childBuilder.id);
            insert primaryContact;

            Id pricebookId = Test.getStandardPricebookId();
            Opportunity opportunityRecord = new Opportunity(
                Name = 'ESPC Test Opportunity',
                AccountId = childBuilder.id,
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

            Product2 productRecord = new Product2(
                Name = 'ESPC Test Product', IsActive = true, PFCL__c = pfclBuilder.id
            );
            insert productRecord;
            PricebookEntry pricebookEntryRecord = new PricebookEntry(
                Pricebook2Id = pricebookId,
                Product2Id = productRecord.Id,
                UnitPrice = 100,
                IsActive = true
            );
            insert pricebookEntryRecord;

            Asset childAsset = new Asset(
                Name = CHILD_ASSET_NAME,
                SerialNumber = CHILD_SERIAL,
                AccountId = childBuilder.id,
                Product2Id = productRecord.Id,
                Street = '5960 Heisley Rd',
                City = 'Mentor',
                PostalCode = '44060',
                InstallDate = Date.today().addYears(-1),
                Status = 'Purchased',
                Quantity = 1
            );
            Asset parentAsset = new Asset(
                Name = 'ESPC Parent Account Asset',
                SerialNumber = PARENT_SERIAL,
                AccountId = parentBuilder.id,
                Product2Id = productRecord.Id,
                Status = 'Purchased',
                Quantity = 1
            );
            insert new List<Asset>{ childAsset, parentAsset };

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
                Asset__c = childAsset.Id,
                PFCL__c = pfclBuilder.id,
                RequestedNumberofPMVisits__c = REQUESTED_VISITS,
                SelectedAssets__c = JSON.serialize(new List<Id>{ childAsset.Id, parentAsset.Id }),
                AssetVisits__c = ASSET_VISITS_JSON
            );

            AutomationControl.setAllDisabled(false);
        }
    }

    // Read as the test user (inside runAs) so the test permission set applies.
    private static QuoteLineItem getLine() {
        QuoteLineItem line;
        System.runAs(new User(Id = UserInfo.getUserId())) {
            line = [
                SELECT Id, QuoteId, Quote.AccountId, Product2Id, SelectedAssets__c
                FROM QuoteLineItem
                WITH USER_MODE
                LIMIT 1
            ];
        }
        return line;
    }

    /**
     * @description Assets on the quote's account and its parent account are returned, quote account first
     *              in the data and with a formatted address.
     */
    @IsTest
    static void testGetAssetsIncludesParentAccountAssets() {
        User contextUser = new User(Id = UserInfo.getUserId());
        QuoteLineItem line = getLine();

        Assert.areEqual(2, [SELECT COUNT() FROM Asset WITH USER_MODE], 'Two assets should exist');

        EsServiceAssetSelectionController.AssetList result;
        Test.startTest();
        System.runAs(contextUser) {
            result = EsServiceAssetSelectionController.getAssets(line.QuoteId);
        }
        Test.stopTest();

        Assert.areEqual(line.Quote.AccountId, result.quoteAccountId, 'Quote account should be returned');
        Assert.areEqual(1, result.relatedAccountCount, 'One related (parent) account should be counted');
        Assert.areEqual(2, result.rows.size(), 'Assets from both accounts should be returned');
        Assert.isFalse(result.truncated, 'The list should not be truncated');
        Map<String, EsServiceAssetSelectionController.AssetRow> rowsBySerial =
            new Map<String, EsServiceAssetSelectionController.AssetRow>();
        for (EsServiceAssetSelectionController.AssetRow row : result.rows) {
            rowsBySerial.put(row.serialNumber, row);
        }
        EsServiceAssetSelectionController.AssetRow childRow = rowsBySerial.get(CHILD_SERIAL);
        Assert.isNotNull(childRow, 'The quote account asset should be returned');
        Assert.isTrue(rowsBySerial.containsKey(PARENT_SERIAL), 'The parent account asset should be returned');
        // The org may default Country (e.g. ", US"), so only the start of the address is fixed.
        Assert.isTrue(childRow.address.startsWith('5960 Heisley Rd, Mentor, 44060'),
                      'Address should be formatted: ' + childRow.address);
        Assert.areEqual(PFCL_NAME, childRow.pfcl, 'PFCL name should come from the asset product');
    }

    /**
     * @description A null quote returns an empty list without querying.
     */
    @IsTest
    static void testGetAssetsNullQuote() {
        User contextUser = new User(Id = UserInfo.getUserId());
        Id noQuoteId = null;

        Assert.isNull(noQuoteId, 'No quote is given');

        EsServiceAssetSelectionController.AssetList result;
        Test.startTest();
        System.runAs(contextUser) {
            result = EsServiceAssetSelectionController.getAssets(noQuoteId);
        }
        Test.stopTest();

        Assert.isTrue(result.rows.isEmpty(), 'No assets for a null quote');
        Assert.isNull(result.quoteAccountId, 'No account for a null quote');
    }

    /**
     * @description Saved selection preview: assets are returned by Id; an empty list returns nothing.
     */
    @IsTest
    static void testGetAssetsByIds() {
        User contextUser = new User(Id = UserInfo.getUserId());
        Asset childAsset = [SELECT Id FROM Asset WHERE SerialNumber = :CHILD_SERIAL WITH USER_MODE];

        Assert.isNotNull(childAsset.Id, 'The asset should exist');

        List<EsServiceAssetSelectionController.AssetRow> rows;
        List<EsServiceAssetSelectionController.AssetRow> emptyRows;
        Test.startTest();
        System.runAs(contextUser) {
            rows = EsServiceAssetSelectionController.getAssetsByIds(new List<Id>{ childAsset.Id });
            emptyRows = EsServiceAssetSelectionController.getAssetsByIds(new List<Id>());
        }
        Test.stopTest();

        Assert.areEqual(1, rows.size(), 'One asset should be returned');
        Assert.areEqual(childAsset.Id, rows[0].id, 'The requested asset should be returned');
        Assert.areEqual(CHILD_ASSET_NAME, rows[0].name, 'Asset name should be returned');
        Assert.isTrue(emptyRows.isEmpty(), 'No assets for an empty Id list');
    }

    /**
     * @description The bundle line's product is returned; unsaved line Ids return null.
     */
    @IsTest
    static void testGetLineProductId() {

        User contextUser = new User(Id = UserInfo.getUserId());
        QuoteLineItem line = getLine();

        Assert.isNotNull(line.Product2Id, 'The line should have a product');

        Id productId;
        Id unsavedProductId;
        Test.startTest();
        System.runAs(contextUser) {
            productId = EsServiceAssetSelectionController.getLineProductId(line.Id);
            unsavedProductId = EsServiceAssetSelectionController.getLineProductId(UNSAVED_LINE_ID);
        }
        Test.stopTest();

        Assert.areEqual(line.Product2Id, productId, 'The line product should be returned');
        Assert.isNull(unsavedProductId, 'No product for an unsaved line');
    }

    /**
     * @description The line's asset is returned with name and PFCL falling back to the related records;
     *              malformed line Ids return null.
     */
    @IsTest
    static void testGetLineAsset() {
        User contextUser = new User(Id = UserInfo.getUserId());
        QuoteLineItem line;
        System.runAs(contextUser) {
            line = [SELECT Id, Asset__c, AssetName__c, PFCLName__c FROM QuoteLineItem WITH USER_MODE LIMIT 1];
        }

        Assert.isTrue(String.isBlank(line.AssetName__c), 'Asset name text should be blank to test the fallback');

        EsServiceAssetSelectionController.LineAsset lineAsset;
        EsServiceAssetSelectionController.LineAsset invalidLineAsset;
        Test.startTest();
        System.runAs(contextUser) {
            lineAsset = EsServiceAssetSelectionController.getLineAsset(line.Id);
            invalidLineAsset = EsServiceAssetSelectionController.getLineAsset(INVALID_LINE_ID);
        }
        Test.stopTest();

        Assert.areEqual(line.Asset__c, lineAsset.assetId, 'Asset Id should match the line');
        Assert.areEqual(CHILD_ASSET_NAME, lineAsset.assetName, 'Asset name should fall back to the asset');
        Assert.areEqual(CHILD_SERIAL, lineAsset.serialNumber, 'Serial number should come from the asset');
        if (String.isBlank(line.PFCLName__c)) {
            Assert.areEqual(PFCL_NAME, lineAsset.pfclName, 'PFCL name should fall back to the PFCL record');
        }
        Assert.areEqual(REQUESTED_VISITS, lineAsset.requestedVisits, 'Requested visits should match the line');
        Assert.isNull(invalidLineAsset, 'No asset for a malformed line Id');
    }

    /**
     * @description Saved per-asset visits and the saved bundle selection are returned as stored;
     *              unsaved and malformed line Ids return null.
     */
    @IsTest
    static void testGetSavedVisitsAndSelection() {
        User contextUser = new User(Id = UserInfo.getUserId());
        QuoteLineItem line = getLine();

        Assert.isNotNull(line.SelectedAssets__c, 'The line should have a saved selection');

        String visits;
        String unsavedVisits;
        String selection;
        String unsavedSelection;
        String invalidSelection;
        Test.startTest();
        System.runAs(contextUser) {
            visits = EsServiceAssetSelectionController.getSavedVisits(line.Id);
            unsavedVisits = EsServiceAssetSelectionController.getSavedVisits(UNSAVED_LINE_ID);
            selection = EsServiceAssetSelectionController.getSavedSelection(line.Id);
            unsavedSelection = EsServiceAssetSelectionController.getSavedSelection(UNSAVED_LINE_ID);
            invalidSelection = EsServiceAssetSelectionController.getSavedSelection(INVALID_LINE_ID);
        }
        Test.stopTest();

        Assert.areEqual(ASSET_VISITS_JSON, visits, 'Saved visits should be returned as stored');
        Assert.isNull(unsavedVisits, 'No visits for an unsaved line');
        Assert.areEqual(line.SelectedAssets__c, selection, 'Saved selection should be returned as stored');
        Assert.isNull(unsavedSelection, 'No selection for an unsaved line');
        Assert.isNull(invalidSelection, 'No selection for a malformed line Id');
    }

    /**
     * @description A failure is logged and surfaced to the LWC as an AuraHandledException with a readable message.
     */
    @IsTest
    static void testToAuraException() {
        QuoteLineItem line = getLine();
        DmlException cause = new DmlException('Simulated failure');

        Assert.areEqual(0, Logger.getBufferSize(), 'Nothing logged yet');

        Test.startTest();
        AuraHandledException result = EsServiceAssetSelectionController.toAuraException(
            'getLineAsset: unable to load the line asset', line.Id, cause, 'Unable to load this line\'s asset.'
        );
        Test.stopTest();

        Assert.areEqual('Unable to load this line\'s asset.', result.getMessage(), 'Message shown in the LWC');
        Assert.areEqual(1, Logger.getBufferSize(), 'The failure should be logged');
    }
}