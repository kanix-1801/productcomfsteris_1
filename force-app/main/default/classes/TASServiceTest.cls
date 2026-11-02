/**
 * @author Suraj Thapliyal
 * @date 2026/07/03
 * @description Tests TASService HRIS-to-AssignedSalesRep__c assignment
 *              for before insert and before update trigger contexts.
 *              GC-3278 - TAS class rename (formerly OrderLineContactServiceTest).
 */
@IsTest(SeeAllData=false)
private class TASServiceTest {

    private static final String EMP_MATCH = 'OLC-SVC-10001';
    private static final String EMP_OTHER = 'OLC-SVC-10002';
    private static final String EMP_NO_MATCH = 'OLC-SVC-NOMATCH';

    @TestSetup
    static void setupData() {
        Profile salesProfile = resolveHealthcareSalesProfile();

        User salesRep = new User(
            FirstName = 'OLC',
            LastName = 'SvcRep',
            Alias = 'olcsvcr',
            Email = 'olc.svc.' + DateTime.now().getTime() + '@test.com',
            Username = 'olc.svc.' + DateTime.now().getTime() + '@test.com',
            CommunityNickname = 'olcsvnick' + Math.abs(Crypto.getRandomInteger()),
            TimeZoneSidKey = 'America/Los_Angeles',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            ProfileId = salesProfile.Id,
            EmployeeNumber__c = EMP_MATCH,
            IsActive = true
        );
        insert salesRep;

        User otherRep = new User(
            FirstName = 'OLC',
            LastName = 'SvcOther',
            Alias = 'olcsvco',
            Email = 'olc.svc.other.' + DateTime.now().getTime() + '@test.com',
            Username = 'olc.svc.other.' + DateTime.now().getTime() + '@test.com',
            CommunityNickname = 'olcsvonick' + Math.abs(Crypto.getRandomInteger()),
            TimeZoneSidKey = 'America/Los_Angeles',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            ProfileId = salesProfile.Id,
            EmployeeNumber__c = EMP_OTHER,
            IsActive = true
        );
        insert otherRep;

        assignTestPermissionSets(salesRep.Id);
    }

    private static void assignTestPermissionSets(Id userId) {
        List<PermissionSet> permissionSets = [
            SELECT Id
            FROM PermissionSet
            WHERE Name IN (
                'System_Administrator',
                'SalesFieldRepAccountManager',
                'OrderLineContact_c_Create_PS'
            )
        ];

        List<PermissionSetAssignment> assignments = new List<PermissionSetAssignment>();
        for (PermissionSet ps : permissionSets) {
            assignments.add(new PermissionSetAssignment(
                AssigneeId = userId,
                PermissionSetId = ps.Id
            ));
        }
        insert assignments;
    }

    private static Profile resolveHealthcareSalesProfile() {
        List<Profile> healthcareProfiles = [
            SELECT Id
            FROM Profile
            WHERE Name = 'Healthcare Sales'
            LIMIT 1
        ];
        if (!healthcareProfiles.isEmpty()) {
            return healthcareProfiles[0];
        }
        return [SELECT Id FROM Profile WHERE Name = 'System Administrator' LIMIT 1];
    }

    private static User getMatchedSalesRep() {
        return [
            SELECT Id, EmployeeNumber__c
            FROM User
            WHERE EmployeeNumber__c = :EMP_MATCH
            LIMIT 1
        ];
    }

    private static User getOtherSalesRep() {
        return [
            SELECT Id, EmployeeNumber__c
            FROM User
            WHERE EmployeeNumber__c = :EMP_OTHER
            LIMIT 1
        ];
    }

    private static User getRunAsUser() {
        return getMatchedSalesRep();
    }

    private static OrderLineContact__c newOlcRow(String hrisId, Id assignedSalesRepId) {
        OrderLineContact__c row = new OrderLineContact__c(
            HRISSalesRepId__c = hrisId,
            TASAddressId__c = 'TAS-SVC-9001'
        );
        if (assignedSalesRepId != null) {
            row.AssignedSalesRep__c = assignedSalesRepId;
        }
        return row;
    }

    /**
     * @description Verifies null and empty insert inputs complete without error.
     */
    @IsTest
    static void testProcessBeforeInsertNullAndEmpty() {
        System.runAs(getRunAsUser()) {
            TASService.processBeforeInsert(null);
            TASService.processBeforeInsert(new List<OrderLineContact__c>());
        }
        System.assert(true, 'Null and empty lists should no-op');
    }

    /**
     * @description Verifies insert assigns AssignedSalesRep__c when HRIS matches an active user.
     */
    @IsTest
    static void testProcessBeforeInsertAssignsWhenHrisMatches() {
        User rep = getMatchedSalesRep();
        OrderLineContact__c row = newOlcRow(EMP_MATCH, null);

        System.runAs(getRunAsUser()) {
            TASService.processBeforeInsert(new List<OrderLineContact__c>{ row });
        }

        System.assertEquals(rep.Id, row.AssignedSalesRep__c);
    }

