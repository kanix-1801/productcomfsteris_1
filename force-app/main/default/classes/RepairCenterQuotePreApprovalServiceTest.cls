/**
 * @description Tests for RepairCenterQuotePreApprovalService.
 */
@isTest
private class RepairCenterQuotePreApprovalServiceTest {
    private static String lastFixtureError;

    @isTest
    static void evaluateQuoteLines_approvesWhenWithinLimit() {
        Id accountId = fakeId(Account.SObjectType, 1);
        Id quoteId = fakeId(Quote.SObjectType, 1);
        Id parentWoliId = fakeId(WorkOrderLineItem.SObjectType, 1);
        Id productServicedId = fakeId(QuoteLineItem.SObjectType, 1);
        Id serviceQliId = fakeId(QuoteLineItem.SObjectType, 2);

        Quote quoteRecord = (Quote) JSON.deserialize(
            '{"attributes":{"type":"Quote"},"Id":"' +
                quoteId +
                '","AccountId":"' +
                accountId +
                '","Status":"Waiting for Approval"}',
            Quote.class
        );

        List<QuoteLineItem> lines = new List<QuoteLineItem>{
            (QuoteLineItem) JSON.deserialize(
                '{"attributes":{"type":"QuoteLineItem"},"Id":"' +
                    productServicedId +
                    '","QuoteId":"' +
                    quoteId +
                    '","LineType__c":"Product Serviced","Status__c":"Waiting for Approval","ProductLine__c":"Biomedical","TotalPrice":0}',
                QuoteLineItem.class
            ),
            (QuoteLineItem) JSON.deserialize(
                '{"attributes":{"type":"QuoteLineItem"},"Id":"' +
                    serviceQliId +
                    '","QuoteId":"' +
                    quoteId +
                    '","LineType__c":"Service Code","Status__c":"Waiting for Approval","ParentWorkOrderLineItem__c":"' +
                    parentWoliId +
                    '","TotalPrice":100}',
                QuoteLineItem.class
            )
        };

        Map<Id, String> parentProductLines = new Map<Id, String>{
            parentWoliId => 'Biomedical'
        };
        Map<String, Decimal> limits = new Map<String, Decimal>{
            String.valueOf(accountId) + '|Biomedical' => 500
        };

        RepairCenterQuotePreApprovalService.EvaluationResult result =
            RepairCenterQuotePreApprovalService.evaluateQuoteLines(
                quoteRecord,
                lines,
                parentProductLines,
                limits
            );

        Assert.areEqual(2, result.qlisToUpdate.size());
        Assert.areNotEqual(null, result.quoteToUpdate);
        Assert.areEqual('Approved', result.quoteToUpdate.Status);
    }

    @isTest
    static void evaluateQuoteLines_doesNotApproveWhenOverLimit() {
        Id accountId = fakeId(Account.SObjectType, 1);
        Id quoteId = fakeId(Quote.SObjectType, 1);
        Id parentWoliId = fakeId(WorkOrderLineItem.SObjectType, 1);

        Quote quoteRecord = (Quote) JSON.deserialize(
            '{"attributes":{"type":"Quote"},"Id":"' +
                quoteId +
                '","AccountId":"' +
                accountId +
                '","Status":"Waiting for Approval"}',
            Quote.class
        );

        List<QuoteLineItem> lines = new List<QuoteLineItem>{
            (QuoteLineItem) JSON.deserialize(
                '{"attributes":{"type":"QuoteLineItem"},"Id":"' +
                    fakeId(QuoteLineItem.SObjectType, 1) +
                    '","QuoteId":"' +
                    quoteId +
                    '","LineType__c":"Product Serviced","Status__c":"Waiting for Approval","ProductLine__c":"Biomedical","TotalPrice":0}',
                QuoteLineItem.class
            ),
            (QuoteLineItem) JSON.deserialize(
                '{"attributes":{"type":"QuoteLineItem"},"Id":"' +
                    fakeId(QuoteLineItem.SObjectType, 2) +
                    '","QuoteId":"' +
                    quoteId +
                    '","LineType__c":"Service Code","Status__c":"Waiting for Approval","ParentWorkOrderLineItem__c":"' +
                    parentWoliId +
                    '","TotalPrice":100}',
                QuoteLineItem.class
            )
        };

        RepairCenterQuotePreApprovalService.EvaluationResult result =
            RepairCenterQuotePreApprovalService.evaluateQuoteLines(
                quoteRecord,
                lines,
                new Map<Id, String>{ parentWoliId => 'Biomedical' },
                new Map<String, Decimal>{ String.valueOf(accountId) + '|Biomedical' => 50 }
            );

        Assert.areEqual(0, result.qlisToUpdate.size());
        Assert.areEqual(null, result.quoteToUpdate);
    }

