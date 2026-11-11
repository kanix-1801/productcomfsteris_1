/**
 * @description Selector class for Case object - handles all SOQL queries for Case records.
 *              Centralizes field lists, enforces security, and provides consistent query patterns.
 *              Follows STERIS enterprise architecture standards.
 * @author STERIS
 * @date 2026-04-22
 */
public with sharing class CasesSelector {
    
    /**
     * @description Base fields used in all Case queries for consistency
     */
    private static final String BASE_FIELDS = 
        'Id, CaseNumber, Subject, Description, Status, Priority, Origin, Type, Reason, ' +
        'AccountId, ContactId, AssetId, ParentId, OwnerId, RecordTypeId, ' +
        'ClosedDate, CreatedDate, LastModifiedDate, IsClosed, IsEscalated, ' +
        'SuppliedName, SuppliedEmail, SuppliedPhone, SuppliedCompany, ' +
        'ContactPhone, ContactEmail, ContactMobile, ContactFax';
    
    /**
     * @description Extended fields including custom fields commonly queried
     */
    private static final String EXTENDED_FIELDS = 
        BASE_FIELDS + ', ' +
        'Customer_Want_Date__c, Order__c, OrderLine__c, Project__c, ' +
        'OverAll_GO_NOGODecision__c, MilestoneStatus, SlaStartDate, SlaExitDate';
    
    /**
     * @description Selects Cases by their Ids with base fields
     * @param caseIds Set of Case Ids to query
     * @return List of Case records with base fields
     */
    public static List<Case> selectById(Set<Id> caseIds) {
        if (caseIds == null || caseIds.isEmpty()) {
            return new List<Case>();
        }
        
        return Database.query(
            'SELECT ' + BASE_FIELDS + 
            ' FROM Case ' +
            ' WHERE Id IN :caseIds ' +
            ' WITH SECURITY_ENFORCED'
        );
    }
    
    /**
     * @description Selects Cases by their Ids with extended fields including custom fields
     * @param caseIds Set of Case Ids to query
     * @return List of Case records with extended fields
     */
    public static List<Case> selectByIdWithExtendedFields(Set<Id> caseIds) {
        if (caseIds == null || caseIds.isEmpty()) {
            return new List<Case>();
        }
        
        return Database.query(
            'SELECT ' + EXTENDED_FIELDS + 
            ' FROM Case ' +
            ' WHERE Id IN :caseIds ' +
            ' WITH SECURITY_ENFORCED'
        );
    }
    
    /**
     * @description Selects Cases by Account Id
     * @param accountIds Set of Account Ids
     * @return List of Case records for the given accounts
     */
    public static List<Case> selectByAccountIds(Set<Id> accountIds) {
        if (accountIds == null || accountIds.isEmpty()) {
            return new List<Case>();
        }
        
        return Database.query(
            'SELECT ' + EXTENDED_FIELDS + 
            ' FROM Case ' +
            ' WHERE AccountId IN :accountIds ' +
            ' WITH SECURITY_ENFORCED ' +
            ' ORDER BY CreatedDate DESC'
        );
    }
    
    /**
     * @description Selects Cases by Contact Id
     * @param contactIds Set of Contact Ids
     * @return List of Case records for the given contacts
     */
    public static List<Case> selectByContactIds(Set<Id> contactIds) {
        if (contactIds == null || contactIds.isEmpty()) {
            return new List<Case>();
        }
        
        return Database.query(
            'SELECT ' + EXTENDED_FIELDS + 
            ' FROM Case ' +
            ' WHERE ContactId IN :contactIds ' +
            ' WITH SECURITY_ENFORCED ' +
            ' ORDER BY CreatedDate DESC'
        );
    }
    
    /**
     * @description Selects Cases by Order Id
     * @param orderIds Set of Order Ids (custom field Order__c)
     * @return List of Case records for the given orders
     */
    public static List<Case> selectByOrderIds(Set<Id> orderIds) {
        if (orderIds == null || orderIds.isEmpty()) {
            return new List<Case>();
        }
        
        return Database.query(
            'SELECT ' + EXTENDED_FIELDS + 
            ' FROM Case ' +
            ' WHERE Order__c IN :orderIds ' +
            ' WITH SECURITY_ENFORCED ' +
            ' ORDER BY CreatedDate DESC'
        );
    }
    
    /**
     * @description Selects Cases by Record Type Developer Name
     * @param recordTypeDeveloperName Record Type Developer Name
     * @param limitCount Maximum number of records to return (optional)
     * @return List of Case records matching the record type
     */
    public static List<Case> selectByRecordTypeDeveloperName(
        String recordTypeDeveloperName,
        Integer limitCount
    ) {
        if (String.isBlank(recordTypeDeveloperName)) {
            return new List<Case>();
        }
        
        // Get Record Type Id by developer name
        Id recordTypeId = Schema.SObjectType.Case
            .getRecordTypeInfosByDeveloperName()
            .get(recordTypeDeveloperName)
            ?.getRecordTypeId();
        
        if (recordTypeId == null) {
            return new List<Case>();
        }
        
        String query = 
            'SELECT ' + EXTENDED_FIELDS + 
            ' FROM Case ' +
            ' WHERE RecordTypeId = :recordTypeId ' +
            ' WITH SECURITY_ENFORCED ' +
            ' ORDER BY CreatedDate DESC';
        
        if (limitCount != null && limitCount > 0) {
            query += ' LIMIT ' + limitCount;
        }
        
        return Database.query(query);
    }
    
    /**
     * @description Selects open Cases (IsClosed = false) by Account Id
     * @param accountIds Set of Account Ids
     * @return List of open Case records for the given accounts
     */
    public static List<Case> selectOpenCasesByAccountIds(Set<Id> accountIds) {
        if (accountIds == null || accountIds.isEmpty()) {
            return new List<Case>();
        }
        
        return Database.query(
            'SELECT ' + EXTENDED_FIELDS + 
            ' FROM Case ' +
            ' WHERE AccountId IN :accountIds ' +
            ' AND IsClosed = false ' +
            ' WITH SECURITY_ENFORCED ' +
            ' ORDER BY CreatedDate DESC'
        );
    }

    /**
     * @description GW-3997 - QueryLocator for closed Inbox Support Cases whose ClosedDate
     *              calendar day is exactly 7 days before the run date.
     * @param closedDateStart Inclusive lower bound for ClosedDate
     * @param closedDateEnd Exclusive upper bound for ClosedDate
     * @return QueryLocator of Cases eligible for FCR evaluation
     */
    public static Database.QueryLocator selectClosedInboxSupportForFcrQueryLocator(
        Date closedDateStart,
        Date closedDateEnd
    ) {
        return Database.getQueryLocator([
            SELECT
                Id,
                ContactId,
                AssetId,
                SerialNumber__c,
                SuppliedEmail,
                Category__c,
                CreatedDate,
                ClosedDate,
                IsFCR__c
            FROM Case
            WHERE IsClosed = TRUE
                AND RecordType.DeveloperName = 'InboxSupport'
                AND Label__c != 'AutoClosed'
                AND Category__c != NULL
                AND ClosedDate >= :closedDateStart
                AND ClosedDate < :closedDateEnd
                AND (
                    ContactId != NULL
                    OR AssetId != NULL
                    OR SerialNumber__c != NULL
                    OR SuppliedEmail != NULL
                )
            WITH SECURITY_ENFORCED
        ]);
    }

    /**
     * @description GW-3997 - Selects Cases that may match FCR criteria within a date window.
     * @param categorySet Categories from the current batch scope
     * @param contactIdSet Contact Ids from the current batch scope
     * @param assetIdSet Asset Ids from the current batch scope
     * @param serialNumberSet Serial numbers from the current batch scope
     * @param suppliedEmailSet Supplied emails from the current batch scope
     * @param createdDateStart Inclusive lower bound for CreatedDate
     * @param createdDateEnd Inclusive upper bound for CreatedDate
     * @return Matching Case rows for FCR related-case counting
     */
    public static List<Case> selectRelatedCasesForFcr(
        Set<String> categorySet,
        Set<Id> contactIdSet,
        Set<Id> assetIdSet,
        Set<String> serialNumberSet,
        Set<String> suppliedEmailSet,
        Datetime createdDateStart,
        Datetime createdDateEnd
    ) {
        if (
            categorySet == null
            || categorySet.isEmpty()
            || createdDateStart == null
            || createdDateEnd == null
        ) {
            return new List<Case>();
        }

        Boolean hasIdentifier =
            (contactIdSet != null && !contactIdSet.isEmpty())
            || (assetIdSet != null && !assetIdSet.isEmpty())
            || (serialNumberSet != null && !serialNumberSet.isEmpty())
            || (suppliedEmailSet != null && !suppliedEmailSet.isEmpty());
        if (!hasIdentifier) {
            return new List<Case>();
        }

        return [
            SELECT
                Id,
                ContactId,
                AssetId,
                SerialNumber__c,
                SuppliedEmail,
                Category__c,
                CreatedDate
            FROM Case
            WHERE Category__c IN :categorySet
                AND CreatedDate >= :createdDateStart
                AND CreatedDate <= :createdDateEnd
                AND (
                    ContactId IN :contactIdSet
                    OR AssetId IN :assetIdSet
                    OR SerialNumber__c IN :serialNumberSet
                    OR SuppliedEmail IN :suppliedEmailSet
                )
            WITH SECURITY_ENFORCED
        ];
    }

    /**
     * @description GW-1509 - Open Cases for Create Return Order account picklist.
     * @param accountId Account Id
     * @return Open Cases ordered by CaseNumber
     */
    public static List<Case> selectOpenByAccountIdForCreateReturnOrder(Id accountId) {
        if (accountId == null) {
            return new List<Case>();
        }
        return (List<Case>) SoqlQueryBuilder.fromObject('Case')
            .selectFields(new List<String>{ 'Id', 'CaseNumber', 'Subject' })
            .whereEquals('AccountId', accountId)
            .whereEquals('IsClosed', false)
            .orderBy('CaseNumber')
            .execute();
    }

    /**
     * @description GW-1509 - Case account/label fields for Create Return Order launch context.
     * @param caseId Case Id
     * @return Matching Case rows (LIMIT 1)
     */
    public static List<Case> selectAccountContextById(Id caseId) {
        if (caseId == null) {
            return new List<Case>();
        }
        return (List<Case>) SoqlQueryBuilder.fromObject('Case')
            .selectFields(new List<String>{ 'AccountId', 'CaseNumber', 'Subject' })
            .whereEquals('Id', caseId)
            .limitTo(1)
            .execute();
    }

}