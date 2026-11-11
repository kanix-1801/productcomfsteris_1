/**
 * @description Tests for AccountContactRelationsSelector.
 */
@IsTest
private class AccountContactRelationsSelectorTest {

    @TestSetup
    static void setup() {
        Account accountRecord = new Account(
            Name = 'ACR Sel Account',
            SystemID__c = 'LEG-ACR-SEL',
            SourceSystemID__c = 'TEST-ORACLE-ACR-SEL',
            OrgIDs__c = '82'
        );
        insert accountRecord;

        insert new Contact(
            FirstName = 'ACR',
            LastName = 'Selector',
            AccountId = accountRecord.Id,
            Email = 'acr.selector@example.com'
        );
    }

    private static AccountContactRelation primaryRelation() {
        return [
            SELECT Id, AccountId, ContactId, IsActive
            FROM AccountContactRelation
            WHERE Account.Name = 'ACR Sel Account'
            LIMIT 1
        ];
    }

    @IsTest
    static void selectById_nullOrEmpty_returnsEmpty() {
        Assert.areEqual(0, AccountContactRelationsSelector.selectById(null).size());
        Assert.areEqual(0, AccountContactRelationsSelector.selectById(new Set<Id>()).size());
    }

    @IsTest
    static void selectById_validIds_returnsRows() {
        AccountContactRelation relation = primaryRelation();

        Test.startTest();
        List<AccountContactRelation> results =
            AccountContactRelationsSelector.selectById(new Set<Id>{ relation.Id });
        Test.stopTest();

        Assert.areEqual(1, results.size());
        Assert.areEqual(relation.Id, results[0].Id);
    }

    @IsTest
    static void selectByAccountId_nullOrEmpty_returnsEmpty() {
        Assert.areEqual(0, AccountContactRelationsSelector.selectByAccountId(null).size());
        Assert.areEqual(0, AccountContactRelationsSelector.selectByAccountId(new Set<Id>()).size());
    }

    @IsTest
    static void selectByAccountId_validIds_returnsRows() {
        AccountContactRelation relation = primaryRelation();

        Test.startTest();
        List<AccountContactRelation> results =
            AccountContactRelationsSelector.selectByAccountId(new Set<Id>{ relation.AccountId });
        Test.stopTest();

        Assert.isFalse(results.isEmpty());
        Assert.areEqual(relation.AccountId, results[0].AccountId);
    }

    @IsTest
    static void selectByContactId_nullOrEmpty_returnsEmpty() {
        Assert.areEqual(0, AccountContactRelationsSelector.selectByContactId(null).size());
        Assert.areEqual(0, AccountContactRelationsSelector.selectByContactId(new Set<Id>()).size());
    }

    @IsTest
    static void selectByContactId_validIds_returnsRows() {
        AccountContactRelation relation = primaryRelation();

        Test.startTest();
        List<AccountContactRelation> results =
            AccountContactRelationsSelector.selectByContactId(new Set<Id>{ relation.ContactId });
        Test.stopTest();

        Assert.isFalse(results.isEmpty());
        Assert.areEqual(relation.ContactId, results[0].ContactId);
    }

    @IsTest
    static void selectByAccountAndContact_nullGuards_returnEmpty() {
        AccountContactRelation relation = primaryRelation();

        Assert.areEqual(
            0,
            AccountContactRelationsSelector.selectByAccountAndContact(null, relation.ContactId)
                .size()
        );
        Assert.areEqual(
            0,
            AccountContactRelationsSelector.selectByAccountAndContact(relation.AccountId, null)
                .size()
        );
    }

    @IsTest
    static void selectByAccountAndContact_validPair_returnsRow() {
        AccountContactRelation relation = primaryRelation();

        Test.startTest();
        List<AccountContactRelation> results =
            AccountContactRelationsSelector.selectByAccountAndContact(
                relation.AccountId,
                relation.ContactId
            );
        Test.stopTest();

        Assert.areEqual(1, results.size());
        Assert.areEqual(relation.Id, results[0].Id);
    }

    @IsTest
    static void selectActiveByAccountId_null_returnsEmpty() {
        Assert.areEqual(0, AccountContactRelationsSelector.selectActiveByAccountId(null).size());
    }

    @IsTest
    static void selectActiveByAccountId_validAccount_returnsContactIds() {
        AccountContactRelation relation = primaryRelation();

        Test.startTest();
        List<AccountContactRelation> results =
            AccountContactRelationsSelector.selectActiveByAccountId(relation.AccountId);
        Test.stopTest();

        Assert.isFalse(results.isEmpty());
        Assert.areEqual(relation.ContactId, results[0].ContactId);
    }
}