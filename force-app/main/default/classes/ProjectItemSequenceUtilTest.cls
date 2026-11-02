@IsTest
private class ProjectItemSequenceUtilTest {
    @IsTest
    static void sequenceToString_handlesNullStringAndNumber() {
        System.assertEquals(null, ProjectItemSequenceUtil.sequenceToString(null));
        System.assertEquals('1.2', ProjectItemSequenceUtil.sequenceToString('1.2'));
        System.assertEquals('3', ProjectItemSequenceUtil.sequenceToString(3));
        System.assertEquals('2.5', ProjectItemSequenceUtil.sequenceToString(Decimal.valueOf('2.5')));
    }

    @IsTest
    static void compareSequences_sortsHierarchical() {
        System.assertEquals(-1, ProjectItemSequenceUtil.compareSequences('1', '2'));
        System.assertEquals(0, ProjectItemSequenceUtil.compareSequences('1.2', '1.2'));
        System.assertEquals(-1, ProjectItemSequenceUtil.compareSequences('1.1', '1.2'));
        System.assertEquals(-1, ProjectItemSequenceUtil.compareSequences('1', '1.1'));
        System.assertEquals(1, ProjectItemSequenceUtil.compareSequences('2', '1.9'));
        System.assertEquals(1, ProjectItemSequenceUtil.compareSequences(null, '1'));
        System.assertEquals(-1, ProjectItemSequenceUtil.compareSequences('1', null));
        System.assertEquals(0, ProjectItemSequenceUtil.compareSequences(null, null), 'Both blank tie');
        System.assertEquals(0, ProjectItemSequenceUtil.compareSequences('', '   '), 'Whitespace-only sequences tie as blank');
        System.assertEquals(0, ProjectItemSequenceUtil.compareSequences('x', 'y'), 'Invalid segments parse as 0 — equal at each index');
    }

    @IsTest
    static void isSequenceStrictDescendantOf_hierarchyRules() {
        System.assertEquals(
            false,
            ProjectItemSequenceUtil.isSequenceStrictDescendantOf(null, '2.1'),
            'Null ancestor'
        );
        System.assertEquals(
            false,
            ProjectItemSequenceUtil.isSequenceStrictDescendantOf('2', null),
            'Null descendant'
        );
        System.assertEquals(
            true,
            ProjectItemSequenceUtil.isSequenceStrictDescendantOf('2', '2.1'),
            'Direct child'
        );
        System.assertEquals(
            true,
            ProjectItemSequenceUtil.isSequenceStrictDescendantOf('2', '2.2'),
            'Another direct child'
        );
        System.assertEquals(
            true,
            ProjectItemSequenceUtil.isSequenceStrictDescendantOf('2', '2.1.3'),
            'Nested descendant'
        );
        System.assertEquals(
            false,
            ProjectItemSequenceUtil.isSequenceStrictDescendantOf('2', '21.1'),
            'Must not match sibling branch 21.x'
        );
        System.assertEquals(
            false,
            ProjectItemSequenceUtil.isSequenceStrictDescendantOf('2', '2'),
            'Same key is not a descendant'
        );
        System.assertEquals(
            false,
            ProjectItemSequenceUtil.isSequenceStrictDescendantOf('2', '3.1'),
            'Different root'
        );
        System.assertEquals(
            true,
            ProjectItemSequenceUtil.isSequenceStrictDescendantOf(' 2 ', '2.1'),
            'Whitespace trimmed on ancestor'
        );
    }

    @IsTest
    static void isSequenceStrictDescendantOf_sameKeyCaseInsensitive() {
        System.assertEquals(
            false,
            ProjectItemSequenceUtil.isSequenceStrictDescendantOf('A', 'a'),
            'Same logical key different case is not a strict descendant'
        );
    }

