/**
 * @description GW-2707 - SOQL for Tech District Alignment. Inherited sharing: territory, resource and membership
 *              lookups run without sharing when called from TechDistrictAlignmentService.TerritoryStore.
 */
public inherited sharing class TechDistrictAlignmentSelector {
    /**
     * @description Active users whose Employee Number (HRIS ID) matches.
     * @param employeeNumbers HRIS IDs from the upload file.
     * @return Matching active users.
     */
    public static List<User> selectActiveUsersByEmployeeNumbers(Set<String> employeeNumbers) {
        if (employeeNumbers == null || employeeNumbers.isEmpty()) {
            return new List<User>();
        }
        return [
            SELECT Id, Name, EmployeeNumber__c
            FROM User
            WHERE IsActive = TRUE
                AND EmployeeNumber__c IN :employeeNumbers
        ];
    }

    /**
     * @description Active Service Resources whose External ID (technician HRIS ID) matches.
     * @param externalIds Technician HRIS IDs from the upload file.
     * @return Matching active Service Resources.
     */
    public static List<ServiceResource> selectActiveResourcesByExternalIds(Set<String> externalIds) {
        if (externalIds == null || externalIds.isEmpty()) {
            return new List<ServiceResource>();
        }
        return [
            SELECT Id, Name, ExternalID__c, RelatedRecordId
            FROM ServiceResource
            WHERE IsActive = TRUE
                AND ExternalID__c IN :externalIds
        ];
    }

    /**
     * @description Service Territories whose Territory ID (Region Number) matches.
     * @param regionNumbers Territory IDs from the upload file.
     * @return Matching territories.
     */
    public static List<ServiceTerritory> selectTerritoriesByRegionNumbers(Set<String> regionNumbers) {
        if (regionNumbers == null || regionNumbers.isEmpty()) {
            return new List<ServiceTerritory>();
        }
        return [
            SELECT Id, Name, RegionNumber__c, TerritoryType__c, TerritoryManager__c, ParentTerritoryId, OperatingHoursId, IsActive
            FROM ServiceTerritory
            WHERE RegionNumber__c IN :regionNumbers
        ];
    }

    /**
     * @description Territory memberships not ended before the given time, newest start first.
     * @param resourceIds Service Resources in the upload file.
     * @param territoryIds Territories in the upload file.
     * @param endedBefore Memberships ending before this time are ignored.
     * @return Matching memberships.
     */
    public static List<ServiceTerritoryMember> selectOpenMembers(Set<Id> resourceIds, Set<Id> territoryIds, Datetime endedBefore) {
        if (resourceIds == null || resourceIds.isEmpty() || territoryIds == null || territoryIds.isEmpty() || endedBefore == null) {
            return new List<ServiceTerritoryMember>();
        }
        return [
            SELECT Id, ServiceResourceId, ServiceTerritoryId, TerritoryType, OperatingHoursId, EffectiveStartDate, EffectiveEndDate
            FROM ServiceTerritoryMember
            WHERE ServiceResourceId IN :resourceIds
                AND ServiceTerritoryId IN :territoryIds
                AND (EffectiveEndDate = NULL OR EffectiveEndDate >= :endedBefore)
            ORDER BY EffectiveStartDate DESC
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