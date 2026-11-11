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

    public static final String ACCESS_FULL = 'Full';
    public static final String ACCESS_BASE = 'Base';
    public static final String CUSTOMER_RECORD_TYPE = 'Customer';

    @TestVisible
    private static Boolean throwTestException = false;

    /**
     * @description
     * GCL-100 - Access decision returned to the Life Sciences Customer 360 panes.
     * showHeaderOnly remains so the earlier header component still understands the response.
     */
    public class HeaderView {
        @AuraEnabled public String accessLevel;
        @AuraEnabled public Boolean showHeaderOnly;
    }

    /**
     * @description
     * GCL-100 - Returns Full or Base for the Account. Field values are not included.
     * Contacts, Opportunities, Activities, Notes, and Emails are not queried.
     *
     * @param accountId Account opened by the running user.
     * @return Full for a non-Customer record type, the Customer owner, and a Customer Account Team member. Base otherwise.
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

        List<Account> accounts = LSAccountHeaderSelector.selectById(accountId);
        if (accounts.isEmpty()) {
            throw new LSAccountHeaderException('You do not have access to this account.');
        }

        HeaderView headerView = new HeaderView();
        if (!isCustomerRecordType(accounts[0])) {
            headerView.accessLevel = ACCESS_FULL;
            headerView.showHeaderOnly = false;
            return headerView;
        }

        Boolean isOwner = accounts[0].OwnerId == UserInfo.getUserId();
        Boolean isTeamMember =
            !LSAccountHeaderSelector.selectCurrentUserTeamMember(accountId).isEmpty();

        headerView.accessLevel = (isOwner || isTeamMember) ? ACCESS_FULL : ACCESS_BASE;
        headerView.showHeaderOnly = headerView.accessLevel == ACCESS_BASE;
        return headerView;
    }

    private static Boolean isCustomerRecordType(Account accountRecord) {
        return accountRecord.RecordType != null
            && accountRecord.RecordType.DeveloperName == CUSTOMER_RECORD_TYPE;
    }
}