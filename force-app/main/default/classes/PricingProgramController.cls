/**
 * Pricing Program Manager: server side for the pricingProgramManager LWC.
 *
 * Objects
 *   PricingProgram__c         header (Type__c, ProgramName__c, DisplayName__c, Status__c, StartDate__c, EndDate__c)
 *   PricingProgramLines__c    one row per Category Code / Service Code (CategoryCodeId__c -> Product2)
 *   PricingProgramIncExc__c   inclusion / exclusion rules (Type = Pricing Program only);
 *                             exclusions point at their inclusion through RelatedRule__c
 *
 * Product2.ProductType__c (label "Service Product Category") decides which products a program type can use:
 *   Pricing Program            -> 'Category Code'
 *   On Location - Mobile Van   -> 'Service Code'
 *   any other type             -> no codes, no rules (e.g. Rapid Replace for now)
 *
 * saveProgram writes the header, its codes and its rules in ONE transaction; on any error nothing is saved.
 */
public with sharing class PricingProgramController {

    public static final String TYPE_PRICING = 'Pricing Program';
    public static final String TYPE_ONL = 'On Location - Mobile Van';
    public static final String RULE_INCLUSION = 'Inclusion';
    public static final String RULE_EXCLUSION = 'Exclusion';

    public static final Map<String, String> CODE_CATEGORY = new Map<String, String>{
        TYPE_PRICING => 'Category Code',
        TYPE_ONL => 'Service Code'
    };

    private static final Integer SEARCH_LIMIT = 15;

    // ------------------------------------------------------------------ DTOs

    public class ProgramData {
        @AuraEnabled public Id id;
        @AuraEnabled public String recordNumber;   // Name (auto number)
        @AuraEnabled public String programType;
        @AuraEnabled public String programName;
        @AuraEnabled public String displayName;
        @AuraEnabled public String status;
        @AuraEnabled public Date startDate;
        @AuraEnabled public Date endDate;
        @AuraEnabled public List<CodeLine> codes;
        @AuraEnabled public List<Rule> rules;
    }

    public class CodeLine {
        @AuraEnabled public Id id;
        @AuraEnabled public Id productId;
        @AuraEnabled public String code;
        @AuraEnabled public String name;
    }

    public class Rule {
        @AuraEnabled public Id id;
        @AuraEnabled public String clientId;      // record Id for saved rules, a temporary key for new ones
        @AuraEnabled public String kind;          // 'Inclusion' | 'Exclusion'
        @AuraEnabled public String parentId;      // exclusions: clientId of their inclusion
        @AuraEnabled public String productLine;
        @AuraEnabled public String subProductLine;
        @AuraEnabled public String productType;
        @AuraEnabled public String manufacturer;
        @AuraEnabled public String model;
        @AuraEnabled public String department;
        @AuraEnabled public Decimal maxQuantity;
        @AuraEnabled public Date startDate;
        @AuraEnabled public Date endDate;
    }

    public class CodeMatch {
        @AuraEnabled public String code;
        @AuraEnabled public Id productId;
        @AuraEnabled public String name;
        @AuraEnabled public String status;        // 'ok' | 'wrong' (other category) | 'missing'
    }

    // ------------------------------------------------------------------ Reads

    @AuraEnabled
    public static List<ProgramData> listPrograms() {
        List<ProgramData> out = new List<ProgramData>();
        for (PricingProgram__c p : [
            SELECT Id, Name, Type__c, ProgramName__c, DisplayName__c, Status__c, StartDate__c, EndDate__c
            FROM PricingProgram__c
            ORDER BY ProgramName__c NULLS LAST, Name
            LIMIT 2000
        ]) {
            out.add(toData(p));
        }
        return out;
    }

    @AuraEnabled
    public static ProgramData getProgram(Id programId) {
        List<PricingProgram__c> found = [
            SELECT Id, Name, Type__c, ProgramName__c, DisplayName__c, Status__c, StartDate__c, EndDate__c
            FROM PricingProgram__c WHERE Id = :programId LIMIT 1
        ];
        if (found.isEmpty()) {
            throw fail('This pricing program no longer exists.');
        }
        ProgramData d = toData(found[0]);

        for (PricingProgramLines__c l : [
            SELECT Id, CategoryCodeId__c, CategoryCode__c, CategoryCodeName__c,
                   CategoryCodeId__r.ProductCode, CategoryCodeId__r.Name
            FROM PricingProgramLines__c
            WHERE PricingProgram__c = :programId
            ORDER BY CategoryCode__c, Id
        ]) {
            CodeLine c = new CodeLine();
            c.id = l.Id;
            c.productId = l.CategoryCodeId__c;
            c.code = l.CategoryCodeId__c != null ? l.CategoryCodeId__r.ProductCode : l.CategoryCode__c;
            c.name = l.CategoryCodeId__c != null ? l.CategoryCodeId__r.Name : l.CategoryCodeName__c;
            d.codes.add(c);
        }

        for (PricingProgramIncExc__c r : [
            SELECT Id, Inc_Exc_Type__c, RelatedRule__c, ProductLine__c, SubProductLine__c, ProductType__c,
                   Manufacturer__c, Model__c, Department__c, Max_Quantity__c, StartDate__c, EndDate__c
            FROM PricingProgramIncExc__c
            WHERE PricingProgram__c = :programId
            ORDER BY CreatedDate, Id
        ]) {
            Rule x = new Rule();
            x.id = r.Id;
            x.clientId = r.Id;
            x.kind = r.Inc_Exc_Type__c == RULE_EXCLUSION ? RULE_EXCLUSION : RULE_INCLUSION;
            x.parentId = r.RelatedRule__c;
            x.productLine = r.ProductLine__c;
            x.subProductLine = r.SubProductLine__c;
            x.productType = r.ProductType__c;
            x.manufacturer = r.Manufacturer__c;
            x.model = r.Model__c;
            x.department = r.Department__c;
            x.maxQuantity = r.Max_Quantity__c;
            x.startDate = r.StartDate__c;
            x.endDate = r.EndDate__c;
            d.rules.add(x);
        }
        return d;
    }

    /** Type-ahead for the add-code box: matches code or name within the program type's category. */
    @AuraEnabled
    public static List<CodeLine> searchCodes(String term, String programType) {
        List<CodeLine> out = new List<CodeLine>();
        String category = CODE_CATEGORY.get(programType);
        if (category == null || String.isBlank(term) || term.trim().length() < 2) {
            return out;
        }
        String likeTerm = '%' + term.trim() + '%';   // bind variable: no escaping needed
        for (Product2 p : [
            SELECT Id, ProductCode, Name
            FROM Product2
            WHERE ProductType__c = :category AND (ProductCode LIKE :likeTerm OR Name LIKE :likeTerm)
            ORDER BY ProductCode
            LIMIT :SEARCH_LIMIT
        ]) {
            out.add(toCode(p));
        }
        return out;
    }

    /** Paste: checks a list of product codes in one query and says which can be added. */
    @AuraEnabled
    public static List<CodeMatch> resolveCodes(List<String> codes, String programType) {
        List<CodeMatch> out = new List<CodeMatch>();
        String category = CODE_CATEGORY.get(programType);
        if (codes == null || codes.isEmpty() || category == null) {
            return out;
        }
        List<String> ordered = new List<String>();
        Set<String> seen = new Set<String>();
        for (String c : codes) {
            String t = c == null ? '' : c.trim();
            if (t.length() > 0 && !seen.contains(t.toUpperCase())) {
                seen.add(t.toUpperCase());
                ordered.add(t);
            }
        }
        Map<String, Product2> inCategory = new Map<String, Product2>();
        Map<String, Product2> otherCategory = new Map<String, Product2>();
        for (Product2 p : [
            SELECT Id, ProductCode, Name, ProductType__c
            FROM Product2 WHERE ProductCode IN :ordered
        ]) {
            String key = p.ProductCode.toUpperCase();
            if (p.ProductType__c == category) {
                inCategory.put(key, p);
            } else if (!otherCategory.containsKey(key)) {
                otherCategory.put(key, p);
            }
        }
        for (String c : ordered) {
            CodeMatch m = new CodeMatch();
            m.code = c;
            Product2 p = inCategory.get(c.toUpperCase());
            if (p != null) {
                m.status = 'ok';
                m.productId = p.Id;
                m.code = p.ProductCode;
                m.name = p.Name;
            } else if (otherCategory.containsKey(c.toUpperCase())) {
                p = otherCategory.get(c.toUpperCase());
                m.status = 'wrong';
                m.code = p.ProductCode;
                m.name = p.Name;
            } else {
                m.status = 'missing';
            }
            out.add(m);
        }
        return out;
    }

    // ------------------------------------------------------------------ Save

    @AuraEnabled
    public static Id saveProgram(String programJson) {
        ProgramData d;
        try {
            d = (ProgramData) JSON.deserialize(programJson, ProgramData.class);
        } catch (Exception e) {
            throw fail('The program could not be read: ' + e.getMessage());
        }
        if (d.codes == null) d.codes = new List<CodeLine>();
        if (d.rules == null) d.rules = new List<Rule>();

        // Type can't change after the first save: use the stored one for existing programs.
        String programType = d.programType;
        if (d.id != null) {
            List<PricingProgram__c> existing = [SELECT Type__c FROM PricingProgram__c WHERE Id = :d.id LIMIT 1];
            if (existing.isEmpty()) throw fail('This pricing program no longer exists.');
            programType = existing[0].Type__c;
        }
        validate(d, programType);

        Savepoint sp = Database.setSavepoint();
        try {
            PricingProgram__c p = new PricingProgram__c(Id = d.id);
            if (d.id == null) p.Type__c = programType;
            p.ProgramName__c = d.programName.trim();
            p.DisplayName__c = String.isBlank(d.displayName) ? null : d.displayName.trim();
            p.Status__c = d.status;
            p.StartDate__c = d.startDate;
            p.EndDate__c = d.endDate;
            upsert p;

            saveCodes(p.Id, programType, d.codes);
            saveRules(p.Id, programType, d.rules);
            return p.Id;
        } catch (Exception e) {
            Database.rollback(sp);
            throw fail(friendly(e));
        }
    }

    private static void validate(ProgramData d, String programType) {
        if (String.isBlank(programType)) throw fail('Choose a Type.');
        if (String.isBlank(d.programName)) throw fail('Enter a Program Name.');
        if (d.startDate == null) throw fail('Enter a Start Date.');
        if (d.endDate != null && d.endDate < d.startDate) throw fail('End Date can\'t be before Start Date.');
        if (CODE_CATEGORY.containsKey(programType) && d.codes.isEmpty()) {
            throw fail('Add at least one ' + CODE_CATEGORY.get(programType) + '.');
        }
        Set<String> inclusionKeys = new Set<String>();
        for (Rule r : d.rules) {
            if (r.kind != RULE_EXCLUSION) inclusionKeys.add(r.clientId);
        }
        for (Rule r : d.rules) {
            if (r.startDate != null && r.endDate != null && r.endDate < r.startDate) {
                throw fail('A rule has an End Date before its Start Date.');
            }
            if (r.maxQuantity != null && r.maxQuantity < 0) {
                throw fail('Max Quantity can\'t be negative.');
            }
            if (r.kind == RULE_EXCLUSION && (r.parentId == null || !inclusionKeys.contains(r.parentId))) {
                throw fail('Every exclusion must sit under an inclusion.');
            }
        }
    }

    private static void saveCodes(Id programId, String programType, List<CodeLine> codes) {
        String category = CODE_CATEGORY.get(programType);
        Map<Id, PricingProgramLines__c> existingByProduct = new Map<Id, PricingProgramLines__c>();
        List<PricingProgramLines__c> toDelete = new List<PricingProgramLines__c>();
        for (PricingProgramLines__c l : [
            SELECT Id, CategoryCodeId__c FROM PricingProgramLines__c WHERE PricingProgram__c = :programId
        ]) {
            if (l.CategoryCodeId__c == null || existingByProduct.containsKey(l.CategoryCodeId__c)) {
                toDelete.add(l);   // orphan or duplicate line
            } else {
                existingByProduct.put(l.CategoryCodeId__c, l);
            }
        }

        Set<Id> wanted = new Set<Id>();
        if (category != null) {
            for (CodeLine c : codes) {
                if (c.productId != null) wanted.add(c.productId);
            }
        }
        for (Id productId : existingByProduct.keySet()) {
            if (!wanted.contains(productId)) toDelete.add(existingByProduct.get(productId));
        }
        if (!toDelete.isEmpty()) delete toDelete;
        if (wanted.isEmpty()) return;

        // Only new codes need a line. CategoryCode__c / CategoryCodeName__c are formulas off CategoryCodeId__c.
        Boolean nameIsAuto = Schema.SObjectType.PricingProgramLines__c.fields.Name.isAutoNumber();
        List<PricingProgramLines__c> toInsert = new List<PricingProgramLines__c>();
        for (Product2 p : [SELECT Id, ProductCode, Name, ProductType__c FROM Product2 WHERE Id IN :wanted]) {
            if (p.ProductType__c != category) {
                throw new PricingProgramException(p.ProductCode + ' is not a ' + category + '.');
            }
            if (existingByProduct.containsKey(p.Id)) continue;
            PricingProgramLines__c l = new PricingProgramLines__c(PricingProgram__c = programId, CategoryCodeId__c = p.Id);
            if (!nameIsAuto) l.put('Name', String.isBlank(p.ProductCode) ? p.Name : p.ProductCode);
            toInsert.add(l);
        }
        if (!toInsert.isEmpty()) insert toInsert;
    }

    private static void saveRules(Id programId, String programType, List<Rule> rules) {
        Map<Id, PricingProgramIncExc__c> existing = new Map<Id, PricingProgramIncExc__c>([
            SELECT Id, Inc_Exc_Type__c FROM PricingProgramIncExc__c WHERE PricingProgram__c = :programId
        ]);
        Boolean rulesAllowed = programType == TYPE_PRICING;

        Set<Id> keep = new Set<Id>();
        if (rulesAllowed) {
            for (Rule r : rules) {
                if (r.id != null && existing.containsKey(r.id)) keep.add(r.id);
            }
        }
        // Remove exclusions before inclusions so the RelatedRule__c lookup never blocks a delete.
        List<PricingProgramIncExc__c> delExclusions = new List<PricingProgramIncExc__c>();
        List<PricingProgramIncExc__c> delInclusions = new List<PricingProgramIncExc__c>();
        for (PricingProgramIncExc__c r : existing.values()) {
            if (keep.contains(r.Id)) continue;
            if (r.Inc_Exc_Type__c == RULE_EXCLUSION) delExclusions.add(r); else delInclusions.add(r);
        }
        if (!delExclusions.isEmpty()) delete delExclusions;
        if (!delInclusions.isEmpty()) delete delInclusions;
        if (!rulesAllowed || rules.isEmpty()) return;

        Boolean nameIsAuto = Schema.SObjectType.PricingProgramIncExc__c.fields.Name.isAutoNumber();

        // Inclusions first, so exclusions can point at their new Ids.
        Map<String, Id> idByClientId = new Map<String, Id>();
        List<Rule> inclusions = new List<Rule>();
        List<PricingProgramIncExc__c> incRecords = new List<PricingProgramIncExc__c>();
        Integer n = 0;
        for (Rule r : rules) {
            if (r.kind == RULE_EXCLUSION) continue;
            n++;
            inclusions.add(r);
            incRecords.add(toRecord(r, programId, RULE_INCLUSION, null, nameIsAuto, 'Inclusion ' + n));
        }
        upsert incRecords;
        for (Integer i = 0; i < inclusions.size(); i++) {
            idByClientId.put(inclusions[i].clientId, incRecords[i].Id);
        }

        List<PricingProgramIncExc__c> excRecords = new List<PricingProgramIncExc__c>();
        n = 0;
        for (Rule r : rules) {
            if (r.kind != RULE_EXCLUSION) continue;
            n++;
            Id parent = idByClientId.get(r.parentId);
            if (parent == null) throw new PricingProgramException('Every exclusion must sit under an inclusion.');
            excRecords.add(toRecord(r, programId, RULE_EXCLUSION, parent, nameIsAuto, 'Exclusion ' + n));
        }
        if (!excRecords.isEmpty()) upsert excRecords;
    }

    private static PricingProgramIncExc__c toRecord(Rule r, Id programId, String kind, Id parent, Boolean nameIsAuto, String fallbackName) {
        PricingProgramIncExc__c x = r.id != null
            ? new PricingProgramIncExc__c(Id = r.id)
            : new PricingProgramIncExc__c(PricingProgram__c = programId);
        x.Inc_Exc_Type__c = kind;
        x.RelatedRule__c = parent;
        x.ProductLine__c = blankToNull(r.productLine);
        x.SubProductLine__c = blankToNull(r.subProductLine);
        x.ProductType__c = blankToNull(r.productType);
        x.Manufacturer__c = blankToNull(r.manufacturer);
        x.Model__c = blankToNull(r.model);
        x.Department__c = blankToNull(r.department);
        x.Max_Quantity__c = r.maxQuantity;
        x.StartDate__c = r.startDate;
        x.EndDate__c = r.endDate;
        if (!nameIsAuto && r.id == null) x.put('Name', fallbackName);
        return x;
    }

    // ------------------------------------------------------------------ Helpers

    private static ProgramData toData(PricingProgram__c p) {
        ProgramData d = new ProgramData();
        d.id = p.Id;
        d.recordNumber = p.Name;
        d.programType = p.Type__c;
        d.programName = p.ProgramName__c;
        d.displayName = p.DisplayName__c;
        d.status = p.Status__c;
        d.startDate = p.StartDate__c;
        d.endDate = p.EndDate__c;
        d.codes = new List<CodeLine>();
        d.rules = new List<Rule>();
        return d;
    }

    private static CodeLine toCode(Product2 p) {
        CodeLine c = new CodeLine();
        c.productId = p.Id;
        c.code = p.ProductCode;
        c.name = p.Name;
        return c;
    }

    private static String blankToNull(String s) {
        return String.isBlank(s) ? null : s.trim();
    }

    private static String friendly(Exception e) {
        if (e instanceof DmlException) {
            return ((DmlException) e).getDmlMessage(0);
        }
        return e.getMessage();
    }

    private static AuraHandledException fail(String message) {
        AuraHandledException ex = new AuraHandledException(message);
        ex.setMessage(message);
        return ex;
    }

    public class PricingProgramException extends Exception {}
}