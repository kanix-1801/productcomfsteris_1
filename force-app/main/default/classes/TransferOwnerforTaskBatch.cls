/**
 * @author PSL
 * @date 01-02-2026
 * @description Helper batch class to transfer Task ownership to the appropriate BL user based on TaskSLAConfig metadata.
 *              Fetches eligible open Tasks, evaluates TransferCriteria__c per matching Subject, resolves BL User from Case Team,
 *              and reassigns Task Owner where criteria is satisfied. Tracks processing statistics across batch chunks.
 */
public with sharing class TransferOwnerforTaskBatch
    implements Database.Batchable<SObject>, Database.Stateful
{
    private static final String DEFAULT_OPEN_STATUS = 'Open';
    private static final String BL_TEAM_ROLE_NAME   = 'BL User';
    private static final String TaskRecordType   = Schema.SObjectType.Task.getRecordTypeInfosByDeveloperName().get('CBM_Task').getRecordTypeId();

    private Map<String, List<TaskSLAConfig__mdt>> cfgsBySubject;
    private Set<String> subjectsFromMdt;
    private Set<Id> activeUserIds;

    public Integer processed = 0, considered = 0, reassigned = 0, skipped = 0, failed = 0;
    public List<String> errors = new List<String>();

    /**
     * @description Initializes batch state by loading active TaskSLAConfig__mdt rows requiring transfer,
     *              caching allowed Subjects and active Users, and returning a QueryLocator for eligible Tasks.
     * @param bc Batchable context provided by the platform
     * @return Database.QueryLocator selecting open Tasks whose Subjects are present in metadata, linked to a WhatId and correct Record Type
     */
    public Database.QueryLocator start(Database.BatchableContext bc) {

        List<TaskSLAConfig__mdt> cfgs = [
            SELECT Id, DeveloperName, MasterLabel,
                   TaskSubject__c, IsActive__c, IsTransferRequired__c,
                   TransferCriteria__c, TransferTo__c, Object__c
              FROM TaskSLAConfig__mdt
             WHERE IsActive__c = TRUE
               AND IsTransferRequired__c = TRUE
        ];

        cfgsBySubject  = new Map<String, List<TaskSLAConfig__mdt>>();
        subjectsFromMdt = new Set<String>();

        for (TaskSLAConfig__mdt cfg : cfgs) {
            if (String.isBlank(cfg.TaskSubject__c)) continue;
            String subj = cfg.TaskSubject__c.trim();

            subjectsFromMdt.add(subj);

            List<TaskSLAConfig__mdt> bucket = cfgsBySubject.get(subj);
            if (bucket == null) {
                bucket = new List<TaskSLAConfig__mdt>();
                cfgsBySubject.put(subj, bucket);
            }
            bucket.add(cfg);
        }

        if (subjectsFromMdt.isEmpty()) {
            return Database.getQueryLocator('SELECT Id FROM Task WHERE Id = null');
        }

        activeUserIds = new Set<Id>();
        for (User u : [SELECT Id FROM User WHERE IsActive = TRUE]) {
            activeUserIds.add(u.Id);
        }

        return Database.getQueryLocator([
            SELECT Id, Subject, Status, OwnerId, WhatId,
                   Priority, ActivityDate, CreatedDate, LastModifiedDate
              FROM Task
             WHERE Subject IN :subjectsFromMdt And TAskTeam__c='OM User' 
            	AND recordTypeID = : TaskRecordType
               AND Status  = :DEFAULT_OPEN_STATUS
               AND WhatId != null
        ]);
    }

    /**
     * @description Processes a scope of Tasks, evaluates TransferCriteria__c per matching Subject,
     *              resolves BL user from Case Team, and reassigns ownership where applicable.
     * @param bc Batchable context provided by the platform
     * @param scope Chunk of SObjects provided by the batch framework (expected Task records)
     * @return void
     */
public void execute(Database.BatchableContext bc, List<SObject> scope) {
    if (scope == null || scope.isEmpty()) return;

    List<Task> tasksInScope = new List<Task>(scope.size());
    for (SObject sob : scope) {
        if (sob == null) {
            skipped++;
            continue;
        }
        if (sob.getSObjectType() == Task.SObjectType) {
            tasksInScope.add((Task)sob);
        } else {
            skipped++;
        }
    }
    if (tasksInScope.isEmpty()) return;

    processed += tasksInScope.size();

    Map<Id, Task> tasksById = new Map<Id, Task>();
    Set<Id> caseIds = new Set<Id>();
    for (Task t : tasksInScope) {
        if (t == null) {
            skipped++;
            continue;
        }
        Id whatId = t.WhatId;
        if (whatId != null && String.valueOf(whatId).startsWith('500')) {
            tasksById.put(t.Id, t);
            caseIds.add(whatId);
        } else {
            skipped++;
        }
    }
    if (tasksById.isEmpty()) return;

    Map<Id, List<CaseTeamMember>> ctmByCase = new Map<Id, List<CaseTeamMember>>();
    for (CaseTeamMember ctm : [
        SELECT Id, ParentId, MemberId, TeamRoleId, TeamRole.Name
          FROM CaseTeamMember
         WHERE ParentId IN :caseIds
    ]) {
        List<CaseTeamMember> bucket = ctmByCase.get(ctm.ParentId);
        if (bucket == null) {
            bucket = new List<CaseTeamMember>();
            ctmByCase.put(ctm.ParentId, bucket);
        }
        bucket.add(ctm);
    }

    List<Task> toUpdate = new List<Task>();

    for (Task t : tasksById.values()) {
        if (t == null) { skipped++; continue; }   // extra guard

        if (cfgsBySubject == null) {
            failed++;
            errors.add('cfgsBySubject is null in execute(); ensure start() initializes it.');
            return;
        }

        List<TaskSLAConfig__mdt> cfgsForSubject = cfgsBySubject.get(t.Subject);
        if (cfgsForSubject == null || cfgsForSubject.isEmpty()) {
            skipped++;
            continue;
        }

        considered++;
        Id newOwnerId = null;

        for (TaskSLAConfig__mdt cfg : cfgsForSubject) {
            if (cfg == null || cfg.IsTransferRequired__c != true) continue;

            Boolean ok = evalCriteriaOnTask(cfg.TransferCriteria__c, t); // formula evaluator
            if (!ok) continue;

            Id blUser = resolveBLUserFromCaseTeam(ctmByCase.get(t.WhatId));
            if (blUser == null) continue;

            if (!activeUserIds.contains(blUser)) continue;
            if (t.OwnerId == blUser)  continue;

            newOwnerId = blUser;
            break;
        }

        if (newOwnerId != null) {
            toUpdate.add(new Task(Id = t.Id, OwnerId = newOwnerId, TaskTeam__C='OM and BL'));
            reassigned++;
        } else {
            skipped++;
        }
    }

    if (!toUpdate.isEmpty()) {
        try {
            System.debug('Tasks to update => ' + toUpdate);
            update toUpdate;
        } catch (DmlException d) {
            failed += toUpdate.size();
            errors.add('Update failed for ' + toUpdate.size() + ' tasks: ' + d.getMessage());
        }
    }
}


    /**
     * @description Logs summary statistics and any captured errors after batch completion.
     * @param bc Batchable context provided by the platform
     * @return void
     */
    public void finish(Database.BatchableContext bc) {
        System.debug(LoggingLevel.INFO,
            'DummyTransferOwner done => processed=' + processed +
            ', considered=' + considered +
            ', reassigned=' + reassigned +
            ', skipped=' + skipped +
            ', failed=' + failed
        );
        for (String e : errors) System.debug(LoggingLevel.ERROR, e);
    }


    /**
     * @description Evaluates a boolean expression (TransferCriteria__c) against the provided Task.
     *              Returns true when blank, false on errors or non-boolean results.
     * @param formulaText Criteria string from metadata
     * @param sObj Task record evaluated by the formula
     * @return Boolean evaluation result; false on exceptions or non-boolean outcome
     */
    @TestVisible
    private Boolean evalCriteriaOnTask(String formulaText, SObject sObj) {
        if (String.isBlank(formulaText)) return true; // blank criteria => allow
        try {
            FormulaEval.FormulaInstance inst = System.Formula.builder()
                .withType(sObj.getSObjectType())
                .withReturnType(FormulaEval.FormulaReturnType.BOOLEAN)
                .withFormula(formulaText)
                .build();
            Object result = inst.evaluate(sObj);
            if (result instanceof Boolean) return (Boolean)result;

            errors.add('Formula did not return BOOLEAN for ' + sObj.getSObjectType() + ': ' + formulaText);
            failed++;
            return false;
        } catch (Exception e) {
            errors.add('Formula eval error: ' + e.getMessage() + ' | formula=' + formulaText);
            failed++;
            return false;
        }
    }

    /**
     * @description Resolves the first Case Team member with TeamRole.Name equal to BL_TEAM_ROLE_NAME (case-insensitive).
     *              Returns the member's User Id or null if not found.
     * @param team List of CaseTeamMember for a Case
     * @return Id of BL user or null
     */
    @TestVisible
    private Id resolveBLUserFromCaseTeam(List<CaseTeamMember> team) {
        if (team == null || team.isEmpty()) return null;
        for (CaseTeamMember ctm : team) {
            if (ctm.TeamRole != null && ctm.TeamRole.Name != null
                && ctm.TeamRole.Name.equalsIgnoreCase(BL_TEAM_ROLE_NAME)) {
                return ctm.MemberId;
            }
        }
        return null;
    }
}