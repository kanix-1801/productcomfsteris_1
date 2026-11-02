/**
 * @description Service class for PricebookEntry business operations (plural).
 *              GW-3913 / GW-3096 - Device Evaluation Price Book Entry lookups.
 *              Distinct from PricebookEntrySelector (Generate Quote).
 */
public with sharing class PricebookEntriesService {
    @TestVisible
    private interface IPricebookEntriesSelector {
        List<PricebookEntry> selectActiveByPricebookProductAndCurrency(
            Id pricebookId,
            Set<Id> productIds,
            String currencyIsoCode
        );
    }

    private class DefaultPricebookEntriesSelector implements IPricebookEntriesSelector {
        public List<PricebookEntry> selectActiveByPricebookProductAndCurrency(
            Id pricebookId,
            Set<Id> productIds,
            String currencyIsoCode
        ) {
            return PricebookEntriesSelector.selectActiveByPricebookProductAndCurrency(
                pricebookId,
                productIds,
                currencyIsoCode
            );
        }
    }

    @TestVisible
    private static IPricebookEntriesSelector selectorOverride;

    private static IPricebookEntriesSelector selector() {
        return selectorOverride == null
            ? new DefaultPricebookEntriesSelector()
            : selectorOverride;
    }

    /**
     * @description GW-3913 / GW-3096 - Returns a map of Product2Id to active PricebookEntry Id
     *              for the given Price Book and currency (Device Evaluation).
     * @param pricebookId Price Book Id
     * @param productIds Product2 Ids to resolve entries for
     * @param currencyIsoCode Work Order CurrencyIsoCode
     * @return Map of Product2Id to PricebookEntry Id (empty when none / null-empty input)
     * @throws PricebookEntriesServiceException when the operation fails
     */
    public static Map<Id, Id> getPricebookEntryIdsByProductId(
        Id pricebookId,
        Set<Id> productIds,
        String currencyIsoCode
    ) {
        Map<Id, Id> entryIdsByProductId = new Map<Id, Id>();
        if (pricebookId == null || productIds == null || productIds.isEmpty()) {
            return entryIdsByProductId;
        }
        try {
            for (
                PricebookEntry entry : selector().selectActiveByPricebookProductAndCurrency(
                    pricebookId,
                    productIds,
                    currencyIsoCode
                )
            ) {
                entryIdsByProductId.put(entry.Product2Id, entry.Id);
            }
            return entryIdsByProductId;
        } catch (Exception e) {
            Logger.error(
                new LogMessage(
                    'PricebookEntriesService.getPricebookEntryIdsByProductId failed for Pricebook {0}: {1}',
                    pricebookId,
                    e.getMessage()
                ),
                e
            );
            throw new PricebookEntriesServiceException(
                'An unexpected error occurred while retrieving Pricebook Entry records for Device Evaluation.',
                e
            );
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description Thrown when a PricebookEntry service operation fails.
     */
    public class PricebookEntriesServiceException extends Exception {
    }
}