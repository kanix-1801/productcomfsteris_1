/**
 * @description Fluent builder over DynamicSoqlQuery. All validation, security checks, logging
 *              and execution are delegated to DynamicSoqlQuery, so the builder cannot bypass them.
 * @example
 * List<Account> accts = (List<Account>) SoqlQueryBuilder.fromObject('Account')
 *     .selectFields(new List<String>{ 'Id', 'Name', 'Owner.Name' })
 *     .whereField('Industry', '=', 'Technology')
 *     .whereField('AnnualRevenue', '>', 1000000)
 *     .whereField('BillingState', 'IN', new List<String>{ 'CA', 'NY' })
 *     .withFilterLogic('1 AND (2 OR 3)')
 *     .orderByDesc('AnnualRevenue')
 *     .limitTo(50)
 *     .execute();
 */
public virtual with sharing class SoqlQueryBuilder {

    /** @description API name of the SObject this builder targets. Set once, either via the constructor or a subclass. */
    protected final String objectName;
    /** @description Explicit field paths to SELECT, in the order they were added. */
    protected final List<String> fields = new List<String>();
    /** @description When true, resolveFields() merges in every field the running user can read, in addition to fields. */
    protected Boolean allFields = false;
    /** @description WHERE conditions, in the order they were added; index+1 is their reference number for withFilterLogic. */
    protected final List<DynamicSoqlQuery.Filter> filters = new List<DynamicSoqlQuery.Filter>();
    /** @description Custom filter logic string (e.g. '1 AND (2 OR 3)'); null/blank means AND all filters. */
    protected String filterLogic;
    /** @description ORDER BY elements, in the order they were added. */
    protected final List<DynamicSoqlQuery.Ordering> orderings = new List<DynamicSoqlQuery.Ordering>();
    /** @description Row limit to apply to the query; null means no LIMIT clause. */
    protected Integer limitCount;
    /** @description Row offset to apply to the query; null means no OFFSET clause. */
    protected Integer offsetCount;

    /**
     * @description Default constructor. Leaves objectName unset; intended for subclasses that
     *              set objectName themselves (e.g. a selector that always targets one object).
     */
    public SoqlQueryBuilder() {
    }

    /**
     * @description Creates a builder targeting the given SObject.
     * @param objectName API name of the SObject to query, e.g. 'Account'.
     */
    public SoqlQueryBuilder(String objectName) {
        this.objectName = objectName;
    }

    /**
     * @description Convenience factory equivalent to `new SoqlQueryBuilder(objectName)`.
     * @param objectName API name of the SObject to query, e.g. 'Account'.
     * @return A new builder targeting the given object.
     */
    public static SoqlQueryBuilder fromObject(String objectName) {
        return new SoqlQueryBuilder(objectName);
    }

    // ---- SELECT ------------------------------------------------------------------------------

    /**
     * @description Adds a single field (or relationship path, e.g. 'Owner.Name') to the SELECT list.
     * @param field Field API name or dotted relationship path.
     * @return This builder, for chaining.
     */
    public SoqlQueryBuilder selectField(String field) {
        fields.add(field);
        return this;
    }

    /**
     * @description Adds multiple fields (or relationship paths) to the SELECT list.
     * @param fieldList Field API names or dotted relationship paths; null is ignored.
     * @return This builder, for chaining.
     */
    public SoqlQueryBuilder selectFields(List<String> fieldList) {
        if (fieldList != null) {
            fields.addAll(fieldList);
        }
        return this;
    }

    /**
     * @description Selects every field the running user can read (merged with any explicit fields
     *              added via selectField/selectFields). Resolved at build time by DynamicSoqlQuery.
     * @return This builder, for chaining.
     */
    public SoqlQueryBuilder selectAllFields() {
        allFields = true;
        return this;
    }

    // ---- WHERE -------------------------------------------------------------------------------

    /**
     * @description Adds a WHERE condition. Filters are numbered 1..n in the order added, which is
     *              the numbering used when referencing them from withFilterLogic().
     * @param field Field API name or dotted relationship path to filter on.
     * @param operator Comparison operator, e.g. '=', '!=', '>', 'LIKE', 'IN'.
     * @param value Value to bind for this condition; a List for collection operators (IN, NOT IN, etc.).
     * @return This builder, for chaining.
     */
    public SoqlQueryBuilder whereField(String field, String operator, Object value) {
        filters.add(new DynamicSoqlQuery.Filter(field, operator, value));
        return this;
    }

    /**
     * @description Adds an equality WHERE condition (field = value).
     * @param field Field API name or dotted relationship path to filter on.
     * @param value Value to bind for this condition.
     * @return This builder, for chaining.
     */
    public SoqlQueryBuilder whereEquals(String field, Object value) {
        return whereField(field, '=', value);
    }

    /**
     * @description Adds an IN WHERE condition (field IN values).
     * @param field Field API name or dotted relationship path to filter on.
     * @param values List of values to match against.
     * @return This builder, for chaining.
     */
    public SoqlQueryBuilder whereIn(String field, List<Object> values) {
        return whereField(field, 'IN', values);
    }

    /**
     * @description Sets custom boolean logic across the filters added so far, e.g. '1 AND (2 OR 3)'.
     *              If not called, all filters are AND-ed together by default.
     * @param logic Filter logic string referencing filters by their 1-based position.
     * @return This builder, for chaining.
     */
    public SoqlQueryBuilder withFilterLogic(String logic) {
        filterLogic = logic;
        return this;
    }

    // ---- ORDER BY / LIMIT / OFFSET -----------------------------------------------------------

    /**
     * @description Adds an ascending ORDER BY element.
     * @param field Field API name or dotted relationship path to sort on.
     * @return This builder, for chaining.
     */
    public SoqlQueryBuilder orderBy(String field) {
        orderings.add(new DynamicSoqlQuery.Ordering(field, false));
        return this;
    }

    /**
     * @description Adds a descending ORDER BY element.
     * @param field Field API name or dotted relationship path to sort on.
     * @return This builder, for chaining.
     */
    public SoqlQueryBuilder orderByDesc(String field) {
        orderings.add(new DynamicSoqlQuery.Ordering(field, true));
        return this;
    }

    /**
     * @description Adds an ORDER BY element with explicit direction and null ordering.
     * @param field Field API name or dotted relationship path to sort on.
     * @param descending True for DESC, false for ASC.
     * @param nullsLast True for NULLS LAST, false for NULLS FIRST, null for the platform default.
     * @return This builder, for chaining.
     */
    public SoqlQueryBuilder orderBy(String field, Boolean descending, Boolean nullsLast) {
        orderings.add(new DynamicSoqlQuery.Ordering(field, descending, nullsLast));
        return this;
    }

    /**
     * @description Sets the LIMIT clause.
     * @param n Maximum number of rows to return; must be 1..DynamicSoqlQuery.MAX_LIMIT at build time.
     * @return This builder, for chaining.
     */
    public SoqlQueryBuilder limitTo(Integer n) {
        limitCount = n;
        return this;
    }

    /**
     * @description Sets the OFFSET clause.
     * @param n Number of rows to skip; must be 0..DynamicSoqlQuery.MAX_OFFSET at build time.
     * @return This builder, for chaining.
     */
    public SoqlQueryBuilder offsetBy(Integer n) {
        offsetCount = n;
        return this;
    }

    // ---- Terminal operations -----------------------------------------------------------------

    /**
     * @description Validates all accumulated input and builds the query without running it.
     * @return A PreparedQuery holding the validated SOQL string and its bind map.
     */
    public DynamicSoqlQuery.PreparedQuery build() {
        return DynamicSoqlQuery.prepare(
            objectName, resolveFields(), filters, filterLogic, orderings, limitCount, offsetCount
        );
    }

    /**
     * @description Builds the query and returns the validated SOQL string (with :bind placeholders),
     *              without executing it.
     * @return The SOQL string.
     */
    public String toSoql() {
        return build().soql;
    }

    /**
     * @description Builds and runs the query in USER_MODE.
     * @return The matching records.
     */
    public List<SObject> execute() {
        return DynamicSoqlQuery.execute(build());
    }

    /**
     * @description Builds and runs the query in SYSTEM_MODE (bypasses sharing; describe FLS still applies).
     * @return The matching records.
     */
    public List<SObject> executeSystemMode() {
        return DynamicSoqlQuery.execute(build(), System.AccessLevel.SYSTEM_MODE);
    }

    /**
     * @description Builds and runs SELECT COUNT() using the accumulated WHERE filters.
     *              SELECT fields, ORDER BY, LIMIT, and OFFSET are ignored.
     * @return Matching row count
     */
    public Integer count() {
        return DynamicSoqlQuery.count(
            DynamicSoqlQuery.prepareCount(objectName, filters, filterLogic)
        );
    }

    /**
     * @description Builds and runs SELECT COUNT() in SYSTEM_MODE using the accumulated WHERE filters.
     * @return Matching row count
     */
    public Integer countSystemMode() {
        return DynamicSoqlQuery.count(
            DynamicSoqlQuery.prepareCount(objectName, filters, filterLogic),
            System.AccessLevel.SYSTEM_MODE
        );
    }

    /**
     * @description Runs the query with LIMIT forced to 1 and returns the first matching record.
     * @return The first matching record, or null if none match.
     */
    public SObject first() {
        limitCount = 1;
        List<SObject> rows = execute();
        return rows.isEmpty() ? null : rows[0];
    }

    /**
     * @description Resolves the effective field list for the SELECT clause: the explicit fields
     *              as-is, or every accessible field on the object merged with the explicit fields
     *              when selectAllFields() was called. Duplicates are removed during validation.
     * @return The field list to pass to DynamicSoqlQuery.
     */
    private List<String> resolveFields() {
        if (!allFields) {
            return fields;
        }
        // Goes through the same object validation (existence + CRUD) as every other path.
        List<String> merged = new List<String>(DynamicSoqlQuery.getAccessibleFieldNames(objectName));
        merged.addAll(fields);   // de-duplicated during validation
        return merged;
    }
}