    @isTest
    static void evaluateQuoteLines_defaultsMissingPreferenceToZero() {
        Id accountId = fakeId(Account.SObjectType, 1);
        Id quoteId = fakeId(Quote.SObjectType, 1);
        Id parentWoliId = fakeId(WorkOrderLineItem.SObjectType, 1);

        Quote quoteRecord = (Quote) JSON.deserialize(
            '{"attributes":{"type":"Quote"},"Id":"' +
                quoteId +
                '","AccountId":"' +
                accountId +
                '","Status":"Waiting for Approval"}',
            Quote.class
        );

        List<QuoteLineItem> lines = new List<QuoteLineItem>{
            (QuoteLineItem) JSON.deserialize(
                '{"attributes":{"type":"QuoteLineItem"},"Id":"' +
                    fakeId(QuoteLineItem.SObjectType, 1) +
                    '","QuoteId":"' +
                    quoteId +
                    '","LineType__c":"Product Serviced","Status__c":"Waiting for Approval","ProductLine__c":"Biomedical","TotalPrice":0}',
                QuoteLineItem.class
            ),
            (QuoteLineItem) JSON.deserialize(
                '{"attributes":{"type":"QuoteLineItem"},"Id":"' +
                    fakeId(QuoteLineItem.SObjectType, 2) +
                    '","QuoteId":"' +
                    quoteId +
                    '","LineType__c":"Category Code","Status__c":"Waiting for Approval","ParentWorkOrderLineItem__c":"' +
                    parentWoliId +
                    '","TotalPrice":0}',
                QuoteLineItem.class
            )
        };

        RepairCenterQuotePreApprovalService.EvaluationResult result =
            RepairCenterQuotePreApprovalService.evaluateQuoteLines(
                quoteRecord,
                lines,
                new Map<Id, String>{ parentWoliId => 'Biomedical' },
                new Map<String, Decimal>()
            );

        Assert.areEqual(2, result.qlisToUpdate.size());
        Assert.areNotEqual(null, result.quoteToUpdate);
    }

    @isTest
    static void toCurrency_parsesTextAndHandlesNulls() {
        Assert.areEqual(0, RepairCenterQuotePreApprovalService.toCurrency(null));
        Assert.areEqual(
            0,
            RepairCenterQuotePreApprovalService.toCurrency(new CustomerPreference__c())
        );
        Assert.areEqual(
            125.5,
            RepairCenterQuotePreApprovalService.toCurrency(
                new CustomerPreference__c(PreferenceValue__c = '$125.50')
            )
        );
        Assert.areEqual(
            0,
            RepairCenterQuotePreApprovalService.toCurrency(
                new CustomerPreference__c(PreferenceValue__c = 'not-a-number')
            )
        );
    }

    @isTest
    static void resolveProductLine_prefersWoliThenPricebookProduct() {
        WorkOrderLineItem withWoliValue = new WorkOrderLineItem(ProductLine__c = 'Endocam');
        Assert.areEqual(
            'Endocam',
            RepairCenterQuotePreApprovalService.resolveProductLine(withWoliValue)
        );
        Assert.areEqual(null, RepairCenterQuotePreApprovalService.resolveProductLine(null));

        WorkOrderLineItem fromPricebook = (WorkOrderLineItem) JSON.deserialize(
            '{"attributes":{"type":"WorkOrderLineItem"},' +
                '"PricebookEntry":{"attributes":{"type":"PricebookEntry"},' +
                '"Product2":{"attributes":{"type":"Product2"},"ProductLine__c":"Instrument"}}}',
            WorkOrderLineItem.class
        );
        Assert.areEqual(
            'Instrument',
            RepairCenterQuotePreApprovalService.resolveProductLine(fromPricebook)
        );
    }

