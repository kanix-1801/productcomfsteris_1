/**
 * @description Secure, fully parameterised dynamic SOQL.
 *
 * Every variable part of the query is a parameter:
 *   object, SELECT fields, WHERE filters (field / operator / value),
 *   filter logic ("1 AND (2 OR 3)"), ORDER BY, LIMIT, OFFSET.
 * COUNT() queries reuse the same object/WHERE validation and run via
 * Database.countQueryWithBinds in USER_MODE.
 *
 * Security model (defence in depth):
 *   1. Object name is resolved through Schema describe; it must exist, be accessible and queryable (CRUD).
 *   2. Every field path (incl. relationship paths like Account.Owner.Name) is resolved segment by
 *      segment through describe; each field and each related object must be accessible (FLS/CRUD).
 *      Filter fields must be filterable, sort fields must be sortable.
 *      Only the canonical API names returned by describe are ever concatenated into the query,
 *      so raw user text never reaches the SOQL string.
 *   3. Operators come from a fixed allow-list.
 *   4. Filter VALUES are never concatenated - they are passed as bind variables
 *      (Database.queryWithBinds), which makes SOQL injection through values impossible.
 *   5. Filter logic is tokenised and only digits, AND, OR, NOT and parentheses are accepted.
 *   6. LIMIT / OFFSET are range-checked integers.
 *   7. The query itself runs in AccessLevel.USER_MODE, so the platform enforces CRUD, FLS and
 *      sharing again at execution time. The class is also declared "with sharing".
 *
 * Requires API version 57.0+ (Database.queryWithBinds).
 */
