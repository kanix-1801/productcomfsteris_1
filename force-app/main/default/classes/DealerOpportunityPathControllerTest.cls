/**
 * #GC-3598 Confirms the dealer path reads active opportunity stages instead of a fixed list.
 */
@IsTest
private class DealerOpportunityPathControllerTest {
    @IsTest
    static void getStageDetails_returnsActiveStages() {
        Test.startTest();
        List<DealerOpportunityPathController.StageDetail> stages = DealerOpportunityPathController.getStageDetails();
        Test.stopTest();

        System.assert(stages.size() > 0, 'Active opportunity stages are returned');
        Boolean sawClosedWon = false;
        for (DealerOpportunityPathController.StageDetail stage : stages) {
            System.assertNotEquals(null, stage.value, 'Each stage has an API name');
            if (stage.value == 'Closed Won') {
                sawClosedWon = true;
                System.assertEquals(true, stage.closed);
                System.assertEquals(true, stage.won);
                System.assertEquals(100, stage.probability);
            }
        }
        System.assert(sawClosedWon, 'Closed Won is included from Opportunity Stage');
    }
}