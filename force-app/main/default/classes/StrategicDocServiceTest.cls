/**
 * @description
 * Test class for StrategicDocService.
 * File links are created with ContentVersion so StrategicDocTrigger calls the service.
 */
@IsTest
private class StrategicDocServiceTest {

    private static final String STRATEGIC_RT = 'HCSalesStrategicContract';
    private static final String OTHER_RT = 'Healthcare_Sales';

    @TestSetup
    static void setupData() {
        Account acc = new Account(Name = 'Strategic Doc Account');
        insert acc;

        Contact primaryContact = new Contact(
            LastName = 'Strategic Doc Contact',
            AccountId = acc.Id
        );
        insert primaryContact;

        Id strategicRecordTypeId = recordTypeId(STRATEGIC_RT);
        Id otherRecordTypeId = recordTypeId(OTHER_RT);

        insert new List<Opportunity>{
            buildOpportunity(
                'Strategic Doc Opp',
                acc.Id,
                primaryContact.Id,
                strategicRecordTypeId,
                'Intake',
                null
            ),
            buildOpportunity(
                'Other Doc Opp',
                acc.Id,
                primaryContact.Id,
                otherRecordTypeId,
                'Discovery',
                'Pipeline'
            )
        };
    }

    @IsTest
    static void handleAfterInsert_ignoresNullEmptyAndNonOpportunityLinks() {
        Account acc = [SELECT Id FROM Account WHERE Name = 'Strategic Doc Account'];

        Test.startTest();
        StrategicDocService.handleAfterInsert(null);
        StrategicDocService.handleAfterInsert(new List<ContentDocumentLink>());
        StrategicDocService.handleAfterInsert(new List<ContentDocumentLink>{
            new ContentDocumentLink(),
            new ContentDocumentLink(LinkedEntityId = acc.Id)
        });
        publishFile(acc.Id, 'Account File');
        Test.stopTest();

        Opportunity strategicOpp = getOpportunity('Strategic Doc Opp');
        Assert.isFalse(
            strategicOpp.HasSupportingDocumentation__c,
            'A file linked to an Account should not mark the Opportunity'
        );
    }

    @IsTest
    static void handleAfterInsert_setsFlagOnlyForStrategicOpportunity() {
        Opportunity strategicOpp = getOpportunity('Strategic Doc Opp');
        Opportunity otherOpp = getOpportunity('Other Doc Opp');

        Test.startTest();
        publishFile(strategicOpp.Id, 'Strategic Support');
        publishFile(otherOpp.Id, 'Other Support');
        Test.stopTest();

        strategicOpp = getOpportunity('Strategic Doc Opp');
        otherOpp = getOpportunity('Other Doc Opp');
        Assert.isTrue(
            strategicOpp.HasSupportingDocumentation__c,
            'A file on a Strategic Contract Opportunity should set the flag'
        );
        Assert.isFalse(
            otherOpp.HasSupportingDocumentation__c,
            'A file on another record type should leave the flag false'
        );
    }

    @IsTest
    static void handleAfterInsert_doesNotUpdateWhenFlagIsAlreadyTrue() {
        Opportunity strategicOpp = getOpportunity('Strategic Doc Opp');
        ContentDocumentLink link = publishFile(strategicOpp.Id, 'Already Linked');

        Test.startTest();
        StrategicDocService.handleAfterInsert(new List<ContentDocumentLink>{ link });
        Test.stopTest();

        strategicOpp = getOpportunity('Strategic Doc Opp');
        Assert.isTrue(
            strategicOpp.HasSupportingDocumentation__c,
            'The flag should stay true when supporting documentation already exists'
        );
    }

    @IsTest
    static void handleAfterDelete_clearsFlagWhenLastFileIsRemoved() {
        Opportunity strategicOpp = getOpportunity('Strategic Doc Opp');
        ContentDocumentLink link = publishFile(strategicOpp.Id, 'Only File');

        Test.startTest();
        delete link;
        Test.stopTest();

        strategicOpp = getOpportunity('Strategic Doc Opp');
        Assert.isFalse(
            strategicOpp.HasSupportingDocumentation__c,
            'The flag should be cleared when the last file is removed'
        );
    }

