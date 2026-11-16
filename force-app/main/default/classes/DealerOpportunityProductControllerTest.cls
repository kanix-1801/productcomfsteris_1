/**
 * @description #GC-3047 Tests for dealer product search and save. EPP product tests stay in EPPProductControllerTest.
 */
@IsTest(SeeAllData=false)
private class DealerOpportunityProductControllerTest {
    @IsTest
    static void search_excludesServiceAndMatchesName() {
        Opportunity opportunity = insertDealerOpportunity();
        Product2 eligible = insertProduct('Dealer Pump', 'DP-1', null);
        eligible.ItemFamily__c = 'Sterilizers';
        eligible.BusinessUnit__c = 'IMS';
        update eligible;
        Product2 service = insertProduct('Dealer Service', 'DS-1', 'SERVICE');
        insertPrice(opportunity, eligible, 25);
        insertPrice(opportunity, service, 15);

        Test.startTest();
        List<DealerOpportunityProductController.ProductOption> results =
            DealerOpportunityProductController.searchProducts(opportunity.Id, 'Dealer');
        Test.stopTest();

        System.assertEquals(1, results.size(), 'Service products stay out of dealer search');
        System.assertEquals('Dealer Pump', results[0].productName);
        System.assertEquals('Sterilizers', results[0].productFamily);
        System.assertEquals('IMS', results[0].businessUnit);
        System.assertEquals('USD', results[0].currencyCode);
        System.assertEquals(false, results[0].recentlyAdded, 'A typed search keeps products that were not added by this dealer unmarked');
    }

    @IsTest
    static void search_blankPutsThisDealersRecentProductsFirst() {
        Account account = insertAccount();
        Opportunity current = insertDealerOpportunity(account);
        Opportunity earlier = insertDealerOpportunity(account);
        Opportunity later = insertDealerOpportunity(account);
        Account otherAccount = insertAccount();
        Opportunity otherDealer = insertDealerOpportunity(otherAccount);
        Product2 olderProduct = insertProduct('Older Catalog Item', 'OLD-1', null);
        Product2 newerProduct = insertProduct('Newer Catalog Item', 'NEW-1', null);
        Product2 otherProduct = insertProduct('Other Catalog Item', 'OTH-1', null);
        Product2 otherAccountProduct = insertProduct('Outside Catalog Item', 'OUT-1', null);
        PricebookEntry olderEntry = insertPrice(current, olderProduct, 10);
        PricebookEntry newerEntry = insertPrice(current, newerProduct, 12);
        insertPrice(current, otherProduct, 14);
        PricebookEntry outsideEntry = insertPrice(current, otherAccountProduct, 16);
        insertLine(earlier, olderEntry);
        insertLine(later, newerEntry);
        insertLine(otherDealer, outsideEntry);
        Test.setCreatedDate(lineId(earlier), DateTime.now().addDays(-2));
        Test.setCreatedDate(lineId(later), DateTime.now().addDays(-1));

        Test.startTest();
        List<DealerOpportunityProductController.ProductOption> blank =
            DealerOpportunityProductController.searchProducts(current.Id, null);
        List<DealerOpportunityProductController.ProductOption> typed =
            DealerOpportunityProductController.searchProducts(current.Id, 'Other Catalog');
        Test.stopTest();

        System.assertEquals(newerProduct.Id, blank[0].productId, 'The newest product added by this dealer is first');
        System.assertEquals(true, blank[0].recentlyAdded);
        System.assertEquals(olderProduct.Id, blank[1].productId);
        System.assertEquals(true, blank[1].recentlyAdded);
        Boolean otherMarked = false;
        Boolean outsidePresent = false;
        for (DealerOpportunityProductController.ProductOption option : blank) {
            if (option.productId == otherProduct.Id) {
                otherMarked = option.recentlyAdded;
            }
            if (option.productId == otherAccountProduct.Id) {
                outsidePresent = option.recentlyAdded;
            }
        }
        System.assertEquals(false, otherMarked, 'A price book product this dealer has not added stays unmarked');
        System.assertEquals(false, outsidePresent, 'Another dealer account does not supply recently added products');
        System.assertEquals(1, typed.size(), 'A typed search still filters the price book by name');
        System.assertEquals(otherProduct.Id, typed[0].productId);
        System.assertEquals(false, typed[0].recentlyAdded);
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
    static void create_convertsSelectedCurrencyIntoOpportunityCurrency() {
        Opportunity opportunity = insertDealerOpportunity();
        Product2 eligible = insertProduct('Dealer Pump', 'DP-1', null);
        PricebookEntry eligibleEntry = insertPrice(opportunity, eligible, 25);
        CurrencyType entered = [
            SELECT ConversionRate
            FROM CurrencyType
            WHERE IsoCode = 'EUR' AND IsActive = true
            LIMIT 1
        ];
        CurrencyType opportunityCurrency = [
            SELECT ConversionRate, DecimalPlaces
            FROM CurrencyType
            WHERE IsoCode = 'USD'
            LIMIT 1
        ];
        Decimal enteredPrice = 86;
        Integer places = opportunityCurrency.DecimalPlaces == null ? 2 : opportunityCurrency.DecimalPlaces;
        Decimal expected = (enteredPrice * opportunityCurrency.ConversionRate / entered.ConversionRate)
            .setScale(places, System.RoundingMode.HALF_UP);

        Test.startTest();
        DealerOpportunityProductController.DealerContext context =
            DealerOpportunityProductController.getDealerContext(opportunity.Id);
        DealerOpportunityProductController.createProducts(
            opportunity.Id,
            JSON.serialize(new List<Object>{
                new Map<String, Object>{
                    'pricebookEntryId' => eligibleEntry.Id,
                    'quantity' => 1,
                    'unitPrice' => enteredPrice,
                    'currencyCode' => 'EUR'
                }
            })
        );
        Test.stopTest();

        System.assertEquals('USD', context.currencyCode);
        System.assert(context.currencies.size() > 1, 'Active corporate currencies are available to the dealer');
        OpportunityLineItem line = [
            SELECT UnitPrice
            FROM OpportunityLineItem
            WHERE OpportunityId = :opportunity.Id
        ];
        System.assertEquals(expected, line.UnitPrice);
        System.assertEquals(expected, [SELECT Amount FROM Opportunity WHERE Id = :opportunity.Id].Amount);
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
        return insertDealerOpportunity(insertAccount());
    }

    private static Opportunity insertDealerOpportunity(Account account) {
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

    private static void insertLine(Opportunity opportunity, PricebookEntry entry) {
        DealerOpportunityProductController.createProducts(
            opportunity.Id,
            JSON.serialize(new List<Object>{
                new Map<String, Object>{
                    'pricebookEntryId' => entry.Id,
                    'quantity' => 1,
                    'unitPrice' => entry.UnitPrice
                }
            })
        );
    }

    private static Id lineId(Opportunity opportunity) {
        return [
            SELECT Id
            FROM OpportunityLineItem
            WHERE OpportunityId = :opportunity.Id
            LIMIT 1
        ].Id;
    }
}