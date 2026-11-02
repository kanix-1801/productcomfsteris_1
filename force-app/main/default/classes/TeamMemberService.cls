/**
 * @author Abhishek Mishra
 * @date 15-10-2026
 * @description #GC-3435 Shares every parent record looked up from Team Member.
 *              A new lookup on Team Member is picked up without an Apex change.
 *              The parent owner is skipped. Removing the last row for a user removes the share.
 */
public without sharing class TeamMemberService {
    public static final String ROW_CAUSE = 'TeamMember__c';
    private static final String MANUAL_ROW_CAUSE = 'Manual';
    private static final String ACCESS_EDIT = 'Edit';
    private static final String ACCESS_READ = 'Read';
    private static List<Schema.DescribeFieldResult> parentLookups;

    /**
     * @description Requires one parent record and blocks the same user on that record twice.
     * @param rows List<TeamMember__c> records being inserted or updated
     * @return void
     */
    public static void validateDuplicates(List<TeamMember__c> rows) {
        Map<String, Id> existingIdByKey = existingIdsByKey(rows);
        Set<String> keysInBatch = new Set<String>();
        for (TeamMember__c row : rows) {
            if (row.User__c == null) {
                row.addError('Select the user to share this record with.');
                continue;
            }
            List<Id> parentIds = parentIds(row);
            if (parentIds.isEmpty()) {
                row.addError('Select the record to share with this user.');
                continue;
            }
            for (Id parentId : parentIds) {
                String rowKey = shareKey(parentId, row.User__c);
                Id existingId = existingIdByKey.get(rowKey);
                if ((existingId != null && existingId != row.Id) || keysInBatch.contains(rowKey)) {
                    row.addError('This user already has access to this record.');
                }
                keysInBatch.add(rowKey);
            }
        }
    }

    /**
     * @description Rebuilds record shares for every parent touched by this transaction.
     * @param newRows List<TeamMember__c> current rows, null on delete
     * @param oldMap Map<Id, TeamMember__c> prior rows, null on insert
     * @return void
     */
    public static void syncShares(
        List<TeamMember__c> newRows,
        Map<Id, TeamMember__c> oldMap
    ) {
        List<TeamMember__c> oldRows = oldMap == null ? null : oldMap.values();
        Map<Schema.SObjectType, Set<Id>> idsByType = parentIdsByType(newRows);
        mergeIds(idsByType, parentIdsByType(oldRows));
        Map<Schema.SObjectType, List<String>> fieldsByType = lookupsByParentType();
        for (Schema.SObjectType parentType : idsByType.keySet()) {
            syncObject(
                parentType,
                fieldsByType.get(parentType),
                idsByType.get(parentType),
                newRows,
                oldMap
            );
        }
    }

    private static void syncObject(
        Schema.SObjectType parentType,
        List<String> lookupFields,
        Set<Id> parentIds,
        List<TeamMember__c> newRows,
        Map<Id, TeamMember__c> oldMap
    ) {
        if (lookupFields == null || lookupFields.isEmpty() || parentIds.isEmpty()) {
            return;
        }
        Schema.DescribeSObjectResult parentDescribe = parentType.getDescribe();
        String shareName = shareObjectName(parentDescribe);
        Schema.SObjectType shareType = shareTypeFor(shareName);
        List<TeamMember__c> rowsForObject = rowsForParents(newRows, oldMap, lookupFields, parentIds);
        if (shareType == null) {
            markError(rowsForObject, parentDescribe.getLabel() + ' does not support record sharing.');
            return;
        }

        String parentField = parentIdField(shareType, parentType);
        String accessField = primaryAccessField(shareType, parentType);
        if (parentField == null || accessField == null) {
            markError(rowsForObject, parentDescribe.getLabel() + ' does not support record sharing.');
            return;
        }

        Map<Id, Id> ownerByParent = ownersByParent(parentDescribe, parentIds);
        Map<String, String> desiredAccessByKey = desiredAccess(lookupFields, parentIds, ownerByParent);
        String rowCause = rowCauseFor(shareType);
        List<SObject> existingShares = Database.query(
            'SELECT Id, ' + parentField + ', UserOrGroupId, ' + accessField +
            ' FROM ' + shareName +
            ' WHERE ' + parentField + ' IN :parentIds AND RowCause = :rowCause'
        );

        List<SObject> toDelete = new List<SObject>();
        List<SObject> toUpdate = new List<SObject>();
        Set<String> coveredKeys = new Set<String>();
        for (SObject shareRow : existingShares) {
            String rowKey = shareKey((Id) shareRow.get(parentField), (Id) shareRow.get('UserOrGroupId'));
            String desiredAccess = desiredAccessByKey.get(rowKey);
            if (desiredAccess == null) {
                toDelete.add(shareRow);
            } else {
                coveredKeys.add(rowKey);
                if ((String) shareRow.get(accessField) != desiredAccess) {
                    shareRow.put(accessField, desiredAccess);
                    toUpdate.add(shareRow);
                }
            }
        }

        List<SObject> toInsert = new List<SObject>();
        for (String rowKey : desiredAccessByKey.keySet()) {
            if (coveredKeys.contains(rowKey)) {
                continue;
            }
            List<String> parts = rowKey.split('\\|');
            SObject shareRow = shareType.newSObject();
            shareRow.put(parentField, (Id) parts[0]);
            shareRow.put('UserOrGroupId', (Id) parts[1]);
            shareRow.put('RowCause', rowCause);
            applyAccess(shareRow, shareType, accessField, desiredAccessByKey.get(rowKey));
            toInsert.add(shareRow);
        }
        saveShares(toDelete, toUpdate, toInsert, rowsForObject);
    }

    private static Map<String, String> desiredAccess(
        List<String> lookupFields,
        Set<Id> parentIds,
        Map<Id, Id> ownerByParent
    ) {
        Map<String, String> desiredAccessByKey = new Map<String, String>();
        for (String lookupField : lookupFields) {
            for (SObject row : Database.query(
                'SELECT ' + lookupField + ', User__c, AccessLevel__c' +
                ' FROM TeamMember__c' +
                ' WHERE ' + lookupField + ' IN :parentIds AND User__c != NULL'
            )) {
                Id parentId = (Id) row.get(lookupField);
                Id userId = (Id) row.get('User__c');
                if (userId == ownerByParent.get(parentId)) {
                    continue;
                }
                String rowKey = shareKey(parentId, userId);
                if (desiredAccessByKey.get(rowKey) != ACCESS_EDIT) {
                    desiredAccessByKey.put(rowKey, accessLevel((String) row.get('AccessLevel__c')));
                }
            }
        }
        return desiredAccessByKey;
    }

    private static Map<Id, Id> ownersByParent(Schema.DescribeSObjectResult parentDescribe, Set<Id> parentIds) {
        Map<Id, Id> ownerByParent = new Map<Id, Id>();
        if (!parentDescribe.fields.getMap().containsKey('ownerid')) {
            return ownerByParent;
        }
        String parentName = parentDescribe.getName();
        for (SObject parent : Database.query(
            'SELECT Id, OwnerId FROM ' + parentName + ' WHERE Id IN :parentIds'
        )) {
            ownerByParent.put((Id) parent.get('Id'), (Id) parent.get('OwnerId'));
        }
        return ownerByParent;
    }

    private static Map<String, Id> existingIdsByKey(List<TeamMember__c> rows) {
        Map<String, Id> existingIdByKey = new Map<String, Id>();
        for (Schema.DescribeFieldResult describe : parentLookupFields()) {
            String fieldName = describe.getName();
            Set<Id> parentIds = new Set<Id>();
            for (TeamMember__c row : rows) {
                Id parentId = (Id) row.get(fieldName);
                if (parentId != null) {
                    parentIds.add(parentId);
                }
            }
            if (parentIds.isEmpty()) {
                continue;
            }
            for (SObject existing : Database.query(
                'SELECT Id, User__c, ' + fieldName +
                ' FROM TeamMember__c WHERE ' + fieldName + ' IN :parentIds'
            )) {
                existingIdByKey.put(
                    shareKey((Id) existing.get(fieldName), (Id) existing.get('User__c')),
                    (Id) existing.get('Id')
                );
            }
        }
        return existingIdByKey;
    }

    private static Map<Schema.SObjectType, Set<Id>> parentIdsByType(List<TeamMember__c> rows) {
        Map<Schema.SObjectType, Set<Id>> idsByType = new Map<Schema.SObjectType, Set<Id>>();
        if (rows == null) {
            return idsByType;
        }
        for (TeamMember__c row : rows) {
            for (Schema.DescribeFieldResult describe : parentLookupFields()) {
                Id parentId = (Id) row.get(describe.getName());
                if (parentId == null) {
                    continue;
                }
                Schema.SObjectType parentType = describe.getReferenceTo()[0];
                if (!idsByType.containsKey(parentType)) {
                    idsByType.put(parentType, new Set<Id>());
                }
                idsByType.get(parentType).add(parentId);
            }
        }
        return idsByType;
    }

    private static void mergeIds(
        Map<Schema.SObjectType, Set<Id>> target,
        Map<Schema.SObjectType, Set<Id>> extra
    ) {
        for (Schema.SObjectType parentType : extra.keySet()) {
            if (!target.containsKey(parentType)) {
                target.put(parentType, new Set<Id>());
            }
            target.get(parentType).addAll(extra.get(parentType));
        }
    }

    private static Map<Schema.SObjectType, List<String>> lookupsByParentType() {
        Map<Schema.SObjectType, List<String>> fieldsByType = new Map<Schema.SObjectType, List<String>>();
        for (Schema.DescribeFieldResult describe : parentLookupFields()) {
            Schema.SObjectType parentType = describe.getReferenceTo()[0];
            if (!fieldsByType.containsKey(parentType)) {
                fieldsByType.put(parentType, new List<String>());
            }
            fieldsByType.get(parentType).add(describe.getName());
        }
        return fieldsByType;
    }

    private static List<Schema.DescribeFieldResult> parentLookupFields() {
        if (parentLookups != null) {
            return parentLookups;
        }
        parentLookups = new List<Schema.DescribeFieldResult>();
        for (Schema.SObjectField field : TeamMember__c.SObjectType.getDescribe().fields.getMap().values()) {
            Schema.DescribeFieldResult describe = field.getDescribe();
            if (!describe.isCustom()
                || describe.getType() != Schema.DisplayType.REFERENCE
                || describe.getReferenceTo().size() != 1
            ) {
                continue;
            }
            Schema.SObjectType target = describe.getReferenceTo()[0];
            if (target == User.SObjectType || target == Group.SObjectType || target == TeamMember__c.SObjectType) {
                continue;
            }
            parentLookups.add(describe);
        }
        return parentLookups;
    }

    private static List<Id> parentIds(TeamMember__c row) {
        List<Id> parentIds = new List<Id>();
        for (Schema.DescribeFieldResult describe : parentLookupFields()) {
            Id parentId = (Id) row.get(describe.getName());
            if (parentId != null) {
                parentIds.add(parentId);
            }
        }
        return parentIds;
    }

    private static String shareObjectName(Schema.DescribeSObjectResult parentDescribe) {
        String objectName = parentDescribe.getName();
        if (parentDescribe.isCustom()) {
            return objectName.replace('__c', '__Share');
        }
        return objectName + 'Share';
    }

    private static Schema.SObjectType shareTypeFor(String shareName) {
        try {
            return Schema.describeSObjects(new List<String>{ shareName })[0].getSObjectType();
        } catch (InvalidParameterValueException ex) {
            return null;
        }
    }

    private static String parentIdField(Schema.SObjectType shareType, Schema.SObjectType parentType) {
        for (Schema.SObjectField field : shareType.getDescribe().fields.getMap().values()) {
            Schema.DescribeFieldResult describe = field.getDescribe();
            if (describe.getType() != Schema.DisplayType.REFERENCE || describe.getName() == 'UserOrGroupId') {
                continue;
            }
            for (Schema.SObjectType reference : describe.getReferenceTo()) {
                if (reference == parentType) {
                    return describe.getName();
                }
            }
        }
        return null;
    }

    private static String primaryAccessField(Schema.SObjectType shareType, Schema.SObjectType parentType) {
        Map<String, Schema.SObjectField> fields = shareType.getDescribe().fields.getMap();
        if (fields.containsKey('accesslevel')) {
            return fields.get('accesslevel').getDescribe().getName();
        }
        String candidate = parentType.getDescribe().getName().replace('__c', '') + 'AccessLevel';
        for (String fieldName : fields.keySet()) {
            if (fieldName.equalsIgnoreCase(candidate)) {
                return fields.get(fieldName).getDescribe().getName();
            }
        }
        return null;
    }

    private static String rowCauseFor(Schema.SObjectType shareType) {
        Schema.SObjectField rowCauseField = shareType.getDescribe().fields.getMap().get('rowcause');
        if (rowCauseField == null) {
            return MANUAL_ROW_CAUSE;
        }
        for (Schema.PicklistEntry entry : rowCauseField.getDescribe().getPicklistValues()) {
            if (entry.getValue() == ROW_CAUSE) {
                return ROW_CAUSE;
            }
        }
        return MANUAL_ROW_CAUSE;
    }

    private static void applyAccess(
        SObject shareRow,
        Schema.SObjectType shareType,
        String primaryField,
        String access
    ) {
        shareRow.put(primaryField, access);
        for (Schema.SObjectField field : shareType.getDescribe().fields.getMap().values()) {
            Schema.DescribeFieldResult describe = field.getDescribe();
            if (describe.getName() == primaryField || !describe.getName().endsWith('AccessLevel') || !describe.isCreateable()) {
                continue;
            }
            shareRow.put(describe.getName(), siblingAccess(describe, access));
        }
    }

    private static String siblingAccess(Schema.DescribeFieldResult describe, String access) {
        Set<String> values = new Set<String>();
        for (Schema.PicklistEntry entry : describe.getPicklistValues()) {
            values.add(entry.getValue());
        }
        if (values.contains('None')) {
            return 'None';
        }
        if (values.contains(access)) {
            return access;
        }
        return ACCESS_READ;
    }

    private static void saveShares(
        List<SObject> toDelete,
        List<SObject> toUpdate,
        List<SObject> toInsert,
        List<TeamMember__c> rows
    ) {
        try {
            if (!toDelete.isEmpty()) {
                delete toDelete;
            }
            if (!toUpdate.isEmpty()) {
                update toUpdate;
            }
            if (!toInsert.isEmpty()) {
                insert toInsert;
            }
        } catch (DmlException ex) {
            markError(
                rows,
                'Could not share this record. Set the object to Private or Public Read Only. ' + ex.getDmlMessage(0)
            );
        }
    }

    private static List<TeamMember__c> rowsForParents(
        List<TeamMember__c> newRows,
        Map<Id, TeamMember__c> oldMap,
        List<String> lookupFields,
        Set<Id> parentIds
    ) {
        List<TeamMember__c> source = newRows != null
            ? newRows
            : (oldMap == null ? new List<TeamMember__c>() : oldMap.values());
        List<TeamMember__c> matched = new List<TeamMember__c>();
        for (TeamMember__c row : source) {
            TeamMember__c priorRow = oldMap == null ? null : oldMap.get(row.Id);
            if (pointsAt(row, lookupFields, parentIds) || pointsAt(priorRow, lookupFields, parentIds)) {
                matched.add(row);
            }
        }
        return matched;
    }

    private static Boolean pointsAt(
        TeamMember__c row,
        List<String> lookupFields,
        Set<Id> parentIds
    ) {
        if (row == null) {
            return false;
        }
        for (String lookupField : lookupFields) {
            Id parentId = (Id) row.get(lookupField);
            if (parentId != null && parentIds.contains(parentId)) {
                return true;
            }
        }
        return false;
    }

    private static void markError(List<TeamMember__c> rows, String message) {
        for (TeamMember__c row : rows) {
            row.addError(message);
        }
    }

    private static String accessLevel(String requestedAccess) {
        return requestedAccess == ACCESS_READ ? ACCESS_READ : ACCESS_EDIT;
    }

    private static String shareKey(Id parentId, Id userId) {
        return String.valueOf(parentId) + '|' + String.valueOf(userId);
    }
}