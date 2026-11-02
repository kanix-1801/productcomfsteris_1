/**
 * @description GC-3431 tests for separate EPP capital and consumable product selection.
 *
 *              Responsibilities:
 *              1. Verify eligible products are separated by section and Opportunity currency.
 *              2. Verify created lines, elevated pricing, and revenue behavior.
 *              3. Verify an EPP cannot leave Draft with incomplete elevated pricing or Service details.
 * @author      Vinay
 * @date        2026-09-29
 */
@IsTest(SeeAllData=false)
private class EPPProductControllerTest {

    private static final String CAPITAL_CODE = 'EPP-CAP-001';
    private static final String CONSUMABLE_CODE = 'EPP-CON-001';
    private static final String INELIGIBLE_CODE = 'EPP-NO-001';

    /**
     * @description Creates the EPP Opportunity, eligible capital and consumable products, and one ineligible product.
     * @return None.
     */
    @TestSetup
    static void setupData() {
        Account accountRecord = new Account(
            Name = 'GC-3431 EPP Test Account',
            SourceSystemID__c = 'GC3431-EPP-TEST'
        );
        insert accountRecord;

        Contact contactRecord = new Contact(
            LastName = 'GC-3431 Contact',
            AccountId = accountRecord.Id
        );
        insert contactRecord;

        List<Product2> products = new List<Product2>{
            new Product2(
                Name = 'Eligible Capital Equipment',
                ProductCode = CAPITAL_CODE,
                IsActive = true,
                EPPEligible__c = true,
                IsConsumable__c = false,
                ItemFamily__c = 'Sterilizers',
                BusinessUnit__c = 'IMS'
            ),
            new Product2(
                Name = 'Eligible Consumable',
                ProductCode = CONSUMABLE_CODE,
                IsActive = true,
                EPPEligible__c = true,
                IsConsumable__c = true,
                ItemFamily__c = 'Consumables',
                BusinessUnit__c = 'IMS'
            ),
            new Product2(
                Name = 'Ineligible Product',
                ProductCode = INELIGIBLE_CODE,
                IsActive = true,
                EPPEligible__c = false,
                IsConsumable__c = false
            )
        };
        insert products;

        Id standardPricebookId = Test.getStandardPricebookId();
        List<PricebookEntry> standardEntries = new List<PricebookEntry>();
        Decimal price = 100;
        for (Product2 productRecord : products) {
            standardEntries.add(new PricebookEntry(
                Pricebook2Id = standardPricebookId,
                Product2Id = productRecord.Id,
                UnitPrice = price,
                IsActive = true
            ));
            price += 50;
        }
        insert standardEntries;

        Id eppRecordTypeId = Schema.SObjectType.Opportunity
            .getRecordTypeInfosByDeveloperName()
            .get('HCSalesEquipmentPlacementProgram')
            .getRecordTypeId();

        insert new Opportunity(
            Name = 'GC-3431 EPP Test Opportunity',
            AccountId = accountRecord.Id,
            RecordTypeId = eppRecordTypeId,
            StageName = 'Draft',
            Type = 'New Business',
            Amount = 1000,
            Probability = 10,
            PrimaryContact__c = contactRecord.Id,
            CloseDate = Date.today().addDays(30),
            Pricebook2Id = standardPricebookId,
            ConsumablesCommitment__c = true
        );
    }

    /**
     * @description Returns the EPP Opportunity created by test setup.
     * @return The test Opportunity and its Price Book.
     */
    private static Opportunity getOpportunity() {
        return [
            SELECT Id, Pricebook2Id
            FROM Opportunity
            WHERE Name = 'GC-3431 EPP Test Opportunity'
            LIMIT 1
        ];
    }

    /**
     * @description Returns the Standard Price Book Entry for a test product.
     * @param productCode Product code created by test setup.
     * @return The matching Price Book Entry.
     */
    private static PricebookEntry getEntry(String productCode) {
        Opportunity opportunityRecord = getOpportunity();
        return [
            SELECT Id, UnitPrice, Product2Id
            FROM PricebookEntry
            WHERE Pricebook2Id = :opportunityRecord.Pricebook2Id
              AND Product2.ProductCode = :productCode
            LIMIT 1
        ];
    }

