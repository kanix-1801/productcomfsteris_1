/**
 * @description Selector for AssetActionSource (GW-5302). Queries are built by callers
 *              through SoqlQueryBuilder; this class only binds the object name.
 * @group GW-5302
 */
public with sharing class AssetActionSourcesSelector extends SoqlQueryBuilder {
    /**
     * @description GW-5302 - Creates a selector for AssetActionSource.
     */
    public AssetActionSourcesSelector() {
        super('AssetActionSource');
    }
}