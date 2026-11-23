/**
 * @description GW-5310 - Current Device and Instrument Work Order list.
 */
@IsTest
private class CurrentWorkOrderStatusControllerTest {
    @IsTest
    static void getCurrentWorkOrderSummaries_returnsOpenDeviceAndInstrumentOnly() {
        Account account = new Account(
            Name = 'GW5310 Summary Account',
            SystemID__c = 'GW5310-SUM',
            SourceSystemID__c = 'GW5310-SUM',
            OrgIDs__c = '82'
        );
        insert account;

        Map<String, Schema.RecordTypeInfo> recordTypes = Schema.SObjectType.WorkOrder
            .getRecordTypeInfosByDeveloperName();
        Id deviceTypeId = recordTypes.get('RepairCenterDevices').getRecordTypeId();
        Id instrumentTypeId = recordTypes.get('RepairCenterInstruments').getRecordTypeId();
        Id otherTypeId = recordTypes.get('RepairCenterOther').getRecordTypeId();

        WorkOrder deviceWorkOrder = new WorkOrder(
            Subject = 'GW5310 Summary Device',
            Status = 'Received',
            AccountId = account.Id,
            RecordTypeId = deviceTypeId
        );
        WorkOrder instrumentWorkOrder = new WorkOrder(
            Subject = 'GW5310 Summary Instrument',
            Status = 'Received',
            AccountId = account.Id,
            RecordTypeId = instrumentTypeId
        );
        WorkOrder closedWorkOrder = new WorkOrder(
            Subject = 'GW5310 Summary Closed',
            Status = 'Closed',
            AccountId = account.Id,
            RecordTypeId = deviceTypeId
        );
        WorkOrder otherWorkOrder = new WorkOrder(
            Subject = 'GW5310 Summary Other',
            Status = 'Received',
            AccountId = account.Id,
            RecordTypeId = otherTypeId
        );
        insert new List<WorkOrder>{
            deviceWorkOrder,
            instrumentWorkOrder,
            closedWorkOrder,
            otherWorkOrder
        };

        Test.startTest();
        List<WorkOrder> results = CurrentWorkOrderStatusController.getCurrentWorkOrderSummaries();
        Test.stopTest();

        Map<Id, WorkOrder> resultsById = new Map<Id, WorkOrder>(results);
        WorkOrder listedDevice = resultsById.get(deviceWorkOrder.Id);
        WorkOrder listedInstrument = resultsById.get(instrumentWorkOrder.Id);

        Assert.isNotNull(listedDevice, 'Open Device Work Order should be listed');
        Assert.areEqual('Received', listedDevice.Status, 'Device status should be returned');
        Assert.isTrue(
            String.isNotBlank(listedDevice.WorkOrderNumber),
            'Device Work Order Number should be returned'
        );
        Assert.areEqual(
            'RepairCenterDevices',
            listedDevice.RecordType.DeveloperName,
            'Device record type should be returned'
        );
        Assert.isNotNull(listedInstrument, 'Open Instrument Work Order should be listed');
        Assert.areEqual('Received', listedInstrument.Status, 'Instrument status should be returned');
        Assert.isFalse(
            resultsById.containsKey(closedWorkOrder.Id),
            'Closed Work Order should be omitted'
        );
        Assert.isFalse(
            resultsById.containsKey(otherWorkOrder.Id),
            'Repair Center Other Work Orders should be omitted'
        );
    }
}