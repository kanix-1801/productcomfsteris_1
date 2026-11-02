/**
 * @description Synchronizes Business Unit Leaders onto Opportunity Team Members.
 *
 * Invoked from Flow with one or more Opportunity Ids. Selected Business Units on
 * each Opportunity are matched to Custom Metadata mappings, resolved to active
 * Users, then inserted or removed from the Opportunity Team as needed.
 *
 * High-level steps:
 *  1. Read selected Business Units from the Opportunity multi-select picklist.
 *  2. Load Business Unit -> Business Unit Leader mappings from Custom Metadata.
 *  3. Resolve mapped leader usernames to active Salesforce Users.
 *  4. Add missing BU Leaders to the Opportunity Team.
 *  5. Remove BU Leaders whose mapped Business Unit is no longer selected.
 *
 * Nebula Logger: diagnostics are buffered throughout this class and persisted via
 * {@code Logger.saveLog()} in the {@code finally} block of {@link #syncBULeaders}.
 *
 * @note Update OPPORTUNITY_BU_FIELD and BU_LEADER_TEAM_ROLE if org API names differ.
 */
public with sharing class OpportunityBULeaderTeamSync {

    private static final String CLASS_NAME = 'OpportunityBULeaderTeamSync';
    private static final String LOGGER_TAG = 'Opportunity';
    private static final String LOGGER_SCENARIO = 'Opportunity BU Leader Team Sync';

    // -------------------------------------------------------------------------
    // Org-specific constants (update if field or team role names change)
    // -------------------------------------------------------------------------

    /** API name of the Opportunity multi-select picklist that stores selected Business Units. */
    private static final String OPPORTUNITY_BU_FIELD = 'HCBusinessUnit__c';

    /**
     * Opportunity Team Member role assigned to BU Leaders.
     * Must match the Team Role value configured in the org exactly.
     */
    private static final String BU_LEADER_TEAM_ROLE = 'Business Unit Leader';

    /**
     * Test-only mapping rows. Production leaves this null and reads Custom Metadata.
     * An empty list is intentional and exercises the no-mapping exit.
     */
    @TestVisible
    private static List<Business_Unit_Leader_Mappings__mdt> testMappings;

    /** When true during a test, syncBULeaders throws and the catch block handles it. */
    @TestVisible
    private static Boolean testThrowBeforeSync = false;

    // -------------------------------------------------------------------------
    // Flow input wrapper
    // -------------------------------------------------------------------------

    /**
     * @description Request payload for the invocable method. Flow supplies Opportunity Ids.
     */
    public class FlowInput {
        @InvocableVariable(
            required=true
            label='Opportunity ID'
            description='Opportunity whose BU Leaders should be synchronized.'
        )
        public Id opportunityId;
    }

    // -------------------------------------------------------------------------
    // Invocable entry point
    // -------------------------------------------------------------------------

    /**
     * @description Flow entry point. Collects Opportunity Ids and runs the team sync.
     * @param inputs List of FlowInput records, each containing an Opportunity Id.
     */
    @InvocableMethod(
        label='Sync Business Unit Leaders'
        description='Synchronizes Business Unit Leaders with Opportunity Team Members.'
    )
    public static void syncBULeaders(List<FlowInput> inputs) {
        try {
            Logger.setScenario(LOGGER_SCENARIO);
            Logger.info(CLASS_NAME + '.syncBULeaders: started').addTag(LOGGER_TAG);

            if (Test.isRunningTest() && testThrowBeforeSync) {
                testThrowBeforeSync = false;
                throw new IllegalArgumentException('OpportunityBULeaderTeamSync test exception');
            }

            if (inputs == null || inputs.isEmpty()) {
                Logger.debug(CLASS_NAME + '.syncBULeaders: no flow inputs received')
                    .addTag(LOGGER_TAG);
                return;
            }

            // Collect unique, non-null Opportunity Ids from the Flow payload.
            Set<Id> opportunityIds = new Set<Id>();
            for (FlowInput inputRecord : inputs) {
                if (inputRecord != null && inputRecord.opportunityId != null) {
                    opportunityIds.add(inputRecord.opportunityId);
                }
            }

            if (opportunityIds.isEmpty()) {
                Logger.warn(CLASS_NAME + '.syncBULeaders: no valid Opportunity Ids resolved from inputs')
                    .addTag(LOGGER_TAG);
                return;
            }

            Logger.debug(
                CLASS_NAME + '.syncBULeaders: opportunityCount=' + opportunityIds.size()
            )
                .addTag(LOGGER_TAG);

            syncOpportunityTeam(opportunityIds);

            Logger.info(CLASS_NAME + '.syncBULeaders: completed').addTag(LOGGER_TAG);
        } catch (Exception e) {
            Logger.error(CLASS_NAME + '.syncBULeaders', e).addTag(LOGGER_TAG);
        } finally {
            // Persist Nebula Logger records even if processing returned early or threw.
            Logger.saveLog();
        }
    }

    // -------------------------------------------------------------------------
    // Core synchronization
    // -------------------------------------------------------------------------

    /**
     * @description Aligns Opportunity Team Members with the BU Leaders required by
     *              each Opportunity's selected Business Units.
     * @param opportunityIds Opportunities to synchronize.
     */
    private static void syncOpportunityTeam(Set<Id> opportunityIds) {
        List<Opportunity> opportunities =
            OpportunityBULeaderSelector.selectOpportunitiesWithBUField(
                opportunityIds,
                OPPORTUNITY_BU_FIELD
            );

        if (opportunities.isEmpty()) {
            Logger.warn(CLASS_NAME + '.syncOpportunityTeam: no Opportunities found for given Ids')
                .addTag(LOGGER_TAG);
            return;
        }

        Logger.debug(
            CLASS_NAME + '.syncOpportunityTeam: loadedOpportunityCount=' + opportunities.size()
        )
            .addTag(LOGGER_TAG);

        // 1. Load all Business Unit Leader Custom Metadata mappings.
        //    Tests can supply rows because Custom Metadata cannot be inserted in Apex.
        List<Business_Unit_Leader_Mappings__mdt> mappings;
        if (Test.isRunningTest() && testMappings != null) {
            mappings = testMappings;
        } else {
            mappings = OpportunityBULeaderSelector.selectBULeaderMappings();
        }

        if (mappings.isEmpty()) {
            Logger.warn(
                CLASS_NAME + '.syncOpportunityTeam: no BU Leader Mappings custom metadata found'
            )
                .addTag(LOGGER_TAG);
            return;
        }

        // 2. Build Business Unit -> leader username map, and a unique set of all leader names.
        Map<String, Set<String>> buToLeaderNames = new Map<String, Set<String>>();
        Set<String> allLeaderNames = new Set<String>();

        for (Business_Unit_Leader_Mappings__mdt mapping : mappings) {
            String businessUnit = mapping.Business_Unit__c != null
                ? mapping.Business_Unit__c.trim()
                : null;
            String leaderName = mapping.Business_Unit_Leader__c != null
                ? mapping.Business_Unit_Leader__c.trim()
                : null;

            // Skip incomplete metadata rows.
            if (String.isBlank(businessUnit) || String.isBlank(leaderName)) {
                Logger.debug(
                    CLASS_NAME + '.syncOpportunityTeam: skipping incomplete mapping row'
                )
                    .addTag(LOGGER_TAG);
                continue;
            }

            if (!buToLeaderNames.containsKey(businessUnit)) {
                buToLeaderNames.put(businessUnit, new Set<String>());
            }
            buToLeaderNames.get(businessUnit).add(leaderName);

            allLeaderNames.add(leaderName);
        }

        if (allLeaderNames.isEmpty()) {
            Logger.warn(
                CLASS_NAME + '.syncOpportunityTeam: no usable BU Leader names resolved from mappings'
            )
                .addTag(LOGGER_TAG);
            return;
        }

        Logger.debug(
            CLASS_NAME + '.syncOpportunityTeam: mappingCount=' + mappings.size() +
            ', leaderNameCount=' + allLeaderNames.size()
        )
            .addTag(LOGGER_TAG);

        // 3. Resolve leader usernames to active Salesforce User Ids.
        //    Username is the join key because metadata stores the leader as a username.
        Map<String, Set<Id>> leaderNameToUserIds = new Map<String, Set<Id>>();
        Map<Id, String> mappedUserIdToName = new Map<Id, String>();

        for (User usr : OpportunityBULeaderSelector.selectActiveUsersByUsernames(allLeaderNames)) {
            if (!leaderNameToUserIds.containsKey(usr.Username)) {
                leaderNameToUserIds.put(usr.Username, new Set<Id>());
            }
            leaderNameToUserIds.get(usr.Username).add(usr.Id);

            mappedUserIdToName.put(usr.Id, usr.Username);
        }

        for (String leaderName : allLeaderNames) {
            if (!leaderNameToUserIds.containsKey(leaderName)) {
                Logger.warn(
                    CLASS_NAME + '.syncOpportunityTeam: no active User found for username=' +
                    leaderName
                )
                    .addTag(LOGGER_TAG);
            }
        }

        // 4. For each Opportunity, compute the User Ids that should be on the team
        //    based on currently selected Business Units.
        Map<Id, Set<Id>> desiredUsersByOpportunity = new Map<Id, Set<Id>>();

        for (Opportunity opp : opportunities) {
            Set<Id> desiredUserIds = new Set<Id>();
            String selectedBUString = (String) opp.get(OPPORTUNITY_BU_FIELD);

            if (!String.isBlank(selectedBUString)) {
                // Multi-select picklist values are stored as a semicolon-delimited string.
                List<String> selectedBUs = selectedBUString.split(';');

                for (String selectedBU : selectedBUs) {
                    if (selectedBU == null) {
                        continue;
                    }

                    String normalizedBU = selectedBU.trim();
                    if (!buToLeaderNames.containsKey(normalizedBU)) {
                        Logger.debug(
                            CLASS_NAME + '.syncOpportunityTeam: no mapping for Business Unit=' +
                            normalizedBU +
                            ', OpportunityId=' +
                            opp.Id
                        )
                            .addTag(LOGGER_TAG)
                            .setRecord(opp);
                        continue;
                    }

                    Set<String> leaderNames = buToLeaderNames.get(normalizedBU);
                    for (String leaderName : leaderNames) {
                        if (leaderNameToUserIds.containsKey(leaderName)) {
                            desiredUserIds.addAll(leaderNameToUserIds.get(leaderName));
                        }
                    }
                }
            } else {
                Logger.debug(
                    CLASS_NAME + '.syncOpportunityTeam: no Business Units selected OpportunityId=' +
                    opp.Id
                )
                    .addTag(LOGGER_TAG)
                    .setRecord(opp);
            }

            desiredUsersByOpportunity.put(opp.Id, desiredUserIds);
        }

        // 5. Load existing Opportunity Team Members that already have the BU Leader role.
        List<OpportunityTeamMember> existingTeamMembers =
            OpportunityBULeaderSelector.selectBULeaderTeamMembers(
                opportunityIds,
                BU_LEADER_TEAM_ROLE
            );

        Logger.debug(
            CLASS_NAME + '.syncOpportunityTeam: existingBULeaderTeamMemberCount=' +
            existingTeamMembers.size()
        )
            .addTag(LOGGER_TAG);

        // Index existing members by Opportunity Id, then by User Id, for O(1) lookups.
        Map<Id, Map<Id, OpportunityTeamMember>> existingByOpportunity =
            new Map<Id, Map<Id, OpportunityTeamMember>>();

        for (OpportunityTeamMember teamMember : existingTeamMembers) {
            if (!existingByOpportunity.containsKey(teamMember.OpportunityId)) {
                existingByOpportunity.put(
                    teamMember.OpportunityId,
                    new Map<Id, OpportunityTeamMember>()
                );
            }
            existingByOpportunity.get(teamMember.OpportunityId).put(teamMember.UserId, teamMember);
        }

        // 6. Diff desired vs existing members: insert missing, delete leftover BU Leaders.
        List<OpportunityTeamMember> membersToInsert = new List<OpportunityTeamMember>();
        List<OpportunityTeamMember> membersToDelete = new List<OpportunityTeamMember>();

        for (Opportunity opp : opportunities) {
            Set<Id> desiredUserIds = desiredUsersByOpportunity.containsKey(opp.Id)
                ? desiredUsersByOpportunity.get(opp.Id)
                : new Set<Id>();

            Map<Id, OpportunityTeamMember> existingMembers = existingByOpportunity.containsKey(opp.Id)
                ? existingByOpportunity.get(opp.Id)
                : new Map<Id, OpportunityTeamMember>();

            // Create team members for mapped leaders who are not already on the Opportunity.
            for (Id desiredUserId : desiredUserIds) {
                if (!existingMembers.containsKey(desiredUserId)) {
                    membersToInsert.add(
                        new OpportunityTeamMember(
                            OpportunityId = opp.Id,
                            UserId = desiredUserId,
                            TeamMemberRole = BU_LEADER_TEAM_ROLE,
                            OpportunityAccessLevel = 'Edit'
                        )
                    );
                }
            }

            // Remove BU Leader team members whose Business Unit is no longer selected.
            // Other Opportunity Team roles are not queried and are left unchanged.
            for (OpportunityTeamMember existingMember : existingMembers.values()) {
                if (!desiredUserIds.contains(existingMember.UserId)) {
                    membersToDelete.add(existingMember);
                }
            }
        }

        // 7. Perform DML once per list to stay within governor limits.
        Logger.info(
            CLASS_NAME + '.syncOpportunityTeam: insertCount=' + membersToInsert.size() +
            ', deleteCount=' + membersToDelete.size()
        )
            .addTag(LOGGER_TAG);

        if (!membersToInsert.isEmpty()) {
            Database.SaveResult[] insertResults = Database.insert(membersToInsert, false);
            logSaveResults('OpportunityTeamMember', insertResults, membersToInsert);
        } else {
            Logger.debug(CLASS_NAME + '.syncOpportunityTeam: no OpportunityTeamMember records to insert')
                .addTag(LOGGER_TAG);
        }

        if (!membersToDelete.isEmpty()) {
            Database.DeleteResult[] deleteResults = Database.delete(membersToDelete, false);
            logDeleteResults('OpportunityTeamMember', deleteResults, membersToDelete);
        } else {
            Logger.debug(CLASS_NAME + '.syncOpportunityTeam: no OpportunityTeamMember records to delete')
                .addTag(LOGGER_TAG);
        }
    }

    /**
     * @description Logs partial-success insert results for Opportunity Team Members.
     * @param objectName API name of the sObject being inserted.
     * @param saveResults Database insert results.
     * @param records Records that were passed to Database.insert, in the same order as saveResults.
     */
    @TestVisible
    private static void logSaveResults(
        String objectName,
        Database.SaveResult[] saveResults,
        List<OpportunityTeamMember> records
    ) {
        try {
            if (saveResults == null || saveResults.isEmpty()) {
                return;
            }

            Integer successCount = 0;
            Integer failureCount = 0;

            for (Integer index = 0; index < saveResults.size(); index++) {
                Database.SaveResult saveResult = saveResults[index];

                if (saveResult.isSuccess()) {
                    successCount++;
                    continue;
                }

                failureCount++;
                OpportunityTeamMember failedRecord = records != null && index < records.size()
                    ? records[index]
                    : null;

                for (Database.Error error : saveResult.getErrors()) {
                    Logger.error(
                        CLASS_NAME + '.logSaveResults: failed to insert ' +
                        objectName +
                        '. index=' +
                        index +
                        ', OpportunityId=' +
                        (failedRecord != null ? String.valueOf(failedRecord.OpportunityId) : 'null') +
                        ', UserId=' +
                        (failedRecord != null ? String.valueOf(failedRecord.UserId) : 'null') +
                        ', statusCode=' +
                        error.getStatusCode() +
                        ', message=' +
                        error.getMessage()
                    )
                        .addTag(LOGGER_TAG)
                        .setRecord(failedRecord != null ? failedRecord.OpportunityId : null);
                }
            }

            Logger.debug(
                CLASS_NAME + '.logSaveResults: objectName=' +
                objectName +
                ', successCount=' +
                successCount +
                ', failureCount=' +
                failureCount
            )
                .addTag(LOGGER_TAG);
        } catch (Exception e) {
            Logger.error(CLASS_NAME + '.logSaveResults', e).addTag(LOGGER_TAG);
        }
    }

    /**
     * @description Logs partial-success delete results for Opportunity Team Members.
     * @param objectName API name of the sObject being deleted.
     * @param deleteResults Database delete results.
     * @param records Records that were passed to Database.delete, in the same order as deleteResults.
     */
    @TestVisible
    private static void logDeleteResults(
        String objectName,
        Database.DeleteResult[] deleteResults,
        List<OpportunityTeamMember> records
    ) {
        try {
            if (deleteResults == null || deleteResults.isEmpty()) {
                return;
            }

            Integer successCount = 0;
            Integer failureCount = 0;

            for (Integer index = 0; index < deleteResults.size(); index++) {
                Database.DeleteResult deleteResult = deleteResults[index];

                if (deleteResult.isSuccess()) {
                    successCount++;
                    continue;
                }

                failureCount++;
                OpportunityTeamMember failedRecord = records != null && index < records.size()
                    ? records[index]
                    : null;

                for (Database.Error error : deleteResult.getErrors()) {
                    Logger.error(
                        CLASS_NAME + '.logDeleteResults: failed to delete ' +
                        objectName +
                        '. index=' +
                        index +
                        ', OpportunityId=' +
                        (failedRecord != null ? String.valueOf(failedRecord.OpportunityId) : 'null') +
                        ', UserId=' +
                        (failedRecord != null ? String.valueOf(failedRecord.UserId) : 'null') +
                        ', statusCode=' +
                        error.getStatusCode() +
                        ', message=' +
                        error.getMessage()
                    )
                        .addTag(LOGGER_TAG)
                        .setRecord(failedRecord != null ? failedRecord.OpportunityId : null);
                }
            }

            Logger.debug(
                CLASS_NAME + '.logDeleteResults: objectName=' +
                objectName +
                ', successCount=' +
                successCount +
                ', failureCount=' +
                failureCount
            )
                .addTag(LOGGER_TAG);
        } catch (Exception e) {
            Logger.error(CLASS_NAME + '.logDeleteResults', e).addTag(LOGGER_TAG);
        }
    }
}