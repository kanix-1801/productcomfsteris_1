/**
 * @description Life Sciences Coverage Panel controller.
 * author PWC Developer
 * @date 2026/09/23
 *
 *  GCL-2 AC1: Apex entry point for the lsAccountTeamMemberDetails LWC.
 *  Returns every Account Team Member on the Account, covering both the
 *  TAS-assigned core territory reps and the Salesforce-managed overlay users
 *  (GAD, APM, Inside Sales).
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

            return accountTeamMemberDTOList;

        } catch (Exception exceptionRecord) {
            AuraHandledException auraException =
                new AuraHandledException(exceptionRecord.getMessage());
            auraException.setMessage(exceptionRecord.getMessage());
            throw auraException;
        }
    }
}