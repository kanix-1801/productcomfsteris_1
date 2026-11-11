/**
 * @author Vinay Soni
 * @date 2026/10/26
 *
 * @group Contract Modifier
 *
 * @description
 * GW-4777 / GW-5676 - Test data for the Model Qty coverage tests (ContractModifierServiceTest,
 * ModelQtyCoverageControllerTest): access to ContractModifier__c and QuoteLineItem.ModelQtyCoverage__c,
 * and a quote with one line whose account has a repair asset.
 */
@IsTest
public class ModelQtyCoverageTestDataFactory {

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
                Name = 'ModelQtyCoverageTestAccess',
                Label = 'Model Qty Coverage Test Access'
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
     * @description Adjustments JSON in the shape the modelQtyCoverage LWC writes, with Model Qty rows only.
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
     * @description Grants the running user read/create on PricingProgram__c and PricingProgramLines__c and
     *              read on the optional fields the Pricing Programs search uses (required, master-detail and
     *              formula fields are covered by the object access), through a test-only permission set.
     */
    public static void grantPricingProgramAccess() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            PermissionSet permissionSetRecord = new PermissionSet(
                Name = 'PricingProgramTestAccess',
                Label = 'Pricing Program Test Access'
            );
            insert permissionSetRecord;
            List<ObjectPermissions> objectPermissionList = new List<ObjectPermissions>();
            for (String objectName : new List<String>{ 'PricingProgram__c', 'PricingProgramLines__c' }) {
                objectPermissionList.add(new ObjectPermissions(
                    ParentId = permissionSetRecord.Id,
                    SobjectType = objectName,
                    PermissionsRead = true,
                    PermissionsCreate = true
                ));
            }
            insert objectPermissionList;
            List<FieldPermissions> fieldPermissionList = new List<FieldPermissions>();
            for (String field : new List<String>{
                'PricingProgram__c.DisplayName__c', 'PricingProgram__c.EndDate__c', 'PricingProgram__c.Status__c',
                'PricingProgramLines__c.CategoryCodeId__c', 'PricingProgramLines__c.CategoryCode__c',
                'PricingProgramLines__c.CategoryCodeName__c'
            }) {
                fieldPermissionList.add(new FieldPermissions(
                    ParentId = permissionSetRecord.Id,
                    SobjectType = field.substringBefore('.'),
                    Field = field,
                    PermissionsRead = true,
                    PermissionsEdit = false
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
     * @description A pricing program with one line per CT code. The CT code and name on a line are formulas
     *              from its Category Code product, so a Product2 is created per code (Name = "<code> Name").
     * @param programName ProgramName__c (and DisplayName__c)
     * @param status Status__c, e.g. Active or Draft
     * @param startDate StartDate__c
     * @param endDate EndDate__c (null = open-ended)
     * @param ctCodes ProductCode of each Category Code product, in insert order
     * @return The program, re-queried with its auto-number Name
     */
    public static PricingProgram__c createPricingProgram(
        String programName, String status, Date startDate, Date endDate, List<String> ctCodes
    ) {
        AutomationControl.setAllDisabled(true);
        // Manufacturer__c depends on ProductLine__c: take the first Product Line that has a valid Manufacturer
        String productLine;
        String manufacturer;
        List<Schema.PicklistEntry> productLineList = PricingProgram__c.ProductLine__c.getDescribe().getPicklistValues();
        for (Integer i = 0; i < productLineList.size() && manufacturer == null; i++) {
            if (productLineList[i].isActive()) {
                productLine = productLineList[i].getValue();
                manufacturer = firstDependentValue(PricingProgram__c.Manufacturer__c.getDescribe(), i);
            }
        }
        PricingProgram__c programRecord = new PricingProgram__c(
            ProgramName__c = programName,
            DisplayName__c = programName,
            Status__c = status,
            StartDate__c = startDate,
            EndDate__c = endDate,
            ProductLine__c = productLine,
            SubProductLine__c = firstActiveValue(PricingProgram__c.SubProductLine__c.getDescribe()),
            Manufacturer__c = manufacturer,
            DeviceType__c = firstActiveValue(PricingProgram__c.DeviceType__c.getDescribe())
        );
        insert programRecord;

        List<Product2> categoryCodeList = new List<Product2>();
        for (String ctCode : ctCodes) {
            categoryCodeList.add(new Product2(Name = ctCode + ' Name', ProductCode = ctCode, IsActive = true));
        }
        insert categoryCodeList;
        List<PricingProgramLines__c> lineList = new List<PricingProgramLines__c>();
        for (Product2 categoryCode : categoryCodeList) {
            lineList.add(new PricingProgramLines__c(
                PricingProgram__c = programRecord.Id,
                CategoryCodeId__c = categoryCode.Id
            ));
        }
        insert lineList;
        AutomationControl.setAllDisabled(false);
        return [SELECT Id, Name, ProgramName__c FROM PricingProgram__c WHERE Id = :programRecord.Id];
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

    // First active value of a dependent picklist that is valid for the controlling value at controllerIndex
    // (decoded from the entry's "validFor" bitmap: one bit per controlling value, high bit first).
    private static String firstDependentValue(Schema.DescribeFieldResult fieldDescribe, Integer controllerIndex) {
        for (Schema.PicklistEntry picklistEntry : fieldDescribe.getPicklistValues()) {
            if (!picklistEntry.isActive()) {
                continue;
            }
            Map<String, Object> entryMap = (Map<String, Object>) JSON.deserializeUntyped(JSON.serialize(picklistEntry));
            String validFor = (String) entryMap.get('validFor');
            if (String.isBlank(validFor)) {
                continue;
            }
            String hex = EncodingUtil.convertToHex(EncodingUtil.base64Decode(validFor));
            Integer byteIndex = controllerIndex / 8;
            if (hex.length() < (byteIndex + 1) * 2) {
                continue;
            }
            Integer byteValue = hexToInteger(hex.substring(byteIndex * 2, byteIndex * 2 + 2));
            Integer mask = 128 >> Math.mod(controllerIndex, 8);
            if ((byteValue & mask) != 0) {
                return picklistEntry.getValue();
            }
        }
        return null;
    }

    private static Integer hexToInteger(String hex) {
        String digits = '0123456789abcdef';
        Integer value = 0;
        for (Integer i = 0; i < hex.length(); i++) {
            value = value * 16 + digits.indexOf(hex.substring(i, i + 1).toLowerCase());
        }
        return value;
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