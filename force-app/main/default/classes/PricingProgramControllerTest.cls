@IsTest
private class PricingProgramControllerTest {

    @TestSetup
    static void setup() {
        insert new List<Product2>{
            new Product2(Name = 'Flexible Gastroscope', ProductCode = 'TST-CT-1', ProductType__c = 'Category Code', IsActive = true),
            new Product2(Name = 'Flexible Colonoscope', ProductCode = 'TST-CT-2', ProductType__c = 'Category Code', IsActive = true),
            new Product2(Name = 'Laparoscopic - Basic', ProductCode = 'TST-SC-1', ProductType__c = 'Service Code', IsActive = true)
        };
    }

    private static Map<String, Id> products() {
        Map<String, Id> m = new Map<String, Id>();
        for (Product2 p : [SELECT Id, ProductCode FROM Product2 WHERE ProductCode LIKE 'TST-%']) {
            m.put(p.ProductCode, p.Id);
        }
        return m;
    }

    private static PricingProgramController.CodeLine code(Id productId) {
        PricingProgramController.CodeLine c = new PricingProgramController.CodeLine();
        c.productId = productId;
        return c;
    }

    private static PricingProgramController.Rule rule(String clientId, String kind, String parentId, String model) {
        PricingProgramController.Rule r = new PricingProgramController.Rule();
        r.clientId = clientId;
        r.kind = kind;
        r.parentId = parentId;
        r.model = model;
        r.department = 'GI Lab';
        r.maxQuantity = 5;
        return r;
    }

    private static PricingProgramController.ProgramData header(String programType) {
        PricingProgramController.ProgramData d = new PricingProgramController.ProgramData();
        d.programType = programType;
        d.programName = 'Test Program';
        d.displayName = 'Test';
        d.status = 'Draft';
        d.startDate = Date.today();
        d.codes = new List<PricingProgramController.CodeLine>();
        d.rules = new List<PricingProgramController.Rule>();
        return d;
    }

    @IsTest
    static void createLoadAndChangePricingProgram() {
        Map<String, Id> p = products();
        PricingProgramController.ProgramData d = header(PricingProgramController.TYPE_PRICING);
        d.codes.add(code(p.get('TST-CT-1')));
        d.codes.add(code(p.get('TST-CT-2')));
        d.rules.add(rule('new-1', 'Inclusion', null, null));
        d.rules.add(rule('new-2', 'Exclusion', 'new-1', 'GIF-XP190N'));

        Test.startTest();
        Id programId = PricingProgramController.saveProgram(JSON.serialize(d));
        PricingProgramController.ProgramData loaded = PricingProgramController.getProgram(programId);
        Test.stopTest();

        System.assertEquals(2, loaded.codes.size(), 'two codes saved');
        System.assertEquals(2, loaded.rules.size(), 'inclusion + exclusion saved');
        System.assertEquals(1, [SELECT COUNT() FROM PricingProgramLines__c
                                WHERE PricingProgram__c = :programId AND CategoryCodeId__c = :p.get('TST-CT-1')],
                            'line points at the product (code and name come from formulas)');
        System.assertEquals('TST-CT-1', loaded.codes[0].code, 'code shown from the product');

        PricingProgramIncExc__c exc = [SELECT RelatedRule__c FROM PricingProgramIncExc__c
                                       WHERE PricingProgram__c = :programId AND Inc_Exc_Type__c = 'Exclusion'];
        PricingProgramIncExc__c inc = [SELECT Id FROM PricingProgramIncExc__c
                                       WHERE PricingProgram__c = :programId AND Inc_Exc_Type__c = 'Inclusion'];
        System.assertEquals(inc.Id, exc.RelatedRule__c, 'exclusion points at its inclusion');

        // Change: drop one code and the inclusion (its exclusion goes with it in the UI), add a new inclusion.
        loaded.codes.remove(1);
        loaded.rules.clear();
        loaded.rules.add(rule('new-3', 'Inclusion', null, 'CF-HQ190L'));
        loaded.programName = 'Renamed';
        PricingProgramController.saveProgram(JSON.serialize(loaded));

        System.assertEquals(1, [SELECT COUNT() FROM PricingProgramLines__c WHERE PricingProgram__c = :programId], 'one code left');
        System.assertEquals(1, [SELECT COUNT() FROM PricingProgramIncExc__c WHERE PricingProgram__c = :programId], 'old rules replaced');
        System.assertEquals('Renamed', [SELECT ProgramName__c FROM PricingProgram__c WHERE Id = :programId].ProgramName__c, 'header updated');
        System.assert(!PricingProgramController.listPrograms().isEmpty(), 'list returns programs');
    }

