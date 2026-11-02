/**
 * @description Service class responsible for processing TAS integration response for Life Sciences Customer Accounts.
 *              Same pattern as the Life Sciences Prospect TAS integration, scoped to Customer.
 *              Territory rows are kept only when ClassCode is Life Science (SC).
 *
 *              Performs TAS callouts via the
 *              SO_Callout framework, creates Account Team Members, and creates
 *              OrderLineContact__c staging records. Classifies each Account into a
 *              three-way outcome:
 *                  Assigned            -> SC territory returned and Account Team Member inserted
 *                  Assignment Missing  -> callout succeeded but no ATM inserted
 *                  Technical Failure   -> callout failed / unparseable
 *
 * Layering:
 *   LSAccountCustomerTasQueueable -> LSAccountCustomerTasIntegrationService
 *     -> TasAssignmentGateway -> SO_Callout -> SO_ProviderFactory -> Boomi TAS
 * #GCL-83 
 */
public with sharing class LSAccountCustomerTasIntegrationService {

    private static final String CLASS_NAME = 'LSAccountCustomerTasIntegrationService';

    private static final String TEAM_MEMBER_ROLE = 'Sales';
    private static final String TEAM_MEMBER_ASSIGNMENT_TYPE = 'Oracle Assigned';
    private static final String ACCOUNT_ACCESS_LEVEL = 'Edit';

    public static final String TAS_STATUS_ASSIGNED = 'Assigned';
    public static final String TAS_STATUS_ASSIGNMENT_MISSING = 'Assignment Missing';
    public static final String TAS_STATUS_TECHNICAL_FAILURE = 'Technical Failure';

    /**
     * @description Processes Life Sciences Customer Accounts for TAS assignment.
     *              Performs one TAS callout per Account and classifies the outcome.
     * @param accounts List of Accounts to process.
     * #GCL-83 
     */
    public static void processAccounts(List<Account> accounts) {
        try {
            Logger.info(CLASS_NAME + '.processAccounts: started');

            if (accounts == null || accounts.isEmpty()) {
                Logger.warn(CLASS_NAME + '.processAccounts: no accounts to process');
                return;
            }

            Logger.info(CLASS_NAME + '.processAccounts: accountCount=' + accounts.size());

            List<TasTerritoryItem> allResponseItems = new List<TasTerritoryItem>();
            Map<Id, Boolean> tasAssignmentStatusByAccountId = new Map<Id, Boolean>();
            Map<Id, String> tasStatusByAccountId = new Map<Id, String>();

            for (Account acc : accounts) {
                if (acc == null || acc.Id == null) {
                    Logger.warn(CLASS_NAME + '.processAccounts: skipping null Account or Account Id');
                    continue;
                }

                tasAssignmentStatusByAccountId.put(acc.Id, false);

                // Pessimistic default: anything unexpected is a technical failure.
                tasStatusByAccountId.put(acc.Id, TAS_STATUS_TECHNICAL_FAILURE);

                try {
                    TasAssignmentRequest requestBody = TasAssignmentRequest.fromAccount(acc);

                    TasAssignmentGateway.CalloutResult calloutResult =
                        TasAssignmentGateway.sendAssignmentRequest(requestBody);

                    if (!calloutResult.calloutSuccess) {
                        Logger.error(
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
                        tasStatusByAccountId.put(acc.Id, TAS_STATUS_ASSIGNMENT_MISSING);
                        Logger.warn(
                            CLASS_NAME + '.processAccounts: no TAS territory data returned AccountId=' +
                            acc.Id
                        );
                        continue;
                    }

                    List<TasTerritoryItem> lifeSciencesItems = new List<TasTerritoryItem>();

                    for (TasTerritoryItem item : parsedResponse.territoryData) {
                        if (item == null || !isLifeSciencesClassCode(item.classCode)) {
                            Logger.warn(
                                CLASS_NAME + '.processAccounts: skipping territory that is not Life Science (SC). classCode=' +
                                (item == null ? null : item.classCode) +
                                ' AccountId=' +
                                acc.Id
                            );
                            continue;
                        }

                        item.accountId = acc.Id;
                        lifeSciencesItems.add(item);
                    }

                    if (lifeSciencesItems.isEmpty()) {
                        tasStatusByAccountId.put(acc.Id, TAS_STATUS_ASSIGNMENT_MISSING);
                        Logger.warn(
                            CLASS_NAME + '.processAccounts: no Life Science (SC) territory data AccountId=' +
                            acc.Id
                        );
                        continue;
                    }

                    allResponseItems.addAll(lifeSciencesItems);

                    tasAssignmentStatusByAccountId.put(acc.Id, true);

                    // Callout succeeded with Life Science territory; finalize after ATM insert.
                    tasStatusByAccountId.put(acc.Id, TAS_STATUS_ASSIGNMENT_MISSING);

                    Logger.info(
                        CLASS_NAME + '.processAccounts: territory data received AccountId=' +
                        acc.Id +
                        ', territoryCount=' +
                        lifeSciencesItems.size()
                    );

                } catch (Exception accountException) {
                    Logger.error(
                        CLASS_NAME + '.processAccounts: failed processing AccountId=' + acc.Id,
                        accountException
                    );
                }
            }

            Set<Id> assignedAccountIds = new Set<Id>();

            if (!allResponseItems.isEmpty()) {
                insertTasAssignments(allResponseItems);
                assignedAccountIds = insertAccountTeamMembers(allResponseItems);
            } else {
                Logger.info(CLASS_NAME + '.processAccounts: no TAS response items to process');
            }

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

            updateTasRetryAssignmentFlag(tasAssignmentStatusByAccountId);
            applyTasOutcome(tasStatusByAccountId);

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

    /**
     * @description Writes TAS_Assignment_Status__c for each Account. Life Sciences does
     *              not create Sales Ops Tasks and does not send bell notifications.
     * @param statusByAccountId Map of Account Id to outcome status.
     * #GCL-83 
     */
    @TestVisible
    private static void applyTasOutcome(Map<Id, String> statusByAccountId) {
        try {
            if (statusByAccountId == null || statusByAccountId.isEmpty()) {
                Logger.debug(CLASS_NAME + '.applyTasOutcome: no statuses to apply');
                return;
            }

            List<Account> accountsToUpdate = new List<Account>();
            Integer assignedCount = 0;
            Integer assignmentMissingCount = 0;
            Integer technicalFailureCount = 0;

            for (Id accId : statusByAccountId.keySet()) {
                if (accId == null) {
                    continue;
                }

                String status = statusByAccountId.get(accId);

                accountsToUpdate.add(new Account(
                    Id = accId,
                    TAS_Assignment_Status__c = status
                ));

                if (status == TAS_STATUS_ASSIGNED) {
                    assignedCount++;
                } else if (status == TAS_STATUS_ASSIGNMENT_MISSING) {
                    assignmentMissingCount++;
                } else if (status == TAS_STATUS_TECHNICAL_FAILURE) {
                    technicalFailureCount++;
                }
            }

            Logger.info(
                CLASS_NAME + '.applyTasOutcome: applying statuses accountCount=' +
                accountsToUpdate.size() +
                ', assigned=' +
                assignedCount +
                ', assignmentMissing=' +
                assignmentMissingCount +
                ', technicalFailure=' +
                technicalFailureCount
            );

            if (!accountsToUpdate.isEmpty()) {
                logSaveResults(
                    'Account TAS_Assignment_Status__c update',
                    Database.update(accountsToUpdate, false)
                );
            }

        } catch (Exception e) {
            Logger.error(CLASS_NAME + '.applyTasOutcome', e);
        }
    }

    /**
     * @description Creates Account Team Member records from TAS response data using
     *              active Life Sciences Sales users. Existing Account Team Members are
     *              skipped to avoid duplicates.
     * @param responseItems TAS response items containing territory and sales rep details.
     * @return Set of Account Ids for which a team member was successfully inserted.
     * #GCL-83 
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
                    CLASS_NAME + '.insertAccountTeamMembers: no active Life Sciences Sales Users found employeeNumberCount=' +
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
                if (item == null || item.accountId == null || !isLifeSciencesClassCode(item.classCode)) {
                    continue;
                }

                Id userId = employeeNumberToUserId.get(item.salesRepEmployeeNumber);

                if (userId == null) {
                    Logger.debug(
                        CLASS_NAME + '.insertAccountTeamMembers: no Life Sciences Sales User for employeeNumber=' +
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

            Database.SaveResult[] saveResults = Database.insert(teamMembersToInsert, false);

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
                if (item == null || item.accountId == null || !isLifeSciencesClassCode(item.classCode)) {
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
                    DeltaScenario__c = TASTeamAccessSelector.DELTA_INSERT_RECORD
                ));
            }

            if (tasRowsToInsert.isEmpty()) {
                Logger.debug(
                    CLASS_NAME + '.insertTasAssignments: no OrderLineContact__c records to insert'
                );
                return;
            }

            Database.SaveResult[] saveResults = Database.insert(tasRowsToInsert, false);

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
     * @description Collects sales rep, region manager and zone manager employee numbers.
     * @param responseItems TAS response items.
     * @return Set of employee numbers present on the response items.
     */
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

    /**
     * @description Resolves employee numbers to active Life Sciences Sales Users.
     *              This is the second of the two Life Sciences differences.
     * @param employeeNumbers HRIS employee numbers from the TAS response.
     * @return Map of employee number to User Id.
     */
    private static Map<String, Id> resolveActiveUsersByEmployeeNumber(Set<String> employeeNumbers) {
        Map<String, Id> employeeNumberToUserId = new Map<String, Id>();

        if (employeeNumbers == null || employeeNumbers.isEmpty()) {
            return employeeNumberToUserId;
        }

        Map<String, User> usersByEmployeeNumber =
            UserSelector.selectActiveLifeSciencesSalesUsersByEmployeeNumber(employeeNumbers);

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
     * @param objectName Name or label of the object/process being logged.
     * @param saveResults DML save results.
     * #GCL-83 
     */
    @TestVisible
    private static void logSaveResults(
        String objectName,
        Database.SaveResult[] saveResults
    ) {
        try {
            if (Test.isRunningTest() && throwTestExceptionInLogSaveResults) {
                throw new LSAccountCustomerTasIntegrationServiceException(
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

    public class LSAccountCustomerTasIntegrationServiceException extends Exception {}

    /**
     * @description Life Sciences class code check for TAS territory rows.
     *              Accepts the Boomi code SC and the Life Science picklist label.
     * @param classCode Class code returned by TAS.
     * @return True when the territory belongs to Life Sciences.
     */
    private static Boolean isLifeSciencesClassCode(String classCode) {
        if (String.isBlank(classCode)) {
            return false;
        }

        String normalized = classCode.trim().toUpperCase();
        return normalized == 'SC'
            || normalized == 'LIFE SCIENCE'
            || normalized == 'LIFE SCIENCES';
    }

    /**
     * @description Converts String value to Decimal safely.
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
            Logger.warn(CLASS_NAME + '.parseDecimal: invalid decimal value=' + value);
            return null;
        }
    }

    /**
     * @description Updates TAS_Retry__c on each Account independently.
     *              TRUE means TAS assignment completed successfully.
     *              FALSE means TAS assignment did not complete and the Retry button
     *              should remain available.
     * @param tasAssignmentStatusByAccountId Map of Account Id to TAS assignment completion status.
     * #GCL-83 
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