/**
 * @description Tests for WoDebriefSkillCheckController Time-tab Work Type skill checks.
 *              Skill DML is not permitted in this org, so match/mismatch paths use test doubles.
 * @see WoDebriefSkillCheckController
 */
@IsTest
private class WoDebriefSkillCheckControllerTest {
    /**
     * @description Clears injected test doubles so methods do not leak state.
     */
    private static void resetTestDoubles() {
        WoDebriefSkillCheckController.testSkillRequirements = null;
        WoDebriefSkillCheckController.testResourceSkillIds = null;
        WoDebriefSkillCheckController.testSkillNames = null;
    }

    /**
     * @description Same Work Type as the Work Order skips the skill check.
     */
    @IsTest
    static void checkServiceResourceSkills_sameWorkType_skipsCheck() {
        resetTestDoubles();
        WorkType workType = insertWorkType('GW2494 Same WT');
        ServiceResource resource = insertServiceResource('GW2494-SAME');

        Test.startTest();
        WoDebriefSkillCheckController.SkillCheckResult result =
            WoDebriefSkillCheckController.checkServiceResourceSkills(
                workType.Id,
                resource.Id,
                workType.Id,
                null
            );
        Test.stopTest();

        System.assertEquals(false, result.checkRequired, 'Same Work Type should not require a skill check');
        System.assertEquals(true, result.hasRequiredSkills, 'Skipped check should pass');
        System.assertEquals(0, result.missingSkillNames.size(), 'Skipped check has no missing skills');
    }

    /**
     * @description Null Work Order returns no assigned Service Resource.
     */
    @IsTest
    static void getAssignedServiceResourceId_nullId_returnsNull() {
        Test.startTest();
        Id resourceId = WoDebriefSkillCheckController.getAssignedServiceResourceId(null);
        Test.stopTest();
        System.assertEquals(null, resourceId);
    }

    /**
     * @description Current-user lookup returns a Service Resource owned by the running user when one exists.
     */
    @IsTest
    static void getCurrentUserServiceResourceId_returnsUsersResourceWhenPresent() {
        insertServiceResource('GW2494-CUR');
        Test.startTest();
        Id currentId = WoDebriefSkillCheckController.getCurrentUserServiceResourceId();
        Test.stopTest();
        System.assertNotEquals(null, currentId, 'Running user should resolve a Service Resource');
        System.assertEquals(
            1,
            [SELECT COUNT() FROM ServiceResource WHERE Id = :currentId AND RelatedRecordId = :UserInfo.getUserId()]
        );
    }

    /**
     * @description Null Work Type or Resource does not fail the check.
     */
    @IsTest
    static void checkServiceResourceSkills_blankInputs_passes() {
        resetTestDoubles();
        WorkType headerType = insertWorkType('GW2494 Header WT');
        WorkType selectedType = insertWorkType('GW2494 Selected WT');

        Test.startTest();
        WoDebriefSkillCheckController.SkillCheckResult nullWorkType =
            WoDebriefSkillCheckController.checkServiceResourceSkills(null, null, headerType.Id, null);
        WoDebriefSkillCheckController.SkillCheckResult noResource =
            WoDebriefSkillCheckController.checkServiceResourceSkills(selectedType.Id, null, headerType.Id, null);
        Test.stopTest();

        System.assertEquals(false, nullWorkType.checkRequired);
        System.assertEquals(true, nullWorkType.hasRequiredSkills);
        System.assertEquals(true, noResource.checkRequired);
        System.assertEquals(true, noResource.hasRequiredSkills);
    }

    /**
     * @description Different Work Type with no Skill Requirements passes.
     */
    @IsTest
    static void checkServiceResourceSkills_noRequirements_passes() {
        resetTestDoubles();
        WorkType headerType = insertWorkType('GW2494 Header None');
        WorkType selectedType = insertWorkType('GW2494 Selected None');
        ServiceResource resource = insertServiceResource('GW2494-NONE');

        Test.startTest();
        WoDebriefSkillCheckController.SkillCheckResult result =
            WoDebriefSkillCheckController.checkServiceResourceSkills(
                selectedType.Id,
                resource.Id,
                headerType.Id,
                null
            );
        Test.stopTest();

        System.assertEquals(true, result.checkRequired);
        System.assertEquals(true, result.hasRequiredSkills);
        System.assertEquals(0, result.missingSkillNames.size());
    }

