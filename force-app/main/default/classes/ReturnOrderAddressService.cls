/**
 * @description Maps account billing addresses for Return Orders and Work Orders.
 */
public with sharing class ReturnOrderAddressService {
    public class AddressValues {
        public String street;
        public String city;
        public String state;
        public String stateCode;
        public String postalCode;
        public String country;
        public String countryCode;

        public Boolean isPopulated() {
            return String.isNotBlank(street)
                || String.isNotBlank(city)
                || String.isNotBlank(state)
                || String.isNotBlank(postalCode)
                || String.isNotBlank(country);
        }
    }

    /**
     * @description Sets Return Order Ship From from the customer account billing address.
     */
    public static void applyBillToAddressToReturnOrder(ReturnOrder returnOrder, Id accountId) {
        if (returnOrder == null || accountId == null) {
            return;
        }

        applyShipFromAddress(returnOrder, resolveAccountBillingAddress(accountId));
    }

    /**
     * @description Sets Work Order ship address from the Return Order billing address
     *              and bill-to from the parent account billing address.
     */
    public static void applyWorkOrderAddressesFromReturnOrder(
        WorkOrder workOrder,
        ReturnOrder returnOrder
    ) {
        if (workOrder == null || returnOrder == null) {
            return;
        }

        AddressValues shipAddress = resolveReturnOrderShipAddress(returnOrder);
        if (!shipAddress.isPopulated()) {
            shipAddress = resolveAccountBillingAddress(returnOrder.AccountId);
        }
        applyWorkOrderShipAddress(workOrder, shipAddress);
        applyWorkOrderBillToAddress(
            workOrder,
            resolveParentAccountBillingAddress(returnOrder.AccountId)
        );
    }

    public static AddressValues resolveAccountBillingAddress(Id accountId) {
        if (accountId == null) {
            return new AddressValues();
        }

        List<Account> accounts = [
            SELECT
                BillingStreet,
                BillingCity,
                BillingState,
                BillingPostalCode,
                BillingCountry
            FROM Account
            WHERE Id = :accountId
            WITH USER_MODE
            LIMIT 1
        ];
        if (accounts.isEmpty()) {
            return new AddressValues();
        }

        return buildAddressValuesFromBillingAddress(accounts[0]);
    }

    public static AddressValues resolveParentAccountBillingAddress(Id customerAccountId) {
        if (customerAccountId == null) {
            return new AddressValues();
        }

        List<Account> accounts = [
            SELECT
                ParentId,
                Parent.BillingStreet,
                Parent.BillingCity,
                Parent.BillingState,
                Parent.BillingPostalCode,
                Parent.BillingCountry
            FROM Account
            WHERE Id = :customerAccountId
            WITH USER_MODE
            LIMIT 1
        ];
        if (accounts.isEmpty() || accounts[0].ParentId == null) {
            return new AddressValues();
        }

        Account parentAccount = accounts[0].Parent;
        AddressValues values = new AddressValues();
        values.street = parentAccount.BillingStreet;
        values.city = parentAccount.BillingCity;
        values.state = parentAccount.BillingState;
        values.postalCode = parentAccount.BillingPostalCode;
        values.country = parentAccount.BillingCountry;
        values.stateCode = normalizeStateCode(values.state);
        values.countryCode = normalizeCountryCode(values.country);
        return values;
    }

    private static AddressValues buildAddressValuesFromBillingAddress(Account account) {
        AddressValues values = new AddressValues();
        if (account == null) {
            return values;
        }

        values.street = account.BillingStreet;
        values.city = account.BillingCity;
        values.state = account.BillingState;
        values.postalCode = account.BillingPostalCode;
        values.country = account.BillingCountry;
        values.stateCode = normalizeStateCode(values.state);
        values.countryCode = normalizeCountryCode(values.country);
        return values;
    }

    private static AddressValues resolveReturnOrderShipAddress(ReturnOrder returnOrder) {
        AddressValues values = new AddressValues();
        if (returnOrder == null) {
            return values;
        }

        values.street = returnOrder.ShipFromStreet;
        values.city = returnOrder.ShipFromCity;
        values.state = String.isNotBlank(returnOrder.ShipFromStateCode)
            ? returnOrder.ShipFromStateCode
            : returnOrder.ShipFromState;
        values.stateCode = returnOrder.ShipFromStateCode;
        values.postalCode = returnOrder.ShipFromPostalCode;
        values.country = String.isNotBlank(returnOrder.ShipFromCountryCode)
            ? returnOrder.ShipFromCountryCode
            : returnOrder.ShipFromCountry;
        values.countryCode = returnOrder.ShipFromCountryCode;
        return values;
    }

    private static String normalizeStateCode(String value) {
        if (String.isBlank(value)) {
            return null;
        }
        String trimmed = value.trim();
        // Compound address StateCode rejects full state names (ISO mismatch).
        return trimmed.length() <= 3 ? trimmed.toUpperCase() : null;
    }

    private static String normalizeCountryCode(String value) {
        if (String.isBlank(value)) {
            return null;
        }
        String trimmed = value.trim();
        return trimmed.length() <= 3 ? trimmed.toUpperCase() : null;
    }

    private static void applyShipFromAddress(SObject record, AddressValues values) {
        if (record == null || values == null || !values.isPopulated()) {
            return;
        }

        setFieldIfCreateable(record, 'ShipFromStreet', values.street);
        setFieldIfCreateable(record, 'ShipFromCity', values.city);
        setFieldIfCreateable(record, 'ShipFromPostalCode', values.postalCode);
        setFieldIfCreateable(record, 'ShipFromState', values.state);
        setFieldIfCreateable(record, 'ShipFromCountry', values.country);
        setFieldIfCreateable(record, 'ShipFromStateCode', values.stateCode);
        setFieldIfCreateable(record, 'ShipFromCountryCode', values.countryCode);
    }

    private static void applyWorkOrderShipAddress(WorkOrder workOrder, AddressValues values) {
        if (workOrder == null || values == null || !values.isPopulated()) {
            return;
        }

        setFieldIfCreateable(workOrder, 'Street', values.street);
        setFieldIfCreateable(workOrder, 'City', values.city);
        setFieldIfCreateable(workOrder, 'PostalCode', values.postalCode);
        setFieldIfCreateable(workOrder, 'State', values.state);
        setFieldIfCreateable(workOrder, 'Country', values.country);
        setFieldIfCreateable(workOrder, 'StateCode', normalizeStateCode(values.stateCode));
        setFieldIfCreateable(workOrder, 'CountryCode', normalizeCountryCode(values.countryCode));
    }

    private static void applyWorkOrderBillToAddress(WorkOrder workOrder, AddressValues values) {
        applyBillToAddressValues(workOrder, values);
    }

    /**
     * @description GW-5492 - Applies Bill-To Address compound fields on a Work Order.
     * @param workOrder Target Work Order
     * @param values Address values
     */
    public static void applyBillToAddressValues(WorkOrder workOrder, AddressValues values) {
        if (workOrder == null || values == null || !values.isPopulated()) {
            return;
        }

        setFieldIfCreateable(workOrder, 'BillToAddress__Street__s', values.street);
        setFieldIfCreateable(workOrder, 'BillToAddress__City__s', values.city);
        setFieldIfCreateable(workOrder, 'BillToAddress__PostalCode__s', values.postalCode);
        String stateCode = String.isNotBlank(values.stateCode)
            ? normalizeStateCode(values.stateCode)
            : normalizeStateCode(values.state);
        String countryCode = String.isNotBlank(values.countryCode)
            ? normalizeCountryCode(values.countryCode)
            : normalizeCountryCode(values.country);
        setFieldIfCreateable(workOrder, 'BillToAddress__StateCode__s', stateCode);
        setFieldIfCreateable(workOrder, 'BillToAddress__CountryCode__s', countryCode);
    }

    private static void setFieldIfCreateable(SObject record, String fieldName, String value) {
        if (record == null || String.isBlank(fieldName) || String.isBlank(value)) {
            return;
        }

        Map<String, Schema.SObjectField> fieldMap = record.getSObjectType().getDescribe().fields.getMap();
        if (!fieldMap.containsKey(fieldName)) {
            return;
        }

        Schema.DescribeFieldResult fieldDescribe = fieldMap.get(fieldName).getDescribe();
        if (!fieldDescribe.isCreateable() && !fieldDescribe.isUpdateable()) {
            return;
        }

        record.put(fieldName, value.trim());
    }
}