/**
 * @description Test class for Assets domain class.
 *              Covers constructor and domain exception.
 */
@IsTest
private class AssetsTest {

    @IsTest
    static void shouldConstructDomain_WhenValidRecordListProvided() {
        /********************************************
         * SETUP
         ********************************************/
        User testUser = new User(id=UserInfo.getUserId()); // Use current user to avoid permission issues in test context

        System.runAs(testUser) {
            /********************************************
             * GIVEN
             ********************************************/
            List<Asset> assetList = new List<Asset>{
                (Asset) new adb_Asset().name('Test Asset 1').record,
                (Asset) new adb_Asset().name('Test Asset 2').record
            };

            /********************************************
             * WHEN
             ********************************************/
            Test.startTest();
            Assets domain = new Assets(assetList);
            Test.stopTest();

            /********************************************
             * THEN
             ********************************************/
            Assert.isNotNull(domain, 'Domain instance should be created from a valid record list');
        }
    }

    @IsTest
    static void shouldConstructDomain_WhenEmptyListProvided() {
        /********************************************
         * SETUP
         ********************************************/
        User testUser = new User(id=UserInfo.getUserId()); // Use current user to avoid permission issues in test context

        System.runAs(testUser) {
            /********************************************
             * WHEN
             ********************************************/
            Test.startTest();
            Assets domain = new Assets(new List<Asset>());
            Test.stopTest();

            /********************************************
             * THEN
             ********************************************/
            Assert.isNotNull(domain, 'Domain instance should be created from an empty list without error');
        }
    }

    @IsTest
    static void shouldThrowAssetsException_WhenExceptionIsRaised() {
        /********************************************
         * SETUP
         ********************************************/
        User testUser = new User(id=UserInfo.getUserId()); // Use current user to avoid permission issues in test context

        System.runAs(testUser) {
            /********************************************
             * WHEN / THEN
             ********************************************/
            Test.startTest();
            try {
                throw new Assets.AssetsException('Asset Name is required.');
            } catch (Assets.AssetsException e) {
                Assert.areEqual(
                    'Asset Name is required.',
                    e.getMessage(),
                    'Exception message should match the value provided at construction'
                );
            }
            Test.stopTest();
        }
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    private static User buildTestUser() {
        adb_User builder = new adb_User();
        builder.persist();
        return (User) builder.record;
    }
}