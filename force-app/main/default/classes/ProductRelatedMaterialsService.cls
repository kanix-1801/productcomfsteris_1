/**
 * @description Service class for ProductRelatedMaterial business operations.
 *              Entry point for all Product Related Material-related transactions.
 *              Performs DML directly — no Unit of Work.
 */
public with sharing class ProductRelatedMaterialsService {
    @TestVisible
    private interface IProductRelatedMaterialsSelector {
        List<ProductRelatedMaterial> selectById(Set<Id> relatedMaterialIds);
        List<ProductRelatedMaterial> selectBomComponentsForDeviceEvaluation(
            Set<Id> parentProductIds,
            Set<String> componentTypes
        );
    }

    private class DefaultProductRelatedMaterialsSelector
        implements IProductRelatedMaterialsSelector {
        public List<ProductRelatedMaterial> selectById(Set<Id> relatedMaterialIds) {
            return ProductRelatedMaterialsSelector.selectById(relatedMaterialIds);
        }

        public List<ProductRelatedMaterial> selectBomComponentsForDeviceEvaluation(
            Set<Id> parentProductIds,
            Set<String> componentTypes
        ) {
            return ProductRelatedMaterialsSelector.selectBomComponentsForDeviceEvaluation(
                parentProductIds,
                componentTypes
            );
        }
    }

    @TestVisible
    private static IProductRelatedMaterialsSelector selectorOverride;

    private static IProductRelatedMaterialsSelector selector() {
        return selectorOverride == null
            ? new DefaultProductRelatedMaterialsSelector()
            : selectorOverride;
    }

    /** GW-3913 / GW-3096 - Device Evaluation BOM component type constants. */
    @TestVisible
    private static final String COMPONENT_TYPE_CATEGORY_CODE = 'Category Code';
    @TestVisible
    private static final String COMPONENT_TYPE_SPECIAL_PRICING = 'Special Pricing';
    @TestVisible
    private static final String COMPONENT_TYPE_OBSERVATION_CODE = 'Observation Code';
    @TestVisible
    private static final String COMPONENT_TYPE_SERVICE_CODE = 'Service Code';
    @TestVisible
    private static final String COMPONENT_TYPE_OPTION_CLASS = 'Option Class';
    @TestVisible
    private static final String EVAL_DISPLAY_YES = 'Y';

    @TestVisible
    private static final Set<String> BOM_COMPONENT_TYPES = new Set<String>{
        COMPONENT_TYPE_CATEGORY_CODE,
        COMPONENT_TYPE_SPECIAL_PRICING,
        COMPONENT_TYPE_OBSERVATION_CODE,
        COMPONENT_TYPE_SERVICE_CODE,
        COMPONENT_TYPE_OPTION_CLASS
    };

    @TestVisible
    private static final Set<String> REPAIR_CODE_COMPONENT_TYPES = new Set<String>{
        COMPONENT_TYPE_CATEGORY_CODE,
        COMPONENT_TYPE_SPECIAL_PRICING,
        COMPONENT_TYPE_OBSERVATION_CODE,
        COMPONENT_TYPE_SERVICE_CODE
    };

    @TestVisible
    private static final Set<String> PRICING_CODE_COMPONENT_TYPES = new Set<String>{
        COMPONENT_TYPE_CATEGORY_CODE,
        COMPONENT_TYPE_SPECIAL_PRICING
    };

        /**
     * @description GW-3913 / GW-3096 - Public catalog of selectable repair-code Products from BOM.
     */
    public class RepairCodeCatalog {
        public Set<Id> categoryCodeIds = new Set<Id>();
        public Set<Id> observationCodeIds = new Set<Id>();
        public Set<Id> serviceCodeIds = new Set<Id>();
        /** Minimum Component Sequence seen for each repair-code Product. */
        public Map<Id, Decimal> componentSequenceByProductId = new Map<Id, Decimal>();
        public Integer totalSelectableCount {
            get {
                return categoryCodeIds.size() + observationCodeIds.size() + serviceCodeIds.size();
            }
        }
        public Set<Id> allProductIds() {
            Set<Id> allIds = new Set<Id>();
            allIds.addAll(categoryCodeIds);
            allIds.addAll(observationCodeIds);
            allIds.addAll(serviceCodeIds);
            return allIds;
        }
    }

    /**
     * @description GW-3913 / GW-3096 - Domain card data for Device Evaluation (not an LWC DTO).
     */
    public class RepairCodeCardData {
        public Id productId;
        public Id workOrderLineItemId;
        public String status;
        public String productCode;
        public String productName;
        public String codeType;
        public String evalCategory;
        public String evalRank;
        public String condition;
        public Decimal componentSequence;
        public Boolean selected;
    }

    /**
     * @description GW-3400 - Category and Service code cards for Instrument Evaluation (no observation).
     */
    public class InstrumentEvaluationCodeCards {
        public List<RepairCodeCardData> categoryCodes = new List<RepairCodeCardData>();
        public List<RepairCodeCardData> serviceCodes = new List<RepairCodeCardData>();
    }

    /**
     * @description GW-3913 / GW-3096 - Domain eval-category tab data for Device Evaluation.
     */
    public class EvalCategoryTabData {
        public String categoryName;
        public String tabValue;
        public String minEvalRank;
        public List<RepairCodeCardData> observationCodes = new List<RepairCodeCardData>();
        public List<RepairCodeCardData> serviceCodes = new List<RepairCodeCardData>();
    }

    /**
     * @description Creates new ProductRelatedMaterial records with validation.
     * @param relatedMaterials List of ProductRelatedMaterial records to create.
     * @throws ProductRelatedMaterialsServiceException when the operation fails.
     */
    public static void createProductRelatedMaterials(List<ProductRelatedMaterial> relatedMaterials) {
        if (relatedMaterials == null || relatedMaterials.isEmpty()) {
            return;
        }
        Logger.setScenario('Product Related Material Management');
        try {
            ProductRelatedMaterials domain = new ProductRelatedMaterials(relatedMaterials);
            // domain.applyDefaults();
            // domain.validate();
            insert relatedMaterials;
        } catch (ProductRelatedMaterials.ProductRelatedMaterialsException e) {
            Logger.error(new LogMessage('ProductRelatedMaterialsService.createProductRelatedMaterials: Validation failed. {0}', e.getMessage()), e);
            Logger.saveLog();
            throw new ProductRelatedMaterialsServiceException(e.getMessage(), e);
        } catch (Exception e) {
            Logger.error('ProductRelatedMaterialsService.createProductRelatedMaterials: Unexpected error.', e);
            Logger.saveLog();
            throw new ProductRelatedMaterialsServiceException('An unexpected error occurred while creating Product Related Material records.', e);
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description Updates existing ProductRelatedMaterial records with validation.
     * @param relatedMaterials List of ProductRelatedMaterial records to update.
     * @throws ProductRelatedMaterialsServiceException when the operation fails.
     */
    public static void updateProductRelatedMaterials(List<ProductRelatedMaterial> relatedMaterials) {
        if (relatedMaterials == null || relatedMaterials.isEmpty()) {
            return;
        }
        Logger.setScenario('Product Related Material Management');
        try {
            ProductRelatedMaterials domain = new ProductRelatedMaterials(relatedMaterials);
            // domain.validate();
            update relatedMaterials;
        } catch (ProductRelatedMaterials.ProductRelatedMaterialsException e) {
            Logger.error(new LogMessage('ProductRelatedMaterialsService.updateProductRelatedMaterials: Validation failed. {0}', e.getMessage()), e);
            Logger.saveLog();
            throw new ProductRelatedMaterialsServiceException(e.getMessage(), e);
        } catch (Exception e) {
            Logger.error('ProductRelatedMaterialsService.updateProductRelatedMaterials: Unexpected error.', e);
            Logger.saveLog();
            throw new ProductRelatedMaterialsServiceException('An unexpected error occurred while updating Product Related Material records.', e);
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description Deletes ProductRelatedMaterial records by their Ids.
     * @param relatedMaterialIds Set of ProductRelatedMaterial Ids to delete.
     * @throws ProductRelatedMaterialsServiceException when the operation fails.
     */
    public static void deleteProductRelatedMaterials(Set<Id> relatedMaterialIds) {
        if (relatedMaterialIds == null || relatedMaterialIds.isEmpty()) {
            return;
        }
        Logger.setScenario('Product Related Material Management');
        try {
            List<ProductRelatedMaterial> relatedMaterialList =
                selector().selectById(relatedMaterialIds);
            if (relatedMaterialList.isEmpty()) {
                return;
            }
            delete relatedMaterialList;
        } catch (Exception e) {
            Logger.error('ProductRelatedMaterialsService.deleteProductRelatedMaterials: Unexpected error.', e);
            Logger.saveLog();
            throw new ProductRelatedMaterialsServiceException('An unexpected error occurred while deleting Product Related Material records.', e);
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description Retrieves ProductRelatedMaterial records by their Ids.
     * @param relatedMaterialIds Set of ProductRelatedMaterial Ids to retrieve.
     * @return List of ProductRelatedMaterial records.
     * @throws ProductRelatedMaterialsServiceException when the operation fails.
     */
    public static List<ProductRelatedMaterial> getProductRelatedMaterialsById(Set<Id> relatedMaterialIds) {
        if (relatedMaterialIds == null || relatedMaterialIds.isEmpty()) {
            return new List<ProductRelatedMaterial>();
        }
        try {
            return selector().selectById(relatedMaterialIds);
        } catch (Exception e) {
            Logger.error('ProductRelatedMaterialsService.getProductRelatedMaterialsById: Unexpected error.', e);
            Logger.saveLog();
            throw new ProductRelatedMaterialsServiceException('An unexpected error occurred while retrieving Product Related Material records.', e);
        }
    }

    /**
     * @description GW-3913 / GW-3096 - Builds the Device Evaluation repair-code catalog from Asset Product BOM
     *              (level-one components plus nested Option Class children). Ports controller catalog logic.
     * @param assetProductId Asset Product2 Id
     * @return Populated RepairCodeCatalog (empty when assetProductId is null)
     * @throws ProductRelatedMaterialsServiceException when the operation fails
     */
    public static RepairCodeCatalog buildRepairCodeCatalogForDeviceEvaluation(Id assetProductId) {
        RepairCodeCatalog catalog = new RepairCodeCatalog();
        if (assetProductId == null) {
            return catalog;
        }
        try {
            List<ProductRelatedMaterial> levelOneComponents =
                selector().selectBomComponentsForDeviceEvaluation(
                    new Set<Id>{ assetProductId },
                    BOM_COMPONENT_TYPES
                );
            Set<Id> optionClassProductIds = new Set<Id>();
            collectRepairCodesFromBom(levelOneComponents, catalog, optionClassProductIds);

            if (!optionClassProductIds.isEmpty()) {
                List<ProductRelatedMaterial> levelTwoComponents =
                    selector().selectBomComponentsForDeviceEvaluation(
                        optionClassProductIds,
                        BOM_COMPONENT_TYPES
                    );
                collectRepairCodesFromBom(levelTwoComponents, catalog, null);
            }
            return catalog;
        } catch (Exception e) {
            Logger.error(
                new LogMessage(
                    'ProductRelatedMaterialsService.buildRepairCodeCatalogForDeviceEvaluation failed for {0}: {1}',
                    assetProductId,
                    e.getMessage()
                ),
                e
            );
            throw new ProductRelatedMaterialsServiceException(
                'An unexpected error occurred while building the Device Evaluation repair-code catalog.',
                e
            );
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description GW-3400 - Builds an Instrument Evaluation repair-code catalog from product BOM.
     *              Reuses Device Evaluation BOM traversal and excludes observation codes.
     * @param productId Instrument Product2 Id
     * @return Catalog with category and service codes only
     * @throws ProductRelatedMaterialsServiceException when the operation fails
     */
    public static RepairCodeCatalog buildInstrumentEvaluationCatalog(Id productId) {
        RepairCodeCatalog catalog = new RepairCodeCatalog();
        if (productId == null) {
            return catalog;
        }
        try {
            catalog = buildRepairCodeCatalogForDeviceEvaluation(productId);
            if (catalog == null) {
                return new RepairCodeCatalog();
            }
            catalog.observationCodeIds.clear();
            return catalog;
        } catch (ProductRelatedMaterialsServiceException e) {
            throw e;
        } catch (Exception e) {
            Logger.error(
                new LogMessage(
                    'ProductRelatedMaterialsService.buildInstrumentEvaluationCatalog failed for {0}: {1}',
                    productId,
                    e.getMessage()
                ),
                e
            );
            throw new ProductRelatedMaterialsServiceException(
                'An unexpected error occurred while building the Instrument Evaluation repair-code catalog.',
                e
            );
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description GW-3400 - Builds sorted Category and Service code cards for Instrument Evaluation.
     * @param productId Instrument Product2 Id
     * @return Code cards with observation omitted
     * @throws ProductRelatedMaterialsServiceException when the operation fails
     */
    public static InstrumentEvaluationCodeCards buildInstrumentEvaluationCodeCards(Id productId) {
        InstrumentEvaluationCodeCards cards = new InstrumentEvaluationCodeCards();
        if (productId == null) {
            return cards;
        }
        try {
            RepairCodeCatalog catalog = buildInstrumentEvaluationCatalog(productId);
            Map<Id, Product2> productsById =
                ProductsService.getProductsForDeviceEvaluationByIds(catalog.allProductIds());
            cards.categoryCodes = buildSortedPricingCards(
                catalog.categoryCodeIds,
                productsById,
                catalog.componentSequenceByProductId,
                new Set<Id>()
            );
            cards.serviceCodes = buildSortedCards(
                catalog.serviceCodeIds,
                productsById,
                catalog.componentSequenceByProductId,
                COMPONENT_TYPE_SERVICE_CODE,
                new Set<Id>()
            );
            return cards;
        } catch (ProductRelatedMaterialsServiceException e) {
            throw e;
        } catch (Exception e) {
            Logger.error(
                new LogMessage(
                    'ProductRelatedMaterialsService.buildInstrumentEvaluationCodeCards failed for {0}: {1}',
                    productId,
                    e.getMessage()
                ),
                e
            );
            throw new ProductRelatedMaterialsServiceException(
                'An unexpected error occurred while building Instrument Evaluation repair-code cards.',
                e
            );
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description Resolves component type from ComponentType__c or ProductComponent.ProductType__c.
     * @param bomRow BOM row
     * @return Component type string or null
     */
    @TestVisible
    private static String resolveComponentType(ProductRelatedMaterial bomRow) {
        if (bomRow == null) {
            return null;
        }
        if (String.isNotBlank(bomRow.ComponentType__c)) {
            return bomRow.ComponentType__c;
        }
        if (bomRow.ProductComponent != null) {
            return bomRow.ProductComponent.ProductType__c;
        }
        return null;
    }

    /**
     * @description Collects selectable repair codes from BOM rows into the catalog.
     * @param bomRows BOM component rows
     * @param catalog Target catalog
     * @param optionClassProductIds Optional set to collect Option Class Product Ids (null skips)
     */
    @TestVisible
    private static void collectRepairCodesFromBom(
        List<ProductRelatedMaterial> bomRows,
        RepairCodeCatalog catalog,
        Set<Id> optionClassProductIds
    ) {
        if (bomRows == null || bomRows.isEmpty()) {
            return;
        }
        for (ProductRelatedMaterial bomRow : bomRows) {
            String componentType = resolveComponentType(bomRow);
            if (componentType == COMPONENT_TYPE_OPTION_CLASS) {
                if (optionClassProductIds != null && bomRow.ProductComponentId != null) {
                    optionClassProductIds.add(bomRow.ProductComponentId);
                }
                continue;
            }
            if (!REPAIR_CODE_COMPONENT_TYPES.contains(componentType)) {
                continue;
            }
            if (bomRow.ProductComponent == null) {
                continue;
            }
            if (!EVAL_DISPLAY_YES.equalsIgnoreCase(bomRow.ProductComponent.EvalDisplayScreen__c)) {
                continue;
            }
            if (PRICING_CODE_COMPONENT_TYPES.contains(componentType)) {
                catalog.categoryCodeIds.add(bomRow.ProductComponentId);
            } else if (componentType == COMPONENT_TYPE_OBSERVATION_CODE) {
                catalog.observationCodeIds.add(bomRow.ProductComponentId);
            } else if (componentType == COMPONENT_TYPE_SERVICE_CODE) {
                catalog.serviceCodeIds.add(bomRow.ProductComponentId);
            }
            trackMinComponentSequence(
                catalog,
                bomRow.ProductComponentId,
                bomRow.ComponentSequence__c
            );
        }
    }

    /**
     * @description Tracks the minimum Component Sequence for a repair-code Product.
     * @param catalog Target catalog
     * @param productId Repair-code Product Id
     * @param componentSequence Component sequence value
     */
    @TestVisible
    private static void trackMinComponentSequence(
        RepairCodeCatalog catalog,
        Id productId,
        Decimal componentSequence
    ) {
        if (catalog == null || productId == null || componentSequence == null) {
            return;
        }
        Decimal existing = catalog.componentSequenceByProductId.get(productId);
        if (existing == null || componentSequence < existing) {
            catalog.componentSequenceByProductId.put(productId, componentSequence);
        }
    }

    /**
     * @description GW-3913 / GW-3096 - Builds sorted Pricing Codes cards for Device Evaluation.
     * @param catalog Repair-code catalog
     * @param productsById Products keyed by Id
     * @param selectedIds Selected Product Ids
     * @return Sorted pricing card data
     */
    public static List<RepairCodeCardData> buildSortedPricingCardsForDeviceEvaluation(
        RepairCodeCatalog catalog,
        Map<Id, Product2> productsById,
        Set<Id> selectedIds
    ) {
        if (catalog == null) {
            return new List<RepairCodeCardData>();
        }
        return buildSortedPricingCards(
            catalog.categoryCodeIds,
            productsById,
            catalog.componentSequenceByProductId,
            selectedIds
        );
    }

    /**
     * @description GW-3913 / GW-3096 - Builds eval-category tabs (Observation + Service) for Device Evaluation.
     * @param catalog Repair-code catalog
     * @param productsById Products keyed by Id
     * @param selectedIds Selected Product Ids
     * @return Sorted eval-category tabs
     */
    public static List<EvalCategoryTabData> buildEvalCategoryTabsForDeviceEvaluation(
        RepairCodeCatalog catalog,
        Map<Id, Product2> productsById,
        Set<Id> selectedIds
    ) {
        List<EvalCategoryTabData> tabs = new List<EvalCategoryTabData>();
        if (catalog == null || productsById == null) {
            return tabs;
        }
        Set<Id> selected = selectedIds == null ? new Set<Id>() : selectedIds;
        Map<String, EvalCategoryTabData> tabsByCategory = new Map<String, EvalCategoryTabData>();
        Map<Id, Decimal> sequences = catalog.componentSequenceByProductId;

        for (Id productId : catalog.observationCodeIds) {
            Product2 product = productsById.get(productId);
            if (product == null || String.isBlank(product.EvalCategory__c)) {
                continue;
            }
            EvalCategoryTabData tab = getOrCreateCategoryTab(tabsByCategory, product.EvalCategory__c);
            tab.observationCodes.add(
                toCard(
                    product,
                    COMPONENT_TYPE_OBSERVATION_CODE,
                    selected.contains(productId),
                    sequences.get(productId)
                )
            );
        }
        for (Id productId : catalog.serviceCodeIds) {
            Product2 product = productsById.get(productId);
            if (product == null || String.isBlank(product.EvalCategory__c)) {
                continue;
            }
            EvalCategoryTabData tab = getOrCreateCategoryTab(tabsByCategory, product.EvalCategory__c);
            tab.serviceCodes.add(
                toCard(
                    product,
                    COMPONENT_TYPE_SERVICE_CODE,
                    selected.contains(productId),
                    sequences.get(productId)
                )
            );
        }

        tabs = new List<EvalCategoryTabData>(tabsByCategory.values());
        for (EvalCategoryTabData tab : tabs) {
            tab.observationCodes.sort(new RepairCodeCardSequenceComparator());
            tab.serviceCodes.sort(new RepairCodeCardSequenceComparator());
            tab.minEvalRank = resolveMinEvalRank(tab);
        }
        tabs.sort(new EvalCategoryTabRankComparator());
        return tabs;
    }

    /**
     * @description Builds sorted repair-code cards for a product Id set and code type.
     */
    @TestVisible
    private static List<RepairCodeCardData> buildSortedCards(
        Set<Id> productIds,
        Map<Id, Product2> productsById,
        Map<Id, Decimal> componentSequenceByProductId,
        String codeType,
        Set<Id> selectedIds
    ) {
        List<RepairCodeCardData> cards = new List<RepairCodeCardData>();
        if (productIds == null || productsById == null) {
            return cards;
        }
        Set<Id> selected = selectedIds == null ? new Set<Id>() : selectedIds;
        for (Id productId : productIds) {
            Product2 product = productsById.get(productId);
            if (product == null) {
                continue;
            }
            Decimal sequence =
                componentSequenceByProductId != null
                    ? componentSequenceByProductId.get(productId)
                    : null;
            cards.add(toCard(product, codeType, selected.contains(productId), sequence));
        }
        cards.sort(new RepairCodeCardSequenceComparator());
        return cards;
    }

    /**
     * @description Builds Pricing Codes cards using each product's ProductType__c as code type.
     */
    @TestVisible
    private static List<RepairCodeCardData> buildSortedPricingCards(
        Set<Id> productIds,
        Map<Id, Product2> productsById,
        Map<Id, Decimal> componentSequenceByProductId,
        Set<Id> selectedIds
    ) {
        List<RepairCodeCardData> cards = new List<RepairCodeCardData>();
        if (productIds == null || productsById == null) {
            return cards;
        }
        Set<Id> selected = selectedIds == null ? new Set<Id>() : selectedIds;
        for (Id productId : productIds) {
            Product2 product = productsById.get(productId);
            if (product == null) {
                continue;
            }
            String codeType = PRICING_CODE_COMPONENT_TYPES.contains(product.ProductType__c)
                ? product.ProductType__c
                : COMPONENT_TYPE_CATEGORY_CODE;
            Decimal sequence =
                componentSequenceByProductId != null
                    ? componentSequenceByProductId.get(productId)
                    : null;
            cards.add(toCard(product, codeType, selected.contains(productId), sequence));
        }
        cards.sort(new RepairCodeCardSequenceComparator());
        return cards;
    }

    private static EvalCategoryTabData getOrCreateCategoryTab(
        Map<String, EvalCategoryTabData> tabsByCategory,
        String categoryName
    ) {
        if (!tabsByCategory.containsKey(categoryName)) {
            EvalCategoryTabData tab = new EvalCategoryTabData();
            tab.categoryName = categoryName;
            tab.tabValue = 'eval-' + String.valueOf(Math.abs(categoryName.hashCode()));
            tab.observationCodes = new List<RepairCodeCardData>();
            tab.serviceCodes = new List<RepairCodeCardData>();
            tabsByCategory.put(categoryName, tab);
        }
        return tabsByCategory.get(categoryName);
    }

    private static RepairCodeCardData toCard(
        Product2 product,
        String codeType,
        Boolean selected,
        Decimal componentSequence
    ) {
        RepairCodeCardData card = new RepairCodeCardData();
        card.productId = product.Id;
        card.productCode = product.ProductCode;
        card.productName = String.isNotBlank(product.Description) ? product.Description : product.Name;
        card.codeType = codeType;
        card.evalCategory = product.EvalCategory__c;
        card.evalRank = product.EvalRank__c;
        card.condition = product.Condition__c;
        card.componentSequence = componentSequence;
        card.selected = selected == true;
        return card;
    }

    private static String resolveMinEvalRank(EvalCategoryTabData tab) {
        Decimal minRank = null;
        if (tab == null) {
            return null;
        }
        List<RepairCodeCardData> allCards = new List<RepairCodeCardData>();
        if (tab.observationCodes != null) {
            allCards.addAll(tab.observationCodes);
        }
        if (tab.serviceCodes != null) {
            allCards.addAll(tab.serviceCodes);
        }
        for (RepairCodeCardData card : allCards) {
            Decimal rank = parseRank(card != null ? card.evalRank : null);
            if (rank == null) {
                continue;
            }
            if (minRank == null || rank < minRank) {
                minRank = rank;
            }
        }
        return minRank == null ? null : String.valueOf(minRank);
    }

    private class RepairCodeCardSequenceComparator implements Comparator<RepairCodeCardData> {
        public Integer compare(RepairCodeCardData left, RepairCodeCardData right) {
            Decimal leftSequence = left != null ? left.componentSequence : null;
            Decimal rightSequence = right != null ? right.componentSequence : null;
            Integer sequenceCompare = compareDecimalsNullsLast(leftSequence, rightSequence);
            if (sequenceCompare != 0) {
                return sequenceCompare;
            }
            String leftCode = left != null && left.productCode != null ? left.productCode : '';
            String rightCode = right != null && right.productCode != null ? right.productCode : '';
            return leftCode.toLowerCase().compareTo(rightCode.toLowerCase());
        }
    }

    private class EvalCategoryTabRankComparator implements Comparator<EvalCategoryTabData> {
        public Integer compare(EvalCategoryTabData left, EvalCategoryTabData right) {
            Decimal leftRank = parseRank(left != null ? left.minEvalRank : null);
            Decimal rightRank = parseRank(right != null ? right.minEvalRank : null);
            Integer rankCompare = compareDecimalsNullsLast(leftRank, rightRank);
            if (rankCompare != 0) {
                return rankCompare;
            }
            String leftName = left != null && left.categoryName != null ? left.categoryName : '';
            String rightName = right != null && right.categoryName != null ? right.categoryName : '';
            return leftName.toLowerCase().compareTo(rightName.toLowerCase());
        }
    }

    private static Integer compareDecimalsNullsLast(Decimal leftValue, Decimal rightValue) {
        Boolean leftBlank = leftValue == null;
        Boolean rightBlank = rightValue == null;
        if (leftBlank && rightBlank) {
            return 0;
        }
        if (leftBlank) {
            return 1;
        }
        if (rightBlank) {
            return -1;
        }
        if (leftValue < rightValue) {
            return -1;
        }
        if (leftValue > rightValue) {
            return 1;
        }
        return 0;
    }

    private static Decimal parseRank(String rankValue) {
        if (String.isBlank(rankValue)) {
            return null;
        }
        try {
            return Decimal.valueOf(rankValue.trim());
        } catch (Exception e) {
            return null;
        }
    }

    /**
     * @description Thrown when a Product Related Material service operation fails.
     */
    public class ProductRelatedMaterialsServiceException extends Exception {}
}