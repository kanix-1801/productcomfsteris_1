/**
 * @description Domain Builder for the Quote SObject.
 *              Provides a fluent API for creating test Quote records.
 */
@IsTest
public class adb_Quote extends adb_DomainBuilder {
    /**
     * @description Constructs a Quote builder on the standard pricebook.
     */
    public adb_Quote() {
        super(Quote.SObjectType);
        set(Quote.Name, 'Test Quote');
        set(Quote.Pricebook2Id, Test.getStandardPricebookId());
    }

    /**
     * @description Sets the Quote Name.
     * @param value The name value.
     * @return This builder instance.
     */
    public adb_Quote name(String value) {
        return (adb_Quote) set(Quote.Name, value);
    }

    /**
     * @description Sets the related Opportunity lookup.
     * @param opportunity The parent Opportunity builder.
     * @return This builder instance.
     */
    public adb_Quote opportunity(adb_Opportunity opportunity) {
        setParent(Quote.OpportunityId, opportunity);
        return this;
    }

    /**
     * @description Sets Pricebook2Id.
     * @param value Pricebook Id.
     * @return This builder instance.
     */
    public adb_Quote pricebook2Id(Id value) {
        return (adb_Quote) set(Quote.Pricebook2Id, value);
    }
}