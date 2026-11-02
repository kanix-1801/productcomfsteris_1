/**
 * @author      : Vinay
 * @date        : 2026-06-30
 * @story       : GC 2641
 * @description : Service class responsible for adding Sales Ops / Contracting
 *                Opportunity Team Members to eligible Instrument Processing
 *                Opportunities.
 *
 *                This service is invoked from OpportunityTriggerHandller after update.
 *
 *                Business Rules:
 *                1. Runs only when Opportunity Stage changes to Proposal.
 *                2. Applies only to Opportunity Record Type InstrumentProcessing.
 *                3. Excludes Opportunities where IP_Pillar__c = Mobile.
 *                4. Retrieves active users from public group
 *                   HC_Sales_IP_Opportunity_Sales_Ops_Cntrct.
 *                5. Supports nested public groups.
 *                6. Prevents duplicate Opportunity Team Member creation.
 *                7. Adds users with Team Member Role = Sales Ops / Contracting
 *                   and Opportunity Access Level = Edit.
 */
public inherited sharing class OpportunityTeamService {

    private static final String TARGET_STAGE = 'Proposal';
    private static final String TARGET_RECORD_TYPE = 'InstrumentProcessing';
    private static final String EXCLUDED_IP_PILLAR = 'Mobile';

    private static final String TEAM_MEMBER_ROLE = 'Sales Ops / Contracting';
    private static final String OPPORTUNITY_ACCESS_LEVEL = 'Edit';
    private static final String CUSTOM_NOTIFICATION_TYPE_DEVELOPER_NAME = 'Opportunity_Team_Member_Added';
    
    @TestVisible
    private static String publicGroupDeveloperName = 'HC_Sales_IP_Opportunity_Sales_Ops_Cntrct';    
    
    @TestVisible
    private static Boolean sendNotifications = true;    
	private static final String SCENARIO = 'Adding Sales Ops / Contracting Opportunity Team Members';
    /**
     *Adds active Sales Ops / Contracting public group users
     *              to Opportunity Team Member records when eligible
     *              Opportunities are updated to Proposal stage.
     *
     * @param newOpportunities List of Opportunities from Trigger.new.
     * @param oldOpportunityMap Map of old Opportunity values from Trigger.oldMap.
     */
    public static void addSalesOpsContractTeamMembers(
        List<Opportunity> newOpportunities,
        Map<Id, Opportunity> oldOpportunityMap
    ) {
        if ( newOpportunities == null ||
            newOpportunities.isEmpty() ||
            oldOpportunityMap == null
        ) { return;
        }

        Id instrumentProcessingRecordTypeId = Schema.SObjectType.Opportunity.getRecordTypeInfosByDeveloperName().get(TARGET_RECORD_TYPE).getRecordTypeId();

        Set<Id> eligibleOpportunityIds = new Set<Id>();

        for (Opportunity newOpp : newOpportunities) {
            Opportunity oldOpp = oldOpportunityMap.get(newOpp.Id);

            if (oldOpp == null) { continue;
            }

            Boolean stageChangedToProposal = newOpp.StageName == TARGET_STAGE && oldOpp.StageName != TARGET_STAGE;
            Boolean isInstrumentProcessing = newOpp.RecordTypeId == instrumentProcessingRecordTypeId;
            Boolean isNotMobile = newOpp.IP_Pillar__c != EXCLUDED_IP_PILLAR;

            if ( stageChangedToProposal && isInstrumentProcessing && isNotMobile) {
                eligibleOpportunityIds.add(newOpp.Id);
            }
        }

        if (eligibleOpportunityIds.isEmpty()) { return;
        }

        Set<Id> publicGroupUserIds = getUserIdsFromPublicGroup(
            publicGroupDeveloperName
        );

        if (publicGroupUserIds.isEmpty()) { return;
        }

        Set<Id> activeUserIds = new Set<Id>();

        for (User userRecord : UserSelector.getActiveUsersByIds(publicGroupUserIds)) {
            activeUserIds.add(userRecord.Id);
        }

        if (activeUserIds.isEmpty()) { return;
        }

        Set<String> existingTeamMemberKeys = new Set<String>();

        for (
            OpportunityTeamMember existingMember : TeamMemberSelector.getOpportunityTeamMembersByOpportunityIdsAndUserIds(
                eligibleOpportunityIds,
                activeUserIds
            )
        ) {
            existingTeamMemberKeys.add( existingMember.OpportunityId + '-' + existingMember.UserId );
        }

        List<OpportunityTeamMember> membersToInsert = new List<OpportunityTeamMember>();

        for (Id opportunityId : eligibleOpportunityIds) {
            for (Id userId : activeUserIds) {
                String uniqueKey = opportunityId + '-' + userId;

                if (existingTeamMemberKeys.contains(uniqueKey)) {
                    continue;
                }

                membersToInsert.add(new OpportunityTeamMember(
                    OpportunityId = opportunityId,
                    UserId = userId,
                    TeamMemberRole = TEAM_MEMBER_ROLE,
                    OpportunityAccessLevel = OPPORTUNITY_ACCESS_LEVEL
                ));
            }
        }

        if (!membersToInsert.isEmpty()) {
            insert membersToInsert;
            if (sendNotifications) { 
                notifyAddedTeamMembers(membersToInsert);
            }
        }
    }

    /**
     *Resolves all User Ids from the configured public group.
     *              This method also supports nested public groups by recursively
     *              processing GroupMember records where UserOrGroupId points
     *              to another Group.
     *
     * @param groupDeveloperName DeveloperName of the parent public group.
     * @return Set of User Ids found in the public group and nested groups.
     */
    private static Set<Id> getUserIdsFromPublicGroup(String groupDeveloperName) {
        Set<Id> userIds = new Set<Id>();

        Group parentGroup = TeamMemberSelector.getPublicGroupByDeveloperName(groupDeveloperName);

        if (parentGroup == null) { return userIds;
        }

        Set<Id> groupIdsToProcess = new Set<Id>{ parentGroup.Id };
        Set<Id> processedGroupIds = new Set<Id>();

        while (!groupIdsToProcess.isEmpty()) {
            Set<Id> currentGroupIds = new Set<Id>(groupIdsToProcess);
            groupIdsToProcess.clear();
            processedGroupIds.addAll(currentGroupIds);

            List<GroupMember> groupMembers =
                TeamMemberSelector.getGroupMembersByGroupIds(currentGroupIds);

            for (GroupMember groupMember : groupMembers) {
                String userOrGroupId = String.valueOf(groupMember.UserOrGroupId);

                if (userOrGroupId.startsWith('005')) {
                    userIds.add(groupMember.UserOrGroupId);
                } else if (
                    userOrGroupId.startsWith('00G') &&
                    !processedGroupIds.contains(groupMember.UserOrGroupId)
                ) {
                    groupIdsToProcess.add(groupMember.UserOrGroupId);
                }
            }
        }

        return userIds;
    }
    /**
     * Sends custom notifications to users added to Opportunity Team.
     */
    private static void notifyAddedTeamMembers(
    List<OpportunityTeamMember> insertedTeamMembers
    ) {
        if (insertedTeamMembers == null || insertedTeamMembers.isEmpty()) {
            return;
        }
    
        Boolean shouldSaveLog = false;
    
        try {
            CustomNotificationType notificationType = TeamMemberSelector.getCustomNotificationTypeByDeveloperName(
                CUSTOM_NOTIFICATION_TYPE_DEVELOPER_NAME
                );
    
            if (notificationType == null) {
                return;
            }
    
            for (OpportunityTeamMember teamMember : insertedTeamMembers) {
                Messaging.CustomNotification notification =
                    new Messaging.CustomNotification();
    
                notification.setTitle(System.Label.OpportunityTeamNotificationTitle);
                notification.setBody( System.Label.OpportunityTeamNotificationBody);
                notification.setNotificationTypeId(notificationType.Id);
                notification.setTargetId(teamMember.OpportunityId);
    
                notification.send(
                    new Set<String>{ String.valueOf(teamMember.UserId) }
                );
            }
        } catch (Exception exceptionRecord) {
            shouldSaveLog = true;
    
            Logger.setScenario(SCENARIO);
    
            Logger.error( 'Failed to send Opportunity Team Member notification. Error: '+ exceptionRecord.getMessage())
            .addTag('Opportunity')
            .addTag('Opportunity Team')
            .setRecord(
                new Opportunity( Id = insertedTeamMembers[0].OpportunityId)
            );
    
        } finally {
            if (shouldSaveLog) {
                Logger.saveLog();
            }
        }
    }
}