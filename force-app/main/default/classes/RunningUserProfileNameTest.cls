@IsTest
private class RunningUserProfileNameTest {
    @IsTest
    static void returnsRunningUserProfileName() {
        String expectedName = [
            SELECT Name
            FROM Profile
            WHERE Id = :UserInfo.getProfileId()
            LIMIT 1
        ].Name;

        Test.startTest();
        List<RunningUserProfileName.ProfileNameResult> results = RunningUserProfileName.getRunningUserProfileName();
        Test.stopTest();

        System.assertEquals(1, results.size(), 'One profile result is returned.');
        System.assertEquals(expectedName, results[0].profileName, 'The result matches the running user profile.');
    }
}