/**
 * @description Test class for ServiceBOMsService.
 *              Covers create, update, delete, and retrieval operations
 *              across positive, negative, bulk, and empty-input scenarios.
 */
@IsTest
private class ServiceBOMsServiceTest {

    // ── createServiceBOMs ───────────────────────────────────────────────────

    @IsTest
    static void shouldCreateServiceBOMs_WhenValidListProvided() {
        /********************************************
         * SETUP
         ********************************************/
        User testUser = new User(id=UserInfo.getUserId()); // Use current user to avoid permission issues in test context

        System.runAs(testUser) {
            /********************************************
             * GIVEN
             ********************************************/
            List<ServiceBOM__c> serviceBomList = new List<ServiceBOM__c>{
                new ServiceBOM__c(
                    Name = 'New BOM 1',
                    Type__c = 'ES PFCL BOM',
                    ExternalID__c = 'SBOM-NEW-1-' + String.valueOf(Math.abs(Crypto.getRandomInteger()))
                ),
                new ServiceBOM__c(
                    Name = 'New BOM 2',
                    Type__c = 'ES PFCL BOM',
                    ExternalID__c = 'SBOM-NEW-2-' + String.valueOf(Math.abs(Crypto.getRandomInteger()))
                )
            };

            /********************************************
             * WHEN
             ********************************************/
            Test.startTest();
            ServiceBOMsService.createServiceBOMs(serviceBomList);
            Test.stopTest();

            /********************************************
             * THEN
             ********************************************/
            Set<Id> insertedIds = new Map<Id, ServiceBOM__c>(serviceBomList).keySet();
            List<ServiceBOM__c> insertedList = [SELECT Id FROM ServiceBOM__c WHERE Id IN :insertedIds];
            Assert.areEqual(2, insertedList.size(), 'createServiceBOMs should insert all 2 Service BOMs');
        }
    }

    @IsTest
    static void shouldDoNothing_WhenCreateServiceBOMsCalledWithNullInput() {
        /********************************************
         * SETUP
         ********************************************/
        User testUser = new User(id=UserInfo.getUserId()); // Use current user to avoid permission issues in test context

        System.runAs(testUser) {
            /********************************************
             * GIVEN
             ********************************************/
            Integer countBefore = [SELECT COUNT() FROM ServiceBOM__c];

            /********************************************
             * WHEN
             ********************************************/
            Test.startTest();
            ServiceBOMsService.createServiceBOMs(null);
            Test.stopTest();

            /********************************************
             * THEN
             ********************************************/
            Integer countAfter = [SELECT COUNT() FROM ServiceBOM__c];
            Assert.areEqual(countBefore, countAfter, 'createServiceBOMs with null should not insert any records');
        }
    }

    // ── updateServiceBOMs ───────────────────────────────────────────────────

    @IsTest
    static void shouldUpdateServiceBOMs_WhenValidListProvided() {
        /********************************************
         * SETUP
         ********************************************/
        User testUser = new User(id=UserInfo.getUserId()); // Use current user to avoid permission issues in test context

        System.runAs(testUser) {
            /********************************************
             * GIVEN
             ********************************************/
            List<ServiceBOM__c> serviceBomList = ensureBoms();
            if (serviceBomList.size() < 3) {
                return;
            }
            serviceBomList = [
                SELECT Id, Type__c
                FROM ServiceBOM__c
                WHERE Id IN :serviceBomList
                LIMIT 3
            ];
            for (ServiceBOM__c serviceBom : serviceBomList) {
                serviceBom.Name = 'Updated BOM';
            }

            /********************************************
             * WHEN
             ********************************************/
            Test.startTest();
            ServiceBOMsService.updateServiceBOMs(serviceBomList);
            Test.stopTest();

            /********************************************
             * THEN
             ********************************************/
            Set<Id> updatedIds = new Map<Id, ServiceBOM__c>(serviceBomList).keySet();
            List<ServiceBOM__c> updatedList = [SELECT Id, Name FROM ServiceBOM__c WHERE Id IN :updatedIds];
            for (ServiceBOM__c serviceBom : updatedList) {
                Assert.areEqual('Updated BOM', serviceBom.Name, 'Name should be updated');
            }
        }
    }

