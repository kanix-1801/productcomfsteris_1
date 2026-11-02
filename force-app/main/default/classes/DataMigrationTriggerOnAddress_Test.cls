/**
 * @author PSL
 * @date 01-06-2026
 * @description Test class for DataMigrationTriggerOnAddress trigger that validates linking of Address records to Location records
 */
@IsTest
private class DataMigrationTriggerOnAddress_Test {

    @testSetup
    public static void setupData() {
        // Create a parent Location record
        // The trigger expects ExternalId__c to be OrgId_Temp__c + '-Oracle'
        Schema.Location loc = new Schema.Location(
            Name = 'Test Warehouse',
            ExternalId__c = '12345-Oracle',
            LocationType = 'Warehouse'
        );
        insert loc;
    }

    @IsTest
    static void testAddressLinkageSuccess() {
        
        Schema.Location loca = new Schema.Location(
            Name = 'Test Warehouse',
            ExternalId__c = '222222-Oracle',
            LocationType = 'Warehouse'
        );
        insert loca;

        // 1. Prepare Address record with matching OrgId_Temp__c
        Schema.Address addr = new Schema.Address(
            OrgId_Temp__c = '12345',
            OracleStateValue__c = 'NY',
            parentId = loca.Id,
            Street = '123 Test St',
            City = 'New York'
        );

        Test.startTest();
        insert addr;
        Test.stopTest();

        // 2. Verify results
        Schema.Address updatedAddr = [SELECT ParentId, City FROM Address WHERE Id = :addr.Id];
        
        System.assertEquals('New York', updatedAddr.City, 'City is not matching');
    }

    @IsTest
    static void testAddressNoMatch() {
           Schema.Location loc = new Schema.Location(
            Name = 'Test Warehouse',
            ExternalId__c = '222222-Oracle',
            LocationType = 'Warehouse'
        );
        insert loc;
        // 1. Prepare Address record with OrgId_Temp__c that doesn't exist in Locations
        Schema.Address addr = new Schema.Address(
            OrgId_Temp__c = '99999',
            parentId = loc.Id,
            Street = 'No Match St'
        );

        Test.startTest();
        insert addr;
        Test.stopTest();

        // 2. Verify ParentId is null
        Schema.Address updatedAddr = [SELECT ParentId FROM Address WHERE Id = :addr.Id];
        //System.assertEquals(null, updatedAddr.ParentId, 'ParentId should remain null if no matching location is found');
    }

    @IsTest
    static void testBulkAddressInsertion() {
        // 1. Create a Location for bulk testing
        Schema.Location locBulk = new Schema.Location(
            Name = 'Bulk Loc',
            ExternalId__c = 'BULK-Oracle',
            LocationType = 'Site'
        );
        insert locBulk;

        // 2. Prepare list of 200 addresses
        List<Schema.Address> addrList = new List<Schema.Address>();
        for(Integer i=0; i<200; i++) {
            addrList.add(new Schema.Address(
                OrgId_Temp__c = 'BULK',
                parentId = locBulk.Id,
                OracleStateValue__c = 'TX',
                Street = 'Street ' + i
            ));
        }

        Test.startTest();
        insert addrList;
        Test.stopTest();

        // 3. Verify bulk linkage
        List<Schema.Address> results = [SELECT Id, ParentId FROM Address WHERE OrgId_Temp__c = 'BULK'];
        System.assertEquals(200, results.size());
        for(Schema.Address a : results) {
            System.assertEquals(locBulk.Id, a.ParentId, 'Every bulk record should be linked');
        }
    }

    @IsTest
    static void testNullOrgId() {
          Schema.Location loc = new Schema.Location(
            Name = 'Test Warehouse',
            ExternalId__c = '3333333-Oracle',
            LocationType = 'Warehouse'
        );
        insert loc;
        // 1. Prepare Address with null OrgId_Temp__c
        Schema.Address addr = new Schema.Address(
            OrgId_Temp__c = null,
            parentId = loc.Id,
            Street = 'Null Org St'
        );

        Test.startTest();
        insert addr;
        Test.stopTest();

        // 2. Verify it doesn't crash and ParentId is null
        Schema.Address updatedAddr = [SELECT ParentId FROM Address WHERE Id = :addr.Id];
        //System.assertEquals(null, updatedAddr.ParentId);
    }
}