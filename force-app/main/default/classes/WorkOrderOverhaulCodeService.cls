/**
 * @description GW-3398: Resolves the Repair Center overhaul service-code product from the asset
 *              model product code and the service codes on the Work Order Line Items.
 *              Rules are the FLEX LARGE matrix in overhaul_codes_for_salesforce_31_JUL_26.
 * @group Repair Center
 */
public with sharing class WorkOrderOverhaulCodeService {
    private static final Set<String> ELECTRICAL_190 = new Set<String>{
        'SC.ELC903',
        'SC.LGT902',
        'SC.LGC908',
        'SC.ELC904',
        'SC.ERR905'
    };
    private static final Set<String> ELECTRICAL_1100 = new Set<String>{
        'SC.ELC1103',
        'SC.ELC1104',
        'SC.ERR1105',
        'SC.LGC1108',
        'SC.LGT1102'
    };
    private static final Set<String> ELECTRICAL_LEGACY = new Set<String>{
        'SC.LGT046',
        'SC.LGC043',
        'SC.ELC010'
    };
    private static final Set<String> INT_061_062_063 = new Set<String>{
        'SC.INT061',
        'SC.INT062',
        'SC.INT063'
    };

    private static final Set<String> MODELS_INT062_FER904 = new Set<String>{
        'FS.17370',
        'FS.17377',
        'FS.10481',
        'FS.10522'
    };
    private static final Set<String> MODELS_INT062_FER908 = new Set<String>{ 'FS.11083' };
    private static final Set<String> MODELS_INT061_FER903 = new Set<String>{
        'FS.17368',
        'FS.17369',
        'FS.10913'
    };
    private static final Set<String> MODELS_INT061_FER900 = new Set<String>{ 'FS.10511' };
    private static final Set<String> MODELS_INT063_FER903 = new Set<String>{ 'FS.11073' };
    private static final Set<String> MODELS_INT1162 = new Set<String>{ 'FS.11089', 'FS.11137' };
    private static final Set<String> MODELS_INT1161 = new Set<String>{ 'FS.11119', 'FS.11152' };
    private static final Set<String> MODELS_LEGACY = new Set<String>{
        'FS.10433',
        'FS.17350',
        'FS.17353',
        'FS.10374',
        'FS.10299',
        'FS.10332',
        'FS.12012',
        'FS.17365',
        'FS.17366',
        'FS.10290',
        'FS.10435',
        'FS.10358',
        'FS.10454',
        'FS.10449',
        'FS.10243',
        'FS.10903',
        'FS.10518',
        'FS.11486',
        'FS.10927',
        'FS.17337',
        'FS.10268',
        'FS.10489',
        'FS.10246',
        'FS.10514'
    };

    /**
     * @description Returns one overhaul product code for each Work Order Id, in the same order.
     *              A null Id returns a null code.
     * @param workOrderIds Work Order Ids from the flow requests
     * @return Overhaul product code for each Id
     */
    public static List<String> determineOverhaulProductCodes(List<Id> workOrderIds) {
        List<String> overhaulProductCodes = new List<String>();
        if (workOrderIds == null || workOrderIds.isEmpty()) {
            return overhaulProductCodes;
        }

        Set<Id> idsToQuery = new Set<Id>();
        for (Id workOrderId : workOrderIds) {
            if (workOrderId != null) {
                idsToQuery.add(workOrderId);
            }
        }

        Map<Id, String> modelCodeByWorkOrderId = new Map<Id, String>();
        Map<Id, Set<String>> serviceCodesByWorkOrderId = new Map<Id, Set<String>>();
        if (!idsToQuery.isEmpty()) {
            for (WorkOrder workOrder : WorkOrdersSelector.selectAssetProductCodesByIds(idsToQuery)) {
                modelCodeByWorkOrderId.put(
                    workOrder.Id,
                    workOrder.Asset == null || workOrder.Asset.Product2 == null
                        ? null
                        : workOrder.Asset.Product2.ProductCode
                );
            }
            for (WorkOrderLineItem lineItem : WorkOrderLineItemsSelector.selectProductCodesByWorkOrderIds(idsToQuery)) {
                if (!serviceCodesByWorkOrderId.containsKey(lineItem.WorkOrderId)) {
                    serviceCodesByWorkOrderId.put(lineItem.WorkOrderId, new Set<String>());
                }
                serviceCodesByWorkOrderId.get(lineItem.WorkOrderId).add(lineItem.Product2.ProductCode);
            }
        }

        for (Id workOrderId : workOrderIds) {
            overhaulProductCodes.add(
                resolveOverhaulProductCode(
                    modelCodeByWorkOrderId.get(workOrderId),
                    serviceCodesByWorkOrderId.get(workOrderId)
                )
            );
        }
        return overhaulProductCodes;
    }

    /**
     * @description Applies the FLEX LARGE overhaul matrix.
     * @param modelProductCode Asset product code, for example FS.17370
     * @param serviceCodes Product codes present on the Work Order Line Items
     * @return Overhaul product code, or null when the model or service codes do not match
     */
    public static String resolveOverhaulProductCode(String modelProductCode, Set<String> serviceCodes) {
        String modelCode = normalizeCode(modelProductCode);
        Set<String> normalizedServiceCodes = normalizeCodes(serviceCodes);
        if (String.isBlank(modelCode) || normalizedServiceCodes.isEmpty()) {
            return null;
        }

        if (MODELS_INT062_FER904.contains(modelCode)) {
            return ccdOrInsertion(
                'SC.CCD907',
                'SC.FER902',
                new Set<String>{ 'SC.INT062' },
                ELECTRICAL_190,
                'SC.FER904',
                'SC.FER903',
                normalizedServiceCodes
            );
        }
        if (MODELS_INT062_FER908.contains(modelCode)) {
            return ccdOrInsertion(
                'SC.CCD907',
                'SC.FER902',
                new Set<String>{ 'SC.INT062' },
                ELECTRICAL_190,
                'SC.FER908',
                'SC.FER907',
                normalizedServiceCodes
            );
        }
        if (MODELS_INT061_FER903.contains(modelCode)) {
            return ccdOrInsertion(
                'SC.CCD907',
                'SC.FER902',
                new Set<String>{ 'SC.INT061' },
                ELECTRICAL_190,
                'SC.FER904',
                'SC.FER903',
                normalizedServiceCodes
            );
        }
        if (MODELS_INT061_FER900.contains(modelCode)) {
            return ccdOrInsertion(
                'SC.CCD907',
                'SC.FER902',
                new Set<String>{ 'SC.INT061' },
                ELECTRICAL_190,
                'SC.FER904',
                'SC.FER900',
                normalizedServiceCodes
            );
        }
        if (MODELS_INT063_FER903.contains(modelCode)) {
            return ccdOrInsertion(
                'SC.CCD907',
                'SC.FER902',
                new Set<String>{ 'SC.INT063' },
                ELECTRICAL_190,
                'SC.FER904',
                'SC.FER903',
                normalizedServiceCodes
            );
        }
        if (MODELS_INT1162.contains(modelCode)) {
            return ccdOrInsertion(
                'SC.CCD1107',
                'SC.FER1102',
                new Set<String>{ 'SC.INT1162' },
                ELECTRICAL_1100,
                'SC.FER1104',
                'SC.FER1103',
                normalizedServiceCodes
            );
        }
        if (MODELS_INT1161.contains(modelCode)) {
            return ccdOrInsertion(
                'SC.CCD1107',
                'SC.FER1102',
                new Set<String>{ 'SC.INT1161' },
                ELECTRICAL_1100,
                'SC.FER1104',
                'SC.FER1103',
                normalizedServiceCodes
            );
        }
        if (MODELS_LEGACY.contains(modelCode)) {
            return ccdOrInsertion(
                'SC.CCD007',
                'SC.FER302',
                INT_061_062_063,
                ELECTRICAL_LEGACY,
                'SC.FER300',
                'SC.FER200',
                normalizedServiceCodes
            );
        }
        return null;
    }

    private static String ccdOrInsertion(
        String ccdCode,
        String ccdOverhaulCode,
        Set<String> insertionCodes,
        Set<String> electricalCodes,
        String electricalOverhaulCode,
        String insertionOnlyOverhaulCode,
        Set<String> serviceCodes
    ) {
        if (containsAny(serviceCodes, new Set<String>{ ccdCode })) {
            return ccdOverhaulCode;
        }
        if (!containsAny(serviceCodes, insertionCodes)) {
            return null;
        }
        if (containsAny(serviceCodes, electricalCodes)) {
            return electricalOverhaulCode;
        }
        return insertionOnlyOverhaulCode;
    }

    private static Boolean containsAny(Set<String> presentCodes, Set<String> expectedCodes) {
        for (String expectedCode : expectedCodes) {
            if (presentCodes.contains(expectedCode)) {
                return true;
            }
        }
        return false;
    }

    private static Set<String> normalizeCodes(Set<String> productCodes) {
        Set<String> normalizedCodes = new Set<String>();
        if (productCodes == null) {
            return normalizedCodes;
        }
        for (String productCode : productCodes) {
            String normalized = normalizeCode(productCode);
            if (normalized != null) {
                normalizedCodes.add(normalized);
            }
        }
        return normalizedCodes;
    }

    private static String normalizeCode(String productCode) {
        if (String.isBlank(productCode)) {
            return null;
        }
        String normalized = productCode.trim().toUpperCase();
        if (normalized == 'FER.1102') {
            return 'SC.FER1102';
        }
        if (normalized == 'ELC010') {
            return 'SC.ELC010';
        }
        return normalized;
    }
}