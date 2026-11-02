/**
 * GW-5231 Service Team service operations for Repair Coordinator Actions.
 *
 * @author Uptima
 * @date 2026-09-21
 * @group Services
 * @description Service-layer entry point for Service Team lookups.
 */
public inherited sharing class ServiceTeamsService {
    /**
     * @description GW-5231 - Resolves Service Teams by Salesforce Id or exact Name.
     * @param serviceTeamInput Service Team Id or Name
     * @return Matching Service Teams, including duplicate-name records
     */
    public static List<ServiceTeam__c> getServiceTeamsByIdOrName(String serviceTeamInput) {
        return ServiceTeamsSelector.selectByIdOrName(serviceTeamInput);
    }

    /**
     * @description GW-5231 - Resolves Service Teams by Id or exact Name at one Repair Center.
     * @param serviceTeamInput Service Team Id or Name
     * @param locationId Repair Center Location Id
     * @return Matching Service Teams at that Repair Center
     */
    public static List<ServiceTeam__c> getServiceTeamsByIdOrNameAtLocation(
        String serviceTeamInput,
        Id locationId
    ) {
        return ServiceTeamsSelector.selectByIdOrNameAtLocation(serviceTeamInput, locationId);
    }

    /**
     * @description GW-4621 - Returns active Service Teams at a Repair Center.
     * @param locationId Repair Center Location Id
     * @return Active Service Teams at that Location, ordered by Name
     */
    public static List<ServiceTeam__c> getActiveServiceTeamsByLocationId(Id locationId) {
        return ServiceTeamsSelector.selectActiveByLocationId(locationId);
    }
}