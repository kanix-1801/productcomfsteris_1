/**
 * @description GW-4777 / GW-5676 - Tests for ContractModifierService (Contract Adjustments sync and lookups).
 */
@IsTest
private class ContractModifierServiceTest {

    @TestSetup
    static void setupTestData() {
        ImsProductConfiguratorTestDataFactory.grantAccess();
        ImsProductConfiguratorTestDataFactory.createQuoteWithLine();
    }

    private static ContractModifier__c modelQtyRecord(QuoteLineItem line, String model, Decimal qty) {
        return new ContractModifier__c(
            RecordTypeId = ContractModifierSelector.MODEL_QTY_RECORD_TYPE_ID,
            Type__c = ContractModifierSelector.TYPE_MODEL_QTY,
            Model__c = model,
            ModelQty__c = qty,
            Quote__c = line.QuoteId,
            QuoteLineItem__c = line.Id
        );
    }

    private static ContractModifier__c incExcRecord(QuoteLineItem line, String incExcType, String manufacturer) {
        return new ContractModifier__c(
            RecordTypeId = ContractModifierSelector.INC_EXC_RECORD_TYPE_ID,
            Type__c = ContractModifierSelector.TYPE_INC_EXC,
            InclusionExclusionType__c = incExcType,
            Manufacture__c = manufacturer,
            Quote__c = line.QuoteId,
            QuoteLineItem__c = line.Id
        );
    }

    private static QuoteLineItem getLine() {
        return [SELECT Id, QuoteId FROM QuoteLineItem LIMIT 1];
    }

    private static Map<String, ContractModifier__c> recordsByModel(Id lineId) {
        Map<String, ContractModifier__c> recordByModelMap = new Map<String, ContractModifier__c>();
        for (ContractModifier__c rec : [
            SELECT Id, Model__c, ModelQty__c, Type__c, Quote__c, QuoteLineItem__c, ProductLine__c, Manufacture__c,
                   StartDate__c, EndDate__c
            FROM ContractModifier__c
            WHERE QuoteLineItem__c = :lineId AND Type__c = :ContractModifierSelector.TYPE_MODEL_QTY
        ]) {
            recordByModelMap.put(rec.Model__c, rec);
        }
        return recordByModelMap;
    }

    private static List<ContractModifier__c> incExcRecords(Id lineId, String incExcType) {
        return [
            SELECT Id, ProductLine__c, Manufacture__c, Model__c, ParentContractModifier__c, Quote__c,
                   StartDate__c, EndDate__c, RecordTypeId
            FROM ContractModifier__c
            WHERE QuoteLineItem__c = :lineId
              AND Type__c = :ContractModifierSelector.TYPE_INC_EXC
              AND InclusionExclusionType__c = :incExcType
            ORDER BY CreatedDate, Manufacture__c
        ];
    }

    private static void setCoverage(Id lineId, String value) {
        QuoteLineItem line = new QuoteLineItem(Id = lineId);
        line.put(ContractModifierService.COVERAGE_FIELD, value);
        update line;
    }

    // Include <productLine> excluding Pentax and model TJF-Q190V; include Olympus with no exclusions.
    private static List<Map<String, Object>> sampleInclusions(String productLine) {
        return new List<Map<String, Object>>{
            ImsProductConfiguratorTestDataFactory.inclusion(
                ImsProductConfiguratorTestDataFactory.criteria(productLine, null, null),
                new List<Map<String, Object>>{
                    ImsProductConfiguratorTestDataFactory.criteria(null, 'Pentax', null),
                    ImsProductConfiguratorTestDataFactory.criteria(null, 'Olympus', 'TJF-Q190V')
                }
            ),
            ImsProductConfiguratorTestDataFactory.inclusion(
                ImsProductConfiguratorTestDataFactory.criteria(null, 'Olympus', null),
                new List<Map<String, Object>>()
            )
        };
    }

