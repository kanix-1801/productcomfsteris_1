/**
 * @description Domain class for the AccountDepartment__c SObject.
 *              Encapsulates business logic, field defaults, derivations, and validations.
 *              Operates on in-memory record lists only — no SOQL or DML.
 *
 *              THE COMMENTED-OUT METHODS BELOW ARE EXAMPLES ONLY.
 *              Delete all commented-out method bodies before deploying to production.
 */
public with sharing class AccountDepartments {

    private final List<AccountDepartment__c> records;

    /**
     * @description Constructs domain instance with the given AccountDepartment__c records.
     * @param records List of AccountDepartment__c records to operate on.
     */
    public AccountDepartments(List<AccountDepartment__c> records) {
        this.records = records;
    }

    // ── Validation Constants ────────────────────────────────────────────────
    // NOTE: Examples only — delete before deploying to production.
    // private static final String ERROR_ACCOUNT_REQUIRED = 'Account is required on Account Department.';
    // private static final String ERROR_DEPARTMENT_REQUIRED = 'Department is required on Account Department.';

    // ── Defaults ────────────────────────────────────────────────────────────

    // NOTE: Examples only — delete before deploying to production.
    // /**
    //  * @description Applies default field values to new AccountDepartment__c records.
    //  */
    // public void applyDefaults() {
    //     // For loop iterates over all account departments to apply defaults
    //     for (AccountDepartment__c accountDepartment : records) {
    //         // Set IsActive__c to true when not provided
    //         if (accountDepartment.IsActive__c == null) {
    //             accountDepartment.IsActive__c = true;
    //         }
    //     }
    // }

    // ── Validation ──────────────────────────────────────────────────────────

    // NOTE: Examples only — delete before deploying to production.
    // /**
    //  * @description Validates AccountDepartment__c records using a dual-path strategy.
    //  *              In a trigger context, addError() blocks platform DML.
    //  *              Outside a trigger, collects all violations and throws AccountDepartmentsException.
    //  * @throws AccountDepartmentsException when one or more rules fail outside a trigger context.
    //  */
    // public void validate() {
    //     List<String> errors = new List<String>();
    //
    //     // Validate each record; both addError() and errors.add() run in one pass
    //     for (AccountDepartment__c accountDepartment : records) {
    //         validateAccount(accountDepartment, errors);
    //         validateDepartment(accountDepartment, errors);
    //     }
    //
    //     // Outside a trigger, addError() does not prevent DML — throw instead
    //     if (!Trigger.isExecuting && !errors.isEmpty()) {
    //         throw new AccountDepartmentsException(String.join(errors, '; '));
    //     }
    // }

    // ── Private Validators ──────────────────────────────────────────────────

    // NOTE: Examples only — delete before deploying to production.
    // private void validateAccount(AccountDepartment__c accountDepartment, List<String> errors) {
    //     // Account lookup is required
    //     if (accountDepartment.Account__c == null) {
    //         accountDepartment.Account__c.addError(ERROR_ACCOUNT_REQUIRED);
    //         errors.add(ERROR_ACCOUNT_REQUIRED);
    //     }
    // }

    // NOTE: Examples only — delete before deploying to production.
    // private void validateDepartment(AccountDepartment__c accountDepartment, List<String> errors) {
    //     // Department lookup is required
    //     if (accountDepartment.Department__c == null) {
    //         accountDepartment.Department__c.addError(ERROR_DEPARTMENT_REQUIRED);
    //         errors.add(ERROR_DEPARTMENT_REQUIRED);
    //     }
    // }

    // ── Domain Exception ────────────────────────────────────────────────────

    /**
     * @description Thrown when validation fails outside a trigger execution context.
     *              Message contains all violations joined by '; '.
     */
    public class AccountDepartmentsException extends Exception {}
}