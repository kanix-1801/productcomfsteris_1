/**
 * @author Uptima
 * @date 2026-11-13
 * @group Repair Center
 * @description GW-5287 tests for ViewWorkOrderSummaryController.
 */
@IsTest
private class ViewWorkOrderSummaryControllerTest {
	private static final String PARENT_SUBJECT = 'VWO Summary Parent';

	/**
	 * @description GW-5287 - Stub client that throws a non-service exception for catch coverage.
	 */
	private class ThrowingSummaryClient implements ViewWorkOrderSummaryController.ISummaryClient {
		/**
		 * @description GW-5287 - Always throws CalloutException.
		 * @param workOrderInput Unused
		 * @return Never returns
		 */
		public WorkOrderSummaryService.WorkOrderSummaryWorkspace getSummary(String workOrderInput) {
			throw new CalloutException('Forced test exception');
		}
	}

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

	@IsTest
	static void testGetSummaryWhenUnexpectedExceptionThrowsAuraHandledException() {
		ViewWorkOrderSummaryController.clientOverride = new ThrowingSummaryClient();
		Boolean threw = false;

		Test.startTest();
		try {
			ViewWorkOrderSummaryController.getSummary('ANY');
		} catch (AuraHandledException e) {
			threw = true;
			Assert.isTrue(
				String.isNotBlank(e.getMessage()),
				'Expected AuraHandledException message'
			);
		} finally {
			ViewWorkOrderSummaryController.clientOverride = null;
		}
		Test.stopTest();

		Assert.isTrue(threw, 'Unexpected exception should throw AuraHandledException');
	}
}