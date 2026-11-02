/**
 * @description Domain class for the ReturnOrderLineItem SObject.
 *              Encapsulates business logic, field defaults, derivations, and validations.
 *              Operates on in-memory record lists only (no SOQL or DML).
 */
public with sharing class ReturnOrderLineItems {

    private final List<ReturnOrderLineItem> records;

    /**
     * @description Constructs domain instance with the given ReturnOrderLineItem records.
     * @param records List of ReturnOrderLineItem records to operate on.
     */
    public ReturnOrderLineItems(List<ReturnOrderLineItem> records) {
        this.records = records;
    }

    /**
     * @description Thrown when validation fails outside a trigger execution context.
     *              Message contains all violations joined by '; '.
     */
    public class ReturnOrderLineItemsException extends Exception {
    }
}