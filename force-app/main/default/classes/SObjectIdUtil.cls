/**
 * @author Uptima
 * @date 2026-08-15
 * @group Utilities
 * @description GW-2891 - Shared helpers for validating Salesforce Id string values.
 */
public with sharing class SObjectIdUtil {
    /**
     * @description GW-2891 - Returns true when value is a 15- or 18-character Salesforce Id that Id.valueOf accepts.
     * @param value Candidate Id string
     * @return true when value is a valid Salesforce Id
     * @example
     * Boolean isId = SObjectIdUtil.isSalesforceId(workOrder.Id);
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
}