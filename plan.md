# Plan: Contract Adjustments → Pricing Programs from the org (Apex)

## Context

The **Pricing Programs** tab in Contract Adjustments (`lwc/modelQtyCoverage`) was built in commit `907edb3`. It has search, select, a table, and a CT-code pill with a hover table, but all its data comes from **mock JSON** (`pricingProgramsMockData.js`). It also has two gaps:
1. Search and CT codes don't come from the org.
2. A saved line reloads **without** its pricing programs. `ContractModifierService.ContractAdjustments` has no `pricingPrograms` property, so `getCoverage` drops it during deserialize. The LWC then shows the mock sample rows instead.

**Goal:** show the real Pricing Programs and their child CT-code lines from the org through Apex, and make the selection survive save and reload.

**Approach:** add the code **into the existing Contract Adjustments classes**, with no new Apex classes:
- `ContractModifierService` holds the logic, in its empty `/* Pricing Programs */` section.
- `ContractModifierSelector` holds the constants.
- `ModelQtyCoverageController` exposes the methods to the LWC.

Each piece follows the conventions those classes already use.

**Decisions confirmed:**
- **Search filter:** `Status__c = 'Active'` and in date. "In date" means Start ≤ today (or blank) and End ≥ today (or blank).
- **Scope:** show the data and keep it in the JSON (`QuoteLineItem.ModelQtyCoverage__c`). Syncing pricing programs to `ContractModifier__c` records is a **later phase**.

## What already exists (findings)

### Org data model (checked live in `steris-cbmdev`)
| Object | Key fields | Notes |
|---|---|---|
| `PricingProgram__c` (parent) | `Name` (auto, e.g. `PP-0009`), `ProgramName__c`, `DisplayName__c`, `Status__c` (Draft/Active), `StartDate__c`, `EndDate__c`, `ProductLine__c`, `SubProductLine__c`, `DeviceType__c`, `Manufacturer__c`, `ProductType__c`, `ModelNumber__c` → Product2 | 13 records (7 Active, 6 Draft) |
| `PricingProgramLines__c` (child, **master-detail**, relationship `PricingProgramLines__r`) | `Name` (`PPL-…`), `CategoryCode__c` (e.g. `CT.APT001`), `CategoryCodeName__c`, `CategoryCodeId__c` → Product2 | 26 records. These are the **CT codes** |
| `ContractModifier__c` | `Type__c` already has `'Pricing Program'` (mixed case!), record type `Pricing_Program`, `CTNumber__c` | Used in the later phase only |

### How `ContractModifierService` is organised today (where the new code fits)
| Part of the class | Existing code | What we add next to it |
|---|---|---|
| Inner DTO classes (lines 58–108) | `Criteria`, `ModelQtyEntry`, `InclusionRule`, `ContractAdjustments`, `AssetGroup` (`@AuraEnabled`, sent to the LWC) | `PricingProgramCtCode`, `PricingProgramEntry` (stored in the JSON), `PricingProgramOption` (`@AuraEnabled`, sent to the LWC, like `AssetGroup`) |
| `ContractAdjustments` (line 83) | `inclusions`, `models`, `pricingProgram` (legacy string) | `List<PricingProgramEntry> pricingPrograms` |
| `parseCoverage` (line 116) | Sets null lists to empty lists | Same for `pricingPrograms` |
| Public read methods (lines 289–392) | `getSubProductLines`, `getManufacturers`, `getAssetCatalog` | `searchPricingPrograms`, `getPricingProgramsByNames` |
| `/* Pricing Programs */` section (line 576) | **Empty** | Private helpers: `toPricingProgramOptions`, `toLikeTerm` |
| Private `select…` helpers (lines 744–774) | `selectAdjustments`, `selectAccountAssets` | `selectPricingPrograms` |
| Constants in `ContractModifierSelector` | `TYPE_MODEL_QTY`, `TYPE_INC_EXC`, record type Ids | `TYPE_PRICING_PROGRAM`, `PRICING_PROGRAM_RECORD_TYPE_ID`, `PRICING_PROGRAM_STATUS_ACTIVE` |

**Two facts behind the design:**
- **No existing method reads `PricingProgram__c` or `PricingProgramLines__c`.** The four existing read methods only read the `QuoteLineItem` JSON, `Product2` and `Asset`.
- `SoqlQueryBuilder`, which is the base of `ContractModifierSelector` and the other selectors, has **no child-subquery support**. The parent and child query is therefore one inline SOQL statement with `WITH USER_MODE`. This follows the project's precedent in `WorkOrdersSelector.selectByIdWithLineItems`. It keeps CRUD/FLS enforcement, the same as the builder's checks.

