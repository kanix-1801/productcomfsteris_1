/**
 * @description GW-2710 - Creates AddressResourcePreference records from a Tech Account Alignment file.
 */
public with sharing class TechAccountAlignmentService {
    public static final String TEMPLATE_TITLE = 'Tech Account Alignment Template';
    public static final String TEMPLATE_RESOURCE_NAME = 'TechAccountAlignmentTemplate';
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
     * @description Counts and skip messages returned to the LWC after Start Upload.
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
        String userIdValue;
        String territoryType;
        String workTypeName;
        String preferenceLevel;
    }

    /**
     * @description Copies the packaged template into Salesforce Files if needed and returns its ContentDocument Id.
     * @return ContentDocument Id of the template file.
     */
    public static Id ensureTemplateDocumentId() {
        FieldServiceBackofficeConfig__c config = FieldServiceBackofficeConfig__c.getOrgDefaults();
        if (config != null && String.isNotBlank(config.TechAccountAlignmentTemplateId__c)) {
            try {
                Id storedId = Id.valueOf(config.TechAccountAlignmentTemplateId__c);
                List<ContentDocument> storedDocs = ContentDocumentsSelector.selectIdAndTitleByIds(new Set<Id>{ storedId });
                if (!storedDocs.isEmpty()) {
                    return storedDocs[0].Id;
                }
            } catch (Exception e) {
                Logger.warn('Tech Account Alignment template Id in custom setting is invalid.');
            }
        }

        List<ContentDocument> titledDocs = ContentDocumentsSelector.selectLatestByTitle(TEMPLATE_TITLE);
        if (!titledDocs.isEmpty()) {
            persistTemplateDocumentId(titledDocs[0].Id);
            return titledDocs[0].Id;
        }

        List<StaticResource> resources = StaticResourcesSelector.selectByName(TEMPLATE_RESOURCE_NAME);
        if (resources.isEmpty() || resources[0].Body == null) {
            throw auraError('Tech Account Alignment template is not available.');
        }

        ContentVersion version = new ContentVersion();
        version.Title = TEMPLATE_TITLE;
        version.PathOnClient = 'Tech_Account_Alignment_Template.csv';
        version.VersionData = resources[0].Body;
        version.IsMajorVersion = true;
        insert version;

        Id documentId = ContentVersionsSelector.selectDocumentIdByVersionId(version.Id)[0].ContentDocumentId;
        persistTemplateDocumentId(documentId);
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
            throw auraError('Upload a file before clicking Start Upload.');
        }

        List<ContentVersion> versions = ContentVersionsSelector.selectLatestForAlignmentUpload(contentDocumentId);
        if (versions.isEmpty() || versions[0].VersionData == null) {
            throw auraError('The uploaded file could not be read.');
        }

        List<AssignmentRow> rows = parseFile(versions[0]);
        result.processedCount = rows.size();
        if (rows.isEmpty()) {
            return result;
        }

        Set<String> oracleAddressIds = new Set<String>();
        Set<Id> userIds = new Set<Id>();
        Set<String> workTypeNames = new Set<String>();
        for (AssignmentRow row : rows) {
            if (String.isNotBlank(row.addressId)) {
                oracleAddressIds.add(row.addressId);
            }
            Id userId = toUserId(row.userIdValue);
            if (userId != null) {
                userIds.add(userId);
            }
            if (String.isNotBlank(row.workTypeName)) {
                workTypeNames.add(row.workTypeName);
            }
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
            String skipReason = skipReason(row, accountByOracleId, resourceByUserId, workTypeByName);
            if (skipReason != null) {
                result.skippedCount++;
                result.errors.add('Row ' + row.rowNumber + ': ' + skipReason);
                continue;
            }

            Account addressAccount = accountByOracleId.get(row.addressId);
            ServiceResource resource = resourceByUserId.get(toUserId(row.userIdValue));
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
                result.skippedCount++;
                result.errors.add('Row ' + row.rowNumber + ': Preference already exists for this technician and district type.');
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
                    result.errors.add('Row ' + insertRowNumbers[i] + ': ' + message);
                }
            }
        }

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
        Map<Id, ServiceResource> resourceByUserId,
        Map<String, WorkType> workTypeByName
    ) {
        if (String.isBlank(row.addressId)) {
            return 'Address ID is required.';
        }
        if (String.isBlank(row.userIdValue)) {
            return 'User ID is required.';
        }
        Id userId = toUserId(row.userIdValue);
        if (userId == null) {
            return 'User ID must match a Salesforce User Id exactly.';
        }
        Account addressAccount = accountByOracleId.get(row.addressId);
        if (addressAccount == null) {
            return 'No Address account found for Address ID ' + row.addressId + '.';
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
        if (!resourceByUserId.containsKey(userId)) {
            return 'User ID must match an active Service Resource RelatedRecordId exactly.';
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

    private static Id toUserId(String value) {
        if (String.isBlank(value)) {
            return null;
        }
        String trimmed = value.trim();
        if (!PlatformUtilities.isSalesforceId(trimmed)) {
            return null;
        }
        return Id.valueOf(trimmed);
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

    private static List<AssignmentRow> parseFile(ContentVersion version) {
        String extension = version.FileExtension == null ? '' : version.FileExtension.toLowerCase();
        String pathOnClient = version.PathOnClient == null ? '' : version.PathOnClient.toLowerCase();
        Boolean isExcel = extension == 'xlsx' || pathOnClient.endsWith('.xlsx');
        List<List<String>> table;
        if (isExcel) {
            try {
                table = parseXlsx(version.VersionData);
            } catch (AuraHandledException e) {
                throw e;
            } catch (Exception e) {
                throw auraError('Unable to read the Excel file. Download the template and save it as CSV.');
            }
        } else {
            table = parseCsv(version.VersionData.toString());
        }
        if (table.isEmpty()) {
            throw auraError('The uploaded file is empty.');
        }
        return toRows(table);
    }

    private static List<AssignmentRow> toRows(List<List<String>> table) {
        Map<String, Integer> columnIndexByName = new Map<String, Integer>();
        List<String> header = table[0];
        for (Integer i = 0; i < header.size(); i++) {
            String headerName = normalizeHeader(header[i]);
            if (String.isNotBlank(headerName) && !columnIndexByName.containsKey(headerName)) {
                columnIndexByName.put(headerName, i);
            }
        }
        if (!columnIndexByName.containsKey('addressid') || !columnIndexByName.containsKey('userid')) {
            throw auraError('The file must include Address ID and User ID columns.');
        }
        if (table.size() - 1 > MAX_ROWS) {
            throw auraError('The file exceeds the maximum of ' + MAX_ROWS + ' data rows.');
        }

        List<AssignmentRow> rows = new List<AssignmentRow>();
        for (Integer i = 1; i < table.size(); i++) {
            List<String> cells = table[i];
            AssignmentRow row = new AssignmentRow();
            row.rowNumber = i + 1;
            row.addressId = cellValue(cells, columnIndexByName.get('addressid'));
            row.userIdValue = cellValue(cells, columnIndexByName.get('userid'));
            row.territoryType = firstPresent(cells, columnIndexByName, new List<String>{ 'territorytype', 'districttype' });
            row.workTypeName = cellValue(cells, columnIndexByName.get('worktype'));
            row.preferenceLevel = firstPresent(cells, columnIndexByName, new List<String>{ 'preferencelevel', 'preferencetype' });
            if (String.isBlank(row.addressId) && String.isBlank(row.userIdValue) && String.isBlank(row.territoryType) && String.isBlank(row.workTypeName)) {
                continue;
            }
            rows.add(row);
        }
        return rows;
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
        return header.replace('\uFEFF', '').replace('_', '').replace(' ', '').replace('-', '').trim().toLowerCase();
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

    private static List<List<String>> parseXlsx(Blob fileBody) {
        Compression.ZipReader zipReader = new Compression.ZipReader(fileBody);
        String sharedStringsXml;
        String sheetXml;
        for (Compression.ZipEntry entry : zipReader.getEntries()) {
            String entryName = entry.getName() == null ? '' : entry.getName().replace('\\', '/').toLowerCase();
            if (entryName.endsWith('xl/sharedstrings.xml')) {
                sharedStringsXml = zipReader.extract(entry).toString();
            } else if (entryName.endsWith('xl/worksheets/sheet1.xml')) {
                sheetXml = zipReader.extract(entry).toString();
            } else if (sheetXml == null && entryName.contains('xl/worksheets/sheet') && entryName.endsWith('.xml')) {
                sheetXml = zipReader.extract(entry).toString();
            }
        }
        if (String.isBlank(sheetXml)) {
            throw auraError('The Excel file does not contain a worksheet that can be read. Save the template as CSV and try again.');
        }
        List<String> sharedStrings = parseSharedStrings(sharedStringsXml);
        return parseSheetXml(sheetXml, sharedStrings);
    }

    private static List<String> parseSharedStrings(String xmlBody) {
        List<String> values = new List<String>();
        if (String.isBlank(xmlBody)) {
            return values;
        }
        XmlStreamReader reader = new XmlStreamReader(xmlBody);
        while (reader.hasNext()) {
            if (reader.getEventType() == XmlTag.START_ELEMENT && reader.getLocalName() == 't') {
                reader.next();
                values.add(reader.getEventType() == XmlTag.CHARACTERS ? reader.getText() : '');
            }
            reader.next();
        }
        return values;
    }

    private static List<List<String>> parseSheetXml(String xmlBody, List<String> sharedStrings) {
        Map<Integer, Map<Integer, String>> cellsByRow = new Map<Integer, Map<Integer, String>>();
        Integer maxColumn = 0;
        XmlStreamReader reader = new XmlStreamReader(xmlBody);
        String cellRef;
        String cellType;
        while (reader.hasNext()) {
            if (reader.getEventType() == XmlTag.START_ELEMENT) {
                String localName = reader.getLocalName();
                if (localName == 'c') {
                    cellRef = reader.getAttributeValue(null, 'r');
                    cellType = reader.getAttributeValue(null, 't');
                } else if (localName == 'v' && String.isNotBlank(cellRef)) {
                    reader.next();
                    String rawValue = reader.getEventType() == XmlTag.CHARACTERS ? reader.getText() : '';
                    putCell(cellsByRow, cellRef, resolveCellValue(cellType, rawValue, sharedStrings));
                    Integer columnIndex = columnIndexFromRef(cellRef);
                    if (columnIndex > maxColumn) {
                        maxColumn = columnIndex;
                    }
                } else if (localName == 't' && cellType == 'inlineStr' && String.isNotBlank(cellRef)) {
                    reader.next();
                    String rawValue = reader.getEventType() == XmlTag.CHARACTERS ? reader.getText() : '';
                    putCell(cellsByRow, cellRef, rawValue);
                    Integer columnIndex = columnIndexFromRef(cellRef);
                    if (columnIndex > maxColumn) {
                        maxColumn = columnIndex;
                    }
                }
            }
            reader.next();
        }

        List<Integer> rowNumbers = new List<Integer>(cellsByRow.keySet());
        rowNumbers.sort();
        List<List<String>> table = new List<List<String>>();
        for (Integer rowNumber : rowNumbers) {
            Map<Integer, String> rowCells = cellsByRow.get(rowNumber);
            List<String> row = new List<String>();
            for (Integer columnIndex = 0; columnIndex <= maxColumn; columnIndex++) {
                row.add(rowCells.containsKey(columnIndex) ? rowCells.get(columnIndex) : '');
            }
            if (!isEmptyRow(row)) {
                table.add(row);
            }
        }
        return table;
    }

    private static void putCell(Map<Integer, Map<Integer, String>> cellsByRow, String cellRef, String value) {
        Integer rowNumber = rowIndexFromRef(cellRef);
        Integer columnIndex = columnIndexFromRef(cellRef);
        if (!cellsByRow.containsKey(rowNumber)) {
            cellsByRow.put(rowNumber, new Map<Integer, String>());
        }
        cellsByRow.get(rowNumber).put(columnIndex, value);
    }

    private static String resolveCellValue(String cellType, String rawValue, List<String> sharedStrings) {
        if (cellType == 's') {
            Integer index = Integer.valueOf(rawValue);
            return index >= 0 && index < sharedStrings.size() ? sharedStrings[index] : rawValue;
        }
        return rawValue;
    }

    private static Integer columnIndexFromRef(String cellRef) {
        String letters = '';
        for (Integer i = 0; i < cellRef.length(); i++) {
            String currentChar = cellRef.substring(i, i + 1);
            if (currentChar >= 'A' && currentChar <= 'Z') {
                letters += currentChar;
            } else {
                break;
            }
        }
        Integer index = 0;
        for (Integer i = 0; i < letters.length(); i++) {
            index = (index * 26) + (letters.charAt(i) - 64);
        }
        return index - 1;
    }

    private static Integer rowIndexFromRef(String cellRef) {
        String digits = '';
        for (Integer i = 0; i < cellRef.length(); i++) {
            String currentChar = cellRef.substring(i, i + 1);
            if (currentChar >= '0' && currentChar <= '9') {
                digits += currentChar;
            }
        }
        return Integer.valueOf(digits);
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
    }
}