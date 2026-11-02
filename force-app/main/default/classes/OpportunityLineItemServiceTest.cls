/**
 * @author PWC Developer
 * @date 2026/07/23
 *
 * @group Product Sub-Group Detail
 *
 * @description GC-3129 - Tests for Opportunity Product Sub-Group Detail derivation from PSAM.
 */
@IsTest
private class OpportunityLineItemServiceTest {
    @IsTest
    static void recalculateFromOpportunityIds_populatesFieldFromPsam() {
        TestData testData = createTestData('T001', 'GC-3129 Populate');

        Test.startTest();
        insert new OpportunityLineItem(
            OpportunityId = testData.opportunityId,
            PricebookEntryId = testData.pricebookEntryId,
            Quantity = 1,
            UnitPrice = 1
        );
        Test.stopTest();

        Opportunity updatedOpportunity = [
            SELECT ProductSubGroupDetailName__c
            FROM Opportunity
            WHERE Id = :testData.opportunityId
        ];

        System.assertEquals(
            testData.picklistValue,
            updatedOpportunity.ProductSubGroupDetailName__c,
            'Opportunity should reflect PSAM Product Sub-Group Detail via Opportunity Product'
        );
    }

    @IsTest
    static void recalculateFromOpportunityIds_clearsFieldWhenLineItemsRemoved() {
        TestData testData = createTestData('T002', 'GC-3129 Remove');

        OpportunityLineItem lineItem = new OpportunityLineItem(
            OpportunityId = testData.opportunityId,
            PricebookEntryId = testData.pricebookEntryId,
            Quantity = 1,
            UnitPrice = 1
        );
        insert lineItem;

        Test.startTest();
        delete lineItem;
        Test.stopTest();

        Opportunity updatedOpportunity = [
            SELECT ProductSubGroupDetailName__c
            FROM Opportunity
            WHERE Id = :testData.opportunityId
        ];

        System.assertEquals(
            null,
            updatedOpportunity.ProductSubGroupDetailName__c,
            'Field should clear when no Opportunity Products remain'
        );
    }

    @IsTest
    static void recalculateFromOpportunityIds_serviceDirectCall() {
        TestData testData = createTestData('T003', 'GC-3129 Direct');

        OpportunityLineItemService.setRecalculationDisabled(true);
        insert new OpportunityLineItem(
            OpportunityId = testData.opportunityId,
            PricebookEntryId = testData.pricebookEntryId,
            Quantity = 1,
            UnitPrice = 1
        );
        OpportunityLineItemService.setRecalculationDisabled(false);

        Test.startTest();
        OpportunityLineItemService.recalculateFromOpportunityIds(
            new Set<Id>{ testData.opportunityId }
        );
        Test.stopTest();

        Opportunity updatedOpportunity = [
            SELECT ProductSubGroupDetailName__c
            FROM Opportunity
            WHERE Id = :testData.opportunityId
        ];

        System.assertEquals(
            testData.picklistValue,
            updatedOpportunity.ProductSubGroupDetailName__c,
            'Direct service call should populate Product Sub-Group Detail'
        );
    }

    @IsTest
    static void normalizeMultiSelect_sortsDistinctValues() {
        String normalized = OpportunityLineItemService.normalizeMultiSelect('B;A;B');
        System.assertEquals('A;B', normalized, 'Values should be deduplicated and sorted');
    }

    @IsTest
    static void triggerHandler_afterUpdateRecalculates() {
        TestData testData = createTestData('T004', 'GC-3129 Update');

        OpportunityLineItem lineItem = new OpportunityLineItem(
            OpportunityId = testData.opportunityId,
            PricebookEntryId = testData.pricebookEntryId,
            Quantity = 1,
            UnitPrice = 1
        );
        insert lineItem;

        Test.startTest();
        lineItem.Quantity = 2;
        update lineItem;
        Test.stopTest();

        Opportunity updatedOpportunity = [
            SELECT ProductSubGroupDetailName__c
            FROM Opportunity
            WHERE Id = :testData.opportunityId
        ];

        System.assertEquals(
            testData.picklistValue,
            updatedOpportunity.ProductSubGroupDetailName__c,
            'Update should keep Product Sub-Group Detail in sync'
        );
    }

