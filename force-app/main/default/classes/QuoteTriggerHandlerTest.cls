/**
 * @author Himanshu Chaurasia
 * @date 2026/07/28
 *
 * @group Forecast Eligible Quotes
 *
 * @description Test class for QuoteTriggerHandler and QuoteService. GC-3185
 *              Scope: HCSales Quote record type only (other Quote RTs are out of scope).
 */
@IsTest
private class QuoteTriggerHandlerTest {
    private static final String TEST_OPPORTUNITY_NAME = 'Quote Forecast Eligible Trigger Test Opportunity';
    private static final String QUOTE_AUTOMATION_RUN_AS_LAST_NAME = 'QuoteForecastEligibleRunAs';
    private static final String SALES_FIELD_REP_PSG_DEVELOPER_NAME = 'SalesFieldRepAccountManagerPSG';
    private static final String HEALTHCARE_SALES_OPPORTUNITY_RECORD_TYPE = 'Healthcare_Sales';

    @TestSetup
    static void setupData() {
        Id standardPricebookId = Test.getStandardPricebookId();

        Account accountRecord = new Account(
            Name = 'Quote Forecast Eligible Test Account',
            SourceSystemID__c = 'QFE-TEST-ACCT',
            OracleAddressId__c = '638265'
        );
        insert accountRecord;

        Contact contactRecord = new Contact(
            FirstName = 'Quote',
            LastName = 'Forecast Eligible',
            AccountId = accountRecord.Id
        );
        insert contactRecord;

        Opportunity opportunityRecord = buildOpportunity(
            TEST_OPPORTUNITY_NAME,
            accountRecord.Id,
            contactRecord.Id,
            standardPricebookId
        );
        insert opportunityRecord;

        User setupUser = new User(Id = UserInfo.getUserId());
        System.runAs(setupUser) {
            User automationUser = createQuoteAutomationRunAsUser();
            insert automationUser;
            assignSalesFieldRepAccountManagerPsg(automationUser.Id);
        }
    }

    @IsTest
    static void testFirstEligibleQuoteIsDesignatedForecastEligible() {
        Opportunity opportunityRecord = getTestOpportunity();

        Test.startTest();
        Quote insertedQuote = insertQuote(
            opportunityRecord,
            'First Open Quote',
            'Open',
            Datetime.now().addDays(-5)
        );
        Test.stopTest();

        Quote resultQuote = [
            SELECT Forecast_Eligible__c
            FROM Quote
            WHERE Id = :insertedQuote.Id
            LIMIT 1
        ];

        System.assertEquals(true, resultQuote.Forecast_Eligible__c, 'AC1: first eligible quote should be designated.');
    }

    @IsTest
    static void testForecastEligibleAutomationUsesHcSalesRecordType() {
        Opportunity opportunityRecord = getTestOpportunity();

        Test.startTest();
        Quote insertedQuote = insertQuote(
            opportunityRecord,
            'HCSales Record Type Quote',
            'Open',
            Datetime.now().addDays(-3)
        );
        Test.stopTest();

        Quote resultQuote = [
            SELECT RecordType.DeveloperName, Forecast_Eligible__c
            FROM Quote
            WHERE Id = :insertedQuote.Id
            LIMIT 1
        ];

        System.assertEquals(
            GenerateQuoteService.QUOTE_RECORD_TYPE_DEVELOPER_NAME,
            resultQuote.RecordType.DeveloperName,
            'Forecast eligible automation tests must use the HCSales Quote record type.'
        );
        System.assertEquals(true, resultQuote.Forecast_Eligible__c);
    }

    @IsTest
    static void testOnlyOpenStatusIsDesignatedForecastEligible() {
        Opportunity opportunityRecord = getTestOpportunity();

        Test.startTest();
        insertQuoteRecords(
            new List<Quote>{
                buildQuote(opportunityRecord, 'Draft Quote', 'Draft', null),
                buildQuote(opportunityRecord, 'Budget Quote', 'Budget', null),
                buildQuote(opportunityRecord, 'Closed Quote', 'Closed', null)
            }
        );
        Test.stopTest();

        Integer forecastEligibleCount = [
            SELECT COUNT()
            FROM Quote
            WHERE OpportunityId = :opportunityRecord.Id
              AND Forecast_Eligible__c = true
        ];

        System.assertEquals(0, forecastEligibleCount, 'Only Open HCSales quotes should be designated.');
    }

    @IsTest
    static void testForecastIneligibleQuoteIsExcludedFromAutoDesignation() {
        Opportunity opportunityRecord = getTestOpportunity();

        Test.startTest();
        Quote ineligibleQuote = insertQuote(
            opportunityRecord,
            'Forecast Ineligible Open Quote',
            'Open',
            Datetime.now().addDays(-10),
            true
        );
        Test.stopTest();

        Quote resultQuote = [
            SELECT Forecast_Eligible__c, IsForecastIneligible__c
            FROM Quote
            WHERE Id = :ineligibleQuote.Id
            LIMIT 1
        ];

        System.assertEquals(true, resultQuote.IsForecastIneligible__c);
        System.assertEquals(
            false,
            resultQuote.Forecast_Eligible__c,
            'Forecast-ineligible quotes should not be auto designated.'
        );
    }

    @IsTest
    static void testAutoDesignationSkipsIneligibleQuoteAndDesignatesNextEligibleQuote() {
        Opportunity opportunityRecord = getTestOpportunity();

        insertQuote(
            opportunityRecord,
            'Ineligible Open Quote',
            'Open',
            Datetime.now().addDays(-10),
            true
        );

        Test.startTest();
        Quote eligibleQuote = insertQuote(
            opportunityRecord,
            'Eligible Open Quote',
            'Open',
            Datetime.now().addDays(-1)
        );
        Test.stopTest();

        Quote eligibleQuoteResult = [
            SELECT Forecast_Eligible__c
            FROM Quote
            WHERE Id = :eligibleQuote.Id
            LIMIT 1
        ];

        System.assertEquals(
            true,
            eligibleQuoteResult.Forecast_Eligible__c,
            'Eligible Open quote should be designated when earlier quote is forecast ineligible.'
        );
    }

