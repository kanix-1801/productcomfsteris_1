/**
 * @author Abhishek Mishra
 * @date 04-06-2026
 * @description Trigger handler for Account insert/update events.
 *
 *              Responsibilities:
 *              1. Receive Account trigger context from AccountTrigger.
 *              2. Control same-context recursion for after insert and after update events.
 *              3. Delegate Prospect and Customer Account TAS processing to AccountService.-GC-3021
 *              4. Enqueue Prospect Account Sales Connection sync via Boomi.-GC-3441
 *              5. Enable Customer Accounts with Type Dealer as partner accounts.-GC-3617
 */
public with sharing class AccountTriggerHandler extends TriggerHandler { 

    /**
     * @description Handles Account after insert trigger events and delegates
     *              Prospect and Customer Account TAS processing to AccountService.
     *              GC-3617 enables Dealer Customer Accounts as partner accounts.
     * @return None.
     */
    @TestVisible
    protected override void afterInsert() {
        if (!TriggerControl.enterAfterInsert(Account.SObjectType)) {
            return;
        }
        List<Account> newAccounts = (List<Account>) Trigger.new;
        // GC-3617 - IsPartner is not createable, so enable after the Account exists.
        AccountService.enableDealerAccounts(newAccounts);
        if(!newAccounts.isEmpty()) {
            if(newAccounts[0].CustomerClassCode__c == 'HC') {
                AccountService.assignTAStoProspect(newAccounts);
                AccountService.assignTAStoCustomer(newAccounts);
            } else if(LSAccountService.isLifeSciencesAccount(newAccounts[0])){
                LSAccountService.assignTAStoProspect(newAccounts);   // GCL-4: Life Sciences Prospect Account real-time TAS validation. Class code Life Science = SC.
                LSAccountService.assignTAStoCustomer(newAccounts);  //GCL- 83 Life science Prospect/Customer Tas Integration
            }
        }
        
    }

    /**
     * @description Handles Account after update trigger events and delegates
     *               Prospect and Customer Account TAS processing to AccountService.
     *               GC-3441 also enqueues Prospect Account SC sync when entry criteria match.
     *               GC-3617 enables Customer Accounts whose Type is Dealer.
     * @return None.
     */
    @TestVisible
    protected override void afterUpdate() {
        if (!TriggerControl.enterAfterUpdate(Account.SObjectType)) {
            return;
        }

        List<Account> updatedAccounts = (List<Account>) Trigger.new;
        Map<Id, Account> oldAccountMap = (Map<Id, Account>) Trigger.oldMap;
        // GC-3617 - covers Boomi updates that arrive as Customer + Type Dealer.
        AccountService.enableDealerAccounts(updatedAccounts);
        if (!updatedAccounts.isEmpty()) {
            if (updatedAccounts[0].CustomerClassCode__c == 'HC') {
                AccountService.assignTAStoCustomerUpdate(updatedAccounts, oldAccountMap);
            } else if (LSAccountService.isLifeSciencesAccount(updatedAccounts[0])) {
                //GCL- 83 Life science Prospect/Customer Tas Integration
                LSAccountService.assignTAStoCustomerUpdate(updatedAccounts, oldAccountMap);
            }
        }        // GC-3441 - Prospect Account real-time sync to Sales Connection via Boomi.
        ProspectAccountScSyncService.enqueueEligibleAccounts(
            updatedAccounts,
            oldAccountMap
        );
        
    }

    /** GC-3282
     * @description Handles Account before insert trigger events and delegates
     *              Org Id population for new Prospect Accounts to AccountService.
     * @return None.
     */
    @TestVisible
    protected override void beforeInsert() {
        List<Account> newAccounts = (List<Account>) Trigger.new;
        AccountService.populateOrgIdOnNewProspect(newAccounts);
    }
}