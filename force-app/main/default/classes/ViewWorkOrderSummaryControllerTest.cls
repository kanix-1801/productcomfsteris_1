/**
 * @author Uptima
 * @date 2026-11-13
 * @group Repair Center
 * @description GW-5287 tests for ViewWorkOrderSummaryController.
 */
@IsTest
private class ViewWorkOrderSummaryControllerTest {
	private static final String PARENT_SUBJECT = 'VWO Summary Parent';

	@TestSetup
	static void setupData() {
		System.runAs(new User(Id = UserInfo.getUserId())) {
			adb_Account account = new adb_Account();
			account.persist();

			adb_WorkOrder parentBuilder = new adb_WorkOrder()
				.subject(PARENT_SUBJECT)
				.status('Received')
				.account(account)
				.setRecordType('RepairCenterDevices');
			parentBuilder.persist();
		}
	}

	@IsTest
	static void testGetSummaryWhenValidInputReturnsWorkspace() {
		WorkOrder parent = [
			SELECT Id, WorkOrderNumber
			FROM WorkOrder
			WHERE Subject = :PARENT_SUBJECT
			LIMIT 1
		];

		Test.startTest();
		WorkOrderSummaryService.WorkOrderSummaryWorkspace workspace =
			ViewWorkOrderSummaryController.getSummary(parent.WorkOrderNumber);
		Test.stopTest();

		Assert.isNotNull(workspace);
		Assert.areEqual(parent.Id, workspace.parentWorkOrderId);
	}

	@IsTest
	static void testGetSummaryWhenInvalidInputThrowsAuraHandledException() {
		Boolean threw = false;
		Test.startTest();
		try {
			ViewWorkOrderSummaryController.getSummary('INVALID');
		} catch (AuraHandledException e) {
			threw = true;
			Assert.isTrue(
				e.getMessage().contains('invalid') || String.isNotBlank(e.getMessage()),
				'Expected AuraHandledException message'
			);
		}
		Test.stopTest();
		Assert.isTrue(threw, 'Invalid input should throw AuraHandledException');
	}
}