    @IsTest
    static void testMarkingQuoteForecastIneligibleClearsForecastEligibleAndRedesignates() {
        Opportunity opportunityRecord = getTestOpportunity();

        Quote oldestOpenQuote = insertQuote(
            opportunityRecord,
            'Oldest Open Quote',
            'Open',
            Datetime.now().addDays(-10)
        );
        Quote newerOpenQuote = insertQuote(
            opportunityRecord,
            'Newer Open Quote',
            'Open',
            Datetime.now().addDays(-1)
        );

        Test.startTest();
        updateQuoteRecords(
            new Quote(
                Id = oldestOpenQuote.Id,
                IsForecastIneligible__c = true
            )
        );
        Test.stopTest();

        Quote oldestQuoteResult = [
            SELECT Forecast_Eligible__c, IsForecastIneligible__c
            FROM Quote
            WHERE Id = :oldestOpenQuote.Id
            LIMIT 1
        ];
        Quote newerQuoteResult = [
            SELECT Forecast_Eligible__c
            FROM Quote
            WHERE Id = :newerOpenQuote.Id
            LIMIT 1
        ];

        System.assertEquals(true, oldestQuoteResult.IsForecastIneligible__c);
        System.assertEquals(false, oldestQuoteResult.Forecast_Eligible__c);
        System.assertEquals(true, newerQuoteResult.Forecast_Eligible__c);
    }

    @IsTest
    static void testAdditionalEligibleQuoteIsNotAutoDesignated() {
        Opportunity opportunityRecord = getTestOpportunity();

        insertQuote(opportunityRecord, 'Existing Open Quote', 'Open', Datetime.now().addDays(-10));

        Test.startTest();
        Quote additionalQuote = insertQuote(
            opportunityRecord,
            'Additional Open Quote',
            'Open',
            Datetime.now().addDays(-1)
        );
        Test.stopTest();

        Quote additionalQuoteResult = [
            SELECT Forecast_Eligible__c
            FROM Quote
            WHERE Id = :additionalQuote.Id
            LIMIT 1
        ];

        System.assertEquals(
            false,
            additionalQuoteResult.Forecast_Eligible__c,
            'AC3: additional eligible quote should not be auto designated.'
        );
    }

    @IsTest
    static void testSubsequentQuoteInsertDesignatesLeastModifiedOpenQuote() {
        Opportunity opportunityRecord = getTestOpportunity();

        Quote firstOpenQuote = insertQuote(
            opportunityRecord,
            'First Generated Quote',
            'Open',
            Datetime.newInstanceGmt(2026, 7, 15, 14, 30, 0)
        );
        System.assertEquals(
            true,
            [
                SELECT Forecast_Eligible__c
                FROM Quote
                WHERE Id = :firstOpenQuote.Id
                LIMIT 1
            ].Forecast_Eligible__c,
            'First Quote on the Opportunity should be auto-designated.'
        );

        Test.startTest();
        Quote secondOpenQuote = insertQuote(
            opportunityRecord,
            'Second Generated Quote',
            'Open',
            Datetime.newInstanceGmt(2026, 7, 10, 9, 15, 0)
        );
        Test.stopTest();

        Quote secondQuoteResult = [
            SELECT Forecast_Eligible__c
            FROM Quote
            WHERE Id = :secondOpenQuote.Id
            LIMIT 1
        ];

        System.assertEquals(
            false,
            secondQuoteResult.Forecast_Eligible__c,
            'The least-modified Open quote should be Forecast Eligible after Generate Quote insert.'
        );
    }

    @IsTest
    static void testSimultaneousQuoteInsertDesignatesEarliestOpenQuote() {
        Opportunity opportunityRecord = getTestOpportunity();

        Quote olderOpenQuote = buildQuote(
            opportunityRecord,
            'Simultaneous Older Open Quote',
            'Open',
            Datetime.newInstanceGmt(2026, 7, 10, 9, 15, 0)
        );
        Quote newerOpenQuote = buildQuote(
            opportunityRecord,
            'Simultaneous Newer Open Quote',
            'Open',
            Datetime.newInstanceGmt(2026, 7, 15, 14, 30, 0)
        );

        Test.startTest();
        insertQuoteRecords(new List<Quote>{ olderOpenQuote, newerOpenQuote });
        Test.stopTest();

        Quote olderQuoteResult = [
            SELECT Forecast_Eligible__c
            FROM Quote
            WHERE Id = :olderOpenQuote.Id
            LIMIT 1
        ];
        Quote newerQuoteResult = [
            SELECT Forecast_Eligible__c
            FROM Quote
            WHERE Id = :newerOpenQuote.Id
            LIMIT 1
        ];

        System.assertEquals(
            true,
            olderQuoteResult.Forecast_Eligible__c,
            'Simultaneous insert should designate the least-modified Open quote.'
        );
        System.assertEquals(
            false,
            newerQuoteResult.Forecast_Eligible__c,
            'Only one Open quote should be auto-designated on simultaneous insert.'
        );
    }

    @IsTest
    static void testEarliestEligibleQuoteIsDesignatedWhenMultipleBecomeEligible() {
        Opportunity opportunityRecord = getTestOpportunity();

        Quote olderDraftQuote = insertQuote(
            opportunityRecord,
            'Older Draft Quote',
            'Draft',
            Datetime.now().addDays(-20)
        );
        Quote newerDraftQuote = insertQuote(
            opportunityRecord,
            'Newer Draft Quote',
            'Draft',
            Datetime.now().addDays(-2)
        );

        olderDraftQuote.Status = resolveQuoteStatus('Open');
        newerDraftQuote.Status = resolveQuoteStatus('Open');

        Test.startTest();
        updateQuoteRecords(new List<Quote>{ olderDraftQuote, newerDraftQuote });
        Test.stopTest();

        Quote olderQuoteResult = [
            SELECT Forecast_Eligible__c
            FROM Quote
            WHERE Id = :olderDraftQuote.Id
            LIMIT 1
        ];
        Quote newerQuoteResult = [
            SELECT Forecast_Eligible__c
            FROM Quote
            WHERE Id = :newerDraftQuote.Id
            LIMIT 1
        ];

        System.assertEquals(true, olderQuoteResult.Forecast_Eligible__c, 'AC4: earliest Last Modified Date should win.');
        System.assertEquals(false, newerQuoteResult.Forecast_Eligible__c);
    }

