/**
 * @description GW-4777 / GW-5676 - Tests for ModelQtyCoverageController (modelQtyCoverage LWC).
 */
@IsTest
private class ModelQtyCoverageControllerTest {

    @TestSetup
    static void setupTestData() {
        ModelQtyCoverageTestDataFactory.grantAccess();
        ModelQtyCoverageTestDataFactory.createQuoteWithLine();
    }

    /**
     * @description A saved line returns its coverage; unsaved ("ref_") and malformed Ids return empty coverage.
     */
    @IsTest
    static void testGetCoverage() {
        /********************************************
        * SETUP
        ********************************************/
        User contextUser = new User(Id = UserInfo.getUserId());
        QuoteLineItem line = [SELECT Id FROM QuoteLineItem LIMIT 1];
        line.put(ContractModifierService.COVERAGE_FIELD, ModelQtyCoverageTestDataFactory.coverageJson(
            null, new Map<String, Decimal>{ 'A-100' => 5 }
        ));
        System.runAs(contextUser) {
            update line; // inside runAs so the test permission set applies to the sync
        }

        /********************************************
        * GIVEN
        ********************************************/
        Assert.areEqual(1, [SELECT COUNT() FROM ContractModifier__c], 'The saved coverage created one record');

        /********************************************
        * WHEN
        ********************************************/
        ContractModifierService.ContractAdjustments saved;
        ContractModifierService.ContractAdjustments unsaved;
        ContractModifierService.ContractAdjustments invalid;
        Test.startTest();
        System.runAs(contextUser) {
            saved = ContractModifierService.parseCoverage(ModelQtyCoverageController.getCoverage(line.Id));
            unsaved = ContractModifierService.parseCoverage(ModelQtyCoverageController.getCoverage('ref_12345'));
            invalid = ContractModifierService.parseCoverage(
                ModelQtyCoverageController.getCoverage('0QLnotAValidId')
            );
        }
        Test.stopTest();

        /********************************************
        * THEN
        ********************************************/
        Assert.areEqual(1, saved.models.size(), 'One saved model');
        Assert.areEqual('A-100', saved.models[0].model, 'Saved model name');
        Assert.areEqual(5, saved.models[0].qty, 'Saved max covered devices');
        Assert.isTrue(unsaved.models.isEmpty(), 'Unsaved line has no coverage');
        Assert.isTrue(invalid.models.isEmpty(), 'Malformed line Id has no coverage');
    }

    /**
     * @description Sub Product Lines and Manufacturers for the Inclusion pickers; the asset catalog for the Model Qty pickers.
     */
    @IsTest
    static void testGetFilterOptions() {
        /********************************************
        * SETUP
        ********************************************/
        User contextUser = new User(Id = UserInfo.getUserId());
        Quote quoteRecord = [SELECT Id FROM Quote LIMIT 1];

        /********************************************
        * GIVEN
        ********************************************/
        Assert.areEqual(1, [SELECT COUNT() FROM Asset], 'One repair asset on the quote account');

        /********************************************
        * WHEN
        ********************************************/
        List<String> subProductLineList;
        List<ContractModifierService.AssetGroup> groupList;
        List<String> manufacturerList;
        List<String> filteredOutList;
        Test.startTest();
        System.runAs(contextUser) {
            manufacturerList = ModelQtyCoverageController.getManufacturers(quoteRecord.Id,
                ModelQtyCoverageTestDataFactory.PRODUCT_LINE, ModelQtyCoverageTestDataFactory.SUB_PRODUCT_LINE);
            filteredOutList = ModelQtyCoverageController.getManufacturers(quoteRecord.Id, 'Another Line', null);
            subProductLineList = ModelQtyCoverageController.getSubProductLines(
                ModelQtyCoverageTestDataFactory.PRODUCT_LINE
            );
            groupList = ModelQtyCoverageController.getAssetCatalog(quoteRecord.Id);
        }
        Test.stopTest();

        /********************************************
        * THEN
        ********************************************/
        Assert.areEqual(new List<String>{ ModelQtyCoverageTestDataFactory.SUB_PRODUCT_LINE }, subProductLineList,
                        'Sub Product Lines for the Product Line');
        Assert.areEqual(new List<String>{ ModelQtyCoverageTestDataFactory.MANUFACTURER }, manufacturerList,
                        'Manufacturer of the repair asset in that Product Line / Sub Product Line');
        Assert.isTrue(filteredOutList.isEmpty(), 'Assets in another Product Line are filtered out');
        Assert.areEqual(1, groupList.size(), 'One group for the one repair asset');
        Assert.areEqual(ModelQtyCoverageTestDataFactory.MANUFACTURER, groupList[0].manufacturer,
                        'Manufacturer of the repair asset');
    }

