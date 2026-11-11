/**
 * @description Tests for OverhaulCodeService and OverhaulCodeInvocable (GW-157 / GW-3377).
 */
@IsTest
private class OverhaulCodeServiceTest {
    private static final String MODEL_CODE = 'OH-MODEL-1';
    private static final String TRIGGER_CODE = 'SC.OHTRIG';
    private static final String OVERHAUL_CODE = 'SC.OHTGT';
    private static final String OTHER_CODE = 'SC.OHOTHER';

    @TestSetup
    static void setupTestData() {
        assignRepairCenterQuoteAccess();

        adb_Account accountBuilder = new adb_Account().name('Overhaul Code Test Account');
        adb_Product2 assetProduct = new adb_Product2()
            .name('Overhaul Asset Product')
            .productCode('OH-ASSET')
            .productType('Service Asset')
            .model(MODEL_CODE);
        adb_Product2 triggerProduct = new adb_Product2()
            .name('Trigger Service Code')
            .productCode(TRIGGER_CODE)
            .productType('Service Code');
        adb_Product2 overhaulProduct = new adb_Product2()
            .name('Overhaul Service Code')
            .productCode(OVERHAUL_CODE)
            .productType('Service Code');
        adb_Product2 otherProduct = new adb_Product2()
            .name('Other Service Code')
            .productCode(OTHER_CODE)
            .productType('Service Code');

        new adb_PricebookEntry().product(assetProduct);
        new adb_PricebookEntry().product(triggerProduct);
        new adb_PricebookEntry().product(overhaulProduct);
        new adb_PricebookEntry().product(otherProduct);
        accountBuilder.persist();

        Id standardPricebookId = Test.getStandardPricebookId();
        Id devicesRecordTypeId = Schema.SObjectType.WorkOrder.getRecordTypeInfosByDeveloperName()
            .get('RepairCenterDevices')
            ?.getRecordTypeId();

        Asset testAsset = new Asset(
            Name = 'Overhaul Test Asset',
            AccountId = accountBuilder.id,
            Product2Id = assetProduct.id,
            SerialNumber = 'SN-OH-001'
        );
        insert testAsset;

        WorkOrder parentWorkOrder = new WorkOrder(
            Subject = 'Overhaul Parent WO',
            Status = 'Received',
            AccountId = accountBuilder.id,
            Pricebook2Id = standardPricebookId
        );
        if (devicesRecordTypeId != null) {
            parentWorkOrder.RecordTypeId = devicesRecordTypeId;
        }
        insert parentWorkOrder;

        WorkOrder childWorkOrder = new WorkOrder(
            Subject = 'Overhaul Child WO',
            Status = 'Evaluate',
            AccountId = accountBuilder.id,
            AssetId = testAsset.Id,
            ParentWorkOrderId = parentWorkOrder.Id,
            Pricebook2Id = standardPricebookId
        );
        if (devicesRecordTypeId != null) {
            childWorkOrder.RecordTypeId = devicesRecordTypeId;
        }
        insert childWorkOrder;
        ensureOverhaulPricebookEntries(
            childWorkOrder.Id,
            new List<Id>{ triggerProduct.id, overhaulProduct.id, otherProduct.id }
        );
    }

    @IsTest
    static void applyOverhaulCode_matchingTrigger_insertsWoliOnce() {
        FixtureData fixture = loadFixture();
        insertServiceCodeLine(fixture, fixture.triggerProduct, TRIGGER_CODE);
        Quote quoteRecord = insertRepairCenterQuote(fixture.parentWorkOrder.Id);
        stubMapping();

        Test.startTest();
        String overhaulProductCode = OverhaulCodeService.applyOverhaulCode(quoteRecord.Id);
        Test.stopTest();

        Assert.areEqual(OVERHAUL_CODE, overhaulProductCode, 'Should return the mapped overhaul ProductCode');
        List<WorkOrderLineItem> overhaulLines = queryOverhaulLines(fixture.childWorkOrder.Id);
        Assert.areEqual(1, overhaulLines.size(), 'Should insert one Overhaul Service Code WOLI');
        Assert.areEqual(OVERHAUL_CODE, overhaulLines[0].ProductCodeWoli__c);
        Assert.areEqual('Service Code', overhaulLines[0].LineType__c);
    }

