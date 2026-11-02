/**
 * GW-5231 Service Team data access for Repair Coordinator Actions.
 *
 * @author Uptima
 * @date 2026-09-21
 * @group Selectors
 * @description Selector for ServiceTeam__c records used by Repair Coordinator Actions.
 */
public inherited sharing class ServiceTeamsSelector {
    /**
     * @description GW-5231 - Selects Service Teams by Salesforce Id or exact Name.
     * @param serviceTeamInput Service Team Id or Name
     * @return Matching Service Teams, including duplicate-name records
     */
    public static List<ServiceTeam__c> selectByIdOrName(String serviceTeamInput) {
        if (String.isBlank(serviceTeamInput)) {
            return new List<ServiceTeam__c>();
        }

        String trimmedInput = serviceTeamInput.trim();
        if (PlatformUtilities.isSalesforceId(trimmedInput)) {
            Id candidateId = Id.valueOf(trimmedInput);
            if (candidateId.getSObjectType() != ServiceTeam__c.SObjectType) {
                return new List<ServiceTeam__c>();
            }
            return [
                SELECT Id, Name, Location__c
                FROM ServiceTeam__c
                WHERE Id = :candidateId
                WITH SYSTEM_MODE
            ];
        }

        return [
            SELECT Id, Name, Location__c
            FROM ServiceTeam__c
            WHERE Name = :trimmedInput
            WITH SYSTEM_MODE
            ORDER BY Location__c, Id
            LIMIT 20
        ];
    }

    /**
     * @description GW-5231 - Selects Service Teams by Id or exact Name at one Repair Center.
     * @param serviceTeamInput Service Team Id or Name
     * @param locationId Repair Center Location Id
     * @return Matching Service Teams at that Repair Center
     */
    public static List<ServiceTeam__c> selectByIdOrNameAtLocation(
        String serviceTeamInput,
        Id locationId
    ) {
        if (String.isBlank(serviceTeamInput) || locationId == null) {
            return new List<ServiceTeam__c>();
        }

        String trimmedInput = serviceTeamInput.trim();
        if (PlatformUtilities.isSalesforceId(trimmedInput)) {
            Id candidateId = Id.valueOf(trimmedInput);
            if (candidateId.getSObjectType() != ServiceTeam__c.SObjectType) {
                return new List<ServiceTeam__c>();
            }
            return [
                SELECT Id, Name, Location__c
                FROM ServiceTeam__c
                WHERE Id = :candidateId
                    AND Location__c = :locationId
                WITH SYSTEM_MODE
            ];
        }

        return [
            SELECT Id, Name, Location__c
            FROM ServiceTeam__c
            WHERE Name = :trimmedInput
                AND Location__c = :locationId
            WITH SYSTEM_MODE
            ORDER BY Id
            LIMIT 20
        ];
    }

    /**
     * @description GW-4621 - Selects active Service Teams at a Repair Center.
     * @param locationId Repair Center Location Id
     * @return Active Service Teams at that Location, ordered by Name
     */
    public static List<ServiceTeam__c> selectActiveByLocationId(Id locationId) {
        if (locationId == null) {
            return new List<ServiceTeam__c>();
        }
        return [
            SELECT Id, Name, Location__c
            FROM ServiceTeam__c
            WHERE Location__c = :locationId
                AND Status__c = 'Active'
            WITH SYSTEM_MODE
            ORDER BY Name
        ];
    }
}