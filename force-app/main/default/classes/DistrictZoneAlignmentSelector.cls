/**
 * @description GW-2706 - SOQL for District Zone Alignment. Inherited sharing: territory and user lookups run
 *              without sharing when called from DistrictZoneAlignmentService.TerritoryStore.
 */
public inherited sharing class DistrictZoneAlignmentSelector {
    public static final String ZONE_TERRITORY_TYPE = 'Zone';

    /**
     * @description Service Territories whose Region Number matches a district #.
     * @param regionNumbers District numbers from the upload file.
     * @return Matching territories.
     */
    public static List<ServiceTerritory> selectTerritoriesByRegionNumbers(Set<String> regionNumbers) {
        if (regionNumbers == null || regionNumbers.isEmpty()) {
            return new List<ServiceTerritory>();
        }
        return [
            SELECT Id, Name, RegionNumber__c, ParentTerritoryId, TerritoryManager__c
            FROM ServiceTerritory
            WHERE RegionNumber__c IN :regionNumbers
        ];
    }

    /**
     * @description Zone territories matched by Region Number or Name.
     * @param zoneKeys Zone numbers from the upload file.
     * @return Matching Zone territories.
     */
    public static List<ServiceTerritory> selectZonesByRegionNumberOrName(Set<String> zoneKeys) {
        if (zoneKeys == null || zoneKeys.isEmpty()) {
            return new List<ServiceTerritory>();
        }
        return [
            SELECT Id, Name, RegionNumber__c, OperatingHoursId
            FROM ServiceTerritory
            WHERE TerritoryType__c = :ZONE_TERRITORY_TYPE
                AND (RegionNumber__c IN :zoneKeys OR Name IN :zoneKeys)
        ];
    }

    /**
     * @description Active users matched by Id, Username, Email or full Name.
     * @param userIds User Ids from the upload file.
     * @param userKeys ASM names / usernames / emails from the upload file.
     * @return Matching active users.
     */
    public static List<User> selectActiveUsers(Set<Id> userIds, Set<String> userKeys) {
        if ((userIds == null || userIds.isEmpty()) && (userKeys == null || userKeys.isEmpty())) {
            return new List<User>();
        }
        Set<Id> ids = userIds == null ? new Set<Id>() : userIds;
        Set<String> keys = userKeys == null ? new Set<String>() : userKeys;
        return [
            SELECT Id, Name, Username, Email
            FROM User
            WHERE IsActive = TRUE
                AND (Id IN :ids OR Username IN :keys OR Email IN :keys OR Name IN :keys)
        ];
    }

    /**
     * @description Latest ContentVersion for a Salesforce File.
     * @param contentDocumentId File Id.
     * @return Latest version, or empty list.
     */
    public static List<ContentVersion> selectLatestVersion(Id contentDocumentId) {
        if (contentDocumentId == null) {
            return new List<ContentVersion>();
        }
        return [
            SELECT Id, Title, FileExtension, PathOnClient, VersionData, ContentDocumentId
            FROM ContentVersion
            WHERE ContentDocumentId = :contentDocumentId
                AND IsLatest = TRUE
            LIMIT 1
        ];
    }

    /**
     * @description ContentDocument by Id.
     * @param contentDocumentId Salesforce Files document Id.
     * @return Matching documents.
     */
    public static List<ContentDocument> selectDocumentsById(Id contentDocumentId) {
        if (contentDocumentId == null) {
            return new List<ContentDocument>();
        }
        return [
            SELECT Id, Title
            FROM ContentDocument
            WHERE Id = :contentDocumentId
            LIMIT 1
        ];
    }

    /**
     * @description Template file previously copied into Salesforce Files.
     * @param title ContentDocument title.
     * @return Matching documents, newest first.
     */
    public static List<ContentDocument> selectDocumentsByTitle(String title) {
        if (String.isBlank(title)) {
            return new List<ContentDocument>();
        }
        return [
            SELECT Id, Title
            FROM ContentDocument
            WHERE Title = :title
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
    }

    /**
     * @description Static resource that holds the packaged template body.
     * @param resourceName Static resource developer name.
     * @return Matching static resources.
     */
    public static List<StaticResource> selectTemplateResource(String resourceName) {
        if (String.isBlank(resourceName)) {
            return new List<StaticResource>();
        }
        return [
            SELECT Id, Name, Body
            FROM StaticResource
            WHERE Name = :resourceName
            LIMIT 1
        ];
    }
}