/**
 * @description Domain class for the RepairCenterRoutingRule__c SObject.
 *              Encapsulates business logic, field defaults, derivations, and validations.
 *              Operates on in-memory record lists only — no SOQL or DML.
 *
 *              THE COMMENTED-OUT METHODS BELOW ARE EXAMPLES ONLY.
 *              Delete all commented-out method bodies before deploying to production.
 */
public with sharing class RepairCenterRoutingRules {

    private final List<RepairCenterRoutingRule__c> records;

    /**
     * @description Constructs domain instance with the given RepairCenterRoutingRule__c records.
     * @param records List of RepairCenterRoutingRule__c records to operate on.
     */
    public RepairCenterRoutingRules(List<RepairCenterRoutingRule__c> records) {
        this.records = records;
    }

    // ── Validation Constants ────────────────────────────────────────────────
    // NOTE: Examples only — delete before deploying to production.
    // private static final String ERROR_NAME_REQUIRED = 'Routing Rule Name is required.';
    // private static final String ERROR_PRIORITY_NEGATIVE = 'Priority must be a positive integer.';

    // ── Defaults ────────────────────────────────────────────────────────────

    // NOTE: Examples only — delete before deploying to production.
    // /**
    //  * @description Applies default field values to new RepairCenterRoutingRule__c records.
    //  */
    // public void applyDefaults() {
    //     // For loop iterates over all routing rules to apply defaults
    //     for (RepairCenterRoutingRule__c rule : records) {
    //         // Set IsActive__c to true when not provided
    //         if (rule.IsActive__c == null) {
    //             rule.IsActive__c = true;
    //         }
    //     }
    // }

    // ── Validation ──────────────────────────────────────────────────────────

    // NOTE: Examples only — delete before deploying to production.
    // /**
    //  * @description Validates RepairCenterRoutingRule__c records using a dual-path strategy.
    //  *              In a trigger context, addError() blocks platform DML.
    //  *              Outside a trigger, collects all violations and throws RepairCenterRoutingRulesException.
    //  * @throws RepairCenterRoutingRulesException when one or more rules fail outside a trigger context.
    //  */
    // public void validate() {
    //     List<String> errors = new List<String>();
    //
    //     // Validate each record; both addError() and errors.add() run in one pass
    //     for (RepairCenterRoutingRule__c rule : records) {
    //         validateName(rule, errors);
    //         validatePriority(rule, errors);
    //     }
    //
    //     // Outside a trigger, addError() does not prevent DML — throw instead
    //     if (!Trigger.isExecuting && !errors.isEmpty()) {
    //         throw new RepairCenterRoutingRulesException(String.join(errors, '; '));
    //     }
    // }

    // ── Private Validators ──────────────────────────────────────────────────

    // NOTE: Examples only — delete before deploying to production.
    // private void validateName(RepairCenterRoutingRule__c rule, List<String> errors) {
    //     // Name is required
    //     if (String.isBlank(rule.Name)) {
    //         rule.Name.addError(ERROR_NAME_REQUIRED);
    //         errors.add(ERROR_NAME_REQUIRED);
    //     }
    // }

    // NOTE: Examples only — delete before deploying to production.
    // private void validatePriority(RepairCenterRoutingRule__c rule, List<String> errors) {
    //     // Priority, if provided, must be positive
    //     if (rule.Priority__c != null && rule.Priority__c <= 0) {
    //         rule.Priority__c.addError(ERROR_PRIORITY_NEGATIVE);
    //         errors.add(ERROR_PRIORITY_NEGATIVE);
    //     }
    // }

    // ── Domain Exception ────────────────────────────────────────────────────

    /**
     * @description Thrown when validation fails outside a trigger execution context.
     *              Message contains all violations joined by '; '.
     */
    public class RepairCenterRoutingRulesException extends Exception {}
}