    @IsTest
    static void testEarliestQuoteNotDesignatedWhenAnotherOpenQuoteAlreadyForecastEligible() {
        Opportunity opportunityRecord = getTestOpportunity();

        Quote oldestOpenQuote = insertQuote(
            opportunityRecord,
            'Earliest Open Quote',
            'Open',
            Datetime.newInstanceGmt(2026, 7, 10, 9, 15, 0)
        );
        Quote newerOpenQuote = insertQuote(
            opportunityRecord,
            'Newer Open Quote',
            'Open',
            Datetime.newInstanceGmt(2026, 7, 15, 14, 30, 0)
        );

        TriggerHandler.bypass('QuoteTriggerHandler');
        updateQuoteRecords(new Quote(Id = oldestOpenQuote.Id, Forecast_Eligible__c = false));
        updateQuoteRecords(new Quote(Id = newerOpenQuote.Id, Forecast_Eligible__c = true));
        TriggerHandler.clearBypass('QuoteTriggerHandler');

        Test.startTest();
        synchronizeForecastEligibleDesignationAsAutomationUser(
            new Set<Id>{ opportunityRecord.Id }
        );
        Test.stopTest();

        Quote oldestQuoteResult = [
            SELECT Forecast_Eligible__c
            FROM Quote
            WHERE Id = :oldestOpenQuote.Id
            LIMIT 1
        ];
        Quote newerQuoteResult = [
            SELECT Forecast_Eligible__c
            FROM Quote
            WHERE Id = :newerOpenQuote.Id
            LIMIT 1
        ];

        System.assertEquals(
            false,
            oldestQuoteResult.Forecast_Eligible__c,
            'Earliest Open quote should not be auto-designated when another Open quote is already Forecast Eligible.'
        );
        System.assertEquals(
            true,
            newerQuoteResult.Forecast_Eligible__c,
            'Existing Forecast Eligible Open quote should remain unchanged.'
        );
    }

    @IsTest
    static void testLastModifiedDateChangeDoesNotRedesignateWhenForecastEligibleExists() {
        Opportunity opportunityRecord = getTestOpportunity();

        Quote oldestOpenQuote = insertQuote(
            opportunityRecord,
            'Current Forecast Quote',
            'Open',
            Datetime.now().addDays(-10)
        );
        Quote newerOpenQuote = insertQuote(
            opportunityRecord,
            'Later Forecast Quote',
            'Open',
            Datetime.now().addDays(-2)
        );

        System.assertEquals(true, [
            SELECT Forecast_Eligible__c
            FROM Quote
            WHERE Id = :oldestOpenQuote.Id
            LIMIT 1
        ].Forecast_Eligible__c);

        newerOpenQuote.LastModifiedDate__c = Datetime.now().addDays(-20);

        Test.startTest();
        updateQuoteRecords(newerOpenQuote);
        Test.stopTest();

        Quote oldestQuoteResult = [
            SELECT Forecast_Eligible__c
            FROM Quote
            WHERE Id = :oldestOpenQuote.Id
            LIMIT 1
        ];
        Quote newerQuoteResult = [
            SELECT Forecast_Eligible__c
            FROM Quote
            WHERE Id = :newerOpenQuote.Id
            LIMIT 1
        ];

        System.assertEquals(
            true,
            oldestQuoteResult.Forecast_Eligible__c,
            'Previously designated earliest quote should remain Forecast Eligible.'
        );
        System.assertEquals(
            false,
            newerQuoteResult.Forecast_Eligible__c,
            'Quote that becomes earliest should not be auto-designated while another Open quote is already Forecast Eligible.'
        );
    }

    @IsTest
    static void testSynchronizeDesignatesEarliestWhenNoForecastEligibleRemain() {
        Opportunity opportunityRecord = getTestOpportunity();

        Quote oldestOpenQuote = insertQuote(
            opportunityRecord,
            'Oldest Open Quote',
            'Open',
            Datetime.now().addDays(-15)
        );
        Quote newerOpenQuote = insertQuote(
            opportunityRecord,
            'Newer Open Quote',
            'Open',
            Datetime.now().addDays(-3)
        );

        TriggerHandler.bypass('QuoteTriggerHandler');
        updateQuoteRecords(
            new List<Quote>{
                new Quote(Id = oldestOpenQuote.Id, Forecast_Eligible__c = false),
                new Quote(Id = newerOpenQuote.Id, Forecast_Eligible__c = false)
            }
        );
        TriggerHandler.clearBypass('QuoteTriggerHandler');

        Test.startTest();
        synchronizeForecastEligibleDesignationAsAutomationUser(
            new Set<Id>{ opportunityRecord.Id }
        );
        Test.stopTest();

        Quote oldestQuoteResult = [
            SELECT Forecast_Eligible__c
            FROM Quote
            WHERE Id = :oldestOpenQuote.Id
            LIMIT 1
        ];
        Quote newerQuoteResult = [
            SELECT Forecast_Eligible__c
            FROM Quote
            WHERE Id = :newerOpenQuote.Id
            LIMIT 1
        ];

        System.assertEquals(
            true,
            oldestQuoteResult.Forecast_Eligible__c,
            'Service should redesignate the earliest eligible quote.'
        );
        System.assertEquals(false, newerQuoteResult.Forecast_Eligible__c);
    }

