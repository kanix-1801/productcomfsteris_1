/**
 * @description GW-2706 - Creates or updates district Service Territories and their parent zone from a
 *              District Zone Alignment file, writes the user's error file and emails it to them.
 *              Row logic follows "Territory Assignment Logic - District to Zone":
 *              1. Current District # blank: Future District # and Future Zone # are required; create a district
 *                 territory under the zone with Future ASM as Territory Manager.
 *              2. Current District # set: it must match a territory; Future District # and Future Zone # are
 *                 required; update Territory Manager, parent zone, District # and name where they differ.
 *              Any other row is skipped and written to the error file. A cell holding only a dash ("-") is blank.
 *              Current District Name, Current Zone #, Current Zone Name and Zone Name are reference columns only.
 */
public with sharing class DistrictZoneAlignmentService {
    public static final String TEMPLATE_TITLE = 'District Zone Alignment Template';
    public static final String TEMPLATE_RESOURCE_NAME = 'DistrictZoneAlignmentTemplate';
    public static final String ERROR_FILE_TITLE = 'District Zone Alignment Errors';
    public static final String ERROR_FILE_NAME = 'District_Zone_Alignment_Errors.csv';
    public static final String DOWNLOAD_URL_PREFIX = '/sfc/servlet.shepherd/document/download/';
    @TestVisible
    private static final Integer MAX_ROWS = 2000;
    private static final Integer NAME_MAX_LENGTH = 80;
    private static final String INVALID_CURRENT_DISTRICT = 'Invalid current district#';
    private static final String INVALID_FUTURE_DISTRICT = 'Invalid future district#';
    private static final String INVALID_FUTURE_ZONE = 'Invalid future zone#';
    private static final String INVALID_FUTURE_ASM = 'Invalid future ASM';
    private static final List<String> CURRENT_DISTRICT_COLUMNS = new List<String>{ 'currentdistrict', 'currentdistrictnumber', 'currentdistrictno' };
    private static final List<String> FUTURE_DISTRICT_COLUMNS = new List<String>{ 'futuredistrict', 'futuredistrictnumber', 'futuredistrictno' };
    private static final List<String> FUTURE_ZONE_COLUMNS = new List<String>{ 'futurezone', 'futurezonenumber', 'futurezoneno' };
    private static final List<String> FUTURE_ASM_COLUMNS = new List<String>{ 'futureasmnames', 'futureasmname', 'futureasm' };
    private static final List<String> FUTURE_DISTRICT_NAME_COLUMNS = new List<String>{ 'futuredistrictname' };

    /**
     * @description Counts, skip messages and error file returned to the LWC after Start Upload.
     */
    public class ProcessResult {
        @AuraEnabled public Integer processedCount;
        @AuraEnabled public Integer createdCount;
        @AuraEnabled public Integer updatedCount;
        @AuraEnabled public Integer unchangedCount;
        @AuraEnabled public Integer skippedCount;
        @AuraEnabled public List<String> errors;
        @AuraEnabled public Id errorFileDocumentId;
        @AuraEnabled public Boolean emailSent;

        /**
         * @description Builds an empty result.
         */
        public ProcessResult() {
            this.processedCount = 0;
            this.createdCount = 0;
            this.updatedCount = 0;
            this.unchangedCount = 0;
            this.skippedCount = 0;
            this.errors = new List<String>();
            this.emailSent = false;
        }
    }

    private class AlignmentRow {
        Integer rowNumber;
        String currentDistrict;
        String futureDistrict;
        String futureZone;
        String futureAsm;
        String districtName;
        List<String> cells;
        String errorMessage;
    }

    /**
     * @description Copies the packaged template into Salesforce Files if needed and returns its ContentDocument Id.
     * @return ContentDocument Id of the template file.
     */
    public static Id ensureTemplateDocumentId() {
        FieldServiceBackofficeConfig__c config = FieldServiceBackofficeConfig__c.getOrgDefaults();
        Id storedId = toId(config == null ? null : config.DistrictZoneAlignmentTemplateId__c);
        if (storedId != null && !DistrictZoneAlignmentSelector.selectDocumentsById(storedId).isEmpty()) {
            return storedId;
        }

        List<ContentDocument> titledDocs = DistrictZoneAlignmentSelector.selectDocumentsByTitle(TEMPLATE_TITLE);
        if (!titledDocs.isEmpty()) {
            new ConfigStore().saveTemplateDocumentId(titledDocs[0].Id);
            return titledDocs[0].Id;
        }

        List<StaticResource> resources = DistrictZoneAlignmentSelector.selectTemplateResource(TEMPLATE_RESOURCE_NAME);
        if (resources.isEmpty() || resources[0].Body == null) {
            throw auraError('District Zone Alignment template is not available.');
        }

        ContentVersion version = new ContentVersion();
        version.Title = TEMPLATE_TITLE;
        version.PathOnClient = 'District_Zone_Alignment_Template.csv';
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
        Id storedId = toId(config == null ? null : config.DistrictZoneAlignmentErrorFileId__c);
        if (storedId == null || DistrictZoneAlignmentSelector.selectDocumentsById(storedId).isEmpty()) {
            return null;
        }
        return storedId;
    }

    /**
     * @description Processes the uploaded file, writes the error file and emails it to the running user.
     * @param contentDocumentId Salesforce Files document Id from lightning-file-upload.
     * @return Counts, row-level skip messages and the error file Id.
     */
    public static ProcessResult processUpload(Id contentDocumentId) {
        Logger.setScenario('District Zone Alignment');
        ProcessResult result = new ProcessResult();
        if (contentDocumentId == null) {
            throw auraError('Upload a file before clicking Start Upload.');
        }

        List<ContentVersion> versions = DistrictZoneAlignmentSelector.selectLatestVersion(contentDocumentId);
        if (versions.isEmpty() || versions[0].VersionData == null) {
            throw auraError('The uploaded file could not be read.');
        }

        List<List<String>> table = BackofficeUploadFileParser.parse(versions[0]);
        List<AlignmentRow> rows = toRows(table);
        result.processedCount = rows.size();
        if (!rows.isEmpty()) {
            applyRows(rows, result);
        }

        for (AlignmentRow row : rows) {
            if (row.errorMessage != null) {
                result.skippedCount++;
                result.errors.add('Row ' + row.rowNumber + ': ' + row.errorMessage);
            }
        }

        ContentVersion errorFile = writeErrorFile(table[0], rows);
        result.errorFileDocumentId = errorFile.ContentDocumentId;
        result.emailSent = sendResultEmail(result, errorFile.Id);

        Logger.info('District Zone Alignment ' + summary(result));
        Logger.saveLog();
        return result;
    }

    private static void applyRows(List<AlignmentRow> rows, ProcessResult result) {
        AlignmentPlan plan = new AlignmentPlan(rows);
        for (AlignmentRow row : rows) {
            row.errorMessage = String.isBlank(row.currentDistrict) ? plan.planCreate(row) : plan.planUpdate(row);
        }
        result.unchangedCount = plan.unchangedCount;

        TerritoryStore store = new TerritoryStore();
        if (!plan.toInsert.isEmpty()) {
            Database.SaveResult[] saveResults = store.insertTerritories(plan.toInsert);
            for (Integer i = 0; i < saveResults.size(); i++) {
                if (saveResults[i].isSuccess()) {
                    result.createdCount++;
                } else {
                    plan.insertRows[i].errorMessage = 'Unable to create the district territory: ' + firstError(saveResults[i]);
                }
            }
        }
        if (!plan.toUpdate.isEmpty()) {
            Database.SaveResult[] saveResults = store.updateTerritories(plan.toUpdate);
            for (Integer i = 0; i < saveResults.size(); i++) {
                if (saveResults[i].isSuccess()) {
                    result.updatedCount++;
                } else {
                    plan.updateRows[i].errorMessage = 'Unable to update the district territory: ' + firstError(saveResults[i]);
                }
            }
        }
    }

    /**
     * @description Looks up every territory and user referenced by the file once, then turns each row into
     *              an insert, an update, no change, or an error message.
     */
    private class AlignmentPlan {
        Map<String, ServiceTerritory> districtByNumber = new Map<String, ServiceTerritory>();
        Map<String, ServiceTerritory> zoneByRegionNumber = new Map<String, ServiceTerritory>();
        Map<String, List<ServiceTerritory>> zonesByName = new Map<String, List<ServiceTerritory>>();
        Map<Id, User> userById = new Map<Id, User>();
        Map<String, User> userByUsername = new Map<String, User>();
        Map<String, List<User>> usersByEmail = new Map<String, List<User>>();
        Map<String, List<User>> usersByName = new Map<String, List<User>>();
        Set<String> claimedNumbers = new Set<String>();
        Set<Id> touchedDistrictIds = new Set<Id>();
        List<ServiceTerritory> toInsert = new List<ServiceTerritory>();
        List<AlignmentRow> insertRows = new List<AlignmentRow>();
        List<ServiceTerritory> toUpdate = new List<ServiceTerritory>();
        List<AlignmentRow> updateRows = new List<AlignmentRow>();
        Integer unchangedCount = 0;

        AlignmentPlan(List<AlignmentRow> rows) {
            Set<String> districtNumbers = new Set<String>();
            Set<String> zoneKeys = new Set<String>();
            Set<Id> userIds = new Set<Id>();
            Set<String> userKeys = new Set<String>();
            for (AlignmentRow row : rows) {
                addIfPresent(districtNumbers, row.currentDistrict);
                addIfPresent(districtNumbers, row.futureDistrict);
                addIfPresent(zoneKeys, row.futureZone);
                if (String.isNotBlank(row.futureAsm)) {
                    Id userId = toUserId(row.futureAsm);
                    if (userId != null) {
                        userIds.add(userId);
                    } else {
                        userKeys.add(row.futureAsm);
                    }
                }
            }

            TerritoryStore store = new TerritoryStore();
            for (ServiceTerritory territory : store.selectDistricts(districtNumbers)) {
                districtByNumber.put(territory.RegionNumber__c.toLowerCase(), territory);
            }
            for (ServiceTerritory zone : store.selectZones(zoneKeys)) {
                if (String.isNotBlank(zone.RegionNumber__c)) {
                    zoneByRegionNumber.put(zone.RegionNumber__c.toLowerCase(), zone);
                }
                String nameKey = zone.Name.toLowerCase();
                if (!zonesByName.containsKey(nameKey)) {
                    zonesByName.put(nameKey, new List<ServiceTerritory>());
                }
                zonesByName.get(nameKey).add(zone);
            }
            for (User activeUser : store.selectUsers(userIds, userKeys)) {
                userById.put(activeUser.Id, activeUser);
                userByUsername.put(activeUser.Username.toLowerCase(), activeUser);
                addToGroup(usersByEmail, activeUser.Email, activeUser);
                addToGroup(usersByName, activeUser.Name, activeUser);
            }
        }

        void addToGroup(Map<String, List<User>> usersByKey, String key, User activeUser) {
            if (String.isBlank(key)) {
                return;
            }
            String groupKey = key.toLowerCase();
            if (!usersByKey.containsKey(groupKey)) {
                usersByKey.put(groupKey, new List<User>());
            }
            usersByKey.get(groupKey).add(activeUser);
        }

        String planCreate(AlignmentRow row) {
            String futureError = futureColumnsError(row);
            if (futureError != null) {
                return futureError;
            }
            if (isNumberTaken(row.futureDistrict, null)) {
                return INVALID_FUTURE_DISTRICT + ': A territory with District # ' + row.futureDistrict +
                    ' already exists. Enter it as Current District # to update it.';
            }
            ServiceTerritory zone = zoneFor(row.futureZone);
            if (zone.OperatingHoursId == null) {
                return INVALID_FUTURE_ZONE + ': Zone ' + row.futureZone + ' has no Operating Hours to copy to the new district.';
            }
            String managerError = asmError(row.futureAsm);
            if (managerError != null) {
                return managerError;
            }

            User asm = asmFor(row.futureAsm);
            ServiceTerritory district = new ServiceTerritory();
            district.Name = (String.isNotBlank(row.districtName) ? row.districtName : row.futureDistrict).left(NAME_MAX_LENGTH);
            district.RegionNumber__c = row.futureDistrict;
            district.ParentTerritoryId = zone.Id;
            district.OperatingHoursId = zone.OperatingHoursId;
            district.IsActive = true;
            district.TerritoryManager__c = asm == null ? null : asm.Id;
            claimedNumbers.add(row.futureDistrict.toLowerCase());
            toInsert.add(district);
            insertRows.add(row);
            return null;
        }

        String planUpdate(AlignmentRow row) {
            ServiceTerritory district = districtByNumber.get(row.currentDistrict.toLowerCase());
            if (district == null) {
                return INVALID_CURRENT_DISTRICT + ': No territory found with District # ' + row.currentDistrict + '.';
            }
            if (touchedDistrictIds.contains(district.Id)) {
                return INVALID_CURRENT_DISTRICT + ': District # ' + row.currentDistrict + ' appears more than once in the file.';
            }
            String futureError = futureColumnsError(row);
            if (futureError != null) {
                return futureError;
            }
            ServiceTerritory zone = zoneFor(row.futureZone);
            if (zone.Id == district.Id) {
                return INVALID_FUTURE_ZONE + ': A district cannot be its own zone.';
            }
            Boolean renumbered = !row.futureDistrict.equals(district.RegionNumber__c);
            if (renumbered && isNumberTaken(row.futureDistrict, district.Id)) {
                return INVALID_FUTURE_DISTRICT + ': District # ' + row.futureDistrict + ' is already used by another territory.';
            }
            String managerError = asmError(row.futureAsm);
            if (managerError != null) {
                return managerError;
            }

            touchedDistrictIds.add(district.Id);
            User asm = asmFor(row.futureAsm);
            ServiceTerritory changes = new ServiceTerritory(Id = district.Id);
            Boolean changed = false;
            if (asm != null && asm.Id != district.TerritoryManager__c) {
                changes.TerritoryManager__c = asm.Id;
                changed = true;
            }
            if (zone.Id != district.ParentTerritoryId) {
                changes.ParentTerritoryId = zone.Id;
                changed = true;
            }
            if (renumbered) {
                changes.RegionNumber__c = row.futureDistrict;
                claimedNumbers.add(row.futureDistrict.toLowerCase());
                changed = true;
            }
            if (String.isNotBlank(row.districtName) && !row.districtName.left(NAME_MAX_LENGTH).equals(district.Name)) {
                changes.Name = row.districtName.left(NAME_MAX_LENGTH);
                changed = true;
            }
            if (!changed) {
                unchangedCount++;
                return null;
            }
            toUpdate.add(changes);
            updateRows.add(row);
            return null;
        }

        String futureColumnsError(AlignmentRow row) {
            if (String.isBlank(row.futureDistrict)) {
                return INVALID_FUTURE_DISTRICT + ': Future District # is required.';
            }
            if (String.isBlank(row.futureZone)) {
                return INVALID_FUTURE_ZONE + ': Future Zone # is required.';
            }
            String zoneKey = row.futureZone.toLowerCase();
            if (zoneByRegionNumber.containsKey(zoneKey)) {
                return null;
            }
            List<ServiceTerritory> namedZones = zonesByName.get(zoneKey);
            if (namedZones == null || namedZones.isEmpty()) {
                return INVALID_FUTURE_ZONE + ': No Zone territory found for ' + row.futureZone + '.';
            }
            if (namedZones.size() > 1) {
                return INVALID_FUTURE_ZONE + ': More than one Zone territory is named ' + row.futureZone + '.';
            }
            return null;
        }

        ServiceTerritory zoneFor(String zoneValue) {
            String zoneKey = zoneValue.toLowerCase();
            return zoneByRegionNumber.containsKey(zoneKey) ? zoneByRegionNumber.get(zoneKey) : zonesByName.get(zoneKey)[0];
        }

        Boolean isNumberTaken(String districtNumber, Id ownDistrictId) {
            String key = districtNumber.toLowerCase();
            if (claimedNumbers.contains(key)) {
                return true;
            }
            ServiceTerritory existing = districtByNumber.get(key);
            return existing != null && existing.Id != ownDistrictId;
        }

        String asmError(String asmValue) {
            if (String.isBlank(asmValue)) {
                return null;
            }
            List<User> matches = usersFor(asmValue);
            if (matches.isEmpty()) {
                return INVALID_FUTURE_ASM + ': No active user found for ' + asmValue + '.';
            }
            if (matches.size() > 1) {
                return INVALID_FUTURE_ASM + ': More than one active user matches ' + asmValue + '. Use the User Id or Username.';
            }
            return null;
        }

        User asmFor(String asmValue) {
            if (String.isBlank(asmValue)) {
                return null;
            }
            List<User> matches = usersFor(asmValue);
            return matches.size() == 1 ? matches[0] : null;
        }

        List<User> usersFor(String asmValue) {
            Id userId = toUserId(asmValue);
            if (userId != null) {
                return userById.containsKey(userId) ? new List<User>{ userById.get(userId) } : new List<User>();
            }
            String key = asmValue.toLowerCase();
            if (userByUsername.containsKey(key)) {
                return new List<User>{ userByUsername.get(key) };
            }
            if (usersByEmail.containsKey(key)) {
                return usersByEmail.get(key);
            }
            return usersByName.containsKey(key) ? usersByName.get(key) : new List<User>();
        }
    }

    private static List<AlignmentRow> toRows(List<List<String>> table) {
        Map<String, Integer> columnIndexByName = BackofficeUploadFileParser.columnIndexByName(table[0]);
        if (
            !BackofficeUploadFileParser.hasColumn(columnIndexByName, CURRENT_DISTRICT_COLUMNS) ||
            !BackofficeUploadFileParser.hasColumn(columnIndexByName, FUTURE_DISTRICT_COLUMNS) ||
            !BackofficeUploadFileParser.hasColumn(columnIndexByName, FUTURE_ZONE_COLUMNS) ||
            !BackofficeUploadFileParser.hasColumn(columnIndexByName, FUTURE_ASM_COLUMNS)
        ) {
            throw auraError('The file must include Current District #, Future District #, Future Zone # and Future ASM Names columns.');
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
            row.currentDistrict = columnValue(cells, columnIndexByName, CURRENT_DISTRICT_COLUMNS);
            row.futureDistrict = columnValue(cells, columnIndexByName, FUTURE_DISTRICT_COLUMNS);
            row.futureZone = columnValue(cells, columnIndexByName, FUTURE_ZONE_COLUMNS);
            row.futureAsm = columnValue(cells, columnIndexByName, FUTURE_ASM_COLUMNS);
            row.districtName = columnValue(cells, columnIndexByName, FUTURE_DISTRICT_NAME_COLUMNS);
            if (String.isBlank(row.currentDistrict) && String.isBlank(row.futureDistrict) && String.isBlank(row.futureZone) && String.isBlank(row.futureAsm)) {
                continue;
            }
            rows.add(row);
        }
        return rows;
    }

    /**
     * @description Column value with a dash-only placeholder ("-") treated as blank.
     * @param cells Row cells.
     * @param columnIndexByName Column index keyed by normalized header name.
     * @param keys Normalized header aliases.
     * @return Trimmed value, or null.
     */
    private static String columnValue(List<String> cells, Map<String, Integer> columnIndexByName, List<String> keys) {
        String value = BackofficeUploadFileParser.firstPresent(cells, columnIndexByName, keys);
        if (value == null || String.isBlank(value.replaceAll('\\p{Pd}', ''))) {
            return null;
        }
        return value;
    }

    /**
     * @description Adds a new version to the running user's error file, creating the file on first use. The file
     *              repeats the uploaded columns for each skipped row, with the row number first and the error last.
     * @param header Header row of the uploaded file.
     * @param rows Processed rows.
     * @return The inserted ContentVersion with its ContentDocumentId.
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
        version.ReasonForChange = 'District Zone Alignment upload ' + Datetime.now().format();
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
            Logger.warn('District Zone Alignment error file could not be versioned; creating a new file. ' + e.getMessage());
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
        mail.setSubject('District Zone Alignment upload results');
        mail.setPlainTextBody(
            'Your District Zone Alignment upload has finished.\n\n' +
            summary(result) +
            '\n\nThe attached error file lists every row that was skipped and why. ' +
            'You can also download it with Download Error File on the District Zone Alignment tab.'
        );
        mail.setEntityAttachments(new List<String>{ errorFileVersionId });
        try {
            Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{ mail });
            return true;
        } catch (Exception e) {
            Logger.warn('District Zone Alignment result email could not be sent. ' + e.getMessage());
            return false;
        }
    }

    private static String summary(ProcessResult result) {
        return 'Processed ' + result.processedCount + ' row(s). Created ' + result.createdCount +
            ', updated ' + result.updatedCount +
            ', unchanged ' + result.unchangedCount +
            ', skipped ' + result.skippedCount + '.';
    }

    private static void addIfPresent(Set<String> values, String value) {
        if (String.isNotBlank(value)) {
            values.add(value);
        }
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

    private static Id toUserId(String value) {
        Id candidate = toId(value);
        return candidate != null && candidate.getSobjectType() == User.SObjectType ? candidate : null;
    }

    private static AuraHandledException auraError(String message) {
        AuraHandledException ex = new AuraHandledException(message);
        ex.setMessage(message);
        return ex;
    }

    /**
     * @description ServiceTerritory is Private; back-office users maintain every district, so lookups and DML
     *              run without sharing. Access is controlled by the FieldServiceBackofficeTool permission set.
     */
    private without sharing class TerritoryStore {
        List<ServiceTerritory> selectDistricts(Set<String> regionNumbers) {
            return DistrictZoneAlignmentSelector.selectTerritoriesByRegionNumbers(regionNumbers);
        }

        List<ServiceTerritory> selectZones(Set<String> zoneKeys) {
            return DistrictZoneAlignmentSelector.selectZonesByRegionNumberOrName(zoneKeys);
        }

        List<User> selectUsers(Set<Id> userIds, Set<String> userKeys) {
            return DistrictZoneAlignmentSelector.selectActiveUsers(userIds, userKeys);
        }

        Database.SaveResult[] insertTerritories(List<ServiceTerritory> territories) {
            return Database.insert(territories, false);
        }

        Database.SaveResult[] updateTerritories(List<ServiceTerritory> territories) {
            return Database.update(territories, false);
        }
    }

    private without sharing class ConfigStore {
        /**
         * @description Stores the template ContentDocument Id on the org-level custom setting.
         * @param documentId Salesforce Files document Id.
         */
        void saveTemplateDocumentId(Id documentId) {
            FieldServiceBackofficeConfig__c config = FieldServiceBackofficeConfig__c.getOrgDefaults();
            if (config == null) {
                config = new FieldServiceBackofficeConfig__c();
            }
            if (config.Id == null) {
                config.SetupOwnerId = UserInfo.getOrganizationId();
            }
            config.DistrictZoneAlignmentTemplateId__c = String.valueOf(documentId);
            upsert config;
        }

        /**
         * @description Stores the user's error file ContentDocument Id on their user-level custom setting.
         * @param userId User who ran the upload.
         * @param documentId Salesforce Files document Id.
         */
        void saveErrorFileId(Id userId, Id documentId) {
            FieldServiceBackofficeConfig__c config = FieldServiceBackofficeConfig__c.getValues(userId);
            if (config == null) {
                config = new FieldServiceBackofficeConfig__c(SetupOwnerId = userId);
            }
            config.DistrictZoneAlignmentErrorFileId__c = String.valueOf(documentId);
            upsert config;
        }
    }
}