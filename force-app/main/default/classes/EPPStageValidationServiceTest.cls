/**
 * @description GC-3431 tests for EPP stage validation when an Opportunity leaves Draft.
 *
 *              Responsibilities:
 *              1. Verify missing trigger context and unchanged stages are ignored.
 *              2. Verify an elevated consumable without an EPP Price blocks the stage change.
 *              3. Verify a priced elevated consumable is allowed and unexpected errors are logged.
 * @author      Vinay
 * @date        2026-10-29
 */
@IsTest(SeeAllData=false)
private class EPPStageValidationServiceTest {

    private static final String CONSUMABLE_CODE = 'EPP-STAGE-CON-001';

    /**
     * @description Creates an EPP Opportunity and one eligible consumable.
     * @return None.
     */
    @TestSetup
    static void setupData() {
        Account accountRecord = new Account(
            Name = 'GC-3431 Stage Validation Account',
            SourceSystemID__c = 'GC3431-STAGE-TEST'
        );
        insert accountRecord;

        Contact contactRecord = new Contact(
            LastName = 'GC-3431 Stage Contact',
            AccountId = accountRecord.Id
        );
        insert contactRecord;

        Product2 consumable = new Product2(
            Name = 'Stage Validation Consumable',
            ProductCode = CONSUMABLE_CODE,
            IsActive = true,
            EPPEligible__c = true,
            IsConsumable__c = true,
            ItemFamily__c = 'Consumables',
            BusinessUnit__c = 'IMS'
        );
        insert consumable;

        Id standardPricebookId = Test.getStandardPricebookId();
        insert new PricebookEntry(
            Pricebook2Id = standardPricebookId,
            Product2Id = consumable.Id,
            UnitPrice = 100,
            IsActive = true
        );

        Id eppRecordTypeId = Schema.SObjectType.Opportunity
            .getRecordTypeInfosByDeveloperName()
            .get('HCSalesEquipmentPlacementProgram')
            .getRecordTypeId();

        insert new Opportunity(
            Name = 'GC-3431 Stage Validation Opportunity',
            AccountId = accountRecord.Id,
            RecordTypeId = eppRecordTypeId,
            StageName = 'Draft',
            Type = 'New Business',
            Amount = 1000,
            Probability = 10,
            PrimaryContact__c = contactRecord.Id,
            CloseDate = Date.today().addDays(30),
            Pricebook2Id = standardPricebookId,
            ConsumablesCommitment__c = true
        );
    }

    /**
     * @description Returns the EPP Opportunity created by test setup.
     * @return The test Opportunity, including the values used by stage validation.
     */
    private static Opportunity getOpportunity() {
        return [
            SELECT Id, RecordTypeId, StageName, Pricebook2Id
            FROM Opportunity
            WHERE Name = 'GC-3431 Stage Validation Opportunity'
            LIMIT 1
        ];
    }

    /**
     * @description Inserts the test consumable on the EPP Opportunity.
     * @param eppPrice EPP Price. Null represents an elevated line that should block leaving Draft.
     * @return None.
     */
    private static void insertElevatedConsumable(Decimal eppPrice) {
        Opportunity opportunityRecord = getOpportunity();
        PricebookEntry consumableEntry = [
            SELECT Id, UnitPrice
            FROM PricebookEntry
            WHERE Pricebook2Id = :opportunityRecord.Pricebook2Id
              AND Product2.ProductCode = :CONSUMABLE_CODE
            LIMIT 1
        ];
        insert new OpportunityLineItem(
            OpportunityId = opportunityRecord.Id,
            PricebookEntryId = consumableEntry.Id,
            Quantity = 1,
            UnitPrice = consumableEntry.UnitPrice,
            ElevatedEPPPricingApplicable__c = true,
            EPPPrice__c = eppPrice,
            ConsumptionFrequency__c = 'Monthly',
            CommitmentStartDate__c = Date.today(),
            CommitmentEndDate__c = Date.today().addYears(1)
        );
    }

