# Plan 2 – Save the ONL Pricing Program and Business Group in the Contract Adjustments JSON

**Ticket:** GW-6468 (On Location - Mobile Van)
**Scope:** JSON structure only (`QuoteLineItem.ModelQtyCoverage__c`). No new fields, no record or sync changes.
**Status:** Plan. Not implemented, not deployed.

---

## 1. Goal

The On Location - Mobile Van tab lets the user pick an **ONL Pricing Program** and a **Business Group**, but both
are kept only in the page (`onlProgramId`, `onlProgramLabel`, `onlBusinessGroup`). They are lost when the window
closes. This change stores them in the adjustments JSON so they are saved with the line and shown again when the
line is reopened.

## 2. JSON structure

Only the `mobileVan` object changes. All other keys stay as they are.

### Before
```json
"mobileVan": {
  "instrumentServices": ["Category A", "Category B"]
}
```

### After
```json
"mobileVan": {
  "programId": "a1Bxx0000067890AAA",
  "program": "PP-0012",
  "description": "ONL Mobile Van Program",
  "businessGroup": "Repair and Onlocation",
  "instrumentServices": ["Category A", "Category B"]
}
```

### No program picked
```json
"mobileVan": {
  "programId": null,
  "program": null,
  "description": null,
  "businessGroup": null,
  "instrumentServices": ["Category A"]
}
```

| Key | Type | Source (LWC) | Purpose |
|---|---|---|---|
| `programId` | Id / null | `onlProgramId` | The `PricingProgram__c` record picked. |
| `program` | String / null | picked program's `program` (Name, e.g. `PP-0012`) | Pill text on reopen, without an extra Apex call. |
| `description` | String / null | picked program's `description` | Pill text on reopen. |
| `businessGroup` | String / null | `onlBusinessGroup` | `Onlocation Only`, `Repair and Onlocation` or `Repair Only` (same values as `ContractLineItem.BusinessGroup__c`). |
| `instrumentServices` | String[] | `mobileVanSelected` | Unchanged. |

**Rules**
- `businessGroup` is required when `programId` is set.
- When `programId` is blank, `program`, `description` and `businessGroup` are saved as `null`.
- Empty values are `null`, never `""`.

## 3. How the JSON flows today (why both files are needed)

```
Save:   workingValue (JS) → pickMobileVan (JS) → handleCommit → JSON.stringify → ModelQtyCoverage__c
Reopen: getCoverage (Apex) → parseCoverage → MobileVanSelection class → JSON.serialize → LWC fromJson
```

On reopen, Apex reads the JSON into the `MobileVanSelection` class and serializes it back to the LWC. **Any key
the class does not declare is dropped.** So the JS change alone would save the values but lose them on reopen,
and the next save would overwrite the field without them. Both sides must change.

---

## 4. Code changes

### 4.1 LWC – `force-app/main/default/lwc/imsProductConfigurator/imsProductConfigurator.js`

#### a) `EMPTY_ADJUSTMENTS` (line ~55) – default shape
```js
mobileVan: { programId: null, program: null, description: null, businessGroup: null, instrumentServices: [] }
```
**Why:** The empty default must have the same keys as a saved value. The "unsaved changes" check
(`commitDisabled`) compares two `JSON.stringify` results, so a missing key would make an untouched form look changed.

#### b) `pickMobileVan` (line ~58) – the one place that defines the `mobileVan` shape
```js
// Mobile Van as stored in the JSON: the ONL pricing program and Business Group (all null when no program is
// picked) and the InstrumentServices__c values picked, once each, sorted
const pickMobileVan = (source) => {
    const programId = blankToNull(source?.programId);
    return {
        programId,
        program: programId ? blankToNull(source?.program) : null,
        description: programId ? blankToNull(source?.description) : null,
        businessGroup: programId ? blankToNull(source?.businessGroup) : null,
        instrumentServices: [...new Set((source?.instrumentServices || []).map(clean).filter(Boolean))].sort()
    };
};
```
**Why:**
- **Single source of truth:** `fromJson` (load), `toValue` (compare) and `workingValue` (save) all call this
  helper, so the shape is defined once and cannot drift between them.
