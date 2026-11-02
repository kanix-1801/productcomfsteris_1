/**
 * @author Vinay Soni
 * @date 2026/10/26
 *
 * @group Contract Modifier
 *
 * @description
 * GW-4777 / GW-5676 - Test data for the Model Qty coverage tests (ContractModifierServiceTest,
 * ImsProductConfiguratorControllerTest): access to ContractModifier__c and QuoteLineItem.ModelQtyCoverage__c,
 * and a quote with one line whose account has a repair asset.
 */
@IsTest
public class ImsProductConfiguratorTestDataFactory {

    public static final String PRODUCT_LINE = 'ESPC Model Qty Line';
    public static final String SUB_PRODUCT_LINE = 'ESPC Model Qty Sub Line';
    public static final String MANUFACTURER = 'ESPC Model Qty Maker';

    private static final List<String> FIELD_LIST = new List<String>{
        'ContractModifier__c.Model__c', 'ContractModifier__c.ModelQty__c', 'ContractModifier__c.Type__c',
        'ContractModifier__c.Quote__c', 'ContractModifier__c.QuoteLineItem__c', 'ContractModifier__c.StartDate__c',
        'ContractModifier__c.EndDate__c', 'ContractModifier__c.InclusionExclusionType__c',
        'ContractModifier__c.ParentContractModifier__c', 'ContractModifier__c.ProductLine__c',
        'ContractModifier__c.SubProductLine__c', 'ContractModifier__c.ProductType__c',
        'ContractModifier__c.Manufacture__c', 'QuoteLineItem.ModelQtyCoverage__c'
    };

    /**
     * @description Term of the test quote line (copied to its Model Qty records).
     */
    public static final Date TERM_START = Date.today();
    public static final Date TERM_END = Date.today().addYears(1).addDays(-1);

