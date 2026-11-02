/**
 * ES Service Product Configurator: after quote lines are saved, expand service product
 * lines to one line per selected asset (in the background).
 */
trigger EsServiceQuoteLineTrigger on QuoteLineItem (after insert, after update, after delete) {
    if (EsServiceLineExpansion.running) return; // lines written by the expansion itself

    Set<Id> quoteIds = new Set<Id>();
    for (QuoteLineItem line : (Trigger.isDelete ? Trigger.old : Trigger.new)) {
        if (line.QuoteId != null) quoteIds.add(line.QuoteId);
    }
    if (quoteIds.isEmpty()) return;

    // Only quotes that have a bundle line with an asset selection.
    // (SelectedAssets__c is a long text field, so it's checked here rather than in the query.)
    Set<Id> eligible = new Set<Id>();
    for (QuoteLineItem line : [
        SELECT QuoteId, SelectedAssets__c FROM QuoteLineItem WHERE QuoteId IN :quoteIds
    ]) {
        if (String.isNotBlank(line.SelectedAssets__c)) eligible.add(line.QuoteId);
    }
    if (eligible.isEmpty()) return;

    if (Limits.getQueueableJobs() < Limits.getLimitQueueableJobs()) {
        System.enqueueJob(new EsServiceLineExpansion(eligible));
    }
}