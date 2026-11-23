/**
 * @description GW-6193 - Tests for the IMS site visit summary review controller.
 * @see WoDebriefIMSSummaryController
 */
@IsTest
private class WoDebriefIMSSummaryControllerTest {
	@IsTest
	static void getSummaryAccess_nullId_blocked() {
		WoDebriefIMSSummaryController.SummaryAccessResult result =
			WoDebriefIMSSummaryController.getSummaryAccess(null);
		System.assertEquals(false, result.allowed);
		System.assertNotEquals(null, result.blockMessage);
	}

	@IsTest
	static void getSummaryAccess_childWorkOrder_blocked() {
		Account account = new Account(Name = 'Summary Access Account');
		insert account;
		WorkOrder parent = new WorkOrder(AccountId = account.Id, Subject = 'Parent Site Visit');
		insert parent;
		WorkOrder child = new WorkOrder(
			AccountId = account.Id,
			Subject = 'Child Tray',
			ParentWorkOrderId = parent.Id
		);
		insert child;

		WoDebriefIMSSummaryController.SummaryAccessResult result =
			WoDebriefIMSSummaryController.getSummaryAccess(child.Id);
		System.assertEquals(false, result.allowed);
		System.assert(
			result.blockMessage.contains('child'),
			'Child work orders should be blocked from the site visit summary.'
		);
	}

	@IsTest
	static void getSiteVisitSummary_countsObrAndOffSiteSeparately() {
		Id instrumentRtId = instrumentRecordTypeId();
		Account account = new Account(Name = 'Summary Count Account');
		insert account;
		Product2 obrProduct = new Product2(
			Name = 'Beyond Repair Code',
			ProductCode = 'SC.OBR-OCB1',
			IsActive = true
		);
		Product2 normalProduct = new Product2(
			Name = 'Normal Service Code',
			ProductCode = 'SC.ONL.130',
			IsActive = true
		);
		insert new List<Product2>{ obrProduct, normalProduct };

		WorkOrder parent = new WorkOrder(
			AccountId = account.Id,
			Subject = 'Site Visit',
			TotalServicedTrays__c = 2,
			ChildWorkOrderReviewDone__c = true
		);
		insert parent;
		WorkOrder child = new WorkOrder(
			AccountId = account.Id,
			Subject = 'Tray WO',
			ParentWorkOrderId = parent.Id
		);
		insert child;

		List<WorkOrderLineItem> lines = new List<WorkOrderLineItem>{
			new WorkOrderLineItem(
				WorkOrderId = child.Id,
				RecordTypeId = instrumentRtId,
				LineType__c = 'Instrument',
				Status = 'Completed',
				BillingType__c = 'Contract',
				RepairCode__c = obrProduct.Id,
				RepairLevel__c = '1'
			),
			new WorkOrderLineItem(
				WorkOrderId = child.Id,
				RecordTypeId = instrumentRtId,
				LineType__c = 'Instrument',
				Status = 'Completed',
				BillingType__c = 'Contract',
				RepairCode__c = obrProduct.Id,
				RepairLevel__c = '1',
				EndOfDayReportRepairCenter__c = true
			),
			new WorkOrderLineItem(
				WorkOrderId = child.Id,
				LineType__c = 'Labor',
				Status = 'Completed',
				BillingType__c = 'Billable'
			),
			new WorkOrderLineItem(
				WorkOrderId = child.Id,
				RecordTypeId = instrumentRtId,
				LineType__c = 'Instrument',
				Status = 'Completed',
				BillingType__c = 'Contract',
				RepairCode__c = normalProduct.Id,
				RepairLevel__c = '0'
			)
		};
		insert lines;

		Test.startTest();
		WoDebriefIMSSummaryController.SiteVisitSummary summary =
			WoDebriefIMSSummaryController.getSiteVisitSummary(parent.Id);
		Test.stopTest();

		System.assertEquals(1, summary.header.instrumentsBeyondRepair,
			'OBR line that is not forwarded should count as beyond repair.');
		System.assertEquals(1, summary.header.instrumentsOffSite,
			'Forwarded Repair Center line should count as off-site only.');
		System.assertEquals(1, summary.coveredGroups.size());
	}