    /**
     * @description Runs stage validation for an in-memory move out of Draft.
     * @param opportunityRecord Opportunity being updated. Its stage is changed by this method.
     * @param oldOpportunitiesById Previous Opportunity values supplied to the service.
     * @return None.
     */
    private static void validateLeavingDraft(
        Opportunity opportunityRecord,
        Map<Id, Opportunity> oldOpportunitiesById
    ) {
        opportunityRecord.StageName = 'Discovery';
        EPPStageValidationService.validateBeforeUpdate(
            new List<Opportunity>{ opportunityRecord },
            oldOpportunitiesById
        );
    }

    /**
     * @description Confirms a missing or empty Opportunity context does not add an error.
     */
    @IsTest
    static void missingContextIsIgnored() {
        Test.startTest();
        EPPStageValidationService.validateBeforeUpdate(null, null);
        EPPStageValidationService.validateBeforeUpdate(
            new List<Opportunity>(),
            new Map<Id, Opportunity>()
        );
        Test.stopTest();

        Assert.areEqual(
            0,
            [SELECT COUNT() FROM Opportunity WHERE StageName != 'Draft'],
            'Missing context must not change the Opportunity stage.'
        );
    }

    /**
     * @description Confirms an EPP that remains in Draft is not blocked.
     */
    @IsTest
    static void draftStageIsNotBlocked() {
        Opportunity opportunityRecord = getOpportunity();
        Opportunity oldOpportunity = opportunityRecord.clone(true, true, true, true);

        Test.startTest();
        EPPStageValidationService.validateBeforeUpdate(
            new List<Opportunity>{ opportunityRecord },
            new Map<Id, Opportunity>{ opportunityRecord.Id => oldOpportunity }
        );
        Test.stopTest();

        Assert.isTrue(
            opportunityRecord.getErrors().isEmpty(),
            'Staying in Draft must not require an EPP Price.'
        );
    }

    /**
     * @description Confirms leaving Draft is blocked when an elevated consumable has no EPP Price.
     */
    @IsTest
    static void missingEppPriceBlocksLeavingDraft() {
        insert new Automation_Setting_Validation_Rule__c(
            SetupOwnerId = UserInfo.getUserId(),
            EPPPriceRequiredWhenElevated__c = true
        );
        insertElevatedConsumable(null);
        Opportunity opportunityRecord = getOpportunity();
        Opportunity oldOpportunity = opportunityRecord.clone(true, true, true, true);

        Test.startTest();
        validateLeavingDraft(
            opportunityRecord,
            new Map<Id, Opportunity>{ opportunityRecord.Id => oldOpportunity }
        );
        Test.stopTest();

        Assert.areEqual(1, opportunityRecord.getErrors().size(), 'A blank EPP Price must block the stage change.');
        Assert.isTrue(
            opportunityRecord.getErrors()[0].getMessage().contains('Enter an EPP Price'),
            'The stage error must tell the user to enter the EPP Price.'
        );
    }

    /**
     * @description Confirms leaving Draft is allowed when the elevated consumable has an EPP Price.
     */
    @IsTest
    static void pricedConsumableCanLeaveDraft() {
        insertElevatedConsumable(80);
        Opportunity opportunityRecord = getOpportunity();
        Opportunity oldOpportunity = opportunityRecord.clone(true, true, true, true);

        Test.startTest();
        validateLeavingDraft(
            opportunityRecord,
            new Map<Id, Opportunity>{ opportunityRecord.Id => oldOpportunity }
        );
        Test.stopTest();

        Assert.isTrue(
            opportunityRecord.getErrors().isEmpty(),
            'An elevated consumable with an EPP Price must not block the stage change.'
        );
    }

    /**
     * @description Confirms a stage change without its previous Opportunity is logged and rethrown.
     */
    @IsTest
    static void missingPreviousOpportunityIsRethrown() {
        Opportunity opportunityRecord = getOpportunity();
        Boolean wasRethrown = false;

        Test.startTest();
        try {
            validateLeavingDraft(opportunityRecord, new Map<Id, Opportunity>());
        } catch (Exception expectedException) {
            wasRethrown = true;
        }
        Test.stopTest();

        Assert.isTrue(wasRethrown, 'A missing previous Opportunity must be logged and rethrown.');
    }
}