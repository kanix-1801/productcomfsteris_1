/**
 * @author PWC Developer
 * @date 2026/08/28
 *
 * @group Action Launcher
 *
 * @description
 * GC-3346 - LWC controller for the custom Account Action Launcher. Contains only UI-facing operations.
 */
@SuppressWarnings('PMD.UseSingleton')
public with sharing class ActionLauncherController {

    public static final String SCENARIO = 'Action Launcher';
    public static final String LOGGER_TAG = 'ActionLauncher';

    /**
     * @description
     * GC-3346 - Action metadata returned to the Action Launcher LWC.
     */
    public class LauncherAction {
        @AuraEnabled public String apiName;
        @AuraEnabled public String label;
        @AuraEnabled public String actionType;
        @AuraEnabled public String targetSobjectType;
        @AuraEnabled public String url;
        @AuraEnabled public Boolean opensInNewWindow;
    }

    /**
     * @description
     * GC-3346 - Returns configured quick actions and URL custom buttons for the Action Launcher LWC.
     *
     * @param recordId Current record id used to resolve custom button merge fields.
     * @param objectApiName Current record object API name.
     * @param actionApiNames Comma-separated action API names in display order.
     * @return Action metadata available to the current user.
     */
    @AuraEnabled(cacheable=true)
    public static List<LauncherAction> getActions(
        String recordId,
        String objectApiName,
        String actionApiNames
    ) {
        try {
            return ActionLauncherService.getActions(recordId, objectApiName, actionApiNames);
        } catch (Exception exceptionValue) {
            Logger.setScenario(SCENARIO);
            Logger.error(
                'Unable to retrieve Action Launcher actions. ' + exceptionValue.getMessage()
            ).addTag(LOGGER_TAG);

            throw new AuraHandledException('Unable to retrieve Action Launcher actions.');
        } finally {
            Logger.saveLog();
        }
    }
}