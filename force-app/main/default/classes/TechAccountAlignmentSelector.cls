/**
 * @description GW-2710 - SOQL for Tech Account Alignment mass technician assignment.
 */
public with sharing class TechAccountAlignmentSelector {
    /**
     * @description Address accounts keyed by Oracle Address Id.
     * @param oracleAddressIds Address IDs from the upload file.
     * @return Matching Address accounts.
     */
    public static List<Account> selectAddressAccountsByOracleAddressIds(Set<String> oracleAddressIds) {
        if (oracleAddressIds == null || oracleAddressIds.isEmpty()) {
            return new List<Account>();
        }
        return [
            SELECT
                Id,
                Name,
                Type,
                ParentId,
                OracleAddressId__c,
                ShiptoAddressStatus__c,
                BilltoAddressStatus__c,
                NotServiceable__c,
                SMI__c,
                CustomerProfileClass__c,
                Parent.Type,
                Parent.SMI__c,
                Parent.CustomerProfileClass__c
            FROM Account
            WHERE Type = 'Address'
                AND OracleAddressId__c IN :oracleAddressIds
        ];
    }

    /**
     * @description Active Service Resources whose RelatedRecordId matches the supplied User Ids.
     * @param userIds Technician User Ids from the upload file.
     * @return Matching active Service Resources.
     */
    public static List<ServiceResource> selectActiveResourcesByUserIds(Set<Id> userIds) {
        if (userIds == null || userIds.isEmpty()) {
            return new List<ServiceResource>();
        }
        return [
            SELECT Id, Name, RelatedRecordId, IsActive
            FROM ServiceResource
            WHERE IsActive = TRUE
                AND RelatedRecordId IN :userIds
        ];
    }

    /**
     * @description Work Types matched by name.
     * @param workTypeNames Work Type names from the upload file.
     * @return Matching Work Types.
     */
    public static List<WorkType> selectWorkTypesByNames(Set<String> workTypeNames) {
        if (workTypeNames == null || workTypeNames.isEmpty()) {
            return new List<WorkType>();
        }
        return [
            SELECT Id, Name
            FROM WorkType
            WHERE Name IN :workTypeNames
        ];
    }

    /**
     * @description Existing AddressResourcePreference rows for the given Address accounts.
     * @param addressAccountIds Address Account Ids being assigned.
     * @return Existing preference records.
     */
    public static List<AddressResourcePreference__c> selectExistingPreferences(Set<Id> addressAccountIds) {
        if (addressAccountIds == null || addressAccountIds.isEmpty()) {
            return new List<AddressResourcePreference__c>();
        }
        return [
            SELECT Id, AddressAccount__c, ServiceResource__c, TerritoryType__c, WorkType__c
            FROM AddressResourcePreference__c
            WHERE AddressAccount__c IN :addressAccountIds
        ];
    }

    /**
     * @description Latest ContentVersion for a Salesforce File.
     * @param contentDocumentId File Id from lightning-file-upload.
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