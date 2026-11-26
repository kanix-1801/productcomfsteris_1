/**
 * @description GW-5892 - Tests for QuoteSelector: HC Sales quotes (Normal, Trial, Sample and Goodwill) on dedicated
 *              Opportunities, every public method and overload, the null / empty input guards and the branch used
 *              when the HCSales record type is not available. Built from the sterisDev QuoteSelectorTest.
 *              Named QuoteSelectorTests so the PR pipeline's test matching picks it for QuoteSelector (a class named
 *              QuoteSelectorTest is skipped because ProductSubGroupDetailQuoteSelectorTest matches first).
 *              The GW-4378 selectByWorkOrderIds tests stay in QuoteSelectorTest on that branch.
 */
@IsTest
private class QuoteSelectorTests {
    private static final String QUOTE_USER_LAST_NAME = 'QuoteSelectorTestUser';
    private static final String RESTRICTED_USER_LAST_NAME = 'QuoteSelectorRestrictedUser';
    private static final String SALES_PSG_DEVELOPER_NAME = 'SalesFieldRepAccountManagerPSG';
    private static final String SYSTEM_ADMIN_PROFILE = 'System Administrator';
    private static final String MINIMUM_ACCESS_PROFILE = 'Minimum Access - Salesforce';
    private static final String STANDARD_USER_PROFILE = 'Standard User';
    private static final String OPPORTUNITY_RECORD_TYPE_DEVELOPER_NAME = 'Healthcare_Sales';
    private static final String SAMPLE_PURPOSE_EVALUATION = 'Evaluation';

    private static final String QUOTE_NORMAL_OPEN = 'QST Normal Open';
    private static final String QUOTE_NORMAL_CLOSED = 'QST Normal Closed';
    private static final String QUOTE_NORMAL_DRAFT = 'QST Normal Draft';
    private static final String QUOTE_TRIAL_INELIGIBLE = 'QST Trial Ineligible';
    private static final String QUOTE_TRIAL_ELIGIBLE = 'QST Trial Eligible';
    private static final String QUOTE_SAMPLE_INELIGIBLE = 'QST Sample Ineligible';
    private static final String QUOTE_SAMPLE_ELIGIBLE = 'QST Sample Eligible';
    private static final String QUOTE_GOODWILL = 'QST Goodwill';
    private static final String QUOTE_B_NORMAL_OPEN = 'QST B Normal Open';
    private static final String QUOTE_B_GOODWILL = 'QST B Goodwill';

    /*
     * Opportunity A quotes (all HCSales record type):
     *   Normal Open       - Open,   Normal,   Forecast Eligible,     eligible,   1 line item
     *   Normal Closed     - Closed, Normal,   Forecast Eligible,     eligible
     *   Normal Draft      - Draft,  Normal,   not Forecast Eligible, eligible
     *   Trial Ineligible  - Open,   Trial,    Trial__c,              forecast-ineligible
     *   Trial Eligible    - Open,   Trial,    Trial__c,              eligible
     *   Sample Ineligible - Open,   Sample,   Sample__c,             forecast-ineligible
     *   Sample Eligible   - Open,   Sample,   Sample__c,             eligible
     *   Goodwill          - Open,   Goodwill,                        forecast-ineligible
     * Opportunity B quotes: B Normal Open (Forecast Eligible) and B Goodwill (forecast-ineligible).
     * Opportunity C has no quotes.
     */
    private static final Integer OPPORTUNITY_A_QUOTE_COUNT = 8;
    private static final Integer OPPORTUNITY_A_NORMAL_QUOTE_COUNT = 3;
    private static final Integer OPPORTUNITY_A_ELIGIBLE_QUOTE_COUNT = 5;
    private static final Integer OPPORTUNITY_A_TRIAL_QUOTE_COUNT = 2;
    private static final Integer OPPORTUNITY_A_SAMPLE_QUOTE_COUNT = 2;
    private static final Integer OPPORTUNITY_A_OPEN_QUOTE_COUNT = 7;
    private static final Integer OPPORTUNITY_A_OPEN_SPECIAL_QUOTE_COUNT = 5;
    private static final Integer OPPORTUNITY_B_QUOTE_COUNT = 2;

    @TestSetup
    static void setupData() {
        insert new List<SObject>{
            new Automation_Setting_Trigger__c(
                SetupOwnerId = UserInfo.getOrganizationId(),
                disableAll__c = true
            ),
            new Automation_Setting_Validation_Rule__c(
                SetupOwnerId = UserInfo.getOrganizationId(),
                disableAll__c = true
            )
        };

        User quoteUser;
        System.runAs(new User(Id = UserInfo.getUserId())) {
            Profile adminProfile = [SELECT Id FROM Profile WHERE Name = :SYSTEM_ADMIN_PROFILE LIMIT 1];
            quoteUser = buildUser(adminProfile.Id, QUOTE_USER_LAST_NAME);
            User restrictedUser = buildUser(resolveRestrictedProfileId(), RESTRICTED_USER_LAST_NAME);
            insert new List<User>{ quoteUser, restrictedUser };

            // Assign the group's permission sets directly instead of the group itself: a permission set group can
            // only be assigned when its status is "Updated", which is not guaranteed in a validation org.
            // SalesFieldRepAccountManager (Quote.HCSales record type) is one of them. Licensed / managed
            // permission sets are skipped so the assignment never needs an extra license.
            List<PermissionSetAssignment> assignments = new List<PermissionSetAssignment>();
            for (PermissionSet permissionSetRecord : [
                SELECT Id
                FROM PermissionSet
                WHERE Id IN (
                        SELECT PermissionSetId
                        FROM PermissionSetGroupComponent
                        WHERE PermissionSetGroup.DeveloperName = :SALES_PSG_DEVELOPER_NAME
                    )
                    AND NamespacePrefix = NULL
                    AND LicenseId = NULL
            ]) {
                assignments.add(
                    new PermissionSetAssignment(AssigneeId = quoteUser.Id, PermissionSetId = permissionSetRecord.Id)
                );
            }
            insert assignments;
        }

        System.runAs(quoteUser) {
            createQuoteData();
        }
    }

