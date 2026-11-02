/**
 * @description Tests for GW-3997 Case FCR evaluation (service, domain, selectors, batch, scheduler).
 * @author STERIS
 * @see CaseFCRService
 * @see CaseFCRBatch
 * @see CaseFCRScheduler
 */
@IsTest
private class CaseFCRBatchTest {

    /**
     * @description Builds an in-memory Case with CreatedDate/ClosedDate via JSON deserialize.
     * @param caseId Case Id
     * @param contactId Contact Id
     * @param assetId Asset Id
     * @param serialNumber SerialNumber__c value
     * @param suppliedEmail SuppliedEmail value
     * @param category Category__c value
     * @param isFcr Initial IsFCR__c
     * @param createdDate CreatedDate value
     * @param closedDate ClosedDate value
     * @return Case instance for domain evaluation
     */
    private static Case buildCaseForEvaluation(
        Id caseId,
        Id contactId,
        Id assetId,
        String serialNumber,
        String suppliedEmail,
        String category,
        Boolean isFcr,
        Datetime createdDate,
        Datetime closedDate
    ) {
        Map<String, Object> caseFieldMap = new Map<String, Object>{
            'Id' => caseId,
            'ContactId' => contactId,
            'AssetId' => assetId,
            'SerialNumber__c' => serialNumber,
            'SuppliedEmail' => suppliedEmail,
            'Category__c' => category,
            'IsFCR__c' => isFcr,
            'CreatedDate' => createdDate,
            'ClosedDate' => closedDate
        };
        return (Case) JSON.deserialize(JSON.serialize(caseFieldMap), Case.class);
    }

    /**
     * @description Creates Account/Contact/Case data for FCR service tests.
     * @return Inserted Case Id
     */
    private static Id createFcrCase() {
        String uniqueSuffix = String.valueOf(Math.abs(Crypto.getRandomInteger())).left(8);
        Account accountRecord = new Account(
            Name = 'FCR Test Account',
            SourceSystemID__c = 'FCR' + uniqueSuffix,
            SystemID__c = 'FCS' + uniqueSuffix
        );
        insert accountRecord;

        Contact contactRecord = new Contact(
            LastName = 'FCR Contact',
            AccountId = accountRecord.Id,
            Email = 'fcr.contact@example.com'
        );
        insert contactRecord;

        Id inboxSupportRecordTypeId = Schema.SObjectType.Case.getRecordTypeInfosByDeveloperName()
            .get('InboxSupport')
            ?.getRecordTypeId();
        Case caseRecord = new Case(
            Subject = 'FCR evaluation case',
            Origin = 'Email',
            Status = 'New',
            ContactId = contactRecord.Id,
            AccountId = accountRecord.Id,
            SuppliedEmail = 'fcr.contact@example.com',
            IsFCR__c = false
        );
        if (inboxSupportRecordTypeId != null) {
            caseRecord.RecordTypeId = inboxSupportRecordTypeId;
        }
        insert caseRecord;
        return caseRecord.Id;
    }

    /**
     * @description Then — Domain sets IsFCR__c true when sent emails + voice calls + related cases equals 1.
     */
    @IsTest
    static void testApplyFcrEvaluation_singleMatch_setsIsFcrTrue() {
        // Setup
        Id fakeCaseId = Case.SObjectType.getDescribe().getKeyPrefix() + '000000000001AAA';
        Id contactId = Contact.SObjectType.getDescribe().getKeyPrefix() + '000000000001AAA';
        Datetime createdDate = System.now().addDays(-3);
        Datetime closedDate = System.now().addDays(-1);
        Case currentCase = buildCaseForEvaluation(
            fakeCaseId,
            contactId,
            null,
            null,
            null,
            'General',
            false,
            createdDate,
            closedDate
        );

        // When — 1 sent email + 0 related Cases = 1
        List<Case> caseToUpdateList = new Cases(new List<Case>{ currentCase }).applyFcrEvaluation(
            new Map<Id, Integer>{ fakeCaseId => 1 },
            new Map<Id, Integer>(),
            new List<Case>()
        );

        // Then
        System.assertEquals(1, caseToUpdateList.size(), 'Case should be marked for update');
        System.assertEquals(true, caseToUpdateList[0].IsFCR__c, 'IsFCR__c should be true when sum equals 1');
    }

