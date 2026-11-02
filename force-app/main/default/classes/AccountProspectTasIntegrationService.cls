/**
 * @author Abhishek Mishra
 * @date 04-06-2026
 * @description Service class responsible for processing TAS integration response
 *              for Prospect Accounts. This class performs TAS callouts via SO_Callout
 *              framework, creates Account Team Members, and creates Order Line Contact records.
 *              and — per GC-3143 — classifies each Account into a three-way outcome:
 *                  Assigned            -> territory returned and Account Team Member inserted
 *                  Assignment Missing  -> callout succeeded but no ATM inserted (AC2 -> Sales Ops)
 *                  Technical Failure   -> callout failed / unparseable (AC3 -> IT track)
 *
 * Layering:
 *   AccountProspectTasQueueable -> AccountProspectTasIntegrationService
 *     -> TasAssignmentGateway -> SO_Callout -> SO_ProviderFactory -> Boomi TAS
  */
public without sharing class AccountProspectTasIntegrationService {

    private static final String CLASS_NAME = 'AccountProspectTasIntegrationService';

    private static final String TEAM_MEMBER_ROLE = 'Sales';
    private static final String TEAM_MEMBER_ASSIGNMENT_TYPE = 'Oracle Assigned';
    private static final String ACCOUNT_ACCESS_LEVEL = 'Edit';

    // GC-3143 start
    public static final String TAS_STATUS_ASSIGNED = 'Assigned';
    public static final String TAS_STATUS_ASSIGNMENT_MISSING = 'Assignment Missing';
    public static final String TAS_STATUS_TECHNICAL_FAILURE = 'Technical Failure';

    private static final String SALES_OPS_QUEUE_DEV_NAME = 'SalesOpsQueue';
    private static final String TAS_NOTIFICATION_TYPE_DEV_NAME = 'TAS_Assignment_Failure';
    // GC-3143 end

    /**
     * @description Processes Prospect Accounts for TAS assignment.
     *              Performs one TAS callout per Account and classifies the outcome.
     *
     * @param accounts List of Accounts to process.
     */
    public static void processAccounts(List<Account> accounts) {
        try {
            Logger.info(CLASS_NAME + '.processAccounts: started');

            if (accounts == null || accounts.isEmpty()) {
                Logger.warn(CLASS_NAME + '.processAccounts: no accounts to process');
                return;
            }

            Logger.info(
                CLASS_NAME + '.processAccounts: accountCount=' + accounts.size()
            );

            List<TasTerritoryItem> allResponseItems = new List<TasTerritoryItem>();

            // GC-3091 start
            Map<Id, Boolean> tasAssignmentStatusByAccountId = new Map<Id, Boolean>();
            // GC-3091 end

            // GC-3143 start — per-Account three-way outcome
            Map<Id, String> tasStatusByAccountId = new Map<Id, String>();
            // GC-3143 end

            for (Account acc : accounts) {
                if (acc == null || acc.Id == null) {
                    Logger.warn(CLASS_NAME + '.processAccounts: skipping null Account or Account Id');
                    continue;
                }

                // GC-3091 start
                tasAssignmentStatusByAccountId.put(acc.Id, false);
                // GC-3091 end

                // GC-3143 start — pessimistic default: anything unexpected is a technical failure
                tasStatusByAccountId.put(acc.Id, TAS_STATUS_TECHNICAL_FAILURE);
                // GC-3143 end

                try {
                    TasAssignmentRequest requestBody =
                        TasAssignmentRequest.fromAccount(acc);

                    TasAssignmentGateway.CalloutResult calloutResult =
                        TasAssignmentGateway.sendAssignmentRequest(requestBody);

                    if (!calloutResult.calloutSuccess) {
                        Logger.error( // changed to error as per nebula logger GC 3160
                            CLASS_NAME + '.processAccounts: TAS callout failed AccountId=' +
                            acc.Id +
                            ', detail=' +
                            calloutResult.errorDetail
                        )
                        .addTag('Account')
                        .setRecord(acc);
                        continue;
                    }

                    TasAssignmentResponse parsedResponse = calloutResult.parsedResponse;

                    if (
                        parsedResponse == null ||
                        parsedResponse.territoryData == null ||
                        parsedResponse.territoryData.isEmpty()
                    ) {
                        // GC-3143 start — AC2: success but no territory returned -> Sales Ops
                        tasStatusByAccountId.put(acc.Id, TAS_STATUS_ASSIGNMENT_MISSING);
                        // GC-3143 end
                        Logger.warn( // verified as per nebula logger GC 3160
                            CLASS_NAME + '.processAccounts: no TAS territory data returned AccountId=' +
                            acc.Id
                        );
                        continue;
                    }

                    for (TasTerritoryItem item : parsedResponse.territoryData) {
                        item.accountId = acc.Id;
                        allResponseItems.add(item);
                    }

                    // GC-3091 start
                    tasAssignmentStatusByAccountId.put(acc.Id, true);
                    // GC-3091 end

                    // GC-3143 — callout succeeded with territory; finalize after ATM insert
                    tasStatusByAccountId.put(acc.Id, TAS_STATUS_ASSIGNMENT_MISSING);

                    Logger.info(
                        CLASS_NAME + '.processAccounts: territory data received AccountId=' +
                        acc.Id +
                        ', territoryCount=' +
                        parsedResponse.territoryData.size()
                    );

                } catch (Exception accountException) {
                    Logger.error(
                        CLASS_NAME + '.processAccounts: failed processing AccountId=' + acc.Id,
                        accountException
                    );
                }
            }

            // GC-3143 — capture which accounts actually received a team member
            Set<Id> assignedAccountIds = new Set<Id>();

            if (!allResponseItems.isEmpty()) {
                insertTasAssignments(allResponseItems);
                assignedAccountIds = insertAccountTeamMembers(allResponseItems);
            } else {
                Logger.info(
                    CLASS_NAME + '.processAccounts: no TAS response items to process'
                );
            }

            // GC-3143 start — finalize status from the ATM outcome
            Integer assignedCount = 0;
            Integer assignmentMissingCount = 0;
            Integer technicalFailureCount = 0;

            for (Id accId : new Set<Id>(tasStatusByAccountId.keySet())) {
                if (tasStatusByAccountId.get(accId) == TAS_STATUS_TECHNICAL_FAILURE) {
                    technicalFailureCount++;
                    continue;
                }

                String finalizedStatus = assignedAccountIds.contains(accId)
                    ? TAS_STATUS_ASSIGNED
                    : TAS_STATUS_ASSIGNMENT_MISSING;
                tasStatusByAccountId.put(accId, finalizedStatus);

                if (finalizedStatus == TAS_STATUS_ASSIGNED) {
                    assignedCount++;
                } else {
                    assignmentMissingCount++;
                }
            }

            Logger.info(
                CLASS_NAME + '.processAccounts: outcome summary assigned=' +
                assignedCount +
                ', assignmentMissing=' +
                assignmentMissingCount +
                ', technicalFailure=' +
                technicalFailureCount
            );
            // GC-3143 end

            // GC-3091 start
            updateTasRetryAssignmentFlag(tasAssignmentStatusByAccountId);
            // GC-3091 end

            // GC-3143 start — write status, create Task, notify Sales Ops
            applyTasOutcome(tasStatusByAccountId);
            // GC-3143 end

            Logger.info(
                CLASS_NAME + '.processAccounts: completed responseItemCount=' +
                allResponseItems.size()
            );

        } catch (Exception e) {
            Logger.error(CLASS_NAME + '.processAccounts', e);
        } finally {
            Logger.saveLog();
        }
    }

    // GC-3143 start
    /**
     * @author vinay
     * @description Applies the classified TAS outcome per Account (picklist + Sales Ops):
     *              writes TAS_Assignment_Status__c, creates the Sales Ops Task + bell
     *              notification for Assignment Missing.
     *              TAS_Retry__c is handled separately by updateTasRetryAssignmentFlag (GC-3091).
     * @param statusByAccountId Map of Account Id to outcome status.
     */
    public static void applyTasOutcome(Map<Id, String> statusByAccountId) {
        try {
            if (statusByAccountId == null || statusByAccountId.isEmpty()) {
                Logger.debug(CLASS_NAME + '.applyTasOutcome: no statuses to apply');
                return;
            }

            List<Account> accountsToUpdate = new List<Account>();
            Set<Id> assignmentMissingIds = new Set<Id>();
            Set<Id> assignedIds = new Set<Id>();
            Set<Id> technicalFailureIds = new Set<Id>();

            for (Id accId : statusByAccountId.keySet()) {
                if (accId == null) {
                    continue;
                }

                String status = statusByAccountId.get(accId);

                accountsToUpdate.add(new Account(
                    Id = accId,
                    TAS_Assignment_Status__c = status
                ));

                if (status == TAS_STATUS_ASSIGNMENT_MISSING) {
                    assignmentMissingIds.add(accId);
                } else if (status == TAS_STATUS_ASSIGNED) {
                    assignedIds.add(accId);
                } else if (status == TAS_STATUS_TECHNICAL_FAILURE) {
                    technicalFailureIds.add(accId);
                }
            }

            Logger.info(
                CLASS_NAME + '.applyTasOutcome: applying statuses accountCount=' +
                accountsToUpdate.size() +
                ', assigned=' +
                assignedIds.size() +
                ', assignmentMissing=' +
                assignmentMissingIds.size() +
                ', technicalFailure=' +
                technicalFailureIds.size()
            );

            if (!accountsToUpdate.isEmpty()) {
                logSaveResults(
                    'Account TAS_Assignment_Status__c update',
                    Database.update(accountsToUpdate, false)
                );
            }

            if (!assignmentMissingIds.isEmpty()) {
                createSalesOpsTasks(assignmentMissingIds);
                notifySalesOps(assignmentMissingIds);
            }

        } catch (Exception e) {
            Logger.error(CLASS_NAME + '.applyTasOutcome', e);
        }
    }

    /**
     * @author vinay
     * @description Creates a Task owned by SalesOpsQueue for each Assignment-Missing Account.
     *              Dedupes against existing open TAS Tasks so a repeat failure won't stack. (AC4)
     * @param accountIds Accounts classified as Assignment Missing.
     */
    @TestVisible
    private static void createSalesOpsTasks(Set<Id> accountIds) {
        Id queueId = TeamMemberSelector.getQueueIdByDeveloperName(SALES_OPS_QUEUE_DEV_NAME);
        if (queueId == null) {
            Logger.warn(CLASS_NAME + '.createSalesOpsTasks: SalesOpsQueue not found');
            return;
        }

        Map<Id, Account> accById = new Map<Id, Account>(
            AccountSelector.selectByIds(accountIds)
        );

        Id taskRtId = Schema.SObjectType.Task.getRecordTypeInfosByDeveloperName()
            .get(TAS_NOTIFICATION_TYPE_DEV_NAME)
            ?.getRecordTypeId();

        Set<Id> alreadyHasOpenTask = new Set<Id>();
        for (Task t : TaskSelector.getOpenTasksByWhatIdsAndRecordType(
            accountIds,
            taskRtId
        )) {
            alreadyHasOpenTask.add(t.WhatId);
        }

        List<Task> tasks = new List<Task>();
        for (Id accId : accountIds) {
            if (alreadyHasOpenTask.contains(accId)) {
                Logger.debug(
                    CLASS_NAME + '.createSalesOpsTasks: open task already exists AccountId=' +
                    accId
                );
                continue;
            }

            String accName = accById.containsKey(accId)
                ? accById.get(accId).Name
                : 'Prospect';

            tasks.add(new Task(
                OwnerId = queueId,
                WhatId = accId,
                Subject = 'TAS assignment failed - ' + accName,
                Description = 'Unable to retrieve the territory assignments for this account. Update the TAS assignment.',
                RecordTypeId = taskRtId
            ));
        }

        if (tasks.isEmpty()) {
            Logger.info(
                CLASS_NAME + '.createSalesOpsTasks: no new tasks to create accountCount=' +
                accountIds.size()
            );
            return;
        }

        logSaveResults('Task', Database.insert(tasks, false));
        Logger.info(
            CLASS_NAME + '.createSalesOpsTasks: created taskCount=' + tasks.size()
        );
    }

    /**
     * @author vinay
     * @description Sends the in-app / bell notification to SalesOpsQueue members.
     *              Passing the queue Id to send() fans out to all members. The
     *              targetId is the Account, so clicking the bell opens the Prospect. (AC5, AC6)
     * @param accountIds Accounts classified as Assignment Missing.
     */
    @TestVisible
    private static void notifySalesOps(Set<Id> accountIds) {
        CustomNotificationType notificationType =
            TeamMemberSelector.getCustomNotificationTypeByDeveloperName(
                TAS_NOTIFICATION_TYPE_DEV_NAME
            );

        if (notificationType == null) {
            Logger.warn(CLASS_NAME + '.notifySalesOps: notification type not found');
            return;
        }

        Id queueId = TeamMemberSelector.getQueueIdByDeveloperName(SALES_OPS_QUEUE_DEV_NAME);
        if (queueId == null) {
            Logger.warn(CLASS_NAME + '.notifySalesOps: SalesOpsQueue not found');
            return;
        }

        Map<Id, Account> accById = new Map<Id, Account>(
            AccountSelector.selectByIds(accountIds)
        );

        Integer sentCount = 0;
        for (Id accId : accountIds) {
            Messaging.CustomNotification cn = new Messaging.CustomNotification();
            cn.setNotificationTypeId(notificationType.Id);
            cn.setTargetId(accId);
            cn.setTitle(Label.TAS_Notification_Title);
            String name = accById.containsKey(accId)
                ? accById.get(accId).Name
                : Label.TAS_Prospect_Fallback;
            cn.setBody(String.format(Label.TAS_Notification_Body, new List<String>{ name }));

            try {
                cn.send(new Set<String>{ String.valueOf(queueId) });
                sentCount++;
            } catch (Exception e) {
                Logger.error(
                    CLASS_NAME + '.notifySalesOps: send failed AccountId=' + accId,
                    e
                );
            }
        }

        Logger.info(
            CLASS_NAME + '.notifySalesOps: sent notificationCount=' +
            sentCount +
            ', requestedAccountCount=' +
            accountIds.size()
        );
    }

    /**
     * @description Creates Account Team Member records from TAS response data.
     *              Existing Account Team Members are skipped to avoid duplicates.
     *
     * @param responseItems TAS response items containing territory and sales rep details.
     * @return Set of Account Ids for which a team member was successfully inserted (GC-3143).
     */
    private static Set<Id> insertAccountTeamMembers(List<TasTerritoryItem> responseItems) {
        Set<Id> insertedForAccountIds = new Set<Id>();

        try {
            if (responseItems == null || responseItems.isEmpty()) {
                Logger.debug(CLASS_NAME + '.insertAccountTeamMembers: no response items');
                return insertedForAccountIds;
            }

            Set<String> employeeNumbers = new Set<String>();
            Set<Id> accountIds = new Set<Id>();

            for (TasTerritoryItem item : responseItems) {
                if (item == null) {
                    continue;
                }

                if (String.isNotBlank(item.salesRepEmployeeNumber)) {
                    employeeNumbers.add(item.salesRepEmployeeNumber);
                }

                if (item.accountId != null) {
                    accountIds.add(item.accountId);
                }
            }

            if (employeeNumbers.isEmpty() || accountIds.isEmpty()) {
                Logger.warn(
                    CLASS_NAME + '.insertAccountTeamMembers: missing employee numbers or Account Ids'
                );
                return insertedForAccountIds;
            }

            Map<String, Id> employeeNumberToUserId = resolveActiveUsersByEmployeeNumber(
                employeeNumbers
            );

            if (employeeNumberToUserId.isEmpty()) {
                Logger.warn(
                    CLASS_NAME + '.insertAccountTeamMembers: no active Users found employeeNumberCount=' +
                    employeeNumbers.size()
                );
                return insertedForAccountIds;
            }

            Set<String> existingTeamKeys = new Set<String>();

            for (AccountTeamMember atm : AccountTeamMemberSelector.selectByAccountsAndUsers(
                accountIds,
                new Set<Id>(employeeNumberToUserId.values())
            )) {
                existingTeamKeys.add(atm.AccountId + '-' + atm.UserId);
            }

            List<AccountTeamMember> teamMembersToInsert = new List<AccountTeamMember>();

            for (TasTerritoryItem item : responseItems) {
                if (item == null || item.accountId == null) {
                    continue;
                }

                Id userId = employeeNumberToUserId.get(item.salesRepEmployeeNumber);

                if (userId == null) {
                    Logger.debug(
                        CLASS_NAME + '.insertAccountTeamMembers: no User for employeeNumber=' +
                        item.salesRepEmployeeNumber +
                        ' AccountId=' +
                        item.accountId
                    );
                    continue;
                }

                String teamKey = item.accountId + '-' + userId;

                if (existingTeamKeys.contains(teamKey)) {
                    continue;
                }

                existingTeamKeys.add(teamKey);

                teamMembersToInsert.add(new AccountTeamMember(
                    AccountId = item.accountId,
                    UserId = userId,
                    TeamMemberRole = TEAM_MEMBER_ROLE,
                    AssignmentType__c = TEAM_MEMBER_ASSIGNMENT_TYPE,
                    AccountAccessLevel = ACCOUNT_ACCESS_LEVEL
                ));
            }

            if (teamMembersToInsert.isEmpty()) {
                Logger.warn(
                    CLASS_NAME + '.insertAccountTeamMembers: no AccountTeamMember records to insert'
                );
                return insertedForAccountIds;
            }

            Database.SaveResult[] saveResults =
                Database.insert(teamMembersToInsert, false);

            for (Integer i = 0; i < saveResults.size(); i++) {
                if (saveResults[i].isSuccess()) {
                    insertedForAccountIds.add(teamMembersToInsert[i].AccountId);
                }
            }

            logSaveResults('AccountTeamMember', saveResults);
            Logger.info(
                CLASS_NAME + '.insertAccountTeamMembers: assignedAccountCount=' +
                insertedForAccountIds.size() +
                ', attemptedInsertCount=' +
                teamMembersToInsert.size()
            );

        } catch (Exception e) {
            Logger.error(CLASS_NAME + '.insertAccountTeamMembers', e);
        }

        return insertedForAccountIds;
    }

    /**
     * @description Creates OrderLineContact__c TAS staging records from territory assignments.
     *
     * @param responseItems TAS response items containing territory and sales rep details.
     */
    @TestVisible
    private static void insertTasAssignments(List<TasTerritoryItem> responseItems) {
        try {
            if (responseItems == null || responseItems.isEmpty()) {
                Logger.debug(CLASS_NAME + '.insertTasAssignments: no response items');
                return;
            }

            Map<String, Id> employeeNumberToUserId = resolveActiveUsersByEmployeeNumber(
                collectEmployeeNumbers(responseItems)
            );

            List<OrderLineContact__c> tasRowsToInsert = new List<OrderLineContact__c>();

            for (TasTerritoryItem item : responseItems) {
                if (item == null || item.accountId == null) {
                    continue;
                }

                tasRowsToInsert.add(new OrderLineContact__c(
                    TASAddressId__c = String.valueOf(item.accountId),
                    TerritoryID__c = item.territoryId,
                    TerritoryNumber__c = item.territoryNumber,
                    TerritoryDescription__c = item.territoryDescription,
                    SalesRepId__c = parseDecimal(item.salesRepId),
                    HRISSalesRepId__c = item.salesRepEmployeeNumber,
                    TAS_Sales_Category__c = item.tasSalesCategory,
                    ClassCode__c = item.classCode,
                    RegionName__c = item.regionName,
                    RegionManager__c = employeeNumberToUserId.get(item.regionManagerEmployeeNumber),
                    TASZone__c = item.zoneName,
                    ZoneManager__c = employeeNumberToUserId.get(item.zoneManagerEmployeeNumber),
                    GeographicalBusinessUnitName__c = item.gbuName,
                    BusinessUnit__c = item.buName,
                    DeltaScenario__c = TASTeamAccessSelector.DELTA_INSERT_RECORD //GC-3278 - references TASTeamAccessSelector for OLC delta constants.
                ));
            }

            if (tasRowsToInsert.isEmpty()) {
                Logger.debug(
                    CLASS_NAME + '.insertTasAssignments: no OrderLineContact__c records to insert'
                );
                return;
            }

            Database.SaveResult[] saveResults =
                Database.insert(tasRowsToInsert, false);

            logSaveResults('OrderLineContact__c', saveResults);
            Logger.info(
                CLASS_NAME + '.insertTasAssignments: attemptedInsertCount=' +
                tasRowsToInsert.size()
            );

        } catch (Exception e) {
            Logger.error(CLASS_NAME + '.insertTasAssignments', e);
        }
    }

    /**
     * @description Backward-compatible alias retained for unit tests.
     */
    @TestVisible
    private static void insertOrderLineContacts(List<TasTerritoryItem> responseItems) {
        insertTasAssignments(responseItems);
    }

    private static Set<String> collectEmployeeNumbers(List<TasTerritoryItem> responseItems) {
        Set<String> employeeNumbers = new Set<String>();

        for (TasTerritoryItem item : responseItems) {
            if (item == null) {
                continue;
            }

            if (String.isNotBlank(item.salesRepEmployeeNumber)) {
                employeeNumbers.add(item.salesRepEmployeeNumber);
            }

            if (String.isNotBlank(item.regionManagerEmployeeNumber)) {
                employeeNumbers.add(item.regionManagerEmployeeNumber);
            }

            if (String.isNotBlank(item.zoneManagerEmployeeNumber)) {
                employeeNumbers.add(item.zoneManagerEmployeeNumber);
            }
        }

        return employeeNumbers;
    }

    private static Map<String, Id> resolveActiveUsersByEmployeeNumber(Set<String> employeeNumbers) {
        Map<String, Id> employeeNumberToUserId = new Map<String, Id>();

        if (employeeNumbers == null || employeeNumbers.isEmpty()) {
            return employeeNumberToUserId;
        }

        Map<String, User> usersByEmployeeNumber =
            UserSelector.selectActiveUsersByEmployeeNumber(employeeNumbers);

        for (String employeeNumber : usersByEmployeeNumber.keySet()) {
            employeeNumberToUserId.put(
                employeeNumber,
                usersByEmployeeNumber.get(employeeNumber).Id
            );
        }

        return employeeNumberToUserId;
    }

    @TestVisible
    private static Boolean throwTestExceptionInLogSaveResults = false;

    /**
     * @description Logs partial DML success and failure details.
     *
     * @param objectName Name or label of the object/process being logged.
     * @param saveResults DML save results.
     */
    @TestVisible
    private static void logSaveResults(
        String objectName,
        Database.SaveResult[] saveResults
    ) {
        try {
            if (Test.isRunningTest() && throwTestExceptionInLogSaveResults) {
                throw new AccountProspectTasIntegrationServiceException(
                    'Test exception for logSaveResults catch coverage'
                );
            }

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

                for (Database.Error error : saveResult.getErrors()) {
                    Logger.error(
                        CLASS_NAME + '.logSaveResults: failed to process ' +
                        objectName +
                        ' index=' +
                        index +
                        ' statusCode=' +
                        error.getStatusCode() +
                        ' message=' +
                        error.getMessage()
                    );
                }
            }

            if (failureCount > 0) {
                Logger.warn(
                    CLASS_NAME + '.logSaveResults: objectName=' +
                    objectName +
                    ' successCount=' +
                    successCount +
                    ' failureCount=' +
                    failureCount
                );
            } else {
                Logger.info(
                    CLASS_NAME + '.logSaveResults: objectName=' +
                    objectName +
                    ' successCount=' +
                    successCount
                );
            }

        } catch (Exception e) {
            Logger.error(CLASS_NAME + '.logSaveResults', e);
        }
    }

    public class AccountProspectTasIntegrationServiceException extends Exception {}

    /**
     * @description Converts String value to Decimal safely.
     *
     * @param value String decimal value.
     * @return Decimal value when valid, otherwise null.
     */
    private static Decimal parseDecimal(String value) {
        if (String.isBlank(value)) {
            return null;
        }

        try {
            return Decimal.valueOf(value);
        } catch (Exception ex) {
            Logger.warn(
                CLASS_NAME + '.parseDecimal: invalid decimal value=' + value
            );
            return null;
        }
    }

    /**
     * @author Abhishek Mishra
     * @description Updates TAS_Retry__c on each Account independently.
     *              TRUE means TAS assignment completed successfully.
     *              FALSE means TAS assignment did not complete and Retry button should be available.
     * @param tasAssignmentStatusByAccountId Map of Account Id to TAS assignment completion status.
     * User Story - GC-3091
     */
    private static void updateTasRetryAssignmentFlag(
        Map<Id, Boolean> tasAssignmentStatusByAccountId
    ) {
        try {
            if (
                tasAssignmentStatusByAccountId == null ||
                tasAssignmentStatusByAccountId.isEmpty()
            ) {
                return;
            }

            List<Account> accountsToUpdate = new List<Account>();

            for (Id accountId : tasAssignmentStatusByAccountId.keySet()) {
                if (accountId == null) {
                    continue;
                }

                accountsToUpdate.add(new Account(
                    Id = accountId,
                    TAS_Retry__c = tasAssignmentStatusByAccountId.get(accountId)
                ));
            }

            if (accountsToUpdate.isEmpty()) {
                return;
            }

            logSaveResults(
                'Account TAS_Retry__c update',
                Database.update(accountsToUpdate, false)
            );
            Logger.info(
                CLASS_NAME + '.updateTasRetryAssignmentFlag: updatedAccountCount=' +
                accountsToUpdate.size()
            );

        } catch (Exception e) {
            Logger.error(CLASS_NAME + '.updateTasRetryAssignmentFlag', e);
        }
    }
}