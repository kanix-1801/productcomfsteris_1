/**
 * @author Uptima Development Team
 * @date 2026-07-15
 * @description DTO for Allowed Unit evaluation results used by Work Order debrief LWCs.
 * @group Work Order Debrief
 */
public with sharing class AllowedUnitEvaluationDTO {
    /** @description True when the Work Order has an Asset. */
    @AuraEnabled public Boolean hasAsset;
    /** @description True when SBOM membership was evaluated (requires an Asset). */
    @AuraEnabled public Boolean evaluated;
    /**
     * @description True when the product is on the allowed parts list; null when not evaluated.
     */
    @AuraEnabled public Boolean allowedUnit;

    /**
     * @description Builds an unevaluated result (no Asset / incomplete inputs).
     * @return Unevaluated Allowed Unit result
     */
    public static AllowedUnitEvaluationDTO unevaluated() {
        AllowedUnitEvaluationDTO dto = new AllowedUnitEvaluationDTO();
        dto.hasAsset = false;
        dto.evaluated = false;
        dto.allowedUnit = null;
        return dto;
    }

    /**
     * @description Builds a skipped result when Root PFCL SBOM Required is not Yes (GW-4218).
     *              Has an Asset but SBOM cross-reference is not required.
     * @return Unevaluated Allowed Unit result with hasAsset = true
     */
    public static AllowedUnitEvaluationDTO sbomCrossReferenceNotRequired() {
        AllowedUnitEvaluationDTO dto = new AllowedUnitEvaluationDTO();
        dto.hasAsset = true;
        dto.evaluated = false;
        dto.allowedUnit = null;
        return dto;
    }

    /**
     * @description Builds an evaluated result for a Work Order that has an Asset.
     * @param isAllowed True when the Product2 is present on the allowed parts list
     * @return Evaluated Allowed Unit result
     */
    public static AllowedUnitEvaluationDTO evaluated(Boolean isAllowed) {
        AllowedUnitEvaluationDTO dto = new AllowedUnitEvaluationDTO();
        dto.hasAsset = true;
        dto.evaluated = true;
        dto.allowedUnit = isAllowed == true;
        return dto;
    }
}