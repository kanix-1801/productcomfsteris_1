/**
 * @description Service wrapper over BinTagPrintQuantitiesSelector (GW-3595 / GW-4637).
 *              Controllers and PrinterService must call this class, not the selector.
 *              Print quantity queries are built here with SoqlQueryBuilder.
 * @group GW-4637
 */
public with sharing class BinTagPrintQuantitiesService {
    private static final String CLASS_NAME = 'BinTagPrintQuantitiesService';
    public static final Integer DEFAULT_PRINT_QUANTITY = 1;
    private static final List<String> PRINT_QUANTITY_FIELDS = new List<String>{
        'Id',
        'PrintQuantity__c',
        'RepairCenter__c',
        'Product_Line__c'
    };

    @TestVisible
    private static Integer testPrintQuantity;

    /**
     * @description Returns the configured number of bin tag copies to print.
     *              Used for every Print Bin Tag record type (Instruments parent/child and Devices).
     *              Matches Repair Center + Product Line only; Country and Account are not used.
     * @param repairCenterId Repair Center Location Id
     * @param productLine Product line used on the mapping
     * @return Print quantity from BinTagPrintQuantity__c.PrintQuantity__c, or 1 when no mapping is found
     */
    public static Integer getPrintQuantity(Id repairCenterId, String productLine) {
        if (testPrintQuantity != null) {
            return testPrintQuantity;
        }

        if (repairCenterId == null || String.isBlank(productLine)) {
            return DEFAULT_PRINT_QUANTITY;
        }

        try {
            BinTagPrintQuantity__c mapping = (BinTagPrintQuantity__c) new BinTagPrintQuantitiesSelector()
                .selectFields(PRINT_QUANTITY_FIELDS)
                .whereEquals('RepairCenter__c', repairCenterId)
                .whereEquals('Product_Line__c', productLine)
                .orderByDesc('LastModifiedDate')
                .first();
            if (mapping == null || mapping.PrintQuantity__c == null || mapping.PrintQuantity__c <= 0) {
                return DEFAULT_PRINT_QUANTITY;
            }
            return Integer.valueOf(mapping.PrintQuantity__c);
        } catch (Exception e) {
            Logger.error(CLASS_NAME + '.getPrintQuantity', e);
            return DEFAULT_PRINT_QUANTITY;
        }
    }
}