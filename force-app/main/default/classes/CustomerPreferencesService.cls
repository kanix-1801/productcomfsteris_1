/**
 * @description Service for CustomerPreference__c — orchestration entry point for other layers/objects.
 *              GW-2860 — Controllers and non-CustomerPreference services must call this class
 *              (not CustomerPreferencesSelector) per STERIS Case-routing layering practice.
 * @author Uptima
 * @date 2026-07-16
 * @group Services
 */
public with sharing class CustomerPreferencesService {
    @TestVisible
    private interface ICustomerPreferencesSelector {
        List<CustomerPreference__c> selectActiveImsByAccountAndProductLine(
            Id accountId,
            Id recordTypeId,
            String productLine,
            Date asOfDate
        );
        List<CustomerPreference__c> selectActiveImsByAccountProductLineAndType(
            Id accountId,
            Id recordTypeId,
            String productLine,
            String preferenceType,
            Date asOfDate
        );
        List<CustomerPreference__c> selectActiveImsByExactProductLineAndType(
            Id accountId,
            Id recordTypeId,
            String productLine,
            String preferenceType,
            Date asOfDate
        );
        List<CustomerPreference__c> selectActiveImsByAccountAndType(
            Id accountId,
            Id recordTypeId,
            String preferenceType,
            Date asOfDate
        );
    }

    private class DefaultCustomerPreferencesSelector implements ICustomerPreferencesSelector {
        public List<CustomerPreference__c> selectActiveImsByAccountAndProductLine(
            Id accountId,
            Id recordTypeId,
            String productLine,
            Date asOfDate
        ) {
            return CustomerPreferencesSelector.selectActiveImsByAccountAndProductLine(
                accountId,
                recordTypeId,
                productLine,
                asOfDate
            );
        }

        public List<CustomerPreference__c> selectActiveImsByAccountProductLineAndType(
            Id accountId,
            Id recordTypeId,
            String productLine,
            String preferenceType,
            Date asOfDate
        ) {
            return CustomerPreferencesSelector.selectActiveImsByAccountProductLineAndType(
                accountId,
                recordTypeId,
                productLine,
                preferenceType,
                asOfDate
            );
        }

        public List<CustomerPreference__c> selectActiveImsByExactProductLineAndType(
            Id accountId,
            Id recordTypeId,
            String productLine,
            String preferenceType,
            Date asOfDate
        ) {
            return CustomerPreferencesSelector.selectActiveImsByExactProductLineAndType(
                accountId,
                recordTypeId,
                productLine,
                preferenceType,
                asOfDate
            );
        }

        public List<CustomerPreference__c> selectActiveImsByAccountAndType(
            Id accountId,
            Id recordTypeId,
            String preferenceType,
            Date asOfDate
        ) {
            return CustomerPreferencesSelector.selectActiveImsByAccountAndType(
                accountId,
                recordTypeId,
                preferenceType,
                asOfDate
            );
        }
    }

    @TestVisible
    private static ICustomerPreferencesSelector selectorOverride;

    private static ICustomerPreferencesSelector selector() {
        return selectorOverride == null
            ? new DefaultCustomerPreferencesSelector()
            : selectorOverride;
    }

    /** PreferenceType__c value that drives Photos Required on Repair Center Work Orders. */
    @TestVisible
    private static final String PREFERENCE_TYPE_PHOTOS_REQUIRED = 'Photos required';

    /**
     * PreferenceType__c API value for FedEx / carrier service level (GW-2793).
     * Org picklist label may differ; value is "Carrier Service level".
     */
    @TestVisible
    private static final String PREFERENCE_TYPE_CARRIER_SERVICE_LEVEL = 'Carrier Service level';

    /** CustomerPreference__c RecordType DeveloperName for IMS preferences. */
    @TestVisible
    private static final String RECORD_TYPE_IMS = 'IMSCustomerPreference';

    /** Test hook to simulate missing IMS record type. */
    @TestVisible
    private static Boolean forceMissingImsRecordType = false;

    /**
     * @description Returns active IMS Customer Preferences for the Account using the shared product-line
     *              filter. When productLine is blank, only preferences with blank ProductLine__c are returned;
     *              otherwise blank ProductLine__c OR an exact match. Date window is Date.today().
     * @param accountId Account Id
     * @param productLine Asset Product Line (blank for parent WO / no Asset)
     * @return Active matching CustomerPreference__c rows (empty when none or when IMS RT missing)
     */
    public static List<CustomerPreference__c> getActiveImsPreferences(Id accountId, String productLine) {
        if (accountId == null) {
            return new List<CustomerPreference__c>();
        }

        try {
            Id imsRecordTypeId = getImsRecordTypeId();
            if (imsRecordTypeId == null) {
                Logger.warn('CustomerPreferencesService.getActiveImsPreferences: IMS record type not found.');
                return new List<CustomerPreference__c>();
            }

            List<CustomerPreference__c> preferences =
                selector().selectActiveImsByAccountAndProductLine(
                    accountId,
                    imsRecordTypeId,
                    productLine,
                    Date.today()
                );
            Logger.fine(
                new LogMessage(
                    'Retrieved {0} active IMS CustomerPreference__c for Account {1}',
                    preferences.size(),
                    accountId
                )
            );
            return preferences;
        } catch (Exception e) {
            Logger.error(
                new LogMessage(
                    'CustomerPreferencesService.getActiveImsPreferences failed for Account {0}: {1}',
                    accountId,
                    e.getMessage()
                ),
                e
            );
            throw new CustomerPreferencesServiceException(
                'Failed to retrieve active IMS customer preferences: ' + e.getMessage(),
                e
            );
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description True when an active IMS "Photos required" preference exists for the Account under the
     *              shared product-line filter.
     * @param accountId Account Id
     * @param productLine Asset Product Line
     * @return true when at least one matching preference exists
     */
    public static Boolean isPhotosRequired(Id accountId, String productLine) {
        if (accountId == null) {
            return false;
        }

        try {
            Id imsRecordTypeId = getImsRecordTypeId();
            if (imsRecordTypeId == null) {
                return false;
            }

            List<CustomerPreference__c> preferences =
                selector().selectActiveImsByAccountProductLineAndType(
                    accountId,
                    imsRecordTypeId,
                    productLine,
                    PREFERENCE_TYPE_PHOTOS_REQUIRED,
                    Date.today()
                );
            return !preferences.isEmpty();
        } catch (Exception e) {
            Logger.error(
                new LogMessage(
                    'CustomerPreferencesService.isPhotosRequired failed for Account {0}: {1}',
                    accountId,
                    e.getMessage()
                ),
                e
            );
            throw new CustomerPreferencesServiceException(
                'Failed to evaluate Photos Required preference: ' + e.getMessage(),
                e
            );
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description GW-2891 - True when an active IMS "Photos required" preference exists for the
     *              Account with an exact Product Line match (blank Product Line does not qualify).
     * @param accountId Account Id
     * @param productLine Required Product Line (e.g. Instrument)
     * @return true when at least one matching preference exists
     */
    public static Boolean isPhotosRequiredExactProductLine(Id accountId, String productLine) {
        if (accountId == null || String.isBlank(productLine)) {
            return false;
        }

        try {
            Id imsRecordTypeId = getImsRecordTypeId();
            if (imsRecordTypeId == null) {
                return false;
            }

            List<CustomerPreference__c> preferences =
                selector().selectActiveImsByExactProductLineAndType(
                    accountId,
                    imsRecordTypeId,
                    productLine,
                    PREFERENCE_TYPE_PHOTOS_REQUIRED,
                    Date.today()
                );
            return !preferences.isEmpty();
        } catch (Exception e) {
            Logger.error(
                new LogMessage(
                    'CustomerPreferencesService.isPhotosRequiredExactProductLine failed for Account {0}: {1}',
                    accountId,
                    e.getMessage()
                ),
                e
            );
            throw new CustomerPreferencesServiceException(
                'Failed to evaluate Photos Required preference: ' + e.getMessage(),
                e
            );
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description GW-2793 - Returns PreferenceValue__c for the active IMS "Carrier Service level"
     *              preference for the Account (StartDate__c <= today <= EndDate__c). No Product Line filter.
     * @param accountId Account Id
     * @return Preference value string, or null when none / blank account / IMS RT missing
     */
    public static String getCarrierServiceLevel(Id accountId) {
        if (accountId == null) {
            return null;
        }

        try {
            Id imsRecordTypeId = getImsRecordTypeId();
            if (imsRecordTypeId == null) {
                Logger.warn(
                    'CustomerPreferencesService.getCarrierServiceLevel: IMS record type not found.'
                );
                return null;
            }

            List<CustomerPreference__c> preferences =
                selector().selectActiveImsByAccountAndType(
                    accountId,
                    imsRecordTypeId,
                    PREFERENCE_TYPE_CARRIER_SERVICE_LEVEL,
                    Date.today()
                );
            if (preferences.isEmpty()) {
                return null;
            }
            String preferenceValue = preferences[0].PreferenceValue__c;
            return String.isBlank(preferenceValue) ? null : preferenceValue.trim();
        } catch (Exception e) {
            Logger.error(
                new LogMessage(
                    'CustomerPreferencesService.getCarrierServiceLevel failed for Account {0}: {1}',
                    accountId,
                    e.getMessage()
                ),
                e
            );
            throw new CustomerPreferencesServiceException(
                'Failed to retrieve Carrier Service level preference: ' + e.getMessage(),
                e
            );
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description Resolves IMSCustomerPreference RecordType Id; null when not available in the org.
     * @return RecordType Id or null
     */
    @TestVisible
    private static Id getImsRecordTypeId() {
        if (forceMissingImsRecordType) {
            return null;
        }
        Map<String, Schema.RecordTypeInfo> recordTypes =
            Schema.SObjectType.CustomerPreference__c.getRecordTypeInfosByDeveloperName();
        Schema.RecordTypeInfo imsInfo = recordTypes.get(RECORD_TYPE_IMS);
        return imsInfo == null ? null : imsInfo.getRecordTypeId();
    }

    /**
     * @description GW-4117 - Loads active IMS Pre-Approval Limit preferences for the given accounts and product lines.
     * @param accountIds Account Ids on the Quotes being evaluated.
     * @param productLines Product lines stamped on Product Serviced quote lines.
     * @param asOfDate Date used for the Start Date / End Date window.
     * @param preferenceType Customer Preference type, such as Pre-Approval Limit.
     * @param recordTypeDeveloperName Customer Preference record type developer name.
     * @return Matching preferences, or an empty list when a required input is missing.
     */
    public static List<CustomerPreference__c> selectActivePreApprovalLimits(
        Set<Id> accountIds,
        Set<String> productLines,
        Date asOfDate,
        String preferenceType,
        String recordTypeDeveloperName
    ) {
        if (
            accountIds == null ||
            accountIds.isEmpty() ||
            productLines == null ||
            productLines.isEmpty() ||
            asOfDate == null ||
            String.isBlank(preferenceType) ||
            String.isBlank(recordTypeDeveloperName)
        ) {
            return new List<CustomerPreference__c>();
        }
        List<String> productLineNames = new List<String>();
        for (String productLine : productLines) {
            if (String.isNotBlank(productLine)) {
                productLineNames.add(productLine);
            }
        }
        if (productLineNames.isEmpty()) {
            return new List<CustomerPreference__c>();
        }
        SoqlQueryBuilder query = new CustomerPreferencesSelector()
            .selectFields(
                new List<String>{ 'Account__c', 'ProductLine__c', 'PreferenceValue__c' }
            );
        List<String> accountFilterNumbers = new List<String>();
        Integer filterNumber = 1;
        for (Id accountId : accountIds) {
            if (accountId == null) {
                continue;
            }
            query.whereEquals('Account__c', accountId);
            accountFilterNumbers.add(String.valueOf(filterNumber));
            filterNumber++;
        }
        if (accountFilterNumbers.isEmpty()) {
            return new List<CustomerPreference__c>();
        }
        List<String> productLineFilterNumbers = new List<String>();
        for (String productLine : productLineNames) {
            query.whereEquals('ProductLine__c', productLine);
            productLineFilterNumbers.add(String.valueOf(filterNumber));
            filterNumber++;
        }
        query.whereEquals('PreferenceType__c', preferenceType);
        Integer preferenceTypeFilter = filterNumber++;
        query.whereEquals('RecordType.DeveloperName', recordTypeDeveloperName);
        Integer recordTypeFilter = filterNumber++;
        query.whereField('StartDate__c', '<=', asOfDate);
        Integer startDateFilter = filterNumber++;
        query.whereField('EndDate__c', '>=', asOfDate);
        Integer endDateFilter = filterNumber++;
        String accountLogic = accountFilterNumbers.size() == 1
            ? accountFilterNumbers[0]
            : '(' + String.join(accountFilterNumbers, ' OR ') + ')';
        String productLineLogic = productLineFilterNumbers.size() == 1
            ? productLineFilterNumbers[0]
            : '(' + String.join(productLineFilterNumbers, ' OR ') + ')';
        query.withFilterLogic(
            accountLogic +
                ' AND ' +
                preferenceTypeFilter +
                ' AND ' +
                recordTypeFilter +
                ' AND ' +
                productLineLogic +
                ' AND ' +
                startDateFilter +
                ' AND ' +
                endDateFilter
        );
        return (List<CustomerPreference__c>) query.execute();
    }

    /**
     * @description Service-layer exception for CustomerPreference__c orchestration failures.
     */
    public class CustomerPreferencesServiceException extends Exception {
    }
}