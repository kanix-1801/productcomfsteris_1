/**
 * @author Himanshu Chaurasia
 * @date 2026/04/16
 *
 * @group Product Sub-Group Detail
 *
 * @description Unit tests for ProductSubGroupDetailQuoteSelector (GC-3129).
 */
@IsTest
private class ProductSubGroupDetailQuoteSelectorTest {
    private static final String TEST_OPPORTUNITY_NAME = 'ProductSubGroupDetailQuoteSelector Opp';
    private static final String OPPORTUNITY_RECORD_TYPE_DEVELOPER_NAME = 'Healthcare_Sales';

    @TestSetup
    static void setup() {
        Id pricebookId = Test.getStandardPricebookId();

        Account accountRecord = new Account(
            Name = 'ProductSubGroupDetailQuoteSelector Account',
            SourceSystemID__c = 'Oracle-PSGQS-1'
        );
        insert accountRecord;

        Contact contactRecord = new Contact(
            LastName = 'ProductSubGroupDetailQuoteSelector Contact',
            AccountId = accountRecord.Id
        );
        insert contactRecord;

        Opportunity opportunityRecord = buildOpportunity(
            TEST_OPPORTUNITY_NAME,
            accountRecord.Id,
            contactRecord.Id,
            pricebookId
        );
        insert opportunityRecord;

        insert buildQuote(opportunityRecord, 'Selector Test Quote A');
        insert buildQuote(opportunityRecord, 'Selector Test Quote B');
    }

    @IsTest
    static void selectOpportunityIdByQuoteIdReturnsEmptyForNullOrEmptyInput() {
        System.assertEquals(
            0,
            ProductSubGroupDetailQuoteSelector.selectOpportunityIdByQuoteId(null).size()
        );
        System.assertEquals(
            0,
            ProductSubGroupDetailQuoteSelector.selectOpportunityIdByQuoteId(new Set<Id>()).size()
        );
    }

    @IsTest
    static void selectOpportunityIdByQuoteIdMapsQuotesToOpportunity() {
        Opportunity opportunityRecord = [
            SELECT Id
            FROM Opportunity
            WHERE Name = :TEST_OPPORTUNITY_NAME
            LIMIT 1
        ];
        List<Quote> quoteRecords = [
            SELECT Id
            FROM Quote
            WHERE OpportunityId = :opportunityRecord.Id
            ORDER BY Name
        ];
        System.assertEquals(2, quoteRecords.size());

        Set<Id> quoteIds = new Map<Id, Quote>(quoteRecords).keySet();

        Test.startTest();
        Map<Id, Id> opportunityIdByQuoteId =
            ProductSubGroupDetailQuoteSelector.selectOpportunityIdByQuoteId(quoteIds);
        Test.stopTest();

        System.assertEquals(2, opportunityIdByQuoteId.size());
        for (Quote quoteRecord : quoteRecords) {
            System.assertEquals(
                opportunityRecord.Id,
                opportunityIdByQuoteId.get(quoteRecord.Id),
                'Each Quote Id should map to the parent Opportunity Id.'
            );
        }
    }

    private static Opportunity buildOpportunity(
        String opportunityName,
        Id accountId,
        Id primaryContactId,
        Id pricebookId
    ) {
        Opportunity opportunityRecord = new Opportunity(
            Name = opportunityName,
            AccountId = accountId,
            StageName = getValidStageName(),
            CloseDate = Date.today().addDays(30),
            Pricebook2Id = pricebookId,
            Type = 'Extension',
            Amount = 100,
            Probability = 10,
            PrimaryContact__c = primaryContactId
        );
        populateForecastConfidenceIfPossible(opportunityRecord);

        Id opportunityRecordTypeId = resolveOpportunityRecordTypeId();
        if (opportunityRecordTypeId != null) {
            opportunityRecord.RecordTypeId = opportunityRecordTypeId;
        }

        return opportunityRecord;
    }

    private static Id resolveOpportunityRecordTypeId() {
        Map<String, Schema.RecordTypeInfo> recordTypesByDeveloperName =
            Schema.SObjectType.Opportunity.getRecordTypeInfosByDeveloperName();

        if (!recordTypesByDeveloperName.containsKey(OPPORTUNITY_RECORD_TYPE_DEVELOPER_NAME)) {
            return null;
        }

        Schema.RecordTypeInfo recordTypeInfo =
            recordTypesByDeveloperName.get(OPPORTUNITY_RECORD_TYPE_DEVELOPER_NAME);
        return recordTypeInfo.isAvailable() ? recordTypeInfo.getRecordTypeId() : null;
    }

    private static Quote buildQuote(Opportunity opportunityRecord, String quoteName) {
        Quote quoteRecord = new Quote(
            Name = quoteName,
            OpportunityId = opportunityRecord.Id,
            Pricebook2Id = opportunityRecord.Pricebook2Id,
            Status = resolveQuoteStatus('Open'),
            Forecast_Eligible__c = false,
            Quote_Total_Without_Freight__c = 1000,
            ExpirationDate = Date.today().addDays(30)
        );

        Id recordTypeId = resolveHcSalesRecordTypeId();
        if (recordTypeId != null) {
            quoteRecord.RecordTypeId = recordTypeId;
        }

        return quoteRecord;
    }

    private static Id resolveHcSalesRecordTypeId() {
        Map<String, Schema.RecordTypeInfo> recordTypesByDeveloperName =
            Schema.SObjectType.Quote.getRecordTypeInfosByDeveloperName();

        if (!recordTypesByDeveloperName.containsKey(GenerateQuoteService.QUOTE_RECORD_TYPE_DEVELOPER_NAME)) {
            return null;
        }

        return recordTypesByDeveloperName.get(GenerateQuoteService.QUOTE_RECORD_TYPE_DEVELOPER_NAME)
            .getRecordTypeId();
    }

    private static String resolveQuoteStatus(String statusValue) {
        for (Schema.PicklistEntry picklistEntry : Quote.Status.getDescribe().getPicklistValues()) {
            if (picklistEntry.isActive() && picklistEntry.getValue().equalsIgnoreCase(statusValue)) {
                return picklistEntry.getValue();
            }
        }

        return statusValue;
    }

    private static String getValidStageName() {
        for (Schema.PicklistEntry picklistEntry : Opportunity.StageName.getDescribe().getPicklistValues()) {
            if (picklistEntry.isActive()) {
                return picklistEntry.getValue();
            }
        }

        return 'Discovery';
    }

    private static void populateForecastConfidenceIfPossible(Opportunity opportunityRecord) {
        Schema.SObjectField forecastField = Schema.SObjectType.Opportunity.fields.getMap()
            .get('ForecastConfidenceLevel__c');
        if (forecastField == null) {
            return;
        }

        for (Schema.PicklistEntry picklistEntry : forecastField.getDescribe().getPicklistValues()) {
            if (picklistEntry.isActive()) {
                opportunityRecord.put(forecastField, picklistEntry.getValue());
                return;
            }
        }
    }
}