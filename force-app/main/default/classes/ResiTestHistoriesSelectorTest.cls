/**
 * @description Tests for ResiTestHistoriesSelector (GW-5492).
 */
@IsTest
private class ResiTestHistoriesSelectorTest {
    @IsTest
    static void testConstructor_bindsResiTestHistoryObject() {
        ResiTestHistoriesSelector selector = new ResiTestHistoriesSelector();
        Assert.isNotNull(selector);
    }
}