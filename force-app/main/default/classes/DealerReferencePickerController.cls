/**
 * @description #GC-3598 Apex controller for the dealerReferencePicker Flow screen LWC.
 * Searches and creates globally reusable DealerReferenceValue__c rows by Type.
 */
public with sharing class DealerReferencePickerController {
    private static final Set<String> VALID_TYPES = new Set<String>{
        'EndCustomer',
        'Architect',
        'MainContractor',
        'EquipmentPlanner',
        'Competitor'
    };

    /**
     * @description Search result row returned to the picker LWC.
     */
    public class Option {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
    }

    /**
     * @description Finds Dealer Reference Values for a type, optionally filtered by name.
     * @param typeValue Type__c picklist API value
     * @param searchTerm Optional name prefix. Blank returns the first 50 names for the type.
     * @return Matching options (max 50), ordered by Name
     */
    @AuraEnabled(cacheable=true)
    public static List<Option> search(String typeValue, String searchTerm) {
        validateType(typeValue);
        assertReadable();

        String prefix = normalizeSearch(searchTerm);
        List<DealerReferenceValue__c> rows;
        if (String.isBlank(prefix)) {
            rows = [
                SELECT Id, Name
                FROM DealerReferenceValue__c
                WHERE Type__c = :typeValue
                WITH USER_MODE
                ORDER BY Name
                LIMIT 50
            ];
        } else {
            String likeTerm = prefix + '%';
            rows = [
                SELECT Id, Name
                FROM DealerReferenceValue__c
                WHERE Type__c = :typeValue
                AND Name LIKE :likeTerm
                WITH USER_MODE
                ORDER BY Name
                LIMIT 50
            ];
        }

        List<Option> options = new List<Option>();
        for (DealerReferenceValue__c row : rows) {
            Option option = new Option();
            option.id = row.Id;
            option.name = row.Name;
            options.add(option);
        }
        return options;
    }

    /**
     * @description Creates a Dealer Reference Value, or returns the existing row for the same Type + Name.
     * @param typeValue Type__c picklist API value
     * @param name Value name to create
     * @return Created or existing option
     */
    @AuraEnabled
    public static Option create(String typeValue, String name) {
        validateType(typeValue);
        if (String.isBlank(name)) {
            throwAura('Enter a name before creating a new value.');
        }

        String trimmedName = name.trim();
        assertReadable();

        List<DealerReferenceValue__c> existing = [
            SELECT Id, Name
            FROM DealerReferenceValue__c
            WHERE Type__c = :typeValue
            AND Name = :trimmedName
            WITH USER_MODE
            LIMIT 1
        ];
        if (!existing.isEmpty()) {
            Option found = new Option();
            found.id = existing[0].Id;
            found.name = existing[0].Name;
            return found;
        }

        if (!Schema.sObjectType.DealerReferenceValue__c.isCreateable()
            || !Schema.sObjectType.DealerReferenceValue__c.fields.Name.isCreateable()
            || !Schema.sObjectType.DealerReferenceValue__c.fields.Type__c.isCreateable()) {
            throwAura('You do not have permission to create dealer reference values.');
        }

        DealerReferenceValue__c row = new DealerReferenceValue__c(
            Name = trimmedName,
            Type__c = typeValue
        );
        try {
            insert as user row;
        } catch (DmlException dmlEx) {
            throwAura(dmlEx.getDmlMessage(0));
        }

        Option created = new Option();
        created.id = row.Id;
        created.name = row.Name;
        return created;
    }

    private static void validateType(String typeValue) {
        if (String.isBlank(typeValue) || !VALID_TYPES.contains(typeValue)) {
            throwAura('Unsupported dealer reference type.');
        }
    }

    private static void assertReadable() {
        if (!Schema.sObjectType.DealerReferenceValue__c.isAccessible()
            || !Schema.sObjectType.DealerReferenceValue__c.fields.Name.isAccessible()
            || !Schema.sObjectType.DealerReferenceValue__c.fields.Type__c.isAccessible()) {
            throwAura('You do not have permission to read dealer reference values.');
        }
    }

    /**
     * @description Turns picker tokens into real Dealer Reference Value Ids.
     * Existing Ids are kept. Names the user typed (pending:) are created here,
     * when the Opportunity is saved, or reused when that Type + Name already exists.
     */
    @InvocableMethod(
        label='Resolve Dealer Reference Selections'
        description='Creates new dealer reference values chosen on the screen and returns their Ids.'
    )
    public static List<ResolveResult> resolve(List<ResolveRequest> requests) {
        Map<Integer, String> competitorNamesByIndex = storeCompetitorNames(requests);
        List<ResolveResult> results = new List<ResolveResult>();
        for (Integer index = 0; index < requests.size(); index++) {
            ResolveRequest request = requests[index];
            Resolver resolver = new Resolver();
            ResolveResult result = new ResolveResult();
            result.endCustomerId = resolver.resolveOne('EndCustomer', request.endCustomerId);
            result.architectId = resolver.resolveOne('Architect', request.architectId);
            result.mainContractorId = resolver.resolveOne('MainContractor', request.mainContractorId);
            result.equipmentPlannerId = resolver.resolveOne('EquipmentPlanner', request.equipmentPlannerId);
            result.competitorNames = competitorNamesByIndex.get(index);
            if (String.isBlank(request.competitorNames)) {
                List<String> competitorIds = resolver.resolveMany('Competitor', request.competitorIds);
                result.competitorId = competitorIds.isEmpty() ? null : competitorIds[0];
            }
            resolver.flush();
            results.add(result);
        }
        return results;
    }

    public class ResolveRequest {
        @InvocableVariable(label='End Customer Token')
        public String endCustomerId;
        @InvocableVariable(label='Architect Token')
        public String architectId;
        @InvocableVariable(label='Main Contractor Token')
        public String mainContractorId;
        @InvocableVariable(label='Equipment Planner Token')
        public String equipmentPlannerId;
        @InvocableVariable(label='Competitor Tokens')
        public String competitorIds;
        @InvocableVariable(
            label='Competitor Names'
            description='Competitor names from the text area. Separate names with a semicolon or a new line.'
        )
        public String competitorNames;
    }

    public class ResolveResult {
        @InvocableVariable(label='End Customer Id')
        public String endCustomerId;
        @InvocableVariable(label='Architect Id')
        public String architectId;
        @InvocableVariable(label='Main Contractor Id')
        public String mainContractorId;
        @InvocableVariable(label='Equipment Planner Id')
        public String equipmentPlannerId;
        @InvocableVariable(label='Competitor Id')
        public String competitorId;
        @InvocableVariable(label='Competitor Names')
        public String competitorNames;
    }

    private static String normalizeSearch(String searchTerm) {
        if (String.isBlank(searchTerm)) {
            return '';
        }
        return searchTerm.trim().replace('%', '').replace('_', '');
    }

    private static void throwAura(String message) {
        AuraHandledException ex = new AuraHandledException(message);
        ex.setMessage(message);
        throw ex;
    }

    /**
     * @description Creates missing Competitor reference rows for every request, then returns the semicolon-separated names.
     * One query and one insert cover the whole invocable batch.
     */
    private static Map<Integer, String> storeCompetitorNames(List<ResolveRequest> requests) {
        Map<Integer, String> storedByIndex = new Map<Integer, String>();
        Map<Integer, List<String>> namesByIndex = new Map<Integer, List<String>>();
        Set<String> allNames = new Set<String>();
        for (Integer index = 0; index < requests.size(); index++) {
            List<String> names = splitCompetitorNames(requests[index].competitorNames);
            namesByIndex.put(index, names);
            allNames.addAll(names);
            storedByIndex.put(index, names.isEmpty() ? null : String.join(names, ';'));
        }
        insertMissingCompetitors(allNames);
        return storedByIndex;
    }

    private static List<String> splitCompetitorNames(String raw) {
        List<String> names = new List<String>();
        if (raw == null) {
            return names;
        }
        String normalized = raw.replace('\r\n', '\n').replace('\r', '\n').replace('\n', ';');
        Set<String> seen = new Set<String>();
        for (String part : normalized.split(';')) {
            if (String.isBlank(part)) {
                continue;
            }
            String name = part.trim();
            if (name.length() > 80) {
                throwAura('A competitor name cannot be longer than 80 characters.');
            }
            String key = name.toLowerCase();
            if (seen.contains(key)) {
                continue;
            }
            seen.add(key);
            names.add(name);
        }
        return names;
    }

    private static void insertMissingCompetitors(Set<String> names) {
        if (names == null || names.isEmpty()) {
            return;
        }
        Set<String> existingKeys = new Set<String>();
        for (DealerReferenceValue__c row : [
            SELECT Name
            FROM DealerReferenceValue__c
            WHERE Type__c = 'Competitor'
            AND Name IN :names
            WITH USER_MODE
        ]) {
            existingKeys.add(row.Name.toLowerCase());
        }
        List<DealerReferenceValue__c> pending = new List<DealerReferenceValue__c>();
        for (String name : names) {
            if (!existingKeys.contains(name.toLowerCase())) {
                pending.add(new DealerReferenceValue__c(Name = name, Type__c = 'Competitor'));
                existingKeys.add(name.toLowerCase());
            }
        }
        if (!pending.isEmpty()) {
            assertReferenceCreateable();
            insert as user pending;
        }
    }

    private class Resolver {
        private Map<String, Id> resolvedByKey = new Map<String, Id>();
        private List<DealerReferenceValue__c> pendingInserts = new List<DealerReferenceValue__c>();
        private List<String> pendingKeys = new List<String>();

        String resolveOne(String typeValue, String token) {
            if (String.isBlank(token)) {
                return null;
            }
            if (!token.startsWith('pending:')) {
                return token;
            }
            String name = EncodingUtil.urlDecode(token.substring('pending:'.length()), 'UTF-8').trim();
            if (String.isBlank(name)) {
                return null;
            }
            String key = typeValue + '|' + name.toLowerCase();
            if (resolvedByKey.containsKey(key)) {
                return resolvedByKey.get(key);
            }
            List<DealerReferenceValue__c> existing = [
                SELECT Id
                FROM DealerReferenceValue__c
                WHERE Type__c = :typeValue
                AND Name = :name
                WITH USER_MODE
                LIMIT 1
            ];
            if (!existing.isEmpty()) {
                resolvedByKey.put(key, existing[0].Id);
                return existing[0].Id;
            }
            pendingInserts.add(new DealerReferenceValue__c(Name = name, Type__c = typeValue));
            pendingKeys.add(key);
            flush();
            return resolvedByKey.get(key);
        }

        List<String> resolveMany(String typeValue, String tokens) {
            List<String> ids = new List<String>();
            if (String.isBlank(tokens)) {
                return ids;
            }
            for (String token : tokens.split(';')) {
                String resolved = resolveOne(typeValue, token);
                if (String.isNotBlank(resolved)) {
                    ids.add(resolved);
                }
            }
            return ids;
        }

        void flush() {
            if (pendingInserts.isEmpty()) {
                return;
            }
            insert as user pendingInserts;
            for (Integer index = 0; index < pendingInserts.size(); index++) {
                resolvedByKey.put(pendingKeys[index], pendingInserts[index].Id);
            }
            pendingInserts.clear();
            pendingKeys.clear();
        }
    }

    /**
     * @description Values shown on the community opportunity detail picker.
     */
    public class OpportunityReferences {
        @AuraEnabled public String endCustomerId;
        @AuraEnabled public String endCustomerName;
        @AuraEnabled public String architectId;
        @AuraEnabled public String architectName;
        @AuraEnabled public String mainContractorId;
        @AuraEnabled public String mainContractorName;
        @AuraEnabled public String equipmentPlannerId;
        @AuraEnabled public String equipmentPlannerName;
        @AuraEnabled public String competitorIds;
        @AuraEnabled public String competitorNames;
    }

    /**
     * @description One opportunity's picker tokens. Used so several records save in one query and one insert.
     */
    public class ReferenceUpdate {
        public Id opportunityId;
        public String endCustomerToken;
        public String architectToken;
        public String mainContractorToken;
        public String equipmentPlannerToken;
        public String competitorTokens;
        public String competitorNames;
        public String endCustomerName;
        public String architectName;
        public String mainContractorName;
        public String equipmentPlannerName;
    }

    /**
     * @description Loads the dealer reference names already stored on an opportunity.
     * @param opportunityId Opportunity open on the community detail page
     * @return Ids and names for each picker
     */
    @AuraEnabled
    public static OpportunityReferences loadOpportunityReferences(Id opportunityId) {
        if (opportunityId == null) {
            throwAura('Opportunity is required.');
        }
        assertOpportunityReadable();
        List<Opportunity> opportunities = [
            SELECT EndCustomerName__c, ArchitectName__c, MainContractorName__c,
                EquipmentPlannerName__c, DealerCompetitors__c
            FROM Opportunity
            WHERE Id = :opportunityId
            WITH USER_MODE
            LIMIT 1
        ];
        if (opportunities.isEmpty()) {
            throwAura('You do not have access to this opportunity.');
        }
        Opportunity opportunity = opportunities[0];
        Map<String, Id> referenceIds = referenceIdsForNames(new List<Opportunity>{ opportunity });
        OpportunityReferences references = new OpportunityReferences();
        applySingleReference(references, 'EndCustomer', opportunity.EndCustomerName__c, referenceIds);
        applySingleReference(references, 'Architect', opportunity.ArchitectName__c, referenceIds);
        applySingleReference(references, 'MainContractor', opportunity.MainContractorName__c, referenceIds);
        applySingleReference(references, 'EquipmentPlanner', opportunity.EquipmentPlannerName__c, referenceIds);
        applyCompetitors(references, opportunity);
        return references;
    }

    /**
     * @description Saves picker selections for the open opportunity.
     * New names are inserted once, then the opportunity text fields are updated once.
     */
    @AuraEnabled
    public static void saveOpportunityReferences(
        Id opportunityId,
        String endCustomerToken,
        String endCustomerName,
        String architectToken,
        String architectName,
        String mainContractorToken,
        String mainContractorName,
        String equipmentPlannerToken,
        String equipmentPlannerName,
        String competitorTokens,
        String competitorNames
    ) {
        ReferenceUpdate updateRow = new ReferenceUpdate();
        updateRow.opportunityId = opportunityId;
        updateRow.endCustomerToken = endCustomerToken;
        updateRow.endCustomerName = endCustomerName;
        updateRow.architectToken = architectToken;
        updateRow.architectName = architectName;
        updateRow.mainContractorToken = mainContractorToken;
        updateRow.mainContractorName = mainContractorName;
        updateRow.equipmentPlannerToken = equipmentPlannerToken;
        updateRow.equipmentPlannerName = equipmentPlannerName;
        updateRow.competitorTokens = competitorTokens;
        updateRow.competitorNames = competitorNames;
        saveReferenceUpdates(new List<ReferenceUpdate>{ updateRow });
    }

    /**
     * @description Resolves every token across the requests, inserts missing names in one DML, and updates opportunities in one DML.
     * @param rows Opportunity picker values to persist
     */
    @TestVisible
    private static void saveReferenceUpdates(List<ReferenceUpdate> rows) {
        if (rows == null || rows.isEmpty()) {
            return;
        }
        assertOpportunityUpdateable();

        List<TokenUse> uses = new List<TokenUse>();
        Set<String> names = new Set<String>();
        Set<String> types = new Set<String>();
        for (ReferenceUpdate row : rows) {
            if (row == null || row.opportunityId == null) {
                throwAura('Opportunity is required.');
            }
            collectToken(uses, row.opportunityId, 'EndCustomer', row.endCustomerToken, names, types);
            collectToken(uses, row.opportunityId, 'Architect', row.architectToken, names, types);
            collectToken(uses, row.opportunityId, 'MainContractor', row.mainContractorToken, names, types);
            collectToken(uses, row.opportunityId, 'EquipmentPlanner', row.equipmentPlannerToken, names, types);
            if (String.isNotBlank(row.competitorTokens)) {
                for (String token : row.competitorTokens.split(';')) {
                    collectToken(uses, row.opportunityId, 'Competitor', token, names, types);
                }
            } else if (row.competitorNames != null) {
                for (String competitorName : splitCompetitorNames(row.competitorNames)) {
                    collectToken(
                        uses,
                        row.opportunityId,
                        'Competitor',
                        'pending:' + EncodingUtil.urlEncode(competitorName, 'UTF-8'),
                        names,
                        types
                    );
                }
            }
        }

        Map<String, Id> idByKey = new Map<String, Id>();
        if (!names.isEmpty()) {
            for (DealerReferenceValue__c existing : [
                SELECT Id, Name, Type__c
                FROM DealerReferenceValue__c
                WHERE Name IN :names
                AND Type__c IN :types
                WITH USER_MODE
            ]) {
                idByKey.put(referenceKey(existing.Type__c, existing.Name), existing.Id);
            }
        }

        List<DealerReferenceValue__c> pending = new List<DealerReferenceValue__c>();
        Set<String> queued = new Set<String>();
        for (TokenUse use : uses) {
            if (use.existingId != null || String.isBlank(use.name)) {
                continue;
            }
            if (use.name.length() > 80) {
                throwAura('A dealer reference name cannot be longer than 80 characters.');
            }
            String key = referenceKey(use.typeValue, use.name);
            if (idByKey.containsKey(key) || queued.contains(key)) {
                continue;
            }
            pending.add(new DealerReferenceValue__c(Name = use.name, Type__c = use.typeValue));
            queued.add(key);
        }
        if (!pending.isEmpty()) {
            assertReferenceCreateable();
            insert as user pending;
        }

        Map<Id, Opportunity> updatesById = new Map<Id, Opportunity>();
        for (ReferenceUpdate row : rows) {
            Opportunity opportunity = new Opportunity(Id = row.opportunityId);
            opportunity.EndCustomerName__c = blankToNull(row.endCustomerName);
            opportunity.ArchitectName__c = blankToNull(row.architectName);
            opportunity.MainContractorName__c = blankToNull(row.mainContractorName);
            opportunity.EquipmentPlannerName__c = blankToNull(row.equipmentPlannerName);
            opportunity.DealerCompetitors__c = storedCompetitorNames(row);
            updatesById.put(row.opportunityId, opportunity);
        }

        update as user updatesById.values();
    }

    private class TokenUse {
        Id opportunityId;
        String typeValue;
        Id existingId;
        String name;
    }

    private static void collectToken(
        List<TokenUse> uses,
        Id opportunityId,
        String typeValue,
        String token,
        Set<String> names,
        Set<String> types
    ) {
        TokenUse use = new TokenUse();
        use.opportunityId = opportunityId;
        use.typeValue = typeValue;
        if (String.isBlank(token)) {
            uses.add(use);
            return;
        }
        String trimmed = token.trim();
        if (!trimmed.startsWith('pending:')) {
            use.existingId = trimmed;
            uses.add(use);
            return;
        }
        String decoded = EncodingUtil.urlDecode(trimmed.substring('pending:'.length()), 'UTF-8').trim();
        use.name = decoded;
        if (String.isNotBlank(decoded)) {
            names.add(decoded);
            types.add(typeValue);
        }
        uses.add(use);
    }

    private static String referenceKey(String typeValue, String name) {
        return typeValue + '|' + (name == null ? '' : name.toLowerCase());
    }

    private static String storedCompetitorNames(ReferenceUpdate row) {
        if (row.competitorNames != null) {
            List<String> names = splitCompetitorNames(row.competitorNames);
            String stored = names.isEmpty() ? null : String.join(names, ';');
            if (stored != null && stored.length() > 255) {
                throwAura('Competitor names exceed 255 characters.');
            }
            return stored;
        }
        if (String.isBlank(row.competitorTokens)) {
            return null;
        }
        return String.isBlank(row.competitorNames) ? null : row.competitorNames;
    }

    private static String blankToNull(String value) {
        if (String.isBlank(value)) {
            return null;
        }
        String trimmed = value.trim();
        if (trimmed.length() > 80) {
            throwAura('A dealer reference name cannot be longer than 80 characters.');
        }
        return trimmed;
    }

    private static void addName(Set<String> names, String value) {
        if (String.isNotBlank(value)) {
            names.add(value.trim());
        }
    }

    private static Map<String, Id> referenceIdsForNames(List<Opportunity> opportunities) {
        Set<String> names = new Set<String>();
        for (Opportunity opportunity : opportunities) {
            addName(names, opportunity.EndCustomerName__c);
            addName(names, opportunity.ArchitectName__c);
            addName(names, opportunity.MainContractorName__c);
            addName(names, opportunity.EquipmentPlannerName__c);
        }
        Map<String, Id> ids = new Map<String, Id>();
        if (names.isEmpty()) {
            return ids;
        }
        for (DealerReferenceValue__c row : [
            SELECT Id, Name, Type__c
            FROM DealerReferenceValue__c
            WHERE Name IN :names
            WITH USER_MODE
        ]) {
            ids.put(referenceKey(row.Type__c, row.Name), row.Id);
        }
        return ids;
    }

    private static void applySingleReference(
        OpportunityReferences references,
        String typeValue,
        String name,
        Map<String, Id> referenceIds
    ) {
        if (String.isBlank(name)) {
            return;
        }
        String resolvedName = name.trim();
        Id matched = referenceIds.get(referenceKey(typeValue, resolvedName));
        String token = matched == null
            ? 'pending:' + EncodingUtil.urlEncode(resolvedName, 'UTF-8')
            : String.valueOf(matched);
        if (typeValue == 'EndCustomer') {
            references.endCustomerId = token;
            references.endCustomerName = resolvedName;
        } else if (typeValue == 'Architect') {
            references.architectId = token;
            references.architectName = resolvedName;
        } else if (typeValue == 'MainContractor') {
            references.mainContractorId = token;
            references.mainContractorName = resolvedName;
        } else if (typeValue == 'EquipmentPlanner') {
            references.equipmentPlannerId = token;
            references.equipmentPlannerName = resolvedName;
        }
    }

    private static void applyCompetitors(OpportunityReferences references, Opportunity opportunity) {
        List<String> names = new List<String>();
        if (String.isNotBlank(opportunity.DealerCompetitors__c)) {
            for (String part : opportunity.DealerCompetitors__c.split(';')) {
                if (String.isNotBlank(part)) {
                    names.add(part.trim());
                }
            }
        }
        if (names.isEmpty()) {
            return;
        }
        Map<String, Id> idByName = new Map<String, Id>();
        for (DealerReferenceValue__c row : [
            SELECT Id, Name
            FROM DealerReferenceValue__c
            WHERE Type__c = 'Competitor'
            AND Name IN :names
            WITH USER_MODE
        ]) {
            idByName.put(row.Name.toLowerCase(), row.Id);
        }
        List<String> ids = new List<String>();
        for (String name : names) {
            Id matched = idByName.get(name.toLowerCase());
            ids.add(matched == null ? 'pending:' + EncodingUtil.urlEncode(name, 'UTF-8') : String.valueOf(matched));
        }
        references.competitorIds = String.join(ids, ';');
        references.competitorNames = String.join(names, ';');
    }

    private static void assertOpportunityReadable() {
        if (!Schema.sObjectType.Opportunity.isAccessible()
            || !Schema.sObjectType.Opportunity.fields.EndCustomerName__c.isAccessible()
            || !Schema.sObjectType.Opportunity.fields.ArchitectName__c.isAccessible()
            || !Schema.sObjectType.Opportunity.fields.MainContractorName__c.isAccessible()
            || !Schema.sObjectType.Opportunity.fields.EquipmentPlannerName__c.isAccessible()
            || !Schema.sObjectType.Opportunity.fields.DealerCompetitors__c.isAccessible()) {
            throwAura('You do not have permission to read these opportunity fields.');
        }
    }

    private static void assertOpportunityUpdateable() {
        if (!Schema.sObjectType.Opportunity.isUpdateable()
            || !Schema.sObjectType.Opportunity.fields.EndCustomerName__c.isUpdateable()
            || !Schema.sObjectType.Opportunity.fields.ArchitectName__c.isUpdateable()
            || !Schema.sObjectType.Opportunity.fields.MainContractorName__c.isUpdateable()
            || !Schema.sObjectType.Opportunity.fields.EquipmentPlannerName__c.isUpdateable()
            || !Schema.sObjectType.Opportunity.fields.DealerCompetitors__c.isUpdateable()) {
            throwAura('You do not have permission to update these opportunity fields.');
        }
    }

    private static void assertReferenceCreateable() {
        if (!Schema.sObjectType.DealerReferenceValue__c.isCreateable()
            || !Schema.sObjectType.DealerReferenceValue__c.fields.Name.isCreateable()
            || !Schema.sObjectType.DealerReferenceValue__c.fields.Type__c.isCreateable()) {
            throwAura('You do not have permission to create dealer reference values.');
        }
    }
}