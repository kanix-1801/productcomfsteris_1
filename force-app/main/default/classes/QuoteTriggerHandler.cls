/**
 * @author Himanshu Chaurasia
 * @date 2026/07/28
 *
 * @group Quote
 *
 * @description GC-2659 Trigger handler for Quote insert, update, and delete events.
 *              Delegates business logic to QuoteService.
 */
public with sharing class QuoteTriggerHandler extends TriggerHandler {
    /**
     * @description Applies non-forecastable status rules before Quote insert.
     */
    public override void beforeInsert() {
        QuoteService.populateQuoteForecastConfidenceOnInsert((List<Quote>) Trigger.new);
        QuoteService.applyStatusRulesBeforeSave(
            (List<Quote>) Trigger.new,
            null
        );
    }

    /**
     * @description Applies non-forecastable status rules before Quote update.
     */
    public override void beforeUpdate() {
        QuoteService.applyStatusRulesBeforeSave(
            (List<Quote>) Trigger.new,
            (Map<Id, Quote>) Trigger.oldMap
        );
    }

    /**
     * @description Runs Forecast Eligible and forecast notification logic after Quote insert.
     */
    public override void afterInsert() {
        QuoteService.handleAfterInsert((List<Quote>) Trigger.new);
    }

    /**
     * @description Runs Forecast Eligible and forecast notification logic after Quote update.
     */
    public override void afterUpdate() {
        QuoteService.handleAfterUpdate(
            (List<Quote>) Trigger.new,
            (Map<Id, Quote>) Trigger.oldMap
        );
    }

    /**
     * @description Runs Forecast Eligible and forecast notification logic after Quote delete.
     */
    public override void afterDelete() {
        QuoteService.handleAfterDelete((List<Quote>) Trigger.old);
    }
}