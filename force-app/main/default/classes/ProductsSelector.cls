/**
 * @description Selector class for the Product2 SObject.
 *              Extends SoqlQueryBuilder for generic queries; legacy selectBy* methods remain.
 *              Centralizes Product SOQL. Classes run with sharing.
 */
public with sharing class ProductsSelector extends SoqlQueryBuilder {
    /**
     * @description Binds this selector to Product2 for SoqlQueryBuilder queries.
     */
    public ProductsSelector() {
        this.objectName = 'Product2';
    }

    private static final String BASE_FIELDS =
        'Id, Name, ProductCode, Description, IsActive, Family, ' +
        'StockKeepingUnit, Type, CreatedDate, LastModifiedDate';

    /**
     * @description Retrieves Product2 records by their Ids.
     * @param ids Set of Product2 Ids to query.
     * @return List of Product2 records matching the given Ids.
     */
    public static List<Product2> selectById(Set<Id> ids) {
        if (ids == null || ids.isEmpty()) {
            return new List<Product2>();
        }
        return Database.query(
            'SELECT ' + BASE_FIELDS +
            ' FROM Product2' +
            ' WHERE Id IN :ids'
        );
    }

    /**
     * @description Retrieves active Product2 records by Name.
     * @param names Set of Product Names to filter by.
     * @return List of Product2 records matching the given Names.
     */
    public static List<Product2> selectByName(Set<String> names) {
        if (names == null || names.isEmpty()) {
            return new List<Product2>();
        }
        return Database.query(
            'SELECT ' + BASE_FIELDS +
            ' FROM Product2' +
            ' WHERE Name IN :names' +
            ' ORDER BY Name ASC'
        );
    }

    /**
     * @description Retrieves active Product2 records by Product Code.
     * @param productCodes Set of product codes to filter by.
     * @return List of Product2 records matching the given product codes.
     */
    public static List<Product2> selectByProductCode(Set<String> productCodes) {
        if (productCodes == null || productCodes.isEmpty()) {
            return new List<Product2>();
        }
        return Database.query(
            'SELECT ' + BASE_FIELDS +
            ' FROM Product2' +
            ' WHERE ProductCode IN :productCodes' +
            ' AND IsActive = true'
        );
    }

    /**
     * @description GW-3913 / GW-3096 - Selects Products with Device Evaluation card fields.
     * @param productIds Set of Product2 Ids
     * @return Matching Product2 records
     */
    public static List<Product2> selectForDeviceEvaluationByIds(Set<Id> productIds) {
        if (productIds == null || productIds.isEmpty()) {
            return new List<Product2>();
        }
        return [
            SELECT
                Id,
                Name,
                ProductCode,
                Description,
                ProductType__c,
                EvalCategory__c,
                EvalRank__c,
                Condition__c,
                Model__c
            FROM Product2
            WHERE Id IN :productIds
        ];
    }

    /**
     * @description GW-3913 / GW-3096 - Selects Product labels for Device Evaluation photo staging
     *              (LIMIT 1, USER_MODE).
     * @param productId Product2 Id
     * @return Matching Product2 records (ProductCode, Name, Description)
     */
    public static List<Product2> selectLabelsById(Id productId) {
        if (productId == null) {
            return new List<Product2>();
        }
        return [
            SELECT ProductCode, Name, Description
            FROM Product2
            WHERE Id = :productId
            WITH USER_MODE
            LIMIT 1
        ];
    }

    private static final String INSTRUMENT_EVALUATION_PRODUCT_TYPE = 'Service Asset';
    private static final String EVAL_DISPLAY_YES = 'Y';

    /**
     * @description GW-3400 - Selects Instrument Evaluation catalog products for a Product Line.
     *              Product Line and Sub Product Line matching is case-insensitive; Product Line also
     *              treats trailing plural "s" as equivalent (Instruments / INSTRUMENT).
     *              When Sub Product Line is blank, returns products across all Sub Product Lines.
     * @param productLine Product Line (Instruments)
     * @param subProductLine Sub Product Line matching Work Order Repair Category; blank = all
     * @return Matching Product2 records ordered by ProductCode
     */
    public static List<Product2> selectForInstrumentEvaluation(
        String productLine,
        String subProductLine
    ) {
        if (String.isBlank(productLine)) {
            return new List<Product2>();
        }
        List<Product2> candidates = [
            SELECT
                Id,
                Name,
                ProductCode,
                EvalCategory__c,
                EvalRank__c,
                ProductLine__c,
                SubProductLine__c
            FROM Product2
            WHERE ProductType__c = :INSTRUMENT_EVALUATION_PRODUCT_TYPE
                AND EvalDisplayScreen__c = :EVAL_DISPLAY_YES
                AND IsActive = true
                AND EvalCategory__c != null
            ORDER BY ProductCode ASC
        ];
        return filterInstrumentEvaluationProducts(candidates, productLine, subProductLine, null);
    }

    /**
     * @description GW-3400 - Selects Instrument Evaluation products for one Eval Category.
     *              Product Line, Sub Product Line, and Eval Category matching is case-insensitive;
     *              Product Line also treats trailing plural "s" as equivalent.
     *              When Sub Product Line is blank, returns products across all Sub Product Lines.
     * @param productLine Product Line (Instruments)
     * @param subProductLine Sub Product Line matching Work Order Repair Category; blank = all
     * @param evalCategory Selected Eval Category
     * @return Matching Product2 records ordered by ProductCode
     */
    public static List<Product2> selectForInstrumentEvaluationByEvalCategory(
        String productLine,
        String subProductLine,
        String evalCategory
    ) {
        if (String.isBlank(productLine) || String.isBlank(evalCategory)) {
            return new List<Product2>();
        }
        List<Product2> candidates = [
            SELECT
                Id,
                Name,
                ProductCode,
                EvalCategory__c,
                EvalRank__c,
                ProductLine__c,
                SubProductLine__c
            FROM Product2
            WHERE ProductType__c = :INSTRUMENT_EVALUATION_PRODUCT_TYPE
                AND EvalDisplayScreen__c = :EVAL_DISPLAY_YES
                AND IsActive = true
                AND EvalCategory__c != null
            ORDER BY ProductCode ASC
        ];
        return filterInstrumentEvaluationProducts(
            candidates,
            productLine,
            subProductLine,
            evalCategory
        );
    }

    private static List<Product2> filterInstrumentEvaluationProducts(
        List<Product2> candidates,
        String productLine,
        String subProductLine,
        String evalCategory
    ) {
        List<Product2> matched = new List<Product2>();
        Boolean filterSubProductLine = String.isNotBlank(subProductLine);
        Boolean filterEvalCategory = String.isNotBlank(evalCategory);
        for (Product2 product : candidates) {
            if (product == null) {
                continue;
            }
            if (!matchesInstrumentProductLine(product.ProductLine__c, productLine)) {
                continue;
            }
            if (
                filterSubProductLine &&
                !equalsIgnoreCaseTrimmed(product.SubProductLine__c, subProductLine)
            ) {
                continue;
            }
            if (
                filterEvalCategory &&
                !equalsIgnoreCaseTrimmed(product.EvalCategory__c, evalCategory)
            ) {
                continue;
            }
            matched.add(product);
        }
        return matched;
    }

    /**
     * @description GW-5333 - Selects Products used by Approve/Reject Quote inspection and disinfection rules.
     * @param productIds Product2 Ids
     * @return Matching Product2 rows
     */
    public static List<Product2> selectForApproveRejectByIds(Set<Id> productIds) {
        if (productIds == null || productIds.isEmpty()) {
            return new List<Product2>();
        }

        return (List<Product2>) SoqlQueryBuilder.fromObject('Product2')
            .selectFields(
                new List<String>{
                    'Id',
                    'Name',
                    'ProductCode',
                    'Description',
                    'ProductType__c',
                    'ProductLine__c',
                    'Model__c',
                    'ServiceCodeType__c',
                    'InspectionFeeApplicable__c',
                    'InspectionServiceCode__c'
                }
            )
            .whereField('Id', 'IN', new List<Id>(productIds))
            .execute();
    }

    /**
     * @description Case-insensitive Product Line match; trailing plural "s" is ignored so
     *              Instruments matches INSTRUMENT.
     */
    private static Boolean matchesInstrumentProductLine(String actual, String expected) {
        if (String.isBlank(actual) || String.isBlank(expected)) {
            return false;
        }
        String left = normalizeInstrumentProductLine(actual);
        String right = normalizeInstrumentProductLine(expected);
        return left == right;
    }

    private static String normalizeInstrumentProductLine(String value) {
        String normalized = value == null ? '' : value.trim().toLowerCase();
        return normalized.removeEnd('s');
    }

    private static Boolean equalsIgnoreCaseTrimmed(String left, String right) {
        if (left == null || right == null) {
            return false;
        }
        return left.trim().equalsIgnoreCase(right.trim());
    }

    /**
     * @description GW-5102 - Products for quote email reply (inspection fee / disinfection).
     * @param productIds Product2 Ids
     * @return Matching Product2 records
     */
    public static List<Product2> selectForQuoteEmailReplyByIds(Set<Id> productIds) {
        if (productIds == null || productIds.isEmpty()) {
            return new List<Product2>();
        }

        return (List<Product2>) SoqlQueryBuilder.fromObject('Product2')
            .selectFields(
                new List<String>{
                    'Id',
                    'Name',
                    'ProductCode',
                    'Description',
                    'ProductType__c',
                    'Model__c',
                    'ServiceCodeType__c',
                    'InspectionFeeApplicable__c',
                    'InspectionServiceCode__c'
                }
            )
            .whereField('Id', 'IN', new List<Id>(productIds))
            .execute();
    }

    private static final List<String> CREATE_RETURN_ORDER_DEFAULT_FIELDS = new List<String>{
        'Id',
        'Name',
        'Description',
        'ProductLine__c',
        'ProductCode',
        'Model__c'
    };

    private static final List<String> CREATE_RETURN_ORDER_DETAIL_FIELDS = new List<String>{
        'Id',
        'Name',
        'Description',
        'ProductLine__c',
        'ProductType__c',
        'ProductCode',
        'Model__c',
        'Manufacturer__c'
    };

    private static final List<String> CREATE_RETURN_ORDER_PICKLIST_FIELDS = new List<String>{
        'Id',
        'Name',
        'ProductCode',
        'Model__c',
        'Description',
        'DeviceType__c'
    };

    private static final List<String> CREATE_RETURN_ORDER_ROUTING_FIELDS = new List<String>{
        'Id',
        'ProductLine__c',
        'SubProductLine__c',
        'Manufacturer__c',
        'DeviceType__c',
        'Model__c'
    };

    /**
     * @description GW-1509 - Oldest active Product2 matching the default Create Return Order name.
     * @param productName Exact Product2.Name
     * @return Matching Product2 rows (LIMIT 1)
     */
    public static List<Product2> selectDefaultActiveByName(String productName) {
        if (String.isBlank(productName)) {
            return new List<Product2>();
        }
        return (List<Product2>) SoqlQueryBuilder.fromObject('Product2')
            .selectFields(CREATE_RETURN_ORDER_DEFAULT_FIELDS)
            .whereEquals('Name', productName)
            .whereEquals('IsActive', true)
            .orderBy('CreatedDate')
            .limitTo(1)
            .execute();
    }

    /**
     * @description GW-1509 - Active Product2 details for Create Return Order, optionally Service Asset only.
     * @param productId Product2 Id
     * @param requireServiceAsset When true, ProductType__c must be Service Asset
     * @return Matching Product2 rows (LIMIT 1)
     */
    public static List<Product2> selectActiveDetailsForCreateReturnOrder(
        Id productId,
        Boolean requireServiceAsset
    ) {
        if (productId == null) {
            return new List<Product2>();
        }
        SoqlQueryBuilder builder = SoqlQueryBuilder.fromObject('Product2')
            .selectFields(CREATE_RETURN_ORDER_DETAIL_FIELDS)
            .whereEquals('Id', productId)
            .whereEquals('IsActive', true);
        if (requireServiceAsset == true) {
            builder.whereEquals('ProductType__c', 'Service Asset');
        }
        return (List<Product2>) builder.limitTo(1).execute();
    }

    /**
     * @description GW-1509 - Active products for Create Return Order line picklists.
     * @param productLine Optional ProductLine__c filter
     * @param requireServiceAsset When true, ProductType__c must be Service Asset
     * @param searchLikeTerm Optional LIKE term including wildcards
     * @param queryLimit Max rows
     * @return Matching Product2 rows ordered by Name
     */
    public static List<Product2> selectForCreateReturnOrderLine(
        String productLine,
        Boolean requireServiceAsset,
        String searchLikeTerm,
        Integer queryLimit
    ) {
        SoqlQueryBuilder builder = SoqlQueryBuilder.fromObject('Product2')
            .selectFields(CREATE_RETURN_ORDER_PICKLIST_FIELDS)
            .whereEquals('IsActive', true);

        List<String> logicParts = new List<String>{ '1' };
        Integer filterIndex = 1;

        if (requireServiceAsset == true) {
            filterIndex++;
            builder.whereEquals('ProductType__c', 'Service Asset');
            logicParts.add(String.valueOf(filterIndex));
        }
        if (String.isNotBlank(productLine)) {
            filterIndex++;
            builder.whereEquals('ProductLine__c', productLine);
            logicParts.add(String.valueOf(filterIndex));
        }
        if (String.isNotBlank(searchLikeTerm)) {
            Integer nameIdx = filterIndex + 1;
            Integer codeIdx = filterIndex + 2;
            Integer modelIdx = filterIndex + 3;
            builder
                .whereField('Name', 'LIKE', searchLikeTerm)
                .whereField('ProductCode', 'LIKE', searchLikeTerm)
                .whereField('Model__c', 'LIKE', searchLikeTerm);
            logicParts.add('(' + nameIdx + ' OR ' + codeIdx + ' OR ' + modelIdx + ')');
        }

        if (logicParts.size() > 1) {
            builder.withFilterLogic(String.join(logicParts, ' AND '));
        }

        Integer limitRows = (queryLimit == null || queryLimit <= 0) ? 200 : queryLimit;
        return (List<Product2>) builder.orderBy('Name').limitTo(limitRows).execute();
    }

    /**
     * @description GW-1509 - Product routing attributes for Create Return Order grouping.
     * @param productIds Product2 Ids
     * @return Matching Product2 rows
     */
    public static List<Product2> selectForCreateReturnOrderRouting(Set<Id> productIds) {
        if (productIds == null || productIds.isEmpty()) {
            return new List<Product2>();
        }
        return (List<Product2>) SoqlQueryBuilder.fromObject('Product2')
            .selectFields(CREATE_RETURN_ORDER_ROUTING_FIELDS)
            .whereField('Id', 'IN', new List<Id>(productIds))
            .execute();
    }

    /**
     * @description GW-5981 - Product fields for a Repair Center parts request.
     * @param productIds Product2 Ids
     * @return Matching products
     */
    public static List<Product2> selectForRepairPartsRequest(Set<Id> productIds) {
        if (productIds == null || productIds.isEmpty()) {
            return new List<Product2>();
        }
        return (List<Product2>) SoqlQueryBuilder.fromObject('Product2')
            .selectFields(
                new List<String>{
                    'Id',
                    'Name',
                    'ProductCode',
                    'Description',
                    'IsActive',
                    'QuantityUnitOfMeasure'
                }
            )
            .whereField('Id', 'IN', new List<Id>(productIds))
            .execute();
    }

    /**
     * @description GW-5981 - Products with an exact Product Code, active records first.
     * @param productCode Scanned or typed item number
     * @return Matching products
     */
    public static List<Product2> selectByExactProductCode(String productCode) {
        if (String.isBlank(productCode)) {
            return new List<Product2>();
        }
        return (List<Product2>) SoqlQueryBuilder.fromObject('Product2')
            .selectFields(
                new List<String>{
                    'Id',
                    'Name',
                    'ProductCode',
                    'Description',
                    'IsActive',
                    'QuantityUnitOfMeasure'
                }
            )
            .whereEquals('ProductCode', productCode)
            .orderByDesc('IsActive')
            .limitTo(20)
            .execute();
    }

}