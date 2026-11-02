/**
 * @author Akash Dahinde PWC
 * GC-3194
 * @date 07-23-2026
 *
 * @description
 * Provides banner state and dismiss handling
 * for the Opportunity OLI pricing banner LWC.
 *
 * Warning Scenario:
 * Deleted_Opportunity_Product__c is not blank
 * AND IsOliBannerToBeShown__c is false.
 *
 * Success Scenario:
 * IsOliBannerToBeShown__c is true.
 */
public with sharing class OpportunityOliBannerController {

    public static final String BANNER_TYPE_WARNING =
        'warning';

    public static final String BANNER_TYPE_SUCCESS =
        'success';

    public class BannerContext {

        @AuraEnabled
        public Boolean showBanner;

        @AuraEnabled
        public String bannerType;

        @AuraEnabled
        public String message;

        @AuraEnabled
        public List<String> productNames;
    }

    /**
     * Returns banner visibility, type, message
     * and affected products for an Opportunity.
     */
    @AuraEnabled(cacheable=true)
    public static BannerContext getBannerContext(
        Id opportunityId
    ) {
        try {
            BannerContext context =
                new BannerContext();

            context.showBanner = false;
            context.productNames =
                new List<String>();

            if (opportunityId == null) {
                return context;
            }

            Opportunity opportunityObj = [
                SELECT
                    Id,
                    IsOliBannerToBeShown__c,
                    Deleted_Opportunity_Product__c
                FROM Opportunity
                WHERE Id = :opportunityId
                LIMIT 1
            ];

            Boolean showOliBanner =
                opportunityObj
                    .IsOliBannerToBeShown__c == true;

            String deletedProducts =
                opportunityObj
                    .Deleted_Opportunity_Product__c;

            /*
             * Success banner gets priority.
             */
            if (showOliBanner) {
                context.showBanner = true;

                context.bannerType =
                    BANNER_TYPE_SUCCESS;

                context.message =
                    buildSuccessMessage();

                return context;
            }

            /*
             * Warning banner.
             */
            if (String.isNotBlank(deletedProducts)) {
                context.showBanner = true;

                context.bannerType =
                    BANNER_TYPE_WARNING;

                context.message =
                    buildWarningMessage();

                context.productNames =
                    parseProductNames(
                        deletedProducts
                    );

                return context;
            }

            return context;

        } catch (Exception e) {
            ErrorLogger.logException(
                e,
                'OpportunityOliBannerController',
                'getBannerContext'
            );

            throw new AuraHandledException(
                'Unable to load the opportunity product banner.'
            );
        }
    }

    /**
     * Clears banner values after user selects Dismiss.
     */
    @AuraEnabled
    public static void dismissBanner(
        Id opportunityId
    ) {
        try {
            if (opportunityId == null) {
                return;
            }

            update new Opportunity(
                Id = opportunityId,
                IsOliBannerToBeShown__c = false,
                Deleted_Opportunity_Product__c = ''
            );

        } catch (Exception e) {
            ErrorLogger.logException(
                e,
                'OpportunityOliBannerController',
                'dismissBanner'
            );

            throw new AuraHandledException(
                'Unable to dismiss the opportunity product banner.'
            );
        }
    }

    @TestVisible
    private static String buildWarningMessage() {
        return System.Label.OLI_Banner_Warning_Message;
    }

    @TestVisible
    private static String buildSuccessMessage() {
        return System.Label.OLI_Banner_Success_Message;
    }

    /**
     * Parses product names stored using braces.
     *
     * Supported example:
     *
     * {Product A, Test-1} {Product B: ABC / XYZ}
     *
     * Product separation is based ONLY on { }.
     */
    @TestVisible
    private static List<String> parseProductNames(
        String deletedProducts
    ) {
        List<String> productNames =
            new List<String>();

        if (String.isBlank(deletedProducts)) {
            return productNames;
        }

        Pattern productPattern =
            Pattern.compile(
                '\\{([^{}]+)\\}'
            );

        Matcher productMatcher =
            productPattern.matcher(
                deletedProducts
            );

        while (productMatcher.find()) {

            String productName =
                productMatcher.group(1);

            if (String.isNotBlank(productName)) {
                productNames.add(
                    productName.trim()
                );
            }
        }

        return productNames;
    }
}