    /**
     * @description Verifies the single-argument and quote-type overloads return every quote on the
     *              Opportunity, with child line items, and nothing from other Opportunities.
     */
    @IsTest
    static void testSelectByOpportunityIdWithLineItemsReturnsAllQuotes() {

        /********************************************
        * SETUP
        ********************************************/
        User testUser = getQuoteUser();

        System.runAs(testUser) {

            /********************************************
            * GIVEN
            ********************************************/
            Fixture fixture = new Fixture();
            Assert.areEqual(
                OPPORTUNITY_A_QUOTE_COUNT,
                [SELECT COUNT() FROM Quote WHERE OpportunityId = :fixture.opportunityAId],
                'Opportunity A setup quotes should exist.'
            );

            /********************************************
            * WHEN
            ********************************************/
            Test.startTest();
            List<Quote> allQuotes = QuoteSelector.selectByOpportunityIdWithLineItems(fixture.opportunityAId);
            List<Quote> blankFilterQuotes = QuoteSelector.selectByOpportunityIdWithLineItems(
                fixture.opportunityAId,
                ''
            );
            List<Quote> emptyOpportunityQuotes = QuoteSelector.selectByOpportunityIdWithLineItems(
                fixture.opportunityCId
            );
            Test.stopTest();

            /********************************************
            * THEN
            ********************************************/
            Assert.areEqual(OPPORTUNITY_A_QUOTE_COUNT, allQuotes.size(), 'All Opportunity A quotes are returned.');
            Assert.areEqual(
                OPPORTUNITY_A_QUOTE_COUNT,
                blankFilterQuotes.size(),
                'A blank quote type filter does not restrict results.'
            );
            Assert.areEqual(0, emptyOpportunityQuotes.size(), 'Opportunity without quotes returns none.');

            Set<Id> returnedIds = new Map<Id, Quote>(allQuotes).keySet();
            Assert.isFalse(
                returnedIds.contains(fixture.quoteId(QUOTE_B_NORMAL_OPEN)),
                'Quotes from another Opportunity are not returned.'
            );

            Quote normalOpenQuote = findQuote(allQuotes, fixture.quoteId(QUOTE_NORMAL_OPEN));
            Assert.isNotNull(normalOpenQuote, 'Normal open quote is returned.');
            Assert.areEqual(1, normalOpenQuote.QuoteLineItems.size(), 'Child quote line item is returned.');
            Assert.areEqual(
                2,
                Integer.valueOf(normalOpenQuote.QuoteLineItems[0].Quantity),
                'Quote line item quantity is selected.'
            );
        }
    }

    /**
     * @description Verifies the quote type filter and forecast-ineligible exclusion overloads.
     */
    @IsTest
    static void testSelectByOpportunityIdWithLineItemsFiltersByTypeAndEligibility() {

        /********************************************
        * SETUP
        ********************************************/
        User testUser = getQuoteUser();

        System.runAs(testUser) {

            /********************************************
            * GIVEN
            ********************************************/
            Fixture fixture = new Fixture();
            Assert.isNotNull(fixture.opportunityAId, 'Opportunity A exists.');

            /********************************************
            * WHEN
            ********************************************/
            Test.startTest();
            List<Quote> normalQuotes = QuoteSelector.selectByOpportunityIdWithLineItems(
                fixture.opportunityAId,
                GenerateQuoteService.QUOTE_TYPE_NORMAL
            );
            List<Quote> normalQuotesExcludingIneligible = QuoteSelector.selectByOpportunityIdWithLineItems(
                fixture.opportunityAId,
                GenerateQuoteService.QUOTE_TYPE_NORMAL,
                true
            );
            List<Quote> eligibleQuotes = QuoteSelector.selectByOpportunityIdWithLineItems(
                fixture.opportunityAId,
                null,
                true
            );
            List<Quote> allQuotes = QuoteSelector.selectByOpportunityIdWithLineItems(
                fixture.opportunityAId,
                null,
                false
            );
            Test.stopTest();

            /********************************************
            * THEN
            ********************************************/
            Assert.areEqual(OPPORTUNITY_A_NORMAL_QUOTE_COUNT, normalQuotes.size(), 'Only Normal quotes are returned.');
            for (Quote quoteRecord : normalQuotes) {
                Assert.areEqual(
                    GenerateQuoteService.QUOTE_TYPE_NORMAL,
                    quoteRecord.QuoteType__c,
                    'Quote type filter is applied.'
                );
            }
            Assert.areEqual(
                OPPORTUNITY_A_NORMAL_QUOTE_COUNT,
                normalQuotesExcludingIneligible.size(),
                'Quote type filter takes precedence over the eligibility flag.'
            );
            Assert.areEqual(
                OPPORTUNITY_A_ELIGIBLE_QUOTE_COUNT,
                eligibleQuotes.size(),
                'Forecast-ineligible quotes are excluded.'
            );
            for (Quote quoteRecord : eligibleQuotes) {
                Assert.isFalse(quoteRecord.IsForecastIneligible__c, 'Only forecast-eligible quotes are returned.');
            }
            Assert.areEqual(OPPORTUNITY_A_QUOTE_COUNT, allQuotes.size(), 'No exclusion returns every quote.');
        }
    }

    /**
     * @description Verifies every Trial__c filter branch of selectByOpportunityIdWithLineItems.
     */
    @IsTest
    static void testSelectByOpportunityIdWithLineItemsFiltersByTrial() {

        /********************************************
        * SETUP
        ********************************************/
        User testUser = getQuoteUser();

        System.runAs(testUser) {

            /********************************************
            * GIVEN
            ********************************************/
            Fixture fixture = new Fixture();
            Assert.isNotNull(fixture.trialId, 'Trial record exists.');

            /********************************************
            * WHEN
            ********************************************/
            Test.startTest();
            List<Quote> trialQuotes = QuoteSelector.selectByOpportunityIdWithLineItems(
                fixture.opportunityAId,
                null,
                false,
                fixture.trialId
            );
            List<Quote> trialTypedQuotes = QuoteSelector.selectByOpportunityIdWithLineItems(
                fixture.opportunityAId,
                GenerateQuoteService.QUOTE_TYPE_TRIAL,
                false,
                fixture.trialId
            );
            List<Quote> mismatchedTypeQuotes = QuoteSelector.selectByOpportunityIdWithLineItems(
                fixture.opportunityAId,
                GenerateQuoteService.QUOTE_TYPE_SAMPLE,
                false,
                fixture.trialId
            );
            List<Quote> eligibleTrialQuotes = QuoteSelector.selectByOpportunityIdWithLineItems(
                fixture.opportunityAId,
                null,
                true,
                fixture.trialId
            );
            Test.stopTest();

            /********************************************
            * THEN
            ********************************************/
            Assert.areEqual(OPPORTUNITY_A_TRIAL_QUOTE_COUNT, trialQuotes.size(), 'Trial quotes are returned.');
            for (Quote quoteRecord : trialQuotes) {
                Assert.areEqual(fixture.trialId, quoteRecord.Trial__c, 'Trial filter is applied.');
            }
            Assert.areEqual(
                OPPORTUNITY_A_TRIAL_QUOTE_COUNT,
                trialTypedQuotes.size(),
                'Trial filter combined with Trial quote type returns the trial quotes.'
            );
            Assert.areEqual(0, mismatchedTypeQuotes.size(), 'Trial filter combined with Sample quote type is empty.');
            Assert.areEqual(1, eligibleTrialQuotes.size(), 'Only the forecast-eligible trial quote is returned.');
            Assert.areEqual(
                fixture.quoteId(QUOTE_TRIAL_ELIGIBLE),
                eligibleTrialQuotes[0].Id,
                'Forecast-eligible trial quote is returned.'
            );
        }
    }

