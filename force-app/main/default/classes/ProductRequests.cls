/**
 * @description Domain class for the ProductRequest SObject.
 *              Encapsulates business logic, field defaults, derivations, and validations.
 *              Operates on in-memory record lists only — no SOQL or DML.
 */
public with sharing class ProductRequests {

    private final List<ProductRequest> records;

    // ── Validation Constants ────────────────────────────────────────────────
    // private static final String ERROR_DESTINATION_REQUIRED = 'Destination is required.';
    // private static final String ERROR_QUANTITY_POSITIVE    = 'Quantity must be greater than zero.';

    /**
     * @description Constructs a domain instance with the given ProductRequest records.
     * @param records List of ProductRequest records to operate on.
     */
    public ProductRequests(List<ProductRequest> records) {
        this.records = records;
    }

    // ── Defaults ────────────────────────────────────────────────────────────

    // /**
    //  * @description Applies default field values to new ProductRequest records.
    //  */
    // public void applyDefaults() {
    //     // For each ProductRequest record, set default field values
    //     for (ProductRequest productRequest : records) {
    //         // Set default values for new records
    //     }
    // }

    // ── Validation ──────────────────────────────────────────────────────────

    // /**
    //  * @description Validates ProductRequest records using a dual-path strategy.
    //  *              In a trigger context, addError() blocks platform DML.
    //  *              Outside a trigger, collects all violations and throws ProductRequestsException.
    //  * @throws ProductRequestsException when one or more rules fail outside a trigger context.
    //  */
    // public void validate() {
    //     List<String> errors = new List<String>();
    //
    //     // Validate each record; both paths run in one pass
    //     for (ProductRequest productRequest : records) {
    //         validateDestination(productRequest, errors);
    //         validateQuantity(productRequest, errors);
    //     }
    //
    //     // Outside a trigger, addError() does not prevent DML — throw instead
    //     if (!Trigger.isExecuting && !errors.isEmpty()) {
    //         throw new ProductRequestsException(String.join(errors, '; '));
    //     }
    // }

    // ── Private Validators ──────────────────────────────────────────────────

    // private void validateDestination(ProductRequest productRequest, List<String> errors) {
    //     // Destination is required
    //     if (productRequest.DestinationLocationId == null) {
    //         productRequest.DestinationLocationId.addError(ERROR_DESTINATION_REQUIRED);
    //         errors.add(ERROR_DESTINATION_REQUIRED);
    //     }
    // }

    // private void validateQuantity(ProductRequest productRequest, List<String> errors) {
    //     // Quantity must be greater than zero if provided
    //     if (productRequest.QuantityRequested != null && productRequest.QuantityRequested <= 0) {
    //         productRequest.QuantityRequested.addError(ERROR_QUANTITY_POSITIVE);
    //         errors.add(ERROR_QUANTITY_POSITIVE);
    //     }
    // }

    // ── Domain Exception ────────────────────────────────────────────────────

    /**
     * @description Thrown when validation fails outside a trigger execution context.
     *              Message contains all violations joined by '; '.
     */
    public class ProductRequestsException extends Exception {}
}