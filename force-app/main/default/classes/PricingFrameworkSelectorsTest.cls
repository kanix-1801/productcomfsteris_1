/**
 * @description GW-4585 - Coverage for pricing-related selector methods.
 */
@IsTest
private class PricingFrameworkSelectorsTest {
    @IsTest
    static void quoteLineItemSelector_nullGuardsAndConstructor() {
        Test.startTest();
        System.assertNotEquals(null, new QuoteLineItemSelector());
        System.assertEquals(0, QuoteLineItemSelector.selectByOpportunityIds(null).size());
        System.assertEquals(0, QuoteLineItemSelector.selectByOpportunityIds(new Set<Id>()).size());
        System.assertEquals(0, QuoteLineItemSelector.selectForQuoteEmailReplyByQuoteId(null).size());
        System.assertEquals(0, QuoteLineItemSelector.selectForApproveRejectByQuoteId(null).size());
        System.assertEquals(null, QuoteLineItemSelector.selectForApproveRejectById(null));
        System.assertEquals(
            0,
            QuoteLineItemSelector.selectQuoteLineItemById(null, new List<String>{ 'Id' }).size()
        );
        System.assertEquals(
            0,
            QuoteLineItemSelector.selectQuoteLineItemById(
                UserInfo.getUserId(),
                new List<String>()
            ).size()
        );
        System.assertEquals(0, QuoteLineItemSelector.selectForPricingFrameworkByQuoteIds(null).size());
        System.assertEquals(
            0,
            QuoteLineItemSelector.selectForPricingFrameworkHeadlessByIds(null).size()
        );
        Test.stopTest();
    }

    @IsTest
    static void quoteLineItemSelector_runsPricingAndRepairQueries() {
        Id fakeQuoteId = fakeIdForType(Quote.SObjectType);
        Id fakeLineId = fakeIdForType(QuoteLineItem.SObjectType);
        Id fakeOppId = fakeIdForType(Opportunity.SObjectType);

        Test.startTest();
        System.assertEquals(
            0,
            QuoteLineItemSelector.selectForPricingFrameworkByQuoteIds(
                new Set<Id>{ fakeQuoteId }
            ).size()
        );
        System.assertEquals(
            0,
            QuoteLineItemSelector.selectForPricingFrameworkHeadlessByIds(
                new Set<Id>{ fakeLineId }
            ).size()
        );
        System.assertEquals(
            0,
            QuoteLineItemSelector.selectByOpportunityIds(new Set<Id>{ fakeOppId }).size()
        );
        System.assertEquals(
            0,
            QuoteLineItemSelector.selectForQuoteEmailReplyByQuoteId(fakeQuoteId).size()
        );
        System.assertEquals(
            0,
            QuoteLineItemSelector.selectForApproveRejectByQuoteId(fakeQuoteId).size()
        );
        System.assertEquals(null, QuoteLineItemSelector.selectForApproveRejectById(fakeLineId));
        System.assertEquals(
            0,
            QuoteLineItemSelector.selectQuoteLineItemById(
                fakeLineId,
                new List<String>{ 'Id', 'Product2.ProductCode', 'Quantity' }
            ).size()
        );
        Test.stopTest();
    }

    @IsTest
    static void accountSelector_oraclePricingQueries() {
        Account customer = insertCustomerAccount('9001', '82');
        insertAddressAccount(customer.Id, '9002', '82', 'Active');

        Test.startTest();
        System.assertEquals(0, AccountSelector.selectForOraclePricingByIds(null).size());
        System.assertEquals(0, AccountSelector.selectOracleAddressAccountsForPricing(null).size());
        Map<Id, Account> accounts = AccountSelector.selectForOraclePricingByIds(
            new Set<Id>{ customer.Id }
        );
        List<Account> addresses = AccountSelector.selectOracleAddressAccountsForPricing(
            customer.Id
        );
        Test.stopTest();

        System.assertEquals(1, accounts.size());
        System.assertEquals('9001', accounts.get(customer.Id).AccountNumber);
        System.assertEquals(1, addresses.size(), 'Active address child should be returned.');
        System.assertEquals('9002', addresses[0].AccountNumber);
    }

    @IsTest
    static void product2Selector_pricingQueries() {
        Product2 product = new Product2(
            Name = 'GW4585 Selector Product',
            ProductCode = 'SEL-4585',
            PricingSource__c = 'Oracle',
            IsActive = true
        );
        insert product;

        Test.startTest();
        System.assertEquals(0, Product2Selector.selectPricingSourceByProductCodes(null).size());
        System.assertEquals(0, Product2Selector.selectIdsByProductCodes(null).size());
        System.assertEquals(
            0,
            Product2Selector.selectSellingModelOptionsByProductIds(null).size()
        );
        List<Product2> sources = Product2Selector.selectPricingSourceByProductCodes(
            new Set<String>{ 'SEL-4585' }
        );
        List<Product2> ids = Product2Selector.selectIdsByProductCodes(
            new Set<String>{ 'SEL-4585' }
        );
        Product2Selector.selectOneTimeSellingModelId();
        Test.stopTest();

        System.assertEquals(1, sources.size());
        System.assertEquals('Oracle', sources[0].PricingSource__c);
        System.assertEquals(product.Id, ids[0].Id);
    }