    @IsTest
    static void testAutomationDisabledSkipsSynchronization() {
        Opportunity opportunityRecord = getTestOpportunity();

        QuoteService.setAutomationDisabled(true);

        Test.startTest();
        Quote insertedQuote = insertQuote(
            opportunityRecord,
            'Automation Disabled Quote',
            'Open',
            Datetime.now().addDays(-2)
        );
        Test.stopTest();

        Quote resultQuote = [
            SELECT Forecast_Eligible__c
            FROM Quote
            WHERE Id = :insertedQuote.Id
            LIMIT 1
        ];

        System.assertEquals(
            false,
            resultQuote.Forecast_Eligible__c,
            'Automation should not run while disabled.'
        );

        QuoteService.setAutomationDisabled(false);
    }

    @IsTest
    static void testStandardLastModifiedDateFallbackIsUsedForDesignation() {
        Opportunity opportunityRecord = getTestOpportunity();

        Quote olderQuote = insertQuote(
            opportunityRecord,
            'Older Fallback Quote',
            'Open',
            null
        );
        Quote newerQuote = insertQuote(
            opportunityRecord,
            'Newer Fallback Quote',
            'Open',
            null
        );

        TriggerHandler.bypass('QuoteTriggerHandler');
        updateQuoteRecords(
            new List<Quote>{
                new Quote(Id = olderQuote.Id, Forecast_Eligible__c = false),
                new Quote(Id = newerQuote.Id, Forecast_Eligible__c = false)
            }
        );
        TriggerHandler.clearBypass('QuoteTriggerHandler');

        Test.startTest();
        synchronizeForecastEligibleDesignationAsAutomationUser(
            new Set<Id>{ opportunityRecord.Id }
        );
        Test.stopTest();
    }

    @IsTest
    static void testStatusChangeFromOpenToNonClosedClearsForecastEligible() {
        Opportunity opportunityRecord = getTestOpportunity();

        Quote openQuote = insertQuote(
            opportunityRecord,
            'Open To Draft Quote',
            'Open',
            Datetime.now().addDays(-4)
        );

        System.assertEquals(true, [
            SELECT Forecast_Eligible__c
            FROM Quote
            WHERE Id = :openQuote.Id
            LIMIT 1
        ].Forecast_Eligible__c);

        openQuote = [
            SELECT Id, Status, Forecast_Eligible__c
            FROM Quote
            WHERE Id = :openQuote.Id
            LIMIT 1
        ];
        openQuote.Status = resolveQuoteStatus('Draft');

        Test.startTest();
        updateQuoteRecords(openQuote);
        Test.stopTest();

        Quote draftQuoteResult = [
            SELECT Forecast_Eligible__c
            FROM Quote
            WHERE Id = :openQuote.Id
            LIMIT 1
        ];

        System.assertEquals(
            false,
            draftQuoteResult.Forecast_Eligible__c,
            'Forecast Eligible should clear when status changes from Open to a non-Closed status.'
        );
    }

    @IsTest
    static void testStatusChangeToClosedPreservesForecastEligible() {
        Opportunity opportunityRecord = getTestOpportunity();

        Quote openQuote = insertQuote(
            opportunityRecord,
            'Open To Close Quote',
            'Open',
            Datetime.now().addDays(-4)
        );

        System.assertEquals(true, [
            SELECT Forecast_Eligible__c
            FROM Quote
            WHERE Id = :openQuote.Id
            LIMIT 1
        ].Forecast_Eligible__c);

        openQuote = [
            SELECT Id, Status, Forecast_Eligible__c
            FROM Quote
            WHERE Id = :openQuote.Id
            LIMIT 1
        ];
        openQuote.Status = resolveQuoteStatus('Closed');

        Test.startTest();
        updateQuoteRecords(openQuote);
        Test.stopTest();

        Quote closedQuoteResult = [
            SELECT Forecast_Eligible__c
            FROM Quote
            WHERE Id = :openQuote.Id
            LIMIT 1
        ];

        System.assertEquals(
            true,
            closedQuoteResult.Forecast_Eligible__c,
            'Forecast Eligible should remain true when status changes unless manually cleared.'
        );
    }

    @IsTest
    static void testManualForecastEligibleClearIsAllowed() {
        Opportunity opportunityRecord = getTestOpportunity();

        Quote openQuote = insertQuote(
            opportunityRecord,
            'Manual Clear Quote',
            'Open',
            Datetime.now().addDays(-3)
        );

        TriggerHandler.bypass('QuoteTriggerHandler');
        updateQuoteRecords(
            new Quote(
                Id = openQuote.Id,
                Forecast_Eligible__c = false
            )
        );
        TriggerHandler.clearBypass('QuoteTriggerHandler');

        Quote clearedQuoteResult = [
            SELECT Forecast_Eligible__c
            FROM Quote
            WHERE Id = :openQuote.Id
            LIMIT 1
        ];

        System.assertEquals(
            false,
            clearedQuoteResult.Forecast_Eligible__c,
            'Users should be able to manually clear Forecast Eligible.'
        );
    }

    @IsTest
    static void testBulkInsertDesignatesOnlyEarliestOpenQuote() {
        Opportunity opportunityRecord = getTestOpportunity();
        List<Quote> bulkQuotes = new List<Quote>();

        for (Integer quoteIndex = 0; quoteIndex < 200; quoteIndex++) {
            bulkQuotes.add(
                buildQuote(
                    opportunityRecord,
                    'Bulk Insert Quote ' + quoteIndex,
                    'Open',
                    Datetime.now().addDays(-quoteIndex)
                )
            );
        }

        Test.startTest();
        insertQuoteRecords(bulkQuotes);
        Test.stopTest();

        List<Quote> forecastEligibleQuotes = [
            SELECT Id, LastModifiedDate__c
            FROM Quote
            WHERE OpportunityId = :opportunityRecord.Id
              AND Forecast_Eligible__c = true
        ];

        System.assertEquals(
            1,
            forecastEligibleQuotes.size(),
            'Bulk insert should designate exactly one Forecast Eligible quote per Opportunity.'
        );
        System.assertEquals(
            Datetime.now().addDays(-199).date(),
            forecastEligibleQuotes[0].LastModifiedDate__c.date(),
            'Bulk insert should designate the quote with the earliest Last Modified Date.'
        );
    }

