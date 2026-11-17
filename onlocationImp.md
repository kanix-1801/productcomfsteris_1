# Implementation: ONL Pricing Program lookup shows only Active programs

> Status: **Implemented locally (not deployed, not committed).** Sections 4 and 5 are in the source. Differences from the guide:
> - The controller ONL error test is part of the existing `testMethodsThrowForUserWithoutAccess`. It now expects 7 failures, one per method.
> - Restoring a saved selection (5.3) is not built yet. The ONL program is not saved on the line, so there is nothing to restore.
> - The new test data uses a start date on every program, so a null `StartDate__c` is not tested.
> Ticket context: GW-5676 (imsProductConfigurator: Contract Adjustments / On Location - Mobile Van tab)

## 1. Goal

The **ONL Pricing Program** search bar is on the *On Location - Mobile Van* tab of the IMS Product Configurator. It must list only **activated** `PricingProgram__c` records:

- `Status__c = 'Active'`
- and the program is within its date range today: `StartDate__c <= today <= EndDate__c`, where a null start or end date counts as open-ended.

This is the same "active" rule the Pricing Programs tab search already uses (`ImsProductConfiguratorService.selectPricingPrograms`). Both search bars must apply it from **one place in Apex**, so they cannot drift apart.

## 2. Current behaviour and root cause

| Item | Location |
|---|---|
| ONL lookup markup | `lwc/imsProductConfigurator/imsProductConfigurator.html:409-412` |
| ONL filter getter | `lwc/imsProductConfigurator/imsProductConfigurator.js:1031-1040` |
| ONL change handler | `lwc/imsProductConfigurator/imsProductConfigurator.js:1067-1071` |
| Existing Apex search (controller) | `classes/ImsProductConfiguratorController.cls:93-109` (`searchPricingPrograms`) |
| Existing Apex search (service) | `classes/ImsProductConfiguratorService.cls:496-502` (`searchPricingPrograms`) |
| Existing selector query | `classes/ImsProductConfiguratorService.cls:1141-1183` (`selectPricingPrograms`, private) |
| Status constant | `classes/ContractAdjustmentSelector.cls:70` (`PRICING_PROGRAM_STATUS_ACTIVE = 'Active'`) |

The ONL lookup is a standard `lightning-record-picker` with a filter applied in the browser. It does not use Apex:

```js
// TODO: confirm the PricingProgram__c field API names (Status__c / Type__c) in the org.
get onlProgramFilter() {
    return {
        criteria: [
            { fieldPath: 'Status__c', operator: 'eq', value: 'Active' },
            { fieldPath: 'Type__c', operator: 'eq', value: 'On Location - Mobile Van' }
        ]
    };
}
```

### Problems

1. **`Type__c` is not a known field on `PricingProgram__c`.** The field list checked live in the org (`plan.md`) does not include it. The value `'On Location - Mobile Van'` belongs to `ContractAdjustment__c.Type__c`. Because of this criterion, the picker returns no records or errors.
2. **Searching by `Name` is not useful.** `Name` is an auto-number (`PP-0009`), so typing a program name finds nothing.
3. **There is no date-window check.** An Active program whose `EndDate__c` has passed would still be listed.
4. **The "active" rule is enforced only in the browser.** A browser-side filter only affects what the UI shows. Nothing on the server stops an inactive program Id from being submitted.
5. **The rule is duplicated.** The Pricing Programs tab enforces Active + in-date in Apex, while ONL has its own separate copy in JS.

## 3. Recommended approach

Replace the record picker with a **search bar backed by Apex**, the same pattern the Pricing Programs tab already uses (`handlePricingProgramSearch` / `runProgramSearch`):

```
LWC (debounced input, at least 3 characters)
  └─ ImsProductConfiguratorController.searchOnlPricingPrograms   (thin; @AuraEnabled cacheable; logs errors)
       └─ ImsProductConfiguratorService.searchOnlPricingPrograms (validates input; holds the business rule)
            └─ selectPricingPrograms (existing; USER_MODE; bind variables; Active + date window; LIMIT 50)
```

This puts the Active rule in **one** Apex query. It also enforces CRUD, FLS and sharing in `USER_MODE`, and is unit-testable. The Apex reuses the existing selector, DTO and LIKE-escaping, so no SOQL is duplicated.

---

