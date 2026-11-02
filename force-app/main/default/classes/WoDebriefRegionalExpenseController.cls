/**
 * @description Resolves country- and business-unit-specific expense types and incremental pricing for ES debrief.
 *              without sharing so technicians can match Account Customer Class Code they do not own.
 * @group Work Order Debrief
 * @see woDebriefES
 */
public without sharing class WoDebriefRegionalExpenseController {
    /**
     * @description Expense type list and incremental pricing bands for a Work Order.
     */
    public class ExpenseDebriefConfig {
        /** @description Allowed Expense.ExpenseType values; empty means show all types. */
        @AuraEnabled public List<String> allowedTypes;
        /** @description Regional Control maximum expense amount; null means no cap. */
        @AuraEnabled public Decimal maximumPrice;
        /** @description Incremental quantity bands. */
        @AuraEnabled public List<PricingBand> pricingRules;

        /**
         * @description Creates an empty unrestricted config.
         */
        public ExpenseDebriefConfig() {
            this.allowedTypes = new List<String>();
            this.maximumPrice = null;
            this.pricingRules = new List<PricingBand>();
        }
    }

    /**
     * @description One incremental pricing band.
     */
    public class PricingBand {
        /** @description First quantity unit in the band. */
        @AuraEnabled public Decimal startingQty;
        /** @description Last quantity unit; null means no upper limit. */
        @AuraEnabled public Decimal endingQty;
        /** @description Rate for units in this band. */
        @AuraEnabled public Decimal rate;
    }

    /**
     * @description Returns allowed Expense.ExpenseType values for a Work Order.
     *              An empty list means no Regional Control match — the LWC shows all types.
     * @param workOrderId Work Order Id
     * @param cacheBust Cache-busting token from the LWC
     * @return Allowed expense type API values, or an empty list when unrestricted
     */
    @AuraEnabled(cacheable=true)
    public static List<String> resolveExpenseTypes(Id workOrderId, String cacheBust) {
        return resolveExpenseDebrief(workOrderId, cacheBust).allowedTypes;
    }

    /**
     * @description Returns allowed expense types and incremental pricing for a Work Order.
     * @param workOrderId Work Order Id
     * @param cacheBust Cache-busting token from the LWC
     * @return Debrief expense config
     */
    @AuraEnabled(cacheable=true)
    public static ExpenseDebriefConfig resolveExpenseDebrief(Id workOrderId, String cacheBust) {
        ExpenseDebriefConfig config = new ExpenseDebriefConfig();
        Regional_Control__c control = matchRegionalControl(workOrderId);
        if (control == null) {
            return config;
        }

        config.maximumPrice = control.MaximumPrice__c;
        config.allowedTypes = allowedTypesForControl(control.Id);
        config.pricingRules = pricingBandsForControl(control.Id);
        return config;
    }

    /**
     * @description Matches the oldest active Regional Control for the Work Order country and account class.
     * @param workOrderId Work Order Id
     * @return Matching Regional Control, or null
     */
    private static Regional_Control__c matchRegionalControl(Id workOrderId) {
        if (workOrderId == null) {
            return null;
        }

        List<WorkOrder> workOrders = [
            SELECT Id, Country, AccountId, Account.CustomerClassCode__c
            FROM WorkOrder
            WHERE Id = :workOrderId
            LIMIT 1
        ];
        if (workOrders.isEmpty()) {
            return null;
        }

        WorkOrder workOrder = workOrders[0];
        String businessUnit = workOrder.Account?.CustomerClassCode__c;
        if (String.isBlank(businessUnit) && workOrder.AccountId != null) {
            List<Account> accounts = [
                SELECT CustomerClassCode__c
                FROM Account
                WHERE Id = :workOrder.AccountId
                LIMIT 1
            ];
            if (!accounts.isEmpty()) {
                businessUnit = accounts[0].CustomerClassCode__c;
            }
        }
        String country = workOrder.Country;
        if (String.isBlank(businessUnit) || String.isBlank(country)) {
            return null;
        }

        List<Regional_Control__c> controls =
            RegionalControlSelector.selectByBusinessUnitAndCountry(businessUnit, country);
        return controls.isEmpty() ? null : controls[0];
    }

    /**
     * @description Parses Expense Type allowed values for a Regional Control.
     * @param controlId Regional Control Id
     * @return Allowed type API values
     */
    private static List<String> allowedTypesForControl(Id controlId) {
        List<String> allowedValues = new List<String>();
        List<Regional_Control_Setting__c> settings =
            RegionalControlSelector.selectExpenseTypeSettingsByControlIds(new Set<Id>{ controlId });
        if (settings.isEmpty() || String.isBlank(settings[0].AllowedValues__c)) {
            return allowedValues;
        }
        for (String value : settings[0].AllowedValues__c.split(';')) {
            String trimmed = value == null ? null : value.trim();
            if (String.isNotBlank(trimmed)) {
                allowedValues.add(trimmed);
            }
        }
        return allowedValues;
    }

    /**
     * @description Maps Pricing Rule records to Aura-enabled bands.
     * @param controlId Regional Control Id
     * @return Incremental pricing bands
     */
    private static List<PricingBand> pricingBandsForControl(Id controlId) {
        List<PricingBand> bands = new List<PricingBand>();
        for (Pricing_Rule__c rule : RegionalControlSelector.selectPricingRulesByControlIds(new Set<Id>{ controlId })) {
            PricingBand band = new PricingBand();
            band.startingQty = rule.StartingQuantity__c;
            band.endingQty = rule.EndingQuantity__c;
            band.rate = rule.Rate__c;
            bands.add(band);
        }
        return bands;
    }

    /**
     * @description Billable Amount, Override, and Override Code for one Expense.
     *              Field Service GraphQL/related-list often omit these custom fields.
     */
    public class ExpenseBillableFields {
        /** @description Expense Id. */
        @AuraEnabled public Id id;
        /** @description OverrideCode__c picklist value. */
        @AuraEnabled public String overrideCode;
        /** @description BillableAmount__c. */
        @AuraEnabled public Decimal billableAmount;
        /** @description OverrideBillableAmount__c. */
        @AuraEnabled public Boolean overrideBillableAmount;
    }

    /**
     * @description Returns billable custom fields for Expenses on a Work Order.
     *              Used by debrief LWCs because Field Service uiapi often returns those
     *              fields blank until the mobile metadata cache refreshes.
     * @param workOrderId Work Order Id
     * @return Billable field rows
     */
    @AuraEnabled
    public static List<ExpenseBillableFields> listExpenseBillableFields(Id workOrderId) {
        List<ExpenseBillableFields> rows = new List<ExpenseBillableFields>();
        if (workOrderId == null) {
            return rows;
        }
        try {
            for (Expense record : [
                SELECT Id, OverrideCode__c, BillableAmount__c, OverrideBillableAmount__c
                FROM Expense
                WHERE WorkOrderId = :workOrderId
            ]) {
                ExpenseBillableFields row = new ExpenseBillableFields();
                row.id = record.Id;
                row.overrideCode = record.OverrideCode__c;
                row.billableAmount = record.BillableAmount__c;
                row.overrideBillableAmount = record.OverrideBillableAmount__c == true;
                rows.add(row);
            }
            return rows;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    /**
     * @description Creates or updates an Expense, including custom billable fields.
     *              Used by debrief LWCs because Field Service mobile rejects those
     *              fields on uiRecordApi create/update until metadata cache refreshes.
     * @param fields Expense field map from the LWC
     * @return Saved Expense Id
     */
    @AuraEnabled
    public static Id saveExpense(Map<String, Object> fields) {
        if (fields == null || fields.isEmpty()) {
            throw new AuraHandledException('Expense fields are required.');
        }
        try {
            Expense record = new Expense();
            Object recordId = fields.get('Id');
            if (recordId != null && String.isNotBlank(String.valueOf(recordId))) {
                record.Id = (Id) String.valueOf(recordId);
            }
            if (fields.containsKey('ExpenseType')) {
                record.ExpenseType = toStringValue(fields.get('ExpenseType'));
            }
            if (fields.containsKey('Description')) {
                record.Description = toStringValue(fields.get('Description'));
            }
            if (fields.containsKey('TransactionDate')) {
                record.TransactionDate = toDateValue(fields.get('TransactionDate'));
            }
            if (fields.containsKey('Amount')) {
                record.Amount = toDecimalValue(fields.get('Amount'));
            }
            if (fields.containsKey('Quantity')) {
                record.Quantity = toDecimalValue(fields.get('Quantity'));
            }
            if (fields.containsKey('UnitPrice')) {
                record.UnitPrice = toDecimalValue(fields.get('UnitPrice'));
            }
            if (fields.containsKey('WorkOrderId')) {
                String workOrderId = toStringValue(fields.get('WorkOrderId'));
                record.WorkOrderId = String.isBlank(workOrderId) ? null : (Id) workOrderId;
            }
            if (fields.containsKey('CurrencyIsoCode')) {
                record.CurrencyIsoCode = toStringValue(fields.get('CurrencyIsoCode'));
            }
            if (fields.containsKey('OwnerId')) {
                String ownerId = toStringValue(fields.get('OwnerId'));
                if (String.isNotBlank(ownerId)) {
                    record.OwnerId = (Id) ownerId;
                }
            }
            if (fields.containsKey('OverrideCode__c')) {
                record.OverrideCode__c = toStringValue(fields.get('OverrideCode__c'));
            }
            if (fields.containsKey('BillableAmount__c')) {
                record.BillableAmount__c = toDecimalValue(fields.get('BillableAmount__c'));
            }
            if (fields.containsKey('OverrideBillableAmount__c')) {
                record.OverrideBillableAmount__c = toBooleanValue(fields.get('OverrideBillableAmount__c'));
            }
            upsert record;
            return record.Id;
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    /**
     * @description Converts an LWC value to String.
     */
    private static String toStringValue(Object value) {
        if (value == null) {
            return null;
        }
        String asString = String.valueOf(value);
        return String.isBlank(asString) ? null : asString;
    }

    /**
     * @description Converts an LWC value to Date.
     */
    private static Date toDateValue(Object value) {
        if (value == null || String.isBlank(String.valueOf(value))) {
            return null;
        }
        if (value instanceof Date) {
            return (Date) value;
        }
        return Date.valueOf(String.valueOf(value));
    }

    /**
     * @description Converts an LWC value to Decimal.
     */
    private static Decimal toDecimalValue(Object value) {
        if (value == null || String.isBlank(String.valueOf(value))) {
            return null;
        }
        if (value instanceof Decimal) {
            return (Decimal) value;
        }
        return Decimal.valueOf(String.valueOf(value));
    }

    /**
     * @description Converts an LWC value to Boolean.
     */
    private static Boolean toBooleanValue(Object value) {
        return value == true || value == 'true';
    }
}