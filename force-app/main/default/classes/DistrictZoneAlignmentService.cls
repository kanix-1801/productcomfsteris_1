/**
 * @author Sagar Anand
 * @date 2026-11-06
 * @group Field Service Backoffice
 * @description GW-2706: District Zone Alignment. Reads the uploaded District Zone Alignment Excel file and
 *              creates or updates district Service Territories:
 *              - Current District # blank or "-": creates the district under the Future Zone, with the
 *                Future ASM as Territory Manager.
 *              - Current District # filled: updates the Territory Manager, parent zone, District # and name
 *                where they differ.
 *              Districts and zones are found by Region Number. A zone is a Van Region or Zone territory.
 *              Skipped rows are written to the running user's error file, which is emailed to them.
 *              User-facing problems are thrown as AuraHandledException; the controller handles the rest.
 */
public with sharing class DistrictZoneAlignmentService {
	public static final String TEMPLATE_TITLE = 'District Zone Alignment Template';
	public static final String TEMPLATE_RESOURCE_NAME = 'DistrictZoneAlignmentTemplate';
	public static final String TEMPLATE_FILE_NAME = 'District_Zone_Alignment_Template.xlsx';
	public static final String ERROR_FILE_TITLE = 'District Zone Alignment Errors';
	public static final String ERROR_FILE_NAME = 'District_Zone_Alignment_Errors.csv';
	public static final String DOWNLOAD_URL_PREFIX = '/sfc/servlet.shepherd/document/download/';
	public static final Set<String> ZONE_TERRITORY_TYPES = new Set<String>{ 'Van Region', 'Zone' };
	public static final String LOG_TAG = 'Service Territory';
	@TestVisible
	private static final Integer MAX_ROWS = 2000;
	private static final Integer NAME_MAX_LENGTH = 80;
	private static final String SCENARIO = 'District Zone Alignment';
	private static final String COLUMN_CURRENT_DISTRICT = 'Current District #';
	private static final String COLUMN_FUTURE_DISTRICT = 'Future District #';
	private static final String COLUMN_FUTURE_ASM = 'Future ASM Names';
	private static final String COLUMN_FUTURE_DISTRICT_NAME = 'Future District Name';
	private static final String COLUMN_FUTURE_ZONE = 'Future Zone #';
	private static final List<String> REQUIRED_COLUMNS = new List<String>{
		COLUMN_CURRENT_DISTRICT,
		COLUMN_FUTURE_DISTRICT,
		COLUMN_FUTURE_ASM,
		COLUMN_FUTURE_ZONE
	};
	private static final List<String> TERRITORY_FIELDS = new List<String>{
		'Id',
		'Name',
		'RegionNumber__c',
		'TerritoryType__c',
		'ParentTerritoryId',
		'TerritoryManager__c',
		'OperatingHoursId'
	};
	private static final List<String> USER_FIELDS = new List<String>{ 'Id', 'Name', 'Username', 'Email' };

	/**
	 * @description GW-2706: Counts, row errors and error file returned to the LWC after Process Data.
	 */
	public class ProcessResult {
		@AuraEnabled
		public Integer processedCount = 0;
		@AuraEnabled
		public Integer createdCount = 0;
		@AuraEnabled
		public Integer updatedCount = 0;
		@AuraEnabled
		public Integer unchangedCount = 0;
		@AuraEnabled
		public Integer skippedCount = 0;
		@AuraEnabled
		public List<String> errors = new List<String>();
		@AuraEnabled
		public String summary;
		@AuraEnabled
		public Id errorFileDocumentId;
		@AuraEnabled
		public Boolean emailSent = false;
	}

	private class AlignmentRow {
		Integer rowNumber;
		List<String> cells;
		String currentDistrict;
		String futureDistrict;
		String futureAsm;
		String futureDistrictName;
		String futureZone;
		String errorMessage;
	}

	/**
	 * @description GW-2706: Returns the template file, copying the packaged template into Salesforce Files
	 *              and sharing it with all internal users the first time.
	 * @return ContentDocument Id of the template file.
	 * @throws AuraHandledException When the template is not available.
	 * @example
	 * Id templateId = DistrictZoneAlignmentService.ensureTemplateDocumentId();
	 */
	public static Id ensureTemplateDocumentId() {
		try {
			FieldServiceBackofficeConfig__c config = FieldServiceBackofficeConfig__c.getOrgDefaults();
			Id documentId = config.DistrictZoneAlignmentTemplateId__c;
			if (isAccessibleDocument(documentId)) {
				return documentId;
			}
			List<ContentDocument> titledDocumentList = ContentDocumentsSelector.selectLatestByTitle(TEMPLATE_TITLE);
			documentId = titledDocumentList.isEmpty() ? createTemplateDocument() : titledDocumentList[0].Id;
			if (config.Id == null) {
				config.SetupOwnerId = UserInfo.getOrganizationId();
			}
			config.DistrictZoneAlignmentTemplateId__c = documentId;
			// System mode: back-office users have no edit access to custom settings.
			Database.upsert(config, AccessLevel.SYSTEM_MODE);
			return documentId;
		} catch (Exception e) {
			logUnexpectedError(e);
			throw e;
		} finally {
			Logger.saveLog();
		}
	}

	/**
	 * @description GW-2706: The running user's error file, or null before their first upload.
	 * @return ContentDocument Id, or null.
	 * @example
	 * Id errorFileId = DistrictZoneAlignmentService.getErrorFileDocumentId();
	 */
	public static Id getErrorFileDocumentId() {
		try {
			Id documentId = FieldServiceBackofficeConfig__c.getInstance().DistrictZoneAlignmentErrorFileId__c;
			return isAccessibleDocument(documentId) ? documentId : null;
		} catch (Exception e) {
			logUnexpectedError(e);
			throw e;
		} finally {
			Logger.saveLog();
		}
	}

	/**
	 * @description GW-2706: Processes the uploaded file, adds a new version to the running user's error file
	 *              and emails it to them.
	 * @param contentDocumentId Salesforce Files document Id from lightning-file-upload.
	 * @return Counts, row errors and the error file Id.
	 * @throws AuraHandledException When the file is missing, unreadable or has the wrong columns.
	 * @example
	 * DistrictZoneAlignmentService.ProcessResult result = DistrictZoneAlignmentService.processUpload(documentId);
	 */
	public static ProcessResult processUpload(Id contentDocumentId) {
		Logger.setScenario(SCENARIO);
		try {
			List<List<String>> table = readUploadedFile(contentDocumentId);
			List<AlignmentRow> rowList = toRows(table);

			ProcessResult result = new ProcessResult();
			result.processedCount = rowList.size();
			applyRows(rowList, result);
			for (AlignmentRow row : rowList) {
				if (row.errorMessage != null) {
					result.skippedCount++;
					List<Object> parameterList = new List<Object>{ String.valueOf(row.rowNumber), row.errorMessage };
					result.errors.add(String.format(Label.DZA_RowError, parameterList));
				}
			}
			result.summary = String.format(
				Label.DZA_Summary,
				new List<Object>{
					result.processedCount,
					result.createdCount,
					result.updatedCount,
					result.unchangedCount,
					result.skippedCount
				}
			);

			ContentVersion errorFile = writeErrorFile(table[0], rowList);
			result.errorFileDocumentId = errorFile.ContentDocumentId;
			result.emailSent = sendResultEmail(result.summary, errorFile.Id);
			Logger.info(result.summary).addTag(LOG_TAG);
			return result;
		} catch (Exception e) {
			logUnexpectedError(e);
			throw e;
		} finally {
			Logger.saveLog();
		}
	}

	/**
	 * @description GW-2706: Logs an unexpected error. User messages (AuraHandledException) are shown to the user
	 *              in the screen they're using, so they aren't logged.
	 */
	private static void logUnexpectedError(Exception e) {
		if (!(e instanceof AuraHandledException)) {
			Logger.setScenario(SCENARIO);
			Logger.error('District Zone Alignment failed.', e).addTag(LOG_TAG);
		}
	}

	private static List<List<String>> readUploadedFile(Id contentDocumentId) {
		List<ContentVersion> versionList = ContentVersionsSelector.selectLatestByContentDocumentId(contentDocumentId);
		if (versionList.isEmpty() || versionList[0].FileExtension?.toLowerCase() != 'xlsx') {
			throw PlatformUtilities.buildAuraException(Label.DZA_FileUnreadable);
		}
		try {
			return ExcelFileParser.readFirstSheet(versionList[0].VersionData);
		} catch (ExcelFileParser.ParseException e) {
			throw PlatformUtilities.buildAuraException(Label.DZA_FileUnreadable);
		}
	}

	private static List<AlignmentRow> toRows(List<List<String>> table) {
		Map<String, Integer> columnIndexByHeaderMap = new Map<String, Integer>();
		List<String> header = table.isEmpty() ? new List<String>() : table[0];
		for (Integer i = 0; i < header.size(); i++) {
			columnIndexByHeaderMap.put(headerKey(header[i]), i);
		}
		List<String> missingColumnList = new List<String>();
		for (String column : REQUIRED_COLUMNS) {
			if (!columnIndexByHeaderMap.containsKey(headerKey(column))) {
				missingColumnList.add(column);
			}
		}
		if (!missingColumnList.isEmpty()) {
			throw PlatformUtilities.buildAuraException(
				String.format(Label.DZA_MissingColumns, new List<Object>{ String.join(missingColumnList, ', ') })
			);
		}
		if (table.size() - 1 > MAX_ROWS) {
			String message = String.format(Label.DZA_TooManyRows, new List<Object>{ MAX_ROWS });
			throw PlatformUtilities.buildAuraException(message);
		}

		List<AlignmentRow> rowList = new List<AlignmentRow>();
		for (Integer i = 1; i < table.size(); i++) {
			AlignmentRow row = new AlignmentRow();
			row.rowNumber = i + 1;
			row.cells = table[i];
			row.currentDistrict = cellValue(row.cells, columnIndexByHeaderMap, COLUMN_CURRENT_DISTRICT);
			row.futureDistrict = cellValue(row.cells, columnIndexByHeaderMap, COLUMN_FUTURE_DISTRICT);
			row.futureAsm = cellValue(row.cells, columnIndexByHeaderMap, COLUMN_FUTURE_ASM);
			row.futureDistrictName = cellValue(row.cells, columnIndexByHeaderMap, COLUMN_FUTURE_DISTRICT_NAME);
			row.futureZone = cellValue(row.cells, columnIndexByHeaderMap, COLUMN_FUTURE_ZONE);
			if (
				row.currentDistrict != null ||
				row.futureDistrict != null ||
				row.futureAsm != null ||
				row.futureZone != null
			) {
				rowList.add(row);
			}
		}
		return rowList;
	}

	private static String headerKey(String header) {
		return header == null ? '' : header.deleteWhitespace().toLowerCase();
	}

	/**
	 * @description Trimmed cell value; blank and dash-only placeholders ("-") are returned as null.
	 */
	private static String cellValue(List<String> cells, Map<String, Integer> columnIndexByHeaderMap, String column) {
		Integer index = columnIndexByHeaderMap.get(headerKey(column));
		String value = index != null && index < cells.size() ? cells[index]?.trim() : null;
		return String.isBlank(value?.replaceAll('\\p{Pd}', '')) ? null : value;
	}

	private static void applyRows(List<AlignmentRow> rowList, ProcessResult result) {
		AlignmentPlan plan = new AlignmentPlan(rowList);
		for (AlignmentRow row : rowList) {
			row.errorMessage = row.currentDistrict == null ? plan.planCreate(row) : plan.planUpdate(row);
		}
		result.unchangedCount = plan.unchangedCount;
		result.createdCount = savedCount(
			Database.insert(plan.toInsertList, false, AccessLevel.USER_MODE),
			plan.toInsertList,
			plan.insertRowList
		);
		result.updatedCount = savedCount(
			Database.update(plan.toUpdateList, false, AccessLevel.USER_MODE),
			plan.toUpdateList,
			plan.updateRowList
		);
	}

	/**
	 * @description Puts the save error on each failed row (for the error file) and returns the number of saved
	 *              records. The failures are logged by PlatformUtilities.logSaveFailures.
	 */
	private static Integer savedCount(
		List<Database.SaveResult> saveResultList,
		List<ServiceTerritory> territoryList,
		List<AlignmentRow> rowList
	) {
		for (Integer i = 0; i < saveResultList.size(); i++) {
			if (!saveResultList[i].isSuccess()) {
				String message = saveResultList[i].getErrors()[0].getMessage();
				rowList[i].errorMessage = String.format(Label.DZA_SaveFailed, new List<Object>{ message });
			}
		}
		return territoryList.size() - PlatformUtilities.logSaveFailures(territoryList, saveResultList);
	}

	/**
	 * @description Looks up every territory and user in the file once, then turns each row into an insert,
	 *              an update, no change, or an error message.
	 */
	private class AlignmentPlan {
		Map<String, ServiceTerritory> territoryByRegionNumberMap = new Map<String, ServiceTerritory>();
		Map<String, Map<Id, User>> usersByKeyMap = new Map<String, Map<Id, User>>();
		Set<String> claimedNumberSet = new Set<String>();
		Set<Id> touchedDistrictIdSet = new Set<Id>();
		List<ServiceTerritory> toInsertList = new List<ServiceTerritory>();
		List<AlignmentRow> insertRowList = new List<AlignmentRow>();
		List<ServiceTerritory> toUpdateList = new List<ServiceTerritory>();
		List<AlignmentRow> updateRowList = new List<AlignmentRow>();
		Integer unchangedCount = 0;

		AlignmentPlan(List<AlignmentRow> rowList) {
			Set<String> regionNumberSet = new Set<String>();
			Set<String> userKeySet = new Set<String>();
			for (AlignmentRow row : rowList) {
				regionNumberSet.addAll(new List<String>{ row.currentDistrict, row.futureDistrict, row.futureZone });
				userKeySet.add(row.futureAsm);
			}
			regionNumberSet.remove(null);
			userKeySet.remove(null);
			List<ServiceTerritory> territoryList = (List<ServiceTerritory>) new ServiceTerritoriesSelector()
				.selectFields(TERRITORY_FIELDS)
				.whereIn('RegionNumber__c', new List<String>(regionNumberSet))
				.execute();
			for (ServiceTerritory territory : territoryList) {
				territoryByRegionNumberMap.put(territory.RegionNumber__c.toLowerCase(), territory);
			}
			// Active users whose full name, username or email matches an ASM value from the file.
			List<String> userKeyList = new List<String>(userKeySet);
			List<User> userList = (List<User>) SoqlQueryBuilder.fromObject('User')
				.selectFields(USER_FIELDS)
				.whereEquals('IsActive', true)
				.whereIn('Name', userKeyList)
				.whereIn('Username', userKeyList)
				.whereIn('Email', userKeyList)
				.withFilterLogic('1 AND (2 OR 3 OR 4)')
				.execute();
			for (User activeUser : userList) {
				for (String key : new List<String>{ activeUser.Name, activeUser.Username, activeUser.Email }) {
					if (String.isNotBlank(key)) {
						Map<Id, User> userById = usersByKeyMap.get(key.toLowerCase()) ?? new Map<Id, User>();
						userById.put(activeUser.Id, activeUser);
						usersByKeyMap.put(key.toLowerCase(), userById);
					}
				}
			}
		}

		String planCreate(AlignmentRow row) {
			String futureError = futureColumnsError(row);
			if (futureError != null) {
				return futureError;
			}
			if (isNumberTaken(row.futureDistrict, null)) {
				return String.format(Label.DZA_DistrictExists, new List<Object>{ row.futureDistrict });
			}
			ServiceTerritory zone = findZone(row.futureZone);
			if (zone.OperatingHoursId == null) {
				return String.format(Label.DZA_ZoneNoOperatingHours, new List<Object>{ row.futureZone });
			}
			String asmError = asmError(row.futureAsm);
			if (asmError != null) {
				return asmError;
			}

			claimedNumberSet.add(row.futureDistrict.toLowerCase());
			toInsertList.add(
				new ServiceTerritory(
					Name = (row.futureDistrictName ?? row.futureDistrict).left(NAME_MAX_LENGTH),
					RegionNumber__c = row.futureDistrict,
					ParentTerritoryId = zone.Id,
					OperatingHoursId = zone.OperatingHoursId,
					TerritoryManager__c = findAsm(row.futureAsm)?.Id,
					IsActive = true
				)
			);
			insertRowList.add(row);
			return null;
		}

		String planUpdate(AlignmentRow row) {
			ServiceTerritory district = territoryByRegionNumberMap.get(row.currentDistrict.toLowerCase());
			if (district == null) {
				return String.format(Label.DZA_InvalidCurrentDistrict, new List<Object>{ row.currentDistrict });
			}
			if (touchedDistrictIdSet.contains(district.Id)) {
				return String.format(Label.DZA_DuplicateCurrentDistrict, new List<Object>{ row.currentDistrict });
			}
			String futureError = futureColumnsError(row);
			if (futureError != null) {
				return futureError;
			}
			ServiceTerritory zone = findZone(row.futureZone);
			if (zone.Id == district.Id) {
				return Label.DZA_OwnZone;
			}
			Boolean isRenumbered = !row.futureDistrict.equalsIgnoreCase(district.RegionNumber__c);
			if (isRenumbered && isNumberTaken(row.futureDistrict, district.Id)) {
				return String.format(Label.DZA_DistrictNumberTaken, new List<Object>{ row.futureDistrict });
			}
			String asmError = asmError(row.futureAsm);
			if (asmError != null) {
				return asmError;
			}

			touchedDistrictIdSet.add(district.Id);
			User asm = findAsm(row.futureAsm);
			ServiceTerritory changes = new ServiceTerritory(Id = district.Id);
			if (asm != null && asm.Id != district.TerritoryManager__c) {
				changes.TerritoryManager__c = asm.Id;
			}
			if (zone.Id != district.ParentTerritoryId) {
				changes.ParentTerritoryId = zone.Id;
			}
			if (isRenumbered) {
				changes.RegionNumber__c = row.futureDistrict;
				claimedNumberSet.add(row.futureDistrict.toLowerCase());
			}
			String futureName = row.futureDistrictName?.left(NAME_MAX_LENGTH);
			if (futureName != null && futureName != district.Name) {
				changes.Name = futureName;
			}
			if (changes.getPopulatedFieldsAsMap().size() == 1) {
				unchangedCount++;
				return null;
			}
			toUpdateList.add(changes);
			updateRowList.add(row);
			return null;
		}

		String futureColumnsError(AlignmentRow row) {
			if (row.futureDistrict == null) {
				return Label.DZA_FutureDistrictRequired;
			}
			if (row.futureZone == null) {
				return Label.DZA_FutureZoneRequired;
			}
			if (findZone(row.futureZone) == null) {
				return String.format(Label.DZA_ZoneNotFound, new List<Object>{ row.futureZone });
			}
			return null;
		}

		ServiceTerritory findZone(String zoneNumber) {
			ServiceTerritory territory = territoryByRegionNumberMap.get(zoneNumber.toLowerCase());
			return ZONE_TERRITORY_TYPES.contains(territory?.TerritoryType__c) ? territory : null;
		}

		Boolean isNumberTaken(String districtNumber, Id ownDistrictId) {
			String key = districtNumber.toLowerCase();
			ServiceTerritory existing = territoryByRegionNumberMap.get(key);
			return claimedNumberSet.contains(key) || (existing != null && existing.Id != ownDistrictId);
		}

		String asmError(String asmValue) {
			if (asmValue == null) {
				return null;
			}
			Map<Id, User> matchById = usersByKeyMap.get(asmValue.toLowerCase()) ?? new Map<Id, User>();
			if (matchById.isEmpty()) {
				return String.format(Label.DZA_AsmNotFound, new List<Object>{ asmValue });
			}
			if (matchById.size() > 1) {
				return String.format(Label.DZA_AsmAmbiguous, new List<Object>{ asmValue });
			}
			return null;
		}

		User findAsm(String asmValue) {
			return asmValue == null ? null : usersByKeyMap.get(asmValue.toLowerCase()).values()[0];
		}
	}

	/**
	 * @description Adds a new version to the running user's error file, creating the file on first use.
	 *              The file repeats the uploaded columns of each skipped row, with the row number first and
	 *              the error last.
	 */
	private static ContentVersion writeErrorFile(List<String> header, List<AlignmentRow> rowList) {
		List<String> lineList = new List<String>{
			errorFileLine(Label.DZA_ErrorFileRowColumn, header, Label.DZA_ErrorFileErrorColumn, header.size())
		};
		for (AlignmentRow row : rowList) {
			if (row.errorMessage != null) {
				lineList.add(errorFileLine(String.valueOf(row.rowNumber), row.cells, row.errorMessage, header.size()));
			}
		}

		Id existingDocumentId = getErrorFileDocumentId();
		ContentVersion version = new ContentVersion(
			Title = ERROR_FILE_TITLE,
			PathOnClient = ERROR_FILE_NAME,
			VersionData = Blob.valueOf(String.join(lineList, '\n') + '\n'),
			ReasonForChange = SCENARIO + ' ' + Datetime.now().format(),
			ContentDocumentId = existingDocumentId
		);
		Database.insert(version, AccessLevel.USER_MODE);

		ContentVersion saved = ContentVersionsSelector.selectDocumentIdByVersionId(version.Id)[0];
		if (saved.ContentDocumentId != existingDocumentId) {
			FieldServiceBackofficeConfig__c config =
				FieldServiceBackofficeConfig__c.getValues(UserInfo.getUserId()) ??
				new FieldServiceBackofficeConfig__c(SetupOwnerId = UserInfo.getUserId());
			config.DistrictZoneAlignmentErrorFileId__c = saved.ContentDocumentId;
			// System mode: back-office users have no edit access to custom settings.
			Database.upsert(config, AccessLevel.SYSTEM_MODE);
		}
		return saved;
	}

	/**
	 * @description One error file line: the first value, the row's cells padded to the header width, the last value.
	 */
	private static String errorFileLine(String first, List<String> cells, String last, Integer columnCount) {
		List<String> valueList = new List<String>{ first };
		for (Integer i = 0; i < columnCount; i++) {
			valueList.add(i < cells.size() ? cells[i] : null);
		}
		valueList.add(last);
		return PlatformUtilities.toCsvLine(valueList);
	}

	private static Boolean sendResultEmail(String summary, Id errorFileVersionId) {
		Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
		mail.setTargetObjectId(UserInfo.getUserId());
		mail.setSaveAsActivity(false);
		mail.setSubject(Label.DZA_EmailSubject);
		mail.setPlainTextBody(String.format(Label.DZA_EmailBody, new List<Object>{ summary }));
		mail.setEntityAttachments(new List<String>{ errorFileVersionId });
		try {
			Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{ mail });
			return true;
		} catch (EmailException e) {
			Logger.warn('District Zone Alignment result email could not be sent.', e).addTag(LOG_TAG);
			return false;
		}
	}

	private static Id createTemplateDocument() {
		List<StaticResource> resourceList = StaticResourcesSelector.selectByName(TEMPLATE_RESOURCE_NAME);
		if (resourceList.isEmpty()) {
			throw PlatformUtilities.buildAuraException(Label.DZA_TemplateUnavailable);
		}
		ContentVersion version = new ContentVersion(
			Title = TEMPLATE_TITLE,
			PathOnClient = TEMPLATE_FILE_NAME,
			VersionData = resourceList[0].Body,
			IsMajorVersion = true
		);
		Database.insert(version, AccessLevel.USER_MODE);
		Id documentId = ContentVersionsSelector.selectDocumentIdByVersionId(version.Id)[0].ContentDocumentId;
		// Shared with the whole org so every back-office user can download the same template.
		Database.insert(
			new ContentDocumentLink(
				ContentDocumentId = documentId,
				LinkedEntityId = UserInfo.getOrganizationId(),
				ShareType = 'V',
				Visibility = 'AllUsers'
			),
			AccessLevel.USER_MODE
		);
		return documentId;
	}

	private static Boolean isAccessibleDocument(Id documentId) {
		return documentId != null &&
			!ContentDocumentsSelector.selectIdAndTitleByIds(new Set<Id>{ documentId }).isEmpty();
	}
}