- **Fixed key order:** the order of the keys is always the same, which the string-compare dirty check relies on.
- **Normalization:** blanks become `null`, values are trimmed, and program fields are cleared when there is no
  program. Bad or partial data cannot be saved.
- **Backward compatible:** JSON saved before this change has no program keys and reads as `null`.

`blankToNull` is a `const` declared below `pickMobileVan`. That is safe because `pickMobileVan` only runs after
the module has loaded.

#### c) New tracked properties (next to `onlProgramLabel`, line ~164)
```js
onlProgramName = null; // PricingProgram__c.Name, e.g. PP-0012
onlProgramDescription = null;
```
Also update the comment above them: they are now saved, not "UI only".
**Why:** `onlProgramLabel` is display text (`"PP-0012 - Description"`). Storing the raw name and description
separately keeps the data clean and lets the label be rebuilt the same way everywhere.

#### d) `handleOnlProgramPick` (line ~1168) and `handleOnlProgramClear` (line ~1194)
```js
// pick
this.onlProgramName = program.program;
this.onlProgramDescription = program.description;

// clear
this.onlProgramName = null;
this.onlProgramDescription = null;
```
**Why:** Picking and clearing must keep all program fields in step. Clearing already resets `onlBusinessGroup`.

#### e) `workingValue` (line ~1238) – what gets saved
```js
mobileVan: pickMobileVan({
    programId: this.onlProgramId,
    program: this.onlProgramName,
    description: this.onlProgramDescription,
    businessGroup: this.onlBusinessGroup,
    instrumentServices: this.mobileVanSelected
})
```
**Why:** This is where the page state becomes the JSON. `handleCommit()` sends whatever this returns, so it needs
no change.

#### f) `openModal` (after line ~477) – restore on reopen
```js
this.onlProgramId = c.mobileVan?.programId || null;
this.onlProgramName = c.mobileVan?.program || null;
this.onlProgramDescription = c.mobileVan?.description || null;
this.onlProgramLabel = this.onlProgramName
    ? (this.onlProgramDescription && this.onlProgramDescription !== this.onlProgramName
        ? `${this.onlProgramName} - ${this.onlProgramDescription}`
        : this.onlProgramName)
    : null;
this.onlBusinessGroup = c.mobileVan?.businessGroup || null;
this.resetOnlSearch();
```
**Why:** The other tabs are rebuilt from the committed value when the window opens. The ONL fields must be too,
or a reopened line shows no program and the next save clears it. The label uses the same format as the search
results (`"PP-0012 - Description"`). `resetOnlSearch()` clears any search left over from the last time the
window was open.

#### g) `validate` (before `return null;`, line ~1308)
```js
if (value.mobileVan.programId && !value.mobileVan.businessGroup) {
    return { section: SECTION_MOBILE_VAN, message: 'Select a Business Group for the ONL Pricing Program.' };
}
```
**Why:** The combobox is already `required={hasOnlProgram}`, but `required` on its own does not stop the save.
All other rules live in `validate()`, which also switches to the tab with the problem. This keeps it consistent.

#### h) Optional – summary card (`summaryTypes`, line ~398)
Add the program and Business Group to the Mobile Van preview text, e.g.
`Program PP-0012 · Repair Only · Category A · Category B`.
**Why:** The user can see what is saved without opening the window. Not needed for the JSON change.

