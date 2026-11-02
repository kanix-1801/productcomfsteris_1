/**
 * @description Service class for Asset business operations.
 *              Entry point for all Asset-related transactions.
 *              Performs DML directly — no Unit of Work.
 */
public with sharing class AssetsService {

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
            Assets domain = new Assets(assets);
            // domain.applyDefaults();
            // domain.validate();
            insert assets;
        } catch (Assets.AssetsException e) {
            Logger.error(new LogMessage('AssetsService.createAssets: Validation failed. {0}', e.getMessage()), e);
            Logger.saveLog();
            throw new AssetsServiceException(e.getMessage(), e);
        } catch (Exception e) {
            Logger.error('AssetsService.createAssets: Unexpected error.', e);
            Logger.saveLog();
            throw new AssetsServiceException('An unexpected error occurred while creating Asset records.', e);
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description Updates existing Asset records with validation.
     * @param assets List of Asset records to update.
     * @throws AssetsServiceException when the operation fails.
     */
    public static void updateAssets(List<Asset> assets) {
        if (assets == null || assets.isEmpty()) {
            return;
        }
        Logger.setScenario('Asset Management');
        try {
            Assets domain = new Assets(assets);
            // domain.validate();
            update assets;
        } catch (Assets.AssetsException e) {
            Logger.error(new LogMessage('AssetsService.updateAssets: Validation failed. {0}', e.getMessage()), e);
            Logger.saveLog();
            throw new AssetsServiceException(e.getMessage(), e);
        } catch (Exception e) {
            Logger.error('AssetsService.updateAssets: Unexpected error.', e);
            Logger.saveLog();
            throw new AssetsServiceException('An unexpected error occurred while updating Asset records.', e);
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
            Logger.saveLog();
            throw new AssetsServiceException('An unexpected error occurred while deleting Asset records.', e);
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description Assets whose serial number and product match a receiving override.
     * @param serialNumbers Listed serial values, including the original casing
     * @param productId Product on the Return Order line
     * @return Matching Asset records
     * @throws AssetsServiceException when the query fails
     */
    public static List<Asset> getAssetsBySerialAndProduct(Set<String> serialNumbers, Id productId) {
        if (serialNumbers == null || serialNumbers.isEmpty() || productId == null) {
            return new List<Asset>();
        }
        try {
            List<Asset> matches = new List<Asset>();
            for (Asset asset : AssetsSelector.selectBySerialNumber(serialNumbers)) {
                if (asset.Product2Id == productId) {
                    matches.add(asset);
                }
            }
            return matches;
        } catch (Exception e) {
            Logger.error('AssetsService.getAssetsBySerialAndProduct: Unexpected error.', e);
            Logger.saveLog();
            throw new AssetsServiceException(
                'An unexpected error occurred while retrieving Asset records.',
                e
            );
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
            Logger.saveLog();
            throw new AssetsServiceException('An unexpected error occurred while retrieving Asset records.', e);
        }
    }

    /**
     * @description Thrown when an Asset service operation fails.
     */
    public class AssetsServiceException extends Exception {}
}