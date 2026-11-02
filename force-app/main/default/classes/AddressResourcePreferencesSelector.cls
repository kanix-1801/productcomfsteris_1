/**
 * @author Sagar Anand
 * @date 2026-10-29
 * @description GW-6099 - Selector for AddressResourcePreference__c (resource preferences of an Address account).
 *              Queries run in USER_MODE through SoqlQueryBuilder / DynamicSoqlQuery.
 * @group Field Service
 */
public with sharing class AddressResourcePreferencesSelector extends SoqlQueryBuilder {
    /** @description Fields needed to resolve the preferred resources of an Address account. */
    private static final List<String> PREFERENCE_FIELDS = new List<String>{
        'Id',
        'AddressAccount__c',
        'ServiceResource__c',
        'PreferenceLevel__c'
    };

    /**
     * @description Binds this selector to AddressResourcePreference__c for SoqlQueryBuilder queries.
     */
    public AddressResourcePreferencesSelector() {
        this.objectName = 'AddressResourcePreference__c';
    }

    /**
     * @description Selects the resource preferences of the given Address accounts with the given level.
     * @param addressAccountIdSet Address Account Ids (AddressAccount__c)
     * @param preferenceLevel PreferenceLevel__c value (e.g. 'Preferred')
     * @return Matching preferences (empty when an input is missing)
     * @example
     * List<AddressResourcePreference__c> preferences = AddressResourcePreferencesSelector
     *     .selectByAddressAccountIdsAndLevel(accountIds, 'Preferred');
     */
    public static List<AddressResourcePreference__c> selectByAddressAccountIdsAndLevel(
        Set<Id> addressAccountIdSet,
        String preferenceLevel
    ) {
        List<String> addressAccountIdList = new List<String>();
        if (addressAccountIdSet != null) {
            for (Id addressAccountId : addressAccountIdSet) {
                if (addressAccountId != null) {
                    addressAccountIdList.add(addressAccountId);
                }
            }
        }
        if (addressAccountIdList.isEmpty() || String.isBlank(preferenceLevel)) {
            return new List<AddressResourcePreference__c>();
        }

        return (List<AddressResourcePreference__c>) new AddressResourcePreferencesSelector()
            .selectFields(PREFERENCE_FIELDS)
            .whereIn('AddressAccount__c', addressAccountIdList)
            .whereEquals('PreferenceLevel__c', preferenceLevel)
            .execute();
    }
}