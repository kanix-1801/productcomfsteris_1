/**
 * @author PSL
 * @date 27-10-2026
 * @description Test class for CaseTeamMemberSelectorTest that validates helper methods for email functionality
 */
@IsTest
private class CaseTeamMemberSelectorTest {
    @IsTest
    static void testGetCaseTeamMember_NoMember() {
        Case testCase = new Case(
            Subject = 'Case Without Team Member',
            Status = 'New',
            Origin = 'Phone'
        );
        insert testCase;
        Test.startTest();
        List<CaseTeamMember> result =
            CaseTeamMemberSelector.getCaseTeamMember(testCase);
        Test.stopTest();
        System.assertEquals(
            null,
            result,
            'Result should be null when Case has no team members'
        );
    }
}