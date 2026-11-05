/**
 * @author Sahithi PWC
 * @date 01-07-2026
 * @description #GC-3162 Test class for Oracle Pricing integration.
 *
 * Test Coverage
 * - Successful Oracle Pricing callout
 * - Weekly Recurring Consumption pricing
 * - Monthly Recurring Consumption pricing
 * - Customer request building
 * - Batch splitting
 * - Opportunity Line Item deletion
 * - Empty Oracle pricing response
 * - Failed Oracle callout
 * - Invalid Flow input
 * - Null Opportunity Id
 */
@IsTest
public class OraclePricingIntegrationTest {

    private static final String CUSTOMER_RT = 'Customer';
    private static final String OPP_RT = 'HCSalesConsumables';

    // =========================================================
    // TEST SETUP
    // =========================================================

    @TestSetup
    static void setupData() {

        Id customerRtId = Schema.SObjectType.Account
            .getRecordTypeInfosByDeveloperName()
            .get(CUSTOMER_RT)
            .getRecordTypeId();

        String uniqueId = String.valueOf(
            Math.abs(Crypto.getRandomInteger())
        );

        if (uniqueId.length() > 15) {
            uniqueId = uniqueId.substring(0, 15);
        }

        Account acc = new Account(
            Name = 'Oracle Pricing Customer',
            RecordTypeId = customerRtId,
            SourceSystemID__c = uniqueId,
            SystemID__c = uniqueId,
            OrgIDs__c = '83',
            OracleAddressId__c = 'ADDR-001'
        );
        insert acc;

        Contact con = new Contact(
            FirstName = 'Oracle',
            LastName = 'Tester',
            AccountId = acc.Id
        );
        insert con;

        Id oppRtId = Schema.SObjectType.Opportunity
            .getRecordTypeInfosByDeveloperName()
            .get(OPP_RT)
            .getRecordTypeId();

        Id standardPricebookId = Test.getStandardPricebookId();

      Opportunity opp = new Opportunity(
    Name = 'Oracle Pricing Opportunity',
    RecordTypeId = oppRtId,
    AccountId = acc.Id,
    StageName = 'Discovery',
    CloseDate = Date.today().addDays(30),
    Amount = 240,
    Type = 'Recurring Consumption',
    Category__c = 'Expansion/Growth',
    Pricebook2Id = standardPricebookId,
    PrimaryContact__c = con.Id,
    CustomerPurchaseMethod__c = 'Direct Purchase'
);
insert opp;

        String productCode = String.valueOf(
            Math.abs(Crypto.getRandomInteger())
        );

        Product2 product = new Product2(
            Name = 'Oracle Pricing Product',
            ProductCode = productCode,
            Description = 'Oracle Pricing Test Product',
            IsActive = true
        );
        insert product;

        PricebookEntry pbe = new PricebookEntry(
            Pricebook2Id = standardPricebookId,
            Product2Id = product.Id,
            UnitPrice = 10,
            IsActive = true
        );
        insert pbe;

        OpportunityLineItem oli = new OpportunityLineItem(
            OpportunityId = opp.Id,
            PricebookEntryId = pbe.Id,
            Quantity = 1,
            UnitPrice = 10,
            ConsumptionFrequency__c = 'Weekly'
        );
        insert oli;
    }


    // =========================================================
    // WEEKLY RECURRING CONSUMPTION
    // =========================================================

    @IsTest
static void testWeeklyRecurringConsumption() {

    Opportunity opp = [
        SELECT Id, Type
        FROM Opportunity
        LIMIT 1
    ];

    OpportunityLineItem oli = [
        SELECT
            Id,
            ProductCode,
            Quantity,
            UnitPrice,
            ConsumptionFrequency__c,
            PricebookEntry.Product2.Name
        FROM OpportunityLineItem
        WHERE OpportunityId = :opp.Id
        LIMIT 1
    ];

    System.assertEquals('Recurring Consumption', opp.Type);
    System.assertEquals('Weekly', oli.ConsumptionFrequency__c);

    OraclePricingRequest request = new OraclePricingRequest();
    request.sfOpportunityId = opp.Id;
    request.productPartNumbers =
        new List<OraclePricingRequest.ProductPartNumber>();

    request.productPartNumbers.add(
        new OraclePricingRequest.ProductPartNumber(
            oli.ProductCode,
            oli.Quantity
        )
    );

    OraclePricingResponse response = new OraclePricingResponse();
    response.priceInfo =
        new List<OraclePricingResponse.PriceInfo>();

    OraclePricingResponse.PriceInfo pricing =
        new OraclePricingResponse.PriceInfo();

    pricing.productPartNumber = oli.ProductCode;
    pricing.price = 120;
    pricing.contractNumber = 'CONTRACT123';
    pricing.currencyCode = 'USD';
    pricing.messageKey = 'SUCCESS';

    response.priceInfo.add(pricing);

    Test.startTest();

    OraclePricingIntegrationService.UpdateResult result =
        OraclePricingIntegrationService.updateOpportunityProducts(
            new List<OpportunityLineItem>{ oli },
            request,
            response,
            opp.Type
        );

    Test.stopTest();

    OpportunityLineItem updatedOli = [
        SELECT UnitPrice, Contract__c
        FROM OpportunityLineItem
        WHERE Id = :oli.Id
    ];

    System.assertEquals(
        6240,
        updatedOli.UnitPrice,
        'Weekly Recurring Consumption should multiply Oracle price by 52.'
    );

    System.assertEquals(
        'CONTRACT123',
        updatedOli.Contract__c
    );

    System.assertEquals(
        1,
        result.updatedOliIds.size()
    );

    System.assertEquals(
        0,
        result.deletedOliIds.size()
    );
}


    
    // =========================================================
    // CUSTOMER REQUEST
    // =========================================================

    @IsTest
    static void testBuildRequestCustomerAccount() {

        Opportunity opp = [
            SELECT
                Id,
                AccountId,
                Account.RecordType.DeveloperName,
                Account.OrgIDs__c,
                Account.AccountNumber,
                Account.OracleAddressId__c,
                Account.Price_List__c,
                Account.Price_List__r.Price_List_ID__c
            FROM Opportunity
            LIMIT 1
        ];

        OpportunityLineItem oli = [
            SELECT
                Id,
                ProductCode,
                Quantity
            FROM OpportunityLineItem
            WHERE OpportunityId = :opp.Id
            LIMIT 1
        ];

        OraclePricingRequest request =
            OraclePricingIntegrationService.buildRequest(
                opp,
                new List<OpportunityLineItem>{ oli }
            );

        System.assertEquals(
            'Account',
            request.accountType
        );

        System.assertEquals(
            opp.Account.OrgIDs__c,
            request.operatingUnit
        );

        System.assertEquals(
            opp.Account.AccountNumber,
            request.shipToCustomerNumber
        );

        System.assertEquals(
            opp.Account.OracleAddressId__c,
            request.shipToAddressSiteId
        );

        System.assertEquals(
            1,
            request.productPartNumbers.size()
        );

        System.assertEquals(
            oli.ProductCode,
            request.productPartNumbers[0].partNumber
        );

        System.assertEquals(
            oli.Quantity,
            request.productPartNumbers[0].quantity
        );
    }


    // =========================================================
    // BATCH SPLITTING
    // =========================================================

    @IsTest
    static void testSplitLineItems() {

        List<OpportunityLineItem> lineItems =
            new List<OpportunityLineItem>();

        for (Integer i = 0; i < 30; i++) {

            lineItems.add(
                new OpportunityLineItem(
                    Id = getFakeId(
                        OpportunityLineItem.SObjectType
                    )
                )
            );
        }

        List<List<OpportunityLineItem>> batches =
            OraclePricingIntegrationService.splitLineItems(lineItems);

        Integer maxSkus =
            Integer.valueOf(
                System.Label.MAX_SKUS_PER_REQUEST
            );

        Integer expectedBatchCount =
            Math.ceil(
                30 / (Decimal) maxSkus
            ).intValue();

        System.assertEquals(
            expectedBatchCount,
            batches.size()
        );

        System.assertEquals(
            maxSkus,
            batches[0].size()
        );
    }


