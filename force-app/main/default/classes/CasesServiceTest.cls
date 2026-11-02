/**
 * @description Test class for CasesService. Active @IsTest methods cover GW-1279 public API on main CasesService
 *              (applyCaseRoutingRules, getCaseAssignmentOrigins). @TestSetup creates one shared Account and optional
 *              Read Only user.https://steris-healthcare--cbmdev.sandbox.my.salesforce.com/_ui/common/apex/debug/ApexCSIPage#
 * @author STERIS
 * @date 2026-04-22
 */
@IsTest
private class CasesServiceTest {

    private static final String ROUTING_TEST_ACCOUNT_NAME = 'CasesService GW1279 Test Account';
    private static final String ROUTING_READONLY_USER_LASTNAME = 'GW1279ReadOnlySetup';

    /**
     * @description Jira GW-1279 — Shared Account and Read Only user for routing tests (one insert per test run).
     */
    @TestSetup
    static void makeTestData() {
        Schema.RecordTypeInfo prospectRt =
            Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName().get('Prospect');
        Account routingAccount = new Account(Name = ROUTING_TEST_ACCOUNT_NAME);
        if (prospectRt != null) {
            routingAccount.RecordTypeId = prospectRt.getRecordTypeId();
            routingAccount.BillingStreet = '1 Test Ship St';
            routingAccount.BillingCity = 'Cleveland';
            routingAccount.BillingStateCode  = 'OH';
            routingAccount.BillingPostalCode = '44101';
            routingAccount.BillingCountryCode  = 'US';
        } else {
            routingAccount.SourceSystemID__c = 'GW1279ACC02';
            routingAccount.SystemID__c = 'GW1279SYS02';
        }
        insert routingAccount;

        List<Profile> readOnlyProfiles = [SELECT Id FROM Profile WHERE Name = 'Read Only' LIMIT 1];
        if (readOnlyProfiles.isEmpty()) {
            return;
        }
        String unique =
            String.valueOf(Math.abs(Crypto.getRandomInteger()))
            + '_'
            + String.valueOf(Datetime.now().getTime());
        String safe = unique.replaceAll('[^0-9A-Za-z]', 'x');
        String aliasSource = ('s' + safe).substring(0, Math.min(8, ('s' + safe).length()));
        String nickname = ('gw1279su' + safe).substring(0, Math.min(40, ('gw1279su' + safe).length()));
        String emailLocal = 'gw1279.setup.' + safe;
        if (emailLocal.length() > 40) {
            emailLocal = emailLocal.substring(0, 40);
        }
        insert new User(
            ProfileId = readOnlyProfiles[0].Id,
            LastName = ROUTING_READONLY_USER_LASTNAME,
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
    }

    /**
     * @description Jira GW-1279 — Id of Account created in @TestSetup for Case.AccountId on routing candidates.
     */
    private static Id routingTestAccountId() {
        return [SELECT Id FROM Account WHERE Name = :ROUTING_TEST_ACCOUNT_NAME LIMIT 1].Id;
    }

    /**
     * @description Jira GW-1279 — Read Only user from @TestSetup for run-as security tests, or null if not created.
     */
    private static User routingReadOnlyTestUser() {
        List<User> users = [
            SELECT Id
            FROM User
            WHERE LastName = :ROUTING_READONLY_USER_LASTNAME
            LIMIT 1
        ];
        return users.isEmpty() ? null : users[0];
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
     * @description Jira GW-1279 — Installs mock picklist dependency maps (no ConnectApi in @IsTest).
     */
    private static void beginGw1279RoutingHelpers() {
        CaseRoutingRulesServiceTest.installStandardMapsForTests();
    }

    /**
     * @description Jira GW-1279 — Origin for routing tests where Category__c can be stamped on Inbox Support
     *              (prefers Loaners and other origins with stampable categories per dependency maps).
     */
    private static String routingTestCaseAssignment() {
        beginGw1279RoutingHelpers();
        Id inboxRt = Schema.SObjectType.Case.getRecordTypeInfosByName().get('Inbox Support')?.getRecordTypeId();
        if (inboxRt == null) {
            return primaryCaseAssignmentMatchingOrigin();
        }
        List<String> preferredOrigins = new List<String>{
            'Washers',
            'GI Reprocessing',
            'ORI',
            'Sterilizers',
            'Surgical',
            'Loaners'
        };
        Set<String> activeOrigins = new Set<String>();
        for (Schema.PicklistEntry pe : Case.Origin.getDescribe().getPicklistValues()) {
            if (pe.isActive()) {
                activeOrigins.add(pe.getValue());
            }
        }
        List<String> tryOrder = new List<String>();
        for (String preferred : preferredOrigins) {
            if (activeOrigins.contains(preferred)) {
                tryOrder.add(preferred);
            }
        }
        String primary = primaryCaseAssignmentMatchingOrigin();
        if (String.isNotBlank(primary) && !tryOrder.contains(primary)) {
            tryOrder.add(primary);
        }
        for (String activeOrigin : activeOrigins) {
            if (!tryOrder.contains(activeOrigin)) {
                tryOrder.add(activeOrigin);
            }
        }
        for (String origin : tryOrder) {
            Case scratch = new Case(Origin = origin, RecordTypeId = inboxRt);
            for (String categoryApi : CaseRoutingRulesServiceTest.listRuleCategoriesForCaseAssignment(origin)) {
                CaseRoutingRulesService.RoutingStampFieldValues resolved =
                    CaseRoutingRulesService.resolveStampableRoutingFieldValues(
                        scratch,
                        new CaseRoutingRule__c(CategoryValue__c = categoryApi)
                    );
                if (String.isNotBlank(resolved.categoryApiValue)) {
                    return origin;
                }
            }
        }
        return primary;
    }

    /**
     * @description Jira GW-1279 — First CategoryValue__c that resolves as stampable for Inbox Support + routing Origin
     *              (respects Origin → Category dependency and CaseAssignment → Category rule picklist).
     */
    private static String routingCategoryApiValue() {
        return routingCategoryApiValueForAssignment(routingTestCaseAssignment());
    }

    /**
     * @description GW-1279 — First stampable CategoryValue__c for a CaseAssignment (valid for rule DML and Case Origin).
     */
    private static String routingCategoryApiValueForAssignment(String caseAssignment) {
        Id inboxRt = Schema.SObjectType.Case.getRecordTypeInfosByName().get('Inbox Support')?.getRecordTypeId();
        if (inboxRt == null || String.isBlank(caseAssignment)) {
            return null;
        }
        Case scratch = new Case(Origin = caseAssignment, RecordTypeId = inboxRt);
        for (String categoryApi : CaseRoutingRulesServiceTest.listRuleCategoriesForCaseAssignment(caseAssignment)) {
            CaseRoutingRulesService.RoutingStampFieldValues resolved =
                CaseRoutingRulesService.resolveStampableRoutingFieldValues(
                    scratch,
                    new CaseRoutingRule__c(CategoryValue__c = categoryApi)
                );
            if (String.isNotBlank(resolved.categoryApiValue)) {
                return categoryApi;
            }
        }
        return null;
    }

    /**
     * @description GW-1279 — Any CategoryValue__c valid for rule DML for the given CaseAssignment (may not stamp on Case).
     */
    private static String firstRuleCategoryForCaseAssignment(String caseAssignment) {
        List<String> categories = CaseRoutingRulesServiceTest.listRuleCategoriesForCaseAssignment(caseAssignment);
        return categories.isEmpty() ? null : categories[0];
    }

    /**
     * @description Jira GW-1279 — Legacy helper: first active rule category whose API value exists on Case.Category__c.
     */
    @TestVisible
    private static String routingCategoryApiValueLegacy() {
        Schema.DescribeFieldResult ruleDescribe = CaseRoutingRule__c.CategoryValue__c.getDescribe();
        if (ruleDescribe.getType() != Schema.DisplayType.PICKLIST
            && ruleDescribe.getType() != Schema.DisplayType.MULTIPICKLIST) {
            return null;
        }
        Schema.DescribeFieldResult caseDescribe = Case.Category__c.getDescribe();
        Boolean caseIsPicklist = (caseDescribe.getType() == Schema.DisplayType.PICKLIST
            || caseDescribe.getType() == Schema.DisplayType.MULTIPICKLIST);
        Set<String> caseActive = new Set<String>();
        if (caseIsPicklist) {
            for (Schema.PicklistEntry pe : caseDescribe.getPicklistValues()) {
                if (pe.isActive()) {
                    caseActive.add(pe.getValue());
                }
            }
        }
        for (Schema.PicklistEntry pe : ruleDescribe.getPicklistValues()) {
            if (!pe.isActive()) {
                continue;
            }
            if (!caseIsPicklist || caseActive.contains(pe.getValue())) {
                return pe.getValue();
            }
        }
        return null;
    }

    /**
     * @description Jira GW-1279 — Category and CloseCode API values that both resolve for Inbox Support + primary Origin.
     */
    private static List<String> routingCategoryAndCloseApiValuesForInbox() {
        Id inboxRt = Schema.SObjectType.Case.getRecordTypeInfosByName().get('Inbox Support')?.getRecordTypeId();
        if (inboxRt == null) {
            return null;
        }
        String origin = routingTestCaseAssignment();
        Case scratch = new Case(Origin = origin, RecordTypeId = inboxRt);
        for (String categoryApi : CaseRoutingRulesServiceTest.listRuleCategoriesForCaseAssignment(origin)) {
            for (String closeApi : CaseRoutingRulesServiceTest.listRuleCloseCodesForCategory(categoryApi)) {
                CaseRoutingRulesService.RoutingStampFieldValues resolved =
                    CaseRoutingRulesService.resolveStampableRoutingFieldValues(
                        scratch,
                        new CaseRoutingRule__c(CategoryValue__c = categoryApi, CloseCode__c = closeApi)
                    );
                if (String.isNotBlank(resolved.categoryApiValue) && String.isNotBlank(resolved.closeReasonApiValue)) {
                    return new List<String>{ categoryApi, closeApi };
                }
            }
        }
        return null;
    }

    /**
     * @description Jira GW-1279 — First SubCategoryValue__c that resolves with a known category for Inbox Support + Origin.
     */
    private static String firstResolvedSubcategoryForCategory(Id inboxRt, String origin, String categoryApi) {
        Case scratch = new Case(Origin = origin, RecordTypeId = inboxRt);
        for (String subApi : CaseRoutingRulesServiceTest.listRuleSubCategoriesForCategory(categoryApi)) {
            CaseRoutingRulesService.RoutingStampFieldValues resolved =
                CaseRoutingRulesService.resolveStampableRoutingFieldValues(
                    scratch,
                    new CaseRoutingRule__c(CategoryValue__c = categoryApi, SubCategoryValue__c = subApi)
                );
            if (String.isNotBlank(resolved.subCategoryApiValue)) {
                return subApi;
            }
        }
        return null;
    }

    /**
     * @description Jira GW-1279 — Origin plus category, subcategory, and close API values that all resolve for Inbox Support.
     */
    private static List<String> routingCategorySubcategoryCloseForInbox() {
        Id inboxRt = Schema.SObjectType.Case.getRecordTypeInfosByName().get('Inbox Support')?.getRecordTypeId();
        if (inboxRt == null) {
            return null;
        }
        String origin = routingTestCaseAssignment();
        Case scratch = new Case(Origin = origin, RecordTypeId = inboxRt);
        for (String categoryApi : CaseRoutingRulesServiceTest.listRuleCategoriesForCaseAssignment(origin)) {
            for (String subApi : CaseRoutingRulesServiceTest.listRuleSubCategoriesForCategory(categoryApi)) {
                for (String closeApi : CaseRoutingRulesServiceTest.listRuleCloseCodesForCategory(categoryApi)) {
                    CaseRoutingRulesService.RoutingStampFieldValues resolved =
                        CaseRoutingRulesService.resolveStampableRoutingFieldValues(
                            scratch,
                            new CaseRoutingRule__c(
                                CategoryValue__c = categoryApi,
                                SubCategoryValue__c = subApi,
                                CloseCode__c = closeApi
                            )
                        );
                    if (String.isNotBlank(resolved.categoryApiValue)
                        && String.isNotBlank(resolved.subCategoryApiValue)
                        && String.isNotBlank(resolved.closeReasonApiValue)) {
                        return new List<String>{
                            origin,
                            categoryApi,
                            subApi,
                            closeApi
                        };
                    }
                }
            }
        }
        return null;
    }

    /**
     * @description Jira GW-1279 — First active Case.Label__c picklist API value when field is a picklist.
     */
    private static String firstActiveLabelValueApi() {
        Schema.DescribeFieldResult dfr = Case.Label__c.getDescribe();
        if (dfr.getType() != Schema.DisplayType.PICKLIST && dfr.getType() != Schema.DisplayType.MULTIPICKLIST) {
            return 'TestLabel';
        }
        for (Schema.PicklistEntry pe : dfr.getPicklistValues()) {
            if (pe.isActive()) {
                return pe.getValue();
            }
        }
        return null;
    }

    /**
     * @description Jira GW-1279 — Active CaseAssignment__c value different from primary (for routing skip tests).
     */
    private static String alternateCaseAssignmentApi(String primary) {
        return CaseRoutingRulesServiceTest.findAlternateGw1279CaseAssignment(primary);
    }

    /**
     * @description Jira GW-1279 — applyCaseRoutingRules wraps unexpected failures (e.g. null Case in list) in CasesServiceException.
     */
    @IsTest
    static void testApplyCaseRoutingRules_wrapsUnexpectedFailuresInServiceException() {
        Test.startTest();
        try {
            CasesService.applyCaseRoutingRules(new List<Case>{ null });
            System.Assert.fail('Expected CasesServiceException for null Case row');
        } catch (CasesService.CasesServiceException e) {
            System.Assert.isTrue(
                e.getMessage() != null && e.getMessage().contains('Failed to apply case routing rules'),
                'Message should describe routing failure: ' + e.getMessage()
            );
        }
        Test.stopTest();
    }

    /**
     * @description Jira GW-1279 — getCaseAssignmentOrigins ignores blank Origins.
     */
    @IsTest
    static void testGetCaseAssignmentOrigins_skipsBlankOrigins() {
        Case blank = (Case) new adb_Case().origin('').subject('B1').record;
        blank.Origin = null;
        Case withOrigin = (Case) new adb_Case().origin('Email').subject('B2').record;
        Test.startTest();
        Set<String> origins = CasesService.getCaseAssignmentOrigins(new List<Case>{ blank, withOrigin });
        Test.stopTest();
        System.Assert.areEqual(1, origins.size());
        System.Assert.isTrue(origins.contains('Email'));
    }

    /**
     * @description Jira GW-1279 — applyCaseRoutingRules matches DescriptionSearchString__c when Subject rule absent.
     */
    @IsTest
    static void testApplyCaseRoutingRules_descriptionSearchMatches() {
        Id inboxRt = Schema.SObjectType.Case.getRecordTypeInfosByName().get('Inbox Support')?.getRecordTypeId();
        if (inboxRt == null) {
            return;
        }
        Id routingAccId = routingTestAccountId();

        String assign = routingTestCaseAssignment();
        String categoryApi = routingCategoryApiValue();
        if (categoryApi == null) {
            return;
        }

        TriggerHandler.bypass('CaseTriggerHandler');
        new adb_CaseRoutingRule_c()
            .name('DescRule ' + String.valueOf(Math.abs(Crypto.getRandomInteger())))
            .isActive(true)
            .priority(1)
            .caseAssignment(assign)
            .suppliedEmailFromAddress('descclient@test.org')
            .descriptionSearchString('DESCUNIQTOKEN')
            .categoryValue(categoryApi);
        adb_DomainBuilder.save();
        TriggerHandler.clearBypass('CaseTriggerHandler');

        Case candidate = (Case) new adb_Case()
            .subject('No subject token here')
            .description('Body has DESCUNIQTOKEN inside')
            .origin(assign)
            .suppliedEmail('descclient@test.org')
            .record;
        candidate.RecordTypeId = inboxRt;
        candidate.AccountId = routingAccId;

        Test.startTest();
        List<Case> routed = CasesService.applyCaseRoutingRules(new List<Case>{ candidate });
        Test.stopTest();

        System.Assert.areEqual(1, routed.size());
        System.Assert.areEqual(categoryApi, routed[0].Category__c);
    }

    /**
     * @description Jira GW-1279 — subject search mismatch skips rule; Case not stamped.
     */
    @IsTest
    static void testApplyCaseRoutingRules_subjectMismatchSkipsStamp() {
        Id inboxRt = Schema.SObjectType.Case.getRecordTypeInfosByName().get('Inbox Support')?.getRecordTypeId();
        if (inboxRt == null) {
            return;
        }
        Id routingAccId = routingTestAccountId();

        String assign = routingTestCaseAssignment();
        String categoryApi = routingCategoryApiValue();
        if (categoryApi == null) {
            return;
        }

        TriggerHandler.bypass('CaseTriggerHandler');
        new adb_CaseRoutingRule_c()
            .name('SubjMiss ' + String.valueOf(Math.abs(Crypto.getRandomInteger())))
            .isActive(true)
            .priority(1)
            .caseAssignment(assign)
            .suppliedEmailFromAddress('subjmiss@test.org')
            .subjectSearchString('ZZZNOTINSUBJECT')
            .categoryValue(categoryApi);
        adb_DomainBuilder.save();
        TriggerHandler.clearBypass('CaseTriggerHandler');

        Case candidate = (Case) new adb_Case()
            .subject('no token here')
            .origin(assign)
            .suppliedEmail('subjmiss@test.org')
            .record;
        candidate.RecordTypeId = inboxRt;
        candidate.AccountId = routingAccId;

        Test.startTest();
        List<Case> routed = CasesService.applyCaseRoutingRules(new List<Case>{ candidate });
        Test.stopTest();

        System.Assert.areEqual(1, routed.size());
        System.Assert.isTrue(String.isBlank(routed[0].Category__c));
    }

    /**
     * @description Jira GW-1279 — supplied email on rule must match Case SuppliedEmail (case-insensitive).
     */
    @IsTest
    static void testApplyCaseRoutingRules_emailMismatchSkipsStamp() {
        Id inboxRt = Schema.SObjectType.Case.getRecordTypeInfosByName().get('Inbox Support')?.getRecordTypeId();
        if (inboxRt == null) {
            return;
        }
        Id routingAccId = routingTestAccountId();

        String assign = routingTestCaseAssignment();
        String categoryApi = routingCategoryApiValue();
        if (categoryApi == null) {
            return;
        }

        TriggerHandler.bypass('CaseTriggerHandler');
        new adb_CaseRoutingRule_c()
            .name('EmailMiss ' + String.valueOf(Math.abs(Crypto.getRandomInteger())))
            .isActive(true)
            .priority(1)
            .caseAssignment(assign)
            .subjectSearchString('EMAILMISS')
            .suppliedEmailFromAddress('expected@only.com')
            .categoryValue(categoryApi);
        adb_DomainBuilder.save();
        TriggerHandler.clearBypass('CaseTriggerHandler');

        Case candidate = (Case) new adb_Case()
            .subject('EMAILMISS in subject')
            .origin(assign)
            .suppliedEmail('different@user.com')
            .record;
        candidate.RecordTypeId = inboxRt;
        candidate.AccountId = routingAccId;

        Test.startTest();
        List<Case> routed = CasesService.applyCaseRoutingRules(new List<Case>{ candidate });
        Test.stopTest();

        System.Assert.areEqual(1, routed.size());
        System.Assert.isTrue(String.isBlank(routed[0].Category__c));
    }

    /**
     * @description Jira GW-1279 — first rule skipped by CaseAssignment; second rule stamps Case.
     */
    @IsTest
    static void testApplyCaseRoutingRules_secondRuleMatchesAfterFirstSkipped() {
        Id inboxRt = Schema.SObjectType.Case.getRecordTypeInfosByName().get('Inbox Support')?.getRecordTypeId();
        if (inboxRt == null) {
            return;
        }
        String assign = routingTestCaseAssignment();
        String wrongAssign = alternateCaseAssignmentApi(assign);
        if (wrongAssign == assign) {
            return;
        }

        Id routingAccId = routingTestAccountId();

        String categoryApi = routingCategoryApiValue();
        String wrongAssignCategory = firstRuleCategoryForCaseAssignment(wrongAssign);
        if (categoryApi == null || wrongAssignCategory == null) {
            return;
        }

        TriggerHandler.bypass('CaseTriggerHandler');
        new adb_CaseRoutingRule_c()
            .name('WrongAssign ' + String.valueOf(Math.abs(Crypto.getRandomInteger())))
            .isActive(true)
            .priority(1)
            .caseAssignment(wrongAssign)
            .subjectSearchString('TWORULETOKEN')
            .categoryValue(wrongAssignCategory);
        new adb_CaseRoutingRule_c()
            .name('RightAssign ' + String.valueOf(Math.abs(Crypto.getRandomInteger())))
            .isActive(true)
            .priority(2)
            .caseAssignment(assign)
            .subjectSearchString('TWORULETOKEN')
            .suppliedEmailFromAddress('two@test.org')
            .categoryValue(categoryApi);
        adb_DomainBuilder.save();
        TriggerHandler.clearBypass('CaseTriggerHandler');

        Case candidate = (Case) new adb_Case()
            .subject('prefix TWORULETOKEN suffix')
            .origin(assign)
            .suppliedEmail('two@test.org')
            .record;
        candidate.RecordTypeId = inboxRt;
        candidate.AccountId = routingAccId;

        Test.startTest();
        List<Case> routed = CasesService.applyCaseRoutingRules(new List<Case>{ candidate });
        Test.stopTest();

        System.Assert.areEqual(1, routed.size());
        System.Assert.areEqual(categoryApi, routed[0].Category__c);
    }

    /**
     * @description Jira GW-1279 — IsSystemGenerated__c stamps CaseSource__c when field accepts configured value.
     */
    @IsTest
    static void testApplyCaseRoutingRules_systemGeneratedStampsCaseSource() {
        Id inboxRt = Schema.SObjectType.Case.getRecordTypeInfosByName().get('Inbox Support')?.getRecordTypeId();
        if (inboxRt == null) {
            return;
        }
        Schema.DescribeFieldResult dfr = Case.CaseSource__c.getDescribe();
        if (!dfr.isCreateable() || !dfr.isUpdateable()) {
            return;
        }
        Boolean hasSystem = false;
        if (dfr.getType() == Schema.DisplayType.PICKLIST || dfr.getType() == Schema.DisplayType.MULTIPICKLIST) {
            for (Schema.PicklistEntry pe : dfr.getPicklistValues()) {
                if (pe.isActive() && pe.getValue() == 'System') {
                    hasSystem = true;
                    break;
                }
            }
        } else {
            hasSystem = true;
        }
        if (!hasSystem) {
            return;
        }

        Id routingAccId = routingTestAccountId();

        String assign = routingTestCaseAssignment();
        String categoryApi = routingCategoryApiValue();
        if (categoryApi == null) {
            return;
        }

        TriggerHandler.bypass('CaseTriggerHandler');
        new adb_CaseRoutingRule_c()
            .name('SysGen ' + String.valueOf(Math.abs(Crypto.getRandomInteger())))
            .isActive(true)
            .priority(1)
            .caseAssignment(assign)
            .subjectSearchString('SYSGENTOKEN')
            .suppliedEmailFromAddress('sysgen@test.org')
            .categoryValue(categoryApi)
            .isSystemGenerated(true);
        adb_DomainBuilder.save();
        TriggerHandler.clearBypass('CaseTriggerHandler');

        Case candidate = (Case) new adb_Case()
            .subject('x SYSGENTOKEN y')
            .origin(assign)
            .suppliedEmail('sysgen@test.org')
            .record;
        candidate.RecordTypeId = inboxRt;
        candidate.AccountId = routingAccId;

        Test.startTest();
        List<Case> routed = CasesService.applyCaseRoutingRules(new List<Case>{ candidate });
        Test.stopTest();

        System.Assert.areEqual(1, routed.size());
        System.Assert.areEqual('System', routed[0].CaseSource__c);
    }

    /**
     * @description Jira GW-1279 — applyCaseRoutingRules stamps category, subcategory, close reason, label, and CaseSource.
     */
    @IsTest
    static void testApplyCaseRoutingRules_stampsFullMatchingRuleCombo() {
        beginGw1279RoutingHelpers();
        Id inboxRt = Schema.SObjectType.Case.getRecordTypeInfosByName().get('Inbox Support')?.getRecordTypeId();
        if (inboxRt == null) {
            return;
        }
        List<String> combo = routingCategorySubcategoryCloseForInbox();
        if (combo == null || combo.size() < 4) {
            return;
        }
        String origin = combo[0];
        String categoryApi = combo[1];
        String subCategoryApi = combo[2];
        String closeApi = combo[3];
        Id routingAccId = routingTestAccountId();
        String labelApi = firstActiveLabelValueApi();

        TriggerHandler.bypass('CaseTriggerHandler');
        adb_CaseRoutingRule_c ruleBuilder = new adb_CaseRoutingRule_c()
            .name('FullCombo ' + String.valueOf(Math.abs(Crypto.getRandomInteger())))
            .isActive(true)
            .priority(1)
            .caseAssignment(origin)
            .subjectSearchString('MATCHME')
            .suppliedEmailFromAddress('matchme@test.org')
            .categoryValue(categoryApi)
            .subCategoryValue(subCategoryApi)
            .closeCode(closeApi)
            .isSystemGenerated(true);
        if (labelApi != null) {
            ruleBuilder.labelValue(labelApi);
        }
        adb_DomainBuilder.save();
        TriggerHandler.clearBypass('CaseTriggerHandler');

        Case candidate = (Case) new adb_Case()
            .subject('contains MATCHME token')
            .origin(origin)
            .suppliedEmail('matchme@test.org')
            .record;
        candidate.RecordTypeId = inboxRt;
        candidate.AccountId = routingAccId;

        Test.startTest();
        List<Case> routed = CasesService.applyCaseRoutingRules(new List<Case>{ candidate });
        Test.stopTest();

        System.Assert.areEqual(1, routed.size());
        System.Assert.areEqual(categoryApi, routed[0].Category__c);
        System.Assert.areEqual(subCategoryApi, routed[0].SubCategory__c);
        System.Assert.areEqual(closeApi, routed[0].CloseReason__c);
        System.Assert.areEqual('Closed', routed[0].Status);
        if (labelApi != null) {
            System.Assert.areEqual(labelApi, routed[0].Label__c);
        }
        Schema.DescribeFieldResult caseSourceDfr = Case.CaseSource__c.getDescribe();
        if (caseSourceDfr.isCreateable()) {
            System.Assert.areEqual('System', routed[0].CaseSource__c);
        }
    }

    /**
     * @description Jira GW-1279 — applyCaseRoutingRules returns empty for null or empty input
     */
    @IsTest
    static void testApplyCaseRoutingRules_nullOrEmptyInput() {
        Test.startTest();
        System.Assert.isTrue(CasesService.applyCaseRoutingRules(null).isEmpty());
        System.Assert.isTrue(CasesService.applyCaseRoutingRules(new List<Case>()).isEmpty());
        Test.stopTest();
    }

    /**
     * @description Jira GW-1279 — getCaseAssignmentOrigins collects distinct Origins from adb_Case-built rows
     */
    @IsTest
    static void testGetCaseAssignmentOrigins_fromAdbCases() {
        Case emailCase = (Case) new adb_Case().origin('Email').subject('E1').record;
        Case dupOrigin = (Case) new adb_Case().origin('Email').subject('E2').record;
        Case phoneCase = (Case) new adb_Case().origin('Phone').subject('P1').record;
        Test.startTest();
        Set<String> origins = CasesService.getCaseAssignmentOrigins(
            new List<Case>{ emailCase, dupOrigin, phoneCase }
        );
        Test.stopTest();
        System.Assert.areEqual(2, origins.size());
        System.Assert.isTrue(origins.contains('Email'));
        System.Assert.isTrue(origins.contains('Phone'));
    }

    /**
     * @description Jira GW-1279 — applyCaseRoutingRules stamps Case fields from first matching adb_CaseRoutingRule__c rule
     */
    @IsTest
    static void testApplyCaseRoutingRules_stampsCaseFromActiveRule() {
        Id inboxRt = Schema.SObjectType.Case.getRecordTypeInfosByName().get('Inbox Support')?.getRecordTypeId();
        if (inboxRt == null) {
            return;
        }
        Id routingAccId = routingTestAccountId();

        String assign = routingTestCaseAssignment();
        String categoryApi = routingCategoryApiValue();
        if (categoryApi == null) {
            return;
        }
        TriggerHandler.bypass('CaseTriggerHandler');
        adb_CaseRoutingRule_c routingRule = new adb_CaseRoutingRule_c()
            .name('SvcRule ' + String.valueOf(Math.abs(Crypto.getRandomInteger())))
            .isActive(true)
            .priority(1)
            .caseAssignment(assign)
            .subjectSearchString('MATCHTOKEN')
            .suppliedEmailFromAddress('client@test.org')
            .categoryValue(categoryApi);
        System.assertNotEquals(null, routingRule);
        adb_DomainBuilder.save();
        TriggerHandler.clearBypass('CaseTriggerHandler');

        Case candidate = (Case) new adb_Case()
            .subject('prefix MATCHTOKEN suffix')
            .origin(assign)
            .suppliedEmail('client@test.org')
            .record;
        candidate.RecordTypeId = inboxRt;
        candidate.AccountId = routingAccId;

        Test.startTest();
        List<Case> routed = CasesService.applyCaseRoutingRules(new List<Case>{ candidate });
        Test.stopTest();

        System.Assert.areEqual(1, routed.size(), 'Inbox Support + email should survive filter');
        System.Assert.areEqual(categoryApi, routed[0].Category__c);
    }

    /**
     * @description Jira GW-1279 — applyCaseRoutingRules returns no rows when Case is not Inbox Support record type
     */
    @IsTest
    static void testApplyCaseRoutingRules_filtersOutNonInboxSupport() {
        Id inboxRt = Schema.SObjectType.Case.getRecordTypeInfosByName().get('Inbox Support')?.getRecordTypeId();
        Id cbmRt = Schema.SObjectType.Case.getRecordTypeInfosByName().get('CBM Case')?.getRecordTypeId();
        if (inboxRt == null || cbmRt == null || cbmRt == inboxRt) {
            return;
        }
        Id routingAccId = routingTestAccountId();
        Case cbmCase = (Case) new adb_Case()
            .subject('MATCHTOKEN')
            .origin(primaryCaseAssignmentMatchingOrigin())
            .suppliedEmail('client@test.org')
            .record;
        cbmCase.RecordTypeId = cbmRt;
        cbmCase.AccountId = routingAccId;

        Test.startTest();
        List<Case> routed = CasesService.applyCaseRoutingRules(new List<Case>{ cbmCase });
        Test.stopTest();
        System.Assert.isTrue(routed.isEmpty(), 'Non Inbox Support cases should be removed from routing set');
    }

    /**
     * @description Jira GW-1279 — applyCaseRoutingRules rethrows Cases.SecurityException when run-as user cannot create Cases.
     */
    @IsTest
    static void testApplyCaseRoutingRules_runAsWithoutCaseCreateThrowsSecurityException() {
        User restricted = routingReadOnlyTestUser();
        if (restricted == null) {
            return;
        }
        Id inboxRt = Schema.SObjectType.Case.getRecordTypeInfosByName().get('Inbox Support')?.getRecordTypeId();
        if (inboxRt == null) {
            return;
        }
        Id routingAccId = routingTestAccountId();
        Case candidate = (Case) new adb_Case()
            .subject('RunAs routing security')
            .origin(primaryCaseAssignmentMatchingOrigin())
            .suppliedEmail('runassec@test.org')
            .record;
        candidate.RecordTypeId = inboxRt;
        candidate.AccountId = routingAccId;

        Test.startTest();
        System.runAs(restricted) {
            try {
                CasesService.applyCaseRoutingRules(new List<Case>{ candidate });
                System.Assert.fail('Expected Cases.SecurityException when Case is not createable');
            } catch (Cases.SecurityException expected) {
                System.Assert.isTrue(
                    String.isNotBlank(expected.getMessage()),
                    'SecurityException should include a message'
                );
            }
        }
        Test.stopTest();
    }

    /**
     * @description Jira GW-1279 — getCaseAssignmentOrigins returns empty for null or empty input
     */
    @IsTest
    static void testGetCaseAssignmentOrigins_nullOrEmptyInput() {
        Test.startTest();
        System.Assert.isTrue(CasesService.getCaseAssignmentOrigins(null).isEmpty());
        System.Assert.isTrue(CasesService.getCaseAssignmentOrigins(new List<Case>()).isEmpty());
        Test.stopTest();
    }

    /**
     * @description Jira GW-1279 — no active rules for Case Origin leaves findMatchingRulesAndPopulateCase with empty rule list.
     */
    @IsTest
    static void testApplyCaseRoutingRules_noActiveRulesForOriginSkipsStamp() {
        Id inboxRt = Schema.SObjectType.Case.getRecordTypeInfosByName().get('Inbox Support')?.getRecordTypeId();
        if (inboxRt == null) {
            return;
        }
        Id routingAccId = routingTestAccountId();
        String uniqueOrigin = 'Gw1279NoRuleOrigin' + String.valueOf(Math.abs(Crypto.getRandomInteger()));

        Case candidate = (Case) new adb_Case()
            .subject('No rules for this origin')
            .origin(uniqueOrigin)
            .suppliedEmail('noruleorigin@test.org')
            .record;
        candidate.RecordTypeId = inboxRt;
        candidate.AccountId = routingAccId;

        Test.startTest();
        List<Case> routed = CasesService.applyCaseRoutingRules(new List<Case>{ candidate });
        Test.stopTest();

        System.Assert.areEqual(1, routed.size());
        System.Assert.isTrue(String.isBlank(routed[0].Category__c));
    }

    /**
     * @description Jira GW-1279 — CloseCode__c on rule sets Case Status to Closed and stamps CloseReason__c.
     */
    @IsTest
    static void testApplyCaseRoutingRules_closeCodeSetsStatusClosed() {
        Id inboxRt = Schema.SObjectType.Case.getRecordTypeInfosByName().get('Inbox Support')?.getRecordTypeId();
        if (inboxRt == null) {
            return;
        }
        Id routingAccId = routingTestAccountId();
        String assign = routingTestCaseAssignment();
        List<String> catClose = routingCategoryAndCloseApiValuesForInbox();
        if (catClose == null || catClose.size() < 2) {
            return;
        }
        String categoryApi = catClose[0];
        String closeApi = catClose[1];

        TriggerHandler.bypass('CaseTriggerHandler');
        new adb_CaseRoutingRule_c()
            .name('CloseRule ' + String.valueOf(Math.abs(Crypto.getRandomInteger())))
            .isActive(true)
            .priority(1)
            .caseAssignment(assign)
            .subjectSearchString('CLOSETOK')
            .suppliedEmailFromAddress('closecode@test.org')
            .categoryValue(categoryApi)
            .closeCode(closeApi);
        adb_DomainBuilder.save();
        TriggerHandler.clearBypass('CaseTriggerHandler');

        Case candidate = (Case) new adb_Case()
            .subject('prefix CLOSETOK suffix')
            .origin(assign)
            .suppliedEmail('closecode@test.org')
            .record;
        candidate.RecordTypeId = inboxRt;
        candidate.AccountId = routingAccId;

        Test.startTest();
        List<Case> routed = CasesService.applyCaseRoutingRules(new List<Case>{ candidate });
        Test.stopTest();

        System.Assert.areEqual(1, routed.size());
        System.Assert.areEqual('Closed', routed[0].Status);
        System.Assert.areEqual(closeApi, routed[0].CloseReason__c);
        System.Assert.areEqual(categoryApi, routed[0].Category__c);
    }

    /**
     * @description Jira GW-1279 — applyCaseRoutingRules stamps SubCategory__c when resolver allows it.
     */
    @IsTest
    static void testApplyCaseRoutingRules_stampsSubcategoryFromRule() {
        Id inboxRt = Schema.SObjectType.Case.getRecordTypeInfosByName().get('Inbox Support')?.getRecordTypeId();
        if (inboxRt == null) {
            return;
        }
        String assign = routingTestCaseAssignment();
        String categoryApi = routingCategoryApiValue();
        if (categoryApi == null) {
            return;
        }
        String subApi = firstResolvedSubcategoryForCategory(inboxRt, assign, categoryApi);
        if (subApi == null) {
            return;
        }
        Id routingAccId = routingTestAccountId();

        TriggerHandler.bypass('CaseTriggerHandler');
        new adb_CaseRoutingRule_c()
            .name('SubStamp ' + String.valueOf(Math.abs(Crypto.getRandomInteger())))
            .isActive(true)
            .priority(1)
            .caseAssignment(assign)
            .subjectSearchString('SUBSTAMPTOK')
            .suppliedEmailFromAddress('substamp@test.org')
            .categoryValue(categoryApi)
            .subCategoryValue(subApi);
        adb_DomainBuilder.save();
        TriggerHandler.clearBypass('CaseTriggerHandler');

        Case candidate = (Case) new adb_Case()
            .subject('prefix SUBSTAMPTOK suffix')
            .origin(assign)
            .suppliedEmail('substamp@test.org')
            .record;
        candidate.RecordTypeId = inboxRt;
        candidate.AccountId = routingAccId;

        Test.startTest();
        List<Case> routed = CasesService.applyCaseRoutingRules(new List<Case>{ candidate });
        Test.stopTest();

        System.Assert.areEqual(1, routed.size());
        System.Assert.areEqual(categoryApi, routed[0].Category__c);
        System.Assert.areEqual(subApi, routed[0].SubCategory__c);
    }

    /**
     * @description Jira GW-1279 — applyCaseRoutingRules stamps LabelValue__c from matched rule.
     */
    @IsTest
    static void testApplyCaseRoutingRules_stampsLabelFromRule() {
        Id inboxRt = Schema.SObjectType.Case.getRecordTypeInfosByName().get('Inbox Support')?.getRecordTypeId();
        if (inboxRt == null) {
            return;
        }
        Id routingAccId = routingTestAccountId();
        String assign = routingTestCaseAssignment();
        String categoryApi = routingCategoryApiValue();
        if (categoryApi == null) {
            return;
        }
        String labelApi = firstActiveLabelValueApi();
        if (labelApi == null) {
            return;
        }

        TriggerHandler.bypass('CaseTriggerHandler');
        new adb_CaseRoutingRule_c()
            .name('LabelStamp ' + String.valueOf(Math.abs(Crypto.getRandomInteger())))
            .isActive(true)
            .priority(1)
            .caseAssignment(assign)
            .subjectSearchString('LABELSTAMPTOK')
            .suppliedEmailFromAddress('labelstamp@test.org')
            .categoryValue(categoryApi)
            .labelValue(labelApi);
        adb_DomainBuilder.save();
        TriggerHandler.clearBypass('CaseTriggerHandler');

        Case candidate = (Case) new adb_Case()
            .subject('LABELSTAMPTOK here')
            .origin(assign)
            .suppliedEmail('labelstamp@test.org')
            .record;
        candidate.RecordTypeId = inboxRt;
        candidate.AccountId = routingAccId;

        Test.startTest();
        List<Case> routed = CasesService.applyCaseRoutingRules(new List<Case>{ candidate });
        Test.stopTest();

        System.Assert.areEqual(1, routed.size());
        System.Assert.areEqual(labelApi, routed[0].Label__c);
    }

    /**
     * @description Jira GW-1279 — rule CaseAssignment__c mismatch with Case.Origin skips rule (continue branch).
     */
    @IsTest
    static void testApplyCaseRoutingRules_originMismatchSkipsRule() {
        Id inboxRt = Schema.SObjectType.Case.getRecordTypeInfosByName().get('Inbox Support')?.getRecordTypeId();
        if (inboxRt == null) {
            return;
        }
        String assign = routingTestCaseAssignment();
        String wrongAssign = alternateCaseAssignmentApi(assign);
        if (wrongAssign == assign) {
            return;
        }
        String wrongAssignCategory = firstRuleCategoryForCaseAssignment(wrongAssign);
        if (wrongAssignCategory == null) {
            return;
        }
        Id routingAccId = routingTestAccountId();

        TriggerHandler.bypass('CaseTriggerHandler');
        new adb_CaseRoutingRule_c()
            .name('OriginMiss ' + String.valueOf(Math.abs(Crypto.getRandomInteger())))
            .isActive(true)
            .priority(1)
            .caseAssignment(wrongAssign)
            .subjectSearchString('ORIGINMISSTOK')
            .categoryValue(wrongAssignCategory);
        adb_DomainBuilder.save();
        TriggerHandler.clearBypass('CaseTriggerHandler');

        Case candidate = (Case) new adb_Case()
            .subject('ORIGINMISSTOK in subject')
            .origin(assign)
            .suppliedEmail('originmiss@test.org')
            .record;
        candidate.RecordTypeId = inboxRt;
        candidate.AccountId = routingAccId;

        Test.startTest();
        List<Case> routed = CasesService.applyCaseRoutingRules(new List<Case>{ candidate });
        Test.stopTest();

        System.Assert.areEqual(1, routed.size());
        System.Assert.isTrue(String.isBlank(routed[0].Category__c));
    }

    /**
     * @description Jira GW-1279 — blank Case Description skips rule when DescriptionSearchString__c is populated.
     */
    @IsTest
    static void testApplyCaseRoutingRules_blankDescriptionSkipsWhenRuleRequiresDescription() {
        Id inboxRt = Schema.SObjectType.Case.getRecordTypeInfosByName().get('Inbox Support')?.getRecordTypeId();
        if (inboxRt == null) {
            return;
        }
        Id routingAccId = routingTestAccountId();
        String assign = routingTestCaseAssignment();
        String categoryApi = routingCategoryApiValue();
        if (categoryApi == null) {
            return;
        }

        TriggerHandler.bypass('CaseTriggerHandler');
        new adb_CaseRoutingRule_c()
            .name('DescBlank ' + String.valueOf(Math.abs(Crypto.getRandomInteger())))
            .isActive(true)
            .priority(1)
            .caseAssignment(assign)
            .suppliedEmailFromAddress('dblank@test.org')
            .descriptionSearchString('REQDESC')
            .categoryValue(categoryApi);
        adb_DomainBuilder.save();
        TriggerHandler.clearBypass('CaseTriggerHandler');

        Case candidate = (Case) new adb_Case()
            .subject('Subject only')
            .origin(assign)
            .suppliedEmail('dblank@test.org')
            .record;
        candidate.RecordTypeId = inboxRt;
        candidate.AccountId = routingAccId;
        candidate.Description = null;

        Test.startTest();
        List<Case> routed = CasesService.applyCaseRoutingRules(new List<Case>{ candidate });
        Test.stopTest();

        System.Assert.areEqual(1, routed.size());
        System.Assert.isTrue(String.isBlank(routed[0].Category__c));
    }

    /**
     * @description Jira GW-1279 — supplied email match is case-insensitive against rule SuppliedEmailFromAddress__c.
     */
    @IsTest
    static void testApplyCaseRoutingRules_emailMatchIsCaseInsensitive() {
        Id inboxRt = Schema.SObjectType.Case.getRecordTypeInfosByName().get('Inbox Support')?.getRecordTypeId();
        if (inboxRt == null) {
            return;
        }
        Id routingAccId = routingTestAccountId();
        String assign = routingTestCaseAssignment();
        String categoryApi = routingCategoryApiValue();
        if (categoryApi == null) {
            return;
        }

        TriggerHandler.bypass('CaseTriggerHandler');
        new adb_CaseRoutingRule_c()
            .name('CiEmail ' + String.valueOf(Math.abs(Crypto.getRandomInteger())))
            .isActive(true)
            .priority(1)
            .caseAssignment(assign)
            .subjectSearchString('CIEMAILTOK')
            .suppliedEmailFromAddress('CaseOnly@Example.org')
            .categoryValue(categoryApi);
        adb_DomainBuilder.save();
        TriggerHandler.clearBypass('CaseTriggerHandler');

        Case candidate = (Case) new adb_Case()
            .subject('CIEMAILTOK in subject')
            .origin(assign)
            .suppliedEmail('caseonly@example.org')
            .record;
        candidate.RecordTypeId = inboxRt;
        candidate.AccountId = routingAccId;

        Test.startTest();
        List<Case> routed = CasesService.applyCaseRoutingRules(new List<Case>{ candidate });
        Test.stopTest();

        System.Assert.areEqual(1, routed.size());
        System.Assert.areEqual(categoryApi, routed[0].Category__c);
    }

}