/**
 * @author PWC Developer
 * @date 2026/10/30
 *
 * @group Life Sciences Account
 *
 * @description
 * GCL-100 - SOQL selector for the out-of-territory Account header.
 * Record visibility is enforced by sharing. The header fields themselves are read
 * by the Lightning UI API, so this selector does not query them.
 */
public with sharing class LSAccountHeaderSelector {

    /**
     * @description
     * GCL-100 - Returns the Account owner row used to decide whether the running
     * user keeps the standard Life Sciences page.
     *
     * @param accountId Account record Id from the record page.
     * @return The Account row, or an empty list when the Id is missing or not visible.
     *
     * @example
     * LSAccountHeaderSelector.selectById(accountId);
     */
    public static List<Account> selectById(Id accountId) {
        if (accountId == null) {
            return new List<Account>();
        }

        return [
            SELECT Id, OwnerId
            FROM Account
            WHERE Id = :accountId
            LIMIT 1
        ];
    }

    /**
     * @description
     * GCL-100 - Returns the running user's Account Team row for the Account.
     * Life Sciences territory coverage is assigned through the Account Team.
     *
     * @param accountId Account record Id from the record page.
     * @return The current user's team row, or an empty list when they are not a member.
     *
     * @example
     * LSAccountHeaderSelector.selectCurrentUserTeamMember(accountId);
     */
    public static List<AccountTeamMember> selectCurrentUserTeamMember(Id accountId) {
        if (accountId == null) {
            return new List<AccountTeamMember>();
        }

        return [
            SELECT Id
            FROM AccountTeamMember
            WHERE AccountId = :accountId
            AND UserId = :UserInfo.getUserId()
            LIMIT 1
        ];
    }
}