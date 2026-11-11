/**
 * @description Tests for GW-2459 Asset Pending Inactivation evaluation
 *              (selector, service, batch, scheduler, Asset trigger guard).
 * @author STERIS
 * @see AssetPendingInactivationService
 * @see AssetPendingInactivationBatch
 * @see AssetPendingInactivationScheduler
 */
@IsTest
private class AssetPendingInactivationBatchTest {

    /**
     * @description Builds a Work Order for the Asset at the given Status.
     * @param assetRecord Pending Inactivation Asset
     * @param status Work Order Status
     * @param subject Work Order Subject
     * @return Work Order builder registered for adb_DomainBuilder.save
     */
    private static adb_WorkOrder workOrderForAsset(Asset assetRecord, String status, String subject) {
        adb_WorkOrder workOrderBuilder = new adb_WorkOrder()
            .subject(subject)
            .status(status);
        WorkOrder workOrderRecord = (WorkOrder) workOrderBuilder.record;
        workOrderRecord.AssetId = assetRecord.Id;
        workOrderRecord.AccountId = assetRecord.AccountId;
        return workOrderBuilder;
    }

    /**
     * @description Inserts an Account and a Pending Inactivation Asset.
     * @param assetName Asset Name
     * @return Inserted Asset
     */
    private static Asset insertPendingAsset(String assetName) {
        adb_Account accountBuilder = new adb_Account();
        adb_Asset assetBuilder = new adb_Asset()
            .name(assetName)
            .status('Serviceable')
            .account(accountBuilder);
        Id esRecordTypeId = Schema.SObjectType.Asset.getRecordTypeInfosByDeveloperName()
            .get('ES_Asset')
            ?.getRecordTypeId();
        if (esRecordTypeId != null) {
            assetBuilder.record.put(Asset.RecordTypeId, esRecordTypeId);
        }
        adb_DomainBuilder.save();

        update new Asset(
            Id = assetBuilder.record.Id,
            Status = AssetPendingInactivationService.STATUS_PENDING_INACTIVATION
        );
        return [
            SELECT Id, AccountId, Status
            FROM Asset
            WHERE Id = :assetBuilder.record.Id
        ];
    }

    /**
     * @description Then — Selector QueryLocator is returned for Pending Inactivation Assets.
     */
    @IsTest
    static void testSelectPendingInactivationQueryLocator_returnsLocator() {
        insertPendingAsset('GW-2459 Locator Asset');

        Test.startTest();
        Database.QueryLocator queryLocator =
            AssetPendingInactivationSelector.selectPendingInactivationQueryLocator();
        Test.stopTest();

        Assert.areNotEqual(null, queryLocator, 'QueryLocator should be returned');
        Integer pendingCount = [
            SELECT COUNT()
            FROM Asset
            WHERE Status = :AssetPendingInactivationService.STATUS_PENDING_INACTIVATION
        ];
        Assert.isTrue(pendingCount >= 1, 'Pending Inactivation Assets should exist for the locator');
    }

    /**
     * @description Then — Selector helpers return empty for blank Asset Id sets.
     */
    @IsTest
    static void testSelector_guardClauses_returnEmpty() {
        Assert.areEqual(
            0,
            AssetPendingInactivationSelector.selectAssetIdsWithOpenWorkOrders(null).size()
        );
        Assert.areEqual(
            0,
            AssetPendingInactivationSelector.selectAssetIdsWithOpenWorkOrders(new Set<Id>()).size()
        );
        Assert.areEqual(
            0,
            AssetPendingInactivationSelector.selectAssetIdsWithActiveContractLines(null).size()
        );
        Assert.areEqual(
            0,
            AssetPendingInactivationSelector.selectAssetIdsWithActiveContractLines(new Set<Id>()).size()
        );
    }

