/**
 * @author PWC Developer
 * @date 2026/11/13
 *
 * @group Dealer Portal
 *
 * @description Tests for DealerPortalAccessController.
 */
@IsTest
private class DealerPortalAccessControllerTest {
    @IsTest
    static void returnsFalseWhenPermissionSetIsNotAssigned() {
        User userRecord = createUser();

        System.runAs(userRecord) {
            System.assertEquals(false, DealerPortalAccessController.hasDealerQuoteAccess());
        }
    }

    @IsTest
    static void returnsFalseWhenNonDealerManagerIsAssigned() {
        User userRecord = createUser();
        assignPermissionSet(userRecord.Id, 'DealerAdmin');

        System.runAs(userRecord) {
            System.assertEquals(false, DealerPortalAccessController.hasDealerQuoteAccess());
        }
    }

    @IsTest
    static void returnsTrueWhenDealerManagerPsIsAssigned() {
        User userRecord = createUser();
        assignPermissionSet(userRecord.Id, 'DealerManagerPS');

        System.runAs(userRecord) {
            System.assertEquals(true, DealerPortalAccessController.hasDealerQuoteAccess());
        }
    }

    private static void assignPermissionSet(Id userId, String permissionSetName) {
        PermissionSet permissionSetRecord = [
            SELECT Id
            FROM PermissionSet
            WHERE Name = :permissionSetName
            LIMIT 1
        ];
        insert new PermissionSetAssignment(
            AssigneeId = userId,
            PermissionSetId = permissionSetRecord.Id
        );
    }

    private static User createUser() {
        Profile sysAdminProfile = [
            SELECT Id
            FROM Profile
            WHERE Name = 'System Administrator'
            LIMIT 1
        ];
        Long uniqueSeed = System.currentTimeMillis();
        User userRecord = new User(
            FirstName = 'Dealer',
            LastName = 'AccessTest',
            Alias = ('dpa' + String.valueOf(Math.abs(Crypto.getRandomInteger()))).left(8),
            Email = 'dealerportalaccess+' + uniqueSeed + '@test.invalid',
            Username = 'dealerportalaccess+' + uniqueSeed + '@test.invalid',
            CommunityNickname = ('dpa' + uniqueSeed).left(40),
            ProfileId = sysAdminProfile.Id,
            TimeZoneSidKey = 'America/New_York',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            EmployeeNumber__c = 'DPA' + String.valueOf(Math.abs(Crypto.getRandomInteger())),
            FederationIdentifier = 'DPA' + String.valueOf(Math.abs(Crypto.getRandomInteger())),
            IsActive = true
        );
        insert userRecord;
        return userRecord;
    }
}