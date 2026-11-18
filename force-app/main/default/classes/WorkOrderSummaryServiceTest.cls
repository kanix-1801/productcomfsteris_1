/**
 * @author Uptima
 * @date 2026-11-13
 * @group Repair Center
 * @description GW-5287 tests for WorkOrderSummaryService.
 */
@IsTest
private class WorkOrderSummaryServiceTest {
	private static final String PARENT_SUBJECT = 'WO Summary Parent';
	private static final String CHILD_SUBJECT = 'WO Summary Child';
	private static final String INVALID_MESSAGE =
		'The input provided is invalid.  Please provide a valid Id for a Device or Instrument Work Order.';

	@TestSetup
	static void setupData() {
		System.runAs(new User(Id = UserInfo.getUserId())) {
			adb_Account account = new adb_Account();
			account.persist();

			adb_WorkOrder parentBuilder = new adb_WorkOrder()
				.subject(PARENT_SUBJECT)
				.status('Received')
				.account(account)
				.setRecordType('RepairCenterInstruments');
			parentBuilder.persist();

			WorkOrder parent = (WorkOrder) parentBuilder.record;
			parent.QuantityReceived__c = 2;
			parent.ScheduledShipDate__c = Date.today().addDays(3);
			parent.ShipComplete__c = false;
			parent.IsPriorityRepair__c = true;
			Database.update(parent, AccessLevel.SYSTEM_MODE);

			adb_WorkOrder childBuilder = new adb_WorkOrder()
				.subject(CHILD_SUBJECT)
				.status('Repair')
				.account(account)
				.setRecordType('RepairCenterInstruments');
			childBuilder.persist();

			WorkOrder child = (WorkOrder) childBuilder.record;
			child.ParentWorkOrderId = parent.Id;
			child.QuantityReceived__c = 1;
			child.TurnTime__c = 4;
			child.ScheduledShipDate__c = Date.today().addDays(3);
			Database.update(child, AccessLevel.SYSTEM_MODE);

			Id wahRecordTypeId = Schema.SObjectType.WOAssignmentHistory__c
				.getRecordTypeInfosByDeveloperName()
				.get('RepairCenter')
				?.getRecordTypeId();
			WOAssignmentHistory__c techAssignment = new WOAssignmentHistory__c(
				WorkOrder__c = child.Id,
				Type__c = 'Technician',
				Technician__c = UserInfo.getUserId(),
				StartDateTime__c = Datetime.now().addHours(-2)
			);
			if (wahRecordTypeId != null) {
				techAssignment.RecordTypeId = wahRecordTypeId;
			}
			insert techAssignment;
		}
	}

	@IsTest
	static void testGetSummaryWhenParentNumberProvidedReturnsChildren() {
		WorkOrder parent = [
			SELECT Id, WorkOrderNumber
			FROM WorkOrder
			WHERE Subject = :PARENT_SUBJECT
			LIMIT 1
		];

		Test.startTest();
		WorkOrderSummaryService.WorkOrderSummaryWorkspace workspace =
			WorkOrderSummaryService.getSummary(parent.WorkOrderNumber);
		Test.stopTest();

		Assert.isNotNull(workspace, 'Workspace should be returned');
		Assert.areEqual(parent.Id, workspace.parentWorkOrderId);
		Assert.areEqual('RepairCenterInstruments', workspace.parentRecordTypeDeveloperName);
		Assert.areEqual(1, workspace.totalChildWorkOrders);
		Assert.areEqual(true, workspace.priorityRepair);
		Assert.areEqual(1, workspace.children.size());
		Assert.areEqual('Repair', workspace.children[0].status);
		Assert.isFalse(
			String.isBlank(workspace.children[0].currentTechnician),
			'Open technician assignment should populate Current Technician'
		);
		Assert.areEqual(1, workspace.statusCounts.size());
		Assert.areEqual('Repair', workspace.statusCounts[0].status);
		Assert.areEqual(1, workspace.statusCounts[0].count);
	}

	@IsTest
	static void testGetSummaryWhenChildIdProvidedResolvesParent() {
		WorkOrder child = [
			SELECT Id, ParentWorkOrderId
			FROM WorkOrder
			WHERE Subject = :CHILD_SUBJECT
			LIMIT 1
		];

		Test.startTest();
		WorkOrderSummaryService.WorkOrderSummaryWorkspace workspace =
			WorkOrderSummaryService.getSummary(child.Id);
		Test.stopTest();

		Assert.areEqual(child.ParentWorkOrderId, workspace.parentWorkOrderId);
		Assert.areEqual(1, workspace.totalChildWorkOrders);
	}

	@IsTest
	static void testGetSummaryWhenInvalidInputThrows() {
		Boolean threw = false;
		Test.startTest();
		try {
			WorkOrderSummaryService.getSummary('NOT-A-REAL-WO');
		} catch (WorkOrderSummaryService.WorkOrderSummaryServiceException e) {
			threw = true;
			Assert.areEqual(INVALID_MESSAGE, e.getMessage());
		}
		Test.stopTest();
		Assert.isTrue(threw, 'Invalid input should throw');
	}

