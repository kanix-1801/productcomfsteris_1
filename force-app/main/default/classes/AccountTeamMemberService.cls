/**
 * @author Divya Sree
 * @date 2026/05/25
 *
 * @group Account Management
 *
 * @description
 * Service layer that orchestrates retrieval of Account Team Member details.
 * Delegates data access to AccountTeamMemberSelector, transforms results into
 * AccountTeamMemberDTO instances, and handles error logging via the Logger
 * framework before surfacing a user-friendly exception to callers.
 */
public with sharing class AccountTeamMemberService {
    /** @description Logger scenario tag used when persisting error logs. */
    private static final String SCENARIO = 'Account Management';

    /** @description Generic message shown to users when retrieval fails. */
    private static final String USER_ERROR_MESSAGE = 'Unable to load Account Team Member details.';

    /**
     * @description
     * Test-only flag that forces an exception path so unit tests can verify
     * error handling without relying on invalid data or governor limits.
     */
    @TestVisible
    private static Boolean throwExceptionForTest = false;

    /**
     * @description
     * Fetches Account Team Members for the specified Account and returns them
     * as DTOs ready for Lightning component display. Returns an empty list when
     * accountId is null. On failure, logs the error and throws
     * AccountTeamMemberException with a sanitized user-facing message.
     *
     * @param accountId Salesforce Id of the Account whose team members to load.
     * @return List of AccountTeamMemberDTO objects; empty when accountId is null.
     */
    public static List<AccountTeamMemberDTO> getAccountTeamMemberDetails(Id accountId, Boolean canViewAccessFields) {
        List<AccountTeamMemberDTO> accountTeamMemberDTOList = new List<AccountTeamMemberDTO>();
        Boolean shouldSaveLog = false;

        if (accountId == null) {
            return accountTeamMemberDTOList;
        }

        try {
            if (throwExceptionForTest) {
                throw new QueryException('Forced exception for unit test.');
            }

            List<AccountTeamMember> accountTeamMemberList =
                AccountTeamMemberSelector.selectByAccountId(accountId, canViewAccessFields);

            for (AccountTeamMember accountTeamMember : accountTeamMemberList) {
                accountTeamMemberDTOList.add(new AccountTeamMemberDTO(accountTeamMember, canViewAccessFields));
            }
        } catch (Exception exceptionRecord) {
            shouldSaveLog = true;

            Logger.setScenario(SCENARIO);
            Logger.error(
                'Unable to retrieve Account Team Member details. Error: ' +
                exceptionRecord.getMessage()
            )
                .addTag('Account')
                .addTag('Account Team Member')
                .setRecord(new Account(Id = accountId));

            throw new AccountTeamMemberException(USER_ERROR_MESSAGE);
        } finally {
            if (shouldSaveLog) {
                Logger.saveLog();
            }
        }

        return accountTeamMemberDTOList;
    }

    /**
     * @description
     * Custom exception thrown by this service when team member retrieval fails.
     * Carries a user-safe message; technical details are captured in Logger.
     */
    public class AccountTeamMemberException extends Exception {
    }
}