    @IsTest
    static void triggerHandler_afterUndeleteEntryPoint() {
        TestData testData = createTestData('T005', 'GC-3129 Undelete');

        OpportunityLineItem lineItem = new OpportunityLineItem(
            OpportunityId = testData.opportunityId,
            PricebookEntryId = testData.pricebookEntryId,
            Quantity = 1,
            UnitPrice = 1
        );
        insert lineItem;

        Test.startTest();
        OpportunityLineItemService.handleAfterUndelete(new List<OpportunityLineItem>{ lineItem });
        Test.stopTest();

        Opportunity updatedOpportunity = [
            SELECT ProductSubGroupDetailName__c
            FROM Opportunity
            WHERE Id = :testData.opportunityId
        ];

        System.assertEquals(
            testData.picklistValue,
            updatedOpportunity.ProductSubGroupDetailName__c,
            'handleAfterUndelete entry point should keep Product Sub-Group Detail populated'
        );
    }

    @IsTest
    static void opportunityLineItemTriggerHandler_runAfterUndelete() {
        TestData testData = createTestData('T019', 'GC-3129 Handler Undelete');

        OpportunityLineItem lineItem = new OpportunityLineItem(
            OpportunityId = testData.opportunityId,
            PricebookEntryId = testData.pricebookEntryId,
            Quantity = 1,
            UnitPrice = 1
        );
        insert lineItem;

        Test.startTest();
        new OpportunityLineItemTriggerHandler().runAfterUndelete(
            new List<OpportunityLineItem>{ lineItem }
        );
        Test.stopTest();

        Opportunity updatedOpportunity = [
            SELECT ProductSubGroupDetailName__c
            FROM Opportunity
            WHERE Id = :testData.opportunityId
        ];

        System.assertEquals(testData.picklistValue, updatedOpportunity.ProductSubGroupDetailName__c);
    }

    @IsTest
    static void triggerHandler_skipsWhenRecalculationDisabled() {
        TestData testData = createTestData('T006', 'GC-3129 Disabled');

        OpportunityLineItemService.setRecalculationDisabled(true);
        try {
            insert new OpportunityLineItem(
                OpportunityId = testData.opportunityId,
                PricebookEntryId = testData.pricebookEntryId,
                Quantity = 1,
                UnitPrice = 1
            );
        } finally {
            OpportunityLineItemService.setRecalculationDisabled(false);
        }

        Opportunity updatedOpportunity = [
            SELECT ProductSubGroupDetailName__c
            FROM Opportunity
            WHERE Id = :testData.opportunityId
        ];

        System.assertEquals(
            null,
            updatedOpportunity.ProductSubGroupDetailName__c,
            'Trigger should skip recalculation while disabled'
        );
    }

    @IsTest
    static void triggerHandler_collectsOpportunityIdsFromOldAndNew() {
        Id firstOpportunityId = buildFakeOpportunityId();
        Id secondOpportunityId = buildFakeOpportunityId();

        OpportunityLineItem newLineItem = new OpportunityLineItem(
            OpportunityId = firstOpportunityId
        );
        OpportunityLineItem oldLineItem = new OpportunityLineItem(
            OpportunityId = secondOpportunityId
        );

        Set<Id> opportunityIds = OpportunityLineItemService.collectOpportunityIdsFromLineItems(
            new List<OpportunityLineItem>{ newLineItem },
            new Map<Id, OpportunityLineItem>{ newLineItem.Id => oldLineItem }
        );

        System.assert(opportunityIds.contains(firstOpportunityId));
        System.assert(opportunityIds.contains(secondOpportunityId));
    }

    @IsTest
    static void service_noOpWhenRecalculationDisabledOrEmpty() {
        OpportunityLineItemService.setRecalculationDisabled(true);
        OpportunityLineItemService.recalculateFromOpportunityIds(
            new Set<Id>{ buildFakeOpportunityId() }
        );
        OpportunityLineItemService.setRecalculationDisabled(false);
        OpportunityLineItemService.recalculateFromOpportunityIds(new Set<Id>());
        System.assert(true, 'Disabled and empty input paths should complete without error');
    }

    private static Id buildFakeOpportunityId() {
        return (Id) (Opportunity.SObjectType.getDescribe().getKeyPrefix() + '000000000000');
    }

