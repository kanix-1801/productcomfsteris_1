/**
 * @description GC-2934 tests for Lead Submit routing.
 *
 *              Responsibilities:
 *              1. Verify one shared matrix queue is assigned.
 *              2. Verify one TAS rep is assigned when the matrix does not agree.
 *              3. Verify the country queue is used when TAS returns no rep.
 *              4. Verify a backend insert uses the same routing, unless the New Lead page skips it.
 *
 *              Queue developer names are unique per run because the org already has
 *              Lead_Country_US. The ultimate queue is the existing Lead_Ultimate_Queue.
 *              Leads use CountryCode and are
 *              inserted as the running user.
 * @author      Vinay
 * @date        2026-10-09
 */
@IsTest(SeeAllData=false)
private class LeadRoutingServiceTest {

    /**
     * @description Confirms every matching Product assigns the same queue.
     */
    @IsTest
    static void matchingProductsAssignTheMatrixQueue() {
        String queueName = uniqueDeveloperName('Lead_Rt_A');
        Group teamQueue = insertQueue(queueName, 'Lead Team A');
        Lead leadRecord = insertLeadWithProduct('Sterilizer', 'US');
        update new Lead(Id = leadRecord.Id, HubSpot_Lead__c = true);
        LeadRoutingService.testMatrixRows = new List<Lead_Routing_Matrix__mdt>{
            matrixRow('Sterilizer', queueName)
        };

        Test.startTest();
        String message = LeadRoutingService.submit(leadRecord.Id);
        Test.stopTest();

        Assert.areEqual(
            teamQueue.Id,
            [SELECT OwnerId FROM Lead WHERE Id = :leadRecord.Id].OwnerId,
            'The Lead should be owned by the shared matrix queue.'
        );
        Assert.isTrue(message.contains('Lead Team A'), 'The toast should name the matrix queue.');
    }

    /**
     * @description Confirms one TAS rep owns the Lead when Products resolve to different queues.
     */
    @IsTest
    static void differentQueuesAssignTheTasRep() {
        String sterilizerQueue = uniqueDeveloperName('Lead_Rt_A');
        String washerQueue = uniqueDeveloperName('Lead_Rt_B');
        insertQueue(sterilizerQueue, 'Lead Team A');
        insertQueue(washerQueue, 'Lead Team B');
        Lead leadRecord = insertLeadWithProduct('Sterilizer', 'US');
        update new Lead(Id = leadRecord.Id, HubSpot_Lead__c = true);
        System.runAs(runningUser()) {
            Product2 secondProduct = new Product2(Name = 'Washer', IsActive = true, BusinessUnit__c = 'IMS');
            insert secondProduct;
            insert new LeadProduct__c(
                Lead__c = leadRecord.Id,
                Product__c = secondProduct.Id,
                ParentCategory__c = 'Infection Prevention',
                ProductCategory__c = 'Capital'
            );
        }
        LeadRoutingService.testMatrixRows = new List<Lead_Routing_Matrix__mdt>{
            matrixRow('Sterilizer', sterilizerQueue),
            matrixRow('Washer', washerQueue)
        };
        LeadRoutingService.testTasOwnerId = UserInfo.getUserId();

        Test.startTest();
        String message = LeadRoutingService.submit(leadRecord.Id);
        Test.stopTest();

        Assert.areEqual(
            UserInfo.getUserId(),
            [SELECT OwnerId FROM Lead WHERE Id = :leadRecord.Id].OwnerId,
            'Different matrix queues should assign the TAS rep.'
        );
        Assert.isTrue(
            message.contains([SELECT Name FROM User WHERE Id = :UserInfo.getUserId()].Name),
            'The toast should name the assigned rep.'
        );
    }