    /**
     * @description Saving adjustments creates one MODEL QTY record per row and one INC/EXC record per inclusion
     *              and exclusion, linked to the quote and the line, with the line's term; each exclusion points
     *              to its inclusion.
     */
    @IsTest
    static void testSyncCreatesModelQtyAndIncExcRecords() {
        /********************************************
        * SETUP
        ********************************************/
        User contextUser = new User(Id = UserInfo.getUserId());
        QuoteLineItem line = getLine();
        String productLine = ImsProductConfiguratorTestDataFactory.validProductLine();
        String coverage = ImsProductConfiguratorTestDataFactory.coverageJson(
            productLine, new Map<String, Decimal>{ 'A-100' => 5, 'B-200' => 3 }, sampleInclusions(productLine)
        );

        /********************************************
        * GIVEN
        ********************************************/
        Assert.areEqual(0, [SELECT COUNT() FROM ContractModifier__c], 'No Contract Modifiers yet');

        /********************************************
        * WHEN
        ********************************************/
        Test.startTest();
        System.runAs(contextUser) {
            setCoverage(line.Id, coverage);
        }
        Test.stopTest();

        /********************************************
        * THEN
        ********************************************/
        Map<String, ContractModifier__c> recordByModelMap = recordsByModel(line.Id);
        Assert.areEqual(2, recordByModelMap.size(), 'One record per Model Qty row');
        ContractModifier__c first = recordByModelMap.get('A-100');
        Assert.areEqual(5, first.ModelQty__c, 'Max covered devices should be saved');
        Assert.areEqual(productLine, first.ProductLine__c, 'Product Line is written to the Model Qty record');
        Assert.areEqual(line.QuoteId, first.Quote__c, 'Record should be linked to the quote');
        Assert.areEqual(line.Id, first.QuoteLineItem__c, 'Record should be linked to the quote line');
        Assert.areEqual(ImsProductConfiguratorTestDataFactory.TERM_START, first.StartDate__c,
                        'Start Date from the line');
        Assert.areEqual(ImsProductConfiguratorTestDataFactory.TERM_END, first.EndDate__c, 'End Date from the line');

        List<ContractModifier__c> inclusionList = incExcRecords(line.Id, ContractModifierSelector.INCLUSION);
        List<ContractModifier__c> exclusionList = incExcRecords(line.Id, ContractModifierSelector.EXCLUSION);
        Assert.areEqual(2, inclusionList.size(), 'One INC record per inclusion');
        Assert.areEqual(2, exclusionList.size(), 'One EXC record per exclusion');
        ContractModifier__c productLineInclusion;
        for (ContractModifier__c rec : inclusionList) {
            Assert.isNull(rec.ParentContractModifier__c, 'Inclusions have no parent');
            Assert.areEqual(ContractModifierSelector.INC_EXC_RECORD_TYPE_ID, rec.RecordTypeId, 'INC/EXC record type');
            if (rec.ProductLine__c == productLine) {
                productLineInclusion = rec;
            }
        }
        Assert.isNotNull(productLineInclusion, 'Inclusion by Product Line saved');
        for (ContractModifier__c rec : exclusionList) {
            Assert.areEqual(productLineInclusion.Id, rec.ParentContractModifier__c, 'Exclusion points to its inclusion');
            Assert.areEqual(ImsProductConfiguratorTestDataFactory.TERM_END, rec.EndDate__c, 'End Date from the line');
        }
    }

    /**
     * @description Changing only the line's term updates the records' dates and keeps the records.
     */
    @IsTest
    static void testSyncFollowsLineTerm() {
        /********************************************
        * SETUP
        ********************************************/
        User contextUser = new User(Id = UserInfo.getUserId());
        QuoteLineItem line = getLine();
        System.runAs(contextUser) {
            setCoverage(line.Id, ImsProductConfiguratorTestDataFactory.coverageJson(
                null, new Map<String, Decimal>{ 'A-100' => 5 },
                sampleInclusions(ImsProductConfiguratorTestDataFactory.validProductLine())
            ));
        }
        ContractModifierService.processedLineIdSet.clear(); // a later save in a new transaction
        Date newEnd = ImsProductConfiguratorTestDataFactory.TERM_END.addYears(1);
        Set<Id> inclusionIdSet = new Map<Id, ContractModifier__c>(
            incExcRecords(line.Id, ContractModifierSelector.INCLUSION)
        ).keySet();

        /********************************************
        * GIVEN
        ********************************************/
        Assert.areEqual(ImsProductConfiguratorTestDataFactory.TERM_END, recordsByModel(line.Id).get('A-100').EndDate__c,
                        'End Date from the original term');

        /********************************************
        * WHEN
        ********************************************/
        Test.startTest();
        System.runAs(contextUser) {
            update new QuoteLineItem(Id = line.Id, EndDate = newEnd);
        }
        Test.stopTest();

        /********************************************
        * THEN
        ********************************************/
        ContractModifier__c rec = recordsByModel(line.Id).get('A-100');
        Assert.areEqual(newEnd, rec.EndDate__c, 'End Date follows the line');
        Assert.areEqual(5, rec.ModelQty__c, 'Max covered devices is unchanged');
        for (ContractModifier__c inclusion : incExcRecords(line.Id, ContractModifierSelector.INCLUSION)) {
            Assert.isTrue(inclusionIdSet.contains(inclusion.Id), 'Inclusions are kept, not replaced');
            Assert.areEqual(newEnd, inclusion.EndDate__c, 'Inclusion End Date follows the line');
        }
    }

