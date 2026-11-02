/**
 * @description Incremental expense amount from Regional Control Pricing Rules.
 * @group Work Order Debrief
 * @see WoDebriefRegionalExpenseController
 */
public with sharing class RegionalExpensePricingCalculator {
    /**
     * @description Incremental amount for a quantity. Blank Ending Qty means no upper limit.
     *              When Maximum Price is set, the amount is capped; save is not blocked.
     * @param quantity Entered expense quantity
     * @param rules Pricing bands, already ordered by Starting Qty
     * @param maximumPrice Optional cap
     * @return Calculated amount, or null when quantity or rules cannot be applied
     */
    public static Decimal calculateIncrementalAmount(
        Decimal quantity,
        List<Pricing_Rule__c> rules,
        Decimal maximumPrice
    ) {
        if (quantity == null || quantity <= 0 || rules == null || rules.isEmpty()) {
            return null;
        }

        Decimal amount = 0;
        for (Pricing_Rule__c rule : rules) {
            if (rule.StartingQuantity__c == null || rule.Rate__c == null) {
                continue;
            }
            Decimal bandEnd = rule.EndingQuantity__c == null ? quantity : rule.EndingQuantity__c;
            Decimal top = quantity < bandEnd ? quantity : bandEnd;
            Decimal units = top - rule.StartingQuantity__c + 1;
            if (units > 0) {
                amount += units * rule.Rate__c;
            }
        }

        if (maximumPrice != null && amount > maximumPrice) {
            return maximumPrice;
        }
        return amount;
    }
}