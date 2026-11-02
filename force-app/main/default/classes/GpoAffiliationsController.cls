public without sharing class GpoAffiliationsController {
    @AuraEnabled(cacheable=true)
    public static List<GpoAffiliationDTO> getGpoAffiliations(Id accountId) {
        return GpoAffiliationsService.getGpoAffiliations(accountId);
    }
}