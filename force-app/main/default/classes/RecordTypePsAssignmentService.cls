/**
 * @author PWC Developer
 * @date 2026/07/15
 *
 * @group Record Type Permission Set Assignment
 *
 * @description
 * GC-3175 - Business logic for Sales Ops record type permission set assignment.
 */
public without sharing class RecordTypePsAssignmentService {

    public static final String SCENARIO = 'Record Type Permission Set Assignment';
    public static final String LOGGER_TAG = 'RecordTypePsAssignment';

    @TestVisible
    private static Boolean isThrowTestException = false;

    @TestVisible
    private static String forcedExceptionMethodName;

    private class RecordTypePermissionSetDefinition {
        public String permissionSetApiNameParam;
        public String recordTypeLabelParam;

        public RecordTypePermissionSetDefinition(String permissionSetApiName, String recordTypeLabel) {
            this.permissionSetApiNameParam = permissionSetApiName;
            this.recordTypeLabelParam = recordTypeLabel;
        }
    }

    /**
     * @description
     * GC-3175 - Returns supported object options for the assignment UI.
     *
     * @return Object options for the picklist.
     */
    public static List<RecordTypePsAssignmentController.ObjectOptionWrapper> getObjectOptions() {
        try {
            throwForcedTestExceptionIfRequested('getObjectOptions');

            List<Record_Type_Permission_Set_Mapping__mdt> mappingList =
                RecordTypePermissionSetMappingSelector.selectActiveMappings();
            Set<String> objectApiNameSet = new Set<String>();

            for (Record_Type_Permission_Set_Mapping__mdt mappingRecord : mappingList) {
                if (String.isNotBlank(mappingRecord.Object_API_Name__c)) {
                    objectApiNameSet.add(mappingRecord.Object_API_Name__c);
                }
            }

            List<RecordTypePsAssignmentController.ObjectOptionWrapper> objectOptionList =
                new List<RecordTypePsAssignmentController.ObjectOptionWrapper>();

            for (String objectApiName : objectApiNameSet) {
                RecordTypePsAssignmentController.ObjectOptionWrapper objectOption =
                    new RecordTypePsAssignmentController.ObjectOptionWrapper();
                objectOption.value = objectApiName;
                objectOption.label = objectApiName;
                objectOptionList.add(objectOption);
            }

            objectOptionList.sort(new ObjectOptionComparator());
            return objectOptionList;
        } catch (Exception exceptionValue) {
            Logger.error('Error retrieving object options', exceptionValue);
            throw new RecordTypePsAssignmentException('Unable to retrieve object options.');
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
    public static List<RecordTypePsAssignmentController.UserWrapper> searchUsers(String searchKey) {
        try {
            throwForcedTestExceptionIfRequested('searchUsers');

            if (isThrowTestException) {
                throw new QueryException('Forced test exception');
            }

            List<User> userList = UserSelector.selectActiveHealthcareSalesUsersBySearch(searchKey);
            List<RecordTypePsAssignmentController.UserWrapper> userWrapperList =
                new List<RecordTypePsAssignmentController.UserWrapper>();

            if (userList == null || userList.isEmpty()) {
                Logger.warn('RecordTypePsAssignmentService.searchUsers: userList is null or empty');
                return userWrapperList;
            }

            for (User userRecord : userList) {
                RecordTypePsAssignmentController.UserWrapper userWrapper =
                    new RecordTypePsAssignmentController.UserWrapper();
                userWrapper.userId = userRecord.Id;
                userWrapper.userName = userRecord.Name;
                userWrapper.profileName = userRecord.Profile.Name;
                userWrapper.email = userRecord.Email;
                userWrapper.role = userRecord.UserRole == null ? null : userRecord.UserRole.Name;
                userWrapper.title = userRecord.Title;
                userWrapperList.add(userWrapper);
            }

            return userWrapperList;
        } catch (Exception exceptionValue) {
            Logger.error('Error searching users', exceptionValue);
            throw new RecordTypePsAssignmentException('Unable to search users.');
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
    public static RecordTypePsAssignmentController.PermissionSetAssignmentViewResult getPermissionSetAssignments(
        String objectApiName,
        Id userId
    ) {
        try {
            throwForcedTestExceptionIfRequested('getPermissionSetAssignments');
            validateObjectApiName(objectApiName);
            validateUserId(userId);

            Map<String, RecordTypePermissionSetDefinition> definitionByApiNameMap =
                getDefinitionByApiNameMap(objectApiName);
            List<PermissionSet> permissionSetList = PermissionSetSelector.selectByNames(definitionByApiNameMap.keySet());
            Map<Id, PermissionSet> permissionSetByIdMap = new Map<Id, PermissionSet>(permissionSetList);

            Set<Id> permissionSetIdSet = permissionSetByIdMap.keySet();
            List<PermissionSetAssignment> assignmentList = PermissionSetSelector.selectAssignmentsByUserAndPermissionSetIds(
                userId,
                permissionSetIdSet
            );

            Set<Id> assignedPermissionSetIdSet = new Set<Id>();
            for (PermissionSetAssignment assignmentRecord : assignmentList) {
                assignedPermissionSetIdSet.add(assignmentRecord.PermissionSetId);
            }

            RecordTypePsAssignmentController.PermissionSetAssignmentViewResult result =
                new RecordTypePsAssignmentController.PermissionSetAssignmentViewResult();
            result.permissionSetOptions = buildPermissionSetOptions(permissionSetList, definitionByApiNameMap);
            result.assignedPermissionSetIds = new List<Id>(assignedPermissionSetIdSet);
            return result;
        } catch (Exception exceptionValue) {
            Logger.error('Error retrieving permission set assignments', exceptionValue);
            throw new RecordTypePsAssignmentException('Unable to retrieve permission set assignments.');
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
    public static void savePermissionSetAssignments(
        String objectApiName,
        Id userId,
        List<Id> selectedPermissionSetIds
    ) {
        Savepoint savepointValue = Database.setSavepoint();

        try {
            throwForcedTestExceptionIfRequested('savePermissionSetAssignments');
            validateObjectApiName(objectApiName);
            validateUserId(userId);

            Set<Id> selectedPermissionSetIdSet = buildIdSet(selectedPermissionSetIds);
            Map<String, RecordTypePermissionSetDefinition> definitionByApiNameMap =
                getDefinitionByApiNameMap(objectApiName);
            List<PermissionSet> permissionSetList = PermissionSetSelector.selectByNames(definitionByApiNameMap.keySet());
            Map<Id, PermissionSet> permissionSetByIdMap = new Map<Id, PermissionSet>(permissionSetList);
            Set<Id> allowedPermissionSetIdSet = permissionSetByIdMap.keySet();

            validateSelectedPermissionSetIds(selectedPermissionSetIdSet, allowedPermissionSetIdSet);

            List<PermissionSetAssignment> existingAssignmentList =
                PermissionSetSelector.selectAssignmentsByUserAndPermissionSetIds(userId, allowedPermissionSetIdSet);

            Set<Id> existingPermissionSetIdSet = new Set<Id>();
            Map<Id, PermissionSetAssignment> assignmentByPermissionSetIdMap =
                new Map<Id, PermissionSetAssignment>();

            for (PermissionSetAssignment assignmentRecord : existingAssignmentList) {
                existingPermissionSetIdSet.add(assignmentRecord.PermissionSetId);
                assignmentByPermissionSetIdMap.put(assignmentRecord.PermissionSetId, assignmentRecord);
            }

            Set<Id> permissionSetIdsToAssign = new Set<Id>(selectedPermissionSetIdSet);
            permissionSetIdsToAssign.removeAll(existingPermissionSetIdSet);

            Set<Id> permissionSetIdsToRemove = new Set<Id>(existingPermissionSetIdSet);
            permissionSetIdsToRemove.removeAll(selectedPermissionSetIdSet);

            insertPermissionSetAssignments(userId, permissionSetIdsToAssign);
            deletePermissionSetAssignments(assignmentByPermissionSetIdMap, permissionSetIdsToRemove);

            Logger.setScenario(SCENARIO);
            Logger.info('Record type permission set assignments saved successfully for user ' + userId)
                .addTag(LOGGER_TAG);
        } catch (Exception exceptionValue) {
            Database.rollback(savepointValue);
            Logger.setScenario(SCENARIO);
            Logger.error('Record type permission set assignment save failed. ' + exceptionValue.getMessage())
                .addTag(LOGGER_TAG);
            throw exceptionValue;
        } finally {
            Logger.saveLog();
        }
    }

    private static List<RecordTypePsAssignmentController.PermissionSetOptionWrapper> buildPermissionSetOptions(
        List<PermissionSet> permissionSetList,
        Map<String, RecordTypePermissionSetDefinition> definitionByApiNameMap
    ) {
        List<RecordTypePsAssignmentController.PermissionSetOptionWrapper> permissionSetOptionList =
            new List<RecordTypePsAssignmentController.PermissionSetOptionWrapper>();

        for (PermissionSet permissionSetRecord : permissionSetList) {
            RecordTypePermissionSetDefinition definitionRecord = definitionByApiNameMap.get(permissionSetRecord.Name);

            RecordTypePsAssignmentController.PermissionSetOptionWrapper permissionSetOption =
                new RecordTypePsAssignmentController.PermissionSetOptionWrapper();
            permissionSetOption.permissionSetId = permissionSetRecord.Id;
            permissionSetOption.apiName = permissionSetRecord.Name;
            permissionSetOption.label = definitionRecord == null
                ? permissionSetRecord.Label
                : definitionRecord.recordTypeLabelParam;
            permissionSetOptionList.add(permissionSetOption);
        }

        permissionSetOptionList.sort(new PermissionSetOptionComparator());
        return permissionSetOptionList;
    }

    private static Map<String, RecordTypePermissionSetDefinition> getDefinitionByApiNameMap(String objectApiName) {
        List<Record_Type_Permission_Set_Mapping__mdt> mappingList =
            RecordTypePermissionSetMappingSelector.selectActiveMappingsByObject(objectApiName);
        Set<String> recordTypeDeveloperNameSet = new Set<String>();

        for (Record_Type_Permission_Set_Mapping__mdt mappingRecord : mappingList) {
            if (String.isNotBlank(mappingRecord.Record_Type_Developer_Name__c)) {
                recordTypeDeveloperNameSet.add(mappingRecord.Record_Type_Developer_Name__c);
            }
        }

        Map<String, String> recordTypeLabelByDeveloperNameMap =
            getRecordTypeLabelByDeveloperNameMap(objectApiName, recordTypeDeveloperNameSet);
        Map<String, RecordTypePermissionSetDefinition> definitionByApiNameMap =
            new Map<String, RecordTypePermissionSetDefinition>();

        for (Record_Type_Permission_Set_Mapping__mdt mappingRecord : mappingList) {
            if (String.isBlank(mappingRecord.Permission_Set_API_Name__c)) {
                continue;
            }

            String recordTypeLabel = recordTypeLabelByDeveloperNameMap.get(
                mappingRecord.Record_Type_Developer_Name__c
            );

            if (String.isBlank(recordTypeLabel)) {
                recordTypeLabel = mappingRecord.MasterLabel;
            }

            definitionByApiNameMap.put(
                mappingRecord.Permission_Set_API_Name__c,
                new RecordTypePermissionSetDefinition(
                    mappingRecord.Permission_Set_API_Name__c,
                    recordTypeLabel
                )
            );
        }

        return definitionByApiNameMap;
    }

    private static Map<String, String> getRecordTypeLabelByDeveloperNameMap(
        String objectApiName,
        Set<String> recordTypeDeveloperNameSet
    ) {
        Map<String, String> recordTypeLabelByDeveloperNameMap = new Map<String, String>();

        if (String.isBlank(objectApiName) || recordTypeDeveloperNameSet == null || recordTypeDeveloperNameSet.isEmpty()) {
            return recordTypeLabelByDeveloperNameMap;
        }

        for (RecordType recordTypeRecord : [
            SELECT Name, DeveloperName
            FROM RecordType
            WHERE SobjectType = :objectApiName
            AND DeveloperName IN :recordTypeDeveloperNameSet
            AND IsActive = TRUE
        ]) {
            recordTypeLabelByDeveloperNameMap.put(recordTypeRecord.DeveloperName, recordTypeRecord.Name);
        }

        return recordTypeLabelByDeveloperNameMap;
    }

    private static void validateObjectApiName(String objectApiName) {
        if (
            String.isBlank(objectApiName) ||
            RecordTypePermissionSetMappingSelector.selectActiveMappingsByObject(objectApiName).isEmpty()
        ) {
            throw new AuraHandledException('Please select a valid object.');
        }
    }

    private static void validateUserId(Id userId) {
        if (userId == null) {
            throw new AuraHandledException('Please select a user.');
        }
    }

    private static void validateSelectedPermissionSetIds(
        Set<Id> selectedPermissionSetIdSet,
        Set<Id> allowedPermissionSetIdSet
    ) {
        for (Id permissionSetId : selectedPermissionSetIdSet) {
            if (!allowedPermissionSetIdSet.contains(permissionSetId)) {
                throw new AuraHandledException('One or more selected permission sets are not valid for this object.');
            }
        }
    }

    private static Set<Id> buildIdSet(List<Id> idList) {
        Set<Id> idSet = new Set<Id>();

        if (idList != null) {
            idSet.addAll(idList);
        }

        return idSet;
    }

    private static void insertPermissionSetAssignments(Id userId, Set<Id> permissionSetIdsToAssign) {
        if (permissionSetIdsToAssign == null || permissionSetIdsToAssign.isEmpty()) {
            Logger.warn('RecordTypePsAssignmentService.insertPermissionSetAssignments: permissionSetIdsToAssign is null or empty');
            return;
        }

        List<PermissionSetAssignment> assignmentList = new List<PermissionSetAssignment>();

        for (Id permissionSetId : permissionSetIdsToAssign) {
            assignmentList.add(
                new PermissionSetAssignment(
                    AssigneeId = userId,
                    PermissionSetId = permissionSetId
                )
            );
        }

        insert assignmentList;
    }

    private static void deletePermissionSetAssignments(
        Map<Id, PermissionSetAssignment> assignmentByPermissionSetIdMap,
        Set<Id> permissionSetIdsToRemove
    ) {
        if (permissionSetIdsToRemove == null || permissionSetIdsToRemove.isEmpty()) {
            Logger.warn('RecordTypePsAssignmentService.deletePermissionSetAssignments: permissionSetIdsToRemove is null or empty');
            return;
        }

        List<PermissionSetAssignment> assignmentList = new List<PermissionSetAssignment>();

        for (Id permissionSetId : permissionSetIdsToRemove) {
            if (assignmentByPermissionSetIdMap.containsKey(permissionSetId)) {
                assignmentList.add(assignmentByPermissionSetIdMap.get(permissionSetId));
            }
        }

        if (assignmentList.isEmpty()) {
            Logger.warn('RecordTypePsAssignmentService.deletePermissionSetAssignments: assignmentList is null or empty');
            return;
        }

        delete assignmentList;
    }

    @SuppressWarnings('PMD.AvoidTestIsRunningTest')
    private static void throwForcedTestExceptionIfRequested(String methodName) {
        if (Test.isRunningTest() && forcedExceptionMethodName == methodName) {
            throw new QueryException('Script-thrown exception');
        }
    }

    private class ObjectOptionComparator implements Comparator<RecordTypePsAssignmentController.ObjectOptionWrapper> {
        public Integer compare(
            RecordTypePsAssignmentController.ObjectOptionWrapper firstOption,
            RecordTypePsAssignmentController.ObjectOptionWrapper secondOption
        ) {
            String firstLabel = firstOption == null || String.isBlank(firstOption.label) ? '' : firstOption.label;
            String secondLabel = secondOption == null || String.isBlank(secondOption.label) ? '' : secondOption.label;
            return firstLabel.compareTo(secondLabel);
        }
    }

    private class PermissionSetOptionComparator implements Comparator<RecordTypePsAssignmentController.PermissionSetOptionWrapper> {
        public Integer compare(
            RecordTypePsAssignmentController.PermissionSetOptionWrapper firstOption,
            RecordTypePsAssignmentController.PermissionSetOptionWrapper secondOption
        ) {
            String firstLabel = firstOption == null || String.isBlank(firstOption.label) ? '' : firstOption.label;
            String secondLabel = secondOption == null || String.isBlank(secondOption.label) ? '' : secondOption.label;
            return firstLabel.compareTo(secondLabel);
        }
    }
}