/**
 * OrderLineContact__c trigger service for sales rep assignment.
 *
 * Business rules:
 * 1. Match HRISSalesRepId__c to active User.EmployeeNumber__c.
 * 2. Set AssignedSalesRep__c to the matched User; clear it when no match exists.
 * 3. Insert — process rows where HRIS id is populated.
 * 4. Update — process only when HRIS id changed to a new populated value.
 * 5. Blank HRIS id — skip the row (AssignedSalesRep__c is left unchanged on update).
 *
 * Bulk pattern: one pass to find eligible rows, one User query, one pass to assign.
 * Runs in before trigger context — no DML, only in-memory field updates.
 * @author Suraj Thapliyal
 * @date 06-29-2026
 * GC-3278 - TAS class rename (formerly OrderLineContactService).
 */
public with sharing class TASService {

    /**
     * Before insert entry point from OrderLineContactTriggerHandler.
     * @author Suraj Thapliyal
     * @param newRecords Trigger.new rows
     */
    public static void processBeforeInsert(List<OrderLineContact__c> newRecords) {
        runAssignment(newRecords, null, 'processBeforeInsert');
    }

    /**
     * Before update entry point from OrderLineContactTriggerHandler.
     * @author Suraj Thapliyal
     * @param newRecords Trigger.new rows
     * @param oldMap Trigger.oldMap keyed by record Id
     */
    public static void processBeforeUpdate(
        List<OrderLineContact__c> newRecords,
        Map<Id, OrderLineContact__c> oldMap
    ) {
        if (oldMap == null || oldMap.isEmpty()) {
            Logger.warn('TASService.processBeforeUpdate: oldMap is null or empty');
            Logger.saveLog();
        } else {
            runAssignment(newRecords, oldMap, 'processBeforeUpdate');
        }
    }

    /**
     * Shared wrapper for insert and update assignment.
     * Logs start/end, enforces field access, and persists Nebula Logger output.
     * @param records Trigger rows to evaluate
     * @param oldMap Null on insert; Trigger.oldMap on update
     * @param methodName Caller name used in log messages
     */
    private static void runAssignment(
        List<OrderLineContact__c> records,
        Map<Id, OrderLineContact__c> oldMap,
        String methodName
    ) {
        try {
            Logger.info('TASService.' + methodName + ': started');

            if (records != null && !records.isEmpty()) {
                assertCanAssignSalesRep();

                Integer assignedCount = assignSalesRepFromHris(records, oldMap);

                Logger.info(
                    'TASService.' + methodName + ': assignedCount=' + assignedCount
                );
            } else {
                Logger.warn('TASService.' + methodName + ': no records in trigger context');
            }
        } catch (Exception e) {
            Logger.error('TASService.' + methodName, e);
            throw e;
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * Resolves AssignedSalesRep__c for all eligible rows in the trigger batch.
     *
     * Step 1 — Walk trigger rows once. Skip ineligible rows. Collect HRIS ids for the rest.
     * Step 2 — Query all matching active Users in a single SOQL call.
     * Step 3 — Set or clear AssignedSalesRep__c on each eligible row.
     *
     * @param records All trigger rows
     * @param oldMap Null on insert; prior field values on update
     * @return Number of rows where AssignedSalesRep__c was evaluated
     */
    private static Integer assignSalesRepFromHris(
        List<OrderLineContact__c> records,
        Map<Id, OrderLineContact__c> oldMap
    ) {
        Set<String> hrisIds = new Set<String>();
        List<OrderLineContact__c> recordsToAssign = new List<OrderLineContact__c>();

        for (OrderLineContact__c orderLineContact : records) {
            if (!shouldAssignSalesRep(orderLineContact, oldMap)) {
                continue;
            }

            hrisIds.add(normalizeHrisId(orderLineContact.HRISSalesRepId__c));
            recordsToAssign.add(orderLineContact);
        }

        if (recordsToAssign.isEmpty()) {
            return 0;
        }

        Map<String, User> activeUsersByHrisId =
            UserSelector.selectActiveUsersByEmployeeNumber(hrisIds);

        for (OrderLineContact__c orderLineContact : recordsToAssign) {
            String hrisId = normalizeHrisId(orderLineContact.HRISSalesRepId__c);
            orderLineContact.AssignedSalesRep__c = resolveUserId(hrisId, activeUsersByHrisId);
        }

        return recordsToAssign.size();
    }

    /**
     * Decides whether a row needs sales rep assignment in the current trigger pass.
     *
     * Insert — HRIS id must be present.
     * Update — HRIS id must be present and different from the old value.
     * Blank HRIS id — always skip; we do not clear AssignedSalesRep__c on update.
     *
     * @param orderLineContact Current trigger row
     * @param oldMap Null on insert; Trigger.oldMap on update
     */
    private static Boolean shouldAssignSalesRep(
        OrderLineContact__c orderLineContact,
        Map<Id, OrderLineContact__c> oldMap
    ) {
        String newHrisId = normalizeHrisId(orderLineContact.HRISSalesRepId__c);

        if (newHrisId == null) {
            return false;
        }

        // Insert path — any populated HRIS id is eligible.
        if (oldMap == null) {
            return true;
        }

        OrderLineContact__c priorVersion = oldMap.get(orderLineContact.Id);

        if (priorVersion == null) {
            Logger.warn(
                'TASService.shouldAssignSalesRep: prior version missing for Id=' +
                orderLineContact.Id
            );
            return false;
        }

        // Update path — only when HRIS id actually changed.
        Boolean shouldAssign =
            newHrisId != normalizeHrisId(priorVersion.HRISSalesRepId__c);
        return shouldAssign;
    }

    /**
     * Looks up the active User Id for a HRIS employee number.
     * Returns null when no active User match exists so AssignedSalesRep__c is cleared.
     *
     * @param hrisId Normalized HRISSalesRepId__c value
     * @param activeUsersByHrisId Users keyed by EmployeeNumber__c from UserSelector
     */
    private static Id resolveUserId(
        String hrisId,
        Map<String, User> activeUsersByHrisId
    ) {
        if (!activeUsersByHrisId.containsKey(hrisId)) {
            return null;
        }

        return activeUsersByHrisId.get(hrisId).Id;
    }

    /**
     * Normalizes HRIS text for consistent comparison and map lookups.
     * Blank and whitespace-only values are treated as absent.
     *
     * @param hrisId Raw HRISSalesRepId__c value
     */
    private static String normalizeHrisId(String hrisId) {
        String normalizedHrisId;
        if (String.isBlank(hrisId)) {
            normalizedHrisId = null;
        } else {
            normalizedHrisId = hrisId.trim();
        }
        return normalizedHrisId;
    }

    /**
     * Ensures the running user can read HRIS/User data and update AssignedSalesRep__c.
     */
    private static void assertCanAssignSalesRep() {
        if (!Schema.sObjectType.OrderLineContact__c.fields.AssignedSalesRep__c.isUpdateable()) {
            throw new TASTeamAccessException('User does not has access to the field AssignedSalesRep__c');
        }
    }
    
    
}