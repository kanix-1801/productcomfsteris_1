/**
 * @author PWC Developer
 * @date 2026/07/15
 *
 * @group Record Type Permission Set Assignment
 *
 * @description
 * Unit tests for RecordTypePsAssignmentController, RecordTypePsAssignmentService,
 * PermissionSetSelector, RecordTypePermissionSetMappingSelector, and RecordTypePsAssignmentException.
 */
@IsTest(SeeAllData=false)
private class RecordTypePsAssignmentControllerTest {

    /**
     * @description
     * Clears service-layer test hooks between test methods.
     *
     * @return void
     */
    private static void resetServiceTestFlags() {
        RecordTypePsAssignmentService.isThrowTestException = false;
        RecordTypePsAssignmentService.forcedExceptionMethodName = null;
    }

    /**
     * @description
     * Returns active CMDT mapping records from the org.
     *
     * @return Active mapping records.
     */
    private static List<Record_Type_Permission_Set_Mapping__mdt> getActiveMappingRecords() {
        return RecordTypePermissionSetMappingSelector.selectActiveMappings();
    }

    /**
     * @description
     * Returns the first object API name configured in active CMDT mappings.
     *
     * @return Object API name.
     */
    private static String getTestObjectApiName() {
        List<Record_Type_Permission_Set_Mapping__mdt> mappingList = getActiveMappingRecords();
        System.assert(!mappingList.isEmpty(), 'At least one active Record_Type_Permission_Set_Mapping__mdt record is required.');
        return mappingList[0].Object_API_Name__c;
    }

    /**
     * @description
     * Returns permission set API names configured for the provided object.
     *
     * @param objectApiName Object API name.
     * @return Permission set API names.
     */
    private static Set<String> getManagedPermissionSetApiNames(String objectApiName) {
        Set<String> permissionSetApiNameSet = new Set<String>();

        for (Record_Type_Permission_Set_Mapping__mdt mappingRecord :
            RecordTypePermissionSetMappingSelector.selectActiveMappingsByObject(objectApiName)) {
            permissionSetApiNameSet.add(mappingRecord.Permission_Set_API_Name__c);
        }

        return permissionSetApiNameSet;
    }

    /**
     * @description
     * Creates a Sales Ops user with SalesCustomerOpsSalesSupportSalesAdminPSG assigned.
     *
     * @param uniqueKey Unique suffix for user fields.
     * @return Sales Ops user.
     */
    private static User createSalesOpsUser(String uniqueKey) {
        User salesOpsUser = TestDataFactory.insertOverlayTestUser('SalesOps', uniqueKey);
        assignAssignPermissionSetsAccess(salesOpsUser.Id);
        return salesOpsUser;
    }

    /**
     * @description
     * Grants permission set assignment access required for save tests in Sales Ops context.
     *
     * @param userId Sales Ops user id.
     * @return void
     */
    private static void assignAssignPermissionSetsAccess(Id userId) {
        List<PermissionSet> assignPermissionSetList = [
            SELECT Id
            FROM PermissionSet
            WHERE PermissionsAssignPermissionSets = true
            AND IsOwnedByProfile = false
            LIMIT 1
        ];

        if (assignPermissionSetList.isEmpty()) {
            return;
        }

        insert new PermissionSetAssignment(
            AssigneeId = userId,
            PermissionSetId = assignPermissionSetList[0].Id
        );
    }

    /**
     * @description
     * Creates an active Healthcare Sales user for search tests.
     *
     * @param uniqueKey Unique suffix for user fields.
     * @return Created user.
     */
    private static User createHealthcareSalesUser(String uniqueKey) {
        Profile healthcareSalesProfile = [
            SELECT Id
            FROM Profile
            WHERE Name = :UserSelector.HEALTHCARE_SALES_PROFILE_NAME
            LIMIT 1
        ];

        User healthcareSalesUser = new User(
            Alias = ('hs' + uniqueKey).left(8),
            Email = 'rtps.hs.' + uniqueKey + '@example.com',
            EmailEncodingKey = 'UTF-8',
            LastName = 'RTPS HS ' + uniqueKey,
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = healthcareSalesProfile.Id,
            TimeZoneSidKey = 'America/New_York',
            Username = 'rtps.hs.' + uniqueKey + '@example.com.test',
            EmployeeNumber__c = 'RTPHS' + uniqueKey
        );
        insert healthcareSalesUser;
        return healthcareSalesUser;
    }

