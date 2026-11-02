@IsTest
public class GpoAffiliationsControllerTest {
@IsTest
static void testGetGpoAffiliationsSuccess() {
    Account accountRecord = new Account(
        Name = 'Test GPO Affiliation Account',
        SourceSystemID__c = 'TestSuccess12'
    );
    insert accountRecord;

    GpoAffiliationsSelector.testAccountAccountRelations =
        new List<AccountAccountRelation>{
            new AccountAccountRelation(
                RelatedAccountId = accountRecord.Id,
                Status__c = 'Active',
                StartDate = Date.today(),
                EndDate = Date.today().addYears(1),
                ContractType__c = 'GPO',
                Account = new Account(Name = 'Test Contract Account')
            )
        };

    Test.startTest();
    List<GpoAffiliationDTO> resultList =
        GpoAffiliationsController.getGpoAffiliations(accountRecord.Id);
    Test.stopTest();

    System.assertEquals(1, resultList.size(), 'Expected one GPO Affiliation.');
}

    @IsTest
    static void testGetGpoAffiliationsNoRecords() {
        Account accountRecord = new Account(
            Name = 'No GPO Affiliations Test Account',
            SourceSystemID__c = 'Test12'
        );
        insert accountRecord;

        GpoAffiliationsSelector.testAccountAccountRelations =
            new List<AccountAccountRelation>();

        Test.startTest();
        List<GpoAffiliationDTO> resultList =
            GpoAffiliationsController.getGpoAffiliations(accountRecord.Id);
        Test.stopTest();

        System.assertEquals(0, resultList.size());
    }

    @IsTest
    static void testGetGpoAffiliationsNullAccountId() {
        Test.startTest();
        List<GpoAffiliationDTO> resultList =
            GpoAffiliationsController.getGpoAffiliations(null);
        Test.stopTest();

        System.assertEquals(0, resultList.size());
    }

    @IsTest
    static void testGetGpoAffiliationsException() {
        Account accountRecord = new Account(
            Name = 'GPO Exception Test Account',
            SourceSystemID__c = 'TestException12'
        );
        insert accountRecord;

        Test.startTest();

        try {
            GpoAffiliationsService.throwExceptionForTest = true;

            GpoAffiliationsController.getGpoAffiliations(accountRecord.Id);

            System.assert(false, 'Expected GpoAffiliationsException to be thrown.');
        } catch (GpoAffiliationsService.GpoAffiliationsException exceptionRecord) {
            System.assertEquals(
                'Unable to load GPO Affiliations.',
                exceptionRecord.getMessage()
            );
        } finally {
            GpoAffiliationsService.throwExceptionForTest = false;
        }

        Test.stopTest();
    }
    @IsTest
    static void testSelectorNoRecords() {
    Account accountRecord = new Account(
        Name = 'Selector No Records Test Account',
        SourceSystemID__c = 'SelectorNoRecords12'
    );
    insert accountRecord;

    GpoAffiliationsSelector.testAccountAccountRelations = null;

    Test.startTest();
    List<AccountAccountRelation> relationList =
        GpoAffiliationsSelector.getAccountAccountRelationsByRelatedAccountId(accountRecord.Id);
    Test.stopTest();

    System.assertEquals(0, relationList.size());
}

    @IsTest
    static void testSelectorNullAccountId() {
    GpoAffiliationsSelector.testAccountAccountRelations = null;

    Test.startTest();
    List<AccountAccountRelation> relationList =
        GpoAffiliationsSelector.getAccountAccountRelationsByRelatedAccountId(null);
    Test.stopTest();

    System.assertEquals(0, relationList.size());
}

}