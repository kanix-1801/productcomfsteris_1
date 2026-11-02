/**
 * @description Resolves the active Workstation Printer mapped to the running user (GW-4751 / GW-4637).
 *              Queries WorkstationPrinter__c through WorkstationPrintersSelector.
 * @group GW-4637
 */
public with sharing class UserPrinterMappingsService {
    private static final String CLASS_NAME = 'UserPrinterMappingsService';
    private static final String PRINTER_TYPE_TRAVEL_TAG = 'TRAVEL_TAG';

    /**
     * @description Thrown when the printer mapping query fails or no travel-tag printer is mapped.
     */
    public class UserPrinterMappingsServiceException extends Exception {
    }

    /**
     * @description Active Workstation Printer of the given type for the running user.
     *              When several match, returns the latest by CreatedDate. Returns null when none match.
     * @param printerType PrinterType__c value to match
     * @return The matching Workstation Printer, or null
     * @throws UserPrinterMappingsServiceException when the query fails
     */
    public static WorkstationPrinter__c getActivePrinterForCurrentUser(String printerType) {
        if (String.isBlank(printerType)) {
            return null;
        }

        try {
            return (WorkstationPrinter__c) new WorkstationPrintersSelector()
                .selectAllFields()
                .whereEquals('Active__c', true)
                .whereEquals('User__c', UserInfo.getUserId())
                .whereEquals('PrinterType__c', printerType)
                .orderByDesc('CreatedDate')
                .first();
        } catch (Exception queryError) {
            Logger.error(
                CLASS_NAME +
                    '.getActivePrinterForCurrentUser: Unable to resolve the active ' +
                    printerType +
                    ' Workstation Printer.',
                queryError
            );
            Logger.saveLog();
            throw new UserPrinterMappingsServiceException(
                'Unable to resolve the active ' + printerType + ' Workstation Printer.',
                queryError
            );
        }
    }

    /**
     * @description Returns the TRAVEL_TAG printer name mapped to the current user.
     * @return Printer name expected by the Zebra PrintLabels API
     * @throws UserPrinterMappingsServiceException when no mapping is available
     */
    public static String getPrinterNameForCurrentUser() {
        WorkstationPrinter__c printer = getActivePrinterForCurrentUser(PRINTER_TYPE_TRAVEL_TAG);
        if (printer == null || String.isBlank(printer.Name)) {
            throw new UserPrinterMappingsServiceException(
                'No active TRAVEL_TAG Workstation Printer is mapped to the current user.'
            );
        }
        return printer.Name;
    }
}