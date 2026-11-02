/**
 * @author PWC Developer
 * @date 2026/10/30
 *
 * @group Life Sciences Account
 *
 * @description
 * GCL-100 - Decides whether the running user sees the out-of-territory Account header.
 * The Account owner and Account Team members keep the standard Life Sciences page.
 * Header field values are loaded by the Lightning component through the UI API.
 */
public with sharing class LSAccountHeaderService {

    @TestVisible
    private static Boolean throwTestException = false;

    /**
     * @description
     * GCL-100 - Access decision returned to the Life Sciences header component.
     */
    public class HeaderView {
        @AuraEnabled public Boolean showHeaderOnly;
    }

    /**
     * @description
     * GCL-100 - Returns the header decision for the Account. Field values are not
     * included. Contacts, Opportunities, Activities, Notes, and Emails are not queried.
     *
     * @param accountId Account opened by the running user.
     * @return Header decision. showHeaderOnly is false for the owner and for team members.
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
        headerView.showHeaderOnly = !isOwnerOrTeamMember(accounts[0]);
        return headerView;
    }

    /**
     * @description
     * GCL-100 - Full page access stays with the owner and with anyone already on the
     * Account Team.
     *
     * @param accountRecord Account row returned by the selector.
     * @return TRUE when the running user should keep the standard record page.
     */
    private static Boolean isOwnerOrTeamMember(Account accountRecord) {
        if (accountRecord.OwnerId == UserInfo.getUserId()) {
            return true;
        }

        return !LSAccountHeaderSelector.selectCurrentUserTeamMember(accountRecord.Id).isEmpty();
    }
}