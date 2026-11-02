/**
 * @description Domain class for the ReturnOrder SObject.
 *              Encapsulates business logic, field defaults, derivations, and validations.
 *              Operates on in-memory record lists only (no SOQL or DML).
 */
public with sharing class ReturnOrders {

    private final List<ReturnOrder> records;

    /**
     * @description Constructs domain instance with the given ReturnOrder records.
     * @param records List of ReturnOrder records to operate on.
     */
    public ReturnOrders(List<ReturnOrder> records) {
        this.records = records;
    }

    /**
     * @description Thrown when validation fails outside a trigger execution context.
     *              Message contains all violations joined by '; '.
     */
    public class ReturnOrdersException extends Exception {
    }
}