/**
 * @author Uptima Development Team
 * @date 2026-06-14
 * @description Controller for the Return Order Path LWC; exposes active Return Order status picklist values.
 * @group Return Order Process
 * @see returnOrderPath
 */
public with sharing class ReturnOrderPathController {

    /**
     * @description Label/value pair for LWC picklists and path components.
     */
    public class PicklistOption {
        /** @description Display label for the picklist entry. */
        @AuraEnabled public String label;
        /** @description API value stored on the Return Order. */
        @AuraEnabled public String value;
    }

    /**
     * @description Returns active Return Order Status picklist values for the path component.
     * @return Active status options ordered as defined in metadata.
     */
    @AuraEnabled(cacheable=true)
    public static List<PicklistOption> getStatusPicklistValues() {
        List<PicklistOption> options = new List<PicklistOption>();
        for (Schema.PicklistEntry entry : ReturnOrder.Status.getDescribe().getPicklistValues()) {
            if (!entry.isActive()) {
                continue;
            }
            PicklistOption option = new PicklistOption();
            option.label = entry.getLabel();
            option.value = entry.getValue();
            options.add(option);
        }
        return options;
    }
}