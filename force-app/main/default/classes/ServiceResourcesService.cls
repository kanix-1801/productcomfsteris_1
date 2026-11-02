/**
 * @author Uptima Development Team
 * @date 2026-09-03
 * @group Services
 * @description Service-layer entry point for ServiceResource lookups (Repair Center context).
 */
public with sharing class ServiceResourcesService {
    /**
     * @description Resolves the running user's Repair Center from their active Service Resource.
     * @return Repair Center Location Id, or null when none is configured
     */
    public static Id getRepairCenterIdForCurrentUser() {
        List<ServiceResource> resources = ServiceResourcesSelector.selectActiveWithRepairCenterByUserId(
            UserInfo.getUserId()
        );
        return resources.isEmpty() ? null : (Id) resources[0].get('RepairCenter__c');
    }

    /**
     * @description GW-4348 / GW-5996 - Resolves the running user's Repair Center name.
     * @return Repair Center Location Name, or null when none is configured
     */
    public static String getRepairCenterNameForCurrentUser() {
        List<ServiceResource> resources = ServiceResourcesSelector.selectActiveWithRepairCenterByUserId(
            UserInfo.getUserId()
        );
        if (resources.isEmpty() || resources[0].RepairCenter__r == null) {
            return null;
        }
        return resources[0].RepairCenter__r.Name;
    }
}