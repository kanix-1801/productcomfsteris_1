/**
 * @description Test doubles for SummitSkillProcessor. Production code reads these only through methods that require
 *              Test.isRunningTest(), so scheduled or interactive batch runs never use synthetic Skill rows or suppressed DML
 *              even if a static were set incorrectly in another transaction (hooks are also reset in tests via reset()).
 *              Nebula Logger (https://github.com/jongpie/NebulaLogger) records WARN/ERROR for invalid test injection and SOQL failures.
 * @see SummitSkillProcessorTest
 */
public with sharing class SummitSkillProcessorTestSupport {
    /** When non-null in a test context, getSkillMap uses this map instead of querying Skill (Skill insert is often blocked in tests). */
    public static Map<String, Skill> skillMapOverride;

    /** When true in a test context, ServiceResourceSkill rows are not inserted (avoids FK issues with synthetic Skill Ids). */
    public static Boolean suppressServiceResourceSkillInsert;

    /**
     * When non-null in a test context, pair keys from buildRequirementPairKey are treated as already having a ServiceResourceSkill.
     */
    public static Set<String> serviceResourceSkillPairKeysTreatedAsExisting;

    /** In tests only: Skill Id used to fill missing skill map keys when Skill rows cannot be inserted in the org. */
    public static Id injectSkillIdForMap;

    public static void reset() {
        skillMapOverride = null;
        suppressServiceResourceSkillInsert = false;
        serviceResourceSkillPairKeysTreatedAsExisting = null;
        injectSkillIdForMap = null;
    }

    /**
     * @description Slice of skillMapOverride for keys in the current chunk; null means caller should query Skill normally.
     */
    public static Map<String, Skill> skillMapOverrideSliceForChunk(Set<String> skillNames) {
        if (!Test.isRunningTest() || skillMapOverride == null || skillMapOverride.isEmpty()) {
            return null;
        }
        Map<String, Skill> slice = new Map<String, Skill>();
        for (String key : skillNames) {
            if (skillMapOverride.containsKey(key)) {
                slice.put(key, skillMapOverride.get(key));
            }
        }
        return slice;
    }

    /**
     * @description Merges injectSkillIdForMap into the map for any skillNames keys still missing (tests only).
     */
    public static void applyInjectSkillForMissingMapKeys(Map<String, Skill> skillMap, Set<String> skillNames) {
        if (!Test.isRunningTest() || injectSkillIdForMap == null || skillMap == null || skillNames == null) {
            return;
        }
        List<Skill> injected;
        try {
            injected = [SELECT Id, MasterLabel FROM Skill WHERE Id = :injectSkillIdForMap LIMIT 1];
            if (injected.isEmpty()) {
                Logger.newEntry(
                    LoggingLevel.WARN,
                    'SummitSkillProcessorTestSupport: injectSkillIdForMap is set but no Skill row was returned for that Id (expected one row).'
                ).setRecord(injectSkillIdForMap);
                return;
            }
            Skill sk = injected[0];
            for (String key : skillNames) {
                if (!skillMap.containsKey(key)) {
                    skillMap.put(key, sk);
                }
            }
        } catch (QueryException e) {
            Logger.newEntry(
                LoggingLevel.ERROR,
                'SummitSkillProcessorTestSupport: query Skill for injectSkillIdForMap failed'
            )
                .setRecord(injectSkillIdForMap)
                .setExceptionDetails(e);
            throw new SummitSkillIntegrationException(
                'Summit skill integration (test support): failed to query Skill for injectSkillIdForMap '
                    + injectSkillIdForMap
                    + '. '
                    + e.getMessage()
            );
        } finally {
            Logger.saveLog();
        }
    }

    public static Boolean isServiceResourceSkillPairTreatedAsExisting(String pairKey) {
        return Test.isRunningTest() &&
            serviceResourceSkillPairKeysTreatedAsExisting != null &&
            serviceResourceSkillPairKeysTreatedAsExisting.contains(pairKey);
    }

    public static Boolean isServiceResourceSkillInsertSuppressedInTest() {
        return Test.isRunningTest() && suppressServiceResourceSkillInsert == true;
    }

    /**
     * @description Stable key for ServiceResource + Skill pair (used with serviceResourceSkillPairKeysTreatedAsExisting).
     */
    public static String buildRequirementPairKey(Id serviceResourceId, Id skillId) {
        return String.valueOf(serviceResourceId) + '|' + String.valueOf(skillId);
    }
}