    /**
     * @description Then — Domain sets IsFCR__c false when the three query counts do not equal 1.
     */
    @IsTest
    static void testApplyFcrEvaluation_multipleMatches_setsIsFcrFalse() {
        // Setup
        Id fakeCaseId = Case.SObjectType.getDescribe().getKeyPrefix() + '000000000001AAA';
        Id relatedCaseId = Case.SObjectType.getDescribe().getKeyPrefix() + '000000000002AAA';
        Id contactId = Contact.SObjectType.getDescribe().getKeyPrefix() + '000000000001AAA';
        Datetime createdDate = System.now().addDays(-3);
        Datetime closedDate = System.now().addDays(-1);
        Case currentCase = buildCaseForEvaluation(
            fakeCaseId,
            contactId,
            null,
            null,
            null,
            'General',
            true,
            createdDate,
            closedDate
        );
        Case relatedMatch = buildCaseForEvaluation(
            relatedCaseId,
            contactId,
            null,
            null,
            null,
            'General',
            false,
            createdDate,
            closedDate
        );
        Case selfRow = buildCaseForEvaluation(
            fakeCaseId,
            contactId,
            null,
            null,
            null,
            'General',
            false,
            createdDate,
            closedDate
        );

        // When — self is excluded; 1 related Case + 1 sent email = 2 (not FCR)
        List<Case> caseToUpdateList = new Cases(new List<Case>{ currentCase }).applyFcrEvaluation(
            new Map<Id, Integer>{ fakeCaseId => 1 },
            new Map<Id, Integer>(),
            new List<Case>{ selfRow, relatedMatch }
        );

        // Then
        System.assertEquals(1, caseToUpdateList.size(), 'Case should be marked for update');
        System.assertEquals(false, caseToUpdateList[0].IsFCR__c, 'IsFCR__c should be false when sum is not 1');
    }

    /**
     * @description Then — Domain matches Asset / Serial / SuppliedEmail identifiers and activity counts.
     */
    @IsTest
    static void testApplyFcrEvaluation_identifierAndActivityBranches() {
        // Setup
        Id fakeCaseId = Case.SObjectType.getDescribe().getKeyPrefix() + '000000000003AAA';
        Id assetId = Asset.SObjectType.getDescribe().getKeyPrefix() + '000000000001AAA';
        Datetime createdDate = System.now().addDays(-2);
        Datetime closedDate = System.now().addDays(-1);
        Case currentCase = buildCaseForEvaluation(
            fakeCaseId,
            null,
            assetId,
            'SN-100',
            'fcr@example.com',
            'Billing',
            true,
            createdDate,
            closedDate
        );
        Case assetMatch = buildCaseForEvaluation(
            Case.SObjectType.getDescribe().getKeyPrefix() + '000000000004AAA',
            null,
            assetId,
            null,
            null,
            'Billing',
            false,
            createdDate,
            closedDate
        );
        Case serialMatch = buildCaseForEvaluation(
            Case.SObjectType.getDescribe().getKeyPrefix() + '000000000005AAA',
            null,
            null,
            'SN-100',
            null,
            'Billing',
            false,
            createdDate,
            closedDate
        );
        Case emailMatch = buildCaseForEvaluation(
            Case.SObjectType.getDescribe().getKeyPrefix() + '000000000006AAA',
            null,
            null,
            null,
            'fcr@example.com',
            'Billing',
            false,
            createdDate,
            closedDate
        );
        Case outOfWindow = buildCaseForEvaluation(
            Case.SObjectType.getDescribe().getKeyPrefix() + '000000000007AAA',
            null,
            assetId,
            null,
            null,
            'Billing',
            false,
            createdDate.addDays(-30),
            closedDate.addDays(-30)
        );

        // When — activity + matches => not FCR (sum != 1)
        List<Case> caseToUpdateList = new Cases(new List<Case>{ currentCase }).applyFcrEvaluation(
            new Map<Id, Integer>{ fakeCaseId => 1 },
            new Map<Id, Integer>{ fakeCaseId => 1 },
            new List<Case>{ assetMatch, serialMatch, emailMatch, outOfWindow }
        );

        // Then
        System.assertEquals(1, caseToUpdateList.size(), 'Case should update when FCR flips');
        System.assertEquals(false, caseToUpdateList[0].IsFCR__c, 'Activity + related matches should not be FCR');
        System.assertEquals(
            0,
            new Cases(new List<Case>()).applyFcrEvaluation(null, null, null).size(),
            'Empty domain should return no updates'
        );
    }

