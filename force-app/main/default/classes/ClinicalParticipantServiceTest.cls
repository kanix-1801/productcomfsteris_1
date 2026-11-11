/**
 * @description GC-3542 - Covers clinical participant save from the create-flow popup.
 */
@IsTest
private class ClinicalParticipantServiceTest {
    @IsTest
    static void savesParticipantsFromJson() {
        KeyAccountProcessReview__c review = new KeyAccountProcessReview__c();
        insert review;

        ClinicalParticipantService.ParticipantInput inputRow = new ClinicalParticipantService.ParticipantInput();
        inputRow.processReviewId = review.Id;
        inputRow.participantsJson = '[{"name":"Ada Lovelace","email":"Ada@example.com"}]';

        Test.startTest();
        ClinicalParticipantService.saveForReview(review.Id, inputRow.participantsJson);
        Test.stopTest();

        ClinicalParticipant__c saved = [
            SELECT Name, Email__c, NotSalesforceUser__c
            FROM ClinicalParticipant__c
            WHERE KeyAccountProcessReview__c = :review.Id
        ];
        System.assertEquals('Ada Lovelace', saved.Name);
        System.assertEquals('Ada@example.com', saved.Email__c);
        System.assertEquals(true, saved.NotSalesforceUser__c);
    }

    @IsTest
    static void salesforceUserPopulatesNameEmailAndUser() {
        Profile standardProfile = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        User salesforceUser = new User(
            Alias = 'cpart',
            Email = 'clinical.participant@example.com',
            EmailEncodingKey = 'UTF-8',
            LastName = 'Participant',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = standardProfile.Id,
            TimeZoneSidKey = 'America/Los_Angeles',
            Username = 'clinical.participant.' + DateTime.now().getTime() + '@example.com'
        );
        insert salesforceUser;

        KeyAccountProcessReview__c review = new KeyAccountProcessReview__c();
        insert review;

        ClinicalParticipantService.ParticipantInput inputRow = new ClinicalParticipantService.ParticipantInput();
        inputRow.processReviewId = review.Id;
        inputRow.participantsJson = '[{"userId":"' + salesforceUser.Id + '","name":"","email":""}]';

        Test.startTest();
        ClinicalParticipantService.saveParticipants(
            new List<ClinicalParticipantService.ParticipantInput>{ inputRow }
        );
        Test.stopTest();

        ClinicalParticipant__c saved = [
            SELECT Name, Email__c, User__c, NotSalesforceUser__c
            FROM ClinicalParticipant__c
            WHERE KeyAccountProcessReview__c = :review.Id
        ];
        System.assertEquals(salesforceUser.Id, saved.User__c);
        System.assertEquals('Participant', saved.Name);
        System.assertEquals('clinical.participant@example.com', saved.Email__c);
        System.assertEquals(false, saved.NotSalesforceUser__c);
    }

    @IsTest
    static void blankJsonCreatesNoRows() {
        KeyAccountProcessReview__c review = new KeyAccountProcessReview__c();
        insert review;

        ClinicalParticipantService.ParticipantInput inputRow = new ClinicalParticipantService.ParticipantInput();
        inputRow.processReviewId = review.Id;
        inputRow.participantsJson = '';

        Test.startTest();
        ClinicalParticipantService.saveParticipants(
            new List<ClinicalParticipantService.ParticipantInput>{ inputRow }
        );
        Test.stopTest();

        System.assertEquals(
            0,
            [SELECT COUNT() FROM ClinicalParticipant__c WHERE KeyAccountProcessReview__c = :review.Id]
        );
    }

    @IsTest
    static void duplicateEmailIsRejected() {
        KeyAccountProcessReview__c review = new KeyAccountProcessReview__c();
        insert review;

        ClinicalParticipantService.ParticipantInput inputRow = new ClinicalParticipantService.ParticipantInput();
        inputRow.processReviewId = review.Id;
        inputRow.participantsJson = '[{"name":"Ada","email":"ada@example.com"},{"name":"Ada Two","email":"ADA@example.com"}]';

        try {
            ClinicalParticipantService.saveParticipants(
                new List<ClinicalParticipantService.ParticipantInput>{ inputRow }
            );
            System.assert(false, 'Expected the duplicate email to be rejected.');
        } catch (ClinicalParticipantService.ClinicalParticipantException ex) {
            System.assert(ex.getMessage().contains('only once'));
        }
    }

    @IsTest
    static void sameEmailIsAllowedOnAnotherReview() {
        KeyAccountProcessReview__c firstReview = new KeyAccountProcessReview__c();
        KeyAccountProcessReview__c secondReview = new KeyAccountProcessReview__c();
        insert new List<KeyAccountProcessReview__c>{ firstReview, secondReview };

        insert new ClinicalParticipant__c(
            Name = 'Ada Lovelace',
            Email__c = 'ada@example.com',
            KeyAccountProcessReview__c = firstReview.Id
        );
        insert new ClinicalParticipant__c(
            Name = 'Ada Lovelace',
            Email__c = 'ada@example.com',
            KeyAccountProcessReview__c = secondReview.Id
        );

        System.assertEquals(2, [SELECT COUNT() FROM ClinicalParticipant__c WHERE Email__c = 'ada@example.com']);
    }

    @IsTest
    static void sameEmailIsBlockedOnTheSameReview() {
        KeyAccountProcessReview__c review = new KeyAccountProcessReview__c();
        insert review;
        insert new ClinicalParticipant__c(
            Name = 'Ada Lovelace',
            Email__c = 'ada@example.com',
            KeyAccountProcessReview__c = review.Id
        );

        try {
            insert new ClinicalParticipant__c(
                Name = 'Ada Again',
                Email__c = 'ADA@example.com',
                KeyAccountProcessReview__c = review.Id
            );
            System.assert(false, 'Expected the duplicate email to be rejected.');
        } catch (DmlException ex) {
            System.assert(ex.getDmlMessage(0).contains('only once'));
        }
    }

    @IsTest
    static void returnsActiveSalesforceUser() {
        User currentUser = ClinicalParticipantService.getSalesforceUser(UserInfo.getUserId());
        System.assertEquals(UserInfo.getName(), currentUser.Name);
        System.assertEquals(null, ClinicalParticipantService.getSalesforceUser(null));
    }
}