/**
 * @description Domain Builder for the QuoteLineItem SObject.
 *              Provides a fluent API for creating test Quote Line Item records.
 */
@IsTest
public class adb_QuoteLineItem extends adb_DomainBuilder {
    /**
     * @description Constructs a Quote Line Item builder with quantity and price defaults.
     */
    public adb_QuoteLineItem() {
        super(QuoteLineItem.SObjectType);
        set(QuoteLineItem.Quantity, 1);
        set(QuoteLineItem.UnitPrice, 1);
    }

    /**
     * @description Sets the related Quote lookup.
     * @param quoteRecord The parent Quote builder.
     * @return This builder instance.
     */
    public adb_QuoteLineItem quote(adb_Quote quoteRecord) {
        setParent(QuoteLineItem.QuoteId, quoteRecord);
        return this;
    }

    /**
     * @description Sets QuoteId when the Quote is already inserted.
     * @param quoteId Inserted Quote Id.
     * @return This builder instance.
     */
    public adb_QuoteLineItem quoteId(Id quoteId) {
        return (adb_QuoteLineItem) set(QuoteLineItem.QuoteId, quoteId);
    }

    /**
     * @description Sets the related Pricebook Entry lookup.
     * @param pricebookEntry The parent Pricebook Entry builder.
     * @return This builder instance.
     */
    public adb_QuoteLineItem pricebookEntry(adb_PricebookEntry pricebookEntry) {
        setParent(QuoteLineItem.PricebookEntryId, pricebookEntry);
        return this;
    }

    /**
     * @description Sets PricebookEntryId when the Pricebook Entry is already inserted.
     * @param pricebookEntryId Inserted Pricebook Entry Id.
     * @return This builder instance.
     */
    public adb_QuoteLineItem pricebookEntryId(Id pricebookEntryId) {
        return (adb_QuoteLineItem) set(QuoteLineItem.PricebookEntryId, pricebookEntryId);
    }

    /**
     * @description Sets the related Quote Action lookup.
     * @param quoteAction The parent Quote Action builder.
     * @return This builder instance.
     */
    public adb_QuoteLineItem quoteAction(adb_QuoteAction quoteAction) {
        setParent(QuoteLineItem.QuoteActionId, quoteAction);
        return this;
    }

    /**
     * @description Sets Quantity.
     * @param value The quantity value.
     * @return This builder instance.
     */
    public adb_QuoteLineItem quantity(Decimal value) {
        return (adb_QuoteLineItem) set(QuoteLineItem.Quantity, value);
    }

    /**
     * @description Sets UnitPrice.
     * @param value The unit price value.
     * @return This builder instance.
     */
    public adb_QuoteLineItem unitPrice(Decimal value) {
        return (adb_QuoteLineItem) set(QuoteLineItem.UnitPrice, value);
    }
}