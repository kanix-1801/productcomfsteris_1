/**
* @author Sarthak Pani
* @date 2026/10/30
*
* @group Generate Quote
*
* @description
* GC-2642 Service class for Generate and Refresh Quote Button on Opportunity.
*/
public with sharing class LSGenerateQuoteService {
    public static final String SCENARIO = 'Generate Quote';
    public static final String LOGGER_TAG = 'GenerateQuote';
    public static final String QUOTE_STATUS_DRAFT = 'Draft';
    public static final String QUOTE_STATUS_OPEN = 'Open';
    public static final String QUOTE_RECORD_TYPE_DEVELOPER_NAME = 'LSSales';    //GCL-66
    public static final String QUOTE_ACCESS_DENIED_MESSAGE =
        'You can\'t perform this operation because you don\'t have edit access to this Opportunity. Reach out to an Opportunity Team member to request access.';    //GCL-66
    public static final String NO_ACTIVE_PRICEBOOK_ENTRIES_MESSAGE =
        'No active products were found in the Opportunity Price Book. Add active Pricebook Entries before generating a Quote.';
    public static final String QUOTE_TYPE_NORMAL = 'Normal Quote';
    public static final String QUOTE_TYPE_TRIAL = 'Trial Quote';
    public static final String QUOTE_TYPE_SAMPLE = 'Sample Quote';
    public static final String QUOTE_TYPE_GOODWILL = 'Goodwill Quote';
    public static final String OPPORTUNITY_RECORD_TYPE_GOODWILL = 'HC_Sales_Customer_Goodwill_Support';

    @TestVisible
    private static Boolean throwTestException = false;

    @TestVisible
    private static Boolean testHasEditAccessOverride;

/**
* @description
* GC-2642 - get the Quote and Quote Line Item Wrapper Items.
* 
* @param Opportunity ID.
* @return Wrapper QuoteWrapper.
* 
* @example
* GenerateQuoteService.getQuotes(opportunityId);
*/
    public static List<GenerateQuoteController.QuoteWrapper> getQuotes(Id opportunityId) {
        return getQuotes(opportunityId, null);
    }

    /**
     * @description Returns quotes for an Opportunity, optionally filtered by Quote Type.
     * @param opportunityId Opportunity Id.
     * @param quoteTypeFilter Optional QuoteType__c value to filter results.
     * @return Quote wrapper rows for the LWC.
     */
    public static List<GenerateQuoteController.QuoteWrapper> getQuotes(
        Id opportunityId,
        String quoteTypeFilter
    ) {
        return getQuotes(opportunityId, quoteTypeFilter, false);
    }

    /**
     * @description Returns quotes for an Opportunity with optional filters.
     * @param opportunityId Opportunity Id.
     * @param quoteTypeFilter Optional QuoteType__c value to filter results.
     * @param excludeForecastIneligible When true, omit forecast-ineligible quotes.
     * @return Quote wrapper rows for the LWC.
     */
    public static List<GenerateQuoteController.QuoteWrapper> getQuotes(
        Id opportunityId,
        String quoteTypeFilter,
        Boolean excludeForecastIneligible
    ) {
        return getQuotes(opportunityId, quoteTypeFilter, excludeForecastIneligible, null);
    }

    /**
     * @description Returns quotes for an Opportunity with optional filters.
     * @param opportunityId Opportunity Id.
     * @param quoteTypeFilter Optional QuoteType__c value to filter results.
     * @param excludeForecastIneligible When true, omit forecast-ineligible quotes.
     * @param trialIdFilter Optional Trial__c Id to limit results to one Trial record.
     * @return Quote wrapper rows for the LWC.
     */
    public static List<GenerateQuoteController.QuoteWrapper> getQuotes(
        Id opportunityId,
        String quoteTypeFilter,
        Boolean excludeForecastIneligible,
        Id trialIdFilter
    ) {
        return getQuotes(
            opportunityId,
            quoteTypeFilter,
            excludeForecastIneligible,
            trialIdFilter,
            null
        );
    }

    /**
     * @description Returns quotes for an Opportunity with optional filters.
     * @param opportunityId Opportunity Id.
     * @param quoteTypeFilter Optional QuoteType__c value to filter results.
     * @param excludeForecastIneligible When true, omit forecast-ineligible quotes.
     * @param trialIdFilter Optional Trial__c Id to limit results to one Trial record.
     * @param sampleIdFilter Optional Sample__c Id to limit results to one Sample record.
     * @return Quote wrapper rows for the LWC.
     */
    public static List<GenerateQuoteController.QuoteWrapper> getQuotes(
        Id opportunityId,
        String quoteTypeFilter,
        Boolean excludeForecastIneligible,
        Id trialIdFilter,
        Id sampleIdFilter
    ) {
        validateOpportunityId(opportunityId);

        try {
            if (throwTestException) {
                throw new QueryException('Forced test exception');
            }

            List<Quote> quoteRecords = QuoteSelector.selectByOpportunityIdWithLineItems(
                opportunityId,
                quoteTypeFilter,
                excludeForecastIneligible == true,
                trialIdFilter,
                sampleIdFilter
            );
            Opportunity opportunityRecord = OpportunitySelector.selectById(opportunityId);
            Account accountRecord = getAccountForSalesConnection(opportunityRecord);
            return mapQuotesToWrappers(quoteRecords, opportunityRecord, accountRecord);
        } catch (Exception exceptionValue) {
            Logger.setScenario(SCENARIO);
            Logger.error('Error retrieving quotes for opportunity.', exceptionValue).addTag(LOGGER_TAG);
            throw new GenerateQuoteException('Unable to retrieve quotes.');
        }finally {
            Logger.saveLog();
        }
    }

    private static String getOpportunityForecastConfidence(Id opportunityId) {
        Opportunity opportunityRecord = OpportunitySelector.selectForecastConfidenceByIds(
            new Set<Id>{ opportunityId }
        ).get(opportunityId);

        return opportunityRecord == null ? null : opportunityRecord.ForecastConfidenceLevel__c;
    }

    /**
     * @description Triggers Refresh Quote on Sales Connection (UpsertRefreshSFQuotes). Success is HTTP 2xx only;
     *              SC updates Salesforce separately via Composite API.
     * @param opportunityId Opportunity Id.
     * @return Empty list (ack-only; UI shows toast and does not reload quote data).
     */
    public static List<LSGenerateQuoteController.QuoteWrapper> refreshQuotes(Id opportunityId) {
        validateOpportunityId(opportunityId);
        validateQuoteAccess(opportunityId);

        try {
            if (throwTestException) {
                throw new CalloutException('Forced test exception');
            }

            GenerateQuoteRefreshGateway.CalloutResult calloutResult =
                GenerateQuoteRefreshGateway.refreshQuotes(
                    RefreshQuoteRequest.fromOpportunityId(opportunityId)
                );

          if (calloutResult.retryEnqueued == true) {
                Logger.setScenario(SCENARIO);
                Logger.warn(
                    'Refresh Quote callout failed; async retry enqueued. opportunityId=' + opportunityId
                ).addTag(LOGGER_TAG);
                throw new GenerateQuoteException(
                    'Refresh Quote callout failed and an async retry was enqueued.'
                );
            }

       	if (calloutResult.calloutSuccess != true) {
                Logger.setScenario(SCENARIO);
                Logger.error(
                    'Refresh Quote callout failed. opportunityId=' + opportunityId +
                    ', detail=' + calloutResult.errorDetail
                ).addTag(LOGGER_TAG);
                throw new GenerateQuoteException(
                    String.isNotBlank(calloutResult.errorDetail)
                        ? calloutResult.errorDetail
                        : 'Refresh Quote callout failed.'
                );
            }

            Logger.setScenario(SCENARIO);
            Logger.info(
                'Refresh Quote callout succeeded (ack-only). opportunityId=' + opportunityId
            ).addTag(LOGGER_TAG);
            return new List<LSGenerateQuoteController.QuoteWrapper>();
        } catch (GenerateQuoteException exceptionValue) {
            Logger.setScenario(SCENARIO);
            Logger.error('Error refreshing quotes for opportunity.', exceptionValue).addTag(LOGGER_TAG);
            throw exceptionValue;
        } catch (Exception exceptionValue) {
            Logger.setScenario(SCENARIO);
            Logger.error('Error refreshing quotes for opportunity.', exceptionValue).addTag(LOGGER_TAG);
            throw new GenerateQuoteException('Unable to refresh quotes.');
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description Creates a Quote and copies Opportunity Products to Quote Line Items.
     * @param opportunityId Opportunity Id.
     * @return Create quote response DTO for the LWC.
     */
    public static LSGenerateQuoteController.CreateQuoteResponse createQuote(Id opportunityId) {
        return createQuote(opportunityId, QUOTE_TYPE_NORMAL);
    }

    /**
     * @description Creates a Quote and copies Opportunity Products to Quote Line Items.
     * @param opportunityId Opportunity Id.
     * @param quoteType Quote Type picklist value to assign on create.
     * @return Create quote response DTO for the LWC.
     */
    public static LSGenerateQuoteController.CreateQuoteResponse createQuote(Id opportunityId, String quoteType) {
        return createQuote(opportunityId, quoteType, null);
    }

    /**
     * @description Creates a Quote and copies Opportunity Products to Quote Line Items.
     * @param opportunityId Opportunity Id.
     * @param quoteType Quote Type picklist value to assign on create.
     * @param trialId Optional Trial record Id for Trial Quote creation.
     * @return Create quote response DTO for the LWC.
     */
    public static LSGenerateQuoteController.CreateQuoteResponse createQuote(
        Id opportunityId,
        String quoteType,
        Id trialId
    ) {
        return createQuote(opportunityId, quoteType, trialId, null);
    }

    /**
     * @description Creates a Quote and copies Opportunity Products to Quote Line Items.
     * @param opportunityId Opportunity Id.
     * @param quoteType Quote Type picklist value to assign on create.
     * @param trialId Optional Trial record Id for Trial Quote creation.
     * @param sampleId Optional Sample record Id for Sample Quote creation.
     * @return Create quote response DTO for the LWC.
     */
    public static LSGenerateQuoteController.CreateQuoteResponse createQuote(
        Id opportunityId,
        String quoteType,
        Id trialId,
        Id sampleId
    ) {
        return createShellQuoteForSalesConnection(
            opportunityId,
            quoteType,
            trialId,
            sampleId,
            LSSalesConnectionUrlService.SF_REQUEST_CREATE
        );
    }

    /**
     * @description Creates a shell Quote and returns the encrypted Sales Connection URL for copy or merge.
     * @param opportunityId Opportunity Id.
     * @param sfRequest Sales Connection sfrequest value (copy or merge).
     * @return Create quote response DTO for the quick action.
     */
    public static LSGenerateQuoteController.CreateQuoteResponse createShellQuoteForSalesConnectionRequest(
        Id opportunityId,
        String sfRequest
    ) {
        return createShellQuoteForSalesConnection(
            opportunityId,
            GenerateQuoteService.QUOTE_TYPE_NORMAL,
            null,
            null,
            sfRequest
        );
    }

    /**
     * @description Creates a shell Quote in Salesforce (Open status) and builds the Sales Connection URL.
     *              Does not perform integration callouts; use Refresh Quote to sync from Sales Connection.
     * @param opportunityId Opportunity Id.
     * @param quoteType Quote Type picklist value to assign on create.
     * @param trialId Optional Trial record Id for Trial Quote creation.
     * @param sampleId Optional Sample record Id for Sample Quote creation.
     * @param sfRequest Sales Connection sfrequest value (create, copy, or merge).
     * @return Create quote response DTO with encrypted Sales Connection URL.
     */
    private static LSGenerateQuoteController.CreateQuoteResponse createShellQuoteForSalesConnection(
        Id opportunityId,
        String quoteType,
        Id trialId,
        Id sampleId,
        String sfRequest
    ) {
        validateOpportunityId(opportunityId);
        validateQuoteAccess(opportunityId);
        validateSalesConnectionSfRequest(sfRequest);

        Savepoint savepointValue = Database.setSavepoint();

        try {
            if (throwTestException) {
                throw new DmlException('Forced test exception');
            }

            Opportunity opportunityRecord = OpportunitySelector.selectById(opportunityId);

            if (opportunityRecord == null) {
                throw new AuraHandledException('Opportunity record was not found.');
            }

            if (opportunityRecord.Pricebook2Id == null) {
                throw new AuraHandledException(
                    'Please add a Price Book to the Opportunity before generating a Quote.'
                );
            }

            Quote newQuote = buildQuote(opportunityRecord, quoteType, trialId, sampleId);
            insertCreatableRecords(new List<SObject>{ newQuote }, 'Quote');

            Quote insertedQuote = QuoteSelector.selectById(newQuote.Id);

            if (insertedQuote == null) {
                throw new GenerateQuoteException('Created quote could not be retrieved.');
            }

            Account accountRecord = getAccountForSalesConnection(opportunityRecord);
            persistStoredSalesConnectionQuoteUrl(
                insertedQuote,
                opportunityRecord,
                accountRecord,
                sfRequest
            );
            insertedQuote = QuoteSelector.selectById(newQuote.Id);

            if (insertedQuote == null) {
                throw new GenerateQuoteException('Created quote could not be retrieved.');
            }

            Logger.setScenario(SCENARIO);
            Logger.info(
                'Created shell quote ' +
                resolveQuoteNumber(insertedQuote) +
                ' for opportunity ' +
                opportunityId +
                ' (' +
                sfRequest +
                ')'
            ).addTag(LOGGER_TAG);

            return mapCreateQuoteResponse(insertedQuote, opportunityRecord, accountRecord);
        } catch (Exception exceptionValue) {
            Database.rollback(savepointValue);
            Logger.setScenario(SCENARIO);
            Logger.error('Shell quote creation failed. ' + exceptionValue.getMessage()).addTag(LOGGER_TAG);

            if (exceptionValue instanceof AuraHandledException) {
                throw exceptionValue;
            }

            if (exceptionValue instanceof GenerateQuoteException) {
                throw new AuraHandledException(exceptionValue.getMessage());
            }
            throw new GenerateQuoteException('Unable to create quote.');
        } finally {
            Logger.saveLog();
        }
    }

    @TestVisible
    private static void validateSalesConnectionSfRequest(String sfRequest) {
        if (
            !LSSalesConnectionUrlService.SF_REQUEST_CREATE.equals(sfRequest) &&
            !LSSalesConnectionUrlService.SF_REQUEST_COPY.equals(sfRequest) &&
            !LSSalesConnectionUrlService.SF_REQUEST_MERGE.equals(sfRequest)
        ) {
            throw new GenerateQuoteException('Unsupported Sales Connection request type.');
        }
    }
    
    /**
* @description
* GC-2642 - Validates the opportunity id whether it's null or not.
* 
* @param Opportunity ID.
* @return NA.
* 
* @example
* GenerateQuoteService.validateOpportunityId(opportunityId);
*/

    private static void validateOpportunityId(Id opportunityId) {
        if (opportunityId == null) {
            throw new AuraHandledException('Opportunity Id is required.');
        }
    }

    /**
     * @description Ensures the current user has edit access to the Opportunity via sharing (UserRecordAccess).
     * @param opportunityId Opportunity Id.
     */
    public static void validateQuoteAccess(Id opportunityId) {
        validateOpportunityId(opportunityId);

        Opportunity opportunityRecord = OpportunitySelector.selectById(opportunityId);

        if (opportunityRecord == null) {
            throw new AuraHandledException('Opportunity record was not found.');
        }

        if (!resolveCurrentUserHasEditAccess(opportunityId)) {
            throw new AuraHandledException(QUOTE_ACCESS_DENIED_MESSAGE);
        }
    }

    private static Boolean resolveCurrentUserHasEditAccess(Id opportunityId) {
        if (Test.isRunningTest() && testHasEditAccessOverride != null) {
            return testHasEditAccessOverride;
        }

        List<UserRecordAccess> accessRows = [
            SELECT RecordId, HasEditAccess
            FROM UserRecordAccess
            WHERE UserId = :UserInfo.getUserId()
            AND RecordId = :opportunityId
            LIMIT 1
        ];

        return !accessRows.isEmpty() && accessRows[0].HasEditAccess;
    }

    private static Quote buildQuote(
        Opportunity opportunityRecord,
        String quoteType,
        Id trialId,
        Id sampleId
    ) {
        Quote newQuote = new Quote();
        String effectiveQuoteType = resolveEffectiveQuoteType(opportunityRecord, quoteType);
        newQuote.Name = resolveQuoteName(opportunityRecord, effectiveQuoteType);
        newQuote.OpportunityId = opportunityRecord.Id;
        newQuote.Pricebook2Id = opportunityRecord.Pricebook2Id;
        newQuote.Status = QUOTE_STATUS_OPEN;
        newQuote.ExpirationDate = Date.today().addDays(30);
        newQuote.QuoteType__c = effectiveQuoteType;

        if (isForecastIneligibleQuoteType(effectiveQuoteType)) {
            newQuote.IsForecastIneligible__c = true;
        }

        if (trialId != null && QUOTE_TYPE_TRIAL.equals(effectiveQuoteType)) {
            newQuote.Trial__c = trialId;
        }

        if (sampleId != null && QUOTE_TYPE_SAMPLE.equals(effectiveQuoteType)) {
            newQuote.Sample__c = sampleId;
        }

        Id quoteRecordTypeId = resolveQuoteRecordTypeId();
        if (quoteRecordTypeId != null) {
            newQuote.RecordTypeId = quoteRecordTypeId;
        }

        applyQuoteCurrencyFromOpportunity(newQuote, opportunityRecord);

        return newQuote;
    }

    @TestVisible
    private static String resolveQuoteType(String quoteType) {
        if (QUOTE_TYPE_TRIAL.equals(quoteType)) {
            return QUOTE_TYPE_TRIAL;
        }

        if (QUOTE_TYPE_SAMPLE.equals(quoteType)) {
            return QUOTE_TYPE_SAMPLE;
        }

        if (QUOTE_TYPE_GOODWILL.equals(quoteType)) {
            return QUOTE_TYPE_GOODWILL;
        }

        return QUOTE_TYPE_NORMAL;
    }

    @TestVisible
    private static String resolveEffectiveQuoteType(Opportunity opportunityRecord, String quoteType) {
        String resolvedQuoteType = resolveQuoteType(quoteType);

        if (
            QUOTE_TYPE_NORMAL.equals(resolvedQuoteType) &&
            isGoodwillSupportOpportunity(opportunityRecord)
        ) {
            return QUOTE_TYPE_GOODWILL;
        }

        return resolvedQuoteType;
    }

    @TestVisible
    private static Boolean isGoodwillSupportOpportunity(Opportunity opportunityRecord) {
        return opportunityRecord != null &&
            OPPORTUNITY_RECORD_TYPE_GOODWILL.equals(opportunityRecord.RecordType?.DeveloperName);
    }

    @TestVisible
    private static Boolean isForecastIneligibleQuoteType(String quoteType) {
        return QUOTE_TYPE_TRIAL.equals(quoteType) ||
            QUOTE_TYPE_SAMPLE.equals(quoteType) ||
            QUOTE_TYPE_GOODWILL.equals(quoteType);
    }

    @TestVisible
    private static Boolean isScopedQuoteType(String quoteType) {
        return QUOTE_TYPE_TRIAL.equals(quoteType) ||
            QUOTE_TYPE_SAMPLE.equals(quoteType) ||
            QUOTE_TYPE_GOODWILL.equals(quoteType);
    }

    @TestVisible
    private static String resolveQuoteName(Opportunity opportunityRecord, String quoteType) {
        String resolvedQuoteType = resolveQuoteType(quoteType);

        if (QUOTE_TYPE_TRIAL.equals(resolvedQuoteType)) {
            return 'Trial Quote - ' + opportunityRecord.Name;
        }

        if (QUOTE_TYPE_SAMPLE.equals(resolvedQuoteType)) {
            return 'Sample Quote - ' + opportunityRecord.Name;
        }

        if (QUOTE_TYPE_GOODWILL.equals(resolvedQuoteType)) {
            return 'Goodwill Quote - ' + opportunityRecord.Name;
        }

        return 'Quote - ' + opportunityRecord.Name;
    }

    /**
     * @description Aligns Quote currency with the parent Opportunity in multi-currency orgs.
     * @param quoteRecord Quote being created.
     * @param opportunityRecord Parent Opportunity.
     */
    public static void applyQuoteCurrencyFromOpportunity(
        Quote quoteRecord,
        Opportunity opportunityRecord
    ) {
        if (
            quoteRecord == null ||
            opportunityRecord == null ||
            !UserInfo.isMultiCurrencyOrganization()
        ) {
            return;
        }

        quoteRecord.put('CurrencyIsoCode', opportunityRecord.get('CurrencyIsoCode'));
    }

    /**
     * @description Resolves the HC_Sales Quote record type Id when available in the org.
     * @return HC_Sales record type Id, or null when unavailable.
     */
    public static Id resolveHcSalesQuoteRecordTypeId() {
        return resolveQuoteRecordTypeId();
    }

    private static Id resolveQuoteRecordTypeId() {
        Map<String, Schema.RecordTypeInfo> recordTypesByDeveloperName =
            Schema.SObjectType.Quote.getRecordTypeInfosByDeveloperName();

        if (!recordTypesByDeveloperName.containsKey(QUOTE_RECORD_TYPE_DEVELOPER_NAME)) {
            return null;
        }

        Schema.RecordTypeInfo recordTypeInfo =
            recordTypesByDeveloperName.get(QUOTE_RECORD_TYPE_DEVELOPER_NAME);
        return recordTypeInfo.isAvailable() ? recordTypeInfo.getRecordTypeId() : null;
    }

    /**
     * @description Resolves the Sales Connection quote number for UI and logging.
     * @param quoteRecord Quote record with custom or standard quote number fields.
     * @return Quote number from Sales Connection when available.
     */
    public static String resolveQuoteNumber(Quote quoteRecord) {
        if (quoteRecord == null) {
            return null;
        }

        if (String.isNotBlank(quoteRecord.QuoteNumber__c)) {
            return quoteRecord.QuoteNumber__c;
        }

        return quoteRecord.QuoteNumber == null ? null : String.valueOf(quoteRecord.QuoteNumber);
    }

    /**
     * @description Resolves the Sales Connection quote id used for navigation and matching.
     * @param quoteRecord Quote record with custom or legacy source-system fields.
     * @return Sales Connection quote id when available.
     */
    public static String resolveSalesConnectionQuoteId(Quote quoteRecord) {
        if (quoteRecord == null) {
            return null;
        }

        if (String.isNotBlank(quoteRecord.SalesConnectionQuoteID__c)) {
            return quoteRecord.SalesConnectionQuoteID__c;
        }

        return quoteRecord.Source_System_ID__c;
    }

    /**
     * @description Resolves QuoteNumber__c for Generate Quote display labels.
     * @param quoteRecord Quote record with Sales Connection quote number field.
     * @return QuoteNumber__c when populated; otherwise null.
     */
    public static String resolveQuoteNumberLabel(Quote quoteRecord) {
        if (quoteRecord == null || String.isBlank(quoteRecord.QuoteNumber__c)) {
            return null;
        }

        return quoteRecord.QuoteNumber__c.trim();
    }

    /**
     * @description Resolves SalesConnectionQuoteID__c for Sales Connection view-quote URLs.
     * @param quoteRecord Quote record with Sales Connection quote id field.
     * @return Numeric Sales Connection quote id when populated; otherwise null.
     */
    public static String resolveSalesConnectionViewQuoteId(Quote quoteRecord) {
        if (quoteRecord == null) {
            return null;
        }

        return normalizeSalesConnectionQuoteIdForStorage(
            resolveSalesConnectionQuoteId(quoteRecord)
        );
    }

    /**
     * @description Normalizes Sales Connection quote ids to numeric values for URL navigation.
     * @param rawValue Raw Sales Connection quote id from integration or Salesforce.
     * @return Digits-only quote id when available.
     */
    public static String normalizeSalesConnectionQuoteIdForStorage(String rawValue) {
        if (String.isBlank(rawValue)) {
            return null;
        }

        String digitsOnly = rawValue.replaceAll('[^0-9]', '');
        return String.isBlank(digitsOnly) ? rawValue.trim() : digitsOnly;
    }

    /**
     * @description Normalizes Sales Connection quote numbers for QuoteNumber__c storage.
     * @param rawValue Raw quote number from integration or Salesforce.
     * @return Trimmed alphanumeric quote number when available.
     */
    public static String normalizeQuoteNumberForStorage(String rawValue) {
        if (String.isBlank(rawValue)) {
            return null;
        }

        return rawValue.trim();
    }

    private static List<GenerateQuoteController.QuoteWrapper> mapQuotesToWrappers(
        List<Quote> quoteRecords,
        Opportunity opportunityRecord,
        Account accountRecord
    ) {
        List<GenerateQuoteController.QuoteWrapper> quoteWrapperList =
            new List<GenerateQuoteController.QuoteWrapper>();
        PsamQuoteLineGroupingService.PsamIndex psamIndex =
            PsamQuoteLineGroupingService.loadPsamForQuotes(quoteRecords);

        for (Quote quoteRecord : quoteRecords) {
            GenerateQuoteController.QuoteWrapper quoteWrapper = new GenerateQuoteController.QuoteWrapper();
            quoteWrapper.id = quoteRecord.Id;
            quoteWrapper.quoteNumber = resolveQuoteNumber(quoteRecord);
            quoteWrapper.salesConnectionViewQuoteNumber = resolveQuoteNumberLabel(quoteRecord);
            quoteWrapper.salesConnectionQuoteId = resolveSalesConnectionQuoteId(quoteRecord);
            quoteWrapper.quoteName = quoteRecord.Name;
            quoteWrapper.expirationDate = quoteRecord.ExpirationDate;
            quoteWrapper.description = quoteRecord.Description;
            quoteWrapper.status = quoteRecord.Status;
            quoteWrapper.approvalStatus = quoteRecord.Approval_Status__c;
            quoteWrapper.quoteTotalWithoutFreight = QuoteService.resolveQuoteTotalWithoutFreight(
                quoteRecord,
                quoteRecord.QuoteLineItems
            );
            quoteWrapper.lastModifiedDate = resolveLastModifiedDate(quoteRecord);
            quoteWrapper.isForecastIneligible = quoteRecord.IsForecastIneligible__c == true;
            quoteWrapper.quoteForecastConfidence = quoteRecord.QuoteForecastConfidence__c;
            quoteWrapper.opportunityForecastConfidence = opportunityRecord == null
                ? null
                : opportunityRecord.ForecastConfidenceLevel__c;
            try {
                quoteWrapper.salesConnectionUrl = LSSalesConnectionUrlService.buildQuoteUrl(
                    quoteRecord,
                    opportunityRecord,
                    accountRecord
                );
            } catch (AuraHandledException exceptionValue) {
                quoteWrapper.salesConnectionUrl = null;
            }
            quoteWrapper.productSubgroupSummary = PsamQuoteLineGroupingService.buildGroupedSummary(
                quoteRecord.QuoteLineItems,
                psamIndex
            );
            quoteWrapper.salesCategorySummary = QuoteLineSalesCategoryService.buildGroupedSummary(
                quoteRecord.QuoteLineItems
            );

            quoteWrapperList.add(quoteWrapper);
        }

        return quoteWrapperList;
    }

    private static Datetime resolveLastModifiedDate(Quote quoteRecord) {
        if (quoteRecord == null) {
            return null;
        }

        if (quoteRecord.LastModifiedDate__c != null) {
            return quoteRecord.LastModifiedDate__c;
        }

        return quoteRecord.LastModifiedDate;
    }

    private static LSGenerateQuoteController.CreateQuoteResponse mapCreateQuoteResponse(
        Quote insertedQuote,
        Opportunity opportunityRecord,
        Account accountRecord
    ) {
        LSGenerateQuoteController.CreateQuoteResponse response = new LSGenerateQuoteController.CreateQuoteResponse();
        response.quoteId = insertedQuote.Id;
        response.quoteName = insertedQuote.Name;
        response.quoteNumber = resolveQuoteNumber(insertedQuote);
        try {
            response.salesConnectionUrl = LSSalesConnectionUrlService.buildQuoteUrl(
                insertedQuote,
                opportunityRecord,
                accountRecord
            );
        } catch (AuraHandledException exceptionValue) {
            Logger.setScenario(SCENARIO);
            Logger.debug(
                'Sales Connection URL could not be built for created quote. ' +
                exceptionValue.getMessage()
            ).addTag(LOGGER_TAG);
            response.salesConnectionUrl = null;
        }
        return response;
    }

    private static void persistStoredSalesConnectionQuoteUrl(
        Quote quoteRecord,
        Opportunity opportunityRecord,
        Account accountRecord,
        String sfRequest
    ) {
        if (LSSalesConnectionUrlService.SF_REQUEST_CREATE.equals(sfRequest)) {
            persistStoredCreateQuoteUrl(quoteRecord, opportunityRecord, accountRecord);
            return;
        }

        if (quoteRecord == null || quoteRecord.Id == null || opportunityRecord == null) {
            return;
        }

        try {
            String storedUrl = LSSalesConnectionUrlService.buildStoredQuoteRequestUrl(
                opportunityRecord.Id,
                quoteRecord.Id,
                accountRecord,
                LSSalesConnectionUrlService.resolveCurrentUserEmployeeNumber(),
                sfRequest
            );

            if (!Schema.sObjectType.Quote.isUpdateable()) {
                return;
            }

            update new Quote(
                Id = quoteRecord.Id,
                SalesConnectionCreateQuoteURL__c = storedUrl
            );
        } catch (Exception exceptionValue) {
            Logger.setScenario(SCENARIO);
            Logger.debug(
                'Stored Sales Connection quote URL could not be saved. ' +
                exceptionValue.getMessage()
            ).addTag(LOGGER_TAG);
        }
    }

    private static void persistStoredCreateQuoteUrl(
        Quote quoteRecord,
        Opportunity opportunityRecord,
        Account accountRecord
    ) {
        if (quoteRecord == null || quoteRecord.Id == null || opportunityRecord == null) {
            return;
        }

        try {
            String storedCreateQuoteUrl = LSSalesConnectionUrlService.buildStoredCreateQuoteUrl(
                opportunityRecord.Id,
                quoteRecord.Id,
                accountRecord,
                LSSalesConnectionUrlService.resolveCurrentUserEmployeeNumber()
            );

            if (!Schema.sObjectType.Quote.isUpdateable()) {
                return;
            }

            update new Quote(
                Id = quoteRecord.Id,
                SalesConnectionCreateQuoteURL__c = storedCreateQuoteUrl
            );
        } catch (Exception exceptionValue) {
            Logger.setScenario(SCENARIO);
            Logger.debug(
                'Stored Sales Connection create-quote URL could not be saved. ' +
                exceptionValue.getMessage()
            ).addTag(LOGGER_TAG);
        }
    }

    private static Account getAccountForSalesConnection(Opportunity opportunityRecord) {
        if (opportunityRecord == null || opportunityRecord.AccountId == null) {
            return null;
        }

        try {
            return AccountSelector.selectAccountForSalesConnection(opportunityRecord.AccountId);
        } catch (Exception exceptionValue) {
            Logger.setScenario(SCENARIO);
            Logger.debug(
                'Account fields for Sales Connection URL are not accessible. ' +
                exceptionValue.getMessage()
            ).addTag(LOGGER_TAG);
            return null;
        }
    }

    private static void insertCreatableRecords(List<SObject> sObjectList, String objectName) {
        if (sObjectList == null || sObjectList.isEmpty()) {
            return;
        }

        if (!isCreateable(objectName)) {
            throw new GenerateQuoteException('Current user cannot create ' + objectName + ' records.');
        }

        List<SObject> recordsToInsert = sObjectList;

        Database.SaveResult[] saveResults = Database.insert(recordsToInsert, false);

        for (Database.SaveResult saveResult : saveResults) {
            if (!saveResult.isSuccess()) {
                throw new GenerateQuoteException(
                    objectName + ' insert failed: ' + saveResult.getErrors()[0].getMessage()
                );
            }
        }
    }

    private static Boolean isCreateable(String objectName) {
        if (objectName == 'Quote') {
            return Schema.sObjectType.Quote.isCreateable();
        }

        if (objectName == 'QuoteLineItem') {
            return Schema.sObjectType.QuoteLineItem.isCreateable();
        }

        return false;
    }
}