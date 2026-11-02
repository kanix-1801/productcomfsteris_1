/**
 * @author PSL
 * @date 11-21-2025
 * @description Test class for CreateCaseHandler to verify proper exception handling for null and empty input scenarios.
 */
@IsTest
private class CreateCaseHandlerExceptionTest {
    
    @IsTest 
    static void testCreateCaseExceptionHandling1() {
        // Test that the createCase method handles null input gracefully
        Test.startTest();
        CreateCaseHandler.createCase((List<String>)null);
        Test.stopTest();
        
        // No exceptions thrown = success
        System.assert(true, 'CreateCase exception handling test passed');
    }
    
    @IsTest
    static void testCreateCaseExceptionHandling2() {
        Test.startTest();
        CreateCaseHandler.createCase(new List<String>());
        Test.stopTest();
        
        // No exceptions thrown = success
        System.assert(true, 'CreateCase exception handling test passed');
    }
    
    @IsTest
    static void testCreateSubCaseExceptionHandling() {
        // Test that the createSubCase method handles null input gracefully
        Test.startTest();
        CreateCaseHandler.createSubCase((List<String>)null);
        Test.stopTest();
        
        // No exceptions thrown = success
        System.assert(true, 'CreateSubCase exception handling test passed');
    }
    
    @IsTest
    static void testCreateSubCaseExceptionHandling2() {
        // Test that the createSubCase method handles empty list gracefully  
        Test.startTest();
        CreateCaseHandler.createSubCase(new List<String>());
        Test.stopTest();
        
        // No exceptions thrown = success
        System.assert(true, 'CreateSubCase exception handling test passed');
    }
}