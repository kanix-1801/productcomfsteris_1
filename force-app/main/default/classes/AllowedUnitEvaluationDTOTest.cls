/**
 * @description Unit tests for AllowedUnitEvaluationDTO factory methods.
 * @see AllowedUnitEvaluationDTO
 */
@IsTest
private class AllowedUnitEvaluationDTOTest {
    /**
     * @description Verifies unevaluated() sets hasAsset/evaluated false and clears result flags.
     */
    @IsTest
    static void unevaluated_setsNullFlags() {
        AllowedUnitEvaluationDTO dto = AllowedUnitEvaluationDTO.unevaluated();

        System.assertEquals(false, dto.hasAsset);
        System.assertEquals(false, dto.evaluated);
        System.assertEquals(null, dto.allowedUnit);
        System.assertEquals(null, dto.criticalPart);
    }

    /**
     * @description GW-4218: SBOM not required keeps hasAsset true but leaves flags unevaluated.
     */
    @IsTest
    static void sbomCrossReferenceNotRequired_hasAssetButNotEvaluated() {
        AllowedUnitEvaluationDTO dto =
            AllowedUnitEvaluationDTO.sbomCrossReferenceNotRequired();

        System.assertEquals(true, dto.hasAsset);
        System.assertEquals(false, dto.evaluated);
        System.assertEquals(null, dto.allowedUnit);
        System.assertEquals(null, dto.criticalPart);
    }

    /**
     * @description Verifies single-arg evaluated() defaults criticalPart to false.
     */
    @IsTest
    static void evaluated_singleArg_defaultsCriticalFalse() {
        AllowedUnitEvaluationDTO allowed = AllowedUnitEvaluationDTO.evaluated(true);
        AllowedUnitEvaluationDTO denied = AllowedUnitEvaluationDTO.evaluated(false);

        System.assertEquals(true, allowed.hasAsset);
        System.assertEquals(true, allowed.evaluated);
        System.assertEquals(true, allowed.allowedUnit);
        System.assertEquals(false, allowed.criticalPart);

        System.assertEquals(true, denied.hasAsset);
        System.assertEquals(true, denied.evaluated);
        System.assertEquals(false, denied.allowedUnit);
        System.assertEquals(false, denied.criticalPart);
    }

    /**
     * @description Verifies two-arg evaluated() sets criticalPart and null-safe booleans.
     */
    @IsTest
    static void evaluated_twoArg_setsCriticalFlag() {
        AllowedUnitEvaluationDTO critical = AllowedUnitEvaluationDTO.evaluated(true, true);
        AllowedUnitEvaluationDTO notCritical = AllowedUnitEvaluationDTO.evaluated(true, false);
        AllowedUnitEvaluationDTO nullSafe = AllowedUnitEvaluationDTO.evaluated(null, null);

        System.assertEquals(true, critical.allowedUnit);
        System.assertEquals(true, critical.criticalPart);
        System.assertEquals(true, notCritical.allowedUnit);
        System.assertEquals(false, notCritical.criticalPart);
        System.assertEquals(false, nullSafe.allowedUnit);
        System.assertEquals(false, nullSafe.criticalPart);
    }
}