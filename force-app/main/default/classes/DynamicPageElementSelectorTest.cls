/**
 * @date 2026/07/28
 *
 * @group Account Management
 *
 * @description
 * Unit tests for DynamicPageElementSelector CMDT queries.
 * GC-3183
 */
@IsTest(SeeAllData=false)
private class DynamicPageElementSelectorTest {

    private static final String TEST_PAGE_NAME = 'DpeSelectorTestPage';
    private static final String UNKNOWN_PAGE_NAME = 'UnknownPageName';
    private static final String FORCED_EXCEPTION_MESSAGE = 'Forced exception for test coverage.';

    /**
     * @description
     * Resets selector mocks before each test method runs.
     */
    private static void resetMocks() {
        DynamicPageElementSelector.mockConfigs = null;
        DynamicPageElementSelector.isForceExceptionForTest = false;
    }

    /**
     * @description
     * Verifies that mock metadata records are returned when mockConfigs is populated.
     */
    @IsTest
    static void testGetDynamicPageElementsReturnsMockConfigs() {
        resetMocks();

        DynamicPageElement__mdt mockRecord = new DynamicPageElement__mdt();
        mockRecord.ApiName__c = 'MockTab';
        mockRecord.PageName__c = TEST_PAGE_NAME;
        mockRecord.AccessLevel__c = 'Base';
        mockRecord.ElementType__c = 'Tab';
        mockRecord.IsVisible__c = true;
        DynamicPageElementSelector.mockConfigs = new List<DynamicPageElement__mdt>{ mockRecord };

        Test.startTest();
        List<DynamicPageElement__mdt> results =
            DynamicPageElementSelector.getDynamicPageElements(TEST_PAGE_NAME, 'Base');
        Test.stopTest();

        Assert.areEqual(1, results.size(), 'Expected the mocked page element.');
        Assert.areEqual('MockTab', results[0].ApiName__c, 'Expected the mocked ApiName__c.');
    }

    /**
     * @description
     * Verifies the Full access query runs for a page this test owns and returns no org metadata.
     */
    @IsTest
    static void testGetDynamicPageElementsFullAccessQueriesMetadata() {
        resetMocks();

        Test.startTest();
        List<DynamicPageElement__mdt> results =
            DynamicPageElementSelector.getDynamicPageElements(TEST_PAGE_NAME, 'Full');
        Test.stopTest();

        Assert.isNotNull(results, 'Full access query should return a list.');
        Assert.areEqual(0, results.size(), 'A test-only page name should not return org metadata.');
    }

    /**
     * @description
     * Verifies the Base access query runs for a page this test owns and returns no org metadata.
     */
    @IsTest
    static void testGetDynamicPageElementsBaseAccessQueriesMetadata() {
        resetMocks();

        Test.startTest();
        List<DynamicPageElement__mdt> results =
            DynamicPageElementSelector.getDynamicPageElements(TEST_PAGE_NAME, 'Base');
        Test.stopTest();

        Assert.isNotNull(results, 'Base access query should return a list.');
        Assert.areEqual(0, results.size(), 'A test-only page name should not return org metadata.');
    }

    /**
     * @description
     * Verifies an unknown page name returns an empty list from the selector.
     */
    @IsTest
    static void testGetDynamicPageElementsUnknownPageReturnsEmpty() {
        resetMocks();

        Test.startTest();
        List<DynamicPageElement__mdt> results =
            DynamicPageElementSelector.getDynamicPageElements(UNKNOWN_PAGE_NAME, 'Full');
        Test.stopTest();

        Assert.areEqual(0, results.size(), 'An unknown page name should return an empty list.');
    }

    /**
     * @description
     * Verifies a query failure is logged and rethrown.
     */
    @IsTest
    static void testGetDynamicPageElementsRethrowsQueryException() {
        resetMocks();
        DynamicPageElementSelector.isForceExceptionForTest = true;
        Boolean wasRethrown = false;
        String exceptionMessage;
        Integer logCountBefore = Logger.getBufferSize();

        Test.startTest();
        try {
            DynamicPageElementSelector.getDynamicPageElements(TEST_PAGE_NAME, 'Base');
        } catch (Exception exceptionRecord) {
            wasRethrown = true;
            exceptionMessage = exceptionRecord.getMessage();
        }
        Integer logCountAfter = Logger.getBufferSize();
        Test.stopTest();

        Assert.areEqual(true, wasRethrown, 'Expected the selector to rethrow the query exception.');
        Assert.areEqual(
            FORCED_EXCEPTION_MESSAGE,
            exceptionMessage,
            'Expected the forced exception message.'
        );
        Assert.areEqual(
            logCountBefore + 1,
            logCountAfter,
            'Expected the catch block to add one error log entry.'
        );
    }
}