	@IsTest
	static void testGetSummaryWhenBlankInputThrows() {
		Boolean threw = false;
		Test.startTest();
		try {
			WorkOrderSummaryService.getSummary('  ');
		} catch (WorkOrderSummaryService.WorkOrderSummaryServiceException e) {
			threw = true;
			Assert.areEqual(INVALID_MESSAGE, e.getMessage());
		}
		Test.stopTest();
		Assert.isTrue(threw, 'Blank input should throw');
	}

	@IsTest
	static void testGetSummaryWhenOpenRackAssignmentPopulatesCurrentRack() {
		WorkOrder parent = [
			SELECT Id
			FROM WorkOrder
			WHERE Subject = :PARENT_SUBJECT
			LIMIT 1
		];

		adb_Location rackBuilder = new adb_Location()
			.name('WO-SUMMARY-OPEN-RACK')
			.locationType('Rack');
		Schema.Location rack = (Schema.Location) rackBuilder.record;
		rack.TrackRackAssignmentHistory__c = true;
		rackBuilder.persist();

		adb_WorkOrder childBuilder = new adb_WorkOrder()
			.subject('WO Summary Rack Child')
			.status('Repair')
			.account(new adb_Account())
			.setRecordType('RepairCenterInstruments');
		childBuilder.persist();
		WorkOrder child = (WorkOrder) childBuilder.record;
		child.ParentWorkOrderId = parent.Id;
		child.Rack__c = rack.Id;
		Database.update(child, AccessLevel.SYSTEM_MODE);

		Id wahRecordTypeId = Schema.SObjectType.WOAssignmentHistory__c
			.getRecordTypeInfosByDeveloperName()
			.get('RepairCenter')
			?.getRecordTypeId();
		WOAssignmentHistory__c rackAssignment = new WOAssignmentHistory__c(
			WorkOrder__c = child.Id,
			Type__c = 'Rack',
			Rack__c = rack.Id,
			StartDateTime__c = Datetime.now().addHours(-1)
		);
		if (wahRecordTypeId != null) {
			rackAssignment.RecordTypeId = wahRecordTypeId;
		}
		insert rackAssignment;

		Test.startTest();
		WorkOrderSummaryService.WorkOrderSummaryWorkspace workspace =
			WorkOrderSummaryService.getSummary(parent.Id);
		Test.stopTest();

		WorkOrderSummaryService.ChildWorkOrderSummary rackChild;
		for (WorkOrderSummaryService.ChildWorkOrderSummary row : workspace.children) {
			if (row.workOrderId == child.Id) {
				rackChild = row;
				break;
			}
		}
		Assert.isNotNull(rackChild, 'Rack child should be in summary');
		Assert.areEqual(
			'WO-SUMMARY-OPEN-RACK',
			rackChild.currentLocation,
			'Open Rack assignment should populate Current Rack'
		);
		Assert.isTrue(
			String.isBlank(rackChild.currentTechnician),
			'Open Rack assignment should leave Current Technician blank'
		);
	}

	@IsTest
	static void testGetSummaryWhenNoOpenAssignmentUsesWorkOrderRack() {
		WorkOrder parent = [
			SELECT Id
			FROM WorkOrder
			WHERE Subject = :PARENT_SUBJECT
			LIMIT 1
		];

		adb_Location rackBuilder = new adb_Location()
			.name('WO-SUMMARY-FALLBACK-RACK')
			.locationType('Rack');
		Schema.Location rack = (Schema.Location) rackBuilder.record;
		rack.TrackRackAssignmentHistory__c = true;
		rackBuilder.persist();

		adb_WorkOrder childBuilder = new adb_WorkOrder()
			.subject('WO Summary Fallback Rack Child')
			.status('Repair')
			.account(new adb_Account())
			.setRecordType('RepairCenterInstruments');
		childBuilder.persist();
		WorkOrder child = (WorkOrder) childBuilder.record;
		child.ParentWorkOrderId = parent.Id;
		child.Rack__c = rack.Id;
		Database.update(child, AccessLevel.SYSTEM_MODE);

		Test.startTest();
		WorkOrderSummaryService.WorkOrderSummaryWorkspace workspace =
			WorkOrderSummaryService.getSummary(parent.Id);
		Test.stopTest();

		WorkOrderSummaryService.ChildWorkOrderSummary fallbackChild;
		for (WorkOrderSummaryService.ChildWorkOrderSummary row : workspace.children) {
			if (row.workOrderId == child.Id) {
				fallbackChild = row;
				break;
			}
		}
		Assert.isNotNull(fallbackChild, 'Fallback rack child should be in summary');
		Assert.areEqual(
			'WO-SUMMARY-FALLBACK-RACK',
			fallbackChild.currentLocation,
			'Work Order Rack__c should populate Current Rack when no open WAH'
		);
		Assert.isTrue(
			String.isBlank(fallbackChild.currentTechnician),
			'Current Technician should stay blank when only WO Rack fallback applies'
		);
	}
}