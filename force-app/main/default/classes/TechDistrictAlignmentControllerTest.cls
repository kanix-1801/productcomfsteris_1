/**
 * @author Sagar Anand
 * @date 2026-11-05
 * @description GW-2707: Tests for Tech District Alignment upload, error file, template download and row rules.
 * @group Field Service
 * @see TechDistrictAlignmentController
 * @see TechDistrictAlignmentService
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
	private static final String BULK_TECH_PREFIX = 'GW2707B';
	private static final Integer BULK_SIZE = 200;

	/**
	 * @description Two technicians in the current IPTLS district under a zone, a second existing district,
	 *              two ASMs, and a technician user whose Employee Number must not identify the technician.
	 */
	@TestSetup
	static void setupData() {
		adb_User techOne = userBuilder('Gwtechone', TECH_USER_ONLY_HRIS);
		adb_User techTwo = userBuilder('Gwtechtwo', null);
		adb_User asmA = userBuilder('Gwasma', ASM_A_HRIS);
		adb_User asmB = userBuilder('Gwasmb', ASM_B_HRIS);
		System.runAs(new User(Id = UserInfo.getUserId())) {
			adb_DomainBuilder.save();
		}

		OperatingHours hours = (OperatingHours) new adb_OperatingHours().name('GW2707 Hours').persist();

		ServiceTerritory zone = new ServiceTerritory(
			Name = 'GW2707 Zone',
			RegionNumber__c = ZONE_TERRITORY,
			TerritoryType__c = 'Zone',
			OperatingHoursId = hours.Id,
			IsActive = true
		);
		insert zone;
		insert new List<ServiceTerritory>{
			district('GW2707 Current', CURRENT_TERRITORY, zone.Id, hours.Id, asmA.id),
			district('GW2707 Next', NEXT_TERRITORY, zone.Id, hours.Id, asmA.id)
		};

		ServiceResource resourceOne = technician('GW2707 Tech One', techOne.id, TECH_ONE_HRIS);
		ServiceResource resourceTwo = technician('GW2707 Tech Two', techTwo.id, TECH_TWO_HRIS);
		insert new List<ServiceResource>{ resourceOne, resourceTwo };

		Id currentId = territoryId(CURRENT_TERRITORY);
		insert new List<ServiceTerritoryMember>{
			currentMembership(resourceOne.Id, currentId),
			currentMembership(resourceTwo.Id, currentId)
		};
	}

	/**
	 * @description A Next Year Territory that does not exist is created from the current territory with the
	 *              Next Year ASM as manager; both technicians move to it from April 1 and their current
	 *              membership ends today.
	 */
	@IsTest
	static void processUpload_createsNextYearTerritoryAndMovesTechs() {
		/*******************************************
		 * SETUP
		 *******************************************/
		User contextUser = new User(Id = UserInfo.getUserId());
		Id documentId = insertCsv(
			headerRow() +
			csvRow(TECH_ONE_HRIS, CURRENT_TERRITORY, ASM_A_HRIS, NEW_TERRITORY, ASM_B_HRIS) +
			csvRow(TECH_TWO_HRIS, CURRENT_TERRITORY, ASM_A_HRIS, NEW_TERRITORY, ASM_B_HRIS)
		);

		/*******************************************
		 * GIVEN
		 *******************************************/
		Assert.areEqual(0, [SELECT COUNT() FROM ServiceTerritory WHERE RegionNumber__c = :NEW_TERRITORY]);
		assertCurrentMembershipsEnded(0);

		/*******************************************
		 * WHEN
		 *******************************************/
		TechDistrictAlignmentService.ProcessResult result;
		Test.startTest();
		System.runAs(contextUser) {
			result = TechDistrictAlignmentController.processUpload(documentId);
		}
		Test.stopTest();

		/*******************************************
		 * THEN
		 *******************************************/
		Assert.areEqual(2, result.processedCount);
		Assert.areEqual(1, result.territoryCreatedCount, 'Both rows share one new territory.');
		Assert.areEqual(2, result.movedCount);
		Assert.areEqual(0, result.skippedCount, String.join(result.errors, '\n'));
		Assert.areEqual(PlatformUtilities.nextFiscalYearStart(Date.today()), result.nextFiscalYearStart);

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
			Assert.areEqual(nextFiscalYearStartMidnight(), member.EffectiveStartDate);
			Assert.areEqual('P', member.TerritoryType);
		}
		assertCurrentMembershipsEnded(2);
	}

	/**
	 * @description Moving to an existing territory with a different Next Year ASM updates its Territory Manager.
	 */
	@IsTest
	static void processUpload_movesToExistingTerritoryAndUpdatesManager() {
		/*******************************************
		 * SETUP
		 *******************************************/
		User contextUser = new User(Id = UserInfo.getUserId());
		Id documentId = insertCsv(
			headerRow() + csvRow(TECH_ONE_HRIS, CURRENT_TERRITORY, ASM_A_HRIS, NEXT_TERRITORY, ASM_B_HRIS)
		);

		/*******************************************
		 * GIVEN
		 *******************************************/
		Assert.areEqual(userIdByHris(ASM_A_HRIS), managerOf(NEXT_TERRITORY));
		Assert.areEqual(0, nextTerritoryMemberCount('GW2707 Tech One'));

		/*******************************************
		 * WHEN
		 *******************************************/
		TechDistrictAlignmentService.ProcessResult result;
		Test.startTest();
		System.runAs(contextUser) {
			result = TechDistrictAlignmentController.processUpload(documentId);
		}
		Test.stopTest();

		/*******************************************
		 * THEN
		 *******************************************/
		Assert.areEqual(1, result.movedCount);
		Assert.areEqual(1, result.managerUpdatedCount);
		Assert.areEqual(0, result.territoryCreatedCount);
		Assert.areEqual(0, result.skippedCount, String.join(result.errors, '\n'));
		Assert.areEqual(userIdByHris(ASM_B_HRIS), managerOf(NEXT_TERRITORY));
		ServiceTerritoryMember nextMember = [
			SELECT EffectiveStartDate
			FROM ServiceTerritoryMember
			WHERE ServiceTerritory.RegionNumber__c = :NEXT_TERRITORY AND ServiceResource.Name = 'GW2707 Tech One'
		];
		Assert.areEqual(nextFiscalYearStartMidnight(), nextMember.EffectiveStartDate);
		assertCurrentMembershipsEnded(1);
	}

	/**
	 * @description Staying in the same territory changes only the Territory Manager when the ASM changes,
	 *              and nothing otherwise.
	 */
	@IsTest
	static void processUpload_sameTerritoryUpdatesManagerOrDoesNothing() {
		/*******************************************
		 * SETUP
		 *******************************************/
		User contextUser = new User(Id = UserInfo.getUserId());
		Id documentId = insertCsv(
			headerRow() +
			csvRow(TECH_ONE_HRIS, CURRENT_TERRITORY, ASM_A_HRIS, CURRENT_TERRITORY, ASM_A_HRIS) +
			csvRow(TECH_TWO_HRIS, CURRENT_TERRITORY, ASM_A_HRIS, CURRENT_TERRITORY, ASM_B_HRIS)
		);

		/*******************************************
		 * GIVEN
		 *******************************************/
		Assert.areEqual(userIdByHris(ASM_A_HRIS), managerOf(CURRENT_TERRITORY));
		Assert.areEqual(2, [SELECT COUNT() FROM ServiceTerritoryMember WHERE EffectiveEndDate = NULL]);

		/*******************************************
		 * WHEN
		 *******************************************/
		TechDistrictAlignmentService.ProcessResult result;
		Test.startTest();
		System.runAs(contextUser) {
			result = TechDistrictAlignmentController.processUpload(documentId);
		}
		Test.stopTest();

		/*******************************************
		 * THEN
		 *******************************************/
		Assert.areEqual(0, result.movedCount);
		Assert.areEqual(1, result.managerUpdatedCount);
		Assert.areEqual(1, result.unchangedCount);
		Assert.areEqual(0, result.skippedCount, String.join(result.errors, '\n'));
		Assert.areEqual(userIdByHris(ASM_B_HRIS), managerOf(CURRENT_TERRITORY));
		Assert.areEqual(2, [SELECT COUNT() FROM ServiceTerritoryMember WHERE EffectiveEndDate = NULL]);
		assertCurrentMembershipsEnded(0);
	}

	/**
	 * @description Every validation rule skips its row with the documented message, and the error file
	 *              repeats the uploaded columns with the row number first and the error last.
	 */
	@IsTest
	static void processUpload_skipsInvalidRowsIntoErrorFile() {
		/*******************************************
		 * SETUP
		 *******************************************/
		User contextUser = new User(Id = UserInfo.getUserId());
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

		/*******************************************
		 * GIVEN
		 *******************************************/
		Assert.isNull(FieldServiceBackofficeConfig__c.getValues(UserInfo.getUserId()), 'No error file yet.');
		Assert.areEqual(0, [SELECT COUNT() FROM ServiceTerritory WHERE RegionNumber__c = :NEW_TERRITORY]);

		/*******************************************
		 * WHEN
		 *******************************************/
		TechDistrictAlignmentService.ProcessResult result;
		Test.startTest();
		System.runAs(contextUser) {
			result = TechDistrictAlignmentController.processUpload(documentId);
		}
		Test.stopTest();

		/*******************************************
		 * THEN
		 *******************************************/
		Assert.areEqual(12, result.processedCount);
		Assert.areEqual(1, result.movedCount);
		Assert.areEqual(1, result.managerUpdatedCount);
		Assert.areEqual(11, result.skippedCount);
		Assert.isTrue(containsMessage(result.errors, 'Row 2: Invalid HRIS ID for Tech: TECH HRIS# is required'));
		Assert.isTrue(
			containsMessage(
				result.errors,
				'Invalid HRIS ID for Tech: No active Service Resource found for HRIS ID NOPE2707'
			)
		);
		Assert.isTrue(containsMessage(result.errors, 'Invalid Current Territory: No service territory found'));
		Assert.isTrue(containsMessage(result.errors, 'Invalid Current Territory: Territory Z2707 has type Zone'));
		Assert.isTrue(containsMessage(result.errors, 'Service Resource is not assigned to service territory S2707NXT'));
		Assert.isTrue(containsMessage(result.errors, 'Current ASM HRIS ID is invalid: No active user found'));
		Assert.isTrue(containsMessage(result.errors, 'Invalid Next Year Territory: Next Year Territory is required'));
		Assert.isTrue(containsMessage(result.errors, 'Next Year ASM HRIS ID is invalid: No active user found'));
		Assert.isTrue(containsMessage(result.errors, 'required to create territory S2707NEW'));
		Assert.isTrue(containsMessage(result.errors, 'Invalid Next Year Territory: Territory Z2707 has type Zone'));
		Assert.isTrue(
			containsMessage(
				result.errors,
				'Row 13: Invalid HRIS ID for Tech: Technician GW2707T1 appears more than once'
			)
		);
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

	/**
	 * @description A User Employee Number alone must not identify the technician; only
	 *              ServiceResource.ExternalID__c does.
	 */
	@IsTest
	static void processUpload_matchesTechOnlyByServiceResourceExternalId() {
		/*******************************************
		 * SETUP
		 *******************************************/
		User contextUser = new User(Id = UserInfo.getUserId());
		Id documentId = insertCsv(
			headerRow() + csvRow(TECH_USER_ONLY_HRIS, CURRENT_TERRITORY, ASM_A_HRIS, NEXT_TERRITORY, ASM_B_HRIS)
		);

		/*******************************************
		 * GIVEN
		 *******************************************/
		Assert.isNotNull(userIdByHris(TECH_USER_ONLY_HRIS), 'A user carries the HRIS ID as Employee Number.');
		Assert.areEqual(0, [SELECT COUNT() FROM ServiceResource WHERE ExternalID__c = :TECH_USER_ONLY_HRIS]);

		/*******************************************
		 * WHEN
		 *******************************************/
		TechDistrictAlignmentService.ProcessResult result;
		Test.startTest();
		System.runAs(contextUser) {
			result = TechDistrictAlignmentController.processUpload(documentId);
		}
		Test.stopTest();

		/*******************************************
		 * THEN
		 *******************************************/
		Assert.areEqual(0, result.movedCount);
		Assert.areEqual(1, result.skippedCount);
		Assert.isTrue(
			containsMessage(
				result.errors,
				'Invalid HRIS ID for Tech: No active Service Resource found for HRIS ID ' + TECH_USER_ONLY_HRIS
			),
			'A User Employee Number alone must not identify the technician.'
		);
	}

	/**
	 * @description Two rows creating the same new territory with different Next Year ASMs: the first wins,
	 *              the second is skipped.
	 */
	@IsTest
	static void processUpload_rejectsConflictingAsmForSameNewTerritory() {
		/*******************************************
		 * SETUP
		 *******************************************/
		User contextUser = new User(Id = UserInfo.getUserId());
		Id documentId = insertCsv(
			headerRow() +
			csvRow(TECH_ONE_HRIS, CURRENT_TERRITORY, ASM_A_HRIS, NEW_TERRITORY, ASM_A_HRIS) +
			csvRow(TECH_TWO_HRIS, CURRENT_TERRITORY, ASM_A_HRIS, NEW_TERRITORY, ASM_B_HRIS)
		);

		/*******************************************
		 * GIVEN
		 *******************************************/
		Assert.areEqual(0, [SELECT COUNT() FROM ServiceTerritory WHERE RegionNumber__c = :NEW_TERRITORY]);

		/*******************************************
		 * WHEN
		 *******************************************/
		TechDistrictAlignmentService.ProcessResult result;
		Test.startTest();
		System.runAs(contextUser) {
			result = TechDistrictAlignmentController.processUpload(documentId);
		}
		Test.stopTest();

		/*******************************************
		 * THEN
		 *******************************************/
		Assert.areEqual(1, result.territoryCreatedCount);
		Assert.areEqual(1, result.movedCount);
		Assert.areEqual(1, result.skippedCount);
		Assert.isTrue(
			containsMessage(
				result.errors,
				'Row 3: Next Year ASM HRIS ID is invalid: Territory S2707NEW has a different Next Year ASM'
			)
		);
		Assert.areEqual(userIdByHris(ASM_A_HRIS), managerOf(NEW_TERRITORY));
	}

	/**
	 * @description Uploading the same file twice does not create a second next-year membership.
	 */
	@IsTest
	static void processUpload_rerunIsUnchanged() {
		/*******************************************
		 * SETUP
		 *******************************************/
		User contextUser = new User(Id = UserInfo.getUserId());
		String body = headerRow() + csvRow(TECH_ONE_HRIS, CURRENT_TERRITORY, ASM_A_HRIS, NEXT_TERRITORY, ASM_B_HRIS);
		TechDistrictAlignmentController.processUpload(insertCsv(body));
		Id secondDocumentId = insertCsv(body);

		/*******************************************
		 * GIVEN
		 *******************************************/
		Assert.areEqual(1, nextTerritoryMemberCount('GW2707 Tech One'), 'The first run added the membership.');

		/*******************************************
		 * WHEN
		 *******************************************/
		TechDistrictAlignmentService.ProcessResult second;
		Test.startTest();
		System.runAs(contextUser) {
			second = TechDistrictAlignmentController.processUpload(secondDocumentId);
		}
		Test.stopTest();

		/*******************************************
		 * THEN
		 *******************************************/
		Assert.areEqual(0, second.skippedCount, String.join(second.errors, '\n'));
		Assert.areEqual(0, second.movedCount);
		Assert.areEqual(0, second.managerUpdatedCount);
		Assert.areEqual(1, second.unchangedCount);
		Assert.areEqual(1, nextTerritoryMemberCount('GW2707 Tech One'));
	}

	/**
	 * @description Excel files are read, and an HRIS number Excel stored as "992707002.0" still matches.
	 */
	@IsTest
	static void processUpload_readsExcelWithNumericHris() {
		/*******************************************
		 * SETUP
		 *******************************************/
		User contextUser = new User(Id = UserInfo.getUserId());
		List<String> header = headerRow().trim().split(',');
		Blob workbook = buildXlsx(
			new List<List<String>>{
				header,
				new List<String>{
					'Tech',
					'Two',
					TECH_TWO_HRIS + '.0',
					CURRENT_TERRITORY,
					'Asm A',
					ASM_A_HRIS,
					NEXT_TERRITORY,
					'Asm A',
					ASM_A_HRIS
				}
			}
		);
		Id documentId = insertFile('gw2707.xlsx', workbook);

		/*******************************************
		 * GIVEN
		 *******************************************/
		Assert.areEqual(0, nextTerritoryMemberCount('GW2707 Tech Two'));

		/*******************************************
		 * WHEN
		 *******************************************/
		TechDistrictAlignmentService.ProcessResult result;
		Test.startTest();
		System.runAs(contextUser) {
			result = TechDistrictAlignmentController.processUpload(documentId);
		}
		Test.stopTest();

		/*******************************************
		 * THEN
		 *******************************************/
		Assert.areEqual(1, result.processedCount);
		Assert.areEqual(1, result.movedCount, String.join(result.errors, '\n'));
		Assert.areEqual(0, result.managerUpdatedCount, 'Same ASM next year leaves the manager alone.');
		Assert.areEqual(1, nextTerritoryMemberCount('GW2707 Tech Two'));
	}

	/**
	 * @description Bulk: 200 technicians move to one new territory in a single upload.
	 */
	@IsTest
	static void processUpload_movesTwoHundredTechsInBulk() {
		/*******************************************
		 * SETUP
		 *******************************************/
		User contextUser = new User(Id = UserInfo.getUserId());
		// adb_User queries the running user in its constructor, so build one and clone it to stay within limits.
		User template = (User) userBuilder('Gwbulk', null).record;
		List<User> bulkUsers = new List<User>();
		for (Integer i = 0; i < BULK_SIZE; i++) {
			User bulkUser = template.clone(false, true);
			String username = 'gw2707.bulk' + i + '.' + Math.abs(Crypto.getRandomInteger()) + '@example.invalid';
			bulkUser.FirstName = 'Gwbulk' + i;
			bulkUser.Username = username;
			bulkUser.Email = username;
			bulkUser.CommunityNickname = ('gw2707b' + i + '.' + Math.abs(Crypto.getRandomInteger())).left(40);
			bulkUsers.add(bulkUser);
		}
		System.runAs(contextUser) {
			adb_DomainBuilder.save();
			Database.insert(bulkUsers, AccessLevel.SYSTEM_MODE);
		}

		Id currentId = territoryId(CURRENT_TERRITORY);
		List<ServiceResource> bulkResources = new List<ServiceResource>();
		String csvBody = headerRow();
		for (Integer i = 0; i < BULK_SIZE; i++) {
			String hris = BULK_TECH_PREFIX + i;
			bulkResources.add(technician(BULK_TECH_PREFIX + ' Tech ' + i, bulkUsers[i].Id, hris));
			csvBody += csvRow(hris, CURRENT_TERRITORY, ASM_A_HRIS, NEW_TERRITORY, ASM_B_HRIS);
		}
		insert bulkResources;
		List<ServiceTerritoryMember> bulkMembers = new List<ServiceTerritoryMember>();
		for (ServiceResource resource : bulkResources) {
			bulkMembers.add(currentMembership(resource.Id, currentId));
		}
		insert bulkMembers;
		Id documentId = insertCsv(csvBody);

		/*******************************************
		 * GIVEN
		 *******************************************/
		Assert.areEqual(0, [SELECT COUNT() FROM ServiceTerritory WHERE RegionNumber__c = :NEW_TERRITORY]);
		Assert.areEqual(BULK_SIZE + 2, [SELECT COUNT() FROM ServiceTerritoryMember WHERE EffectiveEndDate = NULL]);

		/*******************************************
		 * WHEN
		 *******************************************/
		TechDistrictAlignmentService.ProcessResult result;
		Test.startTest();
		System.runAs(contextUser) {
			result = TechDistrictAlignmentController.processUpload(documentId);
		}
		Test.stopTest();

		/*******************************************
		 * THEN
		 *******************************************/
		Assert.areEqual(BULK_SIZE, result.processedCount);
		Assert.areEqual(0, result.skippedCount, String.join(result.errors, '\n'));
		Assert.areEqual(BULK_SIZE, result.movedCount);
		Assert.areEqual(1, result.territoryCreatedCount);
		Assert.areEqual(
			BULK_SIZE,
			[SELECT COUNT() FROM ServiceTerritoryMember WHERE ServiceTerritory.RegionNumber__c = :NEW_TERRITORY]
		);
		Assert.areEqual(
			2,
			[
				SELECT COUNT()
				FROM ServiceTerritoryMember
				WHERE EffectiveEndDate = NULL AND ServiceTerritoryId = :currentId
			],
			'The two technicians not in the file keep their current membership.'
		);
		assertCurrentMembershipsEnded(BULK_SIZE);
	}

	/**
	 * @description Each upload adds a version to the same per-user error file instead of creating a new file.
	 */
	@IsTest
	static void processUpload_reusesErrorFileAcrossRuns() {
		/*******************************************
		 * SETUP
		 *******************************************/
		User contextUser = new User(Id = UserInfo.getUserId());
		TechDistrictAlignmentService.ProcessResult first = TechDistrictAlignmentController.processUpload(
			insertCsv(headerRow() + csvRow('NOPE2707', CURRENT_TERRITORY, ASM_A_HRIS, NEXT_TERRITORY, ASM_B_HRIS))
		);
		Id secondDocumentId = insertCsv(
			headerRow() + csvRow(TECH_ONE_HRIS, CURRENT_TERRITORY, ASM_A_HRIS, CURRENT_TERRITORY, ASM_A_HRIS)
		);

		/*******************************************
		 * GIVEN
		 *******************************************/
		Assert.areEqual(1, [SELECT COUNT() FROM ContentVersion WHERE ContentDocumentId = :first.errorFileDocumentId]);

		/*******************************************
		 * WHEN
		 *******************************************/
		TechDistrictAlignmentService.ProcessResult second;
		String errorFileUrl;
		Test.startTest();
		System.runAs(contextUser) {
			second = TechDistrictAlignmentController.processUpload(secondDocumentId);
			errorFileUrl = TechDistrictAlignmentController.getErrorFileDownloadUrl();
		}
		Test.stopTest();

		/*******************************************
		 * THEN
		 *******************************************/
		Assert.areEqual(first.errorFileDocumentId, second.errorFileDocumentId);
		Assert.areEqual(2, [SELECT COUNT() FROM ContentVersion WHERE ContentDocumentId = :second.errorFileDocumentId]);
		Assert.areEqual(TechDistrictAlignmentService.DOWNLOAD_URL_PREFIX + second.errorFileDocumentId, errorFileUrl);
		FieldServiceBackofficeConfig__c userConfig = FieldServiceBackofficeConfig__c.getValues(UserInfo.getUserId());
		Assert.areEqual(String.valueOf(second.errorFileDocumentId), userConfig.TechDistrictAlignmentErrorFileId__c);
	}

	/**
	 * @description Download Error File before any upload tells the user there is no file yet.
	 */
	@IsTest
	static void getErrorFileDownloadUrl_throwsBeforeFirstUpload() {
		/*******************************************
		 * SETUP
		 *******************************************/
		User contextUser = new User(Id = UserInfo.getUserId());
		AuraHandledException thrown;

		/*******************************************
		 * GIVEN
		 *******************************************/
		Assert.isNull(FieldServiceBackofficeConfig__c.getValues(UserInfo.getUserId()));

		/*******************************************
		 * WHEN
		 *******************************************/
		Test.startTest();
		System.runAs(contextUser) {
			try {
				TechDistrictAlignmentController.getErrorFileDownloadUrl();
			} catch (AuraHandledException e) {
				thrown = e;
			}
		}
		Test.stopTest();

		/*******************************************
		 * THEN
		 *******************************************/
		Assert.isNotNull(thrown);
		Assert.isTrue(thrown.getMessage().contains('No error file yet'));
	}

	/**
	 * @description The packaged template is copied into Files once and its Id stored on the org default setting.
	 */
	@IsTest
	static void getTemplateDownloadUrl_storesTemplateId() {
		/*******************************************
		 * SETUP
		 *******************************************/
		User contextUser = new User(Id = UserInfo.getUserId());
		String url;
		String secondUrl;

		/*******************************************
		 * GIVEN
		 *******************************************/
		FieldServiceBackofficeConfig__c before = FieldServiceBackofficeConfig__c.getOrgDefaults();
		Assert.isTrue(before == null || before.TechDistrictAlignmentTemplateId__c == null);

		/*******************************************
		 * WHEN
		 *******************************************/
		Test.startTest();
		System.runAs(contextUser) {
			url = TechDistrictAlignmentController.getTemplateDownloadUrl();
			secondUrl = TechDistrictAlignmentController.getTemplateDownloadUrl();
		}
		Test.stopTest();

		/*******************************************
		 * THEN
		 *******************************************/
		Assert.isTrue(url.startsWith(TechDistrictAlignmentService.DOWNLOAD_URL_PREFIX));
		Assert.areEqual(url, secondUrl);
		Id templateId = FieldServiceBackofficeConfig__c.getOrgDefaults().TechDistrictAlignmentTemplateId__c;
		Assert.areEqual(url.removeStart(TechDistrictAlignmentService.DOWNLOAD_URL_PREFIX), templateId);
		ContentVersion template = [
			SELECT FileExtension
			FROM ContentVersion
			WHERE ContentDocumentId = :templateId AND IsLatest = TRUE
		];
		Assert.areEqual('xlsx', template.FileExtension, 'The template should be an Excel file.');
		Assert.areEqual(
			1,
			[
				SELECT COUNT()
				FROM ContentDocumentLink
				WHERE ContentDocumentId = :templateId AND LinkedEntityId = :UserInfo.getOrganizationId()
			],
			'The template should be shared with all internal users.'
		);
	}

	/**
	 * @description A missing file or missing required columns are reported to the user and change nothing.
	 */
	@IsTest
	static void processUpload_throwsWhenFileMissingOrColumnsMissing() {
		/*******************************************
		 * SETUP
		 *******************************************/
		User contextUser = new User(Id = UserInfo.getUserId());
		Id badColumnsDocumentId = insertCsv('TECH HRIS#,Current Territory\nA,B\n');
		AuraHandledException missingFile;
		AuraHandledException missingColumns;

		/*******************************************
		 * GIVEN
		 *******************************************/
		Assert.areEqual(0, [SELECT COUNT() FROM ServiceTerritoryMember WHERE EffectiveEndDate != NULL]);

		/*******************************************
		 * WHEN
		 *******************************************/
		Test.startTest();
		System.runAs(contextUser) {
			try {
				TechDistrictAlignmentController.processUpload(null);
			} catch (AuraHandledException e) {
				missingFile = e;
			}
			try {
				TechDistrictAlignmentController.processUpload(badColumnsDocumentId);
			} catch (AuraHandledException e) {
				missingColumns = e;
			}
		}
		Test.stopTest();

		/*******************************************
		 * THEN
		 *******************************************/
		Assert.isNotNull(missingFile);
		Assert.isTrue(missingFile.getMessage().contains('Excel (.xlsx)'));
		Assert.isNotNull(missingColumns);
		Assert.isTrue(missingColumns.getMessage().contains('Next Year ASM HRIS#'));
		Assert.areEqual(0, [SELECT COUNT() FROM ServiceTerritoryMember WHERE EffectiveEndDate != NULL]);
	}

	/**
	 * @description Only Excel (.xlsx) uploads are read; a CSV file is rejected and changes nothing.
	 */
	@IsTest
	static void processUpload_rejectsNonExcelFiles() {
		/*******************************************
		 * SETUP
		 *******************************************/
		User contextUser = new User(Id = UserInfo.getUserId());
		Id csvDocumentId = insertFile('gw2707.csv', Blob.valueOf(headerRow()));
		Id corruptDocumentId = insertFile('gw2707.xlsx', Blob.valueOf('not a workbook'));
		List<String> messages = new List<String>();

		/*******************************************
		 * GIVEN
		 *******************************************/
		Assert.areEqual(0, [SELECT COUNT() FROM ServiceTerritoryMember WHERE EffectiveEndDate != NULL]);

		/*******************************************
		 * WHEN
		 *******************************************/
		Test.startTest();
		System.runAs(contextUser) {
			for (Id documentId : new List<Id>{ csvDocumentId, corruptDocumentId }) {
				try {
					TechDistrictAlignmentController.processUpload(documentId);
				} catch (AuraHandledException e) {
					messages.add(e.getMessage());
				}
			}
		}
		Test.stopTest();

		/*******************************************
		 * THEN
		 *******************************************/
		Assert.areEqual(2, messages.size(), 'Both files should be rejected.');
		Assert.isTrue(messages[0].contains('Excel (.xlsx)'), 'A CSV file should be rejected: ' + messages[0]);
		Assert.isTrue(messages[1].contains('Excel (.xlsx)'), 'A corrupt workbook should be rejected: ' + messages[1]);
		Assert.areEqual(0, [SELECT COUNT() FROM ServiceTerritoryMember WHERE EffectiveEndDate != NULL]);
	}

	/**
	 * @description Midnight (running user's time zone) on the first day of the next fiscal year.
	 */
	private static Datetime nextFiscalYearStartMidnight() {
		return Datetime.newInstance(PlatformUtilities.nextFiscalYearStart(Date.today()), Time.newInstance(0, 0, 0, 0));
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

	/**
	 * @description User builder with a unique username; the Employee Number is the HRIS ID.
	 */
	private static adb_User userBuilder(String firstName, String employeeNumber) {
		String unique = String.valueOf(Math.abs(Crypto.getRandomInteger()));
		String username = 'gw2707.' + firstName.toLowerCase() + '.' + unique + '@example.invalid';
		adb_User builder = new adb_User()
			.firstName(firstName)
			.lastName('Twosevenzeroseven')
			.alias(('g' + unique).left(8))
			.email(username)
			.username(username);
		builder.record.put('CommunityNickname', ('gw2707' + firstName + unique).left(40));
		builder.record.put('EmployeeNumber__c', employeeNumber);
		return builder;
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

	private static ServiceResource technician(String name, Id userId, String hris) {
		return new ServiceResource(
			Name = name,
			RelatedRecordId = userId,
			IsActive = true,
			ResourceType = 'T',
			ExternalID__c = hris
		);
	}

	private static ServiceTerritoryMember currentMembership(Id resourceId, Id territoryId) {
		return new ServiceTerritoryMember(
			ServiceResourceId = resourceId,
			ServiceTerritoryId = territoryId,
			EffectiveStartDate = Datetime.now().addDays(-30),
			TerritoryType = 'P'
		);
	}

	private static Id territoryId(String regionNumber) {
		return [SELECT Id FROM ServiceTerritory WHERE RegionNumber__c = :regionNumber].Id;
	}

	private static Id managerOf(String regionNumber) {
		return [
			SELECT TerritoryManager__c
			FROM ServiceTerritory
			WHERE RegionNumber__c = :regionNumber
		].TerritoryManager__c;
	}

	private static Integer nextTerritoryMemberCount(String resourceName) {
		return [
			SELECT COUNT()
			FROM ServiceTerritoryMember
			WHERE ServiceTerritory.RegionNumber__c = :NEXT_TERRITORY AND ServiceResource.Name = :resourceName
		];
	}

	private static Id userIdByHris(String employeeNumber) {
		List<User> users = [SELECT Id FROM User WHERE EmployeeNumber__c = :employeeNumber LIMIT 1];
		return users.isEmpty() ? null : users[0].Id;
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

	/**
	 * @description Uploads the rows as an Excel (.xlsx) file. Rows are written as comma-separated text for
	 *              readability; no test value contains a comma.
	 */
	private static Id insertCsv(String csvBody) {
		List<List<String>> rows = new List<List<String>>();
		for (String line : csvBody.split('\n')) {
			if (String.isNotBlank(line)) {
				rows.add(line.split(',', -1));
			}
		}
		return insertFile('gw2707.xlsx', buildXlsx(rows));
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
		ContentVersion version = (ContentVersion) new adb_ContentVersion()
			.title('GW2707 Upload')
			.pathOnClient(pathOnClient)
			.versionData(versionData)
			.persist();
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