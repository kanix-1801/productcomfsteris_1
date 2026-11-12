/**
 * @description Own test class for QuoteService (forecast helpers + GW-5333 Approve/Reject).
 */
@IsTest
private class QuoteServiceTest {
    private static final String STATUS_WAITING = 'Waiting for Approval';
    private static final String STATUS_APPROVED = 'Approved';
    private static final String STATUS_REJECTED = 'Rejected';
    private static final String PRODUCT_LINE = 'GW-3507 QuoteService Product Line';
    private static final String REPAIR_CENTER_RT = 'RepairCenter';
    private static final String TEST_OPP_NAME = 'GW-3507 QuoteService Opportunity';

    private static String getFirstActiveValue(Schema.DescribeFieldResult fieldDescribe) {
        for (Schema.PicklistEntry picklistEntry : fieldDescribe.getPicklistValues()) {
            if (picklistEntry.isActive()) {
                return picklistEntry.getValue();
            }
        }
        return null;
    }

    private static String resolveSpecialPricingLineType() {
        Set<String> activeValues = new Set<String>();
        for (
            Schema.PicklistEntry picklistEntry :
            QuoteLineItem.LineType__c.getDescribe().getPicklistValues()
        ) {
            if (picklistEntry.isActive()) {
                activeValues.add(picklistEntry.getValue());
            }
        }
        for (String preferredValue : new List<String>{
            'Special Pricing',
            'Service Code',
            'Observation Code',
            'Category Code'
        }) {
            if (activeValues.contains(preferredValue)) {
                return preferredValue;
            }
        }
        return getFirstActiveValue(QuoteLineItem.LineType__c.getDescribe());
    }

    private static Id resolveHcSalesQuoteRecordTypeId() {
        Schema.RecordTypeInfo recordTypeInfo = Schema.SObjectType.Quote
            .getRecordTypeInfosByDeveloperName()
            .get(GenerateQuoteService.QUOTE_RECORD_TYPE_DEVELOPER_NAME);
        return recordTypeInfo == null ? null : recordTypeInfo.getRecordTypeId();
    }

    /**
     * @description Inserts Opportunity using the Healthcare_Sales fixture that Dev accepts
     *              (same shape as FreeGoodTaskControllerTest). Default Opp RTs reject Pipeline
     *              after automation stamps ForecastConfidenceLevel__c.
     */
    private static Opportunity insertSetupOpportunity(
        Id accountId,
        Id primaryContactId,
        Id pricebookId
    ) {
        Opportunity opportunityRecord = new Opportunity(
            Name = TEST_OPP_NAME,
            AccountId = accountId,
            StageName = 'Discovery',
            Type = 'New Business',
            ForecastConfidenceLevel__c = 'Pipeline',
            PrimaryContact__c = primaryContactId,
            CloseDate = Date.today().addDays(30),
            Amount = 1000,
            Probability = 10,
            Pricebook2Id = pricebookId
        );
        Schema.RecordTypeInfo healthcareSalesRt = Schema.SObjectType.Opportunity
            .getRecordTypeInfosByDeveloperName()
            .get('Healthcare_Sales');
        if (healthcareSalesRt != null) {
            opportunityRecord.RecordTypeId = healthcareSalesRt.getRecordTypeId();
        }
        insert opportunityRecord;
        return opportunityRecord;
    }

    /**
     * @description Disables Quote/WO Overhaul-related flows that NPE in Dev test inserts.
     */
    private static void disableOverhaulAutomationForTests() {
        insert new Automation_Setting_Flow__c(
            SetupOwnerId = UserInfo.getUserId(),
            WorkOrder_AfterSave_SetOverhaulCode__c = true,
            WorkOrder_Async_RecalculateOverhaulCode__c = true,
            WOLI_Created_SetOverhaulCode__c = true,
            WOLI_Deleted_SetOverhaulCode__c = true,
            Quote_AfterSave_SetQuoteFields__c = true,
            RepairCenterQuote_Updated_AfterSave__c = true
        );
    }

    /**
     * @description Resolves the @TestSetup Opportunity via the Approve/Reject Quote.
     *              Opportunity.Name can be rewritten by org automation, so do not query by name.
     */
    private static Opportunity getSetupOpportunity() {
        Quote setupQuote = [
            SELECT OpportunityId
            FROM Quote
            WHERE Name = 'GW-3507 ApproveReject Quote'
            LIMIT 1
        ];
        return [
            SELECT Id, Pricebook2Id, ForecastConfidenceLevel__c
            FROM Opportunity
            WHERE Id = :setupQuote.OpportunityId
            LIMIT 1
        ];
    }