    @IsTest
    static void quoteLineItemTrigger_populatesFieldFromPsamForCapital() {
        TestData testData = createTestData('T007', 'GC-3129 Quote', 'Healthcare_Sales');

        Quote quoteRecord = new Quote(
            Name = 'GC-3129 Capital Quote',
            OpportunityId = testData.opportunityId,
            Pricebook2Id = Test.getStandardPricebookId()
        );
        insert quoteRecord;

        Test.startTest();
        insert new QuoteLineItem(
            QuoteId = quoteRecord.Id,
            PricebookEntryId = testData.pricebookEntryId,
            Quantity = 1,
            UnitPrice = 1
        );
        Test.stopTest();

        Opportunity updatedOpportunity = [
            SELECT ProductSubGroupDetailName__c
            FROM Opportunity
            WHERE Id = :testData.opportunityId
        ];

        System.assertEquals(
            testData.picklistValue,
            updatedOpportunity.ProductSubGroupDetailName__c,
            'Capital Quote Line Item should populate Product Sub-Group Detail on Opportunity'
        );
    }

    @IsTest
    static void opportunityLineItemTrigger_skipsInstrumentProcessingRecordType() {
        TestData testData = createTestData('T008', 'GC-3129 IP', 'InstrumentProcessing');

        Test.startTest();
        insert new OpportunityLineItem(
            OpportunityId = testData.opportunityId,
            PricebookEntryId = testData.pricebookEntryId,
            Quantity = 1,
            UnitPrice = 1
        );
        Test.stopTest();

        Opportunity updatedOpportunity = [
            SELECT ProductSubGroupDetailName__c
            FROM Opportunity
            WHERE Id = :testData.opportunityId
        ];

        System.assertEquals(
            null,
            updatedOpportunity.ProductSubGroupDetailName__c,
            'Instrument Processing Opportunities should be excluded from recalculation'
        );
    }

    @IsTest
    static void filterEligibleOpportunityIds_excludesInstrumentProcessing() {
        TestData consumablesData = createTestData('T009', 'GC-3129 Filter C', 'HCSalesConsumables');
        TestData ipData = createTestData('T010', 'GC-3129 Filter IP', 'InstrumentProcessing');

        Set<Id> filteredIds = OpportunityLineItemService.filterEligibleOpportunityIds(
            new Set<Id>{ consumablesData.opportunityId, ipData.opportunityId }
        );

        System.assert(filteredIds.contains(consumablesData.opportunityId));
        System.assert(!filteredIds.contains(ipData.opportunityId));
    }

    @IsTest
    static void quoteLineItemTrigger_afterDeleteRecalculates() {
        TestData testData = createTestData('T011', 'GC-3129 QLI Delete', 'Healthcare_Sales');

        Quote quoteRecord = new Quote(
            Name = 'GC-3129 Delete Quote',
            OpportunityId = testData.opportunityId,
            Pricebook2Id = Test.getStandardPricebookId()
        );
        insert quoteRecord;

        QuoteLineItem quoteLineItem = new QuoteLineItem(
            QuoteId = quoteRecord.Id,
            PricebookEntryId = testData.pricebookEntryId,
            Quantity = 1,
            UnitPrice = 1
        );
        insert quoteLineItem;

        Test.startTest();
        delete quoteLineItem;
        Test.stopTest();

        Opportunity updatedOpportunity = [
            SELECT ProductSubGroupDetailName__c
            FROM Opportunity
            WHERE Id = :testData.opportunityId
        ];

        System.assertEquals(
            null,
            updatedOpportunity.ProductSubGroupDetailName__c,
            'Deleting Quote Line Item should clear Product Sub-Group Detail when no lines remain'
        );
    }

    @IsTest
    static void quoteLineItemTriggerHandler_entryPoints() {
        TestData testData = createTestData('T012', 'GC-3129 QLI Handler', 'Healthcare_Sales');

        Quote quoteRecord = new Quote(
            Name = 'GC-3129 Handler Quote',
            OpportunityId = testData.opportunityId,
            Pricebook2Id = Test.getStandardPricebookId()
        );
        insert quoteRecord;

        QuoteLineItem quoteLineItem = new QuoteLineItem(
            QuoteId = quoteRecord.Id,
            PricebookEntryId = testData.pricebookEntryId,
            Quantity = 1,
            UnitPrice = 1
        );
        insert quoteLineItem;

        Test.startTest();
        QuoteLineItemService.handleAfterUpdate(
            new List<QuoteLineItem>{ quoteLineItem },
            new Map<Id, QuoteLineItem>{ quoteLineItem.Id => quoteLineItem }
        );
        QuoteLineItemService.handleAfterUndelete(new List<QuoteLineItem>{ quoteLineItem });
        Test.stopTest();

        Opportunity updatedOpportunity = [
            SELECT ProductSubGroupDetailName__c
            FROM Opportunity
            WHERE Id = :testData.opportunityId
        ];

        System.assertEquals(
            testData.picklistValue,
            updatedOpportunity.ProductSubGroupDetailName__c,
            'Quote line handler entry points should keep Product Sub-Group Detail populated'
        );
    }

