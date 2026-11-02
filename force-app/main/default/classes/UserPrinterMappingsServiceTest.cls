/**
 * @description Tests for UserPrinterMappingsService (GW-4751 / GW-4637).
 */
@IsTest
private class UserPrinterMappingsServiceTest {
    @IsTest
    static void testReturnsActiveTravelTagPrinterForCurrentUser() {
        insert new WorkstationPrinter__c(
            Name = PrinterService.PARENT_BIN_TAG_PRINTER_NAME,
            Active__c = true,
            User__c = UserInfo.getUserId(),
            PrinterType__c = 'TRAVEL_TAG',
            IPAddress__c = PrinterService.PARENT_BIN_TAG_PRINTER_IP,
            PrinterModel__c = PrinterService.PARENT_BIN_TAG_PRINTER_MODEL
        );

        Test.startTest();
        WorkstationPrinter__c printer =
            UserPrinterMappingsService.getActivePrinterForCurrentUser('TRAVEL_TAG');
        String printerName = UserPrinterMappingsService.getPrinterNameForCurrentUser();
        Test.stopTest();

        Assert.isNotNull(printer);
        Assert.areEqual(PrinterService.PARENT_BIN_TAG_PRINTER_NAME, printer.Name);
        Assert.areEqual(PrinterService.PARENT_BIN_TAG_PRINTER_NAME, printerName);
    }

    @IsTest
    static void testThrowsWhenTravelTagMappingMissing() {
        try {
            UserPrinterMappingsService.getPrinterNameForCurrentUser();
            Assert.fail('Expected missing printer mapping exception');
        } catch (UserPrinterMappingsService.UserPrinterMappingsServiceException e) {
            Assert.isTrue(e.getMessage().contains('TRAVEL_TAG'));
        }
    }

    @IsTest
    static void testReturnsNullWhenPrinterTypeBlank() {
        Test.startTest();
        WorkstationPrinter__c printer =
            UserPrinterMappingsService.getActivePrinterForCurrentUser(null);
        Test.stopTest();

        Assert.isNull(printer);
    }
}