    @TestSetup
    static void setupTestData() {
        disableOverhaulAutomationForTests();

        adb_Account accountBuilder = new adb_Account().name('GW-3507 QuoteService Account');
        accountBuilder.persist();

        Id pricebookId = Test.getStandardPricebookId();

        Contact primaryContact = new Contact(
            FirstName = 'GW-3507',
            LastName = 'QuoteService Contact',
            AccountId = accountBuilder.id
        );
        insert primaryContact;

        Opportunity opportunityRecord = insertSetupOpportunity(
            accountBuilder.id,
            primaryContact.Id,
            pricebookId
        );

        Product2 productServiced = new Product2(
            Name = 'GW-3507 Product Serviced',
            ProductCode = 'PS-3507-QS',
            Description = 'Product serviced description',
            IsActive = true,
            InspectionFeeApplicable__c = false
        );
        Product2 categoryProduct = new Product2(
            Name = 'GW-3507 Category Code',
            ProductCode = 'CC-3507-QS',
            IsActive = true
        );
        Product2 specialPricingProduct = new Product2(
            Name = 'GW-3507 Special Pricing',
            ProductCode = 'SP-3507-QS',
            IsActive = true
        );
        insert new List<Product2>{ productServiced, categoryProduct, specialPricingProduct };

        insert new List<PricebookEntry>{
            new PricebookEntry(
                Pricebook2Id = pricebookId,
                Product2Id = productServiced.Id,
                UnitPrice = 100,
                IsActive = true
            ),
            new PricebookEntry(
                Pricebook2Id = pricebookId,
                Product2Id = categoryProduct.Id,
                UnitPrice = 50,
                IsActive = true
            ),
            new PricebookEntry(
                Pricebook2Id = pricebookId,
                Product2Id = specialPricingProduct.Id,
                UnitPrice = 25,
                IsActive = true
            )
        };

        adb_WorkOrder workOrderBuilder = new adb_WorkOrder().subject('GW-3507 QuoteService WO');
        workOrderBuilder.persist();
        WorkOrder workOrder = [
            SELECT Id
            FROM WorkOrder
            WHERE Id = :workOrderBuilder.id
        ];
        workOrder.Pricebook2Id = pricebookId;
        workOrder.TurnTime__c = 5;
        workOrder.ScheduledShipDate__c = Date.today().addDays(7);
        update workOrder;

        // Do not stamp RepairCenter RT here. Dev Quote after-save Overhaul automation NPEs on
        // RepairCenter Quotes in test context; Approve/Reject only needs Waiting status + WO link.
        Quote quoteRecord = new Quote(
            Name = 'GW-3507 ApproveReject Quote',
            OpportunityId = opportunityRecord.Id,
            Pricebook2Id = pricebookId,
            Status = STATUS_WAITING,
            WorkOrder__c = workOrder.Id,
            Version__c = 1
        );
        insert quoteRecord;

        workOrder.ActiveQuote__c = quoteRecord.Id;
        update workOrder;

        PricebookEntry productServicedEntry = [
            SELECT Id
            FROM PricebookEntry
            WHERE Product2Id = :productServiced.Id
            LIMIT 1
        ];
        PricebookEntry categoryEntry = [
            SELECT Id
            FROM PricebookEntry
            WHERE Product2Id = :categoryProduct.Id
            LIMIT 1
        ];
        PricebookEntry specialPricingEntry = [
            SELECT Id
            FROM PricebookEntry
            WHERE Product2Id = :specialPricingProduct.Id
            LIMIT 1
        ];

        WorkOrderLineItem productServicedWoli = new WorkOrderLineItem(
            WorkOrderId = workOrder.Id,
            PricebookEntryId = productServicedEntry.Id,
            Quantity = 1,
            UnitPrice = 100,
            ProductLine__c = PRODUCT_LINE
        );
        insert productServicedWoli;

        QuoteLineItem productServicedLine = new QuoteLineItem(
            QuoteId = quoteRecord.Id,
            PricebookEntryId = productServicedEntry.Id,
            Quantity = 1,
            UnitPrice = 100,
            LineType__c = 'Product Serviced',
            Status__c = STATUS_WAITING,
            WorkOrder__c = workOrder.Id,
            WorkOrderLineItem__c = productServicedWoli.Id
        );
        insert productServicedLine;

        insert new List<QuoteLineItem>{
            new QuoteLineItem(
                QuoteId = quoteRecord.Id,
                PricebookEntryId = categoryEntry.Id,
                Quantity = 1,
                UnitPrice = 50,
                LineType__c = 'Category Code',
                Status__c = STATUS_WAITING,
                ParentWorkOrderLineItem__c = productServicedWoli.Id,
                WorkOrder__c = workOrder.Id
            ),
            new QuoteLineItem(
                QuoteId = quoteRecord.Id,
                PricebookEntryId = specialPricingEntry.Id,
                Quantity = 1,
                UnitPrice = 25,
                LineType__c = resolveSpecialPricingLineType(),
                Status__c = STATUS_WAITING,
                ParentWorkOrderLineItem__c = productServicedWoli.Id,
                WorkOrder__c = workOrder.Id
            )
        };
    }