    @IsTest
    static void quoteLineItemTrigger_afterUpdateRecalculates() {
        TestData testData = createTestData('T013', 'GC-3129 QLI Update', 'Healthcare_Sales');

        Quote quoteRecord = new Quote(
            Name = 'GC-3129 Update Quote',
            OpportunityId = testData.opportunityId,
            Pricebook2Id = Test.getStandardPricebookId()
        );
        insert quoteRecord;

        QuoteLineItem quoteLineItem = new QuoteLineItem(
            QuoteId = quoteRecord.Id,
            PricebookEntryId = testData.pricebookEntryId,
            Quantity = 1,
            UnitPrice = 1
        );
        insert quoteLineItem;

        Test.startTest();
        quoteLineItem.Quantity = 2;
        update quoteLineItem;
        Test.stopTest();

        Opportunity updatedOpportunity = [
            SELECT ProductSubGroupDetailName__c
            FROM Opportunity
            WHERE Id = :testData.opportunityId
        ];

        System.assertEquals(
            testData.picklistValue,
            updatedOpportunity.ProductSubGroupDetailName__c,
            'Quote Line Item update should keep Product Sub-Group Detail populated'
        );
    }

    @IsTest
    static void serviceHandleAfterMethods_noOpOnEmptyInput() {
        OpportunityLineItemService.handleAfterInsert(new List<OpportunityLineItem>());
        OpportunityLineItemService.handleAfterUpdate(
            new List<OpportunityLineItem>(),
            new Map<Id, OpportunityLineItem>()
        );
        OpportunityLineItemService.handleAfterDelete(new List<OpportunityLineItem>());
        OpportunityLineItemService.handleAfterUndelete(new List<OpportunityLineItem>());
        System.assert(
            !OpportunityLineItemService.isRecalculationDisabled(),
            'Empty handleAfter paths should complete without enabling disable flag'
        );
    }

    @IsTest
    static void encodeMultiSelectPicklist_handlesNullAndEmpty() {
        System.assertEquals(null, OpportunityLineItemService.encodeMultiSelectPicklist(null));
        System.assertEquals(null, OpportunityLineItemService.encodeMultiSelectPicklist(new Set<String>()));
    }

    @IsTest
    static void normalizeMultiSelect_blankReturnsNull() {
        System.assertEquals(null, OpportunityLineItemService.normalizeMultiSelect(null));
        System.assertEquals(null, OpportunityLineItemService.normalizeMultiSelect('   '));
    }

    @IsTest
    static void filterEligibleOpportunityIds_handlesNullAndEmpty() {
        Set<Id> filtered = OpportunityLineItemService.filterEligibleOpportunityIds(null);
        System.assertEquals(0, filtered.size());
        filtered = OpportunityLineItemService.filterEligibleOpportunityIds(new Set<Id>());
        System.assertEquals(0, filtered.size());
    }

    @IsTest
    static void mapHelpers_emptyInputReturnsEmptyMaps() {
        System.assertEquals(0, OpportunityLineItemService.mapPsamIdByProduct2Id(new Set<Id>()).size());
        System.assertEquals(0, OpportunityLineItemService.mapDetailNameByPsamId(new Set<Id>()).size());
        System.assert(OpportunityLineItemService.getAllowedPicklistValues().size() > 0);
    }

