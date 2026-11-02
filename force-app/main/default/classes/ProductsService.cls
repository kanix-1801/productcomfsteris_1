/**
 * @description Service class for Product2 business operations.
 *              Entry point for all Product-related transactions.
 *              Performs DML directly — no Unit of Work.
 */
public with sharing class ProductsService {
    @TestVisible
    private interface IProductsSelector {
        List<Product2> selectById(Set<Id> productIds);
        List<Product2> selectForDeviceEvaluationByIds(Set<Id> productIds);
        List<Product2> selectLabelsById(Id productId);
        List<Product2> selectForApproveRejectByIds(Set<Id> productIds);
    }

    private class DefaultProductsSelector implements IProductsSelector {
        public List<Product2> selectById(Set<Id> productIds) {
            return ProductsSelector.selectById(productIds);
        }

        public List<Product2> selectForDeviceEvaluationByIds(Set<Id> productIds) {
            return ProductsSelector.selectForDeviceEvaluationByIds(productIds);
        }

        public List<Product2> selectLabelsById(Id productId) {
            return ProductsSelector.selectLabelsById(productId);
        }

        public List<Product2> selectForApproveRejectByIds(Set<Id> productIds) {
            return ProductsSelector.selectForApproveRejectByIds(productIds);
        }
    }

    @TestVisible
    private static IProductsSelector selectorOverride;

    private static IProductsSelector selector() {
        return selectorOverride == null ? new DefaultProductsSelector() : selectorOverride;
    }

    /**
     * @description Creates new Product2 records with validation.
     * @param products List of Product2 records to create.
     * @throws ProductsServiceException when the operation fails.
     */
    public static void createProducts(List<Product2> products) {
        if (products == null || products.isEmpty()) {
            return;
        }
        Logger.setScenario('Product Management');
        try {
            Products domain = new Products(products);
            // domain.applyDefaults();
            // domain.validate();
            insert products;
        } catch (Products.ProductsException e) {
            Logger.error(new LogMessage('ProductsService.createProducts: Validation failed. {0}', e.getMessage()), e);
            Logger.saveLog();
            throw new ProductsServiceException(e.getMessage(), e);
        } catch (Exception e) {
            Logger.error('ProductsService.createProducts: Unexpected error.', e);
            Logger.saveLog();
            throw new ProductsServiceException('An unexpected error occurred while creating Product records.', e);
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description Updates existing Product2 records with validation.
     * @param products List of Product2 records to update.
     * @throws ProductsServiceException when the operation fails.
     */
    public static void updateProducts(List<Product2> products) {
        if (products == null || products.isEmpty()) {
            return;
        }
        Logger.setScenario('Product Management');
        try {
            Products domain = new Products(products);
            // domain.validate();
            update products;
        } catch (Products.ProductsException e) {
            Logger.error(new LogMessage('ProductsService.updateProducts: Validation failed. {0}', e.getMessage()), e);
            Logger.saveLog();
            throw new ProductsServiceException(e.getMessage(), e);
        } catch (Exception e) {
            Logger.error('ProductsService.updateProducts: Unexpected error.', e);
            Logger.saveLog();
            throw new ProductsServiceException('An unexpected error occurred while updating Product records.', e);
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description Deletes Product2 records by their Ids.
     * @param productIds Set of Product2 Ids to delete.
     * @throws ProductsServiceException when the operation fails.
     */
    public static void deleteProducts(Set<Id> productIds) {
        if (productIds == null || productIds.isEmpty()) {
            return;
        }
        Logger.setScenario('Product Management');
        try {
            List<Product2> productList = selector().selectById(productIds);
            if (productList.isEmpty()) {
                return;
            }
            delete productList;
        } catch (Exception e) {
            Logger.error('ProductsService.deleteProducts: Unexpected error.', e);
            Logger.saveLog();
            throw new ProductsServiceException('An unexpected error occurred while deleting Product records.', e);
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description Retrieves Product2 records by their Ids.
     * @param productIds Set of Product2 Ids to retrieve.
     * @return List of Product2 records.
     * @throws ProductsServiceException when the operation fails.
     */
    public static List<Product2> getProductsById(Set<Id> productIds) {
        if (productIds == null || productIds.isEmpty()) {
            return new List<Product2>();
        }
        try {
            return selector().selectById(productIds);
        } catch (Exception e) {
            Logger.error('ProductsService.getProductsById: Unexpected error.', e);
            Logger.saveLog();
            throw new ProductsServiceException('An unexpected error occurred while retrieving Product records.', e);
        }
    }

    /****************************************************************************************
     * ADDITIVES FOR DEVICE EVALUATION (GW-3913 / GW-3096)
     * Methods below this banner were added for Repair Center LWC Batch 9 (not Dev baseline).
     ****************************************************************************************/

    /**
     * @description GW-3913 / GW-3096 - Returns Products keyed by Id for Device Evaluation cards.
     * @param productIds Set of Product2 Ids
     * @return Map of Product2 Id to Product2
     * @throws ProductsServiceException when the operation fails
     */
    public static Map<Id, Product2> getProductsForDeviceEvaluationByIds(Set<Id> productIds) {
        Map<Id, Product2> productsById = new Map<Id, Product2>();
        if (productIds == null || productIds.isEmpty()) {
            return productsById;
        }
        try {
            for (Product2 product : selector().selectForDeviceEvaluationByIds(productIds)) {
                productsById.put(product.Id, product);
            }
            return productsById;
        } catch (Exception e) {
            Logger.error(
                'ProductsService.getProductsForDeviceEvaluationByIds: Unexpected error.',
                e
            );
            Logger.saveLog();
            throw new ProductsServiceException(
                'An unexpected error occurred while retrieving Products for Device Evaluation.',
                e
            );
        }
    }

    /**
     * @description GW-3913 / GW-3096 - Returns Product labels for photo staging, or null when not found.
     * @param productId Product2 Id
     * @return Product2 or null
     * @throws ProductsServiceException when the operation fails
     */
    public static Product2 getProductLabelsById(Id productId) {
        if (productId == null) {
            return null;
        }
        try {
            List<Product2> products = selector().selectLabelsById(productId);
            return products.isEmpty() ? null : products[0];
        } catch (Exception e) {
            Logger.error('ProductsService.getProductLabelsById: Unexpected error.', e);
            Logger.saveLog();
            throw new ProductsServiceException(
                'An unexpected error occurred while retrieving Product labels for Device Evaluation.',
                e
            );
        }
    }

    /**
     * @description GW-5333 - Loads Products for Approve/Reject Quote disinfection and inspection rules.
     * @param productIds Product2 Ids
     * @return Matching Product2 rows
     */
    public static List<Product2> getProductsForApproveRejectById(Set<Id> productIds) {
        if (productIds == null || productIds.isEmpty()) {
            return new List<Product2>();
        }
        try {
            return selector().selectForApproveRejectByIds(productIds);
        } catch (Exception e) {
            Logger.error('ProductsService.getProductsForApproveRejectById: Unexpected error.', e);
            Logger.saveLog();
            throw new ProductsServiceException(
                'An unexpected error occurred while retrieving Products for Approve/Reject Quote.',
                e
            );
        }
    }

    /**
     * @description Thrown when a Product service operation fails.
     */
    public class ProductsServiceException extends Exception {}
}