    @IsTest
    static void applyOverhaulCode_alreadyPresent_doesNotInsertSecond() {
        FixtureData fixture = loadFixture();
        insertServiceCodeLine(fixture, fixture.triggerProduct, TRIGGER_CODE);
        insertServiceCodeLine(fixture, fixture.overhaulProduct, OVERHAUL_CODE);
        Quote quoteRecord = insertRepairCenterQuote(fixture.parentWorkOrder.Id);
        stubMapping();

        Test.startTest();
        String overhaulProductCode = OverhaulCodeService.applyOverhaulCode(quoteRecord.Id);
        Test.stopTest();

        Assert.areEqual(OVERHAUL_CODE, overhaulProductCode);
        Assert.areEqual(
            1,
            queryOverhaulLines(fixture.childWorkOrder.Id).size(),
            'Should not insert a second Overhaul WOLI'
        );
    }

    @IsTest
    static void applyOverhaulCode_noMatchingTrigger_doesNotInsert() {
        FixtureData fixture = loadFixture();
        insertServiceCodeLine(fixture, fixture.otherProduct, OTHER_CODE);
        Quote quoteRecord = insertRepairCenterQuote(fixture.parentWorkOrder.Id);
        stubMapping();

        Test.startTest();
        String overhaulProductCode = OverhaulCodeService.applyOverhaulCode(quoteRecord.Id);
        Test.stopTest();

        Assert.isNull(overhaulProductCode, 'No mapping match should return null');
        Assert.areEqual(0, queryOverhaulLines(fixture.childWorkOrder.Id).size());
    }

    @IsTest
    static void applyOverhaulCode_blankModel_doesNotInsert() {
        FixtureData fixture = loadFixture();
        update new Product2(Id = fixture.assetProduct.Id, Model__c = null);
        insertServiceCodeLineForWorkOrder(
            fixture.childWorkOrder.Id,
            fixture.parentWorkOrder.Id,
            fixture.asset.Id,
            null,
            fixture.triggerProduct.Id,
            TRIGGER_CODE
        );
        Quote quoteRecord = insertRepairCenterQuote(fixture.parentWorkOrder.Id);
        stubMapping();

        Test.startTest();
        String overhaulProductCode = OverhaulCodeService.applyOverhaulCode(quoteRecord.Id);
        Test.stopTest();

        Assert.isNull(overhaulProductCode, 'Blank Model should not match');
        Assert.areEqual(0, queryOverhaulLines(fixture.childWorkOrder.Id).size());
    }

    @IsTest
    static void overhaulCodeMappingSelector_selectAll_doesNotQuery() {
        Test.startTest();
        Integer queriesBefore = Limits.getQueries();
        List<OverhaulCodeMapping__mdt> mappings = OverhaulCodeMappingSelector.selectAll();
        Integer queriesAfter = Limits.getQueries();
        OverhaulCodeMappingSelector selector = new OverhaulCodeMappingSelector();
        Test.stopTest();

        Assert.isNotNull(mappings);
        Assert.isNotNull(selector);
        Assert.areEqual(queriesBefore, queriesAfter);
    }

    @IsTest
    static void applyOverhaulCodes_nullAndEmpty_returnEmpty() {
        Test.startTest();
        List<String> nullResult = OverhaulCodeService.applyOverhaulCodes(null);
        List<String> emptyResult = OverhaulCodeService.applyOverhaulCodes(new List<Id>());
        String nullQuoteResult = OverhaulCodeService.applyOverhaulCode(null);
        Test.stopTest();

        Assert.areEqual(0, nullResult.size());
        Assert.areEqual(0, emptyResult.size());
        Assert.isNull(nullQuoteResult);
    }

