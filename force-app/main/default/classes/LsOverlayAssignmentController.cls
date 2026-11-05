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
     * GCL-79 - Territory search result returned to the Life Sciences Overlay Assignment LWC.
     */
    public class TerritoryWrapper {
        @AuraEnabled public String territoryId;
        @AuraEnabled public String territoryDescription;
    }

    /**
     * @description
     * GCL-79 - Account result returned to the Life Sciences Overlay Assignment LWC.
     */
    public class AccountWrapper {
        @AuraEnabled public Id accountId;
        @AuraEnabled public String accountName;
        @AuraEnabled public String accountNumber;
        @AuraEnabled public String accountType;
        @AuraEnabled public String territoryId;
        @AuraEnabled public String territoryDescription;
        @AuraEnabled public String street;
        @AuraEnabled public String city;
        @AuraEnabled public String state;
        @AuraEnabled public String postalCode;
        @AuraEnabled public String country;
        @AuraEnabled public Id associatedAccountId;
        @AuraEnabled public String associatedAccountName;
    }

    /**
     * @description
     * GCL-79 - Overlay user search result returned to the Life Sciences Overlay Assignment LWC.
     */
    public class UserWrapper {
        @AuraEnabled public Id userId;
        @AuraEnabled public String userName;
        @AuraEnabled public String email;
        @AuraEnabled public String role;
        @AuraEnabled public String country;
        @AuraEnabled public String managerName;
    }

    /**
     * @description
     * GCL-79 - Territory summary returned to the Life Sciences Overlay Assignment LWC before final submission.
     */
    public class SummaryTerritoryWrapper {
        @AuraEnabled public String territoryId;
        @AuraEnabled public String territoryDescription;
        @AuraEnabled public List<AccountWrapper> selectedAccounts;
    }

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
     * GCL-79 - Searches Life Sciences TAS territory records for matching Territory ID, Description, or Number.
     *
     * @param searchKey User-entered search text.
     * @return Matching Life Sciences territories for selection.
     *
     * @example
     * LsOverlayAssignmentController.searchTerritories(searchKey);
     */
    @AuraEnabled
    public static List<TerritoryWrapper> searchTerritories(String searchKey) {
        try {
            return LsOverlayAssignmentService.searchTerritories(searchKey);
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
    public static List<AccountWrapper> searchAccounts(
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
     * GCL-79 - Retrieves address-level Accounts related to the selected territories and accounts.
     *
     * @param territoryIds Selected Territory IDs.
     * @param accountSearchKey Account search key.
     * @param accountType Account type, if selected.
     * @param selectedSearchAccountIds Selected account ids from step 1.
     * @return Address-level account rows for Step 2.
     *
     * @example
     * LsOverlayAssignmentController.retrieveAccounts(territoryIds, accountSearchKey, accountType, selectedSearchAccountIds);
     */
    @AuraEnabled
    public static List<AccountWrapper> retrieveAccounts(
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
     *
     * @param searchKey User-entered search text.
     * @return Matching users for selection.
     *
     * @example
     * LsOverlayAssignmentController.searchOverlayUsers(searchKey);
     */
    @AuraEnabled
    public static List<UserWrapper> searchOverlayUsers(String searchKey) {
        try {
            return LsOverlayAssignmentService.searchOverlayUsers(searchKey);
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
     * @return Territory grouped account summary.
     *
     * @example
     * LsOverlayAssignmentController.getAssignmentSummary(territoryIds, selectedAccountIds);
     */
    @AuraEnabled
    public static List<SummaryTerritoryWrapper> getAssignmentSummary(
        List<String> territoryIds,
        List<Id> selectedAccountIds
    ) {
        try {
            return LsOverlayAssignmentService.getAssignmentSummary(territoryIds, selectedAccountIds);
        } catch (Exception exceptionValue) {
            throw buildHandledException('Unable to build overlay assignment summary.', exceptionValue);
        }
    }

    /**
     * @description
     * GCL-79 - Creates Account Team records for Life Sciences overlay assignments.
     * Only Account access is extended. Opportunity and Case access are not granted.
     *
     * @param territoryIds Selected Territory IDs.
     * @param selectedAccountIds Final selected accounts by user.
     * @param userIds Selected overlay User IDs.
     *
     * @example
     * LsOverlayAssignmentController.submitOverlayAssignments(territoryIds, selectedAccountIds, userIds);
     */
    @AuraEnabled
    public static void submitOverlayAssignments(
        List<String> territoryIds,
        List<Id> selectedAccountIds,
        List<Id> userIds
    ) {
        try {
            LsOverlayAssignmentService.submitOverlayAssignments(territoryIds, selectedAccountIds, userIds);
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
        String safeMessage = exceptionValue instanceof LsOverlayAssignmentException
            ? exceptionValue.getMessage()
            : message;
        AuraHandledException auraException = new AuraHandledException(safeMessage);
        auraException.setMessage(safeMessage);
        return auraException;
    }
}