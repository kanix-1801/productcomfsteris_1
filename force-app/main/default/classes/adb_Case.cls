/**
 * Domain Builder for Case
 * Follows a4d-apex-domainbuilder-rules:
 * - Class name adb_Case (standard object), extends adb_DomainBuilder
 * - Constructor calls super(Case.SObjectType) and sets sensible defaults
 * - Fluent setters return adb_Case and use set(SObjectField, Object)
 * - Relationship helpers use setParent(SObjectField, adb_DomainBuilder)
 *
 * Scope: Focused builder with all lookups + common/high-value fields
 */
@IsTest
public with sharing class adb_Case extends adb_DomainBuilder {

    /**
     * Constructs a Case builder with sensible defaults.
     * Defaults chosen to create a valid, commonly-accepted Case:
     * - Subject: random-ish string
     * - Status: New
     * - Origin: Web
     * - Priority: Medium
     */
    public adb_Case() {
        super(Case.SObjectType);
        // Provide sensible defaults
        set(Case.Subject, 'Case - ' + Datetime.now().formatGmt('yyyy-MM-dd\'T\'HH:mm:ss\'Z\''));
        set(Case.Status, 'New');
        set(Case.Origin, 'Web');
        set(Case.Priority, 'Medium');
    }

    // ---------------------------
    // Common Field Setters
    // ---------------------------
    public adb_Case setRecordType(String developerName) {
        super.recordType(developerName);
        return this;
    }

    public adb_Case subject(String value) {
        return (adb_Case) set(Case.Subject, value);
    }

    public adb_Case description(String value) {
        return (adb_Case) set(Case.Description, value);
    }

    public adb_Case type(String value) {
        return (adb_Case) set(Case.Type, value);
    }

    public adb_Case status(String value) {
        return (adb_Case) set(Case.Status, value);
    }

    public adb_Case priority(String value) {
        return (adb_Case) set(Case.Priority, value);
    }

    public adb_Case reason(String value) {
        return (adb_Case) set(Case.Reason, value);
    }

    public adb_Case origin(String value) {
        return (adb_Case) set(Case.Origin, value);
    }

    public adb_Case language(String value) {
        return (adb_Case) set(Case.Language, value);
    }

    public adb_Case suppliedName(String value) {
        return (adb_Case) set(Case.SuppliedName, value);
    }

    public adb_Case suppliedEmail(String value) {
        return (adb_Case) set(Case.SuppliedEmail, value);
    }

    public adb_Case suppliedPhone(String value) {
        return (adb_Case) set(Case.SuppliedPhone, value);
    }

    public adb_Case suppliedCompany(String value) {
        return (adb_Case) set(Case.SuppliedCompany, value);
    }

    public adb_Case isEscalated(Boolean value) {
        return (adb_Case) set(Case.IsEscalated, value);
    }

    public adb_Case closedDate(Datetime value) {
        return (adb_Case) set(Case.ClosedDate, value);
    }

    public adb_Case slaStartDate(Datetime value) {
        return (adb_Case) set(Case.SlaStartDate, value);
    }

    public adb_Case slaExitDate(Datetime value) {
        return (adb_Case) set(Case.SlaExitDate, value);
    }

    // ---------------------------
    // Helpful Additional Fields (customs frequently referenced)
    // ---------------------------

    public adb_Case milestoneStatus(String value) {
        return (adb_Case) set(Case.MilestoneStatus, value);
    }

    // public adb_Case closeReason__c(String value) {
    //     return (adb_Case) set(Case.CloseReason__c, value);
    // }

    // public adb_Case subStatus__c(String value) {
    //     return (adb_Case) set(Case.SubStatus__c, value);
    // }

    // public adb_Case caseSource__c(String value) {
    //     return (adb_Case) set(Case.CaseSource__c, value);
    // }

    // public adb_Case urgentOrder__c(Boolean value) {
    //     return (adb_Case) set(Case.UrgentOrder__c, value);
    // }

    // public adb_Case customerWantDate__c(Date value) {
    //     return (adb_Case) set(Case.Customer_Want_Date__c, value);
    // }

    // ---------------------------
    // Relationship Helpers (Lookups)
    // ---------------------------

    // public adb_Case account(adb_Account a) {
    //     return (adb_Case) setParent(Case.AccountId, a);
    // }

    // public adb_Case contact(adb_Contact c) {
    //     return (adb_Case) setParent(Case.ContactId, c);
    // }

    // public adb_Case asset(adb_Asset a) {
    //     return (adb_Case) setParent(Case.AssetId, a);
    // }

    // public adb_Case product(adb_Product2 p) {
    //     return (adb_Case) setParent(Case.ProductId, p);
    // }

    // public adb_Case entitlement(adb_Entitlement e) {
    //     return (adb_Case) setParent(Case.EntitlementId, e);
    // }

    // public adb_Case businessHours(adb_BusinessHours bh) {
    //     return (adb_Case) setParent(Case.BusinessHoursId, bh);
    // }

    public adb_Case parent(adb_Case parentCase) {
        return (adb_Case) setParent(Case.ParentId, parentCase);
    }

    // public adb_Case owner(adb_User u) {
    //     return (adb_Case) setParent(Case.OwnerId, u);
    // }

    // public adb_Case recordType(adb_RecordType rt) {
    //     return (adb_Case) setParent(Case.RecordTypeId, rt);
    // }

    // public adb_Case assetWarranty(adb_AssetWarranty aw) {
    //     return (adb_Case) setParent(Case.AssetWarrantyId, aw);
    // }

    // public adb_Case serviceContract(adb_ServiceContract sc) {
    //     return (adb_Case) setParent(Case.ServiceContractId, sc);
    // }

    // Custom lookups from provided Case representation
    public adb_Case project_c(adb_Project_c prj) {
        return (adb_Case) setParent(Case.Project__c, prj);
    }

    // public adb_Case order__c(adb_Order ord) {
    //     return (adb_Case) setParent(Case.Order__c, ord);
    // }

    // public adb_Case orderLine__c(adb_OrderItem oli) {
    //     return (adb_Case) setParent(Case.OrderLine__c, oli);
    // }

    // ---------------------------
    // Convenience: contact details
    // ---------------------------

    public adb_Case contactPhone(String value) {
        return (adb_Case) set(Case.ContactPhone, value);
    }

    public adb_Case contactMobile(String value) {
        return (adb_Case) set(Case.ContactMobile, value);
    }

    public adb_Case contactEmail(String value) {
        return (adb_Case) set(Case.ContactEmail, value);
    }

    public adb_Case contactFax(String value) {
        return (adb_Case) set(Case.ContactFax, value);
    }
}