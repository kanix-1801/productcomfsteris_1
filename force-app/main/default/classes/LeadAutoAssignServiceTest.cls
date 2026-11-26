/**
 * Tests for GC-3662 Auto Assign Lead: the lock, the Product requirement, and routing the first time it is selected.
 */
@IsTest(SeeAllData=false)
private class LeadAutoAssignServiceTest {

    /**
     * A new Lead saved outside the New Lead page cannot select the checkbox.
     */
    @IsTest
    static void insertWithCheckboxSelectedIsRejected() {
        Lead leadRecord = newLead('InsertSelected');
        leadRecord.Auto_Assign_Lead__c = true;

        Database.SaveResult result = Database.insert(leadRecord, false);

        Assert.isFalse(result.isSuccess());
        Assert.areEqual(System.Label.LeadAutoAssignOnInsertMessage, result.getErrors()[0].getMessage());
    }

    /**
     * Selecting the checkbox on a Lead with no Product is rejected and the Lead is not routed.
     */
    @IsTest
    static void selectingWithoutProductIsRejected() {
        Lead leadRecord = newLead('NoProduct');
        insert leadRecord;

        leadRecord.Auto_Assign_Lead__c = true;
        Database.SaveResult result = Database.update(leadRecord, false);

        Assert.isFalse(result.isSuccess());
        Assert.areEqual(System.Label.LeadAutoAssignNoProductMessage, result.getErrors()[0].getMessage());
    }

    /**
     * Selecting the checkbox on a Lead with a Product routes it to the country queue once.
     * The checkbox then cannot be cleared, and a later save does not route again.
     */
    @IsTest
    static void selectingWithProductRoutesOnceAndLocks() {
        Group countryQueue = insertQueue('Lead_AutoAssign_Country', 'Auto Assign Country Queue');
        LeadRoutingService.testCountryRows = new List<Lead_Country_Queue__mdt>{
            new Lead_Country_Queue__mdt(Country__c = 'US', QueueDeveloperName__c = countryQueue.DeveloperName)
        };

        Lead leadRecord = newLead('Selected');
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert leadRecord;
            Product2 productRecord = new Product2(
                Name = 'Auto Assign Sterilizer',
                IsActive = true,
                BusinessUnit__c = 'IMS'
            );
            insert productRecord;
            insert new LeadProduct__c(
                Lead__c = leadRecord.Id,
                Product__c = productRecord.Id,
                ParentCategory__c = 'Infection Prevention',
                ProductCategory__c = 'Capital'
            );

            Test.startTest();
            leadRecord.Auto_Assign_Lead__c = true;
            update leadRecord;
            Test.stopTest();
        }

        Assert.areEqual(
            countryQueue.Id,
            [SELECT OwnerId FROM Lead WHERE Id = :leadRecord.Id].OwnerId,
            'An Auto Assign Lead with no TAS rep goes to the regional queue.'
        );

        leadRecord.Auto_Assign_Lead__c = false;
        Database.SaveResult result = Database.update(leadRecord, false);
        Assert.isFalse(result.isSuccess());
        Assert.areEqual(System.Label.LeadAutoAssignLockedMessage, result.getErrors()[0].getMessage());

        update new Lead(Id = leadRecord.Id, Company = 'Steris Updated');
        Assert.areEqual(0, Limits.getQueueableJobs(), 'A later save must not route the Lead again.');
    }

    /**
     * A Lead from HubSpot is not routed by Auto Assign Lead.
     */
    @IsTest
    static void hubSpotLeadSourceIsNotEligible() {
        Assert.isFalse(LeadAutoAssignService.isEligible(
            new Lead(Auto_Assign_Lead__c = true, LeadSource = 'HubSpot')
        ));
        Assert.isTrue(LeadAutoAssignService.isEligible(
            new Lead(Auto_Assign_Lead__c = true, LeadSource = 'Web')
        ));
        Assert.isFalse(LeadAutoAssignService.isEligible(new Lead(Auto_Assign_Lead__c = false)));
    }

    /**
     * The New Lead page rejects the checkbox with no Product, and routes when a Product is saved.
     */
    @IsTest
    static void newLeadPageRequiresProductAndRoutes() {
        Lead noProductLead = newLead('WizardNone');
        noProductLead.Auto_Assign_Lead__c = true;
        AuraHandledException thrown;
        try {
            LeadCreateController.createLeadWithProducts(noProductLead, null);
        } catch (AuraHandledException ex) {
            thrown = ex;
        }
        Assert.isNotNull(thrown);
        Assert.areEqual(System.Label.LeadAutoAssignNoProductMessage, thrown.getMessage());

        Product2 productRecord = new Product2(Name = 'Wizard Sterilizer', IsActive = true, BusinessUnit__c = 'IMS');
        insert productRecord;
        LeadCreateController.ProductInput productInput = new LeadCreateController.ProductInput();
        productInput.productId = productRecord.Id;
        productInput.parentCategory = 'Infection Prevention';
        productInput.productCategory = 'Capital';
        Lead withProductLead = newLead('WizardProduct');
        withProductLead.Auto_Assign_Lead__c = true;

        Test.startTest();
        Id leadId = LeadCreateController.createLeadWithProducts(
            withProductLead,
            JSON.serialize(new List<LeadCreateController.ProductInput>{ productInput })
        );
        Assert.areEqual(1, Limits.getQueueableJobs());
        Test.stopTest();

        Assert.isTrue([SELECT Auto_Assign_Lead__c FROM Lead WHERE Id = :leadId].Auto_Assign_Lead__c);
    }

    /**
     * Several TAS rows for one rep are one assignment. Different or blank reps are not.
     */
    @IsTest
    static void tasRowsCountDistinctReps() {
        Assert.areEqual('1001', LeadRoutingService.singleRepEmployeeNumber(
            new List<TasTerritoryItem>{ repRow('1001'), repRow(' 1001 ') }
        ));
        Assert.isNull(LeadRoutingService.singleRepEmployeeNumber(
            new List<TasTerritoryItem>{ repRow('1001'), repRow('1002') }
        ));
        Assert.isNull(LeadRoutingService.singleRepEmployeeNumber(
            new List<TasTerritoryItem>{ repRow('1001'), repRow(null) }
        ));
        Assert.isNull(LeadRoutingService.singleRepEmployeeNumber(new List<TasTerritoryItem>()));
        Assert.isNull(LeadRoutingService.singleRepEmployeeNumber(null));
    }

    private static TasTerritoryItem repRow(String employeeNumber) {
        TasTerritoryItem row = new TasTerritoryItem();
        row.salesRepEmployeeNumber = employeeNumber;
        return row;
    }

    private static Group insertQueue(String developerName, String label) {
        Group queueRecord = new Group(Name = label, Type = 'Queue', DeveloperName = developerName);
        insert queueRecord;
        insert new QueueSobject(QueueId = queueRecord.Id, SobjectType = 'Lead');
        return queueRecord;
    }

    private static Lead newLead(String lastName) {
        String token = EncodingUtil.convertToHex(Crypto.generateAesKey(128)).substring(0, 10);
        return new Lead(
            FirstName = 'Ada',
            LastName = lastName,
            Company = 'Steris',
            CountryCode = 'US',
            Email = lastName.toLowerCase() + '.' + token + '@example.com',
            LeadSource = 'Web',
            Status = 'New'
        );
    }
}