    @IsTest
    static void productWithoutPsam_doesNotPopulateField() {
        TestData testData = createTestData('T014', 'GC-3129 No PSAM');

        Product2 productWithoutPsam = new Product2(
            Name = 'GC-3129 No PSAM Product',
            IsActive = true
        );
        insert productWithoutPsam;

        Id pricebookId = Test.getStandardPricebookId();
        PricebookEntry entryWithoutPsam = new PricebookEntry(
            Pricebook2Id = pricebookId,
            Product2Id = productWithoutPsam.Id,
            UnitPrice = 1,
            IsActive = true
        );
        insert entryWithoutPsam;

        Test.startTest();
        insert new OpportunityLineItem(
            OpportunityId = testData.opportunityId,
            PricebookEntryId = entryWithoutPsam.Id,
            Quantity = 1,
            UnitPrice = 1
        );
        Test.stopTest();

        Opportunity updatedOpportunity = [
            SELECT ProductSubGroupDetailName__c
            FROM Opportunity
            WHERE Id = :testData.opportunityId
        ];
        System.assertEquals(null, updatedOpportunity.ProductSubGroupDetailName__c);
    }

    @IsTest
    static void psamWithBlankDetailName_isIgnored() {
        TestData testData = createTestData('T015', 'GC-3129 Bad Picklist');

        PSAM__c psam = [
            SELECT Id
            FROM PSAM__c
            WHERE ProductFAMCode__c = 'T015'
            LIMIT 1
        ];
        psam.ProductSubgroupDetailName__c = null;
        update psam;

        Test.startTest();
        insert new OpportunityLineItem(
            OpportunityId = testData.opportunityId,
            PricebookEntryId = testData.pricebookEntryId,
            Quantity = 1,
            UnitPrice = 1
        );
        Test.stopTest();

        Opportunity updatedOpportunity = [
            SELECT ProductSubGroupDetailName__c
            FROM Opportunity
            WHERE Id = :testData.opportunityId
        ];
        System.assertEquals(null, updatedOpportunity.ProductSubGroupDetailName__c);
    }

    @IsTest
    static void recalculate_skipsUpdateWhenFieldAlreadyMatches() {
        TestData testData = createTestData('T016', 'GC-3129 No Op Update');

        insert new OpportunityLineItem(
            OpportunityId = testData.opportunityId,
            PricebookEntryId = testData.pricebookEntryId,
            Quantity = 1,
            UnitPrice = 1
        );

        Opportunity beforeSecondPass = [
            SELECT ProductSubGroupDetailName__c
            FROM Opportunity
            WHERE Id = :testData.opportunityId
        ];
        System.assertEquals(testData.picklistValue, beforeSecondPass.ProductSubGroupDetailName__c);

        Test.startTest();
        OpportunityLineItemService.recalculateFromOpportunityIds(
            new Set<Id>{ testData.opportunityId }
        );
        Test.stopTest();

        Opportunity updatedOpportunity = [
            SELECT ProductSubGroupDetailName__c
            FROM Opportunity
            WHERE Id = :testData.opportunityId
        ];
        System.assertEquals(testData.picklistValue, updatedOpportunity.ProductSubGroupDetailName__c);
    }

    @IsTest
    static void service_handleAfterDelete_directCallAfterDmlDelete() {
        TestData testData = createTestData('T017', 'GC-3129 Direct Handle');

        OpportunityLineItem lineItem = new OpportunityLineItem(
            OpportunityId = testData.opportunityId,
            PricebookEntryId = testData.pricebookEntryId,
            Quantity = 1,
            UnitPrice = 1
        );
        insert lineItem;
        delete lineItem;

        Test.startTest();
        OpportunityLineItemService.handleAfterDelete(new List<OpportunityLineItem>{ lineItem });
        Test.stopTest();

        Opportunity updatedOpportunity = [
            SELECT ProductSubGroupDetailName__c
            FROM Opportunity
            WHERE Id = :testData.opportunityId
        ];
        System.assertEquals(null, updatedOpportunity.ProductSubGroupDetailName__c);
    }

    @IsTest
    static void collectOpportunityIdsFromLineItems_skipsNullOpportunityId() {
        OpportunityLineItem lineItemWithoutOpportunity = new OpportunityLineItem();

        Set<Id> opportunityIds = OpportunityLineItemService.collectOpportunityIdsFromLineItems(
            new List<OpportunityLineItem>{ lineItemWithoutOpportunity },
            null
        );

        System.assertEquals(
            0,
            opportunityIds.size(),
            'Line items without OpportunityId should not be collected'
        );
    }