    /**
     * @description
     * Creates a standard active user for permission set assignment tests.
     *
     * @param uniqueKey Unique suffix for user fields.
     * @return Created user.
     */
    private static User createAssignmentTargetUser(String uniqueKey) {
        Profile standardProfile = [
            SELECT Id
            FROM Profile
            WHERE Name = 'Standard User'
            LIMIT 1
        ];

        User assignmentTargetUser = new User(
            Alias = ('rt' + uniqueKey).left(8),
            Email = 'rtps.test.' + uniqueKey + '@example.com',
            EmailEncodingKey = 'UTF-8',
            LastName = 'RTPS Test ' + uniqueKey,
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = standardProfile.Id,
            TimeZoneSidKey = 'America/New_York',
            Username = 'rtps.test.' + uniqueKey + '@example.com.test',
            EmployeeNumber__c = 'RTPS' + uniqueKey
        );
        insert assignmentTargetUser;
        return assignmentTargetUser;
    }

    /**
     * @description
     * Returns the permission set id for the provided API name.
     *
     * @param permissionSetApiName Permission set API name.
     * @return Permission set id.
     */
    private static Id getPermissionSetId(String permissionSetApiName) {
        return [
            SELECT Id
            FROM PermissionSet
            WHERE Name = :permissionSetApiName
            LIMIT 1
        ]
        .Id;
    }

    /**
     * @description
     * Removes managed record type permission set assignments for a user.
     *
     * @param userId User id.
     * @param objectApiName Object API name.
     * @return void
     */
    private static void clearManagedAssignments(Id userId, String objectApiName) {
        Set<String> permissionSetApiNameSet = getManagedPermissionSetApiNames(objectApiName);

        delete [
            SELECT Id
            FROM PermissionSetAssignment
            WHERE AssigneeId = :userId
            AND PermissionSet.Name IN :permissionSetApiNameSet
        ];
    }

    /**
     * @description
     * Verifies object options return values configured in CMDT.
     *
     * @return void
     */
    @IsTest
    static void testGetObjectOptionsReturnsCmdtObjects() {
        /********************************************
        * GIVEN
        ********************************************/
        Set<String> expectedObjectApiNameSet = new Set<String>();

        for (Record_Type_Permission_Set_Mapping__mdt mappingRecord : getActiveMappingRecords()) {
            expectedObjectApiNameSet.add(mappingRecord.Object_API_Name__c);
        }

        /********************************************
        * WHEN
        ********************************************/
        User salesOpsUser = createSalesOpsUser('Options');
        Test.startTest();
        List<RecordTypePsAssignmentController.ObjectOptionWrapper> objectOptions;
        System.runAs(salesOpsUser) {
            objectOptions = RecordTypePsAssignmentController.getObjectOptions();
        }
        Test.stopTest();

        /********************************************
        * THEN
        ********************************************/
        System.assertEquals(
            expectedObjectApiNameSet.size(),
            objectOptions.size(),
            'Object options should match active CMDT object values.'
        );

        for (RecordTypePsAssignmentController.ObjectOptionWrapper objectOption : objectOptions) {
            System.assert(
                expectedObjectApiNameSet.contains(objectOption.value),
                'Returned object option should exist in CMDT configuration.'
            );
        }
    }

