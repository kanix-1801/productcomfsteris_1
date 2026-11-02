/**
 * @description Tests for ProductAttributeDefinitionsSelector (GW-5102).
 */
@IsTest
private class ProductAttributeDefinitionsSelectorTest {
    @IsTest
    static void testSelectInspectionFeeApplicable_WhenGuardsAndOverride() {
        ProductAttributeDefinitionsSelector.schemaAvailableOverride = false;

        Test.startTest();
        List<SObject> emptyIds =
            ProductAttributeDefinitionsSelector.selectInspectionFeeApplicableByProductIds(null);
        List<SObject> schemaDisabled =
            ProductAttributeDefinitionsSelector.selectInspectionFeeApplicableByProductIds(
                new Set<Id>{ UserInfo.getUserId() }
            );
        Id inspectionId = ProductAttributeDefinitionsSelector.getInspectionServiceCodeProductId(null);
        Id productId = ProductAttributeDefinitionsSelector.getProductId(null);
        Test.stopTest();

        Assert.isTrue(emptyIds.isEmpty());
        Assert.isTrue(schemaDisabled.isEmpty());
        Assert.isNull(inspectionId);
        Assert.isNull(productId);

        ProductAttributeDefinitionsSelector.schemaAvailableOverride = true;
        List<SObject> queried =
            ProductAttributeDefinitionsSelector.selectInspectionFeeApplicableByProductIds(
                new Set<Id>{ UserInfo.getUserId() }
            );
        Assert.isNotNull(queried);
        Assert.isNull(
            ProductAttributeDefinitionsSelector.getInspectionServiceCodeProductId(new Account())
        );
        Assert.isNull(ProductAttributeDefinitionsSelector.getProductId(new Account()));
    }
}