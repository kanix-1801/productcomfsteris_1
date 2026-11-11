/**
 * @description Tests for DepartmentsSelector.
 */
@IsTest
private class DepartmentsSelectorTest {

    @TestSetup
    static void setup() {
        new adb_Department().name('Dept Sel Alpha').persist();
        new adb_Department().name('Dept Sel Beta').persist();
    }

    @IsTest
    static void selectById_nullOrEmpty_returnsEmpty() {
        Assert.areEqual(0, DepartmentsSelector.selectById(null).size());
        Assert.areEqual(0, DepartmentsSelector.selectById(new Set<Id>()).size());
    }

    @IsTest
    static void selectById_validIds_returnsRows() {
        Department__c department = [
            SELECT Id, Name
            FROM Department__c
            WHERE Name = 'Dept Sel Alpha'
            LIMIT 1
        ];

        Test.startTest();
        List<Department__c> results = DepartmentsSelector.selectById(new Set<Id>{ department.Id });
        Test.stopTest();

        Assert.areEqual(1, results.size());
        Assert.areEqual('Dept Sel Alpha', results[0].Name);
    }

    @IsTest
    static void selectByName_nullOrEmpty_returnsEmpty() {
        Assert.areEqual(0, DepartmentsSelector.selectByName(null).size());
        Assert.areEqual(0, DepartmentsSelector.selectByName(new Set<String>()).size());
    }

    @IsTest
    static void selectByName_validNames_returnsOrderedRows() {
        Test.startTest();
        List<Department__c> results = DepartmentsSelector.selectByName(
            new Set<String>{ 'Dept Sel Beta', 'Dept Sel Alpha' }
        );
        Test.stopTest();

        Assert.areEqual(2, results.size());
        Assert.areEqual('Dept Sel Alpha', results[0].Name);
        Assert.areEqual('Dept Sel Beta', results[1].Name);
    }

    @IsTest
    static void selectNamesByIds_nullOrEmpty_returnsEmpty() {
        Assert.areEqual(0, DepartmentsSelector.selectNamesByIds(null, true).size());
        Assert.areEqual(0, DepartmentsSelector.selectNamesByIds(new Set<Id>(), false).size());
    }

    @IsTest
    static void selectNamesByIds_orderByNameTrue_returnsSorted() {
        Map<Id, Department__c> departments = new Map<Id, Department__c>(
            [SELECT Id, Name FROM Department__c WHERE Name LIKE 'Dept Sel%']
        );

        Test.startTest();
        List<Department__c> ordered =
            DepartmentsSelector.selectNamesByIds(departments.keySet(), true);
        List<Department__c> unordered =
            DepartmentsSelector.selectNamesByIds(departments.keySet(), false);
        Test.stopTest();

        Assert.areEqual(2, ordered.size());
        Assert.areEqual('Dept Sel Alpha', ordered[0].Name);
        Assert.areEqual('Dept Sel Beta', ordered[1].Name);
        Assert.areEqual(2, unordered.size());
    }
}