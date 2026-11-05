/**
 * @description GW-6017 - Tests for Finish Review Work Order on the CRSS debrief.
 */
@IsTest
private class WoDebriefCrssReviewControllerTest {
	private static WorkOrder insertWorkOrder(String token) {
		Account account = new Account(
			Name = 'CRSS Review ' + token,
			SourceSystemID__c = 'ORACLE-CRSS-REVIEW-' + token
		);
		insert account;
		WorkOrder workOrder = new WorkOrder(
			AccountId = account.Id,
			Subject = 'CRSS Review ' + token
		);
		insert workOrder;
		return workOrder;
	}

	private static WorkOrderLineItem newProductServicedLine(Id workOrderId, Boolean sendToRepairCenter) {
		return new WorkOrderLineItem(
			WorkOrderId = workOrderId,
			RecordTypeId = Schema.SObjectType.WorkOrderLineItem
				.getRecordTypeInfosByDeveloperName()
				.get('ProductServiced')
				.getRecordTypeId(),
			LineType__c = 'Product Serviced',
			SendToRepairCenter__c = sendToRepairCenter
		);
	}

	/**
	 * @description GW-6017 - A line waiting for a return order blocks the review.
	 */
	@IsTest
	static void checkWorkOrderReview_blocksWhileReturnOrderIsNeeded() {
		WorkOrder workOrder = insertWorkOrder(String.valueOf(Crypto.getRandomInteger()).replace('-', ''));
		insert newProductServicedLine(workOrder.Id, true);

		Test.startTest();
		WoDebriefCrssReviewController.WorkOrderReviewResult result =
			WoDebriefCrssReviewController.checkWorkOrderReview(workOrder.Id);
		Test.stopTest();

		System.assertEquals(false, result.canFinish, 'A line waiting for a return order should block the review.');
		System.assertEquals(1, result.returnOrderLines.size());
		System.assertEquals(
			false,
			[SELECT WorkOrderReviewDone__c FROM WorkOrder WHERE Id = :workOrder.Id].WorkOrderReviewDone__c
		);
	}

	/**
	 * @description GW-6017 - With no return order needed, the review passes and lists lines without pictures.
	 */
	@IsTest
	static void checkWorkOrderReview_passesAndListsMissingPictures() {
		WorkOrder workOrder = insertWorkOrder(String.valueOf(Crypto.getRandomInteger()).replace('-', ''));
		WorkOrderLineItem withPicture = newProductServicedLine(workOrder.Id, false);
		WorkOrderLineItem withoutPicture = newProductServicedLine(workOrder.Id, false);
		insert new List<WorkOrderLineItem>{ withPicture, withoutPicture };
		insert new ContentVersion(
			Title = WoDebriefIMSchildWOController.MOBILE_DEVICE_PICTURE_TITLE,
			PathOnClient = 'MobileDevicePicture.jpg',
			VersionData = Blob.valueOf('crss-review-photo'),
			FirstPublishLocationId = withPicture.Id
		);

		Test.startTest();
		WoDebriefCrssReviewController.WorkOrderReviewResult result =
			WoDebriefCrssReviewController.checkWorkOrderReview(workOrder.Id);
		Test.stopTest();

		System.assertEquals(true, result.canFinish);
		System.assertEquals(0, result.returnOrderLines.size());
		System.assertEquals(1, result.linesMissingPictures.size(), 'Only the line without a picture should be listed.');
		System.assertEquals(
			true,
			[SELECT WorkOrderReviewDone__c FROM WorkOrder WHERE Id = :workOrder.Id].WorkOrderReviewDone__c
		);
	}

	/**
	 * @description GW-6017 - A missing work order id is rejected.
	 */
	@IsTest
	static void checkWorkOrderReview_requiresWorkOrder() {
		Boolean thrown = false;
		try {
			WoDebriefCrssReviewController.checkWorkOrderReview(null);
		} catch (AuraHandledException ex) {
			thrown = true;
		}
		System.assert(thrown, 'A missing work order should be rejected.');
	}
}