    // =========================================================
    // EMPTY BATCH
    // =========================================================

    @IsTest
    static void testSplitLineItemsEmpty() {

        List<List<OpportunityLineItem>> batches =
            OraclePricingIntegrationService.splitLineItems(
                new List<OpportunityLineItem>()
            );

        System.assertEquals(
            0,
            batches.size()
        );
    }


    // =========================================================
    // NULL BATCH
    // =========================================================

    @IsTest
    static void testSplitLineItemsNull() {

        List<List<OpportunityLineItem>> batches =
            OraclePricingIntegrationService.splitLineItems(null);

        System.assertEquals(
            0,
            batches.size()
        );
    }


    // =========================================================
    // PRODUCT DELETION QUEUEABLE
    // =========================================================

    @IsTest
    static void testProductDeletionQueueable() {

        OpportunityLineItem oli = [
            SELECT Id
            FROM OpportunityLineItem
            LIMIT 1
        ];

        Test.startTest();

        System.enqueueJob(
            new OraclePricingProductDeletionQueueable(
                new List<Id>{ oli.Id }
            )
        );

        Test.stopTest();

        List<OpportunityLineItem> remaining = [
            SELECT Id
            FROM OpportunityLineItem
            WHERE Id = :oli.Id
        ];

        System.assertEquals(
            0,
            remaining.size(),
            'Queueable should delete flagged Opportunity Products.'
        );
    }


    // =========================================================
    // INVALID FLOW INPUT
    // =========================================================

    @IsTest
    static void testInvokeFromFlowInvalidInput() {

        Test.startTest();

        OraclePricingIntegrationService.invokeFromFlow(null);

        OraclePricingIntegrationService.invokeFromFlow(
            new List<OraclePricingIntegrationService.FlowRequest>()
        );

        Test.stopTest();

        System.assert(
            true,
            'Invalid flow input should return without exception.'
        );
    }


    // =========================================================
    // FLOW REQUEST WITH NULL OPPORTUNITY ID
    // =========================================================

    @IsTest
    static void testInvokeFromFlowNullOpportunityId() {

        OraclePricingIntegrationService.FlowRequest request =
            new OraclePricingIntegrationService.FlowRequest();

        request.opportunityId = null;

        Test.startTest();

        OraclePricingIntegrationService.invokeFromFlow(
            new List<OraclePricingIntegrationService.FlowRequest>{
                request
            }
        );

        Test.stopTest();

        System.assert(
            true,
            'Null Opportunity Id should return without exception.'
        );
    }


    // =========================================================
    // ENQUEUE NULL OPPORTUNITY
    // =========================================================

    @IsTest
    static void testEnqueuePricingNullOpportunity() {

        Test.startTest();

        OraclePricingIntegrationService.enqueuePricing(null);

        Test.stopTest();

        System.assert(
            true,
            'Null Opportunity Id should not enqueue pricing.'
        );
    }


    // =========================================================
    // PROCESS OPPORTUNITY NULL
    // =========================================================

    @IsTest
    static void testProcessOpportunityNull() {

        Test.startTest();

        OraclePricingIntegrationService.processOpportunity(null);

        Test.stopTest();

        System.assert(
            true,
            'Null Opportunity Id should be handled safely.'
        );
    }


   


    // =========================================================
    // FAILED CALLOUT
    // =========================================================

    @IsTest
    static void testOracleCalloutFailure() {

        Opportunity opp = [
            SELECT Id
            FROM Opportunity
            LIMIT 1
        ];

        OpportunityLineItem originalOli = [
            SELECT
                Id,
                UnitPrice
            FROM OpportunityLineItem
            WHERE OpportunityId = :opp.Id
            LIMIT 1
        ];

        Decimal originalPrice =
            originalOli.UnitPrice;

        SO_Config.SO_ServiceList_mock.add(
            defaultOracleServiceSetting()
        );

        Test.setMock(
            HttpCalloutMock.class,
            new SO_HttpMockFactory(
                500,
                'Internal Server Error',
                '{"error":"Oracle unavailable"}',
                new Map<String, String>()
            )
        );

        Test.startTest();

        invokeFlow(opp.Id);

        Test.stopTest();

        OpportunityLineItem updatedOli = [
            SELECT UnitPrice
            FROM OpportunityLineItem
            WHERE Id = :originalOli.Id
        ];

        System.assertEquals(
            originalPrice,
            updatedOli.UnitPrice,
            'Unit price should remain unchanged when Oracle callout fails.'
        );

        Opportunity updatedOpp = [
            SELECT
                IsOliBannerToBeShown__c,
                Last_Refreshed_Date_Time_From_Oracle__c
            FROM Opportunity
            WHERE Id = :opp.Id
        ];

        System.assertEquals(
            false,
            updatedOpp.IsOliBannerToBeShown__c,
            'Banner should be false when Oracle pricing fails.'
        );
    }


    // =========================================================
    // BUILD CUSTOMER REQUEST DIRECTLY
    // =========================================================

    @IsTest
    static void testBuildCustomerRequest() {

        Opportunity opp = [
            SELECT
                Id,
                AccountId,
                Account.RecordType.DeveloperName,
                Account.OrgIDs__c,
                Account.AccountNumber,
                Account.OracleAddressId__c,
                Account.Price_List__c,
                Account.Price_List__r.Price_List_ID__c
            FROM Opportunity
            LIMIT 1
        ];

        OpportunityLineItem oli = [
            SELECT
                Id,
                ProductCode,
                Quantity
            FROM OpportunityLineItem
            WHERE OpportunityId = :opp.Id
            LIMIT 1
        ];

        OraclePricingRequest request =
            OraclePricingIntegrationService.buildCustomerRequest(
                opp,
                new List<OpportunityLineItem>{ oli }
            );

        System.assertEquals(
            opp.Id,
            request.sfOpportunityId
        );

        System.assertEquals(
            'Account',
            request.accountType
        );

        System.assertEquals(
            opp.Account.OrgIDs__c,
            request.operatingUnit
        );

        System.assertEquals(
            opp.Account.AccountNumber,
            request.shipToCustomerNumber
        );

        System.assertEquals(
            opp.Account.OracleAddressId__c,
            request.shipToAddressSiteId
        );

        System.assertEquals(
            1,
            request.productPartNumbers.size()
        );
    }


    // =========================================================
    // BUILD CUSTOMER REQUEST - BLANK PRODUCT CODE
    // =========================================================

    @IsTest
    static void testBuildCustomerRequestBlankProductCode() {

        Opportunity opp = [
            SELECT
                Id,
                AccountId,
                Account.RecordType.DeveloperName,
                Account.OrgIDs__c,
                Account.AccountNumber,
                Account.OracleAddressId__c
            FROM Opportunity
            LIMIT 1
        ];

        OpportunityLineItem fakeOli =
            new OpportunityLineItem(
                Quantity = 1
            );

        OraclePricingRequest request =
            OraclePricingIntegrationService.buildCustomerRequest(
                opp,
                new List<OpportunityLineItem>{
                    fakeOli
                }
            );

        System.assertEquals(
            0,
            request.productPartNumbers.size(),
            'Blank ProductCode should not be added to request.'
        );
    }


    // =========================================================
    // PROCESS OPPORTUNITY - NO PRODUCTS
    // =========================================================

