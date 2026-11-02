/**
 * @description GC-3541 Part 1. Compares an incoming Lead with open Leads and Contacts.
 *              Bulk upload calls checkForDuplicateLeadsAndContacts from the Lead trigger.
 *              The custom Lead page calls findDuplicates. A standard Lead Save does not.
 *              The method rejects matching rows and does not perform DML.
 *
 *              Email is compared after trimming and lowercasing. Phone is compared on digits
 *              only, so formatting differences still count as the same number once the
 *              existing record has been found. Company/Facility is Lead.Company or
 *              Contact.Account.Name, compared after trimming and lowercasing.
 *              Converted Leads are ignored.
 */
public with sharing class LeadDuplicateService {

    public static final String STATUS_DEFINITIVE = 'Definitive Match';
    public static final String STATUS_POTENTIAL = 'Potential Match';
    public static final String STATUS_AMBIGUOUS = 'Ambiguous Match';

    public static final String REASON_EXACT_EMAIL = 'Exact Email Match';
    public static final String REASON_NAME_PHONE_COMPANY = 'First Name, Last Name, Phone, and Company match';
    public static final String REASON_NAME_PHONE = 'First Name + Last Name + Phone match, but Email does not match';
    public static final String REASON_PHONE_COMPANY = 'Exact Phone + Company match, but Name or Email differs';
    public static final String REASON_MULTIPLE = 'Email or secondary criteria match multiple existing Leads/Contacts';

    public class MatchedRecord {
        public Id recordId;
        public String name;
        public String email;
        public String phone;
        public String company;
        public String recordType;
        public Id accountId;
    }

    @TestVisible
    private static Boolean bulkRejectOverride;

    @TestVisible
    private static Quiddity quiddityOverride;

    public class MatchResult {
        public String status;
        public String reason;
        public List<Id> matchedRecordIds = new List<Id>();
        public List<String> matchedRecordLabels = new List<String>();
        public List<MatchedRecord> matchedRecords = new List<MatchedRecord>();
        public Boolean matchedLeadInThisInsert = false;

        public String buildDetail() {
            if (String.isBlank(status)) {
                return null;
            }
            List<String> labels = new List<String>();
            Integer shown = Math.min(matchedRecordLabels.size(), 25);
            for (Integer i = 0; i < shown; i++) {
                labels.add(matchedRecordLabels[i]);
            }
            String matchText = String.join(labels, '; ');
            if (matchedRecordLabels.size() > shown) {
                matchText += '; ...';
            }
            if (matchedLeadInThisInsert) {
                matchText = String.isBlank(matchText)
                    ? 'another Lead in this insert'
                    : matchText + '; another Lead in this insert';
            }
            return status + ' - ' + reason + '. Matched records: ' + matchText + '.';
        }
    }

    /**
     * @description Rejects duplicate rows for a bulk Lead upload. The first row that does not
     *              match an existing Lead or Contact is kept. Later rows that match a kept row
     *              are rejected. A row that already matches an existing record is rejected.
     * @param leads Leads from before insert. Ids are not yet assigned.
     */
    public static void checkForDuplicateLeadsAndContacts(List<Lead> leads) {
        if (leads == null || leads.isEmpty()) {
            return;
        }
        List<Candidate> existingRecords = loadCandidates(leads);
        List<Candidate> acceptedInThisInsert = new List<Candidate>();
        Boolean rejectReviewMatches = rejectPotentialAndAmbiguous();
        for (Integer i = 0; i < leads.size(); i++) {
            List<Candidate> candidates = new List<Candidate>();
            candidates.addAll(existingRecords);
            candidates.addAll(acceptedInThisInsert);
            MatchResult result = evaluate(leads[i], candidates, i);
            if (shouldReject(result, rejectReviewMatches)) {
                leads[i].addError(result.buildDetail());
            } else {
                acceptedInThisInsert.add(new Candidate(leads[i], i));
            }
        }
    }

    /**
     * @description Returns one match result per Lead. Used by the custom Lead page
     *              before save so a manual user can see the matching record.
     * @param leads Leads to evaluate. They do not need to be inserted.
     * @return Match results in the same order as the input.
     */
    public static List<MatchResult> findDuplicates(List<Lead> leads) {
        List<MatchResult> results = new List<MatchResult>();
        if (leads == null || leads.isEmpty()) {
            return results;
        }

        List<Candidate> candidates = loadCandidates(leads);
        for (Integer i = 0; i < leads.size(); i++) {
            candidates.add(new Candidate(leads[i], i));
        }
        for (Integer i = 0; i < leads.size(); i++) {
            results.add(evaluate(leads[i], candidates, i));
        }
        return results;
    }

    private static Boolean shouldReject(MatchResult result, Boolean rejectReviewMatches) {
        if (result == null || String.isBlank(result.status)) {
            return false;
        }
        if (result.status == STATUS_DEFINITIVE) {
            return true;
        }
        return rejectReviewMatches
            && (result.status == STATUS_POTENTIAL || result.status == STATUS_AMBIGUOUS);
    }

    /**
     * @description True for a bulk upload request. A standard or custom screen save is not bulk.
     *              The Lead_Bulk_Import permission does not change this result.
     */
    public static Boolean isBulkRequest() {
        if (bulkRejectOverride != null) {
            return bulkRejectOverride;
        }
        Quiddity currentRequest = quiddityOverride == null ? Request.getCurrent().getQuiddity() : quiddityOverride;
        return currentRequest == Quiddity.BULK_API
            || currentRequest == Quiddity.SOAP
            || currentRequest == Quiddity.BATCH_APEX;
    }

    private static Boolean rejectPotentialAndAmbiguous() {
        return isBulkRequest();
    }

    private static MatchResult evaluate(Lead incoming, List<Candidate> candidates, Integer batchIndex) {
        String incomingEmail = normalizeEmail(incoming.Email);
        String incomingFirst = normalizeText(incoming.FirstName);
        String incomingLast = normalizeText(incoming.LastName);
        String incomingPhone = normalizePhone(incoming.Phone);
        String incomingCompany = normalizeText(incoming.Company);

        List<Id> emailHits = new List<Id>();
        List<String> emailLabels = new List<String>();
        List<MatchedRecord> emailRecords = new List<MatchedRecord>();
        List<String> sameInsertEmailLabels = new List<String>();
        List<MatchedRecord> sameInsertEmailRecords = new List<MatchedRecord>();
        List<Id> potentialHits = new List<Id>();
        List<String> potentialLabels = new List<String>();
        List<MatchedRecord> potentialRecords = new List<MatchedRecord>();
        List<String> sameInsertPotentialLabels = new List<String>();
        List<MatchedRecord> sameInsertPotentialRecords = new List<MatchedRecord>();
        Map<Id, String> potentialReasons = new Map<Id, String>();
        String sameInsertPotentialReason;

        for (Candidate candidate : candidates) {
            if (candidate.batchIndex != null && candidate.batchIndex == batchIndex) {
                continue;
            }
            if (incoming.Id != null && candidate.recordId == incoming.Id) {
                continue;
            }
            if (incomingEmail != null && incomingEmail == candidate.email) {
                if (candidate.recordId == null) {
                    sameInsertEmailLabels.add(candidate.displayLabel());
                    sameInsertEmailRecords.add(candidate.toMatchedRecord());
                } else {
                    emailHits.add(candidate.recordId);
                    emailLabels.add(candidate.displayLabel());
                    emailRecords.add(candidate.toMatchedRecord());
                }
                continue;
            }

            String reason = classifyPotential(
                incomingFirst,
                incomingLast,
                incomingEmail,
                incomingPhone,
                incomingCompany,
                candidate
            );
            if (reason == null) {
                continue;
            }
            if (candidate.recordId == null) {
                sameInsertPotentialLabels.add(candidate.displayLabel());
                sameInsertPotentialRecords.add(candidate.toMatchedRecord());
                sameInsertPotentialReason = reason;
            } else {
                potentialHits.add(candidate.recordId);
                potentialLabels.add(candidate.displayLabel());
                potentialRecords.add(candidate.toMatchedRecord());
                potentialReasons.put(candidate.recordId, reason);
            }
        }

        MatchResult result = new MatchResult();
        Integer emailCount = emailHits.size() + sameInsertEmailLabels.size();
        if (emailCount == 1) {
            result.status = STATUS_DEFINITIVE;
            result.reason = REASON_EXACT_EMAIL;
            result.matchedRecordIds.addAll(emailHits);
            result.matchedRecordLabels.addAll(emailLabels);
            result.matchedRecordLabels.addAll(sameInsertEmailLabels);
            result.matchedRecords.addAll(emailRecords);
            result.matchedRecords.addAll(sameInsertEmailRecords);
            return result;
        }
        if (emailCount > 1) {
            result.status = STATUS_AMBIGUOUS;
            result.reason = REASON_MULTIPLE;
            result.matchedRecordIds.addAll(emailHits);
            result.matchedRecordLabels.addAll(emailLabels);
            result.matchedRecordLabels.addAll(sameInsertEmailLabels);
            result.matchedRecords.addAll(emailRecords);
            result.matchedRecords.addAll(sameInsertEmailRecords);
            return result;
        }

        Integer potentialCount = potentialHits.size() + sameInsertPotentialLabels.size();
        if (potentialCount == 1) {
            result.status = STATUS_POTENTIAL;
            result.reason = potentialHits.isEmpty()
                ? sameInsertPotentialReason
                : potentialReasons.get(potentialHits[0]);
            result.matchedRecordIds.addAll(potentialHits);
            result.matchedRecordLabels.addAll(potentialLabels);
            result.matchedRecordLabels.addAll(sameInsertPotentialLabels);
            result.matchedRecords.addAll(potentialRecords);
            result.matchedRecords.addAll(sameInsertPotentialRecords);
            return result;
        }
        if (potentialCount > 1) {
            result.status = STATUS_AMBIGUOUS;
            result.reason = REASON_MULTIPLE;
            result.matchedRecordIds.addAll(potentialHits);
            result.matchedRecordLabels.addAll(potentialLabels);
            result.matchedRecordLabels.addAll(sameInsertPotentialLabels);
            result.matchedRecords.addAll(potentialRecords);
            result.matchedRecords.addAll(sameInsertPotentialRecords);
        }
        return result;
    }

    private static String classifyPotential(
        String incomingFirst,
        String incomingLast,
        String incomingEmail,
        String incomingPhone,
        String incomingCompany,
        Candidate candidate
    ) {
        Boolean nameMatch = incomingFirst != null
            && incomingLast != null
            && incomingFirst == candidate.firstName
            && incomingLast == candidate.lastName;
        Boolean phoneMatch = incomingPhone != null && incomingPhone == candidate.phone;
        Boolean companyMatch = incomingCompany != null && incomingCompany == candidate.company;
        Boolean emailDoesNotMatch = !(incomingEmail != null && incomingEmail == candidate.email);

        if (nameMatch && phoneMatch && companyMatch) {
            return REASON_NAME_PHONE_COMPANY;
        }
        if (nameMatch && phoneMatch && emailDoesNotMatch) {
            return REASON_NAME_PHONE;
        }
        if (phoneMatch && companyMatch && (!nameMatch || emailDoesNotMatch)) {
            return REASON_PHONE_COMPANY;
        }
        return null;
    }

    private static List<Candidate> loadCandidates(List<Lead> leads) {
        Set<String> emails = new Set<String>();
        Set<String> lastNames = new Set<String>();
        Set<String> phones = new Set<String>();
        Set<String> companies = new Set<String>();

        for (Lead leadRecord : leads) {
            addEmailCriteria(emails, leadRecord.Email);
            addTextCriteria(lastNames, leadRecord.LastName);
            addPhoneCriteria(phones, leadRecord.Phone);
            addTextCriteria(companies, leadRecord.Company);
        }

        List<Candidate> candidates = new List<Candidate>();
        if (emails.isEmpty() && lastNames.isEmpty() && phones.isEmpty() && companies.isEmpty()) {
            return candidates;
        }

        for (Lead existingLead : [
            SELECT Id, FirstName, LastName, Email, Phone, Company
            FROM Lead
            WHERE IsConverted = false
            AND (
                Email IN :emails
                OR LastName IN :lastNames
                OR Phone IN :phones
                OR Company IN :companies
            )
        ]) {
            candidates.add(new Candidate(existingLead));
        }

        for (Contact existingContact : [
            SELECT Id, FirstName, LastName, Email, Phone, AccountId, Account.Name
            FROM Contact
            WHERE Email IN :emails
            OR LastName IN :lastNames
            OR Phone IN :phones
            OR Account.Name IN :companies
        ]) {
            candidates.add(new Candidate(existingContact));
        }
        attachAccountLinks(candidates);
        return candidates;
    }

    private static void attachAccountLinks(List<Candidate> candidates) {
        Set<String> names = new Set<String>();
        for (Candidate candidate : candidates) {
            if (candidate.accountId == null && String.isNotBlank(candidate.displayCompany)) {
                names.add(candidate.displayCompany.trim());
            }
        }
        if (names.isEmpty()) {
            return;
        }
        Map<String, List<Account>> accountsByName = new Map<String, List<Account>>();
        for (Account accountRecord : [SELECT Id, Name FROM Account WHERE Name IN :names]) {
            String key = normalizeText(accountRecord.Name);
            if (!accountsByName.containsKey(key)) {
                accountsByName.put(key, new List<Account>());
            }
            accountsByName.get(key).add(accountRecord);
        }
        for (Candidate candidate : candidates) {
            if (candidate.accountId != null || String.isBlank(candidate.displayCompany)) {
                continue;
            }
            List<Account> matches = accountsByName.get(normalizeText(candidate.displayCompany));
            if (matches != null && matches.size() == 1) {
                candidate.accountId = matches[0].Id;
                candidate.displayCompany = matches[0].Name;
            }
        }
    }

    private static void addEmailCriteria(Set<String> values, String email) {
        if (String.isNotBlank(email)) {
            values.add(email.trim());
        }
    }

    private static void addTextCriteria(Set<String> values, String value) {
        if (String.isNotBlank(value)) {
            values.add(value.trim());
        }
    }

    private static void addPhoneCriteria(Set<String> values, String phone) {
        if (String.isBlank(phone)) {
            return;
        }
        values.add(phone.trim());
        String digits = normalizePhone(phone);
        if (digits != null) {
            values.add(digits);
        }
    }

    private static String normalizeEmail(String email) {
        return String.isBlank(email) ? null : email.trim().toLowerCase();
    }

    private static String normalizeText(String value) {
        return String.isBlank(value) ? null : value.trim().toLowerCase();
    }

    private static String normalizePhone(String phone) {
        if (String.isBlank(phone)) {
            return null;
        }
        String digits = phone.replaceAll('[^0-9]', '');
        return String.isBlank(digits) ? null : digits;
    }

    private class Candidate {
        public Id recordId;
        public Integer batchIndex;
        public String firstName;
        public String lastName;
        public String email;
        public String phone;
        public String company;
        public String displayFirstName;
        public String displayLastName;
        public String displayEmail;
        public String displayPhone;
        public String displayCompany;
        public String recordType;
        public Id accountId;

        public Candidate(Lead leadRecord) {
            this(leadRecord.Id, null, leadRecord.FirstName, leadRecord.LastName, leadRecord.Email, leadRecord.Phone, leadRecord.Company, 'Lead', null);
        }

        public Candidate(Contact contactRecord) {
            this(
                contactRecord.Id,
                null,
                contactRecord.FirstName,
                contactRecord.LastName,
                contactRecord.Email,
                contactRecord.Phone,
                contactRecord.Account == null ? null : contactRecord.Account.Name,
                'Contact',
                contactRecord.AccountId
            );
        }

        public Candidate(Lead leadRecord, Integer batchIndex) {
            this(null, batchIndex, leadRecord.FirstName, leadRecord.LastName, leadRecord.Email, leadRecord.Phone, leadRecord.Company, 'Lead', null);
        }

        public MatchedRecord toMatchedRecord() {
            MatchedRecord row = new MatchedRecord();
            row.recordId = recordId;
            row.name = joinDisplay(displayFirstName, displayLastName);
            row.email = displayEmail;
            row.phone = displayPhone;
            row.company = displayCompany;
            row.recordType = recordType;
            row.accountId = accountId;
            return row;
        }

        public String displayLabel() {
            List<String> parts = new List<String>();
            String personName = joinDisplay(displayFirstName, displayLastName);
            if (String.isNotBlank(personName)) {
                parts.add(personName);
            }
            if (String.isNotBlank(displayEmail)) {
                parts.add(displayEmail.trim());
            }
            if (String.isNotBlank(displayCompany)) {
                parts.add(displayCompany.trim());
            }
            String label = String.join(parts, ', ');
            if (String.isNotBlank(recordType)) {
                label = String.isBlank(label) ? recordType : label + ' (' + recordType + ')';
            }
            return label;
        }

        private Candidate(
            Id recordId,
            Integer batchIndex,
            String firstName,
            String lastName,
            String email,
            String phone,
            String company,
            String recordType,
            Id accountId
        ) {
            this.recordId = recordId;
            this.batchIndex = batchIndex;
            this.displayFirstName = firstName;
            this.displayLastName = lastName;
            this.displayEmail = email;
            this.displayPhone = String.isBlank(phone) ? null : phone.trim();
            this.displayCompany = company;
            this.recordType = recordType;
            this.accountId = accountId;
            this.firstName = normalizeText(firstName);
            this.lastName = normalizeText(lastName);
            this.email = normalizeEmail(email);
            this.phone = normalizePhone(phone);
            this.company = normalizeText(company);
        }
    }

    private static String joinDisplay(String firstName, String lastName) {
        List<String> names = new List<String>();
        if (String.isNotBlank(firstName)) {
            names.add(firstName.trim());
        }
        if (String.isNotBlank(lastName)) {
            names.add(lastName.trim());
        }
        return String.join(names, ' ');
    }
}