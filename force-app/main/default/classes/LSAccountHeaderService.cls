/**
 * @author PWC Developer
 * @date 2026/10/30
 *
 * @group Life Sciences Account
 *
 * @description
 * GCL-100 - Decides Full or Base for the Life Sciences Customer record type.
 * Only the Customer record type is checked. Its owner and Account Team members get Full.
 * Anyone else on a Customer account gets the read-only Base panes.
 * Every other record type gets Full, so this check does not apply to it.
 * Field values stay on the UI API.
 */
public with sharing class LSAccountHeaderService {

    /**
     * @description GCL-100 - Access level for the owner, an Account Team member, and every non-Customer record type.
     */
    public static final String ACCESS_FULL = 'Full';

    /**
     * @description GCL-100 - Access level when the user is neither the Customer owner nor on the Account Team.
     */
    public static final String ACCESS_BASE = 'Base';

    /**
     * @description GCL-100 - Account record type developer name that uses the Full or Base check.
     */
    public static final String CUSTOMER_RECORD_TYPE = 'Customer';

    /**
     * @description GCL-100 - Test-only switch that forces a query failure so the controller error path can be covered.
     */
    @TestVisible
    private static Boolean throwTestException = false;

    /**
     * @description
     * GCL-100 - Access decision returned to the Life Sciences Customer 360 panes.
     * showHeaderOnly remains so the earlier header component still understands the response.
     */
    public class HeaderView {
        /**
         * @description GCL-100 - Full or Base. The Lightning component uses this to choose the pane.
         */
        @AuraEnabled public String accessLevel;

        /**
         * @description GCL-100 - True only for Base, so the earlier header component still understands the response.
         */
        @AuraEnabled public Boolean showHeaderOnly;
    }

    /**
     * @description
     * GCL-100 - Returns Full or Base for the Account. Field values are not included.
     * Contacts, Opportunities, Activities, Notes, and Emails are not queried.
     *
     * @param accountId Account opened by the running user.
     * @return Full for a non-Customer, the Customer owner, and a Customer Account Team member. Base otherwise.
     *
     * @example
     * LSAccountHeaderService.getHeaderView(accountId);
     */
    public static HeaderView getHeaderView(Id accountId) {
        if (accountId == null) {
            throw new LSAccountHeaderException('Account Id is required.');
        }

        if (Test.isRunningTest() && throwTestException) {
            throw new QueryException('Forced test exception');
        }

        List<Account> accounts = AccountSelector.selectById(accountId);
        if (accounts.isEmpty()) {
            throw new LSAccountHeaderException('You do not have access to this account.');
        }

        HeaderView headerView = new HeaderView();
        if (!isCustomerRecordType(accounts[0])) {
            headerView.accessLevel = ACCESS_FULL;
            headerView.showHeaderOnly = false;
        } else {
            Boolean isOwner = accounts[0].OwnerId == UserInfo.getUserId();
            Boolean isTeamMember =
                !AccountTeamMemberSelector.selectCurrentUserTeamMember(accountId).isEmpty();
            headerView.accessLevel = (isOwner || isTeamMember) ? ACCESS_FULL : ACCESS_BASE;
            headerView.showHeaderOnly = headerView.accessLevel == ACCESS_BASE;
        }

        Logger.info(
            'LSAccountHeaderService.getHeaderView accessLevel=' +
            headerView.accessLevel +
            ' accountId=' +
            accountId
        );
        return headerView;
    }

    /**
     * @description
     * GCL-100 - True when the Account uses the Customer record type.
     *
     * @param accountRecord Account row returned by the selector.
     * @return True for the Customer record type. False for every other record type.
     *
     * @example
     * isCustomerRecordType(accounts[0]);
     */
    private static Boolean isCustomerRecordType(Account accountRecord) {
        return accountRecord.RecordType != null
            && accountRecord.RecordType.DeveloperName == CUSTOMER_RECORD_TYPE;
    }
}