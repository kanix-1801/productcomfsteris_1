/**
 * @author PWC Developer
 * @date 2026/11/13
 *
 * @group Dealer Portal
 *
 * @description Checks whether the current user can see Generate Quote on the partner portal.
 *              Runs without sharing because Experience Cloud users cannot read PermissionSetAssignment.
 */
public without sharing class DealerPortalAccessController {
    private static final String DEALER_MANAGER_PS_PERMISSION_SET = 'DealerManagerPS';

    /**
     * @description True when DealerManagerPS is assigned, directly or through a permission set group.
     * @return Whether the running user has DealerManagerPS.
     */
    @AuraEnabled(cacheable=true)
    public static Boolean hasDealerQuoteAccess() {
        return ![
            SELECT Id
            FROM PermissionSetAssignment
            WHERE AssigneeId = :UserInfo.getUserId()
            AND PermissionSet.Name = :DEALER_MANAGER_PS_PERMISSION_SET
            LIMIT 1
        ].isEmpty();
    }
}