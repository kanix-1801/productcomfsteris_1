/**
 * @author PWC Developer
 * @date 2026/10/16
 *
 * @group CSC Visit
 *
 * @description
 * GC-3564 - Physician search, Sunshine expense save, and CSC Visit PDF.
 */
public with sharing class SunshineService {

    private static final String PLANNER_NOT_IDENTIFIED = 'Not Identified Yet';

    public class SunshineException extends Exception {}

    /**
     * @description Search outcome returned to the screen flow.
     */
    public class SearchResult {
        public Integer matchCount = 0;
        public String resultMessage;
        public String npi;
        public String firstName;
        public String lastName;
        public String city;
        public String physicianState;
        public String credential;
        public String taxonomyCode;
        public String taxonomyDescription;
    }

    /**
     * @description Expense and physician values collected by the screen flow.
     */
    public class SaveRequest {
        public Id visitId;
        public Id sunshineId;
        public String npi;
        public Decimal airfare;
        public Decimal hotel;
        public Decimal visitNights;
        public Decimal meals;
        public Decimal transportation;
        public String sunshineType;
        public String productAssociated;
    }

    /**
     * @description Values printed on the Visit PDF.
     */
    public class PdfModel {
        public String visitNumber { get; set; }
        public String accountLine { get; set; }
        public String visitWhen { get; set; }
        public String planner { get; set; }
        public String businessLine { get; set; }
        public String capitalAmount { get; set; }
        public String serviceAmount { get; set; }
        public String decisionTimeframe { get; set; }
        public String anticipatedBusiness { get; set; }
        public String projectedSpend { get; set; }
        public String quoteNumber { get; set; }
        public String expectedOpening { get; set; }
        public String pdmReference { get; set; }
        public String objective1 { get; set; }
        public String objective2 { get; set; }
        public String objective3 { get; set; }
        public String construction { get; set; }
        public String comments { get; set; }
        public String lastVendor { get; set; }
        public String otherKeyInformation { get; set; }
        public String globalAffiliation { get; set; }
        public String idnAffiliation { get; set; }
        public String gpoAffiliation { get; set; }
        public String serviceProvider { get; set; }
        public String planningSession { get; set; }
        public String planningRequirements { get; set; }
        public String projectStatus { get; set; }
        public String customerPerspective { get; set; }
        public String winStrategy { get; set; }
        public String attendeeProfile { get; set; }
        public Boolean serviceSteris { get; set; }
        public Boolean serviceInHouse { get; set; }
        public Boolean serviceThirdParty { get; set; }
        public Boolean planGeneric { get; set; }
        public Boolean planCustomerSpecific { get; set; }
        public Boolean planVrImmersion { get; set; }
        public List<PersonRow> customerAttendees { get; set; }
        public List<PersonRow> sterisAttendees { get; set; }
        public List<PhysicianRow> physicians { get; set; }
        public List<TeamRow> accountTeam { get; set; }

        /**
         * @description Starts every printed value as blank so the PDF layout stays stable.
         */
        public PdfModel() {
            visitNumber = '';
            accountLine = '';
            visitWhen = '';
            planner = PLANNER_NOT_IDENTIFIED;
            businessLine = '';
            capitalAmount = '';
            serviceAmount = '';
            decisionTimeframe = '';
            anticipatedBusiness = '';
            projectedSpend = '';
            quoteNumber = '';
            expectedOpening = '';
            pdmReference = '';
            objective1 = '';
            objective2 = '';
            objective3 = '';
            construction = '';
            comments = '';
            lastVendor = '';
            otherKeyInformation = '';
            globalAffiliation = '';
            idnAffiliation = '';
            gpoAffiliation = '';
            serviceProvider = '';
            planningSession = '';
            planningRequirements = '';
            projectStatus = '';
            customerPerspective = '';
            winStrategy = '';
            attendeeProfile = '';
            serviceSteris = false;
            serviceInHouse = false;
            serviceThirdParty = false;
            planGeneric = false;
            planCustomerSpecific = false;
            planVrImmersion = false;
            customerAttendees = new List<PersonRow>();
            sterisAttendees = new List<PersonRow>();
            physicians = new List<PhysicianRow>();
            accountTeam = new List<TeamRow>();
        }
    }

    /**
     * @description STERIS attendee line on the PDF.
     */
    public class PersonRow {
        public String personName { get; set; }
        public String title { get; set; }
        public String status { get; set; }
        public String email { get; set; }
        public String phone { get; set; }
        public String perception { get; set; }
        public String decisionMaker { get; set; }
    }

    /**
     * @description One Full Account Team line on the PDF.
     */
    public class TeamRow {
        public String manager { get; set; }
        public String category { get; set; }
        public String territory { get; set; }
        public String teamClass { get; set; }
    }

    /**
     * @description Physician and expense line on the PDF.
     */
    public class PhysicianRow {
        public String sunshineType { get; set; }
        public String physicianName { get; set; }
        public String airfare { get; set; }
        public String meals { get; set; }
        public String hotel { get; set; }
        public String transportation { get; set; }
        public String productAssociated { get; set; }
    }

    /**
     * @description File saved on the Visit.
     */
    public class PdfFile {
        public Id contentDocumentId;
        public String fileTitle;
    }

    /**
     * @description Searches the local physician directory.
     * @param firstName Physician first name.
     * @param lastName Physician last name.
     * @param city Physician city.
     * @param npi National Provider Identifier. Optional.
     * @return Match count, display text, and the single match when there is one.
     */
    public static SearchResult search(String firstName, String lastName, String city, String npi) {
        SearchResult result = new SearchResult();
        if (String.isBlank(npi) && (String.isBlank(firstName) || String.isBlank(lastName) || String.isBlank(city))) {
            result.resultMessage = 'Enter first name, last name, and city. NPI is optional.';
            return result;
        }

        List<PhysicianSearchSelector.PhysicianRecord> matches =
            PhysicianSearchSelector.selectByCriteria(firstName, lastName, city, npi);
        result.matchCount = matches.size();
        result.resultMessage = buildSearchMessage(matches);
        if (matches.size() == 1) {
            copyPhysician(result, matches[0]);
        }
        return result;
    }

    /**
     * @description Creates a physician row or updates its expenses. Physician values are read again
     * from the directory so the stored taxonomy is the directory value.
     * @param request Visit, optional existing row, and expense amounts.
     * @return Saved Sunshine Id.
     */
    public static Id save(SaveRequest request) {
        if (request == null || request.visitId == null) {
            throw new SunshineException('A CSC Visit is required.');
        }
        validateAmounts(request);

        Sunshine__c record;
        if (request.sunshineId == null) {
            record = newPhysicianRow(request);
        } else {
            record = existingRow(request.sunshineId);
        }
        record.Airfare__c = request.airfare;
        record.Hotel__c = request.hotel;
        record.Visit_Nights__c = request.visitNights == null ? null : request.visitNights.intValue();
        record.Meals__c = request.meals;
        record.Transportation__c = request.transportation;
        record.Type__c = request.sunshineType;
        record.Product_Associated__c = request.productAssociated;

        Database.SaveResult[] results = record.Id == null
            ? Database.insert(new List<Sunshine__c>{ record }, AccessLevel.USER_MODE)
            : Database.update(new List<Sunshine__c>{ record }, AccessLevel.USER_MODE);
        if (!results[0].isSuccess()) {
            throw new SunshineException(results[0].getErrors()[0].getMessage());
        }
        return results[0].getId();
    }

    /**
     * @description Builds the Visit PDF view model.
     * @param visitId CSC Visit Id.
     * @return PDF values. Empty strings when the Visit cannot be read.
     */
    public static PdfModel buildPdf(Id visitId) {
        PdfModel model = new PdfModel();
        SObject visit = SunshineSelector.selectVisit(visitId);
        if (visit == null) {
            return model;
        }
        Id accountId = referenceId(visit, 'AccountFacility__c');
        Account accountRecord = SunshineSelector.selectAccount(accountId);
        model.visitNumber = stringValue(visit.get('Name'));
        model.accountLine = accountLine(accountRecord, visit);
        model.visitWhen = visitWhen(visit);
        model.businessLine = firstFilled(displayValue(visit, 'VisitType__c'), displayValue(visit, 'ProductQuoted__c'));
        model.capitalAmount = displayValue(visit, 'AnticipatedBusinessValue__c');
        model.serviceAmount = displayValue(visit, 'ProjectedServiceBusiness__c');
        model.decisionTimeframe = displayValue(visit, 'DecisionTimeline__c');
        model.anticipatedBusiness = displayValue(visit, 'AnticipatedBusinessOpportunityContext__c');
        model.projectedSpend = displayValue(visit, 'ProjectedSpend__c');
        model.quoteNumber = displayValue(visit, 'ProductQuoted__c');
        model.expectedOpening = monthYear(visit, 'ExpectedOpeningMonthYear__c');
        model.pdmReference = firstFilled(
            displayValue(visit, 'PDMDrawingProjectReference__c'),
            displayValue(visit, 'DrawingNumber__c'),
            displayValue(visit, 'Opportunity__c')
        );
        model.objective1 = displayValue(visit, 'PrimaryObjective__c');
        model.objective2 = displayValue(visit, 'SecondaryObjective__c');
        model.objective3 = displayValue(visit, 'AdditionalDetails__c');
        model.construction = joinValues(
            displayValue(visit, 'ConstructionRenovationProject__c'),
            displayValue(visit, 'RenovationBuildingProjectContext__c')
        );
        model.comments = displayValue(visit, 'STERISVisitAccomplishment__c');
        model.lastVendor = displayValue(visit, 'IncumbentVendor__c');
        model.otherKeyInformation = displayValue(visit, 'AdditionalBackground__c');
        model.globalAffiliation = accountRecord == null || accountRecord.Parent == null ? '' : stringValue(accountRecord.Parent.Name);
        applyAffiliations(model, accountId);
        model.serviceProvider = displayValue(visit, 'ExistingServiceProvider__c');
        Set<String> providers = picklistValues(model.serviceProvider);
        model.serviceSteris = providers.contains('STERIS');
        model.serviceInHouse = providers.contains('In-House');
        model.serviceThirdParty = providers.contains('Third Party');
        model.planningSession = displayValue(visit, 'PlanningSessionType__c');
        Set<String> sessions = picklistValues(model.planningSession);
        model.planGeneric = sessions.contains('Generic');
        model.planCustomerSpecific = sessions.contains('Customer Specific');
        model.planVrImmersion = sessions.contains('VR Immersion');
        model.planningRequirements = displayValue(visit, 'PlanningRequirements__c');
        model.customerAttendees = customerRows(referenceId(visit, 'PrimaryCustomerContact__c'));
        model.sterisAttendees = attendeeRows(visitId);
        model.physicians = physicianRows(visitId);
        model.accountTeam = accountTeamRows(accountId);
        return model;
    }

    /**
     * @description Renders the Visit PDF and saves it on the Visit Files related list.
     * @param visitId CSC Visit Id.
     * @return ContentDocument Id and file title.
     */
    public static PdfFile generatePdfFile(Id visitId) {
        if (visitId == null || SunshineSelector.selectVisit(visitId) == null) {
            throw new SunshineException('The CSC Visit could not be found.');
        }
        PdfModel model = buildPdf(visitId);
        String title = 'CSC Visit ' + (String.isBlank(model.visitNumber) ? String.valueOf(visitId) : model.visitNumber);
        PageReference pageRef = Page.CSCVisitPdf;
        pageRef.getParameters().put('id', String.valueOf(visitId));
        Blob body = Test.isRunningTest() ? Blob.valueOf('GC-3564') : pageRef.getContentAsPDF();

        ContentVersion version = new ContentVersion(
            Title = title,
            PathOnClient = title + '.pdf',
            VersionData = body,
            FirstPublishLocationId = visitId
        );
        Database.SaveResult[] results = Database.insert(new List<ContentVersion>{ version }, AccessLevel.USER_MODE);
        if (!results[0].isSuccess()) {
            throw new SunshineException(results[0].getErrors()[0].getMessage());
        }
        PdfFile file = new PdfFile();
        file.contentDocumentId = SunshineSelector.selectContentDocumentId(results[0].getId());
        file.fileTitle = title;
        return file;
    }

    private static Sunshine__c newPhysicianRow(SaveRequest request) {
        String npi = request.npi == null ? '' : request.npi.replaceAll('[^0-9]', '');
        List<PhysicianSearchSelector.PhysicianRecord> matches =
            PhysicianSearchSelector.selectByCriteria(null, null, null, npi);
        if (matches.size() != 1) {
            throw new SunshineException('Select a physician from the search results before saving.');
        }
        if (!SunshineSelector.selectByVisitAndNpi(request.visitId, matches[0].npi, null).isEmpty()) {
            throw new SunshineException('This physician is already recorded on the Visit.');
        }
        PhysicianSearchSelector.PhysicianRecord physician = matches[0];
        return new Sunshine__c(
            CSC_Visit_Request__c = request.visitId,
            NPI__c = physician.npi,
            First_Name__c = physician.firstName,
            Last_Name__c = physician.lastName,
            City__c = physician.city,
            State__c = physician.physicianState,
            Credential__c = physician.credential,
            Taxonomy_Code__c = physician.taxonomyCode,
            Taxonomy_Description__c = physician.taxonomyDescription,
            Last_NPI_Search__c = System.now(),
            NPI_Key__c = npiKey(request.visitId, physician.npi)
        );
    }

    private static Sunshine__c existingRow(Id sunshineId) {
        List<Sunshine__c> rows = SunshineSelector.selectById(sunshineId);
        if (rows.isEmpty()) {
            throw new SunshineException('The Sunshine record could not be found.');
        }
        return rows[0];
    }

    private static void validateAmounts(SaveRequest request) {
        assertNonNegative(request.airfare, 'Airfare');
        assertNonNegative(request.hotel, 'Hotel');
        assertNonNegative(request.meals, 'Meals');
        assertNonNegative(request.transportation, 'Transportation');
        if (request.visitNights != null && request.visitNights < 0) {
            throw new SunshineException('Visit Nights cannot be negative.');
        }
    }

    private static void assertNonNegative(Decimal amount, String label) {
        if (amount != null && amount < 0) {
            throw new SunshineException(label + ' cannot be negative.');
        }
    }

    private static String npiKey(Id visitId, String npi) {
        return String.valueOf(visitId) + '-' + npi;
    }

    private static String buildSearchMessage(List<PhysicianSearchSelector.PhysicianRecord> matches) {
        if (matches.isEmpty()) {
            return 'No physician matched the search.';
        }
        List<String> lines = new List<String>();
        for (PhysicianSearchSelector.PhysicianRecord physician : matches) {
            lines.add(
                physician.firstName + ' ' + physician.lastName
                + ', ' + physician.city + ', ' + physician.physicianState
                + ' | NPI ' + physician.npi
                + ' | Taxonomy ' + physician.taxonomyCode + ' - ' + physician.taxonomyDescription
            );
        }
        if (matches.size() > 1) {
            return 'More than one physician matched. Search again with the NPI.\n' + String.join(lines, '\n');
        }
        return lines[0];
    }

    private static void copyPhysician(SearchResult result, PhysicianSearchSelector.PhysicianRecord physician) {
        result.npi = physician.npi;
        result.firstName = physician.firstName;
        result.lastName = physician.lastName;
        result.city = physician.city;
        result.physicianState = physician.physicianState;
        result.credential = physician.credential;
        result.taxonomyCode = physician.taxonomyCode;
        result.taxonomyDescription = physician.taxonomyDescription;
    }

    private static String accountLine(Account accountRecord, SObject visit) {
        String accountName = accountRecord == null ? '' : stringValue(accountRecord.Name);
        String city = displayValue(visit, 'CustomerAddressLocation__City__s');
        String state = displayValue(visit, 'CustomerAddressLocation__StateCode__s');
        if (String.isBlank(city) && accountRecord != null) {
            city = stringValue(accountRecord.BillingCity);
            state = stringValue(accountRecord.BillingState);
        }
        String place = joinValues(city, state);
        if (String.isBlank(accountName)) {
            return place;
        }
        return String.isBlank(place) ? accountName : accountName + ' - ' + place;
    }

    private static String visitWhen(SObject visit) {
        String visitDate = longDate(visit, 'Confirmed_Date__c');
        if (String.isBlank(visitDate)) {
            visitDate = longDate(visit, 'Primary_Requested_Date__c');
        }
        String duration = displayValue(visit, 'VisitAgendaDuration__c');
        if (duration == 'One Day') {
            duration = 'All Day';
        }
        if (String.isBlank(visitDate)) {
            return duration;
        }
        return String.isBlank(duration) ? visitDate : visitDate + ' - ' + duration;
    }

    private static String longDate(SObject visit, String fieldApi) {
        if (!fieldWasRead(visit, fieldApi)) {
            return '';
        }
        Object raw = visit.get(fieldApi);
        if (!(raw instanceof Date)) {
            return '';
        }
        return Datetime.newInstance((Date) raw, Time.newInstance(0, 0, 0, 0)).format('EEEE, MMMM d, yyyy');
    }

    private static String monthYear(SObject visit, String fieldApi) {
        if (!fieldWasRead(visit, fieldApi)) {
            return '';
        }
        Object raw = visit.get(fieldApi);
        if (!(raw instanceof Date)) {
            return displayValue(visit, fieldApi);
        }
        return Datetime.newInstance((Date) raw, Time.newInstance(0, 0, 0, 0)).format('MMM/yyyy');
    }

    private static void applyAffiliations(PdfModel model, Id accountId) {
        if (accountId == null) {
            return;
        }
        List<AccountAccountRelationship__c> relationships;
        try {
            relationships = AccountAccountRelationshipSelector.selectGpoIdnAffiliationsByAccountIds(new Set<Id>{ accountId });
        } catch (QueryException ex) {
            return;
        }
        List<String> idnNames = new List<String>();
        List<String> gpoNames = new List<String>();
        for (AccountAccountRelationship__c relationship : relationships) {
            String parentName = relationship.ParentAccount__r == null ? '' : relationship.ParentAccount__r.Name;
            if (String.isBlank(parentName)) {
                continue;
            }
            String relationshipType = stringValue(relationship.RelationshipType__c) + ' ' + stringValue(relationship.InverseRelationshipType__c);
            if (relationshipType.contains('GPO')) {
                gpoNames.add(parentName);
            } else if (relationshipType.contains('IDN')) {
                idnNames.add(parentName);
            }
        }
        model.idnAffiliation = String.join(idnNames, ', ');
        model.gpoAffiliation = String.join(gpoNames, ', ');
    }

    private static List<TeamRow> accountTeamRows(Id accountId) {
        List<TeamRow> rows = new List<TeamRow>();
        if (accountId == null) {
            return rows;
        }
        List<AccountTeamMember> members;
        try {
            members = AccountTeamMemberSelector.selectByAccountId(accountId, false);
        } catch (QueryException ex) {
            return rows;
        }
        for (AccountTeamMember member : members) {
            TeamRow row = new TeamRow();
            row.manager = member.User == null ? '' : stringValue(member.User.Name);
            row.category = firstFilled(member.SalesCategoryCode__c, member.SalesCategoryDescription__c);
            row.territory = stringValue(member.TerritoryCode__c);
            row.teamClass = stringValue(member.AssignmentType__c);
            rows.add(row);
        }
        return rows;
    }

    private static List<PersonRow> customerRows(Id contactId) {
        List<PersonRow> rows = new List<PersonRow>();
        if (contactId == null) {
            return rows;
        }
        List<Contact> customers;
        try {
            customers = SunshineSelector.selectContacts(new Set<Id>{ contactId });
        } catch (QueryException ex) {
            return rows;
        }
        for (Contact customerContact : customers) {
            rows.add(personRow(
                personLabel(
                    readString(customerContact, 'LastName'),
                    readString(customerContact, 'FirstName'),
                    readString(customerContact, 'Name')
                ),
                readString(customerContact, 'Title'),
                '',
                readString(customerContact, 'Email'),
                readString(customerContact, 'Phone'),
                '',
                ''
            ));
        }
        return rows;
    }

    private static List<PersonRow> attendeeRows(Id visitId) {
        Set<Id> userIds = new Set<Id>();
        Set<Id> contactIds = new Set<Id>();
        List<SObject> attendees;
        try {
            attendees = SunshineSelector.selectAttendees(visitId);
        } catch (QueryException ex) {
            return new List<PersonRow>();
        }
        for (SObject attendee : attendees) {
            Id personId = (Id) attendee.get('STERISAttendee__c');
            if (personId == null) {
                continue;
            }
            if (personId.getSObjectType() == User.SObjectType) {
                userIds.add(personId);
            } else if (personId.getSObjectType() == Contact.SObjectType) {
                contactIds.add(personId);
            }
        }
        List<PersonRow> rows = new List<PersonRow>();
        List<User> attendeeUsers = new List<User>();
        List<Contact> attendeeContacts = new List<Contact>();
        try {
            attendeeUsers = SunshineSelector.selectUsers(userIds);
            attendeeContacts = SunshineSelector.selectContacts(contactIds);
        } catch (QueryException ex) {
            return rows;
        }
        for (User attendeeUser : attendeeUsers) {
            rows.add(personRow(
                personLabel(
                    readString(attendeeUser, 'LastName'),
                    readString(attendeeUser, 'FirstName'),
                    readString(attendeeUser, 'Name')
                ),
                readString(attendeeUser, 'Title'),
                '',
                readString(attendeeUser, 'Email'),
                readString(attendeeUser, 'Phone'),
                '',
                ''
            ));
        }
        for (Contact attendeeContact : attendeeContacts) {
            rows.add(personRow(
                personLabel(
                    readString(attendeeContact, 'LastName'),
                    readString(attendeeContact, 'FirstName'),
                    readString(attendeeContact, 'Name')
                ),
                readString(attendeeContact, 'Title'),
                '',
                readString(attendeeContact, 'Email'),
                readString(attendeeContact, 'Phone'),
                '',
                ''
            ));
        }
        return rows;
    }

    private static PersonRow personRow(
        String personName,
        String title,
        String status,
        String email,
        String phone,
        String perception,
        String decisionMaker
    ) {
        PersonRow row = new PersonRow();
        row.personName = stringValue(personName);
        row.title = stringValue(title);
        row.status = stringValue(status);
        row.email = stringValue(email);
        row.phone = stringValue(phone);
        row.perception = stringValue(perception);
        row.decisionMaker = stringValue(decisionMaker);
        return row;
    }

    private static String personLabel(String lastName, String firstName, String fullName) {
        if (String.isNotBlank(lastName) && String.isNotBlank(firstName)) {
            return lastName + ', ' + firstName;
        }
        return stringValue(fullName);
    }

    private static List<PhysicianRow> physicianRows(Id visitId) {
        List<PhysicianRow> rows = new List<PhysicianRow>();
        for (Sunshine__c sunshine : SunshineSelector.selectByVisit(visitId)) {
            PhysicianRow row = new PhysicianRow();
            row.sunshineType = stringValue(sunshine.Type__c);
            row.physicianName = personLabel(sunshine.Last_Name__c, sunshine.First_Name__c, sunshine.Name).toUpperCase();
            row.airfare = dollars(sunshine.Airfare__c);
            row.meals = dollars(sunshine.Meals__c);
            row.hotel = dollars(sunshine.Hotel__c);
            row.transportation = dollars(sunshine.Transportation__c);
            row.productAssociated = stringValue(sunshine.Product_Associated__c);
            rows.add(row);
        }
        return rows;
    }

    private static Set<String> picklistValues(String value) {
        Set<String> values = new Set<String>();
        if (String.isBlank(value)) {
            return values;
        }
        for (String part : value.split(';')) {
            values.add(part.trim());
        }
        return values;
    }

    private static Id referenceId(SObject record, String fieldApi) {
        if (!fieldWasRead(record, fieldApi)) {
            return null;
        }
        Object raw = record.get(fieldApi);
        return raw instanceof Id ? (Id) raw : null;
    }

    private static String firstFilled(String firstValue, String secondValue) {
        return String.isNotBlank(firstValue) ? firstValue : stringValue(secondValue);
    }

    private static String firstFilled(String firstValue, String secondValue, String thirdValue) {
        String filled = firstFilled(firstValue, secondValue);
        return String.isNotBlank(filled) ? filled : stringValue(thirdValue);
    }

    private static String joinValues(String firstValue, String secondValue) {
        if (String.isBlank(firstValue)) {
            return stringValue(secondValue);
        }
        return String.isBlank(secondValue) ? firstValue : firstValue + ' - ' + secondValue;
    }

    private static Boolean fieldWasRead(SObject record, String fieldApi) {
        return record != null && record.getPopulatedFieldsAsMap().containsKey(fieldApi);
    }

    private static String readString(SObject record, String fieldApi) {
        if (!fieldWasRead(record, fieldApi)) {
            return '';
        }
        return stringValue(record.get(fieldApi));
    }

    private static String displayValue(SObject record, String fieldApi) {
        if (!fieldWasRead(record, fieldApi)) {
            return '';
        }
        Object raw = record.get(fieldApi);
        if (raw == null) {
            return '';
        }
        Schema.DescribeFieldResult describe = record.getSObjectType().getDescribe().fields.getMap().get(fieldApi).getDescribe();
        if (describe.getType() == Schema.DisplayType.REFERENCE) {
            return stringValue(SunshineSelector.selectRecordName((Id) raw));
        }
        if (raw instanceof Date) {
            return ((Date) raw).format();
        }
        if (raw instanceof Datetime) {
            return ((Datetime) raw).date().format();
        }
        if (raw instanceof Decimal) {
            Decimal amount = (Decimal) raw;
            if (describe.getType() == Schema.DisplayType.CURRENCY) {
                return groupDigits(amount, amount == amount.setScale(0, RoundingMode.DOWN) ? 0 : 2);
            }
            return amount.stripTrailingZeros().toPlainString();
        }
        return stringValue(raw);
    }

    private static String dollars(Decimal amount) {
        return '$' + groupDigits(amount == null ? 0 : amount, 2);
    }

    private static String groupDigits(Decimal amount, Integer scale) {
        Decimal rounded = amount.setScale(scale, RoundingMode.HALF_UP);
        String plain = rounded.abs().toPlainString();
        String whole = plain.substringBefore('.');
        String fraction = plain.contains('.') ? '.' + plain.substringAfter('.') : '';
        String grouped = '';
        while (whole.length() > 3) {
            grouped = ',' + whole.right(3) + grouped;
            whole = whole.left(whole.length() - 3);
        }
        return (rounded < 0 ? '-' : '') + whole + grouped + fraction;
    }

    private static String stringValue(Object value) {
        return value == null ? '' : String.valueOf(value);
    }
}