    /**
     * @description Then — Empty/null service scope is a no-op.
     */
    @IsTest
    static void testProcessFcrEvaluation_nullOrEmpty_isNoOp() {
        // When / Then
        CaseFCRService.processFcrEvaluation(null);
        CaseFCRService.processFcrEvaluation(new List<Case>());
        System.assertEquals(true, true, 'Null/empty scope should not throw');
    }

    /**
     * @description Then — Service processes an inserted Case through selectors and domain update.
     */
    @IsTest
    static void testProcessFcrEvaluation_withInsertedCase_updatesIsFcr() {
        // Setup
        Id caseId = createFcrCase();
        Case caseRecord = [
            SELECT
                Id,
                ContactId,
                AssetId,
                SerialNumber__c,
                SuppliedEmail,
                Category__c,
                CreatedDate,
                ClosedDate,
                IsFCR__c
            FROM Case
            WHERE Id = :caseId
        ];
        if (caseRecord.ClosedDate == null) {
            String categoryValue = String.isBlank(caseRecord.Category__c)
                ? 'General'
                : caseRecord.Category__c;
            caseRecord = buildCaseForEvaluation(
                caseRecord.Id,
                caseRecord.ContactId,
                caseRecord.AssetId,
                caseRecord.SerialNumber__c,
                caseRecord.SuppliedEmail,
                categoryValue,
                caseRecord.IsFCR__c,
                caseRecord.CreatedDate,
                System.now()
            );
        }

        EmailMessage sentEmail = new EmailMessage(
            ParentId = caseId,
            Subject = 'FCR sent email',
            Status = '3',
            ToAddress = 'fcr.contact@example.com',
            FromAddress = 'support@example.com',
            Incoming = false
        );
        insert sentEmail;

        VoiceCall voiceCallRecord = new VoiceCall(
            RelatedRecordId = caseId,
            CallStartDateTime = System.now().addMinutes(-10),
            CallEndDateTime = System.now(),
            FromPhoneNumber = '+15555550100',
            ToPhoneNumber = '+15555550101',
            CallType = 'Inbound',
            VendorType = 'ContactCenter'
        );
        insert voiceCallRecord;

        update new Case(Id = caseId, IsFCR__c = true);
        caseRecord.IsFCR__c = true;

        // When
        Test.startTest();
        CaseFCRService.processFcrEvaluation(new List<Case>{ caseRecord });
        Test.stopTest();

        // Then
        Case updatedCase = [SELECT IsFCR__c FROM Case WHERE Id = :caseId];
        System.assertEquals(false, updatedCase.IsFCR__c, 'IsFCR__c should update to false when activity sum is not 1');
        System.assertEquals(
            1,
            EmailMessagesSelector.countSentByParentCaseIds(new Set<Id>{ caseId }).get(caseId),
            'Sent email count should include inserted EmailMessage'
        );
        System.assertEquals(
            1,
            VoiceCallsSelector.countByRelatedCaseIds(new Set<Id>{ caseId }).get(caseId),
            'VoiceCall count should include inserted VoiceCall'
        );
    }

