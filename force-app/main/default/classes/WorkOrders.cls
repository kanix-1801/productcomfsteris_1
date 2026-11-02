/**
 * @description Domain class for the WorkOrder SObject.
 *              Encapsulates business logic, field defaults, derivations, and validations.
 *              Operates on in-memory record lists only — no SOQL or DML.
 *
 *              DEFAULT METHODS BELOW ARE FOR DEMONSTRATION ONLY.
 *              Remove all commented-out method bodies before deploying to production.
 */
public with sharing class WorkOrders {

    private final List<WorkOrder> records;

    /**
     * @description Constructs domain instance with the given WorkOrder records.
     * @param records List of WorkOrder records to operate on.
     */
    public WorkOrders(List<WorkOrder> records) {
        this.records = records;
    }

    // ── Validation Constants ────────────────────────────────────────────────
    // NOTE: Demonstration only — delete before deploying to production.
    // private static final String ERROR_SUBJECT_REQUIRED = 'Work Order Subject is required.';
    // private static final String ERROR_STATUS_REQUIRED = 'Work Order Status is required.';
    // private static final String ERROR_DURATION_NEGATIVE = 'Duration cannot be negative.';

    // ── Defaults ────────────────────────────────────────────────────────────

    // NOTE: Demonstration only — delete before deploying to production.
    // /**
    //  * @description Applies default field values to new WorkOrder records.
    //  * @example
    //  * WorkOrders domain = new WorkOrders(Trigger.new);
    //  * domain.applyDefaults();
    //  */
    // public void applyDefaults() {
    //     // For loop iterates over all work orders to apply defaults
    //     for (WorkOrder workOrder : records) {
    //         // Set Status to 'New' when not provided
    //         if (String.isBlank(workOrder.Status)) {
    //             workOrder.Status = 'New';
    //         }
    //         // Set Priority to 'Medium' when not provided
    //         if (String.isBlank(workOrder.Priority)) {
    //             workOrder.Priority = 'Medium';
    //         }
    //     }
    // }

    // ── Validation ──────────────────────────────────────────────────────────

    // NOTE: Demonstration only — delete before deploying to production.
    // /**
    //  * @description Validates WorkOrder records using a dual-path strategy.
    //  *              In a trigger context, addError() blocks platform DML.
    //  *              Outside a trigger, collects all violations and throws WorkOrdersException.
    //  * @throws WorkOrdersException when one or more rules fail outside a trigger context.
    //  * @example
    //  * WorkOrders domain = new WorkOrders(workOrderList);
    //  * domain.validate();
    //  */
    // public void validate() {
    //     List<String> errors = new List<String>();
    //
    //     // Validate each record; both addError() and errors.add() run in one pass
    //     for (WorkOrder workOrder : records) {
    //         validateSubject(workOrder, errors);
    //         validateStatus(workOrder, errors);
    //         validateDuration(workOrder, errors);
    //     }
    //
    //     // Outside a trigger, addError() does not prevent DML — throw instead
    //     if (!Trigger.isExecuting && !errors.isEmpty()) {
    //         throw new WorkOrdersException(String.join(errors, '; '));
    //     }
    // }

    // ── Private Validators ──────────────────────────────────────────────────

    // NOTE: Demonstration only — delete before deploying to production.
    // private void validateSubject(WorkOrder workOrder, List<String> errors) {
    //     // Subject is required
    //     if (String.isBlank(workOrder.Subject)) {
    //         workOrder.Subject.addError(ERROR_SUBJECT_REQUIRED);
    //         errors.add(ERROR_SUBJECT_REQUIRED);
    //     }
    // }

    // NOTE: Demonstration only — delete before deploying to production.
    // private void validateStatus(WorkOrder workOrder, List<String> errors) {
    //     // Status is required
    //     if (String.isBlank(workOrder.Status)) {
    //         workOrder.Status.addError(ERROR_STATUS_REQUIRED);
    //         errors.add(ERROR_STATUS_REQUIRED);
    //     }
    // }

    // NOTE: Demonstration only — delete before deploying to production.
    // private void validateDuration(WorkOrder workOrder, List<String> errors) {
    //     // Duration, if provided, must be non-negative
    //     if (workOrder.Duration != null && workOrder.Duration < 0) {
    //         workOrder.Duration.addError(ERROR_DURATION_NEGATIVE);
    //         errors.add(ERROR_DURATION_NEGATIVE);
    //     }
    // }

    // ── Domain Exception ────────────────────────────────────────────────────

    /**
     * @description Thrown when validation fails outside a trigger execution context.
     *              Message contains all violations joined by '; '.
     */
    public class WorkOrdersException extends Exception {}
}