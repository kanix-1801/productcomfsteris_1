/**
 * @description Domain class for the CustomerPreference__c SObject.
 *              Encapsulates business logic, field defaults, derivations, and validations.
 *              Operates on in-memory record lists only — no SOQL or DML.
 *
 *              THE COMMENTED-OUT METHODS BELOW ARE EXAMPLES ONLY.
 *              Delete all commented-out method bodies before deploying to production.
 */
public with sharing class CustomerPreferences {

    private final List<CustomerPreference__c> records;

    /**
     * @description Constructs domain instance with the given CustomerPreference__c records.
     * @param records List of CustomerPreference__c records to operate on.
     */
    public CustomerPreferences(List<CustomerPreference__c> records) {
        this.records = records;
    }

    // ── Validation Constants ────────────────────────────────────────────────
    // NOTE: Examples only — delete before deploying to production.
    // private static final String ERROR_NAME_REQUIRED = 'Customer Preference Name is required.';

    // ── Defaults ────────────────────────────────────────────────────────────

    // NOTE: Examples only — delete before deploying to production.
    // /**
    //  * @description Applies default field values to new CustomerPreference__c records.
    //  */
    // public void applyDefaults() {
    //     // For loop iterates over all preferences to apply defaults
    //     for (CustomerPreference__c preference : records) {
    //         // Set IsActive__c to true when not provided
    //         if (preference.IsActive__c == null) {
    //             preference.IsActive__c = true;
    //         }
    //     }
    // }

    // ── Validation ──────────────────────────────────────────────────────────

    // NOTE: Examples only — delete before deploying to production.
    // /**
    //  * @description Validates CustomerPreference__c records using a dual-path strategy.
    //  *              In a trigger context, addError() blocks platform DML.
    //  *              Outside a trigger, collects all violations and throws CustomerPreferencesException.
    //  * @throws CustomerPreferencesException when one or more rules fail outside a trigger context.
    //  */
    // public void validate() {
    //     List<String> errors = new List<String>();
    //
    //     // Validate each record; both addError() and errors.add() run in one pass
    //     for (CustomerPreference__c preference : records) {
    //         validateName(preference, errors);
    //     }
    //
    //     // Outside a trigger, addError() does not prevent DML — throw instead
    //     if (!Trigger.isExecuting && !errors.isEmpty()) {
    //         throw new CustomerPreferencesException(String.join(errors, '; '));
    //     }
    // }

    // ── Private Validators ──────────────────────────────────────────────────

    // NOTE: Examples only — delete before deploying to production.
    // private void validateName(CustomerPreference__c preference, List<String> errors) {
    //     // Name is required
    //     if (String.isBlank(preference.Name)) {
    //         preference.Name.addError(ERROR_NAME_REQUIRED);
    //         errors.add(ERROR_NAME_REQUIRED);
    //     }
    // }

    // ── Domain Exception ────────────────────────────────────────────────────

    /**
     * @description Thrown when validation fails outside a trigger execution context.
     *              Message contains all violations joined by '; '.
     */
    public class CustomerPreferencesException extends Exception {}
}