    /**
     * @description A user without access to the data gets an AuraHandledException from every method
     *              (the USER_MODE queries fail), not a raw platform error.
     */
    @IsTest
    static void testMethodsThrowForUserWithoutAccess() {
        /********************************************
        * SETUP
        ********************************************/
        QuoteLineItem line = [SELECT Id, QuoteId FROM QuoteLineItem LIMIT 1];
        User noAccessUser = ModelQtyCoverageTestDataFactory.createNoAccessUser();

        /********************************************
        * GIVEN
        ********************************************/
        Assert.isNotNull(noAccessUser.Id, 'The no-access user should exist');

        /********************************************
        * WHEN
        ********************************************/
        Integer thrownCount = 0;
        Test.startTest();
        System.runAs(noAccessUser) {
            try {
                ModelQtyCoverageController.getCoverage(line.Id);
            } catch (AuraHandledException e) {
                thrownCount++;
            }
            try {
                ModelQtyCoverageController.getSubProductLines(ModelQtyCoverageTestDataFactory.PRODUCT_LINE);
            } catch (AuraHandledException e) {
                thrownCount++;
            }
            try {
                ModelQtyCoverageController.getManufacturers(line.QuoteId, null, null);
            } catch (AuraHandledException e) {
                thrownCount++;
            }
            try {
                ModelQtyCoverageController.getAssetCatalog(line.QuoteId);
            } catch (AuraHandledException e) {
                thrownCount++;
            }
            try {
                ModelQtyCoverageController.searchPricingPrograms('ZZPP');
            } catch (AuraHandledException e) {
                thrownCount++;
            }
            try {
                ModelQtyCoverageController.getPricingProgramsByNames(new List<String>{ 'PP-0001' });
            } catch (AuraHandledException e) {
                thrownCount++;
            }
        }
        Test.stopTest();

        /********************************************
        * THEN
        ********************************************/
        Assert.areEqual(6, thrownCount, 'Each method should throw an AuraHandledException');
    }

    /**
     * @description The Pricing Programs search returns active programs with their CT codes, and a saved program
     *              is found again by its name.
     */
    @IsTest
    static void testPricingPrograms() {
        /********************************************
        * SETUP
        ********************************************/
        ModelQtyCoverageTestDataFactory.grantPricingProgramAccess();
        User contextUser = new User(Id = UserInfo.getUserId());
        PricingProgram__c programRecord = ModelQtyCoverageTestDataFactory.createPricingProgram(
            'ZZPP Controller', 'Active', Date.today(), null, new List<String>{ 'CT.ZZC01' }
        );

        /********************************************
        * GIVEN
        ********************************************/
        Assert.areEqual(1, [SELECT COUNT() FROM PricingProgramLines__c], 'One CT code line');

        /********************************************
        * WHEN
        ********************************************/
        List<ContractModifierService.PricingProgramOption> searchList;
        List<ContractModifierService.PricingProgramOption> byNameList;
        Test.startTest();
        System.runAs(contextUser) {
            searchList = ModelQtyCoverageController.searchPricingPrograms('ZZPP Contr');
            byNameList = ModelQtyCoverageController.getPricingProgramsByNames(
                new List<String>{ programRecord.Name }
            );
        }
        Test.stopTest();

        /********************************************
        * THEN
        ********************************************/
        Assert.areEqual(1, searchList.size(), 'The active program is found');
        Assert.areEqual(programRecord.Name, searchList[0].program, 'Program name');
        Assert.areEqual('CT.ZZC01', searchList[0].ctCodes[0].code, 'CT code of the program');
        Assert.areEqual(1, byNameList.size(), 'The program is found by its name');
    }

    /**
     * @description A failure is logged and surfaced to the LWC as an AuraHandledException with a readable message.
     */
    @IsTest
    static void testToAuraException() {
        /********************************************
        * SETUP
        ********************************************/
        QuoteLineItem line = [SELECT Id FROM QuoteLineItem LIMIT 1];
        DmlException cause = new DmlException('Simulated failure');

        /********************************************
        * GIVEN
        ********************************************/
        Assert.areEqual(0, Logger.getBufferSize(), 'Nothing logged yet');

        /********************************************
        * WHEN
        ********************************************/
        Test.startTest();
        AuraHandledException result = ModelQtyCoverageController.toAuraException(
            'getCoverage: unable to load adjustments', line.Id, cause,
            'Unable to load the contract adjustments for this line.'
        );
        Test.stopTest();

        /********************************************
        * THEN
        ********************************************/
        Assert.areEqual('Unable to load the contract adjustments for this line.', result.getMessage(),
                        'Message shown in the LWC');
        Assert.areEqual(1, Logger.getBufferSize(), 'The failure should be logged');
    }
}