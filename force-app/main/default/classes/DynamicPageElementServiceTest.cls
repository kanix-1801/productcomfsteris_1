/**
 * @date 2026/07/28
 *
 * @group Account Management
 *
 * @description
 * Unit tests for DynamicPageElementService tree building and layout assembly.
 * GC-3183
 */
@IsTest(SeeAllData=false)
private class DynamicPageElementServiceTest {

    /**
     * @description
     * Resets shared mocks before each test method runs.
     */
    private static void resetMocks() {
        DynamicPageElementSelector.mockConfigs = null;
        DynamicPageAccessResolver.mockAccessLevel = null;
        DynamicPageAccessResolver.mockIsAccountTeamMember = null;
        DynamicPageAccessRuleSelector.mockRule = null;
    }

    /**
     * @description
     * Builds a single in-memory DynamicPageElement metadata record for testing.
     */
    private static DynamicPageElement__mdt buildConfig(
        String accessLevel,
        String elementType,
        String apiName,
        String parentApiName,
        String label,
        String objectApiName,
        String fieldApiName,
        String column,
        Decimal displayOrder
    ) {
        DynamicPageElement__mdt config = new DynamicPageElement__mdt();
        config.PageName__c = 'Customer360';
        config.AccessLevel__c = accessLevel;
        config.ElementType__c = elementType;
        config.ApiName__c = apiName;
        config.ParentApiName__c = parentApiName;
        config.Label__c = label;
        config.ObjectAPIName__c = objectApiName;
        config.FieldAPIName__c = fieldApiName;
        config.Column__c = column;
        config.DisplayOrder__c = displayOrder;
        config.IsVisible__c = true;
        config.IsEditable__c = false;
        return config;
    }

    /**
     * @description
     * Verifies dedupe keeps the first record when no Full duplicate exists.
     */
    @IsTest
    static void testDedupeByApiNameKeepsFirstRecordWhenNoFullDuplicate() {
        resetMocks();

        List<DynamicPageElement__mdt> records = new List<DynamicPageElement__mdt>{
            buildConfig('Base', 'Tab', 'DetailsTab', null, 'Details', null, null, null, 10),
            buildConfig('Base', 'Field', 'DetailsTabName', 'DetailsTab', null, 'Account', 'Name', 'Left', 10),
            buildConfig('Base', 'Field', 'DetailsTabName', 'DetailsTab', null, 'Account', 'Phone', 'Left', 20)
        };

        Test.startTest();
        List<DynamicPageElement__mdt> deduped = DynamicPageElementService.dedupeByApiName(records);
        Test.stopTest();

        Map<String, DynamicPageElement__mdt> byApiName = new Map<String, DynamicPageElement__mdt>();
        for (DynamicPageElement__mdt record : deduped) {
            byApiName.put(record.ApiName__c, record);
        }

        System.assertEquals('Name', byApiName.get('DetailsTabName').FieldAPIName__c);
    }

    /**
     * @description
     * Verifies tabs are sorted by DisplayOrder__c when building the layout tree.
     */
    @IsTest
    static void testBuildTabsSortsByDisplayOrder() {
        resetMocks();

        DynamicPageElementSelector.mockConfigs = new List<DynamicPageElement__mdt>{
            buildConfig('Base', 'Tab', 'SecondTab', null, 'Second', null, null, null, 20),
            buildConfig('Base', 'Tab', 'FirstTab', null, 'First', null, null, null, 10)
        };
        DynamicPageAccessResolver.mockAccessLevel = 'Base';

        Account testAccount = new Account(
            Name = 'Service Test Account Sort',
            SourceSystemID__c = 'TEST-SERVICE-SORT-001'
        );
        insert testAccount;

        Test.startTest();
        DynamicPageElementService.DynamicPageElementResponse response =
            DynamicPageElementService.getPageLayout(testAccount.Id, 'Account', 'Customer360');
        Test.stopTest();

        System.assertEquals(2, response.tabs.size());
        System.assertEquals('FirstTab', response.tabs[0].apiName);
        System.assertEquals('SecondTab', response.tabs[1].apiName);
    }

    /**
     * @description
     * Verifies editable sections and blank field columns are mapped correctly.
     */
    @IsTest
    static void testBuildSectionWithEditableFieldAndDefaultColumn() {
        resetMocks();

        DynamicPageElement__mdt section = buildConfig(
            'Base', 'Section', 'EditableSection', 'DetailsTab', 'Editable Section', null, null, null, 10
        );
        section.IsEditable__c = true;

        DynamicPageElement__mdt field = buildConfig(
            'Base', 'Field', 'EditableSectionField', 'EditableSection', null, 'Account', 'Website', null, 10
        );

        DynamicPageElementSelector.mockConfigs = new List<DynamicPageElement__mdt>{
            buildConfig('Base', 'Tab', 'DetailsTab', null, 'Details', null, null, null, 10),
            section,
            field
        };
        DynamicPageAccessResolver.mockAccessLevel = 'Base';

        Account testAccount = new Account(
            Name = 'Service Test Account Section',
            SourceSystemID__c = 'TEST-SERVICE-SECTION-001'
        );
        insert testAccount;

        Test.startTest();
        DynamicPageElementService.DynamicPageElementResponse response =
            DynamicPageElementService.getPageLayout(testAccount.Id, 'Account', 'Customer360');
        Test.stopTest();

        System.assertEquals(1, response.tabs[0].sections.size());
        System.assertEquals(true, response.tabs[0].sections[0].isEditable);
        System.assertEquals('Left', response.tabs[0].sections[0].elements[0].column);
    }