    /**
     * @description A new line inserted with adjustments also gets its records (after insert path).
     */
    @IsTest
    static void testSyncOnInsert() {
        /********************************************
        * SETUP
        ********************************************/
        User contextUser = new User(Id = UserInfo.getUserId());
        QuoteLineItem existing = [SELECT QuoteId, PricebookEntryId FROM QuoteLineItem LIMIT 1];
        QuoteLineItem newLine = new QuoteLineItem(
            QuoteId = existing.QuoteId,
            PricebookEntryId = existing.PricebookEntryId,
            Quantity = 1,
            UnitPrice = 100
        );
        newLine.put(ContractModifierService.COVERAGE_FIELD,
            ImsProductConfiguratorTestDataFactory.coverageJson(null, new Map<String, Decimal>{ 'C-300' => 2 }));

        /********************************************
        * GIVEN
        ********************************************/
        Assert.areEqual(0, [SELECT COUNT() FROM ContractModifier__c], 'No Contract Modifiers yet');

        /********************************************
        * WHEN
        ********************************************/
        Test.startTest();
        System.runAs(contextUser) {
            insert newLine;
        }
        Test.stopTest();

        /********************************************
        * THEN
        ********************************************/
        Map<String, ContractModifier__c> recordByModelMap = recordsByModel(newLine.Id);
        Assert.areEqual(1, recordByModelMap.size(), 'One record for the one row');
        Assert.areEqual(2, recordByModelMap.get('C-300').ModelQty__c, 'Max covered devices should be saved');
    }

    /**
     * @description Changing the adjustments updates kept Model Qty rows, adds new ones and deletes removed ones,
     *              and replaces changed inclusions; clearing them removes all of the line's records.
     */
    @IsTest
    static void testSyncUpdatesDeletesAndClears() {
        /********************************************
        * SETUP
        ********************************************/
        User contextUser = new User(Id = UserInfo.getUserId());
        QuoteLineItem line = getLine();
        insert new List<ContractModifier__c>{
            modelQtyRecord(line, 'A-100', 5),
            modelQtyRecord(line, 'B-200', 3)
        };
        ContractModifier__c oldInclusion = incExcRecord(line, ContractModifierSelector.INCLUSION, 'Storz');
        insert oldInclusion;
        ContractModifier__c orphanExclusion = incExcRecord(line, ContractModifierSelector.EXCLUSION, 'Pentax');
        insert orphanExclusion; // an exclusion without its inclusion is rebuilt
        Id keptRecordId = recordsByModel(line.Id).get('A-100').Id;

        /********************************************
        * GIVEN
        ********************************************/
        Assert.areEqual(2, recordsByModel(line.Id).size(), 'Two Model Qty records before the change');

        /********************************************
        * WHEN
        ********************************************/
        Test.startTest();
        System.runAs(contextUser) {
            setCoverage(line.Id, ImsProductConfiguratorTestDataFactory.coverageJson(
                null, new Map<String, Decimal>{ 'a-100' => 7, 'C-300' => 1 },
                sampleInclusions(ImsProductConfiguratorTestDataFactory.validProductLine())
            ));
        }
        Map<String, ContractModifier__c> afterChangeMap = recordsByModel(line.Id);
        List<ContractModifier__c> inclusionAfterChangeList = incExcRecords(line.Id, ContractModifierSelector.INCLUSION);
        List<ContractModifier__c> exclusionAfterChangeList = incExcRecords(line.Id, ContractModifierSelector.EXCLUSION);
        ContractModifierService.processedLineIdSet.clear(); // a later save in a new transaction
        System.runAs(contextUser) {
            setCoverage(line.Id, null);
        }
        Test.stopTest();

        /********************************************
        * THEN
        ********************************************/
        Assert.areEqual(2, afterChangeMap.size(), 'A-100 kept, C-300 added, B-200 deleted');
        Assert.areEqual(keptRecordId, afterChangeMap.get('a-100').Id, 'The existing record is updated, not replaced');
        Assert.areEqual(7, afterChangeMap.get('a-100').ModelQty__c, 'Max covered devices should be updated');
        Assert.isFalse(afterChangeMap.containsKey('B-200'), 'Removed row should be deleted');
        Assert.areEqual(2, inclusionAfterChangeList.size(), 'Inclusions replaced by the two entered');
        Assert.areEqual(2, exclusionAfterChangeList.size(), 'Exclusions replaced by the two entered');
        Set<Id> oldIdSet = new Set<Id>{ oldInclusion.Id, orphanExclusion.Id };
        Assert.areEqual(0, [SELECT COUNT() FROM ContractModifier__c WHERE Id IN :oldIdSet],
                        'Old INC/EXC records are deleted');
        Assert.areEqual(0, [SELECT COUNT() FROM ContractModifier__c WHERE QuoteLineItem__c = :line.Id],
                        'Clearing the adjustments removes all records');
    }

