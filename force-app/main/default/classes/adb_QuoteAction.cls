/**
 * @description Domain Builder for the QuoteAction SObject.
 *              Provides a fluent API for creating test Quote Action records.
 */
@IsTest
public class adb_QuoteAction extends adb_DomainBuilder {
    /**
     * @description Constructs a Quote Action builder with Type Add.
     */
    public adb_QuoteAction() {
        super(QuoteAction.SObjectType);
        set(QuoteAction.Type, 'Add');
    }

    /**
     * @description Sets the related Quote lookup.
     * @param quoteRecord The parent Quote builder.
     * @return This builder instance.
     */
    public adb_QuoteAction quote(adb_Quote quoteRecord) {
        setParent(QuoteAction.QuoteId, quoteRecord);
        return this;
    }

    /**
     * @description Sets the source Asset lookup.
     * @param assetRecord The parent Asset builder.
     * @return This builder instance.
     */
    public adb_QuoteAction sourceAsset(adb_Asset assetRecord) {
        setParent(QuoteAction.SourceAssetId, assetRecord);
        return this;
    }

    /**
     * @description Sets the Quote Action Type.
     * @param value The type value.
     * @return This builder instance.
     */
    public adb_QuoteAction type(String value) {
        return (adb_QuoteAction) set(QuoteAction.Type, value);
    }
}