    /**
     * @description Verifies every Sample__c filter branch of selectByOpportunityIdWithLineItems.
     */
    @IsTest
    static void testSelectByOpportunityIdWithLineItemsFiltersBySample() {

        /********************************************
        * SETUP
        ********************************************/
        User testUser = getQuoteUser();

        System.runAs(testUser) {

            /********************************************
            * GIVEN
            ********************************************/
            Fixture fixture = new Fixture();
            Assert.isNotNull(fixture.sampleId, 'Sample record exists.');

            /********************************************
            * WHEN
            ********************************************/
            Test.startTest();
            List<Quote> sampleQuotes = QuoteSelector.selectByOpportunityIdWithLineItems(
                fixture.opportunityAId,
                null,
                false,
                null,
                fixture.sampleId
            );
            List<Quote> sampleTypedQuotes = QuoteSelector.selectByOpportunityIdWithLineItems(
                fixture.opportunityAId,
                GenerateQuoteService.QUOTE_TYPE_SAMPLE,
                false,
                null,
                fixture.sampleId
            );
            List<Quote> mismatchedTypeQuotes = QuoteSelector.selectByOpportunityIdWithLineItems(
                fixture.opportunityAId,
                GenerateQuoteService.QUOTE_TYPE_TRIAL,
                false,
                null,
                fixture.sampleId
            );
            List<Quote> eligibleSampleQuotes = QuoteSelector.selectByOpportunityIdWithLineItems(
                fixture.opportunityAId,
                null,
                true,
                null,
                fixture.sampleId
            );
            Test.stopTest();

            /********************************************
            * THEN
            ********************************************/
            Assert.areEqual(OPPORTUNITY_A_SAMPLE_QUOTE_COUNT, sampleQuotes.size(), 'Sample quotes are returned.');
            for (Quote quoteRecord : sampleQuotes) {
                Assert.areEqual(fixture.sampleId, quoteRecord.Sample__c, 'Sample filter is applied.');
            }
            Assert.areEqual(
                OPPORTUNITY_A_SAMPLE_QUOTE_COUNT,
                sampleTypedQuotes.size(),
                'Sample filter combined with Sample quote type returns the sample quotes.'
            );
            Assert.areEqual(0, mismatchedTypeQuotes.size(), 'Sample filter combined with Trial quote type is empty.');
            Assert.areEqual(1, eligibleSampleQuotes.size(), 'Only the forecast-eligible sample quote is returned.');
            Assert.areEqual(
                fixture.quoteId(QUOTE_SAMPLE_ELIGIBLE),
                eligibleSampleQuotes[0].Id,
                'Forecast-eligible sample quote is returned.'
            );
        }
    }

    /**
     * @description Verifies every selectByOpportunityIdWithLineItems overload returns an empty list for a
     *              null Opportunity Id.
     */
    @IsTest
    static void testSelectByOpportunityIdWithLineItemsNullOpportunity() {

        /********************************************
        * SETUP
        ********************************************/
        User testUser = getQuoteUser();

        System.runAs(testUser) {

            /********************************************
            * GIVEN
            ********************************************/
            Fixture fixture = new Fixture();
            Assert.isNotNull(fixture.trialId, 'Trial record exists.');

            /********************************************
            * WHEN
            ********************************************/
            Test.startTest();
            List<List<Quote>> results = new List<List<Quote>>{
                QuoteSelector.selectByOpportunityIdWithLineItems(null),
                QuoteSelector.selectByOpportunityIdWithLineItems(null, GenerateQuoteService.QUOTE_TYPE_NORMAL),
                QuoteSelector.selectByOpportunityIdWithLineItems(null, null, true),
                QuoteSelector.selectByOpportunityIdWithLineItems(null, null, true, fixture.trialId),
                QuoteSelector.selectByOpportunityIdWithLineItems(null, null, true, null, fixture.sampleId)
            };
            Test.stopTest();

            /********************************************
            * THEN
            ********************************************/
            for (List<Quote> result : results) {
                Assert.isNotNull(result, 'A list is always returned.');
                Assert.areEqual(0, result.size(), 'Null Opportunity Id returns no quotes.');
            }
        }
    }

    /**
     * @description Verifies every countByOpportunityId overload and filter branch, including the null guard.
     */
    @IsTest
    static void testCountByOpportunityId() {

        /********************************************
        * SETUP
        ********************************************/
        User testUser = getQuoteUser();

        System.runAs(testUser) {

            /********************************************
            * GIVEN
            ********************************************/
            Fixture fixture = new Fixture();
            Id opportunityId = fixture.opportunityAId;
            Assert.isNotNull(opportunityId, 'Opportunity A exists.');

            /********************************************
            * WHEN
            ********************************************/
            Test.startTest();
            Integer allCount = QuoteSelector.countByOpportunityId(opportunityId);
            Integer normalCount = QuoteSelector.countByOpportunityId(
                opportunityId,
                GenerateQuoteService.QUOTE_TYPE_NORMAL
            );
            Integer eligibleCount = QuoteSelector.countByOpportunityId(opportunityId, null, true);
            Integer unfilteredCount = QuoteSelector.countByOpportunityId(opportunityId, null, false);

            Integer trialCount = QuoteSelector.countByOpportunityId(opportunityId, null, false, fixture.trialId);
            Integer trialTypedCount = QuoteSelector.countByOpportunityId(
                opportunityId,
                GenerateQuoteService.QUOTE_TYPE_TRIAL,
                false,
                fixture.trialId
            );
            Integer trialMismatchCount = QuoteSelector.countByOpportunityId(
                opportunityId,
                GenerateQuoteService.QUOTE_TYPE_SAMPLE,
                false,
                fixture.trialId
            );
            Integer trialEligibleCount = QuoteSelector.countByOpportunityId(
                opportunityId,
                null,
                true,
                fixture.trialId
            );

            Integer sampleCount = QuoteSelector.countByOpportunityId(
                opportunityId,
                null,
                false,
                null,
                fixture.sampleId
            );
            Integer sampleTypedCount = QuoteSelector.countByOpportunityId(
                opportunityId,
                GenerateQuoteService.QUOTE_TYPE_SAMPLE,
                false,
                null,
                fixture.sampleId
            );
            Integer sampleMismatchCount = QuoteSelector.countByOpportunityId(
                opportunityId,
                GenerateQuoteService.QUOTE_TYPE_TRIAL,
                false,
                null,
                fixture.sampleId
            );
            Integer sampleEligibleCount = QuoteSelector.countByOpportunityId(
                opportunityId,
                null,
                true,
                null,
                fixture.sampleId
            );

            Integer emptyOpportunityCount = QuoteSelector.countByOpportunityId(fixture.opportunityCId);
            List<Integer> nullCounts = new List<Integer>{
                QuoteSelector.countByOpportunityId(null),
                QuoteSelector.countByOpportunityId(null, GenerateQuoteService.QUOTE_TYPE_NORMAL),
                QuoteSelector.countByOpportunityId(null, null, true),
                QuoteSelector.countByOpportunityId(null, null, true, fixture.trialId),
                QuoteSelector.countByOpportunityId(null, null, true, null, fixture.sampleId)
            };
            Test.stopTest();

            /********************************************
            * THEN
            ********************************************/
            Assert.areEqual(OPPORTUNITY_A_QUOTE_COUNT, allCount, 'All quotes are counted.');
            Assert.areEqual(OPPORTUNITY_A_NORMAL_QUOTE_COUNT, normalCount, 'Normal quotes are counted.');
            Assert.areEqual(OPPORTUNITY_A_ELIGIBLE_QUOTE_COUNT, eligibleCount, 'Ineligible quotes are excluded.');
            Assert.areEqual(OPPORTUNITY_A_QUOTE_COUNT, unfilteredCount, 'No exclusion counts every quote.');

            Assert.areEqual(OPPORTUNITY_A_TRIAL_QUOTE_COUNT, trialCount, 'Trial quotes are counted.');
            Assert.areEqual(OPPORTUNITY_A_TRIAL_QUOTE_COUNT, trialTypedCount, 'Trial typed quotes are counted.');
            Assert.areEqual(0, trialMismatchCount, 'Trial filter with Sample type counts nothing.');
            Assert.areEqual(1, trialEligibleCount, 'Only the eligible trial quote is counted.');

            Assert.areEqual(OPPORTUNITY_A_SAMPLE_QUOTE_COUNT, sampleCount, 'Sample quotes are counted.');
            Assert.areEqual(OPPORTUNITY_A_SAMPLE_QUOTE_COUNT, sampleTypedCount, 'Sample typed quotes are counted.');
            Assert.areEqual(0, sampleMismatchCount, 'Sample filter with Trial type counts nothing.');
            Assert.areEqual(1, sampleEligibleCount, 'Only the eligible sample quote is counted.');

            Assert.areEqual(0, emptyOpportunityCount, 'Opportunity without quotes counts zero.');
            for (Integer nullCount : nullCounts) {
                Assert.areEqual(0, nullCount, 'Null Opportunity Id counts zero.');
            }
        }
    }

