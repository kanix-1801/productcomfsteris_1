/**
 * @author Divya Sree
 * @date 2026/06/05
 *
 * @group Account Management
 *
 * @description
 * Controller for the Account Addresses Lightning Web Component.
 * Exposes cacheable Aura-enabled methods for retrieving address records
 * associated with an Account.
 */
public without sharing class AccountAddressesController {

    /**
     * @description
     * Retrieves address records for the specified Account Id.
     *
     * @param accountId Account record Id used to query related Address records.
     * @return List of AccountAddressWrapper objects containing address display data.
     */
    @AuraEnabled(cacheable=true)
    public static List<AccountAddressesService.AccountAddressWrapper> getAddresses(Id accountId) {
        return AccountAddressesService.getAddresses(accountId);
    }
}