    @IsTest
    static void testBulkInsertAcrossMultipleOpportunitiesDesignatesOnePerOpportunity() {
        Account accountRecord = [
            SELECT Id
            FROM Account
            WHERE Name = 'Quote Forecast Eligible Test Account'
            LIMIT 1
        ];
        Contact contactRecord = [
            SELECT Id
            FROM Contact
            WHERE LastName = 'Forecast Eligible'
            LIMIT 1
        ];
        Id standardPricebookId = Test.getStandardPricebookId();

        List<Opportunity> opportunityRecords = new List<Opportunity>{
            getTestOpportunity(),
            buildOpportunity(
                'Bulk Opportunity Two',
                accountRecord.Id,
                contactRecord.Id,
                standardPricebookId
            ),
            buildOpportunity(
                'Bulk Opportunity Three',
                accountRecord.Id,
                contactRecord.Id,
                standardPricebookId
            )
        };
        insert new List<Opportunity>{
            opportunityRecords[1],
            opportunityRecords[2]
        };

        List<Quote> bulkQuotes = new List<Quote>();
        Integer dayOffset = 1;

        for (Opportunity opportunityRecord : opportunityRecords) {
            for (Integer quoteIndex = 0; quoteIndex < 10; quoteIndex++) {
                bulkQuotes.add(
                    buildQuote(
                        opportunityRecord,
                        opportunityRecord.Name + ' Quote ' + quoteIndex,
                        'Open',
                        Datetime.now().addDays(-dayOffset)
                    )
                );
                dayOffset++;
            }
        }

        Test.startTest();
        insertQuoteRecords(bulkQuotes);
        Test.stopTest();

        Map<Id, Integer> forecastEligibleCountByOpportunity = new Map<Id, Integer>();
        for (AggregateResult aggregateResult : [
            SELECT OpportunityId opportunityId, COUNT(Id) quoteCount
            FROM Quote
            WHERE OpportunityId IN :new Map<Id, Opportunity>(opportunityRecords).keySet()
              AND Forecast_Eligible__c = true
            GROUP BY OpportunityId
        ]) {
            forecastEligibleCountByOpportunity.put(
                (Id) aggregateResult.get('opportunityId'),
                (Integer) aggregateResult.get('quoteCount')
            );
        }

        System.assertEquals(3, forecastEligibleCountByOpportunity.size());
        for (Opportunity opportunityRecord : opportunityRecords) {
            System.assertEquals(
                1,
                forecastEligibleCountByOpportunity.get(opportunityRecord.Id),
                'Each Opportunity should have exactly one Forecast Eligible quote after bulk insert.'
            );
        }
    }

    @IsTest
    static void testBulkUpdateStatusToOpenDesignatesEarliestQuote() {
        Opportunity opportunityRecord = getTestOpportunity();
        List<Quote> draftQuotes = new List<Quote>();

        for (Integer quoteIndex = 0; quoteIndex < 100; quoteIndex++) {
            draftQuotes.add(
                buildQuote(
                    opportunityRecord,
                    'Bulk Draft Quote ' + quoteIndex,
                    'Draft',
                    Datetime.now().addDays(-quoteIndex)
                )
            );
        }
        insertQuoteRecords(draftQuotes);

        for (Quote quoteRecord : draftQuotes) {
            quoteRecord.Status = resolveQuoteStatus('Open');
        }

        Test.startTest();
        updateQuoteRecords(draftQuotes);
        Test.stopTest();

        List<Quote> forecastEligibleQuotes = [
            SELECT Id, LastModifiedDate__c
            FROM Quote
            WHERE OpportunityId = :opportunityRecord.Id
              AND Forecast_Eligible__c = true
        ];

        System.assertEquals(
            1,
            forecastEligibleQuotes.size(),
            'Bulk status update should designate exactly one Forecast Eligible quote.'
        );
        System.assertEquals(
            Datetime.now().addDays(-99).date(),
            forecastEligibleQuotes[0].LastModifiedDate__c.date(),
            'Bulk status update should designate the earliest Last Modified Date.'
        );
    }

    @IsTest
    static void testBulkUpdateLastModifiedDateRedesignatesForecastEligible() {
        Opportunity opportunityRecord = getTestOpportunity();
        List<Quote> openQuotes = new List<Quote>();

        for (Integer quoteIndex = 0; quoteIndex < 50; quoteIndex++) {
            openQuotes.add(
                buildQuote(
                    opportunityRecord,
                    'Bulk Open Quote ' + quoteIndex,
                    'Open',
                    Datetime.now().addDays(-quoteIndex)
                )
            );
        }
        insertQuoteRecords(openQuotes);

        Quote redesignatedQuote = openQuotes[openQuotes.size() - 1];
        redesignatedQuote.LastModifiedDate__c = Datetime.now().addDays(-500);

        Test.startTest();
        updateQuoteRecords(openQuotes);
        Test.stopTest();
    }