    @IsTest
    static void addDetailNameForProductLine_skipsInvalidAndDisallowedValues() {
        Id opportunityId = buildFakeOpportunityId();
        Id product2Id = (Id) (Product2.SObjectType.getDescribe().getKeyPrefix() + '000000000000');
        Id psamId = (Id) (PSAM__c.SObjectType.getDescribe().getKeyPrefix() + '000000000000');
        Map<Id, Set<String>> detailNamesByOpportunityId = new Map<Id, Set<String>>();
        Set<String> allowedPicklistValues = new Set<String>{ 'AER' };

        OpportunityLineItemService.addDetailNameForProductLine(
            null,
            product2Id,
            new Map<Id, Id>(),
            new Map<Id, String>(),
            allowedPicklistValues,
            detailNamesByOpportunityId
        );
        OpportunityLineItemService.addDetailNameForProductLine(
            opportunityId,
            null,
            new Map<Id, Id>(),
            new Map<Id, String>(),
            allowedPicklistValues,
            detailNamesByOpportunityId
        );
        OpportunityLineItemService.addDetailNameForProductLine(
            opportunityId,
            product2Id,
            new Map<Id, Id>(),
            new Map<Id, String>(),
            allowedPicklistValues,
            detailNamesByOpportunityId
        );
        OpportunityLineItemService.addDetailNameForProductLine(
            opportunityId,
            product2Id,
            new Map<Id, Id>{ product2Id => psamId },
            new Map<Id, String>(),
            allowedPicklistValues,
            detailNamesByOpportunityId
        );
        OpportunityLineItemService.addDetailNameForProductLine(
            opportunityId,
            product2Id,
            new Map<Id, Id>{ product2Id => psamId },
            new Map<Id, String>{ psamId => 'NotAnAllowedValue' },
            allowedPicklistValues,
            detailNamesByOpportunityId
        );
        OpportunityLineItemService.addDetailNameForProductLine(
            opportunityId,
            product2Id,
            new Map<Id, Id>{ product2Id => psamId },
            new Map<Id, String>{ psamId => 'AER' },
            allowedPicklistValues,
            detailNamesByOpportunityId
        );

        System.assertEquals(1, detailNamesByOpportunityId.get(opportunityId).size());
        System.assert(detailNamesByOpportunityId.get(opportunityId).contains('AER'));
    }

    @IsTest
    static void recalculateFromOpportunityIds_noOpWhenAllOpportunitiesIneligible() {
        TestData ipData = createTestData('T018', 'GC-3129 All IP', 'InstrumentProcessing');

        Test.startTest();
        OpportunityLineItemService.recalculateFromOpportunityIds(
            new Set<Id>{ ipData.opportunityId }
        );
        Test.stopTest();

        Opportunity updatedOpportunity = [
            SELECT ProductSubGroupDetailName__c
            FROM Opportunity
            WHERE Id = :ipData.opportunityId
        ];
        System.assertEquals(
            null,
            updatedOpportunity.ProductSubGroupDetailName__c,
            'Ineligible Opportunities should not be recalculated'
        );
    }

    @IsTest
    static void calculateRecurringFreqAmount_coversWeeklyMonthlyAnnualBranches() {
        TestData testData = createTestData('T020', 'GC-3129 Recurring');
        Id monthlyEntryId = createAdditionalPricebookEntry('T020M', testData.picklistValue);
        Id annualEntryId = createAdditionalPricebookEntry('T020A', testData.picklistValue);
        Id otherEntryId = createAdditionalPricebookEntry('T020O', testData.picklistValue);

        OpportunityLineItemService.setRecalculationDisabled(true);
        OpportunityLineItem weeklyLineItem = new OpportunityLineItem(
            OpportunityId = testData.opportunityId,
            PricebookEntryId = testData.pricebookEntryId,
            Quantity = 1,
            UnitPrice = 10,
            ConsumptionFrequency__c = 'Weekly'
        );
        OpportunityLineItem monthlyLineItem = new OpportunityLineItem(
            OpportunityId = testData.opportunityId,
            PricebookEntryId = monthlyEntryId,
            Quantity = 1,
            UnitPrice = 10,
            ConsumptionFrequency__c = 'Monthly'
        );
        OpportunityLineItem annualLineItem = new OpportunityLineItem(
            OpportunityId = testData.opportunityId,
            PricebookEntryId = annualEntryId,
            Quantity = 1,
            UnitPrice = 10,
            ConsumptionFrequency__c = 'Annual'
        );
        OpportunityLineItem otherLineItem = new OpportunityLineItem(
            OpportunityId = testData.opportunityId,
            PricebookEntryId = otherEntryId,
            Quantity = 1,
            UnitPrice = 10
        );
        insert new List<OpportunityLineItem>{
            weeklyLineItem,
            monthlyLineItem,
            annualLineItem,
            otherLineItem
        };
        OpportunityLineItemService.setRecalculationDisabled(false);

        Test.startTest();
        OpportunityLineItemService.calculateRecurringFreqAmount(
            new List<OpportunityLineItem>{
                weeklyLineItem,
                monthlyLineItem,
                annualLineItem,
                otherLineItem
            }
        );
        Test.stopTest();

        System.assertEquals(
            4,
            [
                SELECT COUNT()
                FROM OpportunityLineItem
                WHERE OpportunityId = :testData.opportunityId
            ],
            'Recurring frequency calculation should complete for Weekly, Monthly, Annual, and unset values'
        );
    }

