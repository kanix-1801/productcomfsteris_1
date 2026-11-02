/**
 * @description Selector for AssetAction (GW-5302). Queries are built by callers
 *              through SoqlQueryBuilder; this class only binds the object name.
 * @group GW-5302
 */
public with sharing class AssetActionsSelector extends SoqlQueryBuilder {
    /**
     * @description GW-5302 - Creates a selector for AssetAction.
     */
    public AssetActionsSelector() {
        super('AssetAction');
    }
}