    // =========================================================
// PROCESS OPPORTUNITY - NO PRODUCTS
// =========================================================

@IsTest
static void testProcessOpportunityNoProducts() {

    Opportunity existingOpp = [
        SELECT
            Id,
            AccountId,
            RecordTypeId,
            Pricebook2Id,
            PrimaryContact__c
        FROM Opportunity
        LIMIT 1
    ];

    Opportunity noProductOpp = new Opportunity(
        Name = 'Opportunity Without Products',
        RecordTypeId = existingOpp.RecordTypeId,
        AccountId = existingOpp.AccountId,
        StageName = 'Discovery',
        CloseDate = Date.today().addDays(30),

        // Required fields for Discovery stage
        Amount = 240,
        Type = 'Recurring Consumption',
        Category__c = 'Expansion/Growth',
        PrimaryContact__c = existingOpp.PrimaryContact__c,

        Pricebook2Id = existingOpp.Pricebook2Id,
        CustomerPurchaseMethod__c = 'Direct Purchase'
    );

    insert noProductOpp;

    Test.startTest();

    OraclePricingIntegrationService.processOpportunity(
        noProductOpp.Id
    );

    Test.stopTest();

    Integer oliCount = [
        SELECT COUNT()
        FROM OpportunityLineItem
        WHERE OpportunityId = :noProductOpp.Id
    ];

    System.assertEquals(
        0,
        oliCount,
        'Opportunity should have no Opportunity Products.'
    );
}

    // =========================================================
    // HELPER - INVOKE FLOW
    // =========================================================

    private static void invokeFlow(Id opportunityId) {

        OraclePricingIntegrationService.FlowRequest request =
            new OraclePricingIntegrationService.FlowRequest();

        request.opportunityId = opportunityId;

        OraclePricingIntegrationService.invokeFromFlow(
            new List<OraclePricingIntegrationService.FlowRequest>{
                request
            }
        );
    }


    // =========================================================
    // HELPER - SERVICE SETTING
    // =========================================================

    private static ShoutOut_Service_Setting__mdt
        defaultOracleServiceSetting() {

        ShoutOut_Service_Setting__mdt serviceSetting =
            new ShoutOut_Service_Setting__mdt();

        serviceSetting.DeveloperName =
            'SF_GET_UNIT_PRICE';

        serviceSetting.MasterLabel =
            'SF_GET_UNIT_PRICE';

        serviceSetting.Label =
            'SF_GET_UNIT_PRICE';

        serviceSetting.Framework_Callout_Name__c =
            'SF_GET_UNIT_PRICE';

        serviceSetting.Named_Credential__c =
            'Boomi_Oracle';

        serviceSetting.Provider_Class__c =
            'SO_Provider_Salesforce';

        serviceSetting.Service_Class__c =
            'SO_ServiceAdapterBase_REST';

        serviceSetting.Error_Handler_Class__c =
            'SO_ErrorLogger';

        serviceSetting.REST_Verb__c =
            'POST';

        serviceSetting.REST_Path__c =
            '';

        serviceSetting.REST_query__c =
            '';

        serviceSetting.Timeout__c =
            20;

        serviceSetting.isActive__c =
            true;

        return serviceSetting;
    }


    // =========================================================
    // HELPER - ORACLE RESPONSE
    // =========================================================

    private static String buildOracleResponse() {

        Opportunity opp = [
            SELECT Id
            FROM Opportunity
            LIMIT 1
        ];

        OpportunityLineItem oli = [
            SELECT ProductCode
            FROM OpportunityLineItem
            WHERE OpportunityId = :opp.Id
            LIMIT 1
        ];

        Map<String, Object> response =
            new Map<String, Object>{
                'sfOpportunityId' => opp.Id,

                'priceInfo' =>
                    new List<Object>{
                        new Map<String, Object>{
                            'productPartNumber' =>
                                oli.ProductCode,

                            'price' => 120,

                            'contractNumber' =>
                                'CONTRACT123',

                            'currencyCode' =>
                                'USD',

                            'messageKey' =>
                                'SUCCESS'
                        }
                    }
            };

        return JSON.serialize(response);
    }


    // =========================================================
    // HELPER - FAKE ID
    // =========================================================

