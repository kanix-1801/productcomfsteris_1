/**
 * @author PWC Developer
 * @date 2026/11/04
 *
 * @group Life Sciences Overlay Assignment
 *
 * @description
 * GCL-79 - LWC controller for Life Sciences Overlay Assignment. This class contains only UI-facing operations.
 */
public with sharing class LsOverlayAssignmentController {

    /**
     * @description
     * GCL-79 - Returns the AssignmentType__c value this wizard writes, so the confirmation
     * screen stays in sync with LsOverlayAssignmentService.
     *
     * @return The AssignmentType__c value this wizard assigns on submit.
     *
     * @example
     * LsOverlayAssignmentController.getAssignmentTypeLabel();
     */
    @AuraEnabled(cacheable=true)
    public static String getAssignmentTypeLabel() {
        return LsOverlayAssignmentService.ASSIGNMENT_TYPE_SALESFORCE_ASSIGNED;
    }

    /**
     * @description
     * Returns the overlay types shown on the pre-wizard, with the Account Team role each one writes.
     *
     * @return One option per overlay type: value, label, and teamMemberRole.
     *
     * @example
     * LsOverlayAssignmentController.getOverlayTypeOptions();
     */
    @AuraEnabled(cacheable=true)
    public static List<Map<String, String>> getOverlayTypeOptions() {
        return new List<Map<String, String>>{
            new Map<String, String>{
                'value' => LsOverlayAssignmentService.OVERLAY_TYPE_INSIDE_SALES,
                'label' => LsOverlayAssignmentService.OVERLAY_TYPE_INSIDE_SALES,
                'teamMemberRole' => LsOverlayAssignmentService.TEAM_MEMBER_ROLE_INSIDE_SALES
            },
            new Map<String, String>{
                'value' => LsOverlayAssignmentService.OVERLAY_TYPE_GAD,
                'label' => LsOverlayAssignmentService.OVERLAY_TYPE_GAD,
                'teamMemberRole' => LsOverlayAssignmentService.TEAM_MEMBER_ROLE_GAD
            }
        };
    }

    /**
     * @description
     * GCL-79 - Searches Life Sciences TAS territory records for matching Territory ID, Description, or Number.
     *
     * @param searchKey User-entered search text.
     * @return Matching Life Sciences territories for selection.
     *
     * @example
     * LsOverlayAssignmentController.searchTerritories(searchKey);
     */
    @AuraEnabled
    public static List<OverlayAssignmentController.TerritoryWrapper> searchTerritories(String searchKey) {
        try {
            //GCL-390 : Tech Story - Hc x LS code dependency resolution
            return OverlayAssignmentService.searchTerritories(searchKey);
        } catch (Exception exceptionValue) {
            throw buildHandledException('Unable to search territories.', exceptionValue);
        }
    }

    /**
     * @description
     * GCL-79 - Searches Life Sciences accounts by Account Name, Account Number, and/or Account Type.
     *
     * @param accountSearchKey Account name/number search key.
     * @param accountType Account type selected, if any.
     * @param territoryIds Territory ids selected, if any.
     * @return Matching Life Sciences accounts based on the account search section.
     *
     * @example
     * LsOverlayAssignmentController.searchAccounts(accountSearchKey, accountType, territoryIds);
     */
    @AuraEnabled
    public static List<OverlayAssignmentController.AccountWrapper> searchAccounts(
        String accountSearchKey,
        String accountType,
        List<String> territoryIds
    ) {
        try {
            return LsOverlayAssignmentService.searchAccounts(accountSearchKey, accountType, territoryIds);
        } catch (Exception exceptionValue) {
            throw buildHandledException('Unable to search accounts.', exceptionValue);
        }
    }

    /**
     * @description
     * Searches Global Accounts by Account Name or Account Number for the GAD overlay.
     *
     * @param searchKey Account name/number search key.
     * @return Matching Global Accounts.
     *
     * @example
     * LsOverlayAssignmentController.searchGlobalAccounts(searchKey);
     */
    @AuraEnabled
    public static List<OverlayAssignmentController.AccountWrapper> searchGlobalAccounts(String searchKey) {
        try {
            return LsOverlayAssignmentService.searchGlobalAccounts(searchKey);
        } catch (Exception exceptionValue) {
            throw buildHandledException('Unable to search Global Accounts.', exceptionValue);
        }
    }

    /**
     * @description
     * GCL-79 - Retrieves Customer accounts related to the selected territories and accounts.
     * GPO, IDN, and Address accounts are not returned.
     *
     * @param territoryIds Selected Territory IDs.
     * @param accountSearchKey Account search key.
     * @param accountType Account type, if selected.
     * @param selectedSearchAccountIds Selected account ids from step 1.
     * @return Customer account rows for Step 2.
     *
     * @example
     * LsOverlayAssignmentController.retrieveAccounts(territoryIds, accountSearchKey, accountType, selectedSearchAccountIds);
     */
    @AuraEnabled
    public static List<OverlayAssignmentController.AccountWrapper> retrieveAccounts(
        List<String> territoryIds,
        String accountSearchKey,
        String accountType,
        List<Id> selectedSearchAccountIds
    ) {
        try {
            return LsOverlayAssignmentService.retrieveAccounts(
                territoryIds,
                accountSearchKey,
                accountType,
                selectedSearchAccountIds
            );
        } catch (Exception exceptionValue) {
            throw buildHandledException('Unable to retrieve accounts.', exceptionValue);
        }
    }

    /**
     * @description
     * GCL-79 - Searches active Life Sciences Sales users eligible for overlay assignment selection.
     * Only users with the overlay type's permission set or permission set group are returned.
     *
     * @param searchKey User-entered search text.
     * @param overlayType Inside Sales or GAD.
     * @return Matching users for selection.
     *
     * @example
     * LsOverlayAssignmentController.searchOverlayUsers(searchKey, overlayType);
     */
    @AuraEnabled
    public static List<OverlayAssignmentController.UserWrapper> searchOverlayUsers(String searchKey, String overlayType) {
        try {
            return LsOverlayAssignmentService.searchOverlayUsers(searchKey, overlayType);
        } catch (Exception exceptionValue) {
            throw buildHandledException('Unable to search overlay users.', exceptionValue);
        }
    }

    /**
     * @description
     * GCL-79 - Builds the review summary before final overlay assignment submission.
     *
     * @param territoryIds Selected Territory IDs.
     * @param selectedAccountIds Accounts still selected after Step 2 deselection.
     * @param overlayType Inside Sales or GAD.
     * @return Territory grouped account summary. For GAD, one row per Global Account hierarchy.
     *
     * @example
     * LsOverlayAssignmentController.getAssignmentSummary(territoryIds, selectedAccountIds, overlayType);
     */
    @AuraEnabled
    public static List<OverlayAssignmentController.SummaryTerritoryWrapper> getAssignmentSummary(
        List<String> territoryIds,
        List<Id> selectedAccountIds,
        String overlayType
    ) {
        try {
            return LsOverlayAssignmentService.getAssignmentSummary(territoryIds, selectedAccountIds, overlayType);
        } catch (Exception exceptionValue) {
            throw buildHandledException('Unable to build overlay assignment summary.', exceptionValue);
        }
    }

    /**
     * @description
     * GCL-79 - Creates Account Team records for Life Sciences overlay assignments.
     * Inside Sales gets Account and Contact Edit with no Opportunity access. GAD gets Account and
     * Contact Edit, Opportunity Edit on the Global Account, and Opportunity Read on its hierarchy.
     *
     * @param territoryIds Selected Territory IDs.
     * @param selectedAccountIds Final selected accounts by user.
     * @param userIds Selected overlay User IDs.
     * @param overlayType Inside Sales or GAD.
     *
     * @example
     * LsOverlayAssignmentController.submitOverlayAssignments(territoryIds, selectedAccountIds, userIds, overlayType);
     */
    @AuraEnabled
    public static void submitOverlayAssignments(
        List<String> territoryIds,
        List<Id> selectedAccountIds,
        List<Id> userIds,
        String overlayType
    ) {
        try {
            LsOverlayAssignmentService.submitOverlayAssignments(territoryIds, selectedAccountIds, userIds, overlayType);
        } catch (Exception exceptionValue) {
            throw buildHandledException('Unable to submit overlay assignments.', exceptionValue);
        }
    }

    /**
     * @description
     * GCL-79 - Helper exception handling method.
     *
     * @param message User-safe message used when the exception is not already a Life Sciences overlay exception.
     * @param exceptionValue Exception caught from the service layer.
     * @return AuraHandledException to throw to the LWC caller.
     *
     * @example
     * throw buildHandledException(message, exceptionValue);
     */
    private static AuraHandledException buildHandledException(String message, Exception exceptionValue) {
        String safeMessage = exceptionValue instanceof OverlayAssignmentException
            ? exceptionValue.getMessage()
            : message;
        AuraHandledException auraException = new AuraHandledException(safeMessage);
        auraException.setMessage(safeMessage);
        return auraException;
    }
}