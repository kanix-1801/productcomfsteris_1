/**
 * @author PWC Developer
 * @date 2026/08/28
 *
 * @group Action Launcher
 *
 * @description
 * GC-3346 - Business logic for resolving and preparing Action Launcher actions.
 */
public without sharing class ActionLauncherService {

    public static final String SCENARIO = 'Action Launcher';
    public static final String LOGGER_TAG = 'ActionLauncher';
    public static final String TYPE_QUICK_ACTION = 'QuickAction';
    public static final String TYPE_WEB_LINK = 'WebLink';
    public static final String OPEN_TYPE_NEW_WINDOW = 'newWindow';

    private static final Pattern MERGE_FIELD_PATTERN = Pattern.compile('\\{!([^}]+)\\}');

    @TestVisible
    private static String forcedExceptionMethodName;

    /**
     * @description
     * GC-3346 - Resolves configured action names as quick actions or URL custom buttons.
     *
     * @param recordId Current record id used to resolve custom button merge fields.
     * @param objectApiName Current record object API name.
     * @param actionApiNames Comma-separated action API names in display order.
     * @return Action metadata available to the current user.
     */
    public static List<ActionLauncherController.LauncherAction> getActions(
        String recordId,
        String objectApiName,
        String actionApiNames
    ) {
        try {
            throwForcedTestExceptionIfRequested('getActions');

            List<String> qualifiedActionNameList = qualifyActionNames(objectApiName, actionApiNames);

            if (qualifiedActionNameList.isEmpty()) {
                return new List<ActionLauncherController.LauncherAction>();
            }

            Map<String, QuickAction.DescribeQuickActionResult> quickActionByNameMap =
                describeQuickActions(qualifiedActionNameList);
            List<String> unresolvedActionNameList =
                getUnresolvedActionNames(qualifiedActionNameList, quickActionByNameMap);
            Map<String, WebLink> webLinkByNameMap =
                getWebLinksByQualifiedName(objectApiName, unresolvedActionNameList);
            Map<String, String> mergeValueByTokenMap =
                resolveMergeValues(webLinkByNameMap.values(), recordId, objectApiName);

            return buildLauncherActions(
                qualifiedActionNameList,
                quickActionByNameMap,
                webLinkByNameMap,
                mergeValueByTokenMap
            );
        } catch (Exception exceptionValue) {
            Logger.setScenario(SCENARIO);
            Logger.error('Error resolving Action Launcher actions', exceptionValue).addTag(LOGGER_TAG);
            throw new ActionLauncherException('Unable to resolve Action Launcher actions.');
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description
     * GC-3346 - Qualifies bare action names with the current object and removes duplicates.
     *
     * @param objectApiName Current record object API name.
     * @param actionApiNames Comma-separated action API names.
     * @return Qualified action API names in configured order.
     */
    private static List<String> qualifyActionNames(String objectApiName, String actionApiNames) {
        List<String> qualifiedActionNameList = new List<String>();

        if (String.isBlank(actionApiNames)) {
            return qualifiedActionNameList;
        }

        Set<String> normalizedActionNameSet = new Set<String>();

        for (String rawActionName : actionApiNames.split(',')) {
            String actionName = rawActionName == null ? '' : rawActionName.trim();

            if (String.isBlank(actionName)) {
                continue;
            }

            if (!actionName.contains('.')) {
                if (String.isBlank(objectApiName)) {
                    continue;
                }

                actionName = objectApiName.trim() + '.' + actionName;
            }

            if (normalizedActionNameSet.add(actionName.toLowerCase())) {
                qualifiedActionNameList.add(actionName);
            }
        }

        return qualifiedActionNameList;
    }

    /**
     * @description
     * GC-3346 - Describes quick actions while isolating invalid action API names.
     *
     * @param qualifiedActionNameList Qualified action API names.
     * @return Quick action describe results keyed by API name.
     */
    private static Map<String, QuickAction.DescribeQuickActionResult> describeQuickActions(
        List<String> qualifiedActionNameList
    ) {
        Map<String, QuickAction.DescribeQuickActionResult> quickActionByNameMap =
            new Map<String, QuickAction.DescribeQuickActionResult>();

        try {
            addQuickActionDescribeResults(
                quickActionByNameMap,
                QuickAction.describeQuickActions(qualifiedActionNameList)
            );
            return quickActionByNameMap;
        } catch (Exception bulkDescribeException) {
            quickActionByNameMap.clear();
        }

        for (String qualifiedActionName : qualifiedActionNameList) {
            try {
                addQuickActionDescribeResults(
                    quickActionByNameMap,
                    QuickAction.describeQuickActions(new List<String>{ qualifiedActionName })
                );
            } catch (Exception singleDescribeException) {
                // GC-3346 - The unresolved name may represent a URL custom button.
                continue;
            }
        }

        return quickActionByNameMap;
    }

    /**
     * @description
     * GC-3346 - Adds valid quick action describe results to the action map.
     *
     * @param quickActionByNameMap Output map keyed by action API name.
     * @param describeResultList Quick action describe results.
     * @return void
     */
    private static void addQuickActionDescribeResults(
        Map<String, QuickAction.DescribeQuickActionResult> quickActionByNameMap,
        List<QuickAction.DescribeQuickActionResult> describeResultList
    ) {
        if (describeResultList == null) {
            return;
        }

        for (QuickAction.DescribeQuickActionResult describeResult : describeResultList) {
            if (describeResult != null && String.isNotBlank(describeResult.getName())) {
                quickActionByNameMap.put(describeResult.getName(), describeResult);
            }
        }
    }

    /**
     * @description
     * GC-3346 - Returns configured action names that did not resolve as quick actions.
     *
     * @param qualifiedActionNameList Configured action names.
     * @param quickActionByNameMap Resolved quick actions.
     * @return Names to resolve as URL custom buttons.
     */
    private static List<String> getUnresolvedActionNames(
        List<String> qualifiedActionNameList,
        Map<String, QuickAction.DescribeQuickActionResult> quickActionByNameMap
    ) {
        List<String> unresolvedActionNameList = new List<String>();

        for (String qualifiedActionName : qualifiedActionNameList) {
            if (!quickActionByNameMap.containsKey(qualifiedActionName)) {
                unresolvedActionNameList.add(qualifiedActionName);
            }
        }

        return unresolvedActionNameList;
    }

    /**
     * @description
     * GC-3346 - Queries URL custom buttons and maps them to qualified action names.
     *
     * @param objectApiName Current record object API name.
     * @param qualifiedActionNameList Unresolved qualified action names.
     * @return URL custom buttons keyed by qualified action name.
     */
    private static Map<String, WebLink> getWebLinksByQualifiedName(
        String objectApiName,
        List<String> qualifiedActionNameList
    ) {
        Map<String, WebLink> webLinkByQualifiedNameMap = new Map<String, WebLink>();

        if (
            String.isBlank(objectApiName) ||
            qualifiedActionNameList == null ||
            qualifiedActionNameList.isEmpty()
        ) {
            return webLinkByQualifiedNameMap;
        }

        Map<String, String> qualifiedNameByBareNameMap = new Map<String, String>();

        for (String qualifiedActionName : qualifiedActionNameList) {
            String bareActionName = qualifiedActionName.substringAfterLast('.');

            if (String.isNotBlank(bareActionName)) {
                qualifiedNameByBareNameMap.put(bareActionName, qualifiedActionName);
            }
        }

        for (WebLink webLinkRecord : ActionLauncherSelector.selectUrlWebLinks(
            objectApiName.trim(),
            qualifiedNameByBareNameMap.keySet()
        )) {
            String qualifiedActionName = qualifiedNameByBareNameMap.get(webLinkRecord.Name);

            if (qualifiedActionName != null) {
                webLinkByQualifiedNameMap.put(qualifiedActionName, webLinkRecord);
            }
        }

        return webLinkByQualifiedNameMap;
    }

    /**
     * @description
     * GC-3346 - Resolves supported merge-field tokens used by URL custom buttons.
     *
     * @param webLinkList URL custom buttons.
     * @param recordId Current record id.
     * @param objectApiName Current record object API name.
     * @return URL-encoded record values keyed by merge token.
     */
    private static Map<String, String> resolveMergeValues(
        List<WebLink> webLinkList,
        String recordId,
        String objectApiName
    ) {
        Map<String, String> mergeValueByTokenMap = new Map<String, String>();

        if (
            webLinkList == null ||
            webLinkList.isEmpty() ||
            String.isBlank(recordId) ||
            String.isBlank(objectApiName)
        ) {
            return mergeValueByTokenMap;
        }

        Schema.SObjectType objectType = Schema.getGlobalDescribe().get(objectApiName.trim());

        if (objectType == null) {
            return mergeValueByTokenMap;
        }

        Map<String, Schema.SObjectField> fieldByNameMap = objectType.getDescribe().fields.getMap();
        Map<String, String> fieldNameByTokenMap = new Map<String, String>();
        Set<String> fieldNameSet = new Set<String>{ 'Id' };

        for (WebLink webLinkRecord : webLinkList) {
            Matcher mergeFieldMatcher =
                MERGE_FIELD_PATTERN.matcher(webLinkRecord.Url == null ? '' : webLinkRecord.Url);

            while (mergeFieldMatcher.find()) {
                String mergeToken = mergeFieldMatcher.group(0);

                if (fieldNameByTokenMap.containsKey(mergeToken)) {
                    continue;
                }

                String fieldName = parseFieldName(mergeFieldMatcher.group(1), objectApiName);
                Schema.SObjectField objectField =
                    String.isBlank(fieldName) ? null : fieldByNameMap.get(fieldName.toLowerCase());

                if (objectField == null || !objectField.getDescribe().isAccessible()) {
                    continue;
                }

                String resolvedFieldName = objectField.getDescribe().getName();
                fieldNameByTokenMap.put(mergeToken, resolvedFieldName);
                fieldNameSet.add(resolvedFieldName);
            }
        }

        if (fieldNameByTokenMap.isEmpty()) {
            return mergeValueByTokenMap;
        }

        SObject sourceRecord = ActionLauncherSelector.selectRecordById(
            recordId,
            objectType.getDescribe().getName(),
            fieldNameSet
        );

        if (sourceRecord == null) {
            return mergeValueByTokenMap;
        }

        for (String mergeToken : fieldNameByTokenMap.keySet()) {
            Object fieldValue = sourceRecord.get(fieldNameByTokenMap.get(mergeToken));
            String stringValue = fieldValue == null ? '' : String.valueOf(fieldValue);
            mergeValueByTokenMap.put(mergeToken, EncodingUtil.urlEncode(stringValue, 'UTF-8'));
        }

        return mergeValueByTokenMap;
    }

    /**
     * @description
     * GC-3346 - Extracts a field API name from supported Salesforce merge-field formats.
     *
     * @param rawMergeExpression Merge expression without the outer braces.
     * @param objectApiName Current record object API name.
     * @return Field API name, or null when the expression is blank.
     */
    private static String parseFieldName(String rawMergeExpression, String objectApiName) {
        String mergeExpression = rawMergeExpression == null ? '' : rawMergeExpression.trim();

        if (String.isBlank(mergeExpression)) {
            return null;
        }

        if (
            mergeExpression.toUpperCase().startsWith('CASESAFEID(') &&
            mergeExpression.endsWith(')')
        ) {
            mergeExpression = mergeExpression.substring(
                'CASESAFEID('.length(),
                mergeExpression.length() - 1
            ).trim();
        }

        if (mergeExpression.contains('.')) {
            return mergeExpression.substringAfterLast('.');
        }

        String legacyObjectPrefix = objectApiName.trim() + '_';

        if (
            mergeExpression.length() > legacyObjectPrefix.length() &&
            mergeExpression.startsWithIgnoreCase(legacyObjectPrefix)
        ) {
            return mergeExpression.substring(legacyObjectPrefix.length());
        }

        return mergeExpression;
    }

    /**
     * @description
     * GC-3346 - Builds launcher action wrappers in the configured display order.
     *
     * @param qualifiedActionNameList Configured action names.
     * @param quickActionByNameMap Resolved quick action metadata.
     * @param webLinkByNameMap Resolved URL custom buttons.
     * @param mergeValueByTokenMap URL-encoded merge values.
     * @return Ordered launcher action wrappers.
     */
    private static List<ActionLauncherController.LauncherAction> buildLauncherActions(
        List<String> qualifiedActionNameList,
        Map<String, QuickAction.DescribeQuickActionResult> quickActionByNameMap,
        Map<String, WebLink> webLinkByNameMap,
        Map<String, String> mergeValueByTokenMap
    ) {
        List<ActionLauncherController.LauncherAction> launcherActionList =
            new List<ActionLauncherController.LauncherAction>();

        for (String qualifiedActionName : qualifiedActionNameList) {
            QuickAction.DescribeQuickActionResult describeResult =
                quickActionByNameMap.get(qualifiedActionName);

            if (describeResult != null) {
                if (isQuickActionAccessible(describeResult)) {
                    launcherActionList.add(buildQuickAction(describeResult));
                }
                continue;
            }

            WebLink webLinkRecord = webLinkByNameMap.get(qualifiedActionName);

            if (webLinkRecord != null) {
                launcherActionList.add(
                    buildWebLinkAction(
                        qualifiedActionName,
                        webLinkRecord,
                        mergeValueByTokenMap
                    )
                );
            }
        }

        return launcherActionList;
    }

    /**
     * @description
     * GC-3346 - Maps quick action describe metadata to the UI wrapper.
     *
     * @param describeResult Quick action describe metadata.
     * @return Launcher action wrapper.
     */
    private static ActionLauncherController.LauncherAction buildQuickAction(
        QuickAction.DescribeQuickActionResult describeResult
    ) {
        ActionLauncherController.LauncherAction launcherAction =
            new ActionLauncherController.LauncherAction();
        launcherAction.apiName = describeResult.getName();
        launcherAction.label = String.isBlank(describeResult.getLabel())
            ? describeResult.getName()
            : describeResult.getLabel();
        launcherAction.actionType = TYPE_QUICK_ACTION;
        launcherAction.targetSobjectType = describeResult.getTargetSobjectType();
        launcherAction.opensInNewWindow = false;
        return launcherAction;
    }

    /**
     * @description
     * GC-3346 - Maps a URL custom button to the UI wrapper and resolves merge fields.
     *
     * @param qualifiedActionName Qualified custom button name.
     * @param webLinkRecord URL custom button metadata.
     * @param mergeValueByTokenMap URL-encoded merge values.
     * @return Launcher action wrapper.
     */
    private static ActionLauncherController.LauncherAction buildWebLinkAction(
        String qualifiedActionName,
        WebLink webLinkRecord,
        Map<String, String> mergeValueByTokenMap
    ) {
        ActionLauncherController.LauncherAction launcherAction =
            new ActionLauncherController.LauncherAction();
        launcherAction.apiName = qualifiedActionName;
        launcherAction.label = String.isBlank(webLinkRecord.MasterLabel)
            ? webLinkRecord.Name
            : webLinkRecord.MasterLabel;
        launcherAction.actionType = TYPE_WEB_LINK;
        launcherAction.url = applyMergeValues(webLinkRecord.Url, mergeValueByTokenMap);
        launcherAction.opensInNewWindow =
            OPEN_TYPE_NEW_WINDOW.equalsIgnoreCase(webLinkRecord.OpenType);
        return launcherAction;
    }

    /**
     * @description
     * GC-3346 - Replaces resolved merge fields and removes unsupported tokens from a URL.
     *
     * @param url Custom button URL.
     * @param mergeValueByTokenMap URL-encoded merge values.
     * @return Resolved URL.
     */
    private static String applyMergeValues(
        String url,
        Map<String, String> mergeValueByTokenMap
    ) {
        if (String.isBlank(url)) {
            return url;
        }

        String resolvedUrl = url;

        for (String mergeToken : mergeValueByTokenMap.keySet()) {
            resolvedUrl = resolvedUrl.replace(mergeToken, mergeValueByTokenMap.get(mergeToken));
        }

        return MERGE_FIELD_PATTERN.matcher(resolvedUrl).replaceAll('');
    }

    /**
     * @description
     * GC-3346 - Checks create access for quick actions that create target records.
     *
     * @param describeResult Quick action describe metadata.
     * @return True when the current user can access the action.
     */
    private static Boolean isQuickActionAccessible(
        QuickAction.DescribeQuickActionResult describeResult
    ) {
        String targetSobjectType = describeResult.getTargetSobjectType();

        if (describeResult.getType() != 'Create' || String.isBlank(targetSobjectType)) {
            return true;
        }

        Schema.SObjectType objectType = Schema.getGlobalDescribe().get(targetSobjectType);
        return objectType != null && objectType.getDescribe().isCreateable();
    }

    /**
     * @description
     * GC-3346 - Throws a controlled exception for unit-test exception coverage.
     *
     * @param methodName Current service method name.
     * @return void
     */
    @SuppressWarnings('PMD.AvoidTestIsRunningTest')
    private static void throwForcedTestExceptionIfRequested(String methodName) {
        if (Test.isRunningTest() && forcedExceptionMethodName == methodName) {
            throw new QueryException('Script-thrown exception');
        }
    }
}