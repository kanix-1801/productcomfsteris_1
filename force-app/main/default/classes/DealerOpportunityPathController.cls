/**
 * #GC-3598 Stage facts for the dealer path. Closed, won, and default probability come from Opportunity Stage.
 */
public with sharing class DealerOpportunityPathController {
    @AuraEnabled(cacheable=true)
    public static List<StageDetail> getStageDetails() {
        List<StageDetail> details = new List<StageDetail>();
        for (OpportunityStage stage : [
            SELECT ApiName, IsClosed, IsWon, DefaultProbability
            FROM OpportunityStage
            WHERE IsActive = true
            ORDER BY SortOrder
        ]) {
            details.add(new StageDetail(stage));
        }
        return details;
    }

    public class StageDetail {
        @AuraEnabled public String value;
        @AuraEnabled public Boolean closed;
        @AuraEnabled public Boolean won;
        @AuraEnabled public Decimal probability;

        public StageDetail(OpportunityStage stage) {
            value = stage.ApiName;
            closed = stage.IsClosed;
            won = stage.IsWon;
            probability = stage.DefaultProbability;
        }
    }
}