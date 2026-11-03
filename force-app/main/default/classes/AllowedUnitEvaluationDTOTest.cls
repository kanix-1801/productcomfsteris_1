/**
 * @description Unit tests for AllowedUnitEvaluationDTO factory methods.
 * @see AllowedUnitEvaluationDTO
 */
@IsTest
private class AllowedUnitEvaluationDTOTest {
    /**
     * @description Verifies unevaluated() sets hasAsset/evaluated false and clears the result flag.
     */
    @IsTest
    static void unevaluated_setsNullFlags() {
        AllowedUnitEvaluationDTO dto = AllowedUnitEvaluationDTO.unevaluated();

        System.assertEquals(false, dto.hasAsset);
        System.assertEquals(false, dto.evaluated);
        System.assertEquals(null, dto.allowedUnit);
    }

    /**
     * @description GW-4218: SBOM not required keeps hasAsset true but leaves the flag unevaluated.
     */
    @IsTest
    static void sbomCrossReferenceNotRequired_hasAssetButNotEvaluated() {
        AllowedUnitEvaluationDTO dto =
            AllowedUnitEvaluationDTO.sbomCrossReferenceNotRequired();

        System.assertEquals(true, dto.hasAsset);
        System.assertEquals(false, dto.evaluated);
        System.assertEquals(null, dto.allowedUnit);
    }

    /**
     * @description Verifies evaluated() sets hasAsset/evaluated and the allowed flag.
     */
    @IsTest
    static void evaluated_setsAllowedFlag() {
        AllowedUnitEvaluationDTO allowed = AllowedUnitEvaluationDTO.evaluated(true);
        AllowedUnitEvaluationDTO denied = AllowedUnitEvaluationDTO.evaluated(false);

        System.assertEquals(true, allowed.hasAsset);
        System.assertEquals(true, allowed.evaluated);
        System.assertEquals(true, allowed.allowedUnit);

        System.assertEquals(true, denied.hasAsset);
        System.assertEquals(true, denied.evaluated);
        System.assertEquals(false, denied.allowedUnit);
    }

    /**
     * @description Verifies evaluated() treats a null input as not allowed.
     */
    @IsTest
    static void evaluated_nullInput_isNotAllowed() {
        AllowedUnitEvaluationDTO nullSafe = AllowedUnitEvaluationDTO.evaluated(null);

        System.assertEquals(true, nullSafe.evaluated);
        System.assertEquals(false, nullSafe.allowedUnit);
    }
}