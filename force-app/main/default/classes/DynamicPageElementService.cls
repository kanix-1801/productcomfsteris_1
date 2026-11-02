/**
 * @date 2026/07/22
 *
 * @group Account Management
 *
 * @description
 * Service layer for the metadata-driven page layout framework (GC-3183).
 * Responsibilities:
 * - Resolve access level (Base vs Full) via DynamicPageAccessRule__mdt
 * - Query DynamicPageElement__mdt via DynamicPageElementSelector
 * - Deduplicate rows by ApiName__c (Full wins over Base)
 * - Build nested Tab → Section → Field/Component JSON tree for LWC consumption
 *
 * Inner classes (DynamicPageElementResponse, TabNode, SectionNode, ElementNode) mirror the
 * structure consumed by metadataPageShell and its child components.
 *
 * @see DynamicPageElementController
 * @see DynamicPageElementSelector
 * @see metadataPageShell
 * @see metadataTabContent
 * GC-3183
 */
public with sharing class DynamicPageElementService {

    /** @description Nebula Logger scenario for metadata engine transactions. */
    private static final String SCENARIO = 'Metadata Engine';

    /** @description Nebula Logger tag for this class. */
    private static final String LOGGER_TAG = 'DynamicPageElementService';

    /** @description Access level returned when the user is on the Account Team. */
    private static final String ACCESS_LEVEL_FULL = 'Full';

    /** @description Access level returned when the user is not on the Account Team. */
    private static final String ACCESS_LEVEL_BASE = 'Base';

    /**
     * @description
     * Aura-enabled response wrapper returned to metadataPageShell.
     */
    public class DynamicPageElementResponse {
        /** @description Resolved access level: Base or Full. */
        @AuraEnabled public String accessLevel;
        /** @description Top-level tab nodes ordered by DisplayOrder__c. */
        @AuraEnabled public List<TabNode> tabs;
    }

    /**
     * @description
     * Represents one CMDT Tab row and its direct children.
     */
    public class TabNode {
        /** @description ApiName__c of the tab metadata row. */
        @AuraEnabled public String apiName;
        /** @description Tab label shown in lightning-tab. */
        @AuraEnabled public String label;
        /** @description DisplayOrder__c for tab sort order. */
        @AuraEnabled public Decimal displayOrder;
        /** @description Section nodes nested under this tab. */
        @AuraEnabled public List<SectionNode> sections;
        /** @description Field/Component nodes placed directly under the tab. */
        @AuraEnabled public List<ElementNode> elements;
        /** @description FieldList nodes placed directly under the tab. */
        @AuraEnabled public List<FieldListNode> fieldLists;
    }

    /**
     * @description
     * Represents one CMDT Section row and its child Field/Component elements.
     */
    public class SectionNode {
        /** @description ApiName__c of the section metadata row. */
        @AuraEnabled public String apiName;
        /** @description Section header label. */
        @AuraEnabled public String label;
        /** @description DisplayOrder__c within the parent tab. */
        @AuraEnabled public Decimal displayOrder;
        /** @description IsEditable__c — controls form mode for Full users. */
        @AuraEnabled public Boolean isEditable;
        /** @description Field and Component rows under this section. */
        @AuraEnabled public List<ElementNode> elements;
    }

    /**
     * @description
     * Represents one CMDT Field or Component row. Consumed by metadataColumnLayout
     * (fields) and metadataElementRenderer (components).
     */
    public class ElementNode {
        /** @description ApiName__c unique key within the page. */
        @AuraEnabled public String apiName;
        /** @description ElementType__c: Field or Component. */
        @AuraEnabled public String elementType;
        /** @description ObjectAPIName__c for Field rows (e.g. Account). */
        @AuraEnabled public String objectApiName;
        /** @description FieldAPIName__c for Field rows (e.g. Name). */
        @AuraEnabled public String fieldApiName;
        /** @description ComponentAPIName__c for Component rows (custom or standard:*). */
        @AuraEnabled public String componentApiName;
        /** @description Column__c: Left, Right, or Full. */
        @AuraEnabled public String column;
        /** @description DisplayOrder__c within the parent tab or section. */
        @AuraEnabled public Decimal displayOrder;
        /** @description IsEditable__c on individual field rows (block edit uses section/tab). */
        @AuraEnabled public Boolean isEditable;
        /** @description PropsJson__c JSON string passed to leaf LWCs via lwc:spread. */
        @AuraEnabled public String propsJson;
    }

    /**
     * @description
     * One parsed field entry with its resolved display mode for FieldList rows.
     */
    public class FieldListItemNode {
        /** @description SObject field API name without suffix. */
        @AuraEnabled public String fieldApiName;
        /** @description Field mode: readonly, editable, or required. */
        @AuraEnabled public String mode;
    }

    /**
     * @description
     * Represents one CMDT FieldList row with parsed left and right column field definitions.
     */
    public class FieldListNode {
        /** @description ApiName__c of the FieldList metadata row. */
        @AuraEnabled public String apiName;
        /** @description ObjectAPIName__c for all fields in this list. */
        @AuraEnabled public String objectApiName;
        /** @description DisplayOrder__c within the parent tab. */
        @AuraEnabled public Decimal displayOrder;
        /** @description Parsed left-column field items. */
        @AuraEnabled public List<FieldListItemNode> leftFields;
        /** @description Parsed right-column field items. */
        @AuraEnabled public List<FieldListItemNode> rightFields;
    }

    /**
     * @description
     * Retrieves and builds the page layout tree for the provided record context.
     *
     * @param recordId Record Id used to evaluate the configured access strategy.
     * @param objectApiName SObject API name for the record page.
     * @param pageName PageName__c value used to retrieve matching metadata records.
     * @return Page layout response containing access level and tab hierarchy.
     */
    public static DynamicPageElementResponse getPageLayout(
        Id recordId,
        String objectApiName,
        String pageName
    ) {
        if (recordId == null) {
            Logger.setScenario(SCENARIO);
            Logger.warn(LOGGER_TAG + ': Record Id is required.')
                .addTag(LOGGER_TAG)
                .addTag('MetadataEngine')
                .addTag('GC-3183');
            throw new AuraHandledException('Record Id is required.');
        }

        if (String.isBlank(objectApiName)) {
            Logger.setScenario(SCENARIO);
            Logger.warn(LOGGER_TAG + ': Object API name is required.')
                .addTag(LOGGER_TAG)
                .addTag('MetadataEngine')
                .addTag('GC-3183');
            throw new AuraHandledException('Object API name is required.');
        }

        if (String.isBlank(pageName)) {
            Logger.setScenario(SCENARIO);
            Logger.warn(LOGGER_TAG + ': Page name is required.')
                .addTag(LOGGER_TAG)
                .addTag('MetadataEngine')
                .addTag('GC-3183');
            throw new AuraHandledException('Page name is required.');
        }

        String accessLevel = DynamicPageAccessResolver.resolveAccessLevel(
            recordId,
            objectApiName,
            pageName
        );

        List<DynamicPageElement__mdt> records =
            dedupeByApiName(DynamicPageElementSelector.getDynamicPageElements(pageName, accessLevel));

        DynamicPageElementResponse response = new DynamicPageElementResponse();
        response.accessLevel = accessLevel;
        response.tabs = buildTabs(records);
        return response;
    }

    /**
     * @description
     * Removes duplicate metadata rows by ApiName__c, preferring Full over Base access rows.
     *
     * @param records Flat list of DynamicPageElement metadata records.
     * @return Deduplicated list of metadata records.
     */
    @TestVisible
    private static List<DynamicPageElement__mdt> dedupeByApiName(
        List<DynamicPageElement__mdt> records
    ) {
        Map<String, DynamicPageElement__mdt> uniqueByApiName =
            new Map<String, DynamicPageElement__mdt>();

        for (DynamicPageElement__mdt record : records) {
            if (!uniqueByApiName.containsKey(record.ApiName__c)) {
                uniqueByApiName.put(record.ApiName__c, record);
                continue;
            }

            if (record.AccessLevel__c == ACCESS_LEVEL_FULL) {
                uniqueByApiName.put(record.ApiName__c, record);
            }
        }

        return uniqueByApiName.values();
    }

    /**
     * @description
     * Builds the top-level tab nodes from a flat metadata record list.
     *
     * @param records Deduplicated DynamicPageElement metadata records.
     * @return Ordered list of tab layout nodes.
     */
    @TestVisible
    private static List<TabNode> buildTabs(List<DynamicPageElement__mdt> records) {
        Map<String, List<DynamicPageElement__mdt>> childrenByParent =
            new Map<String, List<DynamicPageElement__mdt>>();
        List<DynamicPageElement__mdt> tabRecords = new List<DynamicPageElement__mdt>();

        for (DynamicPageElement__mdt record : records) {
            if (record.ElementType__c == 'Tab') {
                tabRecords.add(record);
                continue;
            }

            if (String.isBlank(record.ParentApiName__c)) {
                continue;
            }

            addChild(childrenByParent, record.ParentApiName__c, record);
        }

        tabRecords.sort(new ConfigDisplayOrderComparator());

        List<TabNode> tabs = new List<TabNode>();
        for (DynamicPageElement__mdt tabRecord : tabRecords) {
            tabs.add(buildTabNode(tabRecord, childrenByParent));
        }

        return tabs;
    }

    /**
     * @description
     * Builds a tab node with optional sections and direct child field or component elements.
     *
     * @param tabRecord Tab metadata record.
     * @param childrenByParent Map of parent ApiName__c to child metadata records.
     * @return Populated tab layout node.
     */
    private static TabNode buildTabNode(
        DynamicPageElement__mdt tabRecord,
        Map<String, List<DynamicPageElement__mdt>> childrenByParent
    ) {
        TabNode tab = new TabNode();
        tab.apiName = tabRecord.ApiName__c;
        tab.label = tabRecord.Label__c;
        tab.displayOrder = tabRecord.DisplayOrder__c;
        tab.sections = new List<SectionNode>();
        tab.elements = new List<ElementNode>();
        tab.fieldLists = new List<FieldListNode>();

        List<DynamicPageElement__mdt> children = childrenByParent.get(tabRecord.ApiName__c);
        if (children == null) {
            return tab;
        }

        children.sort(new ConfigDisplayOrderComparator());

        for (DynamicPageElement__mdt child : children) {
            if (child.ElementType__c == 'Section') {
                tab.sections.add(buildSectionNode(child, childrenByParent));
            } else if (child.ElementType__c == 'FieldList') {
                tab.fieldLists.add(buildFieldListNode(child));
            } else if (isRenderableElement(child.ElementType__c)) {
                tab.elements.add(buildElementNode(child));
            }
        }

        return tab;
    }

    /**
     * @description
     * Builds a section node and its child field or component elements.
     *
     * @param sectionRecord Section metadata record.
     * @param childrenByParent Map of parent ApiName__c to child metadata records.
     * @return Populated section layout node.
     */
    private static SectionNode buildSectionNode(
        DynamicPageElement__mdt sectionRecord,
        Map<String, List<DynamicPageElement__mdt>> childrenByParent
    ) {
        SectionNode section = new SectionNode();
        section.apiName = sectionRecord.ApiName__c;
        section.label = sectionRecord.Label__c;
        section.displayOrder = sectionRecord.DisplayOrder__c;
        section.isEditable = sectionRecord.IsEditable__c == true;
        section.elements = new List<ElementNode>();

        List<DynamicPageElement__mdt> children = childrenByParent.get(sectionRecord.ApiName__c);
        if (children == null) {
            return section;
        }

        children.sort(new ConfigDisplayOrderComparator());

        for (DynamicPageElement__mdt child : children) {
            if (isRenderableElement(child.ElementType__c)) {
                section.elements.add(buildElementNode(child));
            }
        }

        return section;
    }

    /**
     * @description
     * Maps a metadata record to an Aura-enabled element node.
     *
     * @param record Field or component metadata record.
     * @return Populated element layout node.
     */
    private static ElementNode buildElementNode(DynamicPageElement__mdt record) {
        ElementNode element = new ElementNode();
        element.apiName = record.ApiName__c;
        element.elementType = record.ElementType__c;
        element.objectApiName = record.ObjectAPIName__c;
        element.fieldApiName = record.FieldAPIName__c;
        element.componentApiName = record.ComponentAPIName__c;
        element.column = String.isBlank(record.Column__c) ? 'Left' : record.Column__c;
        element.displayOrder = record.DisplayOrder__c;
        element.isEditable = record.IsEditable__c == true;
        element.propsJson = record.PropsJson__c;
        return element;
    }

    /**
     * @description
     * Maps a FieldList metadata record to an Aura-enabled field list node.
     *
     * @param record FieldList metadata record.
     * @return Populated field list node with parsed left and right columns.
     */
    private static FieldListNode buildFieldListNode(DynamicPageElement__mdt record) {
        FieldListNode fieldList = new FieldListNode();
        fieldList.apiName = record.ApiName__c;
        fieldList.objectApiName = record.ObjectAPIName__c;
        fieldList.displayOrder = record.DisplayOrder__c;
        fieldList.leftFields = toFieldListItemNodes(
            DynamicPageElementFieldListParser.parse(record.LeftSideFields__c)
        );
        fieldList.rightFields = toFieldListItemNodes(
            DynamicPageElementFieldListParser.parse(record.RightSideFields__c)
        );

        return fieldList;
    }

    /**
     * @description
     * Converts parser field items into Aura-enabled layout nodes.
     *
     * @param parsedItems Parsed field list items from DynamicPageElementFieldListParser.
     * @return Aura-enabled field list item nodes.
     */
    private static List<FieldListItemNode> toFieldListItemNodes(
        List<DynamicPageElementFieldListParser.FieldListItem> parsedItems
    ) {
        List<FieldListItemNode> items = new List<FieldListItemNode>();

        if (parsedItems == null) {
            return items;
        }

        for (DynamicPageElementFieldListParser.FieldListItem parsedItem : parsedItems) {
            FieldListItemNode item = new FieldListItemNode();
            item.fieldApiName = parsedItem.fieldApiName;
            item.mode = parsedItem.mode;
            items.add(item);
        }

        return items;
    }

    /**
     * @description
     * Adds a child metadata record to the parent lookup map.
     *
     * @param childrenByParent Map of parent ApiName__c to child metadata records.
     * @param parentApiName Parent ApiName__c value.
     * @param child Child metadata record to append.
     */
    private static void addChild(
        Map<String, List<DynamicPageElement__mdt>> childrenByParent,
        String parentApiName,
        DynamicPageElement__mdt child
    ) {
        if (!childrenByParent.containsKey(parentApiName)) {
            childrenByParent.put(parentApiName, new List<DynamicPageElement__mdt>());
        }

        childrenByParent.get(parentApiName).add(child);
    }

    /**
     * @description
     * Determines whether the metadata element type can be rendered by the LWC framework.
     *
     * @param elementType DynamicPageElement ElementType__c value.
     * @return TRUE when the element type is Field or Component; otherwise FALSE.
     */
    private static Boolean isRenderableElement(String elementType) {
        return elementType == 'Field' || elementType == 'Component';
    }

    /**
     * @description
     * Comparator used to sort DynamicPageElement metadata records by DisplayOrder__c.
     */
    private class ConfigDisplayOrderComparator implements System.Comparator<DynamicPageElement__mdt> {
        /**
         * @description
         * Compares two metadata records by DisplayOrder__c ascending.
         *
         * @param first First metadata record.
         * @param second Second metadata record.
         * @return Negative, zero, or positive comparison result.
         */
        public Integer compare(DynamicPageElement__mdt first, DynamicPageElement__mdt second) {
            Decimal firstOrder = first.DisplayOrder__c != null ? first.DisplayOrder__c : 0;
            Decimal secondOrder = second.DisplayOrder__c != null ? second.DisplayOrder__c : 0;

            if (firstOrder == secondOrder) {
                return 0;
            }

            return firstOrder < secondOrder ? -1 : 1;
        }
    }
}