public with sharing class DynamicSoqlQuery {

    /** @description Upper bound accepted for the LIMIT clause. */
    public static final Integer MAX_LIMIT = 50000;
    /** @description Upper bound accepted for the OFFSET clause. */
    public static final Integer MAX_OFFSET = 2000;
    /** @description Maximum number of relationship hops allowed in a single field path (e.g. A.B.C). */
    private static final Integer MAX_RELATIONSHIP_DEPTH = 5;

    /** @description Comparison operators accepted in a Filter. */
    private static final Set<String> ALLOWED_OPERATORS = new Set<String>{
        '=', '!=', '<', '<=', '>', '>=', 'LIKE', 'IN', 'NOT IN', 'INCLUDES', 'EXCLUDES'
    };
    /** @description Operators that require the filter value to be a List (as opposed to a scalar). */
    private static final Set<String> COLLECTION_OPERATORS = new Set<String>{
        'IN', 'NOT IN', 'INCLUDES', 'EXCLUDES'
    };

    /** @description Matches a single API-name segment: Name, Custom__c, ns__Custom__c, Parent__r ... */
    private static final Pattern IDENTIFIER = Pattern.compile('^[A-Za-z][A-Za-z0-9_]{0,79}$');
    /** @description Matches the tokens allowed in custom filter logic: numbers, parentheses, AND/OR/NOT. */
    private static final Pattern LOGIC_TOKEN = Pattern.compile('(?i)\\s*(\\d+|\\(|\\)|AND\\b|OR\\b|NOT\\b)\\s*');

    /** @description Which clause a field path is being resolved for, so the right describe checks apply. */
    private enum FieldUse { SELECTABLE, FILTERABLE, SORTABLE }

    /** @description Per-transaction cache of SObjectType -> field API name -> SObjectField, to avoid repeat describes. */
    private static final Map<Schema.SObjectType, Map<String, Schema.SObjectField>> FIELD_MAP_CACHE =
        new Map<Schema.SObjectType, Map<String, Schema.SObjectField>>();
    /** @description Per-transaction cache of SObjectType -> relationship name -> lookup field describe. */
    private static final Map<Schema.SObjectType, Map<String, Schema.DescribeFieldResult>> RELATIONSHIP_CACHE =
        new Map<Schema.SObjectType, Map<String, Schema.DescribeFieldResult>>();

    // ------------------------------------------------------------------------------------------
    // Public types
    // ------------------------------------------------------------------------------------------

    /** @description Thrown when input to this class fails validation or a security check. */
    public class DynamicSoqlException extends Exception {}

    /** @description One WHERE condition: `<field> <operator> :bindValue`. */
    public class Filter {
        /** @description Field API name or dotted relationship path to filter on. */
        public String field;
        /** @description Comparison operator; must be one of ALLOWED_OPERATORS. */
        public String operator;
        /** @description Value to bind for this condition; a List for collection operators. */
        public Object value;

        /**
         * @description Creates a filter condition.
         * @param field Field API name or dotted relationship path to filter on.
         * @param operator Comparison operator, e.g. '=', '!=', '>', 'LIKE', 'IN'.
         * @param value Value to bind for this condition.
         */
        public Filter(String field, String operator, Object value) {
            this.field = field;
            this.operator = operator;
            this.value = value;
        }
    }

    /** @description One ORDER BY element. */
    public class Ordering {
        /** @description Field API name or dotted relationship path to sort on. */
        public String field;
        /** @description True for DESC, false for ASC. */
        public Boolean descending = false;
        /** @description True for NULLS LAST, false for NULLS FIRST, null for the platform default. */
        public Boolean nullsLast;          // null = platform default

        /**
         * @description Creates an ascending ordering with default null handling.
         * @param field Field API name or dotted relationship path to sort on.
         */
        public Ordering(String field) {
            this(field, false, null);
        }

        /**
         * @description Creates an ordering with default null handling.
         * @param field Field API name or dotted relationship path to sort on.
         * @param descending True for DESC, false for ASC.
         */
        public Ordering(String field, Boolean descending) {
            this(field, descending, null);
        }

        /**
         * @description Creates an ordering with explicit direction and null handling.
         * @param field Field API name or dotted relationship path to sort on.
         * @param descending True for DESC, false for ASC.
         * @param nullsLast True for NULLS LAST, false for NULLS FIRST, null for the platform default.
         */
        public Ordering(String field, Boolean descending, Boolean nullsLast) {
            this.field = field;
            this.descending = descending == true;
            this.nullsLast = nullsLast;
        }
    }

    /** @description A validated query string plus its bind map, ready to execute. */
    public class PreparedQuery {
        /** @description The validated SOQL string, with :bindName placeholders for every filter value. */
        public String soql { get; private set; }
        /** @description Bind name -> filter value, for use with Database.queryWithBinds. */
        public Map<String, Object> binds { get; private set; }

        /**
         * @description Creates a prepared query. Package-private: only DynamicSoqlQuery builds these.
         * @param soql The validated SOQL string.
         * @param binds The bind map for the SOQL string.
         */
        PreparedQuery(String soql, Map<String, Object> binds) {
            this.soql = soql;
            this.binds = binds;
        }
    }

    // ------------------------------------------------------------------------------------------
    // 1) Core method - explicit field list
    // ------------------------------------------------------------------------------------------

    /**
     * @description Runs a dynamic SOQL query where every clause is supplied by the caller.
     * @param objectName   SObject API name, e.g. 'Account'
     * @param fields       Field paths to SELECT, e.g. {'Id','Name','Owner.Name'}
     * @param filters      WHERE conditions (nullable)
     * @param filterLogic  e.g. '1 AND (2 OR 3)'; null/blank = AND all filters
     * @param orderings    ORDER BY elements (nullable)
     * @param limitCount   1..50000 (nullable)
     * @param offsetCount  0..2000 (nullable)
     * @return The matching records.
     */
    public static List<SObject> query(
        String objectName,
        List<String> fields,
        List<Filter> filters,
        String filterLogic,
        List<Ordering> orderings,
        Integer limitCount,
        Integer offsetCount
    ) {
        PreparedQuery pq = prepare(objectName, fields, filters, filterLogic, orderings, limitCount, offsetCount);
        return execute(pq);
    }

    /**
     * @description Convenience overload: fields only, no filters, ordering, limit or offset.
     * @param objectName SObject API name, e.g. 'Account'.
     * @param fields Field paths to SELECT.
     * @return The matching records.
     */
    public static List<SObject> query(String objectName, List<String> fields) {
        return query(objectName, fields, null, null, null, null, null);
    }

    /**
     * @description Convenience overload: fields + AND-ed filters + limit, no custom filter logic,
     *              ordering or offset.
     * @param objectName SObject API name, e.g. 'Account'.
     * @param fields Field paths to SELECT.
     * @param filters WHERE conditions, AND-ed together (nullable).
     * @param limitCount 1..50000 (nullable).
     * @return The matching records.
     */
    public static List<SObject> query(String objectName, List<String> fields, List<Filter> filters, Integer limitCount) {
        return query(objectName, fields, filters, null, null, limitCount, null);
    }

    // ------------------------------------------------------------------------------------------
    // 2) Variation - all (accessible) fields on the object
    // ------------------------------------------------------------------------------------------

    /**
     * @description Same as query(), but SELECTs every field on the object the running user can read.
     *              Base64 (blob) fields are skipped to protect heap size.
     *
     * Note: SOQL's own FIELDS(ALL) is capped at LIMIT 200 and fails in USER_MODE if any field
     * is inaccessible, so the field list is built from describe instead.
     * @param objectName   SObject API name, e.g. 'Account'
     * @param filters      WHERE conditions (nullable)
     * @param filterLogic  e.g. '1 AND (2 OR 3)'; null/blank = AND all filters
     * @param orderings    ORDER BY elements (nullable)
     * @param limitCount   1..50000 (nullable)
     * @param offsetCount  0..2000 (nullable)
     * @return The matching records, with every accessible field populated.
     */
    public static List<SObject> queryAllFields(
        String objectName,
        List<Filter> filters,
        String filterLogic,
        List<Ordering> orderings,
        Integer limitCount,
        Integer offsetCount
    ) {
        Schema.SObjectType sot = resolveObject(objectName);
        List<String> allFields = getAccessibleFieldNames(sot);
        return query(objectName, allFields, filters, filterLogic, orderings, limitCount, offsetCount);
    }

    /**
     * @description Convenience overload: all fields, AND-ed filters, limit, no custom filter logic,
     *              ordering or offset.
     * @param objectName SObject API name, e.g. 'Account'.
     * @param filters WHERE conditions, AND-ed together (nullable).
     * @param limitCount 1..50000 (nullable).
     * @return The matching records, with every accessible field populated.
     */
    public static List<SObject> queryAllFields(String objectName, List<Filter> filters, Integer limitCount) {
        return queryAllFields(objectName, filters, null, null, limitCount, null);
    }

    /**
     * @description Every readable, non-blob field on the object, after validating the object name.
     * @param objectName SObject API name, e.g. 'Account'.
     * @return Canonical API names of every accessible, non-blob field, sorted alphabetically.
     */
    public static List<String> getAccessibleFieldNames(String objectName) {
        return getAccessibleFieldNames(resolveObject(objectName));
    }

    /**
     * @description Every readable, non-blob field on the object (canonical API names).
     * @param sot The SObjectType to inspect.
     * @return Canonical API names of every accessible, non-blob field, sorted alphabetically.
     */
    public static List<String> getAccessibleFieldNames(Schema.SObjectType sot) {
        List<String> names = new List<String>();
        for (Schema.SObjectField f : getFieldMap(sot).values()) {
            Schema.DescribeFieldResult dfr = f.getDescribe();
            if (dfr.isAccessible() && dfr.getType() != Schema.DisplayType.BASE64) {
                names.add(dfr.getName());
            }
        }
        if (names.isEmpty()) {
            throw new DynamicSoqlException('No accessible fields on ' + sot);
        }
        names.sort();
        return names;
    }

    // ------------------------------------------------------------------------------------------
    // Build + execute
    // ------------------------------------------------------------------------------------------

    /**
     * @description Validates all input and builds the SOQL string + bind map without executing it.
     * @param objectName   SObject API name, e.g. 'Account'
     * @param fields       Field paths to SELECT
     * @param filters      WHERE conditions (nullable)
     * @param filterLogic  e.g. '1 AND (2 OR 3)'; null/blank = AND all filters
     * @param orderings    ORDER BY elements (nullable)
     * @param limitCount   1..50000 (nullable)
     * @param offsetCount  0..2000 (nullable)
     * @return A PreparedQuery holding the validated SOQL string and its bind map.
     */
    public static PreparedQuery prepare(
        String objectName,
        List<String> fields,
        List<Filter> filters,
        String filterLogic,
        List<Ordering> orderings,
        Integer limitCount,
        Integer offsetCount
    ) {
        Schema.SObjectType sot = resolveObject(objectName);
        Map<String, Object> binds = new Map<String, Object>();

        String selectClause = buildSelect(sot, fields);
        String whereClause = buildWhere(sot, filters, filterLogic, binds);
        String orderClause = buildOrderBy(sot, orderings);
        validateLimitOffset(limitCount, offsetCount);

        String soql = 'SELECT ' + selectClause + ' FROM ' + sot.getDescribe(SObjectDescribeOptions.DEFERRED).getName();
        if (String.isNotBlank(whereClause)) {
            soql += ' WHERE ' + whereClause;
        }
        if (String.isNotBlank(orderClause)) {
            soql += ' ORDER BY ' + orderClause;
        }
        if (limitCount != null) {
            soql += ' LIMIT ' + limitCount;
        }
        if (offsetCount != null) {
            soql += ' OFFSET ' + offsetCount;
        }
        return new PreparedQuery(soql, binds);
    }

    /**
     * @description Logs and runs a previously validated query.
     * @param pq The prepared query to execute.
     * @return The matching records.
     */
    public static List<SObject> execute(PreparedQuery pq) {
        // Log the query. Bind values can contain user data/PII, so only their keys + types go to DEBUG.
        Logger.debug('DynamicSoqlQuery SOQL: ' + pq.soql);
        Logger.debug('DynamicSoqlQuery binds: ' + describeBinds(pq.binds));

        return Database.queryWithBinds(pq.soql, pq.binds, AccessLevel.USER_MODE);
    }

    /**
     * @description Validates object + WHERE filters and builds a COUNT() query without executing it.
     *              SELECT fields, ORDER BY, LIMIT, and OFFSET are not used for counts.
     * @param objectName SObject API name, e.g. 'Account'
     * @param filters WHERE conditions (nullable)
     * @param filterLogic e.g. '1 AND (2 OR 3)'; null/blank = AND all filters
     * @return A PreparedQuery holding the validated COUNT SOQL and its bind map
     */
    public static PreparedQuery prepareCount(
        String objectName,
        List<Filter> filters,
        String filterLogic
    ) {
        Schema.SObjectType sot = resolveObject(objectName);
        Map<String, Object> binds = new Map<String, Object>();
        String whereClause = buildWhere(sot, filters, filterLogic, binds);
        String soql =
            'SELECT COUNT() FROM ' + sot.getDescribe(SObjectDescribeOptions.DEFERRED).getName();
        if (String.isNotBlank(whereClause)) {
            soql += ' WHERE ' + whereClause;
        }
        return new PreparedQuery(soql, binds);
    }

    /**
     * @description Logs and runs a previously validated COUNT() query in USER_MODE.
     * @param pq The prepared COUNT query to execute
     * @return Matching row count
     */
    public static Integer count(PreparedQuery pq) {
        if (pq == null || String.isBlank(pq.soql)) {
            throw new DynamicSoqlException('Prepared COUNT query is required.');
        }
        Logger.debug('DynamicSoqlQuery COUNT SOQL: ' + pq.soql);
        Logger.debug('DynamicSoqlQuery binds: ' + describeBinds(pq.binds));
        return Database.countQueryWithBinds(pq.soql, pq.binds, AccessLevel.USER_MODE);
    }

    /**
     * @description Convenience COUNT() that prepares and executes in one call.
     * @param objectName SObject API name, e.g. 'Account'
     * @param filters WHERE conditions (nullable)
     * @param filterLogic e.g. '1 AND (2 OR 3)'; null/blank = AND all filters
     * @return Matching row count
     */
    public static Integer count(
        String objectName,
        List<Filter> filters,
        String filterLogic
    ) {
        return count(prepareCount(objectName, filters, filterLogic));
    }

    // ------------------------------------------------------------------------------------------
    // Security / validation helpers
    // ------------------------------------------------------------------------------------------

    /**
     * @description Validates an object API name and resolves it to a SObjectType, checking that
     *              the object exists and the running user has read (CRUD) access to it.
     * @param objectName SObject API name, e.g. 'Account'.
     * @return The resolved SObjectType.
     * @throws DynamicSoqlException If the name is blank/invalid, the object is unknown, or the
     *         running user lacks read access.
     */
    private static Schema.SObjectType resolveObject(String objectName) {
        if (String.isBlank(objectName) || !IDENTIFIER.matcher(objectName.trim()).matches()) {
            throw new DynamicSoqlException('Invalid object name: ' + objectName);
        }
        Schema.DescribeSObjectResult d;
        try {
            d = Schema.describeSObjects(new List<String>{ objectName.trim() }, SObjectDescribeOptions.DEFERRED)[0];
        } catch (System.InvalidParameterValueException e) {
            throw new DynamicSoqlException('Unknown object: ' + objectName);
        }
        if (!d.isAccessible() || !d.isQueryable()) {
            throw new DynamicSoqlException('Insufficient access to object: ' + d.getName());
        }
        return d.getSObjectType();
    }

    /**
     * @description Validates and de-duplicates the requested SELECT fields, and joins them into
     *              a SELECT clause of canonical field paths.
     * @param sot The SObjectType being queried.
     * @param fields Field paths requested by the caller.
     * @return The comma-separated SELECT clause contents.
     * @throws DynamicSoqlException If fields is null/empty, or any field path is invalid or inaccessible.
     */
    private static String buildSelect(Schema.SObjectType sot, List<String> fields) {
        if (fields == null || fields.isEmpty()) {
            throw new DynamicSoqlException('At least one field is required.');
        }
        // LinkedHashMap-like de-duplication (case-insensitive, preserves order)
        Set<String> seen = new Set<String>();
        List<String> safe = new List<String>();
        for (String path : fields) {
            String canonical = resolveFieldPath(sot, path, FieldUse.SELECTABLE);
            if (seen.add(canonical.toLowerCase())) {
                safe.add(canonical);
            }
        }
        return String.join(safe, ', ');
    }

    /**
     * @description Validates the requested filters, binds each filter's value, and combines the
     *              resulting conditions into a WHERE clause (AND-ed by default, or per filterLogic).
     * @param sot The SObjectType being queried.
     * @param filters WHERE conditions requested by the caller (nullable).
     * @param filterLogic Custom filter logic string (nullable/blank for AND-all).
     * @param binds Output map that bind names/values are added to.
     * @return The WHERE clause contents, or '' if there are no filters.
     * @throws DynamicSoqlException If a filter is invalid, uses a disallowed operator, or filter
     *         logic is supplied without filters.
     */
    private static String buildWhere(
        Schema.SObjectType sot,
        List<Filter> filters,
        String filterLogic,
        Map<String, Object> binds
    ) {
        if (filters == null || filters.isEmpty()) {
            if (String.isNotBlank(filterLogic)) {
                throw new DynamicSoqlException('Filter logic supplied without filters.');
            }
            return '';
        }

        List<String> conditions = new List<String>();
        for (Integer i = 0; i < filters.size(); i++) {
            Filter f = filters[i];
            if (f == null) {
                throw new DynamicSoqlException('Filter #' + (i + 1) + ' is null.');
            }
            String fieldPath = resolveFieldPath(sot, f.field, FieldUse.FILTERABLE);
            String op = (f.operator == null) ? '' : f.operator.normalizeSpace().toUpperCase();

            if (!ALLOWED_OPERATORS.contains(op)) {
                throw new DynamicSoqlException('Operator not allowed: ' + f.operator);
            }
            Boolean isCollection = f.value instanceof List<Object>;
            if (COLLECTION_OPERATORS.contains(op) && !isCollection) {
                throw new DynamicSoqlException(op + ' requires a List value (filter #' + (i + 1) + ').');
            }
            if (!COLLECTION_OPERATORS.contains(op) && isCollection) {
                throw new DynamicSoqlException(op + ' does not accept a List value (filter #' + (i + 1) + ').');
            }
            if (op == 'LIKE' && !(f.value instanceof String)) {
                throw new DynamicSoqlException('LIKE requires a String value (filter #' + (i + 1) + ').');
            }

            String bindName = 'p' + i;
            binds.put(bindName, f.value);                 // value is BOUND, never concatenated
            conditions.add(fieldPath + ' ' + op + ' :' + bindName);
        }

        if (String.isBlank(filterLogic)) {
            return String.join(conditions, ' AND ');
        }
        return applyFilterLogic(filterLogic, conditions);
    }

    /**
     * @description Replaces each filter number in a custom filter logic string with its
     *              parenthesised condition, rejecting any token that isn't a number, AND, OR,
     *              NOT, or a parenthesis, and requiring every filter to be referenced exactly once.
     * @param logic Filter logic string, e.g. '1 AND (2 OR 3)'.
     * @param conditions The bound WHERE conditions, in filter order (1-based when referenced).
     * @return The combined WHERE clause contents.
     * @throws DynamicSoqlException If the logic string contains an invalid token, references an
     *         unknown filter, has unbalanced parentheses, or omits a filter.
     */
    private static String applyFilterLogic(String logic, List<String> conditions) {
        Matcher m = LOGIC_TOKEN.matcher(logic);
        List<String> out = new List<String>();
        Set<Integer> used = new Set<Integer>();
        Integer pos = 0;
        Integer depth = 0;

        while (m.find()) {
            if (m.start() != pos) {
                throw new DynamicSoqlException('Invalid filter logic near position ' + pos + ': ' + logic);
            }
            pos = m.end();
            String tok = m.group(1).toUpperCase();

            if (tok.isNumeric()) {
                Integer idx = Integer.valueOf(tok);
                if (idx < 1 || idx > conditions.size()) {
                    throw new DynamicSoqlException('Filter logic references unknown filter ' + idx);
                }
                used.add(idx);
                out.add('(' + conditions[idx - 1] + ')');
                continue;
            }
            if (tok == '(') {
                depth++;
            } else if (tok == ')') {
                depth--;
                if (depth < 0) {
                    throw new DynamicSoqlException('Unbalanced parentheses in filter logic.');
                }
            }
            out.add(tok);
        }
        if (pos != logic.length()) {
            throw new DynamicSoqlException('Invalid filter logic: ' + logic);
        }
        if (depth != 0) {
            throw new DynamicSoqlException('Unbalanced parentheses in filter logic.');
        }
        if (used.size() != conditions.size()) {
            throw new DynamicSoqlException('Filter logic must reference every filter exactly as supplied.');
        }
        return String.join(out, ' ');
    }

    /**
     * @description Validates the requested orderings and joins them into an ORDER BY clause.
     * @param sot The SObjectType being queried.
     * @param orderings ORDER BY elements requested by the caller (nullable).
     * @return The ORDER BY clause contents, or '' if there are no orderings.
     * @throws DynamicSoqlException If an ordering is null or its field is invalid/not sortable.
     */
    private static String buildOrderBy(Schema.SObjectType sot, List<Ordering> orderings) {
        if (orderings == null || orderings.isEmpty()) {
            return '';
        }
        List<String> parts = new List<String>();
        for (Ordering o : orderings) {
            if (o == null) {
                throw new DynamicSoqlException('Ordering is null.');
            }
            String part = resolveFieldPath(sot, o.field, FieldUse.SORTABLE)
                + (o.descending ? ' DESC' : ' ASC');
            if (o.nullsLast != null) {
                part += o.nullsLast ? ' NULLS LAST' : ' NULLS FIRST';
            }
            parts.add(part);
        }
        return String.join(parts, ', ');
    }

    /**
     * @description Range-checks the LIMIT and OFFSET values.
     * @param limitCount Requested LIMIT (nullable); must be 1..MAX_LIMIT if supplied.
     * @param offsetCount Requested OFFSET (nullable); must be 0..MAX_OFFSET if supplied.
     * @throws DynamicSoqlException If either value is out of range.
     */
    private static void validateLimitOffset(Integer limitCount, Integer offsetCount) {
        if (limitCount != null && (limitCount < 1 || limitCount > MAX_LIMIT)) {
            throw new DynamicSoqlException('LIMIT must be between 1 and ' + MAX_LIMIT);
        }
        if (offsetCount != null && (offsetCount < 0 || offsetCount > MAX_OFFSET)) {
            throw new DynamicSoqlException('OFFSET must be between 0 and ' + MAX_OFFSET);
        }
    }

    /**
     * @description Resolves a (possibly dotted) field path against describe and returns its
     *              canonical form. Checks accessibility of every relationship, every related
     *              object, and the final field, and that the final field supports the requested use.
     * @param rootType The SObjectType the path starts from.
     * @param path Field API name or dotted relationship path, e.g. 'Owner.Name'.
     * @param use Which clause the field is being resolved for (SELECTABLE/FILTERABLE/SORTABLE).
     * @return The canonical, describe-verified field path.
     * @throws DynamicSoqlException If any segment is blank/invalid, the path is too deep, a
     *         relationship or related object is inaccessible or polymorphic, the final field is
     *         unknown or inaccessible, or it doesn't support the requested use (filterable/sortable).
     */
    private static String resolveFieldPath(Schema.SObjectType rootType, String path, FieldUse use) {
        if (String.isBlank(path)) {
            throw new DynamicSoqlException('Field name is blank.');
        }
        List<String> segments = path.trim().split('\\.');
        if (segments.size() > MAX_RELATIONSHIP_DEPTH + 1) {
            throw new DynamicSoqlException('Relationship path too deep: ' + path);
        }

        Schema.SObjectType current = rootType;
        List<String> canonical = new List<String>();

        for (Integer i = 0; i < segments.size(); i++) {
            String seg = segments[i];
            if (!IDENTIFIER.matcher(seg).matches()) {
                throw new DynamicSoqlException('Invalid field name: ' + path);
            }
            Boolean isLast = (i == segments.size() - 1);

            if (!isLast) {
                Schema.DescribeFieldResult rel = getRelationshipMap(current).get(seg.toLowerCase());
                if (rel == null || !rel.isAccessible()) {
                    throw new DynamicSoqlException('Invalid or inaccessible relationship "' + seg + '" in ' + path);
                }
                List<Schema.SObjectType> targets = rel.getReferenceTo();
                if (targets.size() != 1) {
                    throw new DynamicSoqlException('Polymorphic relationship not supported: ' + seg);
                }
                current = targets[0];
                if (!current.getDescribe(SObjectDescribeOptions.DEFERRED).isAccessible()) {
                    throw new DynamicSoqlException('Insufficient access to related object in ' + path);
                }
                canonical.add(rel.getRelationshipName());
            } else {
                Schema.SObjectField f = getFieldMap(current).get(seg.toLowerCase());
                if (f == null) {
                    throw new DynamicSoqlException('Unknown field: ' + path);
                }
                Schema.DescribeFieldResult dfr = f.getDescribe();
                if (!dfr.isAccessible()) {
                    throw new DynamicSoqlException('Insufficient access to field: ' + path);
                }
                if (use == FieldUse.FILTERABLE && !dfr.isFilterable()) {
                    throw new DynamicSoqlException('Field is not filterable: ' + path);
                }
                if (use == FieldUse.SORTABLE && !dfr.isSortable()) {
                    throw new DynamicSoqlException('Field is not sortable: ' + path);
                }
                canonical.add(dfr.getName());
            }
        }
        return String.join(canonical, '.');
    }

    /**
     * @description Returns (and lazily populates) the cached field-name-to-SObjectField map for
     *              an SObjectType.
     * @param sot The SObjectType to look up.
     * @return Map of lower-case field API name to SObjectField.
     */
    private static Map<String, Schema.SObjectField> getFieldMap(Schema.SObjectType sot) {
        if (!FIELD_MAP_CACHE.containsKey(sot)) {
            FIELD_MAP_CACHE.put(sot, sot.getDescribe(SObjectDescribeOptions.DEFERRED).fields.getMap());
        }
        return FIELD_MAP_CACHE.get(sot);
    }

    /**
     * @description Returns (and lazily populates) the cached relationship-name-to-lookup-field map
     *              for an SObjectType, e.g. 'owner' -> the OwnerId field describe.
     * @param sot The SObjectType to look up.
     * @return Map of lower-case relationship name to the describe of its underlying lookup/master-detail field.
     */
    private static Map<String, Schema.DescribeFieldResult> getRelationshipMap(Schema.SObjectType sot) {
        if (!RELATIONSHIP_CACHE.containsKey(sot)) {
            Map<String, Schema.DescribeFieldResult> rels = new Map<String, Schema.DescribeFieldResult>();
            for (Schema.SObjectField f : getFieldMap(sot).values()) {
                Schema.DescribeFieldResult dfr = f.getDescribe();
                if (dfr.getType() == Schema.DisplayType.REFERENCE && dfr.getRelationshipName() != null) {
                    rels.put(dfr.getRelationshipName().toLowerCase(), dfr);
                }
            }
            RELATIONSHIP_CACHE.put(sot, rels);
        }
        return RELATIONSHIP_CACHE.get(sot);
    }

    /**
     * @description Builds a debug-safe summary of a bind map (names and value types only, no
     *              actual values), for logging at DEBUG level without exposing potential PII.
     * @param binds The bind map to summarize.
     * @return A string like '{p0:String, p1:List[2]}'.
     */
    private static String describeBinds(Map<String, Object> binds) {
        List<String> parts = new List<String>();
        for (String key : binds.keySet()) {
            Object v = binds.get(key);
            String kind = (v == null) ? 'null'
                : (v instanceof List<Object>) ? 'List[' + ((List<Object>) v).size() + ']'
                : (v instanceof String) ? 'String'
                : (v instanceof Date) ? 'Date'
                : (v instanceof Datetime) ? 'Datetime'
                : (v instanceof Integer || v instanceof Long || v instanceof Decimal) ? 'Number'
                : (v instanceof Boolean) ? 'Boolean'
                : 'Object';
            parts.add(key + ':' + kind);
        }
        return '{' + String.join(parts, ', ') + '}';
    }
}