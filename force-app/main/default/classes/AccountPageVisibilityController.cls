/**
 * @author Vinay
 * @date 2026/06/05
 *
 * @group Account Management
 *
 * @description
 * Controller for retrieving Account page visibility configuration for Lightning components.
 * Delegates to AccountPageVisibilityService to determine user access level and
 * return configured page element visibility settings.
 */
public with sharing class AccountPageVisibilityController {

    /**
     * @description
     * Retrieves visibility configuration for the specified Account and page name.
     *
     * @param accountId Account record Id used to determine the current user's access level.
     * @param pageName Page name used to retrieve configured visibility metadata.
     * @return Visibility response containing access level and configured page elements.
     */
    @AuraEnabled(cacheable=true)
    public static AccountPageVisibilityService.VisibilityResponse getVisibilityConfig(
        Id accountId,
        String pageName
    ) {
        return AccountPageVisibilityService.getVisibilityConfig(accountId, pageName);
    }
}