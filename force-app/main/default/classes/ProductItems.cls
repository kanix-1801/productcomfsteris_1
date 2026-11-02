/**
 * @description Domain class for the ProductItem SObject.
 *              Encapsulates business logic, field defaults, derivations, and validations.
 *              Operates on in-memory record lists only — no SOQL or DML.
 */
public with sharing class ProductItems {

    private final List<ProductItem> records;

    /**
     * @description Constructs domain instance with the given ProductItem records.
     * @param records List of ProductItem records to operate on.
     */
    public ProductItems(List<ProductItem> records) {
        this.records = records;
    }

    /**
     * @description Thrown when validation fails outside a trigger execution context.
     *              Message contains all violations joined by '; '.
     */
    public class ProductItemsException extends Exception {}
}