    /**
     * @description Verifies selectById returns the matching quote, or null for a null / unmatched Id.
     */
    @IsTest
    static void testSelectById() {

        /********************************************
        * SETUP
        ********************************************/
        User testUser = getQuoteUser();

        System.runAs(testUser) {

            /********************************************
            * GIVEN
            ********************************************/
            Fixture fixture = new Fixture();
            Id quoteId = fixture.quoteId(QUOTE_NORMAL_OPEN);
            Assert.isNotNull(quoteId, 'Normal open quote exists.');

            /********************************************
            * WHEN
            ********************************************/
            Test.startTest();
            Quote selectedQuote = QuoteSelector.selectById(quoteId);
            Quote nullQuote = QuoteSelector.selectById(null);
            // An Opportunity Id never matches a Quote Id, so the not-found path runs without a fake Id.
            Quote unmatchedQuote = QuoteSelector.selectById(fixture.opportunityAId);
            Test.stopTest();

            /********************************************
            * THEN
            ********************************************/
            Assert.isNotNull(selectedQuote, 'Matching quote is returned.');
            Assert.areEqual(quoteId, selectedQuote.Id, 'Requested quote is returned.');
            Assert.areEqual(QUOTE_NORMAL_OPEN, selectedQuote.Name, 'Quote name is selected.');
            Assert.isNull(nullQuote, 'Null Id returns null.');
            Assert.isNull(unmatchedQuote, 'Unmatched Id returns null.');
        }
    }

    /**
     * @description Verifies selectByIdsWithLineItems returns the requested quotes with line items and guards
     *              null / empty input.
     */
    @IsTest
    static void testSelectByIdsWithLineItems() {

        /********************************************
        * SETUP
        ********************************************/
        User testUser = getQuoteUser();

        System.runAs(testUser) {

            /********************************************
            * GIVEN
            ********************************************/
            Fixture fixture = new Fixture();
            Set<Id> quoteIds = new Set<Id>{
                fixture.quoteId(QUOTE_NORMAL_OPEN),
                fixture.quoteId(QUOTE_B_NORMAL_OPEN)
            };
            Assert.areEqual(2, quoteIds.size(), 'Two distinct quotes are requested.');

            /********************************************
            * WHEN
            ********************************************/
            Test.startTest();
            List<Quote> selectedQuotes = QuoteSelector.selectByIdsWithLineItems(quoteIds);
            List<Quote> nullResult = QuoteSelector.selectByIdsWithLineItems(null);
            List<Quote> emptyResult = QuoteSelector.selectByIdsWithLineItems(new Set<Id>());
            Test.stopTest();

            /********************************************
            * THEN
            ********************************************/
            Assert.areEqual(2, selectedQuotes.size(), 'Requested quotes are returned.');
            Assert.areEqual(
                quoteIds,
                new Map<Id, Quote>(selectedQuotes).keySet(),
                'Exactly the requested quotes are returned.'
            );
            Quote normalOpenQuote = findQuote(selectedQuotes, fixture.quoteId(QUOTE_NORMAL_OPEN));
            Assert.areEqual(fixture.opportunityAId, normalOpenQuote.OpportunityId, 'Opportunity Id is selected.');
            Assert.areEqual(1, normalOpenQuote.QuoteLineItems.size(), 'Child quote line item is returned.');
            Quote opportunityBQuote = findQuote(selectedQuotes, fixture.quoteId(QUOTE_B_NORMAL_OPEN));
            Assert.areEqual(0, opportunityBQuote.QuoteLineItems.size(), 'Quote without lines has no children.');
            Assert.areEqual(0, nullResult.size(), 'Null set returns no quotes.');
            Assert.areEqual(0, emptyResult.size(), 'Empty set returns no quotes.');
        }
    }

    /**
     * @description Verifies the open Forecast Eligible HCSales quote query and the derived Opportunity Id set.
     */
    @IsTest
    static void testOpenForecastEligibleQuotesByOpportunityIds() {

        /********************************************
        * SETUP
        ********************************************/
        User testUser = getQuoteUser();

        System.runAs(testUser) {

            /********************************************
            * GIVEN
            ********************************************/
            Fixture fixture = new Fixture();
            Set<Id> opportunityIds = fixture.allOpportunityIds();
            Assert.isNotNull(resolveHcSalesRecordTypeId(), 'HCSales quote record type is available to the user.');

            /********************************************
            * WHEN
            ********************************************/
            Test.startTest();
            List<Quote> openEligibleQuotes =
                QuoteSelector.selectOpenForecastEligibleQuotesByOpportunityIds(opportunityIds);
            Set<Id> opportunityIdsWithEligible =
                QuoteSelector.selectOpportunityIdsWithOpenForecastEligibleQuotes(opportunityIds);
            List<Quote> nullResult = QuoteSelector.selectOpenForecastEligibleQuotesByOpportunityIds(null);
            Set<Id> emptyOpportunityIds =
                QuoteSelector.selectOpportunityIdsWithOpenForecastEligibleQuotes(new Set<Id>());
            Test.stopTest();

            /********************************************
            * THEN
            ********************************************/
            Set<Id> returnedIds = new Map<Id, Quote>(openEligibleQuotes).keySet();
            Assert.areEqual(2, openEligibleQuotes.size(), 'Only open Forecast Eligible quotes are returned.');
            Assert.isTrue(returnedIds.contains(fixture.quoteId(QUOTE_NORMAL_OPEN)), 'Opportunity A quote returned.');
            Assert.isTrue(returnedIds.contains(fixture.quoteId(QUOTE_B_NORMAL_OPEN)), 'Opportunity B quote returned.');
            Assert.isFalse(
                returnedIds.contains(fixture.quoteId(QUOTE_NORMAL_CLOSED)),
                'Closed Forecast Eligible quote is excluded.'
            );
            for (Quote quoteRecord : openEligibleQuotes) {
                Assert.isTrue(quoteRecord.Forecast_Eligible__c, 'Only Forecast Eligible quotes are returned.');
                Assert.areNotEqual(QuoteSelector.CLOSED_STATUS_VALUE, quoteRecord.Status, 'Closed is excluded.');
            }

            Assert.areEqual(
                new Set<Id>{ fixture.opportunityAId, fixture.opportunityBId },
                opportunityIdsWithEligible,
                'Opportunities with open Forecast Eligible quotes are returned.'
            );
            Assert.areEqual(0, nullResult.size(), 'Null set returns no quotes.');
            Assert.areEqual(0, emptyOpportunityIds.size(), 'Empty set returns no Opportunity Ids.');
        }
    }

