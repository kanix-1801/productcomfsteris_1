/**
 * @author PWC Developer
 * @date 2026/10/16
 *
 * @group CSC Visit
 *
 * @description
 * GC-3564 - SOQL for Sunshine rows, the CSC Visit, and the people printed on the Visit PDF.
 */
public with sharing class SunshineSelector {

    private static final List<String> VISIT_FIELD_CANDIDATES = new List<String>{
        'Status__c',
        'Confirmed_Date__c',
        'Primary_Requested_Date__c',
        'AccountFacility__c',
        'VisitRequestor__c',
        'VisitPurpose__c',
        'VisitPurposeOther__c',
        'PrimaryCustomerContact__c',
        'CustomerAddressLocation__City__s',
        'CustomerAddressLocation__StateCode__s',
        'VisitAgendaDuration__c',
        'VisitType__c',
        'AnticipatedBusinessValue__c',
        'ProjectedServiceBusiness__c',
        'ProjectedSpend__c',
        'DecisionTimeline__c',
        'ProductQuoted__c',
        'AnticipatedBusinessOpportunityContext__c',
        'ExpectedOpeningMonthYear__c',
        'PDMDrawingProjectReference__c',
        'DrawingNumber__c',
        'Opportunity__c',
        'PrimaryObjective__c',
        'SecondaryObjective__c',
        'AdditionalDetails__c',
        'ConstructionRenovationProject__c',
        'RenovationBuildingProjectContext__c',
        'STERISVisitAccomplishment__c',
        'IncumbentVendor__c',
        'AdditionalBackground__c',
        'ExistingServiceProvider__c',
        'PlanningSessionType__c',
        'PlanningDesignRequired__c',
        'PlanningRequirements__c'
    };

    /**
     * @description Sunshine rows for one Visit, ordered for the PDF.
     * @param visitId CSC Visit Id.
     * @return Sunshine rows the user can read.
     */
    public static List<Sunshine__c> selectByVisit(Id visitId) {
        if (visitId == null) {
            return new List<Sunshine__c>();
        }
        return [
            SELECT Id, Name, NPI__c, First_Name__c, Last_Name__c, City__c, State__c, Credential__c,
                   Taxonomy_Code__c, Taxonomy_Description__c, Type__c, Product_Associated__c,
                   Airfare__c, Hotel__c, Visit_Nights__c, Meals__c, Transportation__c,
                   Total_Reportable_Expense__c
            FROM Sunshine__c
            WHERE CSC_Visit_Request__c = :visitId
            WITH USER_MODE
            ORDER BY Last_Name__c, First_Name__c
        ];
    }

    /**
     * @description One Sunshine row for an expense update.
     * @param sunshineId Sunshine record Id.
     * @return The row, or an empty list when it is not visible.
     */
    public static List<Sunshine__c> selectById(Id sunshineId) {
        if (sunshineId == null) {
            return new List<Sunshine__c>();
        }
        return [
            SELECT Id
            FROM Sunshine__c
            WHERE Id = :sunshineId
            WITH USER_MODE
        ];
    }

    /**
     * @description Other Sunshine rows on the Visit that already use this NPI.
     * @param visitId CSC Visit Id.
     * @param npi Physician NPI.
     * @param currentId Row being updated. Null on create.
     * @return Conflicting rows.
     */
    public static List<Sunshine__c> selectByVisitAndNpi(Id visitId, String npi, Id currentId) {
        if (visitId == null || String.isBlank(npi)) {
            return new List<Sunshine__c>();
        }
        if (currentId == null) {
            return [
                SELECT Id
                FROM Sunshine__c
                WHERE CSC_Visit_Request__c = :visitId
                  AND NPI__c = :npi
                WITH USER_MODE
            ];
        }
        return [
            SELECT Id
            FROM Sunshine__c
            WHERE CSC_Visit_Request__c = :visitId
              AND NPI__c = :npi
              AND Id != :currentId
            WITH USER_MODE
        ];
    }

    /**
     * @description Loads the Visit fields used on the PDF. Fields that are not in the org are skipped.
     * @param visitId CSC Visit Id.
     * @return The Visit, or null.
     */
    public static SObject selectVisit(Id visitId) {
        if (visitId == null) {
            return null;
        }
        Map<String, Schema.SObjectField> fieldMap = CSC_Visit_Request__c.SObjectType.getDescribe(SObjectDescribeOptions.DEFERRED).fields.getMap();
        List<String> selectedFields = new List<String>{ 'Id', 'Name' };
        for (String candidate : VISIT_FIELD_CANDIDATES) {
            if (!fieldMap.containsKey(candidate)) {
                continue;
            }
            Schema.DescribeFieldResult describe = fieldMap.get(candidate).getDescribe();
            if (describe.isAccessible()) {
                selectedFields.add(candidate);
            }
        }
        String soql = 'SELECT ' + String.join(selectedFields, ',')
            + ' FROM CSC_Visit_Request__c WHERE Id = :visitId WITH USER_MODE';
        List<SObject> rows = Database.query(soql);
        return rows.isEmpty() ? null : rows[0];
    }

    /**
     * @description Attendee rows for the Visit. The lookup API name is resolved from the schema.
     * @param visitId CSC Visit Id.
     * @return Attendee rows, or an empty list when the lookup cannot be resolved.
     */
    public static List<SObject> selectAttendees(Id visitId) {
        String lookupField = findVisitLookupField();
        if (visitId == null || String.isBlank(lookupField) || !attendeeFieldExists('STERISAttendee__c')) {
            return new List<SObject>();
        }
        String soql = 'SELECT Id, STERISAttendee__c FROM CSCVisitAttendee__c WHERE '
            + lookupField + ' = :visitId WITH USER_MODE';
        return Database.query(soql);
    }

    /**
     * @description Lookup on CSCVisitAttendee__c that points at CSC_Visit_Request__c.
     * @return Field API name, or null.
     */
    public static String findVisitLookupField() {
        if (!Schema.getGlobalDescribe().containsKey('CSCVisitAttendee__c')) {
            return null;
        }
        for (Schema.SObjectField fieldToken : CSCVisitAttendee__c.SObjectType.getDescribe(SObjectDescribeOptions.DEFERRED).fields.getMap().values()) {
            Schema.DescribeFieldResult describe = fieldToken.getDescribe();
            if (describe.getType() != Schema.DisplayType.REFERENCE) {
                continue;
            }
            for (Schema.SObjectType target : describe.getReferenceTo()) {
                if (target.getDescribe(SObjectDescribeOptions.DEFERRED).getName() == 'CSC_Visit_Request__c') {
                    return describe.getName();
                }
            }
        }
        return null;
    }

    /**
     * @description Users printed as STERIS attendees.
     * @param userIds User Ids.
     * @return Name, title, email, and phone.
     */
    public static List<User> selectUsers(Set<Id> userIds) {
        if (userIds == null || userIds.isEmpty()) {
            return new List<User>();
        }
        return (List<User>) selectPeople('User', userIds);
    }

    /**
     * @description Contacts printed when the attendee or customer is a Contact.
     * @param contactIds Contact Ids.
     * @return Name, title, email, and phone.
     */
    public static List<Contact> selectContacts(Set<Id> contactIds) {
        if (contactIds == null || contactIds.isEmpty()) {
            return new List<Contact>();
        }
        return (List<Contact>) selectPeople('Contact', contactIds);
    }

    private static List<SObject> selectPeople(String objectName, Set<Id> recordIds) {
        Map<String, Schema.SObjectField> fieldMap =
            Schema.getGlobalDescribe().get(objectName).getDescribe(SObjectDescribeOptions.DEFERRED).fields.getMap();
        List<String> selectedFields = new List<String>{ 'Id' };
        for (String candidate : new List<String>{ 'Name', 'FirstName', 'LastName', 'Title', 'Email', 'Phone' }) {
            if (fieldMap.containsKey(candidate) && fieldMap.get(candidate).getDescribe().isAccessible()) {
                selectedFields.add(candidate);
            }
        }
        Boolean canOrderByName = fieldMap.containsKey('LastName')
            && fieldMap.get('LastName').getDescribe().isAccessible()
            && fieldMap.containsKey('FirstName')
            && fieldMap.get('FirstName').getDescribe().isAccessible();
        String orderField = canOrderByName ? 'LastName, FirstName' : 'Name';
        String soql = 'SELECT ' + String.join(selectedFields, ',')
            + ' FROM ' + objectName
            + ' WHERE Id IN :recordIds WITH USER_MODE ORDER BY ' + orderField;
        return Database.query(soql);
    }

    /**
     * @description Name of a related Account, User, Contact, or other named record.
     * @param recordId Related record Id.
     * @return Name, or null.
     */
    /**
     * @description Account name, parent, and billing city used in the PDF header and customer profile.
     * @param accountId Account Id from the Visit.
     * @return The Account, or null.
     */
    public static Account selectAccount(Id accountId) {
        if (accountId == null) {
            return null;
        }
        List<Account> accounts = [
            SELECT Name, Parent.Name, BillingCity, BillingState
            FROM Account
            WHERE Id = :accountId
            WITH USER_MODE
        ];
        return accounts.isEmpty() ? null : accounts[0];
    }

    public static String selectRecordName(Id recordId) {
        if (recordId == null) {
            return null;
        }
        Schema.DescribeSObjectResult describe = recordId.getSObjectType().getDescribe(SObjectDescribeOptions.DEFERRED);
        if (!describe.fields.getMap().containsKey('name')) {
            return null;
        }
        String objectName = describe.getName();
        String soql = 'SELECT Name FROM ' + objectName + ' WHERE Id = :recordId WITH USER_MODE';
        List<SObject> rows = Database.query(soql);
        return rows.isEmpty() ? null : (String) rows[0].get('Name');
    }

    /**
     * @description ContentDocumentId for a file just inserted.
     * @param versionId ContentVersion Id.
     * @return ContentDocumentId, or null.
     */
    public static Id selectContentDocumentId(Id versionId) {
        if (versionId == null) {
            return null;
        }
        List<ContentVersion> versions = [
            SELECT ContentDocumentId
            FROM ContentVersion
            WHERE Id = :versionId
            WITH USER_MODE
        ];
        return versions.isEmpty() ? null : versions[0].ContentDocumentId;
    }

    private static Boolean attendeeFieldExists(String fieldApi) {
        return CSCVisitAttendee__c.SObjectType.getDescribe(SObjectDescribeOptions.DEFERRED).fields.getMap().containsKey(fieldApi);
    }
}