The LWC helpers (`pickCtCodes`, `pickProgram`, `ctCodeView`, `programDetails`, `programSearchResults`, `handleAddSelectedPrograms`, `MIN_PROGRAM_SEARCH_LENGTH = 3`) already work on the shape `{program, description, category, ctCodes:[{code,name}]}`. Apex returns that **same shape**, so the HTML, CSS and hover pill don't change.

## Implementation

### 1. `classes/ContractModifierSelector.cls`: constants (modify)
Add these next to the existing `TYPE_*` and record-type constants, in the same style:
```apex
/** @description Type__c value for Pricing Program records (org value is mixed case). */
public static final String TYPE_PRICING_PROGRAM = 'Pricing Program';

/** @description Record type for Pricing Program records (used by the later sync phase). */
public static final Id PRICING_PROGRAM_RECORD_TYPE_ID = Schema.SObjectType.ContractModifier__c
                                                              .getRecordTypeInfosByDeveloperName()
                                                              .get('Pricing_Program')
                                                              ?.getRecordTypeId();

/** @description PricingProgram__c.Status__c value offered in the Pricing Programs search. */
public static final String PRICING_PROGRAM_STATUS_ACTIVE = 'Active';
```
> `TYPE_PRICING_PROGRAM` is **not** added to the type filter in `selectAdjustments`. That filter is what keeps the two-way branching in `syncAdjustmentsFromQuoteLines` (line 179) and `getContractAdjustments` (line 264) safe. It changes only in the sync phase.

### 2. `classes/ContractModifierService.cls` (modify)

**a) Class header:** in the `@description`, add a line saying the class also reads Pricing Programs (`PricingProgram__c` and its lines) for the configurator.

**b) Constants,** next to `MAX_ASSETS`:
```apex
private static final Integer PRICING_PROGRAM_MIN_SEARCH_LENGTH = 3; // same as the LWC
private static final Integer PRICING_PROGRAM_MAX_RESULTS = 50;
```

**c) DTOs,** after `AssetGroup`:
```apex
/**
 * @description One CT code (a PricingProgramLines__c record) of a pricing program, as stored in the JSON.
 */
public class PricingProgramCtCode {
    @AuraEnabled public String code;   // CategoryCode__c
    @AuraEnabled public String name;   // CategoryCodeName__c
}

/**
 * @description A pricing program picked on the line (the "pricingPrograms" rows of ModelQtyCoverage__c).
 */
public virtual class PricingProgramEntry {
    @AuraEnabled public String programId;    // PricingProgram__c.Id
    @AuraEnabled public String program;      // PricingProgram__c.Name, e.g. PP-0009 (the LWC row key)
    @AuraEnabled public String description;  // DisplayName__c, or ProgramName__c
    @AuraEnabled public List<PricingProgramCtCode> ctCodes = new List<PricingProgramCtCode>();
}

/**
 * @description A pricing program offered in the LWC search: the stored entry plus fields that are only shown
 *              or searched, not saved.
 */
public class PricingProgramOption extends PricingProgramEntry {
    @AuraEnabled public String category;     // ProductLine__c
    @AuraEnabled public String manufacturer;
    @AuraEnabled public String deviceType;
    @AuraEnabled public Date startDate;
    @AuraEnabled public Date endDate;
}
```

**d) `ContractAdjustments`:** add one property:
```apex
public List<PricingProgramEntry> pricingPrograms = new List<PricingProgramEntry>();
```
With it, `getContractAdjustments` → `getCoverage` returns the saved rows, which fixes gap 2. The rebuild-from-records branch leaves the list empty because no records exist yet.

**e) `parseCoverage`:** add a null default next to the existing ones:
```apex
if (adjustments.pricingPrograms == null) {
    adjustments.pricingPrograms = new List<PricingProgramEntry>();
}
```