    /**
     * @description Resource missing a Work Type Skill Requirement fails with the skill name.
     */
    @IsTest
    static void checkServiceResourceSkills_missingSkill_fails() {
        resetTestDoubles();
        WorkType headerType = insertWorkType('GW2494 Header Missing');
        WorkType selectedType = insertWorkType('GW2494 Selected Missing');
        ServiceResource resource = insertServiceResource('GW2494-MISS');
        Id skillId = stubSkillId();
        WoDebriefSkillCheckController.testSkillRequirements = new List<SkillRequirement>{
            new SkillRequirement(RelatedRecordId = selectedType.Id, SkillId = skillId)
        };
        WoDebriefSkillCheckController.testSkillNames = new Map<Id, String>{ skillId => 'GW2494 Required Skill' };

        Test.startTest();
        WoDebriefSkillCheckController.SkillCheckResult result =
            WoDebriefSkillCheckController.checkServiceResourceSkills(
                selectedType.Id,
                resource.Id,
                headerType.Id,
                null
            );
        Test.stopTest();

        System.assertEquals(true, result.checkRequired);
        System.assertEquals(false, result.hasRequiredSkills);
        System.assertEquals(1, result.missingSkillNames.size());
        System.assertEquals('GW2494 Required Skill', result.missingSkillNames[0]);
    }

    /**
     * @description Resource with the required Service Resource Skill passes.
     */
    @IsTest
    static void checkServiceResourceSkills_resourceHasSkill_passes() {
        resetTestDoubles();
        WorkType headerType = insertWorkType('GW2494 Header Has');
        WorkType selectedType = insertWorkType('GW2494 Selected Has');
        ServiceResource resource = insertServiceResource('GW2494-HAS');
        Id skillId = stubSkillId();
        WoDebriefSkillCheckController.testSkillRequirements = new List<SkillRequirement>{
            new SkillRequirement(RelatedRecordId = selectedType.Id, SkillId = skillId)
        };
        WoDebriefSkillCheckController.testSkillNames = new Map<Id, String>{ skillId => 'GW2494 Required Skill' };
        WoDebriefSkillCheckController.testResourceSkillIds = new Set<Id>{ skillId };

        Test.startTest();
        WoDebriefSkillCheckController.SkillCheckResult result =
            WoDebriefSkillCheckController.checkServiceResourceSkills(
                selectedType.Id,
                resource.Id,
                headerType.Id,
                null
            );
        Test.stopTest();

        System.assertEquals(true, result.checkRequired);
        System.assertEquals(true, result.hasRequiredSkills);
        System.assertEquals(0, result.missingSkillNames.size());
    }

    /**
     * @description Returns a Skill Id for in-memory Skill Requirement doubles.
     * @return Skill Id
     */
    private static Id stubSkillId() {
        String keyPrefix = Skill.SObjectType.getDescribe().getKeyPrefix();
        String id15 = keyPrefix;
        while (id15.length() < 15) {
            id15 += '0';
        }
        return Id.valueOf(id15.substring(0, 15));
    }

    /**
     * @description Inserts a Work Type used as header or Time-line selection.
     * @param name Work Type name
     * @return Inserted Work Type
     */
    private static WorkType insertWorkType(String name) {
        WorkType workType = new WorkType(
            Name = name + ' ' + String.valueOf(Crypto.getRandomInteger()),
            EstimatedDuration = 1,
            DurationType = 'Hours'
        );
        insert workType;
        return workType;
    }

    /**
     * @description Inserts an active Service Resource for the running user.
     * @param prefix External Id prefix
     * @return Inserted Service Resource
     */
    private static ServiceResource insertServiceResource(String prefix) {
        ServiceResource resource = new ServiceResource(
            Name = prefix + ' Resource',
            IsActive = true,
            RelatedRecordId = UserInfo.getUserId(),
            ExternalID__c = prefix + '-' + String.valueOf(Crypto.getRandomInteger())
        );
        insert resource;
        return resource;
    }
}