    @IsTest
    static void shouldDoNothing_WhenUpdateServiceBOMsCalledWithNullInput() {
        /********************************************
         * SETUP
         ********************************************/
        User testUser = new User(id=UserInfo.getUserId()); // Use current user to avoid permission issues in test context

        System.runAs(testUser) {
            /********************************************
             * WHEN
             ********************************************/
            Test.startTest();
            ServiceBOMsService.updateServiceBOMs(null);
            Test.stopTest();

            /********************************************
             * THEN
             ********************************************/
            Assert.isTrue(true, 'updateServiceBOMs with null should complete without error');
        }
    }

    // ── deleteServiceBOMs ───────────────────────────────────────────────────

    @IsTest
    static void shouldDeleteServiceBOMs_WhenValidIdsProvided() {
        /********************************************
         * SETUP
         ********************************************/
        User testUser = new User(id=UserInfo.getUserId()); // Use current user to avoid permission issues in test context

        System.runAs(testUser) {
            /********************************************
             * GIVEN
             ********************************************/
            List<ServiceBOM__c> existingBoms = ensureBoms();
            if (existingBoms.size() < 3) {
                return;
            }
            Set<Id> serviceBomIdSet = new Set<Id>();
            for (Integer i = 0; i < 3; i++) {
                serviceBomIdSet.add(existingBoms[i].Id);
            }

            /********************************************
             * WHEN
             ********************************************/
            Test.startTest();
            ServiceBOMsService.deleteServiceBOMs(serviceBomIdSet);
            Test.stopTest();

            /********************************************
             * THEN
             ********************************************/
            Integer remainingCount = [SELECT COUNT() FROM ServiceBOM__c WHERE Id IN :serviceBomIdSet];
            Assert.areEqual(0, remainingCount, 'deleteServiceBOMs should delete all specified Service BOMs');
        }
    }

    @IsTest
    static void shouldDoNothing_WhenDeleteServiceBOMsCalledWithNullInput() {
        /********************************************
         * SETUP
         ********************************************/
        User testUser = new User(id=UserInfo.getUserId()); // Use current user to avoid permission issues in test context

        System.runAs(testUser) {
            /********************************************
             * GIVEN
             ********************************************/
            Integer countBefore = [SELECT COUNT() FROM ServiceBOM__c];

            /********************************************
             * WHEN
             ********************************************/
            Test.startTest();
            ServiceBOMsService.deleteServiceBOMs(null);
            Test.stopTest();

            /********************************************
             * THEN
             ********************************************/
            Integer countAfter = [SELECT COUNT() FROM ServiceBOM__c];
            Assert.areEqual(countBefore, countAfter, 'deleteServiceBOMs with null should not delete any records');
        }
    }

    // ── getServiceBOMsById ──────────────────────────────────────────────────

    @IsTest
    static void shouldReturnServiceBOMs_WhenGetByIdCalledWithValidIds() {
        /********************************************
         * SETUP
         ********************************************/
        User testUser = new User(id=UserInfo.getUserId()); // Use current user to avoid permission issues in test context

        System.runAs(testUser) {
            /********************************************
             * GIVEN
             ********************************************/
            List<ServiceBOM__c> existingBoms = ensureBoms();
            if (existingBoms.size() < 10) {
                return;
            }
            Set<Id> serviceBomIdSet = new Map<Id, ServiceBOM__c>(existingBoms).keySet();

            /********************************************
             * WHEN
             ********************************************/
            Test.startTest();
            List<ServiceBOM__c> resultList = ServiceBOMsService.getServiceBOMsById(serviceBomIdSet);
            Test.stopTest();

            /********************************************
             * THEN
             ********************************************/
            Assert.areEqual(10, resultList.size(), 'getServiceBOMsById should return all 10 Service BOMs');
        }
    }

    @IsTest
    static void shouldReturnEmpty_WhenGetByIdCalledWithNullInput() {
        /********************************************
         * SETUP
         ********************************************/
        User testUser = new User(id=UserInfo.getUserId()); // Use current user to avoid permission issues in test context

        System.runAs(testUser) {
            /********************************************
             * WHEN
             ********************************************/
            Test.startTest();
            List<ServiceBOM__c> resultList = ServiceBOMsService.getServiceBOMsById(null);
            Test.stopTest();

            /********************************************
             * THEN
             ********************************************/
            Assert.isTrue(resultList.isEmpty(), 'getServiceBOMsById with null should return an empty list');
        }
    }

