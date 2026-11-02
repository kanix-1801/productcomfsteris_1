/**
 * @description Domain class for the Asset SObject.
 *              Encapsulates business logic, field defaults, derivations, and validations.
 *              Operates on in-memory record lists only — no SOQL or DML.
 *
 *              THE COMMENTED-OUT METHODS BELOW ARE EXAMPLES ONLY.
 *              Delete all commented-out method bodies before deploying to production.
 */
public with sharing class Assets {

    private final List<Asset> records;

    /**
     * @description Constructs domain instance with the given Asset records.
     * @param records List of Asset records to operate on.
     */
    public Assets(List<Asset> records) {
        this.records = records;
    }

    // ── Validation Constants ────────────────────────────────────────────────
    // NOTE: Examples only — delete before deploying to production.
    // private static final String ERROR_NAME_REQUIRED = 'Asset Name is required.';
    // private static final String ERROR_QUANTITY_NEGATIVE = 'Quantity cannot be negative.';

    // ── Defaults ────────────────────────────────────────────────────────────

    // NOTE: Examples only — delete before deploying to production.
    // /**
    //  * @description Applies default field values to new Asset records.
    //  */
    // public void applyDefaults() {
    //     // For loop iterates over all assets to apply defaults
    //     for (Asset asset : records) {
    //         // Set Status to 'Purchased' when not provided
    //         if (String.isBlank(asset.Status)) {
    //             asset.Status = 'Purchased';
    //         }
    //         // Set Quantity to 1 when not provided
    //         if (asset.Quantity == null) {
    //             asset.Quantity = 1;
    //         }
    //     }
    // }

    // ── Validation ──────────────────────────────────────────────────────────

    // NOTE: Examples only — delete before deploying to production.
    // /**
    //  * @description Validates Asset records using a dual-path strategy.
    //  *              In a trigger context, addError() blocks platform DML.
    //  *              Outside a trigger, collects all violations and throws AssetsException.
    //  * @throws AssetsException when one or more rules fail outside a trigger context.
    //  */
    // public void validate() {
    //     List<String> errors = new List<String>();
    //
    //     // Validate each record; both addError() and errors.add() run in one pass
    //     for (Asset asset : records) {
    //         validateName(asset, errors);
    //         validateQuantity(asset, errors);
    //     }
    //
    //     // Outside a trigger, addError() does not prevent DML — throw instead
    //     if (!Trigger.isExecuting && !errors.isEmpty()) {
    //         throw new AssetsException(String.join(errors, '; '));
    //     }
    // }

    // ── Private Validators ──────────────────────────────────────────────────

    // NOTE: Examples only — delete before deploying to production.
    // private void validateName(Asset asset, List<String> errors) {
    //     // Name is required
    //     if (String.isBlank(asset.Name)) {
    //         asset.Name.addError(ERROR_NAME_REQUIRED);
    //         errors.add(ERROR_NAME_REQUIRED);
    //     }
    // }

    // NOTE: Examples only — delete before deploying to production.
    // private void validateQuantity(Asset asset, List<String> errors) {
    //     // Quantity, if provided, must be non-negative
    //     if (asset.Quantity != null && asset.Quantity < 0) {
    //         asset.Quantity.addError(ERROR_QUANTITY_NEGATIVE);
    //         errors.add(ERROR_QUANTITY_NEGATIVE);
    //     }
    // }

    // ── Domain Exception ────────────────────────────────────────────────────

    /**
     * @description Thrown when validation fails outside a trigger execution context.
     *              Message contains all violations joined by '; '.
     */
    public class AssetsException extends Exception {}
}