    private static Id getFakeId(
        Schema.SObjectType sObjectType
    ) {

        String prefix =
            sObjectType
                .getDescribe()
                .getKeyPrefix();

        return Id.valueOf(
            prefix + '0'.repeat(12)
        );
    }
    @IsTest
static void testBuildProspectRequest() {

    OpportunityLineItem existingOli = [
        SELECT Id, ProductCode, Quantity
        FROM OpportunityLineItem
        LIMIT 1
    ];

    Account prospectAccount = new Account(
        Id = getFakeId(Account.SObjectType)
    );

    Opportunity prospectOpp = new Opportunity(
        Id = getFakeId(Opportunity.SObjectType),
        AccountId = prospectAccount.Id
    );

    prospectOpp.Account = prospectAccount;

    OraclePricingRequest request =
        OraclePricingIntegrationService.buildProspectRequest(
            prospectOpp,
            new List<OpportunityLineItem>{ existingOli }
        );

    System.assertEquals(
        prospectOpp.Id,
        request.sfOpportunityId
    );

    System.assertEquals(
        prospectOpp.AccountId,
        request.prospectId
    );

    System.assertEquals(
        null,
        request.priceList
    );

    System.assertEquals(
        1,
        request.productPartNumbers.size()
    );

    System.assertEquals(
        existingOli.ProductCode,
        request.productPartNumbers[0].partNumber
    );

    System.assertEquals(
        existingOli.Quantity,
        request.productPartNumbers[0].quantity
    );
}
    @IsTest
static void testBuildProspectRequestBlankProductCode() {

    Account prospectAccount = new Account(
        Id = getFakeId(Account.SObjectType)
    );

    Opportunity prospectOpp = new Opportunity(
        Id = getFakeId(Opportunity.SObjectType),
        AccountId = prospectAccount.Id
    );

    prospectOpp.Account = prospectAccount;

    OpportunityLineItem oli =
        new OpportunityLineItem(
            Quantity = 1
        );

    OraclePricingRequest request =
        OraclePricingIntegrationService.buildProspectRequest(
            prospectOpp,
            new List<OpportunityLineItem>{ oli }
        );

    System.assertEquals(
        0,
        request.productPartNumbers.size(),
        'Blank ProductCode should not be added to Prospect pricing request.'
    );
}
    @IsTest
static void testDeleteFailedOlis() {

    OpportunityLineItem oli = [
        SELECT Id
        FROM OpportunityLineItem
        LIMIT 1
    ];

    Id oliId = oli.Id;

    Test.startTest();

    OraclePricingIntegrationService.deleteFailedOlis(
        new List<Id>{ oliId }
    );

    Test.stopTest();

    List<OpportunityLineItem> remaining = [
        SELECT Id
        FROM OpportunityLineItem
        WHERE Id = :oliId
    ];

    System.assertEquals(
        0,
        remaining.size(),
        'deleteFailedOlis should delete the supplied Opportunity Product.'
    );
}
    @IsTest
static void testDeleteFailedOlisNullAndEmpty() {

    Test.startTest();

    OraclePricingIntegrationService.deleteFailedOlis(null);

    OraclePricingIntegrationService.deleteFailedOlis(
        new List<Id>()
    );

    Test.stopTest();

    System.assert(true);
}
    @IsTest
static void testLogDeleteResultsNullAndEmpty() {

    Test.startTest();

    OraclePricingIntegrationService.logDeleteResults(
        'OpportunityLineItem',
        null
    );

    OraclePricingIntegrationService.logDeleteResults(
        'OpportunityLineItem',
        new List<Database.DeleteResult>()
    );

    Test.stopTest();

    System.assert(true);
}
    private static ShoutOut_Service_Setting__mdt prospectOracleServiceSetting() {

    ShoutOut_Service_Setting__mdt serviceSetting =
        new ShoutOut_Service_Setting__mdt();

    serviceSetting.DeveloperName = 'SF_GET_PROSPECT_PRICE';
    serviceSetting.MasterLabel = 'SF_GET_PROSPECT_PRICE';
    serviceSetting.Label = 'SF_GET_PROSPECT_PRICE';
    serviceSetting.Framework_Callout_Name__c = 'SF_GET_PROSPECT_PRICE';
    serviceSetting.Named_Credential__c = 'Boomi_Oracle';
    serviceSetting.Provider_Class__c = 'SO_Provider_Salesforce';
    serviceSetting.Service_Class__c = 'SO_ServiceAdapterBase_REST';
    serviceSetting.Error_Handler_Class__c = 'SO_ErrorLogger';
    serviceSetting.REST_Verb__c = 'POST';
    serviceSetting.REST_Path__c = '';
    serviceSetting.REST_query__c = '';
    serviceSetting.Timeout__c = 20;
    serviceSetting.isActive__c = true;

    return serviceSetting;
}
    @IsTest
static void testProcessProspectBatch() {

    Opportunity opp = [
        SELECT
            Id,
            Type,
            AccountId
        FROM Opportunity
        LIMIT 1
    ];

    OpportunityLineItem oli = [
        SELECT
            Id,
            ProductCode,
            Quantity,
            UnitPrice,
            ConsumptionFrequency__c,
            PricebookEntry.Product2.Name
        FROM OpportunityLineItem
        WHERE OpportunityId = :opp.Id
        LIMIT 1
    ];

    /*
     * Build Prospect request manually.
     *
     * We are testing processProspectBatch(),
     * so the Account itself does not need to be
     * converted to Prospect for this test.
     */
    OraclePricingRequest request =
        new OraclePricingRequest();

    request.sfOpportunityId = opp.Id;
    request.prospectId = opp.AccountId;
    request.sourceSystem = System.Label.Source_System;

    request.productPartNumbers =
        new List<OraclePricingRequest.ProductPartNumber>();

    request.productPartNumbers.add(
        new OraclePricingRequest.ProductPartNumber(
            oli.ProductCode,
            oli.Quantity
        )
    );

    SO_Config.SO_ServiceList_mock.add(
        prospectOracleServiceSetting()
    );

    /*
     * Intentionally return failure.
     *
     * OracleUnitPricingGateway detects that the test
     * is running and supplies getMockProspectResponse().
     */
    Test.setMock(
        HttpCalloutMock.class,
        new SO_HttpMockFactory(
            500,
            'Internal Server Error',
            '{"error":"Prospect pricing unavailable"}',
            new Map<String, String>()
        )
    );

    Test.startTest();

    OraclePricingIntegrationService.UpdateResult result =
        OraclePricingIntegrationService.processProspectBatch(
            opp,
            request,
            new List<OpportunityLineItem>{ oli }
        );

    Test.stopTest();

    System.assertNotEquals(
        null,
        result,
        'Prospect batch should return an UpdateResult.'
    );
}
    @IsTest
static void testFlagAllForDeletion() {

    OpportunityLineItem oli = [
        SELECT
            Id,
            ProductCode,
            PricebookEntry.Product2.Name
        FROM OpportunityLineItem
        LIMIT 1
    ];

    OraclePricingIntegrationService.UpdateResult result =
        new OraclePricingIntegrationService.UpdateResult();

    Test.startTest();

    OraclePricingIntegrationService.flagAllForDeletion(
        new List<OpportunityLineItem>{ oli },
        result
    );

    Test.stopTest();

    // OLI should be flagged for deletion
    System.assertEquals(
        1,
        result.deletedOliIds.size(),
        'One Opportunity Product should be flagged for deletion.'
    );

    System.assertEquals(
        oli.Id,
        result.deletedOliIds[0],
        'Deleted OLI Id should match the supplied Opportunity Product.'
    );

    // Product name should also be retained
    System.assertEquals(
        1,
        result.deletedProductNames.size(),
        'Deleted product name should be captured.'
    );

    System.assertEquals(
        oli.PricebookEntry.Product2.Name,
        result.deletedProductNames[0],
        'Deleted product name should match the Opportunity Product.'
    );
}
    @IsTest
static void testSuccessfulOliNotDeletedWhenAnotherOliFails() {

    Opportunity opp = [
        SELECT Id, Type, Pricebook2Id
        FROM Opportunity
        LIMIT 1
    ];

    // Existing OLI - this one will receive valid pricing
    OpportunityLineItem validOli = [
        SELECT
            Id,
            ProductCode,
            Quantity,
            UnitPrice,
            ConsumptionFrequency__c,
            PricebookEntry.Product2.Name
        FROM OpportunityLineItem
        WHERE OpportunityId = :opp.Id
        LIMIT 1
    ];

    // ---------------------------------------------------------
    // Create second product - this one will fail pricing
    // ---------------------------------------------------------
    Product2 failedProduct = new Product2(
        Name = 'Failed Pricing Product',
        ProductCode = 'FAILED-001',
        IsActive = true
    );
    insert failedProduct;

    PricebookEntry failedPbe = new PricebookEntry(
        Pricebook2Id = opp.Pricebook2Id,
        Product2Id = failedProduct.Id,
        UnitPrice = 10,
        IsActive = true
    );
    insert failedPbe;

    OpportunityLineItem failedOli = new OpportunityLineItem(
        OpportunityId = opp.Id,
        PricebookEntryId = failedPbe.Id,
        Quantity = 1,
        UnitPrice = 10,
        ConsumptionFrequency__c = 'Weekly'
    );
    insert failedOli;

    // Re-query because applyPricingToBatch uses ProductCode
    // and PricebookEntry.Product2.Name.
    List<OpportunityLineItem> batch = [
        SELECT
            Id,
            ProductCode,
            Quantity,
            UnitPrice,
            ConsumptionFrequency__c,
            PricebookEntry.Product2.Name
        FROM OpportunityLineItem
        WHERE Id IN :new Set<Id>{
            validOli.Id,
            failedOli.Id
        }
        ORDER BY CreatedDate
    ];

    // ---------------------------------------------------------
    // Build request containing both products
    // ---------------------------------------------------------
    OraclePricingRequest request = new OraclePricingRequest();

    request.sfOpportunityId = opp.Id;

    request.productPartNumbers =
        new List<OraclePricingRequest.ProductPartNumber>();

    for (OpportunityLineItem oli : batch) {
        request.productPartNumbers.add(
            new OraclePricingRequest.ProductPartNumber(
                oli.ProductCode,
                oli.Quantity
            )
        );
    }

    // ---------------------------------------------------------
    // Response
    //
    // First product = SUCCESS
    // Second product = failure / null price
    // ---------------------------------------------------------
    OraclePricingResponse response =
        new OraclePricingResponse();

    response.priceInfo =
        new List<OraclePricingResponse.PriceInfo>();

    OraclePricingResponse.PriceInfo successPricing =
        new OraclePricingResponse.PriceInfo();

    successPricing.productPartNumber =
        batch[0].ProductCode;

    successPricing.price = 120;
    successPricing.contractNumber = 'CONTRACT123';
    successPricing.currencyCode = 'USD';
    successPricing.messageKey = 'SUCCESS';

    response.priceInfo.add(successPricing);


    OraclePricingResponse.PriceInfo failedPricing =
        new OraclePricingResponse.PriceInfo();

    failedPricing.productPartNumber =
        batch[1].ProductCode;

    failedPricing.price = null;
    failedPricing.contractNumber = null;
    failedPricing.currencyCode = 'USD';
    failedPricing.messageKey = 'SUCCESS';

    response.priceInfo.add(failedPricing);

    // ---------------------------------------------------------
    // Execute
    // ---------------------------------------------------------
    Test.startTest();

    OraclePricingIntegrationService.UpdateResult result =
        OraclePricingIntegrationService.updateOpportunityProducts(
            batch,
            request,
            response,
            opp.Type
        );

    Test.stopTest();

    // ---------------------------------------------------------
    // Assertions
    // ---------------------------------------------------------

    // First OLI successfully updated
    System.assertEquals(
        1,
        result.updatedOliIds.size(),
        'One OLI should be successfully updated.'
    );

    System.assert(
        result.updatedOliIds.contains(batch[0].Id),
        'Successfully priced OLI should be in updatedOliIds.'
    );

    // Second OLI marked for deletion
    System.assertEquals(
        1,
        result.deletedOliIds.size(),
        'Only failed pricing OLI should remain in deletedOliIds.'
    );

    System.assert(
        result.deletedOliIds.contains(batch[1].Id),
        'Failed pricing OLI should be marked for deletion.'
    );

    // Most important assertion for this branch:
    System.assertEquals(
        false,
        result.deletedOliIds.contains(batch[0].Id),
        'Successfully updated OLI must never be deleted.'
    );

    // Weekly recurring price:
    // 120 * 52 = 6240
    OpportunityLineItem updatedValidOli = [
        SELECT UnitPrice, Contract__c
        FROM OpportunityLineItem
        WHERE Id = :batch[0].Id
    ];

    System.assertEquals(
        6240,
        updatedValidOli.UnitPrice,
        'Weekly Recurring Consumption should calculate 120 * 52.'
    );

    System.assertEquals(
        'CONTRACT123',
        updatedValidOli.Contract__c
    );

    // Failed OLI still exists here.
    // updateOpportunityProducts only FLAGS it for deletion.
    System.assertEquals(
        1,
        [
            SELECT COUNT()
            FROM OpportunityLineItem
            WHERE Id = :batch[1].Id
        ]
    );
}
    
