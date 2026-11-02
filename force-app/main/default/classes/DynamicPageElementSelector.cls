/**
 * @date 2026/07/22
 *
 * @group Account Management
 *
 * @description
 * Data access layer for DynamicPageElement__mdt custom metadata (GC-3183).
 * Executes SOQL filtered by PageName__c, AccessLevel__c, and IsVisible__c.
 * Full-access users receive Base + Full rows; Base users receive Base rows only.
 * Deduplication (Full wins on duplicate ApiName__c) is handled in DynamicPageElementService.
 *
 * Supports test mocking via mockConfigs for DynamicPageElementControllerTest.
 *
 * @see DynamicPageElementService
 * @see DynamicPageElement__mdt
 * GC-3183
 */
public with sharing class DynamicPageElementSelector {

    /** @description Nebula Logger scenario for metadata engine transactions. */
    private static final String SCENARIO = 'Metadata Engine';

    /** @description Nebula Logger tag for this class. */
    private static final String LOGGER_TAG = 'DynamicPageElementSelector';

    /** @description Access level value used when the user is on the Account Team. */
    private static final String ACCESS_LEVEL_FULL = 'Full';

    /**
     * @description
     * Test-only mock DynamicPageElement metadata records returned by getDynamicPageElements.
     */
    @TestVisible
    private static List<DynamicPageElement__mdt> mockConfigs;

    /**
     * @description
     * When true during a test, getDynamicPageElements throws before querying so the catch path can be covered.
     */
    @TestVisible
    private static Boolean isForceExceptionForTest = false;

    /**
     * @description
     * Retrieves visible DynamicPageElement custom metadata records for the provided page
     * and access level. Full access users receive Base and Full rows; Base users
     * receive Base rows only.
     *
     * @param pageName Configured page name matching PageName__c.
     * @param accessLevel Resolved access level value, such as Full or Base.
     * @return List of visible DynamicPageElement metadata records ordered by DisplayOrder__c.
     */
    public static List<DynamicPageElement__mdt> getDynamicPageElements(
        String pageName,
        String accessLevel
    ) {
        if (Test.isRunningTest() && mockConfigs != null) {
            return mockConfigs;
        }

        try {
            if (Test.isRunningTest() && isForceExceptionForTest) {
                throw new QueryException('Forced exception for test coverage.');
            }
            if (accessLevel == ACCESS_LEVEL_FULL) {
                return [
                    SELECT
                        PageName__c,
                        AccessLevel__c,
                        ElementType__c,
                        ApiName__c,
                        ParentApiName__c,
                        Label__c,
                        ObjectAPIName__c,
                        FieldAPIName__c,
                        ComponentAPIName__c,
                        Column__c,
                        DisplayOrder__c,
                        IsVisible__c,
                        IsEditable__c,
                        PropsJson__c,
                        LeftSideFields__c,
                        RightSideFields__c
                    FROM DynamicPageElement__mdt
                    WHERE PageName__c = :pageName
                      AND AccessLevel__c IN ('Base', 'Full')
                      AND IsVisible__c = TRUE
                    ORDER BY DisplayOrder__c ASC
                ];
            }

            return [
                SELECT
                    PageName__c,
                    AccessLevel__c,
                    ElementType__c,
                    ApiName__c,
                    ParentApiName__c,
                    Label__c,
                    ObjectAPIName__c,
                    FieldAPIName__c,
                    ComponentAPIName__c,
                    Column__c,
                    DisplayOrder__c,
                    IsVisible__c,
                    IsEditable__c,
                    PropsJson__c,
                    LeftSideFields__c,
                    RightSideFields__c
                FROM DynamicPageElement__mdt
                WHERE PageName__c = :pageName
                  AND AccessLevel__c = 'Base'
                  AND IsVisible__c = TRUE
                ORDER BY DisplayOrder__c ASC
            ];
        } catch (Exception exceptionRecord) {
            Logger.setScenario(SCENARIO);
            Logger.error(
                LOGGER_TAG + ': Unable to retrieve page elements for pageName=' + pageName
                    + ', accessLevel=' + accessLevel,
                exceptionRecord
            )
                .addTag(LOGGER_TAG)
                .addTag('MetadataEngine')
                .addTag('GC-3183');
            throw exceptionRecord;
        }
    }
}