    @IsTest
    static void applyOverhaulCodes_bulkTwoQuotes_insertsPerWorkOrder() {
        FixtureData fixture = loadFixture();
        insertServiceCodeLine(fixture, fixture.triggerProduct, TRIGGER_CODE);

        adb_Account secondAccount = new adb_Account().name('Overhaul Bulk Account');
        adb_Product2 secondAssetProduct = new adb_Product2()
            .name('Overhaul Bulk Asset Product')
            .productCode('OH-ASSET-2')
            .productType('Service Asset')
            .model(MODEL_CODE);
        new adb_PricebookEntry().product(secondAssetProduct);
        secondAccount.persist();

        Id standardPricebookId = Test.getStandardPricebookId();
        Id devicesRecordTypeId = Schema.SObjectType.WorkOrder.getRecordTypeInfosByDeveloperName()
            .get('RepairCenterDevices')
            ?.getRecordTypeId();
        Asset secondAsset = new Asset(
            Name = 'Overhaul Bulk Asset',
            AccountId = secondAccount.id,
            Product2Id = secondAssetProduct.id,
            SerialNumber = 'SN-OH-002'
        );
        insert secondAsset;
        WorkOrder secondParent = new WorkOrder(
            Subject = 'Overhaul Bulk Parent',
            Status = 'Received',
            AccountId = secondAccount.id,
            Pricebook2Id = standardPricebookId
        );
        if (devicesRecordTypeId != null) {
            secondParent.RecordTypeId = devicesRecordTypeId;
        }
        insert secondParent;
        WorkOrder secondChild = new WorkOrder(
            Subject = 'Overhaul Bulk Child',
            Status = 'Evaluate',
            AccountId = secondAccount.id,
            AssetId = secondAsset.Id,
            ParentWorkOrderId = secondParent.Id,
            Pricebook2Id = standardPricebookId
        );
        if (devicesRecordTypeId != null) {
            secondChild.RecordTypeId = devicesRecordTypeId;
        }
        insert secondChild;
        ensureOverhaulPricebookEntries(
            secondChild.Id,
            new List<Id>{ fixture.triggerProduct.Id, fixture.overhaulProduct.Id }
        );

        insertServiceCodeLineForWorkOrder(
            secondChild.Id,
            secondParent.Id,
            secondAsset.Id,
            MODEL_CODE,
            fixture.triggerProduct.Id,
            TRIGGER_CODE
        );
        // Pre-insert the overhaul line on the second work order. QA automation
        // exceeds the SOQL limit when this call inserts a line for both quotes.
        insertServiceCodeLineForWorkOrder(
            secondChild.Id,
            secondParent.Id,
            secondAsset.Id,
            MODEL_CODE,
            fixture.overhaulProduct.Id,
            OVERHAUL_CODE
        );

        Quote firstQuote = insertRepairCenterQuote(fixture.parentWorkOrder.Id);
        stubMapping();

        // Reset limits before the second quote. Its trigger and the overhaul insert
        // share this window; Quote Type Trial Quote keeps the HC Sales amount flow off.
        Test.startTest();
        Quote secondQuote = insertQuoteOnOpportunity(secondParent.Id, firstQuote.OpportunityId);
        List<String> results = OverhaulCodeService.applyOverhaulCodes(
            new List<Id>{ firstQuote.Id, secondQuote.Id }
        );
        // Query before stopTest. After it, the setup governor limits are restored
        // and these reads exceed the SOQL limit.
        Integer firstLineCount = queryOverhaulLines(fixture.childWorkOrder.Id).size();
        Integer secondLineCount = queryOverhaulLines(secondChild.Id).size();
        Test.stopTest();

        Assert.areEqual(2, results.size());
        Assert.areEqual(OVERHAUL_CODE, results[0]);
        Assert.areEqual(OVERHAUL_CODE, results[1]);
        Assert.areEqual(1, firstLineCount);
        Assert.areEqual(1, secondLineCount);
    }

