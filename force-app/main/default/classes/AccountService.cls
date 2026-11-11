/**
     * @author Abhishek Mishra
     * @date 04-06-2026
     * @description Prospect and Customer Account TAS trigger orchestration.
     *
     *              Responsibilities:
     *              1. Receive Account trigger context from AccountTriggerHandler.
     *              2. Identify eligible Prospect Account records with required TAS fields.
     *              3. Identify eligible Oracle-sourced Customer Accounts with OracleAddressId__c populated.
     *              4. Enqueue TAS queueables for immediate post-save Boomi callouts.
     *              5. Enable Customer Accounts with Type Dealer as partner accounts. GC-3617
     * GC-3021
     */
    public with sharing class AccountService  {

        // User field holding the running user's Org Id. Confirmed picklist,
        // shares the "Org IDs" Global Value Set with Account.OrgIDs__c - GC-3282
        private static final String USER_ORG_ID_FIELD = 'OrgId__c';
        
        private static final Set<String> HC_CLASS_CODES = new Set<String>{'HC'}; // GCL-4: Only allow the Healthcare prospect TAS realtime call if class code is HC
        /**
        * @description Single source of truth for Life Sciences branching. AccountService
        *              calls this to exclude Life Sciences Accounts from the Healthcare path.
        * @param acc Account record to evaluate.
        * @return True when the Account belongs to the Life Sciences business unit.
        */
        public static Boolean isHealthcareAccount(Account acc) {
            return acc != null
                && String.isNotBlank(acc.CustomerClassCode__c)
                && HC_CLASS_CODES.contains(acc.CustomerClassCode__c.trim().toUpperCase());
        }
        //GCL-4 : End
         /* @description Handles Account after insert events and enqueues TAS processing for one eligible Prospect Account.
         * @param newAccounts List of newly inserted Account records from trigger context.
         * @return None.
         */
        public static void assignTAStoProspect(List<Account> newAccounts) {
            try {
                Logger.info('AccountService.assignTAStoProspect: started');
                
                if (newAccounts == null || newAccounts.isEmpty()) {
                    Logger.warn('AccountService.assignTAStoProspect: newAccounts is null or empty');
                    return;
                }
                
                Id prospectRecordTypeId = getProspectRecordTypeId();
                
                if (prospectRecordTypeId == null) {
                    Logger.warn('AccountService.assignTAStoProspect: Prospect record type not found');
                    return;
                }
                
                Set<Id> eligibleAccountIds = new Set<Id>();
                
                for (Account acc : newAccounts) {
                    if (isValidProspectAccount(acc, prospectRecordTypeId)) {
                        eligibleAccountIds.add(acc.Id);
                    }
                }
                
                Logger.info(
                    'AccountService.assignTAStoProspect: eligibleAccountCount=' +
                    eligibleAccountIds.size()
                );
                
                if (!eligibleAccountIds.isEmpty() && eligibleAccountIds.size() == 1) {
                    Id jobId = System.enqueueJob(new AccountProspectTasQueueable(eligibleAccountIds));

                    Logger.info(
                        'AccountService.assignTAStoProspect: submitted AccountProspectTasQueueable, jobId=' +
                        jobId
                    );
                } else if (eligibleAccountIds.size() > 1) {
                    Logger.warn(
                        'AccountService.assignTAStoProspect: more than one eligible Account found. Queueable not submitted. eligibleAccountCount=' +
                        eligibleAccountIds.size()
                    );
                }
                
            } catch (Exception e) {
                Logger.error('AccountService.assignTAStoProspect', e);
                throw e;
            } finally {
                Logger.saveLog();
            }
        }

        /**
         * @description Handles Account after update events and enqueues TAS processing
         *              when relevant Prospect Account fields change.
         *              Same two-argument signature as assignTAStoCustomerUpdate so
         *              callers can pass a null list and a null old-map.
         * @param newAccounts List of updated Account records from trigger context.
         * @param oldAccountMap Map of Account Id to old Account record values from trigger context.
         * @return None.
         */
        public static void assignTAStoProspectUpdate(	
            List<Account> newAccounts,
            Map<Id, Account> oldAccountMap
        ) {
            try {
                Logger.info('AccountService.assignTAStoProspectUpdate: started');

                if (newAccounts == null || newAccounts.isEmpty()) {
                    Logger.warn('AccountService.assignTAStoProspectUpdate: newAccounts is null or empty');
                    return;
                }

                if (oldAccountMap == null || oldAccountMap.isEmpty()) {
                    Logger.warn('AccountService.assignTAStoProspectUpdate: oldAccountMap is null or empty');
                    return;
                }

                Id prospectRecordTypeId = getProspectRecordTypeId();

                if (prospectRecordTypeId == null) {
                    Logger.warn('AccountService.assignTAStoProspectUpdate: Prospect record type not found');
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
                            'AccountService.assignTAStoProspectUpdate: old Account record not found for AccountId=' +
                            acc.Id
                        );
                        continue;
                    }

                    if (
                        isValidProspectAccount(acc, prospectRecordTypeId) &&
                        hasRelevantProspectFieldChanged(acc, oldAcc)
                    ) {
                        eligibleAccountIds.add(acc.Id);
                    }
                }

                Logger.info(
                    'AccountService.assignTAStoProspectUpdate: eligibleAccountCount=' +
                    eligibleAccountIds.size()
                );

                if (!eligibleAccountIds.isEmpty() && eligibleAccountIds.size() == 1) {
                    Id jobId = System.enqueueJob(new AccountProspectTasQueueable(eligibleAccountIds));

                    Logger.info(
                        'AccountService.assignTAStoProspectUpdate: submitted AccountProspectTasQueueable, jobId=' +
                        jobId
                    );
                } else if (eligibleAccountIds.size() > 1) {
                    Logger.warn(
                        'AccountService.assignTAStoProspectUpdate: more than one eligible Account found. Queueable not submitted. eligibleAccountCount=' +
                        eligibleAccountIds.size()
                    );
                }

            } catch (Exception e) {
                Logger.error('AccountService.assignTAStoProspectUpdate', e);
                throw e;
            } finally {
                Logger.saveLog();
            }
        }
        
        /**
         * @description Retrieves the Prospect Account record type Id by developer name.
         * @return Prospect Account RecordType Id when found; otherwise null.
         */
        private static Id getProspectRecordTypeId() {
            Map<String, Schema.RecordTypeInfo> recordTypeInfoByDeveloperName =
                Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName();
            
            if (!recordTypeInfoByDeveloperName.containsKey('Prospect')) {
                return null;
            }
            
            return recordTypeInfoByDeveloperName.get('Prospect').getRecordTypeId();
        }
        
        /**
         * @description Retrieves the Customer Account record type Id by developer name.
         * @return Customer Account RecordType Id when found; otherwise null.
         * GC-3021
         */
        private static Id getCustomerRecordTypeId() {
            Map<String, Schema.RecordTypeInfo> recordTypeInfoByDeveloperName =
                Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName();

            if (!recordTypeInfoByDeveloperName.containsKey('Customer')) {
                return null;
            }

            return recordTypeInfoByDeveloperName.get('Customer').getRecordTypeId();
        }
        
        /**
         *
         * GC-3021
         */
        
            private static void enqueueCustomerTasJob(Set<Id> eligibleAccountIds, String sourceMethod) {
            if (eligibleAccountIds == null || eligibleAccountIds.isEmpty()) {
                return;
            }

            Id jobId = System.enqueueJob(new AccountCustomerTasQueueable(eligibleAccountIds));

            Logger.info(
                'AccountService.' + sourceMethod + ': submitted AccountCustomerTasQueueable, jobId=' +
                jobId +
                ', eligibleAccountCount=' +
                eligibleAccountIds.size()
            );
        }
        
        /**
         * @description Handles Account after insert events and enqueues immediate TAS processing
         *              for eligible Oracle-sourced Customer Accounts. Does not depend on nightly batch.
         * @param newAccounts List of newly inserted Account records from trigger context.
         * @return None.
         */
        public static void assignTAStoCustomer(List<Account> newAccounts) {
            try {
                Logger.info('AccountService.assignTAStoCustomer: started');

                if (newAccounts == null || newAccounts.isEmpty()) {
                    Logger.warn('AccountService.assignTAStoCustomer: newAccounts is null or empty');
                    return;
                }

                Id customerRecordTypeId = getCustomerRecordTypeId();

                if (customerRecordTypeId == null) {
                    Logger.warn('AccountService.assignTAStoCustomer: Customer record type not found');
                    return;
                }

                Set<Id> eligibleAccountIds = new Set<Id>();

                for (Account acc : newAccounts) {
                    if (isValidCustomerAccountForTas(acc, customerRecordTypeId)) {
                        eligibleAccountIds.add(acc.Id);
                    }
                }

                Logger.info(
                    'AccountService.assignTAStoCustomer: eligibleAccountCount=' +
                    eligibleAccountIds.size()
                );

                enqueueCustomerTasJob(eligibleAccountIds, 'assignTAStoCustomer');

            } catch (Exception e) {
                Logger.error('AccountService.assignTAStoCustomer', e);
                throw e;
            } finally {
                Logger.saveLog();
            }
        }
        
            
        /**
         * @description Handles Account after update events and enqueues immediate TAS processing
         *              when relevant Customer Account fields change. Does not depend on nightly batch.
         * @param newAccounts List of updated Account records from trigger context.
         * @param oldAccountMap Map of Account Id to old Account record values from trigger context.
         * @return None.
         */
        public static void assignTAStoCustomerUpdate(
            List<Account> newAccounts,
            Map<Id, Account> oldAccountMap
        ) {
            try {
                Logger.info('AccountService.assignTAStoCustomerUpdate: started');

                if (newAccounts == null || newAccounts.isEmpty()) {
                    Logger.warn('AccountService.assignTAStoCustomerUpdate: newAccounts is null or empty');
                    return;
                }

                if (oldAccountMap == null || oldAccountMap.isEmpty()) {
                    Logger.warn('AccountService.assignTAStoCustomerUpdate: oldAccountMap is null or empty');
                    return;
                }

                Id customerRecordTypeId = getCustomerRecordTypeId();

                if (customerRecordTypeId == null) {
                    Logger.warn('AccountService.assignTAStoCustomerUpdate: Customer record type not found');
                    return;
                }

                Set<Id> eligibleAccountIds = new Set<Id>();

                for (Account acc : newAccounts) {
                    Account oldAcc = oldAccountMap.get(acc.Id);

                    if (oldAcc == null) {
                        Logger.warn(
                            'AccountService.assignTAStoCustomerUpdate: old Account record not found for AccountId=' +
                            acc.Id
                        );
                        continue;
                    }

                    if (
                        isValidCustomerAccountForTas(acc, customerRecordTypeId) &&
                        hasRelevantCustomerFieldChanged(acc, oldAcc)
                    ) {
                        eligibleAccountIds.add(acc.Id);
                    }
                }

                Logger.info(
                    'AccountService.assignTAStoCustomerUpdate: eligibleAccountCount=' +
                    eligibleAccountIds.size()
                );

                enqueueCustomerTasJob(eligibleAccountIds, 'assignTAStoCustomerUpdate');

            } catch (Exception e) {
                Logger.error('AccountService.assignTAStoCustomerUpdate', e);
                throw e;
            } finally {
                Logger.saveLog();
            }
        }
        
        /**
         * @description Determines whether an Account has the Prospect record type and all required TAS fields populated.
         * @param acc Account record to validate.
         * @param prospectRecordTypeId Prospect Account record type Id.
         * @return True when the Account is eligible for TAS processing; otherwise false.
         */
        private static Boolean isValidProspectAccount(Account acc, Id prospectRecordTypeId) {
            return acc != null
                && acc.RecordTypeId == prospectRecordTypeId
                && isHealthcareAccount(acc) // part of GCL-4
                && String.isNotBlank(acc.Name)
                && String.isNotBlank(acc.CustomerClassCode__c)
                && String.isNotBlank(acc.OrgIDs__c)//part of GC-3107
                && String.isNotBlank(acc.BillingStreet)
                && String.isNotBlank(acc.BillingCity)
                && String.isNotBlank(acc.BillingCountry)
                && String.isNotBlank(acc.BillingState)
                && String.isNotBlank(acc.BillingPostalCode)
                && acc.Price_List__c != null;
        }

        /**
         * @description Determines whether fields relevant to Prospect TAS processing changed during update.
         * @param acc Updated Account record from trigger context.
         * @param oldAcc Previous Account record values from trigger context.
         * @return True when at least one relevant field changed; otherwise false.
         */
        private static Boolean hasRelevantProspectFieldChanged(Account acc, Account oldAcc) {
            return acc.RecordTypeId != oldAcc.RecordTypeId
                || acc.Name != oldAcc.Name
                || acc.CustomerClassCode__c != oldAcc.CustomerClassCode__c
                || acc.OrgIDs__c != oldAcc.OrgIDs__c
                || acc.BillingStreet != oldAcc.BillingStreet
                || acc.BillingCity != oldAcc.BillingCity
                || acc.BillingCountry != oldAcc.BillingCountry
                || acc.BillingState != oldAcc.BillingState
                || acc.BillingPostalCode != oldAcc.BillingPostalCode
                || acc.Price_List__c != oldAcc.Price_List__c;
        }

        /**
         * @description Determines whether a Customer Account is eligible for realtime TAS validation.
         *              Requires OracleAddressId__c on Account (Address object is not used).
         * @param acc Account record to validate.
         * @param customerRecordTypeId Customer Account record type Id.
         * @return True when the Account is eligible for Customer TAS processing; otherwise false.
         */
        private static Boolean isValidCustomerAccountForTas(Account acc, Id customerRecordTypeId) {
            return acc != null
                && acc.RecordTypeId == customerRecordTypeId
                && !LSAccountService.isLifeSciencesAccount(acc)
                && isOracleSourcedAccount(acc)
                && String.isNotBlank(acc.OracleAddressId__c)
                && String.isNotBlank(acc.CustomerClassCode__c)
                && String.isNotBlank(acc.OrgIDs__c )
                && String.isNotBlank(acc.BillingCity)
                && String.isNotBlank(acc.BillingCountry)
                && String.isNotBlank(acc.BillingState)
                && String.isNotBlank(acc.BillingPostalCode);
        }
            /**
         * @description Determines whether fields relevant to Customer TAS processing changed during update.
         * @param acc Updated Account record from trigger context.
         * @param oldAcc Previous Account record values from trigger context.
         * @return True when at least one relevant field changed; otherwise false.
         */
        private static Boolean hasRelevantCustomerFieldChanged(Account acc, Account oldAcc) {
            return acc.RecordTypeId != oldAcc.RecordTypeId
                || acc.OracleAddressId__c != oldAcc.OracleAddressId__c
                || acc.CustomerClassCode__c != oldAcc.CustomerClassCode__c
                || acc.OrgIDs__c != oldAcc.OrgIDs__c 
                || acc.BillingStreet != oldAcc.BillingStreet
                || acc.BillingCity != oldAcc.BillingCity
                || acc.BillingCountry != oldAcc.BillingCountry
                || acc.BillingState != oldAcc.BillingState
                || acc.BillingPostalCode != oldAcc.BillingPostalCode;
        }

        /**
         * @description Indicates whether an Account was sourced from Oracle.
         * @param acc Account record to evaluate.
         * @return True when AccountSource or SourceSystemID__c indicates Oracle origin.
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
        
        /**
         * @description Invocable method that retries TAS assignment for Prospect Accounts
         *              initiated from Flow. Validates the incoming Account records,
         *              filters eligible Prospect Accounts, and enqueues asynchronous
         *              TAS processing for retry.
         *
         * @param requests List of FlowRequest records containing Account Ids for which
         *                 TAS assignment should be retried.
         *
         * @return None.
         * User story - GC-3091
         */
        public class FlowRequest {
            @InvocableVariable(required=true)
            public Id accountId;
        }
        
        @InvocableMethod(
            label='Retry TAS Assignment'
            description='Retries TAS assignment for a Prospect Account.'
        )
        public static void retryTasAssignmentFromFlow(List<FlowRequest> requests) {
            try {
                System.debug('This is flow');
                Logger.info('AccountService.retryTasAssignmentFromFlow: started');
                
                if (requests == null || requests.isEmpty()) {
                    Logger.warn('AccountService.retryTasAssignmentFromFlow: requests is null or empty');
                    return;
                }
                
                Set<Id> accountIds = new Set<Id>();
                
                for (FlowRequest request : requests) {
                    if (request != null && request.accountId != null) {
                        accountIds.add(request.accountId);
                    }
                }
                
                if (accountIds.isEmpty()) {
                    Logger.warn('AccountService.retryTasAssignmentFromFlow: no Account Ids found');
                    return;
                }
                
                Id prospectRecordTypeId = getProspectRecordTypeId();
                
                if (prospectRecordTypeId == null) {
                    Logger.warn('AccountService.retryTasAssignmentFromFlow: Prospect record type not found');
                    return;
                }
                
                List<Account> accounts = AccountSelector.selectByIds(accountIds);
                
                Set<Id> eligibleAccountIds = new Set<Id>();
                
                for (Account acc : accounts) {
                    //GC-3143 Changed condition to also run if TAS_Assignment_Status__c != 'Assigned'
                    if (isValidProspectAccount(acc, prospectRecordTypeId) && 
                        (acc.TAS_Retry__c == false || acc.TAS_Assignment_Status__c != 'Assigned')
                        
                    ) {
                        eligibleAccountIds.add(acc.Id);
                    }
                }
                
                Logger.info(
                    'AccountService.retryTasAssignmentFromFlow: eligibleAccountCount=' +
                    eligibleAccountIds.size()
                );
                
                if (!eligibleAccountIds.isEmpty()) {
                    Id jobId = System.enqueueJob(new AccountProspectTasQueueable(eligibleAccountIds));
                    
                    Logger.info(
                        'AccountService.retryTasAssignmentFromFlow: submitted AccountProspectTasQueueable, jobId=' +
                        jobId
                    );
                }
                
            } catch (Exception e) {
                Logger.error('AccountService.retryTasAssignmentFromFlow', e);
                throw e;
            } finally {
                Logger.saveLog();
            }
        }

        /**
         * @description Handles Account before insert events and auto-populates OrgIDs__c
         *              on new Prospect Accounts from the running (creating) user's Org Id.
         *              Runs before insert, so fields are set directly on trigger.new - no DML.
         *              Both User.OrgId__c and Account.OrgIDs__c are restricted picklists
         *              sharing the "Org IDs" Global Value Set, so no value-mapping needed.
         * @param newAccounts List of new Account records from trigger context (Trigger.new).
         * @return None.
         * GC-3282
         */
        public static void populateOrgIdOnNewProspect(List<Account> newAccounts) {
            try {
                Logger.info('AccountService.populateOrgIdOnNewProspect: started');

                if (newAccounts == null || newAccounts.isEmpty()) {
                    Logger.warn('AccountService.populateOrgIdOnNewProspect: newAccounts is null or empty');
                    return;
                }

                Id prospectRecordTypeId = getProspectRecordTypeId();

                if (prospectRecordTypeId == null) {
                    Logger.warn('AccountService.populateOrgIdOnNewProspect: Prospect record type not found');
                    return;
                }

                List<Account> prospectsNeedingOrgId = new List<Account>();
                for (Account acc : newAccounts) {
                    if (acc.RecordTypeId == prospectRecordTypeId && String.isBlank(acc.OrgIDs__c)) {
                        prospectsNeedingOrgId.add(acc);
                    }
                }

                Logger.info(
                    'AccountService.populateOrgIdOnNewProspect: eligibleAccountCount=' +
                    prospectsNeedingOrgId.size()
                );

                if (prospectsNeedingOrgId.isEmpty()) {
                    return;
                }

                // All records in this trigger context share the same running user -
                // one query covers the whole batch.
                List<User> runningUserList = [
                    SELECT Id, OrgId__c
                    FROM User
                    WHERE Id = :UserInfo.getUserId()
                    WITH USER_MODE
                    LIMIT 1
                ];

                if (runningUserList.isEmpty() || String.isBlank(runningUserList[0].OrgId__c)) {
                    Logger.warn('AccountService.populateOrgIdOnNewProspect: running user has no Org Id set');
                    return;
                }

                String orgIdValue = runningUserList[0].OrgId__c;

                for (Account acc : prospectsNeedingOrgId) {
                    acc.OrgIDs__c = orgIdValue;
                }

                Logger.info('AccountService.populateOrgIdOnNewProspect: OrgIDs__c populated successfully');

            } catch (Exception e) {
                Logger.error('AccountService.populateOrgIdOnNewProspect', e);
                throw e;
            } finally {
                Logger.saveLog();
            }
        }

        /**
         * @description GW-5320 - Returns Address accounts that may be selected as a Return Order Ship-To.
         * @param parentAccountId Customer Account Id on the Return Order.
         * @return Address accounts matching the Ship-To lookup filter.
         */
        public static List<Account> getShipToAddressAccounts(Id parentAccountId) {
            return AccountSelector.selectShipToAddressAccountsByParentId(parentAccountId);
        }

        /**
         * @description GC-3617. Sets IsPartner on Customer Accounts whose Type is Dealer.
         *              IsPartner cannot be set during insert, so this updates after save.
         * @param newAccounts Accounts from the trigger.
         * @return None.
         */
        public static void enableDealerAccounts(List<Account> newAccounts) {
            if (newAccounts == null || newAccounts.isEmpty()) {
                return;
            }

            Id customerRecordTypeId = getCustomerRecordTypeId();
            List<Account> accountsToEnable = new List<Account>();
            for (Account accountRecord : newAccounts) {
                if (accountRecord != null
                    && accountRecord.RecordTypeId == customerRecordTypeId
                    && accountRecord.Type == 'Dealer'
                    && accountRecord.IsPartner != true) {
                    accountsToEnable.add(new Account(
                        Id = accountRecord.Id,
                        IsPartner = true
                    ));
                }
            }

            if (!accountsToEnable.isEmpty()) {
                update accountsToEnable;
            }
        }

    }