/**
 * @description Tests for AccountDepartmentsSelector.
 */
@IsTest
private class AccountDepartmentsSelectorTest {

    @TestSetup
    static void setup() {
        Account accountRecord = new Account(
            Name = 'AD Sel Account',
            SystemID__c = 'LEG-AD-SEL',
            SourceSystemID__c = 'TEST-ORACLE-AD-SEL',
            OrgIDs__c = '82'
        );
        insert accountRecord;

        Department__c department = new Department__c(Name = 'AD Sel Surgery');
        insert department;

        insert new AccountDepartment__c(
            Account__c = accountRecord.Id,
            Department__c = department.Id
        );
    }

    @IsTest
    static void selectById_nullOrEmpty_returnsEmpty() {
        Assert.areEqual(0, AccountDepartmentsSelector.selectById(null).size());
        Assert.areEqual(0, AccountDepartmentsSelector.selectById(new Set<Id>()).size());
    }

    @IsTest
    static void selectById_validIds_returnsRows() {
        AccountDepartment__c row = [SELECT Id FROM AccountDepartment__c LIMIT 1];

        Test.startTest();
        List<AccountDepartment__c> results =
            AccountDepartmentsSelector.selectById(new Set<Id>{ row.Id });
        Test.stopTest();

        Assert.areEqual(1, results.size());
        Assert.areEqual(row.Id, results[0].Id);
    }

    @IsTest
    static void selectByAccountId_nullOrEmpty_returnsEmpty() {
        Assert.areEqual(0, AccountDepartmentsSelector.selectByAccountId(null).size());
        Assert.areEqual(0, AccountDepartmentsSelector.selectByAccountId(new Set<Id>()).size());
    }

    @IsTest
    static void selectByAccountId_validIds_returnsRows() {
        Account accountRecord = [SELECT Id FROM Account WHERE Name = 'AD Sel Account' LIMIT 1];

        Test.startTest();
        List<AccountDepartment__c> results =
            AccountDepartmentsSelector.selectByAccountId(new Set<Id>{ accountRecord.Id });
        Test.stopTest();

        Assert.areEqual(1, results.size());
        Assert.areEqual(accountRecord.Id, results[0].Account__c);
    }

    @IsTest
    static void selectByDepartmentId_nullOrEmpty_returnsEmpty() {
        Assert.areEqual(0, AccountDepartmentsSelector.selectByDepartmentId(null).size());
        Assert.areEqual(0, AccountDepartmentsSelector.selectByDepartmentId(new Set<Id>()).size());
    }

    @IsTest
    static void selectByDepartmentId_validIds_returnsRows() {
        Department__c department = [SELECT Id FROM Department__c WHERE Name = 'AD Sel Surgery' LIMIT 1];

        Test.startTest();
        List<AccountDepartment__c> results =
            AccountDepartmentsSelector.selectByDepartmentId(new Set<Id>{ department.Id });
        Test.stopTest();

        Assert.areEqual(1, results.size());
        Assert.areEqual(department.Id, results[0].Department__c);
    }

    @IsTest
    static void selectDepartmentsForCreateReturnOrder_null_returnsEmpty() {
        Assert.areEqual(
            0,
            AccountDepartmentsSelector.selectDepartmentsForCreateReturnOrder(null).size()
        );
    }

    @IsTest
    static void selectDepartmentsForCreateReturnOrder_validAccount_returnsDepartment() {
        Account accountRecord = [SELECT Id FROM Account WHERE Name = 'AD Sel Account' LIMIT 1];

        Test.startTest();
        List<AccountDepartment__c> results =
            AccountDepartmentsSelector.selectDepartmentsForCreateReturnOrder(accountRecord.Id);
        Test.stopTest();

        Assert.areEqual(1, results.size());
        Assert.isNotNull(results[0].Department__c);
        Assert.areEqual('AD Sel Surgery', results[0].Department__r.Name);
    }

    /**
     * @description CI Auto skipped DepartmentsSelectorTest; cover DepartmentsSelector here.
     */
    @IsTest
    static void departmentsSelector_guardsAndHappyPaths_sprint93Coverage() {
        Department__c department = [SELECT Id, Name FROM Department__c WHERE Name = 'AD Sel Surgery' LIMIT 1];
        Department__c second = new Department__c(Name = 'AD Sel Endoscopy');
        insert second;

        Test.startTest();
        Assert.areEqual(0, DepartmentsSelector.selectById(null).size());
        Assert.areEqual(0, DepartmentsSelector.selectById(new Set<Id>()).size());
        Assert.areEqual(0, DepartmentsSelector.selectByName(null).size());
        Assert.areEqual(0, DepartmentsSelector.selectByName(new Set<String>()).size());
        Assert.areEqual(0, DepartmentsSelector.selectNamesByIds(null, true).size());
        Assert.areEqual(0, DepartmentsSelector.selectNamesByIds(new Set<Id>(), false).size());

        List<Department__c> byId = DepartmentsSelector.selectById(new Set<Id>{ department.Id, second.Id });
        List<Department__c> byName = DepartmentsSelector.selectByName(
            new Set<String>{ 'AD Sel Surgery', 'AD Sel Endoscopy' }
        );
        List<Department__c> ordered = DepartmentsSelector.selectNamesByIds(
            new Set<Id>{ department.Id, second.Id },
            true
        );
        List<Department__c> unordered = DepartmentsSelector.selectNamesByIds(
            new Set<Id>{ department.Id, second.Id },
            false
        );
        Test.stopTest();

        Assert.areEqual(2, byId.size());
        Assert.areEqual(2, byName.size());
        Assert.areEqual('AD Sel Endoscopy', byName[0].Name);
        Assert.areEqual('AD Sel Surgery', byName[1].Name);
        Assert.areEqual(2, ordered.size());
        Assert.areEqual('AD Sel Endoscopy', ordered[0].Name);
        Assert.areEqual(2, unordered.size());
    }
}