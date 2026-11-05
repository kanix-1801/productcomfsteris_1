# Plan: Contract Adjustments → Pricing Programs from the org (Apex)

## Context

The **Pricing Programs** tab in Contract Adjustments (`lwc/modelQtyCoverage`) was built in commit `907edb3`. It has search, select, a table, and a CT-code pill with a hover table, but all its data comes from **mock JSON** (`pricingProgramsMockData.js`). It also has two gaps:
1. Search and CT codes don't come from the org.
2. A saved line reloads **without** its pricing programs. The Apex `ContractModifierService.ContractAdjustments` has no `pricingPrograms` property, so `getCoverage` drops it during deserialize. The LWC then shows the mock sample rows instead.

**Goal:** show the real Pricing Programs and their child CT-code lines from the org through Apex, and make the selection survive save and reload. Both should follow the project's existing Controller → Service → Selector conventions.

**Decisions confirmed:**
- **Search filter:** `Status__c = 'Active'` and in date. "In date" means Start ≤ today (or blank) and End ≥ today (or blank).
- **Scope:** show the data and keep it in the JSON (`QuoteLineItem.ModelQtyCoverage__c`). `ContractModifier__c` record sync for pricing programs is a **later phase** and is out of scope here.

## What already exists (findings)

### Org data model (checked live in `steris-cbmdev`)
| Object | Key fields | Notes |
|---|---|---|
| `PricingProgram__c` (parent) | `Name` (auto, e.g. `PP-0009`), `ProgramName__c`, `DisplayName__c`, `Status__c` (Draft/Active), `StartDate__c`, `EndDate__c`, `ProductLine__c`, `SubProductLine__c`, `DeviceType__c`, `Manufacturer__c`, `ProductType__c`, `ModelNumber__c` → Product2 | 13 records (7 Active, 6 Draft) |
| `PricingProgramLines__c` (child, **master-detail**, relationship `PricingProgramLines__r`) | `Name` (`PPL-…`), `CategoryCode__c` (e.g. `CT.APT001`), `CategoryCodeName__c`, `CategoryCodeId__c` → Product2 | 26 records. These are the **CT codes** |
| `ContractModifier__c` | `Type__c` already has `'Pricing Program'` (mixed case!), record type `Pricing_Program`, `CTNumber__c` | Used in the later phase only |

### Reusable code
- **No existing Apex reads `PricingProgram__c` or `PricingProgramLines__c`.** `ModelRepairContractController` only has a `'PricingProgram__c'` string for an old QLI field, and nothing in it can be reused. New methods are needed.
- `classes/ModelQtyCoverageController.cls` is the pattern to copy: `with sharing`, `@AuraEnabled(cacheable=true)`, delegates to a service, `try/catch → toAuraException(...)`, `finally Logger.saveLog()`, Logger tag `ContractAdjustments`.
- `classes/SoqlQueryBuilder.cls` is the base for selectors (`ContractModifierSelector extends SoqlQueryBuilder`). It is CRUD/FLS-checked but has **no child subquery support**. For parent + child queries, the existing precedent is a static inline-SOQL selector method: `WorkOrdersSelector.selectByIdWithLineItems`, `ProductRequestsSelector`, `ReturnOrdersSelector`.
- In the LWC, `pickCtCodes`, `pickProgram`, `ctCodeView`, `programDetails`, `programSearchResults`, `handleAddSelectedPrograms` and `MIN_PROGRAM_SEARCH_LENGTH = 3` already work on the shape `{program, description, category, ctCodes:[{code,name}]}`. If Apex returns that **same shape**, the template, CSS and hover pill need no changes.

## Recommended approach

Use server-side search instead of loading every program. The search is cacheable, needs at least 3 characters and is debounced, and runs one query with a child subquery and `LIMIT`. This scales when production has hundreds of programs, avoids sending the full catalogue to every configurator session, and matches the current UI (search starts at 3 characters).

