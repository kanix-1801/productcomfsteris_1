/**
 * @description GW-4777 / GW-5676 - Tests for ImsProductConfiguratorController (imsProductConfigurator LWC).
 */
@IsTest
private class ImsProductConfiguratorControllerTest {

    @TestSetup
    static void setupTestData() {
        ImsProductConfiguratorTestDataFactory.grantAccess();
        ImsProductConfiguratorTestDataFactory.createQuoteWithLine();
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
        line.put(ImsProductConfiguratorService.COVERAGE_FIELD, ImsProductConfiguratorTestDataFactory.coverageJson(
            null, new Map<String, Decimal>{ 'A-100' => 5 }
        ));
        System.runAs(contextUser) {
            update line; // inside runAs so the test permission set applies to the sync
        }

        /********************************************
        * GIVEN
        ********************************************/
        Assert.areEqual(1, [SELECT COUNT() FROM ContractAdjustment__c], 'The saved coverage created one record');

        /********************************************
        * WHEN
        ********************************************/
        ImsProductConfiguratorService.ContractAdjustments saved;
        ImsProductConfiguratorService.ContractAdjustments unsaved;
        ImsProductConfiguratorService.ContractAdjustments invalid;
        Test.startTest();
        System.runAs(contextUser) {
            saved = ImsProductConfiguratorService.parseCoverage(ImsProductConfiguratorController.getCoverage(line.Id));
            unsaved = ImsProductConfiguratorService.parseCoverage(
                ImsProductConfiguratorController.getCoverage('ref_12345')
            );
            invalid = ImsProductConfiguratorService.parseCoverage(
                ImsProductConfiguratorController.getCoverage('0QLnotAValidId')
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
        List<ImsProductConfiguratorService.AssetGroup> groupList;
        List<String> manufacturerList;
        List<String> filteredOutList;
        Test.startTest();
        System.runAs(contextUser) {
            manufacturerList = ImsProductConfiguratorController.getManufacturers(quoteRecord.Id,
                ImsProductConfiguratorTestDataFactory.PRODUCT_LINE,
                ImsProductConfiguratorTestDataFactory.SUB_PRODUCT_LINE);
            filteredOutList = ImsProductConfiguratorController.getManufacturers(quoteRecord.Id, 'Another Line', null);
            subProductLineList = ImsProductConfiguratorController.getSubProductLines(
                ImsProductConfiguratorTestDataFactory.PRODUCT_LINE
            );
            groupList = ImsProductConfiguratorController.getAssetCatalog(quoteRecord.Id);
        }
        Test.stopTest();

        /********************************************
        * THEN
        ********************************************/
        Assert.areEqual(new List<String>{ ImsProductConfiguratorTestDataFactory.SUB_PRODUCT_LINE }, subProductLineList,
                        'Sub Product Lines for the Product Line');
        Assert.areEqual(new List<String>{ ImsProductConfiguratorTestDataFactory.MANUFACTURER }, manufacturerList,
                        'Manufacturer of the repair asset in that Product Line / Sub Product Line');
        Assert.isTrue(filteredOutList.isEmpty(), 'Assets in another Product Line are filtered out');
        Assert.areEqual(1, groupList.size(), 'One group for the one repair asset');
        Assert.areEqual(ImsProductConfiguratorTestDataFactory.MANUFACTURER, groupList[0].manufacturer,
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
        User noAccessUser = ImsProductConfiguratorTestDataFactory.createNoAccessUser();

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
                ImsProductConfiguratorController.getCoverage(line.Id);
            } catch (AuraHandledException e) {
                thrownCount++;
            }
            try {
                ImsProductConfiguratorController.getSubProductLines(ImsProductConfiguratorTestDataFactory.PRODUCT_LINE);
            } catch (AuraHandledException e) {
                thrownCount++;
            }
            try {
                ImsProductConfiguratorController.getManufacturers(
                    line.QuoteId, ImsProductConfiguratorTestDataFactory.PRODUCT_LINE, null
                );
            } catch (AuraHandledException e) {
                thrownCount++;
            }
            try {
                ImsProductConfiguratorController.getAssetCatalog(line.QuoteId);
            } catch (AuraHandledException e) {
                thrownCount++;
            }
            try {
                ImsProductConfiguratorController.searchPricingPrograms('ZZPP');
            } catch (AuraHandledException e) {
                thrownCount++;
            }
            try {
                ImsProductConfiguratorController.getPricingProgramsByNames(new List<String>{ 'PP-0001' });
            } catch (AuraHandledException e) {
                thrownCount++;
            }
            try {
                ImsProductConfiguratorController.searchOnlPricingPrograms('ZZPP');
            } catch (AuraHandledException e) {
                Assert.areEqual('Unable to load the ONL Pricing Programs.', e.getMessage(),
                                'Generic message for the ONL search');
                thrownCount++;
            }
        }
        Test.stopTest();

        /********************************************
        * THEN
        ********************************************/
        Assert.areEqual(7, thrownCount, 'Each method should throw an AuraHandledException');
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
        ImsProductConfiguratorTestDataFactory.grantPricingProgramAccess();
        User contextUser = new User(Id = UserInfo.getUserId());
        PricingProgram__c programRecord = ImsProductConfiguratorTestDataFactory.createPricingProgram(
            'ZZPP Controller', 'Active', Date.today(), null, new List<String>{ 'CT.ZZC01' }
        );

        /********************************************
        * GIVEN
        ********************************************/
        Assert.areEqual(1, [SELECT COUNT() FROM PricingProgramLines__c], 'One CT code line');

        /********************************************
        * WHEN
        ********************************************/
        List<ImsProductConfiguratorService.PricingProgramOption> searchList;
        List<ImsProductConfiguratorService.PricingProgramOption> byNameList;
        Test.startTest();
        System.runAs(contextUser) {
            searchList = ImsProductConfiguratorController.searchPricingPrograms('ZZPP Contr');
            byNameList = ImsProductConfiguratorController.getPricingProgramsByNames(
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
     * @description GW-6468 - The ONL Pricing Program search returns only Active, in-date programs.
     */
    @IsTest
    static void testSearchOnlPricingPrograms() {
        /********************************************
        * SETUP
        ********************************************/
        ImsProductConfiguratorTestDataFactory.grantPricingProgramAccess();
        User contextUser = new User(Id = UserInfo.getUserId());
        PricingProgram__c activeProgram = ImsProductConfiguratorTestDataFactory.createPricingProgram(
            'ZZPP Onl Active', 'Active', Date.today(), null, new List<String>{ 'CT.ZZO01' }
        );
        ImsProductConfiguratorTestDataFactory.createPricingProgram(
            'ZZPP Onl Draft', 'Draft', Date.today(), null, new List<String>{ 'CT.ZZO02' }
        );

        /********************************************
        * GIVEN
        ********************************************/
        Assert.areEqual(2, [SELECT COUNT() FROM PricingProgram__c], 'Two programs created');

        /********************************************
        * WHEN
        ********************************************/
        List<ImsProductConfiguratorService.PricingProgramOption> searchList;
        Test.startTest();
        System.runAs(contextUser) {
            searchList = ImsProductConfiguratorController.searchOnlPricingPrograms('ZZPP Onl');
        }
        Test.stopTest();

        /********************************************
        * THEN
        ********************************************/
        Assert.areEqual(1, searchList.size(), 'Only the Active program is found');
        Assert.areEqual(activeProgram.Id, searchList[0].programId, 'The Active program');
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
        AuraHandledException result = ImsProductConfiguratorController.toAuraException(
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