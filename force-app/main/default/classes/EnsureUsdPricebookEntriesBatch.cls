/**
 * Ensures every Product2 has active USD PricebookEntry (UnitPrice = 0) on
 * Standard Price Book and IMS Service Pricebook. Skips products that already
 * have a USD entry on the target price book (does not overwrite existing prices).
 */
public class EnsureUsdPricebookEntriesBatch implements Database.Batchable<SObject>, Database.Stateful {
    private static final String CURRENCY_USD = 'USD';
    private static final String IMS_SERVICE_PRICEBOOK_NAME = 'IMS Service Pricebook';

    @TestVisible
    private Id standardPricebookId;
    @TestVisible
    private Id imsServicePricebookId;

    public Integer standardInserted = 0;
    public Integer imsInserted = 0;
    public Integer standardErrors = 0;
    public Integer imsErrors = 0;

    public EnsureUsdPricebookEntriesBatch() {
        resolvePricebooks();
    }

    public Database.QueryLocator start(Database.BatchableContext context) {
        resolvePricebooks();
        if (standardPricebookId == null) {
            throw new AuraHandledException('Standard Price Book was not found or is inactive.');
        }
        if (imsServicePricebookId == null) {
            throw new AuraHandledException('IMS Service Pricebook was not found or is inactive.');
        }
        return Database.getQueryLocator([
            SELECT Id
            FROM Product2
        ]);
    }

    public void execute(Database.BatchableContext context, List<SObject> scope) {
        resolvePricebooks();
        if (standardPricebookId == null || imsServicePricebookId == null || scope.isEmpty()) {
            return;
        }

        Set<Id> productIds = new Set<Id>();
        for (SObject row : scope) {
            productIds.add(row.Id);
        }

        Set<Id> hasStandardUsd = queryProductsWithUsdEntry(standardPricebookId, productIds);
        Set<Id> hasImsUsd = queryProductsWithUsdEntry(imsServicePricebookId, productIds);

        List<PricebookEntry> standardToInsert = new List<PricebookEntry>();
        List<PricebookEntry> imsToInsert = new List<PricebookEntry>();
        for (Id productId : productIds) {
            if (!hasStandardUsd.contains(productId)) {
                standardToInsert.add(buildUsdEntry(standardPricebookId, productId));
            }
            if (!hasImsUsd.contains(productId)) {
                imsToInsert.add(buildUsdEntry(imsServicePricebookId, productId));
            }
        }

        if (!standardToInsert.isEmpty()) {
            Database.SaveResult[] results = Database.insert(standardToInsert, false);
            tallyResults(results, true);
        }
        if (!imsToInsert.isEmpty()) {
            Database.SaveResult[] results = Database.insert(imsToInsert, false);
            tallyResults(results, false);
        }
    }

    public void finish(Database.BatchableContext context) {
        System.debug(
            LoggingLevel.INFO,
            'EnsureUsdPricebookEntriesBatch finished. ' +
            'Standard inserted=' + standardInserted +
            ', Standard errors=' + standardErrors +
            ', IMS Service inserted=' + imsInserted +
            ', IMS Service errors=' + imsErrors
        );
    }

    private void resolvePricebooks() {
        if (standardPricebookId == null) {
            List<Pricebook2> standardBooks = [
                SELECT Id
                FROM Pricebook2
                WHERE IsStandard = true
                AND IsActive = true
                LIMIT 1
            ];
            if (!standardBooks.isEmpty()) {
                standardPricebookId = standardBooks[0].Id;
            }
        }
        if (imsServicePricebookId == null) {
            List<Pricebook2> imsBooks = [
                SELECT Id
                FROM Pricebook2
                WHERE Name = :IMS_SERVICE_PRICEBOOK_NAME
                AND IsActive = true
                LIMIT 1
            ];
            if (!imsBooks.isEmpty()) {
                imsServicePricebookId = imsBooks[0].Id;
            }
        }
    }

    private static Set<Id> queryProductsWithUsdEntry(Id pricebookId, Set<Id> productIds) {
        Set<Id> found = new Set<Id>();
        for (PricebookEntry entry : [
            SELECT Product2Id
            FROM PricebookEntry
            WHERE Pricebook2Id = :pricebookId
            AND Product2Id IN :productIds
            AND CurrencyIsoCode = :CURRENCY_USD
        ]) {
            found.add(entry.Product2Id);
        }
        return found;
    }

    private static PricebookEntry buildUsdEntry(Id pricebookId, Id productId) {
        return new PricebookEntry(
            Pricebook2Id = pricebookId,
            Product2Id = productId,
            CurrencyIsoCode = CURRENCY_USD,
            UnitPrice = 0,
            IsActive = true,
            UseStandardPrice = false
        );
    }

    private void tallyResults(Database.SaveResult[] results, Boolean isStandard) {
        for (Database.SaveResult result : results) {
            if (result.isSuccess()) {
                if (isStandard) {
                    standardInserted++;
                } else {
                    imsInserted++;
                }
            } else {
                if (isStandard) {
                    standardErrors++;
                } else {
                    imsErrors++;
                }
                for (Database.Error error : result.getErrors()) {
                    System.debug(
                        LoggingLevel.WARN,
                        'PricebookEntry insert failed: ' + error.getStatusCode() + ' ' + error.getMessage()
                    );
                }
            }
        }
    }
}