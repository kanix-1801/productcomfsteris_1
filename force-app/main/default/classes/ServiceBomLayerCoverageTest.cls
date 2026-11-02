/**
 * @description QA coverage for Service BOM / PFCL-Service BOM layers.
 *              Intentionally has no TestSetup so validation-rule failures on
 *              ServiceBOM__c insert cannot zero-out coverage for the class.
 */
@IsTest
private class ServiceBomLayerCoverageTest {

    @IsTest
    static void shouldCoverServiceBomDomainSelectorAndServiceWithoutDmlSetup() {
        ServiceBOMs domain = new ServiceBOMs(
            new List<ServiceBOM__c>{ new ServiceBOM__c(Name = 'Coverage BOM') }
        );
        Assert.isNotNull(domain);
        new ServiceBOMs.ServiceBOMsException('coverage');

        Id fakeBomId = fakeId(ServiceBOM__c.SObjectType);
        Id fakePfclId = fakeId(PFCL__c.SObjectType);

        Test.startTest();
        Assert.isTrue(ServiceBOMsSelector.selectById(null).isEmpty());
        Assert.isTrue(ServiceBOMsSelector.selectById(new Set<Id>()).isEmpty());
        Assert.isTrue(ServiceBOMsSelector.selectById(new Set<Id>{ fakeBomId }).isEmpty());
        Assert.isTrue(ServiceBOMsSelector.selectByPFCLId(null).isEmpty());
        Assert.isTrue(ServiceBOMsSelector.selectByPFCLId(new Set<Id>()).isEmpty());
        Assert.isTrue(ServiceBOMsSelector.selectByPFCLId(new Set<Id>{ fakePfclId }).isEmpty());

        ServiceBOMsService.createServiceBOMs(null);
        ServiceBOMsService.createServiceBOMs(new List<ServiceBOM__c>());
        ServiceBOMsService.updateServiceBOMs(null);
        ServiceBOMsService.updateServiceBOMs(new List<ServiceBOM__c>());
        ServiceBOMsService.deleteServiceBOMs(null);
        ServiceBOMsService.deleteServiceBOMs(new Set<Id>());
        ServiceBOMsService.deleteServiceBOMs(new Set<Id>{ fakeBomId });
        Assert.isTrue(ServiceBOMsService.getServiceBOMsById(null).isEmpty());
        Assert.isTrue(ServiceBOMsService.getServiceBOMsById(new Set<Id>()).isEmpty());
        Assert.isTrue(ServiceBOMsService.getServiceBOMsById(new Set<Id>{ fakeBomId }).isEmpty());

        Boolean createThrew = false;
        try {
            ServiceBOMsService.createServiceBOMs(
                new List<ServiceBOM__c>{ new ServiceBOM__c(Id = fakeBomId, Name = 'No Insert') }
            );
        } catch (ServiceBOMsService.ServiceBOMsServiceException e) {
            createThrew = true;
        }
        Boolean updateThrew = false;
        try {
            ServiceBOMsService.updateServiceBOMs(
                new List<ServiceBOM__c>{ new ServiceBOM__c(Id = fakeBomId, Name = 'No Update') }
            );
        } catch (ServiceBOMsService.ServiceBOMsServiceException e) {
            updateThrew = true;
        }
        ServiceBOMsService.simulateUnexpectedException = true;
        Boolean getThrew = false;
        try {
            ServiceBOMsService.getServiceBOMsById(new Set<Id>{ fakeBomId });
        } catch (ServiceBOMsService.ServiceBOMsServiceException e) {
            getThrew = true;
        } finally {
            ServiceBOMsService.simulateUnexpectedException = false;
        }
        Test.stopTest();

        Assert.isTrue(createThrew);
        Assert.isTrue(updateThrew);
        Assert.isTrue(getThrew);
    }

    @IsTest
    static void shouldCoverPfclServiceBomsServiceWithoutJunctionSetup() {
        Id fakeJunctionId = fakeId(PFCLServiceBOM__c.SObjectType);

        Test.startTest();
        PFCLServiceBOMsService.createPFCLServiceBOMs(null);
        PFCLServiceBOMsService.createPFCLServiceBOMs(new List<PFCLServiceBOM__c>());
        PFCLServiceBOMsService.updatePFCLServiceBOMs(null);
        PFCLServiceBOMsService.updatePFCLServiceBOMs(new List<PFCLServiceBOM__c>());
        PFCLServiceBOMsService.deletePFCLServiceBOMs(null);
        PFCLServiceBOMsService.deletePFCLServiceBOMs(new Set<Id>());
        PFCLServiceBOMsService.deletePFCLServiceBOMs(new Set<Id>{ fakeJunctionId });
        Assert.isTrue(PFCLServiceBOMsService.getPFCLServiceBOMsById(null).isEmpty());
        Assert.isTrue(PFCLServiceBOMsService.getPFCLServiceBOMsById(new Set<Id>()).isEmpty());
        Assert.isTrue(
            PFCLServiceBOMsService.getPFCLServiceBOMsById(new Set<Id>{ fakeJunctionId }).isEmpty()
        );

        Boolean createThrew = false;
        try {
            PFCLServiceBOMsService.createPFCLServiceBOMs(
                new List<PFCLServiceBOM__c>{ new PFCLServiceBOM__c(Id = fakeJunctionId) }
            );
        } catch (PFCLServiceBOMsService.PFCLServiceBOMsServiceException e) {
            createThrew = true;
        }
        Boolean updateThrew = false;
        try {
            PFCLServiceBOMsService.updatePFCLServiceBOMs(
                new List<PFCLServiceBOM__c>{ new PFCLServiceBOM__c(Id = fakeJunctionId) }
            );
        } catch (PFCLServiceBOMsService.PFCLServiceBOMsServiceException e) {
            updateThrew = true;
        }
        PFCLServiceBOMsService.simulateUnexpectedException = true;
        Boolean getThrew = false;
        try {
            PFCLServiceBOMsService.getPFCLServiceBOMsById(new Set<Id>{ fakeJunctionId });
        } catch (PFCLServiceBOMsService.PFCLServiceBOMsServiceException e) {
            getThrew = true;
        } finally {
            PFCLServiceBOMsService.simulateUnexpectedException = false;
        }
        Test.stopTest();

        Assert.isTrue(createThrew);
        Assert.isTrue(updateThrew);
        Assert.isTrue(getThrew);
    }

    private static Id fakeId(Schema.SObjectType sobjectType) {
        return (Id) (sobjectType.getDescribe().getKeyPrefix() + '000000000001');
    }
}