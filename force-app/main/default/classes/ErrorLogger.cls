/**
 * @author PSL
 * @date 11-21-2025
 * @description ErrorLogger
 * Centralized, bulk-safe logging utility to persist diagnostics to ErrorLog__c.
 * Captures invalid data types, missing required fields, incorrect event structure, logic exceptions, and other runtime errors.
 *
 * Design:
 * - Never throw from logger methods.
 * - Bulk-safe, no SOQL; single-record insert per call.
 * - Truncation to comply with field limits.
 * - Safe in triggers, async, and integrations.
 */
public with sharing class ErrorLogger {

    public enum Level { ERROR, WARN, INFO, DEBUG }

    // Field limits aligned with metadata
    private static final Integer TEXT_255 = 255;
    private static final Integer TEXT_18 = 18;
    private static final Integer LTA_MESSAGE = 32768;
    private static final Integer LTA_STACK = 131072;

    /**
     * Log an Apex Exception with stack trace and context.
     */
    public static Id logException(
        Exception ex,
        String className,
        String methodName,
        Level level,
        String recordId,
        Map<String, Object> contextData
    ) {
        ErrorLog__c log = baseLogSkeleton(className, methodName, level, recordId, contextData);
            if (ex != null) {
                String msg = ex.getMessage();
                String stack = ex.getStackTraceString();
                log.Message__c = truncate(msg, LTA_MESSAGE);
                log.Stack_Trace__c = truncate(stack, LTA_STACK);
            }
            return safeInsert(log);
    }

    /**
     * Log a validation or data quality message without an Apex Exception.
     */
    public static Id logMessage(
        String message,
        String className,
        String methodName,
        Level level,
        String recordId,
        Map<String, Object> contextData
    ) {
        ErrorLog__c log = baseLogSkeleton(className, methodName, level, recordId, contextData);
            log.Message__c = truncate(message, LTA_MESSAGE);
            return safeInsert(log);
    }

    // Convenience overloads
    public static Id logException(Exception ex, String className, String methodName) {
        return logException(ex, className, methodName, Level.ERROR, null, null);
    }
    public static Id logMessage(String message, String className, String methodName, Level level) {
        return logMessage(message, className, methodName, level, null, null);
    }

    /**
     * Log invalid data type errors
     */
    public static Id logInvalidDataType(
        String fieldName,
        String expectedType,
        String actualType,
        String className,
        String methodName,
        String recordId,
        Map<String, Object> contextData
    ) {
        String message = 'Invalid data type for field "' + fieldName + '". Expected: ' + expectedType + ', Actual: ' + actualType;
            ErrorLog__c log = baseLogSkeleton(className, methodName, Level.ERROR, recordId, contextData);
            log.Message__c = truncate(message, LTA_MESSAGE);
            return safeInsert(log);
    }

    /**
     * Log missing required field errors
     */
    public static Id logMissingRequiredField(
        String fieldName,
        String className,
        String methodName,
        String recordId,
        Map<String, Object> contextData
    ) {
        String message = 'Required field "' + fieldName + '" is missing';
            ErrorLog__c log = baseLogSkeleton(className, methodName, Level.ERROR, recordId, contextData);
            log.Message__c = truncate(message, LTA_MESSAGE);
            return safeInsert(log);
    }

    /**
     * Log incorrect event structure errors
     */
    public static Id logIncorrectEventStructure(
        String eventName,
        String expectedStructure,
        String actualStructure,
        String className,
        String methodName,
        String recordId,
        Map<String, Object> contextData
    ) {
        String message = 'Incorrect event structure for "' + eventName + '". Expected: ' + expectedStructure + ', Actual: ' + actualStructure;
            ErrorLog__c log = baseLogSkeleton(className, methodName, Level.ERROR, recordId, contextData);
            log.Message__c = truncate(message, LTA_MESSAGE);
            return safeInsert(log);
    }

    /**
     * Log validation errors for business logic violations
     */
    public static Id logValidationError(
        String message,
        String className,
        String methodName,
        String recordId,
        Map<String, Object> contextData
    ) {
        ErrorLog__c log = baseLogSkeleton(className, methodName, Level.ERROR, recordId, contextData);
            log.Message__c = truncate(message, LTA_MESSAGE);
            return safeInsert(log);
    }

    /**
     * Log warning messages for recoverable issues
     */
    public static Id logWarning(
        String message,
        String className,
        String methodName,
        String recordId,
        Map<String, Object> contextData
    ) {
        ErrorLog__c log = baseLogSkeleton(className, methodName, Level.WARN, recordId, contextData);
            log.Message__c = truncate(message, LTA_MESSAGE);
            return safeInsert(log);
    }

    /**
     * Log informational messages for monitoring and debugging
     */
    public static Id logInfo(
        String message,
        String className,
        String methodName,
        String recordId,
        Map<String, Object> contextData
    ) {
        ErrorLog__c log = baseLogSkeleton(className, methodName, Level.INFO, recordId, contextData);
            log.Message__c = truncate(message, LTA_MESSAGE);
            return safeInsert(log);
    }

    // Build base record with common context
    private static ErrorLog__c baseLogSkeleton(
        String className,
        String methodName,
        Level level,
        String recordId,
        Map<String, Object> contextData
    ) {
        ErrorLog__c log = new ErrorLog__c();
        log.Class_Name__c = truncate(className, TEXT_255);
        log.Method_Name__c = truncate(methodName, TEXT_255);
        log.Level__c = (level == null ? 'ERROR' : String.valueOf(level));
        if (recordId != null) log.Record_Id__c = truncate(recordId, TEXT_18);

        // Timestamp and user context
        log.Timestamp__c = System.now();
        log.User__c = UserInfo.getUserId();

        // Session / transaction correlation
        String sessionIdSafe;
        sessionIdSafe = UserInfo.getSessionId();
        log.Session_Id__c = truncate(sessionIdSafe, TEXT_255);
        log.Transaction_Id__c = truncate(Request.getCurrent().getRequestId(), TEXT_255);

        // Serialize extra details
        if (contextData != null && !contextData.isEmpty()) {
            String serialized;
            serialized = JSON.serialize(contextData);
            if (String.isNotBlank(log.Message__c)) {
                String combined = log.Message__c + ' | context=' + serialized;
                log.Message__c = truncate(combined, LTA_MESSAGE);
            } else {
                log.Message__c = truncate('context=' + serialized, LTA_MESSAGE);
            }
        }
        return log;
    }

    // Insert with allOrNone=false and swallow DML errors
    private static Id safeInsert(ErrorLog__c log) {
        Database.SaveResult sr = Database.insert(log, false);
            return (sr != null && sr.isSuccess()) ? sr.getId() : null;
    }

    // Utility to truncate text safely
    @TestVisible
    private static String truncate(String s, Integer maxLen) {
        if (s == null) return null;
        if (maxLen == null || maxLen <= 0) return s;
        return s.length() > maxLen ? s.substring(0, maxLen) : s;
    }
}