#### i) Text cleanup
- `js` line ~538 section note and `html` line ~476 help text still say "Saved on the quote line". Change them to
  describe what really happens (saved with the line's adjustments).
- `js` line ~158 comment says Mobile Van is "UI only". Correct it.

**Why:** Comments and help text that describe old behaviour mislead the next developer and the user.

### 4.2 Apex – `force-app/main/default/classes/ImsProductConfiguratorService.cls`

#### `MobileVanSelection` (line ~107)
```apex
/**
 * @description On Location - Mobile Van selection, stored in ModelQtyCoverage__c "mobileVan": the ONL pricing
 *              program and Business Group picked (kept in the JSON only) and the categories checked
 *              (ContractAdjustment__c.InstrumentServices__c values).
 */
public class MobileVanSelection {
    public String programId; // PricingProgram__c.Id
    public String program; // PricingProgram__c.Name, e.g. PP-0012
    public String description; // DisplayName__c, or ProgramName__c
    public String businessGroup; // Onlocation Only | Repair and Onlocation | Repair Only
    public List<String> instrumentServices = new List<String>();
}
```
**Why:**
- **Required for reopen:** typed `JSON.deserialize` drops keys the class does not declare (see section 3).
- **Typed contract:** the class documents the JSON contract between the LWC and Apex in one place.
- **Backward compatible:** old JSON without these keys deserializes with the new fields `null`. `parseCoverage`
  needs no change, and `JSON.deserialize` (not `deserializeStrict`) keeps future extra keys from breaking the read.
- **No side effects:** the sync (`planMobileVanChanges`) still uses only `instrumentServices`, so record behaviour
  is unchanged.

### 4.3 Test – `force-app/main/default/classes/ImsProductConfiguratorServiceTest.cls`

Add one test (or extend `testSyncMobileVan`) that checks the new keys survive the round trip:
```apex
@IsTest
static void testMobileVanProgramRoundTrip() {
    String raw = '{"mobileVan":{"programId":"a1B000000000001AAA","program":"PP-0012",'
               + '"description":"ONL","businessGroup":"Repair Only","instrumentServices":["X"]}}';
    ImsProductConfiguratorService.ContractAdjustments parsed = ImsProductConfiguratorService.parseCoverage(raw);
    Assert.areEqual('PP-0012', parsed.mobileVan.program, 'Program name is read');
    Assert.areEqual('Repair Only', parsed.mobileVan.businessGroup, 'Business Group is read');
    Assert.isTrue(JSON.serialize(parsed).contains('"businessGroup":"Repair Only"'),
                  'Business Group survives the round trip back to the LWC');
    Assert.isNull(ImsProductConfiguratorService.parseCoverage('{"mobileVan":{"instrumentServices":[]}}')
                      .mobileVan.programId, 'Old JSON reads as no program');
}
```
**Why:** It protects the reopen path, which is the reason the Apex change exists, and proves old JSON still
reads. The program Id is only a string here; nothing is queried.

---

## 5. Out of scope (intentionally not changed)

| Item | Reason |
|---|---|
| Writing the program to `ContractAdjustment__c.PricingProgram__c` | Changes record behaviour; separate decision. |
| A Business Group field on QuoteLineItem / ContractAdjustment__c | Needs object metadata; not in this repo. |
| Loading Business Group options from a picklist | No QuoteLineItem field exists yet; the hardcoded list (TODO at js line ~1139) stays. |
| Server-side checks of `programId` / `businessGroup` | Values are not written to records yet. When they are, call `assertActivePricingProgram` before DML. |
| `ImsProductConfiguratorController` | It already serializes the whole `ContractAdjustments` object; no change. |

## 6. Files touched

| File | Change |
|---|---|
| `lwc/imsProductConfigurator/imsProductConfigurator.js` | 4.1 a–i |
| `lwc/imsProductConfigurator/imsProductConfigurator.html` | 4.1 i (help text only) |
| `classes/ImsProductConfiguratorService.cls` | 4.2 |
| `classes/ImsProductConfiguratorServiceTest.cls` | 4.3 |

## 7. How to verify (after deploy to a sandbox)

1. Open a quote line in the configurator, go to **On Location - Mobile Van**.
2. Pick an ONL program, leave Business Group empty, save. The error "Select a Business Group…" shows on the tab.
3. Pick a Business Group and some categories, save the window, then save the configuration.
4. Check `ModelQtyCoverage__c` on the line: `mobileVan` has `programId`, `program`, `description`,
   `businessGroup`, `instrumentServices`.
5. Reopen the configurator: the program pill and Business Group are shown again.
6. Clear the program and save: `program`, `description`, `businessGroup` are `null`.
7. Open an older line saved before this change: it opens without errors and with no program.
8. Run `ImsProductConfiguratorServiceTest`. All tests pass.
