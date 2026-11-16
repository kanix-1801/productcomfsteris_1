/**
 * @author Sagar Anand
 * @date 2026-11-05
 * @description GW-2707: Processes technician-to-district realignment for the next fiscal year from the Tech District
 *              Alignment Excel file. Validates the technician HRIS ID (ServiceResource.ExternalID__c), the current
 *              territory membership and the ASM HRIS IDs (User.EmployeeNumber__c). Creates next-year territories,
 *              updates Territory Managers, ends the current membership at the time of upload and adds the
 *              technician to the next-year territory from the first day of the next fiscal year.
 *              Processes only IPTLS, Low Temp, Procedural and Endoscopy territories.
 *              Invalid rows are skipped and written to a user-specific error file, which is emailed to the
 *              uploader. "-" is treated as blank; name columns are reference-only.
 * @group Field Service
 * @see TechDistrictAlignmentController
 */
public with sharing class TechDistrictAlignmentService {
	public static final String TEMPLATE_TITLE = 'Tech District Alignment Template';
	public static final String TEMPLATE_RESOURCE_NAME = 'TechDistrictAlignmentTemplate';
	public static final String TEMPLATE_FILE_NAME = 'Tech_District_Alignment_Template.xlsx';
	public static final String ERROR_FILE_TITLE = 'Tech District Alignment Errors';
	public static final String ERROR_FILE_NAME = 'Tech_District_Alignment_Errors.csv';
	public static final String DOWNLOAD_URL_PREFIX = '/sfc/servlet.shepherd/document/download/';
	public static final Set<String> SUPPORTED_TERRITORY_TYPES = new Set<String>{
		'IPTLS',
		'Low Temp',
		'Procedural',
		'Endoscopy'
	};
	@TestVisible
	private static final Integer MAX_ROWS = 2000;
	@TestVisible
	private static Date runDate = Date.today();
	private static final Integer NAME_MAX_LENGTH = 80;
	private static final String LOG_SCENARIO = 'Tech District Alignment';
	private static final List<String> LOG_TAGS = new List<String>{
		'Service Territory',
		'Service Territory Member',
		'Service Resource'
	};
	private static final List<String> TERRITORY_FIELDS = new List<String>{
		'Id',
		'Name',
		'RegionNumber__c',
		'TerritoryType__c',
		'TerritoryManager__c',
		'ParentTerritoryId',
		'OperatingHoursId',
		'IsActive'
	};
	private static final String PRIMARY_MEMBER = 'P';
	private static final String SECONDARY_MEMBER = 'S';
	private static final List<String> TECH_HRIS_COLUMNS = new List<String>{
		'techhris',
		'techhrisid',
		'techhrisnumber'
	};
	private static final List<String> CURRENT_TERRITORY_COLUMNS = new List<String>{
		'currentterritory',
		'currentterritoryid',
		'currentterritorynumber'
	};
	private static final List<String> CURRENT_ASM_HRIS_COLUMNS = new List<String>{
		'currentasmhris',
		'currentasmhrisid',
		'currentasmhrisnumber'
	};
	private static final List<String> NEXT_TERRITORY_COLUMNS = new List<String>{
		'nextyearterritory',
		'nextyearterritoryid',
		'nextyearterritorynumber'
	};
	private static final List<String> NEXT_ASM_HRIS_COLUMNS = new List<String>{
		'nextyearasmhris',
		'nextyearasmhrisid',
		'nextyearasmhrisnumber'
	};

	/**
	 * @description Counts, skip messages and error file returned to the LWC after Start Upload.
	 */
	public class ProcessResult {
		@AuraEnabled
		public Integer processedCount = 0;
		@AuraEnabled
		public Integer movedCount = 0;
		@AuraEnabled
		public Integer territoryCreatedCount = 0;
		@AuraEnabled
		public Integer managerUpdatedCount = 0;
		@AuraEnabled
		public Integer unchangedCount = 0;
		@AuraEnabled
		public Integer skippedCount = 0;
		@AuraEnabled
		public List<String> errors = new List<String>();
		@AuraEnabled
		public Id errorFileDocumentId;
		@AuraEnabled
		public Boolean emailSent = false;
		@AuraEnabled
		public Date nextFiscalYearStart;
		@AuraEnabled
		public String summary;
	}

	private class AlignmentRow {
		Integer rowNumber;
		List<String> cells;
		String techHris;
		String currentTerritory;
		String currentAsmHris;
		String nextTerritory;
		String nextAsmHris;
		String errorMessage;
		ServiceResource resource;
		ServiceTerritoryMember currentMember;
		ServiceTerritory targetTerritory;
		Boolean createMember = false;
		Boolean endMember = false;
		Boolean updatesManager = false;
	}

	/**
	 * @description Returns the template file, copying the packaged template into Salesforce Files and sharing it
	 *              with all internal users the first time. To ship a new template, upload it to Files and put its
	 *              Id on the org default FieldServiceBackofficeConfig__c.TechDistrictAlignmentTemplateId__c.
	 * @return ContentDocument Id of the template file.
	 * @throws AuraHandledException When neither a stored template nor the packaged template exists.
	 */
	public static Id ensureTemplateDocumentId() {
		try {
			Logger.setScenario(LOG_SCENARIO);
			return resolveTemplateDocumentId();
		} catch (Exception e) {
			logFailure('Template download failed', e);
			throw e;
		} finally {
			Logger.saveLog();
		}
	}

	/**
	 * @description ContentDocument Id of the running user's error file, or null when none exists yet.
	 * @return ContentDocument Id, or null.
	 */
	public static Id errorFileDocumentId() {
		try {
			Logger.setScenario(LOG_SCENARIO);
			return storedErrorFileDocumentId();
		} catch (Exception e) {
			logFailure('Error file lookup failed', e);
			throw e;
		} finally {
			Logger.saveLog();
		}
	}

	private static Id resolveTemplateDocumentId() {
		Id storedId = toId(FieldServiceBackofficeConfig__c.getOrgDefaults().TechDistrictAlignmentTemplateId__c);
		if (storedId != null && documentExists(storedId)) {
			return storedId;
		}

		List<ContentDocument> titledDocs = ContentDocumentsSelector.selectLatestByTitle(TEMPLATE_TITLE);
		if (!titledDocs.isEmpty()) {
			saveTemplateDocumentId(titledDocs[0].Id);
			return titledDocs[0].Id;
		}

		List<StaticResource> resources = StaticResourcesSelector.selectByName(TEMPLATE_RESOURCE_NAME);
		if (resources.isEmpty() || resources[0].Body == null) {
			throw PlatformUtilities.buildAuraException(Label.TDA_TemplateUnavailable);
		}

		ContentVersion version = new ContentVersion(
			Title = TEMPLATE_TITLE,
			PathOnClient = TEMPLATE_FILE_NAME,
			VersionData = resources[0].Body,
			IsMajorVersion = true
		);
		Database.insert(version, AccessLevel.USER_MODE);
		Id documentId = documentIdOf(version.Id);
		// Shared with the whole org so every back-office user downloads the same template.
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

	private static Id storedErrorFileDocumentId() {
		FieldServiceBackofficeConfig__c config = FieldServiceBackofficeConfig__c.getValues(UserInfo.getUserId());
		Id storedId = toId(config == null ? null : config.TechDistrictAlignmentErrorFileId__c);
		if (storedId == null || !documentExists(storedId)) {
			return null;
		}
		return storedId;
	}

	private static Boolean documentExists(Id documentId) {
		return !ContentDocumentsSelector.selectIdAndTitleByIds(new Set<Id>{ documentId }).isEmpty();
	}

	/**
	 * @description First day of the next fiscal year, from the org's fiscal year start month: this year's start
	 *              when it is still ahead, otherwise next year's.
	 * @return Next fiscal year start date.
	 */
	public static Date nextFiscalYearStart() {
		Organization org = (Organization) SoqlQueryBuilder.fromObject('Organization')
			.selectField('FiscalYearStartMonth')
			.first();
		Date thisYearStart = Date.newInstance(runDate.year(), org.FiscalYearStartMonth, 1);
		return runDate < thisYearStart ? thisYearStart : thisYearStart.addYears(1);
	}

	/**
	 * @description Midnight (running user's time zone) at the start of the next fiscal year.
	 * @return Effective start date for new Service Territory Members.
	 */
	@TestVisible
	private static Datetime nextFiscalYearStartDatetime() {
		return Datetime.newInstance(nextFiscalYearStart(), Time.newInstance(0, 0, 0, 0));
	}

	/**
	 * @description Processes the uploaded file, writes the error file and emails it to the running user.
	 *              Side effects: inserts/updates ServiceTerritory and ServiceTerritoryMember records, adds a
	 *              version to the user's error file, upserts the user-level custom setting and sends an email.
	 * @param contentDocumentId Salesforce Files document Id from lightning-file-upload.
	 * @return Counts, row-level skip messages and the error file Id.
	 * @throws AuraHandledException When the file is missing, unreadable, lacks required columns or
	 *         exceeds the row limit.
	 */
	public static ProcessResult processUpload(Id contentDocumentId) {
		try {
			Logger.setScenario(LOG_SCENARIO);
			ProcessResult result = process(contentDocumentId);
			Logger.info('Tech District Alignment ' + result.summary).addTags(LOG_TAGS);
			return result;
		} catch (Exception e) {
			logFailure('Tech District Alignment upload failed', e);
			throw e;
		} finally {
			Logger.saveLog();
		}
	}

	private static ProcessResult process(Id contentDocumentId) {
		ProcessResult result = new ProcessResult();
		if (contentDocumentId == null) {
			throw PlatformUtilities.buildAuraException(Label.TDA_FileRequired);
		}

		List<List<String>> table = readUploadedFile(contentDocumentId);
		List<AlignmentRow> rows = toRows(table);
		result.processedCount = rows.size();
		result.nextFiscalYearStart = nextFiscalYearStart();
		if (!rows.isEmpty()) {
			applyRows(rows, result);
		}

		for (AlignmentRow row : rows) {
			if (row.errorMessage != null) {
				result.skippedCount++;
				List<Object> rowErrorParams = new List<Object>{ String.valueOf(row.rowNumber), row.errorMessage };
				result.errors.add(String.format(Label.TDA_RowError, rowErrorParams));
			}
		}
		result.summary = summary(result);

		ContentVersion errorFile = writeErrorFile(table[0], rows);
		result.errorFileDocumentId = errorFile.ContentDocumentId;
		result.emailSent = sendResultEmail(result, errorFile.Id);
		return result;
	}

	/**
	 * @description Reads the first worksheet of the uploaded Excel (.xlsx) file.
	 */
	private static List<List<String>> readUploadedFile(Id contentDocumentId) {
		List<ContentVersion> versions = ContentVersionsSelector.selectLatestByContentDocumentId(contentDocumentId);
		if (
			versions.isEmpty() ||
			versions[0].VersionData == null ||
			versions[0].FileExtension?.toLowerCase() != 'xlsx'
		) {
			throw PlatformUtilities.buildAuraException(Label.TDA_FileUnreadable);
		}
		try {
			return ExcelFileParser.readFirstSheet(versions[0].VersionData);
		} catch (ExcelFileParser.ParseException e) {
			throw PlatformUtilities.buildAuraException(Label.TDA_FileUnreadable);
		}
	}

	/**
	 * @description Logs a failed request at the source: WARN for an expected, user-correctable problem
	 *              (AuraHandledException), ERROR for anything unexpected.
	 */
	private static void logFailure(String message, Exception e) {
		if (e instanceof AuraHandledException) {
			Logger.warn(message + ': ' + e.getMessage(), e).addTags(LOG_TAGS);
		} else {
			Logger.error(message, e).addTags(LOG_TAGS);
		}
	}

	private static void applyRows(List<AlignmentRow> rows, ProcessResult result) {
		AlignmentPlan plan = new AlignmentPlan(rows);
		for (AlignmentRow row : rows) {
			row.errorMessage = plan.planRow(row);
		}
		result.unchangedCount = plan.unchangedCount;

		if (!plan.newTerritories.isEmpty()) {
			List<Database.SaveResult> saveResults = Database.insert(plan.newTerritories, false, AccessLevel.USER_MODE);
			for (Integer i = 0; i < saveResults.size(); i++) {
				if (saveResults[i].isSuccess()) {
					result.territoryCreatedCount++;
				} else {
					ServiceTerritory failed = plan.newTerritories[i];
					failRows(
						plan.rowsByNewTerritory.get(key(failed.RegionNumber__c)),
						String.format(
							Label.TDA_TerritoryCreateFailed,
							new List<Object>{ failed.RegionNumber__c, firstError(saveResults[i]) }
						)
					);
				}
			}
		}

		List<ServiceTerritory> managerUpdates = plan.managerUpdateById.values();
		if (!managerUpdates.isEmpty()) {
			List<Database.SaveResult> saveResults = Database.update(managerUpdates, false, AccessLevel.USER_MODE);
			for (Integer i = 0; i < saveResults.size(); i++) {
				if (saveResults[i].isSuccess()) {
					result.managerUpdatedCount++;
				} else {
					failRows(
						plan.rowsByManagerUpdate.get(managerUpdates[i].Id),
						String.format(Label.TDA_ManagerUpdateFailed, new List<Object>{ firstError(saveResults[i]) })
					);
				}
			}
		}

		// End the current membership before creating the next year one: Salesforce rejects a new primary
		// membership while the resource's current primary membership is still open-ended (date overlap).
		Datetime endDatetime = Datetime.now();
		List<ServiceTerritoryMember> endedMembers = new List<ServiceTerritoryMember>();
		List<AlignmentRow> endedMemberRows = new List<AlignmentRow>();
		for (AlignmentRow row : rows) {
			if (row.errorMessage == null && row.endMember) {
				endedMembers.add(new ServiceTerritoryMember(Id = row.currentMember.Id, EffectiveEndDate = endDatetime));
				endedMemberRows.add(row);
			}
		}
		if (!endedMembers.isEmpty()) {
			List<Database.SaveResult> saveResults = Database.update(endedMembers, false, AccessLevel.USER_MODE);
			for (Integer i = 0; i < saveResults.size(); i++) {
				if (!saveResults[i].isSuccess()) {
					endedMemberRows[i].errorMessage = String.format(
						Label.TDA_MemberEndFailed,
						new List<Object>{ firstError(saveResults[i]) }
					);
				}
			}
		}

		Datetime startDatetime = nextFiscalYearStartDatetime();
		List<ServiceTerritoryMember> newMembers = new List<ServiceTerritoryMember>();
		List<AlignmentRow> newMemberRows = new List<AlignmentRow>();
		for (AlignmentRow row : rows) {
			if (row.errorMessage == null && row.createMember) {
				newMembers.add(buildMember(row, startDatetime));
				newMemberRows.add(row);
			}
		}
		if (!newMembers.isEmpty()) {
			List<Database.SaveResult> saveResults = Database.insert(newMembers, false, AccessLevel.USER_MODE);
			List<ServiceTerritoryMember> restoredMembers = new List<ServiceTerritoryMember>();
			for (Integer i = 0; i < saveResults.size(); i++) {
				if (!saveResults[i].isSuccess()) {
					AlignmentRow row = newMemberRows[i];
					row.errorMessage = String.format(
						Label.TDA_MemberCreateFailed,
						new List<Object>{ firstError(saveResults[i]) }
					);
					if (row.endMember) {
						restoredMembers.add(
							new ServiceTerritoryMember(
								Id = row.currentMember.Id,
								EffectiveEndDate = row.currentMember.EffectiveEndDate
							)
						);
					}
				}
			}
			if (!restoredMembers.isEmpty()) {
				// Undo the end date so the technician keeps the current territory when the move failed.
				Database.update(restoredMembers, false, AccessLevel.USER_MODE);
			}
		}

		for (AlignmentRow row : rows) {
			if (row.errorMessage == null && (row.createMember || row.endMember)) {
				result.movedCount++;
			}
		}
	}

	private static void failRows(List<AlignmentRow> rows, String message) {
		if (rows == null) {
			return;
		}
		for (AlignmentRow row : rows) {
			if (row.errorMessage == null) {
				row.errorMessage = message;
			}
		}
	}

	private static ServiceTerritoryMember buildMember(AlignmentRow row, Datetime startDatetime) {
		String memberType = row.currentMember.TerritoryType == SECONDARY_MEMBER ? SECONDARY_MEMBER : PRIMARY_MEMBER;
		return new ServiceTerritoryMember(
			ServiceResourceId = row.resource.Id,
			ServiceTerritoryId = row.targetTerritory.Id,
			EffectiveStartDate = startDatetime,
			TerritoryType = memberType,
			OperatingHoursId = row.currentMember.OperatingHoursId
		);
	}

	/**
	 * @description Looks up every technician, user, territory and membership referenced by the file once, then
	 *              turns each row into territory / manager / membership changes, no change, or an error message.
	 */
	private class AlignmentPlan {
		Datetime now = Datetime.now();
		Datetime startOfToday = Datetime.newInstance(Date.today(), Time.newInstance(0, 0, 0, 0));
		Map<String, User> userByHris = new Map<String, User>();
		Map<String, ServiceResource> resourceByExternalId = new Map<String, ServiceResource>();
		Map<String, ServiceTerritory> territoryByNumber = new Map<String, ServiceTerritory>();
		Map<String, List<ServiceTerritoryMember>> membersByKey = new Map<String, List<ServiceTerritoryMember>>();
		Set<Id> claimedResourceIds = new Set<Id>();
		Map<Id, Id> requestedManagerByTerritoryId = new Map<Id, Id>();
		Map<String, ServiceTerritory> newTerritoryByNumber = new Map<String, ServiceTerritory>();
		List<ServiceTerritory> newTerritories = new List<ServiceTerritory>();
		Map<String, List<AlignmentRow>> rowsByNewTerritory = new Map<String, List<AlignmentRow>>();
		Map<Id, ServiceTerritory> managerUpdateById = new Map<Id, ServiceTerritory>();
		Map<Id, List<AlignmentRow>> rowsByManagerUpdate = new Map<Id, List<AlignmentRow>>();
		Integer unchangedCount = 0;

		AlignmentPlan(List<AlignmentRow> rows) {
			Set<String> techHrisValues = new Set<String>();
			Set<String> asmHrisValues = new Set<String>();
			Set<String> territoryNumbers = new Set<String>();
			for (AlignmentRow row : rows) {
				addIfPresent(techHrisValues, row.techHris);
				addIfPresent(asmHrisValues, row.currentAsmHris);
				addIfPresent(asmHrisValues, row.nextAsmHris);
				addIfPresent(territoryNumbers, row.currentTerritory);
				addIfPresent(territoryNumbers, row.nextTerritory);
			}

			for (User activeUser : UserSelector.selectActiveByEmployeeNumbers(asmHrisValues)) {
				userByHris.put(key(activeUser.EmployeeNumber__c), activeUser);
			}

			Set<Id> resourceIds = new Set<Id>();
			for (ServiceResource resource : ServiceResourcesSelector.selectActiveByExternalIds(techHrisValues)) {
				resourceIds.add(resource.Id);
				resourceByExternalId.put(key(resource.ExternalID__c), resource);
			}

			Set<Id> territoryIds = new Set<Id>();
			List<ServiceTerritory> territories = ServiceTerritoriesSelector.selectByRegionNumbers(
				territoryNumbers,
				TERRITORY_FIELDS
			);
			for (ServiceTerritory territory : territories) {
				territoryByNumber.put(key(territory.RegionNumber__c), territory);
				territoryIds.add(territory.Id);
			}

			List<ServiceTerritoryMember> members = ServiceTerritoryMembersSelector.selectOpenByResourcesAndTerritories(
				resourceIds,
				territoryIds,
				startOfToday
			);
			for (ServiceTerritoryMember member : members) {
				String memberKey = memberKey(member.ServiceResourceId, member.ServiceTerritoryId);
				if (!membersByKey.containsKey(memberKey)) {
					membersByKey.put(memberKey, new List<ServiceTerritoryMember>());
				}
				membersByKey.get(memberKey).add(member);
			}
		}

		String planRow(AlignmentRow row) {
			if (String.isBlank(row.techHris)) {
				return Label.TDA_TechRequired;
			}
			ServiceResource resource = resourceByExternalId.get(key(row.techHris));
			if (resource == null) {
				return String.format(Label.TDA_TechNotFound, new List<Object>{ row.techHris });
			}
			if (claimedResourceIds.contains(resource.Id)) {
				return String.format(Label.TDA_TechDuplicate, new List<Object>{ row.techHris });
			}

			if (String.isBlank(row.currentTerritory)) {
				return Label.TDA_CurrentTerritoryRequired;
			}
			ServiceTerritory current = territoryByNumber.get(key(row.currentTerritory));
			if (current == null) {
				return String.format(Label.TDA_CurrentTerritoryNotFound, new List<Object>{ row.currentTerritory });
			}
			String currentTypeError = typeError(current, Label.TDA_CurrentTerritoryUnsupported);
			if (currentTypeError != null) {
				return currentTypeError;
			}
			ServiceTerritoryMember currentMember = activeMember(resource.Id, current.Id);
			if (currentMember == null) {
				return String.format(Label.TDA_NotAssigned, new List<Object>{ current.RegionNumber__c });
			}

			if (String.isBlank(row.currentAsmHris)) {
				return Label.TDA_CurrentAsmRequired;
			}
			if (!userByHris.containsKey(key(row.currentAsmHris))) {
				return String.format(Label.TDA_CurrentAsmNotFound, new List<Object>{ row.currentAsmHris });
			}

			if (String.isBlank(row.nextTerritory)) {
				return Label.TDA_NextTerritoryRequired;
			}
			User nextAsm;
			if (String.isNotBlank(row.nextAsmHris)) {
				nextAsm = userByHris.get(key(row.nextAsmHris));
				if (nextAsm == null) {
					return String.format(Label.TDA_NextAsmNotFound, new List<Object>{ row.nextAsmHris });
				}
			}

			ServiceTerritory existing = territoryByNumber.get(key(row.nextTerritory));
			String targetError = existing == null
				? planNewTerritory(row, current, nextAsm)
				: planExistingTerritory(row, existing, nextAsm);
			if (targetError != null) {
				return targetError;
			}

			row.resource = resource;
			row.currentMember = currentMember;
			claimedResourceIds.add(resource.Id);
			Boolean moves = row.targetTerritory.Id == null || row.targetTerritory.Id != current.Id;
			if (moves) {
				row.createMember =
					row.targetTerritory.Id == null || openMember(resource.Id, row.targetTerritory.Id) == null;
				row.endMember = currentMember.EffectiveEndDate == null || currentMember.EffectiveEndDate > now;
			}
			if (!row.createMember && !row.endMember && !row.updatesManager) {
				unchangedCount++;
			}
			return null;
		}

		String planNewTerritory(AlignmentRow row, ServiceTerritory current, User nextAsm) {
			if (nextAsm == null) {
				return String.format(Label.TDA_NextAsmRequired, new List<Object>{ row.nextTerritory });
			}
			String territoryKey = key(row.nextTerritory);
			ServiceTerritory pending = newTerritoryByNumber.get(territoryKey);
			if (pending == null) {
				pending = new ServiceTerritory(
					Name = row.nextTerritory.left(NAME_MAX_LENGTH),
					RegionNumber__c = row.nextTerritory,
					TerritoryType__c = current.TerritoryType__c,
					ParentTerritoryId = current.ParentTerritoryId,
					OperatingHoursId = current.OperatingHoursId,
					TerritoryManager__c = nextAsm.Id,
					IsActive = true
				);
				newTerritoryByNumber.put(territoryKey, pending);
				newTerritories.add(pending);
				rowsByNewTerritory.put(territoryKey, new List<AlignmentRow>());
			} else if (pending.TerritoryManager__c != nextAsm.Id) {
				return String.format(Label.TDA_ConflictingAsm, new List<Object>{ row.nextTerritory });
			}
			rowsByNewTerritory.get(territoryKey).add(row);
			row.targetTerritory = pending;
			return null;
		}

		String planExistingTerritory(AlignmentRow row, ServiceTerritory target, User nextAsm) {
			String nextTypeError = typeError(target, Label.TDA_NextTerritoryUnsupported);
			if (nextTypeError != null) {
				return nextTypeError;
			}
			if (!target.IsActive) {
				return String.format(Label.TDA_NextTerritoryInactive, new List<Object>{ target.RegionNumber__c });
			}

			Boolean asmChanged = nextAsm != null && key(row.nextAsmHris) != key(row.currentAsmHris);
			if (asmChanged) {
				Id requested = requestedManagerByTerritoryId.get(target.Id);
				if (requested != null && requested != nextAsm.Id) {
					return String.format(Label.TDA_ConflictingAsm, new List<Object>{ target.RegionNumber__c });
				}
				requestedManagerByTerritoryId.put(target.Id, nextAsm.Id);
				if (target.TerritoryManager__c != nextAsm.Id) {
					if (!managerUpdateById.containsKey(target.Id)) {
						managerUpdateById.put(
							target.Id,
							new ServiceTerritory(Id = target.Id, TerritoryManager__c = nextAsm.Id)
						);
						rowsByManagerUpdate.put(target.Id, new List<AlignmentRow>());
					}
					rowsByManagerUpdate.get(target.Id).add(row);
					row.updatesManager = true;
				}
			}
			row.targetTerritory = target;
			return null;
		}

		String typeError(ServiceTerritory territory, String message) {
			if (SUPPORTED_TERRITORY_TYPES.contains(territory.TerritoryType__c)) {
				return null;
			}
			String typeLabel = String.isBlank(territory.TerritoryType__c) ? '(blank)' : territory.TerritoryType__c;
			return String.format(message, new List<Object>{ territory.RegionNumber__c, typeLabel });
		}

		/**
		 * @description Membership that has started and is not ended before today (newest first).
		 */
		ServiceTerritoryMember activeMember(Id resourceId, Id territoryId) {
			List<ServiceTerritoryMember> members = membersByKey.get(memberKey(resourceId, territoryId));
			if (members == null) {
				return null;
			}
			for (ServiceTerritoryMember member : members) {
				if (member.EffectiveStartDate <= now) {
					return member;
				}
			}
			return null;
		}

		/**
		 * @description Any membership not ended before today, including one that starts in the future.
		 */
		ServiceTerritoryMember openMember(Id resourceId, Id territoryId) {
			List<ServiceTerritoryMember> members = membersByKey.get(memberKey(resourceId, territoryId));
			return members == null || members.isEmpty() ? null : members[0];
		}
	}

	private static List<AlignmentRow> toRows(List<List<String>> table) {
		Map<String, Integer> columnIndexByName = columnIndexByName(table.isEmpty() ? new List<String>() : table[0]);
		Boolean hasRequiredColumns =
			hasColumn(columnIndexByName, TECH_HRIS_COLUMNS) &&
			hasColumn(columnIndexByName, CURRENT_TERRITORY_COLUMNS) &&
			hasColumn(columnIndexByName, CURRENT_ASM_HRIS_COLUMNS) &&
			hasColumn(columnIndexByName, NEXT_TERRITORY_COLUMNS) &&
			hasColumn(columnIndexByName, NEXT_ASM_HRIS_COLUMNS);
		if (!hasRequiredColumns) {
			throw PlatformUtilities.buildAuraException(Label.TDA_MissingColumns);
		}
		if (table.size() - 1 > MAX_ROWS) {
			throw PlatformUtilities.buildAuraException(
				String.format(Label.TDA_TooManyRows, new List<Object>{ String.valueOf(MAX_ROWS) })
			);
		}

		List<AlignmentRow> rows = new List<AlignmentRow>();
		for (Integer i = 1; i < table.size(); i++) {
			List<String> cells = table[i];
			AlignmentRow row = new AlignmentRow();
			row.rowNumber = i + 1;
			row.cells = cells;
			row.techHris = normalizeHris(columnValue(cells, columnIndexByName, TECH_HRIS_COLUMNS));
			row.currentTerritory = columnValue(cells, columnIndexByName, CURRENT_TERRITORY_COLUMNS);
			row.currentAsmHris = normalizeHris(columnValue(cells, columnIndexByName, CURRENT_ASM_HRIS_COLUMNS));
			row.nextTerritory = columnValue(cells, columnIndexByName, NEXT_TERRITORY_COLUMNS);
			row.nextAsmHris = normalizeHris(columnValue(cells, columnIndexByName, NEXT_ASM_HRIS_COLUMNS));
			Boolean isBlankRow =
				String.isBlank(row.techHris) &&
				String.isBlank(row.currentTerritory) &&
				String.isBlank(row.currentAsmHris) &&
				String.isBlank(row.nextTerritory) &&
				String.isBlank(row.nextAsmHris);
			if (!isBlankRow) {
				rows.add(row);
			}
		}
		return rows;
	}

	/**
	 * @description Column index keyed by header name in lower case without spaces or symbols ("TECH HRIS#" is
	 *              "techhris").
	 */
	private static Map<String, Integer> columnIndexByName(List<String> header) {
		Map<String, Integer> columnIndexByName = new Map<String, Integer>();
		for (Integer i = 0; i < header.size(); i++) {
			String name = normalizeHeader(header[i]);
			if (String.isNotBlank(name) && !columnIndexByName.containsKey(name)) {
				columnIndexByName.put(name, i);
			}
		}
		return columnIndexByName;
	}

	private static String normalizeHeader(String header) {
		return header == null ? '' : header.toLowerCase().replaceAll('[^a-z0-9]', '');
	}

	private static Boolean hasColumn(Map<String, Integer> columnIndexByName, List<String> names) {
		for (String name : names) {
			if (columnIndexByName.containsKey(name)) {
				return true;
			}
		}
		return false;
	}

	/**
	 * @description Trimmed value of the first matching column; a blank or dash-only placeholder ("-") is null.
	 */
	private static String columnValue(List<String> cells, Map<String, Integer> columnIndexByName, List<String> names) {
		for (String name : names) {
			Integer index = columnIndexByName.get(name);
			if (index != null && index < cells.size() && cells[index] != null) {
				String value = cells[index].trim();
				return String.isBlank(value.replaceAll('\\p{Pd}', '')) ? null : value;
			}
		}
		return null;
	}

	/**
	 * @description Excel can store an HRIS number as "50708.0"; drop a zero-only decimal part.
	 */
	private static String normalizeHris(String value) {
		return value?.replaceFirst('^(\\d+)\\.0+$', '$1');
	}

	/**
	 * @description Adds a new version to the running user's error file, creating the file on first use. The file
	 *              repeats the uploaded columns for each skipped row, with the row number first and the error last.
	 */
	private static ContentVersion writeErrorFile(List<String> header, List<AlignmentRow> rows) {
		List<String> lines = new List<String>{
			csvLine(Label.TDA_ErrorFileRowColumn, header, Label.TDA_ErrorFileErrorColumn, header.size())
		};
		for (AlignmentRow row : rows) {
			if (row.errorMessage != null) {
				lines.add(csvLine(String.valueOf(row.rowNumber), row.cells, row.errorMessage, header.size()));
			}
		}

		Id existingDocumentId = storedErrorFileDocumentId();
		ContentVersion version = new ContentVersion(
			Title = ERROR_FILE_TITLE,
			PathOnClient = ERROR_FILE_NAME,
			VersionData = Blob.valueOf(String.join(lines, '\n') + '\n'),
			ReasonForChange = 'Tech District Alignment upload ' + Datetime.now().format(),
			ContentDocumentId = existingDocumentId
		);
		Database.insert(version, AccessLevel.USER_MODE);

		// ContentDocumentId is create-only, so read it back instead of setting it on the inserted record.
		ContentVersion saved = new ContentVersion(Id = version.Id, ContentDocumentId = documentIdOf(version.Id));
		if (saved.ContentDocumentId != existingDocumentId) {
			FieldServiceBackofficeConfig__c config = FieldServiceBackofficeConfig__c.getValues(UserInfo.getUserId());
			if (config == null) {
				config = new FieldServiceBackofficeConfig__c(SetupOwnerId = UserInfo.getUserId());
			}
			config.TechDistrictAlignmentErrorFileId__c = String.valueOf(saved.ContentDocumentId);
			saveConfig(config);
		}
		return saved;
	}

	private static String csvLine(String first, List<String> cells, String last, Integer columnCount) {
		List<String> values = new List<String>{ csvEscape(first) };
		for (Integer i = 0; i < columnCount; i++) {
			values.add(csvEscape(i < cells.size() ? cells[i] : null));
		}
		values.add(csvEscape(last));
		return String.join(values, ',');
	}

	private static String csvEscape(String value) {
		if (value == null) {
			return '';
		}
		return value.containsAny(',"\n\r') ? '"' + value.replace('"', '""') + '"' : value;
	}

	private static Boolean sendResultEmail(ProcessResult result, Id errorFileVersionId) {
		Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
		mail.setTargetObjectId(UserInfo.getUserId());
		mail.setSaveAsActivity(false);
		mail.setSubject(Label.TDA_EmailSubject);
		List<Object> bodyParams = new List<Object>{ result.summary, result.nextFiscalYearStart.format() };
		mail.setPlainTextBody(String.format(Label.TDA_EmailBody, bodyParams));
		mail.setEntityAttachments(new List<String>{ errorFileVersionId });
		try {
			Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{ mail });
			return true;
		} catch (EmailException e) {
			Logger.warn('Tech District Alignment result email could not be sent.', e).addTags(LOG_TAGS);
			return false;
		}
	}

	private static String summary(ProcessResult result) {
		return String.format(
			Label.TDA_Summary,
			new List<Object>{
				String.valueOf(result.processedCount),
				String.valueOf(result.movedCount),
				String.valueOf(result.territoryCreatedCount),
				String.valueOf(result.managerUpdatedCount),
				String.valueOf(result.unchangedCount),
				String.valueOf(result.skippedCount)
			}
		);
	}

	private static void saveTemplateDocumentId(Id documentId) {
		FieldServiceBackofficeConfig__c config = FieldServiceBackofficeConfig__c.getOrgDefaults();
		if (config.Id == null) {
			config.SetupOwnerId = UserInfo.getOrganizationId();
		}
		config.TechDistrictAlignmentTemplateId__c = String.valueOf(documentId);
		saveConfig(config);
	}

	/**
	 * @description Custom setting rows are saved in system mode: back-office users have no edit access to
	 *              custom settings, and only the file Id fields are written.
	 */
	private static void saveConfig(FieldServiceBackofficeConfig__c config) {
		Database.upsert(config, AccessLevel.SYSTEM_MODE);
	}

	private static void addIfPresent(Set<String> values, String value) {
		if (String.isNotBlank(value)) {
			values.add(value);
		}
	}

	private static String key(String value) {
		return value == null ? null : value.trim().toLowerCase();
	}

	private static String memberKey(Id resourceId, Id territoryId) {
		return String.valueOf(resourceId) + '|' + String.valueOf(territoryId);
	}

	private static String firstError(Database.SaveResult saveResult) {
		return saveResult.getErrors().isEmpty() ? 'Unknown error.' : saveResult.getErrors()[0].getMessage();
	}

	private static Id documentIdOf(Id contentVersionId) {
		List<ContentVersion> versions = ContentVersionsSelector.selectDocumentIdByVersionId(contentVersionId);
		return versions.isEmpty() ? null : versions[0].ContentDocumentId;
	}

	private static Id toId(String value) {
		return PlatformUtilities.parseId(PlatformUtilities.trimToNull(value));
	}
}