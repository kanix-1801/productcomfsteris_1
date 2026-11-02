/**
 * @description Domain Builder for the Account SObject.
 *              Provides a fluent API for creating test Account records.
 */
@IsTest
public class adb_Account extends adb_DomainBuilder {
    /**
     * @description GW-3164 - Constructs an Account builder with STERIS-friendly defaults.
     *              Shortens SystemID__c / SourceSystemID__c defaults to the org 15-char limit.
     */
    public adb_Account() {
        super(Account.SObjectType);
        // GW-3164 - SystemID__c / SourceSystemID__c are limited to 15 characters in this org.
        String uniquePart = String.valueOf(Math.abs(Crypto.getRandomInteger())).right(8);
        set(Account.Name, 'Test Account ' + uniquePart);
        set(Account.SourceSystemID__c, ('SYS-' + uniquePart).left(15));
        set(Account.SystemID__c, ('LEG-' + uniquePart).left(15));
        set(Account.OrgIDs__c, '82');
    }

    /**
     * @description Sets the Account Name.
     * @param value The name value.
     * @return This builder instance.
     */
    public adb_Account name(String value) {
        return (adb_Account) set(Account.Name, value);
    }

    /**
     * @description Sets SourceSystemID__c.
     * @param value Source system identifier.
     * @return This builder instance.
     */
    public adb_Account sourceSystemId(String value) {
        return (adb_Account) set(Account.SourceSystemID__c, value);
    }

    /**
     * @description Sets SystemID__c.
     * @param value Legacy / system identifier.
     * @return This builder instance.
     */
    public adb_Account systemId(String value) {
        return (adb_Account) set(Account.SystemID__c, value);
    }

    /**
     * @description Sets OrgIDs__c.
     * @param value Operating unit / org ids value.
     * @return This builder instance.
     */
    public adb_Account orgIds(String value) {
        return (adb_Account) set(Account.OrgIDs__c, value);
    }

    /**
     * @description Sets the Account Number.
     * @param value The account number value.
     * @return This builder instance.
     */
    public adb_Account accountNumber(String value) {
        return (adb_Account) set(Account.AccountNumber, value);
    }

    /**
     * @description Sets the Parent Account relationship.
     * @param parent The parent Account builder.
     * @return This builder instance.
     */
    public adb_Account parent(adb_Account parent) {
        return (adb_Account) setParent(Account.ParentId, parent);
    }
}