    @isTest
    static void evaluateQuoteLines_handlesEmptyAndBlankProductLinePaths() {
        Id accountId = fakeId(Account.SObjectType, 1);
        Id quoteId = fakeId(Quote.SObjectType, 1);
        Id parentWoliId = fakeId(WorkOrderLineItem.SObjectType, 1);

        Quote quoteRecord = (Quote) JSON.deserialize(
            '{"attributes":{"type":"Quote"},"Id":"' +
                quoteId +
                '","Status":"Waiting for Approval"}',
            Quote.class
        );

        RepairCenterQuotePreApprovalService.EvaluationResult emptyLines =
            RepairCenterQuotePreApprovalService.evaluateQuoteLines(
                quoteRecord,
                new List<QuoteLineItem>(),
                new Map<Id, String>(),
                new Map<String, Decimal>()
            );
        Assert.areEqual(0, emptyLines.qlisToUpdate.size());

        List<QuoteLineItem> categoryOnly = new List<QuoteLineItem>{
            (QuoteLineItem) JSON.deserialize(
                '{"attributes":{"type":"QuoteLineItem"},"Id":"' +
                    fakeId(QuoteLineItem.SObjectType, 1) +
                    '","QuoteId":"' +
                    quoteId +
                    '","LineType__c":"Category Code","Status__c":"Waiting for Approval","ParentWorkOrderLineItem__c":"' +
                    parentWoliId +
                    '","TotalPrice":10}',
                QuoteLineItem.class
            )
        };
        RepairCenterQuotePreApprovalService.EvaluationResult noProductServiced =
            RepairCenterQuotePreApprovalService.evaluateQuoteLines(
                quoteRecord,
                categoryOnly,
                new Map<Id, String>{ parentWoliId => 'Biomedical' },
                new Map<String, Decimal>()
            );
        Assert.areEqual(0, noProductServiced.qlisToUpdate.size());

        List<QuoteLineItem> blankAndDuplicateProductLines = new List<QuoteLineItem>{
            (QuoteLineItem) JSON.deserialize(
                '{"attributes":{"type":"QuoteLineItem"},"Id":"' +
                    fakeId(QuoteLineItem.SObjectType, 2) +
                    '","QuoteId":"' +
                    quoteId +
                    '","LineType__c":"Product Serviced","Status__c":"Waiting for Approval","ProductLine__c":"","TotalPrice":0}',
                QuoteLineItem.class
            ),
            (QuoteLineItem) JSON.deserialize(
                '{"attributes":{"type":"QuoteLineItem"},"Id":"' +
                    fakeId(QuoteLineItem.SObjectType, 3) +
                    '","QuoteId":"' +
                    quoteId +
                    '","LineType__c":"Product Serviced","Status__c":"Waiting for Approval","ProductLine__c":"Biomedical","TotalPrice":0}',
                QuoteLineItem.class
            ),
            (QuoteLineItem) JSON.deserialize(
                '{"attributes":{"type":"QuoteLineItem"},"Id":"' +
                    fakeId(QuoteLineItem.SObjectType, 4) +
                    '","QuoteId":"' +
                    quoteId +
                    '","LineType__c":"Product Serviced","Status__c":"Waiting for Approval","ProductLine__c":"Biomedical","TotalPrice":0}',
                QuoteLineItem.class
            ),
            (QuoteLineItem) JSON.deserialize(
                '{"attributes":{"type":"QuoteLineItem"},"Id":"' +
                    fakeId(QuoteLineItem.SObjectType, 5) +
                    '","QuoteId":"' +
                    quoteId +
                    '","LineType__c":"Service Code","Status__c":"Waiting for Approval","ParentWorkOrderLineItem__c":"' +
                    parentWoliId +
                    '","TotalPrice":null}',
                QuoteLineItem.class
            )
        };

        RepairCenterQuotePreApprovalService.EvaluationResult result =
            RepairCenterQuotePreApprovalService.evaluateQuoteLines(
                quoteRecord,
                blankAndDuplicateProductLines,
                new Map<Id, String>{ parentWoliId => 'Biomedical' },
                new Map<String, Decimal>{ String.valueOf(accountId) + '|Biomedical' => 100 }
            );
// Null AccountId forces pre-approval limit to 0; null child NetTotalPrice counts as 0.
        // Both Biomedical Product Serviced lines + Service Code approve; blank Product Serviced does not,
        // so the Quote itself stays unapproved.
        Assert.areEqual(3, result.qlisToUpdate.size());
        Assert.areEqual(null, result.quoteToUpdate);
    }

    @isTest
    static void loadPreApprovalLimits_returnsActivePreferenceValues() {
        adb_Account accountBuilder = new adb_Account();
        accountBuilder.persist();

        new adb_CustomerPreference()
            .setRecordType('IMSCustomerPreference')
            .preferenceType('Pre-Approval Limit')
            .preferenceValue('$250.00')
            .productLine('Biomedical')
            .account(accountBuilder)
            .persist();

        Test.startTest();
        Map<String, Decimal> limits = RepairCenterQuotePreApprovalService.loadPreApprovalLimits(
            new Set<Id>{ accountBuilder.id },
            new Set<String>{ 'Biomedical' }
        );
        Test.stopTest();

        String key = String.valueOf(accountBuilder.id) + '|Biomedical';
        Assert.areEqual(250, limits.get(key));
    }

