/**
 * @author PSL
 * @date 11-21-2025
 * @description Test class for ErrorLogger that validates helper methods for Error Logging functionality
 */
@IsTest
public class ErrorLoggerTest {
    
    @IsTest
    static void testLogException() {
        try {
            // Trigger an exception to test logging
            Integer x = 1 / 0;
        } catch (Exception e) {
            Id logId = ErrorLogger.logException(e, 'ErrorLoggerTest', 'testLogException');
            // Should not throw and should return a log ID
            System.assertNotEquals(null, logId, 'Log ID should not be null');
        }
    }
    
    @IsTest
    static void testLogMessage() {
        Id logId = ErrorLogger.logMessage('Test message', 'ErrorLoggerTest', 'testLogMessage', ErrorLogger.Level.INFO);
        System.assertNotEquals(null, logId, 'Log ID should not be null');
    }
    
    @IsTest
    static void testLogInvalidDataType() {
        Id logId = ErrorLogger.logInvalidDataType(
            'testField', 
            'String', 
            'Integer', 
            'ErrorLoggerTest', 
            'testLogInvalidDataType', 
            '001XXXXXXXXXXXX', 
            null
        );
        System.assertNotEquals(null, logId, 'Log ID should not be null');
    }
    
    @IsTest
    static void testLogMissingRequiredField() {
        Id logId = ErrorLogger.logMissingRequiredField(
            'testField', 
            'ErrorLoggerTest', 
            'testLogMissingRequiredField', 
            '001XXXXXXXXXXXX', 
            null
        );
        System.assertNotEquals(null, logId, 'Log ID should not be null');
    }
    
    @IsTest
    static void testLogIncorrectEventStructure() {
        Id logId = ErrorLogger.logIncorrectEventStructure(
            'TestEvent', 
            'ExpectedStructure', 
            'ActualStructure', 
            'ErrorLoggerTest', 
            'testLogIncorrectEventStructure', 
            '001XXXXXXXXXXXX', 
            null
        );
        System.assertNotEquals(null, logId, 'Log ID should not be null');
    }
    
    @IsTest
    static void testLogValidationError() {
        Id logId = ErrorLogger.logValidationError(
            'Validation failed', 
            'ErrorLoggerTest', 
            'testLogValidationError', 
            '001XXXXXXXXXXXX', 
            null
        );
        System.assertNotEquals(null, logId, 'Log ID should not be null');
    }
    
    @IsTest
    static void testLogWarning() {
        Id logId = ErrorLogger.logWarning(
            'This is a warning', 
            'ErrorLoggerTest', 
            'testLogWarning', 
            '001XXXXXXXXXXXX', 
            null
        );
        System.assertNotEquals(null, logId, 'Log ID should not be null');
    }
    
    @IsTest
    static void testLogInfo() {
        Id logId = ErrorLogger.logInfo(
            'This is an info message', 
            'ErrorLoggerTest', 
            'testLogInfo', 
            '001XXXXXXXXXXXX', 
            null
        );
        System.assertNotEquals(null, logId, 'Log ID should not be null');
    }
    
    @IsTest
    static void testConvenienceOverloads() {
        // Test convenience overloads
        try {
            Integer x = 1 / 0;
        } catch (Exception e) {
            Id logId1 = ErrorLogger.logException(e, 'ErrorLoggerTest', 'testConvenienceOverloads');
            System.assertNotEquals(null, logId1, 'Log ID should not be null');
        }
        
        Id logId2 = ErrorLogger.logMessage('Simple message', 'ErrorLoggerTest', 'testConvenienceOverloads', ErrorLogger.Level.WARN);
        System.assertNotEquals(null, logId2, 'Log ID should not be null');
    }
    
    @IsTest
    static void testErrorHandlingInLoggingMethods() {
        // Test that all methods handle errors gracefully
        // Even if the database insert fails, methods should not throw
        
        // Test with null context data
        Id logId1 = ErrorLogger.logInvalidDataType(
            'testField', 
            'String', 
            'Integer', 
            'ErrorLoggerTest', 
            'testErrorHandling', 
            '001XXXXXXXXXXXX', 
            null
        );
        System.assertNotEquals(null, logId1, 'Log ID should not be null even with null context');
        
        // Test with empty context data
        Map<String, Object> emptyContext = new Map<String, Object>();
        Id logId2 = ErrorLogger.logMissingRequiredField(
            'testField', 
            'ErrorLoggerTest', 
            'testErrorHandling', 
            '001XXXXXXXXXXXX', 
            emptyContext
        );
        System.assertNotEquals(null, logId2, 'Log ID should not be null even with empty context');
    }
}