    /**
     * A Lead created in Salesforce keeps its owner. TAS and queue routing do not run.
     */
    @IsTest
    static void manualLeadSkipsRouting() {
        Lead leadRecord = insertLeadWithProduct('Sterilizer', 'US');
        LeadRoutingService.testMatrixRows = new List<Lead_Routing_Matrix__mdt>{
            matrixRow('Sterilizer', 'Lead_Rt_Unused')
        };
        LeadRoutingService.testTasOwnerId = UserInfo.getUserId();
        LeadRoutingService.testCountryRows = new List<Lead_Country_Queue__mdt>{
            new Lead_Country_Queue__mdt(Country__c = 'US', QueueDeveloperName__c = 'Lead_Rt_Unused')
        };

        Test.startTest();
        LeadRoutingService.submit(leadRecord.Id);
        Test.stopTest();

        Assert.areEqual(
            UserInfo.getUserId(),
            [SELECT OwnerId FROM Lead WHERE Id = :leadRecord.Id].OwnerId,
            'A Lead that is not from HubSpot should keep the owner who created it.'
        );
    }

    /**
     * @description Confirms the country queue is used when TAS returns no rep.
     */
    @IsTest
    static void noTasRepAssignsTheCountryQueue() {
        String queueName = uniqueDeveloperName('Lead_Rt_US');
        Group countryQueue = insertQueue(queueName, 'Lead US Queue');
        Lead leadRecord = insertLeadWithProduct('Sterilizer', 'US');
        update new Lead(Id = leadRecord.Id, HubSpot_Lead__c = true);
        LeadRoutingService.testCountryRows = new List<Lead_Country_Queue__mdt>{
            new Lead_Country_Queue__mdt(Country__c = 'US', QueueDeveloperName__c = queueName)
        };

        Test.startTest();
        LeadRoutingService.submit(leadRecord.Id);
        Test.stopTest();

        Assert.areEqual(
            countryQueue.Id,
            [SELECT OwnerId FROM Lead WHERE Id = :leadRecord.Id].OwnerId,
            'No TAS rep should fall through to the country queue.'
        );
    }

    /**
     * @description A Lead inserted outside the New Lead page uses the country queue.
     */
    @IsTest
    static void backendInsertAssignsTheCountryQueue() {
        String queueName = uniqueDeveloperName('Lead_Rt_US');
        Group countryQueue = insertQueue(queueName, 'Lead US Queue');
        LeadRoutingService.testCountryRows = new List<Lead_Country_Queue__mdt>{
            new Lead_Country_Queue__mdt(Country__c = 'US', QueueDeveloperName__c = queueName)
        };

        Test.startTest();
        Lead leadRecord = newLead('Backend', 'US');
        leadRecord.HubSpot_Lead__c = true;
        System.runAs(runningUser()) {
            insert leadRecord;
        }
        Test.stopTest();

        Assert.areEqual(
            countryQueue.Id,
            [SELECT OwnerId FROM Lead WHERE Id = :leadRecord.Id].OwnerId,
            'A backend insert should route to the country queue.'
        );
    }

    /**
     * @description A backend Lead with no country queue is assigned to the existing ultimate queue.
     */
    @IsTest
    static void backendInsertAssignsTheUltimateQueue() {
        Group ultimateQueue = [
            SELECT Id
            FROM Group
            WHERE Type = 'Queue'
            AND DeveloperName = :System.Label.LeadUltimateQueueDeveloperName
            LIMIT 1
        ];
        LeadRoutingService.testCountryRows = new List<Lead_Country_Queue__mdt>();

        Test.startTest();
        Lead leadRecord = newLead('BackendUltimate', 'IE');
        leadRecord.HubSpot_Lead__c = true;
        System.runAs(runningUser()) {
            insert leadRecord;
        }
        Test.stopTest();

        Assert.areEqual(
            ultimateQueue.Id,
            [SELECT OwnerId FROM Lead WHERE Id = :leadRecord.Id].OwnerId,
            'A country with no queue should route to the ultimate queue.'
        );
    }

