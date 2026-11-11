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
 */
public with sharing class DistrictZoneAlignmentService {
	public static final String TEMPLATE_TITLE = 'District Zone Alignment Template';
	public static final String TEMPLATE_RESOURCE_NAME = 'DistrictZoneAlignmentTemplate';
	public static final String TEMPLATE_FILE_NAME = 'District_Zone_Alignment_Template.xlsx';
	public static final String ERROR_FILE_TITLE = 'District Zone Alignment Errors';
	public static final String ERROR_FILE_NAME = 'District_Zone_Alignment_Errors.csv';
	public static final String DOWNLOAD_URL_PREFIX = '/sfc/servlet.shepherd/document/download/';
	public static final Set<String> ZONE_TERRITORY_TYPES = new Set<String>{ 'Van Region', 'Zone' };
	@TestVisible
	private static final Integer MAX_ROWS = 2000;
	private static final Integer NAME_MAX_LENGTH = 80;
	private static final String SCENARIO = 'District Zone Alignment';
	private static final String LOG_TAG = 'Service Territory';
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
	 * @description GW-2706: Thrown with a user-facing message when the upload, template or error file
	 *              can't be processed.
	 */
	public class DistrictZoneAlignmentException extends Exception {}

	/**
	 * @description GW-2706: Counts, row errors and error file returned to the LWC after Start Upload.
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
	 * @throws DistrictZoneAlignmentException When the template is not available.
	 * @example
	 * Id templateId = DistrictZoneAlignmentService.ensureTemplateDocumentId();
	 */
	public static Id ensureTemplateDocumentId() {
		try {
			Id storedId = toId(FieldServiceBackofficeConfig__c.getOrgDefaults().DistrictZoneAlignmentTemplateId__c);
			if (isAccessibleDocument(storedId)) {
				return storedId;
			}
			List<ContentDocument> titledDocumentList = ContentDocumentsSelector.selectLatestByTitle(TEMPLATE_TITLE);
			if (!titledDocumentList.isEmpty()) {
				saveTemplateDocumentId(titledDocumentList[0].Id);
				return titledDocumentList[0].Id;
			}
			return createTemplateDocument();
		} catch (Exception e) {
			throw toAlignmentException(e);
		} finally {
			Logger.saveLog();
		}
	}

	/**
	 * @description GW-2706: The running user's error file, or null when they haven't uploaded a file yet.
	 * @return ContentDocument Id, or null.
	 * @throws DistrictZoneAlignmentException When the error file can't be read.
	 * @example
	 * Id errorFileId = DistrictZoneAlignmentService.getErrorFileDocumentId();
	 */
	public static Id getErrorFileDocumentId() {
		try {
			FieldServiceBackofficeConfig__c config = FieldServiceBackofficeConfig__c.getValues(UserInfo.getUserId());
			Id storedId = toId(config == null ? null : config.DistrictZoneAlignmentErrorFileId__c);
			return isAccessibleDocument(storedId) ? storedId : null;
		} catch (Exception e) {
			throw toAlignmentException(e);
		} finally {
			Logger.saveLog();
		}
	}

	/**
	 * @description GW-2706: Processes the uploaded file, adds a new version to the running user's error file
	 *              and emails it to them.
	 * @param contentDocumentId Salesforce Files document Id from lightning-file-upload.
	 * @return Counts, row errors and the error file Id.
	 * @throws DistrictZoneAlignmentException When the file is missing, unreadable or has the wrong columns.
	 * @example
	 * DistrictZoneAlignmentService.ProcessResult result = DistrictZoneAlignmentService.processUpload(documentId);
	 */
	public static ProcessResult processUpload(Id contentDocumentId) {
		Logger.setScenario(SCENARIO);
		try {
			if (contentDocumentId == null) {
				throw new DistrictZoneAlignmentException(Label.DZA_FileRequired);
			}
			List<List<String>> table = readUploadedFile(contentDocumentId);
			List<AlignmentRow> rowList = toRows(table);

			ProcessResult result = new ProcessResult();
			result.processedCount = rowList.size();
			if (!rowList.isEmpty()) {
				applyRows(rowList, result);
			}
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
			throw toAlignmentException(e);
		} finally {
			Logger.saveLog();
		}
	}

	private static List<List<String>> readUploadedFile(Id contentDocumentId) {
		List<ContentVersion> versionList = ContentVersionsSelector.selectLatestForAlignmentUpload(contentDocumentId);
		if (
			versionList.isEmpty() ||
			versionList[0].VersionData == null ||
			versionList[0].FileExtension?.toLowerCase() != 'xlsx'
		) {
			throw new DistrictZoneAlignmentException(Label.DZA_FileUnreadable);
		}
		try {
			return ExcelFileParser.readFirstSheet(versionList[0].VersionData);
		} catch (ExcelFileParser.ParseException e) {
			throw new DistrictZoneAlignmentException(Label.DZA_FileUnreadable, e);
		}
	}

	private static List<AlignmentRow> toRows(List<List<String>> table) {
		Map<String, Integer> columnIndexByHeaderMap = new Map<String, Integer>();
		if (!table.isEmpty()) {
			for (Integer i = 0; i < table[0].size(); i++) {
				columnIndexByHeaderMap.put(headerKey(table[0][i]), i);
			}
		}
		List<String> missingColumnList = new List<String>();
		for (String column : REQUIRED_COLUMNS) {
			if (!columnIndexByHeaderMap.containsKey(headerKey(column))) {
				missingColumnList.add(column);
			}
		}
		if (!missingColumnList.isEmpty()) {
			throw new DistrictZoneAlignmentException(
				String.format(Label.DZA_MissingColumns, new List<Object>{ String.join(missingColumnList, ', ') })
			);
		}
		if (table.size() - 1 > MAX_ROWS) {
			throw new DistrictZoneAlignmentException(
				String.format(Label.DZA_TooManyRows, new List<Object>{ MAX_ROWS })
			);
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
			Boolean isBlankRow =
				row.currentDistrict == null &&
				row.futureDistrict == null &&
				row.futureAsm == null &&
				row.futureZone == null;
			if (!isBlankRow) {
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
		if (index == null || index >= cells.size() || cells[index] == null) {
			return null;
		}
		String value = cells[index].trim();
		return String.isBlank(value.replaceAll('\\p{Pd}', '')) ? null : value;
	}

	private static void applyRows(List<AlignmentRow> rowList, ProcessResult result) {
		AlignmentPlan plan = new AlignmentPlan(rowList);
		for (AlignmentRow row : rowList) {
			row.errorMessage = row.currentDistrict == null ? plan.planCreate(row) : plan.planUpdate(row);
		}
		result.unchangedCount = plan.unchangedCount;
		if (!plan.toInsertList.isEmpty()) {
			List<Database.SaveResult> saveResultList = Database.insert(plan.toInsertList, false, AccessLevel.USER_MODE);
			result.createdCount = recordSaveErrors(saveResultList, plan.insertRowList);
		}
		if (!plan.toUpdateList.isEmpty()) {
			List<Database.SaveResult> saveResultList = Database.update(plan.toUpdateList, false, AccessLevel.USER_MODE);
			result.updatedCount = recordSaveErrors(saveResultList, plan.updateRowList);
		}
	}

	/**
	 * @description Puts the save error on each failed row and returns the number of saved records.
	 */
	private static Integer recordSaveErrors(List<Database.SaveResult> saveResultList, List<AlignmentRow> rowList) {
		Integer savedCount = 0;
		for (Integer i = 0; i < saveResultList.size(); i++) {
			if (saveResultList[i].isSuccess()) {
				savedCount++;
			} else {
				List<Database.Error> errorList = saveResultList[i].getErrors();
				String message = errorList.isEmpty() ? '' : errorList[0].getMessage();
				rowList[i].errorMessage = String.format(Label.DZA_SaveFailed, new List<Object>{ message });
				Logger.warn(rowList[i].errorMessage).addTag(LOG_TAG);
			}
		}
		return savedCount;
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
				addIfPresent(regionNumberSet, row.currentDistrict);
				addIfPresent(regionNumberSet, row.futureDistrict);
				addIfPresent(regionNumberSet, row.futureZone);
				addIfPresent(userKeySet, row.futureAsm);
			}
			List<ServiceTerritory> territoryList = ServiceTerritoriesSelector.selectByRegionNumbers(
				regionNumberSet,
				TERRITORY_FIELDS
			);
			for (ServiceTerritory territory : territoryList) {
				territoryByRegionNumberMap.put(territory.RegionNumber__c.toLowerCase(), territory);
			}
			for (User activeUser : selectActiveUsers(userKeySet)) {
				addUser(activeUser.Name, activeUser);
				addUser(activeUser.Username, activeUser);
				addUser(activeUser.Email, activeUser);
			}
		}

		void addUser(String key, User activeUser) {
			if (String.isBlank(key)) {
				return;
			}
			String userKey = key.toLowerCase();
			if (!usersByKeyMap.containsKey(userKey)) {
				usersByKeyMap.put(userKey, new Map<Id, User>());
			}
			usersByKeyMap.get(userKey).put(activeUser.Id, activeUser);
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

			User asm = findAsm(row.futureAsm);
			ServiceTerritory district = new ServiceTerritory(
				Name = (row.futureDistrictName ?? row.futureDistrict).left(NAME_MAX_LENGTH),
				RegionNumber__c = row.futureDistrict,
				ParentTerritoryId = zone.Id,
				OperatingHoursId = zone.OperatingHoursId,
				TerritoryManager__c = asm?.Id,
				IsActive = true
			);
			claimedNumberSet.add(row.futureDistrict.toLowerCase());
			toInsertList.add(district);
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
			Boolean isChanged = false;
			if (asm != null && asm.Id != district.TerritoryManager__c) {
				changes.TerritoryManager__c = asm.Id;
				isChanged = true;
			}
			if (zone.Id != district.ParentTerritoryId) {
				changes.ParentTerritoryId = zone.Id;
				isChanged = true;
			}
			if (isRenumbered) {
				changes.RegionNumber__c = row.futureDistrict;
				claimedNumberSet.add(row.futureDistrict.toLowerCase());
				isChanged = true;
			}
			if (row.futureDistrictName != null && row.futureDistrictName.left(NAME_MAX_LENGTH) != district.Name) {
				changes.Name = row.futureDistrictName.left(NAME_MAX_LENGTH);
				isChanged = true;
			}
			if (!isChanged) {
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
			return territory != null && ZONE_TERRITORY_TYPES.contains(territory.TerritoryType__c) ? territory : null;
		}

		Boolean isNumberTaken(String districtNumber, Id ownDistrictId) {
			String key = districtNumber.toLowerCase();
			if (claimedNumberSet.contains(key)) {
				return true;
			}
			ServiceTerritory existing = territoryByRegionNumberMap.get(key);
			return existing != null && existing.Id != ownDistrictId;
		}

		String asmError(String asmValue) {
			if (asmValue == null) {
				return null;
			}
			Integer matchCount = usersByKeyMap.containsKey(asmValue.toLowerCase())
				? usersByKeyMap.get(asmValue.toLowerCase()).size()
				: 0;
			if (matchCount == 0) {
				return String.format(Label.DZA_AsmNotFound, new List<Object>{ asmValue });
			}
			if (matchCount > 1) {
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
			csvLine(Label.DZA_ErrorFileRowColumn, header, Label.DZA_ErrorFileErrorColumn, header.size())
		};
		for (AlignmentRow row : rowList) {
			if (row.errorMessage != null) {
				lineList.add(csvLine(String.valueOf(row.rowNumber), row.cells, row.errorMessage, header.size()));
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
			FieldServiceBackofficeConfig__c config = FieldServiceBackofficeConfig__c.getValues(UserInfo.getUserId());
			if (config == null) {
				config = new FieldServiceBackofficeConfig__c(SetupOwnerId = UserInfo.getUserId());
			}
			config.DistrictZoneAlignmentErrorFileId__c = saved.ContentDocumentId;
			saveConfig(config);
		}
		return saved;
	}

	private static String csvLine(String first, List<String> cells, String last, Integer columnCount) {
		List<String> valueList = new List<String>{ csvEscape(first) };
		for (Integer i = 0; i < columnCount; i++) {
			valueList.add(csvEscape(i < cells.size() ? cells[i] : null));
		}
		valueList.add(csvEscape(last));
		return String.join(valueList, ',');
	}

	private static String csvEscape(String value) {
		if (value == null) {
			return '';
		}
		if (value.containsAny(',"\n\r')) {
			return '"' + value.replace('"', '""') + '"';
		}
		return value;
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
		if (resourceList.isEmpty() || resourceList[0].Body == null) {
			throw new DistrictZoneAlignmentException(Label.DZA_TemplateUnavailable);
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
		saveTemplateDocumentId(documentId);
		return documentId;
	}

	private static void saveTemplateDocumentId(Id documentId) {
		FieldServiceBackofficeConfig__c config = FieldServiceBackofficeConfig__c.getOrgDefaults();
		if (config.Id == null) {
			config.SetupOwnerId = UserInfo.getOrganizationId();
		}
		config.DistrictZoneAlignmentTemplateId__c = documentId;
		saveConfig(config);
	}

	/**
	 * @description Custom setting rows are saved in system mode: back-office users have no edit access to
	 *              custom settings, and only these two file Id fields are written.
	 */
	private static void saveConfig(FieldServiceBackofficeConfig__c config) {
		Database.upsert(config, AccessLevel.SYSTEM_MODE);
	}

	/**
	 * @description Active users whose full name, username or email matches an ASM value from the file.
	 */
	private static List<User> selectActiveUsers(Set<String> keySet) {
		if (keySet.isEmpty()) {
			return new List<User>();
		}
		List<String> keyList = new List<String>(keySet);
		return (List<User>) SoqlQueryBuilder.fromObject('User')
			.selectFields(USER_FIELDS)
			.whereEquals('IsActive', true)
			.whereIn('Name', keyList)
			.whereIn('Username', keyList)
			.whereIn('Email', keyList)
			.withFilterLogic('1 AND (2 OR 3 OR 4)')
			.execute();
	}

	private static Boolean isAccessibleDocument(Id documentId) {
		return documentId != null &&
			!ContentDocumentsSelector.selectIdAndTitleByIds(new Set<Id>{ documentId }).isEmpty();
	}

	private static void addIfPresent(Set<String> valueSet, String value) {
		if (value != null) {
			valueSet.add(value);
		}
	}

	private static Id toId(String value) {
		if (String.isBlank(value)) {
			return null;
		}
		try {
			return Id.valueOf(value.trim());
		} catch (StringException e) {
			return null;
		}
	}

	/**
	 * @description Logs the failure and returns an exception with a user-facing message.
	 */
	private static DistrictZoneAlignmentException toAlignmentException(Exception e) {
		if (e instanceof DistrictZoneAlignmentException) {
			Logger.warn(e.getMessage()).addTag(LOG_TAG);
			return (DistrictZoneAlignmentException) e;
		}
		Logger.error('District Zone Alignment failed.', e).addTag(LOG_TAG);
		return new DistrictZoneAlignmentException(Label.DZA_UnexpectedError, e);
	}
}