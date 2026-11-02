/**
* @author PWC Developer
* @date 2026/07/15
*
* @group Record Type Permission Set Assignment
*
* @description
* GC-3175 - LWC controller for Record Type Permission Set Assignment. Contains only UI-facing operations.
*/
@SuppressWarnings('PMD.UseSingleton')
public with sharing class RecordTypePsAssignmentController {
    
    public static final String SCENARIO = 'Record Type Permission Set Assignment';
    public static final String LOGGER_TAG = 'RecordTypePsAssignment';
    
    /**
* @description
* GC-3175 - Object option returned to the assignment LWC.
*/
    public class ObjectOptionWrapper {
        @AuraEnabled public String label;
        @AuraEnabled public String value;
    }
    
    /**
* @description
* GC-3175 - User search result returned to the assignment LWC.
*/
    public class UserWrapper {
        @AuraEnabled public Id userId;
        @AuraEnabled public String userName;
        @AuraEnabled public String email;
        @AuraEnabled public String profileName;
        @AuraEnabled public String role;
        @AuraEnabled public String title;
    }
    
    /**
* @description
* GC-3175 - Permission set option returned to the dual-listbox UI.
*/
    public class PermissionSetOptionWrapper {
        @AuraEnabled public Id permissionSetId;
        @AuraEnabled public String label;
        @AuraEnabled public String apiName;
    }
    
    /**
* @description
* GC-3175 - Permission set assignment view returned to the assignment LWC.
*/
    public class PermissionSetAssignmentViewResult {
        @AuraEnabled public List<PermissionSetOptionWrapper> permissionSetOptions;
        @AuraEnabled public List<Id> assignedPermissionSetIds;
    }
    
    /**
* @description
* GC-3175 - Returns supported object options for the assignment UI.
*
* @return Object options for the picklist.
*/
    @AuraEnabled(cacheable=true)
    public static List<ObjectOptionWrapper> getObjectOptions() {
        try {
            return RecordTypePsAssignmentService.getObjectOptions();
        } catch (Exception exceptionValue) {
            Logger.setScenario(SCENARIO);
            Logger.error(
                'Unable to retrieve object options. ' + exceptionValue.getMessage()
            ).addTag(LOGGER_TAG);
            
            throw new AuraHandledException('Unable to retrieve object options.');
        } finally {
            Logger.saveLog();
        }
    }
    
    /**
* @description
* GC-3175 - Searches active users for assignment selection.
*
* @param searchKey User-entered search text.
* @return Matching users.
*/
    @AuraEnabled
    public static List<UserWrapper> searchUsers(String searchKey) {
        try {
            return RecordTypePsAssignmentService.searchUsers(searchKey);
        } catch (Exception exceptionValue) {
            Logger.setScenario(SCENARIO);
            Logger.error(
                'Unable to search users. ' + exceptionValue.getMessage()
            ).addTag(LOGGER_TAG);
            
            throw new AuraHandledException('Unable to search users.');
        } finally {
            Logger.saveLog();
        }
    }
    
    /**
* @description
* GC-3175 - Returns permission set options and currently assigned ids for the selected user and object.
*
* @param objectApiName Selected object API name.
* @param userId Selected user id.
* @return Permission set assignment view data.
*/
    @AuraEnabled
    public static PermissionSetAssignmentViewResult getPermissionSetAssignments(String objectApiName, Id userId) {
        try {
            return RecordTypePsAssignmentService.getPermissionSetAssignments(objectApiName, userId);
        } catch (Exception exceptionValue) {
            Logger.setScenario(SCENARIO);
            Logger.error(
                'Unable to retrieve permission set assignments. ' +
                exceptionValue.getMessage()
            ).addTag(LOGGER_TAG);
            
            throw new AuraHandledException(
                'Unable to retrieve permission set assignments.'
            );
        } finally {
            Logger.saveLog();
        }
    }
    
    /**
* @description
* GC-3175 - Saves permission set assignments for the selected user and object.
*
* @param objectApiName Selected object API name.
* @param userId Selected user id.
* @param selectedPermissionSetIds Permission set ids selected in the UI.
*/
    @AuraEnabled
    public static void savePermissionSetAssignments(
        String objectApiName,
        Id userId,
        List<Id> selectedPermissionSetIds
    ) {
        try {
            RecordTypePsAssignmentService.savePermissionSetAssignments(
                objectApiName,
                userId,
                selectedPermissionSetIds
            );
        } catch (Exception exceptionValue) {
            Logger.setScenario(SCENARIO);
            Logger.error(
                'Unable to save permission set assignments. ' +
                exceptionValue.getMessage()
            ).addTag(LOGGER_TAG);
            throw new AuraHandledException(
                'Unable to save permission set assignments.'
            );
        } finally {
            Logger.saveLog();
        }
    }
}