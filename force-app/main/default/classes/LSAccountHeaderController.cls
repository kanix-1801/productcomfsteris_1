/**
 * @author PWC Developer
 * @date 2026/10/30
 *
 * @group Life Sciences Account
 *
 * @description
 * GCL-100 - LWC controller for the Life Sciences Customer 360 panes.
 * Delegates Full or Base to LSAccountHeaderService. Field display stays in
 * the Lightning components so field-level security is enforced by the UI API.
 */
public with sharing class LSAccountHeaderController {

    /**
     * @description
     * GCL-100 - Logger constants used in the class.
     */
    public static final String SCENARIO = 'LS Account Header';
    public static final String LOGGER_TAG = 'LSAccountHeader';

    /**
     * @description
     * GCL-100 - Returns Full or Base for the running user on this Account.
     *
     * @param accountId Account record opened on the Life Sciences record page.
     * @return Full for the Account owner and for an Account Team member. Base otherwise.
     *
     * @example
     * LSAccountHeaderController.getHeaderView(accountId);
     */
    @AuraEnabled(cacheable=true)
    public static LSAccountHeaderService.HeaderView getHeaderView(Id accountId) {
        try {
            return LSAccountHeaderService.getHeaderView(accountId);
        } catch (Exception exceptionValue) {
            throw buildHandledException('Unable to load the account header.', exceptionValue);
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description
     * GCL-100 - Logs the failure and returns a message the Lightning component can show.
     * Validation messages raised by the service are surfaced unchanged.
     *
     * @param message Fallback error message.
     * @param exceptionValue Exception caught by the calling method.
     * @return AuraHandledException to throw to the LWC caller.
     *
     * @example
     * throw buildHandledException(message, exceptionValue);
     */
    private static AuraHandledException buildHandledException(String message, Exception exceptionValue) {
        Logger.setScenario(SCENARIO);
        Logger.error(message, exceptionValue).addTag(LOGGER_TAG);

        String clientMessage = exceptionValue instanceof LSAccountHeaderException
            ? exceptionValue.getMessage()
            : message;
        AuraHandledException handledException = new AuraHandledException(clientMessage);
        handledException.setMessage(clientMessage);
        return handledException;
    }
}