    // --- Forecast / pricing helpers ---

    @IsTest
    static void testMapOpportunityForecastConfidenceToQuote_WhenValuesProvided() {
        Assert.isNull(QuoteService.mapOpportunityForecastConfidenceToQuote(null));
        Assert.isNull(QuoteService.mapOpportunityForecastConfidenceToQuote(''));
        Assert.areEqual('Make-It', QuoteService.mapOpportunityForecastConfidenceToQuote('Make It'));
        Assert.areEqual(
            'Pipeline',
            QuoteService.mapOpportunityForecastConfidenceToQuote('Pipeline')
        );
        Assert.isNull(QuoteService.mapOpportunityForecastConfidenceToQuote('NotARealValue'));
    }

    @IsTest
    static void testForecastStatusHelpers_WhenStatusProvided() {
        Assert.isTrue(QuoteService.isForecastableStatus(QuoteSelector.OPEN_STATUS_VALUE));
        Assert.isFalse(QuoteService.isForecastableStatus('Draft'));
        Assert.isTrue(QuoteService.isClosedStatus(QuoteSelector.CLOSED_STATUS_VALUE));
        Assert.isFalse(QuoteService.isClosedStatus('Open'));
    }

    @IsTest
    static void testAutomationDisabledToggle_WhenSet() {
        QuoteService.setAutomationDisabled(true);
        Assert.isTrue(QuoteService.isAutomationDisabled());
        QuoteService.setAutomationDisabled(false);
        Assert.isFalse(QuoteService.isAutomationDisabled());
    }

    @IsTest
    static void testCalculateQuoteLineTotals_WhenLinesProvided() {
        Assert.areEqual(0, QuoteService.calculateQuoteLineTotal(null));
        // TotalPrice is not writeable; hydrate via JSON for the TotalPrice branch.
        QuoteLineItem withTotalPrice = (QuoteLineItem) JSON.deserialize(
            '{"TotalPrice":40,"Quantity":2,"UnitPrice":10}',
            QuoteLineItem.class
        );
        Assert.areEqual(40, QuoteService.calculateQuoteLineTotal(withTotalPrice));
        Assert.areEqual(
            30,
            QuoteService.calculateQuoteLineTotal(
                new QuoteLineItem(Quantity = 3, UnitPrice = 10)
            )
        );
        Assert.areEqual(
            12,
            QuoteService.calculateQuoteLineTotal(
                new QuoteLineItem(Quantity = null, UnitPrice = 12)
            )
        );

        Assert.isNull(QuoteService.calculateQuoteLinesTotal(null));
        Assert.areEqual(0, QuoteService.calculateQuoteLinesTotal(new List<QuoteLineItem>()));
        QuoteLineItem lineWithTotal = (QuoteLineItem) JSON.deserialize(
            '{"TotalPrice":20}',
            QuoteLineItem.class
        );
        Assert.areEqual(
            50,
            QuoteService.calculateQuoteLinesTotal(
                new List<QuoteLineItem>{
                    lineWithTotal,
                    new QuoteLineItem(Quantity = 3, UnitPrice = 10)
                }
            )
        );
    }

