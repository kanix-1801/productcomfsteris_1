/**
 * @description Domain Builder for the Opportunity SObject.
 *              Provides a fluent API for creating test Opportunity records.
 */
@IsTest
public class adb_Opportunity extends adb_DomainBuilder {
    /**
     * @description Constructs an Opportunity builder with the fields Quote Line Item tests require.
     */
    public adb_Opportunity() {
        super(Opportunity.SObjectType);
        set(Opportunity.Name, 'Test Opportunity');
        set(Opportunity.StageName, firstActiveValue(Opportunity.StageName, 'Discovery'));
        set(Opportunity.CloseDate, Date.today().addDays(30));
        set(Opportunity.Amount, 100);
        set(Opportunity.Probability, 10);
        set(Opportunity.Type, firstActiveValue(Opportunity.Type, 'Extension'));
        set(Opportunity.Pricebook2Id, Test.getStandardPricebookId());
        String forecastConfidence = firstActiveValue(Opportunity.ForecastConfidenceLevel__c, null);
        if (forecastConfidence != null) {
            set(Opportunity.ForecastConfidenceLevel__c, forecastConfidence);
        }
    }

    /**
     * @description Sets the Opportunity Name.
     * @param value The name value.
     * @return This builder instance.
     */
    public adb_Opportunity name(String value) {
        return (adb_Opportunity) set(Opportunity.Name, value);
    }

    /**
     * @description Sets the related Account lookup.
     * @param account The parent Account builder.
     * @return This builder instance.
     */
    public adb_Opportunity account(adb_Account account) {
        setParent(Opportunity.AccountId, account);
        return this;
    }

    /**
     * @description Sets the primary Contact lookup.
     * @param contact The parent Contact builder.
     * @return This builder instance.
     */
    public adb_Opportunity primaryContact(adb_Contact contact) {
        setParent(Opportunity.PrimaryContact__c, contact);
        return this;
    }

    /**
     * @description Sets Pricebook2Id.
     * @param value Pricebook Id.
     * @return This builder instance.
     */
    public adb_Opportunity pricebook2Id(Id value) {
        return (adb_Opportunity) set(Opportunity.Pricebook2Id, value);
    }

    private static String firstActiveValue(Schema.SObjectField field, String fallback) {
        for (Schema.PicklistEntry picklistEntry : field.getDescribe().getPicklistValues()) {
            if (picklistEntry.isActive()) {
                return picklistEntry.getValue();
            }
        }
        return fallback;
    }
}