/**
 * @description GW-2137: Tests for ComplaintIntakeTrackwiseService and ComplaintIntakeTrackwiseQueueable.
 */
@IsTest
private class ComplaintIntakeTrackwiseServiceTest {

    private static ComplaintIntake__c createIntake() {
        Account acct = new Account(Name = 'GW-2137 Test Customer', SystemID__c = 'SYS-2137', OracleAddressId__c = 'ADDR-2137');
        insert acct;
        ComplaintIntake__c intake = new ComplaintIntake__c(
            Account__c = acct.Id,
            CustomerAddress__c = '1 Test Street',
            CustomerPhone__c = '5555550100',
            ComplainantName__c = 'Test Complainant'
        );
        insert intake;
        return [SELECT Id, Name FROM ComplaintIntake__c WHERE Id = :intake.Id];
    }

    private static ComplaintIntakeTrackwiseService.SubmitResult submit(Id intakeId, Boolean performCallout) {
        ComplaintIntakeTrackwiseService.SubmitRequest req = new ComplaintIntakeTrackwiseService.SubmitRequest();
        req.complaintIntakeId = intakeId;
        req.performCallout = performCallout;
        return ComplaintIntakeTrackwiseService.submitToTrackwise(
            new List<ComplaintIntakeTrackwiseService.SubmitRequest>{ req }
        )[0];
    }

    private static ComplaintIntake__c reload(Id intakeId) {
        return [
            SELECT SubmissionStatus__c, IntegrationStatus__c, IntegrationMessage__c, TrackwiseComplaintNumber__c
            FROM ComplaintIntake__c
            WHERE Id = :intakeId
        ];
    }

    @IsTest
    static void shouldBuildJsonWithIdAndNumber_WhenCalloutSkipped() {
        ComplaintIntake__c intake = createIntake();

        Test.startTest();
        ComplaintIntakeTrackwiseService.SubmitResult result = submit(intake.Id, false);
        Test.stopTest();

        Assert.isTrue(result.success, result.integrationMessage);
        Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(result.requestJson);
        Assert.areEqual(String.valueOf(intake.Id), body.get('ComplaintIntakeId'));
        Assert.areEqual(intake.Name, body.get('ComplaintIntakeNumber'));
        Assert.isNull(body.get('Part'));
        Assert.areEqual(4, body.size());
        Map<String, Object> complaint = (Map<String, Object>) body.get('Complaint');
        Assert.areEqual('SYS-2137', complaint.get('CMPL123CME__Customer__c'));
        Assert.areEqual('ADDR-2137', complaint.get('Customer_Address_ID__c'));
        Assert.areEqual('5555550100', complaint.get('Customer_Primary_Contact_Phone__c'));
        Assert.areEqual('Test Complainant', complaint.get('Complainant_Name__c'));
        Assert.isTrue(complaint.containsKey('Product_Number_SKU_Lookup__c'));
        Assert.isNull(reload(intake.Id).IntegrationStatus__c);
    }

    @IsTest
    static void shouldBuildPart_WithAssetIdFallback_WhenLegacyNumberBlank() {
        ComplaintIntake__c intake = createIntake();
        Product2 prod = new Product2(Name = 'GW-2137 Product', ProductCode = 'CE-2137');
        insert prod;
        Asset a = new Asset(
            Name = 'GW-2137 Asset',
            AccountId = [SELECT Account__c FROM ComplaintIntake__c WHERE Id = :intake.Id].Account__c,
            Product2Id = prod.Id,
            SerialNumber = 'SN-2137'
        );
        insert a;
        update new ComplaintIntake__c(Id = intake.Id, Asset__c = a.Id);

        Test.startTest();
        ComplaintIntakeTrackwiseService.SubmitResult result = submit(intake.Id, false);
        Test.stopTest();

        Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(result.requestJson);
        Map<String, Object> part = (Map<String, Object>) body.get('Part');
        Assert.areEqual('CE-2137', part.get('ITEM_NUM'));
        Assert.areEqual('SN-2137', part.get('SERIAL_NUM'));
        Assert.areEqual(String.valueOf(a.Id), part.get('EQUIPMENT_NUM'));
        Assert.areEqual(3, part.size());
    }

    @IsTest
    static void shouldStampSuccess_WhenTrackwiseReturnsNumber() {
        ComplaintIntake__c intake = createIntake();

        Test.startTest();
        ComplaintIntakeTrackwiseService.SubmitResult result = submit(intake.Id, true);
        Test.stopTest();

        Assert.isTrue(result.success, result.integrationMessage);
        ComplaintIntake__c stamped = reload(intake.Id);
        Assert.areEqual('Submitted', stamped.SubmissionStatus__c);
        Assert.areEqual('Success Create', stamped.IntegrationStatus__c);
        Assert.areEqual('TW-TEST-001', stamped.TrackwiseComplaintNumber__c);
        Assert.areEqual('Complaint created.', stamped.IntegrationMessage__c);
    }