    /**
     * @description Unreadable JSON leaves the records alone; invalid and duplicate rows and rules are skipped.
     */
    @IsTest
    static void testSyncSkipsInvalidInput() {
        /********************************************
        * SETUP
        ********************************************/
        User contextUser = new User(Id = UserInfo.getUserId());
        QuoteLineItem line = getLine();
        insert modelQtyRecord(line, 'A-100', 5);
        String invalidEntries = JSON.serialize(new Map<String, Object>{
            'models' => new List<Object>{
                new Map<String, Object>{ 'model' => 'D-400', 'qty' => 2 },
                new Map<String, Object>{ 'model' => 'd-400', 'qty' => 4 },
                new Map<String, Object>{ 'model' => 'E-500', 'qty' => 0 },
                new Map<String, Object>{ 'model' => ' ', 'qty' => 1 },
                new Map<String, Object>{ 'model' => 'F-600', 'qty' => 1.5 },
                new Map<String, Object>{ 'productLine' => 'Not A Product Line', 'qty' => 1 }
            },
            'inclusions' => new List<Object>{
                new Map<String, Object>{ 'manufacturer' => ' ', 'exclusions' => new List<Object>() },
                new Map<String, Object>{
                    'manufacturer' => 'Olympus',
                    'exclusions' => new List<Object>{
                        new Map<String, Object>{ 'model' => 'X-1' },
                        new Map<String, Object>{ 'model' => 'x-1' },
                        new Map<String, Object>()
                    }
                },
                new Map<String, Object>{ 'manufacturer' => 'olympus' }
            }
        });

        /********************************************
        * GIVEN
        ********************************************/
        Assert.areEqual(1, recordsByModel(line.Id).size(), 'One record before the change');

        /********************************************
        * WHEN
        ********************************************/
        Test.startTest();
        System.runAs(contextUser) {
            setCoverage(line.Id, '{not json');
        }
        Map<String, ContractModifier__c> afterBadJsonMap = recordsByModel(line.Id);
        ContractModifierService.processedLineIdSet.clear(); // a later save in a new transaction
        System.runAs(contextUser) {
            setCoverage(line.Id, invalidEntries);
        }
        Test.stopTest();

        /********************************************
        * THEN
        ********************************************/
        Assert.isTrue(afterBadJsonMap.containsKey('A-100'), 'Unreadable JSON keeps the existing records');
        Map<String, ContractModifier__c> recordByModelMap = recordsByModel(line.Id);
        Assert.areEqual(1, recordByModelMap.size(), 'Only the first valid D-400 row is kept');
        Assert.areEqual(2, recordByModelMap.get('D-400').ModelQty__c, 'First row wins for a duplicate');
        List<ContractModifier__c> inclusionList = incExcRecords(line.Id, ContractModifierSelector.INCLUSION);
        Assert.areEqual(1, inclusionList.size(), 'Blank and duplicate inclusions are skipped');
        Assert.areEqual('Olympus', inclusionList[0].Manufacture__c, 'The valid inclusion is saved');
        Assert.areEqual(1, incExcRecords(line.Id, ContractModifierSelector.EXCLUSION).size(),
                        'Blank and duplicate exclusions are skipped');
    }