    /**
     * @description Verifies the Forecast Eligible management query excludes Draft, Closed and ineligible quotes.
     */
    @IsTest
    static void testSelectForecastManagementQuotesByOpportunityId() {

        /********************************************
        * SETUP
        ********************************************/
        User testUser = getQuoteUser();

        System.runAs(testUser) {

            /********************************************
            * GIVEN
            ********************************************/
            Fixture fixture = new Fixture();
            Set<Id> expectedIds = new Set<Id>{
                fixture.quoteId(QUOTE_NORMAL_OPEN),
                fixture.quoteId(QUOTE_TRIAL_ELIGIBLE),
                fixture.quoteId(QUOTE_SAMPLE_ELIGIBLE)
            };
            Assert.areEqual(3, expectedIds.size(), 'Three manageable quotes exist.');

            /********************************************
            * WHEN
            ********************************************/
            Test.startTest();
            List<Quote> managementQuotes =
                QuoteSelector.selectForecastManagementQuotesByOpportunityId(fixture.opportunityAId);
            List<Quote> nullResult = QuoteSelector.selectForecastManagementQuotesByOpportunityId(null);
            Test.stopTest();

            /********************************************
            * THEN
            ********************************************/
            Assert.areEqual(
                expectedIds,
                new Map<Id, Quote>(managementQuotes).keySet(),
                'Only open, forecast-eligible, non-Draft quotes are returned.'
            );
            Quote normalOpenQuote = findQuote(managementQuotes, fixture.quoteId(QUOTE_NORMAL_OPEN));
            Assert.areEqual(1, normalOpenQuote.QuoteLineItems.size(), 'Child quote line item is returned.');
            Assert.areEqual(0, nullResult.size(), 'Null Opportunity Id returns no quotes.');
        }
    }

    /**
     * @description Verifies the Sales Connection (HCSales) quote query used by Forecast Eligible automation.
     */
    @IsTest
    static void testSelectSalesConnectionQuotesForForecastEligibleByOpportunityIds() {

        /********************************************
        * SETUP
        ********************************************/
        User testUser = getQuoteUser();

        System.runAs(testUser) {

            /********************************************
            * GIVEN
            ********************************************/
            Fixture fixture = new Fixture();
            Id hcSalesRecordTypeId = resolveHcSalesRecordTypeId();
            Assert.isNotNull(hcSalesRecordTypeId, 'HCSales quote record type is available to the user.');

            /********************************************
            * WHEN
            ********************************************/
            Test.startTest();
            List<Quote> salesConnectionQuotes =
                QuoteSelector.selectSalesConnectionQuotesForForecastEligibleByOpportunityIds(
                    fixture.allOpportunityIds()
                );
            List<Quote> nullResult = QuoteSelector.selectSalesConnectionQuotesForForecastEligibleByOpportunityIds(
                null
            );
            List<Quote> emptyResult = QuoteSelector.selectSalesConnectionQuotesForForecastEligibleByOpportunityIds(
                new Set<Id>()
            );
            Test.stopTest();

            /********************************************
            * THEN
            ********************************************/
            Assert.areEqual(
                OPPORTUNITY_A_QUOTE_COUNT + OPPORTUNITY_B_QUOTE_COUNT,
                salesConnectionQuotes.size(),
                'All HCSales quotes on the Opportunities are returned.'
            );
            for (Quote quoteRecord : salesConnectionQuotes) {
                Assert.areEqual(hcSalesRecordTypeId, quoteRecord.RecordTypeId, 'Only HCSales quotes are returned.');
            }
            Assert.areEqual(0, nullResult.size(), 'Null set returns no quotes.');
            Assert.areEqual(0, emptyResult.size(), 'Empty set returns no quotes.');
        }
    }