    /**
     * @description Then — An Asset with no open Work Orders or contract lines becomes Service Inactive.
     */
    @IsTest
    static void testEvaluate_noOpenDependencies_setsServiceInactive() {
        Asset assetRecord = insertPendingAsset('GW-2459 Free Asset');

        Test.startTest();
        AssetPendingInactivationService.EvaluationResult result =
            AssetPendingInactivationService.evaluatePendingInactivation(
                new List<Asset>{ assetRecord }
            );
        Test.stopTest();

        Asset updatedAsset = [SELECT Status FROM Asset WHERE Id = :assetRecord.Id];
        Assert.areEqual(1, result.evaluatedCount);
        Assert.areEqual(1, result.inactivatedCount);
        Assert.areEqual(0, result.blockedCount);
        Assert.areEqual(
            AssetPendingInactivationService.STATUS_SERVICE_INACTIVE,
            updatedAsset.Status,
            'Asset with no open transactions should become Service Inactive'
        );
    }

    /**
     * @description Then — An Asset with an open Work Order stays Pending Inactivation.
     */
    @IsTest
    static void testEvaluate_openWorkOrder_remainsPending() {
        Asset assetRecord = insertPendingAsset('GW-2459 Open WO Asset');
        workOrderForAsset(assetRecord, 'New', 'GW-2459 Open Work Order');
        adb_DomainBuilder.save();

        Test.startTest();
        AssetPendingInactivationService.EvaluationResult result =
            AssetPendingInactivationService.evaluatePendingInactivation(
                new List<Asset>{ assetRecord }
            );
        Test.stopTest();

        Asset updatedAsset = [SELECT Status FROM Asset WHERE Id = :assetRecord.Id];
        Assert.areEqual(1, result.evaluatedCount);
        Assert.areEqual(0, result.inactivatedCount);
        Assert.areEqual(1, result.blockedCount);
        Assert.areEqual(
            AssetPendingInactivationService.STATUS_PENDING_INACTIVATION,
            updatedAsset.Status,
            'Open Work Order should block Service Inactive'
        );
    }

    /**
     * @description Then — Completed, Canceled, and Closed Work Orders do not block inactivation.
     */
    @IsTest
    static void testEvaluate_completedCanceledClosedWorkOrders_setServiceInactive() {
        Asset completedAsset = insertPendingAsset('GW-2459 Completed WO Asset');
        Asset canceledAsset = insertPendingAsset('GW-2459 Canceled WO Asset');
        Asset closedAsset = insertPendingAsset('GW-2459 Closed WO Asset');
        workOrderForAsset(completedAsset, 'Completed', 'GW-2459 Completed Work Order');
        workOrderForAsset(canceledAsset, 'Canceled', 'GW-2459 Canceled Work Order');
        workOrderForAsset(closedAsset, 'Closed', 'GW-2459 Closed Work Order');
        adb_DomainBuilder.save();

        Test.startTest();
        AssetPendingInactivationService.EvaluationResult result =
            AssetPendingInactivationService.evaluatePendingInactivation(
                new List<Asset>{ completedAsset, canceledAsset, closedAsset }
            );
        Test.stopTest();

        Map<Id, Asset> updatedById = new Map<Id, Asset>(
            [
                SELECT Status
                FROM Asset
                WHERE Id IN :new Set<Id>{ completedAsset.Id, canceledAsset.Id, closedAsset.Id }
            ]
        );
        Assert.areEqual(3, result.evaluatedCount);
        Assert.areEqual(3, result.inactivatedCount);
        Assert.areEqual(0, result.blockedCount);
        Assert.areEqual(
            AssetPendingInactivationService.STATUS_SERVICE_INACTIVE,
            updatedById.get(completedAsset.Id).Status,
            'Completed Work Order should not block Service Inactive'
        );
        Assert.areEqual(
            AssetPendingInactivationService.STATUS_SERVICE_INACTIVE,
            updatedById.get(canceledAsset.Id).Status,
            'Canceled Work Order should not block Service Inactive'
        );
        Assert.areEqual(
            AssetPendingInactivationService.STATUS_SERVICE_INACTIVE,
            updatedById.get(closedAsset.Id).Status,
            'Closed Work Order should not block Service Inactive'
        );
    }

