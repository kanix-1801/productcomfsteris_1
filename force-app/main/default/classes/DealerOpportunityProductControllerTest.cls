/**
 * @description #GC-3047 Tests for dealer product search and save. EPP product tests stay in EPPProductControllerTest.
 */
@IsTest(SeeAllData=false)
private class DealerOpportunityProductControllerTest {
    @IsTest
    static void search_excludesServiceAndMatchesName() {
        Opportunity opportunity = insertDealerOpportunity();
        Product2 eligible = insertProduct('Dealer Pump', 'DP-1', null);
        Product2 service = insertProduct('Dealer Service', 'DS-1', 'SERVICE');
        insertPrice(opportunity, eligible, 25);
        insertPrice(opportunity, service, 15);

        Test.startTest();
        List<DealerOpportunityProductController.ProductOption> results =
            DealerOpportunityProductController.searchProducts(opportunity.Id, 'Dealer');
        Test.stopTest();

        System.assertEquals(1, results.size(), 'Service products stay out of dealer search');
        System.assertEquals('Dealer Pump', results[0].productName);
        System.assertEquals('USD', results[0].currencyCode);
    }

    @IsTest
    static void search_rejectsNonDealerOpportunity() {
        Account account = insertAccount();
        Opportunity opportunity = new Opportunity(
            Name = 'Direct Opportunity',
            AccountId = account.Id,
            StageName = 'Discovery',
            CloseDate = Date.today().addDays(20),
            Pricebook2Id = Test.getStandardPricebookId(),
            BypassValidations__c = true
        );
        insert opportunity;
        Boolean threw = false;

        try {
            DealerOpportunityProductController.searchProducts(opportunity.Id, 'Dealer');
        } catch (AuraHandledException ex) {
            threw = true;
        }

        System.assertEquals(true, threw, 'EPP and other opportunities stay out of the dealer search');
    }

    @IsTest
    static void create_writesDealerLineAndBlocksServiceEntry() {
        Opportunity opportunity = insertDealerOpportunity();
        Product2 eligible = insertProduct('Dealer Pump', 'DP-1', null);
        Product2 service = insertProduct('Dealer Service', 'DS-1', 'SERVICE');
        PricebookEntry eligibleEntry = insertPrice(opportunity, eligible, 25);
        PricebookEntry serviceEntry = insertPrice(opportunity, service, 15);
        String payload = JSON.serialize(new List<Object>{
            new Map<String, Object>{
                'pricebookEntryId' => eligibleEntry.Id,
                'quantity' => 2,
                'unitPrice' => 30,
                'comments' => 'Dealer estimate'
            }
        });

        Test.startTest();
        Integer created = DealerOpportunityProductController.createProducts(opportunity.Id, payload);
        Test.stopTest();

        System.assertEquals(1, created);
        OpportunityLineItem line = [
            SELECT Quantity, UnitPrice, Status__c, ConfidenceLevel__c, ExpectedOrderDate__c,
                ExpectedShipDate__c, Comments__c
            FROM OpportunityLineItem
            WHERE OpportunityId = :opportunity.Id
        ];
        System.assertEquals(2, line.Quantity);
        System.assertEquals(30, line.UnitPrice);
        System.assertEquals('Open', line.Status__c);
        System.assertEquals('Pipeline', line.ConfidenceLevel__c);
        System.assertEquals(opportunity.CloseDate, line.ExpectedOrderDate__c);
        System.assertEquals(opportunity.Expected_Ship_Date__c, line.ExpectedShipDate__c);
        System.assertEquals('Dealer estimate', line.Comments__c);

        Boolean blocked = false;
        try {
            DealerOpportunityProductController.createProducts(
                opportunity.Id,
                JSON.serialize(new List<Object>{
                    new Map<String, Object>{
                        'pricebookEntryId' => serviceEntry.Id,
                        'quantity' => 1,
                        'unitPrice' => 10
                    }
                })
            );
        } catch (AuraHandledException ex) {
            blocked = true;
        }
        System.assertEquals(true, blocked, 'A service price book entry cannot be saved');
    }

    @IsTest
    static void getAndDelete_roundTripTheDealerLine() {
        Opportunity opportunity = insertDealerOpportunity();
        Product2 eligible = insertProduct('Dealer Pump', 'DP-1', null);
        PricebookEntry eligibleEntry = insertPrice(opportunity, eligible, 25);
        DealerOpportunityProductController.createProducts(
            opportunity.Id,
            JSON.serialize(new List<Object>{
                new Map<String, Object>{
                    'pricebookEntryId' => eligibleEntry.Id,
                    'quantity' => 1,
                    'unitPrice' => 25
                }
            })
        );

        List<DealerOpportunityProductController.ProductLine> lines =
            DealerOpportunityProductController.getProducts(opportunity.Id);
        System.assertEquals(1, lines.size());
        System.assertEquals('USD', lines[0].currencyCode);

        Test.startTest();
        DealerOpportunityProductController.deleteProduct(opportunity.Id, lines[0].opportunityLineItemId);
        Test.stopTest();

        System.assertEquals(0, [SELECT COUNT() FROM OpportunityLineItem WHERE OpportunityId = :opportunity.Id]);
    }

    private static Opportunity insertDealerOpportunity() {
        Account account = insertAccount();
        Opportunity opportunity = new Opportunity(
            Name = 'Dealer Product Opportunity',
            AccountId = account.Id,
            StageName = 'Evaluation',
            CloseDate = Date.today().addDays(30),
            Expected_Ship_Date__c = Date.today().addDays(45),
            ForecastConfidenceLevel__c = 'Pipeline',
            Pricebook2Id = Test.getStandardPricebookId(),
            CurrencyIsoCode = 'USD',
            BypassValidations__c = true
        );
        Schema.RecordTypeInfo dealerType = Schema.SObjectType.Opportunity
            .getRecordTypeInfosByDeveloperName()
            .get('HCSalesDealer');
        System.assertNotEquals(null, dealerType, 'HC Sales - Dealer record type is required');
        opportunity.RecordTypeId = dealerType.getRecordTypeId();
        insert opportunity;
        return opportunity;
    }

    private static Account insertAccount() {
        Account account = new Account(Name = 'Dealer Product Account');
        insert account;
        return account;
    }

    private static Product2 insertProduct(String name, String code, String salesCategoryCode) {
        Product2 product = new Product2(
            Name = name,
            ProductCode = code,
            IsActive = true,
            SalesCategoryCode__c = salesCategoryCode
        );
        insert product;
        return product;
    }

    private static PricebookEntry insertPrice(Opportunity opportunity, Product2 product, Decimal price) {
        PricebookEntry entry = new PricebookEntry(
            Pricebook2Id = opportunity.Pricebook2Id,
            Product2Id = product.Id,
            UnitPrice = price,
            IsActive = true,
            CurrencyIsoCode = opportunity.CurrencyIsoCode
        );
        insert entry;
        return entry;
    }
}