    @isTest
    static void evaluatePreApprovalLimits_stampsAndApprovesWithPersistedQuoteGraph() {
        PreApprovalFixture fixture = buildPreApprovalFixture();
        Assert.areNotEqual(
            null,
            fixture,
            'Failed to build Quote/QLI graph for pre-approval coverage: ' + lastFixtureError
        );

        RepairCenterQuotePreApprovalService.Request request =
            new RepairCenterQuotePreApprovalService.Request();
        request.quoteId = fixture.quoteId;

        Test.startTest();
        RepairCenterQuotePreApprovalService.evaluatePreApprovalLimits(
            new List<RepairCenterQuotePreApprovalService.Request>{ request }
        );
        Test.stopTest();

        Quote refreshedQuote = [
            SELECT Id, Status
            FROM Quote
            WHERE Id = :fixture.quoteId
        ];
        List<QuoteLineItem> refreshedLines = [
            SELECT Id, Status__c, ProductLine__c, LineType__c
            FROM QuoteLineItem
            WHERE QuoteId = :fixture.quoteId
        ];

        Assert.areEqual('Approved', refreshedQuote.Status);
        Integer approvedCount = 0;
        for (QuoteLineItem line : refreshedLines) {
            if (line.Status__c == 'Approved') {
                approvedCount++;
            }
            if (line.LineType__c == 'Product Serviced') {
                Assert.areEqual('Biomedical', line.ProductLine__c);
            }
        }
        Assert.isTrue(approvedCount >= 2, 'Product Serviced and Service Code lines should approve');
    }

    @isTest
    static void evaluatePreApprovalLimits_handlesEmptyRequests() {
        Test.startTest();
        RepairCenterQuotePreApprovalService.evaluatePreApprovalLimits(null);
        RepairCenterQuotePreApprovalService.evaluatePreApprovalLimits(
            new List<RepairCenterQuotePreApprovalService.Request>()
        );
        RepairCenterQuotePreApprovalService.Request blankRequest =
            new RepairCenterQuotePreApprovalService.Request();
        RepairCenterQuotePreApprovalService.evaluatePreApprovalLimits(
            new List<RepairCenterQuotePreApprovalService.Request>{ blankRequest }
        );
        Assert.areEqual(0, Limits.getDmlStatements(), 'Empty requests should not perform DML');
        Test.stopTest();
    }

    @isTest
    static void evaluateQuotes_andHelpers_handleEmptyDataPaths() {
        Id fakeQuoteId = fakeId(Quote.SObjectType, 9);
        Id fakeAccountId = fakeId(Account.SObjectType, 9);

        RepairCenterQuotePreApprovalService.Request request =
            new RepairCenterQuotePreApprovalService.Request();
        request.quoteId = fakeQuoteId;

        Test.startTest();
        RepairCenterQuotePreApprovalService.evaluatePreApprovalLimits(
            new List<RepairCenterQuotePreApprovalService.Request>{ request }
        );
        RepairCenterQuotePreApprovalService.evaluateQuotes(new Set<Id>{ fakeQuoteId });
        RepairCenterQuotePreApprovalService.stampProductLinesFromPricebookProduct(null);
        RepairCenterQuotePreApprovalService.stampProductLinesFromPricebookProduct(
            new List<QuoteLineItem>()
        );
        RepairCenterQuotePreApprovalService.stampProductLinesFromPricebookProduct(
            new List<QuoteLineItem>{ new QuoteLineItem() }
        );
        Map<String, Decimal> emptyLimits =
            RepairCenterQuotePreApprovalService.loadPreApprovalLimits(
                new Set<Id>(),
                new Set<String>()
            );
        Map<String, Decimal> noMatchLimits =
            RepairCenterQuotePreApprovalService.loadPreApprovalLimits(
                new Set<Id>{ fakeAccountId },
                new Set<String>{ 'Biomedical' }
            );
        Test.stopTest();

        Assert.areEqual(0, emptyLimits.size());
        Assert.areEqual(0, noMatchLimits.size());
    }

    private class PreApprovalFixture {
        public Id quoteId;
    }