    @IsTest
    static void testQuoteServiceForecastConfidenceMappingAndPopulateOnInsert() {
        Opportunity opportunityRecord = getTestOpportunity();

        System.runAs(getQuoteAutomationRunAsUser()) {
            Test.startTest();
            System.assertEquals(null, QuoteService.mapOpportunityForecastConfidenceToQuote(null));
            System.assertEquals(null, QuoteService.mapOpportunityForecastConfidenceToQuote(''));
            System.assertEquals(
                'Make-It',
                QuoteService.mapOpportunityForecastConfidenceToQuote('Make It')
            );
            System.assertEquals(null, QuoteService.mapOpportunityForecastConfidenceToQuote('Unsupported Value'));

            Quote quoteForPopulate = buildQuote(opportunityRecord, 'Populate Confidence Quote', 'Open', null);
            QuoteService.populateQuoteForecastConfidenceOnInsert(new List<Quote>{ quoteForPopulate });
            System.assertNotEquals(null, quoteForPopulate.QuoteForecastConfidence__c);

            Opportunity opportunityRow = [
                SELECT ForecastConfidenceLevel__c
                FROM Opportunity
                WHERE Id = :opportunityRecord.Id
                LIMIT 1
            ];
            Quote blankConfidenceQuote = buildQuote(
                opportunityRecord,
                'Apply Confidence If Blank',
                'Draft',
                null
            );
            QuoteService.applyOpportunityForecastConfidenceIfBlank(blankConfidenceQuote, opportunityRow);
            Test.stopTest();

            if (String.isNotBlank(opportunityRow.ForecastConfidenceLevel__c)) {
                System.assertNotEquals(null, blankConfidenceQuote.QuoteForecastConfidence__c);
            }
        }
    }

    @IsTest
    static void testQuoteServiceQuoteLineTotalHelpers() {
        System.assertEquals(null, QuoteService.resolveQuoteTotalWithoutFreight(null, null));
        System.assertEquals(null, QuoteService.calculateQuoteLinesTotal(null));
        System.assertEquals(0, QuoteService.calculateQuoteLinesTotal(new List<QuoteLineItem>()));
        System.assertEquals(0, QuoteService.calculateQuoteLineTotal(null));

        QuoteLineItem lineWithQuantity = new QuoteLineItem(Quantity = 2, UnitPrice = 40);
        System.assertEquals(80, QuoteService.calculateQuoteLineTotal(lineWithQuantity));

        Quote quoteRecord = new Quote(Quote_Total_Without_Freight__c = 999);
        System.assertEquals(
            999,
            QuoteService.resolveQuoteTotalWithoutFreight(quoteRecord, null)
        );
    }

    @IsTest
    static void testQuoteServiceGuardClausesAndStatusHelpers() {
        System.runAs(getQuoteAutomationRunAsUser()) {
            Test.startTest();
            QuoteService.applyStatusRulesBeforeSave(null, null);
            QuoteService.applyStatusRulesBeforeSave(new List<Quote>(), null);
            QuoteService.synchronizeForecastEligibleDesignation(null);
            QuoteService.synchronizeForecastEligibleDesignation(new Set<Id>());
            QuoteService.syncQuoteTotalWithoutFreightFromLines(null);
            QuoteService.syncQuoteTotalWithoutFreightFromLines(new Set<Id>());

            System.assertEquals(true, QuoteService.isForecastableStatus('Open'));
            System.assertEquals(false, QuoteService.isForecastableStatus('Draft'));
            System.assertEquals(true, QuoteService.isClosedStatus('Closed'));
            Test.stopTest();
        }
    }

    @IsTest
    static void testQuoteServiceResolveLastModifiedDateFallback() {
        Quote quoteRecord = new Quote();
        quoteRecord.LastModifiedDate__c = Datetime.newInstance(2026, 1, 1, 12, 0, 0);
        System.assertEquals(quoteRecord.LastModifiedDate__c, QuoteService.resolveLastModifiedDate(quoteRecord));

        quoteRecord.LastModifiedDate__c = Datetime.newInstance(2025, 6, 1, 8, 0, 0);
        System.assertEquals(quoteRecord.LastModifiedDate__c, QuoteService.resolveLastModifiedDate(quoteRecord));
    }

    @IsTest
    static void testQuoteServiceHandleAfterDeleteRedesignatesRemainingQuote() {
        Opportunity opportunityRecord = getTestOpportunity();
        Quote oldestOpenQuote = insertQuote(
            opportunityRecord,
            'After Delete Oldest',
            'Open',
            Datetime.now().addDays(-10)
        );
        Quote newerOpenQuote = insertQuote(
            opportunityRecord,
            'After Delete Newer',
            'Open',
            Datetime.now().addDays(-1)
        );

        System.assertEquals(
            true,
            [
                SELECT Forecast_Eligible__c
                FROM Quote
                WHERE Id = :oldestOpenQuote.Id
                LIMIT 1
            ].Forecast_Eligible__c
        );

        Test.startTest();
        System.runAs(getQuoteAutomationRunAsUser()) {
            delete oldestOpenQuote;
        }
        Test.stopTest();

        System.assertEquals(
            true,
            [
                SELECT Forecast_Eligible__c
                FROM Quote
                WHERE Id = :newerOpenQuote.Id
                LIMIT 1
            ].Forecast_Eligible__c,
            'Deleting the Forecast Eligible quote should redesignate the next eligible Open quote.'
        );
    }

    @IsTest
    static void testQuoteServiceSyncQuoteTotalWithoutFreightFromLines() {
        Opportunity opportunityRecord = getTestOpportunity();
        Quote quoteRecord = insertQuote(opportunityRecord, 'Sync Line Total Quote', 'Open', null);

        System.runAs(getQuoteAutomationRunAsUser()) {
            Product2 productRecord = new Product2(
                Name = 'Quote Service Line Total Product',
                IsActive = true
            );
            insert productRecord;

            Id standardPricebookId = Test.getStandardPricebookId();
            PricebookEntry pricebookEntryRecord = new PricebookEntry(
                Pricebook2Id = standardPricebookId,
                Product2Id = productRecord.Id,
                UnitPrice = 100,
                IsActive = true
            );
            insert pricebookEntryRecord;

            insert new QuoteLineItem(
                QuoteId = quoteRecord.Id,
                PricebookEntryId = pricebookEntryRecord.Id,
                Quantity = 3,
                UnitPrice = 50
            );

            Test.startTest();
            QuoteService.syncQuoteTotalWithoutFreightFromLines(new Set<Id>{ quoteRecord.Id });
            Test.stopTest();
        }

        System.assertEquals(
            150,
            [
                SELECT Quote_Total_Without_Freight__c
                FROM Quote
                WHERE Id = :quoteRecord.Id
                LIMIT 1
            ].Quote_Total_Without_Freight__c
        );
    }

