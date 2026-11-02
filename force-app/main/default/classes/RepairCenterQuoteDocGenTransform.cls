/**
 * @author Oskay Taskin
 * @date 2026/09/02
 *
 * @group Repair Center Quote Document Generation
 *
 * @description
 * GW-3600 - Context Service transform plug-in for Repair Center Quote document generation.
 */
global with sharing class RepairCenterQuoteDocGenTransform implements ind_docgen_api.OpenInterface {
    /**
     * @description Routes document generation transform requests to the Repair Center service layer.
     * @param methodName Requested method name from document generation.
     * @param inputMap Input values supplied by document generation.
     * @param outputMap Output values returned to document generation.
     * @return True when the requested method is handled.
     */
    global Boolean invokeMethod(
        String methodName,
        Map<String, Object> inputMap,
        Map<String, Object> outputMap
    ) {
        if (RepairCenterDocGenService.TRANSFORM_METHOD_NAME.equalsIgnoreCase(methodName)) {
            RepairCenterDocGenService.transformTokenData(inputMap, outputMap);
            return true;
        }
        return false;
    }
}