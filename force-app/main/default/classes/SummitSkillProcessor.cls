/**
 * @description Batch Apex class to process SummitSkill__c records and sync Work Types, Skills, and Service Resource Skill requirements.
 *              Logging uses Nebula Logger from https://github.com/jongpie/NebulaLogger — install, settings, and architecture are documented there and in the project wiki.
 *              Apex usage follows https://github.com/jongpie/NebulaLogger/wiki/Logging-in-Apex (including batch parent transaction correlation).
 *              Platform exceptions are caught specifically, logged at ERROR with related records where possible, then rethrown as SummitSkillIntegrationException.
 *              Test-only behavior is centralized in SummitSkillProcessorTestSupport (see that class for why Test.isRunningTest() guards exist).
 * @see SummitSkillProcessorTest
 */
public with sharing class SummitSkillProcessor implements Database.Batchable<SObject>, Schedulable, Database.Stateful {

    /** Nebula Logger parent transaction id from batch start(); used to relate each batch chunk log to the job root (see Nebula wiki: Logging in Apex). */
    private String batchParentLogTransactionId;

    private class ProcessorContext {
        public Map<String, WorkType> wtMap;
        public Map<String, Skill> skillMap;
        public Map<String, ServiceResource> resMap;
        public Set<String> inactiveResExternalIds;
    }

    /**
     * @description Schedules a batch run of this processor with batch size 50.
     * @param sc The schedulable context provided by the platform (unused).
     */
    public void execute(SchedulableContext sc) {
        try {
            Database.executeBatch(new SummitSkillProcessor(), 50);
        } catch (AsyncException e) {
            Logger.newEntry(LoggingLevel.ERROR, 'SummitSkillProcessor: failed to enqueue batch from schedulable')
                .setExceptionDetails(e);
            throw new SummitSkillIntegrationException(
                'Summit skill integration: unable to enqueue SummitSkill__c batch job from schedulable. ' + e.getMessage()
            );
        } catch (LimitException e) {
            Logger.newEntry(LoggingLevel.ERROR, 'SummitSkillProcessor: governor limit prevented batch enqueue from schedulable')
                .setExceptionDetails(e);
            throw new SummitSkillIntegrationException(
                'Summit skill integration: governor limit prevented SummitSkill__c batch job from being enqueued. ' + e.getMessage()
            );
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description Returns SummitSkill__c records in Wait status for integration processing.
     * @param bc The batchable context for this job.
     * @return A query locator over the scope records.
     */
    public Database.QueryLocator start(Database.BatchableContext bc) {
        this.batchParentLogTransactionId = Logger.getTransactionId();
        try {
            Logger.newEntry(LoggingLevel.DEBUG, 'SummitSkillProcessor batch job start');
            return Database.getQueryLocator([
                SELECT Id, WorkType__c, PFCL__c, HRISID__c, Integration_Status__c, DeploymentStatus__c
                FROM SummitSkill__c
                WHERE Integration_Status__c = 'Wait'
            ]);
        } catch (QueryException e) {
            Logger.newEntry(LoggingLevel.ERROR, 'SummitSkillProcessor: query SummitSkill__c in Wait status failed')
                .setExceptionDetails(e);
            throw new SummitSkillIntegrationException(
                'Summit skill integration: failed to query SummitSkill__c records in Wait status for batch start. ' + e.getMessage()
            );
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description Processes one batch chunk: resolves context maps, builds ServiceResourceSkill rows, and updates source records.
     * @param bc The batchable context for this chunk.
     * @param scope SummitSkill__c rows to process.
     */
    public void execute(Database.BatchableContext bc, List<SObject> scope) {
        if (String.isNotBlank(this.batchParentLogTransactionId)) {
            Logger.setParentLogTransactionId(this.batchParentLogTransactionId);
        }

        List<SummitSkill__c> skillRecords = (List<SummitSkill__c>) scope;
        List<SummitSkill__c> recordsToUpdate = new List<SummitSkill__c>();
        List<ServiceResourceSkill> skillsToInsert = new List<ServiceResourceSkill>();

        try {
            ProcessorContext ctx = new ProcessorContext();
            ctx.wtMap = upsertWorkTypes(skillRecords);
            ctx.skillMap = getSkillMap(skillRecords);
            ctx.resMap = loadServiceResources(skillRecords, ctx);

            for (SummitSkill__c record : skillRecords) {
                processRecord(record, ctx, skillsToInsert);
                recordsToUpdate.add(record);
            }

            if (!skillsToInsert.isEmpty()) {
                if (!SummitSkillProcessorTestSupport.isServiceResourceSkillInsertSuppressedInTest()) {
                    insert skillsToInsert;
                }
            }
            if (!recordsToUpdate.isEmpty()) {
                update recordsToUpdate;
            }
        } catch (SummitSkillIntegrationException e) {
            throw e;
        } catch (DmlException e) {
            LogEntryEventBuilder dmlLogEntry = Logger.newEntry(
                LoggingLevel.ERROR,
                'SummitSkillProcessor: DML failed while inserting ServiceResourceSkill or updating SummitSkill__c'
            ).setExceptionDetails(e);
            if (!skillRecords.isEmpty()) {
                dmlLogEntry.setRecord(skillRecords[0]);
            }
            throw new SummitSkillIntegrationException(
                'Summit skill integration: DML failed while persisting ServiceResourceSkill rows or SummitSkill__c updates. '
                    + e.getDmlMessage(0)
            );
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description Sets deployment/integration fields on a single SummitSkill__c and queues ServiceResourceSkill inserts when all lookups resolve.
     * @param record The SummitSkill__c row to update in memory (persisted by caller DML).
     * @param ctx Preloaded WorkType, Skill, and ServiceResource maps for the chunk.
     * @param skillsToInsert Output list; new ServiceResourceSkill rows are added here when appropriate.
     */
    private void processRecord(SummitSkill__c record, ProcessorContext ctx, List<ServiceResourceSkill> skillsToInsert) {
        String statusTrace = 'Found Work Type; ';
        Boolean isSuccess = true;
        String skillKey = SummitSkillsUtil.buildCompositeSkillMasterLabel(record.PFCL__c, record.WorkType__c);

        Skill sk = ctx.skillMap.get(skillKey);
        ServiceResource sr = ctx.resMap.get(record.HRISID__c);

        if (sk != null) {
            statusTrace += 'Found Skill; ';
        } else {
            statusTrace += 'Skill Not Found; ';
            isSuccess = false;
        }

        if (sr != null) {
            statusTrace += 'Found Service Resource; ';
        } else if (
            ctx.inactiveResExternalIds != null &&
            record.HRISID__c != null &&
            ctx.inactiveResExternalIds.contains(record.HRISID__c)
        ) {
            statusTrace += 'Service Resource Inactive; ';
            isSuccess = false;
        } else {
            statusTrace += 'Service Resource Not Found; ';
            isSuccess = false;
        }

        if (isSuccess) {
            if (isRequirementMissing(record, sr.Id, sk.Id)) {
                skillsToInsert.add(new ServiceResourceSkill(
                    ServiceResourceId = sr.Id,
                    SkillId = sk.Id,
                    EffectiveStartDate = Date.today()
                ));
                statusTrace += 'Created Skill Requirement; ';
            } else {
                statusTrace += 'Skill Requirement Already Exists; ';
            }
        }

        record.DeploymentStatus__c = statusTrace;
        record.Integration_Status__c = isSuccess ? 'Done' : 'Fail';
    }

    /**
     * @description Returns true when no ServiceResourceSkill exists yet for the given Service Resource and Skill.
     * @param summitSkill SummitSkill__c row under integration (used for error logging context).
     * @param srId Service Resource Id.
     * @param sId Skill Id.
     * @return True if no matching row exists.
     */
    private Boolean isRequirementMissing(SummitSkill__c summitSkill, Id srId, Id sId) {
        if (
            SummitSkillProcessorTestSupport.isServiceResourceSkillPairTreatedAsExisting(
                SummitSkillProcessorTestSupport.buildRequirementPairKey(srId, sId)
            )
        ) {
            return false;
        }
        // Synthetic Skill Ids in tests may not be query-bindable as SkillId; skip SOQL when SRS insert is suppressed.
        if (SummitSkillProcessorTestSupport.isServiceResourceSkillInsertSuppressedInTest()) {
            return true;
        }
        // SOQL into a List never throws when zero rows match (unlike assigning a single sObject from the same query).
        try {
            return [SELECT Id FROM ServiceResourceSkill WHERE ServiceResourceId = :srId AND SkillId = :sId LIMIT 1].isEmpty();
        } catch (QueryException e) {
            Logger.newEntry(LoggingLevel.ERROR, 'SummitSkillProcessor: query ServiceResourceSkill failed')
                .setRecord(summitSkill)
                .setExceptionDetails(e);
            throw new SummitSkillIntegrationException(
                'Summit skill integration: failed to query existing ServiceResourceSkill for SummitSkill__c Id '
                    + summitSkill.Id
                    + '. '
                    + e.getMessage()
            );
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description Ensures WorkType rows exist for all distinct work type names in the scope; inserts missing types.
     * @param scope SummitSkill__c rows in the current chunk.
     * @return Map of WorkType Name to WorkType (existing plus newly inserted).
     */
    private Map<String, WorkType> upsertWorkTypes(List<SummitSkill__c> scope) {
        Set<String> wtNames = new Set<String>();
        for (SummitSkill__c s : scope) {
            if (s.WorkType__c != null) {
                wtNames.add(s.WorkType__c);
            }
        }

        Map<String, WorkType> existingWTs = new Map<String, WorkType>();
        List<WorkType> toCreate = new List<WorkType>();
        try {
            for (WorkType wt : [SELECT Id, Name FROM WorkType WHERE Name IN :wtNames]) {
                existingWTs.put(wt.Name, wt);
            }

            for (String name : wtNames) {
                if (!existingWTs.containsKey(name)) {
                    toCreate.add(new WorkType(Name = name, EstimatedDuration = 60));
                }
            }
            if (!toCreate.isEmpty()) {
                insert toCreate;
                for (WorkType wt : toCreate) {
                    existingWTs.put(wt.Name, wt);
                }
            }
        } catch (QueryException e) {
            LogEntryEventBuilder workTypeLogEntry = Logger.newEntry(
                LoggingLevel.ERROR,
                'SummitSkillProcessor: query WorkType failed'
            ).setExceptionDetails(e);
            if (!scope.isEmpty()) {
                workTypeLogEntry.setRecord(scope[0]);
            }
            throw new SummitSkillIntegrationException(
                'Summit skill integration: failed to query WorkType rows for SummitSkill__c chunk. ' + e.getMessage()
            );
        } catch (DmlException e) {
            LogEntryEventBuilder workTypeDmlLogEntry = Logger.newEntry(
                LoggingLevel.ERROR,
                'SummitSkillProcessor: insert WorkType failed'
            ).setExceptionDetails(e);
            if (!scope.isEmpty()) {
                workTypeDmlLogEntry.setRecord(scope[0]);
            }
            throw new SummitSkillIntegrationException(
                'Summit skill integration: failed to insert WorkType rows required by SummitSkill__c chunk. '
                    + e.getDmlMessage(0)
            );
        } finally {
            Logger.saveLog();
        }
        return existingWTs;
    }

    /**
     * @description Builds a map of Skill MasterLabel to Skill for labels required by the scope; in tests may use SummitSkillProcessorTestSupport overrides.
     * @param scope SummitSkill__c rows in the current chunk.
     * @return Map of composite skill key to Skill.
     */
    private Map<String, Skill> getSkillMap(List<SummitSkill__c> scope) {
        Set<String> skillNames = new Set<String>();
        for (SummitSkill__c s : scope) {
            if (s.PFCL__c != null && s.WorkType__c != null) {
                skillNames.add(SummitSkillsUtil.buildCompositeSkillMasterLabel(s.PFCL__c, s.WorkType__c));
            }
        }
        Map<String, Skill> overrideSlice = SummitSkillProcessorTestSupport.skillMapOverrideSliceForChunk(skillNames);
        if (overrideSlice != null) {
            return overrideSlice;
        }
        Map<String, Skill> m = new Map<String, Skill>();
        try {
            for (Skill s : [SELECT Id, MasterLabel FROM Skill WHERE MasterLabel IN :skillNames]) {
                m.put(s.MasterLabel, s);
            }
            SummitSkillProcessorTestSupport.applyInjectSkillForMissingMapKeys(m, skillNames);
        } catch (QueryException e) {
            LogEntryEventBuilder skillLogEntry = Logger.newEntry(
                LoggingLevel.ERROR,
                'SummitSkillProcessor: query Skill failed'
            ).setExceptionDetails(e);
            if (!scope.isEmpty()) {
                skillLogEntry.setRecord(scope[0]);
            }
            throw new SummitSkillIntegrationException(
                'Summit skill integration: failed to query Skill rows for SummitSkill__c chunk. ' + e.getMessage()
            );
        } catch (SummitSkillIntegrationException e) {
            throw e;
        } finally {
            Logger.saveLog();
        }
        return m;
    }

    /**
     * @description Loads active ServiceResource rows and tracks inactive HRIS external ids for the scope.
     * @param scope SummitSkill__c rows in the current chunk.
     * @param ctx Processor context; inactiveResExternalIds is populated from the lookup.
     * @return Map of ExternalID__c to active ServiceResource.
     */
    private Map<String, ServiceResource> loadServiceResources(List<SummitSkill__c> scope, ProcessorContext ctx) {
        Set<String> ids = new Set<String>();
        for (SummitSkill__c s : scope) {
            if (s.HRISID__c != null) {
                ids.add(s.HRISID__c);
            }
        }
        SummitSkillsUtil.ServiceResourceByExternalIdLookup lookup =
            SummitSkillsUtil.lookupServiceResourcesByExternalId(ids, scope);
        ctx.inactiveResExternalIds = lookup.inactiveExternalIds;
        return lookup.activeByExternalId;
    }

    /**
     * @description Runs after all chunks complete; logs batch completion at DEBUG level.
     * @param bc The batchable context for the finished job.
     */
    public void finish(Database.BatchableContext bc) {
        if (String.isNotBlank(this.batchParentLogTransactionId)) {
            Logger.setParentLogTransactionId(this.batchParentLogTransactionId);
        }
        try {
            Logger.newEntry(LoggingLevel.DEBUG, 'SummitSkillProcessor batch job finished.');
        } finally {
            Logger.saveLog();
        }
    }
}