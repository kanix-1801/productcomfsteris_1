@IsTest(SeeAllData=true)
private class OverlayDavidTerrTest {
    @IsTest
    static void searchTerr001AsDavid() {
        User david = [SELECT Id FROM User WHERE Id = '005Ou00000QoumsIAB' LIMIT 1];
        System.runAs(david) {
            try {
                List<OverlayAssignmentController.TerritoryWrapper> territories =
                    OverlayAssignmentController.searchTerritories('terr-001');
                System.debug(LoggingLevel.ERROR, 'TERR COUNT=' + territories.size());
            } catch (Exception e) {
                System.debug(LoggingLevel.ERROR, 'TERR ERR=' + e.getTypeName() + ' :: ' + e.getMessage());
            }

            try {
                List<OverlayAssignmentController.AccountWrapper> accounts =
                    OverlayAssignmentController.searchAccounts(null, null, new List<String>{ 'TERR-001' });
                System.debug(LoggingLevel.ERROR, 'ACCT COUNT=' + accounts.size());
            } catch (Exception e) {
                System.debug(LoggingLevel.ERROR, 'ACCT ERR=' + e.getTypeName() + ' :: ' + e.getMessage());
            }

            try {
                Integer olcCount = [
                    SELECT COUNT()
                    FROM OrderLineContact__c
                    WHERE TerritoryID__c = 'TERR-001'
                ];
                System.debug(LoggingLevel.ERROR, 'OLC COUNT AS DAVID=' + olcCount);
            } catch (Exception e) {
                System.debug(LoggingLevel.ERROR, 'OLC ERR=' + e.getTypeName() + ' :: ' + e.getMessage());
            }

            try {
                List<OrderLineContact__c> secured = [
                    SELECT TerritoryID__c, TASAddressId__c
                    FROM OrderLineContact__c
                    WHERE TerritoryID__c = 'TERR-001'
                    WITH SECURITY_ENFORCED
                    LIMIT 5
                ];
                System.debug(LoggingLevel.ERROR, 'OLC SECURED=' + secured.size());
            } catch (Exception e) {
                System.debug(LoggingLevel.ERROR, 'OLC SECURED ERR=' + e.getTypeName() + ' :: ' + e.getMessage());
            }
        }
        System.assert(true);
    }
}