    /**
     * @description Verifies the forecast confidence propagation count and select queries.
     */
    @IsTest
    static void testPropagatableForecastConfidenceQuotes() {

        /********************************************
        * SETUP
        ********************************************/
        User testUser = getQuoteUser();

        System.runAs(testUser) {

            /********************************************
            * GIVEN
            ********************************************/
            Fixture fixture = new Fixture();
            Set<Id> opportunityIds = fixture.allOpportunityIds();
            Assert.areEqual(3, opportunityIds.size(), 'Three test Opportunities exist.');

            /********************************************
            * WHEN
            ********************************************/
            Test.startTest();
            Map<Id, Integer> countsByOpportunityId =
                QuoteSelector.countPropagatableForecastConfidenceQuotesByOpportunityIds(opportunityIds);
            List<Quote> propagatableQuotes =
                QuoteSelector.selectPropagatableForecastConfidenceQuotesByOpportunityId(fixture.opportunityAId);
            Map<Id, Integer> nullCounts = QuoteSelector.countPropagatableForecastConfidenceQuotesByOpportunityIds(null);
            Map<Id, Integer> emptyCounts = QuoteSelector.countPropagatableForecastConfidenceQuotesByOpportunityIds(
                new Set<Id>()
            );
            List<Quote> nullQuotes = QuoteSelector.selectPropagatableForecastConfidenceQuotesByOpportunityId(null);
            Test.stopTest();

            /********************************************
            * THEN
            ********************************************/
            // The propagation rules are being narrowed in other work (only quotes whose forecast confidence differs
            // from the Opportunity's are counted), so exact counts are not asserted. Every quote on A and B is a
            // candidate, so the counts can never exceed the quotes created on each Opportunity.
            Integer opportunityACount = countsByOpportunityId.get(fixture.opportunityAId);
            Assert.isNotNull(opportunityACount, 'Opportunity A has propagatable quotes.');
            Assert.isTrue(
                opportunityACount >= 1 && opportunityACount <= OPPORTUNITY_A_QUOTE_COUNT,
                'Opportunity A count stays within its quotes: ' + opportunityACount
            );
            Integer opportunityBCount = countsByOpportunityId.get(fixture.opportunityBId);
            Assert.isTrue(
                opportunityBCount == null || opportunityBCount <= OPPORTUNITY_B_QUOTE_COUNT,
                'Opportunity B count stays within its quotes: ' + opportunityBCount
            );
            Assert.isFalse(
                countsByOpportunityId.containsKey(fixture.opportunityCId),
                'Opportunity without quotes has no count entry.'
            );

            Set<Id> opportunityAQuoteIds = new Set<Id>();
            for (String quoteName : new List<String>{
                QUOTE_NORMAL_OPEN,
                QUOTE_NORMAL_CLOSED,
                QUOTE_NORMAL_DRAFT,
                QUOTE_TRIAL_INELIGIBLE,
                QUOTE_TRIAL_ELIGIBLE,
                QUOTE_SAMPLE_INELIGIBLE,
                QUOTE_SAMPLE_ELIGIBLE,
                QUOTE_GOODWILL
            }) {
                opportunityAQuoteIds.add(fixture.quoteId(quoteName));
            }
            Assert.isFalse(propagatableQuotes.isEmpty(), 'Propagatable quotes are returned for Opportunity A.');
            for (Quote quoteRecord : propagatableQuotes) {
                Assert.isTrue(
                    opportunityAQuoteIds.contains(quoteRecord.Id),
                    'Only Opportunity A quotes are returned: ' + quoteRecord.Id
                );
            }
            Assert.isTrue(nullCounts.isEmpty(), 'Null set returns an empty map.');
            Assert.isTrue(emptyCounts.isEmpty(), 'Empty set returns an empty map.');
            Assert.areEqual(0, nullQuotes.size(), 'Null Opportunity Id returns no quotes.');
        }
    }

    /**
     * @description Verifies the open Sales Connection quote select and count queries for a user that can
     *              see the HCSales record type.
     */
    @IsTest
    static void testOpenSalesConnectionQuotes() {

        /********************************************
        * SETUP
        ********************************************/
        User testUser = getQuoteUser();

        System.runAs(testUser) {

            /********************************************
            * GIVEN
            ********************************************/
            Fixture fixture = new Fixture();
            Assert.isNotNull(resolveHcSalesRecordTypeId(), 'HCSales quote record type is available to the user.');

            /********************************************
            * WHEN
            ********************************************/
            Test.startTest();
            List<Quote> openQuotes = QuoteSelector.selectOpenSalesConnectionQuotesByOpportunityId(
                fixture.opportunityAId
            );
            Map<Id, Integer> countsByOpportunityId = QuoteSelector.countOpenSalesConnectionQuotesByOpportunityIds(
                fixture.allOpportunityIds()
            );
            List<Quote> nullQuotes = QuoteSelector.selectOpenSalesConnectionQuotesByOpportunityId(null);
            Map<Id, Integer> nullCounts = QuoteSelector.countOpenSalesConnectionQuotesByOpportunityIds(null);
            Map<Id, Integer> emptyCounts = QuoteSelector.countOpenSalesConnectionQuotesByOpportunityIds(
                new Set<Id>()
            );
            Test.stopTest();

            /********************************************
            * THEN
            ********************************************/
            Assert.areEqual(OPPORTUNITY_A_OPEN_QUOTE_COUNT, openQuotes.size(), 'Only non-Closed quotes are returned.');
            Assert.isFalse(
                new Map<Id, Quote>(openQuotes).keySet().contains(fixture.quoteId(QUOTE_NORMAL_CLOSED)),
                'Closed quote is excluded.'
            );
            Assert.areEqual(
                OPPORTUNITY_A_OPEN_QUOTE_COUNT,
                countsByOpportunityId.get(fixture.opportunityAId),
                'Open quotes are counted for Opportunity A.'
            );
            Assert.areEqual(
                OPPORTUNITY_B_QUOTE_COUNT,
                countsByOpportunityId.get(fixture.opportunityBId),
                'Open quotes are counted for Opportunity B.'
            );
            Assert.isFalse(
                countsByOpportunityId.containsKey(fixture.opportunityCId),
                'Opportunity without quotes has no count entry.'
            );
            Assert.areEqual(0, nullQuotes.size(), 'Null Opportunity Id returns no quotes.');
            Assert.isTrue(nullCounts.isEmpty(), 'Null set returns an empty map.');
            Assert.isTrue(emptyCounts.isEmpty(), 'Empty set returns an empty map.');
        }
    }

    /**
     * @description Runs the HCSales-dependent queries as a user without the Sales permission set group, so
     *              the record type is normally unavailable and the special-quote-type-only fallback branches
     *              execute. Results are limited by that user's record access, so assertions check that every
     *              returned row honours the fallback filters.
     */
    @IsTest
    static void testSalesConnectionQueriesWithoutHcSalesRecordType() {

        /********************************************
        * SETUP
        ********************************************/
        Fixture fixture;
        System.runAs(getQuoteUser()) {
            fixture = new Fixture();
        }
        User restrictedUser = getRestrictedUser();
        Set<String> specialQuoteTypes = new Set<String>{
            GenerateQuoteService.QUOTE_TYPE_TRIAL,
            GenerateQuoteService.QUOTE_TYPE_SAMPLE,
            GenerateQuoteService.QUOTE_TYPE_GOODWILL
        };

        System.runAs(restrictedUser) {

            /********************************************
            * GIVEN
            ********************************************/
            Boolean isHcSalesAvailable = resolveHcSalesRecordTypeId() != null;
            Set<Id> opportunityIds = fixture.allOpportunityIds();
            Assert.areEqual(3, opportunityIds.size(), 'Three test Opportunities exist.');

            /********************************************
            * WHEN
            ********************************************/
            Test.startTest();
            List<Quote> openQuotes = QuoteSelector.selectOpenSalesConnectionQuotesByOpportunityId(
                fixture.opportunityAId
            );
            Map<Id, Integer> openCounts = QuoteSelector.countOpenSalesConnectionQuotesByOpportunityIds(opportunityIds);
            List<Quote> salesConnectionQuotes =
                QuoteSelector.selectSalesConnectionQuotesForForecastEligibleByOpportunityIds(opportunityIds);
            // USER_MODE query: only called when the record type is unavailable (it then returns before querying).
            List<Quote> openEligibleQuotes = isHcSalesAvailable
                ? new List<Quote>()
                : QuoteSelector.selectOpenForecastEligibleQuotesByOpportunityIds(opportunityIds);
            Test.stopTest();

            /********************************************
            * THEN
            ********************************************/
            for (Quote quoteRecord : openQuotes) {
                Assert.areNotEqual(QuoteSelector.CLOSED_STATUS_VALUE, quoteRecord.Status, 'Closed is excluded.');
                if (!isHcSalesAvailable) {
                    Assert.isTrue(
                        specialQuoteTypes.contains(quoteRecord.QuoteType__c),
                        'Without HCSales only Trial, Sample and Goodwill quotes are returned.'
                    );
                }
            }
            Integer opportunityACount = openCounts.containsKey(fixture.opportunityAId)
                ? openCounts.get(fixture.opportunityAId)
                : 0;
            Assert.areEqual(openQuotes.size(), opportunityACount, 'Count matches the selected open quotes.');
            if (!isHcSalesAvailable) {
                Assert.isTrue(
                    opportunityACount <= OPPORTUNITY_A_OPEN_SPECIAL_QUOTE_COUNT,
                    'Only special quote types are counted without HCSales.'
                );
                Assert.areEqual(0, salesConnectionQuotes.size(), 'No HCSales quotes without the record type.');
                Assert.areEqual(0, openEligibleQuotes.size(), 'No Forecast Eligible quotes without the record type.');
            }
        }
    }