    /**
     * @description Grants the running user CRUD on ContractModifier__c and read/edit on the fields the
     *              feature uses, through a test-only permission set (setup DML isolated with runAs).
     */
    public static void grantAccess() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            PermissionSet permissionSetRecord = new PermissionSet(
                Name = 'ImsProductConfiguratorTestAccess',
                Label = 'IMS Product Configurator Test Access'
            );
            insert permissionSetRecord;
            insert new ObjectPermissions(
                ParentId = permissionSetRecord.Id,
                SobjectType = 'ContractModifier__c',
                PermissionsRead = true,
                PermissionsCreate = true,
                PermissionsEdit = true,
                PermissionsDelete = true
            );
            List<FieldPermissions> fieldPermissionList = new List<FieldPermissions>();
            for (String field : FIELD_LIST) {
                fieldPermissionList.add(new FieldPermissions(
                    ParentId = permissionSetRecord.Id,
                    SobjectType = field.substringBefore('.'),
                    Field = field,
                    PermissionsRead = true,
                    PermissionsEdit = true
                ));
            }
            insert fieldPermissionList;
            insert new PermissionSetAssignment(
                AssigneeId = UserInfo.getUserId(),
                PermissionSetId = permissionSetRecord.Id
            );
        }
    }

    /**
     * @description Account, opportunity, quote and one quote line (without coverage), plus a repair asset
     *              on the account whose product has PRODUCT_LINE / SUB_PRODUCT_LINE / MANUFACTURER.
     * @return The quote line
     */
    public static QuoteLineItem createQuoteWithLine() {
        AutomationControl.setAllDisabled(true);

        adb_Account accountBuilder = new adb_Account().name('Model Qty Test Account');
        accountBuilder.persist();
        Contact primaryContact = new Contact(FirstName = 'Model', LastName = 'Qty', AccountId = accountBuilder.id);
        insert primaryContact;

        Id pricebookId = Test.getStandardPricebookId();
        Opportunity opportunityRecord = new Opportunity(
            Name = 'Model Qty Test Opportunity',
            AccountId = accountBuilder.id,
            StageName = firstActiveValue(Opportunity.StageName.getDescribe()),
            ForecastConfidenceLevel__c = firstActiveValue(Opportunity.ForecastConfidenceLevel__c.getDescribe()),
            Type = firstActiveValue(Opportunity.Type.getDescribe()),
            PrimaryContact__c = primaryContact.Id,
            CloseDate = Date.today().addDays(30),
            Amount = 1000,
            Probability = 10,
            Pricebook2Id = pricebookId
        );
        insert opportunityRecord;

        Product2 productRecord = new Product2(
            Name = 'IMS Repair Contract',
            IsActive = true,
            ProductLine__c = PRODUCT_LINE,
            SubProductLine__c = SUB_PRODUCT_LINE,
            Manufacturer__c = MANUFACTURER
        );
        insert productRecord;
        PricebookEntry pricebookEntryRecord = new PricebookEntry(
            Pricebook2Id = pricebookId,
            Product2Id = productRecord.Id,
            UnitPrice = 100,
            IsActive = true
        );
        insert pricebookEntryRecord;

        insert new Asset(
            Name = 'Model Qty Repair Asset',
            SerialNumber = 'SN-MQ-0001',
            AccountId = accountBuilder.id,
            Product2Id = productRecord.Id,
            Status = 'Purchased',
            Quantity = 1
        );

        Quote quoteRecord = new Quote(
            Name = 'Model Qty Test Quote',
            OpportunityId = opportunityRecord.Id,
            Pricebook2Id = pricebookId
        );
        insert quoteRecord;

        QuoteLineItem line = new QuoteLineItem(
            QuoteId = quoteRecord.Id,
            PricebookEntryId = pricebookEntryRecord.Id,
            Quantity = 1,
            UnitPrice = 100,
            StartDate = TERM_START,
            EndDate = TERM_END
        );
        insert line;

        AutomationControl.setAllDisabled(false);
        return line;
    }

    /**
     * @description Adjustments JSON in the shape the imsProductConfigurator LWC writes, with Model Qty rows only.
     * @param productLine Product Line of every row (may be null)
     * @param models Model name -> max covered devices, in order
     * @return JSON for QuoteLineItem.ModelQtyCoverage__c
     */
    public static String coverageJson(String productLine, Map<String, Decimal> models) {
        return coverageJson(productLine, models, new List<Map<String, Object>>());
    }

    /**
     * @description Adjustments JSON with Model Qty rows and inclusions (see inclusion()).
     * @param productLine Product Line of every Model Qty row (may be null)
     * @param models Model name -> max covered devices, in order
     * @param inclusions Inclusions, each with an "exclusions" list
     * @return JSON for QuoteLineItem.ModelQtyCoverage__c
     */
    public static String coverageJson(
        String productLine, Map<String, Decimal> models, List<Map<String, Object>> inclusions
    ) {
        List<Map<String, Object>> modelList = new List<Map<String, Object>>();
        for (String model : models.keySet()) {
            Map<String, Object> row = criteria(productLine, null, model);
            row.put('qty', models.get(model));
            modelList.add(row);
        }
        return JSON.serialize(new Map<String, Object>{
            'inclusions' => inclusions,
            'models' => modelList,
            'pricingProgram' => null
        });
    }

    /**
     * @description One inclusion for coverageJson.
     * @param criteria The inclusion's fields (see criteria())
     * @param exclusions Its exclusions' fields
     * @return Inclusion map
     */
    public static Map<String, Object> inclusion(Map<String, Object> criteria, List<Map<String, Object>> exclusions) {
        Map<String, Object> rule = criteria.clone();
        rule.put('exclusions', exclusions);
        return rule;
    }

    /**
     * @description Equipment fields of a rule; the ones not given are blank (any value).
     */
    public static Map<String, Object> criteria(String productLine, String manufacturer, String model) {
        return new Map<String, Object>{
            'productLine' => productLine,
            'subProductLine' => null,
            'productType' => null,
            'manufacturer' => manufacturer,
            'model' => model
        };
    }

    /**
     * @description An active ContractModifier__c.ProductLine__c value (the field is a restricted picklist).
     */
    public static String validProductLine() {
        return firstActiveValue(ContractModifier__c.ProductLine__c.getDescribe());
    }

    /**
     * @description A user on the Minimum Access profile: no access to quotes, products, assets or
     *              ContractModifier__c, so USER_MODE queries fail for them.
     * @return The inserted user
     */
    public static User createNoAccessUser() {
        Profile minimumAccess = [SELECT Id FROM Profile WHERE Name = 'Minimum Access - Salesforce' LIMIT 1];
        String uniqueName = 'mqnoaccess' + System.currentTimeMillis() + '@example.com';
        User userRecord = new User(
            Alias = 'mqnoacc',
            Email = uniqueName,
            Username = uniqueName,
            LastName = 'No Access',
            ProfileId = minimumAccess.Id,
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            TimeZoneSidKey = 'America/Los_Angeles'
        );
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert userRecord;
        }
        return userRecord;
    }

    private static String firstActiveValue(Schema.DescribeFieldResult fieldDescribe) {
        for (Schema.PicklistEntry picklistEntry : fieldDescribe.getPicklistValues()) {
            if (picklistEntry.isActive()) {
                return picklistEntry.getValue();
            }
        }
        return null;
    }
}