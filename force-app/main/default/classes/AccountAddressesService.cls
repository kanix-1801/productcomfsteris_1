/**
 * @author Divya Sree
 * @date 2026/06/05
 *
 * @group Account Management
 *
 * @description
 * Service layer for Account Address retrieval and transformation.
 * Queries Address records via the selector layer and maps them to
 * Aura-enabled wrapper objects for Lightning component consumption.
 */
public with sharing class AccountAddressesService {
    private static final String SCENARIO = 'Account Management';
    private static final String USER_ERROR_MESSAGE = 'Unable to load Addresses.';

    /**
     * @description
     * Test-only flag to force an exception during unit test execution.
     */
    @TestVisible
    private static Boolean throwExceptionForTest = false;

    /**
     * @description
     * Retrieves and wraps Address records for the specified Account.
     * Logs errors and throws an AuraHandledException when retrieval fails.
     *
     * @param accountId Account record Id used to query related Address records.
     * @return List of AccountAddressWrapper objects; empty list when accountId is null.
     */
    public static List<AccountAddressWrapper> getAddresses(Id accountId) {
        List<AccountAddressWrapper> addressList = new List<AccountAddressWrapper>();
        Boolean shouldSaveLog = false;

        if (accountId == null) {
            return addressList;
        }

        try {
            if (throwExceptionForTest) {
                throw new QueryException('Forced exception for unit test.');
            }

            for (SObject addressRecord : AccountAddressesSelector.selectByAccountId(accountId)) {
                addressList.add(new AccountAddressWrapper(addressRecord));
            }
        } catch (Exception exceptionRecord) {
            shouldSaveLog = true;

            Logger.setScenario(SCENARIO);
            Logger.error('Unable to retrieve Addresses. Error: ' + exceptionRecord.getMessage())
                .addTag('Account')
                .addTag('Address')
                .setRecord(new Account(Id = accountId));

            throw new AuraHandledException(USER_ERROR_MESSAGE);
        } finally {
            if (shouldSaveLog) {
                Logger.saveLog();
            }
        }

        return addressList;
    }

    /**
     * @description
     * Aura-enabled wrapper class for Address display data on Account pages.
     */
    public class AccountAddressWrapper {
        @AuraEnabled public Id id;
        @AuraEnabled public String street;
        @AuraEnabled public String addressType;
        @AuraEnabled public String city;
        @AuraEnabled public String state;
        @AuraEnabled public String postalCode;

        /**
         * @description
         * Maps an Address SObject record to wrapper fields for Lightning display.
         *
         * @param addressRecord Address SObject record containing field values.
         */
        public AccountAddressWrapper(SObject addressRecord) {
            id = (Id) addressRecord.get('Id');
            street = (String) addressRecord.get('Street');
            addressType = (String) addressRecord.get('AddressType');
            city = (String) addressRecord.get('City');
            state = (String) addressRecord.get('State');
            postalCode = (String) addressRecord.get('PostalCode');
        }
    }
}