/**
 * @description Test class for ReturnOrderPathController.
 */
@isTest
private class ReturnOrderPathControllerTest {

    @isTest
    static void getStatusPicklistValues_returnsActiveValues() {
        Test.startTest();
        List<ReturnOrderPathController.PicklistOption> options =
            ReturnOrderPathController.getStatusPicklistValues();
        Test.stopTest();

        System.assertNotEquals(null, options, 'Options list should not be null');
        System.assert(options.size() > 0, 'At least one active status value should be returned');

        for (ReturnOrderPathController.PicklistOption option : options) {
            System.assertNotEquals(null, option.label, 'Each option should have a label');
            System.assertNotEquals(null, option.value, 'Each option should have a value');
            System.assert(String.isNotBlank(option.label), 'Each option label should be populated');
            System.assert(String.isNotBlank(option.value), 'Each option value should be populated');
        }

        Boolean hasCreatedStatus = false;
        for (ReturnOrderPathController.PicklistOption option : options) {
            if (option.value == 'Created') {
                hasCreatedStatus = true;
                break;
            }
        }
        System.assert(hasCreatedStatus, 'Expected Created to be an active Return Order status value');
    }
}