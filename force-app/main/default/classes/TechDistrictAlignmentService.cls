/**
 * @description GW-2707 - Processes technician-to-district realignment for the next fiscal year
 *              from the Tech District Alignment file. Validates technician HRIS ID, current territory
 *              membership and ASM HRIS IDs. Creates or updates next-year territories and ASM assignments,
 *              adds technicians effective April 1, and ends current memberships on March 31 (23:59:59) so
 *              there is no gap and no overlap between the two memberships.
 *              Processes only IPTLS, Low Temp, Procedural and Endoscopy territories.
 *              Invalid rows are skipped and logged in a user-specific error file, which is emailed
 *              to the uploader. "-" is treated as blank; name columns are reference-only.
 */
public with sharing class TechDistrictAlignmentService {
    public static final String TEMPLATE_TITLE = 'Tech District Alignment Template';
    public static final String TEMPLATE_RESOURCE_NAME = 'TechDistrictAlignmentTemplate';
    public static final String ERROR_FILE_TITLE = 'Tech District Alignment Errors';
    public static final String ERROR_FILE_NAME = 'Tech_District_Alignment_Errors.csv';
    public static final String DOWNLOAD_URL_PREFIX = '/sfc/servlet.shepherd/document/download/';
    public static final Set<String> SUPPORTED_TERRITORY_TYPES = new Set<String>{ 'IPTLS', 'Low Temp', 'Procedural', 'Endoscopy' };
    public static final Integer FISCAL_YEAR_START_MONTH = 4;
    public static final Integer FISCAL_YEAR_START_DAY = 1;
    @TestVisible
    private static final Integer MAX_ROWS = 2000;
    @TestVisible
    private static Date runDate = Date.today();
    private static final Integer NAME_MAX_LENGTH = 80;
    private static final String PRIMARY_MEMBER = 'P';
    private static final String SECONDARY_MEMBER = 'S';
    private static final String INVALID_TECH_HRIS = 'Invalid HRIS ID for Tech';
    private static final String INVALID_CURRENT_TERRITORY = 'Invalid Current Territory';
    private static final String NOT_ASSIGNED = 'Service Resource is not assigned to service territory';
    private static final String INVALID_CURRENT_ASM = 'Current ASM HRIS ID is invalid';
    private static final String INVALID_NEXT_TERRITORY = 'Invalid Next Year Territory';
    private static final String INVALID_NEXT_ASM = 'Next Year ASM HRIS ID is invalid';
    private static final List<String> TECH_HRIS_COLUMNS = new List<String>{ 'techhris', 'techhrisid', 'techhrisnumber' };
    private static final List<String> CURRENT_TERRITORY_COLUMNS = new List<String>{ 'currentterritory', 'currentterritoryid', 'currentterritorynumber' };
    private static final List<String> CURRENT_ASM_HRIS_COLUMNS = new List<String>{ 'currentasmhris', 'currentasmhrisid', 'currentasmhrisnumber' };
    private static final List<String> NEXT_TERRITORY_COLUMNS = new List<String>{ 'nextyearterritory', 'nextyearterritoryid', 'nextyearterritorynumber' };
    private static final List<String> NEXT_ASM_HRIS_COLUMNS = new List<String>{ 'nextyearasmhris', 'nextyearasmhrisid', 'nextyearasmhrisnumber' };

    /**
     * @description Counts, skip messages and error file returned to the LWC after Start Upload.
     */
    public class ProcessResult {
        @AuraEnabled public Integer processedCount;
        @AuraEnabled public Integer movedCount;
        @AuraEnabled public Integer territoryCreatedCount;
        @AuraEnabled public Integer managerUpdatedCount;
        @AuraEnabled public Integer unchangedCount;
        @AuraEnabled public Integer skippedCount;
        @AuraEnabled public List<String> errors;
        @AuraEnabled public Id errorFileDocumentId;
        @AuraEnabled public Boolean emailSent;
        @AuraEnabled public Date nextFiscalYearStart;
        @AuraEnabled public String summary;

        /**
         * @description Builds an empty result.
         */
        public ProcessResult() {
            this.processedCount = 0;
            this.movedCount = 0;
            this.territoryCreatedCount = 0;
            this.managerUpdatedCount = 0;
            this.unchangedCount = 0;
            this.skippedCount = 0;
            this.errors = new List<String>();
            this.emailSent = false;
        }
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
     * @description Copies the packaged template into Salesforce Files if needed and returns its ContentDocument Id.
     *              To ship a new Excel template, upload it to Files and put its Id on the org default
     *              FieldServiceBackofficeConfig__c.TechDistrictAlignmentTemplateId__c.
     * @return ContentDocument Id of the template file.
     */
    public static Id ensureTemplateDocumentId() {
        FieldServiceBackofficeConfig__c config = FieldServiceBackofficeConfig__c.getOrgDefaults();
        Id storedId = toId(config == null ? null : config.TechDistrictAlignmentTemplateId__c);
        if (storedId != null && !TechDistrictAlignmentSelector.selectDocumentsById(storedId).isEmpty()) {
            return storedId;
        }

        List<ContentDocument> titledDocs = TechDistrictAlignmentSelector.selectDocumentsByTitle(TEMPLATE_TITLE);
        if (!titledDocs.isEmpty()) {
            new ConfigStore().saveTemplateDocumentId(titledDocs[0].Id);
            return titledDocs[0].Id;
        }

        List<StaticResource> resources = TechDistrictAlignmentSelector.selectTemplateResource(TEMPLATE_RESOURCE_NAME);
        if (resources.isEmpty() || resources[0].Body == null) {
            throw auraError('Tech District Alignment template is not available.');
        }

        ContentVersion version = new ContentVersion();
        version.Title = TEMPLATE_TITLE;
        version.PathOnClient = 'Tech_District_Alignment_Template.csv';
        version.VersionData = resources[0].Body;
        version.IsMajorVersion = true;
        insert version;

        Id documentId = documentIdOf(version.Id);
        new ConfigStore().saveTemplateDocumentId(documentId);
        return documentId;
    }

    /**
     * @description ContentDocument Id of the running user's error file, or null when none exists yet.
     * @return ContentDocument Id, or null.
     */
    public static Id errorFileDocumentId() {
        FieldServiceBackofficeConfig__c config = FieldServiceBackofficeConfig__c.getValues(UserInfo.getUserId());
        Id storedId = toId(config == null ? null : config.TechDistrictAlignmentErrorFileId__c);
        if (storedId == null || TechDistrictAlignmentSelector.selectDocumentsById(storedId).isEmpty()) {
            return null;
        }
        return storedId;
    }

    /**
     * @description First day of the next fiscal year (April 1): this year's April 1 when today is before it,
     *              otherwise next year's.
     * @return Next fiscal year start date.
     */
    public static Date nextFiscalYearStart() {
        Date thisYearStart = Date.newInstance(runDate.year(), FISCAL_YEAR_START_MONTH, FISCAL_YEAR_START_DAY);
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
     * @param contentDocumentId Salesforce Files document Id from lightning-file-upload.
     * @return Counts, row-level skip messages and the error file Id.
     */
    public static ProcessResult processUpload(Id contentDocumentId) {
        Logger.setScenario('Tech District Alignment');
        ProcessResult result = new ProcessResult();
        if (contentDocumentId == null) {
            throw auraError('Upload a file before clicking Start Upload.');
        }

        List<ContentVersion> versions = TechDistrictAlignmentSelector.selectLatestVersion(contentDocumentId);
        if (versions.isEmpty() || versions[0].VersionData == null) {
            throw auraError('The uploaded file could not be read.');
        }

        List<List<String>> table = BackofficeUploadFileParser.parse(versions[0]);
        List<AlignmentRow> rows = toRows(table);
        result.processedCount = rows.size();
        result.nextFiscalYearStart = nextFiscalYearStart();
        if (!rows.isEmpty()) {
            applyRows(rows, result);
        }

        for (AlignmentRow row : rows) {
            if (row.errorMessage != null) {
                result.skippedCount++;
                result.errors.add('Row ' + row.rowNumber + ': ' + row.errorMessage);
            }
        }
        result.summary = summary(result);

        ContentVersion errorFile = writeErrorFile(table[0], rows);
        result.errorFileDocumentId = errorFile.ContentDocumentId;
        result.emailSent = sendResultEmail(result, errorFile.Id);

        Logger.info('Tech District Alignment ' + result.summary);
        Logger.saveLog();
        return result;
    }

    private static void applyRows(List<AlignmentRow> rows, ProcessResult result) {
        AlignmentPlan plan = new AlignmentPlan(rows);
        for (AlignmentRow row : rows) {
            row.errorMessage = plan.planRow(row);
        }
        result.unchangedCount = plan.unchangedCount;

        TerritoryStore store = new TerritoryStore();
        if (!plan.newTerritories.isEmpty()) {
            Database.SaveResult[] saveResults = store.insertRecords(plan.newTerritories);
            for (Integer i = 0; i < saveResults.size(); i++) {
                if (saveResults[i].isSuccess()) {
                    result.territoryCreatedCount++;
                } else {
                    ServiceTerritory failed = plan.newTerritories[i];
                    failRows(
                        plan.rowsByNewTerritory.get(key(failed.RegionNumber__c)),
                        'Unable to create territory ' + failed.RegionNumber__c + ': ' + firstError(saveResults[i])
                    );
                }
            }
        }

        List<ServiceTerritory> managerUpdates = plan.managerUpdateById.values();
        if (!managerUpdates.isEmpty()) {
            Database.SaveResult[] saveResults = store.updateRecords(managerUpdates);
            for (Integer i = 0; i < saveResults.size(); i++) {
                if (saveResults[i].isSuccess()) {
                    result.managerUpdatedCount++;
                } else {
                    failRows(
                        plan.rowsByManagerUpdate.get(managerUpdates[i].Id),
                        'Unable to update the Territory Manager: ' + firstError(saveResults[i])
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
            Database.SaveResult[] saveResults = store.updateRecords(endedMembers);
            for (Integer i = 0; i < saveResults.size(); i++) {
                if (!saveResults[i].isSuccess()) {
                    endedMemberRows[i].errorMessage =
                        'The current service territory membership could not be ended: ' + firstError(saveResults[i]);
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
            Database.SaveResult[] saveResults = store.insertRecords(newMembers);
            List<ServiceTerritoryMember> restoredMembers = new List<ServiceTerritoryMember>();
            for (Integer i = 0; i < saveResults.size(); i++) {
                if (!saveResults[i].isSuccess()) {
                    AlignmentRow row = newMemberRows[i];
                    row.errorMessage = 'Unable to create the service territory member: ' + firstError(saveResults[i]);
                    if (row.endMember) {
                        restoredMembers.add(
                            new ServiceTerritoryMember(Id = row.currentMember.Id, EffectiveEndDate = row.currentMember.EffectiveEndDate)
                        );
                    }
                }
            }
            if (!restoredMembers.isEmpty()) {
                // Undo the end date so the technician keeps the current territory when the move failed.
                store.updateRecords(restoredMembers);
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
        Datetime startOfToday = Datetime.newInstance(Date.today(), Time.newInstance(0, 0, 0, 0));        Map<String, User> userByHris = new Map<String, User>();
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

            TerritoryStore store = new TerritoryStore();
            for (User activeUser : store.selectUsers(asmHrisValues)) {
                userByHris.put(key(activeUser.EmployeeNumber__c), activeUser);
            }

            Set<Id> resourceIds = new Set<Id>();
            for (ServiceResource resource : store.selectResources(techHrisValues)) {
                resourceIds.add(resource.Id);
                resourceByExternalId.put(key(resource.ExternalID__c), resource);
            }

            Set<Id> territoryIds = new Set<Id>();
            for (ServiceTerritory territory : store.selectTerritories(territoryNumbers)) {
                territoryByNumber.put(key(territory.RegionNumber__c), territory);
                territoryIds.add(territory.Id);
            }

            for (ServiceTerritoryMember member : store.selectOpenMembers(resourceIds, territoryIds, startOfToday)) {
                String memberKey = memberKey(member.ServiceResourceId, member.ServiceTerritoryId);
                if (!membersByKey.containsKey(memberKey)) {
                    membersByKey.put(memberKey, new List<ServiceTerritoryMember>());
                }
                membersByKey.get(memberKey).add(member);
            }
        }

        String planRow(AlignmentRow row) {
            if (String.isBlank(row.techHris)) {
                return INVALID_TECH_HRIS + ': TECH HRIS# is required.';
            }
            ServiceResource resource = resourceFor(row.techHris);
            if (resource == null) {
                return INVALID_TECH_HRIS + ': No active Service Resource found for HRIS ID ' + row.techHris + '.';
            }
            if (claimedResourceIds.contains(resource.Id)) {
                return INVALID_TECH_HRIS + ': Technician ' + row.techHris + ' appears more than once in the file.';
            }

            if (String.isBlank(row.currentTerritory)) {
                return INVALID_CURRENT_TERRITORY + ': Current Territory is required.';
            }
            ServiceTerritory current = territoryByNumber.get(key(row.currentTerritory));
            if (current == null) {
                return INVALID_CURRENT_TERRITORY + ': No service territory found with Territory ID ' + row.currentTerritory + '.';
            }
            String currentTypeError = typeError(current, INVALID_CURRENT_TERRITORY);
            if (currentTypeError != null) {
                return currentTypeError;
            }
            ServiceTerritoryMember currentMember = activeMember(resource.Id, current.Id);
            if (currentMember == null) {
                return NOT_ASSIGNED + ' ' + current.RegionNumber__c + '.';
            }

            if (String.isBlank(row.currentAsmHris)) {
                return INVALID_CURRENT_ASM + ': Current ASM HRIS# is required.';
            }
            if (!userByHris.containsKey(key(row.currentAsmHris))) {
                return INVALID_CURRENT_ASM + ': No active user found for HRIS ID ' + row.currentAsmHris + '.';
            }

            if (String.isBlank(row.nextTerritory)) {
                return INVALID_NEXT_TERRITORY + ': Next Year Territory is required.';
            }
            User nextAsm;
            if (String.isNotBlank(row.nextAsmHris)) {
                nextAsm = userByHris.get(key(row.nextAsmHris));
                if (nextAsm == null) {
                    return INVALID_NEXT_ASM + ': No active user found for HRIS ID ' + row.nextAsmHris + '.';
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
                row.createMember = row.targetTerritory.Id == null || openMember(resource.Id, row.targetTerritory.Id) == null;
                row.endMember = currentMember.EffectiveEndDate == null || currentMember.EffectiveEndDate > now;
            }
            if (!row.createMember && !row.endMember && !row.updatesManager) {
                unchangedCount++;
            }
            return null;
        }

        String planNewTerritory(AlignmentRow row, ServiceTerritory current, User nextAsm) {
            if (nextAsm == null) {
                return INVALID_NEXT_ASM + ': Next Year ASM HRIS# is required to create territory ' + row.nextTerritory + '.';
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
                return INVALID_NEXT_ASM + ': Territory ' + row.nextTerritory +
                    ' has a different Next Year ASM on an earlier row of the file.';
            }
            rowsByNewTerritory.get(territoryKey).add(row);
            row.targetTerritory = pending;
            return null;
        }

        String planExistingTerritory(AlignmentRow row, ServiceTerritory target, User nextAsm) {
            String nextTypeError = typeError(target, INVALID_NEXT_TERRITORY);
            if (nextTypeError != null) {
                return nextTypeError;
            }
            if (!target.IsActive) {
                return INVALID_NEXT_TERRITORY + ': Territory ' + target.RegionNumber__c + ' is inactive.';
            }

            Boolean asmChanged = nextAsm != null && key(row.nextAsmHris) != key(row.currentAsmHris);
            if (asmChanged) {
                Id requested = requestedManagerByTerritoryId.get(target.Id);
                if (requested != null && requested != nextAsm.Id) {
                    return INVALID_NEXT_ASM + ': Territory ' + target.RegionNumber__c +
                        ' has a different Next Year ASM on an earlier row of the file.';
                }
                requestedManagerByTerritoryId.put(target.Id, nextAsm.Id);
                if (target.TerritoryManager__c != nextAsm.Id) {
                    if (!managerUpdateById.containsKey(target.Id)) {
                        managerUpdateById.put(target.Id, new ServiceTerritory(Id = target.Id, TerritoryManager__c = nextAsm.Id));
                        rowsByManagerUpdate.put(target.Id, new List<AlignmentRow>());
                    }
                    rowsByManagerUpdate.get(target.Id).add(row);
                    row.updatesManager = true;
                }
            }
            row.targetTerritory = target;
            return null;
        }

        String typeError(ServiceTerritory territory, String prefix) {
            if (SUPPORTED_TERRITORY_TYPES.contains(territory.TerritoryType__c)) {
                return null;
            }
            String typeLabel = String.isBlank(territory.TerritoryType__c) ? '(blank)' : territory.TerritoryType__c;
            return prefix + ': Territory ' + territory.RegionNumber__c + ' has type ' + typeLabel +
                '. Only IPTLS, Low Temp, Procedural and Endoscopy territories are supported.';
        }

        ServiceResource resourceFor(String hris) {
            return resourceByExternalId.get(key(hris));
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
        Map<String, Integer> columnIndexByName = BackofficeUploadFileParser.columnIndexByName(table[0]);
        if (
            !BackofficeUploadFileParser.hasColumn(columnIndexByName, TECH_HRIS_COLUMNS) ||
            !BackofficeUploadFileParser.hasColumn(columnIndexByName, CURRENT_TERRITORY_COLUMNS) ||
            !BackofficeUploadFileParser.hasColumn(columnIndexByName, CURRENT_ASM_HRIS_COLUMNS) ||
            !BackofficeUploadFileParser.hasColumn(columnIndexByName, NEXT_TERRITORY_COLUMNS) ||
            !BackofficeUploadFileParser.hasColumn(columnIndexByName, NEXT_ASM_HRIS_COLUMNS)
        ) {
            throw auraError(
                'The file must include TECH HRIS#, Current Territory, Current ASM HRIS#, Next Year Territory and Next Year ASM HRIS# columns.'
            );
        }
        if (table.size() - 1 > MAX_ROWS) {
            throw auraError('The file exceeds the maximum of ' + MAX_ROWS + ' data rows.');
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
            if (
                String.isBlank(row.techHris) &&
                String.isBlank(row.currentTerritory) &&
                String.isBlank(row.currentAsmHris) &&
                String.isBlank(row.nextTerritory) &&
                String.isBlank(row.nextAsmHris)
            ) {
                continue;
            }
            rows.add(row);
        }
        return rows;
    }

    /**
     * @description Column value with a dash-only placeholder ("-") treated as blank.
     */
    private static String columnValue(List<String> cells, Map<String, Integer> columnIndexByName, List<String> keys) {
        String value = BackofficeUploadFileParser.firstPresent(cells, columnIndexByName, keys);
        if (value == null || String.isBlank(value.replaceAll('\\p{Pd}', ''))) {
            return null;
        }
        return value;
    }

    /**
     * @description Excel can store an HRIS number as "50708.0"; drop a zero-only decimal part.
     */
    private static String normalizeHris(String value) {
        if (value == null) {
            return null;
        }
        return value.replaceFirst('^(\\d+)\\.0+$', '$1');
    }

    /**
     * @description Adds a new version to the running user's error file, creating the file on first use. The file
     *              repeats the uploaded columns for each skipped row, with the row number first and the error last.
     */
    private static ContentVersion writeErrorFile(List<String> header, List<AlignmentRow> rows) {
        List<String> lines = new List<String>{ csvLine('Row', header, 'Error', header.size()) };
        for (AlignmentRow row : rows) {
            if (row.errorMessage != null) {
                lines.add(csvLine(String.valueOf(row.rowNumber), row.cells, row.errorMessage, header.size()));
            }
        }

        ContentVersion version = new ContentVersion();
        version.Title = ERROR_FILE_TITLE;
        version.PathOnClient = ERROR_FILE_NAME;
        version.VersionData = Blob.valueOf(String.join(lines, '\n') + '\n');
        version.ReasonForChange = 'Tech District Alignment upload ' + Datetime.now().format();
        Id existingDocumentId = errorFileDocumentId();
        if (existingDocumentId != null) {
            version.ContentDocumentId = existingDocumentId;
        }
        try {
            insert version;
        } catch (DmlException e) {
            if (existingDocumentId == null) {
                throw e;
            }
            Logger.warn('Tech District Alignment error file could not be versioned; creating a new file. ' + e.getMessage());
            version = version.clone(false, true);
            version.ContentDocumentId = null;
            insert version;
        }

        // ContentDocumentId is create-only, so read it back instead of setting it on the inserted record.
        ContentVersion saved = [
            SELECT Id, ContentDocumentId
            FROM ContentVersion
            WHERE Id = :version.Id
        ];
        if (saved.ContentDocumentId != existingDocumentId) {
            new ConfigStore().saveErrorFileId(UserInfo.getUserId(), saved.ContentDocumentId);
        }
        return saved;
    }

    private static String csvLine(String first, List<String> cells, String last, Integer columnCount) {
        List<String> values = new List<String>{ BackofficeUploadFileParser.csvEscape(first) };
        for (Integer i = 0; i < columnCount; i++) {
            values.add(BackofficeUploadFileParser.csvEscape(i < cells.size() ? cells[i] : null));
        }
        values.add(BackofficeUploadFileParser.csvEscape(last));
        return String.join(values, ',');
    }

    private static Boolean sendResultEmail(ProcessResult result, Id errorFileVersionId) {
        Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
        mail.setTargetObjectId(UserInfo.getUserId());
        mail.setSaveAsActivity(false);
        mail.setSubject('Tech District Alignment upload results');
        mail.setPlainTextBody(
            'Your Tech District Alignment upload has finished.\n\n' +
            result.summary +
            '\n\nNext year memberships start on ' + result.nextFiscalYearStart.format() + '.' +
            '\n\nThe attached error file lists every row that was skipped and why. ' +
            'You can also download it with Download Error File on the Tech District Alignment tab.'
        );
        mail.setEntityAttachments(new List<String>{ errorFileVersionId });
        try {
            Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{ mail });
            return true;
        } catch (Exception e) {
            Logger.warn('Tech District Alignment result email could not be sent. ' + e.getMessage());
            return false;
        }
    }

    private static String summary(ProcessResult result) {
        return 'Processed ' + result.processedCount + ' row(s). Moved ' + result.movedCount +
            ' technician(s), created ' + result.territoryCreatedCount +
            ' territory(ies), updated ' + result.managerUpdatedCount +
            ' territory manager(s), unchanged ' + result.unchangedCount +
            ', skipped ' + result.skippedCount + '.';
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
        return [
            SELECT ContentDocumentId
            FROM ContentVersion
            WHERE Id = :contentVersionId
        ].ContentDocumentId;
    }

    private static Id toId(String value) {
        if (String.isBlank(value)) {
            return null;
        }
        try {
            return Id.valueOf(value.trim());
        } catch (Exception e) {
            return null;
        }
    }

    private static AuraHandledException auraError(String message) {
        AuraHandledException ex = new AuraHandledException(message);
        ex.setMessage(message);
        return ex;
    }

    /**
     * @description ServiceTerritory, ServiceTerritoryMember and ServiceResource are Private; back-office users
     *              realign every district, so lookups and DML run without sharing. Access is controlled by the
     *              FieldServiceBackofficeTool permission set.
     */
    private without sharing class TerritoryStore {
        List<User> selectUsers(Set<String> hrisValues) {
            return TechDistrictAlignmentSelector.selectActiveUsersByEmployeeNumbers(hrisValues);
        }

        List<ServiceResource> selectResources(Set<String> externalIds) {
            return TechDistrictAlignmentSelector.selectActiveResourcesByExternalIds(externalIds);
        }

        List<ServiceTerritory> selectTerritories(Set<String> regionNumbers) {
            return TechDistrictAlignmentSelector.selectTerritoriesByRegionNumbers(regionNumbers);
        }

        List<ServiceTerritoryMember> selectOpenMembers(Set<Id> resourceIds, Set<Id> territoryIds, Datetime endedBefore) {
            return TechDistrictAlignmentSelector.selectOpenMembers(resourceIds, territoryIds, endedBefore);
        }

        Database.SaveResult[] insertRecords(List<SObject> records) {
            return Database.insert(records, false);
        }

        Database.SaveResult[] updateRecords(List<SObject> records) {
            return Database.update(records, false);
        }
    }

    private without sharing class ConfigStore {
        /**
         * @description Stores the template ContentDocument Id on the org-level custom setting.
         */
        void saveTemplateDocumentId(Id documentId) {
            FieldServiceBackofficeConfig__c config = FieldServiceBackofficeConfig__c.getOrgDefaults();
            if (config == null) {
                config = new FieldServiceBackofficeConfig__c();
            }
            if (config.Id == null) {
                config.SetupOwnerId = UserInfo.getOrganizationId();
            }
            config.TechDistrictAlignmentTemplateId__c = String.valueOf(documentId);
            upsert config;
        }

        /**
         * @description Stores the user's error file ContentDocument Id on their user-level custom setting.
         */
        void saveErrorFileId(Id userId, Id documentId) {
            FieldServiceBackofficeConfig__c config = FieldServiceBackofficeConfig__c.getValues(userId);
            if (config == null) {
                config = new FieldServiceBackofficeConfig__c(SetupOwnerId = userId);
            }
            config.TechDistrictAlignmentErrorFileId__c = String.valueOf(documentId);
            upsert config;
        }
    }
}