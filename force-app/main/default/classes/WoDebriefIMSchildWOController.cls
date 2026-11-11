/**
 * @author Uptima Development Team
 * @date 2026-07-15
 * @description LWC controller for IMS child Work Order debrief. Resolves Service Code
 *              Product2 options from a part or Device Type Base Service Code / Item Number,
 *              and PricebookEntry Ids for Device Type products.
 *              Reads go through selectors. without sharing so labor-line saves are not blocked
 *              by Field Service sharing.
 * @group Work Order Debrief
 * @see woDebriefIMSchildWO
 */
public without sharing class WoDebriefIMSchildWOController {
	/** @description GW-375 - ContentVersion.Description for pictures taken with the mobile device camera. */
	public static final String MOBILE_DEVICE_PICTURE_MARKER = 'MobileDevicePicture';
	/** @description GW-6437 - Delimiter between upload context and optional CRSS picture comment. */
	private static final String MOBILE_PICTURE_COMMENT_DELIMITER = '|||';
	/** @description GW-375 - Separates an embedded line id from the image body. Not a Salesforce id character. */
	private static final String LINE_PICTURE_EMBED_MARK = ':::';
	/** @description GW-6017 - Separates the line token from the work order and asset used to find a newly synced line. */
	private static final String LINE_PICTURE_CONTEXT_MARK = '~';
	/** @description GW-6017 - How far back a newly synced Product Serviced line is looked up by work order and asset. */
	private static final Integer NEW_LINE_PICTURE_LOOKBACK_MINUTES = 30;
	/** @description GW-6437 - Maximum CRSS Mobile Device Picture comment length. */
	private static final Integer MOBILE_PICTURE_COMMENT_MAX_LENGTH = 1000;
	/** @description GW-375 - File title shown on the work order and instrument line. */
	public static final String MOBILE_DEVICE_PICTURE_TITLE = 'Mobile Device Picture';
	/** @description GW-6340 - File title of a picture taken with the external microscopic camera. */
	public static final String MICROSCOPE_PICTURE_TITLE = 'Microscope Picture';
	/** @description GW-6340 - Titles of debrief pictures. Both are listed and counted toward the required pictures. */
	public static final Set<String> PICTURE_TITLES = new Set<String>{
		MOBILE_DEVICE_PICTURE_TITLE,
		MICROSCOPE_PICTURE_TITLE
	};
	/**
	 * @description GW-375 - Follows the marker in ContentVersion.Description when the mobile app uploads
	 *              a picture with its details. The file adapter only takes a title and a description,
	 *              so the details travel there and are moved into their fields once the file is linked.
	 */
	public static final String PICTURE_DETAILS_SEPARATOR = '|';
	private static final Integer MAX_MOBILE_PICTURE_BYTES = 4500000;
	private static final String WORK_ORDER_STATUS_COMPLETED = 'Completed';
	/**
	 * @description Access payload for the IMS child Work Order debrief screen.
	 */
	public class ChildDebriefAccessResult {
		/** @description True when the WO is a child with an Asset (IMS instrument debrief). */
		@AuraEnabled public Boolean allowed;
		/** @description Work Order Id that was checked. */
		@AuraEnabled public Id workOrderId;
		/** @description Work Order Number for user messaging. */
		@AuraEnabled public String workOrderNumber;
		/** @description User-facing message when allowed is false. */
		@AuraEnabled public String blockMessage;
	}

	/**
	 * @description Child debrief requires Parent Work Order and Asset (site visits typically have neither).
	 * @param workOrderId Work Order Id opened in the debrief action
	 * @return Access result for the child debrief screen
	 */
	@AuraEnabled(cacheable=true)
	public static ChildDebriefAccessResult getChildDebriefAccess(Id workOrderId) {
		ChildDebriefAccessResult result = new ChildDebriefAccessResult();
		result.workOrderId = workOrderId;
		result.allowed = false;
		if (workOrderId == null) {
			result.blockMessage = 'Work order could not be identified. Open this action from a work order record.';
			return result;
		}
		List<WorkOrder> workOrders = (List<WorkOrder>) new WorkOrdersSelector()
			.selectFields(new List<String>{ 'ParentWorkOrderId', 'WorkOrderNumber', 'AssetId' })
			.whereEquals('Id', workOrderId)
			.limitTo(1)
			.execute();
		if (workOrders.isEmpty()) {
			result.blockMessage = 'Work order could not be loaded.';
			return result;
		}
		WorkOrder wo = workOrders[0];
		result.workOrderNumber = wo.WorkOrderNumber;
		Boolean hasParent = wo.ParentWorkOrderId != null;
		Boolean hasAsset = wo.AssetId != null;
		result.allowed = hasParent && hasAsset;
		if (!result.allowed) {
			String woLabel = String.isNotBlank(wo.WorkOrderNumber) ? wo.WorkOrderNumber : 'this work order';
			if (!hasAsset) {
				result.blockMessage =
					'Work Order ' + woLabel + ' has no Asset. This action is only for child work orders with an instrument asset. Use Work Order Review - IMS Site Visit for the site visit work order.';
			} else if (!hasParent) {
				result.blockMessage =
					'Work Order ' + woLabel + ' has no Parent Work Order. Use Work Order Review - IMS Site Visit instead. This action is only for child work orders.';
			} else {
				result.blockMessage = 'This work order cannot open the child work order debrief.';
			}
		}
		return result;
	}

	/**
	 * @description GW-312 - Result of the Complete Work Order check on an IMS child Work Order.
	 */
	public class CompletionCheckResult {
		/** @description Work Order Number for user messaging. */
		@AuraEnabled public String workOrderNumber;
		/** @description True when there are instrument lines and each has a Service Code and the required pictures. */
		@AuraEnabled public Boolean canComplete;
		/** @description Reasons the work order cannot be completed, per instrument line or for the whole work order. */
		@AuraEnabled public List<String> missingLines;
		/** @description Instrument lines marked Send to Repair Center. */
		@AuraEnabled public List<String> repairCenterLines;
	}

	/** @description GW-312 - Mobile Device Pictures each instrument line needs before the work order is completed. */
	public static final Integer REQUIRED_PICTURES_PER_LINE = 2;

	/**
	 * @description GW-312 - Checks that the child Work Order has instrument lines, and that each has a Service Code
	 *              and the required Mobile Device Pictures. Lists the lines sent to the Repair Center.
	 * @param workOrderId Child Work Order Id
	 * @return Completion check result
	 */
	@AuraEnabled
	public static CompletionCheckResult getCompletionCheck(Id workOrderId) {
		if (workOrderId == null) {
			throw auraException('Work order could not be identified.');
		}
		List<WorkOrder> workOrders = (List<WorkOrder>) new WorkOrdersSelector()
			.selectFields(new List<String>{ 'WorkOrderNumber' })
			.whereEquals('Id', workOrderId)
			.limitTo(1)
			.execute();
		if (workOrders.isEmpty()) {
			throw auraException('Work order could not be loaded.');
		}
		CompletionCheckResult result = new CompletionCheckResult();
		result.workOrderNumber = workOrders[0].WorkOrderNumber;
		result.missingLines = new List<String>();
		result.repairCenterLines = new List<String>();

		List<WorkOrderLineItem> lines = [
			SELECT
				Id,
				LineItemNumber,
				RepairLevel__c,
				MobileDevicePictureCount__c,
				SendToRepairCenter__c,
				Product2.Name
			FROM WorkOrderLineItem
			WHERE WorkOrderId = :workOrderId
				AND LineType__c = 'Instrument'
				AND Status != 'Canceled'
		];
		if (lines.isEmpty()) {
			result.missingLines.add('Add at least one instrument line');
		}
		for (WorkOrderLineItem line : lines) {
			List<String> missing = new List<String>();
			if (String.isBlank(line.RepairLevel__c)) {
				missing.add('Service Code');
			}
			Integer pictureCount = line.MobileDevicePictureCount__c == null
				? 0
				: line.MobileDevicePictureCount__c.intValue();
			if (pictureCount < REQUIRED_PICTURES_PER_LINE) {
				missing.add(REQUIRED_PICTURES_PER_LINE + ' pictures (has ' + pictureCount + ')');
			}
			if (!missing.isEmpty()) {
				result.missingLines.add(instrumentLineLabel(line) + ': missing ' + String.join(missing, ' and '));
			}
			if (line.SendToRepairCenter__c) {
				result.repairCenterLines.add(instrumentLineLabel(line));
			}
		}
		result.canComplete = result.missingLines.isEmpty();
		return result;
	}

	/**
	 * @description GW-312 - Sets the child Work Order to Completed after the completion check passes.
	 * @param workOrderId Child Work Order Id
	 * @return Completion check result used for the update
	 */
	@AuraEnabled
	public static CompletionCheckResult completeChildWorkOrder(Id workOrderId) {
		CompletionCheckResult result = getCompletionCheck(workOrderId);
		if (!result.canComplete) {
			throw auraException(
				'Work Order ' + result.workOrderNumber + ' cannot be completed. ' +
				String.join(result.missingLines, '. ') + '.'
			);
		}
		try {
			update new WorkOrder(Id = workOrderId, Status = WORK_ORDER_STATUS_COMPLETED);
		} catch (DmlException ex) {
			throw auraException(ex.getDmlMessage(0));
		}
		return result;
	}

	/**
	 * @description GW-312 - Line label used in completion messages.
	 * @param line Instrument line
	 * @return Line number and instrument name
	 */
	private static String instrumentLineLabel(WorkOrderLineItem line) {
		String name = String.isNotBlank(line.Product2?.Name) ? line.Product2.Name : 'Instrument';
		return 'Line ' + line.LineItemNumber + ' - ' + name;
	}

	/**
	 * @description Backward-compatible boolean wrapper for callers/tests.
	 * @param workOrderId Work Order Id opened in the debrief action
	 * @return False for site visit / parent work orders
	 */
	@AuraEnabled(cacheable=true)
	public static Boolean allowsChildWorkOrderDebrief(Id workOrderId) {
		return getChildDebriefAccess(workOrderId).allowed;
	}

	/**
	 * @description Picklist-style option for a matching Service Code product.
	 */
	public class RepairCodeOption {
		/** @description Product2 Id of the service code. */
		@AuraEnabled public Id id;
		/** @description Product Code value. */
		@AuraEnabled public String productCode;
		/** @description Product Name. */
		@AuraEnabled public String name;
		/** @description Product Description. */
		@AuraEnabled public String description;
		/** @description Display label combining product code and name when both are present. */
		@AuraEnabled public String label;
	}

	/**
	 * @description Result payload for repair-code lookup against a part Product2.
	 */
	public class RepairCodesForProductResult {
		/** @description Trimmed Base Service Code from the part product. */
		@AuraEnabled public String baseServiceCode;
		/** @description Matching Service Code product options. */
		@AuraEnabled public List<RepairCodeOption> options;
	}

	/**
	 * @description Returns Service Code products whose Base Service Code starts with the part's code.
	 * @param product2Id Part Product2 Id
	 * @return Base service code and matching repair-code options (empty when inputs are incomplete)
	 */
	@AuraEnabled
	public static RepairCodesForProductResult getRepairCodesForProduct(Id product2Id) {
		RepairCodesForProductResult result = new RepairCodesForProductResult();
		result.baseServiceCode = '';
		result.options = new List<RepairCodeOption>();

		if (product2Id == null) {
			return result;
		}

		List<Product2> partProducts = (List<Product2>) new ProductsSelector()
			.selectFields(new List<String>{ 'BaseServiceCode__c' })
			.whereEquals('Id', product2Id)
			.limitTo(1)
			.execute();

		if (partProducts.isEmpty()) {
			return result;
		}

		String baseServiceCode = partProducts[0].BaseServiceCode__c;
		if (String.isBlank(baseServiceCode)) {
			return result;
		}

		baseServiceCode = baseServiceCode.trim();
		result.baseServiceCode = baseServiceCode;

		String likePattern = baseServiceCode + '%';
		// SC.ONL.130 → SC.ONL130 so Item Number SC.ONL1304 matches the Device Type base.
		String itemNumberPrefix = baseServiceCode.replaceAll('\\.(\\d+)$', '$1');
		String itemNumberLike = itemNumberPrefix + '%';
		// Beyond repair uses BR in place of NL: SC.ONL.130 also matches SC.OBR.130 / SC.OBR1304.
		String beyondRepairBase = baseServiceCode.replaceAll('(?i)NL', 'BR');
		String beyondRepairLike = beyondRepairBase + '%';
		String beyondRepairItemPrefix = beyondRepairBase.replaceAll('\\.(\\d+)$', '$1');
		String beyondRepairItemLike = beyondRepairItemPrefix + '%';
		List<Product2> products = (List<Product2>) new ProductsSelector()
			.selectFields(new List<String>{ 'Id', 'ProductCode', 'Name', 'Description' })
			.whereEquals('ProductType__c', 'Service Code')
			.whereField('BaseServiceCode__c', 'LIKE', likePattern)
			.whereField('ProductCode', 'LIKE', likePattern)
			.whereField('ProductCode', 'LIKE', itemNumberLike)
			.whereField('BaseServiceCode__c', 'LIKE', beyondRepairLike)
			.whereField('ProductCode', 'LIKE', beyondRepairLike)
			.whereField('ProductCode', 'LIKE', beyondRepairItemLike)
			.withFilterLogic('1 AND (2 OR 3 OR 4 OR 5 OR 6 OR 7)')
			.orderBy('ProductCode')
			.limitTo(200)
			.execute();

		// Build LWC options from each matching service-code product.
		for (Product2 product : products) {
			RepairCodeOption option = new RepairCodeOption();
			option.id = product.Id;
			option.productCode = product.ProductCode;
			option.name = product.Name;
			option.description = product.Description;
			option.label = formatRepairCodeLabel(product.ProductCode, product.Name);
			result.options.add(option);
		}

		return result;
	}

	/**
	 * @description Resolves an active PricebookEntry for a Device Type product on the Work Order pricebook.
	 * @param workOrderId Work Order Id (provides Pricebook2Id and currency)
	 * @param product2Id Device Type Product2 Id
	 * @return PricebookEntry Id, or null when the Work Order or product has no matching entry
	 */
	@AuraEnabled
	public static Id resolvePricebookEntryId(Id workOrderId, Id product2Id) {
		if (workOrderId == null || product2Id == null) {
			return null;
		}

		List<WorkOrder> workOrders = (List<WorkOrder>) new WorkOrdersSelector()
			.selectFields(new List<String>{ 'Pricebook2Id', 'CurrencyIsoCode' })
			.whereEquals('Id', workOrderId)
			.limitTo(1)
			.execute();
		if (workOrders.isEmpty() || workOrders[0].Pricebook2Id == null) {
			return null;
		}

		String currencyIso = String.isNotBlank(workOrders[0].CurrencyIsoCode)
			? workOrders[0].CurrencyIsoCode
			: UserInfo.getDefaultCurrency();

		List<PricebookEntry> entries = PricebookEntriesSelector.selectActiveByPricebookProductAndCurrency(
			workOrders[0].Pricebook2Id,
			new Set<Id>{ product2Id },
			currencyIso
		);
		return entries.isEmpty() ? null : entries[0].Id;
	}

	/**
	 * @description Creates or updates a labor line.
	 *              Used instead of LDS so Field Service Mobile drafts do not
	 *              pass a local draft id into an Apex Id parameter.
	 * @param workOrderId Parent Work Order Id (required when creating)
	 * @param workOrderLineItemId Existing WOLI Id, or blank when creating
	 * @param assignedResourceId Assigned Resource
	 * @param workTypeId Work Type
	 * @param quantity Labor qty
	 * @param lineType Line Type (defaults to Labor)
	 * @param billingType Billing Type picklist value (Time lines are stored as Non-Billable)
	 * @return Saved Work Order Line Item Id
	 */
	@AuraEnabled
	public static Id saveLaborLine(
		Id workOrderId,
		String workOrderLineItemId,
		Id assignedResourceId,
		Id workTypeId,
		Decimal quantity,
		String lineType,
		String billingType
	) {
		Id existingId = tryWorkOrderLineItemId(workOrderLineItemId);
		if (existingId == null && workOrderId == null) {
			throw new AuraHandledException('Work Order is required to save a labor line.');
		}

		WorkOrderLineItem line = new WorkOrderLineItem();
		if (existingId != null) {
			line.Id = existingId;
		} else {
			line.WorkOrderId = workOrderId;
		}
		line.LineType__c = String.isBlank(lineType) ? 'Labor' : lineType;
		line.AssignedResource__c = assignedResourceId;
		line.WorkTypeId = workTypeId;
		line.UnitQty__c = quantity;
		line.BillingType__c = 'Non-Billable';

		try {
			upsert line;
		} catch (Exception e) {
			if (line.Discount != null) {
				line.Discount = null;
				try {
					upsert line;
				} catch (Exception retryError) {
					throw new AuraHandledException(retryError.getMessage());
				}
			} else {
				throw new AuraHandledException(e.getMessage());
			}
		}
		return line.Id;
	}

	/**
	 * @description Parses a WOLI Id and rejects draft/local identifiers.
	 * @param value Candidate Id
	 * @return WorkOrderLineItem Id, or null when the value is not a WOLI Id
	 */
	@TestVisible
	private static Id tryWorkOrderLineItemId(String value) {
		if (String.isBlank(value)) {
			return null;
		}
		try {
			Id parsed = Id.valueOf(value);
			if (parsed.getSobjectType() != WorkOrderLineItem.SObjectType) {
				return null;
			}
			return parsed;
		} catch (Exception e) {
			return null;
		}
	}

	/**
	 * @description Builds a display label from product code and/or name.
	 * @param productCode Product Code (optional)
	 * @param name Product Name (optional)
	 * @return Combined label, code-only, name-only, or null when both blank
	 */
	@TestVisible
	private static String formatRepairCodeLabel(String productCode, String name) {
		if (String.isNotBlank(productCode) && String.isNotBlank(name)) {
			return productCode + ' — ' + name;
		}
		if (String.isNotBlank(productCode)) {
			return productCode;
		}
		return name;
	}

	/**
	 * @description Read-only Tray Planner row for the child work order debrief.
	 */
	public class TrayPlannerRow {
		/** @description Tray Planner record Id. */
		@AuraEnabled public Id id;
		/** @description Component name. */
		@AuraEnabled public String componentName;
		/** @description Quantity. */
		@AuraEnabled public Decimal quantity;
		/** @description Supplier / make. */
		@AuraEnabled public String supplier;
		/** @description Catalogue number. */
		@AuraEnabled public String catalogNumber;
		/** @description V. Mueller number. */
		@AuraEnabled public String vMuellerNumber;
		/** @description Device Type product name. */
		@AuraEnabled public String deviceName;
		/** @description Device Type item number. */
		@AuraEnabled public String itemNumber;
	}

	/**
	 * @description Tray Planner records for the Work Order asset.
	 * @param assetId Asset Id on the Work Order
	 * @return Rows ordered by component name; empty when the asset is blank or has none
	 */
	@AuraEnabled(cacheable=true)
	public static List<TrayPlannerRow> getTrayPlanners(Id assetId) {
		List<TrayPlannerRow> rows = new List<TrayPlannerRow>();
		if (assetId == null) {
			return rows;
		}

		for (TrayPlanner__c planner : TrayPlannersSelector.selectByAssetId(assetId)) {
			TrayPlannerRow row = new TrayPlannerRow();
			row.id = planner.Id;
			row.componentName = planner.Name;
			row.quantity = planner.Quantity__c;
			row.supplier = planner.SupplierMake__c;
			row.catalogNumber = planner.CatalogNumber__c;
			row.vMuellerNumber = planner.VMuellerNumber__c;
			row.deviceName = planner.DeviceType__r?.Name;
			row.itemNumber = planner.DeviceType__r?.ProductCode;
			rows.add(row);
		}
		return rows;
	}

	/**
	 * @description Department option for the repair-center instrument form.
	 */
	public class DepartmentOption implements Comparable {
		/** @description Department__c Id. */
		@AuraEnabled public Id id;
		/** @description Department name. */
		@AuraEnabled public String name;

		/**
		 * @description Orders options by department name.
		 * @param other Another DepartmentOption
		 * @return Comparison result
		 */
		public Integer compareTo(Object other) {
			DepartmentOption that = (DepartmentOption) other;
			String left = this.name == null ? '' : this.name;
			String right = that.name == null ? '' : that.name;
			return left.toLowerCase().compareTo(right.toLowerCase());
		}
	}

	/**
	 * @description Departments linked to the Work Order account.
	 * @param accountId Work Order Account Id
	 * @return Department options ordered by name
	 */
	@AuraEnabled(cacheable=true)
	public static List<DepartmentOption> getDepartmentsForAccount(Id accountId) {
		Map<Id, DepartmentOption> optionsById = new Map<Id, DepartmentOption>();
		if (accountId == null) {
			return new List<DepartmentOption>();
		}

		List<AccountDepartment__c> links = AccountDepartmentsSelector.selectByAccountId(
			new Set<Id>{ accountId }
		);
		Set<Id> departmentIds = new Set<Id>();
		for (AccountDepartment__c link : links) {
			if (link.Department__c != null) {
				departmentIds.add(link.Department__c);
			}
		}
		Map<Id, Department__c> departmentsById = new Map<Id, Department__c>(
			DepartmentsSelector.selectById(departmentIds)
		);
		for (Id departmentId : departmentIds) {
			if (optionsById.containsKey(departmentId)) {
				continue;
			}
			DepartmentOption option = new DepartmentOption();
			option.id = departmentId;
			option.name = departmentsById.get(departmentId)?.Name;
			optionsById.put(departmentId, option);
		}
		List<DepartmentOption> options = optionsById.values();
		options.sort();
		return options;
	}

	/**
	 * @description Links uploaded pictures to a Work Order Line Item after the line is saved.
	 * @param recordId Work Order Line Item Id
	 * @param contentDocumentIds Files uploaded before the line existed
	 */
	@AuraEnabled
	public static void linkFilesToRecord(Id recordId, List<Id> contentDocumentIds) {
		if (recordId == null || contentDocumentIds == null || contentDocumentIds.isEmpty()) {
			return;
		}

		Set<Id> documentIds = new Set<Id>(contentDocumentIds);
		documentIds.remove(null);
		if (documentIds.isEmpty()) {
			return;
		}

		Set<Id> alreadyLinked = new Set<Id>();
		for (ContentDocumentLink existingLink : ContentDocumentLinksSelector.selectByDocumentsAndLinkedEntities(
			documentIds,
			new Set<Id>{ recordId }
		)) {
			alreadyLinked.add(existingLink.ContentDocumentId);
		}

		List<ContentDocumentLink> links = new List<ContentDocumentLink>();
		for (Id documentId : documentIds) {
			if (alreadyLinked.contains(documentId)) {
				continue;
			}
			ContentDocumentLink link = new ContentDocumentLink();
			link.ContentDocumentId = documentId;
			link.LinkedEntityId = recordId;
			link.ShareType = 'V';
			link.Visibility = 'AllUsers';
			links.add(link);
		}
		if (!links.isEmpty()) {
			insert links;
		}
	}

	/**
	 * @description GW-375 - A Mobile Device Picture linked to a child work order or instrument line.
	 */
	public class MobileDevicePicture {
		/** @description ContentDocument Id. Deleting this removes the file from every linked record. */
		@AuraEnabled public Id contentDocumentId;
		/** @description Latest ContentVersion Id, used for preview. */
		@AuraEnabled public Id contentVersionId;
		/** @description Child work order or Work Order Line Item the picture is listed under. */
		@AuraEnabled public Id linkedEntityId;
		/** @description File title. */
		@AuraEnabled public String title;
		/** @description GW-6437 - Optional CRSS debrief comment for this picture. */
		@AuraEnabled public String comment;
		/** @description GW-375 - Beyond Repair, Care and Handling, Extensive Repair, or Technical Excellence. */
		@AuraEnabled public String category;
		/** @description GW-375 - Before or After. */
		@AuraEnabled public String beforeAfter;
	}

	/**
	 * @description GW-375 - Category, Before/After, and comment chosen when the picture is taken.
	 */
	public class PictureDetails {
		public String category;
		public String beforeAfter;
		public String comment;
		/** @description GW-6340 - Microscope Picture for microscopic camera pictures; otherwise Mobile Device Picture. */
		public String title;
	}

	/**
	 * @description GW-375 - Lists Mobile Device Pictures for the CRSS debrief on Field Service Mobile.
	 *              The mobile app does not expose Apex actions that take List parameters.
	 * @param recordIdsCsv Comma-separated work order and line ids
	 * @return Mobile Device Pictures linked to those records
	 */
	@AuraEnabled
	public static List<MobileDevicePicture> listMobileDevicePictures(String recordIdsCsv) {
		List<String> recordIds = new List<String>();
		if (String.isNotBlank(recordIdsCsv)) {
			for (String token : recordIdsCsv.split(',')) {
				String part = token == null ? '' : token.trim();
				if (!String.isBlank(part)) {
					recordIds.add(part);
				}
			}
		}
		return getMobileDevicePictures(recordIds);
	}

	/**
	 * @description GW-375 - Lists Mobile Device Pictures for the child work order and instrument lines.
	 * @param recordIds Child Work Order Id and Instrument Work Order Line Item Ids
	 * @return Mobile Device Pictures linked to those records
	 */
	public static List<MobileDevicePicture> getMobileDevicePictures(List<String> recordIds) {
		List<MobileDevicePicture> pictures = new List<MobileDevicePicture>();
		Set<Id> recordIdSet = expandRecordIdsForPictureList(recordIds);
		if (recordIdSet.isEmpty()) {
			return pictures;
		}

		// GW-375: Field Service users often lack CDL read via SECURITY_ENFORCED selectors.
		List<ContentDocumentLink> links = [
			SELECT ContentDocumentId, LinkedEntityId
			FROM ContentDocumentLink
			WHERE LinkedEntityId IN :recordIdSet
		];
		Set<Id> documentIds = new Set<Id>();
		for (ContentDocumentLink link : links) {
			if (link.ContentDocumentId != null) {
				documentIds.add(link.ContentDocumentId);
			}
		}
		Map<Id, ContentVersion> versionByDocumentId = new Map<Id, ContentVersion>();
		for (ContentVersion version : selectMobileDevicePictures(documentIds)) {
			versionByDocumentId.put(version.ContentDocumentId, version);
		}
		for (ContentDocumentLink link : links) {
			ContentVersion version = versionByDocumentId.get(link.ContentDocumentId);
			if (version == null) {
				continue;
			}
			pictures.add(toMobileDevicePicture(version, link.LinkedEntityId));
		}
		return pictures;
	}

	/**
	 * @description GW-375 - Image body for a saved Mobile Device Picture.
	 *              The mobile app does not paint the file download link inside the preview,
	 *              so the screen shows these bytes directly, the same way an unsaved line picture is shown.
	 * @param contentVersionId Latest ContentVersion Id of a Mobile Device Picture
	 * @return Base64 image body, without a data-url prefix
	 */
	@AuraEnabled
	public static String getMobileDevicePictureData(String contentVersionId) {
		Id versionId = parseRecordId(contentVersionId);
		if (versionId == null) {
			throw auraException('A picture is required.');
		}
		List<ContentVersion> versions = [
			SELECT VersionData
			FROM ContentVersion
			WHERE Id = :versionId
				AND IsLatest = true
				AND (Description = :MOBILE_DEVICE_PICTURE_MARKER OR Title IN :PICTURE_TITLES)
			LIMIT 1
		];
		if (versions.isEmpty() || versions[0].VersionData == null) {
			throw auraException('The picture could not be previewed.');
		}
		return EncodingUtil.base64Encode(versions[0].VersionData);
	}

	/**
	 * @description GW-375 - Saves a Mobile Device Picture on the primary record and the site visit work order.
	 *              Instrument pictures use the Work Order Line Item as the primary record.
	 *              Tray pictures use the child Work Order as the primary record.
	 * @param primaryRecordId Instrument line or child Work Order
	 * @param parentWorkOrderId Site visit Work Order. The same file is linked here when it is a different record.
	 * @param base64Data Image data, with or without a data-url prefix
	 * @param fileName Client file name
	 * @param workOrderIdForResolve Work order that owns the line. Used when the mobile app damages the primary id.
	 * @return Saved picture
	 */
	@AuraEnabled
	public static MobileDevicePicture saveMobileDevicePicture(
		String primaryRecordId,
		String parentWorkOrderId,
		String base64Data,
		String fileName,
		String workOrderIdForResolve
	) {
		return savePrimaryMobileDevicePicture(
			primaryRecordId,
			parentWorkOrderId,
			base64Data,
			fileName,
			workOrderIdForResolve,
			null
		);
	}

	/**
	 * @description GW-375 - Saves a Mobile Device Picture with its Category, Before/After, and comment
	 *              on the instrument line or child work order, and links it to the site visit work order.
	 * @param primaryRecordId Instrument line or child Work Order
	 * @param parentWorkOrderId Site visit Work Order
	 * @param base64Data Image data, with or without a data-url prefix
	 * @param fileName Client file name
	 * @param pictureDetails JSON with category, beforeAfter, and comment
	 * @return Saved picture
	 */
	@AuraEnabled
	public static MobileDevicePicture saveMobileDevicePictureWithDetails(
		String primaryRecordId,
		String parentWorkOrderId,
		String base64Data,
		String fileName,
		String pictureDetails
	) {
		return savePrimaryMobileDevicePicture(
			primaryRecordId,
			parentWorkOrderId,
			base64Data,
			fileName,
			null,
			parsePictureDetails(pictureDetails)
		);
	}

	private static MobileDevicePicture savePrimaryMobileDevicePicture(
		String primaryRecordId,
		String parentWorkOrderId,
		String base64Data,
		String fileName,
		String workOrderIdForResolve,
		PictureDetails details
	) {
		PrimaryPictureTarget target = parsePrimaryPictureTarget(primaryRecordId, workOrderIdForResolve);
		Id primaryId = target.primaryId;
		if (primaryId == null
			&& String.isNotBlank(workOrderIdForResolve)
			&& isWorkOrderHeaderPictureRequest(primaryRecordId)) {
			String resolvedWorkOrder = resolveMobilePictureRecordId(
				workOrderIdForResolve,
				workOrderIdForResolve
			);
			primaryId = parseRecordId(resolvedWorkOrder);
		}
		if (primaryId == null || !picturePrimaryRecordExists(primaryId)) {
			throw auraException('A record is required to save the picture.');
		}
		Id parentId = parseRecordId(parentWorkOrderId);
		return insertMobileDevicePictureWithDetails(primaryId, parentId, base64Data, fileName, details);
	}
	/**
	 * @description GW-375 - Saves a Mobile Device Picture on the site visit work order header.
	 *              Uses only String parameters for Field Service Mobile.
	 * @param workOrderIdValue Work Order Id from the debrief screen
	 * @param base64Data Image data
	 * @param fileName Client file name
	 * @return Saved picture
	 */
	@AuraEnabled
	public static MobileDevicePicture saveWorkOrderHeaderMobileDevicePicture(
		String pictureUploadContext,
		String base64Data
	) {
		PictureCommentSplit split = splitPictureUploadComment(pictureUploadContext);
		Id workOrderId = resolveWorkOrderId(split.payload);
		if (workOrderId == null || !picturePrimaryRecordExists(workOrderId)) {
			throw auraException('A record is required to save the picture.');
		}
		return insertMobileDevicePicture(
			workOrderId,
			null,
			base64Data,
			'MobileDevicePicture.jpg',
			split.comment
		);
	}

	/**
	 * @description GW-375 - Saves a Mobile Device Picture on a Product Serviced line.
	 *              Uses only String parameters for Field Service Mobile.
	 * @param workOrderIdValue Work Order that owns the line
	 * @param lineIdValue Work Order Line Item Id from GraphQL (may be lowercased on mobile)
	 * @param base64Data Image data
	 * @param fileName Client file name
	 * @return Saved picture
	 */
	@AuraEnabled
	public static MobileDevicePicture saveProductServicedLineMobileDevicePicture(
		String pictureUploadContext,
		String base64Data
	) {
		LinePictureUpload upload = parseLinePictureUpload(pictureUploadContext, base64Data);
		if (upload.lineId == null) {
			throw auraException('A Product Serviced line is required to save the picture.');
		}
		if (!picturePrimaryRecordExists(upload.lineId)) {
			throw auraException('A Product Serviced line is required to save the picture.');
		}
		return insertMobileDevicePicture(
			upload.lineId,
			null,
			upload.base64Data,
			'MobileDevicePicture.jpg',
			upload.comment
		);
	}

	/**
	 * @description GW-375 - Reads the Product Serviced line id from the image payload.
	 *              Field Service Mobile replaces a bare line id with the work order id.
	 *              The id is split with a dot and sent inside the image string.
	 */
	private class LinePictureUpload {
		private Id lineId;
		private String comment;
		private String base64Data;
	}

	/**
	 * @description GW-375 - Line id, comment, and image body from a mobile upload.
	 * @param pictureUploadContext Context string, possibly replaced by the mobile app
	 * @param base64Data Image data, with the line id embedded when the client sent one
	 * @return Parsed upload
	 */
	private static LinePictureUpload parseLinePictureUpload(String pictureUploadContext, String base64Data) {
		LinePictureUpload upload = new LinePictureUpload();
		upload.base64Data = base64Data;
		upload.comment = '';
		String data = String.isBlank(base64Data) ? '' : base64Data;
		Integer mark = data.indexOf(LINE_PICTURE_EMBED_MARK);
		if (data.startsWith('ps.') && mark > 0) {
			PictureCommentSplit embedded = splitPictureUploadComment(data.substring(0, mark));
			upload.base64Data = data.substring(mark + LINE_PICTURE_EMBED_MARK.length());
			upload.lineId = lineIdFromMobileToken(embedded.payload);
			upload.comment = embedded.comment;
		}
		PictureCommentSplit split = splitPictureUploadComment(pictureUploadContext);
		if (upload.lineId == null) {
			upload.lineId = lineIdFromMobileToken(split.payload);
		}
		if (String.isBlank(upload.comment)) {
			upload.comment = split.comment;
		}
		return upload;
	}

	/**
	 * @description GW-375 - Turns a mobile line token into a Work Order Line Item Id.
	 *              Accepts ps.#####.rest, a bare line id, or an older composite token.
	 * @param token Upload token
	 * @return Work Order Line Item Id, or null
	 */
	private static Id lineIdFromMobileToken(String token) {
		if (String.isBlank(token)) {
			return null;
		}
		String value = token.trim();
		String newLineContext = '';
		if (value.startsWith('ps.')) {
			value = value.substring(3);
			Integer contextSplit = value.indexOf(LINE_PICTURE_CONTEXT_MARK);
			if (contextSplit >= 0) {
				newLineContext = value.substring(contextSplit + LINE_PICTURE_CONTEXT_MARK.length());
				value = value.substring(0, contextSplit);
			}
			value = value.replace('.', '');
		}
		Id lineId = parseProductServicedLineIdFromUploadToken(value);
		if (lineId != null && picturePrimaryRecordExists(lineId)) {
			return lineId;
		}
		Id newLineId = newProductServicedLineFromContext(newLineContext);
		if (newLineId != null) {
			return newLineId;
		}
		if (lineId == null) {
			lineId = resolveProductServicedLineIdFromUploadContext(value);
		}
		return lineId;
	}

	/**
	 * @description GW-6017 - Finds a Product Serviced line the current user just synced from the mobile app.
	 *              The app returns a temporary line id until the line reaches Salesforce, so the
	 *              line is looked up by its work order and asset instead.
	 * @param context Work order and asset ids, each split with dots, joined by the context mark
	 * @return Newest matching Work Order Line Item Id, or null
	 */
	private static Id newProductServicedLineFromContext(String context) {
		if (String.isBlank(context)) {
			return null;
		}
		List<String> parts = context.split(LINE_PICTURE_CONTEXT_MARK, -1);
		Id workOrderId = parseRecordId(parts[0].replace('.', ''));
		if (workOrderId == null || workOrderId.getSobjectType() != WorkOrder.SObjectType) {
			return null;
		}
		Id assetId = parts.size() > 1 ? parseRecordId(parts[1].replace('.', '')) : null;
		Id userId = UserInfo.getUserId();
		Datetime createdAfter = Datetime.now().addMinutes(-NEW_LINE_PICTURE_LOOKBACK_MINUTES);
		List<WorkOrderLineItem> lines = assetId != null
			? [
				SELECT Id
				FROM WorkOrderLineItem
				WHERE WorkOrderId = :workOrderId
					AND LineType__c = 'Product Serviced'
					AND AssetId = :assetId
					AND CreatedById = :userId
					AND CreatedDate >= :createdAfter
				ORDER BY CreatedDate DESC
				LIMIT 1
			]
			: [
				SELECT Id
				FROM WorkOrderLineItem
				WHERE WorkOrderId = :workOrderId
					AND LineType__c = 'Product Serviced'
					AND CreatedById = :userId
					AND CreatedDate >= :createdAfter
				ORDER BY CreatedDate DESC
				LIMIT 1
			];
		return lines.isEmpty() ? null : lines[0].Id;
	}

	/**
	 * @description GW-375 - Parses a known Work Order Line Item id from Save All or the debrief screen.
	 *              Used before composite mobile repair tokens are considered.
	 * @param payload Upload token without the optional comment suffix
	 * @return Work Order Line Item Id, or null
	 */
	private static Id parseProductServicedLineIdFromUploadToken(String payload) {
		if (String.isBlank(payload)) {
			return null;
		}
		String token = payload.trim();
		Integer compositeSplit = token.indexOf('::');
		if (compositeSplit > 0) {
			token = token.substring(compositeSplit + 2).trim();
		}
		Id lineId = parseRecordId(token);
		if (lineId != null && lineId.getSobjectType() == WorkOrderLineItem.SObjectType) {
			return lineId;
		}
		return null;
	}

	/**
	 * @description GW-375 - Saves a Mobile Device Picture on a Work Order Line Item that was just created.
	 *              Used after Save All when staged photos were taken before the line existed.
	 * @param workOrderLineItemIdValue WOLI Id, optionally lineId|workOrderId for mobile id repair
	 * @param base64Data Image data
	 * @param fileName Client file name
	 * @return Saved picture
	 */
	@AuraEnabled
	public static MobileDevicePicture saveMobileDevicePictureOnWorkOrderLineItem(
		String pictureUploadContext,
		String base64Data
	) {
		PictureCommentSplit split = splitPictureUploadComment(pictureUploadContext);
		String fileName = 'MobileDevicePicture.jpg';
		String linePayload = String.isBlank(split.payload) ? '' : split.payload.trim();
		Integer contextSplit = linePayload.indexOf('||');
		if (contextSplit > 0) {
			fileName = linePayload.substring(0, contextSplit).trim();
			linePayload = linePayload.substring(contextSplit + 2).trim();
		}
		Id lineId = resolveProductServicedLineIdFromUploadContext(linePayload);
		if (lineId == null) {
			lineId = resolveProductServicedLineIdFromUploadContext(split.payload);
		}
		if (lineId == null) {
			lineId = resolveCreatedWorkOrderLineItemId(linePayload, fileName);
		}
		if (lineId == null || !picturePrimaryRecordExists(lineId)) {
			throw auraException('A Product Serviced line is required to save the picture.');
		}
		return insertMobileDevicePicture(lineId, null, base64Data, fileName, split.comment);
	}

	/**
	 * @description GW-6437 - Updates the CRSS comment on a saved Mobile Device Picture.
	 * @param contentDocumentIdValue ContentDocument Id
	 * @param pictureComment Comment text
	 */
	@AuraEnabled
	public static MobileDevicePicture updateMobileDevicePictureComment(
		String contentDocumentIdValue,
		String pictureComment
	) {
		Id contentDocumentId = parseRecordId(contentDocumentIdValue);
		if (contentDocumentId == null) {
			throw auraException('A picture is required.');
		}
		List<ContentVersion> versions = selectMobileDevicePictures(new Set<Id>{ contentDocumentId });
		if (versions.isEmpty()) {
			throw auraException('Only a Mobile Device Picture can be updated here.');
		}
		ContentVersion version = versions[0];
		version.MobileDevicePictureComment__c = normalizeMobilePictureComment(pictureComment);
		update version;
		Id linkedEntityId = null;
		for (ContentDocumentLink link : [
			SELECT LinkedEntityId
			FROM ContentDocumentLink
			WHERE ContentDocumentId = :contentDocumentId
			LIMIT 1
		]) {
			linkedEntityId = link.LinkedEntityId;
			break;
		}
		return toMobileDevicePicture(version, linkedEntityId);
	}

	/**
	 * @description GW-375 - Resolves a WOLI Id returned from createRecord or a mobile-damaged token.
	 * @param workOrderLineItemIdValue Raw id, or lineId|workOrderId
	 * @return Work Order Line Item Id, or null
	 */
	private static Id resolveCreatedWorkOrderLineItemId(String workOrderLineItemIdValue, String fileName) {
		CreatedLinePictureContext context = parseCreatedLinePictureContext(
			workOrderLineItemIdValue,
			fileName
		);
		if (context == null) {
			return null;
		}
		Id lineId = parseRecordId(context.lineToken);
		if (lineId != null && lineId.getSobjectType() == WorkOrderLineItem.SObjectType) {
			return lineId;
		}
		Id workOrderId = resolveWorkOrderId(context.workOrderToken);
		String linePrefix = idPrefix(context.lineToken);
		if (workOrderId != null && linePrefix != null) {
			Id matched = matchLineOnWorkOrderByPrefix(workOrderId, linePrefix, false);
			if (matched != null) {
				return matched;
			}
		}
		lineId = resolveDirectWorkOrderLineItemId(context.lineToken);
		if (lineId != null) {
			return lineId;
		}
		if (workOrderId != null) {
			Id latest = findLatestProductServicedLineIdOnWorkOrder(workOrderId, context.assetToken);
			if (latest != null) {
				return latest;
			}
			return findNewestWorkOrderLineItemOnWorkOrder(workOrderId);
		}
		if (fromNameContextHasWorkOrder(fromNameContext(fileName))) {
			CreatedLinePictureContext fileContext = fromNameContext(fileName);
			Id workOrderIdFromName = resolveWorkOrderId(fileContext.workOrderToken);
			if (workOrderIdFromName != null) {
				return findLatestProductServicedLineIdOnWorkOrder(
					workOrderIdFromName,
					fileContext.assetToken
				);
			}
		}
		return null;
	}

	/**
	 * @description GW-375 - Parsed file-name context when the pipe payload is missing.
	 * @param fileName Client file name
	 * @return Parsed context, or null
	 */
	private static CreatedLinePictureContext fromNameContext(String fileName) {
		return parseCreatedLinePictureFileName(fileName);
	}

	/**
	 * @description GW-375 - True when the file name carries a work order token.
	 * @param context Parsed file-name context
	 * @return True when a work order token is present
	 */
	private static Boolean fromNameContextHasWorkOrder(CreatedLinePictureContext context) {
		return context != null && String.isNotBlank(context.workOrderToken);
	}

	/**
	 * @description GW-375 - Parsed upload context for a staged new-line picture.
	 */
	private class CreatedLinePictureContext {
		private String lineToken;
		private String workOrderToken;
		private String assetToken;
	}

	/**
	 * @description GW-375 - Reads line, work order, and asset tokens from the mobile payload.
	 * @param workOrderLineItemIdValue lineId|workOrderId|assetId from the LWC
	 * @param fileName Backup carrier when Field Service Mobile drops id parameters
	 * @return Parsed context, or null
	 */
	private static CreatedLinePictureContext parseCreatedLinePictureContext(
		String workOrderLineItemIdValue,
		String fileName
	) {
		CreatedLinePictureContext context = new CreatedLinePictureContext();
		context.lineToken = '';
		context.workOrderToken = '';
		context.assetToken = '';
		if (String.isNotBlank(workOrderLineItemIdValue)) {
			List<String> parts = workOrderLineItemIdValue.trim().split('\\|', -1);
			context.lineToken = parts.size() > 0 ? parts[0].trim() : '';
			context.workOrderToken = parts.size() > 1 ? parts[1].trim() : '';
			context.assetToken = parts.size() > 2 ? parts[2].trim() : '';
		}
		CreatedLinePictureContext fromName = parseCreatedLinePictureFileName(fileName);
		if (fromName != null) {
			if (String.isBlank(context.lineToken) || isWorkOrderIdToken(context.lineToken)) {
				context.lineToken = fromName.lineToken;
			}
			if (String.isBlank(context.workOrderToken)) {
				context.workOrderToken = fromName.workOrderToken;
			}
			if (String.isBlank(context.assetToken)) {
				context.assetToken = fromName.assetToken;
			}
		}
		if (String.isBlank(context.workOrderToken)
			&& String.isBlank(context.lineToken)
			&& String.isBlank(context.assetToken)) {
			return null;
		}
		return context;
	}

	/**
	 * @description GW-375 - Backup line context embedded in the upload file name.
	 *              Format: GW375;lineId;workOrderId;assetId;MobileDevicePicture.jpg
	 * @param fileName Client file name
	 * @return Parsed context, or null
	 */
	private static CreatedLinePictureContext parseCreatedLinePictureFileName(String fileName) {
		if (String.isBlank(fileName) || !fileName.startsWith('GW375;')) {
			return null;
		}
		String body = fileName.substring(6);
		Integer semi = body.indexOf(';');
		if (semi < 0) {
			return null;
		}
		CreatedLinePictureContext context = new CreatedLinePictureContext();
		context.lineToken = body.substring(0, semi).trim();
		body = body.substring(semi + 1);
		semi = body.indexOf(';');
		if (semi < 0) {
			return null;
		}
		context.workOrderToken = body.substring(0, semi).trim();
		body = body.substring(semi + 1);
		semi = body.indexOf(';');
		if (semi < 0) {
			return null;
		}
		context.assetToken = body.substring(0, semi).trim();
		return context;
	}

	/**
	 * @description GW-375 - Newest Product Serviced line on a work order, optionally for one asset.
	 * @param workOrderId Work Order Id
	 * @param assetIdValue Asset Id token
	 * @return Work Order Line Item Id, or null
	 */
	private static Id findLatestProductServicedLineIdOnWorkOrder(Id workOrderId, String assetIdValue) {
		if (workOrderId == null) {
			return null;
		}
		String assetKey = idPrefix(assetIdValue);
		List<WorkOrderLineItem> productServicedLines = [
			SELECT Id, AssetId
			FROM WorkOrderLineItem
			WHERE WorkOrderId = :workOrderId
				AND LineType__c = 'Product Serviced'
			ORDER BY CreatedDate DESC
			LIMIT 50
		];
		for (WorkOrderLineItem line : productServicedLines) {
			if (assetKey == null || idPrefix(line.AssetId) == assetKey) {
				return line.Id;
			}
		}
		if (!productServicedLines.isEmpty()) {
			return productServicedLines[0].Id;
		}
		return null;
	}

	/**
	 * @description GW-375 - Newest line on a work order when Product Serviced filters return nothing.
	 * @param workOrderId Work Order Id
	 * @return Work Order Line Item Id, or null
	 */
	private static Id findNewestWorkOrderLineItemOnWorkOrder(Id workOrderId) {
		if (workOrderId == null) {
			return null;
		}
		List<WorkOrderLineItem> lines = [
			SELECT Id
			FROM WorkOrderLineItem
			WHERE WorkOrderId = :workOrderId
			ORDER BY CreatedDate DESC
			LIMIT 1
		];
		return lines.isEmpty() ? null : lines[0].Id;
	}

	/**
	 * @description GW-375 - Inserts a Mobile Device Picture on one Salesforce record.
	 * @param primaryId Work Order or Work Order Line Item
	 * @param parentId Optional second link target
	 * @param base64Data Image data
	 * @param fileName Client file name
	 * @return Saved picture
	 */
	private static MobileDevicePicture insertMobileDevicePicture(
		Id primaryId,
		Id parentId,
		String base64Data,
		String fileName
	) {
		return insertMobileDevicePicture(primaryId, parentId, base64Data, fileName, null);
	}

	/**
	 * @description GW-6437 - Inserts a Mobile Device Picture with an optional CRSS comment.
	 * @param primaryId Work Order or Work Order Line Item
	 * @param parentId Optional second link target
	 * @param base64Data Image data
	 * @param fileName Client file name
	 * @param pictureComment Optional CRSS comment
	 * @return Saved picture
	 */
	private static MobileDevicePicture insertMobileDevicePicture(
		Id primaryId,
		Id parentId,
		String base64Data,
		String fileName,
		String pictureComment
	) {
		PictureDetails details = new PictureDetails();
		details.comment = pictureComment;
		return insertMobileDevicePictureWithDetails(primaryId, parentId, base64Data, fileName, details);
	}

	/**
	 * @description GW-375 - Inserts a Mobile Device Picture with its Category, Before/After, and comment.
	 * @param primaryId Work Order or Work Order Line Item
	 * @param parentId Optional second link target
	 * @param base64Data Image data
	 * @param fileName Client file name
	 * @param details Picture details, or null
	 * @return Saved picture
	 */
	private static MobileDevicePicture insertMobileDevicePictureWithDetails(
		Id primaryId,
		Id parentId,
		String base64Data,
		String fileName,
		PictureDetails details
	) {
		ContentVersion version = new ContentVersion();
		version.Title = pictureTitle(details);
		version.PathOnClient = mobilePictureFileName(fileName);
		version.VersionData = decodeMobilePicture(base64Data);
		version.Description = MOBILE_DEVICE_PICTURE_MARKER;
		applyPictureDetails(version, details);
		version.FirstPublishLocationId = primaryId;
		try {
			TriggerHandler.bypass('ContentDocumentLinkTriggerHandler');
			TriggerHandler.bypass('RepairCenterCdlTriggerHandler');
			AutomationControl.disableTrigger('ContentDocumentLinkTrigger');
			AutomationControl.disableTrigger('RepairCenterCdlTrigger');
			insert version;
		} catch (DmlException ex) {
			throw auraException(mobilePictureDmlMessage(ex));
		} finally {
			TriggerHandler.clearBypass('ContentDocumentLinkTriggerHandler');
			TriggerHandler.clearBypass('RepairCenterCdlTriggerHandler');
			AutomationControl.enableTrigger('ContentDocumentLinkTrigger');
			AutomationControl.enableTrigger('RepairCenterCdlTrigger');
		}

		List<ContentVersion> saved = [
			SELECT Id, ContentDocumentId, Title, Description, MobileDevicePictureComment__c,
				PictureCategory__c, BeforeAfter__c
			FROM ContentVersion
			WHERE Id = :version.Id
			LIMIT 1
		];
		if (saved.isEmpty() || saved[0].ContentDocumentId == null) {
			throw auraException('The picture was uploaded but could not be read back.');
		}
		if (parentId != null && parentId != primaryId) {
			try {
				linkFilesToRecord(parentId, new List<Id>{ saved[0].ContentDocumentId });
			} catch (Exception ex) {
				Logger.error('Mobile device picture parent link will be queued', ex);
				Logger.saveLog();
				MobileDevicePictureLinkHandler.publishParentLink(
					saved[0].ContentDocumentId,
					parentId
				);
			}
		}
		refreshMobileDevicePictureCount(new Set<Id>{ primaryId });
		return toMobileDevicePicture(saved[0], primaryId);
	}

	/**
	 * @description GW-375 - Resolves a Work Order Id from the debrief screen.
	 * @param workOrderIdValue Raw id
	 * @return Work Order Id, or null
	 */
	private static Id resolveWorkOrderId(String workOrderIdValue) {
		if (String.isBlank(workOrderIdValue)) {
			return null;
		}
		String resolved = resolveMobilePictureRecordId(workOrderIdValue, workOrderIdValue);
		Id workOrderId = parseRecordId(resolved);
		if (workOrderId != null && workOrderId.getSobjectType() == WorkOrder.SObjectType) {
			return workOrderId;
		}
		return null;
	}

	/**
	 * @description GW-375 - Deletes a Mobile Device Picture from the primary record and the site visit work order.
	 * @param contentDocumentId ContentDocument Id of the Mobile Device Picture
	 */
	@AuraEnabled
	public static void deleteMobileDevicePicture(Id contentDocumentId) {
		if (contentDocumentId == null) {
			return;
		}
		List<ContentVersion> versions = selectMobileDevicePictures(new Set<Id>{ contentDocumentId });
		if (versions.isEmpty()) {
			throw auraException('Only a Mobile Device Picture can be deleted here.');
		}
		Set<Id> linkedRecordIds = new Set<Id>();
		for (ContentDocumentLink link : ContentDocumentLinksSelector.selectByContentDocumentId(
			new Set<Id>{ contentDocumentId }
		)) {
			linkedRecordIds.add(link.LinkedEntityId);
		}
		List<ContentDocument> documents = ContentDocumentsSelector.selectById(
			new Set<Id>{ contentDocumentId }
		);
		if (!documents.isEmpty()) {
			delete documents;
		}
		refreshMobileDevicePictureCount(linkedRecordIds);
	}

	/**
	 * @description GW-375 - Writes the Mobile Device Picture count onto each instrument line.
	 *              Tray pictures are stored on the child work order and do not change this field.
	 * @param recordIds Records the picture was linked to. Only Work Order Line Items are updated.
	 */
	public static void refreshMobileDevicePictureCount(Set<Id> recordIds) {
		if (recordIds == null || recordIds.isEmpty()) {
			return;
		}
		Set<Id> lineIds = new Set<Id>();
		for (Id recordId : recordIds) {
			if (recordId != null && recordId.getSobjectType() == WorkOrderLineItem.SObjectType) {
				lineIds.add(recordId);
			}
		}
		if (lineIds.isEmpty()) {
			return;
		}
		Map<Id, Integer> countByLineId = new Map<Id, Integer>();
		for (Id lineId : lineIds) {
			countByLineId.put(lineId, 0);
		}
		List<String> lineIdValues = new List<String>();
		for (Id lineId : lineIds) {
			lineIdValues.add(String.valueOf(lineId));
		}
		for (MobileDevicePicture picture : getMobileDevicePictures(lineIdValues)) {
			if (picture.linkedEntityId != null && countByLineId.containsKey(picture.linkedEntityId)) {
				countByLineId.put(
					picture.linkedEntityId,
					countByLineId.get(picture.linkedEntityId) + 1
				);
			}
		}
		List<WorkOrderLineItem> lines = new List<WorkOrderLineItem>();
		for (Id lineId : countByLineId.keySet()) {
			lines.add(new WorkOrderLineItem(
				Id = lineId,
				MobileDevicePictureCount__c = countByLineId.get(lineId)
			));
		}
		update lines;
	}

	/**
	 * @description GW-375 - Latest Mobile Device Pictures. Kept on this controller so the
	 *              shared ContentVersionsSelector does not need a deployment for this story.
	 *              Description separates these files from a future connected camera. Title is also
	 *              accepted because the mobile app file upload may not keep the description.
	 * @param contentDocumentIds ContentDocument Ids already linked to the requested records
	 * @return Matching latest versions, oldest first
	 */
	private static List<ContentVersion> selectMobileDevicePictures(Set<Id> contentDocumentIds) {
		if (contentDocumentIds == null || contentDocumentIds.isEmpty()) {
			return new List<ContentVersion>();
		}
		return [
			SELECT Id, ContentDocumentId, Title, Description, CreatedDate, MobileDevicePictureComment__c,
				PictureCategory__c, BeforeAfter__c
			FROM ContentVersion
			WHERE ContentDocumentId IN :contentDocumentIds
				AND IsLatest = true
				AND (Description = :MOBILE_DEVICE_PICTURE_MARKER OR Title IN :PICTURE_TITLES)
			ORDER BY CreatedDate ASC
		];
	}

	/**
	 * @description Builds the LWC picture row.
	 * @param version Latest ContentVersion
	 * @param linkedEntityId Record the picture is listed under
	 * @return Picture row
	 */
	private static MobileDevicePicture toMobileDevicePicture(ContentVersion version, Id linkedEntityId) {
		MobileDevicePicture picture = new MobileDevicePicture();
		picture.contentDocumentId = version.ContentDocumentId;
		picture.contentVersionId = version.Id;
		picture.linkedEntityId = linkedEntityId;
		picture.title = version.Title;
		picture.comment = version.MobileDevicePictureComment__c;
		picture.category = version.PictureCategory__c;
		picture.beforeAfter = version.BeforeAfter__c;
		return picture;
	}

	/**
	 * @description GW-375 - Reads picture details sent as JSON by the debrief screen.
	 * @param value JSON with category, beforeAfter, and comment
	 * @return Details, or null when blank
	 */
	@TestVisible
	private static PictureDetails parsePictureDetails(String value) {
		if (String.isBlank(value)) {
			return null;
		}
		try {
			return (PictureDetails) JSON.deserialize(value, PictureDetails.class);
		} catch (JSONException ex) {
			throw auraException('The picture details could not be read.');
		}
	}

	/**
	 * @description GW-6340 - File title of a new debrief picture.
	 * @param details Picture details, or null
	 * @return Microscope Picture when requested; otherwise Mobile Device Picture
	 */
	@TestVisible
	private static String pictureTitle(PictureDetails details) {
		return details != null && details.title == MICROSCOPE_PICTURE_TITLE
			? MICROSCOPE_PICTURE_TITLE
			: MOBILE_DEVICE_PICTURE_TITLE;
	}

	/**
	 * @description GW-375 - Writes picture details onto a ContentVersion.
	 * @param version ContentVersion to update
	 * @param details Picture details, or null
	 */
	private static void applyPictureDetails(ContentVersion version, PictureDetails details) {
		if (details == null) {
			return;
		}
		version.MobileDevicePictureComment__c = normalizeMobilePictureComment(details.comment);
		version.PictureCategory__c = String.isBlank(details.category) ? null : details.category.trim();
		version.BeforeAfter__c = String.isBlank(details.beforeAfter) ? null : details.beforeAfter.trim();
	}

	/**
	 * @description GW-375 - Moves picture details the mobile app put in the description into their fields,
	 *              and leaves only the marker in the description so the picture is still found and counted.
	 * @param versions Latest Mobile Device Picture versions with Id and Description
	 */
	public static void applyPictureDetailsFromDescription(List<ContentVersion> versions) {
		String prefix = MOBILE_DEVICE_PICTURE_MARKER + PICTURE_DETAILS_SEPARATOR;
		List<ContentVersion> updates = new List<ContentVersion>();
		for (ContentVersion version : versions == null ? new List<ContentVersion>() : versions) {
			if (version?.Description == null || !version.Description.startsWith(prefix)) {
				continue;
			}
			PictureDetails details;
			try {
				details = parsePictureDetails(version.Description.substring(prefix.length()));
			} catch (AuraHandledException ex) {
				details = null;
			}
			ContentVersion row = new ContentVersion(Id = version.Id, Description = MOBILE_DEVICE_PICTURE_MARKER);
			applyPictureDetails(row, details);
			updates.add(row);
		}
		if (!updates.isEmpty()) {
			update updates;
		}
	}

	/**
	 * @description GW-6437 - Payload and comment split from a mobile upload context string.
	 */
	private class PictureCommentSplit {
		private String payload;
		private String comment;
	}

	/**
	 * @description GW-375 - Resolves a Product Serviced line from a CRSS mobile upload context.
	 *              Accepts workOrder::lineId, saveKey|lineNumber|lineId, or a bare line token.
	 * @param payload Upload context without the optional comment suffix
	 * @return Work Order Line Item Id, or null
	 */
	private static Id resolveProductServicedLineIdFromUploadContext(String payload) {
		String reference = String.isBlank(payload) ? '' : payload.trim();
		if (String.isBlank(reference)) {
			return null;
		}
		String workOrderToken = '';
		String lineReference = reference;
		Integer targetSplit = reference.indexOf('::');
		if (targetSplit > 0) {
			workOrderToken = reference.substring(0, targetSplit).trim();
			lineReference = reference.substring(targetSplit + 2).trim();
		}
		Id lineId = resolveDirectWorkOrderLineItemId(lineReference);
		if (lineId != null) {
			return lineId;
		}
		lineId = resolveProductServicedLineForPicture(lineReference, workOrderToken);
		if (lineId != null) {
			return lineId;
		}
		if (String.isNotBlank(workOrderToken)) {
			String resolved = resolveMobilePictureRecordId(lineReference, workOrderToken);
			lineId = parseRecordId(resolved);
			if (lineId != null && lineId.getSobjectType() == WorkOrderLineItem.SObjectType) {
				return lineId;
			}
		}
		String resolvedBare = resolveMobilePictureRecordId(lineReference, lineReference);
		lineId = parseRecordId(resolvedBare);
		if (lineId != null && lineId.getSobjectType() == WorkOrderLineItem.SObjectType) {
			return lineId;
		}
		return null;
	}

	private static PictureCommentSplit splitPictureUploadComment(String value) {
		PictureCommentSplit split = new PictureCommentSplit();
		split.payload = String.isBlank(value) ? '' : value.trim();
		split.comment = '';
		Integer delimiter = split.payload.indexOf(MOBILE_PICTURE_COMMENT_DELIMITER);
		if (delimiter >= 0) {
			split.comment = split.payload.substring(delimiter + MOBILE_PICTURE_COMMENT_DELIMITER.length());
			split.payload = split.payload.substring(0, delimiter).trim();
		}
		split.comment = normalizeMobilePictureComment(split.comment);
		return split;
	}

	/**
	 * @description GW-6437 - Trims and caps a CRSS Mobile Device Picture comment.
	 * @param pictureComment Raw comment
	 * @return Stored comment, or null when blank
	 */
	private static String normalizeMobilePictureComment(String pictureComment) {
		if (String.isBlank(pictureComment)) {
			return null;
		}
		String text = pictureComment.trim();
		if (text.length() > MOBILE_PICTURE_COMMENT_MAX_LENGTH) {
			text = text.substring(0, MOBILE_PICTURE_COMMENT_MAX_LENGTH);
		}
		return text;
	}

	/**
	 * @description Decodes a camera image and rejects an empty or oversized file.
	 * @param base64Data Raw or data-url base64
	 * @return Image body
	 */
	private static Blob decodeMobilePicture(String base64Data) {
		if (String.isBlank(base64Data)) {
			throw auraException('A picture is required.');
		}
		String payload = base64Data.trim();
		Integer comma = payload.indexOf(',');
		if (payload.startsWith('data:') && comma > -1) {
			payload = payload.substring(comma + 1);
		}
		payload = stripBase64Whitespace(payload);
		Blob body;
		try {
			body = EncodingUtil.base64Decode(payload);
		} catch (Exception ex) {
			throw auraException('The picture could not be read. Take it again.');
		}
		if (body == null || body.size() == 0) {
			throw auraException('A picture is required.');
		}
		if (body.size() > MAX_MOBILE_PICTURE_BYTES) {
			throw auraException('The picture is too large. Take it again.');
		}
		return body;
	}

	/**
	 * @description GW-375 - Removes whitespace from base64 without regex (large payloads throw "Regex too complicated").
	 * @param payload Base64 text
	 * @return Payload without spaces, tabs, or line breaks
	 */
	private static String stripBase64Whitespace(String payload) {
		if (String.isBlank(payload)) {
			return payload;
		}
		if (
			!payload.contains(' ')
			&& !payload.contains('\n')
			&& !payload.contains('\r')
			&& !payload.contains('\t')
		) {
			return payload;
		}
		return payload.replace(' ', '').replace('\n', '').replace('\r', '').replace('\t', '');
	}

	/**
	 * @description Keeps a simple image file name for the mobile device picture.
	 * @param fileName Client file name
	 * @return jpg, jpeg, or png file name
	 */
	private static String mobilePictureFileName(String fileName) {
		String name = String.isBlank(fileName) ? 'MobileDevicePicture.jpg' : fileName.trim();
		if (name.contains('\\')) {
			name = name.substringAfterLast('\\');
		}
		if (name.contains('/')) {
			name = name.substringAfterLast('/');
		}
		String lower = name.toLowerCase();
		if (!lower.endsWith('.jpg') && !lower.endsWith('.jpeg') && !lower.endsWith('.png')) {
			name = 'MobileDevicePicture.jpg';
		}
		return name;
	}

	/**
	 * @description GW-375 - The product serviced line just created, when the mobile id cannot be read.
	 *              Does not link the picture to the work order.
	 * @param workOrderIdValue Work order that owns the line
	 * @param assetIdValue Asset on the new line. When blank, the newest product serviced line is used.
	 * @return Work Order Line Item Id, or null
	 */
	@AuraEnabled
	public static String findLatestProductServicedLineId(String workOrderIdValue, String assetIdValue) {
		Id workOrderId = resolveWorkOrderId(workOrderIdValue);
		if (workOrderId == null) {
			return null;
		}
		Id lineId = findLatestProductServicedLineIdOnWorkOrder(workOrderId, assetIdValue);
		return lineId == null ? null : String.valueOf(lineId);
	}

	/**
	 * @description GW-375 - First 15 characters of an id, lowercased.
	 * @param value Id
	 * @return Prefix, or null
	 */
	private static String idPrefix(String value) {
		if (String.isBlank(value)) {
			return null;
		}
		String token = value.trim().toLowerCase();
		return token.length() >= 15 ? token.substring(0, 15) : null;
	}

	/**
	 * @description GW-375 - True when the work order or line the picture will be stored on exists.
	 * @param primaryId Resolved primary record Id
	 * @return True when the record exists
	 */
	private static Boolean picturePrimaryRecordExists(Id primaryId) {
		if (primaryId == null) {
			return false;
		}
		Schema.SObjectType tokenType = primaryId.getSobjectType();
		if (tokenType == WorkOrder.SObjectType) {
			return [SELECT COUNT() FROM WorkOrder WHERE Id = :primaryId] > 0;
		}
		if (tokenType == WorkOrderLineItem.SObjectType) {
			return [SELECT COUNT() FROM WorkOrderLineItem WHERE Id = :primaryId] > 0;
		}
		return false;
	}

	/**
	 * @description GW-375 - User-facing message when a Mobile Device Picture insert fails.
	 * @param ex DML exception from ContentVersion insert
	 * @return Message for the debrief screen
	 */
	private static String mobilePictureDmlMessage(DmlException ex) {
		if (ex == null) {
			return 'The picture could not be saved.';
		}
		if (ex.getNumDml() > 0 && String.isNotBlank(ex.getDmlMessage(0))) {
			return ex.getDmlMessage(0);
		}
		return ex.getMessage();
	}

	/**
	 * @description GW-375 - Parses the primary record token from the debrief screen.
	 *              Mobile Field Service may omit extra Aura parameters, so the work order id can be appended after ::.
	 * @param primaryRecordId Line, work order, or composite token from the LWC
	 * @param workOrderIdForResolve Work order that owns the line
	 * @return Parsed primary id, or null when no record matches
	 */
	private static PrimaryPictureTarget parsePrimaryPictureTarget(
		String primaryRecordId,
		String workOrderIdForResolve
	) {
		String primaryToken = String.isBlank(primaryRecordId) ? '' : primaryRecordId.trim();
		String workOrderToken = String.isBlank(workOrderIdForResolve) ? '' : workOrderIdForResolve.trim();
		Integer compositeSplit = primaryToken.indexOf('::');
		if (String.isBlank(workOrderToken) && compositeSplit > 0) {
			workOrderToken = primaryToken.substring(compositeSplit + 2).trim();
			primaryToken = primaryToken.substring(0, compositeSplit).trim();
		}
		Id primaryId = null;
		if (String.isNotBlank(workOrderToken) && String.isNotBlank(primaryToken)) {
			String resolved = resolveMobilePictureRecordId(primaryToken, workOrderToken);
			primaryId = parseRecordId(resolved);
		}
		if (primaryId == null) {
			primaryId = parseRecordId(primaryToken);
		}
		if (primaryId == null
			&& isProductServicedLinePictureToken(primaryToken)
			&& String.isNotBlank(workOrderToken)) {
			primaryId = resolveProductServicedLineId(primaryToken, workOrderToken);
		}
		if (primaryId == null
			&& String.isNotBlank(workOrderToken)
			&& !isProductServicedLinePictureToken(primaryToken)) {
			String resolvedWorkOrder = resolveMobilePictureRecordId(workOrderToken, workOrderToken);
			primaryId = parseRecordId(resolvedWorkOrder);
		}
		PrimaryPictureTarget target = new PrimaryPictureTarget();
		target.primaryId = primaryId;
		return target;
	}

	/**
	 * @description GW-375 - Resolves a Product Serviced line on this work order by id prefix.
	 * @param lineToken Line id token from the debrief screen
	 * @param workOrderToken Work order that owns the line
	 * @return Work Order Line Item Id, or null
	 */
	private static Id resolveProductServicedLineId(String lineToken, String workOrderToken) {
		if (isWorkOrderIdToken(lineToken)) {
			return null;
		}
		String resolvedLine = resolveMobilePictureRecordId(lineToken, workOrderToken);
		Id lineId = parseRecordId(resolvedLine);
		if (lineId != null && lineId.getSobjectType() == WorkOrderLineItem.SObjectType) {
			return lineId;
		}
		Id workOrderId = parseRecordId(resolveMobilePictureRecordId(workOrderToken, workOrderToken));
		String linePrefix = idPrefix(lineToken);
		if (workOrderId == null || linePrefix == null) {
			return null;
		}
		return matchProductServicedLineByPrefix(workOrderId, linePrefix);
	}

	/**
	 * @description GW-375 - Resolves a Product Serviced line from the debrief composite reference.
	 *              Format: saveKey|lineItemNumber|lineId (Field Service Mobile may drop lineId and send the work order id).
	 * @param lineReferenceValue Composite or raw line id from the LWC
	 * @param workOrderIdValue Work order on the debrief screen
	 * @return Work Order Line Item Id, or null
	 */
	private static Id resolveProductServicedLineForPicture(
		String lineReferenceValue,
		String workOrderIdValue
	) {
		String reference = String.isBlank(lineReferenceValue) ? '' : lineReferenceValue.trim();
		String workOrderToken = String.isBlank(workOrderIdValue) ? '' : workOrderIdValue.trim();
		Id workOrderId = resolveWorkOrderId(workOrderToken);
		if (workOrderId == null) {
			workOrderId = parseRecordId(resolveMobilePictureRecordId(workOrderToken, workOrderToken));
		}
		if (workOrderId == null) {
			Id directLine = resolveDirectWorkOrderLineItemId(reference);
			if (directLine != null) {
				return directLine;
			}
			if (reference.contains('|')) {
				List<String> parts = reference.split('\\|', -1);
				for (Integer index = parts.size() - 1; index >= 0; index--) {
					String part = parts[index] == null ? '' : parts[index].trim();
					if (String.isBlank(part) || isWorkOrderIdToken(part)) {
						continue;
					}
					String resolvedPart = resolveMobilePictureRecordId(part, part);
					Id lineFromPart = parseRecordId(resolvedPart);
					if (lineFromPart != null
						&& lineFromPart.getSobjectType() == WorkOrderLineItem.SObjectType
						&& picturePrimaryRecordExists(lineFromPart)) {
						return lineFromPart;
					}
				}
			}
			String resolvedReference = resolveMobilePictureRecordId(reference, reference);
			Id lineFromReference = parseRecordId(resolvedReference);
			if (lineFromReference != null
				&& lineFromReference.getSobjectType() == WorkOrderLineItem.SObjectType
				&& picturePrimaryRecordExists(lineFromReference)) {
				return lineFromReference;
			}
			return null;
		}
		if (!reference.contains('|')) {
			Id direct = resolveProductServicedLineId(reference, workOrderToken);
			if (direct != null) {
				return direct;
			}
			return matchProductServicedLineByPrefix(workOrderId, idPrefix(reference));
		}
		List<String> parts = reference.split('\\|', -1);
		String saveKey = parts.size() > 0 ? parts[0].trim() : '';
		String lineNumber = parts.size() > 1 ? parts[1].trim() : '';
		String lineToken = parts.size() > 2 ? parts[2].trim() : '';
		if (String.isNotBlank(saveKey)) {
			Id fromKey = matchProductServicedLineByPrefix(workOrderId, idPrefix(saveKey));
			if (fromKey != null) {
				return fromKey;
			}
		}
		if (String.isNotBlank(lineNumber)) {
			Id fromNumber = matchProductServicedLineByLineNumber(workOrderId, lineNumber);
			if (fromNumber != null) {
				return fromNumber;
			}
		}
		if (String.isNotBlank(lineToken) && !isWorkOrderIdToken(lineToken)) {
			Id fromToken = resolveProductServicedLineId(lineToken, workOrderToken);
			if (fromToken != null) {
				return fromToken;
			}
		}
		return null;
	}

	/**
	 * @description GW-375 - Product Serviced line on a work order whose id prefix matches.
	 * @param workOrderId Work Order Id
	 * @param linePrefix First 15 characters of the line id, lowercased
	 * @return Matching line Id, or null
	 */
	private static Id matchProductServicedLineByPrefix(Id workOrderId, String linePrefix) {
		if (workOrderId == null || linePrefix == null) {
			return null;
		}
		Id matched = matchLineOnWorkOrderByPrefix(workOrderId, linePrefix, true);
		if (matched != null) {
			return matched;
		}
		return matchLineOnWorkOrderByPrefix(workOrderId, linePrefix, false);
	}

	/**
	 * @description GW-375 - Product Serviced line on a work order by LineItemNumber.
	 * @param workOrderId Work Order Id
	 * @param lineNumber Line item number from the debrief list
	 * @return Matching line Id, or null
	 */
	private static Id matchProductServicedLineByLineNumber(Id workOrderId, String lineNumber) {
		if (workOrderId == null || String.isBlank(lineNumber)) {
			return null;
		}
		String target = lineNumber.trim();
		for (WorkOrderLineItem line : queryProductServicedLinesForPicture(workOrderId)) {
			if (line.LineItemNumber != null && String.valueOf(line.LineItemNumber).trim() == target) {
				return line.Id;
			}
		}
		return null;
	}

	/**
	 * @description GW-375 - Product Serviced lines on a work order for mobile picture resolution.
	 * @param workOrderId Work Order Id
	 * @return Product Serviced Work Order Line Items
	 */
	private static List<WorkOrderLineItem> queryProductServicedLinesForPicture(Id workOrderId) {
		return [
			SELECT Id, LineItemNumber
			FROM WorkOrderLineItem
			WHERE WorkOrderId = :workOrderId
				AND LineType__c = 'Product Serviced'
		];
	}

	/**
	 * @description GW-375 - Work Order Line Item on a work order whose id prefix matches.
	 * @param workOrderId Work Order Id
	 * @param linePrefix First 15 characters of the line id, lowercased
	 * @param productServicedOnly When true, only Product Serviced lines are considered
	 * @return Matching line Id, or null
	 */
	private static Id matchLineOnWorkOrderByPrefix(
		Id workOrderId,
		String linePrefix,
		Boolean productServicedOnly
	) {
		if (workOrderId == null || linePrefix == null) {
			return null;
		}
		List<WorkOrderLineItem> lines = productServicedOnly
			? queryProductServicedLinesForPicture(workOrderId)
			: [
				SELECT Id
				FROM WorkOrderLineItem
				WHERE WorkOrderId = :workOrderId
			];
		for (WorkOrderLineItem line : lines) {
			if (idPrefix(String.valueOf(line.Id)) == linePrefix) {
				return line.Id;
			}
		}
		return null;
	}

	/**
	 * @description GW-375 - Parses a Salesforce Work Order Line Item id from the client payload.
	 * @param token Raw id or composite segment
	 * @return Work Order Line Item Id, or null
	 */
	private static Id resolveDirectWorkOrderLineItemId(String token) {
		if (String.isBlank(token)) {
			return null;
		}
		String reference = token.trim();
		List<String> candidates = new List<String>{ reference };
		if (reference.contains('|')) {
			candidates = reference.split('\\|', -1);
		}
		for (String candidate : candidates) {
			String part = candidate == null ? '' : candidate.trim();
			if (String.isBlank(part) || isWorkOrderIdToken(part)) {
				continue;
			}
			Id direct = parseRecordId(part);
			if (direct != null && direct.getSobjectType() == WorkOrderLineItem.SObjectType) {
				return direct;
			}
		}
		return null;
	}

	/**
	 * @description GW-375 - True when the token is a Work Order id (including a corrupted line button value).
	 * @param token Id token from the client
	 * @return True when the token refers to a work order
	 */
	private static Boolean isWorkOrderIdToken(String token) {
		if (String.isBlank(token) || token.length() < 3) {
			return false;
		}
		return token.substring(0, 3).equalsIgnoreCase('0WO');
	}

	/**
	 * @description GW-375 - True when the client intended a Product Serviced line picture, not the work order header.
	 * @param token Primary id token before or after composite split
	 * @return True when the token refers to a line
	 */
	private static Boolean isProductServicedLinePictureToken(String token) {
		if (String.isBlank(token) || token.length() < 3) {
			return false;
		}
		String prefix = token.substring(0, 3).toUpperCase();
		return prefix == '1WL' || token.startsWith('_new_');
	}

	/**
	 * @description GW-375 - True when a failed parse should fall back to the work order header.
	 * @param primaryRecordId Raw value from the debrief screen
	 * @return True for header uploads only
	 */
	private static Boolean isWorkOrderHeaderPictureRequest(String primaryRecordId) {
		if (String.isBlank(primaryRecordId)) {
			return true;
		}
		String token = primaryRecordId.trim();
		Integer split = token.indexOf('::');
		String left = split > 0 ? token.substring(0, split).trim() : token;
		if (isProductServicedLinePictureToken(left)) {
			return false;
		}
		if (left.length() >= 3 && left.substring(0, 3).equalsIgnoreCase('0WO')) {
			return true;
		}
		return split <= 0;
	}

	/**
	 * @description GW-375 - Parsed primary record for a mobile device picture save.
	 */
	private class PrimaryPictureTarget {
		private Id primaryId;
	}

	/**
	 * @description GW-375 - Finds the work order or line when the mobile app has changed the id's letter case.
	 *              A lowercased 15-character id cannot be cast, so it is matched to a line on this work order.
	 * @param recordIdValue Id from the debrief screen, possibly lowercased
	 * @param workOrderIdValue Work order that owns the line. Not used as a file link.
	 * @return Salesforce id, or null when no record matches
	 */
	@AuraEnabled
	public static String resolveMobilePictureRecordId(String recordIdValue, String workOrderIdValue) {
		String token = String.isBlank(recordIdValue) ? '' : recordIdValue.trim();
		if (token.length() == 18) {
			Id restored = parseRecordId(token);
			if (restored != null) {
				return String.valueOf(restored);
			}
		}
		Id workOrderId = parseRecordId(workOrderIdValue);
		if (workOrderId != null && workOrderId.getSobjectType() != WorkOrder.SObjectType) {
			workOrderId = null;
		}
		if (workOrderId != null && token.length() >= 15) {
			String key = token.substring(0, 15).toLowerCase();
			Boolean lineIntent = token.length() >= 3 && token.substring(0, 3).equalsIgnoreCase('1WL');
			if (!lineIntent
				&& String.valueOf(workOrderId).substring(0, 15).toLowerCase() == key) {
				return String.valueOf(workOrderId);
			}
			String linePrefix = idPrefix(token);
			for (WorkOrderLineItem line : [
				SELECT Id
				FROM WorkOrderLineItem
				WHERE WorkOrderId = :workOrderId
					AND LineType__c = 'Product Serviced'
			]) {
				if (linePrefix != null && idPrefix(String.valueOf(line.Id)) == linePrefix) {
					return String.valueOf(line.Id);
				}
			}
		}
		Id direct = parseRecordId(token);
		if (direct == null) {
			return null;
		}
		try {
			Schema.SObjectType tokenType = direct.getSobjectType();
			if (tokenType == WorkOrder.SObjectType
				&& [SELECT COUNT() FROM WorkOrder WHERE Id = :direct] > 0) {
				return String.valueOf(direct);
			}
			if (tokenType == WorkOrderLineItem.SObjectType
				&& [SELECT COUNT() FROM WorkOrderLineItem WHERE Id = :direct] > 0) {
				return String.valueOf(direct);
			}
		} catch (Exception ex) {
			return null;
		}
		return null;
	}

	/**
	 * @description GW-375 - Turns mobile record ids into Ids. An 18-character id whose case was changed is not a valid Id, so the first 15 characters are used.
	 * @param recordIds Raw record ids from the debrief screen
	 * @return Ids that can be queried
	 */
	private static Set<Id> parseRecordIds(List<String> recordIds) {
		return expandRecordIdsForPictureList(recordIds);
	}

	/**
	 * @description GW-375 - Record ids for listing pictures, including mobile-damaged tokens.
	 * @param recordIds Raw ids from the debrief screen
	 * @return Parsed record ids
	 */
	private static Set<Id> expandRecordIdsForPictureList(List<String> recordIds) {
		Set<Id> parsed = new Set<Id>();
		if (recordIds == null) {
			return parsed;
		}
		for (String recordIdValue : recordIds) {
			if (String.isBlank(recordIdValue)) {
				continue;
			}
			String token = recordIdValue.trim();
			Id recordId = parseRecordId(token);
			if (recordId != null) {
				parsed.add(recordId);
			}
			String resolved = resolveMobilePictureRecordId(token, token);
			recordId = parseRecordId(resolved);
			if (recordId != null) {
				parsed.add(recordId);
			}
		}
		return parsed;
	}

	/**
	 * @description GW-375 - Turns one mobile record id into an Id.
	 * @param recordIdValue Raw record id
	 * @return Id, or null when the value is blank or not an id
	 */
	private static Id parseRecordId(String recordIdValue) {
		if (String.isBlank(recordIdValue)) {
			return null;
		}
		String token = recordIdValue.trim();
		if (token.length() != 15 && token.length() != 18) {
			return null;
		}
		if (token.length() == 18) {
			token = restoreIdCase(token);
		}
		try {
			return (Id) token;
		} catch (Exception ex) {
			return null;
		}
	}

	/**
	 * @description GW-375 - Puts the original letter case back on a mobile id.
	 *              The mobile app lowercases the id. The last three characters still say which letters were uppercase.
	 * @param id18 18-character id, possibly lowercased
	 * @return 15-character id with its original case
	 */
	private static String restoreIdCase(String id18) {
		String body = id18.substring(0, 15);
		String checksum = id18.substring(15, 18).toUpperCase();
		String alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ012345';
		String restored = '';
		for (Integer groupIndex = 0; groupIndex < 3; groupIndex++) {
			Integer code = alphabet.indexOf(checksum.substring(groupIndex, groupIndex + 1));
			if (code < 0) {
				return body;
			}
			Integer bit = 1;
			for (Integer position = 0; position < 5; position++) {
				Integer start = (groupIndex * 5) + position;
				String character = body.substring(start, start + 1);
				Boolean uppercase = Math.mod(code / bit, 2) == 1;
				restored += uppercase ? character.toUpperCase() : character.toLowerCase();
				bit *= 2;
			}
		}
		return restored;
	}

	/**
	 * @description Aura exception whose message survives the Aura wrapper.
	 * @param message Message shown in the debrief screen
	 * @return Exception to throw
	 */
	private static AuraHandledException auraException(String message) {
		AuraHandledException ex = new AuraHandledException(message);
		ex.setMessage(message);
		return ex;
	}
}