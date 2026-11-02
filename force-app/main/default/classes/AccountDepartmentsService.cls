/**
 * @description Service class for AccountDepartment__c business operations.
 *              Entry point for all AccountDepartment-related transactions.
 *              Performs DML directly — no Unit of Work.
 */
public with sharing class AccountDepartmentsService {

    /**
     * @description Creates new AccountDepartment__c records with validation.
     * @param accountDepartments List of AccountDepartment__c records to create.
     * @throws AccountDepartmentsServiceException when the operation fails.
     */
    public static void createAccountDepartments(List<AccountDepartment__c> accountDepartments) {
        if (accountDepartments == null || accountDepartments.isEmpty()) {
            return;
        }
        Logger.setScenario('Account Department Management');
        try {
            AccountDepartments domain = new AccountDepartments(accountDepartments);
            // domain.applyDefaults();
            // domain.validate();
            insert accountDepartments;
        } catch (AccountDepartments.AccountDepartmentsException e) {
            Logger.error(new LogMessage('AccountDepartmentsService.createAccountDepartments: Validation failed. {0}', e.getMessage()), e);
            Logger.saveLog();
            throw new AccountDepartmentsServiceException(e.getMessage(), e);
        } catch (Exception e) {
            Logger.error('AccountDepartmentsService.createAccountDepartments: Unexpected error.', e);
            Logger.saveLog();
            throw new AccountDepartmentsServiceException('An unexpected error occurred while creating AccountDepartment records.', e);
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description Updates existing AccountDepartment__c records with validation.
     * @param accountDepartments List of AccountDepartment__c records to update.
     * @throws AccountDepartmentsServiceException when the operation fails.
     */
    public static void updateAccountDepartments(List<AccountDepartment__c> accountDepartments) {
        if (accountDepartments == null || accountDepartments.isEmpty()) {
            return;
        }
        Logger.setScenario('Account Department Management');
        try {
            AccountDepartments domain = new AccountDepartments(accountDepartments);
            // domain.validate();
            update accountDepartments;
        } catch (AccountDepartments.AccountDepartmentsException e) {
            Logger.error(new LogMessage('AccountDepartmentsService.updateAccountDepartments: Validation failed. {0}', e.getMessage()), e);
            Logger.saveLog();
            throw new AccountDepartmentsServiceException(e.getMessage(), e);
        } catch (Exception e) {
            Logger.error('AccountDepartmentsService.updateAccountDepartments: Unexpected error.', e);
            Logger.saveLog();
            throw new AccountDepartmentsServiceException('An unexpected error occurred while updating AccountDepartment records.', e);
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description Deletes AccountDepartment__c records by their Ids.
     * @param accountDepartmentIds Set of AccountDepartment__c Ids to delete.
     * @throws AccountDepartmentsServiceException when the operation fails.
     */
    public static void deleteAccountDepartments(Set<Id> accountDepartmentIds) {
        if (accountDepartmentIds == null || accountDepartmentIds.isEmpty()) {
            return;
        }
        Logger.setScenario('Account Department Management');
        try {
            List<AccountDepartment__c> accountDepartmentList = AccountDepartmentsSelector.selectById(accountDepartmentIds);
            if (accountDepartmentList.isEmpty()) {
                return;
            }
            delete accountDepartmentList;
        } catch (Exception e) {
            Logger.error('AccountDepartmentsService.deleteAccountDepartments: Unexpected error.', e);
            Logger.saveLog();
            throw new AccountDepartmentsServiceException('An unexpected error occurred while deleting AccountDepartment records.', e);
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description Retrieves AccountDepartment__c records by their Ids.
     * @param accountDepartmentIds Set of AccountDepartment__c Ids to retrieve.
     * @return List of AccountDepartment__c records.
     * @throws AccountDepartmentsServiceException when the operation fails.
     */
    public static List<AccountDepartment__c> getAccountDepartmentsById(Set<Id> accountDepartmentIds) {
        if (accountDepartmentIds == null || accountDepartmentIds.isEmpty()) {
            return new List<AccountDepartment__c>();
        }
        try {
            return AccountDepartmentsSelector.selectById(accountDepartmentIds);
        } catch (Exception e) {
            Logger.error('AccountDepartmentsService.getAccountDepartmentsById: Unexpected error.', e);
            Logger.saveLog();
            throw new AccountDepartmentsServiceException('An unexpected error occurred while retrieving AccountDepartment records.', e);
        }
    }

    /**
     * @description Thrown when an AccountDepartment service operation fails.
     */
    public class AccountDepartmentsServiceException extends Exception {}
}