/**
 * @description GW-5892: Shared test data for Field Service Quote tests.
 * @group Field Service Quote
 */
@IsTest
public class FieldServiceQuoteTestData {
    public static final String CURRENCY_CODE = 'USD';
    public static final String PART_CODE = 'GW5892-PART-1';
    public static final String UNPRICED_PART_CODE = 'GW5892-PART-NOPRICE';
    public static final Decimal PART_PRICE = 125;

    /**
     * @description Created records for a scenario.
     */
    public class Scenario {
        public Account account;
        public RateList__c rateList;
        public WorkOrder workOrder;
        public Product2 part;
        public Product2 unpricedPart;
        public Map<String, Product2> productByCode = new Map<String, Product2>();
    }

    /**
     * @description Account, Rate List, Work Order on the standard price book, priced products (part, labor,
     *              travel, expense) and Products Required on the Work Order (one priced, one without a price).
     * @return Scenario
     */
    public static Scenario createScenario() {
        Scenario scenario = new Scenario();
        scenario.rateList = new RateList__c(
            Name = 'GW5892 Rate List',
            LaborHour__c = 150,
            TravelHour__c = 100,
            PremiumRateHour__c = 200,
            TravelZone1__c = 95
        );
        insert scenario.rateList;

        scenario.account = new Account(
            Name = 'GW5892 Customer',
            SourceSystemID__c = 'ORACLE-GW5892-' + String.valueOf(Crypto.getRandomInteger()),
            RateList__c = scenario.rateList.Id
        );
        insert scenario.account;

        List<Product2> products = new List<Product2>{
            new Product2(Name = 'GW5892 Gasket', ProductCode = PART_CODE, IsActive = true),
            new Product2(Name = 'GW5892 Unpriced', ProductCode = UNPRICED_PART_CODE, IsActive = true),
            new Product2(Name = 'FS Labor', ProductCode = System.Label.FS_Quote_Labor_Product_Code, IsActive = true),
            new Product2(Name = 'FS Travel', ProductCode = System.Label.FS_Quote_Travel_Product_Code, IsActive = true),
            new Product2(Name = 'FS Expense', ProductCode = System.Label.FS_Quote_Expense_Product_Code, IsActive = true)
        };
        insert products;
        for (Product2 product : products) {
            scenario.productByCode.put(product.ProductCode, product);
        }
        scenario.part = scenario.productByCode.get(PART_CODE);
        scenario.unpricedPart = scenario.productByCode.get(UNPRICED_PART_CODE);

        Id pricebookId = Test.getStandardPricebookId();
        List<PricebookEntry> entries = new List<PricebookEntry>();
        for (Product2 product : products) {
            if (product.Id == scenario.unpricedPart.Id) {
                continue;
            }
            entries.add(
                new PricebookEntry(
                    Pricebook2Id = pricebookId,
                    Product2Id = product.Id,
                    UnitPrice = product.Id == scenario.part.Id ? PART_PRICE : 0,
                    CurrencyIsoCode = CURRENCY_CODE,
                    IsActive = true
                )
            );
        }
        insert entries;

        scenario.workOrder = new WorkOrder(
            AccountId = scenario.account.Id,
            Subject = 'GW5892 Field Service Quote WO',
            Pricebook2Id = pricebookId,
            CurrencyIsoCode = CURRENCY_CODE,
            RateList__c = scenario.rateList.Id
        );
        insert scenario.workOrder;

        insert new List<ProductRequired>{
            new ProductRequired(
                ParentRecordId = scenario.workOrder.Id,
                Product2Id = scenario.part.Id,
                QuantityRequired = 2
            ),
            new ProductRequired(
                ParentRecordId = scenario.workOrder.Id,
                Product2Id = scenario.unpricedPart.Id,
                QuantityRequired = 1
            )
        };
        return scenario;
    }
}