## 4. Apex changes

### 4.1 `classes/ImsProductConfiguratorService.cls` (modify)

**a) New public search method.** Add it next to `searchPricingPrograms` (around line 503):

```apex
/**
 * @description GW-5676 - Active, in-date pricing programs for the ONL Pricing Program search bar
 *              (On Location - Mobile Van tab). Same Active + date-window rule as the Pricing Programs search.
 *              When PricingProgram__c gets a program type field, the ONL-only filter belongs here, not in the LWC.
 * @param searchTerm Text typed in the LWC (3 characters minimum)
 * @return Matching programs sorted by name (at most 50); empty for a blank or too-short term
 */
public static List<PricingProgramOption> searchOnlPricingPrograms(String searchTerm) {
	return searchPricingPrograms(searchTerm);
}
```

> For now this only passes the call through. It still gives the ONL tab its own entry point, so ONL-only rules (for example a future type field) can be added in one place without changing the Pricing Programs tab.

**b) Server-side guard for the selected program.** Add this for when the ONL selection is saved (that save path is still a TODO in the LWC). Never rely on the browser's filter:

```apex
/**
 * @description GW-5676 - Throws when the ONL pricing program is missing, not readable by the user, not Active,
 *              or outside its start/end dates on asOf. Call before writing the ONL adjustments.
 * @param programId PricingProgram__c Id picked in the ONL search bar
 * @param asOf      Date the program must be valid on (normally Date.today())
 */
public static void assertActivePricingProgram(Id programId, Date asOf) {
	if (programId == null || programId.getSobjectType() != PricingProgram__c.SObjectType) {
		throw new ImsProductConfiguratorException('A valid Pricing Program is required.');
	}
	Date validOn = asOf == null ? Date.today() : asOf;
	String status = ContractAdjustmentSelector.PRICING_PROGRAM_STATUS_ACTIVE;
	List<PricingProgram__c> programList = [
		SELECT Id FROM PricingProgram__c
		WHERE Id = :programId
		AND Status__c = :status
		AND (StartDate__c = null OR StartDate__c <= :validOn)
		AND (EndDate__c = null OR EndDate__c >= :validOn)
		WITH USER_MODE
		LIMIT 1
	];
	if (programList.isEmpty()) {
		throw new ImsProductConfiguratorException('The selected Pricing Program is not active.');
	}
}
```

> The service has no custom exception class yet (checked). Add `public class ImsProductConfiguratorException extends Exception {}` as an inner class of `ImsProductConfiguratorService`.

**c) No change to `selectPricingPrograms`.** It already:
- runs in `AccessLevel.USER_MODE`
- uses only bind variables (`Database.queryWithBinds`), with no user input concatenated into the query
- escapes LIKE wildcards through `toLikeTerm`
- takes `asOf` as a parameter instead of calling `Date.today()` inside, so tests can control the date
- caps results with `LIMIT :maxRows` (50) and limits CT-line reads (10,000)

### 4.2 `classes/ImsProductConfiguratorController.cls` (modify)

Add this after `searchPricingPrograms` (around line 110). It follows the class's existing conventions: thin wrapper, `try/catch` → `toAuraException`, and `Logger.saveLog()` in `finally`.

```apex
/**
 * @description GW-5676 - Active, in-date pricing programs for the ONL Pricing Program search bar
 *              (On Location - Mobile Van tab).
 * @param searchTerm Text typed in the ONL search bar (3 characters minimum)
 * @return Matching programs; empty for a blank or too-short term
 */
@AuraEnabled(cacheable=true)
public static List<ImsProductConfiguratorService.PricingProgramOption> searchOnlPricingPrograms(String searchTerm) {
	try {
		return ImsProductConfiguratorService.searchOnlPricingPrograms(searchTerm);
	} catch (Exception e) {
		throw toAuraException('searchOnlPricingPrograms: search failed for ' + searchTerm, null, e,
		                      'Unable to load the ONL Pricing Programs.');
	} finally {
		Logger.saveLog();
	}
}
```

### 4.3 Apex best-practice checklist (apply to every change above)