    @IsTest
    static void invocable_matchingTrigger_returnsOverhaulProductCode() {
        FixtureData fixture = loadFixture();
        insertServiceCodeLine(fixture, fixture.triggerProduct, TRIGGER_CODE);
        Quote quoteRecord = insertRepairCenterQuote(fixture.parentWorkOrder.Id);
        stubMapping();

        OverhaulCodeInvocable.Request request = new OverhaulCodeInvocable.Request();
        request.recordId = quoteRecord.Id;

        Test.startTest();
        List<OverhaulCodeInvocable.Response> responses =
            OverhaulCodeInvocable.applyOverhaulCodes(
                new List<OverhaulCodeInvocable.Request>{ request }
            );
        Test.stopTest();

        Assert.areEqual(1, responses.size());
        Assert.areEqual(OVERHAUL_CODE, responses[0].overhaulProductCode);
        Assert.areEqual(1, queryOverhaulLines(fixture.childWorkOrder.Id).size());
    }

    @IsTest
    static void invocable_nullRequests_returnsEmpty() {
        Test.startTest();
        List<OverhaulCodeInvocable.Response> responses =
            OverhaulCodeInvocable.applyOverhaulCodes(null);
        Test.stopTest();

        Assert.areEqual(0, responses.size());
    }

    /**
     * @description Quote.RepairCenter is granted by CreateQuotes, which the CI user does not have.
     *              Assign it before other DML so later test methods can insert that record type.
     */
    private static void assignRepairCenterQuoteAccess() {
        List<PermissionSet> permissionSets = [
            SELECT Id
            FROM PermissionSet
            WHERE Name = 'CreateQuotes'
            LIMIT 1
        ];
        if (permissionSets.isEmpty()) {
            return;
        }
        List<PermissionSetAssignment> existingAssignments = [
            SELECT Id
            FROM PermissionSetAssignment
            WHERE AssigneeId = :UserInfo.getUserId()
                AND PermissionSetId = :permissionSets[0].Id
            LIMIT 1
        ];
        if (!existingAssignments.isEmpty()) {
            return;
        }
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert new PermissionSetAssignment(
                AssigneeId = UserInfo.getUserId(),
                PermissionSetId = permissionSets[0].Id
            );
        }
    }

    private static void stubMapping() {
        OverhaulCodeMapping__mdt mapping = new OverhaulCodeMapping__mdt();
        mapping.Model__c = MODEL_CODE;
        mapping.TriggerProductCode__c = TRIGGER_CODE;
        mapping.OverhaulProductCode__c = OVERHAUL_CODE;
        OverhaulCodeService.mappingOverride = new List<OverhaulCodeMapping__mdt>{ mapping };
        OverhaulCodeService.treatAsRepairCenterQuote = true;
    }

    private static WorkOrderLineItem insertServiceCodeLine(
        FixtureData fixture,
        Product2 product,
        String productCode
    ) {
        return insertServiceCodeLineForWorkOrder(
            fixture.childWorkOrder.Id,
            fixture.parentWorkOrder.Id,
            fixture.asset.Id,
            MODEL_CODE,
            product.Id,
            productCode
        );
    }

    private static WorkOrderLineItem insertServiceCodeLineForWorkOrder(
        Id childWorkOrderId,
        Id parentWorkOrderId,
        Id assetId,
        String model,
        Id productId,
        String productCode
    ) {
        PricebookEntry pricebookEntry = [
            SELECT Id
            FROM PricebookEntry
            WHERE Product2Id = :productId
                AND Pricebook2Id = :Test.getStandardPricebookId()
            LIMIT 1
        ];
        Id repairCodeRtId = Schema.SObjectType.WorkOrderLineItem
            .getRecordTypeInfosByDeveloperName()
            .get('RepairCode')
            ?.getRecordTypeId();

        WorkOrderLineItem lineItem = new WorkOrderLineItem(
            WorkOrderId = childWorkOrderId,
            RecordTypeId = repairCodeRtId,
            LineType__c = 'Service Code',
            Product__c = productId,
            RepairCode__c = productId,
            ProductCodeWoli__c = productCode,
            PricebookEntryId = pricebookEntry.Id,
            Quantity = 1,
            AssetId = assetId,
            Model__c = model,
            TopLevelWorkOrder__c = parentWorkOrderId
        );
        insert lineItem;
        return lineItem;
    }

    private static Quote insertRepairCenterQuote(Id parentWorkOrderId) {
        Schema.RecordTypeInfo repairCenterRt = Schema.SObjectType.Quote
            .getRecordTypeInfosByDeveloperName()
            .get('RepairCenter');
        Schema.RecordTypeInfo opportunityRepairCenterRt = Schema.SObjectType.Opportunity
            .getRecordTypeInfosByDeveloperName()
            .get('Repair_Center');
        Id repairCenterRtId = repairCenterRt != null && repairCenterRt.isAvailable()
            ? repairCenterRt.getRecordTypeId()
            : null;
        Id opportunityRepairCenterRtId = opportunityRepairCenterRt != null &&
            opportunityRepairCenterRt.isAvailable()
            ? opportunityRepairCenterRt.getRecordTypeId()
            : null;
        WorkOrder parentWorkOrder = [
            SELECT Id, AccountId, Pricebook2Id
            FROM WorkOrder
            WHERE Id = :parentWorkOrderId
            LIMIT 1
        ];

        Opportunity opportunityRecord = new Opportunity(
            Name = 'Overhaul Quote Opp ' + String.valueOf(Math.random()).substring(0, 8),
            AccountId = parentWorkOrder.AccountId,
            StageName = opportunityRepairCenterRtId == null ? 'Discovery' : 'Evaluate',
            CloseDate = Date.today().addDays(30),
            Pricebook2Id = parentWorkOrder.Pricebook2Id
        );
        if (opportunityRepairCenterRtId != null) {
            opportunityRecord.RecordTypeId = opportunityRepairCenterRtId;
        }
        insert opportunityRecord;

        Quote quoteRecord = new Quote(
            Name = 'Overhaul Test Quote',
            OpportunityId = opportunityRecord.Id,
            Pricebook2Id = parentWorkOrder.Pricebook2Id,
            WorkOrder__c = parentWorkOrderId,
            Status = 'Draft'
        );
        if (repairCenterRtId != null) {
            quoteRecord.RecordTypeId = repairCenterRtId;
        }
        insert quoteRecord;
        return quoteRecord;
    }

    private static Quote insertQuoteOnOpportunity(Id parentWorkOrderId, Id opportunityId) {
        Schema.RecordTypeInfo repairCenterRt = Schema.SObjectType.Quote
            .getRecordTypeInfosByDeveloperName()
            .get('RepairCenter');
        Id repairCenterRtId = repairCenterRt != null && repairCenterRt.isAvailable()
            ? repairCenterRt.getRecordTypeId()
            : null;
        WorkOrder parentWorkOrder = [
            SELECT Pricebook2Id
            FROM WorkOrder
            WHERE Id = :parentWorkOrderId
            LIMIT 1
        ];
        Quote quoteRecord = new Quote(
            Name = 'Overhaul Test Quote 2',
            OpportunityId = opportunityId,
            Pricebook2Id = parentWorkOrder.Pricebook2Id,
            WorkOrder__c = parentWorkOrderId,
            Status = 'Draft',
            QuoteType__c = 'Trial Quote'
        );
        if (repairCenterRtId != null) {
            quoteRecord.RecordTypeId = repairCenterRtId;
        }
        insert quoteRecord;
        return quoteRecord;
    }

    private static List<WorkOrderLineItem> queryOverhaulLines(Id childWorkOrderId) {
        return [
            SELECT Id, ProductCodeWoli__c, LineType__c
            FROM WorkOrderLineItem
            WHERE WorkOrderId = :childWorkOrderId
                AND ProductCodeWoli__c = :OVERHAUL_CODE
        ];
    }

    private static FixtureData loadFixture() {
        FixtureData fixture = new FixtureData();
        fixture.parentWorkOrder = [
            SELECT Id, AccountId, Pricebook2Id
            FROM WorkOrder
            WHERE Subject = 'Overhaul Parent WO'
            LIMIT 1
        ];
        fixture.childWorkOrder = [
            SELECT Id, AssetId, ParentWorkOrderId
            FROM WorkOrder
            WHERE Subject = 'Overhaul Child WO'
            LIMIT 1
        ];
        fixture.asset = [
            SELECT Id, Product2Id
            FROM Asset
            WHERE SerialNumber = 'SN-OH-001'
            LIMIT 1
        ];
        Map<String, Product2> productsByCode = new Map<String, Product2>();
        for (Product2 product : [
            SELECT Id, ProductCode, Model__c
            FROM Product2
            WHERE ProductCode IN :new Set<String>{
                TRIGGER_CODE,
                OVERHAUL_CODE,
                OTHER_CODE,
                'OH-ASSET'
            }
        ]) {
            productsByCode.put(product.ProductCode, product);
        }
        fixture.triggerProduct = productsByCode.get(TRIGGER_CODE);
        fixture.overhaulProduct = productsByCode.get(OVERHAUL_CODE);
        fixture.otherProduct = productsByCode.get(OTHER_CODE);
        fixture.assetProduct = productsByCode.get('OH-ASSET');
        return fixture;
    }

    private class FixtureData {
        WorkOrder parentWorkOrder;
        WorkOrder childWorkOrder;
        Asset asset;
        Product2 triggerProduct;
        Product2 overhaulProduct;
        Product2 otherProduct;
        Product2 assetProduct;
    }

    private static void ensureOverhaulPricebookEntries(Id childWorkOrderId, List<Id> productIds) {
        WorkOrder childWorkOrder = [
            SELECT Pricebook2Id, CurrencyIsoCode, ParentWorkOrder.Pricebook2Id
            FROM WorkOrder
            WHERE Id = :childWorkOrderId
            LIMIT 1
        ];
        String currencyIsoCode = childWorkOrder.CurrencyIsoCode;
        Set<Id> pricebookIds = new Set<Id>();
        if (childWorkOrder.Pricebook2Id != null) {
            pricebookIds.add(childWorkOrder.Pricebook2Id);
        }
        if (
            childWorkOrder.ParentWorkOrder != null &&
            childWorkOrder.ParentWorkOrder.Pricebook2Id != null
        ) {
            pricebookIds.add(childWorkOrder.ParentWorkOrder.Pricebook2Id);
        }
        Id standardPricebookId = Test.getStandardPricebookId();
        for (Id productId : productIds) {
            if (productId == null) {
                continue;
            }
            for (Id pricebookId : pricebookIds) {
                if (pricebookId != standardPricebookId) {
                    insertPricebookEntryIfMissing(productId, standardPricebookId, currencyIsoCode);
                }
                insertPricebookEntryIfMissing(productId, pricebookId, currencyIsoCode);
            }
        }
    }

    private static void insertPricebookEntryIfMissing(
        Id productId,
        Id pricebookId,
        String currencyIsoCode
    ) {
        String soql =
            'SELECT Id FROM PricebookEntry WHERE Product2Id = :productId AND Pricebook2Id = :pricebookId';
        if (UserInfo.isMultiCurrencyOrganization() && String.isNotBlank(currencyIsoCode)) {
            soql += ' AND CurrencyIsoCode = :currencyIsoCode';
        }
        if (!Database.query(soql).isEmpty()) {
            return;
        }
        PricebookEntry entry = new PricebookEntry(
            Product2Id = productId,
            Pricebook2Id = pricebookId,
            UnitPrice = 1,
            IsActive = true
        );
        if (UserInfo.isMultiCurrencyOrganization() && String.isNotBlank(currencyIsoCode)) {
            entry.put('CurrencyIsoCode', currencyIsoCode);
        }
        insert entry;
    }
}