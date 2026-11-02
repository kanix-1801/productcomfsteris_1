/**
 * @author Divya Sree
 * @date 2026/07/20
 *
 * @group AccountAccountRelationship
 *
 * @description
 * LWC-facing entry point for the "Account Account Relationship" tab on
 * Customer 360. Delegates all logic to AccountAccountRelationshipService.
 * Related story: GC-3126.
 */
public with sharing class AccountAccountRelationshipController {

    /**
     * @description
     * Test-only override to force getAccountType and isSystemAdministrator
     * to throw, so callers can verify their exception handling behavior.
     * Added at the Controller level since the Service class cannot be
     * modified for this change.
     */
    @TestVisible
    private static Boolean forceExceptionForTest = false;

    /**
     * @description
     * Returns the relationship records to display for the given Account.
     *
     * @param accountId Id of the Account currently being viewed
     * @return List of AccountAccountRelationship__c records
     * @example
     * AccountAccountRelationshipController.getRelationships(accId);
     */
    @AuraEnabled(cacheable=true)
    public static List<AccountAccountRelationship__c> getRelationships(Id accountId) {
        try {
            return AccountAccountRelationshipService.getRelationshipsForAccount(accountId);
        } catch (Exception e) {
            throw new AuraHandledException(
                'Unable to load Account Account Relationships. ' +
                e.getTypeName() + ': ' + e.getMessage()
            );
        }
    }

    /**
     * @description
     * Returns the Type value of the given Account, used to determine which
     * lookup field to pre-fill when creating a new relationship.
     *
     * @param accountId Id of the Account currently being viewed
     * @return The Account.Type value
     * @example
     * AccountAccountRelationshipController.getAccountType(accId);
     */
    @AuraEnabled(cacheable=true)
    public static String getAccountType(Id accountId) {
        try {
            if (Test.isRunningTest() && forceExceptionForTest) {
                throw new AccountAccountRelationshipException('Forced exception for test coverage.');
            }
            return AccountAccountRelationshipService.getAccountType(accountId);
        } catch (Exception e) {
            throw new AuraHandledException(
                'Unable to load Account details. ' +
                e.getTypeName() + ': ' + e.getMessage()
            );
        }
    }

    /**
     * @description
     * Returns whether the current user is a System Administrator, used to
     * show/hide the "New" relationship creation button.
     *
     * @return True if the running user's Profile is System Administrator
     * @example
     * AccountAccountRelationshipController.isSystemAdministrator();
     */
    @AuraEnabled(cacheable=true)
    public static Boolean isSystemAdministrator() {
        try {
            if (Test.isRunningTest() && forceExceptionForTest) {
                throw new AccountAccountRelationshipException('Forced exception for test coverage.');
            }
            return AccountAccountRelationshipService.isSystemAdministrator();
        } catch (Exception e) {
            throw new AuraHandledException(
                'Unable to check user access. ' +
                e.getTypeName() + ': ' + e.getMessage()
            );
        }
    }
}