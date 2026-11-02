/**
 * @description Domain class for the AccountContactRelation SObject.
 *              Encapsulates business logic, field defaults, derivations, and validations.
 *              Operates on in-memory record lists only — no SOQL or DML.
 *
 *              THE COMMENTED-OUT METHODS BELOW ARE EXAMPLES ONLY.
 *              Delete all commented-out method bodies before deploying to production.
 */
public with sharing class AccountContactRelations {

    private final List<AccountContactRelation> records;

    /**
     * @description Constructs domain instance with the given AccountContactRelation records.
     * @param records List of AccountContactRelation records to operate on.
     */
    public AccountContactRelations(List<AccountContactRelation> records) {
        this.records = records;
    }

    // ── Validation Constants ────────────────────────────────────────────────
    // NOTE: Examples only — delete before deploying to production.
    // private static final String ERROR_ROLES_REQUIRED = 'Roles must be specified on the relationship.';

    // ── Defaults ────────────────────────────────────────────────────────────

    // NOTE: Examples only — delete before deploying to production.
    // /**
    //  * @description Applies default field values to new AccountContactRelation records.
    //  */
    // public void applyDefaults() {
    //     // For loop iterates over all relations to apply defaults
    //     for (AccountContactRelation relation : records) {
    //         // Set IsActive to true when not provided
    //         if (relation.IsActive == null) {
    //             relation.IsActive = true;
    //         }
    //     }
    // }

    // ── Validation ──────────────────────────────────────────────────────────

    // NOTE: Examples only — delete before deploying to production.
    // /**
    //  * @description Validates AccountContactRelation records using a dual-path strategy.
    //  *              In a trigger context, addError() blocks platform DML.
    //  *              Outside a trigger, collects all violations and throws AccountContactRelationsException.
    //  * @throws AccountContactRelationsException when one or more rules fail outside a trigger context.
    //  */
    // public void validate() {
    //     List<String> errors = new List<String>();
    //
    //     // Validate each record; both addError() and errors.add() run in one pass
    //     for (AccountContactRelation relation : records) {
    //         validateRoles(relation, errors);
    //     }
    //
    //     // Outside a trigger, addError() does not prevent DML — throw instead
    //     if (!Trigger.isExecuting && !errors.isEmpty()) {
    //         throw new AccountContactRelationsException(String.join(errors, '; '));
    //     }
    // }

    // ── Private Validators ──────────────────────────────────────────────────

    // NOTE: Examples only — delete before deploying to production.
    // private void validateRoles(AccountContactRelation relation, List<String> errors) {
    //     // Roles must be provided
    //     if (String.isBlank(relation.Roles)) {
    //         relation.Roles.addError(ERROR_ROLES_REQUIRED);
    //         errors.add(ERROR_ROLES_REQUIRED);
    //     }
    // }

    // ── Domain Exception ────────────────────────────────────────────────────

    /**
     * @description Thrown when validation fails outside a trigger execution context.
     *              Message contains all violations joined by '; '.
     */
    public class AccountContactRelationsException extends Exception {}
}