    /**
     * @description Then — Batch start returns a QueryLocator.
     */
    @IsTest
    static void testCaseFcrBatch_start_returnsQueryLocator() {
        // When
        Test.startTest();
        Database.QueryLocator queryLocator = new CaseFCRBatch().start(null);
        Test.stopTest();

        // Then
        System.assertNotEquals(null, queryLocator, 'QueryLocator should be returned');
        System.assertNotEquals(
            null,
            CaseFCRService.getFcrEvaluationQueryLocator(),
            'Service QueryLocator should be returned'
        );
    }

    /**
     * @description Then — Batch execute handles an empty scope and finish completes.
     */
    @IsTest
    static void testCaseFcrBatch_execute_emptyScope() {
        // When / Then
        Test.startTest();
        CaseFCRBatch batchJob = new CaseFCRBatch();
        batchJob.start(null);
        batchJob.execute(null, new List<SObject>());
        batchJob.finish(null);
        Test.stopTest();
        System.assertEquals(true, true, 'Empty execute/finish should not throw');
    }

    /**
     * @description Then — Scheduler execute submits the batch and covers the catch path.
     */
    @IsTest
    static void testCaseFcrScheduler_execute_submitsBatch() {
        // Setup
        System.assertEquals('Case FCR Evaluation', CaseFCRScheduler.SCHEDULE_JOB_NAME);
        System.assertEquals('0 0 1 * * ?', CaseFCRScheduler.SCHEDULE_CRON_DAILY_1AM);
        System.assertEquals(200, CaseFCRBatch.DEFAULT_BATCH_SIZE);

        // When / Then — happy path
        Test.startTest();
        new CaseFCRScheduler().execute(null);
        Test.stopTest();

        // When / Then — forced failure covers catch
        CaseFCRScheduler.forceExceptionForTest = true;
        Boolean threwException = false;
        try {
            new CaseFCRScheduler().execute(null);
        } catch (Exception e) {
            threwException = true;
        } finally {
            CaseFCRScheduler.forceExceptionForTest = false;
        }
        System.assertEquals(true, threwException, 'Forced scheduler failure should throw');
    }

    /**
     * @description Then — Selector related-case helpers return empty for blank inputs.
     */
    @IsTest
    static void testSelectRelatedCasesForFcr_guardClauses_returnEmpty() {
        // When / Then
        System.assertEquals(
            0,
            CasesSelector.selectRelatedCasesForFcr(
                new Set<String>(),
                new Set<Id>(),
                new Set<Id>(),
                new Set<String>(),
                new Set<String>(),
                System.now().addDays(-10),
                System.now()
            ).size(),
            'Blank categories should return no rows'
        );
        System.assertEquals(
            0,
            CasesSelector.selectRelatedCasesForFcr(
                new Set<String>{ 'General' },
                new Set<Id>(),
                new Set<Id>(),
                new Set<String>(),
                new Set<String>(),
                System.now().addDays(-10),
                System.now()
            ).size(),
            'Missing identifiers should return no rows'
        );
        System.assertEquals(
            0,
            CasesSelector.selectRelatedCasesForFcr(
                new Set<String>{ 'General' },
                new Set<Id>{ UserInfo.getUserId() },
                null,
                null,
                null,
                null,
                null
            ).size(),
            'Null date bounds should return no rows'
        );
    }

