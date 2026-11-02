/**
 * @description Domain class for the ProductRelatedMaterial SObject.
 *              Encapsulates business logic, field defaults, derivations, and validations.
 *              Operates on in-memory record lists only — no SOQL or DML.
 *
 *              THE COMMENTED-OUT METHODS BELOW ARE EXAMPLES ONLY.
 *              Delete all commented-out method bodies before deploying to production.
 */
public with sharing class ProductRelatedMaterials {

    private final List<ProductRelatedMaterial> records;

    /**
     * @description Constructs domain instance with the given ProductRelatedMaterial records.
     * @param records List of ProductRelatedMaterial records to operate on.
     */
    public ProductRelatedMaterials(List<ProductRelatedMaterial> records) {
        this.records = records;
    }

    // ── Validation Constants ────────────────────────────────────────────────
    // NOTE: Examples only — delete before deploying to production.
    // private static final String ERROR_QUANTITY_NEGATIVE = 'Quantity Per Product Unit cannot be negative.';

    // ── Defaults ────────────────────────────────────────────────────────────

    // NOTE: Examples only — delete before deploying to production.
    // /**
    //  * @description Applies default field values to new ProductRelatedMaterial records.
    //  */
    // public void applyDefaults() {
    //     // For loop iterates over all related materials to apply defaults
    //     for (ProductRelatedMaterial relatedMaterial : records) {
    //         // Default QuantityPerProductUnit to one when not provided
    //         if (relatedMaterial.QuantityPerProductUnit == null) {
    //             relatedMaterial.QuantityPerProductUnit = 1;
    //         }
    //     }
    // }

    // ── Validation ──────────────────────────────────────────────────────────

    // NOTE: Examples only — delete before deploying to production.
    // /**
    //  * @description Validates ProductRelatedMaterial records using a dual-path strategy.
    //  *              In a trigger context, addError() blocks platform DML.
    //  *              Outside a trigger, collects all violations and throws ProductRelatedMaterialsException.
    //  * @throws ProductRelatedMaterialsException when one or more rules fail outside a trigger context.
    //  */
    // public void validate() {
    //     List<String> errors = new List<String>();
    //
    //     // Validate each record; both addError() and errors.add() run in one pass
    //     for (ProductRelatedMaterial relatedMaterial : records) {
    //         validateQuantity(relatedMaterial, errors);
    //     }
    //
    //     // Outside a trigger, addError() does not prevent DML — throw instead
    //     if (!Trigger.isExecuting && !errors.isEmpty()) {
    //         throw new ProductRelatedMaterialsException(String.join(errors, '; '));
    //     }
    // }

    // ── Private Validators ──────────────────────────────────────────────────

    // NOTE: Examples only — delete before deploying to production.
    // private void validateQuantity(ProductRelatedMaterial relatedMaterial, List<String> errors) {
    //     // QuantityPerProductUnit, if provided, must be non-negative
    //     if (relatedMaterial.QuantityPerProductUnit != null && relatedMaterial.QuantityPerProductUnit < 0) {
    //         relatedMaterial.QuantityPerProductUnit.addError(ERROR_QUANTITY_NEGATIVE);
    //         errors.add(ERROR_QUANTITY_NEGATIVE);
    //     }
    // }

    // ── Domain Exception ────────────────────────────────────────────────────

    /**
     * @description Thrown when validation fails outside a trigger execution context.
     *              Message contains all violations joined by '; '.
     */
    public class ProductRelatedMaterialsException extends Exception {}
}