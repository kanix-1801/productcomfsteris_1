/**
 * @description Selector for OverhaulCodeMapping__mdt.
 *              getAll() loads every mapping without a SOQL query.
 */
public with sharing class OverhaulCodeMappingSelector extends SoqlQueryBuilder {
    /**
     * @description Binds this selector to OverhaulCodeMapping__mdt.
     */
    public OverhaulCodeMappingSelector() {
        this.objectName = 'OverhaulCodeMapping__mdt';
    }

    /**
     * @description Returns every overhaul code mapping.
     *              Custom Metadata getAll() does not count against the SOQL governor limit.
     * @return All OverhaulCodeMapping__mdt records
     */
    public static List<OverhaulCodeMapping__mdt> selectAll() {
        return OverhaulCodeMapping__mdt.getAll().values();
    }
}