    /**
     * @description Verifies insert clears AssignedSalesRep__c when HRIS has no active user match.
     */
    @IsTest
    static void testProcessBeforeInsertClearsWhenHrisNoMatch() {
        OrderLineContact__c row = newOlcRow(EMP_NO_MATCH, getMatchedSalesRep().Id);

        System.runAs(getRunAsUser()) {
            TASService.processBeforeInsert(new List<OrderLineContact__c>{ row });
        }

        System.assertEquals(null, row.AssignedSalesRep__c);
    }

    /**
     * @description Verifies insert skips rows with blank HRIS id.
     */
    @IsTest
    static void testProcessBeforeInsertSkipsBlankHris() {
        Id presetRepId = getMatchedSalesRep().Id;
        OrderLineContact__c row = newOlcRow(null, presetRepId);

        System.runAs(getRunAsUser()) {
            TASService.processBeforeInsert(new List<OrderLineContact__c>{ row });
        }

        System.assertEquals(presetRepId, row.AssignedSalesRep__c);
    }

    /**
     * @description Verifies HRIS values are trimmed before user lookup on insert.
     */
    @IsTest
    static void testProcessBeforeInsertTrimsHrisWhitespace() {
        User rep = getMatchedSalesRep();
        OrderLineContact__c row = newOlcRow('  ' + EMP_MATCH + '  ', null);

        System.runAs(getRunAsUser()) {
            TASService.processBeforeInsert(new List<OrderLineContact__c>{ row });
        }

        System.assertEquals(rep.Id, row.AssignedSalesRep__c);
    }

    /**
     * @description Verifies bulk insert assigns multiple eligible rows in one pass.
     */
    @IsTest
    static void testProcessBeforeInsertBulkMixedRows() {
        User rep = getMatchedSalesRep();
        User otherRep = getOtherSalesRep();
        Id presetRepId = rep.Id;

        OrderLineContact__c matchRow = newOlcRow(EMP_MATCH, null);
        OrderLineContact__c otherMatchRow = newOlcRow(EMP_OTHER, null);
        OrderLineContact__c noMatchRow = newOlcRow(EMP_NO_MATCH, presetRepId);
        OrderLineContact__c blankRow = newOlcRow(null, presetRepId);

        System.runAs(getRunAsUser()) {
            TASService.processBeforeInsert(
                new List<OrderLineContact__c>{ matchRow, otherMatchRow, noMatchRow, blankRow }
            );
        }

        System.assertEquals(rep.Id, matchRow.AssignedSalesRep__c);
        System.assertEquals(otherRep.Id, otherMatchRow.AssignedSalesRep__c);
        System.assertEquals(null, noMatchRow.AssignedSalesRep__c);
        System.assertEquals(presetRepId, blankRow.AssignedSalesRep__c);
    }

    /**
     * @description Verifies update returns early when oldMap is null or empty.
     */
    @IsTest
    static void testProcessBeforeUpdateNullOldMapReturnsEarly() {
        OrderLineContact__c row = newOlcRow(EMP_MATCH, null);
        Id presetRepId = getMatchedSalesRep().Id;
        row.AssignedSalesRep__c = presetRepId;

        System.runAs(getRunAsUser()) {
            TASService.processBeforeUpdate(new List<OrderLineContact__c>{ row }, null);
            TASService.processBeforeUpdate(
                new List<OrderLineContact__c>{ row },
                new Map<Id, OrderLineContact__c>()
            );
        }

        System.assertEquals(presetRepId, row.AssignedSalesRep__c);
    }

    /**
     * @description Verifies update reassigns when HRIS id changes to a new populated value.
     */
    @IsTest
    static void testProcessBeforeUpdateAssignsWhenHrisChanges() {
        User otherRep = getOtherSalesRep();
        OrderLineContact__c persisted = newOlcRow(EMP_MATCH, getMatchedSalesRep().Id);
        insert persisted;

        OrderLineContact__c updated = persisted.clone(true, true, true, true);
        updated.HRISSalesRepId__c = EMP_OTHER;

        OrderLineContact__c prior = new OrderLineContact__c(
            Id = persisted.Id,
            HRISSalesRepId__c = EMP_MATCH
        );

        System.runAs(getRunAsUser()) {
            TASService.processBeforeUpdate(
                new List<OrderLineContact__c>{ updated },
                new Map<Id, OrderLineContact__c>{ persisted.Id => prior }
            );
        }

        System.assertEquals(otherRep.Id, updated.AssignedSalesRep__c);
    }

    /**
     * @description Verifies update skips rows when HRIS id is unchanged.
     */
    @IsTest
    static void testProcessBeforeUpdateSkipsWhenHrisUnchanged() {
        Id presetRepId = getMatchedSalesRep().Id;
        OrderLineContact__c persisted = newOlcRow(EMP_MATCH, presetRepId);
        insert persisted;

        OrderLineContact__c updated = persisted.clone(true, true, true, true);
        updated.TASAddressId__c = 'TAS-SVC-UPDATED';

        OrderLineContact__c prior = new OrderLineContact__c(
            Id = persisted.Id,
            HRISSalesRepId__c = EMP_MATCH
        );

        System.runAs(getRunAsUser()) {
            TASService.processBeforeUpdate(
                new List<OrderLineContact__c>{ updated },
                new Map<Id, OrderLineContact__c>{ persisted.Id => prior }
            );
        }

        System.assertEquals(presetRepId, updated.AssignedSalesRep__c);
    }