    /**
     * @description Saved adjustments come from the JSON when present, otherwise from the records.
     */
    @IsTest
    static void testGetContractAdjustments() {
        /********************************************
        * SETUP
        ********************************************/
        User contextUser = new User(Id = UserInfo.getUserId());
        QuoteLineItem line = getLine();
        insert modelQtyRecord(line, 'R-1', 4);
        ContractModifier__c inclusion = incExcRecord(line, ContractModifierSelector.INCLUSION, 'Olympus');
        insert inclusion;
        ContractModifier__c exclusion = incExcRecord(line, ContractModifierSelector.EXCLUSION, null);
        exclusion.Model__c = 'TJF-Q190V';
        exclusion.ParentContractModifier__c = inclusion.Id;
        insert exclusion;

        /********************************************
        * GIVEN
        ********************************************/
        Assert.isNull(ContractModifierService.parseCoverage(null), 'Blank JSON parses to null');

        /********************************************
        * WHEN
        ********************************************/
        ContractModifierService.ContractAdjustments fromRecords;
        ContractModifierService.ContractAdjustments fromJson;
        ContractModifierService.ContractAdjustments noLine;
        Test.startTest();
        System.runAs(contextUser) {
            fromRecords = ContractModifierService.getContractAdjustments(line.Id);
            setCoverage(line.Id, ImsProductConfiguratorTestDataFactory.coverageJson(
                null, new Map<String, Decimal>{ 'J-1' => 6 }, sampleInclusions(null)
            ));
            fromJson = ContractModifierService.getContractAdjustments(line.Id);
            noLine = ContractModifierService.getContractAdjustments(null);
        }
        Test.stopTest();

        /********************************************
        * THEN
        ********************************************/
        Assert.areEqual(1, fromRecords.models.size(), 'Model Qty rebuilt from the records');
        Assert.areEqual('R-1', fromRecords.models[0].model, 'Model from the record');
        Assert.areEqual(4, fromRecords.models[0].qty, 'Quantity from the record');
        Assert.areEqual(1, fromRecords.inclusions.size(), 'Inclusion rebuilt from the records');
        Assert.areEqual('Olympus', fromRecords.inclusions[0].manufacturer, 'Inclusion manufacturer');
        Assert.areEqual('TJF-Q190V', fromRecords.inclusions[0].exclusions[0].model, 'Exclusion under its inclusion');
        Assert.areEqual('J-1', fromJson.models[0].model, 'Model Qty read from the JSON');
        Assert.areEqual(2, fromJson.inclusions.size(), 'Inclusions read from the JSON');
        Assert.areEqual(2, fromJson.inclusions[0].exclusions.size(), 'Exclusions read from the JSON');
        Assert.isTrue(noLine.models.isEmpty() && noLine.inclusions.isEmpty(), 'No line returns empty adjustments');
    }

    /**
     * @description Deleting and restoring a line runs the trigger without touching its Contract Modifiers.
     */
    @IsTest
    static void testDeleteAndUndeleteLine() {
        /********************************************
        * SETUP
        ********************************************/
        User contextUser = new User(Id = UserInfo.getUserId());
        QuoteLineItem line = getLine();
        insert modelQtyRecord(line, 'A-100', 5);

        /********************************************
        * GIVEN
        ********************************************/
        Assert.areEqual(1, [SELECT COUNT() FROM ContractModifier__c], 'One Contract Modifier before the delete');

        /********************************************
        * WHEN
        ********************************************/
        Test.startTest();
        System.runAs(contextUser) {
            delete line;
            undelete line;
        }
        Test.stopTest();

        /********************************************
        * THEN
        ********************************************/
        Assert.areEqual(1, [SELECT COUNT() FROM QuoteLineItem WHERE Id = :line.Id], 'Line is restored');
        Assert.areEqual(1, [SELECT COUNT() FROM ContractModifier__c], 'Contract Modifier is kept');
    }

