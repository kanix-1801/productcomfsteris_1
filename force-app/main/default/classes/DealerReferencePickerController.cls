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
        List<ResolveResult> results = new List<ResolveResult>();
        for (ResolveRequest request : requests) {
            Resolver resolver = new Resolver();
            ResolveResult result = new ResolveResult();
            result.endCustomerId = resolver.resolveOne('EndCustomer', request.endCustomerId);
            result.architectId = resolver.resolveOne('Architect', request.architectId);
            result.mainContractorId = resolver.resolveOne('MainContractor', request.mainContractorId);
            result.equipmentPlannerId = resolver.resolveOne('EquipmentPlanner', request.equipmentPlannerId);
            List<String> competitorIds = resolver.resolveMany('Competitor', request.competitorIds);
            result.competitorId = competitorIds.isEmpty() ? null : competitorIds[0];
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
}