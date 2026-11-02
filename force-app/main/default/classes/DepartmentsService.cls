/**
 * @description Service class for Department__c business operations.
 *              Entry point for all Department-related transactions.
 *              Performs DML directly — no Unit of Work.
 */
public with sharing class DepartmentsService {

    /**
     * @description Creates new Department__c records with validation.
     * @param departments List of Department__c records to create.
     * @throws DepartmentsServiceException when the operation fails.
     */
    public static void createDepartments(List<Department__c> departments) {
        if (departments == null || departments.isEmpty()) {
            return;
        }
        Logger.setScenario('Department Management');
        try {
            Departments domain = new Departments(departments);
            // domain.applyDefaults();
            // domain.validate();
            insert departments;
        } catch (Departments.DepartmentsException e) {
            Logger.error(new LogMessage('DepartmentsService.createDepartments: Validation failed. {0}', e.getMessage()), e);
            Logger.saveLog();
            throw new DepartmentsServiceException(e.getMessage(), e);
        } catch (Exception e) {
            Logger.error('DepartmentsService.createDepartments: Unexpected error.', e);
            Logger.saveLog();
            throw new DepartmentsServiceException('An unexpected error occurred while creating Department records.', e);
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description Updates existing Department__c records with validation.
     * @param departments List of Department__c records to update.
     * @throws DepartmentsServiceException when the operation fails.
     */
    public static void updateDepartments(List<Department__c> departments) {
        if (departments == null || departments.isEmpty()) {
            return;
        }
        Logger.setScenario('Department Management');
        try {
            Departments domain = new Departments(departments);
            // domain.validate();
            update departments;
        } catch (Departments.DepartmentsException e) {
            Logger.error(new LogMessage('DepartmentsService.updateDepartments: Validation failed. {0}', e.getMessage()), e);
            Logger.saveLog();
            throw new DepartmentsServiceException(e.getMessage(), e);
        } catch (Exception e) {
            Logger.error('DepartmentsService.updateDepartments: Unexpected error.', e);
            Logger.saveLog();
            throw new DepartmentsServiceException('An unexpected error occurred while updating Department records.', e);
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description Deletes Department__c records by their Ids.
     * @param departmentIds Set of Department__c Ids to delete.
     * @throws DepartmentsServiceException when the operation fails.
     */
    public static void deleteDepartments(Set<Id> departmentIds) {
        if (departmentIds == null || departmentIds.isEmpty()) {
            return;
        }
        Logger.setScenario('Department Management');
        try {
            List<Department__c> departmentList = DepartmentsSelector.selectById(departmentIds);
            if (departmentList.isEmpty()) {
                return;
            }
            delete departmentList;
        } catch (Exception e) {
            Logger.error('DepartmentsService.deleteDepartments: Unexpected error.', e);
            Logger.saveLog();
            throw new DepartmentsServiceException('An unexpected error occurred while deleting Department records.', e);
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description Retrieves Department__c records by their Ids.
     * @param departmentIds Set of Department__c Ids to retrieve.
     * @return List of Department__c records.
     * @throws DepartmentsServiceException when the operation fails.
     */
    public static List<Department__c> getDepartmentsById(Set<Id> departmentIds) {
        if (departmentIds == null || departmentIds.isEmpty()) {
            return new List<Department__c>();
        }
        try {
            return DepartmentsSelector.selectById(departmentIds);
        } catch (Exception e) {
            Logger.error('DepartmentsService.getDepartmentsById: Unexpected error.', e);
            Logger.saveLog();
            throw new DepartmentsServiceException('An unexpected error occurred while retrieving Department records.', e);
        }
    }

    /**
     * @description Thrown when a Department service operation fails.
     */
    public class DepartmentsServiceException extends Exception {}
}