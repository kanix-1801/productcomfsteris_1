/**
 * Tests for {@link OraclePricingService}.
 * <p>Full success-path tests require Work Order Line Items that allow {@code Product2Id}; this org returns
 * FIELD_INTEGRITY_EXCEPTION for product on WOLI, so integration coverage is run manually or in an org that
 * permits product lines. Gateway and validation paths remain testable.</p>
 *
 * @author STERIS
 */
@IsTest
private class OraclePricingServiceTest {
    @IsTest
    static void testFetchAndApplyOraclePricingNullId() {
        OraclePricingService.WorkOrderPricingResult result = OraclePricingService.fetchAndApplyOraclePricing(null);
        Assert.isFalse(result.success, 'Null Work Order Id should return success = false.');
        Assert.isTrue(
            result.message != null && result.message.contains('required'),
            'Expected validation message for null Id.'
        );
    }
}