    @IsTest
    static void testResolveQuoteTotalWithoutFreight_WhenLinesOrField() {
        Assert.isNull(QuoteService.resolveQuoteTotalWithoutFreight(null, null));

        Quote quoteWithField = new Quote(Quote_Total_Without_Freight__c = 99);
        Assert.areEqual(
            99,
            QuoteService.resolveQuoteTotalWithoutFreight(quoteWithField, null)
        );
        QuoteLineItem pricedLine = (QuoteLineItem) JSON.deserialize(
            '{"TotalPrice":25}',
            QuoteLineItem.class
        );
        Assert.areEqual(
            25,
            QuoteService.resolveQuoteTotalWithoutFreight(
                quoteWithField,
                new List<QuoteLineItem>{ pricedLine }
            )
        );
    }

    @IsTest
    static void testResolveLastModifiedDate_WhenCustomOrStandard() {
        Datetime customDate = Datetime.now().addDays(-2);
        Quote withCustom = new Quote(LastModifiedDate__c = customDate);
        Assert.areEqual(customDate, QuoteService.resolveLastModifiedDate(withCustom));

        Quote withoutCustom = new Quote();
        Assert.isNull(QuoteService.resolveLastModifiedDate(withoutCustom));
    }

    @IsTest
    static void testPopulateAndApplyForecastConfidence_WhenGuardsAndHappyPath() {
        QuoteService.populateQuoteForecastConfidenceOnInsert(null);
        QuoteService.populateQuoteForecastConfidenceOnInsert(new List<Quote>());
        QuoteService.setAutomationDisabled(true);
        QuoteService.populateQuoteForecastConfidenceOnInsert(
            new List<Quote>{ new Quote(Name = 'Disabled') }
        );
        QuoteService.setAutomationDisabled(false);

        Opportunity opportunityRecord = getSetupOpportunity();
        Id hcSalesRecordTypeId = resolveHcSalesQuoteRecordTypeId();
        if (hcSalesRecordTypeId == null) {
            return;
        }

        // Prefer an Opp confidence value that this org/record type accepts.
        String usableOppConfidence = null;
        for (String candidate : new List<String>{
            'Upside',
            'Make It',
            'Won',
            'Lost',
            'Budget',
            'Pipeline'
        }) {
            try {
                update new Opportunity(
                    Id = opportunityRecord.Id,
                    ForecastConfidenceLevel__c = candidate
                );
                usableOppConfidence = candidate;
                opportunityRecord.ForecastConfidenceLevel__c = candidate;
                break;
            } catch (DmlException ignore) {
                // Restricted picklist / RT mismatch; try next candidate.
            }
        }

        Quote quoteRecord = new Quote(
            Name = 'Confidence Apply Quote',
            OpportunityId = opportunityRecord.Id,
            RecordTypeId = hcSalesRecordTypeId,
            Pricebook2Id = Test.getStandardPricebookId(),
            Status = QuoteSelector.OPEN_STATUS_VALUE
        );
        QuoteService.populateQuoteForecastConfidenceOnInsert(new List<Quote>{ quoteRecord });

        // In-memory Opp covers apply*() without depending on DML picklist validity.
        Opportunity confidenceSource = new Opportunity(
            ForecastConfidenceLevel__c = 'Make It'
        );
        Quote blankConfidenceQuote = new Quote(
            Name = 'Blank Confidence',
            OpportunityId = opportunityRecord.Id,
            RecordTypeId = hcSalesRecordTypeId
        );
        QuoteService.applyOpportunityForecastConfidenceIfBlank(null, confidenceSource);
        QuoteService.applyOpportunityForecastConfidenceIfBlank(blankConfidenceQuote, null);
        QuoteService.applyOpportunityForecastConfidenceIfBlank(
            blankConfidenceQuote,
            confidenceSource
        );
        Assert.areEqual('Make-It', blankConfidenceQuote.QuoteForecastConfidence__c);

        if (usableOppConfidence != null) {
            Assert.areEqual(
                QuoteService.mapOpportunityForecastConfidenceToQuote(usableOppConfidence),
                quoteRecord.QuoteForecastConfidence__c
            );
        }

        Quote ineligibleQuote = new Quote(
            RecordTypeId = hcSalesRecordTypeId,
            IsForecastIneligible__c = true
        );
        QuoteService.applyOpportunityForecastConfidenceIfBlank(ineligibleQuote, confidenceSource);
        Assert.isNull(ineligibleQuote.QuoteForecastConfidence__c);

        Quote alreadySet = new Quote(
            RecordTypeId = hcSalesRecordTypeId,
            QuoteForecastConfidence__c = 'Pipeline'
        );
        QuoteService.applyOpportunityForecastConfidenceIfBlank(alreadySet, confidenceSource);
        Assert.areEqual('Pipeline', alreadySet.QuoteForecastConfidence__c);
    }