**f) Public read methods,** after `getAssetCatalog`, documented in the same style:
```apex
/**
 * @description Active, in-date pricing programs whose name, display name, Product Line, Manufacturer or a CT
 *              code / CT name contains the search text, each with its CT codes (Pricing Programs search).
 * @param searchTerm Text typed in the LWC (3 characters minimum)
 * @return Matching programs, sorted by name (max 50); empty for a blank or too-short term
 */
public static List<PricingProgramOption> searchPricingPrograms(String searchTerm) {
    String term = searchTerm?.trim();
    if (String.isBlank(term) || term.length() < PRICING_PROGRAM_MIN_SEARCH_LENGTH) {
        return new List<PricingProgramOption>();
    }
    return toPricingProgramOptions(selectPricingPrograms(toLikeTerm(term), null, Date.today()));
}

/**
 * @description Pricing programs by name, with their current CT codes, to refresh the rows saved on a line.
 *              No status or date filter, so a program that has since expired still shows on an older quote.
 * @param programNames PricingProgram__c names, e.g. PP-0009
 * @return The programs found
 */
public static List<PricingProgramOption> getPricingProgramsByNames(List<String> programNames) {
    Set<String> nameSet = new Set<String>();
    for (String name : programNames == null ? new List<String>() : programNames) {
        if (String.isNotBlank(name)) {
            nameSet.add(name.trim());
        }
    }
    return nameSet.isEmpty() ? new List<PricingProgramOption>()
                             : toPricingProgramOptions(selectPricingPrograms(null, nameSet, null));
}
```

**g) The empty `/* Pricing Programs */` section (line 576):** add the private helpers:
```apex
// PricingProgram__c records (with their lines) -> LWC options; CT codes keep the query order.
private static List<PricingProgramOption> toPricingProgramOptions(List<PricingProgram__c> programList) {
    List<PricingProgramOption> optionList = new List<PricingProgramOption>();
    for (PricingProgram__c programRecord : programList) {
        PricingProgramOption option = new PricingProgramOption();
        option.programId = programRecord.Id;
        option.program = programRecord.Name;
        option.description = blankToNull(programRecord.DisplayName__c) != null
            ? programRecord.DisplayName__c : programRecord.ProgramName__c;
        option.category = programRecord.ProductLine__c;
        option.manufacturer = programRecord.Manufacturer__c;
        option.deviceType = programRecord.DeviceType__c;
        option.startDate = programRecord.StartDate__c;
        option.endDate = programRecord.EndDate__c;
        for (PricingProgramLines__c lineRecord : programRecord.PricingProgramLines__r) {
            if (String.isBlank(lineRecord.CategoryCode__c)) {
                continue;
            }
            PricingProgramCtCode ctCode = new PricingProgramCtCode();
            ctCode.code = lineRecord.CategoryCode__c;
            ctCode.name = lineRecord.CategoryCodeName__c;
            option.ctCodes.add(ctCode);
        }
        optionList.add(option);
    }
    return optionList;
}

// "%text%" for a LIKE bind, with the LIKE wildcards in the user's text escaped.
private static String toLikeTerm(String term) {
    return '%' + term.replace('\\', '\\\\').replace('%', '\\%').replace('_', '\\_') + '%';
}
```

**h) `select…` helpers section:** add next to `selectAdjustments`. It uses one query with bind variables only; a `null` argument means that filter is not applied.
```apex
// Pricing programs with their lines. likeTerm: search mode (Active + in date on asOf + text match);
// nameSet: lookup by name (no status/date filter). Inline SOQL because SoqlQueryBuilder has no subqueries.
private static List<PricingProgram__c> selectPricingPrograms(String likeTerm, Set<String> nameSet, Date asOf) {
    String status = ContractModifierSelector.PRICING_PROGRAM_STATUS_ACTIVE;
    Integer maxRows = PRICING_PROGRAM_MAX_RESULTS;
    String soql = 'SELECT Id, Name, ProgramName__c, DisplayName__c, ProductLine__c, Manufacturer__c, '
        + 'DeviceType__c, StartDate__c, EndDate__c, '
        + '(SELECT Id, CategoryCode__c, CategoryCodeName__c FROM PricingProgramLines__r ORDER BY CategoryCode__c) '
        + 'FROM PricingProgram__c WHERE ';
    if (nameSet != null) {
        soql += 'Name IN :nameSet';
    } else {
        soql += 'Status__c = :status '
            + 'AND (StartDate__c = null OR StartDate__c <= :asOf) '
            + 'AND (EndDate__c = null OR EndDate__c >= :asOf) '
            + 'AND (Name LIKE :likeTerm OR ProgramName__c LIKE :likeTerm OR DisplayName__c LIKE :likeTerm '
            + 'OR Id IN (SELECT PricingProgram__c FROM PricingProgramLines__c '
            + 'WHERE CategoryCode__c LIKE :likeTerm OR CategoryCodeName__c LIKE :likeTerm))';
    }
    soql += ' WITH USER_MODE ORDER BY Name LIMIT :maxRows';
    return (List<PricingProgram__c>) Database.query(soql);
}
```
> Searching by Product Line or Manufacturer (both picklists) is left out on purpose. SOQL doesn't support `LIKE` on picklist fields in every context, and the LWC already shows `category` in the results. If business wants it, `Database.queryWithBinds` can add `ProductLine__c IN :matchingValues`, with the matching values taken from the picklist describe.

