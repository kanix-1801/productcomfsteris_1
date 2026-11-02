/**
 * @description GC-2860 - Unit tests for Competitive Installed Base roll-up and hierarchy.
 */
@IsTest(SeeAllData=false)
private class CompetitiveInstalledBaseControllerTest {
    private static final String RUN_AS_FIRST_NAME = 'CIB';
    private static final String RUN_AS_LAST_NAME = 'SysAdmin';

    @TestSetup
    static void setupData() {
        TestDataFactory.setupCompetitiveInstalledBaseScenario();
        TestDataFactory.insertCompetitiveInstalledBaseSysAdminTestUser(RUN_AS_FIRST_NAME, RUN_AS_LAST_NAME);
    }

    /**
     * @description System Administrator user with System_Administrator permission set assigned.
     */
    private static User getSysAdminUser() {
        return [
            SELECT Id
            FROM User
            WHERE FirstName = :RUN_AS_FIRST_NAME
              AND LastName = :RUN_AS_LAST_NAME
              AND IsActive = true
            LIMIT 1
        ];
    }

    @IsTest
    static void testGetCompetitiveInstalledBaseForFacilityAccount() {
        Id facilityA1Id = TestDataFactory.getCompetitiveInstalledBaseAccountIdBySourceSystemId(
            TestDataFactory.CIB_SOURCE_FACILITY_A1
        );

        System.runAs(getSysAdminUser()) {
            Test.startTest();
            CompetitiveInstalledBaseService.Response response =
                CompetitiveInstalledBaseController.getCompetitiveInstalledBase(facilityA1Id);
            Test.stopTest();

            System.assertEquals(1, response.totalAssetCount, 'Facility should show only its own asset.');
            System.assertEquals(1000, response.totalAssetValue);
            System.assertEquals(1, response.assets.size());
            System.assertEquals(
                'All Competitive Assets on this Facility',
                response.assetDetailHeading
            );
            System.assertEquals(
                TestDataFactory.CIB_FACILITY_A1_ORACLE_ID,
                response.assets[0].Account.OracleAddressId__c
            );
        }
    }

    @IsTest
    static void testGetCompetitiveInstalledBaseForImmediateParent() {
        Id parentAId = TestDataFactory.getCompetitiveInstalledBaseAccountIdBySourceSystemId(
            TestDataFactory.CIB_SOURCE_PARENT_A
        );
        Id facilityA1Id = TestDataFactory.getCompetitiveInstalledBaseAccountIdBySourceSystemId(
            TestDataFactory.CIB_SOURCE_FACILITY_A1
        );
        Id facilityA2Id = TestDataFactory.getCompetitiveInstalledBaseAccountIdBySourceSystemId(
            TestDataFactory.CIB_SOURCE_FACILITY_A2
        );

        System.runAs(getSysAdminUser()) {
            Test.startTest();
            CompetitiveInstalledBaseService.Response response =
                CompetitiveInstalledBaseController.getCompetitiveInstalledBase(parentAId);
            Test.stopTest();

            System.assertEquals(
                2,
                response.totalAssetCount,
                'Parent A rolls up its own assets and direct child facilities only.'
            );
            System.assertEquals(3000, response.totalAssetValue);
            System.assertEquals(
                'All Competitive Assets on this Customer and related Facilities',
                response.assetDetailHeading
            );

            Set<Id> facilityIds = new Set<Id>();
            for (Asset assetRecord : response.assets) {
                facilityIds.add(assetRecord.AccountId);
            }
            System.assert(facilityIds.contains(facilityA1Id));
            System.assert(facilityIds.contains(facilityA2Id));
        }
    }

    @IsTest
    static void testGetCompetitiveInstalledBaseForSecondParent() {
        Id parentBId = TestDataFactory.getCompetitiveInstalledBaseAccountIdBySourceSystemId(
            TestDataFactory.CIB_SOURCE_PARENT_B
        );

        System.runAs(getSysAdminUser()) {
            Test.startTest();
            CompetitiveInstalledBaseService.Response response =
                CompetitiveInstalledBaseController.getCompetitiveInstalledBase(parentBId);
            Test.stopTest();

            System.assertEquals(
                1,
                response.totalAssetCount,
                'Parent B rolls up its own assets and direct child facilities only.'
            );
            System.assertEquals(1500, response.totalAssetValue);
            System.assertEquals(
                'All Competitive Assets on this Customer and related Facilities',
                response.assetDetailHeading
            );
        }
    }

    @IsTest
    static void testGetCompetitiveInstalledBaseForIdnAffiliation() {
        Id idnAccountId = TestDataFactory.getCompetitiveInstalledBaseAccountIdBySourceSystemId(
            TestDataFactory.CIB_SOURCE_IDN
        );

        System.runAs(getSysAdminUser()) {
            Test.startTest();
            CompetitiveInstalledBaseService.Response response =
                CompetitiveInstalledBaseController.getCompetitiveInstalledBase(idnAccountId);
            Test.stopTest();

            System.assertEquals(
                3,
                response.totalAssetCount,
                'IDN should roll up affiliated customer parents and their facilities.'
            );
            System.assertEquals(4500, response.totalAssetValue);
            System.assertEquals(
                'All Competitive Assets on this IDN\'s affiliated Customers and related Facilities',
                response.assetDetailHeading
            );

            Map<String, CompetitiveInstalledBaseService.CompetitorSummary> summaryByCompetitor =
                new Map<String, CompetitiveInstalledBaseService.CompetitorSummary>();
            for (CompetitiveInstalledBaseService.CompetitorSummary competitorSummary :
                response.competitorSummaries) {
                summaryByCompetitor.put(competitorSummary.competitorName, competitorSummary);
            }

            System.assertEquals(2, summaryByCompetitor.size());
            System.assertEquals(2, summaryByCompetitor.get(TestDataFactory.CIB_COMPETITOR_ALPHA).assetCount);
            System.assertEquals(2500, summaryByCompetitor.get(TestDataFactory.CIB_COMPETITOR_ALPHA).totalValue);
            System.assertEquals(1, summaryByCompetitor.get(TestDataFactory.CIB_COMPETITOR_BETA).assetCount);
            System.assertEquals(2000, summaryByCompetitor.get(TestDataFactory.CIB_COMPETITOR_BETA).totalValue);
        }
    }