| # | Practice | How it is met |
|---|---|---|
| 1 | Sharing | The controller and service stay `with sharing`. Do not add `without sharing` or `inherited sharing` overrides. |
| 2 | CRUD / FLS | Every query uses `WITH USER_MODE` / `AccessLevel.USER_MODE`. Do not use `WITH SECURITY_ENFORCED` (mixing both is inconsistent) and do not skip checks. |
| 3 | SOQL injection | User text reaches SOQL only as a bind variable. Field and object names are never built from client input. LIKE wildcards are escaped (`toLikeTerm`). |
| 4 | Layering | Controller: transport and error handling only. Service: validation and rules. Query: the private selector method. No SOQL in the controller. |
| 5 | Single source of truth | The Active rule is in `selectPricingPrograms` / `assertActivePricingProgram` and the status constant is `ContractAdjustmentSelector.PRICING_PROGRAM_STATUS_ACTIVE`. No hard-coded `'Active'` in new Apex or the LWC. |
| 6 | Read-only and cacheable | Search methods are `@AuraEnabled(cacheable=true)` and do no DML. Write methods (the future ONL save) must **not** be cacheable. |
| 7 | Input validation | Trim; return an empty list (not an error) for blank input or fewer than 3 characters; check the `Id` sObject type before querying. |
| 8 | Governor limits | No SOQL or DML in loops; the result set is limited (`LIMIT 50`); one CT-line query per search; constants for the limits. |
| 9 | Error handling | Catch at the controller boundary only. Log the full exception with `Logger.error(...).addTag('ContractAdjustments')`, return a short, generic `AuraHandledException` message to the user, and never expose stack traces or SOQL. |
| 10 | Testable dates | Pass `asOf` in; use `Date.today()` only at the outermost call. |
| 11 | Documentation | ApexDoc (`@description`, `@param`, `@return`) on every public method, with the ticket number (GW-5676). |
| 12 | DTOs, not SObjects | Return `PricingProgramOption` (already `@AuraEnabled`) so the LWC gets only the fields it needs. |
| 13 | Static analysis | Run `sf code-analyzer run --target force-app/main/default/classes/ImsProductConfigurator*` (PMD / Code Analyzer) and fix violations before review. |

### 4.4 Tests

All tests use the existing factory and structure: `ImsProductConfiguratorTestDataFactory.createPricingProgram(...)`, `grantPricingProgramAccess()`, `System.runAs`, `Assert.*`, and SETUP / GIVEN / WHEN / THEN blocks.

**`classes/ImsProductConfiguratorServiceTest.cls`: add these methods**

1. `testSearchOnlPricingPrograms`
   - Create five programs: Active in date, Active with open end, Draft, Active expired, Active future.
   - Assert that only the two Active, in-date programs are returned, sorted by name.
   - Assert that a term under 3 characters and a null term return empty lists.
   - Assert that `%` is matched literally.
2. `testAssertActivePricingProgram`
   - Active, in-date Id: no exception.
   - Draft, expired and future programs: each throws `ImsProductConfiguratorException`.
   - A null Id and a non-`PricingProgram__c` Id (for example an Account Id): each throws.
3. `testSearchOnlPricingProgramsNoAccess`
   - Run as a user **without** `grantPricingProgramAccess()`.
   - Assert that a `QueryException` / security error is thrown, or that nothing is returned. This proves `USER_MODE` is enforced.

**`classes/ImsProductConfiguratorControllerTest.cls`: add these methods**

4. `testSearchOnlPricingPrograms`: a successful call through the controller returns the Active program.
5. `testSearchOnlPricingProgramsError`
   - Make the call fail, for example by running as a user without read access to `PricingProgram__c`.
   - Assert that an `AuraHandledException` is thrown with the generic message `'Unable to load the ONL Pricing Programs.'`.

Target: **≥ 90% coverage** on the changed classes, with meaningful assertions (not just coverage).

---

## 5. LWC changes (`lwc/imsProductConfigurator`)

### 5.1 JS (modify)

- **Import** (next to line 23):
  ```js
  import searchOnlPricingPrograms from '@salesforce/apex/ImsProductConfiguratorController.searchOnlPricingPrograms';
  ```
- **State** (next to `onlProgramId`, line 155):
  ```js
  onlSearchTerm = '';
  onlSearchData = [];
  onlSearching = false;
  onlSearchError;
  onlProgramLabel = null; // shown in the input after a selection
  _onlSearchTimer;
  ```