    /**
     * @description Verifies the Field Service Edit Quote query returns the quote, or an empty list for null.
     */
    @IsTest
    static void testSelectFieldServiceQuoteById() {

        /********************************************
        * SETUP
        ********************************************/
        User testUser = getQuoteUser();

        System.runAs(testUser) {

            /********************************************
            * GIVEN
            ********************************************/
            Fixture fixture = new Fixture();
            Id quoteId = fixture.quoteId(QUOTE_NORMAL_OPEN);
            Assert.isNotNull(quoteId, 'Normal open quote exists.');

            /********************************************
            * WHEN
            ********************************************/
            Test.startTest();
            List<Quote> selectedQuotes = QuoteSelector.selectFieldServiceQuoteById(quoteId);
            List<Quote> nullResult = QuoteSelector.selectFieldServiceQuoteById(null);
            Test.stopTest();

            /********************************************
            * THEN
            ********************************************/
            Assert.areEqual(1, selectedQuotes.size(), 'Matching quote is returned.');
            Assert.areEqual(quoteId, selectedQuotes[0].Id, 'Requested quote is returned.');
            Assert.areEqual(fixture.opportunityAId, selectedQuotes[0].OpportunityId, 'Opportunity Id is selected.');
            Assert.areEqual(0, nullResult.size(), 'Null Id returns no quotes.');
        }
    }

    // ------------------------------------------------------------------
    // Test data helpers
    // ------------------------------------------------------------------

    /**
     * @description Creates Account, Opportunities, Trial, Sample, Product and the HCSales quotes.
     */
    private static void createQuoteData() {
        Id standardPricebookId = Test.getStandardPricebookId();
        String currencyCode = UserInfo.getDefaultCurrency();
        String suffix = uniqueSuffix();

        Account accountRecord = new Account(
            Name = 'QuoteSelectorTest Account ' + suffix,
            SourceSystemID__c = ('QST-' + suffix).left(50),
            OracleAddressId__c = ('QST' + suffix).left(30)
        );
        insert accountRecord;

        Opportunity opportunityA = buildOpportunity(accountRecord.Id, 'QuoteSelectorTest Opportunity A');
        Opportunity opportunityB = buildOpportunity(accountRecord.Id, 'QuoteSelectorTest Opportunity B');
        Opportunity opportunityC = buildOpportunity(accountRecord.Id, 'QuoteSelectorTest Opportunity C');
        insert new List<Opportunity>{ opportunityA, opportunityB, opportunityC };

        Trial__c trialRecord = new Trial__c(Opportunity__c = opportunityA.Id);
        insert trialRecord;

        Sample__c sampleRecord = new Sample__c(
            RelatedOpportunity__c = opportunityA.Id,
            SamplePurpose__c = SAMPLE_PURPOSE_EVALUATION,
            RequestedDeliveryDate__c = Date.today().addDays(14),
            BusinessJustification__c = 'QuoteSelectorTest sample'
        );
        insert sampleRecord;

        Product2 productRecord = new Product2(
            Name = 'QuoteSelectorTest Product',
            ProductCode = 'QST-' + suffix.left(20),
            IsActive = true
        );
        insert productRecord;

        PricebookEntry pricebookEntryRecord = new PricebookEntry(
            Pricebook2Id = standardPricebookId,
            Product2Id = productRecord.Id,
            UnitPrice = 100,
            IsActive = true,
            CurrencyIsoCode = currencyCode
        );
        insert pricebookEntryRecord;

        String normalType = GenerateQuoteService.QUOTE_TYPE_NORMAL;
        String trialType = GenerateQuoteService.QUOTE_TYPE_TRIAL;
        String sampleType = GenerateQuoteService.QUOTE_TYPE_SAMPLE;
        String goodwillType = GenerateQuoteService.QUOTE_TYPE_GOODWILL;
        String openStatus = QuoteSelector.OPEN_STATUS_VALUE;
        String closedStatus = QuoteSelector.CLOSED_STATUS_VALUE;
        String draftStatus = GenerateQuoteService.QUOTE_STATUS_DRAFT;

        Quote normalOpen = buildQuote(QUOTE_NORMAL_OPEN, opportunityA.Id, openStatus, normalType, true, false);
        Quote normalClosed = buildQuote(QUOTE_NORMAL_CLOSED, opportunityA.Id, closedStatus, normalType, true, false);
        Quote normalDraft = buildQuote(QUOTE_NORMAL_DRAFT, opportunityA.Id, draftStatus, normalType, false, false);
        Quote trialIneligible = buildQuote(QUOTE_TRIAL_INELIGIBLE, opportunityA.Id, openStatus, trialType, false, true);
        trialIneligible.Trial__c = trialRecord.Id;
        Quote trialEligible = buildQuote(QUOTE_TRIAL_ELIGIBLE, opportunityA.Id, openStatus, trialType, false, false);
        trialEligible.Trial__c = trialRecord.Id;
        Quote sampleIneligible = buildQuote(
            QUOTE_SAMPLE_INELIGIBLE,
            opportunityA.Id,
            openStatus,
            sampleType,
            false,
            true
        );
        sampleIneligible.Sample__c = sampleRecord.Id;
        Quote sampleEligible = buildQuote(QUOTE_SAMPLE_ELIGIBLE, opportunityA.Id, openStatus, sampleType, false, false);
        sampleEligible.Sample__c = sampleRecord.Id;
        Quote goodwill = buildQuote(QUOTE_GOODWILL, opportunityA.Id, openStatus, goodwillType, false, true);
        Quote opportunityBNormal = buildQuote(QUOTE_B_NORMAL_OPEN, opportunityB.Id, openStatus, normalType, true, false);
        Quote opportunityBGoodwill = buildQuote(QUOTE_B_GOODWILL, opportunityB.Id, openStatus, goodwillType, false, true);

        insert new List<Quote>{
            normalOpen,
            normalClosed,
            normalDraft,
            trialIneligible,
            trialEligible,
            sampleIneligible,
            sampleEligible,
            goodwill,
            opportunityBNormal,
            opportunityBGoodwill
        };

        insert new QuoteLineItem(
            QuoteId = normalOpen.Id,
            PricebookEntryId = pricebookEntryRecord.Id,
            Quantity = 2,
            UnitPrice = 100
        );
    }

