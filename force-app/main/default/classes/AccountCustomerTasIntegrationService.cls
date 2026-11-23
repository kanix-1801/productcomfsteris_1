/**
 * @author Akash Dahinde
 * @date 07-01-2026
 * @description Service class responsible for processing TAS integration response
 *              for Customer Accounts sourced from Oracle. Performs TAS callouts via
 *              SO_Callout framework and creates Account Team Members only.
 *              Does not write OrderLineContact__c (TAS table) per AC3.
 *              Nightly batch uses OrderLineContact__c.AssignedSalesRep__c for HRIS rep lookup;
 *              this realtime path resolves User.EmployeeNumber__c directly from TAS response.
 *
 * Layering:
 *   AccountCustomerTasQueueable -> AccountCustomerTasIntegrationService
 *     -> AccountCustomerTasGateway -> SO_Callout -> SO_ProviderFactory -> Boomi TAS
 *
 * Nebula Logger: diagnostics are buffered here and persisted via {@code Logger.saveLog()}
 * in {@link #processAccounts}.
 */
public with sharing class AccountCustomerTasIntegrationService {

	private static final String CLASS_NAME = 'AccountCustomerTasIntegrationService';
	private static final String TEAM_MEMBER_ROLE = 'Sales';
	private static final String TEAM_MEMBER_ASSIGNMENT_TYPE = 'Oracle Assigned';
	private static final String ACCOUNT_ACCESS_LEVEL = 'Edit';

    /**
     * @description Processes Customer Accounts for TAS assignment.
     *              Performs one TAS callout per Account.
     * @param accounts List of Accounts to process.
     */
	public static void processAccounts(List<Account> accounts) {
		try {
			Logger.info(CLASS_NAME + '.processAccounts: started');

			if (accounts == null || accounts.isEmpty()) {
				Logger.debug(CLASS_NAME + '.processAccounts: no accounts to process');
				return;
			}

			Logger.debug(
				CLASS_NAME + '.processAccounts: accountCount=' + accounts.size()
			);

			List<TasAccountResponseItem> allResponseItems = new List<TasAccountResponseItem>();
			Integer calloutFailureCount = 0;
			Integer noTerritoryCount = 0;

			for (Account acc : accounts) {
				if (acc == null || acc.Id == null) {
					Logger.debug(CLASS_NAME + '.processAccounts: skipping null Account or Account Id');
					continue;
				}

				try {
					TasCustomerAccountRequest requestBody =
						TasCustomerAccountRequest.fromAccount(acc);

					AccountCustomerTasGateway.CalloutResult calloutResult =
						AccountCustomerTasGateway.sendCustomerAccountRequest(requestBody);

					if (!calloutResult.calloutSuccess) {
						calloutFailureCount++;
						Logger.error(
							CLASS_NAME + '.processAccounts: TAS callout failed AccountId=' +
							acc.Id + ', detail=' + calloutResult.errorDetail
						)
							.addTag('Account')
							.setRecord(acc);
						continue;
					}

					TasCustomerAccountResponse parsedResponse = calloutResult.parsedResponse;

					if (
						parsedResponse == null ||
						parsedResponse.territoryData == null ||
						parsedResponse.territoryData.isEmpty()
					) {
						noTerritoryCount++;
						Logger.debug(
							CLASS_NAME + '.processAccounts: no TAS territory data returned AccountId=' +
							acc.Id
						)
							.addTag('Account')
							.setRecord(acc);
						continue;
					}

					for (TasAccountResponseItem item : parsedResponse.territoryData) {
						item.accountId = acc.Id;
						allResponseItems.add(item);
					}

					Logger.info(
						CLASS_NAME + '.processAccounts: territory data received AccountId=' +
						acc.Id +
						', territoryCount=' +
						parsedResponse.territoryData.size()
					);

				} catch (Exception accountException) {
					Logger.error(
						CLASS_NAME + '.processAccounts: failed processing AccountId=' +
						acc.Id,
						accountException
					)
						.addTag('Account')
						.setRecord(acc);
				}
			}

			if (!allResponseItems.isEmpty()) {
				Map<Id, Boolean> lifeSciencesByAccountId = new Map<Id, Boolean>();
                for (Account acc : accounts) {
                    if (acc != null && acc.Id != null) {
                        lifeSciencesByAccountId.put(acc.Id, LSAccountService.isLifeSciencesAccount(acc));
                    }
                }
                insertAccountTeamMembers(allResponseItems, lifeSciencesByAccountId);
			} else {
				Logger.debug(
					CLASS_NAME + '.processAccounts: no TAS response items to process'
				);
			}

			Logger.debug(
				CLASS_NAME + '.processAccounts: outcome summary responseItemCount=' +
				allResponseItems.size() +
				', calloutFailureCount=' +
				calloutFailureCount +
				', noTerritoryCount=' +
				noTerritoryCount
			);

			Logger.info(
				CLASS_NAME + '.processAccounts: completed, responseItemCount=' +
				allResponseItems.size()
			);

		} catch (Exception e) {
			Logger.error(CLASS_NAME + '.processAccounts', e);
		} finally {
			Logger.saveLog();
		}
	}

    /** GC-3021
     * @description Creates Account Team Member records from TAS response data.
     * @param responseItems TAS response items containing territory and sales rep details.
     */
	private static void insertAccountTeamMembers(List<TasAccountResponseItem> responseItems, Map<Id, Boolean> lifeSciencesByAccountId) {
		try {
			if (responseItems == null || responseItems.isEmpty()) {
				Logger.debug(
					CLASS_NAME + '.insertAccountTeamMembers: no response items'
				);
				return;
			}

			Set<String> employeeNumbers = new Set<String>();
			Set<Id> accountIds = new Set<Id>();

			for (TasAccountResponseItem item : responseItems) {
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
				Logger.debug(
					CLASS_NAME + '.insertAccountTeamMembers: missing employee numbers or Account Ids'
				);
				return;
			}

			Map<String, Id> employeeNumberToUserId = resolveUsersByBusinessLine(
                responseItems,
                lifeSciencesByAccountId
			);

			if (employeeNumberToUserId.isEmpty()) {
				Logger.debug(
					CLASS_NAME + '.insertAccountTeamMembers: no active Users found employeeNumberCount=' +
					employeeNumbers.size()
				);
				return;
			}

			Set<String> existingTeamKeys = new Set<String>();

			for (AccountTeamMember atm : [
				SELECT AccountId, UserId
				FROM AccountTeamMember
				WHERE AccountId IN :accountIds
				  AND UserId IN :employeeNumberToUserId.values()
			]) {
				existingTeamKeys.add(atm.AccountId + '-' + atm.UserId);
			}

			List<AccountTeamMember> teamMembersToInsert = new List<AccountTeamMember>();

			for (TasAccountResponseItem item : responseItems) {
				if (item == null || item.accountId == null) {
					continue;
				}

				Id userId = employeeNumberToUserId.get(item.salesRepEmployeeNumber.trim());

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
				Logger.debug(
					CLASS_NAME + '.insertAccountTeamMembers: no AccountTeamMember records to insert'
				);
				return;
			}

			Database.SaveResult[] saveResults =
				Database.insert(teamMembersToInsert, false);

			logSaveResults('AccountTeamMember', saveResults);
			Logger.info(
				CLASS_NAME + '.insertAccountTeamMembers: attemptedInsertCount=' +
				teamMembersToInsert.size()
			);

		} catch (Exception e) {
			Logger.error(
				CLASS_NAME + '.insertAccountTeamMembers',
				e
			);
		}
	}

    /** GC-3021 Account class code selects the sales profile.*/
	private static Map<String, Id> resolveUsersByBusinessLine(List<TasAccountResponseItem> responseItems,Map<Id, Boolean> lifeSciencesByAccountId) {
            
		Set<String> healthcareEmployeeNumbers = new Set<String>();
        Set<String> lifeSciencesEmployeeNumbers = new Set<String>();
		Map<String, Id> employeeNumberToUserId = new Map<String, Id>();
		for (TasAccountResponseItem item : responseItems) {
            if (item == null || String.isBlank(item.salesRepEmployeeNumber)) {
                continue;
            }
            if (lifeSciencesByAccountId != null && lifeSciencesByAccountId.get(item.accountId) == true) {
                lifeSciencesEmployeeNumbers.add(item.salesRepEmployeeNumber);
            } else {
                healthcareEmployeeNumbers.add(item.salesRepEmployeeNumber);
            }
		}

        addUsers(employeeNumberToUserId, UserSelector.selectActiveHealthcareSalesUsersByEmployeeNumber(healthcareEmployeeNumbers));
        addUsers(employeeNumberToUserId, UserSelector.selectActiveLifeSciencesSalesUsersByEmployeeNumber(lifeSciencesEmployeeNumbers));

		return employeeNumberToUserId;
	}
    
    
    private static void addUsers(Map<String, Id> employeeNumberToUserId, Map<String, User> usersByEmployeeNumber) {
        if (usersByEmployeeNumber == null) {
            return;
        }
        for (String employeeNumber : usersByEmployeeNumber.keySet()) {
            employeeNumberToUserId.put(employeeNumber, usersByEmployeeNumber.get(employeeNumber).Id);
        }
    }

	@TestVisible
	private static void logSaveResults(
		String objectName,
		Database.SaveResult[] saveResults
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

				for (Database.Error error : saveResult.getErrors()) {
					Logger.error(
						CLASS_NAME + '.logSaveResults: failed to process ' +
						objectName +
						'. index=' +
						index +
						', statusCode=' +
						error.getStatusCode() +
						', message=' +
						error.getMessage()
					);
				}
			}

			Logger.debug(
				CLASS_NAME + '.logSaveResults: objectName=' +
				objectName +
				', successCount=' +
				successCount +
				', failureCount=' +
				failureCount
			);

		} catch (Exception e) {
			Logger.error(
				CLASS_NAME + '.logSaveResults',
				e
			);
		}
	}
}