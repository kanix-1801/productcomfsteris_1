/**
 * Generates Opportunity.Name for LSSalesConsumables and LSEquipmentService:
 * "<LS Opportunity Number> - <Account Name> - <Application values>".
 *
 * The number is stored on Opportunity.LSOpportunityNumber__c. Apex assigns the
 * next value only for these two record types, so other Opportunities do not
 * consume a number. Name is written on the in-memory record during before
 * insert and before update, so no follow-up Opportunity update is required.
 *
 * Application__c is semicolon-delimited. Whole values are appended with ", "
 * while Name stays within 120 characters. A value that does not fit is omitted.
 */
public with sharing class LSOpportunityNamingService {

    private static final String CLASS_NAME = 'LSOpportunityNamingService';
    private static final String NUMBER_PREFIX = 'LS-';
    private static final Integer NUMBER_PAD = 6;
    private static final String SEGMENT_SEPARATOR = ' - ';
    private static final String VALUE_SEPARATOR = ', ';
    private static final Integer NAME_MAX_LENGTH = 120;

    /**
     * Must match LS_Opp_057_OppLockedWhenClosed. Edits of an already closed
     * Opportunity are rejected, so a before-update rename is skipped.
     * Create is still named, because that rule uses PRIORVALUE(StageName).
     */
    private static final Set<String> LOCKED_STAGES =
        new Set<String>{ 'Closed Won', 'Closed Lost' };

    public static final Set<String> IN_SCOPE_RECORD_TYPE_DEVELOPER_NAMES =
        new Set<String>{ 'LSSalesConsumables', 'LSEquipmentService' };

    @TestVisible
    private static Set<Id> inScopeRecordTypeIds;

    /**
     * Assigns the LS sequence and writes Name onto Trigger.new.
     * Before insert the records have no Id, so a Closed Won or Closed Lost
     * create is still named. Before update the Id is present, so an already
     * closed Opportunity is left unchanged.
     */
    public static void applyNames(List<Opportunity> opportunities) {
        try {
            List<Opportunity> eligible = eligibleOpportunities(
                opportunities,
                isUpdate(opportunities)
            );
            if (eligible.isEmpty()) {
                Logger.debug(CLASS_NAME + '.applyNames: no eligible Opportunities');
                return;
            }

            assignMissingNumbers(eligible);
            Map<Id, String> accountNames = accountNamesById(eligible);

            for (Opportunity opp : eligible) {
                if (opp.LSOpportunityNumber__c == null) {
                    continue;
                }
                opp.Name = buildName(
                    formatNumber(opp.LSOpportunityNumber__c),
                    accountNames.get(opp.AccountId),
                    opp.Application__c
                );
            }

            Logger.info(
                CLASS_NAME + '.applyNames: opportunityCount=' + eligible.size()
            );
        } catch (Exception e) {
            Logger.error(CLASS_NAME + '.applyNames', e);
            throw e;
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * Format: LS-000123 - Account Name - Application1, Application2.
     * The sequence is never cut. If Account Name cannot fit in full, it is
     * shortened and Application values are left off. Application values are
     * never cut in the middle; the first one that does not fit stops the list.
     */
    @TestVisible
    private static String buildName(
        String opportunityNumber,
        String accountName,
        String rawApplications
    ) {
        String generatedName = opportunityNumber == null
            ? ''
            : opportunityNumber.trim();
        if (String.isBlank(generatedName)) {
            return generatedName;
        }

        if (String.isNotBlank(accountName)) {
            String accountValue = accountName.trim();
            String withAccount = generatedName + SEGMENT_SEPARATOR + accountValue;
            if (withAccount.length() > NAME_MAX_LENGTH) {
                Integer room =
                    NAME_MAX_LENGTH - generatedName.length() - SEGMENT_SEPARATOR.length();
                return room <= 0
                    ? generatedName.left(NAME_MAX_LENGTH)
                    : generatedName + SEGMENT_SEPARATOR + accountValue.left(room);
            }
            generatedName = withAccount;
        }

        if (String.isBlank(rawApplications)) {
            return generatedName;
        }

        Boolean firstApplication = true;
        for (String rawValue : rawApplications.split(';')) {
            String application = rawValue == null ? null : rawValue.trim();
            if (String.isBlank(application)) {
                continue;
            }

            String separator = firstApplication ? SEGMENT_SEPARATOR : VALUE_SEPARATOR;
            String candidate = generatedName + separator + application;
            if (candidate.length() > NAME_MAX_LENGTH) {
                break;
            }
            generatedName = candidate;
            firstApplication = false;
        }
        return generatedName;
    }

    private static Boolean isUpdate(List<Opportunity> opportunities) {
        return opportunities != null &&
            !opportunities.isEmpty() &&
            opportunities[0].Id != null;
    }

    private static List<Opportunity> eligibleOpportunities(
        List<Opportunity> opportunities,
        Boolean skipLockedStages
    ) {
        List<Opportunity> eligible = new List<Opportunity>();
        if (opportunities == null) {
            return eligible;
        }
        for (Opportunity opp : opportunities) {
            if (!isInScope(opp)) {
                continue;
            }
            if (skipLockedStages == true && isLocked(opp)) {
                continue;
            }
            eligible.add(opp);
        }
        return eligible;
    }

    /**
     * Next number is one higher than the highest LSOpportunityNumber__c already
     * stored on the two LS record types. Other record types are not queried, so
     * they do not advance the sequence. One bulk save receives consecutive numbers.
     */
    private static void assignMissingNumbers(List<Opportunity> opportunities) {
        List<Opportunity> missing = new List<Opportunity>();
        for (Opportunity opp : opportunities) {
            if (opp.LSOpportunityNumber__c == null) {
                missing.add(opp);
            }
        }
        if (missing.isEmpty()) {
            return;
        }

        Integer nextNumber = latestNumber() + 1;
        for (Opportunity opp : missing) {
            opp.LSOpportunityNumber__c = nextNumber;
            nextNumber++;
        }
    }

    private static Integer latestNumber() {
        return new SequenceReader().highestNumber(getInScopeRecordTypeIds());
    }

    /**
     * Reads the sequence without sharing. A Life Science user cannot see every
     * LS Opportunity an admin can see, so a with-sharing query would calculate
     * a different next number for each user.
     */
    private without sharing class SequenceReader {
        Integer highestNumber(Set<Id> recordTypeIds) {
            if (recordTypeIds == null || recordTypeIds.isEmpty()) {
                return 0;
            }

            // FOR UPDATE cannot be combined with ORDER BY. Find the highest
            // number first, lock that row, then read the max again.
            List<Opportunity> candidates = [
                SELECT Id
                FROM Opportunity
                WHERE RecordTypeId IN :recordTypeIds
                AND LSOpportunityNumber__c != null
                ORDER BY LSOpportunityNumber__c DESC
                LIMIT 1
            ];
            if (!candidates.isEmpty()) {
                List<Opportunity> lockedRows = [
                    SELECT Id
                    FROM Opportunity
                    WHERE Id = :candidates[0].Id
                    FOR UPDATE
                ];
            }

            List<AggregateResult> totals = [
                SELECT MAX(LSOpportunityNumber__c) maxNumber
                FROM Opportunity
                WHERE RecordTypeId IN :recordTypeIds
                AND LSOpportunityNumber__c != null
            ];
            if (totals.isEmpty() || totals[0].get('maxNumber') == null) {
                return 0;
            }
            return ((Decimal) totals[0].get('maxNumber')).intValue();
        }
    }

    @TestVisible
    private static String formatNumber(Decimal sequence) {
        if (sequence == null) {
            return null;
        }
        return NUMBER_PREFIX + String.valueOf(sequence.intValue()).leftPad(NUMBER_PAD, '0');
    }

    private static Map<Id, String> accountNamesById(List<Opportunity> opportunities) {
        Set<Id> accountIds = new Set<Id>();
        for (Opportunity opp : opportunities) {
            if (opp.AccountId != null) {
                accountIds.add(opp.AccountId);
            }
        }
        Map<Id, String> namesById = new Map<Id, String>();
        if (accountIds.isEmpty()) {
            return namesById;
        }
        for (Account account : [
            SELECT Id, Name
            FROM Account
            WHERE Id IN :accountIds
        ]) {
            namesById.put(account.Id, account.Name);
        }
        return namesById;
    }

    private static Boolean isInScope(Opportunity opp) {
        return opp != null &&
            opp.RecordTypeId != null &&
            getInScopeRecordTypeIds().contains(opp.RecordTypeId);
    }

    private static Boolean isLocked(Opportunity opp) {
        return opp != null && LOCKED_STAGES.contains(opp.StageName);
    }

    private static Set<Id> getInScopeRecordTypeIds() {
        if (inScopeRecordTypeIds != null) {
            return inScopeRecordTypeIds;
        }

        inScopeRecordTypeIds = new Set<Id>();
        Map<String, Schema.RecordTypeInfo> byDeveloperName =
            Opportunity.SObjectType.getDescribe()
                .getRecordTypeInfosByDeveloperName();

        for (String developerName : IN_SCOPE_RECORD_TYPE_DEVELOPER_NAMES) {
            Schema.RecordTypeInfo info = byDeveloperName.get(developerName);
            if (info != null) {
                inScopeRecordTypeIds.add(info.getRecordTypeId());
            } else {
                Logger.warn(
                    CLASS_NAME + '.getInScopeRecordTypeIds: record type not found=' +
                    developerName
                );
            }
        }
        return inScopeRecordTypeIds;
    }
}