- **Remove** the `onlProgramFilter` getter (lines 1031-1040), including the `Type__c` criterion and the TODO.
- **Search handlers.** These mirror `handlePricingProgramSearch` / `runProgramSearch` and reuse `MIN_PROGRAM_SEARCH_LENGTH`, `PROGRAM_SEARCH_DELAY_MS`, `clean` and `reduceError`:
  ```js
  handleOnlProgramSearch(event) {
      this.onlSearchTerm = clean(event.detail.value);
      this.onlSearchError = null;
      clearTimeout(this._onlSearchTimer);
      if (this.onlSearchTerm.length < MIN_PROGRAM_SEARCH_LENGTH) {
          this.onlSearchData = [];
          this.onlSearching = false;
          return;
      }
      this.onlSearching = true;
      const searchTerm = this.onlSearchTerm;
      // eslint-disable-next-line @lwc/lwc/no-async-operation
      this._onlSearchTimer = setTimeout(() => this.runOnlProgramSearch(searchTerm), PROGRAM_SEARCH_DELAY_MS);
  }

  async runOnlProgramSearch(searchTerm) {
      try {
          const programs = await searchOnlPricingPrograms({ searchTerm });
          if (searchTerm !== this.onlSearchTerm) return; // ignore results from an older search
          this.onlSearchData = programs || [];
      } catch (e) {
          if (searchTerm !== this.onlSearchTerm) return;
          this.onlSearchData = [];
          this.onlSearchError = reduceError(e);
      } finally {
          if (searchTerm === this.onlSearchTerm) this.onlSearching = false;
      }
  }

  handleOnlProgramPick(event) {
      const { id } = event.currentTarget.dataset;
      const program = this.onlSearchData.find((p) => p.programId === id);
      if (!program) return;
      this.onlProgramId = program.programId;
      this.onlProgramLabel = `${program.program} - ${program.description || ''}`;
      this.onlSearchTerm = '';
      this.onlSearchData = [];
      // Functional pass (separate story): load the program's ONL_Category__c lines into onlProgramCategories
  }

  handleOnlProgramClear() {
      this.onlProgramId = null;
      this.onlProgramLabel = null;
      this.onlBusinessGroup = null;
  }
  ```
- **Getters:** `hasOnlSearchResults`, `noOnlSearchResults`, `onlSearchTooShort`, `showOnlSearchSpinner`. Copy the `programSearch*` getters at lines 863-901.
- **Cleanup:** in `disconnectedCallback` (next to line 242), add `clearTimeout(this._onlSearchTimer);`.
- `handleOnlProgramChange` is replaced by `handleOnlProgramPick` and `handleOnlProgramClear`.

### 5.2 HTML (modify lines 409-412)

Replace the `lightning-record-picker` with a search input, a results list and a "selected" pill. Reuse the CSS classes the Pricing Programs tab already uses at lines 88-158:

```html
<template lwc:if={hasOnlProgram}>
    <lightning-pill label={onlProgramLabel} onremove={handleOnlProgramClear}></lightning-pill>
</template>
<template lwc:else>
    <lightning-input type="search" label="ONL Pricing Program" placeholder="Search active programs..."
        value={onlSearchTerm} onchange={handleOnlProgramSearch} required></lightning-input>
    <template lwc:if={showOnlSearchSpinner}>
        <lightning-spinner size="small" alternative-text="Searching"></lightning-spinner>
    </template>
    <template lwc:if={onlSearchError}><p class="slds-text-color_error">{onlSearchError}</p></template>
    <template lwc:if={hasOnlSearchResults}>
        <ul class="slds-listbox slds-listbox_vertical">
            <template for:each={onlSearchData} for:item="p">
                <li key={p.programId} class="slds-listbox__item" data-id={p.programId} onclick={handleOnlProgramPick}>
                    <span class="slds-truncate">{p.program} - {p.description}</span>
                </li>
            </template>
        </ul>
    </template>
    <template lwc:if={noOnlSearchResults}><p>No active programs found.</p></template>
</template>
<p class="ca-field-help">Only Active programs within their start/end dates.</p>
```

For accessibility, give each result `role="option"` and `tabindex="0"`, and add an `onkeydown` that responds to Enter.

### 5.3 Restoring a saved selection

