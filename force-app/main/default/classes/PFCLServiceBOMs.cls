/**
 * @description Domain class for the PFCLServiceBOM__c SObject.
 *              Junction object linking PFCL__c and ServiceBOM__c.
 *              Encapsulates business logic, field defaults, derivations, and validations.
 *              Operates on in-memory record lists only — no SOQL or DML.
 */
public with sharing class PFCLServiceBOMs {

    private final List<PFCLServiceBOM__c> records;

    /**
     * @description Constructs domain instance with the given PFCLServiceBOM__c records.
     * @param records List of PFCLServiceBOM__c records to operate on.
     */
    public PFCLServiceBOMs(List<PFCLServiceBOM__c> records) {
        this.records = records;
    }

    /**
     * @description Thrown when validation fails outside a trigger execution context.
     *              Message contains all violations joined by '; '.
     */
    public class PFCLServiceBOMsException extends Exception {}
}