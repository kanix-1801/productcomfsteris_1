/**
 * @description Domain class for the ServiceBOM__c SObject.
 *              Encapsulates business logic, field defaults, derivations, and validations.
 *              Operates on in-memory record lists only (no SOQL or DML).
 */
public with sharing class ServiceBOMs {

    private final List<ServiceBOM__c> records;

    /**
     * @description Constructs domain instance with the given ServiceBOM__c records.
     * @param records List of ServiceBOM__c records to operate on.
     */
    public ServiceBOMs(List<ServiceBOM__c> records) {
        this.records = records;
    }

    /**
     * @description Thrown when validation fails outside a trigger execution context.
     *              Message contains all violations joined by '; '.
     */
    public class ServiceBOMsException extends Exception {
    }
}