### 3. `classes/ModelQtyCoverageController.cls`: expose to the LWC (modify)
Add two methods after `getAssetCatalog`, with exactly the existing pattern: `cacheable=true`, delegate to the service, `toAuraException`, `Logger.saveLog()` in `finally`.
```apex
/**
 * @description Active, in-date pricing programs matching the search text, with their CT codes.
 * @param searchTerm Text typed in the Pricing Programs search (3 characters minimum)
 * @return Matching programs
 */
@AuraEnabled(cacheable=true)
public static List<ContractModifierService.PricingProgramOption> searchPricingPrograms(String searchTerm) {
    try {
        return ContractModifierService.searchPricingPrograms(searchTerm);
    } catch (Exception e) {
        throw toAuraException('searchPricingPrograms: search failed for ' + searchTerm, null, e,
                              'Unable to load the Pricing Programs.');
    } finally {
        Logger.saveLog();
    }
}

/**
 * @description Pricing programs by name, to refresh the programs saved on a line.
 * @param programNames PricingProgram__c names
 * @return The programs found
 */
@AuraEnabled(cacheable=true)
public static List<ContractModifierService.PricingProgramOption> getPricingProgramsByNames(List<String> programNames) {
    try {
        return ContractModifierService.getPricingProgramsByNames(programNames);
    } catch (Exception e) {
        throw toAuraException('getPricingProgramsByNames: lookup failed', null, e,
                              'Unable to load the Pricing Programs.');
    } finally {
        Logger.saveLog();
    }
}
```
> `ImsProductConfiguratorController` (the duplicate of this controller) can get the same two methods when `imsProductConfigurator` gets the tab. Because the logic lives in the shared service, nothing is duplicated.

### 4. LWC `lwc/modelQtyCoverage/modelQtyCoverage.js` (modify)
- **Imports:** remove `./pricingProgramsMockData`. Add `searchPricingPrograms` and `getPricingProgramsByNames` from `@salesforce/apex/ModelQtyCoverageController.*`.
- **State:** replace `pricingPrograms = PRICING_PROGRAMS` with:
  - `programSearchData = []`
  - `programSearching = false`, `programSearchError`
  - `knownPrograms = {}`: a cache keyed by `program` name, filled from both the search results and the saved-row refresh
- **`handlePricingProgramSearch`:** store the term, then **debounce for 300 ms**, clearing the timer in `disconnectedCallback`. At 3 or more characters, call `searchPricingPrograms({ searchTerm })`, set `programSearchData` and merge the results into `knownPrograms`. Ignore a stale response by comparing its term with the current one.
- **`programSearchResults`:** build from `programSearchData`, which the server has already filtered, and still exclude programs already in the table. The output shape is unchanged.
- **`programDetails`:** use `this.knownPrograms[p.program]` instead of `this.pricingPrograms.find(...)`.
- **`handleAddSelectedPrograms`:** pick the rows from `programSearchData`.
- **`fromJson`:** use `(data?.pricingPrograms || [])`. **Remove the `PRICING_PROGRAM_SAMPLE_ROWS` fallback.**
- **`loadLine`:** after `getCoverage`, call `getPricingProgramsByNames` once with the saved names, merge the result into `knownPrograms`, and rebuild the line's rows. A failure here is non-fatal: the saved JSON values are shown.
- **`pickProgram`:** add `programId` so it is saved in the JSON for the sync phase.
- **HTML:** add only a small spinner or error line under the search box.
- Delete `pricingProgramsMockData.js`. If Jest needs it, move it to `__tests__/data/`.

### 5. Security / access (org metadata)
- Grant **Read** on `PricingProgram__c` and `PricingProgramLines__c`, plus FLS on the fields queried, in the permission set(s) the IMS sales users already use for `ContractModifier__c`. `WITH USER_MODE` enforces this.
- Retrieve both objects into the repo:
  ```
  sf project retrieve start -m CustomObject:PricingProgram__c CustomObject:PricingProgramLines__c
  ```