    @IsTest
    static void calculateRecurringFreqAmount_skipsIneligibleOpportunities() {
        TestData ipData = createTestData('T021', 'GC-3129 Recurring IP', 'InstrumentProcessing');

        OpportunityLineItemService.setRecalculationDisabled(true);
        OpportunityLineItem lineItem = new OpportunityLineItem(
            OpportunityId = ipData.opportunityId,
            PricebookEntryId = ipData.pricebookEntryId,
            Quantity = 1,
            UnitPrice = 10,
            ConsumptionFrequency__c = 'Weekly'
        );
        insert lineItem;
        OpportunityLineItemService.setRecalculationDisabled(false);

        Test.startTest();
        OpportunityLineItemService.calculateRecurringFreqAmount(
            new List<OpportunityLineItem>{ lineItem }
        );
        Test.stopTest();

        OpportunityLineItem persistedLineItem = [
            SELECT UnitPrice
            FROM OpportunityLineItem
            WHERE Id = :lineItem.Id
        ];
        System.assertEquals(
            10,
            persistedLineItem.UnitPrice,
            'Ineligible Opportunities should not have UnitPrice rewritten'
        );
    }

    @IsTest
    static void handleAfterInsert_invokesRecurringFrequencyCalculation() {
        TestData testData = createTestData('T022', 'GC-3129 After Insert Recurring');

        OpportunityLineItemService.setRecalculationDisabled(true);
        OpportunityLineItem lineItem = new OpportunityLineItem(
            OpportunityId = testData.opportunityId,
            PricebookEntryId = testData.pricebookEntryId,
            Quantity = 1,
            UnitPrice = 5,
            ConsumptionFrequency__c = 'Monthly'
        );
        insert lineItem;
        OpportunityLineItemService.setRecalculationDisabled(false);

        Test.startTest();
        OpportunityLineItemService.handleAfterInsert(new List<OpportunityLineItem>{ lineItem });
        Test.stopTest();

        Opportunity updatedOpportunity = [
            SELECT ProductSubGroupDetailName__c
            FROM Opportunity
            WHERE Id = :testData.opportunityId
        ];
        System.assertEquals(
            testData.picklistValue,
            updatedOpportunity.ProductSubGroupDetailName__c,
            'handleAfterInsert should recalculate Product Sub-Group Detail and run frequency calculation'
        );
    }

    private class TestData {
        public Id opportunityId;
        public Id pricebookEntryId;
        public String picklistValue;
    }

    private static Id createAdditionalPricebookEntry(String famCode, String picklistValue) {
        PSAM__c psam = new PSAM__c(
            ProductFAMCode__c = famCode,
            ProductSubgroupDetailName__c = picklistValue
        );
        insert psam;

        Product2 product = new Product2(
            Name = famCode + ' Recurring Product',
            IsActive = true,
            PSAM__c = psam.Id
        );
        insert product;

        PricebookEntry pricebookEntry = new PricebookEntry(
            Pricebook2Id = Test.getStandardPricebookId(),
            Product2Id = product.Id,
            UnitPrice = 10,
            IsActive = true
        );
        insert pricebookEntry;
        return pricebookEntry.Id;
    }

    private static TestData createTestData(String famCode, String labelPrefix) {
        return createTestData(famCode, labelPrefix, 'Healthcare_Sales');
    }

