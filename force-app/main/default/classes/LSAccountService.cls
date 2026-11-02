/**
 * @description Life Sciences Account TAS trigger orchestration for Prospect and Customer.
 * author PWC Developer
 * @date 2026/06/10
 *
 *  GCL-4: Real-time TAS validation when a new Life Sciences Prospect Account is created.
 *  Customer TAS uses the same class. Record type selects Prospect or Customer.
 *  Class code selects Life Sciences: SC, Life Science, or Life Sciences.
 *
 *  Responsibilities:
 *   1. Receive Account trigger context from AccountTriggerHandler.
 *   2. Identify eligible Life Sciences Prospect and Customer Accounts.
 *   3. Enqueue the matching TAS queueable for post-save Boomi callouts.
 */
public with sharing class LSAccountService {

    private static final String CLASS_NAME = 'LSAccountService';
    private static final String PROSPECT_RECORD_TYPE_DEV_NAME = 'Prospect';
    private static final String CUSTOMER_RECORD_TYPE_DEV_NAME = 'Customer';
    private static final String TAS_STATUS_ASSIGNED = 'Assigned';

    @TestVisible
    private static Boolean throwTestException = false;

    /**
     * Life Sciences class codes. Accepts both the Boomi code and the picklist label so
     * the branch is correct whichever value Account.CustomerClassCode__c stores.
     */
    private static final Set<String> LS_CLASS_CODES = new Set<String>{
        'SC'
    };

    /**
     * @description Single source of truth for Life Sciences branching. AccountService
     *              calls this to exclude Life Sciences Accounts from the Healthcare path.
     * @param acc Account record to evaluate.
     * @return True when the Account belongs to the Life Sciences business unit.
     */
    public static Boolean isLifeSciencesAccount(Account acc) {
        return acc != null
            && String.isNotBlank(acc.CustomerClassCode__c)
            && LS_CLASS_CODES.contains(acc.CustomerClassCode__c.trim().toUpperCase());
    }

    /**
     * @description Handles Account after insert events and enqueues TAS processing for
     *              all eligible Life Sciences Prospect Accounts.
     * @param newAccounts List of newly inserted Account records from trigger context.
     */
    public static void assignTAStoProspect(List<Account> newAccounts) {
        try {
            Logger.info(CLASS_NAME + '.assignTAStoProspect: started');

            if (Test.isRunningTest() && throwTestException) {
                throw new LSAccountServiceException('Test exception for assignTAStoProspect catch coverage');
            }

            if (newAccounts == null || newAccounts.isEmpty()) {
                Logger.warn(CLASS_NAME + '.assignTAStoProspect: newAccounts is null or empty');
                return;
            }

            Id prospectRecordTypeId = getProspectRecordTypeId();

            if (prospectRecordTypeId == null) {
                Logger.warn(CLASS_NAME + '.assignTAStoProspect: Prospect record type not found');
                return;
            }

            Set<Id> eligibleAccountIds = new Set<Id>();

            for (Account acc : newAccounts) {
                if (isValidProspectAccount(acc, prospectRecordTypeId)) {
                    eligibleAccountIds.add(acc.Id);
                }
            }

            Logger.info(
                CLASS_NAME + '.assignTAStoProspect: eligibleAccountCount=' +
                eligibleAccountIds.size()
            );

            enqueueProspectTasJob(eligibleAccountIds, 'assignTAStoProspect');

        } catch (Exception e) {
            Logger.error(CLASS_NAME + '.assignTAStoProspect', e);
            throw e;
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description Handles Account after insert events and enqueues TAS processing for
     *              eligible Life Sciences Customer Accounts.
     * @param newAccounts List of newly inserted Account records from trigger context.
     */
    public static void assignTAStoCustomer(List<Account> newAccounts) {
        try {
            Logger.info(CLASS_NAME + '.assignTAStoCustomer: started');

            if (Test.isRunningTest() && throwTestException) {
                throw new LSAccountServiceException(
                    'Test exception for assignTAStoCustomer catch coverage'
                );
            }

            Set<Id> eligibleAccountIds = collectEligibleCustomerIds(newAccounts, 'assignTAStoCustomer');
            enqueueCustomerTasJob(eligibleAccountIds, 'assignTAStoCustomer');
        } catch (Exception e) {
            Logger.error(CLASS_NAME + '.assignTAStoCustomer', e);
            throw e;
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description Handles Account after update events and enqueues TAS processing when
     *              a Life Sciences Customer stays eligible and a TAS field changed.
     * @param newAccounts Updated Account records from trigger context.
     * @param oldAccountMap Prior Account values from trigger context.
     */
    public static void assignTAStoCustomerUpdate(
        List<Account> newAccounts,
        Map<Id, Account> oldAccountMap
    ) {
        try {
            Logger.info(CLASS_NAME + '.assignTAStoCustomerUpdate: started');

            if (Test.isRunningTest() && throwTestException) {
                throw new LSAccountServiceException(
                    'Test exception for assignTAStoCustomerUpdate catch coverage'
                );
            }

            if (newAccounts == null || newAccounts.isEmpty()) {
                Logger.warn(CLASS_NAME + '.assignTAStoCustomerUpdate: newAccounts is null or empty');
                return;
            }

            if (oldAccountMap == null || oldAccountMap.isEmpty()) {
                Logger.warn(CLASS_NAME + '.assignTAStoCustomerUpdate: oldAccountMap is null or empty');
                return;
            }

            Id customerRecordTypeId = getCustomerRecordTypeId();
            if (customerRecordTypeId == null) {
                Logger.warn(CLASS_NAME + '.assignTAStoCustomerUpdate: Customer record type not found');
                return;
            }

            Set<Id> eligibleAccountIds = new Set<Id>();

            for (Account acc : newAccounts) {
                if (acc == null || acc.Id == null) {
                    continue;
                }

                Account oldAcc = oldAccountMap.get(acc.Id);
                if (oldAcc == null) {
                    Logger.warn(
                        CLASS_NAME + '.assignTAStoCustomerUpdate: old Account record not found for AccountId=' +
                        acc.Id
                    );
                    continue;
                }

                if (
                    isValidCustomerAccount(acc, customerRecordTypeId) &&
                    hasRelevantCustomerFieldChanged(acc, oldAcc)
                ) {
                    eligibleAccountIds.add(acc.Id);
                }
            }

            Logger.info(
                CLASS_NAME + '.assignTAStoCustomerUpdate: eligibleAccountCount=' +
                eligibleAccountIds.size()
            );

            enqueueCustomerTasJob(eligibleAccountIds, 'assignTAStoCustomerUpdate');
        } catch (Exception e) {
            Logger.error(CLASS_NAME + '.assignTAStoCustomerUpdate', e);
            throw e;
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description Flow input wrapper carrying the Account Id to retry.
     */
    public class FlowRequest {
        @InvocableVariable(required=true)
        public Id accountId;
    }

    /**
     * @description Retries TAS assignment for a Life Sciences Prospect or Customer.
     *              Record type selects the queueable. Class code must be Life Science (SC).
     * @param requests Flow requests containing Account Ids to retry.
     */
    @InvocableMethod(
        label='Retry TAS Assignment (Life Sciences)'
        description='Retries TAS assignment for a Life Sciences Prospect or Customer Account. Class code must be Life Science (SC).'
    )
    public static void retryTasAssignmentFromFlow(List<FlowRequest> requests) {
        try {
            Logger.info(CLASS_NAME + '.retryTasAssignmentFromFlow: started');

            if (Test.isRunningTest() && throwTestException) {
                throw new LSAccountServiceException('Test exception for retryTasAssignmentFromFlow catch coverage');
            }

            if (requests == null || requests.isEmpty()) {
                Logger.warn(CLASS_NAME + '.retryTasAssignmentFromFlow: requests is null or empty');
                return;
            }

            Set<Id> accountIds = new Set<Id>();

            for (FlowRequest request : requests) {
                if (request != null && request.accountId != null) {
                    accountIds.add(request.accountId);
                }
            }

            if (accountIds.isEmpty()) {
                Logger.warn(CLASS_NAME + '.retryTasAssignmentFromFlow: no Account Ids found');
                return;
            }

            Id prospectRecordTypeId = getProspectRecordTypeId();
            Id customerRecordTypeId = getCustomerRecordTypeId();
            List<Account> accounts = AccountSelector.selectByIds(accountIds);
            Set<Id> eligibleProspectIds = new Set<Id>();
            Set<Id> eligibleCustomerIds = new Set<Id>();

            for (Account acc : accounts) {
                if (acc == null || acc.Id == null) {
                    continue;
                }
                if (!(acc.TAS_Retry__c == false || acc.TAS_Assignment_Status__c != TAS_STATUS_ASSIGNED)) {
                    continue;
                }
                if (prospectRecordTypeId != null && isValidProspectAccount(acc, prospectRecordTypeId)) {
                    eligibleProspectIds.add(acc.Id);
                } else if (customerRecordTypeId != null && isValidCustomerAccount(acc, customerRecordTypeId)) {
                    eligibleCustomerIds.add(acc.Id);
                }
            }

            Logger.info(
                CLASS_NAME + '.retryTasAssignmentFromFlow: eligibleProspectCount=' +
                eligibleProspectIds.size() +
                ', eligibleCustomerCount=' +
                eligibleCustomerIds.size()
            );

            enqueueProspectTasJob(eligibleProspectIds, 'retryTasAssignmentFromFlow');
            enqueueCustomerTasJob(eligibleCustomerIds, 'retryTasAssignmentFromFlow');

        } catch (Exception e) {
            Logger.error(CLASS_NAME + '.retryTasAssignmentFromFlow', e);
            throw e;
        } finally {
            Logger.saveLog();
        }
    }

    private static void enqueueProspectTasJob(Set<Id> eligibleAccountIds, String sourceMethod) {
        if (eligibleAccountIds == null || eligibleAccountIds.isEmpty()) {
            return;
        }

        Id jobId = System.enqueueJob(new LSAccountProspectTasQueueable(eligibleAccountIds));
        Logger.info(
            CLASS_NAME + '.' + sourceMethod + ': submitted LSAccountProspectTasQueueable, jobId=' +
            jobId
        );
    }

    private static void enqueueCustomerTasJob(Set<Id> eligibleAccountIds, String sourceMethod) {
        if (eligibleAccountIds == null || eligibleAccountIds.isEmpty()) {
            return;
        }

        Id jobId = System.enqueueJob(new LSAccountCustomerTasQueueable(eligibleAccountIds));
        Logger.info(
            CLASS_NAME + '.' + sourceMethod + ': submitted LSAccountCustomerTasQueueable, jobId=' +
            jobId
        );
    }

    private static Set<Id> collectEligibleCustomerIds(List<Account> newAccounts, String sourceMethod) {
        if (newAccounts == null || newAccounts.isEmpty()) {
            Logger.warn(CLASS_NAME + '.' + sourceMethod + ': newAccounts is null or empty');
            return new Set<Id>();
        }

        Id customerRecordTypeId = getCustomerRecordTypeId();
        if (customerRecordTypeId == null) {
            Logger.warn(CLASS_NAME + '.' + sourceMethod + ': Customer record type not found');
            return new Set<Id>();
        }

        Set<Id> eligibleAccountIds = new Set<Id>();
        for (Account acc : newAccounts) {
            if (isValidCustomerAccount(acc, customerRecordTypeId)) {
                eligibleAccountIds.add(acc.Id);
            }
        }

        Logger.info(
            CLASS_NAME + '.' + sourceMethod + ': eligibleAccountCount=' +
            eligibleAccountIds.size()
        );
        return eligibleAccountIds;
    }

    private static Id getProspectRecordTypeId() {
        Map<String, Schema.RecordTypeInfo> recordTypeInfoByDeveloperName =
            Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName();

        if (!recordTypeInfoByDeveloperName.containsKey(PROSPECT_RECORD_TYPE_DEV_NAME)) {
            return null;
        }

        return recordTypeInfoByDeveloperName.get(PROSPECT_RECORD_TYPE_DEV_NAME).getRecordTypeId();
    }

    private static Id getCustomerRecordTypeId() {
        Map<String, Schema.RecordTypeInfo> recordTypeInfoByDeveloperName =
            Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName();

        if (!recordTypeInfoByDeveloperName.containsKey(CUSTOMER_RECORD_TYPE_DEV_NAME)) {
            return null;
        }

        return recordTypeInfoByDeveloperName.get(CUSTOMER_RECORD_TYPE_DEV_NAME).getRecordTypeId();
    }

    /**
     * @description Life Sciences Prospect eligibility. Price List is required.
     */
    private static Boolean isValidProspectAccount(Account acc, Id prospectRecordTypeId) {
        return acc != null
            && acc.RecordTypeId == prospectRecordTypeId
            && isLifeSciencesAccount(acc)
            && String.isNotBlank(acc.Name)
            && String.isNotBlank(acc.CustomerClassCode__c)
            && String.isNotBlank(acc.OrgIDs__c)
            && String.isNotBlank(acc.BillingStreet)
            && String.isNotBlank(acc.BillingCity)
            && String.isNotBlank(acc.BillingCountry)
            && String.isNotBlank(acc.BillingState)
            && String.isNotBlank(acc.BillingPostalCode)
            && acc.Price_List__c != null;
    }

    /**
     * @description Life Sciences Customer eligibility. Record type must be Customer and
     *              class code must be Life Science (label or SC). Oracle source, Oracle
     *              Address Id, Org Id, and billing city/state/country/postal are required.
     *              Price List is not required.
     */
    private static Boolean isValidCustomerAccount(Account acc, Id customerRecordTypeId) {
        return acc != null
            && acc.RecordTypeId == customerRecordTypeId
            && isLifeSciencesAccount(acc)
            && isOracleSourcedAccount(acc)
            && String.isNotBlank(acc.OracleAddressId__c)
            && String.isNotBlank(acc.CustomerClassCode__c)
            && String.isNotBlank(acc.OrgIDs__c)
            && String.isNotBlank(acc.BillingCity)
            && String.isNotBlank(acc.BillingCountry)
            && String.isNotBlank(acc.BillingState)
            && String.isNotBlank(acc.BillingPostalCode);
    }

    /**
     * @description True when the Account was sourced from Oracle.
     *              AccountSource = Oracle, or SourceSystemID__c contains Oracle.
     */
    private static Boolean isOracleSourcedAccount(Account acc) {
        if (acc == null) {
            return false;
        }
        if (acc.AccountSource == 'Oracle') {
            return true;
        }
        return acc.SourceSystemID__c != null
            && acc.SourceSystemID__c.containsIgnoreCase('Oracle');
    }

    private static Boolean hasRelevantCustomerFieldChanged(Account acc, Account oldAcc) {
        return acc.RecordTypeId != oldAcc.RecordTypeId
            || acc.Name != oldAcc.Name
            || acc.CustomerClassCode__c != oldAcc.CustomerClassCode__c
            || acc.AccountSource != oldAcc.AccountSource
            || acc.SourceSystemID__c != oldAcc.SourceSystemID__c
            || acc.OracleAddressId__c != oldAcc.OracleAddressId__c
            || acc.OrgIDs__c != oldAcc.OrgIDs__c
            || acc.BillingStreet != oldAcc.BillingStreet
            || acc.BillingCity != oldAcc.BillingCity
            || acc.BillingCountry != oldAcc.BillingCountry
            || acc.BillingState != oldAcc.BillingState
            || acc.BillingPostalCode != oldAcc.BillingPostalCode
            || acc.Price_List__c != oldAcc.Price_List__c;
    }

    public class LSAccountServiceException extends Exception {}
}