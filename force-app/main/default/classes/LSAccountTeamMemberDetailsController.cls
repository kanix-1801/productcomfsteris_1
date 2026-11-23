/**
 * @description Life Sciences Coverage Panel controller.
 * author PWC Developer
 * @date 2026/09/23
 *
 *  GCL-2 AC1: Apex entry point for the lsAccountTeamMemberDetails LWC.
 *  Returns every Account Team Member on the Account, covering both the
 *  TAS-assigned core territory reps and the Salesforce-managed overlay users
 *  (GAD, APM, Inside Sales).
 *  GCL-117: For Life Sciences (class code SC) only, also shows the Account
 *  Owner as a display row. Healthcare accounts and existing team rows are
 *  returned unchanged. No Account Team Member record is created or deleted.
 */
public with sharing class LSAccountTeamMemberDetailsController {

    @TestVisible
    private static Boolean throwTestException = false;

    /**
     * @description Loads the Life Sciences Coverage Panel rows for an Account.
     * @param accountId Account Id from the record page.
     * @return Account Team Member details shaped for the Life Sciences panel.
     * @throws AuraHandledException when the query fails.
     */
    @AuraEnabled
    public static List<AccountTeamMemberDTO> getLifeSciencesAccountTeamMembers(Id accountId) {
        List<AccountTeamMemberDTO> accountTeamMemberDTOList = new List<AccountTeamMemberDTO>();

        if (accountId == null) {
            return accountTeamMemberDTOList;
        }

        try {
            if (throwTestException) {
                throw new QueryException('Unable to load Account Team Member details.');
            }

            for (AccountTeamMember accountTeamMember :
                    AccountTeamMemberSelector.selectByAccountIdForLifeSciences(accountId)) {

                accountTeamMemberDTOList.add(
                    AccountTeamMemberDTO.fromLifeSciencesAccountTeamMember(accountTeamMember)
                );
            }

            return includeAccountOwnerRow(
                accountTeamMemberDTOList,
                AccountTeamMemberSelector.selectOwnerForCoveragePanel(accountId)
            );

        } catch (Exception exceptionRecord) {
            AuraHandledException auraException =
                new AuraHandledException(exceptionRecord.getMessage());
            auraException.setMessage(exceptionRecord.getMessage());
            throw auraException;
        }
    }

    /**
     * @description GCL-117 - Adds a display-only Account Owner row for Life
     *              Sciences accounts. Healthcare is returned unchanged. Existing
     *              team rows are not replaced.
     * @param rows Coverage panel rows already loaded from Account Team.
     * @param accountRecord Account owner and class code.
     * @return Rows with the Account Owner first when the account is Life Sciences.
     */
    private static List<AccountTeamMemberDTO> includeAccountOwnerRow(
        List<AccountTeamMemberDTO> rows,
        Account accountRecord
    ) {
        if (accountRecord == null
            || accountRecord.OwnerId == null
            || !LSAccountService.isLifeSciencesAccount(accountRecord)) {
            return rows;
        }

        List<AccountTeamMemberDTO> orderedRows = new List<AccountTeamMemberDTO>();
        Boolean ownerRowFound = false;

        for (AccountTeamMemberDTO row : rows) {
            if (row.userId == accountRecord.OwnerId
                && row.teamRole == AccountTeamMemberDTO.LIFE_SCIENCES_OWNER_ROLE) {
                orderedRows.add(row);
                ownerRowFound = true;
            }
        }

        if (!ownerRowFound) {
            orderedRows.add(AccountTeamMemberDTO.fromAccountOwner(accountRecord));
        }

        for (AccountTeamMemberDTO row : rows) {
            if (!(row.userId == accountRecord.OwnerId
                && row.teamRole == AccountTeamMemberDTO.LIFE_SCIENCES_OWNER_ROLE)) {
                orderedRows.add(row);
            }
        }

        return orderedRows;
    }
}