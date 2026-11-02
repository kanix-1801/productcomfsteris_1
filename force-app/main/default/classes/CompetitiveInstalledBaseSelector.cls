/**
* @description GC-2860 - SOQL selector for competitive installed base assets.
*/
public with sharing class CompetitiveInstalledBaseSelector {
    private static Id competitiveAssetRecordTypeId;
    
    /**
     * @description Returns competitive assets for the given account Ids.
     * @param accountIds Account Ids whose competitive assets should be displayed.
     * @return Competitive Asset rows with drill-down context fields.
     */
    public static List<Asset> selectCompetitiveAssetsByAccountIds(Set<Id> accountIds) {
        if (accountIds == null || accountIds.isEmpty()) {
            return new List<Asset>();
        }

        Id recordTypeId = Schema.SObjectType.Asset.getRecordTypeInfosByDeveloperName().get('Competitive_Asset').getRecordTypeId();
        if (recordTypeId == null) {
            return new List<Asset>();
        }

        return [
            SELECT Id,
                   Name,
                   SerialNumber,
                   Status,
                   InstallDate,
                   AssetValue__c,
                   AccountId,
                   Account.Name,
                   Account.OracleAddressId__c,
                   Account.ParentId,
                   Account.Parent.Name,
                   Product2Id,
                   Product2.Name,
                   Product2.Manufacturer__c,
                   Product2.Family
            FROM Asset
            WHERE RecordTypeId = :recordTypeId
              AND AccountId IN :accountIds
            WITH USER_MODE
            ORDER BY Account.Name, Name
            LIMIT 5000
        ];
    }
}