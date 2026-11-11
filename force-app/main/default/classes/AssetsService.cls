/**
 * @description Service class for Asset business operations.
 *              Entry point for all Asset-related transactions.
 *              Performs DML directly without a Unit of Work.
 */
public with sharing class AssetsService {

    private static final List<String> ELEVATED_SERIAL_PRODUCT_FIELDS = new List<String>{
        'Id',
        'Name',
        'SerialNumber',
        'Product2Id',
        'Product2.ProductCode'
    };

    /**
     * @description Creates new Asset records with validation.
     * @param assets List of Asset records to create.
     * @throws AssetsServiceException when the operation fails.
     */
    public static void createAssets(List<Asset> assets) {
        if (assets == null || assets.isEmpty()) {
            return;
        }
        Logger.setScenario('Asset Management');
        try {
            // Domain validate/defaults are not active yet; keep construction for future use.
            new Assets(assets);
            insert assets;
        } catch (Exception e) {
            Logger.error('AssetsService.createAssets: Unexpected error.', e);
            throw new AssetsServiceException('An unexpected error occurred while creating Asset records.', e);
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description Deletes Asset records by their Ids.
     * @param assetIds Set of Asset Ids to delete.
     * @throws AssetsServiceException when the operation fails.
     */
    public static void deleteAssets(Set<Id> assetIds) {
        if (assetIds == null || assetIds.isEmpty()) {
            return;
        }
        Logger.setScenario('Asset Management');
        try {
            List<Asset> assetList = AssetsSelector.selectById(assetIds);
            if (assetList.isEmpty()) {
                return;
            }
            delete assetList;
        } catch (Exception e) {
            Logger.error('AssetsService.deleteAssets: Unexpected error.', e);
            throw new AssetsServiceException('An unexpected error occurred while deleting Asset records.', e);
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description GW-6877 - Serial + product Asset lookup that ignores Asset sharing.
     *              Used by Receiving serial override when the receiver does not own the Asset.
     * @param serialNumbers Listed serial values, including the original casing
     * @param productId Product on the Return Order or Work Order line
     * @return Matching Asset records
     * @throws AssetsServiceException when the query fails
     */
    public static List<Asset> getAssetsBySerialAndProductElevated(
        Set<String> serialNumbers,
        Id productId
    ) {
        if (serialNumbers == null || serialNumbers.isEmpty() || productId == null) {
            return new List<Asset>();
        }
        try {
            // Match ReceivingService: compose the query on the Selector builder at Service level.
            return (List<Asset>) new AssetsSelector()
                .selectFields(ELEVATED_SERIAL_PRODUCT_FIELDS)
                .whereField('SerialNumber', 'IN', new List<String>(serialNumbers))
                .whereEquals('Product2Id', productId)
                .executeSystemMode();
        } catch (Exception e) {
            Logger.error(
                'AssetsService.getAssetsBySerialAndProductElevated: Unexpected error.',
                e
            );
            throw new AssetsServiceException(
                'An unexpected error occurred while retrieving Asset records.',
                e
            );
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description GW-6877 - Updates Asset records ignoring Asset sharing.
     *              Used by Receiving serial override when the receiver does not own the Asset.
     * @param assets List of Asset records to update
     * @throws AssetsServiceException when the operation fails
     */
    public static void updateAssetsElevated(List<Asset> assets) {
        if (assets == null || assets.isEmpty()) {
            return;
        }
        Logger.setScenario('Asset Management');
        try {
            // Domain validate is not active yet; keep construction for future use.
            new Assets(assets);
            // Match ReceivingFinishService: without sharing + SYSTEM_MODE.
            // SYSTEM_MODE alone from a with-sharing class still failed for RC technicians
            // (INSUFFICIENT_ACCESS_OR_READONLY on Private Asset).
            new AssetSystemAccess().updateAssets(assets);
        } catch (Exception e) {
            Logger.error('AssetsService.updateAssetsElevated: Unexpected error.', e);
            throw new AssetsServiceException(
                'An unexpected error occurred while updating Asset records.',
                e
            );
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description Retrieves Asset records by their Ids.
     * @param assetIds Set of Asset Ids to retrieve.
     * @return List of Asset records.
     * @throws AssetsServiceException when the operation fails.
     */
    public static List<Asset> getAssetsById(Set<Id> assetIds) {
        if (assetIds == null || assetIds.isEmpty()) {
            return new List<Asset>();
        }
        try {
            return AssetsSelector.selectById(assetIds);
        } catch (Exception e) {
            Logger.error('AssetsService.getAssetsById: Unexpected error.', e);
            throw new AssetsServiceException('An unexpected error occurred while retrieving Asset records.', e);
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description Elevates Asset DML for Receiving serial override (sharing + CRUD).
     */
    private without sharing class AssetSystemAccess {
        private void updateAssets(List<Asset> assets) {
            Database.update(assets, System.AccessLevel.SYSTEM_MODE);
        }
    }

    /**
     * @description Thrown when an Asset service operation fails.
     */
    public class AssetsServiceException extends Exception {}
}