    /**
     * @description Builds one capital-equipment product payload.
     * @param productCode Product code to add.
     * @param quantity Quantity to save.
     * @param unitPrice Sales Price to save.
     * @return Serialized ProductInput list.
     */
    private static String capitalInputJson(String productCode, Decimal quantity, Decimal unitPrice) {
        EPPProductController.ProductInput input = new EPPProductController.ProductInput();
        input.pricebookEntryId = getEntry(productCode).Id;
        input.quantity = quantity;
        input.unitPrice = unitPrice;
        input.placementStartDate = Date.today();
        input.placementEndDate = Date.today().addYears(1);
        return JSON.serialize(new List<EPPProductController.ProductInput>{ input });
    }

    /**
     * @description Builds one non-elevated consumable payload with monthly frequency.
     * @param productCode Product code to add.
     * @param quantity Quantity to save.
     * @return Serialized ProductInput list.
     */
    private static String consumableInputJson(String productCode, Decimal quantity) {
        EPPProductController.ProductInput input = new EPPProductController.ProductInput();
        input.pricebookEntryId = getEntry(productCode).Id;
        input.quantity = quantity;
        input.consumptionFrequency = 'Monthly';
        input.elevatedEPPPricingApplicable = false;
        input.commitmentStartDate = Date.today();
        input.commitmentEndDate = Date.today().addYears(5);
        return JSON.serialize(new List<EPPProductController.ProductInput>{ input });
    }

    /**
     * @description Builds one elevated-pricing consumable payload.
     * @param productCode Product code to add.
     * @param quantity Quantity to save.
     * @param frequency Consumption frequency.
     * @param eppPrice EPP Price. Null represents an incomplete Draft line.
     * @return Serialized ProductInput list.
     */
    private static String elevatedConsumableInputJson(
        String productCode,
        Decimal quantity,
        String frequency,
        Decimal eppPrice
    ) {
        EPPProductController.ProductInput input = new EPPProductController.ProductInput();
        input.pricebookEntryId = getEntry(productCode).Id;
        input.quantity = quantity;
        input.consumptionFrequency = frequency;
        input.elevatedEPPPricingApplicable = true;
        input.eppPrice = eppPrice;
        input.commitmentStartDate = Date.today();
        input.commitmentEndDate = Date.today().addYears(5);
        return JSON.serialize(new List<EPPProductController.ProductInput>{ input });
    }

    /**
     * @description Confirms capital and consumable searches return only their own eligible products.
     */
    @IsTest
    static void searchSeparatesCapitalAndConsumables() {
        Opportunity opportunityRecord = getOpportunity();

        Test.startTest();
        List<EPPProductController.ProductWrapper> capitalProducts =
            EPPProductController.searchProducts(opportunityRecord.Id, false, 'Eligible');
        List<EPPProductController.ProductWrapper> consumableProducts =
            EPPProductController.searchProducts(opportunityRecord.Id, true, 'Eligible');
        Test.stopTest();

        Assert.areEqual(1, capitalProducts.size(), 'Only eligible capital should be returned.');
        Assert.areEqual(CAPITAL_CODE, capitalProducts[0].productCode, 'Capital product expected.');
        Assert.areEqual('Sterilizers', capitalProducts[0].productFamily, 'Product Family should come from Product2.');
        Assert.areEqual('IMS', capitalProducts[0].businessUnit, 'Business Unit should come from Product2.');
        Assert.areEqual(1, consumableProducts.size(), 'Only eligible consumables should be returned.');
        Assert.areEqual(CONSUMABLE_CODE, consumableProducts[0].productCode, 'Consumable expected.');
    }

    /**
     * @description Confirms a product with USD and CAD Price Book Entries appears once, in the Opportunity currency.
     */
    @IsTest
    static void searchReturnsOneRowWhenProductHasMultipleCurrencies() {
        Opportunity opportunityRecord = getOpportunity();
        PricebookEntry usdEntry = getEntry(CAPITAL_CODE);
        insert new PricebookEntry(
            Pricebook2Id = opportunityRecord.Pricebook2Id,
            Product2Id = usdEntry.Product2Id,
            UnitPrice = 100,
            IsActive = true,
            CurrencyIsoCode = 'CAD'
        );

        Test.startTest();
        List<EPPProductController.ProductWrapper> capitalProducts =
            EPPProductController.searchProducts(opportunityRecord.Id, false, 'Eligible');
        Test.stopTest();

        Assert.areEqual(1, capitalProducts.size(), 'Only the Opportunity currency Price Book Entry should be returned.');
        Assert.areEqual(usdEntry.Id, capitalProducts[0].pricebookEntryId, 'USD Price Book Entry expected.');
    }