### 1. Apex: Selector (new) `classes/PricingProgramSelector.cls` (+ meta)
`public with sharing class PricingProgramSelector extends SoqlQueryBuilder` (objectName `PricingProgram__c`), with constants `STATUS_ACTIVE = 'Active'`, `MAX_RESULTS = 50`.

- `public static List<PricingProgram__c> selectActiveBySearchTerm(String term, Date asOf, Integer maxRows)`
  ```sql
  SELECT Id, Name, ProgramName__c, DisplayName__c, ProductLine__c, SubProductLine__c,
         DeviceType__c, Manufacturer__c, StartDate__c, EndDate__c,
         (SELECT Id, CategoryCode__c, CategoryCodeName__c, CategoryCodeId__c
            FROM PricingProgramLines__r ORDER BY CategoryCode__c)
  FROM PricingProgram__c
  WHERE Status__c = :STATUS_ACTIVE
    AND (StartDate__c = null OR StartDate__c <= :asOf)
    AND (EndDate__c = null OR EndDate__c >= :asOf)
    AND (Name LIKE :likeTerm OR ProgramName__c LIKE :likeTerm OR DisplayName__c LIKE :likeTerm
         OR ProductLine__c LIKE :likeTerm OR Manufacturer__c LIKE :likeTerm
         OR Id IN (SELECT PricingProgram__c FROM PricingProgramLines__c
                   WHERE CategoryCode__c LIKE :likeTerm OR CategoryCodeName__c LIKE :likeTerm))
  WITH USER_MODE
  ORDER BY Name LIMIT :maxRows
  ```
  - Escape the term with `String.escapeSingleQuotes` and also escape `%` and `_`. Use bind variables only, with no string concatenation of user input.
  - Picklist `LIKE` works in SOQL. If a picklist `LIKE` fails in the org, drop those two filters and keep the name and CT filters.
- `public static List<PricingProgram__c> selectByNames(Set<String> names)`: same fields and subquery, with `WHERE Name IN :names` and **no status/date filter**. A quote saved last year still shows its program even if the program has since expired. Used to refresh saved rows.

### 2. Apex: Service (new) `classes/PricingProgramService.cls` (+ meta)
This is a separate small service, which keeps the 727-line `ContractModifierService` from growing. It holds the DTOs, which mirror the LWC shape:
```apex
public class CtCode { @AuraEnabled public String code; @AuraEnabled public String name; @AuraEnabled public Id productId; }
public class ProgramOption {
    @AuraEnabled public Id programId;      // PricingProgram__c.Id
    @AuraEnabled public String program;    // Name, e.g. PP-0009 (stable key the LWC already uses)
    @AuraEnabled public String description;// DisplayName__c ?? ProgramName__c
    @AuraEnabled public String category;   // ProductLine__c (searched + shown in results)
    @AuraEnabled public String manufacturer; @AuraEnabled public String deviceType;
    @AuraEnabled public Date startDate; @AuraEnabled public Date endDate;
    @AuraEnabled public List<CtCode> ctCodes;
}
```
- `searchPrograms(String term)`: returns `[]` when `term` is blank or shorter than 3 characters. Otherwise it calls `selectActiveBySearchTerm(term, Date.today(), MAX_RESULTS)` and passes the result to `toOptions`.
- `getProgramsByNames(List<String> names)`: de-duplicates and drops blanks, then calls `selectByNames` and passes the result to `toOptions`.
- `private static List<ProgramOption> toOptions(List<PricingProgram__c>)`: maps the child `PricingProgramLines__r` to `CtCode` (`code = CategoryCode__c`, `name = CategoryCodeName__c`, `productId = CategoryCodeId__c`).

### 3. Apex: Controller `classes/ModelQtyCoverageController.cls` (modify)
Add two methods that follow the exact pattern already in the file (try / `toAuraException` / `Logger.saveLog()`):
- `@AuraEnabled(cacheable=true) public static List<PricingProgramService.ProgramOption> searchPricingPrograms(String searchTerm)`
- `@AuraEnabled(cacheable=true) public static List<PricingProgramService.ProgramOption> getPricingProgramsByNames(List<String> programNames)`

