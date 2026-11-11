/**
 * @author Sagar Anand
 * @date 2026-11-06
 * @group Field Service Backoffice
 * @description GW-2706: Tests for District Zone Alignment (DistrictZoneAlignmentController and
 *              DistrictZoneAlignmentService). Runs as a Standard User with the FieldServiceBackofficeTool
 *              permission set and uploads real .xlsx files.
 */
@IsTest
private class DistrictZoneAlignmentControllerTest {
	private static final String BACKOFFICE_LAST_NAME = 'Backoffice2706';
	private static final String VAN_REGION_ZONE = 'Z2706-VR';
	private static final String TYPE_ZONE = 'Z2706-ZN';
	private static final String IPTLS_TERRITORY = 'I2706-1';
	private static final String DISTRICT_ONE = 'D2706-1';
	private static final String DISTRICT_TWO = 'D2706-2';
	private static final String ASM_NAME = 'Gwasm Twosevenzerosix';
	private static final String DUPLICATE_ASM_NAME = 'Gwdup Twosevenzerosix';
	private static final List<String> HEADER = new List<String>{
		'Current District #',
		'Current District Name',
		'Current Zone #',
		'Current Zone Name',
		'Future District #',
		'Future ASM Names',
		'Future District Name',
		'Future Zone #',
		'Zone Name'
	};

	@TestSetup
	static void setupData() {
		// SETUP: back-office users and ASM users. Back-office users are Standard Users with the tool's permission
		// set plus Field Service Admin Permissions, which the managed territory trigger needs to save territories.
		System.runAs(new User(Id = UserInfo.getUserId())) {
			Id standardProfileId = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1].Id;
			List<PermissionSet> permissionSetList = [
				SELECT Id
				FROM PermissionSet
				WHERE Name IN ('FieldServiceBackofficeTool', 'FSL_Admin_Permissions')
			];
			for (Integer i = 0; i < 2; i++) {
				User backofficeUser = (User) new adb_User()
					.firstName('Office' + i)
					.lastName(BACKOFFICE_LAST_NAME)
					.alias('bo2706' + i)
					.username(uniqueUsername('backoffice' + i))
					.profileId(standardProfileId)
					.persist();
				for (PermissionSet permissionSet : permissionSetList) {
					new adb_PermissionSetAssignment()
						.assigneeId(backofficeUser.Id)
						.permissionSetId(permissionSet.Id)
						.persist();
				}
			}
			createAsm('Gwasm', 'asm');
			createAsm('Gwdup', 'dup1');
			createAsm('Gwdup', 'dup2');
		}