    @IsTest
    static void testApplyStatusRulesBeforeSave_WhenInsertAndUpdate() {
        QuoteService.applyStatusRulesBeforeSave(null, null);
        QuoteService.applyStatusRulesBeforeSave(new List<Quote>(), null);
        QuoteService.setAutomationDisabled(true);
        QuoteService.applyStatusRulesBeforeSave(new List<Quote>{ new Quote() }, null);
        QuoteService.setAutomationDisabled(false);

        Opportunity opportunityRecord = getSetupOpportunity();
        Id hcSalesRecordTypeId = resolveHcSalesQuoteRecordTypeId();
        if (hcSalesRecordTypeId == null) {
            return;
        }

        Quote openQuote = new Quote(
            Name = 'FE Insert Open',
            OpportunityId = opportunityRecord.Id,
            RecordTypeId = hcSalesRecordTypeId,
            Pricebook2Id = opportunityRecord.Pricebook2Id,
            Status = QuoteSelector.OPEN_STATUS_VALUE,
            Forecast_Eligible__c = false,
            IsForecastIneligible__c = false,
            LastModifiedDate__c = Datetime.now().addDays(-3)
        );
        Quote draftQuote = new Quote(
            Name = 'FE Insert Draft',
            OpportunityId = opportunityRecord.Id,
            RecordTypeId = hcSalesRecordTypeId,
            Pricebook2Id = opportunityRecord.Pricebook2Id,
            Status = 'Draft',
            Forecast_Eligible__c = true,
            IsForecastIneligible__c = false
        );
        Quote ineligibleQuote = new Quote(
            Name = 'FE Insert Ineligible',
            OpportunityId = opportunityRecord.Id,
            RecordTypeId = hcSalesRecordTypeId,
            Pricebook2Id = opportunityRecord.Pricebook2Id,
            Status = QuoteSelector.OPEN_STATUS_VALUE,
            Forecast_Eligible__c = true,
            IsForecastIneligible__c = true
        );

        Test.startTest();
        QuoteService.applyStatusRulesBeforeSave(
            new List<Quote>{ openQuote, draftQuote, ineligibleQuote },
            null
        );
        Test.stopTest();

        Assert.isTrue(openQuote.Forecast_Eligible__c);
        Assert.isFalse(draftQuote.Forecast_Eligible__c);
        Assert.isFalse(ineligibleQuote.Forecast_Eligible__c);
    }

    @IsTest
    static void testApplyStatusRulesBeforeSave_WhenUpdateTransitions() {
        Opportunity opportunityRecord = getSetupOpportunity();
        Id hcSalesRecordTypeId = resolveHcSalesQuoteRecordTypeId();
        if (hcSalesRecordTypeId == null) {
            return;
        }

        Quote persistedQuote = new Quote(
            Name = 'FE Update Quote',
            OpportunityId = opportunityRecord.Id,
            RecordTypeId = hcSalesRecordTypeId,
            Pricebook2Id = opportunityRecord.Pricebook2Id,
            Status = 'Draft',
            Forecast_Eligible__c = false,
            ExpirationDate = Date.today().addDays(14)
        );
        insert persistedQuote;

        Quote updatedToOpen = [
            SELECT
                Id,
                OpportunityId,
                RecordTypeId,
                Status,
                Forecast_Eligible__c,
                IsForecastIneligible__c,
                LastModifiedDate__c,
                LastModifiedDate
            FROM Quote
            WHERE Id = :persistedQuote.Id
        ];
        Quote oldQuote = updatedToOpen.clone(true, true, true, true);
        updatedToOpen.Status = QuoteSelector.OPEN_STATUS_VALUE;

        Map<Id, Quote> oldMap = new Map<Id, Quote>{ oldQuote.Id => oldQuote };

        Test.startTest();
        QuoteService.applyStatusRulesBeforeSave(new List<Quote>{ updatedToOpen }, oldMap);
        Test.stopTest();

        Assert.isTrue(updatedToOpen.Forecast_Eligible__c);

        Quote leaveOpen = updatedToOpen.clone(true, true, true, true);
        leaveOpen.Status = 'Budget';
        leaveOpen.Forecast_Eligible__c = true;
        QuoteService.applyStatusRulesBeforeSave(
            new List<Quote>{ leaveOpen },
            new Map<Id, Quote>{ updatedToOpen.Id => updatedToOpen }
        );
        Assert.isFalse(leaveOpen.Forecast_Eligible__c);
    }

