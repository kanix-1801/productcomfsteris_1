/**
 * @description GW-2707 - Tests for Tech District Alignment upload, error file, template download and row rules.
 */
@IsTest
private class TechDistrictAlignmentControllerTest {
    private static final String TECH_ONE_HRIS = 'GW2707T1';
    private static final String TECH_TWO_HRIS = '992707002';
    private static final String TECH_USER_ONLY_HRIS = 'GW2707T1USER';
    private static final String ASM_A_HRIS = 'GW2707ASMA';
    private static final String ASM_B_HRIS = 'GW2707ASMB';
    private static final String CURRENT_TERRITORY = 'S2707CUR';
    private static final String NEXT_TERRITORY = 'S2707NXT';
    private static final String NEW_TERRITORY = 'S2707NEW';
    private static final String ZONE_TERRITORY = 'Z2707';

    @TestSetup
    static void setupData() {
        User techOne = newUser('Gwtechone', 'a', TECH_USER_ONLY_HRIS);
        User techTwo = newUser('Gwtechtwo', 'b', null);
        User asmA = newUser('Gwasma', 'c', ASM_A_HRIS);
        User asmB = newUser('Gwasmb', 'd', ASM_B_HRIS);
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert new List<User>{ techOne, techTwo, asmA, asmB };
        }

        OperatingHours hours = new OperatingHours(Name = 'GW2707 Hours', TimeZone = 'America/New_York');
        insert hours;

        ServiceTerritory zone = new ServiceTerritory(
            Name = 'GW2707 Zone',
            RegionNumber__c = ZONE_TERRITORY,
            TerritoryType__c = 'Zone',
            OperatingHoursId = hours.Id,
            IsActive = true
        );
        insert zone;
        insert new List<ServiceTerritory>{
            district('GW2707 Current', CURRENT_TERRITORY, zone.Id, hours.Id, asmA.Id),
            district('GW2707 Next', NEXT_TERRITORY, zone.Id, hours.Id, asmA.Id)
        };

        ServiceResource resourceOne = new ServiceResource(
            Name = 'GW2707 Tech One',
            RelatedRecordId = techOne.Id,
            IsActive = true,
            ResourceType = 'T',
            ExternalID__c = TECH_ONE_HRIS
        );
        ServiceResource resourceTwo = new ServiceResource(
            Name = 'GW2707 Tech Two',
            RelatedRecordId = techTwo.Id,
            IsActive = true,
            ResourceType = 'T',
            ExternalID__c = TECH_TWO_HRIS
        );
        insert new List<ServiceResource>{ resourceOne, resourceTwo };

