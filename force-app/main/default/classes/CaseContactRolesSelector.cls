/**
 * @author PSL
 * @date 18-11-2026
 * @description Helper class for fetching records from caseContactRole Object.
 */
public with sharing class CaseContactRolesSelector {
/*
     * Used only by test class to cover exception block.
     */
    @TestVisible
    private static Boolean forceException = false;

    public static List<CaseContactRole> caseContactRecord(Id caseId) {

        try {

            /*
             * Runs only during unit testing.
             * Does not affect production execution.
             */
            if (Test.isRunningTest() && forceException) {
                throw new CaseContactRoleSelectorException(
                    'Forced exception for test coverage'
                );
            }

            List<CaseContactRole> csList = [
                SELECT Id,
                       Contact.FirstName,
                       ContactId,
                       Role
                FROM CaseContactRole
                WHERE Cases.Id = :caseId
                AND Role = 'Trade-in Contact'
            ];

            if (!csList.isEmpty()) {
                return csList;
            }

            return NULL;

        } catch (Exception ex) {

            ErrorLogger.logException(
                ex,
                'caseContactRolesSelector',
                'caseContactRecord'
            );

            throw ex;
        }
    }

    /*
     * Custom exception used for test coverage.
     */
    public class CaseContactRoleSelectorException extends Exception {
    }
}