public class TaskSelector {
    
    /**
     * Returns open TAS notification Tasks for the given Accounts and Record Type.
     * GC 3143
     * @param accountIds Account Ids.
     * @param taskRecordTypeId Task Record Type Id.
     * @return List of open Task records.
     */
    public static List<Task> getOpenTasksByWhatIdsAndRecordType( Set<Id> accountIds, Id taskRecordTypeId) {
        if ( accountIds != null && !accountIds.isEmpty() &&
            taskRecordTypeId != null && Schema.sObjectType.Task.isAccessible()
        ) {
            return [
                SELECT Id, WhatId
                FROM Task
                WHERE WhatId IN :accountIds
                AND RecordTypeId = :taskRecordTypeId
                AND IsClosed = false
                WITH USER_MODE
            ];
        }
        return new List<Task>();
    }

}