    /**
     * @description JSON saved before Contract Adjustments (models with model/qty and top-level filters) still reads.
     */
    @IsTest
    static void testParseLegacyCoverage() {
        /********************************************
        * SETUP
        ********************************************/
        String legacy = '{"productLine":null,"manufacturer":"Olympus","includeExclude":"INC",'
                      + '"models":[{"model":"A-100","qty":5}]}';

        /********************************************
        * GIVEN
        ********************************************/
        Assert.isTrue(legacy.contains('includeExclude'), 'Legacy JSON shape');

        /********************************************
        * WHEN
        ********************************************/
        Test.startTest();
        ContractModifierService.ContractAdjustments parsed = ContractModifierService.parseCoverage(legacy);
        Test.stopTest();

        /********************************************
        * THEN
        ********************************************/
        Assert.areEqual('A-100', parsed.models[0].model, 'Legacy model kept');
        Assert.areEqual(5, parsed.models[0].qty, 'Legacy quantity kept');
        Assert.isTrue(parsed.inclusions.isEmpty(), 'No inclusions in legacy JSON');
    }

    /**
     * @description Sub Product Lines come from products in the Product Line; the asset catalog groups the quote
     *              account's repair assets; manufacturers are narrowed by Product Line and Sub Product Line.
     */
    @IsTest
    static void testGetSubProductLinesAndAssetCatalog() {
        /********************************************
        * SETUP
        ********************************************/
        User contextUser = new User(Id = UserInfo.getUserId());
        QuoteLineItem line = getLine();

        /********************************************
        * GIVEN
        ********************************************/
        Assert.areEqual(1, [SELECT COUNT() FROM Asset], 'One repair asset on the quote account');

        /********************************************
        * WHEN
        ********************************************/
        List<String> subProductLineList;
        List<String> noProductLineList;
        List<ContractModifierService.AssetGroup> groupList;
        List<ContractModifierService.AssetGroup> noQuoteList;
        List<String> manufacturerList;
        List<String> filteredOutList;
        Test.startTest();
        System.runAs(contextUser) {
            subProductLineList = ContractModifierService.getSubProductLines(
                ImsProductConfiguratorTestDataFactory.PRODUCT_LINE
            );
            noProductLineList = ContractModifierService.getSubProductLines(null);
            groupList = ContractModifierService.getAssetCatalog(line.QuoteId);
            noQuoteList = ContractModifierService.getAssetCatalog(null);
            manufacturerList = ContractModifierService.getManufacturers(line.QuoteId,
                ImsProductConfiguratorTestDataFactory.PRODUCT_LINE.toUpperCase(),
                ImsProductConfiguratorTestDataFactory.SUB_PRODUCT_LINE);
            filteredOutList = ContractModifierService.getManufacturers(line.QuoteId, 'Another Line', null);
        }
        Test.stopTest();

        /********************************************
        * THEN
        ********************************************/
        Assert.areEqual(new List<String>{ ImsProductConfiguratorTestDataFactory.SUB_PRODUCT_LINE }, subProductLineList,
                        'Sub Product Line of the product in that Product Line');
        Assert.isTrue(noProductLineList.isEmpty(), 'No Product Line returns no Sub Product Lines');
        Assert.areEqual(1, groupList.size(), 'One group for the one asset');
        Assert.areEqual(1, groupList[0].assetCount, 'Group counts its assets');
        Assert.areEqual(ImsProductConfiguratorTestDataFactory.MANUFACTURER, groupList[0].manufacturer,
                        'Manufacturer of the repair asset');
        Assert.isTrue(noQuoteList.isEmpty(), 'No quote returns no assets');
        Assert.areEqual(new List<String>{ ImsProductConfiguratorTestDataFactory.MANUFACTURER }, manufacturerList,
                        'Manufacturer of the asset in that Product Line (case ignored) and Sub Product Line');
        Assert.isTrue(filteredOutList.isEmpty(), 'Assets in another Product Line are filtered out');
    }

    /* =====================  Pricing Programs  ===================== */

    private static List<String> programNames(List<ContractModifierService.PricingProgramOption> optionList) {
        List<String> nameList = new List<String>();
        for (ContractModifierService.PricingProgramOption option : optionList) {
            nameList.add(option.description);
        }
        return nameList;
    }

