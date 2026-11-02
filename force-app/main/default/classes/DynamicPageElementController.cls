/**
 * @date 2026/07/22
 *
 * @group Account Management
 *
 * @description
 * Aura-enabled entry point for the metadata-driven page layout framework (GC-3183).
 * Called by metadataPageShell via @wire. Delegates to DynamicPageElementService to determine
 * the user's access level from DynamicPageAccessRule__mdt and return a nested tab, section,
 * field, and component tree built from DynamicPageElement__mdt.
 *
 * @see DynamicPageElementService
 * @see DynamicPageAccessResolver
 * @see DynamicPageElementSelector
 * @see metadataPageShell
 * GC-3183
 */
public with sharing class DynamicPageElementController {

    /** @description Nebula Logger scenario for metadata engine transactions. */
    private static final String SCENARIO = 'Metadata Engine';

    /** @description Nebula Logger tag for this class. */
    private static final String LOGGER_TAG = 'DynamicPageElementController';

    /**
     * @description
     * Retrieves the page layout configuration for the specified record page context.
     *
     * @param recordId Record Id used to evaluate the configured access strategy.
     * @param objectApiName SObject API name for the record page.
     * @param pageName PageName__c value used to retrieve matching DynamicPageElement metadata.
     * @return Page layout response containing access level and configured tab hierarchy.
     */
    @AuraEnabled(cacheable=true)
    public static DynamicPageElementService.DynamicPageElementResponse getPageLayout(
        Id recordId,
        String objectApiName,
        String pageName
    ) {
        try {
            return DynamicPageElementService.getPageLayout(recordId, objectApiName, pageName);
        } catch (Exception exceptionRecord) {
            Logger.setScenario(SCENARIO);
            Logger.error(LOGGER_TAG + ': Unable to retrieve page layout.', exceptionRecord)
                .addTag(LOGGER_TAG)
                .addTag('MetadataEngine')
                .addTag('GC-3183');

            if (exceptionRecord instanceof AuraHandledException) {
                throw exceptionRecord;
            }

            throw new AuraHandledException('Unable to retrieve page layout.');
        } finally {
            try {
                Logger.saveLog();
            } catch (Exception loggingError) {
                // Do not fail the user transaction when Nebula Logger persistence is unavailable.
            }
        }
    }
}