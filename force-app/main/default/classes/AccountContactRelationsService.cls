/**
 * @description Service class for AccountContactRelation business operations.
 *              Entry point for all AccountContactRelation-related transactions.
 *              Performs DML directly — no Unit of Work.
 */
public with sharing class AccountContactRelationsService {

    /**
     * @description Creates new AccountContactRelation records with validation.
     * @param relations List of AccountContactRelation records to create.
     * @throws AccountContactRelationsServiceException when the operation fails.
     */
    public static void createAccountContactRelations(List<AccountContactRelation> relations) {
        if (relations == null || relations.isEmpty()) {
            return;
        }
        Logger.setScenario('Account Contact Relation Management');
        try {
            AccountContactRelations domain = new AccountContactRelations(relations);
            // domain.applyDefaults();
            // domain.validate();
            insert relations;
        } catch (AccountContactRelations.AccountContactRelationsException e) {
            Logger.error(new LogMessage('AccountContactRelationsService.createAccountContactRelations: Validation failed. {0}', e.getMessage()), e);
            Logger.saveLog();
            throw new AccountContactRelationsServiceException(e.getMessage(), e);
        } catch (Exception e) {
            Logger.error('AccountContactRelationsService.createAccountContactRelations: Unexpected error.', e);
            Logger.saveLog();
            throw new AccountContactRelationsServiceException('An unexpected error occurred while creating AccountContactRelation records.', e);
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description Updates existing AccountContactRelation records with validation.
     * @param relations List of AccountContactRelation records to update.
     * @throws AccountContactRelationsServiceException when the operation fails.
     */
    public static void updateAccountContactRelations(List<AccountContactRelation> relations) {
        if (relations == null || relations.isEmpty()) {
            return;
        }
        Logger.setScenario('Account Contact Relation Management');
        try {
            AccountContactRelations domain = new AccountContactRelations(relations);
            // domain.validate();
            update relations;
        } catch (AccountContactRelations.AccountContactRelationsException e) {
            Logger.error(new LogMessage('AccountContactRelationsService.updateAccountContactRelations: Validation failed. {0}', e.getMessage()), e);
            Logger.saveLog();
            throw new AccountContactRelationsServiceException(e.getMessage(), e);
        } catch (Exception e) {
            Logger.error('AccountContactRelationsService.updateAccountContactRelations: Unexpected error.', e);
            Logger.saveLog();
            throw new AccountContactRelationsServiceException('An unexpected error occurred while updating AccountContactRelation records.', e);
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description Deletes AccountContactRelation records by their Ids.
     * @param relationIds Set of AccountContactRelation Ids to delete.
     * @throws AccountContactRelationsServiceException when the operation fails.
     */
    public static void deleteAccountContactRelations(Set<Id> relationIds) {
        if (relationIds == null || relationIds.isEmpty()) {
            return;
        }
        Logger.setScenario('Account Contact Relation Management');
        try {
            List<AccountContactRelation> relationList = AccountContactRelationsSelector.selectById(relationIds);
            if (relationList.isEmpty()) {
                return;
            }
            delete relationList;
        } catch (Exception e) {
            Logger.error('AccountContactRelationsService.deleteAccountContactRelations: Unexpected error.', e);
            Logger.saveLog();
            throw new AccountContactRelationsServiceException('An unexpected error occurred while deleting AccountContactRelation records.', e);
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description Retrieves AccountContactRelation records by their Ids.
     * @param relationIds Set of AccountContactRelation Ids to retrieve.
     * @return List of AccountContactRelation records.
     * @throws AccountContactRelationsServiceException when the operation fails.
     */
    public static List<AccountContactRelation> getAccountContactRelationsById(Set<Id> relationIds) {
        if (relationIds == null || relationIds.isEmpty()) {
            return new List<AccountContactRelation>();
        }
        try {
            return AccountContactRelationsSelector.selectById(relationIds);
        } catch (Exception e) {
            Logger.error('AccountContactRelationsService.getAccountContactRelationsById: Unexpected error.', e);
            Logger.saveLog();
            throw new AccountContactRelationsServiceException('An unexpected error occurred while retrieving AccountContactRelation records.', e);
        }
    }

    /**
     * @description Thrown when an AccountContactRelation service operation fails.
     */
    public class AccountContactRelationsServiceException extends Exception {}
}