    @IsTest
    static void product2Selector_catalogAndPsamQueries() {
        Product2 product = new Product2(
            Name = 'GW4585 Searchable Widget',
            ProductCode = 'GW4585-SRCH-01',
            IsActive = true
        );
        insert product;

        Test.startTest();
        System.assertEquals(0, Product2Selector.selectPsamByIds(null).size());
        System.assertEquals(0, Product2Selector.selectActiveByIds(null).size());
        List<Product2> psamRows = Product2Selector.selectPsamByIds(new Set<Id>{ product.Id });
        List<Product2> activeRows = Product2Selector.selectActiveByIds(new Set<Id>{ product.Id });
        List<Product2> searchHits = Product2Selector.selectActiveBySearchKey('GW4585-SRCH');
        List<Product2> browsePage = Product2Selector.selectActiveBySearchKey('');
        List<Product2> escapedSearch = Product2Selector.selectActiveBySearchKey('50%');
        Test.stopTest();

        System.assertEquals(1, psamRows.size());
        System.assertEquals(1, activeRows.size());
        System.assertEquals(product.Id, activeRows[0].Id);
        System.assert(!searchHits.isEmpty(), 'Search should find the active product by code.');
        System.assert(browsePage != null, 'Blank search should return a browse list.');
        System.assert(escapedSearch != null, 'Wildcard search input should be escaped safely.');
    }

    @IsTest
    static void pricebookEntriesSelector_standardPricebookAndEntries() {
        User testUser = new User(Id = UserInfo.getUserId());
        System.runAs(testUser) {
            adb_Product2 productBuilder = new adb_Product2()
                .name('GW4585 PBE Product')
                .productCode('PBE-4585');
            new adb_PricebookEntry()
                .product(productBuilder)
                .unitPrice(12)
                .persist();

            Product2 product = [
                SELECT Id
                FROM Product2
                WHERE ProductCode = 'PBE-4585'
                LIMIT 1
            ];
            PricebookEntry persistedEntry = [
                SELECT Id, Pricebook2Id, Product2Id, CurrencyIsoCode
                FROM PricebookEntry
                WHERE Product2Id = :product.Id
                LIMIT 1
            ];
            String currencyCode = persistedEntry.CurrencyIsoCode;
            if (String.isBlank(currencyCode)) {
                currencyCode = UserInfo.getDefaultCurrency();
            }

            Test.startTest();
            Id resolvedPricebookId = PricebookEntriesSelector.selectStandardPricebookId();
            Id cachedPricebookId = PricebookEntriesSelector.selectStandardPricebookId();
            List<PricebookEntry> nullGuard =
                PricebookEntriesSelector.selectActiveByPricebookProductAndCurrency(
                    null,
                    new Set<Id>{ product.Id },
                    currencyCode
                );
            List<PricebookEntry> matches =
                PricebookEntriesSelector.selectActiveByPricebookProductAndCurrency(
                    persistedEntry.Pricebook2Id,
                    new Set<Id>{ product.Id },
                    currencyCode
                );
            Test.stopTest();

            System.assertEquals(persistedEntry.Pricebook2Id, resolvedPricebookId);
            System.assertEquals(cachedPricebookId, resolvedPricebookId, 'Second call should use cached Id.');
            System.assertEquals(0, nullGuard.size());
            System.assertEquals(1, matches.size());
            System.assertEquals(persistedEntry.Id, matches[0].Id);
        }
    }

    @IsTest
    static void workOrderLineItemsSelector_pricingFrameworkQueries() {
        Test.startTest();
        System.assertEquals(
            0,
            WorkOrderLineItemsSelector.selectForPricingFrameworkByWorkOrderIds(null).size()
        );
        System.assertEquals(
            0,
            WorkOrderLineItemsSelector.selectForPricingFrameworkHeadlessByIds(null).size()
        );
        Test.stopTest();
    }

    private static Id fakeIdForType(Schema.SObjectType sobjectType) {
        return (Id) (String.valueOf(sobjectType.getDescribe().getKeyPrefix()) + '000000000AAA');
    }

    private static Account insertCustomerAccount(String accountNumber, String orgId) {
        Account account = new Account(
            Name = 'GW4585 Selector Account ' + accountNumber,
            SourceSystemID__c = 'ORACLE-SEL-' + accountNumber,
            AccountNumber = accountNumber,
            OrgIDs__c = orgId
        );
        insert account;
        return account;
    }

    private static Account insertAddressAccount(
        Id parentId,
        String accountNumber,
        String orgId,
        String status
    ) {
        Account addressAccount = new Account(
            Name = 'GW4585 Selector Address ' + accountNumber,
            ParentId = parentId,
            Type = 'Address',
            SourceSystemID__c = 'ORACLE-SEL-ADDR-' + accountNumber,
            AccountNumber = accountNumber,
            OrgIDs__c = orgId,
            OracleAddressId__c = 'SITE-' + accountNumber,
            ShiptoAddressStatus__c = status
        );
        insert addressAccount;
        return addressAccount;
    }
}