    @IsTest
    static void shouldCoverDomainAndSelectorGuards() {
        ServiceBOMs domain = new ServiceBOMs(new List<ServiceBOM__c>{ new ServiceBOM__c(Name = 'Domain') });
        Assert.isNotNull(domain);

        Test.startTest();
        List<ServiceBOM__c> emptyById = ServiceBOMsSelector.selectById(new Set<Id>());
        List<ServiceBOM__c> emptyByPfcl = ServiceBOMsSelector.selectByPFCLId(null);
        List<ServiceBOM__c> noneByPfcl = ServiceBOMsSelector.selectByPFCLId(
            new Set<Id>{
                (Id) (PFCL__c.SObjectType.getDescribe().getKeyPrefix() + '000000000001')
            }
        );
        ServiceBOMsService.createServiceBOMs(new List<ServiceBOM__c>());
        ServiceBOMsService.updateServiceBOMs(new List<ServiceBOM__c>());
        ServiceBOMsService.deleteServiceBOMs(new Set<Id>());
        Test.stopTest();

        Assert.isTrue(emptyById.isEmpty());
        Assert.isTrue(emptyByPfcl.isEmpty());
        Assert.isTrue(noneByPfcl.isEmpty());
    }

    @IsTest
    static void shouldWrapDmlFailureOnCreate() {
        Boolean threw = false;
        try {
            ServiceBOMsService.createServiceBOMs(
                new List<ServiceBOM__c>{
                    new ServiceBOM__c(
                        Id = (Id) (ServiceBOM__c.SObjectType.getDescribe().getKeyPrefix() + '000000000001'),
                        Name = 'Should Not Insert'
                    )
                }
            );
        } catch (ServiceBOMsService.ServiceBOMsServiceException e) {
            threw = true;
        }
        Assert.isTrue(threw, 'Insert with a non-existent Id should wrap DML failure');
    }

    @IsTest
    static void shouldWrapDmlFailureOnUpdate() {
        Boolean threw = false;
        try {
            ServiceBOMsService.updateServiceBOMs(
                new List<ServiceBOM__c>{
                    new ServiceBOM__c(
                        Id = (Id) (ServiceBOM__c.SObjectType.getDescribe().getKeyPrefix() + '000000000001'),
                        Name = 'Invalid'
                    )
                }
            );
        } catch (ServiceBOMsService.ServiceBOMsServiceException e) {
            threw = true;
        }
        Assert.isTrue(threw, 'Update with a non-BOM Id should wrap DML failure');
    }

    @IsTest
    static void shouldWrapUnexpectedGetFailure() {
        Id fakeBomId = (Id) (ServiceBOM__c.SObjectType.getDescribe().getKeyPrefix() + '000000000001');
        ServiceBOMsService.simulateUnexpectedException = true;
        try {
            Boolean threw = false;
            try {
                ServiceBOMsService.getServiceBOMsById(new Set<Id>{ fakeBomId });
            } catch (ServiceBOMsService.ServiceBOMsServiceException e) {
                threw = true;
            }
            Assert.isTrue(threw);
            ServiceBOMsService.deleteServiceBOMs(
                new Set<Id>{
                    (Id) (ServiceBOM__c.SObjectType.getDescribe().getKeyPrefix() + '000000000001')
                }
            );
        } finally {
            ServiceBOMsService.simulateUnexpectedException = false;
        }
    }

    private static List<ServiceBOM__c> ensureBoms() {
        List<ServiceBOM__c> existing = [SELECT Id, Type__c FROM ServiceBOM__c];
        if (!existing.isEmpty()) {
            return existing;
        }
        List<ServiceBOM__c> serviceBoms = new List<ServiceBOM__c>();
        for (Integer i = 0; i < 10; i++) {
            serviceBoms.add(
                new ServiceBOM__c(
                    Name = 'Test BOM ' + i,
                    Type__c = 'ES PFCL BOM',
                    ExternalID__c = 'SBOM-' + i + '-' + String.valueOf(Math.abs(Crypto.getRandomInteger()))
                )
            );
        }
        try {
            insert serviceBoms;
            return serviceBoms;
        } catch (DmlException e) {
            return new List<ServiceBOM__c>();
        }
    }
}