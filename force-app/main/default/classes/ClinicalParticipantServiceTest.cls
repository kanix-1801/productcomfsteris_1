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
        ClinicalParticipantService.saveParticipants(
            new List<ClinicalParticipantService.ParticipantInput>{ inputRow }
        );
        Test.stopTest();

        ClinicalParticipant__c saved = [
            SELECT Name, Email__c
            FROM ClinicalParticipant__c
            WHERE KeyAccountProcessReview__c = :review.Id
        ];
        System.assertEquals('Ada Lovelace', saved.Name);
        System.assertEquals('Ada@example.com', saved.Email__c);
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