When the configurator reopens with a saved `onlProgramId`, load the label with LDS (`getRecord` from `lightning/uiRecordApi` with `PricingProgram__c.Name` and `PricingProgram__c.ProgramName__c`) instead of another Apex call. Do **not** filter this load on Active: a program that has since expired must still display on an older quote. This matches `getPricingProgramsByNames`, which also skips the status filter.

---

## 6. Optional: legacy `modelQtyCoverage` component

`lwc/modelQtyCoverage` has an older copy of the ONL picker (`.html:409-412`, `.js:1019-1024`). Its Apex (`ContractModifierService.selectPricingPrograms`, about line 873) ignores the search term. `CONTRACT_ADJUSTMENTS_PRICING_PROGRAMS_DESIGN.md` says to change only `imsProductConfigurator`. Leave the legacy component as it is unless it is still on a live page.

## 7. Future: ONL-only program type

If a type field is added to `PricingProgram__c` (for example a `Type__c` picklist with an `On Location - Mobile Van` value), add the filter **only** in Apex, inside `searchOnlPricingPrograms` / the selector, as a bind variable plus a constant. Add the same condition to `assertActivePricingProgram`. The LWC does not change.

## 8. Out of scope

- Loading the selected program's ONL categories (the existing TODO).
- Saving the ONL program and Business Group onto the quote line. When that is built, call `assertActivePricingProgram` before any DML.
- Object, field, permission set or page layout metadata.

## 9. Files touched (when implemented)

| File | Change |
|---|---|
| `classes/ImsProductConfiguratorService.cls` | Add `searchOnlPricingPrograms`, `assertActivePricingProgram` and the inner class `ImsProductConfiguratorException` |
| `classes/ImsProductConfiguratorController.cls` | Add `searchOnlPricingPrograms` (`@AuraEnabled(cacheable=true)`) |
| `classes/ImsProductConfiguratorServiceTest.cls` | Add 3 test methods |
| `classes/ImsProductConfiguratorControllerTest.cls` | Add 2 test methods |
| `lwc/imsProductConfigurator/imsProductConfigurator.js` | Apex import, ONL search state/handlers/getters; remove `onlProgramFilter` |
| `lwc/imsProductConfigurator/imsProductConfigurator.html` | Replace the record picker with the search, results and pill; update help text |

## 10. Verification

1. **Check fields and access (read-only):**
   ```bash
   sf sobject describe -s PricingProgram__c --target-org <alias>
   ```
   Confirm that `Status__c` (with an `Active` value), `StartDate__c`, `EndDate__c`, `ProgramName__c` and `DisplayName__c` exist, and that configurator users have read FLS on them.
2. **Expected list (read-only SOQL):**
   ```sql
   SELECT Id, Name, ProgramName__c, Status__c, StartDate__c, EndDate__c
   FROM PricingProgram__c
   WHERE Status__c = 'Active'
     AND (StartDate__c = null OR StartDate__c <= TODAY)
     AND (EndDate__c = null OR EndDate__c >= TODAY)
   ORDER BY Name
   ```
3. **Static checks:**
   - `npm run lint -- force-app/main/default/lwc/imsProductConfigurator`
   - `sf code-analyzer run --target force-app/main/default/classes`
4. **Apex tests (sandbox only, after deploy):**
   ```bash
   sf apex run test --tests ImsProductConfiguratorServiceTest --tests ImsProductConfiguratorControllerTest \
     --code-coverage --result-format human --target-org <sandbox-alias>
   ```
5. **UI check (sandbox):**
   - Open a quote line, then the configurator, then the **On Location - Mobile Van** tab.
   - Type 3 or more characters of a program name. Only the records from step 2 appear.
   - Draft, expired and future programs do not appear.
   - Picking a program shows the pill and makes Business Group required. Removing the pill clears both.

## 11. Deploy note

**Nothing has been deployed.** After code review, deploy to a **sandbox first** and run the tests together with the deploy:

```bash
sf project deploy start \
  -m ApexClass:ImsProductConfiguratorService -m ApexClass:ImsProductConfiguratorController \
  -m ApexClass:ImsProductConfiguratorServiceTest -m ApexClass:ImsProductConfiguratorControllerTest \
  -m LightningComponentBundle:imsProductConfigurator \
  --test-level RunSpecifiedTests \
  --tests ImsProductConfiguratorServiceTest --tests ImsProductConfiguratorControllerTest \
  --target-org <sandbox-alias>
```
