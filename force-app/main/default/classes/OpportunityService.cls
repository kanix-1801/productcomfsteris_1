/**
 * @author Akash Dahinde
 * @date 06-03-2026
 * @description Opportunity service for duplicate detection (GC-2643), closure validation (GC-3188),
 *              and Sales Ops team member assignment (GC-2641).
 */
public inherited sharing class OpportunityService {

    private static final String CLASS_NAME = 'OpportunityService';
    private static Set<String> duplicateKeyRecordTypeNames;
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
     * @description GC-2643 - Builds Duplicate_Match_Key__c and Territory_ID__c from TAS Address Id
     *              (Account.OracleAddressId__c), PrimaryContact__c, Type, and TerritoryID__c.
     *              Applies to Opportunity record types configured in custom label
     *              Opportunity_Duplicate_Key_Record_Types.
     *              Regenerates the key on update when AccountId, PrimaryContact__c, or Type changes.
     *
     * @param opportunities Opportunity records from Trigger.new.
     * @param oldMap Opportunity records from Trigger.oldMap; pass null during insert.
     */
    public static void populateDuplicateMatchKey(
        List<Opportunity> opportunities,
        Map<Id, Opportunity> oldMap
    ) {
        try {
            Logger.debug(CLASS_NAME + '.populateDuplicateMatchKey: started');

            if (opportunities == null || opportunities.isEmpty()) {
                return;
            }

            List<Opportunity> oppsToProcess = filterOpportunitiesForDuplicateKey(
                opportunities,
                oldMap
            );

            if (oppsToProcess.isEmpty()) {
                Logger.debug(CLASS_NAME + '.populateDuplicateMatchKey: no relevant field changes');
                return;
            }

            Map<Id, String> accountIdToOracleAddressId =
                loadOracleAddressIdsForOpportunities(oppsToProcess);
            Set<String> tasAddressIdSet = new Set<String>();

            for (Opportunity opp : oppsToProcess) {
                String tasAddressId = resolveOpportunityTasAddressId(opp, accountIdToOracleAddressId);

                if (String.isNotBlank(tasAddressId)) {
                    tasAddressIdSet.add(tasAddressId);
                }
            }

            Map<String, String> tasAddressIdToTerritoryId =
                getTerritoryIdsByTasAddressId(new List<String>(tasAddressIdSet));

            for (Opportunity opp : oppsToProcess) {
                String tasAddressId = resolveOpportunityTasAddressId(opp, accountIdToOracleAddressId);
                String territoryId = tasAddressIdToTerritoryId.get(tasAddressId);

                opp.Territory_ID__c = territoryId;
                opp.Duplicate_Match_Key__c = buildDuplicateMatchKey(
                    opp,
                    tasAddressId,
                    territoryId
                );
            }

            Logger.debug(CLASS_NAME + '.populateDuplicateMatchKey: completed');
        } catch (Exception e) {
            Logger.error(CLASS_NAME + '.populateDuplicateMatchKey', e);
            throw e;
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description GC-2643 - Returns Opportunities requiring duplicate match key evaluation.
     *              Only record types listed in custom label Opportunity_Duplicate_Key_Record_Types are processed.
     *              All eligible inserts are processed; updates only when AccountId, PrimaryContact__c, or Type changes.
     *
     * @param opportunities Opportunity records from Trigger.new.
     * @param oldMap Opportunity records from Trigger.oldMap; null during insert.
     * @return Filtered list of Opportunities to process.
     */
    private static List<Opportunity> filterOpportunitiesForDuplicateKey(
        List<Opportunity> opportunities,
        Map<Id, Opportunity> oldMap
    ) {
        List<Opportunity> oppsToProcess = new List<Opportunity>();
        Map<Id, Schema.RecordTypeInfo> recordTypesById =
            Schema.SObjectType.Opportunity.getRecordTypeInfosById();

        if (duplicateKeyRecordTypeNames == null) {
            duplicateKeyRecordTypeNames = new Set<String>();
            String recordTypeNames = Label.Opportunity_Duplicate_Key_Record_Types;

            if (String.isNotBlank(recordTypeNames)) {
                for (String name : recordTypeNames.split(',')) {
                    duplicateKeyRecordTypeNames.add(name.trim());
                }
            }
        }

        for (Opportunity opp : opportunities) {
            Schema.RecordTypeInfo recordTypeInfo = recordTypesById.get(opp.RecordTypeId);

            if (
                recordTypeInfo == null ||
                !duplicateKeyRecordTypeNames.contains(recordTypeInfo.getDeveloperName())
            ) {
                continue;
            }

            if (oldMap == null) {
                oppsToProcess.add(opp);
                continue;
            }

            Opportunity oldOpp = oldMap.get(opp.Id);

            if (
                oldOpp != null &&
                (
                    opp.AccountId != oldOpp.AccountId ||
                    opp.PrimaryContact__c != oldOpp.PrimaryContact__c ||
                    opp.Type != oldOpp.Type
                )
            ) {
                oppsToProcess.add(opp);
            }
        }

        return oppsToProcess;
    }

    /**
     * @description GC-2643 - Resolves TAS Address Id from the related Account for duplicate matching.
     *
     * @param opp Opportunity row being processed.
     * @param accountIdToOracleAddressId Account Id to OracleAddressId__c map from AccountSelector.
     * @return Normalized TAS Address Id or null when not resolved.
     */
    private static String resolveOpportunityTasAddressId(
        Opportunity opp,
        Map<Id, String> accountIdToOracleAddressId
    ) {
        if (opp == null || opp.AccountId == null || accountIdToOracleAddressId == null) {
            return null;
        }

        return normalize(accountIdToOracleAddressId.get(opp.AccountId));
    }

    /**
     * @description GC-2643 - Loads Account Oracle Address Ids needed for duplicate key resolution.
     *
     * @param opportunities Opportunity rows requiring TAS Address Id resolution.
     * @return Map of Account Id to OracleAddressId__c.
     */
    private static Map<Id, String> loadOracleAddressIdsForOpportunities(
        List<Opportunity> opportunities
    ) {
        Set<Id> accountIds = new Set<Id>();

        if (opportunities == null || opportunities.isEmpty()) {
            return new Map<Id, String>();
        }

        for (Opportunity opp : opportunities) {
            if (opp.AccountId != null) {
                accountIds.add(opp.AccountId);
            }
        }

        Map<Id, String> accountIdToOracleAddressId = new Map<Id, String>();

        if (accountIds.isEmpty()) {
            return accountIdToOracleAddressId;
        }

        for (Account accountRecord : AccountSelector.selectOracleAddressIdByAccountIds(accountIds)) {
            String oracleAddressId = normalize(accountRecord.OracleAddressId__c);

            if (String.isNotBlank(oracleAddressId)) {
                accountIdToOracleAddressId.put(accountRecord.Id, oracleAddressId);
            }
        }

        Logger.debug(
            CLASS_NAME + '.loadOracleAddressIdsForOpportunities: mappedAccountCount=' +
            accountIdToOracleAddressId.size()
        );

        return accountIdToOracleAddressId;
    }

    /**
     * @description GC-2643 - Resolves Territory Id from OrderLineContact__c by TAS Address Id.
     *
     * @param tasAddressIds TAS Address Id values from related Accounts.
     * @return Map of TASAddressId__c to TerritoryID__c.
     */
    private static Map<String, String> getTerritoryIdsByTasAddressId(
        List<String> tasAddressIds
    ) {
        Map<String, String> tasAddressIdToTerritoryId = new Map<String, String>();

        if (tasAddressIds == null || tasAddressIds.isEmpty()) {
            return tasAddressIdToTerritoryId;
        }

        Set<String> normalizedTasAddressIds = new Set<String>();

        for (String tasAddressId : tasAddressIds) {
            String normalizedTasAddressId = normalize(tasAddressId);

            if (String.isNotBlank(normalizedTasAddressId)) {
                normalizedTasAddressIds.add(normalizedTasAddressId);
            }
        }

        if (normalizedTasAddressIds.isEmpty()) {
            return tasAddressIdToTerritoryId;
        }

        for (OrderLineContact__c olc : [
            SELECT TASAddressId__c,
                   TerritoryID__c
            FROM OrderLineContact__c
            WHERE TASAddressId__c IN :normalizedTasAddressIds
              AND TerritoryID__c != null
            ORDER BY TerritoryID__c ASC
        ]) {
            String tasAddressId = normalize(olc.TASAddressId__c);

            if (
                String.isNotBlank(tasAddressId) &&
                String.isNotBlank(olc.TerritoryID__c) &&
                !tasAddressIdToTerritoryId.containsKey(tasAddressId)
            ) {
                tasAddressIdToTerritoryId.put(
                    tasAddressId,
                    normalize(olc.TerritoryID__c)
                );
            }
        }

        Logger.debug(
            CLASS_NAME + '.getTerritoryIdsByTasAddressId: mappedTerritoryCount=' +
            tasAddressIdToTerritoryId.size()
        );

        return tasAddressIdToTerritoryId;
    }

    /**
     * @description GC-2643 - Builds the composite duplicate match key from Address, Primary Contact,
     *              Opportunity Type, and Territory.
     *
     * @param opp Opportunity record.
     * @param tasAddressId TAS Address Id for the Opportunity.
     * @param territoryId Territory Id resolved from OrderLineContact__c.
     * @return Duplicate match key when all required values are available; otherwise null.
     */
    private static String buildDuplicateMatchKey(
        Opportunity opp,
        String tasAddressId,
        String territoryId
    ) {
        if (
            opp == null ||
            String.isBlank(tasAddressId) ||
            opp.PrimaryContact__c == null ||
            String.isBlank(opp.Type) ||
            String.isBlank(territoryId)
        ) {
            return null;
        }

        return normalizeDuplicateKey(
            tasAddressId +
            String.valueOf(opp.PrimaryContact__c) +
            opp.Type +
            territoryId
        );
    }

    /**
     * @description GC-2643 - Normalizes the duplicate match key to a lowercase trimmed value.
     * @param value Input value.
     * @return Lowercase trimmed value, or null when blank.
     */
    private static String normalizeDuplicateKey(String value) {
        return String.isBlank(value) ? null : value.trim().toLowerCase();
    }

    /**
     * @description GC-2643 - Trims input values and converts blank strings to null.
     * @param value Input string
     * @return Trimmed value or null
     */
    private static String normalize(String value) {
        return String.isBlank(value) ? null : value.trim();
    }

    /**
     * Blocks closure of Opportunities transitioning to Closed Won
     * when any associated Forecast Eligible Quote is not yet Closed.
     * GC-3188
     *
     * @param newOpportunities Trigger.new Opportunity list.
     * @param oldOpportunityMap Trigger.oldMap of prior Opportunity values.
     */
    public static void validateForecastEligibleQuoteClosure(
        List<Opportunity> newOpportunities,
        Map<Id, Opportunity> oldOpportunityMap
    ) {
        Id healthcareSalesRtId = Schema.SObjectType.Opportunity.getRecordTypeInfosByDeveloperName().get('Healthcare_Sales').getRecordTypeId();
       
        Set<Id> recordTypeIds = new Set<Id>{healthcareSalesRtId};
        try {
            if (newOpportunities == null || newOpportunities.isEmpty() || oldOpportunityMap == null) {
                return;
            }

            Set<Id> closingOpportunityIds = new Set<Id>();

            for (Opportunity opp : newOpportunities) {
                Opportunity oldOpp = oldOpportunityMap.get(opp.Id);

                if (oldOpp == null) {
                    continue;
                }

                if (
                    opp.IsClosed &&
                    !oldOpp.IsClosed &&
                    opp.IsWon == true &&
                    recordTypeIds.contains(opp.RecordtypeId)
                ) {
                    closingOpportunityIds.add(opp.Id);
                }
            }

            if (closingOpportunityIds.isEmpty()) {
                return;
            }

            List<Quote> openForecastEligibleQuotes =
                QuoteSelector.selectOpenForecastEligibleQuotesByOpportunityIds(closingOpportunityIds);

            Set<Id> opportunityIdsWithOpenQuotes = new Set<Id>();
            for (Quote q : openForecastEligibleQuotes) {
                opportunityIdsWithOpenQuotes.add(q.OpportunityId);
            }

            if (opportunityIdsWithOpenQuotes.isEmpty()) {
                return;
            }

            for (Opportunity opp : newOpportunities) {
                if (opportunityIdsWithOpenQuotes.contains(opp.Id)) {
                    opp.addError(Label.Opp_Closure_Blocked_Forecast_Eligible_Quotes);

                    Logger.info(
                        CLASS_NAME + '.validateForecastEligibleQuoteClosure: blocked closure OpportunityId=' +
                        opp.Id
                    )
                        .addTag('Opportunity')
                        .setRecord(opp);
                }
            }

        } catch (Exception e) {
            Logger.error(CLASS_NAME + '.validateForecastEligibleQuoteClosure', e);
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description Stages the forecast confidence propagation banner when Opportunity Forecast Confidence changes
     *              and applicable associated quotes exist.
     * @param newOpportunities Trigger.new Opportunity rows.
     * @param oldOpportunityMap Trigger.oldMap Opportunity rows.
     */
    public static void stageForecastConfidencePropagateBanner(
        List<Opportunity> newOpportunities,
        Map<Id, Opportunity> oldOpportunityMap
    ) {
        OppForecastConfPropagateService.stagePropagateBanner(
            newOpportunities,
            oldOpportunityMap
        );
    }

    /**
     * @description Stages the Closed Lost quote closure banner when an Opportunity moves to Closed Lost.
     * @param newOpportunities Trigger.new Opportunity rows.
     * @param oldOpportunityMap Trigger.oldMap Opportunity rows.
     */
    public static void stageClosedLostQuoteClosureBanner(
        List<Opportunity> newOpportunities,
        Map<Id, Opportunity> oldOpportunityMap
    ) {
        OppClosedLostQuoteService.stageClosedLostQuoteBanner(
            newOpportunities,
            oldOpportunityMap
        );
    }

    /**
     * Adds active Sales Ops / Contracting public group users
     * to Opportunity Team Member records when eligible
     * Opportunities are updated to Proposal stage.
     * GC-2641
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

   private static void notifyAddedTeamMembers(
        List<OpportunityTeamMember> insertedTeamMemberList
    ) {
        if (insertedTeamMemberList == null || insertedTeamMemberList.isEmpty()) {
            return;
        }
    
        Boolean shouldSaveLog = false;
        try {
            CustomNotificationType notificationType =
                TeamMemberSelector.getCustomNotificationTypeByDeveloperName(
                    CUSTOM_NOTIFICATION_TYPE_DEVELOPER_NAME
                );
            if (notificationType == null) {
                return;
            }
    
            // Collect recipient UserIds per Opportunity (the notification target)
            Map<Id, Set<String>> recipientIdSetByOpportunityId = new Map<Id, Set<String>>();
            for (OpportunityTeamMember teamMember : insertedTeamMemberList) {
                if (teamMember.OpportunityId == null || teamMember.UserId == null) {
                    continue;
                }
                if (!recipientIdSetByOpportunityId.containsKey(teamMember.OpportunityId)) {
                    recipientIdSetByOpportunityId.put(
                        teamMember.OpportunityId, new Set<String>()
                    );
                }
                recipientIdSetByOpportunityId.get(teamMember.OpportunityId)
                    .add(String.valueOf(teamMember.UserId));
            }
    
            // One send per Opportunity target, fanning out to all its new members
            for (Id opportunityId : recipientIdSetByOpportunityId.keySet()) {
                try {
                    Messaging.CustomNotification notification =
                        new Messaging.CustomNotification();
                    notification.setTitle(System.Label.OpportunityTeamNotificationTitle);
                    notification.setBody(System.Label.OpportunityTeamNotificationBody);
                    notification.setNotificationTypeId(notificationType.Id);
                    notification.setTargetId(opportunityId);
                    notification.send(recipientIdSetByOpportunityId.get(opportunityId));
                } catch (Exception sendException) {
                    shouldSaveLog = true;
                    Logger.setScenario(SCENARIO);
                    Logger.error(
                        'Failed to send Opportunity Team Member notification for OpportunityId=' +
                        opportunityId,
                        sendException
                    )
                    .addTag('Opportunity')
                    .addTag('Opportunity Team')
                    .setRecord(new Opportunity(Id = opportunityId));
                }
            }
        } catch (Exception exceptionRecord) {
            shouldSaveLog = true;
            Logger.setScenario(SCENARIO);
            Logger.error(
                'Failed to prepare Opportunity Team Member notifications. Error: ' +
                exceptionRecord.getMessage()
            )
            .addTag('Opportunity')
            .addTag('Opportunity Team');
        } finally {
            if (shouldSaveLog) {
                Logger.saveLog();
            }
        }
    }
}