    @IsTest
    static void handleAfterDelete_keepsFlagWhenAnotherFileRemains() {
        Opportunity strategicOpp = getOpportunity('Strategic Doc Opp');
        ContentDocumentLink firstLink = publishFile(strategicOpp.Id, 'First File');
        publishFile(strategicOpp.Id, 'Second File');

        Test.startTest();
        delete firstLink;
        Test.stopTest();

        strategicOpp = getOpportunity('Strategic Doc Opp');
        Assert.isTrue(
            strategicOpp.HasSupportingDocumentation__c,
            'The flag should stay true while another file remains'
        );
    }

    @IsTest
    static void handleAfterDelete_setsFlagWhenAFileStillExists() {
        Opportunity strategicOpp = getOpportunity('Strategic Doc Opp');
        publishFile(strategicOpp.Id, 'Remaining File');
        update new Opportunity(
            Id = strategicOpp.Id,
            HasSupportingDocumentation__c = false
        );

        Test.startTest();
        StrategicDocService.handleAfterDelete(new List<ContentDocumentLink>{
            new ContentDocumentLink(LinkedEntityId = strategicOpp.Id)
        });
        Test.stopTest();

        strategicOpp = getOpportunity('Strategic Doc Opp');
        Assert.isTrue(
            strategicOpp.HasSupportingDocumentation__c,
            'The flag should be set back to true when a file is still linked'
        );
    }

    @IsTest
    static void handleAfterDelete_ignoresNullEmptyAndNonStrategicLinks() {
        Opportunity strategicOpp = getOpportunity('Strategic Doc Opp');
        Opportunity otherOpp = getOpportunity('Other Doc Opp');

        Test.startTest();
        StrategicDocService.handleAfterDelete(null);
        StrategicDocService.handleAfterDelete(new List<ContentDocumentLink>());
        StrategicDocService.handleAfterDelete(new List<ContentDocumentLink>{
            new ContentDocumentLink(),
            new ContentDocumentLink(LinkedEntityId = otherOpp.Id),
            new ContentDocumentLink(LinkedEntityId = strategicOpp.Id)
        });
        Test.stopTest();

        strategicOpp = getOpportunity('Strategic Doc Opp');
        otherOpp = getOpportunity('Other Doc Opp');
        Assert.isFalse(strategicOpp.HasSupportingDocumentation__c, 'Strategic Opportunity should stay unchanged');
        Assert.isFalse(otherOpp.HasSupportingDocumentation__c, 'Other Opportunity should stay unchanged');
    }

    private static Id recordTypeId(String developerName) {
        return Schema.SObjectType.Opportunity
            .getRecordTypeInfosByDeveloperName()
            .get(developerName)
            .getRecordTypeId();
    }

    private static Opportunity buildOpportunity(
        String name,
        Id accountId,
        Id contactId,
        Id recordTypeId,
        String stageName,
        String forecastConfidence
    ) {
        return new Opportunity(
            Name = name,
            AccountId = accountId,
            RecordTypeId = recordTypeId,
            Type = 'New Business',
            Amount = 1000,
            Probability = 10,
            PrimaryContact__c = contactId,
            StageName = stageName,
            ForecastConfidenceLevel__c = forecastConfidence,
            CloseDate = Date.today().addDays(30)
        );
    }

    private static Opportunity getOpportunity(String name) {
        return [
            SELECT Id, HasSupportingDocumentation__c
            FROM Opportunity
            WHERE Name = :name
            LIMIT 1
        ];
    }

    private static ContentDocumentLink publishFile(Id linkedEntityId, String title) {
        ContentVersion version = new ContentVersion(
            Title = title,
            PathOnClient = title + '.txt',
            VersionData = Blob.valueOf(title),
            FirstPublishLocationId = linkedEntityId
        );
        insert version;

        Id contentDocumentId = [
            SELECT ContentDocumentId
            FROM ContentVersion
            WHERE Id = :version.Id
        ].ContentDocumentId;

        return [
            SELECT Id, LinkedEntityId, ContentDocumentId
            FROM ContentDocumentLink
            WHERE ContentDocumentId = :contentDocumentId
            AND LinkedEntityId = :linkedEntityId
            LIMIT 1
        ];
    }
}