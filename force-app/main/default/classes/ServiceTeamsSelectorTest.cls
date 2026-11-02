/**
 * @description GW-5231 tests for ServiceTeamsSelector.
 */
@IsTest
private class ServiceTeamsSelectorTest {
    private static final String TEAM_NAME = 'GW5231 Selector Team';

    /**
     * @description GW-5231 - Creates duplicate-name Service Teams for selector tests.
     */
    @TestSetup
    static void setupData() {
        insert new List<ServiceTeam__c>{
            new ServiceTeam__c(Name = TEAM_NAME, Status__c = 'Active', Type__c = 'Repair Center'),
            new ServiceTeam__c(Name = TEAM_NAME, Status__c = 'Active', Type__c = 'Repair Center')
        };
    }

    /**
     * @description GW-5231 - Exact Name returns all duplicate-name Service Teams.
     */
    @IsTest
    static void testSelectByIdOrNameDuplicateNameReturnsAll() {
        Test.startTest();
        List<ServiceTeam__c> results = ServiceTeamsSelector.selectByIdOrName(TEAM_NAME);
        Test.stopTest();

        Assert.areEqual(2, results.size(), 'Both same-name teams should be returned');
    }

    /**
     * @description GW-5231 - Service Team Id returns only that record.
     */
    @IsTest
    static void testSelectByIdOrNameIdReturnsOne() {
        ServiceTeam__c expectedTeam = [
            SELECT Id
            FROM ServiceTeam__c
            WHERE Name = :TEAM_NAME
            LIMIT 1
        ];

        Test.startTest();
        List<ServiceTeam__c> results =
            ServiceTeamsSelector.selectByIdOrName(String.valueOf(expectedTeam.Id));
        Test.stopTest();

        Assert.areEqual(1, results.size(), 'Id lookup should return one team');
        Assert.areEqual(expectedTeam.Id, results[0].Id, 'The selected team should match');
    }

    /**
     * @description GW-5231 - Blank and wrong-object Id inputs return no Service Teams.
     */
    @IsTest
    static void testSelectByIdOrNameInvalidInputsReturnEmpty() {
        Test.startTest();
        List<ServiceTeam__c> blankResults = ServiceTeamsSelector.selectByIdOrName(' ');
        List<ServiceTeam__c> wrongTypeResults =
            ServiceTeamsSelector.selectByIdOrName(String.valueOf(UserInfo.getUserId()));
        Test.stopTest();

        Assert.areEqual(0, blankResults.size(), 'Blank input should return no records');
        Assert.areEqual(0, wrongTypeResults.size(), 'Wrong Id prefix should return no records');
    }

    /**
     * @description GW-5231 - Id or Name lookup is limited to the requested Repair Center.
     */
    @IsTest
    static void testSelectByIdOrNameAtLocationExcludesOtherCenter() {
        Schema.Location repairCenter = new Schema.Location(
            Name = 'GW5231 Selector Center',
            LocationType = 'Repair Center'
        );
        Schema.Location otherCenter = new Schema.Location(
            Name = 'GW5231 Selector Other Center',
            LocationType = 'Repair Center'
        );
        insert new List<Schema.Location>{ repairCenter, otherCenter };

        ServiceTeam__c includedTeam = new ServiceTeam__c(
            Name = 'GW5231 Center Team',
            Status__c = 'Active',
            Type__c = 'Repair Center',
            Location__c = repairCenter.Id
        );
        ServiceTeam__c otherCenterTeam = new ServiceTeam__c(
            Name = 'GW5231 Center Team',
            Status__c = 'Active',
            Type__c = 'Repair Center',
            Location__c = otherCenter.Id
        );
        insert new List<ServiceTeam__c>{ includedTeam, otherCenterTeam };

        Test.startTest();
        List<ServiceTeam__c> nameResults =
            ServiceTeamsSelector.selectByIdOrNameAtLocation(
                includedTeam.Name,
                repairCenter.Id
            );
        List<ServiceTeam__c> idResults =
            ServiceTeamsSelector.selectByIdOrNameAtLocation(
                String.valueOf(otherCenterTeam.Id),
                repairCenter.Id
            );
        List<ServiceTeam__c> blankResults =
            ServiceTeamsSelector.selectByIdOrNameAtLocation(includedTeam.Name, null);
        Test.stopTest();

        Assert.areEqual(1, nameResults.size(), 'Only the team at the Repair Center should return');
        Assert.areEqual(includedTeam.Id, nameResults[0].Id, 'The matching Service Team should return');
        Assert.areEqual(0, idResults.size(), 'A team at another Repair Center should be excluded');
        Assert.areEqual(0, blankResults.size(), 'A blank Repair Center should return no teams');
    }

    /**
     * @description GW-4621 - Active Service Teams are limited to the requested Repair Center.
     */
    @IsTest
    static void testSelectActiveByLocationIdReturnsActiveTeamsAtLocation() {
        Schema.Location repairCenter = new Schema.Location(
            Name = 'GW4621 Selector Center',
            LocationType = 'Repair Center'
        );
        Schema.Location otherCenter = new Schema.Location(
            Name = 'GW4621 Selector Other',
            LocationType = 'Repair Center'
        );
        insert new List<Schema.Location>{ repairCenter, otherCenter };

        ServiceTeam__c includedTeam = new ServiceTeam__c(
            Name = 'GW4621 Included',
            Status__c = 'Active',
            Type__c = 'Repair Center',
            Location__c = repairCenter.Id
        );
        ServiceTeam__c inactiveTeam = new ServiceTeam__c(
            Name = 'GW4621 Inactive',
            Status__c = 'Inactive',
            Type__c = 'Repair Center',
            Location__c = repairCenter.Id
        );
        ServiceTeam__c otherCenterTeam = new ServiceTeam__c(
            Name = 'GW4621 Other Center',
            Status__c = 'Active',
            Type__c = 'Repair Center',
            Location__c = otherCenter.Id
        );
        insert new List<ServiceTeam__c>{ includedTeam, inactiveTeam, otherCenterTeam };

        Test.startTest();
        List<ServiceTeam__c> results =
            ServiceTeamsSelector.selectActiveByLocationId(repairCenter.Id);
        List<ServiceTeam__c> blankResults =
            ServiceTeamsSelector.selectActiveByLocationId(null);
        Test.stopTest();

        Assert.areEqual(1, results.size(), 'Only the active team at the center should return');
        Assert.areEqual(includedTeam.Id, results[0].Id, 'The matching Service Team should return');
        Assert.areEqual(0, blankResults.size(), 'A blank Location should return no teams');
    }
}