    /**
     * @description Verifies update does not clear AssignedSalesRep__c when HRIS is blanked.
     */
    @IsTest
    static void testProcessBeforeUpdateSkipsWhenHrisCleared() {
        Id presetRepId = getMatchedSalesRep().Id;
        OrderLineContact__c persisted = newOlcRow(EMP_MATCH, presetRepId);
        insert persisted;

        OrderLineContact__c updated = persisted.clone(true, true, true, true);
        updated.HRISSalesRepId__c = null;

        OrderLineContact__c prior = new OrderLineContact__c(
            Id = persisted.Id,
            HRISSalesRepId__c = EMP_MATCH
        );

        System.runAs(getRunAsUser()) {
            TASService.processBeforeUpdate(
                new List<OrderLineContact__c>{ updated },
                new Map<Id, OrderLineContact__c>{ persisted.Id => prior }
            );
        }

        System.assertEquals(presetRepId, updated.AssignedSalesRep__c);
    }

    /**
     * @description Verifies update clears AssignedSalesRep__c when HRIS changes to a value with no user match.
     */
    @IsTest
    static void testProcessBeforeUpdateClearsWhenNewHrisNoMatch() {
        Id presetRepId = getMatchedSalesRep().Id;
        OrderLineContact__c persisted = newOlcRow(EMP_MATCH, presetRepId);
        insert persisted;

        OrderLineContact__c updated = persisted.clone(true, true, true, true);
        updated.HRISSalesRepId__c = EMP_NO_MATCH;

        OrderLineContact__c prior = new OrderLineContact__c(
            Id = persisted.Id,
            HRISSalesRepId__c = EMP_MATCH
        );

        System.runAs(getRunAsUser()) {
            TASService.processBeforeUpdate(
                new List<OrderLineContact__c>{ updated },
                new Map<Id, OrderLineContact__c>{ persisted.Id => prior }
            );
        }

        System.assertEquals(null, updated.AssignedSalesRep__c);
    }

    /**
     * @description Verifies update skips a row when its prior version is missing from oldMap.
     */
    @IsTest
    static void testProcessBeforeUpdateMissingOldMapEntrySkipsRow() {
        Id presetRepId = getMatchedSalesRep().Id;
        OrderLineContact__c persisted = newOlcRow(EMP_MATCH, presetRepId);
        OrderLineContact__c otherRow = newOlcRow(EMP_OTHER, getOtherSalesRep().Id);
        insert new List<OrderLineContact__c>{ persisted, otherRow };

        OrderLineContact__c updated = persisted.clone(true, true, true, true);
        updated.HRISSalesRepId__c = EMP_OTHER;

        Map<Id, OrderLineContact__c> oldMap = new Map<Id, OrderLineContact__c>{
            otherRow.Id => new OrderLineContact__c(
                Id = otherRow.Id,
                HRISSalesRepId__c = EMP_OTHER
            )
        };

        System.runAs(getRunAsUser()) {
            TASService.processBeforeUpdate(
                new List<OrderLineContact__c>{ updated },
                oldMap
            );
        }

        System.assertEquals(presetRepId, updated.AssignedSalesRep__c);
    }

    /**
     * @description Exercises UserSelector public methods for deploy test coverage.
     */
    @IsTest
    static void testUserSelectorCoverage() {
        User rep = getMatchedSalesRep();

        System.runAs(getRunAsUser()) {
            System.assertEquals(0, UserSelector.selectActiveUsersBySearch(null).size());
            System.assert(UserSelector.selectActiveUsersBySearch('OLC').size() > 0);

            System.assertEquals(0, UserSelector.selectByIds(null).size());
            System.assertEquals(1, UserSelector.selectByIds(new Set<Id>{ rep.Id }).size());

            System.assertEquals(
                1,
                UserSelector.selectByIdsForEmail(new Set<Id>{ rep.Id }).size()
            );

            System.assertEquals(
                rep.Id,
                UserSelector.selectActiveUsersByEmployeeNumber(
                    new Set<String>{ EMP_MATCH }
                ).get(EMP_MATCH).Id
            );
            System.assertEquals(
                0,
                UserSelector.selectActiveUsersByEmployeeNumber(new Set<String>()).size()
            );

            System.assertEquals(1, UserSelector.getActiveUsersByIds(new Set<Id>{ rep.Id }).size());
            System.assertEquals(0, UserSelector.getInactiveUsersByIds(new Set<Id>{ rep.Id }).size());

            System.assert(
                UserSelector.selectActiveHealthcareSalesUsersBySearch('OLC').size() > 0
            );
            System.assertEquals(
                0,
                UserSelector.selectActiveHealthcareSalesUsersBySearch(null).size()
            );
        }
    }
}