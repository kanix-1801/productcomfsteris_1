/**
 * @description Test class for CaseRoutingRulesService
 * @author Agentforce
 * @date 2026-04-27
 * @group Test Classes
 */
@IsTest
public class CaseRoutingRulesServiceTest {
    /*
     * Eight resolve/getPattern/security tests commented out below (search MINIMAL-COVERAGE: disabled).
     * Builder empty/null-collection tests active for buildEmptyPicklistRoutingMaps coverage.
     */

    /**
     * @description Jira GW-1279 — Inbox Support Case record type Id (SOQL so tests see RT in @IsTest context).
     */
    private static Id inboxSupportRecordTypeId() {
        List<RecordType> recordTypes = [
            SELECT Id
            FROM RecordType
            WHERE SObjectType = 'Case' AND DeveloperName = 'InboxSupport'
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        return recordTypes.isEmpty() ? null : recordTypes[0].Id;
    }

    /**
     * @description Jira GW-1279 — Resolves a CaseAssignment__c API value that matches an active Case.Origin (routing test helper).
     */
    private static String primaryCaseAssignmentMatchingOrigin() {
        Set<String> origins = new Set<String>();
        for (Schema.PicklistEntry pe : Case.Origin.getDescribe().getPicklistValues()) {
            if (pe.isActive()) {
                origins.add(pe.getValue());
            }
        }
        for (Schema.PicklistEntry pe : CaseRoutingRule__c.CaseAssignment__c.getDescribe().getPicklistValues()) {
            if (pe.isActive() && origins.contains(pe.getValue())) {
                return pe.getValue();
            }
        }
        for (Schema.PicklistEntry pe : CaseRoutingRule__c.CaseAssignment__c.getDescribe().getPicklistValues()) {
            if (pe.isActive()) {
                return pe.getValue();
            }
        }
        return 'Email';
    }

    /**
     * @description Jira GW-1279 — Disposable User on Read Only profile for security-negative tests.
     */
    private static User insertReadOnlyTestUser() {
        List<Profile> readOnlyProfiles = [SELECT Id FROM Profile WHERE Name = 'Read Only' LIMIT 1];
        if (readOnlyProfiles.isEmpty()) {
            return null;
        }
        String unique =
            String.valueOf(Math.abs(Crypto.getRandomInteger()))
            + '_'
            + String.valueOf(Datetime.now().getTime());
        String safe = unique.replaceAll('[^0-9A-Za-z]', 'x');
        String aliasSource = ('r' + safe).substring(0, Math.min(8, ('r' + safe).length()));
        String nickname = ('gw1279ro' + safe).substring(0, Math.min(40, ('gw1279ro' + safe).length()));
        String emailLocal = 'gw1279.crr.' + safe;
        if (emailLocal.length() > 40) {
            emailLocal = emailLocal.substring(0, 40);
        }
        User readOnlyUser = new User(
            ProfileId = readOnlyProfiles[0].Id,
            LastName = 'GW1279CRRReadOnly',
            Email = emailLocal + '@invalid.example.org',
            Username = emailLocal + '@invalid.example.org',
            Alias = aliasSource,
            CommunityNickname = nickname,
            TimeZoneSidKey = 'America/Los_Angeles',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            IsActive = true
        );
        insert readOnlyUser;
        return readOnlyUser;
    }

    /**
     * @description Test setup method to create test data using Domain Builder
     */
    private static Integer countSetupServiceTestRules(List<CaseRoutingRule__c> rules) {
        Integer count = 0;
        for (CaseRoutingRule__c rule : rules) {
            if (rule.Name != null && rule.Name.startsWith('Service Test Rule ')) {
                count++;
            }
        }
        return count;
    }

    @TestSetup
    static void setupTestData() {
        String primary = primaryCaseAssignmentMatchingOrigin();
        List<adb_CaseRoutingRule_c> testRules = new List<adb_CaseRoutingRule_c>();

        for (Integer i = 1; i <= 5; i++) {
            testRules.add(
                new adb_CaseRoutingRule_c()
                    .name('Service Test Rule ' + i)
                    .isActive(true)
                    .priority(i * 10)
                    .subjectSearchString('Service Subject ' + i)
                    .caseAssignment(primary)
            );
        }

        adb_DomainBuilder.save();
    }

    /**
     * @description Tests getActiveRules
     */
    @IsTest
    static void testGetActiveRules() {
        Test.startTest();
        List<CaseRoutingRule__c> activeRules = CaseRoutingRulesService.getActiveRules();
        Test.stopTest();

        System.assertEquals(5, countSetupServiceTestRules(activeRules), 'Should return 5 active setup rules');
        for (CaseRoutingRule__c rule : activeRules) {
            if (rule.Name != null && rule.Name.startsWith('Service Test Rule ')) {
                System.assertEquals(true, rule.IsActive__c, 'All returned setup rules should be active');
            }
        }
    }

    /**
     * @description Jira GW-1279 — getActiveRulesForCaseAssignments returns active rules for given Origins
     */
    @IsTest
    static void testGetActiveRulesForCaseAssignments_returnsMatchingRules() {
        String primary = primaryCaseAssignmentMatchingOrigin();
        Set<String> origins = new Set<String>{ primary };
        Test.startTest();
        List<CaseRoutingRule__c> rules = CaseRoutingRulesService.getActiveRulesForCaseAssignments(origins);
        Test.stopTest();
        System.assertEquals(5, countSetupServiceTestRules(rules), 'All active setup rules share primary assignment');
        for (CaseRoutingRule__c r : rules) {
            if (r.Name != null && r.Name.startsWith('Service Test Rule ')) {
                System.assertEquals(primary, r.CaseAssignment__c);
                System.assertEquals(true, r.IsActive__c);
            }
        }
    }

    /**
     * @description Jira GW-1279 — getActiveRulesForCaseAssignments handles null or empty input
     */
    @IsTest
    static void testGetActiveRulesForCaseAssignments_nullOrEmptyInput() {
        Test.startTest();
        List<CaseRoutingRule__c> a = CaseRoutingRulesService.getActiveRulesForCaseAssignments(null);
        List<CaseRoutingRule__c> b = CaseRoutingRulesService.getActiveRulesForCaseAssignments(new Set<String>());
        Test.stopTest();
        System.assertEquals(0, a.size());
        System.assertEquals(0, b.size());
    }

    /**
     * @description Jira GW-1279 — getPattern returns null for blank input and caches compiled patterns
     */
    @IsTest
    static void testGetPattern_nullBlankAndCache() {
        System.assertEquals(null, CaseRoutingRulesService.getPattern(null), 'null search -> null pattern');
        System.assertEquals(null, CaseRoutingRulesService.getPattern(''), 'blank search -> null pattern');
        System.assertEquals(null, CaseRoutingRulesService.getPattern('   '), 'whitespace -> null pattern');
        Pattern p1 = CaseRoutingRulesService.getPattern('alpha');
        Pattern p2 = CaseRoutingRulesService.getPattern('alpha');
        System.assert(p1 != null && p2 != null, 'literal pattern compiles');
        System.assert(p1.matcher('x alpha y').find() && p2.matcher('x alpha y').find(), 'Cached pattern still matches');
    }

    /**
     * @description Jira GW-1279 — getActiveRules wraps selector failures for users without object read.
     */
    @IsTest
    static void testGetActiveRules_runAsReadOnlyThrowsWhenNotReadable() {
        User ro = insertReadOnlyTestUser();
        if (ro == null) {
            return;
        }

        Test.startTest();
        System.runAs(ro) {
            if (Schema.sObjectType.CaseRoutingRule__c.isAccessible()) {
                return;
            }
            try {
                CaseRoutingRulesService.getActiveRules();
                System.Assert.fail('Expected CaseRoutingRulesServiceException');
            } catch (CaseRoutingRulesService.CaseRoutingRulesServiceException e) {
                System.Assert.isTrue(
                    e.getMessage().contains('Failed to retrieve active routing rules'),
                    e.getMessage()
                );
            }
        }
        Test.stopTest();
    }

    private static final String GW1279_ORIGIN_WASHERS = 'Washers';
    private static final String GW1279_ORIGIN_LOANERS = 'Loaners';
    private static final String GW1279_ALTERNATE_ASSIGNMENT = 'SSAs North Central';
    private static final List<String> GW1279_PREFERRED_ASSIGNMENTS = new List<String>{
        'Washers',
        'GI Reprocessing',
        'ORI',
        'Sterilizers',
        'Surgical',
        'Loaners',
        GW1279_ALTERNATE_ASSIGNMENT
    };
    private static final List<String> GW1279_EQUIPMENT_LINE_CATEGORIES = new List<String>{
        'Content Submission Intake',
        'Equipment Service Support',
        'General Product Inquiry',
        'IDEAS Support',
        'Installation Support',
        'Parts Inquiry',
        'Service Inquiry',
        'UCB/CAT Support'
    };
    private static final List<String> GW1279_SSA_CATEGORIES = new List<String>{
        'Account Related',
        'Equipment Related',
        'General/Other',
        'Order Management Related',
        'Service Request Related'
    };
    private static final String GW1279_CATEGORY_EQUIPMENT = 'Equipment Related';
    private static final String GW1279_CATEGORY_GENERAL = 'General/Other';
    private static final String GW1279_CATEGORY_UCB = 'UCB/CAT Support';
    private static final String GW1279_SUB_ORDER_INQUIRY = 'Order Inquiry';
    private static final String GW1279_SUB_INVALID = 'InvalidSubForTests';
    private static final String GW1279_CLOSE_DUPLICATE = 'Duplicate Case';
    private static final String GW1279_CLOSE_INVALID = 'InvalidCloseForTests';

    /**
     * @description GW-1279 — Installs org-aligned dependency maps for integration tests (CasesServiceTest, trigger tests).
     */
    public static void installStandardMapsForTests() {
        CaseRoutingRulesService.setDependencyMapsForTests(buildOrgAlignedGw1279Maps());
    }

    /**
     * @description GW-1279 — Clears injected dependency maps on CaseRoutingRulesService.
     */
    public static void clearDependencyMapsForTests() {
        CaseRoutingRulesService.resetDependencyMapsForTests();
    }

    /**
     * @description GW-1279 — Case assignments used by integration tests (matches CasesServiceTest preferred origins).
     */
    public static List<String> gw1279PreferredCaseAssignments() {
        return filterActiveCaseAssignments(GW1279_PREFERRED_ASSIGNMENTS);
    }

    /**
     * @description GW-1279 — Deterministic alternate CaseAssignment for origin-mismatch tests (slim map coverage).
     */
    public static String findAlternateGw1279CaseAssignment(String primaryAssignment) {
        if (String.isNotBlank(GW1279_ALTERNATE_ASSIGNMENT)
            && GW1279_ALTERNATE_ASSIGNMENT != primaryAssignment
            && isActiveCaseAssignment(GW1279_ALTERNATE_ASSIGNMENT)) {
            return GW1279_ALTERNATE_ASSIGNMENT;
        }
        for (String candidate : GW1279_PREFERRED_ASSIGNMENTS) {
            if (candidate != primaryAssignment && isActiveCaseAssignment(candidate)) {
                return candidate;
            }
        }
        return primaryAssignment;
    }

    /**
     * @description GW-1279 — Category values valid for a CaseAssignment__c on CaseRoutingRule__c (dependent picklist).
     */
    public static List<String> listRuleCategoriesForCaseAssignment(String caseAssignment) {
        if (String.isBlank(caseAssignment)) {
            return new List<String>();
        }
        return filterActiveDependentValues(
            CaseRoutingRule__c.CategoryValue__c,
            getRuleCategoriesByAssignment().get(caseAssignment)
        );
    }

    /**
     * @description GW-1279 — SubCategory values valid for a CategoryValue__c on CaseRoutingRule__c.
     */
    public static List<String> listRuleSubCategoriesForCategory(String categoryValue) {
        if (String.isBlank(categoryValue)) {
            return new List<String>();
        }
        return filterActiveDependentValues(
            CaseRoutingRule__c.SubCategoryValue__c,
            getRuleSubCategoriesByCategory().get(categoryValue)
        );
    }

    /**
     * @description GW-1279 — CloseCode values valid for a CategoryValue__c on CaseRoutingRule__c.
     */
    public static List<String> listRuleCloseCodesForCategory(String categoryValue) {
        if (String.isBlank(categoryValue)) {
            return new List<String>();
        }
        return filterActiveDependentValues(
            CaseRoutingRule__c.CloseCode__c,
            getRuleCloseCodesByCategory().get(categoryValue)
        );
    }

    /**
     * @description GW-1279 — First category valid for Washers CaseAssignment (rule DML-safe).
     */
    public static String firstActiveRuleCategoryValue() {
        List<String> forWashers = listRuleCategoriesForCaseAssignment(GW1279_ORIGIN_WASHERS);
        if (!forWashers.isEmpty()) {
            return forWashers[0];
        }
        return firstActivePicklistApiValue(CaseRoutingRule__c.CategoryValue__c);
    }

    /**
     * @description GW-1279 — Category valid for Loaners (or second Washers) for mismatch routing tests.
     */
    public static String secondActiveRuleCategoryValue() {
        List<String> forLoaners = listRuleCategoriesForCaseAssignment(GW1279_ORIGIN_LOANERS);
        if (!forLoaners.isEmpty()) {
            return forLoaners[0];
        }
        List<String> forWashers = listRuleCategoriesForCaseAssignment(GW1279_ORIGIN_WASHERS);
        if (forWashers.size() > 1) {
            return forWashers[1];
        }
        return nthActivePicklistApiValue(CaseRoutingRule__c.CategoryValue__c, 1);
    }

    /**
     * @description GW-1279 — Fixed dependency maps for resolveStampableRoutingFieldValues unit tests.
     */
    public static CaseRoutingRulesService.CasePicklistRoutingMaps buildFixedGw1279Maps() {
        Map<String, Set<String>> originToCategories = new Map<String, Set<String>>{
            'Washers' => new Set<String>{ 'Equipment Related', 'General/Other' },
            'Loaners' => new Set<String>{ 'General/Other' }
        };
        Map<String, Set<String>> categoryToSubCategories = new Map<String, Set<String>>{
            'Equipment Related' => new Set<String>{ 'Order Inquiry' },
            'General/Other' => new Set<String>{ 'Order Inquiry' }
        };
        Map<String, Set<String>> categoryToCloseReasons = new Map<String, Set<String>>{
            'Equipment Related' => new Set<String>{ 'Duplicate Case' },
            'General/Other' => new Set<String>{ 'Duplicate Case' }
        };
        Set<String> allCategories = new Set<String>{ 'Equipment Related', 'General/Other', 'UCB/CAT Support' };
        Set<String> allSubs = new Set<String>{ 'Order Inquiry', 'InvalidSubForTests', 'Credit/Rebill' };
        Set<String> allCloses = new Set<String>{ 'Duplicate Case', 'InvalidCloseForTests' };
        return new CaseRoutingRulesService.CasePicklistRoutingMaps(
            true,
            true,
            true,
            originToCategories,
            categoryToSubCategories,
            categoryToCloseReasons,
            allCategories,
            allSubs,
            allCloses
        );
    }

    /**
     * @description GW-1279 — Builds mock maps from org rule picklist values so routing rule DML succeeds in @IsTest.
     *              Categories are limited to those valid for each CaseAssignment__c (CategoryValue__c controlling field).
     */
    public static CaseRoutingRulesService.CasePicklistRoutingMaps buildOrgAlignedGw1279Maps() {
        List<String> origins = gw1279PreferredCaseAssignments();
        if (origins.isEmpty()) {
            return buildFixedGw1279Maps();
        }

        Map<String, Set<String>> originToCategories = new Map<String, Set<String>>();
        Map<String, Set<String>> categoryToSubCategories = new Map<String, Set<String>>();
        Map<String, Set<String>> categoryToCloseReasons = new Map<String, Set<String>>();
        Set<String> allCategories = new Set<String>();
        Set<String> allSubs = new Set<String>();
        Set<String> allCloses = new Set<String>();

        for (String origin : origins) {
            List<String> assignmentCategories = listRuleCategoriesForCaseAssignment(origin);
            if (assignmentCategories.isEmpty()) {
                continue;
            }
            originToCategories.put(origin, new Set<String>(assignmentCategories));
            allCategories.addAll(assignmentCategories);
            for (String categoryApi : assignmentCategories) {
                List<String> subs = listRuleSubCategoriesForCategory(categoryApi);
                List<String> closes = listRuleCloseCodesForCategory(categoryApi);
                if (!subs.isEmpty()) {
                    categoryToSubCategories.put(categoryApi, new Set<String>(subs));
                    allSubs.addAll(subs);
                }
                if (!closes.isEmpty()) {
                    categoryToCloseReasons.put(categoryApi, new Set<String>(closes));
                    allCloses.addAll(closes);
                }
            }
        }

        if (originToCategories.isEmpty() || allCategories.isEmpty()) {
            return buildFixedGw1279Maps();
        }

        return new CaseRoutingRulesService.CasePicklistRoutingMaps(
            true,
            true,
            true,
            originToCategories,
            categoryToSubCategories,
            categoryToCloseReasons,
            allCategories,
            allSubs,
            allCloses
        );
    }

    private static String firstActivePicklistApiValue(Schema.SObjectField fieldToken) {
        return nthActivePicklistApiValue(fieldToken, 0);
    }

    private static String nthActivePicklistApiValue(Schema.SObjectField fieldToken, Integer index) {
        List<String> values = listActivePicklistApiValues(fieldToken.getDescribe());
        return index < values.size() ? values[index] : null;
    }

    private static List<String> listActivePicklistApiValues(Schema.DescribeFieldResult fieldDescribe) {
        List<String> values = new List<String>();
        if (fieldDescribe.getType() != Schema.DisplayType.PICKLIST
            && fieldDescribe.getType() != Schema.DisplayType.MULTIPICKLIST) {
            return values;
        }
        for (Schema.PicklistEntry entry : fieldDescribe.getPicklistValues()) {
            if (entry.isActive()) {
                values.add(entry.getValue());
            }
        }
        return values;
    }

    private static String pickPreferredOrigin(List<String> activeOrigins) {
        List<String> preferred = new List<String>{ 'Washers', 'Loaners', 'Email' };
        for (String candidate : preferred) {
            if (activeOrigins.contains(candidate)) {
                return candidate;
            }
        }
        return activeOrigins[0];
    }

    private static String pickSecondaryOrigin(List<String> activeOrigins, String primaryOrigin) {
        for (String origin : activeOrigins) {
            if (origin != primaryOrigin) {
                return origin;
            }
        }
        return null;
    }

    private static Map<String, List<String>> ruleCategoriesByAssignment;
    private static Map<String, List<String>> ruleSubCategoriesByCategory;
    private static Map<String, List<String>> ruleCloseCodesByCategory;

    private static Map<String, List<String>> getRuleCategoriesByAssignment() {
        if (ruleCategoriesByAssignment == null) {
            ruleCategoriesByAssignment = buildRuleCategoriesByAssignment();
        }
        return ruleCategoriesByAssignment;
    }

    private static Map<String, List<String>> getRuleSubCategoriesByCategory() {
        if (ruleSubCategoriesByCategory == null) {
            ruleSubCategoriesByCategory = buildRuleSubCategoriesByCategory();
        }
        return ruleSubCategoriesByCategory;
    }

    private static Map<String, List<String>> getRuleCloseCodesByCategory() {
        if (ruleCloseCodesByCategory == null) {
            ruleCloseCodesByCategory = buildRuleCloseCodesByCategory();
        }
        return ruleCloseCodesByCategory;
    }

    private static List<String> filterActiveDependentValues(
        Schema.SObjectField dependentField,
        List<String> candidateValues
    ) {
        List<String> filtered = new List<String>();
        if (candidateValues == null || candidateValues.isEmpty()) {
            return filtered;
        }
        Set<String> activeValues = new Set<String>(listActivePicklistApiValues(dependentField.getDescribe()));
        for (String candidate : candidateValues) {
            if (activeValues.contains(candidate)) {
                filtered.add(candidate);
            }
        }
        return filtered;
    }

    private static Boolean isActiveCaseAssignment(String caseAssignment) {
        if (String.isBlank(caseAssignment)) {
            return false;
        }
        for (Schema.PicklistEntry entry : CaseRoutingRule__c.CaseAssignment__c.getDescribe().getPicklistValues()) {
            if (entry.isActive() && entry.getValue() == caseAssignment) {
                return true;
            }
        }
        return false;
    }

    private static List<String> filterActiveCaseAssignments(List<String> candidates) {
        List<String> active = new List<String>();
        for (String candidate : candidates) {
            if (isActiveCaseAssignment(candidate)) {
                active.add(candidate);
            }
        }
        return active;
    }

    private static void putAssignmentCategories(
        Map<String, List<String>> target,
        String assignment,
        List<String> categories
    ) {
        target.put(assignment, categories);
    }

    private static Map<String, List<String>> buildRuleCategoriesByAssignment() {
        Map<String, List<String>> data = new Map<String, List<String>>();
        putAssignmentCategories(data, 'Washers', GW1279_EQUIPMENT_LINE_CATEGORIES);
        putAssignmentCategories(data, 'GI Reprocessing', GW1279_EQUIPMENT_LINE_CATEGORIES);
        putAssignmentCategories(data, 'ORI', GW1279_EQUIPMENT_LINE_CATEGORIES);
        putAssignmentCategories(data, 'Sterilizers', GW1279_EQUIPMENT_LINE_CATEGORIES);
        putAssignmentCategories(data, 'Surgical', GW1279_EQUIPMENT_LINE_CATEGORIES);
        putAssignmentCategories(
            data,
            'Loaners',
            new List<String>{
                'Finance',
                'General Inquiry',
                'Inventory Management',
                'Inventory Tracking',
                'Loaners',
                'Shipping/Receiving'
            }
        );
        putAssignmentCategories(data, GW1279_ALTERNATE_ASSIGNMENT, GW1279_SSA_CATEGORIES);
        return data;
    }

    private static Map<String, List<String>> buildRuleSubCategoriesByCategory() {
        Map<String, List<String>> data = new Map<String, List<String>>();
        data.put('Account Related', new List<String>{ 'CDM Requests', 'General/Other', 'Modify', 'Tech Assignment' });
        data.put('Equipment Related', new List<String>{ 'Add', 'General/Other', 'Light Configuration', 'Modify', 'Warranty' });
        data.put(
            'Order Management Related',
            new List<String>{ 'General/Other', 'Order Inquiry', 'PO Req', 'SSQ' }
        );
        data.put(
            'Service Request Related',
            new List<String>{ 'Backlog', 'Data Correction', 'FSR/Service History', 'General/Other', 'Trouble Shooting' }
        );
        return data;
    }

    private static Map<String, List<String>> buildRuleCloseCodesByCategory() {
        Map<String, List<String>> data = new Map<String, List<String>>();
        data.put('Content Submission Intake', new List<String>{ 'Request Dispositioned', 'Request Intake Completed', 'Request Redirected' });
        data.put('Equipment Related', new List<String>{ 'No Action Required', 'Request Redirected', 'Support Provided' });
        data.put('Equipment Service Support', new List<String>{ 'Request Redirected', 'Service Work Order Created', 'Support Provided' });
        data.put('General Product Inquiry', new List<String>{ 'Request Redirected', 'Service Work Order Created', 'Support Provided' });
        data.put('General/Other', new List<String>{ 'No Action Required', 'Request Redirected', 'Support Provided' });
        data.put('IDEAS Support', new List<String>{ 'Review Completed', 'Review Redirected' });
        data.put('Installation Support', new List<String>{ 'Request Redirected', 'Service Work Order Created', 'Support Provided' });
        data.put('Loaners', new List<String>{ 'No Action Required', 'Request Redirected', 'Support Provided' });
        data.put('Parts Inquiry', new List<String>{ 'Request Redirected', 'Support Provided' });
        data.put('Service Inquiry', new List<String>{ 'Request Redirected', 'Service Work Order Created', 'Support Provided' });
        data.put('UCB/CAT Support', new List<String>{ 'Request Redirected', 'Service Work Order Created', 'Support Provided' });
        return data;
    }

    private static void beginGw1279ResolveTests() {
        CaseRoutingRulesService.setDependencyMapsForTests(buildFixedGw1279Maps());
    }

    /**
     * @description Jira GW-1279 — resolveStampableRoutingFieldValues returns nulls when rule is null.
     */
    @IsTest
    static void testResolveStampableRoutingFieldValues_nullRule() {
        beginGw1279ResolveTests();
        Case c = new Case(Origin = GW1279_ORIGIN_WASHERS);
        CaseRoutingRulesService.RoutingStampFieldValues v = CaseRoutingRulesService.resolveStampableRoutingFieldValues(c, null);
        System.Assert.isNull(v.categoryApiValue);
        System.Assert.isNull(v.subCategoryApiValue);
        System.Assert.isNull(v.closeReasonApiValue);
    }

    /**
     * @description Jira GW-1279 — invalid Category for Origin omits category, subcategory, and close reason.
     */
    @IsTest
    static void testResolveStampableRoutingFieldValues_invalidCategoryOmitsAll() {
        beginGw1279ResolveTests();
        Id inboxRt = inboxSupportRecordTypeId();
        System.Assert.isNotNull(inboxRt);
        Case c = new Case(Origin = GW1279_ORIGIN_WASHERS, RecordTypeId = inboxRt);
        CaseRoutingRule__c rule = new CaseRoutingRule__c(
            CategoryValue__c = GW1279_CATEGORY_UCB,
            SubCategoryValue__c = 'Credit/Rebill',
            CloseCode__c = GW1279_CLOSE_DUPLICATE
        );
        CaseRoutingRulesService.RoutingStampFieldValues v = CaseRoutingRulesService.resolveStampableRoutingFieldValues(c, rule);
        System.Assert.isNull(v.categoryApiValue);
        System.Assert.isNull(v.subCategoryApiValue);
        System.Assert.isNull(v.closeReasonApiValue);
    }

    /**
     * @description Jira GW-1279 — valid category with invalid subcategory keeps category only.
     */
    @IsTest
    static void testResolveStampableRoutingFieldValues_invalidSubcategoryKeepsCategory() {
        beginGw1279ResolveTests();
        Id inboxRt = inboxSupportRecordTypeId();
        System.Assert.isNotNull(inboxRt);
        Case c = new Case(Origin = GW1279_ORIGIN_WASHERS, RecordTypeId = inboxRt);
        CaseRoutingRule__c rule = new CaseRoutingRule__c(
            CategoryValue__c = GW1279_CATEGORY_EQUIPMENT,
            SubCategoryValue__c = GW1279_SUB_INVALID
        );
        CaseRoutingRulesService.RoutingStampFieldValues v = CaseRoutingRulesService.resolveStampableRoutingFieldValues(c, rule);
        System.Assert.areEqual(GW1279_CATEGORY_EQUIPMENT, v.categoryApiValue);
        System.Assert.isNull(v.subCategoryApiValue);
    }

    /**
     * @description Jira GW-1279 — valid category with invalid close reason keeps category only (no Closed).
     */
    @IsTest
    static void testResolveStampableRoutingFieldValues_invalidCloseKeepsCategory() {
        beginGw1279ResolveTests();
        Id inboxRt = inboxSupportRecordTypeId();
        System.Assert.isNotNull(inboxRt);
        Case c = new Case(Origin = GW1279_ORIGIN_WASHERS, RecordTypeId = inboxRt);
        CaseRoutingRule__c rule = new CaseRoutingRule__c(
            CategoryValue__c = GW1279_CATEGORY_EQUIPMENT,
            CloseCode__c = GW1279_CLOSE_INVALID
        );
        CaseRoutingRulesService.RoutingStampFieldValues v = CaseRoutingRulesService.resolveStampableRoutingFieldValues(c, rule);
        System.Assert.areEqual(GW1279_CATEGORY_EQUIPMENT, v.categoryApiValue);
        System.Assert.isNull(v.subCategoryApiValue);
        System.Assert.isNull(v.closeReasonApiValue);
    }

    /**
     * @description Jira GW-1279 — category not valid for Origin must not stamp (e.g. Loaners + UCB/CAT Support).
     */
    @IsTest
    static void testResolveStampableRoutingFieldValues_categoryInvalidForOriginOmitsCategory() {
        beginGw1279ResolveTests();
        Id inboxRt = inboxSupportRecordTypeId();
        System.Assert.isNotNull(inboxRt);
        Case c = new Case(Origin = GW1279_ORIGIN_LOANERS, RecordTypeId = inboxRt);
        CaseRoutingRulesService.RoutingStampFieldValues v = CaseRoutingRulesService.resolveStampableRoutingFieldValues(
            c,
            new CaseRoutingRule__c(CategoryValue__c = GW1279_CATEGORY_UCB, SubCategoryValue__c = 'Credit/Rebill')
        );
        System.Assert.isNull(v.categoryApiValue, 'UCB/CAT Support is not valid for Loaners Origin');
        System.Assert.isNull(v.subCategoryApiValue);
        System.Assert.isNull(v.closeReasonApiValue);
    }

    /**
     * @description Jira GW-1279 — full valid stamp (category, subcategory, close) via ConnectApi maps.
     */
    @IsTest
    static void testResolveStampableRoutingFieldValues_fullStampAllThreeFields() {
        beginGw1279ResolveTests();
        Id inboxRt = inboxSupportRecordTypeId();
        System.Assert.isNotNull(inboxRt);
        Case c = new Case(Origin = GW1279_ORIGIN_WASHERS, RecordTypeId = inboxRt);
        CaseRoutingRulesService.RoutingStampFieldValues v = CaseRoutingRulesService.resolveStampableRoutingFieldValues(
            c,
            new CaseRoutingRule__c(
                CategoryValue__c = GW1279_CATEGORY_EQUIPMENT,
                SubCategoryValue__c = GW1279_SUB_ORDER_INQUIRY,
                CloseCode__c = GW1279_CLOSE_DUPLICATE
            )
        );
        System.Assert.areEqual(GW1279_CATEGORY_EQUIPMENT, v.categoryApiValue);
        System.Assert.areEqual(GW1279_SUB_ORDER_INQUIRY, v.subCategoryApiValue);
        System.Assert.areEqual(GW1279_CLOSE_DUPLICATE, v.closeReasonApiValue);
    }

    /**
     * @description Jira GW-1279 — blank Origin omits origin-dependent category (ConnectApi path).
     */
    @IsTest
    static void testResolveStampableRoutingFieldValues_blankOriginOmitsCategory() {
        beginGw1279ResolveTests();
        Id inboxRt = inboxSupportRecordTypeId();
        System.Assert.isNotNull(inboxRt);
        Case blankOriginCase = new Case(Origin = null, RecordTypeId = inboxRt);
        CaseRoutingRulesService.RoutingStampFieldValues v = CaseRoutingRulesService.resolveStampableRoutingFieldValues(
            blankOriginCase,
            new CaseRoutingRule__c(CategoryValue__c = GW1279_CATEGORY_EQUIPMENT)
        );
        System.Assert.isNull(v.categoryApiValue);
    }

    /**
     * @description Jira GW-1279 — rule picklist values are trimmed before validation.
     */
    @IsTest
    static void testResolveStampableRoutingFieldValues_ruleValuesTrimmed() {
        beginGw1279ResolveTests();
        Id inboxRt = inboxSupportRecordTypeId();
        System.Assert.isNotNull(inboxRt);
        Case c = new Case(Origin = GW1279_ORIGIN_WASHERS, RecordTypeId = inboxRt);
        CaseRoutingRulesService.RoutingStampFieldValues v = CaseRoutingRulesService.resolveStampableRoutingFieldValues(
            c,
            new CaseRoutingRule__c(CategoryValue__c = '  ' + GW1279_CATEGORY_EQUIPMENT + '  ')
        );
        System.Assert.areEqual(GW1279_CATEGORY_EQUIPMENT, v.categoryApiValue);
    }

    /**
     * @description Jira GW-1279 — blank rule picklist fields yield null stamps (no DML).
     */
    @IsTest
    static void testResolveStampableRoutingFieldValues_blankRulePicklistFields() {
        beginGw1279ResolveTests();
        Id inboxRt = inboxSupportRecordTypeId();
        System.Assert.isNotNull(inboxRt);
        Case c = new Case(Origin = GW1279_ORIGIN_WASHERS, RecordTypeId = inboxRt);
        CaseRoutingRulesService.RoutingStampFieldValues v = CaseRoutingRulesService.resolveStampableRoutingFieldValues(
            c,
            new CaseRoutingRule__c(
                CategoryValue__c = '   ',
                SubCategoryValue__c = '',
                CloseCode__c = null
            )
        );
        System.Assert.isNull(v.categoryApiValue);
        System.Assert.isNull(v.subCategoryApiValue);
        System.Assert.isNull(v.closeReasonApiValue);
    }

    /**
     * @description Jira GW-1279 — resetDependencyMapsForTests clears injected maps (test seam lifecycle).
     */
    @IsTest
    static void testResetDependencyMapsForTests_clearsInjectedMaps() {
        beginGw1279ResolveTests();
        Case c = new Case(Origin = GW1279_ORIGIN_WASHERS);
        CaseRoutingRule__c rule = new CaseRoutingRule__c(CategoryValue__c = GW1279_CATEGORY_EQUIPMENT);
        System.Assert.isNotNull(
            CaseRoutingRulesService.resolveStampableRoutingFieldValues(c, rule).categoryApiValue
        );
        clearDependencyMapsForTests();
        System.Assert.isNull(
            CaseRoutingRulesService.resolveStampableRoutingFieldValues(c, rule).categoryApiValue
        );
    }

    /**
     * @description Jira GW-1279 — record type resolution for ConnectApi picklist describe.
     */
    @IsTest
    static void testResolveRecordTypeIdForConnectApi_explicitAndMasterScope() {
        Id inboxRt = inboxSupportRecordTypeId();
        System.Assert.isNotNull(inboxRt);
        System.Assert.areEqual(inboxRt, CaseRoutingRulesService.resolveRecordTypeIdForConnectApi(inboxRt));
        System.Assert.isNotNull(CaseRoutingRulesService.resolveRecordTypeIdForConnectApi(null));
    }

    /**
     * @description Jira GW-1279 — without injected maps, ConnectApi is unavailable in @IsTest and yields empty maps.
     */
    @IsTest
    static void testResolveStampableRoutingFieldValues_connectApiUnavailableInTestWithoutOverride() {
        clearDependencyMapsForTests();
        Id inboxRt = inboxSupportRecordTypeId();
        System.Assert.isNotNull(inboxRt);
        Case c = new Case(Origin = GW1279_ORIGIN_WASHERS, RecordTypeId = inboxRt);
        CaseRoutingRulesService.RoutingStampFieldValues v = CaseRoutingRulesService.resolveStampableRoutingFieldValues(
            c,
            new CaseRoutingRule__c(CategoryValue__c = GW1279_CATEGORY_EQUIPMENT)
        );
        System.Assert.isNull(v.categoryApiValue);
    }

    @IsTest
    static void testPicklistRoutingMapsBuilder_buildEmptyMaps() {
        CaseRoutingRulesService.CasePicklistRoutingMaps maps =
            CaseRoutingRulesService.buildEmptyPicklistRoutingMapsForTests();
        System.Assert.isFalse(maps.isCategoryAllowedForOrigin('Washers', 'Equipment Related'));
    }

    @IsTest
    static void testPicklistRoutingMapsBuilder_buildFromPicklistValuesCollection_nullCollection() {
        CaseRoutingRulesService.CasePicklistRoutingMaps maps =
            CaseRoutingRulesService.buildPicklistRoutingMapsFromCollectionForTests(null);
        System.Assert.isFalse(maps.isCategoryAllowedForOrigin('Washers', 'Any'));
    }

    @IsTest
    static void testPicklistRoutingMapsBuilder_buildFromPicklistValuesCollection_originToCategoryDependency() {
        ConnectApi.PicklistValues categoryPicklist = buildCategoryPicklistWithOriginDependency();
        ConnectApi.PicklistValuesCollection collection = new ConnectApi.PicklistValuesCollection();
        collection.picklistFieldValues = new Map<String, ConnectApi.PicklistValues>{
            'Category__c' => categoryPicklist
        };

        CaseRoutingRulesService.CasePicklistRoutingMaps maps =
            CaseRoutingRulesService.buildPicklistRoutingMapsFromCollectionForTests(collection);
        System.Assert.isTrue(maps.isCategoryAllowedForOrigin('Washers', 'Equipment Related'));
        System.Assert.isFalse(maps.isCategoryAllowedForOrigin('Loaners', 'Equipment Related'));
        System.Assert.isFalse(maps.isCategoryAllowedForOrigin('Washers', ''));
        System.Assert.isFalse(maps.isCategoryAllowedForOrigin(null, 'Equipment Related'));
    }

    @IsTest
    static void testCasePicklistRoutingMaps_isCategoryAllowedForOrigin_dependentAndNonDependent() {
        Map<String, Set<String>> originToCategories = new Map<String, Set<String>>{
            'Washers' => new Set<String>{ 'Equipment Related' }
        };
        CaseRoutingRulesService.CasePicklistRoutingMaps dependentMaps = new CaseRoutingRulesService.CasePicklistRoutingMaps(
            true,
            false,
            false,
            originToCategories,
            null,
            null,
            new Set<String>(),
            null,
            null
        );
        System.Assert.isTrue(dependentMaps.isCategoryAllowedForOrigin('Washers', 'Equipment Related'));
        System.Assert.isFalse(dependentMaps.isCategoryAllowedForOrigin('Washers', ''));
        System.Assert.isFalse(dependentMaps.isCategoryAllowedForOrigin('', 'Equipment Related'));

        CaseRoutingRulesService.CasePicklistRoutingMaps nonDependentMaps =
            new CaseRoutingRulesService.CasePicklistRoutingMaps(
                false,
                false,
                false,
                null,
                null,
                null,
                new Set<String>{ 'AnyCategory' },
                null,
                null
            );
        System.Assert.isTrue(nonDependentMaps.isCategoryAllowedForOrigin('AnyOrigin', 'AnyCategory'));
    }

    @IsTest
    static void testCasePicklistRoutingMaps_isSubCategoryAndCloseReasonAllowedForCategory() {
        Map<String, Set<String>> categoryToSub = new Map<String, Set<String>>{
            'Equipment Related' => new Set<String>{ 'Order Inquiry' }
        };
        Map<String, Set<String>> categoryToClose = new Map<String, Set<String>>{
            'Equipment Related' => new Set<String>{ 'Duplicate Case' }
        };
        CaseRoutingRulesService.CasePicklistRoutingMaps maps = new CaseRoutingRulesService.CasePicklistRoutingMaps(
            false,
            true,
            true,
            null,
            categoryToSub,
            categoryToClose,
            null,
            new Set<String>(),
            new Set<String>()
        );
        System.Assert.isTrue(maps.isSubCategoryAllowedForCategory('Equipment Related', 'Order Inquiry'));
        System.Assert.isFalse(maps.isSubCategoryAllowedForCategory('Equipment Related', 'BadSub'));
        System.Assert.isTrue(maps.isCloseReasonAllowedForCategory('Equipment Related', 'Duplicate Case'));
        System.Assert.isFalse(maps.isCloseReasonAllowedForCategory('Equipment Related', ''));
    }

    private static ConnectApi.PicklistValues buildCategoryPicklistWithOriginDependency() {
        ConnectApi.PicklistValues picklistValues = new ConnectApi.PicklistValues();
        picklistValues.controllerValues = new Map<String, Integer>{ 'Washers' => 0, 'Loaners' => 1 };
        ConnectApi.PicklistValue equipmentRelated = new ConnectApi.PicklistValue();
        equipmentRelated.value = 'Equipment Related';
        equipmentRelated.validFor = new List<Integer>{ 0 };
        ConnectApi.PicklistValue generalOther = new ConnectApi.PicklistValue();
        generalOther.value = 'General/Other';
        generalOther.validFor = new List<Integer>{ 0, 1 };
        picklistValues.values = new List<ConnectApi.PicklistValue>{ equipmentRelated, generalOther };
        return picklistValues;
    }
}