/**
 * @description Service class for CaseRoutingRule__c - handles business orchestration and transaction management
 * @author Agentforce
 * @date 2026-04-27
 * @group Services
 */
public with sharing class CaseRoutingRulesService {

    // Cache patterns to save CPU time during bulk processing
    private static Map<String, Pattern> patternCache = new Map<String, Pattern>();

    private static final String MASTER_RECORD_TYPE_CACHE_KEY = 'MASTER';
    private static final String CASE_OBJECT_API_NAME = 'Case';
    private static final String CASE_FIELD_CATEGORY = 'Category__c';
    private static final String CASE_FIELD_SUB_CATEGORY = 'SubCategory__c';
    private static final String CASE_FIELD_CLOSE_REASON = 'CloseReason__c';

    private static Map<String, CasePicklistRoutingMaps> dependencyMapsByRecordTypeKey = new Map<String, CasePicklistRoutingMaps>();

    /**
     * GW-1279 test seam — fixed dependency maps for @IsTest (see setDependencyMapsForTests).
     * Not used in production.
     */
    private static CasePicklistRoutingMaps testDependencyMapsOverride;

    /**
     * @description GW-1279 - Returns a compiled whole-word, case-insensitive Pattern for the search string (literal
     *              via Pattern.quote). Patterns are cached per Apex transaction for bulk routing.
     * @param searchString Substring to match as a whole word; null or blank returns null
     * @return Cached or newly compiled Pattern, or null when searchString is blank
     */
    public static Pattern getPattern(String searchString) {
        if (String.isBlank(searchString)) {
            return null;
        }
        if (!patternCache.containsKey(searchString)) {
            // (?i) = Case Insensitive
            // (?<!\w) = Only match if NOT preceded by a word character
            // (?!\w) = Only match if NOT followed by a word character
            String escaped = Pattern.quote(searchString);
            String regex = '(?i)(?<!\\w)' + escaped + '(?!\\w)';
            patternCache.put(searchString, Pattern.compile(regex));
        }
        return patternCache.get(searchString);
    }

    /**
     * @description Sanitized Case picklist API values to apply from a matched routing rule (null = leave Case field
     *              unchanged for that slot).
     */
    public class RoutingStampFieldValues {
        /** Case.Category__c API value when valid for Case.Origin (and record type); otherwise null. */
        public final String categoryApiValue;
        /** Case.SubCategory__c API value when valid for stamped Category; otherwise null. */
        public final String subCategoryApiValue;
        /** Case.CloseReason__c API value when valid for stamped Category; otherwise null. */
        public final String closeReasonApiValue;

        private RoutingStampFieldValues(String categoryApiValue, String subCategoryApiValue, String closeReasonApiValue) {
            this.categoryApiValue = categoryApiValue;
            this.subCategoryApiValue = subCategoryApiValue;
            this.closeReasonApiValue = closeReasonApiValue;
        }
    }

    /**
     * @description GW-1279 - Validates routing rule picklist stamps against Case dependent picklists. Omits values
     *              that would violate Origin → Category, Category → SubCategory, or Category → CloseReason. Dependency
     *              maps are loaded via ConnectApi in production (see loadDependencyMapsFromConnectApi), cached once per
     *              transaction per record type key.
     * @param caseRow Case context (Origin, RecordTypeId for picklist describe scope).
     * @param rule Matched routing rule (CategoryValue__c, SubCategoryValue__c, CloseCode__c).
     * @return RoutingStampFieldValues with null members where the rule value must not be applied.
     */
    public static RoutingStampFieldValues resolveStampableRoutingFieldValues(Case caseRow, CaseRoutingRule__c rule) {
        if (rule == null) {
            return new RoutingStampFieldValues(null, null, null);
        }

        Id recordTypeId = caseRow == null ? null : caseRow.RecordTypeId;
        CasePicklistRoutingMaps maps = getOrBuildDependencyMaps(recordTypeId);
        String origin = caseRow == null ? null : caseRow.Origin;

        String stampedCategory = null;
        String ruleCategory = String.isBlank(rule.CategoryValue__c) ? null : rule.CategoryValue__c.trim();
        if (ruleCategory != null && maps.isCategoryAllowedForOrigin(origin, ruleCategory)) {
            stampedCategory = ruleCategory;
        }

        String stampedSub = null;
        if (stampedCategory != null) {
            String ruleSub = String.isBlank(rule.SubCategoryValue__c) ? null : rule.SubCategoryValue__c.trim();
            if (ruleSub != null && maps.isSubCategoryAllowedForCategory(stampedCategory, ruleSub)) {
                stampedSub = ruleSub;
            }
        }

        String stampedClose = null;
        if (stampedCategory != null) {
            String ruleClose = String.isBlank(rule.CloseCode__c) ? null : rule.CloseCode__c.trim();
            if (ruleClose != null && maps.isCloseReasonAllowedForCategory(stampedCategory, ruleClose)) {
                stampedClose = ruleClose;
            }
        }

        return new RoutingStampFieldValues(stampedCategory, stampedSub, stampedClose);
    }

    /**
     * @description GW-1279 test seam — supplies in-memory picklist dependency maps for unit tests.
     *              Production loads maps via ConnectApi.RecordUi.getPicklistValuesByRecordType. That API is not
     *              available in data-siloed @IsTest runs (ConnectApi throws), which would leave maps empty and make
     *              resolveStampableRoutingFieldValues untestable. The practical alternative was @IsTest(SeeAllData=true)
     *              on routing tests, which this project avoids for pipeline and isolation reasons. Injecting fixed maps
     *              keeps production on ConnectApi while tests assert real validation logic without SeeAllData.
     * @param maps Pre-built CasePicklistRoutingMaps (e.g. from CaseRoutingRulesServiceTest.buildOrgAlignedGw1279Maps)
     */
    @TestVisible
    private static void setDependencyMapsForTests(CasePicklistRoutingMaps maps) {
        testDependencyMapsOverride = maps;
        dependencyMapsByRecordTypeKey.clear();
    }

    /**
     * @description GW-1279 test seam — clears injected maps and per-transaction cache so tests do not leak state.
     */
    @TestVisible
    private static void resetDependencyMapsForTests() {
        testDependencyMapsOverride = null;
        dependencyMapsByRecordTypeKey.clear();
    }

    private static CasePicklistRoutingMaps getOrBuildDependencyMaps(Id recordTypeId) {
        if (testDependencyMapsOverride != null) {
            return testDependencyMapsOverride;
        }
        String cacheKey = recordTypeId == null ? MASTER_RECORD_TYPE_CACHE_KEY : String.valueOf(recordTypeId);
        if (!dependencyMapsByRecordTypeKey.containsKey(cacheKey)) {
            dependencyMapsByRecordTypeKey.put(cacheKey, loadDependencyMapsFromConnectApi(recordTypeId));
        }
        return dependencyMapsByRecordTypeKey.get(cacheKey);
    }

    /**
     * @description GW-1279 - Loads Case dependent picklist maps via ConnectApi for the given record type scope.
     * @param caseRecordTypeId Case.RecordTypeId from routing context, or null for master scope
     * @return Routing maps, or empty maps when ConnectApi cannot be used
     */
    private static CasePicklistRoutingMaps loadDependencyMapsFromConnectApi(Id caseRecordTypeId) {
        Id connectApiRecordTypeId = resolveRecordTypeIdForConnectApi(caseRecordTypeId);
        try {
            ConnectApi.PicklistValuesCollection picklistValuesCollection =
                ConnectApi.RecordUi.getPicklistValuesByRecordType(
                    CASE_OBJECT_API_NAME,
                    String.valueOf(connectApiRecordTypeId)
                );
            return buildPicklistRoutingMapsFromCollection(picklistValuesCollection);
        } catch (Exception e) {
            Logger.error(
                new LogMessage(
                    'Failed to load Case picklist values via ConnectApi for record type {0}: {1}',
                    connectApiRecordTypeId,
                    e.getMessage()
                ),
                e
            );
            return buildEmptyPicklistRoutingMaps();
        }
    }

    @TestVisible
    private static CasePicklistRoutingMaps buildEmptyPicklistRoutingMapsForTests() {
        return buildEmptyPicklistRoutingMaps();
    }

    @TestVisible
    private static CasePicklistRoutingMaps buildPicklistRoutingMapsFromCollectionForTests(
        ConnectApi.PicklistValuesCollection picklistValuesCollection
    ) {
        return buildPicklistRoutingMapsFromCollection(picklistValuesCollection);
    }

    private static CasePicklistRoutingMaps buildEmptyPicklistRoutingMaps() {
        return new CasePicklistRoutingMaps(
            true,
            true,
            true,
            new Map<String, Set<String>>(),
            new Map<String, Set<String>>(),
            new Map<String, Set<String>>(),
            new Set<String>(),
            new Set<String>(),
            new Set<String>()
        );
    }

    private static CasePicklistRoutingMaps buildPicklistRoutingMapsFromCollection(
        ConnectApi.PicklistValuesCollection picklistValuesCollection
    ) {
        ConnectApi.PicklistValues categoryPicklist = getConnectApiPicklistValues(
            picklistValuesCollection,
            CASE_FIELD_CATEGORY
        );
        ConnectApi.PicklistValues subCategoryPicklist = getConnectApiPicklistValues(
            picklistValuesCollection,
            CASE_FIELD_SUB_CATEGORY
        );
        ConnectApi.PicklistValues closeReasonPicklist = getConnectApiPicklistValues(
            picklistValuesCollection,
            CASE_FIELD_CLOSE_REASON
        );

        Boolean categoryDependsOnOrigin = hasConnectApiPicklistDependency(categoryPicklist);
        Boolean subCategoryDependsOnCategory = hasConnectApiPicklistDependency(subCategoryPicklist);
        Boolean closeReasonDependsOnCategory = hasConnectApiPicklistDependency(closeReasonPicklist);

        Map<String, Set<String>> originToCategories = categoryDependsOnOrigin
            ? buildControllerToDependentPicklistValues(categoryPicklist)
            : new Map<String, Set<String>>();
        Map<String, Set<String>> categoryToSubCategories = subCategoryDependsOnCategory
            ? buildControllerToDependentPicklistValues(subCategoryPicklist)
            : new Map<String, Set<String>>();
        Map<String, Set<String>> categoryToCloseReasons = closeReasonDependsOnCategory
            ? buildControllerToDependentPicklistValues(closeReasonPicklist)
            : new Map<String, Set<String>>();

        return new CasePicklistRoutingMaps(
            categoryDependsOnOrigin,
            subCategoryDependsOnCategory,
            closeReasonDependsOnCategory,
            originToCategories,
            categoryToSubCategories,
            categoryToCloseReasons,
            collectConnectApiActivePicklistValues(categoryPicklist),
            collectConnectApiActivePicklistValues(subCategoryPicklist),
            collectConnectApiActivePicklistValues(closeReasonPicklist)
        );
    }

    private static ConnectApi.PicklistValues getConnectApiPicklistValues(
        ConnectApi.PicklistValuesCollection picklistValuesCollection,
        String fieldApiName
    ) {
        if (picklistValuesCollection == null || picklistValuesCollection.picklistFieldValues == null) {
            return null;
        }
        return picklistValuesCollection.picklistFieldValues.get(fieldApiName);
    }

    private static Boolean hasConnectApiPicklistDependency(ConnectApi.PicklistValues picklistValues) {
        return picklistValues != null
            && picklistValues.controllerValues != null
            && !picklistValues.controllerValues.isEmpty();
    }

    private static Boolean isConnectApiPicklistValueActive(ConnectApi.PicklistValue picklistValue) {
        return picklistValue != null && String.isNotBlank(picklistValue.value);
    }

    private static Set<String> collectConnectApiActivePicklistValues(ConnectApi.PicklistValues picklistValues) {
        Set<String> activeValues = new Set<String>();
        if (picklistValues == null || picklistValues.values == null) {
            return activeValues;
        }
        for (ConnectApi.PicklistValue picklistValue : picklistValues.values) {
            if (isConnectApiPicklistValueActive(picklistValue) && String.isNotBlank(picklistValue.value)) {
                activeValues.add(picklistValue.value);
            }
        }
        return activeValues;
    }

    private static Map<String, Set<String>> buildControllerToDependentPicklistValues(
        ConnectApi.PicklistValues picklistValues
    ) {
        Map<String, Set<String>> result = new Map<String, Set<String>>();
        if (picklistValues == null) {
            return result;
        }
        Map<Integer, String> controllerIndexToApiValue = new Map<Integer, String>();
        if (picklistValues.controllerValues != null) {
            for (String controllerApiValue : picklistValues.controllerValues.keySet()) {
                result.put(controllerApiValue, new Set<String>());
                Integer controllerIndex = picklistValues.controllerValues.get(controllerApiValue);
                if (controllerIndex != null) {
                    controllerIndexToApiValue.put(controllerIndex, controllerApiValue);
                }
            }
        }
        if (picklistValues.values == null) {
            return result;
        }
        for (ConnectApi.PicklistValue picklistValue : picklistValues.values) {
            if (!isConnectApiPicklistValueActive(picklistValue) || String.isBlank(picklistValue.value)) {
                continue;
            }
            if (picklistValue.validFor == null || picklistValue.validFor.isEmpty()) {
                continue;
            }
            for (Integer controllerIndex : picklistValue.validFor) {
                String controllerApiValue = controllerIndexToApiValue.get(controllerIndex);
                if (String.isBlank(controllerApiValue)) {
                    continue;
                }
                if (!result.containsKey(controllerApiValue)) {
                    result.put(controllerApiValue, new Set<String>());
                }
                result.get(controllerApiValue).add(picklistValue.value);
            }
        }
        return result;
    }

    /**
     * @description Resolves record type Id for ConnectApi picklist describe (master when Case has no record type).
     */
    @TestVisible
    private static Id resolveRecordTypeIdForConnectApi(Id recordTypeId) {
        if (recordTypeId != null) {
            return recordTypeId;
        }
        for (Schema.RecordTypeInfo recordTypeInfo : Case.SObjectType.getDescribe().getRecordTypeInfos()) {
            if (recordTypeInfo.isMaster()) {
                return recordTypeInfo.getRecordTypeId();
            }
        }
        for (Schema.RecordTypeInfo recordTypeInfo : Case.SObjectType.getDescribe().getRecordTypeInfos()) {
            if (recordTypeInfo.isActive() && recordTypeInfo.isAvailable()) {
                return recordTypeInfo.getRecordTypeId();
            }
        }
        return null;
    }

    /**
     * @description GW-1279 - Retrieves active CaseRoutingRule__c rows whose CaseAssignment__c matches any of the
     *              given Case Origin values. Delegates to CaseRoutingRulesSelector.selectActiveCRRsByAssignment.
     * @param caseAssignments Distinct Case.Origin / Case Assignment API values from candidate Cases
     * @return Active rules ordered by priority (empty when none or when input is null/empty)
     */
    public static List<CaseRoutingRule__c> getActiveRulesForCaseAssignments(Set<String> caseAssignments) {
        if (caseAssignments == null || caseAssignments.isEmpty()) {
            Logger.fine('CaseRoutingRulesService.getActiveRulesForCaseAssignments called with null or empty set.');
            return new List<CaseRoutingRule__c>();
        }

        try {
            Logger.fine(
                new LogMessage(
                    'Retrieving active CaseRoutingRule__c for {0} case assignment value(s)',
                    caseAssignments.size()
                )
            );
            List<CaseRoutingRule__c> rules = CaseRoutingRulesSelector.selectActiveCRRsByAssignment(caseAssignments);
            Logger.fine(new LogMessage('Retrieved {0} active CaseRoutingRule__c record(s) for assignments', rules.size()));
            return rules;
        } catch (Exception e) {
            Logger.error(new LogMessage('Failed to retrieve routing rules by assignment: {0}', e.getMessage()), e);
            throw new CaseRoutingRulesServiceException(
                'Failed to retrieve routing rules by case assignment: ' + e.getMessage(),
                e
            );
        }
    }

    /**
     * @description Retrieves all active routing rules ordered by priority
     * @return List of active CaseRoutingRule__c records
     */
    public static List<CaseRoutingRule__c> getActiveRules() {
        try {
            Logger.info('Retrieving active CaseRoutingRule__c records');
            List<CaseRoutingRule__c> activeRules = CaseRoutingRulesSelector.selectActiveRules();
            Logger.info(new LogMessage('Retrieved {0} active CaseRoutingRule__c records', activeRules.size()));
            return activeRules;
        } catch (Exception e) {
            Logger.error(new LogMessage('Failed to retrieve active routing rules: {0}', e.getMessage()), e);
            throw new CaseRoutingRulesServiceException('Failed to retrieve active routing rules: ' + e.getMessage(), e);
        }
    }

    /**
     * @description GW-1279 - In-memory Case dependent picklist maps for routing stamp validation.
     */
    public class CasePicklistRoutingMaps {
        private final Boolean categoryDependsOnOrigin;
        private final Boolean subCategoryDependsOnCategory;
        private final Boolean closeReasonDependsOnCategory;
        private final Map<String, Set<String>> originToCategories;
        private final Map<String, Set<String>> categoryToSubCategories;
        private final Map<String, Set<String>> categoryToCloseReasons;
        private final Set<String> allActiveCategories;
        private final Set<String> allActiveSubCategories;
        private final Set<String> allActiveCloseReasons;

        public CasePicklistRoutingMaps(
            Boolean categoryDependsOnOrigin,
            Boolean subCategoryDependsOnCategory,
            Boolean closeReasonDependsOnCategory,
            Map<String, Set<String>> originToCategories,
            Map<String, Set<String>> categoryToSubCategories,
            Map<String, Set<String>> categoryToCloseReasons,
            Set<String> allActiveCategories,
            Set<String> allActiveSubCategories,
            Set<String> allActiveCloseReasons
        ) {
            this.categoryDependsOnOrigin = categoryDependsOnOrigin;
            this.subCategoryDependsOnCategory = subCategoryDependsOnCategory;
            this.closeReasonDependsOnCategory = closeReasonDependsOnCategory;
            this.originToCategories = originToCategories == null ? new Map<String, Set<String>>() : originToCategories;
            this.categoryToSubCategories =
                categoryToSubCategories == null ? new Map<String, Set<String>>() : categoryToSubCategories;
            this.categoryToCloseReasons =
                categoryToCloseReasons == null ? new Map<String, Set<String>>() : categoryToCloseReasons;
            this.allActiveCategories = allActiveCategories == null ? new Set<String>() : allActiveCategories;
            this.allActiveSubCategories = allActiveSubCategories == null ? new Set<String>() : allActiveSubCategories;
            this.allActiveCloseReasons = allActiveCloseReasons == null ? new Set<String>() : allActiveCloseReasons;
        }

        public Boolean isCategoryAllowedForOrigin(String origin, String categoryApi) {
            if (String.isBlank(categoryApi)) {
                return false;
            }
            if (!categoryDependsOnOrigin) {
                return allActiveCategories.contains(categoryApi);
            }
            if (String.isBlank(origin)) {
                return false;
            }
            Set<String> allowed = originToCategories.get(origin);
            return allowed != null && allowed.contains(categoryApi);
        }

        public Boolean isSubCategoryAllowedForCategory(String categoryApi, String subCategoryApi) {
            if (String.isBlank(subCategoryApi)) {
                return false;
            }
            if (!subCategoryDependsOnCategory) {
                return allActiveSubCategories.contains(subCategoryApi);
            }
            Set<String> allowed = categoryToSubCategories.get(categoryApi);
            return allowed != null && allowed.contains(subCategoryApi);
        }

        public Boolean isCloseReasonAllowedForCategory(String categoryApi, String closeReasonApi) {
            if (String.isBlank(closeReasonApi)) {
                return false;
            }
            if (!closeReasonDependsOnCategory) {
                return allActiveCloseReasons.contains(closeReasonApi);
            }
            Set<String> allowed = categoryToCloseReasons.get(categoryApi);
            return allowed != null && allowed.contains(closeReasonApi);
        }
    }

    /**
     * @description Custom exception class for CaseRoutingRulesService
     */
    public class CaseRoutingRulesServiceException extends Exception {}
}