    /**
     * @description
     * Verifies user search returns matching active Healthcare Sales users.
     *
     * @return void
     */
    @IsTest
    static void testSearchUsersReturnsMatchingUsers() {
        /********************************************
        * GIVEN
        ********************************************/
        User assignmentTargetUser = createHealthcareSalesUser('Search');
        User salesOpsUser = createSalesOpsUser('Search');

        /********************************************
        * WHEN
        ********************************************/
        Test.startTest();
        List<RecordTypePsAssignmentController.UserWrapper> userResults;
        System.runAs(salesOpsUser) {
            userResults = RecordTypePsAssignmentController.searchUsers(assignmentTargetUser.LastName);
        }
        Test.stopTest();

        /********************************************
        * THEN
        ********************************************/
        System.assert(userResults.size() > 0, 'Search should return at least one matching user.');
        System.assertEquals(
            assignmentTargetUser.Id,
            userResults[0].userId,
            'Returned user should match the searched user.'
        );
    }

    /**
     * @description
     * Verifies permission set assignment view returns all managed options for a user.
     *
     * @return void
     */
    @IsTest
    static void testGetPermissionSetAssignmentsReturnsManagedOptions() {
        /********************************************
        * GIVEN
        ********************************************/
        String objectApiName = getTestObjectApiName();
        User assignmentTargetUser = createAssignmentTargetUser('View');
        clearManagedAssignments(assignmentTargetUser.Id, objectApiName);
        Integer expectedOptionCount = getManagedPermissionSetApiNames(objectApiName).size();
        User salesOpsUser = createSalesOpsUser('View');

        /********************************************
        * WHEN
        ********************************************/
        Test.startTest();
        RecordTypePsAssignmentController.PermissionSetAssignmentViewResult assignmentView;
        System.runAs(salesOpsUser) {
            assignmentView = RecordTypePsAssignmentController.getPermissionSetAssignments(
                objectApiName,
                assignmentTargetUser.Id
            );
        }
        Test.stopTest();

        /********************************************
        * THEN
        ********************************************/
        System.assertEquals(
            expectedOptionCount,
            assignmentView.permissionSetOptions.size(),
            'Managed permission sets from CMDT should be returned.'
        );
        System.assertEquals(0, assignmentView.assignedPermissionSetIds.size(), 'User should start with no managed assignments.');

        for (RecordTypePsAssignmentController.PermissionSetOptionWrapper permissionSetOption :
            assignmentView.permissionSetOptions) {
            System.assert(
                String.isNotBlank(permissionSetOption.label),
                'Permission set option label should come from the record type label.'
            );
        }
    }

    /**
     * @description
     * Verifies save assigns and removes managed permission sets for the selected user.
     *
     * @return void
     */
    @IsTest
    static void testSavePermissionSetAssignmentsAssignsAndRemovesRecords() {
        /********************************************
        * GIVEN
        ********************************************/
        String objectApiName = getTestObjectApiName();
        List<Record_Type_Permission_Set_Mapping__mdt> mappingList =
            RecordTypePermissionSetMappingSelector.selectActiveMappingsByObject(objectApiName);
        System.assert(mappingList.size() >= 2, 'At least two CMDT mappings are required for save tests.');

        User assignmentTargetUser = createAssignmentTargetUser('Save');
        clearManagedAssignments(assignmentTargetUser.Id, objectApiName);
        Id firstPermissionSetId = getPermissionSetId(mappingList[0].Permission_Set_API_Name__c);
        Id secondPermissionSetId = getPermissionSetId(mappingList[1].Permission_Set_API_Name__c);
        User salesOpsUser = createSalesOpsUser('Save');

        /********************************************
        * WHEN
        ********************************************/
        Test.startTest();
        System.runAs(salesOpsUser) {
            RecordTypePsAssignmentController.savePermissionSetAssignments(
                objectApiName,
                assignmentTargetUser.Id,
                new List<Id>{ firstPermissionSetId, secondPermissionSetId }
            );
        }
        Test.stopTest();

        /********************************************
        * THEN
        ********************************************/
        Set<Id> assignedPermissionSetIds = new Map<Id, PermissionSetAssignment>(
            [
                SELECT PermissionSetId
                FROM PermissionSetAssignment
                WHERE AssigneeId = :assignmentTargetUser.Id
                AND PermissionSetId IN :new Set<Id>{ firstPermissionSetId, secondPermissionSetId }
            ]
        ).keySet();

        System.assertEquals(2, assignedPermissionSetIds.size(), 'Two permission sets should be assigned.');

        System.runAs(salesOpsUser) {
            RecordTypePsAssignmentController.savePermissionSetAssignments(
                objectApiName,
                assignmentTargetUser.Id,
                new List<Id>{ secondPermissionSetId }
            );
        }

        Integer remainingAssignmentCount = [
            SELECT COUNT()
            FROM PermissionSetAssignment
            WHERE AssigneeId = :assignmentTargetUser.Id
            AND PermissionSetId IN :new Set<Id>{ firstPermissionSetId, secondPermissionSetId }
        ];

        System.assertEquals(1, remainingAssignmentCount, 'First permission set assignment should be removed.');
    }