> `imsProductConfigurator` + `ImsProductConfiguratorController` is the duplicate component noted in `CONTRACT_ADJUSTMENTS_PRICING_PROGRAMS_DESIGN.md` §6.1. If it should get the tab too, add the same two delegating methods there. The service and selector are shared, so this needs no duplicated logic.

### 4. Apex: keep `pricingPrograms` through save and reload `classes/ContractModifierService.cls` (modify)
```apex
public class PricingProgramCtCode { public String code; public String name; }
public class PricingProgramEntry {
    public String programId; public String program; public String description;
    public List<PricingProgramCtCode> ctCodes = new List<PricingProgramCtCode>();
}
public class ContractAdjustments {
    public List<InclusionRule> inclusions = new List<InclusionRule>();
    public List<ModelQtyEntry> models = new List<ModelQtyEntry>();
    public List<PricingProgramEntry> pricingPrograms = new List<PricingProgramEntry>(); // NEW
    public String pricingProgram; // legacy, unchanged
}
```
- With this property in place, `getContractAdjustments` → `JSON.serialize` returns `pricingPrograms` (gap 2 fixed).
- In `parseCoverage` (or wherever the JSON is deserialized), default a null `pricingPrograms` to `[]` the same way the other lists are handled.
- **Sync logic stays untouched** in this phase. No `ContractModifier__c` rows are created or deleted for pricing programs.

### 5. Security / access (org metadata)
- Grant **Read** on `PricingProgram__c` and `PricingProgramLines__c`, plus FLS on the fields above, in the permission set(s) used by IMS sales users. These are the same ones that already grant `ContractModifier__c`; none of them are in the repo, so retrieve them first. `WITH USER_MODE` enforces this.
- Retrieve both objects into the repo (`sf project retrieve start -m CustomObject:PricingProgram__c CustomObject:PricingProgramLines__c`) so the fields referenced in Apex are version-controlled.

### 6. LWC `lwc/modelQtyCoverage/modelQtyCoverage.js` (modify)
- Imports: remove `./pricingProgramsMockData`. Add `searchPricingPrograms` and `getPricingProgramsByNames` from `@salesforce/apex/ModelQtyCoverageController.*`.
- State: replace `pricingPrograms = PRICING_PROGRAMS` with:
  - `programSearchData = []`: results for the current term
  - `programSearching = false`, `programSearchError`
  - `knownPrograms = {}`: cache of `ProgramOption` by `program` name, filled from both search results and hydration
- `handlePricingProgramSearch`: store the term, and **debounce for 300 ms** (`clearTimeout` / `setTimeout`, with the timer cleared in `disconnectedCallback`). At 3 or more characters, call `searchPricingPrograms({ searchTerm })`, then set `programSearchData` and merge the results into `knownPrograms`. Ignore stale responses by comparing the term.
- `programSearchResults` getter: build from `programSearchData` (the server already filtered it) and still exclude programs already in the table. The `.map(...)` output shape stays the same, so the **HTML is unchanged** apart from an optional spinner or error line.
- `programDetails(source)`: look up `this.knownPrograms[p.program]` instead of `this.pricingPrograms.find(...)`.
- `handleAddSelectedPrograms`: take selected rows from `programSearchData`.
- `fromJson`: `pricingPrograms: (data?.pricingPrograms || []).map(...)`. **Remove the `PRICING_PROGRAM_SAMPLE_ROWS` fallback.**
- `loadLine` (after `getCoverage`): collect the saved program names and call `getPricingProgramsByNames` once. Merge the result into `knownPrograms` and rebuild that line's rows, so descriptions and CT codes stay current. If this call fails, it is non-fatal: the saved JSON values are shown.
- `pickProgram`: add `programId` so it is stored in the JSON for the later record-sync phase.
- Delete `pricingProgramsMockData.js`. If Jest needs fixtures, move it to `__tests__/data/`.