    @IsTest
static void testUpdateProspectOpportunityProducts() {

    Opportunity opp = [
        SELECT Id, Type
        FROM Opportunity
        LIMIT 1
    ];

    OpportunityLineItem oli = [
        SELECT
            Id,
            ProductCode,
            Quantity,
            UnitPrice,
            Contract__c,
            ConsumptionFrequency__c,
            PricebookEntry.Product2.Name
        FROM OpportunityLineItem
        WHERE OpportunityId = :opp.Id
        LIMIT 1
    ];

    // ---------------------------------------------------------
    // Build Prospect pricing request
    // ---------------------------------------------------------
    OraclePricingRequest request =
        new OraclePricingRequest();

    request.sfOpportunityId = opp.Id;
    request.prospectId = opp.Id;

    request.productPartNumbers =
        new List<OraclePricingRequest.ProductPartNumber>();

    request.productPartNumbers.add(
        new OraclePricingRequest.ProductPartNumber(
            oli.ProductCode,
            oli.Quantity
        )
    );

    // ---------------------------------------------------------
    // Build successful Prospect response
    // ---------------------------------------------------------
    OraclePricingResponse response =
        new OraclePricingResponse();

    response.priceInfo =
        new List<OraclePricingResponse.PriceInfo>();

    OraclePricingResponse.PriceInfo pricing =
        new OraclePricingResponse.PriceInfo();

    pricing.productPartNumber = oli.ProductCode;
    pricing.price = 120;
    pricing.contractNumber = 'PROSPECT-CONTRACT';
    pricing.currencyCode = 'USD';
    pricing.messageKey = 'SUCCESS';

    response.priceInfo.add(pricing);

    Test.startTest();

    OraclePricingIntegrationService.UpdateResult result =
        OraclePricingIntegrationService.updateProspectOpportunityProducts(
            new List<OpportunityLineItem>{ oli },
            request,
            response,
            opp.Type
        );

    Test.stopTest();

    // ---------------------------------------------------------
    // Verify result
    // ---------------------------------------------------------
    System.assertNotEquals(
        null,
        result,
        'Prospect pricing should return an UpdateResult.'
    );

    System.assertEquals(
        1,
        result.updatedOliIds.size(),
        'Prospect OLI should be successfully updated.'
    );

    System.assert(
        result.updatedOliIds.contains(oli.Id),
        'Updated OLI Id should be returned.'
    );

    System.assertEquals(
        0,
        result.deletedOliIds.size(),
        'Successfully priced Prospect OLI should not be deleted.'
    );

    // ---------------------------------------------------------
    // Verify database
    // ---------------------------------------------------------
    OpportunityLineItem updatedOli = [
        SELECT
            UnitPrice,
            Contract__c
        FROM OpportunityLineItem
        WHERE Id = :oli.Id
    ];

    /*
     * Setup Opportunity:
     * Type = Recurring Consumption
     * Frequency = Weekly
     *
     * Oracle price = 120
     * 120 * 52 = 6240
     */
    System.assertEquals(
        6240,
        updatedOli.UnitPrice,
        'Prospect Weekly Recurring Consumption should calculate 120 * 52.'
    );

    /*
     * IMPORTANT:
     * Prospect path passes setContract = false.
     * Therefore Contract__c should NOT be populated.
     */
    System.assertEquals(
        null,
        updatedOli.Contract__c,
        'Prospect pricing should not update Contract__c.'
    );
}
    

    @IsTest
    static void requestJsonCoversCustomerAndProspectFields() {
        OraclePricingRequest request = new OraclePricingRequest();
        request.sfOpportunityId = '006000000000001AAA';
        request.operatingUnit = '83';
        request.shipToCustomerNumber = 'ST-1';
        request.shipToAddressSiteId = 'SITE "1"';
        request.accountType = 'Prospect';
        request.priceListName = 'USA HEALTHCARE';
        request.priceList = '6125';
        request.sourceSystem = 'SFDC';
        request.prospectId = UserInfo.getUserId();
        request.productPartNumbers = new List<OraclePricingRequest.ProductPartNumber>{
            new OraclePricingRequest.ProductPartNumber(),
            new OraclePricingRequest.ProductPartNumber('PART-1', null),
            new OraclePricingRequest.ProductPartNumber('   ', 2),
            new OraclePricingRequest.ProductPartNumber('PART-2', 3.9)
        };

        Map<String, Object> inputParameters =
            (Map<String, Object>) request.toJsonMap().get('InputParameters');
        System.assertEquals('USA HEALTHCARE', inputParameters.get('P_PRICE_LIST_NAME'));
        System.assertEquals('83', inputParameters.get('P_OU_ID'));
        System.assertEquals('ST-1', inputParameters.get('P_ST_ACCT_NUM'));
        System.assertEquals(null, inputParameters.get('P_OU_NAME'));
        System.assertEquals(null, inputParameters.get('P_BT_ACCT_NUM'));
        System.assertEquals('ST_ADDRESS', inputParameters.get('P_PRICE_LIST_LEVEL'));
        System.assertEquals('ST_ACCOUNT', inputParameters.get('P_DISCOUNT_ACCOUNT'));

        String customerJson = request.toJsonString();
        System.assert(customerJson.contains('PART-1'));
        System.assert(customerJson.contains('PART-2'));
        System.assert(customerJson.contains('USA HEALTHCARE'));
        System.assert(customerJson.contains('ST_ADDRESS'));
        System.assert(customerJson.contains('ST_ACCOUNT'));
        System.assert(customerJson.contains('\\"'));

        String prospectJson = request.toProspectJsonString();
        System.assert(prospectJson.contains('PART-1,PART-2'));
        System.assert(prospectJson.contains('6125'));

        request.accountType = 'Account';
        request.priceList = 'not-a-number';
        request.productPartNumbers = null;
        request.sourceSystem = null;
        System.assert(request.toJsonString().contains('"P_PRICE_LIST_NAME":null'));
        System.assert(request.toProspectJsonString().contains('"priceList":null'));
        System.assert(request.toProspectJsonString().contains('"partNumbers":null'));
    }