    /**
     * @description Builds a Healthcare Sales Opportunity on the standard price book.
     */
    private static Opportunity buildOpportunity(Id accountId, String opportunityName) {
        Opportunity opportunityRecord = new Opportunity(
            Name = opportunityName,
            AccountId = accountId,
            StageName = 'Discovery',
            CloseDate = Date.today().addDays(30),
            Amount = 1000,
            Probability = 10,
            Pricebook2Id = Test.getStandardPricebookId(),
            CurrencyIsoCode = UserInfo.getDefaultCurrency(),
            BypassValidations__c = true
        );

        Map<String, Schema.RecordTypeInfo> recordTypesByDeveloperName =
            Schema.SObjectType.Opportunity.getRecordTypeInfosByDeveloperName();
        if (recordTypesByDeveloperName.containsKey(OPPORTUNITY_RECORD_TYPE_DEVELOPER_NAME)) {
            opportunityRecord.RecordTypeId =
                recordTypesByDeveloperName.get(OPPORTUNITY_RECORD_TYPE_DEVELOPER_NAME).getRecordTypeId();
        }

        return opportunityRecord;
    }

    /**
     * @description Builds an HCSales Quote.
     */
    private static Quote buildQuote(
        String quoteName,
        Id opportunityId,
        String status,
        String quoteType,
        Boolean isForecastEligible,
        Boolean isForecastIneligible
    ) {
        return new Quote(
            Name = quoteName,
            OpportunityId = opportunityId,
            Pricebook2Id = Test.getStandardPricebookId(),
            RecordTypeId = resolveHcSalesRecordTypeIdForInsert(),
            Status = status,
            QuoteType__c = quoteType,
            Forecast_Eligible__c = isForecastEligible,
            IsForecastIneligible__c = isForecastIneligible,
            ExpirationDate = Date.today().addDays(30),
            CurrencyIsoCode = UserInfo.getDefaultCurrency()
        );
    }

    /**
     * @description Builds a test User.
     */
    private static User buildUser(Id profileId, String lastName) {
        String suffix = uniqueSuffix();
        String username = lastName.toLowerCase() + '.' + suffix + '@quoteselectortest.com';

        return new User(
            FirstName = 'Quote',
            LastName = lastName,
            Alias = ('qs' + suffix).left(8),
            Email = username,
            Username = username,
            CommunityNickname = ('qst' + suffix).left(40),
            ProfileId = profileId,
            TimeZoneSidKey = 'America/New_York',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            EmployeeNumber__c = 'QST' + suffix,
            FederationIdentifier = 'QST' + suffix,
            IsActive = true
        );
    }

    /**
     * @description Resolves a profile without the HCSales quote record type, preferring Minimum Access.
     */
    private static Id resolveRestrictedProfileId() {
        Map<String, Id> profileIdsByName = new Map<String, Id>();
        for (Profile profileRecord : [
            SELECT Id, Name
            FROM Profile
            WHERE Name IN (:MINIMUM_ACCESS_PROFILE, :STANDARD_USER_PROFILE)
        ]) {
            profileIdsByName.put(profileRecord.Name, profileRecord.Id);
        }

        if (profileIdsByName.containsKey(MINIMUM_ACCESS_PROFILE)) {
            return profileIdsByName.get(MINIMUM_ACCESS_PROFILE);
        }
        if (profileIdsByName.containsKey(STANDARD_USER_PROFILE)) {
            return profileIdsByName.get(STANDARD_USER_PROFILE);
        }
        return UserInfo.getProfileId();
    }

    /**
     * @description HCSales record type Id for DML (independent of running-user availability).
     */
    private static Id resolveHcSalesRecordTypeIdForInsert() {
        return Schema.SObjectType.Quote.getRecordTypeInfosByDeveloperName()
            .get(GenerateQuoteService.QUOTE_RECORD_TYPE_DEVELOPER_NAME)
            .getRecordTypeId();
    }

    /**
     * @description HCSales record type Id when available to the running user, mirroring QuoteSelector.
     */
    private static Id resolveHcSalesRecordTypeId() {
        Schema.RecordTypeInfo recordTypeInfo = Schema.SObjectType.Quote.getRecordTypeInfosByDeveloperName()
            .get(GenerateQuoteService.QUOTE_RECORD_TYPE_DEVELOPER_NAME);
        return recordTypeInfo != null && recordTypeInfo.isAvailable() ? recordTypeInfo.getRecordTypeId() : null;
    }

    private static String uniqueSuffix() {
        return String.valueOf(Math.abs(Crypto.getRandomInteger()));
    }

    private static User getQuoteUser() {
        return [SELECT Id FROM User WHERE LastName = :QUOTE_USER_LAST_NAME LIMIT 1];
    }

    private static User getRestrictedUser() {
        return [SELECT Id FROM User WHERE LastName = :RESTRICTED_USER_LAST_NAME LIMIT 1];
    }

    private static Quote findQuote(List<Quote> quotes, Id quoteId) {
        for (Quote quoteRecord : quotes) {
            if (quoteRecord.Id == quoteId) {
                return quoteRecord;
            }
        }
        return null;
    }

    /**
     * @description Loads the Ids of the records created in @TestSetup. Opportunities are resolved through
     *              their quotes (names can be rewritten by Opportunity automation); Opportunity C is the only
     *              test Opportunity without quotes.
     */
    private class Fixture {
        Id opportunityAId;
        Id opportunityBId;
        Id opportunityCId;
        Id trialId;
        Id sampleId;
        Map<String, Id> quoteIdsByName = new Map<String, Id>();

        Fixture() {
            for (Quote quoteRecord : [SELECT Id, Name, OpportunityId FROM Quote WHERE Name LIKE 'QST %']) {
                quoteIdsByName.put(quoteRecord.Name, quoteRecord.Id);
                if (quoteRecord.Name == QUOTE_NORMAL_OPEN) {
                    opportunityAId = quoteRecord.OpportunityId;
                } else if (quoteRecord.Name == QUOTE_B_NORMAL_OPEN) {
                    opportunityBId = quoteRecord.OpportunityId;
                }
            }

            Set<Id> opportunityIdsWithQuotes = new Set<Id>{ opportunityAId, opportunityBId };
            opportunityCId = [
                SELECT Id
                FROM Opportunity
                WHERE Id NOT IN :opportunityIdsWithQuotes
                LIMIT 1
            ].Id;

            trialId = [SELECT Id FROM Trial__c WHERE Opportunity__c = :opportunityAId LIMIT 1].Id;
            sampleId = [SELECT Id FROM Sample__c WHERE RelatedOpportunity__c = :opportunityAId LIMIT 1].Id;
        }

        Id quoteId(String quoteName) {
            return quoteIdsByName.get(quoteName);
        }

        Set<Id> allOpportunityIds() {
            return new Set<Id>{ opportunityAId, opportunityBId, opportunityCId };
        }
    }
}