    /**
     * @description
     * Verifies save validation is surfaced when no user is selected.
     *
     * @return void
     */
    @IsTest
    static void testSaveWithoutUserThrowsException() {
        /********************************************
        * WHEN / THEN
        ********************************************/
        User salesOpsUser = createSalesOpsUser('NoUser');
        Boolean exceptionThrown = false;

        System.runAs(salesOpsUser) {
            try {
                RecordTypePsAssignmentController.savePermissionSetAssignments(
                    getTestObjectApiName(),
                    null,
                    new List<Id>()
                );
            } catch (AuraHandledException exceptionValue) {
                exceptionThrown = true;
            }
        }

        System.assertEquals(true, exceptionThrown, 'Save without a user should throw AuraHandledException.');
    }

    /**
     * @description
     * Verifies search users exception path surfaces AuraHandledException.
     *
     * @return void
     */
    @IsTest
    static void testSearchUsersExceptionPath() {
        User salesOpsUser = createSalesOpsUser('SearchException');

        try {
            /********************************************
            * WHEN / THEN
            ********************************************/
            RecordTypePsAssignmentService.isThrowTestException = true;
            Boolean exceptionThrown = false;

            Test.startTest();
            System.runAs(salesOpsUser) {
                try {
                    RecordTypePsAssignmentController.searchUsers('Test');
                } catch (AuraHandledException exceptionValue) {
                    exceptionThrown = true;
                }
            }
            Test.stopTest();

            System.assertEquals(true, exceptionThrown, 'Expected user search exception path to throw AuraHandledException.');
        } finally {
            resetServiceTestFlags();
        }
    }

    /**
     * @description
     * Verifies getObjectOptions exception path surfaces AuraHandledException.
     *
     * @return void
     */
    @IsTest
    static void testGetObjectOptionsExceptionPath() {
        User salesOpsUser = createSalesOpsUser('OptionsException');

        try {
            /********************************************
            * WHEN / THEN
            ********************************************/
            RecordTypePsAssignmentService.forcedExceptionMethodName = 'getObjectOptions';
            Boolean exceptionThrown = false;

            Test.startTest();
            System.runAs(salesOpsUser) {
                try {
                    RecordTypePsAssignmentController.getObjectOptions();
                } catch (AuraHandledException exceptionValue) {
                    exceptionThrown = true;
                }
            }
            Test.stopTest();

            System.assertEquals(true, exceptionThrown, 'Expected object options exception path to throw AuraHandledException.');
        } finally {
            resetServiceTestFlags();
        }
    }

    /**
     * @description
     * Verifies getPermissionSetAssignments exception path surfaces AuraHandledException.
     *
     * @return void
     */
    @IsTest
    static void testGetPermissionSetAssignmentsExceptionPath() {
        User salesOpsUser = createSalesOpsUser('AssignEx');

        try {
            /********************************************
            * WHEN / THEN
            ********************************************/
            RecordTypePsAssignmentService.forcedExceptionMethodName = 'getPermissionSetAssignments';
            Boolean exceptionThrown = false;

            Test.startTest();
            System.runAs(salesOpsUser) {
                try {
                    RecordTypePsAssignmentController.getPermissionSetAssignments(null, null);
                } catch (AuraHandledException exceptionValue) {
                    exceptionThrown = true;
                }
            }
            Test.stopTest();

            System.assertEquals(
                true,
                exceptionThrown,
                'Expected permission set assignment exception path to throw AuraHandledException.'
            );
        } finally {
            resetServiceTestFlags();
        }
    }