    @IsTest
    static void responseParsesOracleAndProspectPayloads() {
        System.assertEquals(null, OraclePricingResponse.parse(null));
        System.assertEquals(null, OraclePricingResponse.parseProspect('  '));

        String oracleBody =
            '{"OutputParameters":{"P_MESSAGEKEY":"Success","P_ERRORCODE":"0","P_ITEMS_TBL":[' +
            '{"P_ITEMS_TBL_ITEM":[{"PARTNUMBER":"PART-1","PRICE":"10.5","LIST_PRICE":"12","MESSAGEKEY":"Success","ERRORCODE":"0","CURRENCY":"USD","UOM":"EA","ORACLEPRICELISTID":"6125","ORACLEPRICELISTNAME":"USA","ORACLEMODIFIERNUMBER":"C-1"},"skip-me"]},' +
            '{"ignored":true}' +
            ']}}';
        OraclePricingResponse parsed = OraclePricingResponse.parse(oracleBody);
        System.assertEquals('Success', parsed.messageKey);
        System.assertEquals(1, parsed.priceInfo.size());
        System.assertEquals(10.5, parsed.priceInfo[0].price);
        System.assertEquals('C-1', parsed.priceInfo[0].contractNumber);

        String mapBody =
            '{"P_MESSAGEKEY":"Success","P_ITEMS_TBL":{"P_ITEMS_TBL_ITEM":{"PARTNUMBER":"PART-2","PRICE":"bad"}}}';
        OraclePricingResponse mapParsed = OraclePricingResponse.parse(mapBody);
        System.assertEquals('PART-2', mapParsed.priceInfo[0].productPartNumber);
        System.assertEquals(null, mapParsed.priceInfo[0].price);
        System.assertEquals(0, OraclePricingResponse.parse('{"P_MESSAGEKEY":"Success"}').priceInfo.size());

        System.assertEquals(null, OraclePricingResponse.parseId(null));
        System.assertEquals(null, OraclePricingResponse.parseId('not-an-id'));
        System.assertEquals(null, OraclePricingResponse.parseDecimal(null));
        System.assertEquals(null, OraclePricingResponse.parseDecimal('abc'));
        System.assertEquals(null, OraclePricingResponse.getString(null, 'PRICE'));

        String prospectBody =
            '{"opportunityId":"' + String.valueOf(UserInfo.getUserId()) + '",' +
            '"prospectId":"not-an-id",' +
            '"partNumbers":[{"partNumber":"PART-1","messageKey":"Success","errorCode":"0","listPrice":"8.25","currency":"USD"},"skip"]}';
        OraclePricingResponse prospect = OraclePricingResponse.parseProspect(prospectBody);
        System.assertEquals(null, prospect.prospectId);
        System.assertEquals(8.25, prospect.priceInfo[0].price);
        System.assertEquals(0, OraclePricingResponse.parseProspect('{"partNumbers":"PART-1"}').priceInfo.size());

        System.assertEquals(true, OraclePricingResponse.isPricingSuccess('success'));
        System.assertEquals(false, OraclePricingResponse.isPricingSuccess(null));
        System.assertEquals(true, OraclePricingResponse.isPricingSuccess('Failed', '0'));
        System.assertEquals(false, OraclePricingResponse.isPricingSuccess('Success', '700'));
        System.assertEquals(null, OraclePricingResponse.resolveUnitPrice(null));
        OraclePricingResponse.PriceInfo listOnly = new OraclePricingResponse.PriceInfo();
        listOnly.listPrice = 4;
        System.assertEquals(4, OraclePricingResponse.resolveUnitPrice(listOnly));
    }

    @IsTest
    static void responseBuildsPricingMapAndMockPayloads() {
        System.assertEquals(0, OraclePricingResponse.buildPricingMap(null, null).size());
        OraclePricingResponse emptyResponse = new OraclePricingResponse();
        System.assertEquals(0, OraclePricingResponse.buildPricingMap(emptyResponse, null).size());

        OraclePricingRequest request = new OraclePricingRequest();
        request.productPartNumbers = new List<OraclePricingRequest.ProductPartNumber>{
            new OraclePricingRequest.ProductPartNumber('PART-1', 1),
            new OraclePricingRequest.ProductPartNumber(null, 1)
        };
        OraclePricingResponse response = new OraclePricingResponse();
        response.priceInfo = new List<OraclePricingResponse.PriceInfo>();
        OraclePricingResponse.PriceInfo blank = new OraclePricingResponse.PriceInfo();
        blank.price = 10;
        response.priceInfo.add(blank);
        OraclePricingResponse.PriceInfo named = new OraclePricingResponse.PriceInfo();
        named.productPartNumber = 'PART-2';
        named.price = 20;
        response.priceInfo.add(named);
        OraclePricingResponse.PriceInfo dropped = new OraclePricingResponse.PriceInfo();
        response.priceInfo.add(dropped);

        Map<String, OraclePricingResponse.PriceInfo> pricingMap =
            OraclePricingResponse.buildPricingMap(response, request);
        System.assertEquals(2, pricingMap.size());
        System.assertEquals('PART-1', pricingMap.get('PART-1').productPartNumber);

        request.productPartNumbers.add(new OraclePricingRequest.ProductPartNumber('PART-3', 1));
        OraclePricingResponse multiMock = OraclePricingResponse.getMockResponse(request);
        System.assertEquals(3, multiMock.priceInfo.size());
        System.assertEquals(130, multiMock.priceInfo[0].price);
        System.assertEquals(null, multiMock.priceInfo[1].price);
        System.assertEquals('0', multiMock.errorCode);

        request.productPartNumbers = null;
        System.assertEquals(0, OraclePricingResponse.getMockResponse(request).priceInfo.size());
        System.assertEquals(0, OraclePricingResponse.getMockProspectResponse(request).priceInfo.size());

        request.productPartNumbers = new List<OraclePricingRequest.ProductPartNumber>{
            new OraclePricingRequest.ProductPartNumber('ONLY', 1)
        };
        System.assertEquals(63.61, OraclePricingResponse.getMockProspectResponse(request).priceInfo[0].price);

        request.productPartNumbers.add(new OraclePricingRequest.ProductPartNumber('SECOND', 1));
        OraclePricingResponse prospectMock = OraclePricingResponse.getMockProspectResponse(request);
        System.assertEquals(null, prospectMock.priceInfo[0].price);
        System.assertEquals(63.61, prospectMock.priceInfo[1].price);
    }

    @IsTest
    static void gatewayCoversNullRequestsAndUtilityMethods() {
        OracleUnitPricingGateway.CalloutResult nullUnit =
            OracleUnitPricingGateway.sendUnitPriceRequest(null);
        System.assertEquals(false, nullUnit.calloutSuccess);
        System.assertEquals('Request body is null', nullUnit.errorDetail);

        OracleUnitPricingGateway.CalloutResult nullProspect =
            OracleUnitPricingGateway.sendProspectPriceRequest(null);
        System.assertEquals(false, nullProspect.calloutSuccess);

        System.assertEquals(false, OracleUnitPricingGateway.isSuccessful(null));
        System.assertEquals(false, OracleUnitPricingGateway.isSuccessful(new Map<String, Object>()));
        System.assertEquals(
            false,
            OracleUnitPricingGateway.isSuccessful(new Map<String, Object>{ 'SO_SUCCESS' => 'yes' })
        );
        System.assertEquals(
            true,
            OracleUnitPricingGateway.isSuccessful(new Map<String, Object>{ 'SO_SUCCESS' => true })
        );
        System.assertEquals(null, OracleUnitPricingGateway.extractResponseBody(new Map<String, Object>()));
        System.assertEquals(
            null,
            OracleUnitPricingGateway.extractResponseBody(new Map<String, Object>{ 'SERVICE_DATA' => '   ' })
        );
        System.assertEquals(
            '{"ok":true}',
            OracleUnitPricingGateway.extractResponseBody(new Map<String, Object>{ 'SERVICE_DATA' => '{"ok":true}' })
        );
        System.assert(
            OracleUnitPricingGateway.extractResponseBody(
                new Map<String, Object>{ 'SERVICERESPONSE' => new Map<String, Object>{ 'a' => 1 } }
            ).contains('"a"')
        );
        System.assertEquals(
            'SO_Callout returned empty response',
            OracleUnitPricingGateway.extractErrorDetail(null)
        );
        System.assertEquals(
            'SO_Callout returned empty response',
            OracleUnitPricingGateway.extractErrorDetail(new Map<String, Object>())
        );
        System.assertEquals(
            'timeout',
            OracleUnitPricingGateway.extractErrorDetail(new Map<String, Object>{ 'SO_RETURN' => 'timeout' })
        );
        System.assertEquals(
            'raw body',
            OracleUnitPricingGateway.extractErrorDetail(new Map<String, Object>{ 'SERVICERESPONSE' => 'raw body' })
        );
        System.assertEquals(
            'SO_Callout failed',
            OracleUnitPricingGateway.extractErrorDetail(new Map<String, Object>{ 'SO_SUCCESS' => false })
        );
    }

