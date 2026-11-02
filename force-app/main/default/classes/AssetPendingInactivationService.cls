/**
 * @description GW-2459 - Evaluates Pending Inactivation Assets and sets Service Inactive
 *              only when no open Work Orders or active contract lines exist.
 * @author STERIS
 * @see AssetPendingInactivationSelector
 * @see AssetPendingInactivationBatch
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
                    Logger.info(
                        'AssetPendingInactivationService: Asset ' +
                        assetRecord.Id +
                        ' remains ' +
                        STATUS_PENDING_INACTIVATION +
                        '; open Work Order or active contract line found. timestamp=' +
                        String.valueOf(System.now()) +
                        ' userId=' +
                        UserInfo.getUserId()
                    );
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
                    Logger.info(
                        'AssetPendingInactivationService: Asset ' +
                        updatedAsset.Id +
                        ' status ' +
                        STATUS_PENDING_INACTIVATION +
                        ' -> ' +
                        STATUS_SERVICE_INACTIVE +
                        '. timestamp=' +
                        String.valueOf(System.now()) +
                        ' userId=' +
                        UserInfo.getUserId()
                    );
                } else {
                    Logger.error(
                        'AssetPendingInactivationService: failed to inactivate Asset ' +
                        updatedAsset.Id +
                        ': ' +
                        saveResult.getErrors()[0].getMessage()
                    );
                }
            }
            return result;
        } catch (AssetPendingInactivationException e) {
            Logger.error('AssetPendingInactivationService.evaluatePendingInactivation', e);
            throw e;
        } catch (Exception e) {
            Logger.error('AssetPendingInactivationService.evaluatePendingInactivation', e);
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