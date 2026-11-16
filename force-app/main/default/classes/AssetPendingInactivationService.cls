/**
 * @description GW-2459 - Evaluates Pending Inactivation Assets and sets Service Inactive
 *              only when no open Work Orders or active contract lines exist.
 * @author STERIS
 * @see AssetPendingInactivationSelector
 * @see AssetPendingInactivationBatch
 * @see AssetTriggerHandler
 */
public without sharing class AssetPendingInactivationService {

    /**
     * @description Asset Status value that queues inactivation evaluation.
     */
    public static final String STATUS_PENDING_INACTIVATION = 'Pending Inactivation';

    /**
     * @description Asset Status value set when evaluation finds no open dependencies.
     */
    public static final String STATUS_SERVICE_INACTIVE = 'Service Inactive';

    /**
     * @description Work Order statuses treated as closed even when IsClosed is false
     *              (Field Service Completed keeps IsClosed false).
     */
    public static final Set<String> CLOSED_WORK_ORDER_STATUSES = new Set<String>{
        'Completed',
        'Canceled',
        'Closed'
    };

    /**
     * @description Error when a user sets Service Inactive without evaluation.
     */
    public static final String BYPASS_EVALUATION_ERROR =
        'Service Inactive can only be set after Pending Inactivation evaluation finds no open Work Orders or active contract lines.';

    /**
     * @description Custom exception for pending inactivation operations.
     */
    public class AssetPendingInactivationException extends Exception {
    }

    /**
     * @description When true, the current transaction is the evaluation update.
     */
    @TestVisible
    private static Boolean isEvaluatingInactivation = false;

    /**
     * @description When true in tests, forces service methods onto the catch path.
     */
    @TestVisible
    private static Boolean forceExceptionForTest = false;

    /**
     * @description When true in tests, treats Asset.Status as not updateable.
     */
    @TestVisible
    private static Boolean forceStatusNotUpdateableForTest = false;

    /**
     * @description Result counters for a single evaluation chunk.
     */
    public class EvaluationResult {
        public Integer evaluatedCount = 0;
        public Integer inactivatedCount = 0;
        public Integer blockedCount = 0;
    }

    /**
     * @description Message returned to the flow when open items block inactivation.
     */
    public static final String OPEN_ITEMS_ERROR =
        'This Asset can\'t be inactivated because open work orders or active contract lines were found. It stays in Pending Inactivation.';

    /**
     * @description Flow input for inactivating one Asset.
     */
    public class InactivateRequest {
        @InvocableVariable(label='Asset Id' required=true)
        public Id assetId;

        @InvocableVariable(label='Service Reason' required=true)
        public String serviceReason;
    }

    /**
     * @description Flow output for one inactivation request.
     */
    public class InactivateResult {
        @InvocableVariable(label='Is Success')
        public Boolean isSuccess = false;

        @InvocableVariable(label='Error Message')
        public String errorMessage;
    }

    /**
     * @description GW-6918 - Called from Asset_SCR_Inactivate. Re-checks open Work Orders and
     *              active contract lines, then sets Service Inactive and Service Reason.
     *              Runs as an evaluation so preventUnevaluatedServiceInactive allows the update.
     *              Updates in system mode because the flow runs in system mode and users
     *              do not have edit access to Asset Status or Service Reason.
     * @param requestList One request per Asset
     * @return One result per request, in the same order
     */
    @InvocableMethod(
        label='Inactivate Asset'
        description='Sets Service Inactive and Service Reason when no open Work Orders or active contract lines exist.'
        category='Asset'
    )
    public static List<InactivateResult> inactivateFromFlow(List<InactivateRequest> requestList) {
        List<InactivateResult> resultList = new List<InactivateResult>();
        Set<Id> assetIdSet = new Set<Id>();
        for (InactivateRequest request : requestList) {
            InactivateResult result = new InactivateResult();
            resultList.add(result);
            if (request == null || request.assetId == null) {
                result.errorMessage = 'Asset Id is required.';
                continue;
            }
            assetIdSet.add(request.assetId);
        }
        if (assetIdSet.isEmpty()) {
            return resultList;
        }

        try {
            if (forceExceptionForTest == true) {
                throw new AssetPendingInactivationException('Forced inactivation failure for test');
            }

            Set<Id> blockedAssetIdSet = new Set<Id>();
            blockedAssetIdSet.addAll(
                AssetPendingInactivationSelector.selectAssetIdsWithOpenWorkOrders(assetIdSet)
            );
            blockedAssetIdSet.addAll(
                AssetPendingInactivationSelector.selectAssetIdsWithActiveContractLines(assetIdSet)
            );

            List<Asset> assetsToInactivate = new List<Asset>();
            List<Integer> resultIndexList = new List<Integer>();
            for (Integer index = 0; index < requestList.size(); index++) {
                InactivateRequest request = requestList[index];
                if (request == null || request.assetId == null) {
                    continue;
                }
                if (blockedAssetIdSet.contains(request.assetId)) {
                    resultList[index].errorMessage = OPEN_ITEMS_ERROR;
                    Logger.info('AssetPendingInactivationService: Asset ' + request.assetId + ' not inactivated from flow; open Work Order or active contract line found.');
                    continue;
                }
                assetsToInactivate.add(new Asset(
                    Id = request.assetId,
                    Status = STATUS_SERVICE_INACTIVE,
                    ServiceReason__c = request.serviceReason
                ));
                resultIndexList.add(index);
            }

            if (assetsToInactivate.isEmpty()) {
                return resultList;
            }

            isEvaluatingInactivation = true;
            List<Database.SaveResult> saveResultList =
                Database.update(assetsToInactivate, false, AccessLevel.SYSTEM_MODE);
            for (Integer index = 0; index < saveResultList.size(); index++) {
                Database.SaveResult saveResult = saveResultList[index];
                InactivateResult result = resultList[resultIndexList[index]];
                Id assetId = assetsToInactivate[index].Id;
                if (saveResult.isSuccess()) {
                    result.isSuccess = true;
                    Logger.info('AssetPendingInactivationService: Asset ' + assetId + ' set to ' + STATUS_SERVICE_INACTIVE + ' from flow. userId=' + UserInfo.getUserId());
                } else {
                    result.errorMessage = saveResult.getErrors()[0].getMessage();
                    Logger.error('AssetPendingInactivationService: failed to inactivate Asset ' + assetId + ' from flow: ' + result.errorMessage);
                }
            }
            return resultList;
        } catch (Exception e) {
            Logger.error('AssetPendingInactivationService.inactivateFromFlow', e);
            if (e instanceof AssetPendingInactivationException) {
                throw e;
            }
            throw new AssetPendingInactivationException(
                'An unexpected error occurred while inactivating the Asset.',
                e
            );
        } finally {
            isEvaluatingInactivation = false;
            Logger.saveLog();
        }
    }

    /**
     * @description Blocks Pending Inactivation → Service Inactive unless this service
     *              already evaluated the Asset in the current transaction.
     * @param newAssetList Trigger.new
     * @param oldAssetById Trigger.oldMap
     */
    public static void preventUnevaluatedServiceInactive(
        List<Asset> newAssetList,
        Map<Id, Asset> oldAssetById
    ) {
        if (isEvaluatingInactivation == true || newAssetList == null || oldAssetById == null) {
            return;
        }

        for (Asset newAsset : newAssetList) {
            Asset oldAsset = oldAssetById.get(newAsset.Id);
            if (oldAsset == null) {
                continue;
            }
            if (
                oldAsset.Status == STATUS_PENDING_INACTIVATION &&
                newAsset.Status == STATUS_SERVICE_INACTIVE
            ) {
                newAsset.addError(BYPASS_EVALUATION_ERROR);
            }
        }
    }

    /**
     * @description Evaluates a batch of Pending Inactivation Assets and inactivates
     *              those with no open Work Orders or active contract lines.
     * @param assetList Assets from the batch scope
     * @return Evaluation counters for the chunk
     */
    public static EvaluationResult evaluatePendingInactivation(List<Asset> assetList) {
        EvaluationResult result = new EvaluationResult();
        if (assetList == null || assetList.isEmpty()) {
            return result;
        }

        try {
            if (forceExceptionForTest == true) {
                throw new AssetPendingInactivationException('Forced evaluation failure for test');
            }
            if (
                forceStatusNotUpdateableForTest == true ||
                !Schema.sObjectType.Asset.fields.Status.isUpdateable()
            ) {
                throw new AssetPendingInactivationException(
                    'User does not have permission to update Asset.Status'
                );
            }

            Set<Id> pendingAssetIdSet = new Set<Id>();
            List<Asset> pendingAssetList = new List<Asset>();
            for (Asset assetRecord : assetList) {
                if (assetRecord == null || assetRecord.Status != STATUS_PENDING_INACTIVATION) {
                    continue;
                }
                pendingAssetIdSet.add(assetRecord.Id);
                pendingAssetList.add(assetRecord);
            }
            result.evaluatedCount = pendingAssetList.size();
            if (pendingAssetList.isEmpty()) {
                return result;
            }

            Set<Id> blockedAssetIdSet = new Set<Id>();
            blockedAssetIdSet.addAll(
                AssetPendingInactivationSelector.selectAssetIdsWithOpenWorkOrders(pendingAssetIdSet)
            );
            blockedAssetIdSet.addAll(
                AssetPendingInactivationSelector.selectAssetIdsWithActiveContractLines(pendingAssetIdSet)
            );

            List<Asset> assetsToInactivate = new List<Asset>();
            for (Asset assetRecord : pendingAssetList) {
                if (blockedAssetIdSet.contains(assetRecord.Id)) {
                    result.blockedCount++;
                    Logger.info('AssetPendingInactivationService: Asset ' + assetRecord.Id + ' remains ' + STATUS_PENDING_INACTIVATION + '; open Work Order or active contract line found. timestamp=' + String.valueOf(System.now()) + ' userId=' + UserInfo.getUserId());
                    continue;
                }
                assetsToInactivate.add(
                    new Asset(Id = assetRecord.Id, Status = STATUS_SERVICE_INACTIVE)
                );
            }

            if (assetsToInactivate.isEmpty()) {
                return result;
            }

            isEvaluatingInactivation = true;
            List<Database.SaveResult> saveResultList = Database.update(assetsToInactivate, false);
            for (Integer index = 0; index < saveResultList.size(); index++) {
                Database.SaveResult saveResult = saveResultList[index];
                Asset updatedAsset = assetsToInactivate[index];
                if (saveResult.isSuccess()) {
                    result.inactivatedCount++;
                    Logger.info('AssetPendingInactivationService: Asset ' + updatedAsset.Id + ' status ' + STATUS_PENDING_INACTIVATION + ' -> ' + STATUS_SERVICE_INACTIVE + '. timestamp=' + String.valueOf(System.now()) + ' userId=' + UserInfo.getUserId());
                } else {
                    Logger.error('AssetPendingInactivationService: failed to inactivate Asset ' + updatedAsset.Id + ': ' + saveResult.getErrors()[0].getMessage());
                }
            }
            return result;
        } catch (Exception e) {
            Logger.error('AssetPendingInactivationService.evaluatePendingInactivation', e);
            if (e instanceof AssetPendingInactivationException) {
                throw e;
            }
            throw new AssetPendingInactivationException(
                'An unexpected error occurred while evaluating Asset inactivation.',
                e
            );
        } finally {
            isEvaluatingInactivation = false;
            Logger.saveLog();
        }
    }
}