### 6. Tests: extend the existing test classes
- **`ModelQtyCoverageTestDataFactory.cls`:** add `createPricingProgram(String programName, String status, Date startDate, Date endDate, List<String> ctCodes)`, which inserts the parent and its lines.
- **`ContractModifierServiceTest.cls`:** add a `/* Pricing Programs */` block covering:
  - `searchPricingPrograms`:
    - Active and in date is returned.
    - Draft, expired and future-dated programs are not.
    - Programs are found by name, display name, CT code and CT name.
    - A blank or 2-character term returns `[]`.
    - `%` and `_` in the term are treated literally.
    - CT codes are mapped and sorted.
  - `getPricingProgramsByNames`: returns an expired or Draft program; blanks and duplicates are ignored.
  - `parseCoverage` / `getContractAdjustments`:
    - JSON with `pricingPrograms` round-trips.
    - Old JSON without the key gives `[]`.
  - **Regression:** a QLI update with `pricingPrograms` in the JSON still syncs only the MODEL QTY and INC/EXC records, and doesn't create pricing records.
- **`ModelQtyCoverageControllerTest.cls`:** the two new methods, on both the happy path and the `AuraHandledException` path (for example `System.runAs` a user without object access).

## Files

| Action | File |
|---|---|
| Modify | `force-app/main/default/classes/ContractModifierSelector.cls` (constants) |
| Modify | `force-app/main/default/classes/ContractModifierService.cls` (DTOs, `pricingPrograms`, 2 public methods, helpers, select helper) |
| Modify | `force-app/main/default/classes/ModelQtyCoverageController.cls` (2 `@AuraEnabled` methods) |
| Modify | `force-app/main/default/classes/ContractModifierServiceTest.cls`, `ModelQtyCoverageControllerTest.cls`, `ModelQtyCoverageTestDataFactory.cls` |
| Modify | `force-app/main/default/lwc/modelQtyCoverage/modelQtyCoverage.js` (+ small `.html` change) |
| Delete | `force-app/main/default/lwc/modelQtyCoverage/pricingProgramsMockData.js` |
| Retrieve | `objects/PricingProgram__c`, `objects/PricingProgramLines__c`, the relevant permission set |
| Docs | `ModelQtyCoverageCodeExplain.md` §5.10 and the known-gaps table (gaps 1 and 2 closed) |

**No new Apex classes.**

## Out of scope (next phase: sync to `ContractModifier__c`)
- Add a `planPricingProgramChanges` method to `ContractModifierService`, next to `planModelQtyChanges`. It writes `Type__c = ContractModifierSelector.TYPE_PRICING_PROGRAM`, `PRICING_PROGRAM_RECORD_TYPE_ID` and `CTNumber__c` (whether that is one record per CT code or one per program is still to be decided).
- Add `TYPE_PRICING_PROGRAM` to the type filter in `selectAdjustments`. At the **same time**, make the bucketing in `syncAdjustmentsFromQuoteLines` (line 179) and `getContractAdjustments` (line 264) three-way.
- Filter programs by the quote account's assets.

## Verification
1. Deploy:
   ```
   sf project deploy start -o steris-cbmdev -d force-app/main/default/classes/ContractModifierSelector.cls force-app/main/default/classes/ContractModifierService.cls force-app/main/default/classes/ModelQtyCoverageController.cls force-app/main/default/lwc/modelQtyCoverage
   ```
   Deploy the test classes as well.
2. Run the tests:
   ```
   sf apex run test -o steris-cbmdev -n ContractModifierServiceTest,ModelQtyCoverageControllerTest -c -r human -w 20
   ```
   Expect all to pass, with coverage at or above the current level.
3. In Anonymous Apex:
   ```
   System.debug(JSON.serializePretty(ContractModifierService.searchPricingPrograms('Air')));
   ```
   It should return only **Active, in-date** programs (for example PP-0009 and PP-0011, but not Draft PP-0008), each with its `ctCodes`.
4. In the UI, go to Quote, then IMS Service Agreement, then Product Configuration, then Contract Adjustments, then the Pricing Programs tab:
   - 2 characters shows the "too short" hint.
   - `CT.APT` lists programs, and hovering the pill shows the CT Code/Name table.
   - Select, then Add, then save the configuration and the quote. Reopening the saved line (`0QL…`) shows the same rows, and no mock rows.
   - A new line (`ref_…`) starts empty.
5. Saving a line that has Model Qty, Inc/Exc **and** Pricing Programs changes only the MODEL QTY and INC/EXC `ContractModifier__c` records.
6. For a user without access to the objects, the search shows "Unable to load the Pricing Programs.", and a `LogEntry__c` with tag `ContractAdjustments` is created.