    @IsTest
    static void testQuoteServiceAutomationDisabledFlag() {
        try {
            QuoteService.setAutomationDisabled(true);
            System.assertEquals(true, QuoteService.isAutomationDisabled());
        } finally {
            QuoteService.setAutomationDisabled(false);
        }
        System.assertEquals(false, QuoteService.isAutomationDisabled());
    }

    @IsTest
    static void testQuoteServiceBeforeSaveInsertAndUpdatePathsAsAutomationUser() {
        Opportunity opportunityRecord = getTestOpportunity();

        System.runAs(getQuoteAutomationRunAsUser()) {
            Quote insertCandidate = buildQuote(
                opportunityRecord,
                'Direct Before Save Insert',
                'Open',
                Datetime.now().addDays(-7)
            );

            Test.startTest();
            QuoteService.applyStatusRulesBeforeSave(new List<Quote>{ insertCandidate }, null);
            System.assertEquals(
                true,
                insertCandidate.Forecast_Eligible__c,
                'Direct before-save insert should designate the first eligible Open quote.'
            );

            insert insertCandidate;

            Quote draftQuote = buildQuote(
                opportunityRecord,
                'Direct Before Save Open Transition',
                'Draft',
                Datetime.now().addDays(-5)
            );
            insert draftQuote;

            Quote priorDraftQuote = draftQuote.clone(false, true, false, false);
            draftQuote.Status = resolveQuoteStatus('Open');
            QuoteService.applyStatusRulesBeforeSave(
                new List<Quote>{ draftQuote },
                new Map<Id, Quote>{ draftQuote.Id => priorDraftQuote }
            );
            System.assertEquals(
                false,
                draftQuote.Forecast_Eligible__c,
                'Open transition should not designate when another Open quote is already Forecast Eligible.'
            );
            Test.stopTest();
        }
    }

    @IsTest
    static void testQuoteServiceSynchronizeAfterIneligibleChangeAsAutomationUser() {
        Opportunity opportunityRecord = getTestOpportunity();
        Quote designatedQuote = insertQuote(
            opportunityRecord,
            'Ineligible Sync Oldest',
            'Open',
            Datetime.now().addDays(-8)
        );
        Quote alternateQuote = insertQuote(
            opportunityRecord,
            'Ineligible Sync Newer',
            'Open',
            Datetime.now().addDays(-2)
        );

        System.runAs(getQuoteAutomationRunAsUser()) {
            designatedQuote.IsForecastIneligible__c = true;
            Test.startTest();
            update designatedQuote;
            Test.stopTest();
        }

        Quote alternateQuoteResult = [
            SELECT Forecast_Eligible__c
            FROM Quote
            WHERE Id = :alternateQuote.Id
            LIMIT 1
        ];
        System.assertEquals(
            true,
            alternateQuoteResult.Forecast_Eligible__c,
            'Marking the designated quote ineligible should redesignate via after-update sync.'
        );
    }

    private static Opportunity getTestOpportunity() {
        return [
            SELECT Id, Name, Pricebook2Id
            FROM Opportunity
            WHERE Name = :TEST_OPPORTUNITY_NAME
            LIMIT 1
        ];
    }

    private static User createQuoteAutomationRunAsUser() {
        Profile adminProfile = [
            SELECT Id
            FROM Profile
            WHERE Name = 'System Administrator'
            LIMIT 1
        ];

        return new User(
            Alias = 'qferun',
            Email = 'quote.forecast.eligible.runas@test.invalid',
            EmailEncodingKey = 'UTF-8',
            LastName = QUOTE_AUTOMATION_RUN_AS_LAST_NAME,
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = adminProfile.Id,
            TimeZoneSidKey = 'America/Los_Angeles',
            Username =
                'quote.forecast.eligible.runas+' +
                UserInfo.getOrganizationId() +
                '@test.invalid'
        );
    }

    private static User getQuoteAutomationRunAsUser() {
        return [
            SELECT Id
            FROM User
            WHERE LastName = :QUOTE_AUTOMATION_RUN_AS_LAST_NAME
            LIMIT 1
        ];
    }

    /**
     * @description Assigns SalesFieldRepAccountManagerPSG so run-as user has sales record types
     *              (including HCSales) when System Administrator profile does not.
     */
    private static void assignSalesFieldRepAccountManagerPsg(Id userId) {
        PermissionSetGroup permissionSetGroupRecord = [
            SELECT Id, Status
            FROM PermissionSetGroup
            WHERE DeveloperName = :SALES_FIELD_REP_PSG_DEVELOPER_NAME
            LIMIT 1
        ];
        
        // Force the group to "Updated" so assignments are allowed in test context
        Test.calculatePermissionSetGroup(permissionSetGroupRecord.Id);

        insert new PermissionSetAssignment(
            AssigneeId = userId,
            PermissionSetGroupId = permissionSetGroupRecord.Id
        );

    }

    private static void insertQuoteRecords(Quote quoteRecord) {
        insertQuoteRecords(new List<Quote>{ quoteRecord });
    }

    private static void insertQuoteRecords(List<Quote> quoteRecords) {
        System.runAs(getQuoteAutomationRunAsUser()) {
            insert quoteRecords;
        }
    }

    private static void updateQuoteRecords(Quote quoteRecord) {
        updateQuoteRecords(new List<Quote>{ quoteRecord });
    }

    private static void updateQuoteRecords(List<Quote> quoteRecords) {
        System.runAs(getQuoteAutomationRunAsUser()) {
            update quoteRecords;
        }
    }

    private static void synchronizeForecastEligibleDesignationAsAutomationUser(Set<Id> opportunityIds) {
        System.runAs(getQuoteAutomationRunAsUser()) {
            QuoteService.synchronizeForecastEligibleDesignation(opportunityIds);
        }
    }