    /**
     * @description The New Lead page sets skipInsertTas so the trigger does not route the same Lead.
     */
    @IsTest
    static void skippedInsertDoesNotRoute() {
        String queueName = uniqueDeveloperName('Lead_Rt_US');
        insertQueue(queueName, 'Lead US Queue');
        LeadRoutingService.testCountryRows = new List<Lead_Country_Queue__mdt>{
            new Lead_Country_Queue__mdt(Country__c = 'US', QueueDeveloperName__c = queueName)
        };
        LeadService.skipInsertTas = true;

        Test.startTest();
        Lead leadRecord = newLead('SkipRoute', 'US');
        System.runAs(runningUser()) {
            insert leadRecord;
        }
        Test.stopTest();

        Assert.areEqual(
            UserInfo.getUserId(),
            [SELECT OwnerId FROM Lead WHERE Id = :leadRecord.Id].OwnerId,
            'A skipped insert should stay with the user who created it.'
        );
    }

    /**
     * @description Inserts a Lead queue. Kept outside runAs so it is not mixed with a User insert.
     * @param developerName Queue developer name. Must not already exist in the org.
     * @param label Queue label shown in the routing message.
     * @return Inserted queue.
     */
    private static Group insertQueue(String developerName, String label) {
        Group queueRecord = new Group(Name = label, Type = 'Queue', DeveloperName = developerName);
        insert queueRecord;
        insert new QueueSobject(QueueId = queueRecord.Id, SobjectType = 'Lead');
        return queueRecord;
    }

    /**
     * @description Inserts a Lead and one Product as the running user.
     * @param productName Product name used by the matrix row.
     * @param countryCode ISO country code stored on the Lead.
     * @return Inserted Lead.
     */
    private static Lead insertLeadWithProduct(String productName, String countryCode) {
        Lead leadRecord = newLead('Submit', countryCode);
        System.runAs(runningUser()) {
            insert leadRecord;
            Product2 productRecord = new Product2(
                Name = productName,
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
        }
        return leadRecord;
    }

    /**
     * @description Builds a Lead that satisfies the Sales Lead validation rules.
     * @param lastName Last name.
     * @param countryCode ISO country code. The platform fills Country from this code.
     * @return Unsaved Lead.
     */
    private static Lead newLead(String lastName, String countryCode) {
        String token = EncodingUtil.convertToHex(Crypto.generateAesKey(128)).substring(0, 10);
        return new Lead(
            FirstName = 'Ada',
            LastName = lastName,
            Company = 'Steris',
            CountryCode = countryCode,
            Email = lastName.toLowerCase() + '.' + token + '@example.com',
            LeadSource = 'Web',
            Status = 'New'
        );
    }

    /**
     * @description Builds a matrix row for the United States.
     * @param productName Product name.
     * @param queueDeveloperName Queue the row assigns.
     * @return Unsaved matrix row used only in the test.
     */
    private static Lead_Routing_Matrix__mdt matrixRow(String productName, String queueDeveloperName) {
        return new Lead_Routing_Matrix__mdt(
            ProductName__c = productName,
            ParentCategory__c = 'Infection Prevention',
            ProductCategory__c = 'Capital',
            BusinessUnit__c = 'IMS',
            Country__c = 'US',
            QueueDeveloperName__c = queueDeveloperName
        );
    }

    /**
     * @description A developer name that does not collide with queues already in the org.
     * @param prefix Short prefix. The full name stays within 40 characters.
     * @return Unique queue developer name.
     */
    private static String uniqueDeveloperName(String prefix) {
        String developerName = prefix + '_' + EncodingUtil.convertToHex(Crypto.generateAesKey(128)).substring(0, 8);
        return developerName.length() > 40 ? developerName.substring(0, 40) : developerName;
    }

    /**
     * @description The user the test is already running as.
     * @return Current user, without a User insert.
     */
    private static User runningUser() {
        return new User(Id = UserInfo.getUserId());
    }
}