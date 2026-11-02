/**
 * @description Domain class for the Department__c SObject.
 *              Encapsulates business logic, field defaults, derivations, and validations.
 *              Operates on in-memory record lists only — no SOQL or DML.
 *
 *              THE COMMENTED-OUT METHODS BELOW ARE EXAMPLES ONLY.
 *              Delete all commented-out method bodies before deploying to production.
 */
public with sharing class Departments {

    private final List<Department__c> records;

    /**
     * @description Constructs domain instance with the given Department__c records.
     * @param records List of Department__c records to operate on.
     */
    public Departments(List<Department__c> records) {
        this.records = records;
    }

    // ── Validation Constants ────────────────────────────────────────────────
    // NOTE: Examples only — delete before deploying to production.
    // private static final String ERROR_NAME_REQUIRED = 'Department Name is required.';

    // ── Defaults ────────────────────────────────────────────────────────────

    // NOTE: Examples only — delete before deploying to production.
    // /**
    //  * @description Applies default field values to new Department__c records.
    //  */
    // public void applyDefaults() {
    //     // For loop iterates over all departments to apply defaults
    //     for (Department__c department : records) {
    //         // Set IsActive__c to true when not provided
    //         if (department.IsActive__c == null) {
    //             department.IsActive__c = true;
    //         }
    //     }
    // }

    // ── Validation ──────────────────────────────────────────────────────────

    // NOTE: Examples only — delete before deploying to production.
    // /**
    //  * @description Validates Department__c records using a dual-path strategy.
    //  *              In a trigger context, addError() blocks platform DML.
    //  *              Outside a trigger, collects all violations and throws DepartmentsException.
    //  * @throws DepartmentsException when one or more rules fail outside a trigger context.
    //  */
    // public void validate() {
    //     List<String> errors = new List<String>();
    //
    //     // Validate each record; both addError() and errors.add() run in one pass
    //     for (Department__c department : records) {
    //         validateName(department, errors);
    //     }
    //
    //     // Outside a trigger, addError() does not prevent DML — throw instead
    //     if (!Trigger.isExecuting && !errors.isEmpty()) {
    //         throw new DepartmentsException(String.join(errors, '; '));
    //     }
    // }

    // ── Private Validators ──────────────────────────────────────────────────

    // NOTE: Examples only — delete before deploying to production.
    // private void validateName(Department__c department, List<String> errors) {
    //     // Name is required
    //     if (String.isBlank(department.Name)) {
    //         department.Name.addError(ERROR_NAME_REQUIRED);
    //         errors.add(ERROR_NAME_REQUIRED);
    //     }
    // }

    // ── Domain Exception ────────────────────────────────────────────────────

    /**
     * @description Thrown when validation fails outside a trigger execution context.
     *              Message contains all violations joined by '; '.
     */
    public class DepartmentsException extends Exception {}
}