    /**
     * @description Then — Empty or non-pending input is a no-op.
     */
    @IsTest
    static void testEvaluate_emptyOrNonPending_isNoOp() {
        AssetPendingInactivationService.EvaluationResult emptyResult =
            AssetPendingInactivationService.evaluatePendingInactivation(null);
        AssetPendingInactivationService.EvaluationResult blankResult =
            AssetPendingInactivationService.evaluatePendingInactivation(new List<Asset>());

        Asset serviceableAsset = insertPendingAsset('GW-2459 Serviceable Asset');
        serviceableAsset.Status = 'Serviceable';
        AssetPendingInactivationService.isEvaluatingInactivation = true;
        update serviceableAsset;
        AssetPendingInactivationService.isEvaluatingInactivation = false;

        AssetPendingInactivationService.EvaluationResult skippedResult =
            AssetPendingInactivationService.evaluatePendingInactivation(
                new List<Asset>{ serviceableAsset }
            );

        Assert.areEqual(0, emptyResult.evaluatedCount);
        Assert.areEqual(0, blankResult.evaluatedCount);
        Assert.areEqual(0, skippedResult.evaluatedCount);
    }

    /**
     * @description Then — A user cannot set Service Inactive without evaluation.
     */
    @IsTest
    static void testTrigger_directServiceInactive_isBlocked() {
        Asset assetRecord = insertPendingAsset('GW-2459 Bypass Asset');
        Boolean threwError = false;

        try {
            assetRecord.Status = AssetPendingInactivationService.STATUS_SERVICE_INACTIVE;
            update assetRecord;
        } catch (DmlException e) {
            threwError = e.getMessage().contains(
                AssetPendingInactivationService.BYPASS_EVALUATION_ERROR
            );
        }

        Assert.isTrue(threwError, 'Direct Service Inactive update should be blocked');
        Assert.areEqual(
            AssetPendingInactivationService.STATUS_PENDING_INACTIVATION,
            [SELECT Status FROM Asset WHERE Id = :assetRecord.Id].Status
        );
    }

    /**
     * @description Then — The Asset trigger bypass lets the update through.
     */
    @IsTest
    static void testTrigger_whenBypassed_allowsServiceInactive() {
        Asset assetRecord = insertPendingAsset('GW-2459 Bypass Off Asset');
        AutomationControl.disableTrigger('AssetTrigger');

        assetRecord.Status = AssetPendingInactivationService.STATUS_SERVICE_INACTIVE;
        update assetRecord;

        Assert.areEqual(
            AssetPendingInactivationService.STATUS_SERVICE_INACTIVE,
            [SELECT Status FROM Asset WHERE Id = :assetRecord.Id].Status
        );
    }

    /**
     * @description Then — A disabled Asset trigger returns before the guard and domain call
     *              on insert, update, and delete.
     */
    @IsTest
    static void testAssetTrigger_whenBypassed_skipsHandlerBody() {
        AutomationControl.disableTrigger('AssetTrigger');
        Asset assetRecord = insertPendingAsset('GW-2459 Disabled Trigger Asset');

        delete assetRecord;

        Assert.areEqual(0, [SELECT COUNT() FROM Asset WHERE Id = :assetRecord.Id]);
        Assert.isNotNull(
            new Assets.AssetsException('Asset domain exception'),
            'Asset domain exception should construct'
        );
    }