    /**
     * @description Confirms a flagged product on the Standard Price Book is returned when the Opportunity uses another Price Book.
     */
    @IsTest
    static void searchIgnoresOpportunityPriceBook() {
        Opportunity opportunityRecord = getOpportunity();
        String consumablePayload = consumableInputJson(CONSUMABLE_CODE, 1);
        Pricebook2 customPricebook = new Pricebook2(Name = 'GC-3431 Other Price Book', IsActive = true);
        insert customPricebook;
        opportunityRecord.Pricebook2Id = customPricebook.Id;
        update opportunityRecord;

        Test.startTest();
        List<EPPProductController.ProductWrapper> consumableProducts =
            EPPProductController.searchProducts(opportunityRecord.Id, true, CONSUMABLE_CODE);
        Integer createdCount = EPPProductController.createOpportunityProducts(
            opportunityRecord.Id,
            true,
            consumablePayload
        );
        Test.stopTest();

        OpportunityLineItem line = [
            SELECT PricebookEntry.Pricebook2Id
            FROM OpportunityLineItem
            WHERE OpportunityId = :opportunityRecord.Id
            LIMIT 1
        ];
        Assert.areEqual(1, consumableProducts.size(), 'The Standard Price Book consumable should be returned.');
        Assert.areEqual(1, createdCount, 'The consumable should be added from the Standard Price Book.');
        Assert.areEqual(
            customPricebook.Id,
            line.PricebookEntry.Pricebook2Id,
            'The Opportunity Product should use the Opportunity Price Book entry.'
        );
    }

    /**
     * @description Confirms capital and consumable products are inserted as separate Opportunity Products.
     */
    @IsTest
    static void createProductsBuildsSeparateOpportunityLines() {
        Opportunity opportunityRecord = getOpportunity();

        Test.startTest();
        Integer capitalCount = EPPProductController.createOpportunityProducts(
            opportunityRecord.Id,
            false,
            capitalInputJson(CAPITAL_CODE, 2, 125)
        );
        Integer consumableCount = EPPProductController.createOpportunityProducts(
            opportunityRecord.Id,
            true,
            consumableInputJson(CONSUMABLE_CODE, 5)
        );
        Test.stopTest();

        Assert.areEqual(1, capitalCount, 'One capital line expected.');
        Assert.areEqual(1, consumableCount, 'One consumable line expected.');

        List<OpportunityLineItem> lines = [
            SELECT Quantity, UnitPrice, Product2.ProductCode,
                   PlacementStartDate__c, PlacementEndDate__c,
                   ConsumptionFrequency__c, CommitmentStartDate__c, CommitmentEndDate__c
            FROM OpportunityLineItem
            WHERE OpportunityId = :opportunityRecord.Id
        ];
        Assert.areEqual(2, lines.size(), 'Both lines should be inserted.');

        Map<String, OpportunityLineItem> lineByCode = new Map<String, OpportunityLineItem>();
        for (OpportunityLineItem line : lines) {
            lineByCode.put(line.Product2.ProductCode, line);
        }
        Assert.areEqual(2, lineByCode.get(CAPITAL_CODE).Quantity, 'Capital quantity expected.');
        Assert.areEqual(125, lineByCode.get(CAPITAL_CODE).UnitPrice, 'Entered price expected.');
        Assert.areEqual(Date.today(), lineByCode.get(CAPITAL_CODE).PlacementStartDate__c, 'Placement start expected.');
        Assert.areEqual(Date.today().addYears(1), lineByCode.get(CAPITAL_CODE).PlacementEndDate__c, 'Placement end expected.');
        Assert.areEqual(5, lineByCode.get(CONSUMABLE_CODE).Quantity, 'Consumable quantity expected.');
        Assert.areEqual(
            getEntry(CONSUMABLE_CODE).UnitPrice,
            lineByCode.get(CONSUMABLE_CODE).UnitPrice,
            'List price should be used when no price is entered.'
        );
        Assert.areEqual('Monthly', lineByCode.get(CONSUMABLE_CODE).ConsumptionFrequency__c, 'Frequency expected.');
        Assert.areEqual(Date.today(), lineByCode.get(CONSUMABLE_CODE).CommitmentStartDate__c, 'Commitment start expected.');
        Assert.areEqual(Date.today().addYears(5), lineByCode.get(CONSUMABLE_CODE).CommitmentEndDate__c, 'Commitment end expected.');
    }

