/**
 * @description Selector for Pricebook2. Queries use SoqlQueryBuilder.
 */
public with sharing class PricebooksSelector extends SoqlQueryBuilder {
    /**
     * @description Binds this selector to Pricebook2 for SoqlQueryBuilder queries.
     */
    public PricebooksSelector() {
        this.objectName = 'Pricebook2';
    }

    /**
     * @description GW-5492 - Active standard price book.
     * @return Matching price book, or an empty list
     */
    public static List<Pricebook2> selectActiveStandard() {
        return (List<Pricebook2>) new PricebooksSelector()
            .selectField('Id')
            .whereEquals('IsActive', true)
            .whereEquals('IsStandard', true)
            .limitTo(1)
            .execute();
    }

    /**
     * @description Active price book with the given name.
     * @param pricebookName Price book name
     * @return Matching price book, or an empty list
     */
    public static List<Pricebook2> selectActiveByName(String pricebookName) {
        if (String.isBlank(pricebookName)) {
            return new List<Pricebook2>();
        }
        return (List<Pricebook2>) new PricebooksSelector()
            .selectField('Id')
            .whereEquals('Name', pricebookName)
            .whereEquals('IsActive', true)
            .limitTo(1)
            .execute();
    }

    /**
     * @description GW-5492 - Oldest active price book.
     * @return Matching price book, or an empty list
     */
    public static List<Pricebook2> selectFirstActive() {
        return (List<Pricebook2>) new PricebooksSelector()
            .selectField('Id')
            .whereEquals('IsActive', true)
            .orderBy('CreatedDate')
            .limitTo(1)
            .execute();
    }
}