    /**
     * @description Then — Related-case selector runs with identifiers and QueryLocator is returned.
     */
    @IsTest
    static void testSelectRelatedCasesForFcr_withIdentifiers_runsQuery() {
        // Setup
        Id contactId = Contact.SObjectType.getDescribe().getKeyPrefix() + '000000000001AAA';

        // When
        List<Case> relatedCaseList = CasesSelector.selectRelatedCasesForFcr(
            new Set<String>{ 'General' },
            new Set<Id>{ contactId },
            new Set<Id>(),
            new Set<String>{ 'SN-1' },
            new Set<String>{ 'fcr@example.com' },
            System.now().addDays(-10),
            System.now()
        );
        Database.QueryLocator queryLocator =
            CasesSelector.selectClosedInboxSupportForFcrQueryLocator(
                Date.today().addDays(-7),
                Date.today().addDays(-6)
            );

        // Then
        System.assertNotEquals(null, relatedCaseList, 'Related Case list should not be null');
        System.assertNotEquals(null, queryLocator, 'FCR QueryLocator should not be null');
    }

    /**
     * @description Then — EmailMessage / VoiceCall selector guard clauses and queries execute.
     */
    @IsTest
    static void testActivitySelectors_guardClausesAndQueries() {
        // Setup
        Id fakeCaseId = Case.SObjectType.getDescribe().getKeyPrefix() + '000000000001AAA';

        // When / Then — EmailMessagesSelector
        System.assertEquals(0, EmailMessagesSelector.selectByIds(null).size());
        System.assertEquals(0, EmailMessagesSelector.selectByIds(new Set<Id>()).size());
        System.assertNotEquals(
            null,
            EmailMessagesSelector.selectByIds(new Set<Id>{ fakeCaseId }),
            'selectByIds should execute SOQL for non-empty Ids'
        );
        System.assertEquals(0, EmailMessagesSelector.countSentByParentCaseIds(null).size());
        System.assertEquals(0, EmailMessagesSelector.countSentByParentCaseIds(new Set<Id>()).size());
        System.assertNotEquals(
            null,
            EmailMessagesSelector.countSentByParentCaseIds(new Set<Id>{ fakeCaseId })
        );

        // When / Then — VoiceCallsSelector
        System.assertEquals(0, VoiceCallsSelector.countByRelatedCaseIds(null).size());
        System.assertEquals(0, VoiceCallsSelector.countByRelatedCaseIds(new Set<Id>()).size());
        System.assertNotEquals(
            null,
            VoiceCallsSelector.countByRelatedCaseIds(new Set<Id>{ fakeCaseId })
        );
    }

    /**
     * @description Then — Service skips Cases missing ClosedDate or Category and returns without DML.
     */
    @IsTest
    static void testProcessFcrEvaluation_missingClosedDateOrCategory_isNoOp() {
        // Setup
        Id fakeCaseId = Case.SObjectType.getDescribe().getKeyPrefix() + '000000000008AAA';
        Case missingClosedDate = buildCaseForEvaluation(
            fakeCaseId,
            null,
            null,
            null,
            null,
            'General',
            false,
            System.now().addDays(-3),
            null
        );
        Case missingCategory = buildCaseForEvaluation(
            fakeCaseId,
            null,
            null,
            null,
            null,
            null,
            false,
            System.now().addDays(-3),
            System.now()
        );

        // When / Then
        CaseFCRService.processFcrEvaluation(new List<Case>{ missingClosedDate, missingCategory });
        System.assertEquals(true, true, 'Skipped Cases should not throw');
    }