    /**
     * @description Confirms elevated pricing cannot be saved without an EPP Price.
     */
    @IsTest
    static void elevatedPricingRequiresEppPrice() {
        Opportunity opportunityRecord = getOpportunity();
        Boolean blocked = false;

        Test.startTest();
        try {
            EPPProductController.createOpportunityProducts(
                opportunityRecord.Id,
                true,
                elevatedConsumableInputJson(CONSUMABLE_CODE, 2, 'Monthly', null)
            );
        } catch (AuraHandledException expectedException) {
            blocked = expectedException.getMessage().contains(
                'Enter the EPP Price when Elevated / EPP Pricing Applicable is selected.'
            );
        }
        Test.stopTest();

        Assert.isTrue(blocked, 'Elevated pricing must require an EPP Price.');
        Assert.areEqual(0, [SELECT COUNT() FROM OpportunityLineItem], 'No line should be inserted.');
    }

    /**
     * @description Confirms One Time revenue equals quantity times EPP Price and is not repeated across the term.
     */
    @IsTest
    static void oneTimeRevenueIsCountedOnce() {
        Opportunity opportunityRecord = getOpportunity();
        Decimal eppPrice = 75;

        EPPProductController.createOpportunityProducts(
            opportunityRecord.Id,
            true,
            elevatedConsumableInputJson(CONSUMABLE_CODE, 4, 'One Time', eppPrice)
        );

        OpportunityLineItem line = [
            SELECT AnnualCommittedRevenue__c, ContractTermRevenue__c
            FROM OpportunityLineItem
            WHERE OpportunityId = :opportunityRecord.Id
              AND Product2.ProductCode = :CONSUMABLE_CODE
            LIMIT 1
        ];
        Assert.areEqual(300, line.AnnualCommittedRevenue__c, 'One-time annual revenue should be counted once.');
        Assert.areEqual(300, line.ContractTermRevenue__c, 'One-time contract revenue should be counted once.');
    }

    /**
     * @description Confirms an existing elevated consumable cannot be saved with a blank EPP Price.
     */
    @IsTest
    static void elevatedLineCannotBeSavedWithoutEppPrice() {
        Opportunity opportunityRecord = getOpportunity();
        EPPProductController.createOpportunityProducts(
            opportunityRecord.Id,
            true,
            elevatedConsumableInputJson(CONSUMABLE_CODE, 2, 'Monthly', 100)
        );
        OpportunityLineItem line = [
            SELECT Id
            FROM OpportunityLineItem
            WHERE OpportunityId = :opportunityRecord.Id
            LIMIT 1
        ];
        line.EPPPrice__c = null;

        Boolean blocked = false;
        Test.startTest();
        try {
            update line;
        } catch (DmlException expectedException) {
            blocked = expectedException.getMessage().contains(
                'Enter the EPP Price when Elevated / EPP Pricing Applicable is selected.'
            );
        }
        Test.stopTest();

        Assert.isTrue(blocked, 'Clearing EPP Price must be blocked while elevated pricing is selected.');
    }

    /**
     * @description Confirms the capital and consumable tables return only their own saved lines.
     */
    @IsTest
    static void getOpportunityProductsSeparatesExistingLines() {
        Opportunity opportunityRecord = getOpportunity();
        EPPProductController.createOpportunityProducts(
            opportunityRecord.Id,
            false,
            capitalInputJson(CAPITAL_CODE, 1, 100)
        );

        Test.startTest();
        List<EPPProductController.OpportunityProductWrapper> capitalLines =
            EPPProductController.getOpportunityProducts(opportunityRecord.Id, false);
        List<EPPProductController.OpportunityProductWrapper> consumableLines =
            EPPProductController.getOpportunityProducts(opportunityRecord.Id, true);
        Test.stopTest();

        Assert.areEqual(1, capitalLines.size(), 'Capital section should contain the capital line.');
        Assert.areEqual(CAPITAL_CODE, capitalLines[0].productCode, 'Capital product expected.');
        Assert.areEqual('Sterilizers', capitalLines[0].productFamily, 'Line Product Family should be derived.');
        Assert.areEqual('IMS', capitalLines[0].businessUnit, 'Line Business Unit should be derived.');
        Assert.isTrue(consumableLines.isEmpty(), 'Consumable section should remain empty.');
    }

