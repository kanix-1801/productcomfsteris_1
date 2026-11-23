/**
 * @description GW-2710 - Creates AddressResourcePreference records from a Tech Account Alignment file.
 */
public with sharing class TechAccountAlignmentService {
    public static final String TEMPLATE_TITLE = 'Tech Account Alignment Template';
    public static final String TEMPLATE_RESOURCE_NAME = 'TechAccountAlignmentTemplate';
    public static final String TEMPLATE_FILE_NAME = 'Tech_Account_Alignment_Template.xlsx';
    public static final String ERROR_FILE_TITLE = 'Tech Account Alignment Errors';
    private static final String ERROR_FILE_NAME = 'Tech_Account_Alignment_Errors.csv';
    public static final String PREFERENCE_PREFERRED = 'Preferred';
    @TestVisible
    private static final Integer MAX_ROWS = 2000;
    private static final Integer NAME_MAX_LENGTH = 80;
    private static final Set<String> ACTIVE_SHIP_TO_STATUSES = new Set<String>{ 'Active', 'Primary' };
    private static final Set<String> ACTIVE_BILL_TO_STATUSES = new Set<String>{ 'Active', 'Primary' };
    private static final Map<String, String> TERRITORY_BY_KEY = new Map<String, String>{
        'surgical' => 'Surgical',
        'iptls' => 'IPTLS',
        'cantel' => 'Cantel',
        'mobile spd' => 'Mobile SPD',
        'mobilespd' => 'Mobile SPD',
        'low temp' => 'Low Temp',
        'lowtemp' => 'Low Temp',
        'on location' => 'On Location',
        'onlocation' => 'On Location'
    };
    private static final Map<String, String> PREFERENCE_BY_KEY = new Map<String, String>{
        'preferred' => 'Preferred',
        'excluded' => 'Excluded',
        'required' => 'Required'
    };

    /**
     * @description Counts and skip messages returned to the LWC after Process Data.
     */
    public class ProcessResult {
        @AuraEnabled public Integer processedCount;
        @AuraEnabled public Integer createdCount;
        @AuraEnabled public Integer skippedCount;
        @AuraEnabled public List<String> errors;

        /**
         * @description Builds an empty result.
         */
        public ProcessResult() {
            this.processedCount = 0;
            this.createdCount = 0;
            this.skippedCount = 0;
            this.errors = new List<String>();
        }
    }

    private class AssignmentRow {
        Integer rowNumber;
        String addressId;
        String hrisId;
        String territoryType;
        String workTypeName;
        String preferenceLevel;
        List<String> cells;
        String errorMessage;
    }

    private class ParsedFile {
        List<String> header = new List<String>();
        List<AssignmentRow> rows = new List<AssignmentRow>();
    }

    /**
     * @description Copies the packaged template into Salesforce Files if needed and returns its ContentDocument Id.
     * @return ContentDocument Id of the template file.
     */
    public static Id ensureTemplateDocumentId() {
        Id storedId = readStoredTemplateId();
        if (storedId != null && templateIsCurrent(storedId)) {
            return storedId;
        }
        if (storedId != null) {
            Id refreshedId = publishTemplate(storedId);
            if (refreshedId != null) {
                return refreshedId;
            }
        }

        List<ContentDocument> titledDocs = ContentDocumentsSelector.selectLatestByTitle(TEMPLATE_TITLE);
        if (!titledDocs.isEmpty()) {
            Id titledId = titledDocs[0].Id;
            if (!templateIsCurrent(titledId)) {
                Id refreshedId = publishTemplate(titledId);
                if (refreshedId != null) {
                    titledId = refreshedId;
                }
            }
            persistTemplateDocumentId(titledId);
            return titledId;
        }

        ContentVersion version = newTemplateVersion(null);
        Id documentId = ContentVersionsSelector.selectDocumentIdByVersionId(version.Id)[0].ContentDocumentId;
        persistTemplateDocumentId(documentId);
        return documentId;
    }

    /**
     * @description Download id of the running user's latest error file.
     * @return ContentDocument Id.
     */
    public static Id requireErrorFileDocumentId() {
        Id documentId = storedErrorFileDocumentId();
        if (documentId == null) {
            throw auraError('No error file is available yet. Process a file first.');
        }
        return documentId;
    }

    /**
     * @description Parses the uploaded file and inserts eligible AddressResourcePreference records.
     * @param contentDocumentId Salesforce Files document Id.
     * @return Processed / created / skipped counts and row-level skip messages.
     */
    public static ProcessResult processUpload(Id contentDocumentId) {
        Logger.setScenario('Tech Account Alignment');
        ProcessResult result = new ProcessResult();
        if (contentDocumentId == null) {
            throw auraError('Upload a file before clicking Process Data.');
        }

        List<ContentVersion> versions = ContentVersionsSelector.selectLatestByContentDocumentId(contentDocumentId);
        if (versions.isEmpty() || versions[0].VersionData == null) {
            throw auraError('The uploaded file could not be read.');
        }

        ParsedFile parsed = parseFile(versions[0]);
        List<AssignmentRow> rows = parsed.rows;
        result.processedCount = rows.size();

        Set<String> oracleAddressIds = new Set<String>();
        Set<String> hrisIds = new Set<String>();
        Set<String> workTypeNames = new Set<String>();
        for (AssignmentRow row : rows) {
            if (String.isNotBlank(row.addressId)) {
                oracleAddressIds.add(row.addressId);
            }
            if (String.isNotBlank(row.hrisId)) {
                hrisIds.add(row.hrisId);
            }
            if (String.isNotBlank(row.workTypeName)) {
                workTypeNames.add(row.workTypeName);
            }
        }

        Map<String, User> userByHris = new Map<String, User>();
        Set<Id> userIds = new Set<Id>();
        for (User technician : UserSelector.selectActiveByEmployeeNumbers(hrisIds)) {
            if (String.isBlank(technician.EmployeeNumber__c) || userByHris.containsKey(technician.EmployeeNumber__c.trim())) {
                continue;
            }
            userByHris.put(technician.EmployeeNumber__c.trim(), technician);
            userIds.add(technician.Id);
        }

        Map<String, Account> accountByOracleId = new Map<String, Account>();
        for (Account addressAccount : AccountSelector.selectAddressAccountsByOracleAddressIds(oracleAddressIds)) {
            accountByOracleId.put(addressAccount.OracleAddressId__c, addressAccount);
        }

        Map<Id, ServiceResource> resourceByUserId = new Map<Id, ServiceResource>();
        for (ServiceResource resource : ServiceResourcesSelector.selectActiveByRelatedRecordIds(userIds)) {
            resourceByUserId.put(resource.RelatedRecordId, resource);
        }

        Map<String, WorkType> workTypeByName = new Map<String, WorkType>();
        for (WorkType workType : WorkTypesSelector.selectByNames(workTypeNames)) {
            workTypeByName.put(workType.Name.toLowerCase(), workType);
        }

        Set<Id> addressAccountIds = new Set<Id>();
        for (Account addressAccount : accountByOracleId.values()) {
            addressAccountIds.add(addressAccount.Id);
        }

        Set<String> existingKeys = new Set<String>();
        for (AddressResourcePreference__c existing : AddressResourcePreferencesSelector.selectByAddressAccountIds(addressAccountIds)) {
            existingKeys.add(preferenceKey(existing.AddressAccount__c, existing.ServiceResource__c, existing.TerritoryType__c, existing.WorkType__c));
        }

        List<AddressResourcePreference__c> toInsert = new List<AddressResourcePreference__c>();
        List<Integer> insertRowNumbers = new List<Integer>();
        Set<String> pendingKeys = new Set<String>();

        for (AssignmentRow row : rows) {
            String skipReason = skipReason(row, accountByOracleId, userByHris, resourceByUserId, workTypeByName);
            if (skipReason != null) {
                row.errorMessage = skipReason;
                result.skippedCount++;
                result.errors.add('Row ' + row.rowNumber + ': ' + skipReason);
                continue;
            }

            Account addressAccount = accountByOracleId.get(row.addressId);
            User technician = userByHris.get(row.hrisId);
            ServiceResource resource = resourceByUserId.get(technician.Id);
            WorkType workType = String.isBlank(row.workTypeName)
                ? null
                : workTypeByName.get(row.workTypeName.toLowerCase());
            String territoryType = normalizeTerritory(row.territoryType);
            String preferenceLevel = normalizePreference(row.preferenceLevel);
            String key = preferenceKey(
                addressAccount.Id,
                resource.Id,
                territoryType,
                workType == null ? null : workType.Id
            );
            if (existingKeys.contains(key) || pendingKeys.contains(key)) {
                row.errorMessage = 'Preference already exists for this technician and district type.';
                result.skippedCount++;
                result.errors.add('Row ' + row.rowNumber + ': ' + row.errorMessage);
                continue;
            }

            AddressResourcePreference__c preference = new AddressResourcePreference__c();
            preference.Name = preferenceName(territoryType, row.workTypeName, preferenceLevel, resource.Name);
            preference.AddressAccount__c = addressAccount.Id;
            preference.ServiceResource__c = resource.Id;
            preference.PreferenceLevel__c = preferenceLevel;
            preference.TerritoryType__c = territoryType;
            if (workType != null) {
                preference.WorkType__c = workType.Id;
            }
            toInsert.add(preference);
            insertRowNumbers.add(row.rowNumber);
            pendingKeys.add(key);
        }

        if (!toInsert.isEmpty()) {
            Database.SaveResult[] saveResults = Database.insert(toInsert, false);
            for (Integer i = 0; i < saveResults.size(); i++) {
                if (saveResults[i].isSuccess()) {
                    result.createdCount++;
                } else {
                    result.skippedCount++;
                    String message = saveResults[i].getErrors().isEmpty()
                        ? 'Unable to create AddressResourcePreference.'
                        : saveResults[i].getErrors()[0].getMessage();
                    rowError(rows, insertRowNumbers[i], message);
                    result.errors.add('Row ' + insertRowNumbers[i] + ': ' + message);
                }
            }
        }

        writeErrorFile(parsed.header, rows);
        Logger.info(
            'Tech Account Alignment processed ' +
            result.processedCount +
            ', created ' +
            result.createdCount +
            ', skipped ' +
            result.skippedCount
        );
        Logger.saveLog();
        return result;
    }

    private static String skipReason(
        AssignmentRow row,
        Map<String, Account> accountByOracleId,
        Map<String, User> userByHris,
        Map<Id, ServiceResource> resourceByUserId,
        Map<String, WorkType> workTypeByName
    ) {
        if (String.isBlank(row.addressId)) {
            return 'ADDID is required.';
        }
        if (String.isBlank(row.hrisId)) {
            return 'HRIS ID is required.';
        }
        User technician = userByHris.get(row.hrisId);
        if (technician == null) {
            return 'No active user found for HRIS ID ' + row.hrisId + '.';
        }
        Account addressAccount = accountByOracleId.get(row.addressId);
        if (addressAccount == null) {
            return 'No Address account found for ADDID ' + row.addressId + '.';
        }
        if (addressAccount.NotServiceable__c == true || containsNoEquipmentHere(addressAccount.Name)) {
            return 'Do not assign where No Equipment Here / Not Serviceable.';
        }
        Boolean activeShipTo = ACTIVE_SHIP_TO_STATUSES.contains(addressAccount.ShiptoAddressStatus__c);
        Boolean billToOnly =
            ACTIVE_BILL_TO_STATUSES.contains(addressAccount.BilltoAddressStatus__c) && !activeShipTo;
        if (billToOnly) {
            return 'Do not assign to Bill-To-only addresses.';
        }
        if (!activeShipTo) {
            return 'Must be an active ship-to.';
        }
        if (isDistributor(addressAccount)) {
            return 'Do not assign to distributor / bill-to-only accounts.';
        }
        if (!resourceByUserId.containsKey(technician.Id)) {
            return 'No active Service Resource found for HRIS ID ' + row.hrisId + '.';
        }
        if (String.isNotBlank(row.workTypeName) && !workTypeByName.containsKey(row.workTypeName.toLowerCase())) {
            return 'Work Type not found: ' + row.workTypeName + '.';
        }
        if (String.isNotBlank(row.territoryType) && String.isBlank(normalizeTerritory(row.territoryType))) {
            return 'Territory Type is not valid: ' + row.territoryType + '.';
        }
        if (String.isNotBlank(row.preferenceLevel) && String.isBlank(normalizePreference(row.preferenceLevel))) {
            return 'Preference Level is not valid: ' + row.preferenceLevel + '.';
        }
        return null;
    }

    private static Boolean containsNoEquipmentHere(String accountName) {
        return String.isNotBlank(accountName) && accountName.toLowerCase().contains('no equipment here');
    }

    private static Boolean isDistributor(Account addressAccount) {
        return looksLikeDistributor(addressAccount.SMI__c) ||
            looksLikeDistributor(addressAccount.CustomerProfileClass__c) ||
            looksLikeDistributor(addressAccount.Type) ||
            looksLikeDistributor(addressAccount.Parent == null ? null : addressAccount.Parent.SMI__c) ||
            looksLikeDistributor(addressAccount.Parent == null ? null : addressAccount.Parent.CustomerProfileClass__c) ||
            looksLikeDistributor(addressAccount.Parent == null ? null : addressAccount.Parent.Type);
    }

    private static Boolean looksLikeDistributor(String value) {
        return String.isNotBlank(value) && value.toLowerCase().contains('distributor');
    }

    private static String normalizeTerritory(String value) {
        if (String.isBlank(value)) {
            return null;
        }
        String key = value.trim().toLowerCase();
        if (TERRITORY_BY_KEY.containsKey(key)) {
            return TERRITORY_BY_KEY.get(key);
        }
        return null;
    }

    private static String normalizePreference(String value) {
        if (String.isBlank(value)) {
            return PREFERENCE_PREFERRED;
        }
        String key = value.trim().toLowerCase();
        return PREFERENCE_BY_KEY.containsKey(key) ? PREFERENCE_BY_KEY.get(key) : null;
    }

    private static String preferenceKey(Id addressAccountId, Id serviceResourceId, String territoryType, Id workTypeId) {
        return String.valueOf(addressAccountId) +
            '|' +
            String.valueOf(serviceResourceId) +
            '|' +
            String.valueOf(territoryType) +
            '|' +
            String.valueOf(workTypeId);
    }

    private static String preferenceName(String territoryType, String workTypeName, String preferenceLevel, String resourceName) {
        String nameValue;
        if (String.isNotBlank(territoryType) && String.isNotBlank(workTypeName)) {
            nameValue = territoryType + '-' + workTypeName + ' -' + preferenceLevel;
        } else if (String.isNotBlank(territoryType)) {
            nameValue = territoryType + '-' + preferenceLevel;
        } else {
            nameValue = preferenceLevel;
        }
        if (String.isBlank(nameValue)) {
            nameValue = resourceName;
        }
        return nameValue.left(NAME_MAX_LENGTH);
    }

    private static ParsedFile parseFile(ContentVersion version) {
        String extension = version.FileExtension == null ? '' : version.FileExtension.toLowerCase();
        String pathOnClient = version.PathOnClient == null ? '' : version.PathOnClient.toLowerCase();
        Boolean isExcel = extension == 'xlsx' || pathOnClient.endsWith('.xlsx');
        List<List<String>> table;
        if (isExcel) {
            try {
                table = ExcelFileParser.readFirstSheet(version.VersionData);
            } catch (ExcelFileParser.ParseException e) {
                throw auraError(excelUploadMessage(e));
            }
        } else {
            table = parseCsv(version.VersionData.toString());
        }
        if (table.isEmpty()) {
            throw auraError('The uploaded file is empty.');
        }
        return toRows(table);
    }

    private static ParsedFile toRows(List<List<String>> table) {
        Map<String, Integer> columnIndexByName = new Map<String, Integer>();
        List<String> header = table[0];
        for (Integer i = 0; i < header.size(); i++) {
            String headerName = normalizeHeader(header[i]);
            if (String.isNotBlank(headerName) && !columnIndexByName.containsKey(headerName)) {
                columnIndexByName.put(headerName, i);
            }
        }
        Integer addressColumn = firstColumn(columnIndexByName, new List<String>{ 'addid', 'addressid', 'oracleaddressid' });
        Integer hrisColumn = firstColumn(columnIndexByName, new List<String>{ 'hrisid', 'employeenumber', 'userid', 'techhris' });
        if (addressColumn == null || hrisColumn == null) {
            throw auraError('The file must include ADDID and HRIS ID columns.');
        }
        if (table.size() - 1 > MAX_ROWS) {
            throw auraError('The file exceeds the maximum of ' + MAX_ROWS + ' data rows.');
        }

        ParsedFile parsed = new ParsedFile();
        parsed.header = table[0];
        for (Integer i = 1; i < table.size(); i++) {
            List<String> cells = table[i];
            AssignmentRow row = new AssignmentRow();
            row.rowNumber = i + 1;
            row.cells = cells;
            row.addressId = normalizeKey(cellValue(cells, addressColumn));
            row.hrisId = normalizeKey(cellValue(cells, hrisColumn));
            row.territoryType = firstPresent(cells, columnIndexByName, new List<String>{ 'territorytype', 'districttype', 'type' });
            row.workTypeName = cellValue(cells, columnIndexByName.get('worktype'));
            row.preferenceLevel = firstPresent(cells, columnIndexByName, new List<String>{ 'preferencelevel', 'preferencetype' });
            if (String.isBlank(row.addressId) && String.isBlank(row.hrisId) && String.isBlank(row.territoryType) && String.isBlank(row.workTypeName)) {
                continue;
            }
            parsed.rows.add(row);
        }
        return parsed;
    }

    private static Integer firstColumn(Map<String, Integer> columnIndexByName, List<String> keys) {
        for (String key : keys) {
            if (columnIndexByName.containsKey(key)) {
                return columnIndexByName.get(key);
            }
        }
        return null;
    }

    private static String firstPresent(List<String> cells, Map<String, Integer> columnIndexByName, List<String> keys) {
        for (String key : keys) {
            if (columnIndexByName.containsKey(key)) {
                String value = cellValue(cells, columnIndexByName.get(key));
                if (String.isNotBlank(value)) {
                    return value;
                }
            }
        }
        return null;
    }

    private static String cellValue(List<String> cells, Integer index) {
        if (index == null || cells == null || index < 0 || index >= cells.size()) {
            return null;
        }
        String value = cells[index];
        return String.isBlank(value) ? null : value.trim();
    }

    private static String normalizeHeader(String header) {
        if (String.isBlank(header)) {
            return null;
        }
        return header.replace('\uFEFF', '').replace('_', '').replace(' ', '').replace('-', '').replace('#', '').trim().toLowerCase();
    }

    private static List<List<String>> parseCsv(String csvBody) {
        String body = csvBody == null ? '' : csvBody.replace('\uFEFF', '').replace('\r\n', '\n').replace('\r', '\n');
        List<List<String>> table = new List<List<String>>();
        List<String> currentRow = new List<String>();
        String currentValue = '';
        Boolean inQuotes = false;
        for (Integer i = 0; i < body.length(); i++) {
            String currentChar = body.substring(i, i + 1);
            if (inQuotes) {
                if (currentChar == '"') {
                    Boolean isEscapedQuote = i + 1 < body.length() && body.substring(i + 1, i + 2) == '"';
                    if (isEscapedQuote) {
                        currentValue += '"';
                        i++;
                    } else {
                        inQuotes = false;
                    }
                } else {
                    currentValue += currentChar;
                }
            } else if (currentChar == '"') {
                inQuotes = true;
            } else if (currentChar == ',') {
                currentRow.add(currentValue);
                currentValue = '';
            } else if (currentChar == '\n') {
                currentRow.add(currentValue);
                if (!isEmptyRow(currentRow)) {
                    table.add(currentRow);
                }
                currentRow = new List<String>();
                currentValue = '';
            } else {
                currentValue += currentChar;
            }
        }
        currentRow.add(currentValue);
        if (!isEmptyRow(currentRow)) {
            table.add(currentRow);
        }
        return table;
    }

    private static Boolean isEmptyRow(List<String> row) {
        for (String value : row) {
            if (String.isNotBlank(value)) {
                return false;
            }
        }
        return true;
    }

    private static String excelUploadMessage(ExcelFileParser.ParseException e) {
        String detail = e == null ? null : e.getMessage();
        if (String.isNotBlank(detail) && detail.contains('worksheet')) {
            return 'The Excel file does not contain a worksheet that can be read. Save the template as CSV and try again.';
        }
        return 'Unable to read the Excel file. Download the template and save it as CSV.';
    }

    private static String normalizeKey(String value) {
        if (String.isBlank(value)) {
            return null;
        }
        return value.trim().replaceFirst('^(\\d+)\\.0+$', '$1');
    }

    private static void rowError(List<AssignmentRow> rows, Integer rowNumber, String message) {
        for (AssignmentRow row : rows) {
            if (row.rowNumber == rowNumber) {
                row.errorMessage = message;
                return;
            }
        }
    }

    private static Id readStoredTemplateId() {
        FieldServiceBackofficeConfig__c config = FieldServiceBackofficeConfig__c.getOrgDefaults();
        if (config == null || String.isBlank(config.TechAccountAlignmentTemplateId__c)) {
            return null;
        }
        try {
            Id storedId = Id.valueOf(config.TechAccountAlignmentTemplateId__c);
            List<ContentDocument> storedDocs = ContentDocumentsSelector.selectIdAndTitleByIds(new Set<Id>{ storedId });
            return storedDocs.isEmpty() ? null : storedDocs[0].Id;
        } catch (Exception e) {
            Logger.warn('Tech Account Alignment template Id in custom setting is invalid.');
            return null;
        }
    }

    private static Boolean templateIsCurrent(Id documentId) {
        List<ContentVersion> latest = ContentVersionsSelector.selectLatestByContentDocumentId(documentId);
        Blob packagedBody = packagedTemplateBody();
        return !latest.isEmpty() &&
            latest[0].VersionData != null &&
            packagedBody != null &&
            latest[0].VersionData == packagedBody &&
            latest[0].FileExtension != null &&
            latest[0].FileExtension.equalsIgnoreCase('xlsx');
    }

    private static Blob packagedTemplateBody() {
        List<StaticResource> resources = StaticResourcesSelector.selectByName(TEMPLATE_RESOURCE_NAME);
        if (resources.isEmpty()) {
            return null;
        }
        return resources[0].Body;
    }

    private static Id publishTemplate(Id documentId) {
        try {
            ContentVersion version = newTemplateVersion(documentId);
            return ContentVersionsSelector.selectDocumentIdByVersionId(version.Id)[0].ContentDocumentId;
        } catch (Exception e) {
            Logger.warn('Tech Account Alignment template could not be refreshed.');
            return null;
        }
    }

    private static ContentVersion newTemplateVersion(Id documentId) {
        Blob packagedBody = packagedTemplateBody();
        if (packagedBody == null) {
            throw auraError('Tech Account Alignment template is not available.');
        }
        ContentVersion version = new ContentVersion();
        version.Title = TEMPLATE_TITLE;
        version.PathOnClient = TEMPLATE_FILE_NAME;
        version.VersionData = packagedBody;
        version.IsMajorVersion = true;
        if (documentId != null) {
            version.ContentDocumentId = documentId;
        }
        insert version;
        return version;
    }

    private static Id storedErrorFileDocumentId() {
        FieldServiceBackofficeConfig__c config = FieldServiceBackofficeConfig__c.getValues(UserInfo.getUserId());
        if (config == null || String.isBlank(config.TechAccountAlignmentErrorFileId__c)) {
            return null;
        }
        try {
            Id storedId = Id.valueOf(config.TechAccountAlignmentErrorFileId__c);
            List<ContentDocument> storedDocs = ContentDocumentsSelector.selectIdAndTitleByIds(new Set<Id>{ storedId });
            return storedDocs.isEmpty() ? null : storedDocs[0].Id;
        } catch (Exception e) {
            return null;
        }
    }

    private static void writeErrorFile(List<String> header, List<AssignmentRow> rows) {
        List<String> lines = new List<String>{ csvLine('Row', header, 'Error', header == null ? 0 : header.size()) };
        for (AssignmentRow row : rows) {
            if (row.errorMessage != null) {
                lines.add(csvLine(String.valueOf(row.rowNumber), row.cells, row.errorMessage, header.size()));
            }
        }

        Id existingDocumentId = storedErrorFileDocumentId();
        ContentVersion version = new ContentVersion();
        version.Title = ERROR_FILE_TITLE;
        version.PathOnClient = ERROR_FILE_NAME;
        version.VersionData = Blob.valueOf(String.join(lines, '\n') + '\n');
        version.IsMajorVersion = true;
        if (existingDocumentId != null) {
            version.ContentDocumentId = existingDocumentId;
        }
        insert version;

        Id documentId = ContentVersionsSelector.selectDocumentIdByVersionId(version.Id)[0].ContentDocumentId;
        if (documentId != existingDocumentId) {
            new TemplateStore().saveErrorFileDocumentId(documentId);
        }
    }

    private static String csvLine(String first, List<String> cells, String last, Integer columnCount) {
        List<String> values = new List<String>{ csvEscape(first) };
        Integer size = cells == null ? 0 : cells.size();
        for (Integer i = 0; i < columnCount; i++) {
            values.add(csvEscape(i < size ? cells[i] : null));
        }
        values.add(csvEscape(last));
        return String.join(values, ',');
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

    private static AuraHandledException auraError(String message) {
        AuraHandledException ex = new AuraHandledException(message);
        ex.setMessage(message);
        return ex;
    }

    private static void persistTemplateDocumentId(Id documentId) {
        new TemplateStore().saveDocumentId(documentId);
    }

    private without sharing class TemplateStore {
        /**
         * @description Stores the template ContentDocument Id on the org-level custom setting.
         * @param documentId Salesforce Files document Id.
         */
        public void saveDocumentId(Id documentId) {
            FieldServiceBackofficeConfig__c config = FieldServiceBackofficeConfig__c.getOrgDefaults();
            if (config == null) {
                config = new FieldServiceBackofficeConfig__c();
            }
            if (config.Id == null) {
                config.SetupOwnerId = UserInfo.getOrganizationId();
            }
            config.TechAccountAlignmentTemplateId__c = String.valueOf(documentId);
            upsert config;
        }

        /**
         * @description Stores the running user's error-file ContentDocument Id.
         * @param documentId Salesforce Files document Id.
         */
        public void saveErrorFileDocumentId(Id documentId) {
            FieldServiceBackofficeConfig__c config = FieldServiceBackofficeConfig__c.getValues(UserInfo.getUserId());
            if (config == null) {
                config = new FieldServiceBackofficeConfig__c();
            }
            if (config.Id == null) {
                config.SetupOwnerId = UserInfo.getUserId();
            }
            config.TechAccountAlignmentErrorFileId__c = String.valueOf(documentId);
            upsert config;
        }
    }
}