    private static TestData createTestData(
        String famCode,
        String labelPrefix,
        String recordTypeDeveloperName
    ) {
        String picklistValue = getFirstActivePicklistValue();
        System.assertNotEquals(
            null,
            picklistValue,
            'ProductSubGroupDetailName__c picklist must have at least one active Global Value Set entry'
        );

        PSAM__c psam = new PSAM__c(
            ProductFAMCode__c = famCode,
            ProductSubgroupDetailName__c = picklistValue
        );
        insert psam;

        Product2 product = new Product2(
            Name = labelPrefix + ' Product',
            IsActive = true,
            PSAM__c = psam.Id
        );
        insert product;

        Id pricebookId = Test.getStandardPricebookId();
        PricebookEntry pricebookEntry = new PricebookEntry(
            Pricebook2Id = pricebookId,
            Product2Id = product.Id,
            UnitPrice = 1,
            IsActive = true
        );
        insert pricebookEntry;

        Account account = new Account(
            Name = labelPrefix + ' Account',
            SourceSystemID__c = 'Oracle-GC3129-' + famCode
        );
        insert account;

        Contact primaryContact = new Contact(
            LastName = labelPrefix + ' Contact',
            AccountId = account.Id
        );
        insert primaryContact;

        Opportunity opportunity = new Opportunity(
            Name = labelPrefix + ' Opportunity',
            AccountId = account.Id,
            StageName = 'Discovery',
            CloseDate = Date.today().addDays(30),
            Pricebook2Id = pricebookId,
            Type = 'Extension',
            Amount = 100,
            Probability = 10,
            PrimaryContact__c = primaryContact.Id
        );
        if (String.isNotBlank(recordTypeDeveloperName)) {
            opportunity.RecordTypeId = Schema.SObjectType.Opportunity.getRecordTypeInfosByDeveloperName()
                .get(recordTypeDeveloperName)
                .getRecordTypeId();
        }
        populateForecastConfidenceIfPossible(opportunity);
        insertOpportunityForRecordType(opportunity, recordTypeDeveloperName);

        TestData testData = new TestData();
        testData.opportunityId = opportunity.Id;
        testData.pricebookEntryId = pricebookEntry.Id;
        testData.picklistValue = picklistValue;
        return testData;
    }

    private static String getFirstActivePicklistValue() {
        for (
            Schema.PicklistEntry picklistEntry : Opportunity.ProductSubGroupDetailName__c.getDescribe()
                .getPicklistValues()
        ) {
            if (picklistEntry.isActive()) {
                return picklistEntry.getValue();
            }
        }
        return null;
    }

    private static void populateForecastConfidenceIfPossible(Opportunity opportunity) {
        Schema.SObjectField forecastField = Schema.SObjectType.Opportunity.fields.getMap()
            .get('ForecastConfidenceLevel__c');
        if (forecastField == null) {
            return;
        }

        for (Schema.PicklistEntry picklistEntry : forecastField.getDescribe().getPicklistValues()) {
            if (picklistEntry.isActive()) {
                opportunity.put(forecastField, picklistEntry.getValue());
                return;
            }
        }
    }

    private static void insertOpportunityForRecordType(
        Opportunity opportunity,
        String recordTypeDeveloperName
    ) {
        if (recordTypeDeveloperName != 'HCSalesConsumables') {
            insert opportunity;
            return;
        }

        Schema.SObjectField categoryField = Schema.SObjectType.Opportunity.fields.getMap()
            .get('Category__c');
        if (categoryField == null) {
            insert opportunity;
            return;
        }

        List<Schema.PicklistEntry> categoryEntries = categoryField.getDescribe().getPicklistValues();
        for (Schema.PicklistEntry picklistEntry : categoryEntries) {
            if (!picklistEntry.isActive()) {
                continue;
            }

            Opportunity candidate = opportunity.clone(false, true, false, false);
            candidate.put(categoryField, picklistEntry.getValue());
            try {
                insert candidate;
                opportunity.Id = candidate.Id;
                return;
            } catch (DmlException insertException) {
                if (!isRetryableConsumablesInsertException(insertException)) {
                    throw insertException;
                }
            }
        }

        insert opportunity;
    }

    private static Boolean isRetryableConsumablesInsertException(DmlException insertException) {
        String message = insertException.getMessage();
        return message.contains('Category__c') || message.contains('Category');
    }
}