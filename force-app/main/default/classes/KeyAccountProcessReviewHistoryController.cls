/**
 * @description
 * GC-2615 - Aura-enabled controller for Account-scoped Key Account Process Review history.
 */
public with sharing class KeyAccountProcessReviewHistoryController {
    /**
     * @description GC-2615 - Delegates Process Review history retrieval to the service layer.
     * @param accountId Current Account record Id.
     * @return Account-scoped Process Review response.
     */
    @AuraEnabled(cacheable=true)
    public static KeyAccountProcessReviewHistoryService.ProcessReviewHistoryResponse
        getProcessReviewHistory(Id accountId) {
        return KeyAccountProcessReviewHistoryService.getProcessReviewHistory(accountId);
    }
}