/**
 * @author Divya Sree
 * @date 2026/05/25
 *
 * @group Account Management
 *
 * @description
 * Apex controller exposed to the AccountTeamMemberDetails Lightning Web Component.
 * Acts as the entry point from the UI: delegates business logic to
 * AccountTeamMemberService and translates service exceptions into
 * AuraHandledException so the LWC can display meaningful error messages.
 */
public with sharing class AccountTeamMemberDetailsController {

    @TestVisible
    private static final String SALES_OPS_PERMISSION_SET_GROUP_NAME =
        'SalesCustomerOpsSalesSupportSalesAdminPSG';

    @TestVisible
    private static Boolean canViewAccessFieldsForTest;

    /**
     * @description
     * Aura-enabled method invoked by the LWC to load Account Team Member
     * details for a given Account record page.
     *
     * @param accountId Salesforce Id of the Account displayed on the record page.
     * @return List of AccountTeamMemberDTO objects for UI rendering.
     * @throws AuraHandledException when the service layer fails to retrieve data.
     */
    @AuraEnabled
    public static List<AccountTeamMemberDTO> getAccountTeamMembers(Id accountId) {

        try {
            Boolean canViewAccessFields =
                canViewAccessFieldsForTest != null
                ? canViewAccessFieldsForTest
                : currentUserHasSalesOpsPermissionSetGroup();

            return AccountTeamMemberService.getAccountTeamMemberDetails(
                accountId,
                canViewAccessFields
            );

        } catch (AccountTeamMemberService.AccountTeamMemberException exceptionRecord) {
            throw new AuraHandledException(exceptionRecord.getMessage());
        }
    }

    /**
     * @description
     * Access columns (Account/Case/Contact/Opportunity Access) are visible only
     * to the Sales Ops persona. Other Sales permission set groups do not receive
     * these fields in the query or the LWC datatable.
     *
     * @return true when the running user is assigned SalesCustomerOpsSalesSupportSalesAdminPSG.
     */
    @TestVisible
    private static Boolean currentUserHasSalesOpsPermissionSetGroup() {
        List<PermissionSetGroup> salesOpsPermissionSetGroups = [
            SELECT Id
            FROM PermissionSetGroup
            WHERE DeveloperName = :SALES_OPS_PERMISSION_SET_GROUP_NAME
            LIMIT 1
        ];

        if (salesOpsPermissionSetGroups.isEmpty()) {
            return false;
        }

        return [
                SELECT Id
                FROM PermissionSetAssignment
                WHERE AssigneeId = :UserInfo.getUserId()
                AND PermissionSetGroupId = :salesOpsPermissionSetGroups[0].Id
                LIMIT 1
            ]
            .size() > 0;
    }
}