/**
* @description GC-2860 - AuraEnabled controller for Competitive Installed Base tab.
*/
public with sharing class CompetitiveInstalledBaseController {
    @AuraEnabled(cacheable=true)
    public static CompetitiveInstalledBaseService.Response getCompetitiveInstalledBase(Id accountId) {
        return CompetitiveInstalledBaseService.getCompetitiveInstalledBase(accountId);
    }
}