    @IsTest
    static void testSynchronizeForecastEligibleDesignation_WhenOpportunityHasQuotes() {
        QuoteService.synchronizeForecastEligibleDesignation(null);
        QuoteService.synchronizeForecastEligibleDesignation(new Set<Id>());

        Opportunity opportunityRecord = getSetupOpportunity();
        Id hcSalesRecordTypeId = resolveHcSalesQuoteRecordTypeId();
        if (hcSalesRecordTypeId == null) {
            return;
        }

        Quote olderOpen = new Quote(
            Name = 'FE Sync Older',
            OpportunityId = opportunityRecord.Id,
            RecordTypeId = hcSalesRecordTypeId,
            Pricebook2Id = opportunityRecord.Pricebook2Id,
            Status = QuoteSelector.OPEN_STATUS_VALUE,
            Forecast_Eligible__c = false,
            LastModifiedDate__c = Datetime.now().addDays(-10),
            ExpirationDate = Date.today().addDays(20)
        );
        Quote newerOpen = new Quote(
            Name = 'FE Sync Newer',
            OpportunityId = opportunityRecord.Id,
            RecordTypeId = hcSalesRecordTypeId,
            Pricebook2Id = opportunityRecord.Pricebook2Id,
            Status = QuoteSelector.OPEN_STATUS_VALUE,
            Forecast_Eligible__c = false,
            LastModifiedDate__c = Datetime.now().addDays(-1),
            ExpirationDate = Date.today().addDays(20)
        );
        insert new List<Quote>{ olderOpen, newerOpen };

        Test.startTest();
        QuoteService.synchronizeForecastEligibleDesignation(new Set<Id>{ opportunityRecord.Id });
        Test.stopTest();

        Map<Id, Quote> quotesById = new Map<Id, Quote>([
            SELECT Id, Forecast_Eligible__c
            FROM Quote
            WHERE Id IN :new Set<Id>{ olderOpen.Id, newerOpen.Id }
        ]);
        Assert.isTrue(quotesById.get(olderOpen.Id).Forecast_Eligible__c);
        Assert.isFalse(quotesById.get(newerOpen.Id).Forecast_Eligible__c);
    }

    @IsTest
    static void testHandleAfterEvents_WhenQuotesProvided() {
        Opportunity opportunityRecord = getSetupOpportunity();
        Id hcSalesRecordTypeId = resolveHcSalesQuoteRecordTypeId();
        if (hcSalesRecordTypeId == null) {
            return;
        }

        Quote quoteRecord = new Quote(
            Name = 'FE After Events',
            OpportunityId = opportunityRecord.Id,
            RecordTypeId = hcSalesRecordTypeId,
            Pricebook2Id = opportunityRecord.Pricebook2Id,
            Status = QuoteSelector.OPEN_STATUS_VALUE,
            Forecast_Eligible__c = true,
            ExpirationDate = Date.today().addDays(10)
        );
        insert quoteRecord;

        Quote afterInsertRow = [
            SELECT
                Id,
                OpportunityId,
                RecordTypeId,
                Status,
                Forecast_Eligible__c,
                IsForecastIneligible__c,
                QuoteType__c
            FROM Quote
            WHERE Id = :quoteRecord.Id
        ];

        Test.startTest();
        QuoteService.handleAfterInsert(new List<Quote>{ afterInsertRow });

        Quote oldRow = afterInsertRow.clone(true, true, true, true);
        afterInsertRow.Status = 'Budget';
        QuoteService.handleAfterUpdate(
            new List<Quote>{ afterInsertRow },
            new Map<Id, Quote>{ oldRow.Id => oldRow }
        );
        QuoteService.handleAfterDelete(new List<Quote>{ afterInsertRow });
        Test.stopTest();
    }

    @IsTest
    static void testSyncQuoteTotalWithoutFreightFromLines_WhenQuoteHasLines() {
        QuoteService.syncQuoteTotalWithoutFreightFromLines(null);
        QuoteService.syncQuoteTotalWithoutFreightFromLines(new Set<Id>());

        Quote quoteRecord = [
            SELECT Id, Quote_Total_Without_Freight__c
            FROM Quote
            WHERE Name = 'GW-3507 ApproveReject Quote'
            LIMIT 1
        ];

        Test.startTest();
        QuoteService.syncQuoteTotalWithoutFreightFromLines(new Set<Id>{ quoteRecord.Id });
        Test.stopTest();

        Quote refreshed = [
            SELECT Quote_Total_Without_Freight__c
            FROM Quote
            WHERE Id = :quoteRecord.Id
        ];
        Assert.areEqual(175, refreshed.Quote_Total_Without_Freight__c);
    }