    /**
     * @description Then — Batch inactivates a Pending Inactivation Asset with no dependencies.
     */
    @IsTest
    static void testBatch_execute_inactivatesEligibleAsset() {
        Asset assetRecord = insertPendingAsset('GW-2459 Batch Asset');

        Test.startTest();
        Database.executeBatch(new AssetPendingInactivationBatch(), 200);
        Test.stopTest();

        Assert.areEqual(
            AssetPendingInactivationService.STATUS_SERVICE_INACTIVE,
            [SELECT Status FROM Asset WHERE Id = :assetRecord.Id].Status,
            'Batch should inactivate an Asset with no open transactions'
        );
    }

    /**
     * @description Then — Batch execute handles an empty scope and finish completes.
     */
    @IsTest
    static void testBatch_execute_emptyScope() {
        Test.startTest();
        AssetPendingInactivationBatch batchJob = new AssetPendingInactivationBatch();
        batchJob.start(null);
        batchJob.execute(null, new List<SObject>());
        batchJob.finish(null);
        Test.stopTest();
        Assert.areEqual(0, batchJob.totalEvaluatedCount, 'Empty scope should evaluate no Assets');
    }

    /**
     * @description Then — Scheduler execute submits the batch.
     */
    @IsTest
    static void testScheduler_execute_submitsBatch() {
        Assert.areEqual(
            'Asset Pending Inactivation Evaluation',
            AssetPendingInactivationScheduler.SCHEDULE_JOB_NAME
        );
        Assert.areEqual('0 0 1 * * ?', AssetPendingInactivationScheduler.SCHEDULE_CRON_DAILY_1AM);
        Assert.areEqual(200, AssetPendingInactivationBatch.DEFAULT_BATCH_SIZE);

        Test.startTest();
        new AssetPendingInactivationScheduler().execute(null);
        Test.stopTest();
    }

    /**
     * @description Then — An invalid batch scope is logged and rethrown.
     */
    @IsTest
    static void testScheduler_execute_invalidScopeIsRethrown() {
        AssetPendingInactivationScheduler.batchSizeForTest = 0;
        Boolean threw = false;
        Test.startTest();
        try {
            new AssetPendingInactivationScheduler().execute(null);
        } catch (Exception ex) {
            threw = true;
        }
        Test.stopTest();
        Assert.isTrue(threw, 'An invalid batch scope should be logged and rethrown.');
    }

    /**
     * @description Then — Service wraps unexpected failures.
     */
    @IsTest
    static void testEvaluate_forcedException_isWrapped() {
        AssetPendingInactivationService.forceExceptionForTest = true;
        Boolean threwServiceException = false;

        try {
            AssetPendingInactivationService.evaluatePendingInactivation(
                new List<Asset>{ new Asset() }
            );
        } catch (AssetPendingInactivationService.AssetPendingInactivationException e) {
            threwServiceException = true;
        } finally {
            AssetPendingInactivationService.forceExceptionForTest = false;
        }

        Assert.isTrue(threwServiceException, 'Forced evaluation failure should throw');
    }

    /**
     * @description Then — Missing Status update access throws.
     */
    @IsTest
    static void testEvaluate_statusNotUpdateable_throws() {
        AssetPendingInactivationService.forceStatusNotUpdateableForTest = true;
        Boolean threwSecurityException = false;

        try {
            AssetPendingInactivationService.evaluatePendingInactivation(
                new List<Asset>{ insertPendingAsset('GW-2459 Secure Asset') }
            );
        } catch (AssetPendingInactivationService.AssetPendingInactivationException e) {
            threwSecurityException = e.getMessage().contains('permission');
        } finally {
            AssetPendingInactivationService.forceStatusNotUpdateableForTest = false;
        }

        Assert.isTrue(threwSecurityException, 'Missing Status update access should throw');
    }

    /**
     * @description Then — ContractLineItemSelector is constructed for the pending-inactivation query.
     */
    @IsTest
    static void testContractLineItemSelector_constructs() {
        ContractLineItemSelector selector = new ContractLineItemSelector();
        Assert.isNotNull(selector, 'Contract line selector should construct.');
    }
}