    /**
     * @description The search returns only Active, in-date programs matching the program name, CT code or CT name,
     *              each with its CT codes sorted; a short term returns nothing and LIKE wildcards are literal.
     */
    @IsTest
    static void testSearchPricingPrograms() {
        /********************************************
        * SETUP
        ********************************************/
        ModelQtyCoverageTestDataFactory.grantPricingProgramAccess();
        User contextUser = new User(Id = UserInfo.getUserId());
        Date today = Date.today();
        ModelQtyCoverageTestDataFactory.createPricingProgram(
            'ZZPP Alpha', 'Active', today.addDays(-10), today.addDays(10), new List<String>{ 'CT.ZZA02', 'CT.ZZA01' }
        );
        ModelQtyCoverageTestDataFactory.createPricingProgram(
            'ZZPP Beta', 'Active', today.addDays(-10), null, new List<String>{ 'CT.ZZB01' }
        );
        ModelQtyCoverageTestDataFactory.createPricingProgram(
            'ZZPP Draft', 'Draft', today.addDays(-10), null, new List<String>{ 'CT.ZZD01' }
        );
        ModelQtyCoverageTestDataFactory.createPricingProgram(
            'ZZPP Expired', 'Active', today.addDays(-30), today.addDays(-1), new List<String>{ 'CT.ZZE01' }
        );
        ModelQtyCoverageTestDataFactory.createPricingProgram(
            'ZZPP Future', 'Active', today.addDays(1), null, new List<String>{ 'CT.ZZF01' }
        );

        /********************************************
        * GIVEN
        ********************************************/
        Assert.areEqual(5, [SELECT COUNT() FROM PricingProgram__c], 'Five programs created');
        Assert.areEqual(6, [SELECT COUNT() FROM PricingProgramLines__c], 'Six CT code lines created');

        /********************************************
        * WHEN
        ********************************************/
        List<ContractModifierService.PricingProgramOption> byNameList;
        List<ContractModifierService.PricingProgramOption> byCtCodeList;
        List<ContractModifierService.PricingProgramOption> byCtNameList;
        List<ContractModifierService.PricingProgramOption> wildcardList;
        List<ContractModifierService.PricingProgramOption> shortList;
        List<ContractModifierService.PricingProgramOption> blankList;
        Test.startTest();
        System.runAs(contextUser) {
            byNameList = ContractModifierService.searchPricingPrograms('  zzpp ');
            byCtCodeList = ContractModifierService.searchPricingPrograms('CT.ZZA02');
            byCtNameList = ContractModifierService.searchPricingPrograms('ZZB01 Name');
            wildcardList = ContractModifierService.searchPricingPrograms('ZZPP%');
            shortList = ContractModifierService.searchPricingPrograms('ZZ');
            blankList = ContractModifierService.searchPricingPrograms(null);
        }
        Test.stopTest();

        /********************************************
        * THEN
        ********************************************/
        Assert.areEqual(new List<String>{ 'ZZPP Alpha', 'ZZPP Beta' }, programNames(byNameList),
                        'Only Active, in-date programs (open-ended end date included), case ignored');
        Assert.areEqual(new List<String>{ 'ZZPP Alpha' }, programNames(byCtCodeList), 'Found by CT code');
        ContractModifierService.PricingProgramOption alpha = byCtCodeList[0];
        Assert.isNotNull(alpha.programId, 'Program Id returned');
        Assert.isTrue(String.isNotBlank(alpha.program), 'Program auto-number name returned');
        Assert.areEqual(2, alpha.ctCodes.size(), 'Both CT codes of the program');
        Assert.areEqual('CT.ZZA01', alpha.ctCodes[0].code, 'CT codes sorted by code');
        Assert.areEqual('CT.ZZA01 Name', alpha.ctCodes[0].name, 'CT name from the Category Code product');
        Assert.isNotNull(alpha.category, 'Product Line returned as category');
        Assert.areEqual(new List<String>{ 'ZZPP Beta' }, programNames(byCtNameList), 'Found by CT name');
        Assert.isTrue(wildcardList.isEmpty(), '% typed by the user is matched literally');
        Assert.isTrue(shortList.isEmpty(), 'A term under 3 characters returns nothing');
        Assert.isTrue(blankList.isEmpty(), 'A blank term returns nothing');
    }