    /**
     * @description Builds Account, preference, product/PBE, WOLI, Quote, and QLIs for end-to-end
     *              pre-approval coverage. Uses the first Quote record type the running user can
     *              assign, including HC Sales. The service does not filter Quotes by record type.
     */
    private static PreApprovalFixture buildPreApprovalFixture() {
        try {
            Id quoteRecordTypeId = availableQuoteRecordTypeId();
            if (quoteRecordTypeId == null) {
                lastFixtureError = 'No Quote record type is available to the running user.';
                return null;
            }

            adb_Account accountBuilder = new adb_Account();
            accountBuilder.persist();

            new adb_CustomerPreference()
                .setRecordType('IMSCustomerPreference')
                .preferenceType('Pre-Approval Limit')
                .preferenceValue('500')
                .productLine('Biomedical')
                .account(accountBuilder)
                .persist();

            Product2 product = new Product2(
                Name = 'GW-4117 PreApproval Product',
                ProductCode = 'GW4117-PAP-' + String.valueOf(Crypto.getRandomInteger()).right(6),
                IsActive = true,
                ProductLine__c = 'Biomedical'
            );
            insert product;

            Id pricebookId = Test.getStandardPricebookId();
            PricebookEntry pricebookEntry = new PricebookEntry(
                Pricebook2Id = pricebookId,
                Product2Id = product.Id,
                UnitPrice = 100,
                IsActive = true
            );
            insert pricebookEntry;

            adb_WorkOrder workOrderBuilder = new adb_WorkOrder()
                .setRecordType('RepairCenterInstruments');
            workOrderBuilder.persist();
            WorkOrder workOrder = [
                SELECT Id, Pricebook2Id
                FROM WorkOrder
                WHERE Id = :workOrderBuilder.id
            ];
            workOrder.Pricebook2Id = pricebookId;
            workOrder.AccountId = accountBuilder.id;
            update workOrder;

            WorkOrderLineItem parentWoli = new WorkOrderLineItem(
                WorkOrderId = workOrder.Id,
                PricebookEntryId = pricebookEntry.Id,
                Quantity = 1,
                UnitPrice = 100,
                Status = 'New'
            );
            insert parentWoli;

            Opportunity opportunityRecord = new Opportunity(
                Name = 'GW-4117 PreApproval Opp',
                AccountId = accountBuilder.id,
                StageName = 'Discovery',
                CloseDate = Date.today().addDays(30)
            );
            insert opportunityRecord;

            Quote quoteRecord = new Quote(
                Name = 'GW-4117 PreApproval Quote',
                OpportunityId = opportunityRecord.Id,
                Pricebook2Id = pricebookId,
                Status = 'Waiting for Approval',
                RecordTypeId = quoteRecordTypeId
            );
            insert quoteRecord;

            QuoteLineItem productServiced = new QuoteLineItem(
                QuoteId = quoteRecord.Id,
                PricebookEntryId = pricebookEntry.Id,
                Quantity = 1,
                UnitPrice = 0,
                LineType__c = 'Product Serviced',
                Status__c = 'Waiting for Approval',
                WorkOrderLineItem__c = parentWoli.Id
            );
            QuoteLineItem serviceCode = new QuoteLineItem(
                QuoteId = quoteRecord.Id,
                PricebookEntryId = pricebookEntry.Id,
                Quantity = 1,
                UnitPrice = 100,
                LineType__c = 'Service Code',
                Status__c = 'Waiting for Approval',
                ParentWorkOrderLineItem__c = parentWoli.Id,
                WorkOrderLineItem__c = parentWoli.Id
            );
            insert new List<QuoteLineItem>{ productServiced, serviceCode };

            PreApprovalFixture fixture = new PreApprovalFixture();
            fixture.quoteId = quoteRecord.Id;
            return fixture;
        } catch (Exception e) {
            lastFixtureError = e.getMessage() + ' | ' + e.getStackTraceString();
            return null;
        }
    }

    /**
     * @description Returns the first active Quote record type the running user can assign.
     *              HC Sales is allowed. The QA deploy user has the System Administrator
     *              permission set, which can read IsForecastIneligible__c and QuoteType__c.
     * @return Record type Id, or null when none are available
     */
    private static Id availableQuoteRecordTypeId() {
        for (Schema.RecordTypeInfo info : Schema.SObjectType.Quote.getRecordTypeInfos()) {
            if (info == null || info.isMaster() || !info.isActive() || !info.isAvailable()) {
                continue;
            }
            return info.getRecordTypeId();
        }
        return null;
    }

    private static Id fakeId(Schema.SObjectType sobjectType, Integer seed) {
        String prefix = sobjectType.getDescribe().getKeyPrefix();
        String suffix = String.valueOf(seed).leftPad(12, '0');
        return Id.valueOf(prefix + suffix);
    }
}