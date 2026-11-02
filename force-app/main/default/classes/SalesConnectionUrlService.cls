/**
 * @author Himanshu Chaurasia
 * @date 2026/06/18
 *
 * @group Generate Quote
 *
 * @description
 * GC-2642 Builds Sales Connection navigation URLs from ExternalSystemEndpoint custom metadata.
 * Create-quote URLs are stored in plain text on the Quote and encrypted when opened in a new tab.
 */
public with sharing class SalesConnectionUrlService {
    public static final String ACCOUNT_TYPE_CUSTOMER = 'C';
    public static final String ACCOUNT_TYPE_PROSPECT = 'P';
    public static final String ACCOUNT_RECORD_TYPE_CUSTOMER = 'Customer';
    public static final String ACCOUNT_RECORD_TYPE_PROSPECT = 'Prospect';
    public static final String CREATE_QUOTE_HASH_PREFIX = '#Quote|';
    public static final String HARDCODED_CREATE_QUOTE_ID = '0';
    public static final String DEFAULT_VIEW_QUOTE_PATH = '#Quote|id={0}';
    public static final String SF_REQUEST_CREATE = 'create';
    public static final String SF_REQUEST_COPY = 'copy';
    public static final String SF_REQUEST_MERGE = 'merge';

    @TestVisible
    private static ExternalSystemEndpoint__mdt testSettingsOverride;

    @TestVisible
    private static String testEmployeeNumberOverride;

    /**
     * @description Builds the Sales Connection URL used when opening a Quote in the browser.
     * @param quoteRecord Quote with optional Sales Connection quote id or stored create-quote URL.
     * @param opportunityRecord Opportunity related to the quote.
     * @param accountRecord Parent Account on the Opportunity.
     * @return Encrypted create-quote URL or plain view-quote URL.
     */
    public static String buildQuoteUrl(
        Quote quoteRecord,
        Opportunity opportunityRecord,
        Account accountRecord
    ) {
        if (quoteRecord == null || opportunityRecord == null) {
            return null;
        }

        String viewQuoteId = GenerateQuoteService.resolveSalesConnectionViewQuoteId(quoteRecord);
        if (String.isNotBlank(viewQuoteId)) {
            return buildExistingQuoteUrl(viewQuoteId);
        }

        if (String.isNotBlank(quoteRecord.SalesConnectionCreateQuoteURL__c)) {
            return buildOpenCreateQuoteUrl(quoteRecord.SalesConnectionCreateQuoteURL__c);
        }

        return buildOpenCreateQuoteUrl(
            opportunityRecord.Id,
            quoteRecord.Id,
            accountRecord,
            resolveCurrentUserEmployeeNumber()
        );
    }

    /**
     * @description Builds and stores the plain-text create-quote URL format on a Salesforce Quote.
     * @param opportunityId Opportunity Id.
     * @param quoteId Salesforce Quote Id.
     * @param accountRecord Parent Account on the Opportunity.
     * @param employeeNumber HRIS employee number for the creating user.
     * @return Plain-text Sales Connection create-quote URL.
     */
    public static String buildStoredCreateQuoteUrl(
        Id opportunityId,
        Id quoteId,
        Account accountRecord,
        String employeeNumber
    ) {
        validateAccountForCreateQuote(accountRecord);
        validateEmployeeNumber(employeeNumber);

        String payload = buildQuoteRequestPayload(
            opportunityId,
            quoteId,
            accountRecord,
            employeeNumber,
            SF_REQUEST_CREATE
        );

        return combineBaseUrlAndPath(getBaseUrl(), CREATE_QUOTE_HASH_PREFIX + payload);
    }

    /**
     * @description Builds and stores the plain-text Sales Connection URL for copy or merge shell quotes.
     * @param opportunityId Opportunity Id.
     * @param quoteId Salesforce Quote Id.
     * @param accountRecord Parent Account on the Opportunity.
     * @param employeeNumber HRIS employee number for the creating user.
     * @param sfRequest Sales Connection sfrequest value (copy or merge).
     * @return Plain-text Sales Connection URL.
     */
    public static String buildStoredQuoteRequestUrl(
        Id opportunityId,
        Id quoteId,
        Account accountRecord,
        String employeeNumber,
        String sfRequest
    ) {
        validateAccountForCreateQuote(accountRecord);
        validateEmployeeNumber(employeeNumber);
        validateSfRequest(sfRequest);

        String payload = buildQuoteRequestPayload(
            opportunityId,
            quoteId,
            accountRecord,
            employeeNumber,
            sfRequest
        );

        return combineBaseUrlAndPath(getBaseUrl(), CREATE_QUOTE_HASH_PREFIX + payload);
    }

    /**
     * @description Builds the encrypted create-quote URL opened in a new browser tab.
     * @param opportunityId Opportunity Id.
     * @param quoteId Salesforce Quote Id.
     * @param accountRecord Parent Account on the Opportunity.
     * @param employeeNumber HRIS employee number for the creating user.
     * @return Encrypted Sales Connection create-quote URL.
     */
    public static String buildOpenCreateQuoteUrl(
        Id opportunityId,
        Id quoteId,
        Account accountRecord,
        String employeeNumber
    ) {
        return buildOpenCreateQuoteUrl(
            buildStoredCreateQuoteUrl(opportunityId, quoteId, accountRecord, employeeNumber)
        );
    }

    /**
     * @description Builds the encrypted create-quote URL from a stored plain-text URL.
     * @param storedCreateQuoteUrl Plain-text URL saved on the Quote record.
     * @return Encrypted Sales Connection create-quote URL.
     */
    public static String buildOpenCreateQuoteUrl(String storedCreateQuoteUrl) {
        if (String.isBlank(storedCreateQuoteUrl)) {
            return null;
        }

        String payload = extractCreateQuotePayload(storedCreateQuoteUrl);
        String encryptedPayload = SalesConnectionEncryptionService.encrypt(payload);
        String baseUrl = storedCreateQuoteUrl.substringBefore(CREATE_QUOTE_HASH_PREFIX);

        return combineBaseUrlAndPath(baseUrl, CREATE_QUOTE_HASH_PREFIX + encryptedPayload);
    }

    /**
     * @description Backward-compatible wrapper that returns the encrypted create-quote URL.
     * @param opportunityId Opportunity Id.
     * @param quoteId Salesforce Quote Id.
     * @param accountRecord Parent Account on the Opportunity.
     * @return Encrypted Sales Connection create-quote URL.
     */
    public static String buildCreateQuoteUrl(Id opportunityId, Id quoteId, Account accountRecord) {
        return buildOpenCreateQuoteUrl(
            opportunityId,
            quoteId,
            accountRecord,
            resolveCurrentUserEmployeeNumber()
        );
    }

    /**
     * @description Builds the Sales Connection view-quote URL from the quote identifier.
     * @param viewQuoteId QuoteNumber__c or Sales Connection quote id for the view URL.
     * @return Sales Connection view-quote URL.
     */
    public static String buildExistingQuoteUrl(String viewQuoteId) {
        if (String.isBlank(viewQuoteId)) {
            return null;
        }

        ExternalSystemEndpoint__mdt settings = getSettings();
        String pathTemplate = String.isNotBlank(settings.SalesConnectionViewQuotePath__c)
            ? settings.SalesConnectionViewQuotePath__c
            : DEFAULT_VIEW_QUOTE_PATH;

        String path = String.format(pathTemplate, new List<String>{ viewQuoteId });
        return combineBaseUrlAndPath(getBaseUrl(), path);
    }

    /**
     * @description Resolves the creating user's HRIS employee number.
     * @return Employee number for the running user.
     */
    public static String resolveCurrentUserEmployeeNumber() {
        if (Test.isRunningTest() && String.isNotBlank(testEmployeeNumberOverride)) {
            return testEmployeeNumberOverride;
        }

        User currentUser = [
            SELECT EmployeeNumber__c, EmployeeNumber
            FROM User
            WHERE Id = :UserInfo.getUserId()
            WITH SYSTEM_MODE
            LIMIT 1
        ];

        if (String.isNotBlank(currentUser.EmployeeNumber__c)) {
            return currentUser.EmployeeNumber__c.trim();
        }

        if (String.isNotBlank(currentUser.EmployeeNumber)) {
            return currentUser.EmployeeNumber.trim();
        }

        throw new AuraHandledException(
            'Employee Number is required on the User record before opening Sales Connection.'
        );
    }

    @TestVisible
    private static String buildQuoteRequestPayload(
        Id opportunityId,
        Id quoteId,
        Account accountRecord,
        String employeeNumber,
        String sfRequest
    ) {
        validateSfRequest(sfRequest);

        return 'id=' + HARDCODED_CREATE_QUOTE_ID +
            '&addressid=' + accountRecord.OracleAddressId__c +
            '&accounttype=' + resolveAccountType(accountRecord) +
            '&sfrequest=' + sfRequest +
            '&sfopportunityid=' + String.valueOf(opportunityId) +
            '&sfquoteid=' + String.valueOf(quoteId) +
            '&employeenumber=' + employeeNumber;
    }

    private static void validateSfRequest(String sfRequest) {
        if (
            !SF_REQUEST_CREATE.equals(sfRequest) &&
            !SF_REQUEST_COPY.equals(sfRequest) &&
            !SF_REQUEST_MERGE.equals(sfRequest)
        ) {
            throw new AuraHandledException('Sales Connection sfrequest value is not supported.');
        }
    }

    @TestVisible
    private static String extractCreateQuotePayload(String storedCreateQuoteUrl) {
        Integer payloadStartIndex = storedCreateQuoteUrl.indexOf(CREATE_QUOTE_HASH_PREFIX);

        if (payloadStartIndex < 0) {
            throw new AuraHandledException('Stored Sales Connection create-quote URL is invalid.');
        }

        return storedCreateQuoteUrl.substring(
            payloadStartIndex + CREATE_QUOTE_HASH_PREFIX.length()
        );
    }

    private static void validateAccountForCreateQuote(Account accountRecord) {
        if (accountRecord == null) {
            throw new AuraHandledException(
                'An Account is required on the Opportunity before opening Sales Connection.'
            );
        }

        if (String.isBlank(accountRecord.OracleAddressId__c)) {
            throw new AuraHandledException(
                'Oracle Address Id is required on the Account before opening Sales Connection.'
            );
        }
    }

    private static void validateEmployeeNumber(String employeeNumber) {
        if (String.isBlank(employeeNumber)) {
            throw new AuraHandledException(
                'Employee Number is required on the User record before opening Sales Connection.'
            );
        }
    }

    private static String resolveAccountType(Account accountRecord) {
        String recordTypeDeveloperName = accountRecord.RecordType?.DeveloperName;

        if (ACCOUNT_RECORD_TYPE_PROSPECT.equalsIgnoreCase(recordTypeDeveloperName)) {
            return ACCOUNT_TYPE_PROSPECT;
        }

        return ACCOUNT_TYPE_CUSTOMER;
    }

    private static String getBaseUrl() {
        String baseUrl = getSettings().SalesConnectionBaseUrl__c;

        if (String.isBlank(baseUrl)) {
            throw new AuraHandledException(
                'Sales Connection Base URL is not configured. Please contact your administrator.'
            );
        }

        return baseUrl;
    }

    private static String combineBaseUrlAndPath(String baseUrl, String path) {
        String normalizedBaseUrl = baseUrl.removeEnd('/');
        String normalizedPath = String.isBlank(path) ? '' : path;

        if (normalizedPath.startsWith('#')) {
            return normalizedBaseUrl + '/' + normalizedPath;
        }

        if (normalizedPath.startsWith('/')) {
            return normalizedBaseUrl + normalizedPath;
        }

        return normalizedBaseUrl + '/' + normalizedPath;
    }

    private static ExternalSystemEndpoint__mdt getSettings() {
        if (Test.isRunningTest() && testSettingsOverride != null) {
            return testSettingsOverride;
        }

        ExternalSystemEndpoint__mdt settings = ExternalSystemEndpointSelector.selectSalesConnection();
        return settings == null ? new ExternalSystemEndpoint__mdt() : settings;
    }
}