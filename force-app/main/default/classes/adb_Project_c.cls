@IsTest
/**
 * Domain Builder for Project__c
 * Follows adb_DomainBuilder conventions defined in a4d-apex-domainbuilder-rules.md
 *
 * Naming: __c -> _c
 * Location: force-app/main/default/classes
 *
 * Provides:
 * - Constructor calling super(Project__c.SObjectType) with sensible defaults
 * - Fluent setters for standard and custom fields
 * - Relationship helpers for lookups (Account__c, ProjectTemplate__c, ProjectContact__c, PrimaryCase__c)
 *
 * Note:
 * - Add additional setters as new fields are introduced on Project__c.
 */
public with sharing class adb_Project_c extends adb_DomainBuilder {

    /**
     * Create a Project__c builder with sensible defaults.
     * Defaults:
     * - Name: 'Project ' + unique sequence
     * - Stage__c: 'New' (common default)
     * - ProjectStartDate__c: Date.today()
     */
    public adb_Project_c() {
        super(Project__c.SObjectType);
        // Provide common defaults
        name('Project ' + uniqueSuffix());
        projectStartDate(Date.today());
    }

    /**
     * Utility to produce a short unique suffix for default naming.
     */
    private static String uniqueSuffix() {
        // Use time-based suffix; adb_DomainBuilder commonly provides helpers, but safe fallback here.
        return String.valueOf(Datetime.now().getTime()).right(6);
    }

    // -----------------------------
    // Standard/base field setters
    // -----------------------------

    /**
     * Set Name
     */
    public adb_Project_c name(String value) {
        return (adb_Project_c) set(Project__c.Name, value);
    }

    /**
     * Set OwnerId
     */
    public adb_Project_c owner(Id value) {
        return (adb_Project_c) set(Project__c.OwnerId, value);
    }

    /**
     * Set CurrencyIsoCode
     */
    public adb_Project_c currencyIsoCode(String value) {
        return (adb_Project_c) set(Project__c.CurrencyIsoCode, value);
    }

    // -----------------------------
    // Date fields
    // -----------------------------

    /**
     * Set ProjectStartDate__c
     */
    public adb_Project_c projectStartDate(Date value) {
        return (adb_Project_c) set(Project__c.ProjectStartDate__c, value);
    }

    /**
     * Set ProjectEndDate__c
     */
    public adb_Project_c projectEndDate(Date value) {
        return (adb_Project_c) set(Project__c.ProjectEndDate__c, value);
    }

    /**
     * Set ProjectRequestedDate__c
     */
    public adb_Project_c projectRequestedDate(Date value) {
        return (adb_Project_c) set(Project__c.ProjectRequestedDate__c, value);
    }

    /**
     * Set ProjectShippedDate__c
     */
    public adb_Project_c projectShippedDate(Date value) {
        return (adb_Project_c) set(Project__c.ProjectShippedDate__c, value);
    }

    /**
     * Set FirstDateOrdered__c (read-only mirror in production, but allow for tests if not protected)
     */
    public adb_Project_c firstDateOrdered(Date value) {
        return (adb_Project_c) set(Project__c.FirstDateOrdered__c, value);
    }

    /**
     * Set CustomerWantDate__c (read-only mirror in production, but available here for convenience)
     */
    public adb_Project_c customerWantDate(Date value) {
        return (adb_Project_c) set(Project__c.CustomerWantDate__c, value);
    }

    // -----------------------------
    // Lookup relationships (helpers)
    // -----------------------------

    /**
     * Set Account__c via Id
     */
    public adb_Project_c account(Id accountId) {
        return (adb_Project_c) set(Project__c.Account__c, accountId);
    }

    // /**
    //  * Link to Account via builder (uses setParent pattern)
    //  */
    // public adb_Project_c account(adb_Account a) {
    //     return (adb_Project_c) setParent(Project__c.Account__c, a);
    // }

    /**
     * Set ProjectTemplate__c via Id
     */
    public adb_Project_c projectTemplate(Id templateId) {
        return (adb_Project_c) set(Project__c.ProjectTemplate__c, templateId);
    }

    // /**
    //  * Link to ProjectTemplate via builder
    //  */
    // public adb_Project_c projectTemplate(adb_ProjectTemplate_c t) {
    //     return (adb_Project_c) setParent(Project__c.ProjectTemplate__c, t);
    // }

    /**
     * Set ProjectContact__c via Id
     */
    public adb_Project_c projectContact(Id contactId) {
        return (adb_Project_c) set(Project__c.ProjectContact__c, contactId);
    }

    // /**
    //  * Link to Contact via builder
    //  */
    // public adb_Project_c projectContact(adb_Contact c) {
    //     return (adb_Project_c) setParent(Project__c.ProjectContact__c, c);
    // }

    /**
     * Set PrimaryCase__c via Id
     */
    public adb_Project_c primaryCase(Id caseId) {
        return (adb_Project_c) set(Project__c.PrimaryCase__c, caseId);
    }

    // /**
    //  * Link to Case via builder
    //  */
    // public adb_Project_c primaryCase(adb_Case c) {
    //     return (adb_Project_c) setParent(Project__c.PrimaryCase__c, c);
    // }

    // -----------------------------
    // Text fields
    // -----------------------------

    /**
     * Set ProjectDescription__c
     */
    public adb_Project_c projectDescription(String value) {
        return (adb_Project_c) set(Project__c.ProjectDescription__c, value);
    }

    /**
     * Set Stage__c
     */
    public adb_Project_c stage(String value) {
        return (adb_Project_c) set(Project__c.Stage__c, value);
    }

    /**
     * Set PrimaryEST__c
     */
    public adb_Project_c primaryEST(String value) {
        return (adb_Project_c) set(Project__c.PrimaryEST__c, value);
    }

    /**
     * Set PrimaryInstaller__c
     */
    public adb_Project_c primaryInstaller(String value) {
        return (adb_Project_c) set(Project__c.PrimaryInstaller__c, value);
    }

    /**
     * Set DistrictServiceManager__c
     */
    public adb_Project_c districtServiceManager(String value) {
        return (adb_Project_c) set(Project__c.DistrictServiceManager__c, value);
    }

    /**
     * Set CapitalAccountManager__c
     */
    public adb_Project_c capitalAccountManager(String value) {
        return (adb_Project_c) set(Project__c.CapitalAccountManager__c, value);
    }

    /**
     * Set SaleOrderNumbers__c (read-only mirror in production, exposed for tests)
     */
    public adb_Project_c saleOrderNumbers(String value) {
        return (adb_Project_c) set(Project__c.SaleOrderNumbers__c, value);
    }

    /**
     * Set RegistrationNumber__c (read-only mirror in production, exposed for tests)
     */
    public adb_Project_c registrationNumber(String value) {
        return (adb_Project_c) set(Project__c.RegistrationNumber__c, value);
    }

    /**
     * Set AccountNumber__c (read-only mirror in production, exposed for tests)
     */
    public adb_Project_c accountNumber(String value) {
        return (adb_Project_c) set(Project__c.AccountNumber__c, value);
    }

    /**
     * Set CustomerName__c (read-only mirror in production, exposed for tests)
     */
    public adb_Project_c customerName(String value) {
        return (adb_Project_c) set(Project__c.CustomerName__c, value);
    }

    /**
     * Set PurchaseOrderNumber__c (read-only mirror in production, exposed for tests)
     */
    public adb_Project_c purchaseOrderNumber(String value) {
        return (adb_Project_c) set(Project__c.PurchaseOrderNumber__c, value);
    }

    /**
     * Set PrimaryContact__c (read-only mirror in production, exposed for tests)
     */
    public adb_Project_c primaryContact(String value) {
        return (adb_Project_c) set(Project__c.PrimaryContact__c, value);
    }

    /**
     * Set BillingAddress__c (read-only mirror in production, exposed for tests)
     */
    public adb_Project_c billingAddress(String value) {
        return (adb_Project_c) set(Project__c.BillingAddress__c, value);
    }

    /**
     * Set ContactType__c (read-only mirror in production, exposed for tests)
     */
    public adb_Project_c contactType(String value) {
        return (adb_Project_c) set(Project__c.ContactType__c, value);
    }

    /**
     * Set ShippingAddress__c (read-only mirror in production, exposed for tests)
     */
    public adb_Project_c shippingAddress(String value) {
        return (adb_Project_c) set(Project__c.ShippingAddress__c, value);
    }

    /**
     * Set OrderCity__c
     */
    public adb_Project_c orderCity(String value) {
        return (adb_Project_c) set(Project__c.OrderCity__c, value);
    }

    /**
     * Set OrderState__c
     */
    public adb_Project_c orderState(String value) {
        return (adb_Project_c) set(Project__c.OrderState__c, value);
    }

    // -----------------------------
    // Booleans
    // -----------------------------

    /**
     * Set Urgency__c
     */
    public adb_Project_c urgency(Boolean value) {
        return (adb_Project_c) set(Project__c.Urgency__c, value);
    }
}