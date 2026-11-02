/**
 * @description Domain class for the Product2 SObject.
 *              Encapsulates business logic, field defaults, derivations, and validations.
 *              Operates on in-memory record lists only — no SOQL or DML.
 *
 *              THE COMMENTED-OUT METHODS BELOW ARE EXAMPLES ONLY.
 *              Delete all commented-out method bodies before deploying to production.
 */
public with sharing class Products {

    private final List<Product2> records;

    /**
     * @description Constructs domain instance with the given Product2 records.
     * @param records List of Product2 records to operate on.
     */
    public Products(List<Product2> records) {
        this.records = records;
    }

    // ── Validation Constants ────────────────────────────────────────────────
    // NOTE: Examples only — delete before deploying to production.
    // private static final String ERROR_NAME_REQUIRED = 'Product Name is required.';

    // ── Defaults ────────────────────────────────────────────────────────────

    // NOTE: Examples only — delete before deploying to production.
    // /**
    //  * @description Applies default field values to new Product2 records.
    //  */
    // public void applyDefaults() {
    //     // For loop iterates over all products to apply defaults
    //     for (Product2 product : records) {
    //         // Set IsActive to true when not provided
    //         if (product.IsActive == null) {
    //             product.IsActive = true;
    //         }
    //     }
    // }

    // ── Validation ──────────────────────────────────────────────────────────

    // NOTE: Examples only — delete before deploying to production.
    // /**
    //  * @description Validates Product2 records using a dual-path strategy.
    //  *              In a trigger context, addError() blocks platform DML.
    //  *              Outside a trigger, collects all violations and throws ProductsException.
    //  * @throws ProductsException when one or more rules fail outside a trigger context.
    //  */
    // public void validate() {
    //     List<String> errors = new List<String>();
    //
    //     // Validate each record; both addError() and errors.add() run in one pass
    //     for (Product2 product : records) {
    //         validateName(product, errors);
    //     }
    //
    //     // Outside a trigger, addError() does not prevent DML — throw instead
    //     if (!Trigger.isExecuting && !errors.isEmpty()) {
    //         throw new ProductsException(String.join(errors, '; '));
    //     }
    // }

    // ── Private Validators ──────────────────────────────────────────────────

    // NOTE: Examples only — delete before deploying to production.
    // private void validateName(Product2 product, List<String> errors) {
    //     // Name is required
    //     if (String.isBlank(product.Name)) {
    //         product.Name.addError(ERROR_NAME_REQUIRED);
    //         errors.add(ERROR_NAME_REQUIRED);
    //     }
    // }

    // ── Domain Exception ────────────────────────────────────────────────────

    /**
     * @description Thrown when validation fails outside a trigger execution context.
     *              Message contains all violations joined by '; '.
     */
    public class ProductsException extends Exception {}
}