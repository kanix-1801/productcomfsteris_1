/**
 * @description Tests for ProductAttributeDefinitionsService (GW-5102).
 */
@IsTest
private class ProductAttributeDefinitionsServiceTest {
    @IsTest
    static void testGetInspectionFeeApplicable_WhenGuardsAndOverride() {
        ProductAttributeDefinitionsService.schemaAvailableOverride = false;

        Test.startTest();
        List<SObject> emptyIds =
            ProductAttributeDefinitionsService.getInspectionFeeApplicableByProductIds(null);
        List<SObject> schemaDisabled =
            ProductAttributeDefinitionsService.getInspectionFeeApplicableByProductIds(
                new Set<Id>{ UserInfo.getUserId() }
            );
        Id inspectionId = ProductAttributeDefinitionsService.getInspectionServiceCodeProductId(null);
        Id productId = ProductAttributeDefinitionsService.getProductId(null);
        Test.stopTest();

        Assert.isTrue(emptyIds.isEmpty());
        Assert.isTrue(schemaDisabled.isEmpty());
        Assert.isNull(inspectionId);
        Assert.isNull(productId);

        ProductAttributeDefinitionsService.schemaAvailableOverride = true;
        List<SObject> queried =
            ProductAttributeDefinitionsService.getInspectionFeeApplicableByProductIds(
                new Set<Id>{ UserInfo.getUserId() }
            );
        Assert.isNotNull(queried);
        Assert.isNull(
            ProductAttributeDefinitionsService.getInspectionServiceCodeProductId(new Account())
        );
        Assert.isNull(ProductAttributeDefinitionsService.getProductId(new Account()));
    }
}