    @IsTest
    static void canonicalRootSequenceKeyForCascade_collapsesDotZero() {
        System.assertEquals(
            '1',
            ProjectItemSequenceUtil.canonicalRootSequenceKeyForCascade('1.0'),
            'Decimal root 1.0 should match sublines 1.1, 1.2'
        );
        System.assertEquals(
            '2',
            ProjectItemSequenceUtil.canonicalRootSequenceKeyForCascade('2.0'),
            'Root 2.0 collapses to 2'
        );
        System.assertEquals(
            '1.1',
            ProjectItemSequenceUtil.canonicalRootSequenceKeyForCascade('1.1'),
            'Non-zero second segment unchanged'
        );
        System.assertEquals(
            '1',
            ProjectItemSequenceUtil.canonicalRootSequenceKeyForCascade('1'),
            'Single segment unchanged'
        );
        System.assertEquals(null, ProjectItemSequenceUtil.canonicalRootSequenceKeyForCascade(null));
        System.assertEquals('', ProjectItemSequenceUtil.canonicalRootSequenceKeyForCascade(''));
    }

    @IsTest
    static void isRootMainProjectLineSequence_identifiesMainLinesOnly() {
        System.assertEquals(true, ProjectItemSequenceUtil.isRootMainProjectLineSequence('1'));
        System.assertEquals(true, ProjectItemSequenceUtil.isRootMainProjectLineSequence('3'));
        System.assertEquals(true, ProjectItemSequenceUtil.isRootMainProjectLineSequence('2.0'));
        System.assertEquals(false, ProjectItemSequenceUtil.isRootMainProjectLineSequence('3.1'));
        System.assertEquals(false, ProjectItemSequenceUtil.isRootMainProjectLineSequence('1.4'));
        System.assertEquals(false, ProjectItemSequenceUtil.isRootMainProjectLineSequence(null));
    }

    @IsTest
    static void putTemplateItemNumber_setsFieldWhenPresent() {
        if (!ProjectItemSequenceUtil.hasTemplateItemNumberField(Task.SObjectType)) {
            return;
        }
        Task t = new Task();
        ProjectItemSequenceUtil.putTemplateItemNumber(t, '5.01');
        System.assertEquals(Decimal.valueOf('5.01'), ProjectItemSequenceUtil.getTemplateItemNumber(t));
    }

    @IsTest
    static void cascadeAncestor_matchesSublinesWhenParentStoredAsDotZero() {
        String ancestor = ProjectItemSequenceUtil.canonicalRootSequenceKeyForCascade('1.0');
        System.assertEquals(
            true,
            ProjectItemSequenceUtil.isSequenceStrictDescendantOf(ancestor, '1.1'),
            '1.1 under canonical parent 1'
        );
        System.assertEquals(
            true,
            ProjectItemSequenceUtil.isSequenceStrictDescendantOf(ancestor, '1.2'),
            '1.2 under canonical parent 1'
        );
        System.assertEquals(
            false,
            ProjectItemSequenceUtil.isSequenceStrictDescendantOf('1.0', '1.1'),
            'Without canonicalization 1.0 would wrongly exclude 1.1'
        );
    }

    @IsTest
    static void getExcludedAssignableUserProfileIds_returnsList() {
        List<String> ids = ProjectItemSequenceUtil.getExcludedAssignableUserProfileIds();
        System.assertNotEquals(null, ids);
    }

    @IsTest
    static void getAssignableUsersPicklist_returnsList() {
        List<InstallationProjectViewerController.PicklistOption> opts = ProjectItemSequenceUtil.getAssignableUsersPicklist();
        System.assertNotEquals(null, opts);
    }

    @IsTest
    static void isAssignableUserId_currentUserWhenStandard() {
        User u = [SELECT Id, UserType, Profile.Name FROM User WHERE Id = :UserInfo.getUserId() LIMIT 1];
        if (u.UserType != 'Standard') {
            return;
        }
        if (
            u.Profile.Name != null &&
            (u.Profile.Name.containsIgnoreCase('Integration') || u.Profile.Name.containsIgnoreCase('Generic'))
        ) {
            return;
        }
        System.assertEquals(true, ProjectItemSequenceUtil.isAssignableUserId(u.Id));
    }

    @IsTest
    static void isAssignableUserId_nullIsFalse() {
        System.assertEquals(false, ProjectItemSequenceUtil.isAssignableUserId(null));
    }
}