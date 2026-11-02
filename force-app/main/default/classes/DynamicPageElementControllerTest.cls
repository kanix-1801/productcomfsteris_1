/**
 * @date 2026/07/22
 *
 * @group Account Management
 *
 * @description
 * Test class for DynamicPageElementController, DynamicPageElementService, and DynamicPageElementSelector.
 * Validates Base and Full access levels, layout tree building for direct fields and
 * sections, deduplication behavior, and input validation.
 * GC-3183
 */
@IsTest(SeeAllData=false)
private class DynamicPageElementControllerTest {

    /**
     * @description
     * Creates shared Account test data for all test methods.
     */
    @TestSetup
    static void setupData() {
        insert new Account(
            Name = 'Page Layout Test Account',
            SourceSystemID__c = 'TEST-PAGE-LAYOUT-001'
        );
    }

    /**
     * @description
     * Retrieves the test Account created during TestSetup.
     *
     * @return Account record used as test input.
     */
    private static Account getTestAccount() {
        return [
            SELECT Id
            FROM Account
            WHERE Name = 'Page Layout Test Account'
            LIMIT 1
        ];
    }

    /**
     * @description
     * Resets selector mock variables to null before each test execution.
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
     *
     * @param accessLevel AccessLevel__c value, such as Base or Full.
     * @param elementType ElementType__c value, such as Tab, Section, or Field.
     * @param apiName ApiName__c value for the metadata row.
     * @param parentApiName ParentApiName__c value linking the row to its parent.
     * @param label Label__c value used for tab and section rows.
     * @param objectApiName ObjectAPIName__c value for field rows.
     * @param fieldApiName FieldAPIName__c value for field rows.
     * @param column Column__c value for field rows.
     * @param displayOrder DisplayOrder__c sort value.
     * @return Mock DynamicPageElement metadata record.
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
     * Builds a mock FieldList layout with left/right CSV columns under a tab.
     *
     * @return List of mock metadata records representing a tab with one FieldList row.
     */
    private static List<DynamicPageElement__mdt> buildFieldListLayout() {
        DynamicPageElement__mdt fieldList = buildConfig(
            'Base', 'FieldList', 'DetailsTabFieldList', 'DetailsTab', null, 'Account', null, null, 10
        );
        fieldList.LeftSideFields__c = 'Name*,Phone#,Industry$';
        fieldList.RightSideFields__c = 'AccountSource#,Type$,Status__c#';

        return new List<DynamicPageElement__mdt>{
            buildConfig('Base', 'Tab', 'DetailsTab', null, 'Details', null, null, null, 10),
            fieldList
        };
    }

    /**
     * @description
     * Builds a mock layout where fields are placed directly under a tab.
     *
     * @return List of mock metadata records representing a tab with direct fields.
     */
    private static List<DynamicPageElement__mdt> buildDirectFieldLayout() {
        return new List<DynamicPageElement__mdt>{
            buildConfig('Base', 'Tab', 'DetailsTab', null, 'Details', null, null, null, 10),
            buildConfig('Base', 'Field', 'DetailsTabName', 'DetailsTab', null, 'Account', 'Name', 'Left', 10),
            buildConfig('Base', 'Field', 'DetailsTabPhone', 'DetailsTab', null, 'Account', 'Phone', 'Right', 20)
        };
    }

    /**
     * @description
     * Builds a mock layout where fields are nested under a section within a tab.
     *
     * @return List of mock metadata records representing a tab with one section.
     */
    private static List<DynamicPageElement__mdt> buildSectionLayout() {
        return new List<DynamicPageElement__mdt>{
            buildConfig('Base', 'Tab', 'DetailsTab', null, 'Details', null, null, null, 10),
            buildConfig('Base', 'Section', 'AccountInfoSection', 'DetailsTab', 'Account Information', null, null, null, 10),
            buildConfig('Base', 'Field', 'AccountInfoSectionName', 'AccountInfoSection', null, 'Account', 'Name', 'Left', 10),
            buildConfig('Base', 'Field', 'AccountInfoSectionPhone', 'AccountInfoSection', null, 'Account', 'Phone', 'Right', 20)
        };
    }

    /**
     * @description
     * Builds a mock layout where a registered custom LWC is placed directly under a tab.
     *
     * @return List of mock metadata records representing Tab to Component hierarchy.
     */
    private static List<DynamicPageElement__mdt> buildTabComponentLayout() {
        DynamicPageElement__mdt relatedTab = buildConfig(
            'Base', 'Tab', 'RelatedTab', null, 'Related', null, null, null, 90
        );
        DynamicPageElement__mdt relatedComponent = buildConfig(
            'Base', 'Component', 'RelatedTabRelated', 'RelatedTab', null, null, null, 'Full', 10
        );
        relatedComponent.ComponentAPIName__c = 'relatedTab';
        relatedComponent.PropsJson__c = '{}';

        return new List<DynamicPageElement__mdt>{ relatedTab, relatedComponent };
    }

