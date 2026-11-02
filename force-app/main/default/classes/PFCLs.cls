/**
 * @description Domain class for the PFCL__c SObject.
 *              Encapsulates business logic, field defaults, derivations, and validations.
 *              Operates on in-memory record lists only — no SOQL or DML.
 */
public with sharing class PFCLs {

    private final List<PFCL__c> records;

    /**
     * @description Constructs domain instance with the given PFCL__c records.
     * @param records List of PFCL__c records to operate on.
     */
    public PFCLs(List<PFCL__c> records) {
        this.records = records;
    }

    /**
     * @description Thrown when validation fails outside a trigger execution context.
     *              Message contains all violations joined by '; '.
     */
    public class PFCLsException extends Exception {}
}