### 7. Tests
- `ModelQtyCoverageTestDataFactory.cls`: add `createPricingProgram(name, status, start, end, List<String> ctCodes)`, which inserts the parent and its lines.
- `PricingProgramSelectorTest` / `PricingProgramServiceTest` (new) should cover:
  - Active and in date is returned; Draft, expired and future programs are not
  - Match on Name, display name and CT code / CT name
  - The term is shorter than 3 characters, so the result is `[]`
  - `%`/`_`/quote characters are escaped
  - `selectByNames` returns an expired program
  - The CT codes are mapped and ordered
  - `System.runAs` a user without object access gets an exception from `USER_MODE`
- `ModelQtyCoverageControllerTest`: the two new methods (happy path and the error path through `toAuraException`). `getCoverage` round-trips a JSON value that includes `pricingPrograms`.
- Target at least 90% coverage on the new classes.

## Files

| Action | File |
|---|---|
| New | `force-app/main/default/classes/PricingProgramSelector.cls` (+ meta, + Test) |
| New | `force-app/main/default/classes/PricingProgramService.cls` (+ meta, + Test) |
| Modify | `force-app/main/default/classes/ModelQtyCoverageController.cls` (+ Test) |
| Modify | `force-app/main/default/classes/ContractModifierService.cls` (DTO only) |
| Modify | `force-app/main/default/classes/ModelQtyCoverageTestDataFactory.cls` |
| Modify | `force-app/main/default/lwc/modelQtyCoverage/modelQtyCoverage.js` (and a small `.html` spinner/error) |
| Delete | `force-app/main/default/lwc/modelQtyCoverage/pricingProgramsMockData.js` |
| Retrieve | `objects/PricingProgram__c`, `objects/PricingProgramLines__c`, the relevant permission set |
| Docs | Update `ModelQtyCoverageCodeExplain.md` §5.10 and the "known gaps" table (gaps 1 and 2 closed) |

## Out of scope (next phase)
- Sync selected programs to `ContractModifier__c`. This needs `Type__c = 'Pricing Program'`, the `Pricing_Program` record type and `CTNumber__c` (one record per CT code, or per program; to be decided). It also needs the 3-way type bucketing fix described in `CONTRACT_ADJUSTMENTS_PRICING_PROGRAMS_DESIGN.md` §5.3 and §9. **Note:** the org picklist value is `'Pricing Program'`, not `'PRICING PROGRAM'` as that design doc assumes.
- Filtering programs by the quote account's assets.

## Verification
1. `sf project deploy start -o steris-cbmdev -d force-app/main/default/classes/PricingProgram* force-app/main/default/classes/ModelQtyCoverage* force-app/main/default/classes/ContractModifierService.cls force-app/main/default/lwc/modelQtyCoverage`
2. `sf apex run test -o steris-cbmdev -n PricingProgramSelectorTest,PricingProgramServiceTest,ModelQtyCoverageControllerTest,ContractModifierServiceTest -c -r human -w 20`
3. Quick data check in Anonymous Apex: `System.debug(JSON.serializePretty(ModelQtyCoverageController.searchPricingPrograms('Air')));` should return only **Active, in-date** programs (for example PP-0009 and PP-0011, not Draft PP-0008), each with its `ctCodes`.
4. In the UI, open a Quote, then IMS Service Agreement, then Product Configuration, then Contract Adjustments, then the Pricing Programs tab:
   - Typing 2 characters shows the "too short" hint.
   - Typing `CT.APT` lists programs, and hovering the pill shows the CT Code/Name table.
   - Select and Add puts the rows in the table. Saving the configuration and the quote, then reopening the saved line (`0QL…`), shows the same rows (no mock sample rows).
   - A new line (`ref_…`) starts with an empty table.
5. As a sales user without the permission set, the search shows a friendly error, and a `LogEntry__c` with tag `ContractAdjustments` is created.