    /**
     * @description
     * Verifies that Base access returns a tab with direct child fields and no sections.
     */
    @IsTest
    static void testGetPageLayoutDirectFieldsBaseAccess() {
        /********************************************
        * SETUP
        ********************************************/
        resetMocks();
        Account testAccount = getTestAccount();

        DynamicPageAccessResolver.mockAccessLevel = 'Base';
        DynamicPageElementSelector.mockConfigs = buildDirectFieldLayout();

        /********************************************
        * WHEN
        ********************************************/
        DynamicPageElementService.DynamicPageElementResponse response;

        Test.startTest();
        response = DynamicPageElementController.getPageLayout(testAccount.Id, 'Account', 'Customer360');
        Test.stopTest();

        /********************************************
        * THEN
        ********************************************/
        System.assertEquals('Base', response.accessLevel);
        System.assertEquals(1, response.tabs.size());
        System.assertEquals('DetailsTab', response.tabs[0].apiName);
        System.assertEquals(0, response.tabs[0].sections.size());
        System.assertEquals(2, response.tabs[0].elements.size());
        System.assertEquals('Name', response.tabs[0].elements[0].fieldApiName);
    }

    /**
     * @description
     * Verifies that section metadata is transformed into nested section nodes with child fields.
     */
    @IsTest
    static void testGetPageLayoutWithSections() {
        /********************************************
        * SETUP
        ********************************************/
        resetMocks();
        Account testAccount = getTestAccount();

        DynamicPageAccessResolver.mockAccessLevel = 'Base';
        DynamicPageElementSelector.mockConfigs = buildSectionLayout();

        /********************************************
        * WHEN
        ********************************************/
        DynamicPageElementService.DynamicPageElementResponse response;

        Test.startTest();
        response = DynamicPageElementController.getPageLayout(testAccount.Id, 'Account', 'Customer360');
        Test.stopTest();

        /********************************************
        * THEN
        ********************************************/
        System.assertEquals(1, response.tabs.size());
        System.assertEquals(0, response.tabs[0].elements.size());
        System.assertEquals(1, response.tabs[0].sections.size());
        System.assertEquals('Account Information', response.tabs[0].sections[0].label);
        System.assertEquals(2, response.tabs[0].sections[0].elements.size());
    }

    /**
     * @description
     * Verifies that a Component metadata row under a tab is returned as a direct tab element.
     */
    @IsTest
    static void testGetPageLayoutWithTabComponent() {
        /********************************************
        * SETUP
        ********************************************/
        resetMocks();
        Account testAccount = getTestAccount();

        DynamicPageAccessResolver.mockAccessLevel = 'Base';
        DynamicPageElementSelector.mockConfigs = buildTabComponentLayout();

        /********************************************
        * WHEN
        ********************************************/
        DynamicPageElementService.DynamicPageElementResponse response;

        Test.startTest();
        response = DynamicPageElementController.getPageLayout(testAccount.Id, 'Account', 'Customer360');
        Test.stopTest();

        /********************************************
        * THEN
        ********************************************/
        System.assertEquals(1, response.tabs.size());
        System.assertEquals('RelatedTab', response.tabs[0].apiName);
        System.assertEquals(0, response.tabs[0].sections.size());
        System.assertEquals(1, response.tabs[0].elements.size());
        System.assertEquals('Component', response.tabs[0].elements[0].elementType);
        System.assertEquals('relatedTab', response.tabs[0].elements[0].componentApiName);
        System.assertEquals('Full', response.tabs[0].elements[0].column);
    }

    /**
     * @description
     * Verifies that standard component ApiNames and PropsJson pass through the layout tree.
     */
    @IsTest
    static void testGetPageLayoutStandardRelatedListComponent() {
        /********************************************
        * SETUP
        ********************************************/
        resetMocks();
        Account testAccount = getTestAccount();

        DynamicPageAccessResolver.mockAccessLevel = 'Full';

        DynamicPageElement__mdt opportunityTab = buildConfig(
            'Full', 'Tab', 'OpportunityTab', null, 'Opportunity', null, null, null, 30
        );
        DynamicPageElement__mdt opportunityList = buildConfig(
            'Full', 'Component', 'OpportunityTabStdList', 'OpportunityTab', null, null, null, 'Full', 10
        );
        opportunityList.ComponentAPIName__c = 'standard:relatedList';
        opportunityList.PropsJson__c =
            '{"relatedListId":"Opportunities","title":"Opportunities","fields":[' +
            '{"label":"Name","wireField":"Opportunity.Name","fieldName":"name"}' +
            ']}';

        DynamicPageElementSelector.mockConfigs = new List<DynamicPageElement__mdt>{ opportunityTab, opportunityList };

        /********************************************
        * WHEN
        ********************************************/
        DynamicPageElementService.DynamicPageElementResponse response;

        Test.startTest();
        response = DynamicPageElementController.getPageLayout(testAccount.Id, 'Account', 'Customer360');
        Test.stopTest();

        /********************************************
        * THEN
        ********************************************/
        System.assertEquals(1, response.tabs.size());
        System.assertEquals('OpportunityTab', response.tabs[0].apiName);
        System.assertEquals(1, response.tabs[0].elements.size());
        System.assertEquals('Component', response.tabs[0].elements[0].elementType);
        System.assertEquals('standard:relatedList', response.tabs[0].elements[0].componentApiName);
        System.assert(
            response.tabs[0].elements[0].propsJson.contains('Opportunities'),
            'PropsJson should include related list configuration'
        );
    }