    @IsTest
    static void mobileVanUsesServiceCodesAndNoRules() {
        Map<String, Id> p = products();
        PricingProgramController.ProgramData d = header(PricingProgramController.TYPE_ONL);
        d.codes.add(code(p.get('TST-SC-1')));
        d.rules.add(rule('new-1', 'Inclusion', null, null));   // ignored: rules only apply to Pricing Program

        Id programId = PricingProgramController.saveProgram(JSON.serialize(d));
        System.assertEquals(1, [SELECT COUNT() FROM PricingProgramLines__c WHERE PricingProgram__c = :programId], 'service code saved');
        System.assertEquals(0, [SELECT COUNT() FROM PricingProgramIncExc__c WHERE PricingProgram__c = :programId], 'no rules for Mobile Van');

        List<PricingProgramController.CodeLine> found = PricingProgramController.searchCodes('TST-SC', PricingProgramController.TYPE_ONL);
        System.assertEquals(1, found.size(), 'search limited to Service Codes');
    }

    @IsTest
    static void wrongCategoryIsRejectedAndNothingSaved() {
        Map<String, Id> p = products();
        PricingProgramController.ProgramData d = header(PricingProgramController.TYPE_ONL);
        d.codes.add(code(p.get('TST-CT-1')));   // a Category Code on a Mobile Van program
        Boolean failed = false;
        try {
            PricingProgramController.saveProgram(JSON.serialize(d));
        } catch (AuraHandledException e) {
            failed = true;
            System.assert(e.getMessage().contains('Service Code'), e.getMessage());
        }
        System.assert(failed, 'save should fail');
        System.assertEquals(0, [SELECT COUNT() FROM PricingProgram__c WHERE ProgramName__c = 'Test Program'], 'header rolled back');
    }

    @IsTest
    static void validationMessages() {
        PricingProgramController.ProgramData d = header(PricingProgramController.TYPE_PRICING);
        d.programName = '';
        assertFails(d, 'Program Name');

        d = header(PricingProgramController.TYPE_PRICING);
        assertFails(d, 'Category Code');   // no codes

        d = header(PricingProgramController.TYPE_PRICING);
        d.codes.add(code(products().get('TST-CT-1')));
        d.endDate = d.startDate.addDays(-1);
        assertFails(d, 'End Date');

        d = header(PricingProgramController.TYPE_PRICING);
        d.codes.add(code(products().get('TST-CT-1')));
        d.rules.add(rule('x-1', 'Exclusion', 'missing', null));
        assertFails(d, 'exclusion');
    }

    @IsTest
    static void resolvePastedCodes() {
        List<PricingProgramController.CodeMatch> res = PricingProgramController.resolveCodes(
            new List<String>{ 'TST-CT-1', ' tst-ct-1 ', 'TST-SC-1', 'NOPE-1' }, PricingProgramController.TYPE_PRICING);
        System.assertEquals(3, res.size(), 'duplicates removed');
        System.assertEquals('ok', res[0].status);
        System.assertEquals('wrong', res[1].status);
        System.assertEquals('missing', res[2].status);
        System.assert(PricingProgramController.searchCodes('x', PricingProgramController.TYPE_PRICING).isEmpty(), 'short terms return nothing');
    }

    private static void assertFails(PricingProgramController.ProgramData d, String expected) {
        Boolean failed = false;
        try {
            PricingProgramController.saveProgram(JSON.serialize(d));
        } catch (AuraHandledException e) {
            failed = true;
            System.assert(e.getMessage().containsIgnoreCase(expected), 'expected "' + expected + '" in: ' + e.getMessage());
        }
        System.assert(failed, 'expected a validation error mentioning ' + expected);
    }
}