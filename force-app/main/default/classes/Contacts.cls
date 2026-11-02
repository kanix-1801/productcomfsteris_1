/**
 * @description Domain class for the Contact SObject.
 *              Encapsulates business logic, field defaults, derivations, and validations.
 *              Operates on in-memory record lists only — no SOQL or DML.
 *
 *              THE COMMENTED-OUT METHODS BELOW ARE EXAMPLES ONLY.
 *              Delete all commented-out method bodies before deploying to production.
 */
public with sharing class Contacts {

    private final List<Contact> records;

    /**
     * @description Constructs domain instance with the given Contact records.
     * @param records List of Contact records to operate on.
     */
    public Contacts(List<Contact> records) {
        this.records = records;
    }

    // ── Validation Constants ────────────────────────────────────────────────
    // NOTE: Examples only — delete before deploying to production.
    // private static final String ERROR_LAST_NAME_REQUIRED = 'Contact Last Name is required.';

    // ── Defaults ────────────────────────────────────────────────────────────

    // NOTE: Examples only — delete before deploying to production.
    // /**
    //  * @description Applies default field values to new Contact records.
    //  */
    // public void applyDefaults() {
    //     // For loop iterates over all contacts to apply defaults
    //     for (Contact contact : records) {
    //         // Set LeadSource when not provided
    //         if (String.isBlank(contact.LeadSource)) {
    //             contact.LeadSource = 'Other';
    //         }
    //     }
    // }

    // ── Validation ──────────────────────────────────────────────────────────

    // NOTE: Examples only — delete before deploying to production.
    // /**
    //  * @description Validates Contact records using a dual-path strategy.
    //  *              In a trigger context, addError() blocks platform DML.
    //  *              Outside a trigger, collects all violations and throws ContactsException.
    //  * @throws ContactsException when one or more rules fail outside a trigger context.
    //  */
    // public void validate() {
    //     List<String> errors = new List<String>();
    //
    //     // Validate each record; both addError() and errors.add() run in one pass
    //     for (Contact contact : records) {
    //         validateLastName(contact, errors);
    //     }
    //
    //     // Outside a trigger, addError() does not prevent DML — throw instead
    //     if (!Trigger.isExecuting && !errors.isEmpty()) {
    //         throw new ContactsException(String.join(errors, '; '));
    //     }
    // }

    // ── Private Validators ──────────────────────────────────────────────────

    // NOTE: Examples only — delete before deploying to production.
    // private void validateLastName(Contact contact, List<String> errors) {
    //     // Last Name is required
    //     if (String.isBlank(contact.LastName)) {
    //         contact.LastName.addError(ERROR_LAST_NAME_REQUIRED);
    //         errors.add(ERROR_LAST_NAME_REQUIRED);
    //     }
    // }

    // ── Domain Exception ────────────────────────────────────────────────────

    /**
     * @description Thrown when validation fails outside a trigger execution context.
     *              Message contains all violations joined by '; '.
     */
    public class ContactsException extends Exception {}
}