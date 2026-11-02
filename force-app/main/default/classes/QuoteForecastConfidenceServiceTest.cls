@IsTest
private class QuoteForecastConfidenceServiceTest {
    @IsTest
    static void testGetActiveOptionsReturnsActiveValues() {
        Test.startTest();
        List<QuoteForecastConfidenceService.Option> options =
            QuoteForecastConfidenceService.getActiveOptions();
        Test.stopTest();

        System.assertEquals(
            false,
            options.isEmpty(),
            'Active Quote Forecast Confidence values should be returned.'
        );

        Set<String> values = new Set<String>();
        for (QuoteForecastConfidenceService.Option option : options) {
            System.assertEquals(true, String.isNotBlank(option.label));
            System.assertEquals(true, String.isNotBlank(option.value));
            values.add(option.value);
        }

        System.assertEquals(
            true,
            values.contains('Pipeline') || values.contains('Budget') || values.contains('Upside'),
            'Field-level picklist values should be included regardless of record type.'
        );
    }
}