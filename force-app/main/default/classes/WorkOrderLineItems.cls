/**
 * @description Domain class for the WorkOrderLineItem SObject.
 *              Encapsulates business logic, field defaults, derivations, and validations.
 *              Operates on in-memory record lists only — no SOQL or DML.
 *
 *              DEFAULT METHODS BELOW ARE FOR DEMONSTRATION ONLY.
 *              Remove all commented-out method bodies before deploying to production.
 */
public with sharing class WorkOrderLineItems {

    private final List<WorkOrderLineItem> records;

    /**
     * @description Constructs domain instance with the given WorkOrderLineItem records.
     * @param records List of WorkOrderLineItem records to operate on.
     */
    public WorkOrderLineItems(List<WorkOrderLineItem> records) {
        this.records = records;
    }

    // ── Validation Constants ────────────────────────────────────────────────
    // NOTE: Demonstration only — delete before deploying to production.
    // private static final String ERROR_WORK_ORDER_REQUIRED  = 'Work Order Line Item must be linked to a Work Order.';
    // private static final String ERROR_DURATION_NEGATIVE    = 'Duration cannot be negative.';
    // private static final String ERROR_STATUS_REQUIRED      = 'Work Order Line Item Status is required.';

    // ── Defaults ────────────────────────────────────────────────────────────

    // NOTE: Demonstration only — delete before deploying to production.
    // /**
    //  * @description Applies default field values to new WorkOrderLineItem records.
    //  * @example
    //  * WorkOrderLineItems domain = new WorkOrderLineItems(Trigger.new);
    //  * domain.applyDefaults();
    //  */
    // public void applyDefaults() {
    //     // For loop iterates over all line items to apply defaults
    //     for (WorkOrderLineItem lineItem : records) {
    //         // Set Status to 'New' when not provided
    //         if (String.isBlank(lineItem.Status)) {
    //             lineItem.Status = 'New';
    //         }
    //         // Set DurationType to 'Hours' when Duration is populated but DurationType is blank
    //         if (lineItem.Duration != null && String.isBlank(lineItem.DurationType)) {
    //             lineItem.DurationType = 'Hours';
    //         }
    //     }
    // }

    // ── Validation ──────────────────────────────────────────────────────────

    // NOTE: Demonstration only — delete before deploying to production.
    // /**
    //  * @description Validates WorkOrderLineItem records using a dual-path strategy.
    //  *              In a trigger context, addError() blocks platform DML.
    //  *              Outside a trigger, collects all violations and throws WorkOrderLineItemsException.
    //  * @throws WorkOrderLineItemsException when one or more rules fail outside a trigger context.
    //  * @example
    //  * WorkOrderLineItems domain = new WorkOrderLineItems(lineItemList);
    //  * domain.validate();
    //  */
    // public void validate() {
    //     List<String> errors = new List<String>();
    //
    //     // Validate each record; both addError() and errors.add() run in one pass
    //     for (WorkOrderLineItem lineItem : records) {
    //         validateWorkOrder(lineItem, errors);
    //         validateStatus(lineItem, errors);
    //         validateDuration(lineItem, errors);
    //     }
    //
    //     // Outside a trigger, addError() does not prevent DML — throw instead
    //     if (!Trigger.isExecuting && !errors.isEmpty()) {
    //         throw new WorkOrderLineItemsException(String.join(errors, '; '));
    //     }
    // }

    // ── Private Validators ──────────────────────────────────────────────────

    // NOTE: Demonstration only — delete before deploying to production.
    // private void validateWorkOrder(WorkOrderLineItem lineItem, List<String> errors) {
    //     // WorkOrderId is required
    //     if (lineItem.WorkOrderId == null) {
    //         lineItem.WorkOrderId.addError(ERROR_WORK_ORDER_REQUIRED);
    //         errors.add(ERROR_WORK_ORDER_REQUIRED);
    //     }
    // }

    // NOTE: Demonstration only — delete before deploying to production.
    // private void validateStatus(WorkOrderLineItem lineItem, List<String> errors) {
    //     // Status is required
    //     if (String.isBlank(lineItem.Status)) {
    //         lineItem.Status.addError(ERROR_STATUS_REQUIRED);
    //         errors.add(ERROR_STATUS_REQUIRED);
    //     }
    // }

    // NOTE: Demonstration only — delete before deploying to production.
    // private void validateDuration(WorkOrderLineItem lineItem, List<String> errors) {
    //     // Duration, if provided, must be non-negative
    //     if (lineItem.Duration != null && lineItem.Duration < 0) {
    //         lineItem.Duration.addError(ERROR_DURATION_NEGATIVE);
    //         errors.add(ERROR_DURATION_NEGATIVE);
    //     }
    // }

    // ── Domain Exception ────────────────────────────────────────────────────

    /**
     * @description Thrown when validation fails outside a trigger execution context.
     *              Message contains all violations joined by '; '.
     */
    public class WorkOrderLineItemsException extends Exception {}
}