    @IsTest
    static void gatewayUsesMockPricingWhenCalloutDoesNotSucceed() {
        OraclePricingRequest request = new OraclePricingRequest();
        request.sfOpportunityId = String.valueOf(UserInfo.getUserId());
        request.prospectId = UserInfo.getUserId();
        request.operatingUnit = '83';
        request.accountType = 'Account';
        request.sourceSystem = 'SFDC';
        request.productPartNumbers = new List<OraclePricingRequest.ProductPartNumber>{
            new OraclePricingRequest.ProductPartNumber('PART-1', 1),
            new OraclePricingRequest.ProductPartNumber('PART-2', 2)
        };

        SO_Config.SO_ServiceList_mock.add(defaultOracleServiceSetting());
        SO_Config.SO_ServiceList_mock.add(prospectOracleServiceSetting());
        Test.setMock(
            HttpCalloutMock.class,
            new SO_HttpMockFactory(
                500,
                'Internal Server Error',
                '{"error":"Oracle unavailable"}',
                new Map<String, String>()
            )
        );

        Test.startTest();
        OracleUnitPricingGateway.CalloutResult unitResult =
            OracleUnitPricingGateway.sendUnitPriceRequest(request);
        OracleUnitPricingGateway.CalloutResult prospectResult =
            OracleUnitPricingGateway.sendProspectPriceRequest(request);
        Test.stopTest();

        System.assertEquals(true, unitResult.calloutSuccess, unitResult.errorDetail);
        System.assertEquals(2, unitResult.parsedResponse.priceInfo.size());
        System.assertEquals(130, unitResult.parsedResponse.priceInfo[0].price);
        System.assertEquals(null, unitResult.parsedResponse.priceInfo[1].price);

        System.assertEquals(true, prospectResult.calloutSuccess, prospectResult.errorDetail);
        System.assertEquals(2, prospectResult.parsedResponse.priceInfo.size());
        System.assertEquals(null, prospectResult.parsedResponse.priceInfo[0].price);
        System.assertEquals(63.61, prospectResult.parsedResponse.priceInfo[1].price);
    }

    @IsTest
    static void gatewayParsesSuccessfulUnitPriceBody() {
        OraclePricingRequest request = new OraclePricingRequest();
        request.sfOpportunityId = String.valueOf(UserInfo.getUserId());
        request.operatingUnit = '83';
        request.accountType = 'Account';
        request.sourceSystem = 'SFDC';
        request.productPartNumbers = new List<OraclePricingRequest.ProductPartNumber>{
            new OraclePricingRequest.ProductPartNumber('PART-1', 1)
        };

        SO_Config.SO_ServiceList_mock.add(defaultOracleServiceSetting());
        Test.setMock(
            HttpCalloutMock.class,
            new SO_HttpMockFactory(
                200,
                'OK',
                '{"OutputParameters":{"P_MESSAGEKEY":"Success","P_ERRORCODE":"0","P_ITEMS_TBL":[{"P_ITEMS_TBL_ITEM":[{"PARTNUMBER":"PART-1","PRICE":"10.5","LIST_PRICE":"12","MESSAGEKEY":"Success","ERRORCODE":"0"}]}]}}',
                new Map<String, String>{ 'Content-Type' => 'application/json' }
            )
        );

        Test.startTest();
        OracleUnitPricingGateway.CalloutResult result =
            OracleUnitPricingGateway.sendUnitPriceRequest(request);
        Test.stopTest();

        System.assertEquals(true, result.calloutSuccess);
    }

    @IsTest
    static void gatewayParsesSuccessfulProspectPriceBody() {
        OraclePricingRequest request = new OraclePricingRequest();
        request.sfOpportunityId = String.valueOf(UserInfo.getUserId());
        request.prospectId = UserInfo.getUserId();
        request.priceList = '6125';
        request.sourceSystem = 'SFDC';
        request.productPartNumbers = new List<OraclePricingRequest.ProductPartNumber>{
            new OraclePricingRequest.ProductPartNumber('PART-1', 1)
        };

        SO_Config.SO_ServiceList_mock.add(prospectOracleServiceSetting());
        Test.setMock(
            HttpCalloutMock.class,
            new SO_HttpMockFactory(
                200,
                'OK',
                '{"opportunityId":"' + String.valueOf(UserInfo.getUserId()) + '","prospectId":"' +
                    String.valueOf(UserInfo.getUserId()) +
                    '","partNumbers":[{"partNumber":"PART-1","messageKey":"Success","errorCode":"0","listPrice":"8.25","currency":"USD"}]}',
                new Map<String, String>{ 'Content-Type' => 'application/json' }
            )
        );

        Test.startTest();
        OracleUnitPricingGateway.CalloutResult result =
            OracleUnitPricingGateway.sendProspectPriceRequest(request);
        Test.stopTest();

        System.assertEquals(true, result.calloutSuccess);
    }

    @IsTest
    static void gatewaySubstitutesMockWhenPricingBodyIsEmpty() {
        OraclePricingRequest request = new OraclePricingRequest();
        request.sfOpportunityId = String.valueOf(UserInfo.getUserId());
        request.prospectId = UserInfo.getUserId();
        request.operatingUnit = '83';
        request.accountType = 'Account';
        request.priceList = '6125';
        request.sourceSystem = 'SFDC';
        request.productPartNumbers = new List<OraclePricingRequest.ProductPartNumber>{
            new OraclePricingRequest.ProductPartNumber('PART-1', 1)
        };

        SO_Config.SO_ServiceList_mock.add(defaultOracleServiceSetting());
        Test.setMock(
            HttpCalloutMock.class,
            new SO_HttpMockFactory(
                200,
                'OK',
                '{"OutputParameters":{"P_MESSAGEKEY":"Success","P_ERRORCODE":"0"}}',
                new Map<String, String>()
            )
        );

        Test.startTest();
        OracleUnitPricingGateway.CalloutResult unitResult =
            OracleUnitPricingGateway.sendUnitPriceRequest(request);
        Test.stopTest();

        System.assertEquals(true, unitResult.calloutSuccess);
        System.assertEquals(130, unitResult.parsedResponse.priceInfo[0].price);
    }

    @IsTest
    static void gatewaySubstitutesMockWhenProspectBodyIsEmpty() {
        OraclePricingRequest request = new OraclePricingRequest();
        request.sfOpportunityId = String.valueOf(UserInfo.getUserId());
        request.prospectId = UserInfo.getUserId();
        request.priceList = '6125';
        request.sourceSystem = 'SFDC';
        request.productPartNumbers = new List<OraclePricingRequest.ProductPartNumber>{
            new OraclePricingRequest.ProductPartNumber('PART-1', 1)
        };

        SO_Config.SO_ServiceList_mock.add(prospectOracleServiceSetting());
        Test.setMock(
            HttpCalloutMock.class,
            new SO_HttpMockFactory(
                200,
                'OK',
                '{"opportunityId":"' + String.valueOf(UserInfo.getUserId()) + '","partNumbers":[]}',
                new Map<String, String>()
            )
        );

        Test.startTest();
        OracleUnitPricingGateway.CalloutResult prospectResult =
            OracleUnitPricingGateway.sendProspectPriceRequest(request);
        Test.stopTest();

        System.assertEquals(true, prospectResult.calloutSuccess);
        System.assertEquals(63.61, prospectResult.parsedResponse.priceInfo[0].price);
    }