		// SETUP: zones (Van Region and Zone), an IPTLS territory and two districts
		OperatingHours hours = (OperatingHours) new adb_OperatingHours()
			.name('GW2706 Hours')
			.timeZone('America/New_York')
			.persist();
		ServiceTerritory vanRegion = territory('GW2706 Van Region', VAN_REGION_ZONE, 'Van Region', null, hours.Id);
		ServiceTerritory typeZone = territory('GW2706 Zone', TYPE_ZONE, 'Zone', null, hours.Id);
		Database.insert(new List<ServiceTerritory>{ vanRegion, typeZone }, AccessLevel.SYSTEM_MODE);
		Database.insert(
			new List<ServiceTerritory>{
				territory('GW2706 IPTLS', IPTLS_TERRITORY, 'IPTLS', vanRegion.Id, hours.Id),
				territory('GW2706 District One', DISTRICT_ONE, 'IPTLS', vanRegion.Id, hours.Id),
				territory('GW2706 District Two', DISTRICT_TWO, 'IPTLS', vanRegion.Id, hours.Id)
			},
			AccessLevel.SYSTEM_MODE
		);
	}

	@IsTest
	static void testProcessUploadCreatesDistrictUnderVanRegion() {
		// GIVEN
		User contextUser = backofficeUser(0);
		DistrictZoneAlignmentService.ProcessResult result;

		System.runAs(contextUser) {
			Id documentId = uploadWorkbook(new List<List<String>>{
				alignmentRow('-', 'D2706-NEW', ASM_NAME, 'SVC D2706 - (SC) East', VAN_REGION_ZONE)
			});

			// WHEN
			Test.startTest();
			result = DistrictZoneAlignmentController.processUpload(documentId);
			Test.stopTest();
		}

		// THEN
		Assert.areEqual(1, result.processedCount, 'One row should be processed.');
		Assert.areEqual(1, result.createdCount, 'The district should be created.');
		Assert.areEqual(0, result.skippedCount, 'No row should be skipped.');
		ServiceTerritory zone = territoryByNumber(VAN_REGION_ZONE);
		ServiceTerritory district = territoryByNumber('D2706-NEW');
		Assert.areEqual('SVC D2706 - (SC) East', district.Name, 'Future District Name should be the name.');
		Assert.areEqual(zone.Id, district.ParentTerritoryId, 'The Van Region should be the parent zone.');
		Assert.areEqual(zone.OperatingHoursId, district.OperatingHoursId, 'Operating Hours should come from the zone.');
		Assert.areEqual(asmUserId(), district.TerritoryManager__c, 'The Future ASM should be the manager.');
		Assert.isTrue(district.IsActive, 'The new district should be active.');
	}

	@IsTest
	static void testProcessUploadUpdatesManagerZoneNumberAndName() {
		// GIVEN
		User contextUser = backofficeUser(0);
		DistrictZoneAlignmentService.ProcessResult result;

		System.runAs(contextUser) {
			Id documentId = uploadWorkbook(new List<List<String>>{
				alignmentRow(DISTRICT_ONE, 'D2706-1B', ASM_NAME, 'GW2706 District One Renamed', TYPE_ZONE),
				alignmentRow(DISTRICT_TWO, DISTRICT_TWO, '', '', VAN_REGION_ZONE)
			});

			// WHEN
			Test.startTest();
			result = DistrictZoneAlignmentController.processUpload(documentId);
			Test.stopTest();
		}

		// THEN
		Assert.areEqual(2, result.processedCount, 'Both rows should be processed.');
		Assert.areEqual(1, result.updatedCount, 'District One should be updated.');
		Assert.areEqual(1, result.unchangedCount, 'District Two already matches the file.');
		Assert.areEqual(0, result.skippedCount, 'No row should be skipped.');
		ServiceTerritory district = territoryByNumber('D2706-1B');
		Assert.areEqual('GW2706 District One Renamed', district.Name, 'The district should be renamed.');
		Assert.areEqual(territoryByNumber(TYPE_ZONE).Id, district.ParentTerritoryId, 'The district should move zone.');
		Assert.areEqual(asmUserId(), district.TerritoryManager__c, 'The Future ASM should be the manager.');
	}

	@IsTest
	static void testProcessUploadSkipsInvalidRowsIntoErrorFile() {
		// GIVEN
		User contextUser = backofficeUser(0);
		DistrictZoneAlignmentService.ProcessResult result;
		ContentVersion errorFile;

		System.runAs(contextUser) {
			Id documentId = uploadWorkbook(new List<List<String>>{
				alignmentRow('-', '', '', '', VAN_REGION_ZONE),
				alignmentRow('-', 'D2706-X', '', '', ''),
				alignmentRow('-', 'D2706-X', '', '', 'NO-SUCH-ZONE'),
				alignmentRow('-', 'D2706-X', '', '', IPTLS_TERRITORY),
				alignmentRow('-', DISTRICT_ONE, '', '', VAN_REGION_ZONE),
				alignmentRow('-', 'D2706-Y', 'Nobody Twosevenzerosix', '', VAN_REGION_ZONE),
				alignmentRow('-', 'D2706-Z', DUPLICATE_ASM_NAME, '', VAN_REGION_ZONE),
				alignmentRow('NO-SUCH-DISTRICT', 'D2706-Q', '', '', VAN_REGION_ZONE),
				alignmentRow(DISTRICT_TWO, DISTRICT_ONE, '', '', VAN_REGION_ZONE),
				alignmentRow(VAN_REGION_ZONE, VAN_REGION_ZONE, '', '', VAN_REGION_ZONE),
				alignmentRow(DISTRICT_TWO, DISTRICT_TWO, '', '', VAN_REGION_ZONE),
				alignmentRow(DISTRICT_TWO, DISTRICT_TWO, '', '', VAN_REGION_ZONE)
			});

			// WHEN
			Test.startTest();
			result = DistrictZoneAlignmentController.processUpload(documentId);
			Test.stopTest();

			errorFile = [
				SELECT VersionData
				FROM ContentVersion
				WHERE ContentDocumentId = :result.errorFileDocumentId AND IsLatest = TRUE
			];
		}

		// THEN
		Assert.areEqual(12, result.processedCount, 'Every non-blank row should be processed.');
		Assert.areEqual(0, result.createdCount + result.updatedCount, 'Nothing should be saved.');
		Assert.areEqual(1, result.unchangedCount, 'The first District Two row already matches.');
		Assert.areEqual(11, result.skippedCount, 'Eleven rows are invalid.');
		assertHasError(result.errors, 'Row 2: Invalid future district#: Future District # is required.');
		assertHasError(result.errors, 'Row 3: Invalid future zone#: Future Zone # is required.');
		assertHasError(result.errors, 'Row 4: Invalid future zone#: No Van Region or Zone territory found');
		assertHasError(result.errors, 'Row 5: Invalid future zone#: No Van Region or Zone territory found');
		assertHasError(result.errors, 'Row 6: Invalid future district#: District # D2706-1 already exists');
		assertHasError(result.errors, 'Row 7: Invalid future ASM: No active user found');
		assertHasError(result.errors, 'Row 8: Invalid future ASM: More than one active user');
		assertHasError(result.errors, 'Row 9: Invalid current district#: No territory found');
		assertHasError(result.errors, 'Row 10: Invalid future district#: District # D2706-1 is already used');
		assertHasError(result.errors, 'Row 11: Invalid future zone#: A district cannot be its own zone.');
		assertHasError(result.errors, 'Row 13: Invalid current district#: District # D2706-2 appears more');

		List<String> lineList = errorFile.VersionData.toString().split('\n');
		Assert.areEqual(12, lineList.size(), 'The error file should have a header and one line per skipped row.');
		Assert.areEqual('Row,' + String.join(HEADER, ',') + ',Error', lineList[0], 'Unexpected error file header.');
		Assert.isTrue(lineList[3].startsWith('4,-,'), 'Row 4 should keep the uploaded values.');
		Assert.isTrue(lineList[3].endsWith('found with Zone # NO-SUCH-ZONE.'), 'Row 4 should end with its error.');
	}

	@IsTest
	static void testProcessUploadReusesErrorFileAcrossRuns() {
		// GIVEN
		User contextUser = backofficeUser(0);
		DistrictZoneAlignmentService.ProcessResult first;
		DistrictZoneAlignmentService.ProcessResult second;
		String downloadUrl;
		Integer versionCount;

		System.runAs(contextUser) {
			first = DistrictZoneAlignmentController.processUpload(
				uploadWorkbook(new List<List<String>>{ alignmentRow('-', '', '', '', VAN_REGION_ZONE) })
			);
			Id secondDocumentId = uploadWorkbook(new List<List<String>>{
				alignmentRow(DISTRICT_TWO, DISTRICT_TWO, '', '', VAN_REGION_ZONE)
			});

			// WHEN
			Test.startTest();
			second = DistrictZoneAlignmentController.processUpload(secondDocumentId);
			downloadUrl = DistrictZoneAlignmentController.getErrorFileDownloadUrl();
			Test.stopTest();

			versionCount = [SELECT COUNT() FROM ContentVersion WHERE ContentDocumentId = :second.errorFileDocumentId];
		}

		// THEN
		Assert.areEqual(first.errorFileDocumentId, second.errorFileDocumentId, 'Both runs should use one error file.');
		Assert.areEqual(2, versionCount, 'Each run should add a version to the error file.');
		Assert.areEqual(
			DistrictZoneAlignmentService.DOWNLOAD_URL_PREFIX + second.errorFileDocumentId,
			downloadUrl,
			'Download Error File should open the latest error file.'
		);
		Assert.areEqual(
			String.valueOf(second.errorFileDocumentId),
			FieldServiceBackofficeConfig__c.getValues(contextUser.Id).DistrictZoneAlignmentErrorFileId__c,
			'The error file Id should be stored on the user setting.'
		);
	}

	@IsTest
	static void testProcessUploadCreatesDistrictsInBulk() {
		// GIVEN
		User contextUser = backofficeUser(0);
		DistrictZoneAlignmentService.ProcessResult result;
		List<List<String>> rowList = new List<List<String>>();
		for (Integer i = 0; i < 200; i++) {
			rowList.add(alignmentRow('-', 'B2706-' + i, '', 'GW2706 Bulk ' + i, VAN_REGION_ZONE));
		}

		System.runAs(contextUser) {
			Id documentId = uploadWorkbook(rowList);

			// WHEN
			Test.startTest();
			result = DistrictZoneAlignmentController.processUpload(documentId);
			Test.stopTest();
		}

		// THEN
		Assert.areEqual(200, result.createdCount, 'All 200 districts should be created.');
		Assert.areEqual(0, result.skippedCount, 'No row should be skipped.');
		Assert.areEqual(
			200,
			[SELECT COUNT() FROM ServiceTerritory WHERE RegionNumber__c LIKE 'B2706-%'],
			'All 200 districts should exist.'
		);
	}

	@IsTest
	static void testProcessUploadRejectsMissingOrUnreadableFiles() {
		// GIVEN
		User contextUser = backofficeUser(0);
		List<String> messageList = new List<String>();
		List<List<String>> tooManyRows = new List<List<String>>();
		for (Integer i = 0; i <= DistrictZoneAlignmentService.MAX_ROWS; i++) {
			tooManyRows.add(new List<String>{ 'T' + i });
		}

		System.runAs(contextUser) {
			Id csvDocumentId = uploadFile('districts.csv', Blob.valueOf(String.join(HEADER, ',')));
			Id corruptDocumentId = uploadFile('districts.xlsx', Blob.valueOf('not a workbook'));
			Id missingColumnsDocumentId = uploadFile(
				'districts.xlsx',
				workbook(new List<List<String>>{ new List<String>{ 'Current District #', 'Future District #' } })
			);
			Id tooManyRowsDocumentId = uploadWorkbook(tooManyRows);

			// WHEN
			Test.startTest();
			for (Id documentId : new List<Id>{
				null,
				csvDocumentId,
				corruptDocumentId,
				missingColumnsDocumentId,
				tooManyRowsDocumentId
			}) {
				try {
					DistrictZoneAlignmentController.processUpload(documentId);
				} catch (AuraHandledException e) {
					messageList.add(e.getMessage());
				}
			}
			Test.stopTest();
		}

		// THEN
		Assert.areEqual(5, messageList.size(), 'Every file should be rejected.');
		Assert.areEqual(Label.DZA_FileRequired, messageList[0], 'A missing file should be rejected.');
		Assert.areEqual(Label.DZA_FileUnreadable, messageList[1], 'A CSV file should be rejected.');
		Assert.areEqual(Label.DZA_FileUnreadable, messageList[2], 'A corrupt workbook should be rejected.');
		Assert.isTrue(messageList[3].contains('Future ASM Names, Future Zone #'), 'Missing columns should be listed.');
		Assert.isTrue(
			messageList[4].contains('2,000') || messageList[4].contains('2000'),
			'The row limit should be named.'
		);
	}

	@IsTest
	static void testGetErrorFileDownloadUrlBeforeFirstUpload() {
		// GIVEN
		User contextUser = backofficeUser(0);
		AuraHandledException thrown;

		// WHEN
		System.runAs(contextUser) {
			try {
				DistrictZoneAlignmentController.getErrorFileDownloadUrl();
			} catch (AuraHandledException e) {
				thrown = e;
			}
		}

		// THEN
		Assert.isNotNull(thrown, 'An exception should be thrown.');
		Assert.areEqual(Label.DZA_NoErrorFile, thrown.getMessage(), 'The user should be told to upload first.');
	}

	@IsTest
	static void testGetTemplateDownloadUrlSharesOneTemplateWithAllUsers() {
		// GIVEN
		String firstUrl;
		String secondUrl;

		// WHEN
		Test.startTest();
		System.runAs(backofficeUser(0)) {
			firstUrl = DistrictZoneAlignmentController.getTemplateDownloadUrl();
		}
		System.runAs(backofficeUser(1)) {
			secondUrl = DistrictZoneAlignmentController.getTemplateDownloadUrl();
		}
		Test.stopTest();

		// THEN
		Id templateId = FieldServiceBackofficeConfig__c.getOrgDefaults().DistrictZoneAlignmentTemplateId__c;
		String expectedUrl = DistrictZoneAlignmentService.DOWNLOAD_URL_PREFIX + templateId;
		Assert.areEqual(expectedUrl, firstUrl, 'Unexpected template URL.');
		Assert.areEqual(firstUrl, secondUrl, 'Every user should get the same template.');
		Assert.areEqual(
			1,
			[
				SELECT COUNT()
				FROM ContentDocumentLink
				WHERE ContentDocumentId = :templateId AND LinkedEntityId = :UserInfo.getOrganizationId()
			],
			'The template should be shared with all internal users.'
		);
		ContentVersion template = [
			SELECT FileExtension, VersionData
			FROM ContentVersion
			WHERE ContentDocumentId = :templateId AND IsLatest = TRUE
		];
		Assert.areEqual('xlsx', template.FileExtension, 'The template should be an Excel file.');
		List<String> templateHeader = ExcelFileParser.readFirstSheet(template.VersionData)[0];
		Assert.areEqual(HEADER, templateHeader, 'Unexpected template columns.');
	}

	private static void createAsm(String firstName, String key) {
		new adb_User()
			.firstName(firstName)
			.lastName('Twosevenzerosix')
			.alias(('a' + key).left(8))
			.username(uniqueUsername(key))
			.persist();
	}

	private static String uniqueUsername(String key) {
		return 'gw2706.' + key + '.' + UserInfo.getOrganizationId() + '@example.com.invalid';
	}

	private static ServiceTerritory territory(String name, String regionNumber, String type, Id parentId, Id hoursId) {
		return new ServiceTerritory(
			Name = name,
			RegionNumber__c = regionNumber,
			TerritoryType__c = type,
			ParentTerritoryId = parentId,
			OperatingHoursId = hoursId,
			IsActive = true
		);
	}

	private static User backofficeUser(Integer index) {
		return [
			SELECT Id
			FROM User
			WHERE LastName = :BACKOFFICE_LAST_NAME AND FirstName = :('Office' + index)
			LIMIT 1
		];
	}

	private static Id asmUserId() {
		return [SELECT Id FROM User WHERE Name = :ASM_NAME AND IsActive = TRUE LIMIT 1].Id;
	}

	private static ServiceTerritory territoryByNumber(String regionNumber) {
		return [
			SELECT Id, Name, ParentTerritoryId, TerritoryManager__c, OperatingHoursId, IsActive
			FROM ServiceTerritory
			WHERE RegionNumber__c = :regionNumber
		];
	}

	/**
	 * @description One template row. Reference columns are "-" for new districts and placeholder text otherwise.
	 */
	private static List<String> alignmentRow(
		String currentDistrict,
		String futureDistrict,
		String futureAsm,
		String futureDistrictName,
		String futureZone
	) {
		String reference = currentDistrict == '-' ? '-' : 'Ref';
		return new List<String>{
			currentDistrict,
			reference,
			reference,
			reference,
			futureDistrict,
			futureAsm,
			futureDistrictName,
			futureZone,
			'Zone Ref'
		};
	}

	private static Id uploadWorkbook(List<List<String>> dataRows) {
		List<List<String>> rowList = new List<List<String>>{ HEADER };
		rowList.addAll(dataRows);
		return uploadFile('districts.xlsx', workbook(rowList));
	}

	/**
	 * @description Minimal .xlsx with one worksheet of inline strings, as read by ExcelFileParser.
	 */
	private static Blob workbook(List<List<String>> rowList) {
		List<String> xmlList = new List<String>{ '<worksheet><sheetData>' };
		for (Integer r = 0; r < rowList.size(); r++) {
			xmlList.add('<row r="' + (r + 1) + '">');
			for (Integer c = 0; c < rowList[r].size(); c++) {
				if (String.isNotBlank(rowList[r][c])) {
					String cellRef = String.fromCharArray(new List<Integer>{ 65 + c }) + (r + 1);
					xmlList.add(
						'<c r="' + cellRef + '" t="inlineStr"><is><t>' + rowList[r][c].escapeXml() + '</t></is></c>'
					);
				}
			}
			xmlList.add('</row>');
		}
		xmlList.add('</sheetData></worksheet>');
		Compression.ZipWriter writer = new Compression.ZipWriter();
		writer.addEntry('xl/worksheets/sheet1.xml', Blob.valueOf(String.join(xmlList, '')));
		return writer.getArchive();
	}

	private static Id uploadFile(String fileName, Blob body) {
		ContentVersion version = new ContentVersion(
			Title = 'GW2706 Upload',
			PathOnClient = fileName,
			VersionData = body
		);
		insert version;
		return [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :version.Id].ContentDocumentId;
	}

	private static void assertHasError(List<String> errorList, String expectedStart) {
		for (String message : errorList) {
			if (message.startsWith(expectedStart)) {
				return;
			}
		}
		Assert.fail('Expected an error starting with "' + expectedStart + '" in ' + errorList);
	}
}