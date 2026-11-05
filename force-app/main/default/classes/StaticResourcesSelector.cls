/**
 * @description Selector for StaticResource.
 *              StaticResource is not available through SoqlQueryBuilder user mode for the
 *              backoffice persona, so this query stays in system mode.
 */
public with sharing class StaticResourcesSelector {
    /**
     * @description GW-2710 - Packaged static resource body by developer name.
     * @param resourceName Static resource developer name.
     * @return Matching static resources.
     */
    public static List<StaticResource> selectByName(String resourceName) {
        if (String.isBlank(resourceName)) {
            return new List<StaticResource>();
        }
        return [
            SELECT Id, Name, Body
            FROM StaticResource
            WHERE Name = :resourceName
            LIMIT 1
        ];
    }
}