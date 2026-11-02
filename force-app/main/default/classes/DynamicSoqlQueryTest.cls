@IsTest
private class DynamicSoqlQueryTest {

    @TestSetup
    static void setup() {
        new adb_Product2().name('Alpha Pump').productCode('AP-100').isActive(true);
        new adb_Product2().name('Beta Valve').productCode('BV-200').isActive(false);
        new adb_Product2().name('Gamma Pump').productCode('GP-300').isActive(true);
        new adb_Product2().name('Delta Hose').productCode('DH-400').isActive(true);

        adb_DomainBuilder.save();
    }

    @IsTest
    static void queryWithFiltersLogicOrderAndLimit() {
        // (active AND name contains "Pump") OR code is BV-200
        List<DynamicSoqlQuery.Filter> filters = new List<DynamicSoqlQuery.Filter>{
            new DynamicSoqlQuery.Filter('IsActive', '=', true),
            new DynamicSoqlQuery.Filter('Name', 'LIKE', '%Pump%'),
            new DynamicSoqlQuery.Filter('ProductCode', 'IN', new List<String>{ 'BV-200' })
        };
        List<Product2> rows = (List<Product2>) DynamicSoqlQuery.query(
            'Product2',
            new List<String>{ 'Id', 'Name', 'ProductCode', 'CreatedBy.Name' },
            filters,
            '(1 AND 2) OR 3',
            new List<DynamicSoqlQuery.Ordering>{ new DynamicSoqlQuery.Ordering('Name', false) },
            10,
            null
        );
        Assert.areEqual(3, rows.size());
        Assert.areEqual('Alpha Pump', rows[0].Name);
        Assert.areEqual('Beta Valve', rows[1].Name);
        Assert.areEqual('Gamma Pump', rows[2].Name);
        Assert.isNotNull(rows[0].CreatedBy.Name, 'Relationship field should be populated');
    }

    @IsTest
    static void queryAllFieldsReturnsPopulatedRecord() {
        List<Product2> rows = (List<Product2>) DynamicSoqlQuery.queryAllFields(
            'Product2',
            new List<DynamicSoqlQuery.Filter>{ new DynamicSoqlQuery.Filter('Name', '=', 'Gamma Pump') },
            1
        );
        Assert.areEqual(1, rows.size());
        Assert.areEqual('GP-300', rows[0].ProductCode);
        Assert.areEqual(true, rows[0].IsActive);
    }

    @IsTest
    static void builderProducesSameResult() {
        SoqlQueryBuilder b = SoqlQueryBuilder.fromObject('Product2')
            .selectFields(new List<String>{ 'Id', 'Name' })
            .whereEquals('IsActive', true)
            .orderByDesc('ProductCode')
            .limitTo(5);

        Assert.areEqual(
            'SELECT Id, Name FROM Product2 WHERE IsActive = :p0 ORDER BY ProductCode DESC LIMIT 5',
            b.toSoql()
        );
        List<Product2> rows = (List<Product2>) b.execute();
        Assert.areEqual(3, rows.size());
        Assert.areEqual('Gamma Pump', rows[0].Name);   // GP-300 sorts first descending

        Product2 first = (Product2) SoqlQueryBuilder.fromObject('Product2')
            .selectAllFields()
            .whereField('Name', 'LIKE', 'Bet%')
            .first();
        Assert.areEqual('BV-200', first.ProductCode);
        Assert.areEqual(false, first.IsActive);
    }

    @IsTest
    static void countWithFiltersReturnsMatchingRowCount() {
        List<DynamicSoqlQuery.Filter> filters = new List<DynamicSoqlQuery.Filter>{
            new DynamicSoqlQuery.Filter('IsActive', '=', true),
            new DynamicSoqlQuery.Filter('Name', 'LIKE', '%Pump%')
        };

        Test.startTest();
        Integer activePumps = DynamicSoqlQuery.count('Product2', filters, '1 AND 2');
        Integer none = DynamicSoqlQuery.count(
            'Product2',
            new List<DynamicSoqlQuery.Filter>{
                new DynamicSoqlQuery.Filter('ProductCode', '=', 'DOES-NOT-EXIST')
            },
            null
        );
        Integer viaBuilder = SoqlQueryBuilder.fromObject('Product2')
            .whereEquals('IsActive', true)
            .count();
        Test.stopTest();

        Assert.areEqual(2, activePumps, 'Alpha Pump and Gamma Pump should match');
        Assert.areEqual(0, none, 'Unmatched filter should return zero');
        Assert.areEqual(3, viaBuilder, 'Three active products in setup');
    }

    @IsTest
    static void countRejectsInvalidObject() {
        try {
            DynamicSoqlQuery.count('Product2 WHERE Id != null', null, null);
            Assert.fail('Expected DynamicSoqlException');
        } catch (DynamicSoqlQuery.DynamicSoqlException e) {
            Assert.isNotNull(e.getMessage());
        }
    }

    @IsTest
    static void injectionAttemptsAreRejected() {
        // Injection via value is harmless: it is bound, not concatenated.
        List<SObject> rows = DynamicSoqlQuery.query(
            'Product2', new List<String>{ 'Id' },
            new List<DynamicSoqlQuery.Filter>{ new DynamicSoqlQuery.Filter('Name', '=', '\' OR Name != \'') },
            null
        );
        Assert.areEqual(0, rows.size());

        assertRejected('Product2 WHERE Id != null', new List<String>{ 'Id' }, null, null, null);  // object
        assertRejected('Product2', new List<String>{ 'Id FROM User --' }, null, null, null);        // field
        assertRejected('Product2', new List<String>{ 'NotAField__c' }, null, null, null);           // unknown field
        assertRejected('Product2', new List<String>{ 'Id' },
            new List<DynamicSoqlQuery.Filter>{ new DynamicSoqlQuery.Filter('Name', '= \'x\' OR Name', 'y') },
            null, null);                                                                              // operator
        assertRejected('Product2', new List<String>{ 'Id' },
            new List<DynamicSoqlQuery.Filter>{ new DynamicSoqlQuery.Filter('Name', '=', 'x') },
            '1 OR Name != null', null);                                                               // logic
        assertRejected('Product2', new List<String>{ 'Id' }, null, null, 0);                        // limit
    }

    private static void assertRejected(
        String obj, List<String> fields, List<DynamicSoqlQuery.Filter> filters, String logic, Integer lim
    ) {
        try {
            DynamicSoqlQuery.query(obj, fields, filters, logic, null, lim, null);
            Assert.fail('Expected DynamicSoqlException');
        } catch (DynamicSoqlQuery.DynamicSoqlException e) {
            Assert.isNotNull(e.getMessage());
        }
    }
}