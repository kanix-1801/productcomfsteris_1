/**
* @description GC-2860 - Service for competitive installed base roll-up and summary.
*/
public with sharing class CompetitiveInstalledBaseService {
    private static final String SCENARIO = 'Competitive Installed Base';
    private static final String USER_ERROR_MESSAGE = 'Unable to load Competitive Installed Base.';
    
    @TestVisible
    private static Boolean throwExceptionForTest = false;
    
    public class Response {
        @AuraEnabled public List<Asset> assets;
        @AuraEnabled public List<CompetitorSummary> competitorSummaries;
        @AuraEnabled public Integer totalAssetCount;
        @AuraEnabled public Decimal totalAssetValue;
        @AuraEnabled public String assetDetailHeading;
    }
    
    public class CompetitorSummary {
        @AuraEnabled public String competitorName;
        @AuraEnabled public Integer assetCount;
        @AuraEnabled public Decimal totalValue;
    }
    
    /**
* @description Returns rolled-up competitive assets and competitor summary for an account.
* @param accountId Account context Id.
* @return Response DTO with asset rows and summary metrics.
*/
    public static Response getCompetitiveInstalledBase(Id accountId) {
        Response response = new Response();
        response.assets = new List<Asset>();
        response.competitorSummaries = new List<CompetitorSummary>();
        response.totalAssetCount = 0;
        response.totalAssetValue = 0;
        
        if (accountId == null) {
            return response;
        }
        
        Boolean shouldSaveLog = false;
        
        try {
            if (throwExceptionForTest) {
                throw new QueryException('Forced exception for unit test.');
            }
            
            AccountHierarchyResolutionService.AccountScope accountScope =
                AccountHierarchyResolutionService.resolveAccountScope(accountId);
            response.assetDetailHeading = accountScope.assetDetailHeading;

            if (accountScope.accountIds.isEmpty()) {
                return response;
            }

            List<Asset> assetRecords =
                CompetitiveInstalledBaseSelector.selectCompetitiveAssetsByAccountIds(accountScope.accountIds);
            
            Map<String, CompetitorSummary> summaryByCompetitor =
                new Map<String, CompetitorSummary>();
            
            for (Asset assetRecord : assetRecords) {
                response.assets.add(assetRecord);
                response.totalAssetCount++;
                response.totalAssetValue += assetRecord.AssetValue__c == null ? 0 : assetRecord.AssetValue__c;
                String competitorName = assetRecord.Product2 != null
                    ? String.isNotBlank(assetRecord.Product2.Manufacturer__c)
                    ? assetRecord.Product2.Manufacturer__c
                    : String.isNotBlank(assetRecord.Product2.Family)
                        ? assetRecord.Product2.Family
                        : ''
                            : '';
                CompetitorSummary competitorSummary = summaryByCompetitor.get(
                    competitorName
                );
                
                if (competitorSummary == null) {
                    competitorSummary = new CompetitorSummary();
                    competitorSummary.competitorName = competitorName;
                    competitorSummary.assetCount = 0;
                    competitorSummary.totalValue = 0;
                    summaryByCompetitor.put(competitorName, competitorSummary);
                }
                
                competitorSummary.assetCount++;
                competitorSummary.totalValue += assetRecord.AssetValue__c == null ? 0 : assetRecord.AssetValue__c;
            }
            
            response.competitorSummaries = summaryByCompetitor.values();
            response.competitorSummaries.sort(new CompetitorSummaryComparator());
        } catch (Exception exceptionRecord) {
            shouldSaveLog = true;
            
            Logger.setScenario(SCENARIO);
            Logger.error(
                'Unable to retrieve Competitive Installed Base. Error: ' + exceptionRecord.getMessage()
            )
                .addTag('Competitive Installed Base')
                .setRecord(new Account(Id = accountId));
            
            throw new CompetitiveInstalledBaseException(USER_ERROR_MESSAGE);
        } finally {
            if (shouldSaveLog) {
                Logger.saveLog();
            }
        }
        
        return response;
    }
    
    private class CompetitorSummaryComparator implements Comparator<CompetitorSummary> {
        public Integer compare(
            CompetitorSummary firstSummary,
            CompetitorSummary secondSummary
        ) {
            String firstName = firstSummary == null || firstSummary.competitorName == null
                ? ''
                : firstSummary.competitorName;
            String secondName = secondSummary == null || secondSummary.competitorName == null
                ? ''
                : secondSummary.competitorName;
            return firstName.compareTo(secondName);
        }
    }
    
    public class CompetitiveInstalledBaseException extends Exception {
    }
}