/**
 * @description Tests for creating a Lead with Products and starting routing afterward.
 * @author      Vinay
 * @date        2026-10-12
 */
@IsTest(SeeAllData=false)
private class LeadCreateControllerTest {

    /**
     * @description Confirms the Lead and Product are saved and a manual Lead stays with the user.
     */
    @IsTest
    static void createsLeadAndProductsThenRoutes() {
        Id leadId;
        System.runAs(new User(Id = UserInfo.getUserId())) {
            Product2 productRecord = new Product2(
                Name = 'Sterilizer',
                IsActive = true,
                BusinessUnit__c = 'IMS'
            );
            insert productRecord;

            Lead leadRecord = new Lead(
                FirstName = 'Ada',
                LastName = 'Wizard',
                Company = 'Steris',
                CountryCode = 'US',
                Email = 'ada@example.com',
                LeadSource = 'Other',
                LeadSourceDetail__c = 'Trade show',
                Status = 'New'
            );
            LeadCreateController.ProductInput productInput = new LeadCreateController.ProductInput();
            productInput.productId = productRecord.Id;
            productInput.parentCategory = 'Infection Prevention';
            productInput.productCategory = 'Capital';

            Test.startTest();
            leadId = LeadCreateController.createLeadWithProducts(
                leadRecord,
                JSON.serialize(new List<LeadCreateController.ProductInput>{ productInput })
            );
            Test.stopTest();
        }

        Assert.areEqual(1, [SELECT COUNT() FROM LeadProduct__c WHERE Lead__c = :leadId]);
        Assert.areEqual(UserInfo.getUserId(), [SELECT OwnerId FROM Lead WHERE Id = :leadId].OwnerId);
    }

    /**
     * The product table finds active Products by name or code, and ignores a short term.
     */
    @IsTest
    static void searchProductsFindsActiveProducts() {
        insert new List<Product2>{
            new Product2(Name = 'Zeta Sterilizer Search', ProductCode = 'ZSS-100', IsActive = true),
            new Product2(Name = 'Zeta Washer Inactive', ProductCode = 'ZWI-200', IsActive = false)
        };

        List<LeadCreateController.ProductOption> byName = LeadCreateController.searchProducts('zeta ster');
        List<LeadCreateController.ProductOption> byCode = LeadCreateController.searchProducts('ZSS-1');
        List<LeadCreateController.ProductOption> inactive = LeadCreateController.searchProducts('Zeta Washer');

        Assert.areEqual(1, byName.size());
        Assert.areEqual('Zeta Sterilizer Search', byName[0].name);
        Assert.areEqual('ZSS-100', byName[0].productCode);
        Assert.areEqual(1, byCode.size());
        Assert.areEqual(0, inactive.size());
        Assert.areEqual(0, LeadCreateController.searchProducts('z').size());
    }

    /**
     * With no search text the product table lists the Products most used on Leads first.
     */
    @IsTest
    static void searchProductsListsPopularProductsFirst() {
        Product2 popular = new Product2(Name = 'Zeta Popular Pick', ProductCode = 'ZPP-1', IsActive = true);
        Product2 other = new Product2(Name = 'Aaa Rarely Picked', ProductCode = 'ARP-1', IsActive = true);
        insert new List<Product2>{ popular, other };
        Lead leadRecord = new Lead(
            FirstName = 'Ada',
            LastName = 'Popular',
            Company = 'Steris',
            CountryCode = 'US',
            Email = 'ada.popular.products@example.com',
            LeadSource = 'Web',
            Status = 'New'
        );
        insert leadRecord;
        insert new List<LeadProduct__c>{
            new LeadProduct__c(Lead__c = leadRecord.Id, Product__c = popular.Id)
        };

        List<LeadCreateController.ProductOption> options = LeadCreateController.searchProducts(null);

        Assert.isFalse(options.isEmpty());
        Assert.areEqual(popular.Id, options[0].id);
        Assert.areEqual(options.size(), LeadCreateController.searchProducts('').size());
    }

    /**
     * @description Confirms a Lead saves with no Products and stays with the user.
     */
    @IsTest
    static void createsLeadWithoutProductsThenRoutes() {
        Id leadId;
        System.runAs(new User(Id = UserInfo.getUserId())) {
            Lead leadRecord = new Lead(
                FirstName = 'Ada',
                LastName = 'NoProduct',
                Company = 'Steris',
                CountryCode = 'US',
                Email = 'ada@example.com',
                LeadSource = 'Web'
            );

            Test.startTest();
            leadId = LeadCreateController.createLeadWithProducts(leadRecord, null);
            Test.stopTest();
        }

        Assert.areEqual(0, [SELECT COUNT() FROM LeadProduct__c WHERE Lead__c = :leadId]);
        Assert.areEqual(UserInfo.getUserId(), [SELECT OwnerId FROM Lead WHERE Id = :leadId].OwnerId);
    }

    /**
     * @description Confirms wizard-created Leads do not also enqueue the insert-time TAS job.
     */
    @IsTest
    static void wizardSkipsInsertTimeTas() {
        LeadService.skipInsertTas = true;
        Lead leadRecord = new Lead(
            LastName = 'Skip',
            PostalCode = '44101',
            Country = 'United States',
            Org_ID__c = '100',
            Class_Code__c = 'Healthcare'
        );

        LeadService.assignTAStoLead(new List<Lead>{ leadRecord });

        Assert.areEqual(0, Limits.getQueueableJobs());
    }