    /**
     * @description
     * Verifies tabs without children return empty child collections.
     */
    @IsTest
    static void testBuildTabWithNoChildren() {
        resetMocks();

        DynamicPageElementSelector.mockConfigs = new List<DynamicPageElement__mdt>{
            buildConfig('Base', 'Tab', 'EmptyTab', null, 'Empty', null, null, null, 10)
        };
        DynamicPageAccessResolver.mockAccessLevel = 'Base';

        Account testAccount = new Account(
            Name = 'Service Test Account Empty Tab',
            SourceSystemID__c = 'TEST-SERVICE-EMPTY-001'
        );
        insert testAccount;

        Test.startTest();
        DynamicPageElementService.DynamicPageElementResponse response =
            DynamicPageElementService.getPageLayout(testAccount.Id, 'Account', 'Customer360');
        Test.stopTest();

        System.assertEquals(1, response.tabs.size());
        System.assertEquals(0, response.tabs[0].sections.size());
        System.assertEquals(0, response.tabs[0].elements.size());
        System.assertEquals(0, response.tabs[0].fieldLists.size());
    }

    /**
     * @description
     * Verifies getPageLayout can use deployed CMDT through the selector without mocks.
     */
    @IsTest
    static void testGetPageLayoutUsesDeployedMetadataForFullAccess() {
        resetMocks();

        DynamicPageAccessRule__mdt rule = new DynamicPageAccessRule__mdt();
        rule.PageName__c = 'Customer360';
        rule.ObjectAPIName__c = 'Account';
        rule.AccessStrategy__c = DynamicPageAccessResolver.STRATEGY_ALWAYS_FULL;
        rule.BaseAccessValue__c = 'Base';
        rule.FullAccessValue__c = 'Full';
        DynamicPageAccessRuleSelector.mockRule = rule;

        Account testAccount = new Account(
            Name = 'Service Test Account Full Metadata',
            SourceSystemID__c = 'TEST-SERVICE-FULL-001'
        );
        insert testAccount;

        Test.startTest();
        DynamicPageElementService.DynamicPageElementResponse response =
            DynamicPageElementService.getPageLayout(testAccount.Id, 'Account', 'Customer360');
        Test.stopTest();

        System.assertEquals('Full', response.accessLevel);
        System.assert(response.tabs.size() > 0, 'Expected tabs from deployed Customer360 metadata.');
    }

    /**
     * @description
     * Verifies records with blank ParentApiName__c are excluded from child grouping.
     */
    @IsTest
    static void testBuildTabsIgnoresOrphanRecordsWithoutParent() {
        resetMocks();

        DynamicPageElementSelector.mockConfigs = new List<DynamicPageElement__mdt>{
            buildConfig('Base', 'Tab', 'DetailsTab', null, 'Details', null, null, null, 10),
            buildConfig('Base', 'Field', 'OrphanField', null, null, 'Account', 'Name', 'Left', 10)
        };
        DynamicPageAccessResolver.mockAccessLevel = 'Base';

        Account testAccount = new Account(
            Name = 'Service Test Account Orphan',
            SourceSystemID__c = 'TEST-SERVICE-ORPHAN-001'
        );
        insert testAccount;

        Test.startTest();
        DynamicPageElementService.DynamicPageElementResponse response =
            DynamicPageElementService.getPageLayout(testAccount.Id, 'Account', 'Customer360');
        Test.stopTest();

        System.assertEquals(0, response.tabs[0].elements.size());
    }

    /**
     * @description
     * Verifies sections without child records return an empty element collection.
     */
    @IsTest
    static void testBuildSectionWithNoChildren() {
        resetMocks();

        DynamicPageElementSelector.mockConfigs = new List<DynamicPageElement__mdt>{
            buildConfig('Base', 'Tab', 'DetailsTab', null, 'Details', null, null, null, 10),
            buildConfig('Base', 'Section', 'EmptySection', 'DetailsTab', 'Empty Section', null, null, null, 10)
        };
        DynamicPageAccessResolver.mockAccessLevel = 'Base';

        Account testAccount = new Account(
            Name = 'Service Test Account Empty Section',
            SourceSystemID__c = 'TEST-SERVICE-EMPTY-SECTION-001'
        );
        insert testAccount;

        Test.startTest();
        DynamicPageElementService.DynamicPageElementResponse response =
            DynamicPageElementService.getPageLayout(testAccount.Id, 'Account', 'Customer360');
        Test.stopTest();

        System.assertEquals(1, response.tabs[0].sections.size());
        System.assertEquals(0, response.tabs[0].sections[0].elements.size());
    }

    /**
     * @description
     * Verifies tabs with equal DisplayOrder__c values still build successfully.
     */
    @IsTest
    static void testBuildTabsHandlesEqualDisplayOrder() {
        resetMocks();

        DynamicPageElementSelector.mockConfigs = new List<DynamicPageElement__mdt>{
            buildConfig('Base', 'Tab', 'TabA', null, 'Tab A', null, null, null, 10),
            buildConfig('Base', 'Tab', 'TabB', null, 'Tab B', null, null, null, 10)
        };
        DynamicPageAccessResolver.mockAccessLevel = 'Base';

        Account testAccount = new Account(
            Name = 'Service Test Account Equal Order',
            SourceSystemID__c = 'TEST-SERVICE-EQUAL-ORDER-001'
        );
        insert testAccount;

        Test.startTest();
        DynamicPageElementService.DynamicPageElementResponse response =
            DynamicPageElementService.getPageLayout(testAccount.Id, 'Account', 'Customer360');
        Test.stopTest();

        System.assertEquals(2, response.tabs.size());
    }
}