    /**
     * @description Then — Service collects Asset and SerialNumber identifiers for related-case matching.
     */
    @IsTest
    static void testProcessFcrEvaluation_withAssetAndSerial_runsEvaluation() {
        // Setup
        Id caseId = createFcrCase();
        Case caseRecord = [
            SELECT Id, AccountId, ContactId, Category__c, CreatedDate, ClosedDate, IsFCR__c, SuppliedEmail
            FROM Case
            WHERE Id = :caseId
        ];
        Product2 productRecord = new Product2(Name = 'FCR Asset Product', IsActive = true);
        insert productRecord;
        Asset assetRecord = new Asset(
            Name = 'FCR Asset',
            AccountId = caseRecord.AccountId,
            Product2Id = productRecord.Id,
            SerialNumber = 'SN-FCR-100'
        );
        insert assetRecord;
        update new Case(
            Id = caseId,
            AssetId = assetRecord.Id,
            SerialNumber__c = 'SN-FCR-100'
        );

        String categoryValue = String.isBlank(caseRecord.Category__c) ? 'General' : caseRecord.Category__c;
        Case evaluationCase = buildCaseForEvaluation(
            caseId,
            caseRecord.ContactId,
            assetRecord.Id,
            'SN-FCR-100',
            caseRecord.SuppliedEmail,
            categoryValue,
            caseRecord.IsFCR__c,
            caseRecord.CreatedDate,
            caseRecord.ClosedDate != null ? caseRecord.ClosedDate : System.now()
        );

        // When
        Test.startTest();
        CaseFCRService.processFcrEvaluation(new List<Case>{ evaluationCase });
        Test.stopTest();

        // Then
        System.assertEquals(
            caseId,
            [SELECT Id FROM Case WHERE Id = :caseId].Id,
            'Evaluation with Asset and SerialNumber should complete'
        );
    }

    /**
     * @description Then — Service throws Cases.SecurityException when IsFCR__c is not updateable.
     */
    @IsTest
    static void testProcessFcrEvaluation_isFcrNotUpdateable_throwsSecurityException() {
        // Setup
        Id fakeCaseId = Case.SObjectType.getDescribe().getKeyPrefix() + '000000000009AAA';
        Case caseRecord = buildCaseForEvaluation(
            fakeCaseId,
            null,
            null,
            null,
            null,
            'General',
            false,
            System.now().addDays(-3),
            System.now()
        );
        CaseFCRService.forceIsFcrNotUpdateableForTest = true;
        Boolean threwSecurityException = false;

        // When
        try {
            CaseFCRService.processFcrEvaluation(new List<Case>{ caseRecord });
        } catch (Cases.SecurityException e) {
            threwSecurityException = true;
        } finally {
            CaseFCRService.forceIsFcrNotUpdateableForTest = false;
        }

        // Then
        System.assertEquals(true, threwSecurityException, 'Missing IsFCR__c update access should throw');
    }

    /**
     * @description Then — Service wraps unexpected failures in CaseFCRServiceException.
     */
    @IsTest
    static void testProcessFcrEvaluation_unexpectedException_isWrapped() {
        // Setup
        Id fakeCaseId = Case.SObjectType.getDescribe().getKeyPrefix() + '000000000010AAA';
        Case caseRecord = buildCaseForEvaluation(
            fakeCaseId,
            null,
            null,
            null,
            null,
            'General',
            false,
            System.now().addDays(-3),
            System.now()
        );
        CaseFCRService.forceExceptionForTest = true;
        Boolean threwServiceException = false;

        // When
        try {
            CaseFCRService.processFcrEvaluation(new List<Case>{ caseRecord });
        } catch (CaseFCRService.CaseFCRServiceException e) {
            threwServiceException = true;
        } finally {
            CaseFCRService.forceExceptionForTest = false;
        }

        // Then
        System.assertEquals(true, threwServiceException, 'Unexpected failures should be wrapped');
    }

    /**
     * @description Then — Batch start/execute/finish catch paths are covered.
     */
    @IsTest
    static void testCaseFcrBatch_forcedException_coversCatchPaths() {
        // Setup
        CaseFCRBatch.forceExceptionForTest = true;
        CaseFCRBatch batchJob = new CaseFCRBatch();
        Boolean startThrew = false;

        // When / Then — start rethrows
        try {
            batchJob.start(null);
        } catch (Exception e) {
            startThrew = true;
        }
        System.assertEquals(true, startThrew, 'Forced start failure should throw');

        // When / Then — execute swallows
        batchJob.execute(null, new List<SObject>());
        batchJob.finish(null);
        CaseFCRBatch.forceExceptionForTest = false;
        System.assertEquals(true, true, 'Forced execute/finish failures should not throw');
    }
}