    @IsTest
    static void shouldReadNumberFromJsonStringServiceData() {
        ComplaintIntake__c intake = createIntake();
        ComplaintIntakeTrackwiseService.testResponseOverride = new Map<String, Object>{
            'SO_SUCCESS' => true,
            'SERVICE_DATA' => '{"result":{"Complaint_Number":"TW-STR-9"}}'
        };

        Test.startTest();
        ComplaintIntakeTrackwiseService.SubmitResult result = submit(intake.Id, true);
        Test.stopTest();

        Assert.isTrue(result.success, result.integrationMessage);
        Assert.areEqual('TW-STR-9', reload(intake.Id).TrackwiseComplaintNumber__c);
    }

    @IsTest
    static void shouldStampFail_WhenNoNumberReturned() {
        ComplaintIntake__c intake = createIntake();
        ComplaintIntakeTrackwiseService.testResponseOverride = new Map<String, Object>{
            'SO_SUCCESS' => true,
            'SERVICE_DATA' => new Map<String, Object>{ 'message' => 'Part upsert failed' }
        };

        Test.startTest();
        ComplaintIntakeTrackwiseService.SubmitResult result = submit(intake.Id, true);
        Test.stopTest();

        Assert.isFalse(result.success);
        ComplaintIntake__c stamped = reload(intake.Id);
        Assert.areEqual('Submitted', stamped.SubmissionStatus__c);
        Assert.areEqual('Fail Create', stamped.IntegrationStatus__c);
        Assert.areEqual('Part upsert failed', stamped.IntegrationMessage__c);
        Assert.isNull(stamped.TrackwiseComplaintNumber__c);
    }

    @IsTest
    static void shouldStampFail_WhenTransportFails() {
        ComplaintIntake__c intake = createIntake();
        ComplaintIntakeTrackwiseService.testResponseOverride = new Map<String, Object>{
            'SO_SUCCESS' => false,
            'SO_RETURN' => 'Read timed out'
        };

        Test.startTest();
        ComplaintIntakeTrackwiseService.SubmitResult result = submit(intake.Id, true);
        Test.stopTest();

        Assert.isFalse(result.success);
        ComplaintIntake__c stamped = reload(intake.Id);
        Assert.areEqual('Fail Create', stamped.IntegrationStatus__c);
        Assert.areEqual('Read timed out', stamped.IntegrationMessage__c);
    }

    @IsTest
    static void shouldNotCreateAgain_WhenNumberAlreadySet() {
        ComplaintIntake__c intake = createIntake();
        update new ComplaintIntake__c(
            Id = intake.Id,
            TrackwiseComplaintNumber__c = 'TW-EXISTING',
            IntegrationStatus__c = 'Success Create',
            SubmissionStatus__c = 'Submit Create'
        );
        ComplaintIntakeTrackwiseService.testResponseOverride = new Map<String, Object>{
            'SO_SUCCESS' => true,
            'SERVICE_DATA' => new Map<String, Object>{ 'TrackwiseComplaintNumber' => 'TW-SECOND' }
        };

        Test.startTest();
        ComplaintIntakeTrackwiseService.SubmitResult result = submit(intake.Id, true);
        Test.stopTest();

        Assert.isTrue(result.success);
        Assert.isNull(result.requestJson);
        ComplaintIntake__c stamped = reload(intake.Id);
        Assert.areEqual('TW-EXISTING', stamped.TrackwiseComplaintNumber__c);
        Assert.areEqual('Success Create', stamped.IntegrationStatus__c);
        Assert.areEqual('Submitted', stamped.SubmissionStatus__c);
    }

    @IsTest
    static void shouldRunSubmit_WhenQueueableExecutes() {
        ComplaintIntake__c intake = createIntake();
        ComplaintIntakeTrackwiseQueueable.Request req = new ComplaintIntakeTrackwiseQueueable.Request();
        req.complaintIntakeId = intake.Id;

        Test.startTest();
        ComplaintIntakeTrackwiseQueueable.enqueue(new List<ComplaintIntakeTrackwiseQueueable.Request>{ req });
        Test.stopTest();

        Assert.areEqual('Success Create', reload(intake.Id).IntegrationStatus__c);
    }

    @IsTest
    static void shouldDoNothing_WhenQueueRequestEmpty() {
        Test.startTest();
        ComplaintIntakeTrackwiseQueueable.enqueue(null);
        ComplaintIntakeTrackwiseQueueable.enqueue(new List<ComplaintIntakeTrackwiseQueueable.Request>());
        Test.stopTest();

        Assert.areEqual(0, Limits.getQueueableJobs());
    }
}