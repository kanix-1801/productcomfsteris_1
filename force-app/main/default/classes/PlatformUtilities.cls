/**
 * @author Uptima
 * @date 2026-09-19
 * @group Utilities
 * @description Shared platform helpers for Aura controllers (Id validation, Aura exceptions, picklists).
 */
public with sharing class PlatformUtilities {
    /**
     * @description Label/value pair for Aura-enabled picklist UIs.
     */
    public class PicklistOption {
        @AuraEnabled
        public String label;
        @AuraEnabled
        public String value;
    }

    /**
     * @description Returns true when value is a 15- or 18-character Salesforce Id that Id.valueOf accepts.
     * @param value Candidate Id string
     * @return true when value is a valid Salesforce Id
     */
    public static Boolean isSalesforceId(String value) {
        if (String.isBlank(value) || (value.length() != 15 && value.length() != 18)) {
            return false;
        }
        try {
            Id.valueOf(value);
            return true;
        } catch (Exception e) {
            return false;
        }
    }

    /**
     * @description Builds an AuraHandledException with a user-visible message.
     * @param message Message shown to the Lightning client
     * @return AuraHandledException
     */
    public static AuraHandledException buildAuraException(String message) {
        AuraHandledException ex = new AuraHandledException(message);
        ex.setMessage(message);
        return ex;
    }

    /**
     * @description Resolves a readable exception message, preferring the cause when present.
     * @param e Exception to inspect
     * @return Message string, or null when e is null
     */
    public static String resolveExceptionMessage(Exception e) {
        if (e == null) {
            return null;
        }
        if (e.getCause() != null && String.isNotBlank(e.getCause().getMessage())) {
            return e.getCause().getMessage();
        }
        return e.getMessage();
    }

    /**
     * @description Returns active picklist entries for a field as Aura picklist options.
     * @param fieldToken SObject field token
     * @return Active picklist options
     */
    public static List<PicklistOption> getActivePicklistOptions(Schema.SObjectField fieldToken) {
        List<PicklistOption> options = new List<PicklistOption>();
        if (fieldToken == null) {
            return options;
        }
        for (Schema.PicklistEntry entry : fieldToken.getDescribe().getPicklistValues()) {
            if (!entry.isActive()) {
                continue;
            }
            PicklistOption option = new PicklistOption();
            option.label = entry.getLabel();
            option.value = entry.getValue();
            options.add(option);
        }
        return options;
    }

    /**
     * @description Returns Yes/No options for boolean-style Aura picklists.
     * @return Yes and No picklist options
     */
    public static List<PicklistOption> buildYesNoOptions() {
        List<PicklistOption> options = new List<PicklistOption>();
        PicklistOption yesOption = new PicklistOption();
        yesOption.label = 'Yes';
        yesOption.value = 'Yes';
        options.add(yesOption);
        PicklistOption noOption = new PicklistOption();
        noOption.label = 'No';
        noOption.value = 'No';
        options.add(noOption);
        return options;
    }

    /**
     * @description Returns the value at the given key as a Map<String, Object>, or null if
     *              the source map is null, the key is absent, or the value isn't a map.
     * @param source The map to read from.
     * @param key The key to look up.
     * @return The value as a Map<String, Object>, or null.
     */
    public static Map<String, Object> getMapValue(Map<String, Object> source, String key) {
        if (source == null || !source.containsKey(key)) {
            return null;
        }

        Object value = source.get(key);
        return value instanceof Map<String, Object> ? (Map<String, Object>) value : null;
    }

    /**
     * @description Returns the value at the given key as a List<Object>, or null if the
     *              source map is null, the key is absent, or the value isn't a list.
     * @param source The map to read from.
     * @param key The key to look up.
     * @return The value as a List<Object>, or null.
     */
    public static List<Object> getListValue(Map<String, Object> source, String key) {
        if (source == null || !source.containsKey(key)) {
            return null;
        }

        Object value = source.get(key);
        return value instanceof List<Object> ? (List<Object>) value : null;
    }

    /**
     * @description Trims a string and returns null in place of an empty or blank result,
     *              so callers can treat "no value" and "blank value" the same way.
     * @param value The string to trim.
     * @return The trimmed string, or null if it is null or blank after trimming.
     */
    public static String trimToNull(String value) {
        if (value == null) {
            return null;
        }

        String trimmed = value.trim();
        return String.isBlank(trimmed) ? null : trimmed;
    }

    /**
     * @description Parses a string as a Salesforce Id, returning null instead of throwing
     *              if the value is blank or not a valid Id.
     * @param value The string to parse.
     * @return The parsed Id, or null if it is blank or invalid.
     */
    public static Id parseId(String value) {
        if (String.isBlank(value)) {
            return null;
        }

        try {
            return (Id) value;
        } catch (Exception e) {
            return null;
        }
    }

    /**
     * @description Serializes the given body to JSON and writes it to the REST response
     *              along with the given HTTP status code.
     * @param response The REST response to write to.
     * @param statusCode The HTTP status code to set on the response.
     * @param body The map to serialize as the response body.
     */
    public static void writeJson(RestResponse response, Integer statusCode, Map<String, Object> body) {
        response.statusCode = statusCode;
        response.responseBody = Blob.valueOf(JSON.serialize(body));
    }

    /**
     * @description GW-5874 - Reduces a North American phone number to its 10 digits: strips formatting and the
     *              +1 country code, so '+1 (555) 123-4567' becomes '5551234567'.
     * @param phone Raw phone number
     * @return Digits only, or null when the value has no digits
     */
    public static String normalizePhone(String phone) {
        if (String.isBlank(phone)) {
            return null;
        }

        String digits = phone.replaceAll('[^0-9]', '');
        if (digits.length() == 11 && digits.startsWith('1')) {
            digits = digits.substring(1);
        }
        return String.isBlank(digits) ? null : digits;
    }
}