    /**
     * @description Confirms a consumable cannot be saved from the Capital Equipment section.
     */
    @IsTest
    static void createRejectsWrongProductSection() {
        Opportunity opportunityRecord = getOpportunity();
        Boolean failed = false;

        Test.startTest();
        try {
            EPPProductController.createOpportunityProducts(
                opportunityRecord.Id,
                false,
                capitalInputJson(CONSUMABLE_CODE, 1, 100)
            );
        } catch (AuraHandledException expectedException) {
            failed = expectedException.getMessage().contains('not eligible');
        }
        Test.stopTest();

        Assert.isTrue(failed, 'A consumable must not be inserted from the capital section.');
        Assert.areEqual(0, [SELECT COUNT() FROM OpportunityLineItem], 'No line should be inserted.');
    }

    /**
     * @description Confirms a zero quantity and an unreadable product payload are rejected.
     */
    @IsTest
    static void createRejectsInvalidQuantityAndPayload() {
        Opportunity opportunityRecord = getOpportunity();
        Boolean quantityFailed = false;
        Boolean payloadFailed = false;

        Test.startTest();
        try {
            EPPProductController.createOpportunityProducts(
                opportunityRecord.Id,
                false,
                capitalInputJson(CAPITAL_CODE, 0, 100)
            );
        } catch (AuraHandledException expectedException) {
            quantityFailed = expectedException.getMessage().contains('Quantity');
        }

        try {
            EPPProductController.createOpportunityProducts(
                opportunityRecord.Id,
                false,
                'not-json'
            );
        } catch (AuraHandledException expectedException) {
            payloadFailed = expectedException.getMessage().contains('could not be read');
        }
        Test.stopTest();

        Assert.isTrue(quantityFailed, 'Zero quantity should be rejected.');
        Assert.isTrue(payloadFailed, 'Unreadable JSON should be rejected.');
    }

    /**
     * @description Confirms date order and a negative Sales Price are rejected before insert.
     */
    @IsTest
    static void createRejectsInvalidDatesAndNegativePrice() {
        Opportunity opportunityRecord = getOpportunity();
        EPPProductController.ProductInput consumableInput = new EPPProductController.ProductInput();
        consumableInput.pricebookEntryId = getEntry(CONSUMABLE_CODE).Id;
        consumableInput.quantity = 1;
        consumableInput.consumptionFrequency = 'Monthly';
        consumableInput.elevatedEPPPricingApplicable = false;
        consumableInput.commitmentStartDate = Date.today();
        consumableInput.commitmentEndDate = Date.today().addDays(-1);

        EPPProductController.ProductInput capitalInput = new EPPProductController.ProductInput();
        capitalInput.pricebookEntryId = getEntry(CAPITAL_CODE).Id;
        capitalInput.quantity = 1;
        capitalInput.unitPrice = -1;
        capitalInput.placementStartDate = Date.today();
        capitalInput.placementEndDate = Date.today().addDays(-1);

        Boolean commitmentDatesFailed = false;
        Boolean negativePriceFailed = false;

        Test.startTest();
        try {
            EPPProductController.createOpportunityProducts(
                opportunityRecord.Id,
                true,
                JSON.serialize(new List<EPPProductController.ProductInput>{ consumableInput })
            );
        } catch (AuraHandledException expectedException) {
            commitmentDatesFailed = expectedException.getMessage().contains(
                'Commitment End Date cannot be earlier'
            );
        }

        try {
            EPPProductController.createOpportunityProducts(
                opportunityRecord.Id,
                false,
                JSON.serialize(new List<EPPProductController.ProductInput>{ capitalInput })
            );
        } catch (AuraHandledException expectedException) {
            negativePriceFailed = expectedException.getMessage().contains('cannot be negative');
        }
        Test.stopTest();

        Assert.isTrue(commitmentDatesFailed, 'Commitment end date must not precede the start date.');
        Assert.isTrue(negativePriceFailed, 'A negative Sales Price must be rejected.');
        Assert.areEqual(0, [SELECT COUNT() FROM OpportunityLineItem], 'No line should be inserted.');
    }

