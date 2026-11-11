/**
 * @description Tests for PricebooksSelector.
 */
@IsTest
private class PricebooksSelectorTest {
    @IsTest
    static void testSelectActiveStandard_returnsStandardPricebook() {
        Id standardPricebookId = Test.getStandardPricebookId();
        update new Pricebook2(Id = standardPricebookId, IsActive = true);

        Test.startTest();
        List<Pricebook2> standardPricebooks = PricebooksSelector.selectActiveStandard();
        List<Pricebook2> activePricebooks = PricebooksSelector.selectFirstActive();
        Test.stopTest();

        Assert.isFalse(standardPricebooks.isEmpty(), 'Active standard price book should be returned');
        Assert.areEqual(standardPricebookId, standardPricebooks[0].Id);
        Assert.isFalse(activePricebooks.isEmpty(), 'An active price book should be returned');
    }
}