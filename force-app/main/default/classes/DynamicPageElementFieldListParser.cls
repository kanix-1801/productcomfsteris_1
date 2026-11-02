/**
 * @date 2026/07/28
 *
 * @group Account Management
 *
 * @description
 * Parses comma-separated field lists from DynamicPageElement__mdt FieldList rows.
 * Each entry may end with a single suffix character controlling field mode for Full users:
 * * = required (editable), # = readonly, $ = editable. No suffix defaults to readonly.
 *
 * @see DynamicPageElementService
 * GC-3183
 */
public with sharing class DynamicPageElementFieldListParser {

    /** @description Nebula Logger scenario for metadata engine transactions. */
    private static final String SCENARIO = 'Metadata Engine';

    /** @description Nebula Logger tag for this class. */
    private static final String LOGGER_TAG = 'DynamicPageElementFieldListParser';

    /** @description Suffix marking a field as required when editable. */
    public static final String SUFFIX_REQUIRED = '*';

    /** @description Suffix marking a field as read-only. */
    public static final String SUFFIX_READONLY = '#';

    /** @description Suffix marking a field as editable. */
    public static final String SUFFIX_EDITABLE = '$';

    /** @description Mode value for read-only fields. */
    public static final String MODE_READONLY = 'readonly';

    /** @description Mode value for editable fields. */
    public static final String MODE_EDITABLE = 'editable';

    /** @description Mode value for required editable fields. */
    public static final String MODE_REQUIRED = 'required';

    /**
     * @description
     * One parsed field entry with its resolved display mode.
     */
    public class FieldListItem {
        /** @description SObject field API name without suffix. */
        public String fieldApiName;
        /** @description Field mode: readonly, editable, or required. */
        public String mode;
    }

    /**
     * @description
     * Parses a comma-separated field list into ordered FieldListItem entries.
     *
     * @param csv Comma-separated field tokens, e.g. Name*,Phone#,Industry$.
     * @return Ordered list of parsed field items; empty when input is blank.
     */
    public static List<FieldListItem> parse(String csv) {
        List<FieldListItem> items = new List<FieldListItem>();

        if (String.isBlank(csv)) {
            return items;
        }

        for (String token : csv.split(',')) {
            FieldListItem item = parseToken(token);
            if (item != null) {
                items.add(item);
            }
        }

        return items;
    }

    /**
     * @description
     * Parses a single field token and strips an optional trailing mode suffix.
     *
     * @param token Raw field token from the CSV string.
     * @return Parsed field item, or null when the token is blank after trimming.
     */
    @TestVisible
    private static FieldListItem parseToken(String token) {
        if (String.isBlank(token)) {
            return null;
        }

        String trimmed = token.trim();
        String fieldApiName = trimmed;
        String mode = MODE_READONLY;

        if (trimmed.endsWith(SUFFIX_REQUIRED)) {
            fieldApiName = trimmed.substring(0, trimmed.length() - 1).trim();
            mode = MODE_REQUIRED;
        } else if (trimmed.endsWith(SUFFIX_READONLY)) {
            fieldApiName = trimmed.substring(0, trimmed.length() - 1).trim();
            mode = MODE_READONLY;
        } else if (trimmed.endsWith(SUFFIX_EDITABLE)) {
            fieldApiName = trimmed.substring(0, trimmed.length() - 1).trim();
            mode = MODE_EDITABLE;
        }

        if (String.isBlank(fieldApiName)) {
            Logger.setScenario(SCENARIO);
            Logger.warn(LOGGER_TAG + ': Skipping blank field token: ' + token)
                .addTag(LOGGER_TAG)
                .addTag('MetadataEngine')
                .addTag('GC-3183');
            return null;
        }

        FieldListItem item = new FieldListItem();
        item.fieldApiName = fieldApiName;
        item.mode = mode;
        return item;
    }
}