    /**
     * @description GC-3541. The custom page blocks an exact email match and does not save the Lead.
     */
    @IsTest
    static void customPageBlocksExactEmail() {
        insert new Contact(LastName = 'Doe', Email = 'gc3541.wizard@example.com');
        Lead leadRecord = new Lead(
            FirstName = 'Pat',
            LastName = 'Doe',
            Company = 'Clinic',
            Email = 'gc3541.wizard@example.com',
            LeadSource = 'Marketing Campaign'
        );

        LeadCreateController.DuplicatePreview preview = LeadCreateController.previewLeadDuplicate(leadRecord);
        Assert.areEqual(true, preview.blockSave);
        Assert.areEqual('Definitive Match', preview.status);
        Assert.areEqual('Exact Email Match', preview.reason);
        Assert.areEqual(1, preview.matches.size());
        Assert.areEqual('gc3541.wizard@example.com', preview.matches[0].email);
        Assert.areEqual('Doe', preview.matches[0].name);

        AuraHandledException thrown;
        try {
            LeadCreateController.createLeadWithProducts(leadRecord, null, true);
        } catch (AuraHandledException ex) {
            thrown = ex;
        }

        Assert.isNotNull(thrown);
        Assert.isTrue(thrown.getMessage().contains('Definitive Match'));
        Assert.areEqual(0, [SELECT COUNT() FROM Lead WHERE Email = 'gc3541.wizard@example.com']);
    }

    /**
     * @description GC-3541. A possible match waits for Continue, and Continue creates the Lead.
     */
    @IsTest
    static void customPageContinuesAfterPotentialMatch() {
        Group countryQueue = new Group(
            Name = 'Lead Create Duplicate Test',
            Type = 'Queue',
            DeveloperName = 'Lead_Create_Duplicate_Test'
        );
        insert countryQueue;
        insert new QueueSobject(QueueId = countryQueue.Id, SobjectType = 'Lead');
        LeadRoutingService.testCountryRows = new List<Lead_Country_Queue__mdt>{
            new Lead_Country_Queue__mdt(
                Country__c = 'US',
                QueueDeveloperName__c = 'Lead_Create_Duplicate_Test'
            )
        };

        Id leadId;
        System.runAs(new User(Id = UserInfo.getUserId())) {
            Account accountRecord = new Account(Name = 'Steris Clinic');
            insert accountRecord;
            insert new Contact(
                FirstName = 'Ann',
                LastName = 'Lee',
                Email = 'ann.existing@example.com',
                Phone = '5551112222',
                AccountId = accountRecord.Id
            );
            Lead leadRecord = new Lead(
                FirstName = 'Ann',
                LastName = 'Lee',
                Company = 'Steris Clinic',
                Email = 'ann.new.wizard@example.com',
                Phone = '5551112222',
                CountryCode = 'US',
                LeadSource = 'Marketing Campaign'
            );

            LeadCreateController.DuplicatePreview preview = LeadCreateController.previewLeadDuplicate(leadRecord);
            Assert.areEqual(true, preview.requiresConfirmation);
            Assert.areEqual('Potential Match', preview.status);
            Assert.areEqual(1, preview.matches.size());
            Assert.areEqual('Ann Lee', preview.matches[0].name);
            Assert.areEqual('ann.existing@example.com', preview.matches[0].email);
            Assert.areEqual('5551112222', preview.matches[0].phone);
            Assert.areEqual('Steris Clinic', preview.matches[0].accountName);

            AuraHandledException thrown;
            try {
                LeadCreateController.createLeadWithProducts(leadRecord, null, false);
            } catch (AuraHandledException ex) {
                thrown = ex;
            }
            Assert.isNotNull(thrown);
            Assert.areEqual(0, [SELECT COUNT() FROM Lead WHERE Email = 'ann.new.wizard@example.com']);

            Test.startTest();
            leadId = LeadCreateController.createLeadWithProducts(leadRecord, null, true);
            Test.stopTest();
        }

        Assert.areEqual(1, [SELECT COUNT() FROM Lead WHERE Id = :leadId]);
    }

    /**
     * @description GC-3541. A no-match on the custom page is saved even when the standard duplicate rule alerts.
     */
    @IsTest
    static void customPageSavesNoMatchPastStandardDuplicateAlert() {
        Group countryQueue = new Group(
            Name = 'Lead Create No Match Test',
            Type = 'Queue',
            DeveloperName = 'Lead_Create_No_Match_Test'
        );
        insert countryQueue;
        insert new QueueSobject(QueueId = countryQueue.Id, SobjectType = 'Lead');
        LeadRoutingService.testCountryRows = new List<Lead_Country_Queue__mdt>{
            new Lead_Country_Queue__mdt(
                Country__c = 'US',
                QueueDeveloperName__c = 'Lead_Create_No_Match_Test'
            )
        };

        Id leadId;
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert new Lead(
                FirstName = 'Nora',
                LastName = 'Fresh',
                Company = 'Brand New Clinic',
                Email = 'gc3541.existing.nora@example.com',
                Phone = '5554441000',
                CountryCode = 'US',
                LeadSource = 'Marketing Campaign'
            );
            Lead leadRecord = new Lead(
                FirstName = 'Nora',
                LastName = 'Fresh',
                Company = 'Brand New Clinic 1016',
                Email = 'gc3541.manual.nora@example.com',
                Phone = '5554443016',
                CountryCode = 'US',
                LeadSource = 'Marketing Campaign'
            );

            LeadCreateController.DuplicatePreview preview = LeadCreateController.previewLeadDuplicate(leadRecord);
            Assert.areEqual(false, preview.blockSave);
            Assert.areEqual(false, preview.requiresConfirmation);

            Test.startTest();
            leadId = LeadCreateController.createLeadWithProducts(leadRecord, null, false);
            Test.stopTest();
        }

        Assert.areEqual(1, [SELECT COUNT() FROM Lead WHERE Id = :leadId]);
    }
}