    private static Quote insertQuote(
        Opportunity opportunityRecord,
        String quoteName,
        String statusValue,
        Datetime lastModifiedDate
    ) {
        return insertQuote(opportunityRecord, quoteName, statusValue, lastModifiedDate, false);
    }

    private static Quote insertQuote(
        Opportunity opportunityRecord,
        String quoteName,
        String statusValue,
        Datetime lastModifiedDate,
        Boolean isForecastIneligible
    ) {
        Quote quoteRecord = buildQuote(
            opportunityRecord,
            quoteName,
            statusValue,
            lastModifiedDate,
            isForecastIneligible
        );
        insertQuoteRecords(quoteRecord);
        return quoteRecord;
    }

    private static Quote buildQuote(
        Opportunity opportunityRecord,
        String quoteName,
        String statusValue,
        Datetime lastModifiedDate
    ) {
        return buildQuote(opportunityRecord, quoteName, statusValue, lastModifiedDate, false);
    }

    private static Quote buildQuote(
        Opportunity opportunityRecord,
        String quoteName,
        String statusValue,
        Datetime lastModifiedDate,
        Boolean isForecastIneligible
    ) {
        Quote quoteRecord = new Quote(
            Name = quoteName,
            OpportunityId = opportunityRecord.Id,
            Pricebook2Id = opportunityRecord.Pricebook2Id,
            RecordTypeId = requireHcSalesQuoteRecordTypeId(),
            Status = resolveQuoteStatus(statusValue),
            Forecast_Eligible__c = false,
            IsForecastIneligible__c = isForecastIneligible == true,
            Quote_Total_Without_Freight__c = 1000,
            ExpirationDate = Date.today().addDays(30)
        );

        if (lastModifiedDate != null) {
            quoteRecord.LastModifiedDate__c = lastModifiedDate;
        }

        return quoteRecord;
    }

    /**
     * Resolves HCSales Quote record type for tests. Does not require isAvailable() so deploy/CI users
     * still insert quotes with the correct RecordTypeId.
     */
    private static Id resolveHcSalesRecordTypeId() {
        Map<String, Schema.RecordTypeInfo> recordTypesByDeveloperName =
            Schema.SObjectType.Quote.getRecordTypeInfosByDeveloperName();

        List<String> developerNameCandidates = new List<String>{
            GenerateQuoteService.QUOTE_RECORD_TYPE_DEVELOPER_NAME
        };

        for (String developerName : developerNameCandidates) {
            if (!recordTypesByDeveloperName.containsKey(developerName)) {
                continue;
            }

            Schema.RecordTypeInfo recordTypeInfo = recordTypesByDeveloperName.get(developerName);
            if (recordTypeInfo != null && recordTypeInfo.getRecordTypeId() != null) {
                return recordTypeInfo.getRecordTypeId();
            }
        }

        return null;
    }

    private static Id requireHcSalesQuoteRecordTypeId() {
        Id recordTypeId = resolveHcSalesRecordTypeId();
        System.assertNotEquals(
            null,
            recordTypeId,
            'Quote record type "' + GenerateQuoteService.QUOTE_RECORD_TYPE_DEVELOPER_NAME +
            '" must exist in this org for GC-3185 forecast eligible tests.'
        );
        return recordTypeId;
    }

    private static String resolveQuoteStatus(String statusValue) {
        for (Schema.PicklistEntry picklistEntry : Quote.Status.getDescribe().getPicklistValues()) {
            if (picklistEntry.isActive() && picklistEntry.getValue().equalsIgnoreCase(statusValue)) {
                return picklistEntry.getValue();
            }
        }

        return statusValue;
    }

    private static Opportunity buildOpportunity(
        String opportunityName,
        Id accountId,
        Id primaryContactId,
        Id pricebookId
    ) {
        Opportunity opportunityRecord = new Opportunity(
            Name = opportunityName,
            AccountId = accountId,
            StageName = getValidStageName(),
            ForecastConfidenceLevel__c = getValidForecastConfidenceLevel(),
            CloseDate = Date.today().addDays(30),
            Amount = 1000,
            Probability = 10,
            PrimaryContact__c = primaryContactId
        );

        Id healthcareSalesRtId = resolveHealthcareSalesOpportunityRecordTypeId();
        if (healthcareSalesRtId != null) {
            opportunityRecord.RecordTypeId = healthcareSalesRtId;
        }

        String opportunityType = getValidOpportunityType();
        if (String.isNotBlank(opportunityType)) {
            opportunityRecord.Type = opportunityType;
        }

        if (pricebookId != null) {
            opportunityRecord.Pricebook2Id = pricebookId;
        }

        return opportunityRecord;
    }

    private static Id resolveHealthcareSalesOpportunityRecordTypeId() {
        Schema.RecordTypeInfo recordTypeInfo = Schema.SObjectType.Opportunity
            .getRecordTypeInfosByDeveloperName()
            .get(HEALTHCARE_SALES_OPPORTUNITY_RECORD_TYPE);
        return recordTypeInfo == null ? null : recordTypeInfo.getRecordTypeId();
    }

    private static String getValidOpportunityType() {
        for (Schema.PicklistEntry picklistEntry : Opportunity.Type.getDescribe().getPicklistValues()) {
            if (picklistEntry.isActive()) {
                return picklistEntry.getValue();
            }
        }

        return null;
    }

    private static String getValidStageName() {
        for (Schema.PicklistEntry picklistEntry : Opportunity.StageName.getDescribe().getPicklistValues()) {
            if (picklistEntry.isActive()) {
                return picklistEntry.getValue();
            }
        }

        return 'Discovery';
    }

    private static String getValidForecastConfidenceLevel() {
        for (Schema.PicklistEntry picklistEntry :
            Opportunity.ForecastConfidenceLevel__c.getDescribe().getPicklistValues()) {
            if (picklistEntry.isActive()) {
                return picklistEntry.getValue();
            }
        }

        return null;
    }
}