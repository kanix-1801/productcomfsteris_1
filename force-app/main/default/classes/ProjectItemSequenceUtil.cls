/**
 * Shared helpers for installation project lines: sequence ordering, template item numbers,
 * and assignable User filtering for Task/Event assignment UIs.
 */
public with sharing class ProjectItemSequenceUtil {
    @TestVisible
    private static final String PROFILE_INTEGRATION_PATTERN = '%Integration%';
    @TestVisible
    private static final String PROFILE_GENERIC_PATTERN = '%Generic%';
    /**
     * Project item sequence may be Text or Number in different orgs; sorting uses the string form.
     */
    public static String sequenceToString(Object raw) {
        if (raw == null) {
            return null;
        }
        if (raw instanceof String) {
            return (String) raw;
        }
        return String.valueOf(raw);
    }

    /**
     * True when descendantKey is nested under ancestorKey (e.g. 2.1 under 2), not a sibling like 21.1 or 3.1.
     */
    @TestVisible
    public static Boolean isSequenceStrictDescendantOf(String ancestorKey, String descendantKey) {
        if (String.isBlank(ancestorKey) || String.isBlank(descendantKey)) {
            return false;
        }
        String a = ancestorKey.trim();
        String d = descendantKey.trim();
        if (d.equalsIgnoreCase(a)) {
            return false;
        }
        return d.startsWith(a + '.');
    }

    /**
     * Root rows are often stored as N.0 (decimal) while children are N.1, N.2 — same as LWC merge of N.0 into N.
     * Canonicalizes only two-part keys whose second segment is zero so cascade finds sublines.
     */
    @TestVisible
    public static String canonicalRootSequenceKeyForCascade(String seq) {
        if (String.isBlank(seq)) {
            return seq;
        }
        String s = seq.trim();
        List<String> parts = s.split('\\.');
        if (parts.size() == 2 && partToDecimal(parts, 1) == 0) {
            return parts[0] != null ? parts[0].trim() : s;
        }
        return s;
    }

    /**
     * True for root main lines (1, 2, 3 or 2.0 stored as 2), not sub-lines (3.1, 1.4).
     */
    @TestVisible
    public static Boolean isRootMainProjectLineSequence(String seq) {
        String canon = canonicalRootSequenceKeyForCascade(seq);
        return String.isNotBlank(canon) && !canon.contains('.');
    }

    /**
     * Hierarchical sort: 1, 1.1, 1.2, 2, 3, 4, 4.1 (blank sequences sort last).
     */
    @TestVisible
    public static Integer compareSequences(String seqA, String seqB) {
        Boolean blankA = String.isBlank(seqA);
        Boolean blankB = String.isBlank(seqB);
        if (blankA && blankB) {
            return 0;
        }
        if (blankA) {
            return 1;
        }
        if (blankB) {
            return -1;
        }

        List<String> aParts = seqA.trim().split('\\.');
        List<String> bParts = seqB.trim().split('\\.');
        Integer maxLen = Math.max(aParts.size(), bParts.size());

        for (Integer i = 0; i < maxLen; i++) {
            Decimal aVal = partToDecimal(aParts, i);
            Decimal bVal = partToDecimal(bParts, i);
            if (aVal > bVal) {
                return 1;
            }
            if (aVal < bVal) {
                return -1;
            }
        }
        return 0;
    }

    public static Boolean hasTemplateItemNumberField(Schema.SObjectType sobType) {
        return sobType != null &&
            sobType.getDescribe().fields.getMap().containsKey('templateitemnumber__c');
    }

    /**
     * Sets TemplateItemNumber__c when the field exists (frozen template line identity).
     */
    public static void putTemplateItemNumber(SObject rec, Object rawItemNumber) {
        if (rec == null || !hasTemplateItemNumberField(rec.getSObjectType())) {
            return;
        }
        Decimal itemNumber = coerceToDecimal(rawItemNumber);
        if (itemNumber == null) {
            return;
        }
        rec.put('TemplateItemNumber__c', itemNumber);
    }

    public static Decimal getTemplateItemNumber(SObject rec) {
        if (rec == null || !hasTemplateItemNumberField(rec.getSObjectType())) {
            return null;
        }
        Object raw = rec.get('TemplateItemNumber__c');
        return coerceToDecimal(raw);
    }

    /**
     * Coerces JSON-deserialized or field values (String, Integer, Long, Double, Decimal) to Decimal.
     */
    public static Decimal coerceToDecimal(Object value) {
        if (value == null) {
            return null;
        }
        if (value instanceof Decimal) {
            return (Decimal) value;
        }
        if (value instanceof Integer) {
            return Decimal.valueOf((Integer) value);
        }
        if (value instanceof Long) {
            return Decimal.valueOf((Long) value);
        }
        if (value instanceof Double) {
            return Decimal.valueOf((Double) value);
        }
        if (value instanceof String) {
            String s = ((String) value).trim();
            return String.isBlank(s) ? null : Decimal.valueOf(s);
        }
        try {
            return Decimal.valueOf(String.valueOf(value));
        } catch (Exception e) {
            return null;
        }
    }

    /**
     * Profile Ids excluded from lightning-record-picker User filters (Integration / Generic in name).
     */
    @AuraEnabled(cacheable=true)
    public static List<String> getExcludedAssignableUserProfileIds() {
        List<String> out = new List<String>();
        for (Id profileId : loadExcludedAssignableProfileIds()) {
            out.add((String) profileId);
        }
        return out;
    }

    @AuraEnabled(cacheable=true)
    public static List<InstallationProjectViewerController.PicklistOption> getAssignableUsersPicklist() {
        List<InstallationProjectViewerController.PicklistOption> out = new List<InstallationProjectViewerController.PicklistOption>();
        for (User u : queryAssignableUsers(500)) {
            InstallationProjectViewerController.PicklistOption o = new InstallationProjectViewerController.PicklistOption();
            o.label = u.Name;
            o.value = (String) u.Id;
            out.add(o);
        }
        return out;
    }

    public static Boolean isAssignableUserId(Id userId) {
        if (userId == null || userId.getSobjectType() != User.SObjectType) {
            return false;
        }
        User candidate = new AssignableUserLookup().loadCandidate(userId);
        if (candidate == null) {
            return false;
        }
        String profileName = candidate.Profile != null ? candidate.Profile.Name : null;
        return !isExcludedAssignableProfileName(profileName);
    }

    /**
     * Reads User assignment fields in system mode so validation works for all editor profiles.
     */
    private without sharing class AssignableUserLookup {
        private User loadCandidate(Id userId) {
            List<User> hits = [
                SELECT Id, Profile.Name
                FROM User
                WHERE Id = :userId
                AND IsActive = TRUE
                AND UserType = 'Standard'
                WITH SYSTEM_MODE
                LIMIT 1
            ];
            return hits.isEmpty() ? null : hits[0];
        }

        private List<User> loadCandidates(Integer rowLimit) {
            Integer lim = rowLimit == null || rowLimit < 1 ? 200 : rowLimit;
            return [
                SELECT Id, Name, Profile.Name
                FROM User
                WHERE IsActive = TRUE
                AND UserType = 'Standard'
                WITH SYSTEM_MODE
                ORDER BY Name
                LIMIT :lim
            ];
        }
    }

    @TestVisible
    private static Boolean isExcludedAssignableProfileName(String profileName) {
        if (String.isBlank(profileName)) {
            return false;
        }
        String normalized = profileName.toLowerCase();
        return normalized.contains('integration') || normalized.contains('generic');
    }

    private static Set<Id> loadExcludedAssignableProfileIds() {
        Set<Id> excluded = new Set<Id>();
        for (Profile p : [
            SELECT Id
            FROM Profile
            WHERE Name LIKE :PROFILE_INTEGRATION_PATTERN OR Name LIKE :PROFILE_GENERIC_PATTERN
        ]) {
            excluded.add(p.Id);
        }
        return excluded;
    }

    private static List<User> queryAssignableUsers(Integer rowLimit) {
        Integer lim = rowLimit == null || rowLimit < 1 ? 200 : rowLimit;
        List<User> assignableUsers = new List<User>();
        for (User candidate : new AssignableUserLookup().loadCandidates(lim)) {
            String profileName = candidate.Profile != null ? candidate.Profile.Name : null;
            if (!isExcludedAssignableProfileName(profileName)) {
                assignableUsers.add(candidate);
            }
        }
        return assignableUsers;
    }

    private static Decimal partToDecimal(List<String> parts, Integer idx) {
        if (parts == null || idx >= parts.size()) {
            return 0;
        }
        String raw = parts[idx] != null ? parts[idx].trim() : '';
        if (String.isBlank(raw)) {
            return 0;
        }
        try {
            return Decimal.valueOf(raw);
        } catch (Exception e) {
            return 0;
        }
    }
}