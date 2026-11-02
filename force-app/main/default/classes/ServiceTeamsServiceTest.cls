/**
 * @description GW-5231 tests for ServiceTeamsService.
 */
@IsTest
private class ServiceTeamsServiceTest {
    /**
     * @description GW-5231 - Service delegates Service Team resolution to its selector.
     */
    @IsTest
    static void testGetServiceTeamsByIdOrNameExistingNameReturnsTeam() {
        ServiceTeam__c expectedTeam = new ServiceTeam__c(
            Name = 'GW5231 Service Team',
            Status__c = 'Active',
            Type__c = 'Repair Center'
        );
        insert expectedTeam;

        Test.startTest();
        List<ServiceTeam__c> results =
            ServiceTeamsService.getServiceTeamsByIdOrName(expectedTeam.Name);
        Test.stopTest();

        Assert.areEqual(1, results.size(), 'One matching team should be returned');
        Assert.areEqual(expectedTeam.Id, results[0].Id, 'The matching team should be returned');
    }

    /**
     * @description GW-5231 - Service returns an empty list for blank input.
     */
    @IsTest
    static void testGetServiceTeamsByIdOrNameBlankReturnsEmpty() {
        Test.startTest();
        List<ServiceTeam__c> results =
            ServiceTeamsService.getServiceTeamsByIdOrName(null);
        Test.stopTest();

        Assert.areEqual(0, results.size(), 'Blank input should return no teams');
    }

    /**
     * @description GW-5231 - Service returns only Service Teams at the requested Repair Center.
     */
    @IsTest
    static void testGetServiceTeamsByIdOrNameAtLocationReturnsMatchingTeam() {
        Schema.Location repairCenter = new Schema.Location(
            Name = 'GW5231 Service Repair Center',
            LocationType = 'Repair Center'
        );
        Schema.Location otherCenter = new Schema.Location(
            Name = 'GW5231 Service Other Center',
            LocationType = 'Repair Center'
        );
        insert new List<Schema.Location>{ repairCenter, otherCenter };
        ServiceTeam__c expectedTeam = new ServiceTeam__c(
            Name = 'GW5231 Location Name Team',
            Status__c = 'Active',
            Type__c = 'Repair Center',
            Location__c = repairCenter.Id
        );
        ServiceTeam__c otherCenterTeam = new ServiceTeam__c(
            Name = 'GW5231 Location Name Team',
            Status__c = 'Active',
            Type__c = 'Repair Center',
            Location__c = otherCenter.Id
        );
        insert new List<ServiceTeam__c>{ expectedTeam, otherCenterTeam };

        Test.startTest();
        List<ServiceTeam__c> results =
            ServiceTeamsService.getServiceTeamsByIdOrNameAtLocation(
                expectedTeam.Name,
                repairCenter.Id
            );
        Test.stopTest();

        Assert.areEqual(1, results.size(), 'Only the Repair Center team should be returned');
        Assert.areEqual(expectedTeam.Id, results[0].Id, 'The matching team should be returned');
    }

    /**
     * @description GW-4621 - Service returns active Service Teams for a Repair Center.
     */
    @IsTest
    static void testGetActiveServiceTeamsByLocationIdReturnsTeam() {
        Schema.Location repairCenter = new Schema.Location(
            Name = 'GW4621 Service Center',
            LocationType = 'Repair Center'
        );
        insert repairCenter;
        ServiceTeam__c expectedTeam = new ServiceTeam__c(
            Name = 'GW4621 Location Team',
            Status__c = 'Active',
            Type__c = 'Repair Center',
            Location__c = repairCenter.Id
        );
        insert expectedTeam;

        Test.startTest();
        List<ServiceTeam__c> results =
            ServiceTeamsService.getActiveServiceTeamsByLocationId(repairCenter.Id);
        Test.stopTest();

        Assert.areEqual(1, results.size(), 'The Repair Center team should be returned');
        Assert.areEqual(expectedTeam.Id, results[0].Id, 'The matching team should be returned');
    }
}