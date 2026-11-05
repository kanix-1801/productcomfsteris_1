/**
 * @description Selector for WorkType. Queries use SoqlQueryBuilder.
 */
public with sharing class WorkTypesSelector extends SoqlQueryBuilder {
    /**
     * @description Creates a selector for WorkType.
     */
    public WorkTypesSelector() {
        super('WorkType');
    }

    /**
     * @description GW-2710 - Work Types matched by name.
     * @param workTypeNames Work Type names from the upload file.
     * @return Matching Work Types.
     */
    public static List<WorkType> selectByNames(Set<String> workTypeNames) {
        if (workTypeNames == null || workTypeNames.isEmpty()) {
            return new List<WorkType>();
        }
        List<String> names = new List<String>();
        names.addAll(workTypeNames);
        return (List<WorkType>) new WorkTypesSelector()
            .selectFields(new List<String>{ 'Id', 'Name' })
            .whereIn('Name', names)
            .execute();
    }
}