    // --- Approve / Reject (call QuoteService directly) ---

    @IsTest
    static void testGetApproveRejectWorkspace_WhenWaitingQuoteProvided() {
        WorkOrder workOrder = [SELECT Id, WorkOrderNumber FROM WorkOrder LIMIT 1];

        Test.startTest();
        QuoteService.ApproveRejectWorkspace workspace =
            QuoteService.getApproveRejectWorkspace(workOrder.Id);
        Test.stopTest();

        Assert.areEqual(workOrder.Id, workspace.workOrderId);
        Assert.areEqual(workOrder.WorkOrderNumber, workspace.workOrderNumber);
        Assert.areEqual(1, workspace.lines.size());
        Assert.areEqual(STATUS_WAITING, workspace.quoteStatus);
        Assert.areEqual(75, workspace.estimateTotal);
    }

    @IsTest
    static void testGetApproveRejectWorkspace_WhenWorkOrderMissing_Throws() {
        Boolean threw = false;
        try {
            QuoteService.getApproveRejectWorkspace(null);
        } catch (QuoteService.ApproveRejectException e) {
            threw = true;
        }
        Assert.isTrue(threw);
    }

    @IsTest
    static void testSaveApproveRejectDecisions_WhenPartialApprove() {
        WorkOrder workOrder = [SELECT Id FROM WorkOrder LIMIT 1];
        QuoteLineItem productServicedLine = [
            SELECT Id
            FROM QuoteLineItem
            WHERE LineType__c = 'Product Serviced'
            LIMIT 1
        ];

        QuoteService.ApproveRejectDecision decision = new QuoteService.ApproveRejectDecision();
        decision.quoteLineItemId = productServicedLine.Id;
        decision.status = STATUS_APPROVED;

        Test.startTest();
        QuoteService.ApproveRejectWorkspace workspace = QuoteService.saveApproveRejectDecisions(
            workOrder.Id,
            new List<QuoteService.ApproveRejectDecision>{ decision }
        );
        Test.stopTest();

        Assert.areEqual(STATUS_APPROVED, workspace.quoteStatus);
        Assert.areEqual(STATUS_APPROVED, workspace.lines[0].selectedDecision);
    }

    @IsTest
    static void testSaveApproveRejectDecisions_WhenRejectAll() {
        WorkOrder workOrder = [SELECT Id FROM WorkOrder LIMIT 1];
        QuoteLineItem productServicedLine = [
            SELECT Id
            FROM QuoteLineItem
            WHERE LineType__c = 'Product Serviced'
            LIMIT 1
        ];

        QuoteService.ApproveRejectDecision decision = new QuoteService.ApproveRejectDecision();
        decision.quoteLineItemId = productServicedLine.Id;
        decision.status = STATUS_REJECTED;

        Test.startTest();
        QuoteService.ApproveRejectWorkspace workspace = QuoteService.saveApproveRejectDecisions(
            workOrder.Id,
            new List<QuoteService.ApproveRejectDecision>{ decision }
        );
        Test.stopTest();

        Assert.areEqual(STATUS_REJECTED, workspace.quoteStatus);
    }

    @IsTest
    static void testSaveApproveRejectComment_WhenCommentsProvided() {
        QuoteLineItem productServicedLine = [
            SELECT Id
            FROM QuoteLineItem
            WHERE LineType__c = 'Product Serviced'
            LIMIT 1
        ];

        Test.startTest();
        String saved = QuoteService.saveApproveRejectComment(
            productServicedLine.Id,
            'Customer approved by phone'
        );
        Test.stopTest();

        Assert.areEqual('Customer approved by phone', saved);
    }

    @IsTest
    static void testSaveApproveRejectComment_WhenLineMissing_Throws() {
        Boolean threw = false;
        try {
            QuoteService.saveApproveRejectComment(null, 'x');
        } catch (QuoteService.ApproveRejectException e) {
            threw = true;
        }
        Assert.isTrue(threw);
    }
}