    /**
     * @description Confirms revenue formulas stay blank until an approved consumption frequency is selected.
     */
    @IsTest
    static void revenueRemainsBlankWithoutApprovedFrequency() {
        Opportunity opportunityRecord = getOpportunity();
        PricebookEntry consumableEntry = getEntry(CONSUMABLE_CODE);
        insert new OpportunityLineItem(
            OpportunityId = opportunityRecord.Id,
            PricebookEntryId = consumableEntry.Id,
            Quantity = 2,
            UnitPrice = consumableEntry.UnitPrice,
            CommitmentStartDate__c = Date.today(),
            CommitmentEndDate__c = Date.today().addYears(1)
        );

        OpportunityLineItem line = [
            SELECT AnnualCommittedRevenue__c, ContractTermRevenue__c
            FROM OpportunityLineItem
            WHERE OpportunityId = :opportunityRecord.Id
              AND Product2.ProductCode = :CONSUMABLE_CODE
            LIMIT 1
        ];
        Assert.isNull(line.AnnualCommittedRevenue__c, 'Annual revenue needs an approved frequency.');
        Assert.isNull(line.ContractTermRevenue__c, 'Contract-term revenue needs annual revenue.');
    }

    /**
     * @description Confirms incomplete Service details block an EPP from leaving Draft.
     */
    @IsTest
    static void incompleteServiceDetailsAllowedInDraftButNotBeyond() {
        Opportunity opportunityRecord = getOpportunity();
        opportunityRecord.ServiceCommitment__c = true;
        update opportunityRecord;

        opportunityRecord.StageName = 'Discovery';
        Boolean blocked = false;
        Test.startTest();
        try {
            update opportunityRecord;
        } catch (DmlException expectedException) {
            blocked = expectedException.getMessage().contains('Service Type')
                || expectedException.getMessage().contains('Annual Service Amount')
                || expectedException.getMessage().contains('Service Start Date');
        }
        Test.stopTest();

        Assert.isTrue(blocked, 'Incomplete Service details must block progression beyond Draft.');
    }

    /**
     * @description Confirms Service End Date cannot be earlier than Service Start Date.
     */
    @IsTest
    static void serviceEndDateCannotPrecedeStartDate() {
        Opportunity opportunityRecord = getOpportunity();
        opportunityRecord.ServiceCommitment__c = true;
        opportunityRecord.ServiceType__c = 'Preventative Maintenance Only';
        opportunityRecord.AnnualServiceAmount__c = 1000;
        opportunityRecord.PreventativeMaintenanceFrequency__c = 'Monthly';
        opportunityRecord.ServiceStartDate__c = Date.today();
        opportunityRecord.ServiceEndDate__c = Date.today().addDays(-1);

        Boolean blocked = false;
        Test.startTest();
        try {
            update opportunityRecord;
        } catch (DmlException expectedException) {
            blocked = expectedException.getMessage().contains(
                'Service End Date cannot be earlier than Service Start Date'
            );
        }
        Test.stopTest();

        Assert.isTrue(blocked, 'An invalid Service date range must be rejected.');
    }

    /**
     * @description Confirms complete Service details allow an approved EPP to leave Draft.
     */
    @IsTest
    static void completeServiceDetailsCanLeaveDraft() {
        Opportunity opportunityRecord = getOpportunity();
        opportunityRecord.ServiceCommitment__c = true;
        opportunityRecord.ServiceType__c = 'Full Service / Comprehensive Coverage';
        opportunityRecord.AnnualServiceAmount__c = 1000;
        opportunityRecord.PreventativeMaintenanceFrequency__c = 'Quarterly';
        opportunityRecord.ServiceStartDate__c = Date.today();
        opportunityRecord.ServiceEndDate__c = Date.today().addYears(1);
        opportunityRecord.EPP_All_Approvals_Complete__c = true;
        opportunityRecord.StageName = 'Discovery';

        Test.startTest();
        update opportunityRecord;
        Test.stopTest();

        Opportunity savedOpportunity = [
            SELECT StageName
            FROM Opportunity
            WHERE Id = :opportunityRecord.Id
        ];
        Assert.areEqual('Discovery', savedOpportunity.StageName, 'Complete Service details should permit progression.');
    }
}