    /**
     * @description
     * Verifies that duplicate ApiName__c rows prefer the Full access metadata record.
     */
    @IsTest
    static void testFullAccessPrefersFullRecordOnDuplicateApiName() {
        /********************************************
        * SETUP
        ********************************************/
        resetMocks();

        List<DynamicPageElement__mdt> records = new List<DynamicPageElement__mdt>{
            buildConfig('Base', 'Tab', 'DetailsTab', null, 'Details', null, null, null, 10),
            buildConfig('Base', 'Field', 'DetailsTabName', 'DetailsTab', null, 'Account', 'Name', 'Left', 10),
            buildConfig('Full', 'Field', 'DetailsTabName', 'DetailsTab', null, 'Account', 'Website', 'Left', 10)
        };

        /********************************************
        * WHEN
        ********************************************/
        List<DynamicPageElement__mdt> deduped;

        Test.startTest();
        deduped = DynamicPageElementService.dedupeByApiName(records);
        Test.stopTest();

        /********************************************
        * THEN
        ********************************************/
        System.assertEquals(2, deduped.size());

        Map<String, DynamicPageElement__mdt> byApiName = new Map<String, DynamicPageElement__mdt>();
        for (DynamicPageElement__mdt record : deduped) {
            byApiName.put(record.ApiName__c, record);
        }

        System.assertEquals('Website', byApiName.get('DetailsTabName').FieldAPIName__c);
    }

    /**
     * @description
     * Verifies that an AuraHandledException is thrown when record Id is null.
     */
    @IsTest
    static void testMissingRecordIdThrowsError() {
        resetMocks();
        Boolean threw = false;

        Test.startTest();
        try {
            DynamicPageElementController.getPageLayout(null, 'Account', 'Customer360');
        } catch (AuraHandledException ex) {
            threw = true;
        }
        Test.stopTest();

        System.assertEquals(true, threw, 'Expected AuraHandledException for missing record Id.');
    }

    /**
     * @description
     * Verifies that an AuraHandledException is thrown when object API name is blank.
     */
    @IsTest
    static void testBlankObjectApiNameThrowsError() {
        resetMocks();
        Account testAccount = getTestAccount();
        Boolean threw = false;

        Test.startTest();
        try {
            DynamicPageElementController.getPageLayout(testAccount.Id, '', 'Customer360');
        } catch (AuraHandledException ex) {
            threw = true;
        }
        Test.stopTest();

        System.assertEquals(true, threw, 'Expected AuraHandledException for blank object API name.');
    }

    /**
     * @description
     * Verifies that an AuraHandledException is thrown when page name is blank.
     */
    @IsTest
    static void testBlankPageNameThrowsError() {
        resetMocks();
        Account testAccount = getTestAccount();
        Boolean threw = false;

        Test.startTest();
        try {
            DynamicPageElementController.getPageLayout(testAccount.Id, 'Account', '');
        } catch (AuraHandledException ex) {
            threw = true;
        }
        Test.stopTest();

        System.assertEquals(true, threw, 'Expected AuraHandledException for blank page name.');
    }

    /**
     * @description
     * Verifies that a FieldList metadata row is parsed into left/right field items on the tab.
     */
    @IsTest
    static void testGetPageLayoutWithFieldList() {
        /********************************************
        * SETUP
        ********************************************/
        resetMocks();
        Account testAccount = getTestAccount();

        DynamicPageAccessResolver.mockAccessLevel = 'Base';
        DynamicPageElementSelector.mockConfigs = buildFieldListLayout();

        /********************************************
        * WHEN
        ********************************************/
        DynamicPageElementService.DynamicPageElementResponse response;

        Test.startTest();
        response = DynamicPageElementController.getPageLayout(testAccount.Id, 'Account', 'Customer360');
        Test.stopTest();

        /********************************************
        * THEN
        ********************************************/
        System.assertEquals(1, response.tabs.size());
        System.assertEquals(0, response.tabs[0].elements.size());
        System.assertEquals(1, response.tabs[0].fieldLists.size());

        DynamicPageElementService.FieldListNode fieldList = response.tabs[0].fieldLists[0];
        System.assertEquals('DetailsTabFieldList', fieldList.apiName);
        System.assertEquals('Account', fieldList.objectApiName);
        System.assertEquals(3, fieldList.leftFields.size());
        System.assertEquals(3, fieldList.rightFields.size());
        System.assertEquals('Name', fieldList.leftFields[0].fieldApiName);
        System.assertEquals(
            DynamicPageElementFieldListParser.MODE_REQUIRED,
            fieldList.leftFields[0].mode
        );
        System.assertEquals('Status__c', fieldList.rightFields[2].fieldApiName);
    }
}