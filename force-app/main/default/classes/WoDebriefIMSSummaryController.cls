/**
 * @author Uptima Development Team
 * @date 2026-11-22
 * @description GW-6193 - Apex for the IMS site visit summary review on the parent Work Order.
 *              Loads child work order rollups, WOLI coverage rows, and WOLI photos; saves photo
 *              selection and Billable→Warranty/Courtesy overrides; marks the summary review done.
 *              without sharing so Field Service mobile can read linked files and update lines.
 * @group Work Order Debrief
 * @see woDebriefIMSSummary
 */
public without sharing class WoDebriefIMSSummaryController {
	private static final String LINE_TYPE_INSTRUMENT = 'Instrument';
	private static final String LINE_TYPE_PRODUCT_SERVICED = 'Product Serviced';
	private static final String LINE_TYPE_PARTS = 'Parts';
	private static final Set<String> INSTRUMENT_LINE_TYPES = new Set<String>{
		LINE_TYPE_INSTRUMENT,
		LINE_TYPE_PRODUCT_SERVICED
	};
	private static final Set<String> COVERAGE_LINE_TYPES = new Set<String>{
		LINE_TYPE_INSTRUMENT,
		LINE_TYPE_PRODUCT_SERVICED,
		LINE_TYPE_PARTS
	};
	private static final String BILLING_CONTRACT = 'Contract';
	private static final String BILLING_BILLABLE = 'Billable';
	private static final String BILLING_WARRANTY = 'Warranty';
	private static final String BILLING_COURTESY = 'Courtesy';
	private static final Set<String> BILLABLE_TAB_TYPES = new Set<String>{
		BILLING_BILLABLE,
		BILLING_WARRANTY,
		BILLING_COURTESY
	};
	private static final Set<String> FULL_DISCOUNT_TYPES = new Set<String>{
		BILLING_WARRANTY,
		BILLING_COURTESY
	};
	private static final Integer MAX_PHOTOS_PER_CATEGORY = 8;
	private static final String OBR_PRODUCT_CODE_TOKEN = 'OBR';
	private static final Set<String> PICTURE_TITLES = WoDebriefIMSchildWOController.PICTURE_TITLES;
	private static final String MOBILE_DEVICE_PICTURE_MARKER =
		WoDebriefIMSchildWOController.MOBILE_DEVICE_PICTURE_MARKER;

	/**
	 * @description Access and summary payload for the site visit summary screen.
	 */
	public class SummaryAccessResult {
		@AuraEnabled public Boolean allowed;
		@AuraEnabled public Id workOrderId;
		@AuraEnabled public String workOrderNumber;
		@AuraEnabled public String blockMessage;
		@AuraEnabled public Boolean childReviewDone;
		@AuraEnabled public Boolean summaryReviewDone;
	}

	/**
	 * @description Parent Work Order header values for Tab 1.
	 */
	public class SummaryHeader {
		@AuraEnabled public Id workOrderId;
		@AuraEnabled public String workOrderNumber;
		@AuraEnabled public String accountName;
		@AuraEnabled public Date serviceDate;
		@AuraEnabled public Date nextServiceDate;
		@AuraEnabled public Decimal traysServiced;
		@AuraEnabled public Integer instrumentsBeyondRepair;
		@AuraEnabled public Integer instrumentsOffSite;
		@AuraEnabled public Id returnOrderId;
		@AuraEnabled public String returnOrderNumber;
		@AuraEnabled public Boolean childReviewDone;
		@AuraEnabled public Boolean summaryReviewDone;
	}

	/**
	 * @description Child Work Order / asset rollup row for Tab 1.
	 */
	public class ChildAssetRow {
		@AuraEnabled public Id workOrderId;
		@AuraEnabled public String workOrderNumber;
		@AuraEnabled public Id assetId;
		@AuraEnabled public String assetName;
		@AuraEnabled public Integer instrumentCount;
		@AuraEnabled public Integer beyondRepairCount;
		@AuraEnabled public Integer offSiteCount;
		@AuraEnabled public Integer partsReplacedCount;
		@AuraEnabled public Boolean hasPhotos;
	}

	/**
	 * @description One WOLI photo that can be selected for the summary report.
	 */
	public class SummaryPhoto {
		@AuraEnabled public Id contentDocumentId;
		@AuraEnabled public Id contentVersionId;
		@AuraEnabled public Id linkedEntityId;
		@AuraEnabled public Id workOrderId;
		@AuraEnabled public String workOrderNumber;
		@AuraEnabled public String assetName;
		@AuraEnabled public String lineLabel;
		@AuraEnabled public String title;
		@AuraEnabled public String category;
		@AuraEnabled public String beforeAfter;
		@AuraEnabled public Boolean includeInSummaryReport;
	}

	/**
	 * @description Work Order Line Item row for Covered or Billable tabs.
	 */
	public class CoverageLineRow {
		@AuraEnabled public Id lineId;
		@AuraEnabled public String lineNumber;
		@AuraEnabled public String lineLabel;
		@AuraEnabled public String lineType;
		@AuraEnabled public String billingType;
		@AuraEnabled public Decimal quantity;
		@AuraEnabled public Decimal unitPrice;
		@AuraEnabled public Decimal discount;
		@AuraEnabled public Decimal totalPrice;
		@AuraEnabled public Boolean priceIsZero;
	}

	/**
	 * @description Child asset group with coverage lines.
	 */
	public class CoverageAssetGroup {
		@AuraEnabled public Id workOrderId;
		@AuraEnabled public String workOrderNumber;
		@AuraEnabled public Id assetId;
		@AuraEnabled public String assetName;
		@AuraEnabled public List<CoverageLineRow> lines;
	}

	/**
	 * @description Full summary payload returned to the LWC.
	 */
	public class SiteVisitSummary {
		@AuraEnabled public SummaryHeader header;
		@AuraEnabled public List<ChildAssetRow> childAssets;
		@AuraEnabled public List<SummaryPhoto> photos;
		@AuraEnabled public List<CoverageAssetGroup> coveredGroups;
		@AuraEnabled public List<CoverageAssetGroup> billableGroups;
		@AuraEnabled public Decimal billableGrandTotal;
	}

	/**
	 * @description Coverage change from Tab 3.
	 */
	public class CoverageChange {
		@AuraEnabled public Id lineId;
		@AuraEnabled public String billingType;
	}

	/**
	 * @description Checks that the Work Order is an IMS site visit (parent, no Parent Work Order).
	 * @param workOrderId Work Order Id opened in the summary action
	 * @return Access result
	 */
	@AuraEnabled(cacheable=true)
	public static SummaryAccessResult getSummaryAccess(Id workOrderId) {
		SummaryAccessResult result = new SummaryAccessResult();
		result.workOrderId = workOrderId;
		result.allowed = false;
		if (workOrderId == null) {
			result.blockMessage = 'Work order could not be identified. Open this action from a work order record.';
			return result;
		}
		List<WorkOrder> workOrders = [
			SELECT Id, WorkOrderNumber, ParentWorkOrderId,
				ChildWorkOrderReviewDone__c, SiteVisitSummaryReviewDone__c
			FROM WorkOrder
			WHERE Id = :workOrderId
			LIMIT 1
		];
		if (workOrders.isEmpty()) {
			result.blockMessage = 'Work order could not be loaded.';
			return result;
		}
		WorkOrder wo = workOrders[0];
		result.workOrderNumber = wo.WorkOrderNumber;
		result.childReviewDone = wo.ChildWorkOrderReviewDone__c == true;
		result.summaryReviewDone = wo.SiteVisitSummaryReviewDone__c == true;
		if (wo.ParentWorkOrderId != null) {
			result.blockMessage =
				'Work Order ' + labelFor(wo.WorkOrderNumber) +
				' is a child work order. Open Site Visit Summary Review from the parent site visit.';
			return result;
		}
		result.allowed = true;
		return result;
	}

	/**
	 * @description Loads the site visit summary for the parent Work Order.
	 * @param workOrderId Parent / site visit Work Order Id
	 * @return Summary payload
	 */
	@AuraEnabled
	public static SiteVisitSummary getSiteVisitSummary(Id workOrderId) {
		SummaryAccessResult access = getSummaryAccess(workOrderId);
		if (!access.allowed) {
			throw auraException(
				String.isNotBlank(access.blockMessage)
					? access.blockMessage
					: 'This work order cannot open the site visit summary.'
			);
		}

		WorkOrder parent = [
			SELECT
				Id,
				WorkOrderNumber,
				Account.Name,
				StartDate,
				EndDate,
				SuggestedMaintenanceDate,
				TotalServicedTrays__c,
				ChildWorkOrderReviewDone__c,
				SiteVisitSummaryReviewDone__c,
				ReturnOrder__c,
				ReturnOrder__r.ReturnOrderNumber,
				ReturnOrderId,
				ReturnOrder.ReturnOrderNumber
			FROM WorkOrder
			WHERE Id = :workOrderId
			LIMIT 1
		];

		List<WorkOrder> children = [
			SELECT
				Id,
				WorkOrderNumber,
				AssetId,
				Asset.Name,
				TotalServicedInstruments__c,
				(
					SELECT
						Id,
						LineItemNumber,
						LineType__c,
						Status,
						BillingType__c,
						Quantity,
						UnitPrice,
						Discount,
						TotalPrice,
						Description,
						Product2.Name,
						SendToRepairCenter__c,
						EndOfDayReportRepairCenter__c,
						RepairCode__c,
						RepairCode__r.ProductCode,
						RepairCode__r.Name
					FROM WorkOrderLineItems
					WHERE Status != 'Canceled'
					ORDER BY LineItemNumber
				)
			FROM WorkOrder
			WHERE ParentWorkOrderId = :workOrderId
			ORDER BY WorkOrderNumber
		];

		SiteVisitSummary summary = new SiteVisitSummary();
		summary.header = buildHeader(parent, children);
		summary.childAssets = buildChildAssetRows(children);
		summary.photos = listSummaryPhotos(children);
		summary.coveredGroups = buildCoverageGroups(children, true);
		summary.billableGroups = buildCoverageGroups(children, false);
		summary.billableGrandTotal = sumBillableTotal(summary.billableGroups);
		return summary;
	}

	/**
	 * @description Saves which WOLI photos are included in the Service Summary Report.
	 *              Enforces a maximum of 8 selected photos per Picture Category.
	 * @param workOrderId Parent Work Order Id
	 * @param selectedContentVersionIds ContentVersion Ids to include
	 */
	@AuraEnabled
	public static void savePhotoSelection(Id workOrderId, List<Id> selectedContentVersionIds) {
		SummaryAccessResult access = getSummaryAccess(workOrderId);
		if (!access.allowed) {
			throw auraException(access.blockMessage);
		}
		Set<Id> selectedIds = selectedContentVersionIds == null
			? new Set<Id>()
			: new Set<Id>(selectedContentVersionIds);

		List<WorkOrder> children = [
			SELECT Id, (SELECT Id FROM WorkOrderLineItems WHERE Status != 'Canceled')
			FROM WorkOrder
			WHERE ParentWorkOrderId = :workOrderId
		];
		Set<Id> linkedEntityIds = new Set<Id>();
		for (WorkOrder child : children) {
			linkedEntityIds.add(child.Id);
			for (WorkOrderLineItem line : child.WorkOrderLineItems) {
				linkedEntityIds.add(line.Id);
			}
		}
		if (linkedEntityIds.isEmpty()) {
			return;
		}

		Set<Id> documentIds = new Set<Id>();
		for (ContentDocumentLink link : [
			SELECT ContentDocumentId
			FROM ContentDocumentLink
			WHERE LinkedEntityId IN :linkedEntityIds
		]) {
			if (link.ContentDocumentId != null) {
				documentIds.add(link.ContentDocumentId);
			}
		}
		List<ContentVersion> versions = selectSummaryPictures(documentIds);
		Map<String, Integer> selectedByCategory = new Map<String, Integer>();
		List<ContentVersion> toUpdate = new List<ContentVersion>();
		for (ContentVersion version : versions) {
			Boolean shouldInclude = selectedIds.contains(version.Id);
			String categoryKey = String.isBlank(version.PictureCategory__c)
				? '(none)'
				: version.PictureCategory__c;
			if (shouldInclude) {
				Integer count = selectedByCategory.containsKey(categoryKey)
					? selectedByCategory.get(categoryKey)
					: 0;
				count++;
				if (count > MAX_PHOTOS_PER_CATEGORY) {
					throw auraException(
						'Select no more than ' + MAX_PHOTOS_PER_CATEGORY +
						' photos per category. Category "' + categoryKey + '" has too many.'
					);
				}
				selectedByCategory.put(categoryKey, count);
			}
			Boolean current = version.IncludeInSummaryReport__c == true;
			if (current != shouldInclude) {
				toUpdate.add(new ContentVersion(
					Id = version.Id,
					IncludeInSummaryReport__c = shouldInclude
				));
			}
		}
		if (!toUpdate.isEmpty()) {
			try {
				update toUpdate;
			} catch (DmlException ex) {
				throw auraException(ex.getDmlMessage(0));
			}
		}
	}

	/**
	 * @description Saves Tab 3 coverage overrides. Warranty or Courtesy sets Discount to 100.
	 * @param workOrderId Parent Work Order Id
	 * @param changesJson JSON array of { lineId, billingType }
	 */
	@AuraEnabled
	public static void saveCoverageChanges(Id workOrderId, String changesJson) {
		SummaryAccessResult access = getSummaryAccess(workOrderId);
		if (!access.allowed) {
			throw auraException(access.blockMessage);
		}
		if (String.isBlank(changesJson)) {
			return;
		}
		List<CoverageChange> changes =
			(List<CoverageChange>) JSON.deserialize(changesJson, List<CoverageChange>.class);
		if (changes == null || changes.isEmpty()) {
			return;
		}

		Set<Id> lineIds = new Set<Id>();
		Map<Id, String> billingByLineId = new Map<Id, String>();
		for (CoverageChange change : changes) {
			if (change == null || change.lineId == null || String.isBlank(change.billingType)) {
				continue;
			}
			if (!BILLABLE_TAB_TYPES.contains(change.billingType)) {
				throw auraException(
					'Coverage type must be Billable, Warranty, or Courtesy.'
				);
			}
			lineIds.add(change.lineId);
			billingByLineId.put(change.lineId, change.billingType);
		}
		if (lineIds.isEmpty()) {
			return;
		}

		List<WorkOrderLineItem> lines = [
			SELECT Id, BillingType__c, Discount, PricebookEntryId, Product2Id, WorkOrder.ParentWorkOrderId
			FROM WorkOrderLineItem
			WHERE Id IN :lineIds
		];
		List<WorkOrderLineItem> toUpdate = new List<WorkOrderLineItem>();
		for (WorkOrderLineItem line : lines) {
			if (line.WorkOrder.ParentWorkOrderId != workOrderId) {
				throw auraException('A line does not belong to this site visit.');
			}
			String billingType = billingByLineId.get(line.Id);
			WorkOrderLineItem updateLine = new WorkOrderLineItem(
				Id = line.Id,
				BillingType__c = billingType
			);
			// Standard WOLI Discount requires a product / pricebook entry.
			if (line.PricebookEntryId != null || line.Product2Id != null) {
				updateLine.Discount = FULL_DISCOUNT_TYPES.contains(billingType) ? 100 : 0;
			}
			toUpdate.add(updateLine);
		}
		if (!toUpdate.isEmpty()) {
			try {
				update toUpdate;
			} catch (DmlException ex) {
				throw auraException(ex.getDmlMessage(0));
			}
		}
	}

	/**
	 * @description Marks the site visit summary review as done.
	 * @param workOrderId Parent Work Order Id
	 * @return Access result after update
	 */
	@AuraEnabled
	public static SummaryAccessResult completeSummaryReview(Id workOrderId) {
		SummaryAccessResult access = getSummaryAccess(workOrderId);
		if (!access.allowed) {
			throw auraException(access.blockMessage);
		}
		if (access.childReviewDone != true) {
			throw auraException(
				'Finish Review Child Work Orders on the site visit before approving the summary.'
			);
		}
		try {
			update new WorkOrder(Id = workOrderId, SiteVisitSummaryReviewDone__c = true);
		} catch (DmlException ex) {
			throw auraException(ex.getDmlMessage(0));
		}
		access.summaryReviewDone = true;
		return access;
	}

	/**
	 * @description Image body for a saved Mobile Device / Microscope Picture.
	 * @param contentVersionId Latest ContentVersion Id
	 * @return Base64 image body without a data-url prefix
	 */
	@AuraEnabled
	public static String getSummaryPhotoData(String contentVersionId) {
		return WoDebriefIMSchildWOController.getMobileDevicePictureData(contentVersionId);
	}

	private static SummaryHeader buildHeader(WorkOrder parent, List<WorkOrder> children) {
		SummaryHeader header = new SummaryHeader();
		header.workOrderId = parent.Id;
		header.workOrderNumber = parent.WorkOrderNumber;
		header.accountName = parent.Account != null ? parent.Account.Name : null;
		header.serviceDate = parent.StartDate != null
			? parent.StartDate.date()
			: (parent.EndDate != null ? parent.EndDate.date() : null);
		header.nextServiceDate = parent.SuggestedMaintenanceDate;
		header.traysServiced = parent.TotalServicedTrays__c;
		header.childReviewDone = parent.ChildWorkOrderReviewDone__c == true;
		header.summaryReviewDone = parent.SiteVisitSummaryReviewDone__c == true;
		if (parent.ReturnOrder__c != null) {
			header.returnOrderId = parent.ReturnOrder__c;
			header.returnOrderNumber = parent.ReturnOrder__r != null
				? parent.ReturnOrder__r.ReturnOrderNumber
				: null;
		} else if (parent.ReturnOrderId != null) {
			header.returnOrderId = parent.ReturnOrderId;
			header.returnOrderNumber = parent.ReturnOrder != null
				? parent.ReturnOrder.ReturnOrderNumber
				: null;
		}

		Integer beyondRepair = 0;
		Integer offSite = 0;
		for (WorkOrder child : children) {
			for (WorkOrderLineItem line : child.WorkOrderLineItems) {
				if (!isInstrumentLine(line) || line.Status == 'Canceled') {
					continue;
				}
				if (isOffSite(line)) {
					offSite++;
				} else if (isBeyondRepair(line)) {
					beyondRepair++;
				}
			}
		}
		header.instrumentsBeyondRepair = beyondRepair;
		header.instrumentsOffSite = offSite;
		return header;
	}

	private static List<ChildAssetRow> buildChildAssetRows(List<WorkOrder> children) {
		List<ChildAssetRow> rows = new List<ChildAssetRow>();
		Set<Id> childIds = new Set<Id>();
		Map<Id, Set<Id>> lineIdsByChild = new Map<Id, Set<Id>>();
		for (WorkOrder child : children) {
			childIds.add(child.Id);
			Set<Id> lineIds = new Set<Id>();
			for (WorkOrderLineItem line : child.WorkOrderLineItems) {
				lineIds.add(line.Id);
			}
			lineIdsByChild.put(child.Id, lineIds);
		}
		Set<Id> childrenWithPhotos = childrenWithPhotos(childIds, lineIdsByChild);

		for (WorkOrder child : children) {
			ChildAssetRow row = new ChildAssetRow();
			row.workOrderId = child.Id;
			row.workOrderNumber = child.WorkOrderNumber;
			row.assetId = child.AssetId;
			row.assetName = child.Asset != null ? child.Asset.Name : null;
			row.instrumentCount = 0;
			row.beyondRepairCount = 0;
			row.offSiteCount = 0;
			row.partsReplacedCount = 0;
			row.hasPhotos = childrenWithPhotos.contains(child.Id);

			for (WorkOrderLineItem line : child.WorkOrderLineItems) {
				if (line.Status == 'Canceled') {
					continue;
				}
				if (isInstrumentLine(line)) {
					row.instrumentCount++;
					if (isOffSite(line)) {
						row.offSiteCount++;
					} else if (isBeyondRepair(line)) {
						row.beyondRepairCount++;
					}
				} else if (line.LineType__c == LINE_TYPE_PARTS) {
					Decimal qty = line.Quantity == null ? 1 : line.Quantity;
					row.partsReplacedCount += qty.intValue();
				}
			}
			rows.add(row);
		}
		return rows;
	}

	private static List<CoverageAssetGroup> buildCoverageGroups(
		List<WorkOrder> children,
		Boolean coveredOnly
	) {
		List<CoverageAssetGroup> groups = new List<CoverageAssetGroup>();
		for (WorkOrder child : children) {
			List<CoverageLineRow> lines = new List<CoverageLineRow>();
			for (WorkOrderLineItem line : child.WorkOrderLineItems) {
				if (line.Status == 'Canceled' || !COVERAGE_LINE_TYPES.contains(line.LineType__c)) {
					continue;
				}
				String billing = line.BillingType__c;
				if (coveredOnly) {
					if (billing != BILLING_CONTRACT) {
						continue;
					}
				} else if (!BILLABLE_TAB_TYPES.contains(billing)) {
					continue;
				}
				lines.add(toCoverageLine(line));
			}
			if (lines.isEmpty()) {
				continue;
			}
			CoverageAssetGroup assetGroup = new CoverageAssetGroup();
			assetGroup.workOrderId = child.Id;
			assetGroup.workOrderNumber = child.WorkOrderNumber;
			assetGroup.assetId = child.AssetId;
			assetGroup.assetName = child.Asset != null ? child.Asset.Name : null;
			assetGroup.lines = lines;
			groups.add(assetGroup);
		}
		return groups;
	}

	private static CoverageLineRow toCoverageLine(WorkOrderLineItem line) {
		CoverageLineRow row = new CoverageLineRow();
		row.lineId = line.Id;
		row.lineNumber = line.LineItemNumber;
		row.lineLabel = lineLabel(line);
		row.lineType = line.LineType__c;
		row.billingType = line.BillingType__c;
		row.quantity = line.Quantity;
		row.unitPrice = line.UnitPrice;
		row.discount = line.Discount;
		row.totalPrice = line.TotalPrice;
		row.priceIsZero = FULL_DISCOUNT_TYPES.contains(line.BillingType__c)
			|| (line.TotalPrice != null && line.TotalPrice == 0)
			|| (line.Discount != null && line.Discount >= 100);
		return row;
	}

	private static Decimal sumBillableTotal(List<CoverageAssetGroup> groups) {
		Decimal total = 0;
		for (CoverageAssetGroup assetGroup : groups) {
			for (CoverageLineRow line : assetGroup.lines) {
				if (line.totalPrice != null) {
					total += line.totalPrice;
				}
			}
		}
		return total;
	}

	private static List<SummaryPhoto> listSummaryPhotos(List<WorkOrder> children) {
		List<SummaryPhoto> photos = new List<SummaryPhoto>();
		Set<Id> linkedEntityIds = new Set<Id>();
		Map<Id, WorkOrder> childById = new Map<Id, WorkOrder>();
		Map<Id, WorkOrderLineItem> lineById = new Map<Id, WorkOrderLineItem>();
		Map<Id, Id> lineToChildId = new Map<Id, Id>();
		for (WorkOrder child : children) {
			childById.put(child.Id, child);
			linkedEntityIds.add(child.Id);
			for (WorkOrderLineItem line : child.WorkOrderLineItems) {
				linkedEntityIds.add(line.Id);
				lineById.put(line.Id, line);
				lineToChildId.put(line.Id, child.Id);
			}
		}
		if (linkedEntityIds.isEmpty()) {
			return photos;
		}

		List<ContentDocumentLink> links = [
			SELECT ContentDocumentId, LinkedEntityId
			FROM ContentDocumentLink
			WHERE LinkedEntityId IN :linkedEntityIds
		];
		Set<Id> documentIds = new Set<Id>();
		for (ContentDocumentLink link : links) {
			if (link.ContentDocumentId != null) {
				documentIds.add(link.ContentDocumentId);
			}
		}
		Map<Id, ContentVersion> versionByDocumentId = new Map<Id, ContentVersion>();
		for (ContentVersion version : selectSummaryPictures(documentIds)) {
			versionByDocumentId.put(version.ContentDocumentId, version);
		}
		for (ContentDocumentLink link : links) {
			ContentVersion version = versionByDocumentId.get(link.ContentDocumentId);
			if (version == null) {
				continue;
			}
			SummaryPhoto photo = new SummaryPhoto();
			photo.contentDocumentId = version.ContentDocumentId;
			photo.contentVersionId = version.Id;
			photo.linkedEntityId = link.LinkedEntityId;
			photo.title = version.Title;
			photo.category = version.PictureCategory__c;
			photo.beforeAfter = version.BeforeAfter__c;
			photo.includeInSummaryReport = version.IncludeInSummaryReport__c == true;

			WorkOrderLineItem line = lineById.get(link.LinkedEntityId);
			if (line != null) {
				WorkOrder child = childById.get(lineToChildId.get(line.Id));
				if (child != null) {
					photo.workOrderId = child.Id;
					photo.workOrderNumber = child.WorkOrderNumber;
					photo.assetName = child.Asset != null ? child.Asset.Name : null;
				}
				photo.lineLabel = lineLabel(line);
			} else {
				WorkOrder child = childById.get(link.LinkedEntityId);
				if (child != null) {
					photo.workOrderId = child.Id;
					photo.workOrderNumber = child.WorkOrderNumber;
					photo.assetName = child.Asset != null ? child.Asset.Name : null;
					photo.lineLabel = 'Tray';
				}
			}
			photos.add(photo);
		}
		return photos;
	}

	private static Set<Id> childrenWithPhotos(
		Set<Id> childIds,
		Map<Id, Set<Id>> lineIdsByChild
	) {
		Set<Id> result = new Set<Id>();
		if (childIds.isEmpty()) {
			return result;
		}
		Set<Id> allLinked = new Set<Id>(childIds);
		for (Set<Id> lineIds : lineIdsByChild.values()) {
			allLinked.addAll(lineIds);
		}
		Map<Id, Id> entityToChild = new Map<Id, Id>();
		for (Id childId : childIds) {
			entityToChild.put(childId, childId);
			for (Id lineId : lineIdsByChild.get(childId)) {
				entityToChild.put(lineId, childId);
			}
		}
		List<ContentDocumentLink> links = [
			SELECT ContentDocumentId, LinkedEntityId
			FROM ContentDocumentLink
			WHERE LinkedEntityId IN :allLinked
		];
		Set<Id> documentIds = new Set<Id>();
		for (ContentDocumentLink link : links) {
			documentIds.add(link.ContentDocumentId);
		}
		Map<Id, ContentVersion> versionByDocumentId = new Map<Id, ContentVersion>();
		for (ContentVersion version : selectSummaryPictures(documentIds)) {
			versionByDocumentId.put(version.ContentDocumentId, version);
		}
		for (ContentDocumentLink link : links) {
			if (versionByDocumentId.containsKey(link.ContentDocumentId)) {
				Id childId = entityToChild.get(link.LinkedEntityId);
				if (childId != null) {
					result.add(childId);
				}
			}
		}
		return result;
	}

	private static List<ContentVersion> selectSummaryPictures(Set<Id> documentIds) {
		if (documentIds == null || documentIds.isEmpty()) {
			return new List<ContentVersion>();
		}
		return [
			SELECT
				Id,
				ContentDocumentId,
				Title,
				PictureCategory__c,
				BeforeAfter__c,
				IncludeInSummaryReport__c
			FROM ContentVersion
			WHERE ContentDocumentId IN :documentIds
				AND IsLatest = true
				AND (Description = :MOBILE_DEVICE_PICTURE_MARKER OR Title IN :PICTURE_TITLES)
		];
	}

	private static Boolean isInstrumentLine(WorkOrderLineItem line) {
		return line != null && INSTRUMENT_LINE_TYPES.contains(line.LineType__c);
	}

	private static Boolean isOffSite(WorkOrderLineItem line) {
		return line != null && line.EndOfDayReportRepairCenter__c == true;
	}

	/**
	 * @description True when the line's saved Service Code Product Code contains OBR
	 *              and the line was not forwarded to the Repair Center.
	 */
	@TestVisible
	private static Boolean isBeyondRepair(WorkOrderLineItem line) {
		if (line == null || isOffSite(line)) {
			return false;
		}
		String productCode = line.RepairCode__r != null ? line.RepairCode__r.ProductCode : null;
		return String.isNotBlank(productCode)
			&& productCode.toUpperCase().contains(OBR_PRODUCT_CODE_TOKEN);
	}

	private static String lineLabel(WorkOrderLineItem line) {
		String name = line.Product2 != null && String.isNotBlank(line.Product2.Name)
			? line.Product2.Name
			: (String.isNotBlank(line.Description) ? line.Description : 'Line');
		if (String.isNotBlank(line.LineItemNumber)) {
			return 'Line ' + line.LineItemNumber + ' - ' + name;
		}
		return name;
	}

	private static String labelFor(String workOrderNumber) {
		return String.isNotBlank(workOrderNumber) ? workOrderNumber : 'this work order';
	}

	private static AuraHandledException auraException(String message) {
		return new AuraHandledException(message);
	}
}