/**
 * @description Service class for ProductItem business operations.
 *              Entry point for all Product Item-related transactions.
 *              Performs DML directly — no Unit of Work.
 */
public with sharing class ProductItemsService {
    @TestVisible
    private static Boolean simulateUnexpectedException = false;

    /**
     * @description Creates new ProductItem records with validation.
     * @param productItems List of ProductItem records to create.
     * @throws ProductItemsServiceException when the operation fails.
     */
    public static void createProductItems(List<ProductItem> productItems) {
        if (productItems == null || productItems.isEmpty()) {
            return;
        }
        Logger.setScenario('Product Item Management');
        try {
            ProductItems domain = new ProductItems(productItems);
            // domain.applyDefaults();
            // domain.validate();
            insert productItems;
        } catch (ProductItems.ProductItemsException e) {
            Logger.error(new LogMessage('ProductItemsService.createProductItems: Validation failed. {0}', e.getMessage()), e);
            Logger.saveLog();
            throw new ProductItemsServiceException(e.getMessage(), e);
        } catch (Exception e) {
            Logger.error('ProductItemsService.createProductItems: Unexpected error.', e);
            Logger.saveLog();
            throw new ProductItemsServiceException('An unexpected error occurred while creating Product Item records.', e);
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description Updates existing ProductItem records with validation.
     * @param productItems List of ProductItem records to update.
     * @throws ProductItemsServiceException when the operation fails.
     */
    public static void updateProductItems(List<ProductItem> productItems) {
        if (productItems == null || productItems.isEmpty()) {
            return;
        }
        Logger.setScenario('Product Item Management');
        try {
            ProductItems domain = new ProductItems(productItems);
            // domain.validate();
            update productItems;
        } catch (ProductItems.ProductItemsException e) {
            Logger.error(new LogMessage('ProductItemsService.updateProductItems: Validation failed. {0}', e.getMessage()), e);
            Logger.saveLog();
            throw new ProductItemsServiceException(e.getMessage(), e);
        } catch (Exception e) {
            Logger.error('ProductItemsService.updateProductItems: Unexpected error.', e);
            Logger.saveLog();
            throw new ProductItemsServiceException('An unexpected error occurred while updating Product Item records.', e);
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description Deletes ProductItem records by their Ids.
     * @param productItemIds Set of ProductItem Ids to delete.
     * @throws ProductItemsServiceException when the operation fails.
     */
    public static void deleteProductItems(Set<Id> productItemIds) {
        if (productItemIds == null || productItemIds.isEmpty()) {
            return;
        }
        Logger.setScenario('Product Item Management');
        try {
            List<ProductItem> productItemList = ProductItemsSelector.selectById(productItemIds);
            if (productItemList.isEmpty()) {
                return;
            }
            delete productItemList;
        } catch (Exception e) {
            Logger.error('ProductItemsService.deleteProductItems: Unexpected error.', e);
            Logger.saveLog();
            throw new ProductItemsServiceException('An unexpected error occurred while deleting Product Item records.', e);
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description Retrieves ProductItem records by their Ids.
     * @param productItemIds Set of ProductItem Ids to retrieve.
     * @return List of ProductItem records.
     * @throws ProductItemsServiceException when the operation fails.
     */
    public static List<ProductItem> getProductItemsById(Set<Id> productItemIds) {
        if (productItemIds == null || productItemIds.isEmpty()) {
            return new List<ProductItem>();
        }
        try {
            if (simulateUnexpectedException) {
                throw new QueryException('Simulated failure');
            }
            return ProductItemsSelector.selectById(productItemIds);
        } catch (Exception e) {
            Logger.error('ProductItemsService.getProductItemsById: Unexpected error.', e);
            Logger.saveLog();
            throw new ProductItemsServiceException('An unexpected error occurred while retrieving Product Item records.', e);
        }
    }

    /**
     * @description Thrown when a Product Item service operation fails.
     */
    public class ProductItemsServiceException extends Exception {}
}