    /**
     * @description Lookup by name refreshes saved rows: no status or date filter; blanks and duplicates ignored.
     */
    @IsTest
    static void testGetPricingProgramsByNames() {
        /********************************************
        * SETUP
        ********************************************/
        ModelQtyCoverageTestDataFactory.grantPricingProgramAccess();
        User contextUser = new User(Id = UserInfo.getUserId());
        Date today = Date.today();
        PricingProgram__c draft = ModelQtyCoverageTestDataFactory.createPricingProgram(
            'ZZPP Draft', 'Draft', today.addDays(-10), null, new List<String>{ 'CT.ZZD01' }
        );
        PricingProgram__c expired = ModelQtyCoverageTestDataFactory.createPricingProgram(
            'ZZPP Expired', 'Active', today.addDays(-30), today.addDays(-1), new List<String>{ 'CT.ZZE01' }
        );

        /********************************************
        * GIVEN
        ********************************************/
        Assert.areNotEqual(draft.Name, expired.Name, 'Programs have distinct names');

        /********************************************
        * WHEN
        ********************************************/
        List<ContractModifierService.PricingProgramOption> foundList;
        List<ContractModifierService.PricingProgramOption> emptyList;
        List<ContractModifierService.PricingProgramOption> nullList;
        Test.startTest();
        System.runAs(contextUser) {
            foundList = ContractModifierService.getPricingProgramsByNames(
                new List<String>{ draft.Name, ' ' + expired.Name + ' ', draft.Name, '', null }
            );
            emptyList = ContractModifierService.getPricingProgramsByNames(new List<String>{ ' ' });
            nullList = ContractModifierService.getPricingProgramsByNames(null);
        }
        Test.stopTest();

        /********************************************
        * THEN
        ********************************************/
        Assert.areEqual(new List<String>{ 'ZZPP Draft', 'ZZPP Expired' }, programNames(foundList),
                        'Draft and expired programs are returned by name, once each');
        Assert.areEqual('CT.ZZE01', foundList[1].ctCodes[0].code, 'CT code of the expired program');
        Assert.isTrue(emptyList.isEmpty(), 'Blank names return nothing');
        Assert.isTrue(nullList.isEmpty(), 'No names return nothing');
    }

    /**
     * @description Pricing Programs in the JSON survive save and reload, old JSON without them reads as an empty
     *              list, and the sync still creates only the MODEL QTY records (no Pricing Program records yet).
     */
    @IsTest
    static void testPricingProgramsKeptInCoverage() {
        /********************************************
        * SETUP
        ********************************************/
        User contextUser = new User(Id = UserInfo.getUserId());
        QuoteLineItem line = getLine();
        String coverage = JSON.serialize(new Map<String, Object>{
            'inclusions' => new List<Object>(),
            'models' => new List<Object>{ new Map<String, Object>{ 'model' => 'P-1', 'qty' => 2 } },
            'pricingPrograms' => new List<Object>{ new Map<String, Object>{
                'programId' => null, 'program' => 'PP-9999', 'description' => 'ZZPP Saved',
                'ctCodes' => new List<Object>{ new Map<String, Object>{ 'code' => 'CT.ZZS01', 'name' => 'Saved' } }
            } },
            'pricingProgram' => null
        });

        /********************************************
        * GIVEN
        ********************************************/
        Assert.isTrue(ContractModifierService.parseCoverage('{"models":[]}').pricingPrograms.isEmpty(),
                      'JSON saved before Pricing Programs reads as an empty list');

        /********************************************
        * WHEN
        ********************************************/
        ContractModifierService.ContractAdjustments saved;
        Test.startTest();
        System.runAs(contextUser) {
            setCoverage(line.Id, coverage);
            saved = ContractModifierService.getContractAdjustments(line.Id);
        }
        Test.stopTest();

        /********************************************
        * THEN
        ********************************************/
        Assert.areEqual(1, saved.pricingPrograms.size(), 'Pricing Program read back from the JSON');
        Assert.areEqual('PP-9999', saved.pricingPrograms[0].program, 'Program name kept');
        Assert.areEqual('CT.ZZS01', saved.pricingPrograms[0].ctCodes[0].code, 'CT code kept');
        Assert.areEqual(1, [SELECT COUNT() FROM ContractModifier__c], 'Only the MODEL QTY record is created');
        Assert.areEqual(0, [
            SELECT COUNT() FROM ContractModifier__c WHERE Type__c = :ContractModifierSelector.TYPE_PRICING_PROGRAM
        ], 'No Pricing Program records yet');
    }
}