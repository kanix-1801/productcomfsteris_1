/**
 * @author PWC Developer
 * @date 2026/10/09
 *
 * @group Mock Room / ORI Request
 *
 * @description
 * GC-3483 - Covers attaching an uploaded file to a new request.
 */
@IsTest
private class MockRoomORIFileControllerTest {

    @IsTest
    static void linkFiles_addsTheFileToTheRequest() {
        Account testAccount = new Account(Name = 'GC-3483 File Account', SourceSystemID__c = 'GC3483-FILE-001');
        insert testAccount;
        Contact testContact = new Contact(LastName = 'GC-3483 File Contact', AccountId = testAccount.Id);
        insert testContact;
        Opportunity capitalOpportunity = new Opportunity(
            Name = 'GC-3483 File Opportunity',
            AccountId = testAccount.Id,
            RecordTypeId = Schema.SObjectType.Opportunity.getRecordTypeInfosByDeveloperName()
                .get('Healthcare_Sales').getRecordTypeId(),
            StageName = 'Discovery',
            ForecastConfidenceLevel__c = 'Pipeline',
            Type = 'New Business',
            Amount = 1000,
            Probability = 10,
            PrimaryContact__c = testContact.Id,
            CloseDate = Date.today().addDays(30)
        );
        insert capitalOpportunity;
        MockRoomOrORIRequest__c requestRecord = new MockRoomOrORIRequest__c(
            Opportunity__c = capitalOpportunity.Id,
            Account__c = testAccount.Id,
            RecordTypeId = Schema.SObjectType.MockRoomOrORIRequest__c.getRecordTypeInfosByDeveloperName()
                .get('MockRoom').getRecordTypeId(),
            Status__c = 'Draft'
        );
        insert requestRecord;

        ContentVersion version = new ContentVersion(
            Title = 'Intake Photo',
            PathOnClient = 'IntakePhoto.txt',
            VersionData = Blob.valueOf('photo')
        );
        insert version;
        version = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :version.Id];

        MockRoomORIFileController.FileLinkRequest linkRequest = new MockRoomORIFileController.FileLinkRequest();
        linkRequest.requestId = requestRecord.Id;
        linkRequest.documentIds = version.ContentDocumentId;

        Test.startTest();
        MockRoomORIFileController.linkFiles(new List<MockRoomORIFileController.FileLinkRequest>{ linkRequest });
        Test.stopTest();

        System.assertEquals(
            1,
            [SELECT COUNT() FROM ContentDocumentLink WHERE LinkedEntityId = :requestRecord.Id]
        );

        linkRequest.documentIds = '069000000000001AAA';
        try {
            MockRoomORIFileController.linkFiles(new List<MockRoomORIFileController.FileLinkRequest>{ linkRequest });
            System.assert(false, 'A missing file should be reported.');
        } catch (AuraHandledException expectedError) {
            System.assertNotEquals(null, expectedError.getMessage());
        }
    }
}