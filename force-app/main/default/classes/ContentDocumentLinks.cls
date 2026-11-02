/**
 * @description Domain class for the ContentDocumentLink SObject.
 *              Encapsulates business logic, field defaults, derivations, and validations.
 *              Operates on in-memory record lists only — no SOQL or DML.
 *
 *              NOTE: ContentDocumentLink records link a ContentDocument to a record.
 *              They require both ContentDocumentId and LinkedEntityId to be set.
 *
 *              THE COMMENTED-OUT METHODS BELOW ARE EXAMPLES ONLY.
 *              Delete all commented-out method bodies before deploying to production.
 */
public with sharing class ContentDocumentLinks {

    private final List<ContentDocumentLink> records;

    /**
     * @description Constructs domain instance with the given ContentDocumentLink records.
     * @param records List of ContentDocumentLink records to operate on.
     */
    public ContentDocumentLinks(List<ContentDocumentLink> records) {
        this.records = records;
    }

    // ── Validation Constants ────────────────────────────────────────────────
    // NOTE: Examples only — delete before deploying to production.
    // private static final String ERROR_CONTENT_DOCUMENT_REQUIRED = 'Content Document is required.';
    // private static final String ERROR_LINKED_ENTITY_REQUIRED = 'Linked Entity is required.';

    // ── Defaults ────────────────────────────────────────────────────────────

    // NOTE: Examples only — delete before deploying to production.
    // /**
    //  * @description Applies default field values to new ContentDocumentLink records.
    //  */
    // public void applyDefaults() {
    //     // For loop iterates over all document links to apply defaults
    //     for (ContentDocumentLink link : records) {
    //         // Set ShareType to 'V' (Viewer) when not provided
    //         if (String.isBlank(link.ShareType)) {
    //             link.ShareType = 'V';
    //         }
    //         // Set Visibility to 'AllUsers' when not provided
    //         if (String.isBlank(link.Visibility)) {
    //             link.Visibility = 'AllUsers';
    //         }
    //     }
    // }

    // ── Validation ──────────────────────────────────────────────────────────

    // NOTE: Examples only — delete before deploying to production.
    // /**
    //  * @description Validates ContentDocumentLink records using a dual-path strategy.
    //  *              In a trigger context, addError() blocks platform DML.
    //  *              Outside a trigger, collects all violations and throws ContentDocumentLinksException.
    //  * @throws ContentDocumentLinksException when one or more rules fail outside a trigger context.
    //  */
    // public void validate() {
    //     List<String> errors = new List<String>();
    //
    //     // Validate each record; both addError() and errors.add() run in one pass
    //     for (ContentDocumentLink link : records) {
    //         validateContentDocument(link, errors);
    //         validateLinkedEntity(link, errors);
    //     }
    //
    //     // Outside a trigger, addError() does not prevent DML — throw instead
    //     if (!Trigger.isExecuting && !errors.isEmpty()) {
    //         throw new ContentDocumentLinksException(String.join(errors, '; '));
    //     }
    // }

    // ── Private Validators ──────────────────────────────────────────────────

    // NOTE: Examples only — delete before deploying to production.
    // private void validateContentDocument(ContentDocumentLink link, List<String> errors) {
    //     // ContentDocumentId is required
    //     if (link.ContentDocumentId == null) {
    //         link.ContentDocumentId.addError(ERROR_CONTENT_DOCUMENT_REQUIRED);
    //         errors.add(ERROR_CONTENT_DOCUMENT_REQUIRED);
    //     }
    // }

    // NOTE: Examples only — delete before deploying to production.
    // private void validateLinkedEntity(ContentDocumentLink link, List<String> errors) {
    //     // LinkedEntityId is required
    //     if (link.LinkedEntityId == null) {
    //         link.LinkedEntityId.addError(ERROR_LINKED_ENTITY_REQUIRED);
    //         errors.add(ERROR_LINKED_ENTITY_REQUIRED);
    //     }
    // }

    // ── Domain Exception ────────────────────────────────────────────────────

    /**
     * @description Thrown when validation fails outside a trigger execution context.
     *              Message contains all violations joined by '; '.
     */
    public class ContentDocumentLinksException extends Exception {}
}