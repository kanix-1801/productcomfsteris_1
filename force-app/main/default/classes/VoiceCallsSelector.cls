/**
 * @description Selector for VoiceCall queries used by Case FCR evaluation (GW-3997).
 * @author STERIS
 * @group Selectors
 * @see VoiceCall
 * @see CaseFCRService
 */
public with sharing class VoiceCallsSelector {

    /**
     * @description GW-3997 - Counts VoiceCall records grouped by related Case Id.
     * @param relatedCaseIdSet Case Ids to count against
     * @return Map of Case Id to VoiceCall count
     */
    public static Map<Id, Integer> countByRelatedCaseIds(Set<Id> relatedCaseIdSet) {
        Map<Id, Integer> voiceCallCountByCaseIdMap = new Map<Id, Integer>();
        if (relatedCaseIdSet == null || relatedCaseIdSet.isEmpty()) {
            return voiceCallCountByCaseIdMap;
        }

        for (AggregateResult aggregateRow : [
            SELECT RelatedRecordId relatedRecordId, COUNT(Id) total
            FROM VoiceCall
            WHERE RelatedRecordId IN :relatedCaseIdSet
            WITH SECURITY_ENFORCED
            GROUP BY RelatedRecordId
        ]) {
            voiceCallCountByCaseIdMap.put(
                (Id) aggregateRow.get('relatedRecordId'),
                (Integer) aggregateRow.get('total')
            );
        }
        return voiceCallCountByCaseIdMap;
    }
}