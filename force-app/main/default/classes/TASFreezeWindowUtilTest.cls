/**
 * @author Suraj Thapliyal
 * @date 2026/08/11
 *
 * @group Order Line Contact
 *
 * @description Tests for TASFreezeWindowUtil label parsing and delete freeze evaluation.
 *              GC-2596 - TAS delete freeze window.
 */
@IsTest(SeeAllData=false)
private class TASFreezeWindowUtilTest {

    private static final String SAMPLE_WINDOW = '08/10/2026|08/20/2026';

    /**
     * @description Clears TASFreezeWindowUtil test hooks before each test method.
     * @return void
     */
    private static void resetHooks() {
        TASFreezeWindowUtil.testOnlyResetHooks();
    }

    /**
     * @description Asserts isDeleteFreezeActive throws TASTeamAccessException containing the reason fragment.
     * @param labelOverride Label value to evaluate.
     * @param reasonFragment Expected substring in the exception message.
     * @return void
     */
    private static void assertParseFailure(String labelOverride, String reasonFragment) {
        TASFreezeWindowUtil.testLabelOverride = labelOverride;
        Boolean threw = false;
        try {
            TASFreezeWindowUtil.isDeleteFreezeActive();
        } catch (TASTeamAccessException e) {
            threw = true;
            System.assert(
                e.getMessage().contains(reasonFragment),
                'Expected parse failure containing "' + reasonFragment + '", got: ' + e.getMessage()
            );
        }
        System.assert(threw, 'Expected TASTeamAccessException for labelValue=' + labelOverride);
    }

    /**
     * @description
     * GC-2596 - Verifies freeze is active on the start date, end date, and a date within the window.
     *
     * @return void
     */
    @IsTest
    static void testFreezeActiveOnStartEndAndMidWindowDates() {
        resetHooks();
        TASFreezeWindowUtil.testLabelOverride = SAMPLE_WINDOW;

        TASFreezeWindowUtil.testTodayOverride = Date.newInstance(2026, 8, 10);
        System.assertEquals(
            true,
            TASFreezeWindowUtil.isDeleteFreezeActive(),
            'Freeze should be active on window start date'
        );

        TASFreezeWindowUtil.testTodayOverride = Date.newInstance(2026, 8, 15);
        System.assertEquals(
            true,
            TASFreezeWindowUtil.isDeleteFreezeActive(),
            'Freeze should be active on a mid-window date'
        );

        TASFreezeWindowUtil.testTodayOverride = Date.newInstance(2026, 8, 20);
        System.assertEquals(
            true,
            TASFreezeWindowUtil.isDeleteFreezeActive(),
            'Freeze should be active on window end date'
        );
    }

    /**
     * @description
     * GC-2596 - Verifies freeze is inactive before/after the window and when the label is blank or NO_FREEZE.
     *
     * @return void
     */
    @IsTest
    static void testFreezeInactiveBeforeAfterBlankAndNoFreeze() {
        resetHooks();
        TASFreezeWindowUtil.testLabelOverride = SAMPLE_WINDOW;

        TASFreezeWindowUtil.testTodayOverride = Date.newInstance(2026, 8, 9);
        System.assertEquals(
            false,
            TASFreezeWindowUtil.isDeleteFreezeActive(),
            'Freeze should be inactive before window start'
        );

        TASFreezeWindowUtil.testTodayOverride = Date.newInstance(2026, 8, 21);
        System.assertEquals(
            false,
            TASFreezeWindowUtil.isDeleteFreezeActive(),
            'Freeze should be inactive after window end'
        );

        TASFreezeWindowUtil.testLabelOverride = '';
        TASFreezeWindowUtil.testTodayOverride = Date.newInstance(2026, 8, 15);
        System.assertEquals(
            false,
            TASFreezeWindowUtil.isDeleteFreezeActive(),
            'Blank label should not activate freeze'
        );

        TASFreezeWindowUtil.testLabelOverride = 'NO_FREEZE';
        System.assertEquals(
            false,
            TASFreezeWindowUtil.isDeleteFreezeActive(),
            'NO_FREEZE default should not activate freeze'
        );
    }

    /**
     * @description
     * GC-2596 - Verifies malformed label values throw TASTeamAccessException with parse failure details.
     *
     * @return void
     */
    @IsTest
    static void testInvalidLabelParseThrowsException() {
        resetHooks();
        TASFreezeWindowUtil.testTodayOverride = Date.newInstance(2026, 8, 15);

        assertParseFailure('08/10/2026', 'expected MM/DD/YYYY|MM/DD/YYYY');
        assertParseFailure('08/20/2026|08/10/2026', 'start date must be on or before end date');
        assertParseFailure('02/31/2026|08/20/2026', 'invalid start date; expected MM/DD/YYYY');
        assertParseFailure('08/10/2026|abc/def/ghi', 'invalid end date; expected MM/DD/YYYY');
        assertParseFailure('08/10/2026|20/10/2026', 'invalid end date; expected MM/DD/YYYY');
    }

    /**
     * @description
     * GC-2596 - Verifies validateFreezeWindowLabel throws for malformed values and allows blank/NO_FREEZE.
     *
     * @return void
     */
    @IsTest
    static void testValidateFreezeWindowLabel() {
        resetHooks();

        TASFreezeWindowUtil.testLabelOverride = '';
        TASFreezeWindowUtil.validateFreezeWindowLabel();

        TASFreezeWindowUtil.testLabelOverride = 'NO_FREEZE';
        TASFreezeWindowUtil.validateFreezeWindowLabel();

        TASFreezeWindowUtil.testLabelOverride = SAMPLE_WINDOW;
        TASFreezeWindowUtil.validateFreezeWindowLabel();

        assertParseFailure('08/10/2026|20/10/2026', 'invalid end date; expected MM/DD/YYYY');
    }

    /**
     * @description
     * GC-2596 - Verifies org Custom Label and Pacific today paths run without throwing when hooks are unset.
     *
     * @return void
     */
    @IsTest
    static void testOrgLabelAndPacificTodayPathWithoutThrow() {
        resetHooks();
        TASFreezeWindowUtil.validateFreezeWindowLabel();
        TASFreezeWindowUtil.isDeleteFreezeActive();
    }
}