    /**
     * @description
     * Verifies PermissionSetSelector empty-input guards return empty collections.
     *
     * @return void
     */
    @IsTest
    static void testPermissionSetSelectorEmptyInputs() {
        User salesOpsUser = createSalesOpsUser('PsSelector');

        /********************************************
        * WHEN / THEN
        ********************************************/
        System.runAs(salesOpsUser) {
            System.assertEquals(0, PermissionSetSelector.selectByNames(null).size());
            System.assertEquals(0, PermissionSetSelector.selectByNames(new Set<String>()).size());
            System.assertEquals(
                0,
                PermissionSetSelector.selectAssignmentsByUserAndPermissionSetIds(null, new Set<Id>{ UserInfo.getUserId() }).size()
            );
            System.assertEquals(
                0,
                PermissionSetSelector.selectAssignmentsByUserAndPermissionSetIds(UserInfo.getUserId(), null).size()
            );
        }
    }

    /**
     * @description
     * Verifies RecordTypePermissionSetMappingSelector empty-input guards return empty collections.
     *
     * @return void
     */
    @IsTest
    static void testRecordTypePermissionSetMappingSelectorEmptyInputs() {
        User salesOpsUser = createSalesOpsUser('MappingSelector');

        /********************************************
        * WHEN / THEN
        ********************************************/
        System.runAs(salesOpsUser) {
            System.assertEquals(
                0,
                RecordTypePermissionSetMappingSelector.selectActiveMappingsByObject(null).size()
            );
            System.assertEquals(
                0,
                RecordTypePermissionSetMappingSelector.selectActiveMappingsByObject('').size()
            );
        }
    }

    /**
     * @description
     * Verifies UserSelector Healthcare Sales search guards and query path.
     *
     * @return void
     */
    @IsTest
    static void testUserSelectorHealthcareSalesSearch() {
        /********************************************
        * GIVEN
        ********************************************/
        User healthcareSalesUser = createHealthcareSalesUser('Selector');
        User salesOpsUser = createSalesOpsUser('Selector');

        /********************************************
        * WHEN / THEN
        ********************************************/
        Test.startTest();
        System.runAs(salesOpsUser) {
            System.assertEquals(0, UserSelector.selectActiveHealthcareSalesUsersBySearch(null).size());
            System.assertEquals(0, UserSelector.selectActiveHealthcareSalesUsersBySearch('').size());
            System.assert(
                UserSelector.selectActiveHealthcareSalesUsersBySearch(healthcareSalesUser.LastName).size() > 0,
                'Healthcare Sales user search should return matching users.'
            );
            System.assertEquals(0, UserSelector.selectActiveUsersByEmployeeNumber(new Set<String>()).size());
            System.assertEquals(
                1,
                UserSelector.getActiveUsersByIds(new Set<Id>{ UserInfo.getUserId() }).size()
            );
        }
        Test.stopTest();
    }

    /**
     * @description
     * Verifies RecordTypePsAssignmentException can be thrown and caught with a message.
     *
     * @return void
     */
    @IsTest
    static void testExceptionTypeMessageAndThrow() {
        /********************************************
        * SETUP
        ********************************************/
        String expectedMessage = 'Record type permission set assignment failure';
        User salesOpsUser = createSalesOpsUser('Exception');

        /********************************************
        * WHEN / THEN
        ********************************************/
        Boolean threw = false;
        System.runAs(salesOpsUser) {
            try {
                throw new RecordTypePsAssignmentException(expectedMessage);
            } catch (RecordTypePsAssignmentException exceptionValue) {
                threw = true;
                System.assertEquals(expectedMessage, exceptionValue.getMessage());
            }
        }

        System.assert(threw, 'RecordTypePsAssignmentException should be throwable');
    }
}