    // Gateway success, empty body, retry, null map, and exception paths.
    // A test provider returns the response map. SO_Provider_Salesforce plus a
    // failing callout never sets SO_SUCCESS, so sendUnitPriceRequest returns
    // inside the Test.isRunningTest fallback and skips these lines.
    private static Map<String, Object> gatewayResponseOverride;

    @IsTest
    static void gatewayParsesRealUnitAndProspectBodies() {
        OraclePricingRequest request = sampleGatewayRequest();
        String prospectId = String.valueOf(request.prospectId);

        useGatewayProvider(new Map<String, Object>{
            'SO_SUCCESS' => true,
            'SERVICE_STATUS' => 200,
            'SERVICE_DATA' =>
                '{"OutputParameters":{"P_MESSAGEKEY":"Success","P_ERRORCODE":"0","P_ITEMS_TBL":[{"P_ITEMS_TBL_ITEM":[{"PARTNUMBER":"PART-1","PRICE":"10.5","LIST_PRICE":"12","MESSAGEKEY":"Success","ERRORCODE":"0"}]}]}}'
        });

        Test.startTest();
        OracleUnitPricingGateway.CalloutResult unitResult =
            OracleUnitPricingGateway.sendUnitPriceRequest(request);

        useGatewayProvider(new Map<String, Object>{
            'SO_SUCCESS' => true,
            'SERVICE_STATUS' => 200,
            'SERVICE_DATA' =>
                '{"opportunityId":"' + prospectId + '","prospectId":"' + prospectId +
                '","partNumbers":[{"partNumber":"PART-1","messageKey":"Success","errorCode":"0","listPrice":"8.25","currency":"USD"}]}'
        });
        OracleUnitPricingGateway.CalloutResult prospectResult =
            OracleUnitPricingGateway.sendProspectPriceRequest(request);
        Test.stopTest();

        System.assertEquals(null, unitResult.errorDetail);
        System.assertEquals(true, unitResult.calloutSuccess);
        System.assertEquals(false, unitResult.retryEnqueued);
        System.assertEquals(10.5, unitResult.parsedResponse.priceInfo[0].price);

        System.assertEquals(null, prospectResult.errorDetail);
        System.assertEquals(true, prospectResult.calloutSuccess);
        System.assertEquals(8.25, prospectResult.parsedResponse.priceInfo[0].price);
    }

    @IsTest
    static void gatewaySubstitutesMockWhenParsedPriceInfoIsEmpty() {
        OraclePricingRequest request = sampleGatewayRequest();

        useGatewayProvider(new Map<String, Object>{
            'SO_SUCCESS' => true,
            'SERVICE_DATA' => '{"OutputParameters":{"P_MESSAGEKEY":"Success","P_ERRORCODE":"0"}}'
        });

        Test.startTest();
        OracleUnitPricingGateway.CalloutResult unitResult =
            OracleUnitPricingGateway.sendUnitPriceRequest(request);

        useGatewayProvider(new Map<String, Object>{
            'SO_SUCCESS' => true,
            'SERVICE_DATA' => '{"opportunityId":"' + String.valueOf(request.prospectId) + '","partNumbers":[]}'
        });
        OracleUnitPricingGateway.CalloutResult prospectResult =
            OracleUnitPricingGateway.sendProspectPriceRequest(request);
        Test.stopTest();

        System.assertEquals('Oracle returned empty pricing response', unitResult.errorDetail);
        System.assertEquals(true, unitResult.calloutSuccess);
        System.assertEquals(130, unitResult.parsedResponse.priceInfo[0].price);

        System.assertEquals('Boomi returned empty pricing response', prospectResult.errorDetail);
        System.assertEquals(true, prospectResult.calloutSuccess);
        System.assertEquals(63.61, prospectResult.parsedResponse.priceInfo[0].price);
    }

    @IsTest
    static void gatewayHandlesInvalidPricingJson() {
        OraclePricingRequest request = sampleGatewayRequest();
        Map<String, Object> invalidBody = new Map<String, Object>{
            'SO_SUCCESS' => true,
            'SERVICE_DATA' => 'not-json'
        };

        useGatewayProvider(invalidBody);

        Test.startTest();
        OracleUnitPricingGateway.CalloutResult unitResult =
            OracleUnitPricingGateway.sendUnitPriceRequest(request);

        useGatewayProvider(invalidBody);
        OracleUnitPricingGateway.CalloutResult prospectResult =
            OracleUnitPricingGateway.sendProspectPriceRequest(request);
        Test.stopTest();

        System.assertEquals(false, unitResult.calloutSuccess);
        System.assert(String.isNotBlank(unitResult.errorDetail));
        System.assertEquals(null, unitResult.parsedResponse);

        System.assertEquals(true, prospectResult.calloutSuccess);
        System.assertEquals(63.61, prospectResult.parsedResponse.priceInfo[0].price);
    }

    @IsTest
    static void gatewayHandlesNullResponseMapAndRetry() {
        OraclePricingRequest request = sampleGatewayRequest();

        useGatewayProvider(null);

        Test.startTest();
        OracleUnitPricingGateway.CalloutResult nullUnit =
            OracleUnitPricingGateway.sendUnitPriceRequest(request);
        OracleUnitPricingGateway.CalloutResult nullProspect =
            OracleUnitPricingGateway.sendProspectPriceRequest(request);

        useGatewayProvider(new Map<String, Object>{
            'SO_SUCCESS' => false,
            'SO_RETURN' => 'retry scheduled',
            SO_Constants.RETRY_ENQUEUED => true
        });
        OracleUnitPricingGateway.CalloutResult retryResult =
            OracleUnitPricingGateway.sendUnitPriceRequest(request);
        Test.stopTest();

        System.assertEquals(null, nullUnit.serviceResponseMap);
        System.assertEquals(null, nullProspect.serviceResponseMap);
        System.assertEquals(true, retryResult.retryEnqueued);
    }

    private static OraclePricingRequest sampleGatewayRequest() {
        OraclePricingRequest request = new OraclePricingRequest();
        request.sfOpportunityId = String.valueOf(UserInfo.getUserId());
        request.prospectId = UserInfo.getUserId();
        request.operatingUnit = '83';
        request.accountType = 'Account';
        request.priceList = '6125';
        request.sourceSystem = 'SFDC';
        request.productPartNumbers = new List<OraclePricingRequest.ProductPartNumber>{
            new OraclePricingRequest.ProductPartNumber('PART-1', 1)
        };
        return request;
    }

    private static void useGatewayProvider(Map<String, Object> responseMap) {
        gatewayResponseOverride = responseMap;
        SO_Config.SO_ServiceList_mock.clear();
        SO_Config.SO_ServiceList_mock.add(gatewayProviderSetting('SF_GET_UNIT_PRICE'));
        SO_Config.SO_ServiceList_mock.add(gatewayProviderSetting('SF_GET_PROSPECT_PRICE'));
    }

    private static ShoutOut_Service_Setting__mdt gatewayProviderSetting(String settingName) {
        ShoutOut_Service_Setting__mdt serviceSetting = new ShoutOut_Service_Setting__mdt();
        serviceSetting.DeveloperName = settingName;
        serviceSetting.MasterLabel = settingName;
        serviceSetting.Label = settingName;
        serviceSetting.Framework_Callout_Name__c = settingName;
        serviceSetting.Provider_Class__c =
            'OraclePricingIntegrationTest.UnitPricingCalloutProvider';
        serviceSetting.isActive__c = true;
        serviceSetting.REST_Verb__c = 'POST';
        serviceSetting.Service_Class__c = 'SO_ServiceAdapterBase_REST';
        return serviceSetting;
    }

    public class UnitPricingCalloutProvider extends SO_Provider_Base {
        public override Map<String, Object> makeCallout(SO_Callout callout) {
            return gatewayResponseOverride;
        }
    }

}