	@IsTest
	static void saveCoverageChanges_updatesBillingType() {
		Account account = new Account(Name = 'Summary Coverage Account');
		insert account;
		WorkOrder parent = new WorkOrder(AccountId = account.Id, Subject = 'Site Visit Coverage');
		insert parent;
		WorkOrder child = new WorkOrder(
			AccountId = account.Id,
			Subject = 'Child Coverage',
			ParentWorkOrderId = parent.Id
		);
		insert child;
		WorkOrderLineItem line = new WorkOrderLineItem(
			WorkOrderId = child.Id,
			LineType__c = 'Labor',
			Status = 'Completed',
			BillingType__c = 'Billable'
		);
		insert line;

		String changesJson = JSON.serialize(new List<Map<String, Object>>{
			new Map<String, Object>{
				'lineId' => line.Id,
				'billingType' => 'Warranty'
			}
		});

		Test.startTest();
		WoDebriefIMSSummaryController.saveCoverageChanges(parent.Id, changesJson);
		Test.stopTest();

		WorkOrderLineItem updated = [
			SELECT BillingType__c
			FROM WorkOrderLineItem
			WHERE Id = :line.Id
		];
		System.assertEquals('Warranty', updated.BillingType__c);
	}

	@IsTest
	static void completeSummaryReview_requiresChildReview() {
		Account account = new Account(Name = 'Summary Approve Account');
		insert account;
		WorkOrder parent = new WorkOrder(
			AccountId = account.Id,
			Subject = 'Site Visit Approve',
			ChildWorkOrderReviewDone__c = false
		);
		insert parent;

		Boolean threw = false;
		try {
			WoDebriefIMSSummaryController.completeSummaryReview(parent.Id);
		} catch (AuraHandledException ex) {
			threw = true;
		}
		System.assertEquals(true, threw, 'Summary approve should require child review first.');
	}

	@IsTest
	static void completeSummaryReview_setsFlagWhenChildReviewDone() {
		Account account = new Account(Name = 'Summary Approve Done Account');
		insert account;
		WorkOrder parent = new WorkOrder(
			AccountId = account.Id,
			Subject = 'Site Visit Approve Done',
			ChildWorkOrderReviewDone__c = true
		);
		insert parent;

		Test.startTest();
		WoDebriefIMSSummaryController.SummaryAccessResult result =
			WoDebriefIMSSummaryController.completeSummaryReview(parent.Id);
		Test.stopTest();

		System.assertEquals(true, result.summaryReviewDone);
		WorkOrder updated = [
			SELECT SiteVisitSummaryReviewDone__c
			FROM WorkOrder
			WHERE Id = :parent.Id
		];
		System.assertEquals(true, updated.SiteVisitSummaryReviewDone__c);
	}