        Id currentId = territoryId(CURRENT_TERRITORY);
        Datetime started = Datetime.now().addDays(-30);
        insert new List<ServiceTerritoryMember>{
            new ServiceTerritoryMember(
                ServiceResourceId = resourceOne.Id,
                ServiceTerritoryId = currentId,
                EffectiveStartDate = started,
                TerritoryType = 'P'
            ),
            new ServiceTerritoryMember(
                ServiceResourceId = resourceTwo.Id,
                ServiceTerritoryId = currentId,
                EffectiveStartDate = started,
                TerritoryType = 'P'
            )
        };
    }

    @IsTest
    static void processUpload_createsNextYearTerritoryAndMovesTechs() {
        Id documentId = insertCsv(
            headerRow() +
            csvRow(TECH_ONE_HRIS, CURRENT_TERRITORY, ASM_A_HRIS, NEW_TERRITORY, ASM_B_HRIS) +
            csvRow(TECH_TWO_HRIS, CURRENT_TERRITORY, ASM_A_HRIS, NEW_TERRITORY, ASM_B_HRIS)
        );

        Test.startTest();
        TechDistrictAlignmentService.ProcessResult result = TechDistrictAlignmentController.processUpload(documentId);
        Test.stopTest();

        Assert.areEqual(2, result.processedCount);
        Assert.areEqual(1, result.territoryCreatedCount, 'Both rows share one new territory.');
        Assert.areEqual(2, result.movedCount);
        Assert.areEqual(0, result.skippedCount, String.join(result.errors, '\n'));
        Assert.areEqual(TechDistrictAlignmentService.nextFiscalYearStart(), result.nextFiscalYearStart);

        ServiceTerritory current = [
            SELECT Id, TerritoryType__c, ParentTerritoryId, OperatingHoursId
            FROM ServiceTerritory
            WHERE RegionNumber__c = :CURRENT_TERRITORY
        ];
        ServiceTerritory created = [
            SELECT Id, Name, TerritoryType__c, ParentTerritoryId, OperatingHoursId, TerritoryManager__c, IsActive
            FROM ServiceTerritory
            WHERE RegionNumber__c = :NEW_TERRITORY
        ];
        Assert.areEqual(NEW_TERRITORY, created.Name);
        Assert.areEqual(current.TerritoryType__c, created.TerritoryType__c);
        Assert.areEqual(current.ParentTerritoryId, created.ParentTerritoryId);
        Assert.areEqual(current.OperatingHoursId, created.OperatingHoursId);
        Assert.areEqual(userIdByHris(ASM_B_HRIS), created.TerritoryManager__c);
        Assert.isTrue(created.IsActive);

        List<ServiceTerritoryMember> nextMembers = [
            SELECT EffectiveStartDate, TerritoryType
            FROM ServiceTerritoryMember
            WHERE ServiceTerritoryId = :created.Id
        ];
        Assert.areEqual(2, nextMembers.size());
        for (ServiceTerritoryMember member : nextMembers) {
            Assert.areEqual(TechDistrictAlignmentService.nextFiscalYearStartDatetime(), member.EffectiveStartDate);
            Assert.areEqual('P', member.TerritoryType);
        }
        assertCurrentMembershipsEnded(2);
    }

    @IsTest
    static void processUpload_movesToExistingTerritoryAndUpdatesManager() {
        Id documentId = insertCsv(
            headerRow() + csvRow(TECH_ONE_HRIS, CURRENT_TERRITORY, ASM_A_HRIS, NEXT_TERRITORY, ASM_B_HRIS)
        );

        Test.startTest();
        TechDistrictAlignmentService.ProcessResult result = TechDistrictAlignmentController.processUpload(documentId);
        Test.stopTest();

        Assert.areEqual(1, result.movedCount);
        Assert.areEqual(1, result.managerUpdatedCount);
        Assert.areEqual(0, result.territoryCreatedCount);
        Assert.areEqual(0, result.skippedCount, String.join(result.errors, '\n'));

        ServiceTerritory next = [SELECT Id, TerritoryManager__c FROM ServiceTerritory WHERE RegionNumber__c = :NEXT_TERRITORY];
        Assert.areEqual(userIdByHris(ASM_B_HRIS), next.TerritoryManager__c);
        ServiceTerritoryMember nextMember = [
            SELECT EffectiveStartDate
            FROM ServiceTerritoryMember
            WHERE ServiceTerritoryId = :next.Id AND ServiceResource.Name = 'GW2707 Tech One'
        ];
        Assert.areEqual(TechDistrictAlignmentService.nextFiscalYearStartDatetime(), nextMember.EffectiveStartDate);
        assertCurrentMembershipsEnded(1);
    }

    @IsTest
    static void processUpload_sameTerritoryUpdatesManagerOrDoesNothing() {
        Id documentId = insertCsv(
            headerRow() +
            csvRow(TECH_ONE_HRIS, CURRENT_TERRITORY, ASM_A_HRIS, CURRENT_TERRITORY, ASM_A_HRIS) +
            csvRow(TECH_TWO_HRIS, CURRENT_TERRITORY, ASM_A_HRIS, CURRENT_TERRITORY, ASM_B_HRIS)
        );

        Test.startTest();
        TechDistrictAlignmentService.ProcessResult result = TechDistrictAlignmentController.processUpload(documentId);
        Test.stopTest();

        Assert.areEqual(0, result.movedCount);
        Assert.areEqual(1, result.managerUpdatedCount);
        Assert.areEqual(1, result.unchangedCount);
        Assert.areEqual(0, result.skippedCount, String.join(result.errors, '\n'));
        Assert.areEqual(userIdByHris(ASM_B_HRIS), [SELECT TerritoryManager__c FROM ServiceTerritory WHERE RegionNumber__c = :CURRENT_TERRITORY].TerritoryManager__c);
        Assert.areEqual(2, [SELECT COUNT() FROM ServiceTerritoryMember WHERE EffectiveEndDate = NULL]);
        assertCurrentMembershipsEnded(0);
    }

    @IsTest
    static void processUpload_skipsInvalidRowsIntoErrorFile() {
        Id documentId = insertCsv(
            headerRow() +
            csvRow('', CURRENT_TERRITORY, ASM_A_HRIS, NEXT_TERRITORY, ASM_B_HRIS) +
            csvRow('NOPE2707', CURRENT_TERRITORY, ASM_A_HRIS, NEXT_TERRITORY, ASM_B_HRIS) +
            csvRow(TECH_ONE_HRIS, 'NOPE2707', ASM_A_HRIS, NEXT_TERRITORY, ASM_B_HRIS) +
            csvRow(TECH_ONE_HRIS, ZONE_TERRITORY, ASM_A_HRIS, NEXT_TERRITORY, ASM_B_HRIS) +
            csvRow(TECH_TWO_HRIS, NEXT_TERRITORY, ASM_A_HRIS, NEXT_TERRITORY, ASM_B_HRIS) +
            csvRow(TECH_ONE_HRIS, CURRENT_TERRITORY, 'NOPE2707', NEXT_TERRITORY, ASM_B_HRIS) +
            csvRow(TECH_ONE_HRIS, CURRENT_TERRITORY, ASM_A_HRIS, '-', ASM_B_HRIS) +
            csvRow(TECH_ONE_HRIS, CURRENT_TERRITORY, ASM_A_HRIS, NEXT_TERRITORY, 'NOPE2707') +
            csvRow(TECH_ONE_HRIS, CURRENT_TERRITORY, ASM_A_HRIS, NEW_TERRITORY, '') +
            csvRow(TECH_ONE_HRIS, CURRENT_TERRITORY, ASM_A_HRIS, ZONE_TERRITORY, ASM_B_HRIS) +
            csvRow(TECH_ONE_HRIS, CURRENT_TERRITORY, ASM_A_HRIS, NEXT_TERRITORY, ASM_B_HRIS) +
            csvRow(TECH_ONE_HRIS, CURRENT_TERRITORY, ASM_A_HRIS, NEXT_TERRITORY, ASM_B_HRIS)
        );

        Test.startTest();
        TechDistrictAlignmentService.ProcessResult result = TechDistrictAlignmentController.processUpload(documentId);
        Test.stopTest();

        Assert.areEqual(12, result.processedCount);
        Assert.areEqual(1, result.movedCount);
        Assert.areEqual(1, result.managerUpdatedCount);
        Assert.areEqual(11, result.skippedCount);
        Assert.isTrue(containsMessage(result.errors, 'Row 2: Invalid HRIS ID for Tech: TECH HRIS# is required'));
        Assert.isTrue(containsMessage(result.errors, 'Invalid HRIS ID for Tech: No active Service Resource found for HRIS ID NOPE2707'));
        Assert.isTrue(containsMessage(result.errors, 'Invalid Current Territory: No service territory found'));
        Assert.isTrue(containsMessage(result.errors, 'Invalid Current Territory: Territory Z2707 has type Zone'));
        Assert.isTrue(containsMessage(result.errors, 'Service Resource is not assigned to service territory S2707NXT'));
        Assert.isTrue(containsMessage(result.errors, 'Current ASM HRIS ID is invalid: No active user found'));
        Assert.isTrue(containsMessage(result.errors, 'Invalid Next Year Territory: Next Year Territory is required'));
        Assert.isTrue(containsMessage(result.errors, 'Next Year ASM HRIS ID is invalid: No active user found'));
        Assert.isTrue(containsMessage(result.errors, 'required to create territory S2707NEW'));
        Assert.isTrue(containsMessage(result.errors, 'Invalid Next Year Territory: Territory Z2707 has type Zone'));
        Assert.isTrue(containsMessage(result.errors, 'Row 13: Invalid HRIS ID for Tech: Technician GW2707T1 appears more than once'));
        Assert.areEqual(0, [SELECT COUNT() FROM ServiceTerritory WHERE RegionNumber__c = :NEW_TERRITORY]);

        Assert.isNotNull(result.errorFileDocumentId);
        ContentVersion errorFile = [
            SELECT VersionData
            FROM ContentVersion
            WHERE ContentDocumentId = :result.errorFileDocumentId AND IsLatest = TRUE
        ];
        List<String> lines = errorFile.VersionData.toString().split('\n');
        Assert.areEqual(12, lines.size(), 'Header plus one line per skipped row.');
        Assert.areEqual('Row,' + headerRow().trim() + ',Error', lines[0]);
        Assert.isTrue(lines[2].startsWith('3,Tech,Ref,NOPE2707,'));
        Assert.isTrue(lines[2].endsWith('No active Service Resource found for HRIS ID NOPE2707.'));
    }

    @IsTest
    static void processUpload_matchesTechOnlyByServiceResourceExternalId() {
        Id documentId = insertCsv(
            headerRow() + csvRow(TECH_USER_ONLY_HRIS, CURRENT_TERRITORY, ASM_A_HRIS, NEXT_TERRITORY, ASM_B_HRIS)
        );

        Test.startTest();
        TechDistrictAlignmentService.ProcessResult result = TechDistrictAlignmentController.processUpload(documentId);
        Test.stopTest();

        Assert.areEqual(0, result.movedCount);
        Assert.areEqual(1, result.skippedCount);
        Assert.isTrue(
            containsMessage(result.errors, 'Invalid HRIS ID for Tech: No active Service Resource found for HRIS ID ' + TECH_USER_ONLY_HRIS),
            'A User Employee Number alone must not identify the technician.'
        );
    }

    @IsTest
    static void processUpload_rejectsConflictingAsmForSameNewTerritory() {
        Id documentId = insertCsv(
            headerRow() +
            csvRow(TECH_ONE_HRIS, CURRENT_TERRITORY, ASM_A_HRIS, NEW_TERRITORY, ASM_A_HRIS) +
            csvRow(TECH_TWO_HRIS, CURRENT_TERRITORY, ASM_A_HRIS, NEW_TERRITORY, ASM_B_HRIS)
        );

        Test.startTest();
        TechDistrictAlignmentService.ProcessResult result = TechDistrictAlignmentController.processUpload(documentId);
        Test.stopTest();

        Assert.areEqual(1, result.territoryCreatedCount);
        Assert.areEqual(1, result.movedCount);
        Assert.areEqual(1, result.skippedCount);
        Assert.isTrue(containsMessage(result.errors, 'Row 3: Next Year ASM HRIS ID is invalid: Territory S2707NEW has a different Next Year ASM'));
        Assert.areEqual(userIdByHris(ASM_A_HRIS), [SELECT TerritoryManager__c FROM ServiceTerritory WHERE RegionNumber__c = :NEW_TERRITORY].TerritoryManager__c);
    }

    @IsTest
    static void processUpload_rerunIsUnchanged() {
        String body = headerRow() + csvRow(TECH_ONE_HRIS, CURRENT_TERRITORY, ASM_A_HRIS, NEXT_TERRITORY, ASM_B_HRIS);
        TechDistrictAlignmentController.processUpload(insertCsv(body));

        Test.startTest();
        TechDistrictAlignmentService.ProcessResult second = TechDistrictAlignmentController.processUpload(insertCsv(body));
        Test.stopTest();

        Assert.areEqual(0, second.skippedCount, String.join(second.errors, '\n'));
        Assert.areEqual(0, second.movedCount);
        Assert.areEqual(0, second.managerUpdatedCount);
        Assert.areEqual(1, second.unchangedCount);
        Assert.areEqual(
            1,
            [SELECT COUNT() FROM ServiceTerritoryMember WHERE ServiceTerritory.RegionNumber__c = :NEXT_TERRITORY AND ServiceResource.Name = 'GW2707 Tech One']
        );
    }

    @IsTest
    static void processUpload_readsExcelWithNumericHris() {
        List<String> header = headerRow().trim().split(',');
        Blob workbook = buildXlsx(
            new List<List<String>>{
                header,
                new List<String>{ 'Tech', 'Two', TECH_TWO_HRIS + '.0', CURRENT_TERRITORY, 'Asm A', ASM_A_HRIS, NEXT_TERRITORY, 'Asm A', ASM_A_HRIS }
            }
        );

        Test.startTest();
        TechDistrictAlignmentService.ProcessResult result = TechDistrictAlignmentController.processUpload(insertFile('gw2707.xlsx', workbook));
        Test.stopTest();

        Assert.areEqual(1, result.processedCount);
        Assert.areEqual(1, result.movedCount, String.join(result.errors, '\n'));
        Assert.areEqual(0, result.managerUpdatedCount, 'Same ASM next year leaves the manager alone.');
    }

    @IsTest
    static void processUpload_reusesErrorFileAcrossRuns() {
        TechDistrictAlignmentService.ProcessResult first = TechDistrictAlignmentController.processUpload(
            insertCsv(headerRow() + csvRow('NOPE2707', CURRENT_TERRITORY, ASM_A_HRIS, NEXT_TERRITORY, ASM_B_HRIS))
        );

        Test.startTest();
        TechDistrictAlignmentService.ProcessResult second = TechDistrictAlignmentController.processUpload(
            insertCsv(headerRow() + csvRow(TECH_ONE_HRIS, CURRENT_TERRITORY, ASM_A_HRIS, CURRENT_TERRITORY, ASM_A_HRIS))
        );
        Test.stopTest();

        Assert.areEqual(first.errorFileDocumentId, second.errorFileDocumentId);
        Assert.areEqual(2, [SELECT COUNT() FROM ContentVersion WHERE ContentDocumentId = :second.errorFileDocumentId]);
        Assert.areEqual(
            TechDistrictAlignmentService.DOWNLOAD_URL_PREFIX + second.errorFileDocumentId,
            TechDistrictAlignmentController.getErrorFileDownloadUrl()
        );
        FieldServiceBackofficeConfig__c userConfig = FieldServiceBackofficeConfig__c.getValues(UserInfo.getUserId());
        Assert.areEqual(String.valueOf(second.errorFileDocumentId), userConfig.TechDistrictAlignmentErrorFileId__c);
    }

    @IsTest
    static void getErrorFileDownloadUrl_throwsBeforeFirstUpload() {
        AuraHandledException thrown;
        try {
            TechDistrictAlignmentController.getErrorFileDownloadUrl();
        } catch (AuraHandledException e) {
            thrown = e;
        }
        Assert.isNotNull(thrown);
        Assert.isTrue(thrown.getMessage().contains('No error file yet'));
    }

    @IsTest
    static void getTemplateDownloadUrl_storesTemplateId() {
        Test.startTest();
        String url = TechDistrictAlignmentController.getTemplateDownloadUrl();
        String secondUrl = TechDistrictAlignmentController.getTemplateDownloadUrl();
        Test.stopTest();

        Assert.isTrue(url.startsWith(TechDistrictAlignmentService.DOWNLOAD_URL_PREFIX));
        Assert.areEqual(url, secondUrl);
        FieldServiceBackofficeConfig__c config = FieldServiceBackofficeConfig__c.getOrgDefaults();
        Assert.areEqual(url.removeStart(TechDistrictAlignmentService.DOWNLOAD_URL_PREFIX), config.TechDistrictAlignmentTemplateId__c);
    }

    @IsTest
    static void processUpload_throwsWhenFileMissingOrColumnsMissing() {
        AuraHandledException thrown;
        try {
            TechDistrictAlignmentController.processUpload(null);
        } catch (AuraHandledException e) {
            thrown = e;
        }
        Assert.isNotNull(thrown);
        Assert.isTrue(thrown.getMessage().contains('Upload a file'));

        thrown = null;
        try {
            TechDistrictAlignmentController.processUpload(insertCsv('TECH HRIS#,Current Territory\nA,B\n'));
        } catch (AuraHandledException e) {
            thrown = e;
        }
        Assert.isNotNull(thrown);
        Assert.isTrue(thrown.getMessage().contains('Next Year ASM HRIS#'));
    }

    @IsTest
    static void nextFiscalYearStart_isNextAprilFirst() {
        TechDistrictAlignmentService.runDate = Date.newInstance(2026, 11, 5);
        Assert.areEqual(Date.newInstance(2027, 4, 1), TechDistrictAlignmentService.nextFiscalYearStart());
        TechDistrictAlignmentService.runDate = Date.newInstance(2027, 2, 10);
        Assert.areEqual(Date.newInstance(2027, 4, 1), TechDistrictAlignmentService.nextFiscalYearStart());
        TechDistrictAlignmentService.runDate = Date.newInstance(2027, 4, 1);
        Assert.areEqual(Date.newInstance(2028, 4, 1), TechDistrictAlignmentService.nextFiscalYearStart());
    }

    @IsTest
    static void controller_wrapsUnexpectedErrors() {
        TechDistrictAlignmentController.throwTestException = true;
        List<String> messages = new List<String>();
        try {
            TechDistrictAlignmentController.getTemplateDownloadUrl();
        } catch (AuraHandledException e) {
            messages.add(e.getMessage());
        }
        try {
            TechDistrictAlignmentController.getErrorFileDownloadUrl();
        } catch (AuraHandledException e) {
            messages.add(e.getMessage());
        }
        try {
            TechDistrictAlignmentController.processUpload(UserInfo.getUserId());
        } catch (AuraHandledException e) {
            messages.add(e.getMessage());
        }
        Assert.areEqual(3, messages.size());
        Assert.isTrue(containsMessage(messages, 'Unable to resolve the Tech District Alignment template'));
        Assert.isTrue(containsMessage(messages, 'Unable to resolve the Tech District Alignment error file'));
        Assert.isTrue(containsMessage(messages, 'Unable to process'));
    }

    @IsTest
    static void selector_handlesBlankInputs() {
        Assert.areEqual(0, TechDistrictAlignmentSelector.selectActiveUsersByEmployeeNumbers(null).size());
        Assert.areEqual(0, TechDistrictAlignmentSelector.selectActiveResourcesByExternalIds(new Set<String>()).size());
        Assert.areEqual(0, TechDistrictAlignmentSelector.selectTerritoriesByRegionNumbers(new Set<String>()).size());
        Assert.areEqual(0, TechDistrictAlignmentSelector.selectOpenMembers(null, new Set<Id>(), Datetime.now()).size());
        Assert.areEqual(0, TechDistrictAlignmentSelector.selectLatestVersion(null).size());
        Assert.areEqual(0, TechDistrictAlignmentSelector.selectDocumentsById(null).size());
        Assert.areEqual(0, TechDistrictAlignmentSelector.selectDocumentsByTitle(null).size());
        Assert.areEqual(0, TechDistrictAlignmentSelector.selectTemplateResource(null).size());
    }

    private static void assertCurrentMembershipsEnded(Integer expected) {
        List<ServiceTerritoryMember> currentMembers = [
            SELECT EffectiveEndDate
            FROM ServiceTerritoryMember
            WHERE ServiceTerritory.RegionNumber__c = :CURRENT_TERRITORY AND EffectiveEndDate != NULL
        ];
        Assert.areEqual(expected, currentMembers.size());
        for (ServiceTerritoryMember member : currentMembers) {
            Assert.areEqual(Date.today(), member.EffectiveEndDate.date(), 'Current membership ends today.');
        }
    }

    private static User newUser(String firstName, String suffix, String employeeNumber) {
        String unique = String.valueOf(Math.abs(Crypto.getRandomInteger())) + suffix;
        String username = 'gw2707.' + unique + '@example.invalid';
        return new User(
            FirstName = firstName,
            LastName = 'Twosevenzeroseven',
            Alias = ('g' + unique).left(8),
            Email = username,
            Username = username,
            CommunityNickname = ('gw2707' + unique).left(40),
            EmployeeNumber__c = employeeNumber,
            ProfileId = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1].Id,
            TimeZoneSidKey = 'America/New_York',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US'
        );
    }

    private static ServiceTerritory district(String name, String regionNumber, Id zoneId, Id hoursId, Id managerId) {
        return new ServiceTerritory(
            Name = name,
            RegionNumber__c = regionNumber,
            TerritoryType__c = 'IPTLS',
            ParentTerritoryId = zoneId,
            OperatingHoursId = hoursId,
            TerritoryManager__c = managerId,
            IsActive = true
        );
    }

    private static Id territoryId(String regionNumber) {
        return [SELECT Id FROM ServiceTerritory WHERE RegionNumber__c = :regionNumber].Id;
    }

    private static Id userIdByHris(String employeeNumber) {
        return [SELECT Id FROM User WHERE EmployeeNumber__c = :employeeNumber LIMIT 1].Id;
    }

    private static String headerRow() {
        return 'Last Name,First Name,TECH HRIS#,Current Territory,Current ASM,Current ASM HRIS#,' +
            'Next Year Territory,Next Year ASM Name,Next Year ASM HRIS#\n';
    }

    /**
     * @description One template row; the name columns are reference-only placeholder text.
     */
    private static String csvRow(
        String techHris,
        String currentTerritory,
        String currentAsmHris,
        String nextTerritory,
        String nextAsmHris
    ) {
        return String.join(
            new List<String>{
                'Tech',
                'Ref',
                techHris,
                currentTerritory,
                'Ref ASM',
                currentAsmHris,
                nextTerritory,
                'Ref Next ASM',
                nextAsmHris
            },
            ','
        ) + '\n';
    }

    private static Id insertCsv(String csvBody) {
        return insertFile('gw2707.csv', Blob.valueOf(csvBody));
    }

    /**
     * @description Minimal .xlsx (first worksheet only) with every non-blank cell as an inline string.
     */
    private static Blob buildXlsx(List<List<String>> rows) {
        String columnLetters = 'ABCDEFGHIJ';
        String sheet =
            '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>' +
            '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData>';
        for (Integer r = 0; r < rows.size(); r++) {
            sheet += '<row r="' + (r + 1) + '">';
            for (Integer c = 0; c < rows[r].size(); c++) {
                if (String.isNotBlank(rows[r][c])) {
                    String cellRef = columnLetters.substring(c, c + 1) + (r + 1);
                    sheet += '<c r="' + cellRef + '" t="inlineStr"><is><t>' + rows[r][c].escapeXml() + '</t></is></c>';
                }
            }
            sheet += '</row>';
        }
        sheet += '</sheetData></worksheet>';

        Compression.ZipWriter writer = new Compression.ZipWriter();
        writer.addEntry('xl/worksheets/sheet1.xml', Blob.valueOf(sheet));
        return writer.getArchive();
    }

    private static Id insertFile(String pathOnClient, Blob versionData) {
        ContentVersion version = new ContentVersion(
            Title = 'GW2707 Upload',
            PathOnClient = pathOnClient,
            VersionData = versionData,
            IsMajorVersion = true
        );
        insert version;
        return [
            SELECT ContentDocumentId
            FROM ContentVersion
            WHERE Id = :version.Id
        ].ContentDocumentId;
    }

    private static Boolean containsMessage(List<String> messages, String fragment) {
        if (messages == null) {
            return false;
        }
        for (String message : messages) {
            if (message != null && message.contains(fragment)) {
                return true;
            }
        }
        return false;
    }
}