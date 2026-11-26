/**
 * Tests for GC-3606 Lead Product codes: copy from the Product, find the Product from the codes,
 * and keep the codes when no single Product can be found.
 */
@IsTest(SeeAllData=false)
private class LeadProductTriggerHandlerTest {

    /**
     * Choosing a Product copies its codes, and changing the Product copies the new codes.
     */
    @IsTest
    static void chosenProductCopiesItsCodes() {
        Lead leadRecord = newLead();
        Product2 first = newProduct('Washer A', '412', '2239');
        Product2 second = newProduct('Washer B', '156', '1956');
        LeadProduct__c row = new LeadProduct__c(Lead__c = leadRecord.Id, Product__c = first.Id);
        insert row;

        row = [SELECT Product_Family_Code__c, Product_Class_Code__c FROM LeadProduct__c WHERE Id = :row.Id];
        Assert.areEqual('412', row.Product_Family_Code__c);
        Assert.areEqual('2239', row.Product_Class_Code__c);

        row.Product__c = second.Id;
        update row;
        row = [SELECT Product_Family_Code__c, Product_Class_Code__c FROM LeadProduct__c WHERE Id = :row.Id];
        Assert.areEqual('156', row.Product_Family_Code__c);
        Assert.areEqual('1956', row.Product_Class_Code__c);
    }

    /**
     * Codes that match one Product set the Product. Several rows work in one insert.
     */
    @IsTest
    static void codesThatMatchOneProductSetTheProduct() {
        Lead leadRecord = newLead();
        Product2 first = newProduct('Sterilizer A', '101', '1103');
        Product2 second = newProduct('Sterilizer B', '332', '3287');

        insert new List<LeadProduct__c>{
            new LeadProduct__c(Lead__c = leadRecord.Id, Product_Family_Code__c = '101', Product_Class_Code__c = '1103'),
            new LeadProduct__c(Lead__c = leadRecord.Id, Product_Family_Code__c = ' 332 ', Product_Class_Code__c = '3287')
        };

        Set<Id> productIds = new Set<Id>();
        for (LeadProduct__c row : [SELECT Product__c FROM LeadProduct__c WHERE Lead__c = :leadRecord.Id]) {
            productIds.add(row.Product__c);
        }
        Assert.areEqual(new Set<Id>{ first.Id, second.Id }, productIds);
    }

    /**
     * Codes that match several Products use the submitted name. Without a matching name the
     * Product stays empty and the codes are kept.
     */
    @IsTest
    static void codesThatMatchManyProductsUseTheName() {
        Lead leadRecord = newLead();
        newProduct('Cart Washer', '326', '8858');
        Product2 target = newProduct('Rack Washer', '326', '8858');

        LeadProduct__c named = new LeadProduct__c(
            Lead__c = leadRecord.Id,
            Product_Family_Code__c = '326',
            Product_Class_Code__c = '8858',
            Submitted_Product_Name__c = 'rack washer'
        );
        LeadProduct__c unnamed = new LeadProduct__c(
            Lead__c = leadRecord.Id,
            Product_Family_Code__c = '326',
            Product_Class_Code__c = '8858'
        );
        insert new List<LeadProduct__c>{ named, unnamed };

        Assert.areEqual(target.Id, [SELECT Product__c FROM LeadProduct__c WHERE Id = :named.Id].Product__c);
        unnamed = [SELECT Product__c, Product_Family_Code__c, Product_Class_Code__c FROM LeadProduct__c WHERE Id = :unnamed.Id];
        Assert.isNull(unnamed.Product__c);
        Assert.areEqual('326', unnamed.Product_Family_Code__c);
        Assert.areEqual('8858', unnamed.Product_Class_Code__c);
    }

    /**
     * Codes that match no Product keep the codes and leave the Product empty.
     */
    @IsTest
    static void codesWithNoProductAreKept() {
        Lead leadRecord = newLead();
        LeadProduct__c row = new LeadProduct__c(
            Lead__c = leadRecord.Id,
            Product_Family_Code__c = '999',
            Product_Class_Code__c = '9999'
        );
        insert row;

        row = [SELECT Product__c, Product_Family_Code__c FROM LeadProduct__c WHERE Id = :row.Id];
        Assert.isNull(row.Product__c);
        Assert.areEqual('999', row.Product_Family_Code__c);
    }

    /**
     * A row with no Product and no codes is still rejected.
     */
    @IsTest
    static void rowWithNoProductAndNoCodesIsRejected() {
        Lead leadRecord = newLead();

        Database.SaveResult result = Database.insert(new LeadProduct__c(Lead__c = leadRecord.Id), false);

        Assert.isFalse(result.isSuccess());
        Assert.areEqual('Select a Product.', result.getErrors()[0].getMessage());
    }

    /**
     * The TAS request sends the family and class codes saved on the Lead Product.
     */
    @IsTest
    static void tasRequestSendsTheCodes() {
        Lead leadRecord = newLead();
        insert new LeadProduct__c(
            Lead__c = leadRecord.Id,
            Product_Family_Code__c = '999',
            Product_Class_Code__c = '9999'
        );

        List<Object> products = (List<Object>) TasAssignmentRequest.fromLead(leadRecord).toJsonMap().get('products');

        Assert.areEqual(1, products.size());
        Map<String, String> product = (Map<String, String>) products[0];
        Assert.areEqual('999', product.get('productFamilyCode'));
        Assert.areEqual('9999', product.get('productClassCode'));
    }

    /**
     * The TAS request maps the country and class code, and sends no products without a Lead.
     */
    @IsTest
    static void tasRequestMapsCountryAndClassCode() {
        TasAssignmentRequest request = new TasAssignmentRequest();
        request.country = 'United States';
        request.classCode = 'Healthcare';

        Map<String, Object> payload = request.toJsonMap();

        Assert.areEqual('US', payload.get('country'));
        Assert.areEqual('HC', payload.get('classCode'));
        Assert.isTrue(((List<Object>) payload.get('products')).isEmpty());
    }

    private static Lead newLead() {
        Lead leadRecord = new Lead(
            FirstName = 'Ada',
            LastName = 'Codes',
            Company = 'Steris',
            CountryCode = 'US',
            Email = 'ada.codes@example.com',
            LeadSource = 'Web',
            Status = 'New'
        );
        insert leadRecord;
        return leadRecord;
    }

    private static Product2 newProduct(String name, String family, String classCode) {
        Product2 productRecord = new Product2(
            Name = name,
            IsActive = true,
            ItemFamily__c = family,
            ProductClassCode__c = classCode,
            BusinessUnit__c = 'IMS'
        );
        insert productRecord;
        return productRecord;
    }
}