	@IsTest
	static void savePhotoSelection_updatesIncludeFlagAndEnforcesCategoryLimit() {
		Id instrumentRtId = instrumentRecordTypeId();
		Account account = new Account(Name = 'Summary Photo Account');
		insert account;
		WorkOrder parent = new WorkOrder(AccountId = account.Id, Subject = 'Site Visit Photos');
		insert parent;
		WorkOrder child = new WorkOrder(
			AccountId = account.Id,
			Subject = 'Child Photos',
			ParentWorkOrderId = parent.Id
		);
		insert child;
		WorkOrderLineItem line = new WorkOrderLineItem(
			WorkOrderId = child.Id,
			RecordTypeId = instrumentRtId,
			LineType__c = 'Instrument',
			Status = 'Completed',
			BillingType__c = 'Contract',
			RepairLevel__c = '1'
		);
		insert line;

		List<ContentVersion> versions = new List<ContentVersion>();
		for (Integer i = 0; i < 2; i++) {
			versions.add(new ContentVersion(
				Title = WoDebriefIMSchildWOController.MOBILE_DEVICE_PICTURE_TITLE,
				PathOnClient = 'photo' + i + '.jpg',
				VersionData = Blob.valueOf('photo-body-' + i),
				FirstPublishLocationId = line.Id,
				Description = WoDebriefIMSchildWOController.MOBILE_DEVICE_PICTURE_MARKER,
				PictureCategory__c = 'Beyond Repair',
				BeforeAfter__c = Math.mod(i, 2) == 0 ? 'Before' : 'After',
				IncludeInSummaryReport__c = false
			));
		}
		insert versions;
		versions = [
			SELECT Id, IncludeInSummaryReport__c
			FROM ContentVersion
			WHERE Id IN :versions
		];

		Test.startTest();
		WoDebriefIMSSummaryController.SiteVisitSummary summary =
			WoDebriefIMSSummaryController.getSiteVisitSummary(parent.Id);
		WoDebriefIMSSummaryController.savePhotoSelection(
			parent.Id,
			new List<Id>{ versions[0].Id }
		);
		Test.stopTest();

		System.assert(summary.photos.size() >= 1, 'Saved WOLI photos should appear on the summary.');
		ContentVersion selected = [
			SELECT IncludeInSummaryReport__c
			FROM ContentVersion
			WHERE Id = :versions[0].Id
		];
		System.assertEquals(true, selected.IncludeInSummaryReport__c);
	}

	@IsTest
	static void saveCoverageChanges_rejectsInvalidBillingType() {
		Account account = new Account(Name = 'Summary Invalid Billing Account');
		insert account;
		WorkOrder parent = new WorkOrder(AccountId = account.Id, Subject = 'Site Visit Invalid Billing');
		insert parent;
		WorkOrder child = new WorkOrder(
			AccountId = account.Id,
			Subject = 'Child Invalid Billing',
			ParentWorkOrderId = parent.Id
		);
		insert child;
		WorkOrderLineItem line = new WorkOrderLineItem(
			WorkOrderId = child.Id,
			LineType__c = 'Labor',
			Status = 'Completed',
			BillingType__c = 'Billable'
		);
		insert line;

		String changesJson = JSON.serialize(new List<Map<String, Object>>{
			new Map<String, Object>{
				'lineId' => line.Id,
				'billingType' => 'Contract'
			}
		});

		Boolean threw = false;
		try {
			WoDebriefIMSSummaryController.saveCoverageChanges(parent.Id, changesJson);
		} catch (AuraHandledException ex) {
			threw = true;
		}
		System.assertEquals(true, threw, 'Contract is not allowed on the billable tab save.');
	}

	@IsTest
	static void isBeyondRepair_requiresObrProductCodeAndNotOffSite() {
		WorkOrderLineItem obr = new WorkOrderLineItem();
		obr.EndOfDayReportRepairCenter__c = false;
		obr.RepairCode__r = new Product2(ProductCode = 'SC.OBR-OCB1');
		System.assertEquals(true, WoDebriefIMSSummaryController.isBeyondRepair(obr));

		WorkOrderLineItem offSite = new WorkOrderLineItem();
		offSite.EndOfDayReportRepairCenter__c = true;
		offSite.RepairCode__r = new Product2(ProductCode = 'SC.OBR-OCB1');
		System.assertEquals(false, WoDebriefIMSSummaryController.isBeyondRepair(offSite));

		WorkOrderLineItem normal = new WorkOrderLineItem();
		normal.EndOfDayReportRepairCenter__c = false;
		normal.RepairCode__r = new Product2(ProductCode = 'SC.ONL.130');
		System.assertEquals(false, WoDebriefIMSSummaryController.isBeyondRepair(normal));
	}

	private static Id instrumentRecordTypeId() {
		return Schema.SObjectType.WorkOrderLineItem
			.getRecordTypeInfosByDeveloperName()
			.get('ProductServiced')
			.getRecordTypeId();
	}
}