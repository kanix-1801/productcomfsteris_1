/**
 * @author Vinay
 * @date 2026/06/05
 *
 * @group Account Management
 */
 /** @description 
 * Selector layer for Account page visibility queries.
 * Contains SOQL-only access for Account Team Member and Account Page Visibility metadata.
 */
public with sharing class AccountPageVisibilitySelector {

    /**
     * @description
     * Test-only override for isCurrentUserAccountTeamMember query results.
     */
    @TestVisible
    private static Boolean mockIsTeamMember;

    /**
     * @description
     * Test-only mock visibility configuration metadata records.
     */
    @TestVisible
    private static List<Account_Page_Visibility_Config__mdt> mockConfigs;

    /**
     * @description
     * Retrieves Account page visibility custom metadata records for the provided page
     * and access level.
     *
     * @param pageName Configured page name.
     * @param accessLevel Access level value, such as Full or Base.
     * @return List of Account page visibility configuration metadata records.
     */
    public static List<Account_Page_Visibility_Config__mdt> getVisibilityConfigs(
        String pageName,
        String accessLevel
    ) {
        if (Test.isRunningTest() && mockConfigs != null) {
            return mockConfigs;
        }

        return [
            SELECT
                Access_Level__c,
                PageName__c,
                Element_Type__c,
                TabAPIName__c,
                ComponentAPIName__c,
                IsVisible__c,
                DisplayOrder__c
            FROM Account_Page_Visibility_Config__mdt
            WHERE PageName__c = :pageName AND Access_Level__c = :accessLevel
            ORDER BY DisplayOrder__c ASC
        ];
    }

    /**
     * @description
     * Determines whether the current user is an Account Team Member for the supplied Account.
     *
     * @param accountId Account record Id.
     * @return TRUE when the current user is an Account Team Member; otherwise FALSE.
     */
    public static Boolean isCurrentUserAccountTeamMember(Id accountId) {
        if (Test.isRunningTest() && mockIsTeamMember != null) {
            return mockIsTeamMember;
        }

        return ![
            SELECT Id
            FROM AccountTeamMember
            WHERE AccountId = :accountId
            AND UserId = :UserInfo.getUserId()
            LIMIT 1
        ].isEmpty();
    }
}