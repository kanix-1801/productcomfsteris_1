/**
 * @description Selector for CustomerPreference__c — SOQL only.
 *              GW-2860 — active IMS preferences by Account + product line date window.
 * @author Uptima
 * @date 2026-07-16
 * @group Selectors
 */
public with sharing class CustomerPreferencesSelector extends SoqlQueryBuilder {
    /**
     * @description GW-4117 - Binds this selector to CustomerPreference__c for SoqlQueryBuilder queries.
     */
    public CustomerPreferencesSelector() {
        this.objectName = 'CustomerPreference__c';
    }

    /**
     * @description Display / evaluation fields for active IMS preference rows.
     */
    private static final String ACTIVE_IMS_FIELDS =
        'Id, Name, PreferenceType__c, PreferenceValue__c, ProductLine__c, StartDate__c, EndDate__c, Account__c, RecordTypeId';

    /**
     * @description Selects active IMS Customer Preference rows for an Account where the product line is
     *              blank (applies to all) or matches the given Asset Product Line, and today is within Start/End.
     *              When productLine is blank (e.g. parent WO with no Asset), only preferences with blank
     *              ProductLine__c are returned.
     * @param accountId Account Id (required)
     * @param recordTypeId CustomerPreference__c RecordType Id (IMS)
     * @param productLine Asset Product Line value; blank returns preferences with blank ProductLine__c only
     * @param asOfDate Date used for StartDate__c / EndDate__c window (typically Date.today())
     * @return Matching preferences ordered by PreferenceType__c, Name
     */
    public static List<CustomerPreference__c> selectActiveImsByAccountAndProductLine(
        Id accountId,
        Id recordTypeId,
        String productLine,
        Date asOfDate
    ) {
        if (accountId == null || recordTypeId == null || asOfDate == null) {
            return new List<CustomerPreference__c>();
        }

        String productLineFilter = String.isBlank(productLine)
            ? ' AND ProductLine__c = null'
            : ' AND (ProductLine__c = null OR ProductLine__c = :productLine)';

        return Database.query(
            'SELECT ' + ACTIVE_IMS_FIELDS +
            ' FROM CustomerPreference__c' +
            ' WHERE Account__c = :accountId' +
            ' AND RecordTypeId = :recordTypeId' +
            ' AND StartDate__c <= :asOfDate' +
            ' AND EndDate__c >= :asOfDate' +
            productLineFilter +
            ' WITH SECURITY_ENFORCED' +
            ' ORDER BY PreferenceType__c ASC NULLS LAST, Name ASC'
        );
    }

    /**
     * @description Same date / product-line filter as selectActiveImsByAccountAndProductLine, narrowed by
     *              PreferenceType__c (e.g. Photos required). LIMIT 1 for existence checks.
     * @param accountId Account Id (required)
     * @param recordTypeId CustomerPreference__c RecordType Id (IMS)
     * @param productLine Asset Product Line value; blank returns preferences with blank ProductLine__c only
     * @param preferenceType PreferenceType__c API value
     * @param asOfDate Date used for Start/End window
     * @return Up to one matching preference (empty when none)
     */
    public static List<CustomerPreference__c> selectActiveImsByAccountProductLineAndType(
        Id accountId,
        Id recordTypeId,
        String productLine,
        String preferenceType,
        Date asOfDate
    ) {
        if (
            accountId == null ||
            recordTypeId == null ||
            asOfDate == null ||
            String.isBlank(preferenceType)
        ) {
            return new List<CustomerPreference__c>();
        }

        String productLineFilter = String.isBlank(productLine)
            ? ' AND ProductLine__c = null'
            : ' AND (ProductLine__c = null OR ProductLine__c = :productLine)';

        return Database.query(
            'SELECT Id, PreferenceValue__c, ProductLine__c' +
            ' FROM CustomerPreference__c' +
            ' WHERE Account__c = :accountId' +
            ' AND RecordTypeId = :recordTypeId' +
            ' AND PreferenceType__c = :preferenceType' +
            ' AND StartDate__c <= :asOfDate' +
            ' AND EndDate__c >= :asOfDate' +
            productLineFilter +
            ' WITH SECURITY_ENFORCED' +
            ' ORDER BY ProductLine__c DESC NULLS LAST' +
            ' LIMIT 1'
        );
    }

    /**
     * @description GW-2891 - Active IMS preference for Account + Preference Type + exact Product Line
     *              (blank Product Line does not match). LIMIT 1 for existence checks.
     * @param accountId Account Id (required)
     * @param recordTypeId CustomerPreference__c RecordType Id (IMS)
     * @param productLine Required Product Line value (exact match)
     * @param preferenceType PreferenceType__c API value
     * @param asOfDate Date used for Start/End window
     * @return Up to one matching preference (empty when none)
     */
    public static List<CustomerPreference__c> selectActiveImsByExactProductLineAndType(
        Id accountId,
        Id recordTypeId,
        String productLine,
        String preferenceType,
        Date asOfDate
    ) {
        if (
            accountId == null ||
            recordTypeId == null ||
            asOfDate == null ||
            String.isBlank(preferenceType) ||
            String.isBlank(productLine)
        ) {
            return new List<CustomerPreference__c>();
        }

        return [
            SELECT Id
            FROM CustomerPreference__c
            WHERE Account__c = :accountId
                AND RecordTypeId = :recordTypeId
                AND PreferenceType__c = :preferenceType
                AND ProductLine__c = :productLine
                AND StartDate__c <= :asOfDate
                AND EndDate__c >= :asOfDate
            WITH SECURITY_ENFORCED
            LIMIT 1
        ];
    }

    /**
     * @description GW-2793 - Active IMS preference for Account + Preference Type within the date window
     *              (no Product Line filter). LIMIT 1.
     * @param accountId Account Id (required)
     * @param recordTypeId CustomerPreference__c RecordType Id (IMS)
     * @param preferenceType PreferenceType__c API value
     * @param asOfDate Date used for Start/End window
     * @return Up to one matching preference including PreferenceValue__c (empty when none)
     */
    public static List<CustomerPreference__c> selectActiveImsByAccountAndType(
        Id accountId,
        Id recordTypeId,
        String preferenceType,
        Date asOfDate
    ) {
        if (
            accountId == null ||
            recordTypeId == null ||
            asOfDate == null ||
            String.isBlank(preferenceType)
        ) {
            return new List<CustomerPreference__c>();
        }

        return [
            SELECT Id, PreferenceType__c, PreferenceValue__c, Account__c, StartDate__c, EndDate__c
            FROM CustomerPreference__c
            WHERE Account__c = :accountId
                AND RecordTypeId = :recordTypeId
                AND PreferenceType__c = :preferenceType
                AND StartDate__c <= :asOfDate
                AND EndDate__c >= :asOfDate
            WITH SECURITY_ENFORCED
            LIMIT 1
        ];
    }
}