    @IsTest
    static void testGetCompetitiveInstalledBaseForGpoAffiliation() {
        Id gpoAccountId = TestDataFactory.getCompetitiveInstalledBaseAccountIdBySourceSystemId(
            TestDataFactory.CIB_SOURCE_GPO
        );

        System.runAs(getSysAdminUser()) {
            Test.startTest();
            CompetitiveInstalledBaseService.Response response =
                CompetitiveInstalledBaseController.getCompetitiveInstalledBase(gpoAccountId);
            Test.stopTest();

            System.assertEquals(
                3,
                response.totalAssetCount,
                'GPO should roll up affiliated customer parents and their facilities.'
            );
            System.assertEquals(4500, response.totalAssetValue);
            System.assertEquals(
                'All Competitive Assets on this GPO\'s affiliated Customers and related Facilities',
                response.assetDetailHeading
            );
        }
    }

    @IsTest
    static void testGetCompetitiveInstalledBaseForStandaloneFacility() {
        Id facilityStandaloneId = TestDataFactory.getCompetitiveInstalledBaseAccountIdBySourceSystemId(
            TestDataFactory.CIB_SOURCE_FACILITY_STANDALONE
        );

        System.runAs(getSysAdminUser()) {
            Test.startTest();
            CompetitiveInstalledBaseService.Response response =
                CompetitiveInstalledBaseController.getCompetitiveInstalledBase(facilityStandaloneId);
            Test.stopTest();

            System.assertEquals(1, response.totalAssetCount);
            System.assertEquals(500, response.totalAssetValue);
        }
    }

    @IsTest
    static void testGetCompetitiveInstalledBaseForUnrelatedAccount() {
        Id unrelatedAccountId = TestDataFactory.getCompetitiveInstalledBaseAccountIdBySourceSystemId(
            TestDataFactory.CIB_SOURCE_UNRELATED
        );

        System.runAs(getSysAdminUser()) {
            Test.startTest();
            CompetitiveInstalledBaseService.Response response =
                CompetitiveInstalledBaseController.getCompetitiveInstalledBase(unrelatedAccountId);
            Test.stopTest();

            System.assertEquals(0, response.totalAssetCount);
            System.assertEquals(0, response.assets.size());
        }
    }

    @IsTest
    static void testGetCompetitiveInstalledBaseNullAccountId() {
        System.runAs(getSysAdminUser()) {
            Test.startTest();
            CompetitiveInstalledBaseService.Response response =
                CompetitiveInstalledBaseController.getCompetitiveInstalledBase(null);
            Test.stopTest();

            System.assertEquals(0, response.totalAssetCount);
            System.assertEquals(0, response.assets.size());
        }
    }

    @IsTest
    static void testGetCompetitiveInstalledBaseException() {
        Id parentAId = TestDataFactory.getCompetitiveInstalledBaseAccountIdBySourceSystemId(
            TestDataFactory.CIB_SOURCE_PARENT_A
        );

        System.runAs(getSysAdminUser()) {
            Test.startTest();
            try {
                CompetitiveInstalledBaseService.throwExceptionForTest = true;
                CompetitiveInstalledBaseController.getCompetitiveInstalledBase(parentAId);
                System.assert(false, 'Expected CompetitiveInstalledBaseException.');
            } catch (CompetitiveInstalledBaseService.CompetitiveInstalledBaseException exceptionRecord) {
                System.assertEquals(
                    'Unable to load Competitive Installed Base.',
                    exceptionRecord.getMessage()
                );
            } finally {
                CompetitiveInstalledBaseService.throwExceptionForTest = false;
            }
            Test.stopTest();
        }
    }

    @IsTest
    static void testHierarchyResolutionForGrandparentDoesNotIncludeFacility() {
        Id grandparentAId = TestDataFactory.getCompetitiveInstalledBaseAccountIdBySourceSystemId(
            TestDataFactory.CIB_SOURCE_GRANDPARENT_A
        );
        Id facilityA1Id = TestDataFactory.getCompetitiveInstalledBaseAccountIdBySourceSystemId(
            TestDataFactory.CIB_SOURCE_FACILITY_A1
        );

        System.runAs(getSysAdminUser()) {
            Test.startTest();
            AccountHierarchyResolutionService.AccountScope accountScope =
                AccountHierarchyResolutionService.resolveAccountScope(grandparentAId);
            Test.stopTest();

            System.assertEquals(
                'All Competitive Assets on this Customer and related Facilities',
                accountScope.assetDetailHeading
            );
            System.assert(accountScope.accountIds.contains(grandparentAId));
            System.assert(
                !accountScope.accountIds.contains(facilityA1Id),
                'Grandparent should not roll up descendant facilities.'
            );
        }
    }
}