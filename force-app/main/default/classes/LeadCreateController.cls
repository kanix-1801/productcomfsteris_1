/**
 * @description Creates a Lead, then starts routing after the record exists.
 *              Products are optional unless Auto Assign Lead is selected.
 * @author      Vinay
 * @date        2026-10-12
 */
public with sharing class LeadCreateController {

    /**
     * @description Product entered on the New Lead wizard.
     */
    public class ProductInput {
        @AuraEnabled public Id productId;
        @AuraEnabled public String parentCategory;
        @AuraEnabled public String productCategory;
    }

    /**
     * Product row shown in the product table on the New Lead wizard.
     */
    public class ProductOption {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String productCode;
        @AuraEnabled public String productFamily;
        @AuraEnabled public String productClassCode;
    }

    /**
     * Finds active Products for the product table. With no search text it returns the Products most
     * used on Leads, filled up with other Products that have a family. The org has tens of thousands
     * of Products, so a search needs two characters and returns the first 50 matches.
     * @param searchTerm Text typed in the product search box.
     * @return Matching Products, or an empty list when the term is a single character.
     */
    @AuraEnabled(cacheable=true)
    public static List<ProductOption> searchProducts(String searchTerm) {
        String term = searchTerm == null ? '' : searchTerm.trim();
        List<ProductOption> options = new List<ProductOption>();
        if (term.length() == 1) {
            return options;
        }
        if (String.isBlank(term)) {
            return defaultProducts();
        }
        String pattern = '%' + term + '%';
        for (Product2 productRecord : [
            SELECT Id, Name, ProductCode, ItemFamily__c, ProductClassCode__c
            FROM Product2
            WHERE IsActive = true
            AND (Name LIKE :pattern OR ProductCode LIKE :pattern OR ItemFamily__c LIKE :pattern)
            WITH USER_MODE
            ORDER BY Name
            LIMIT 50
        ]) {
            options.add(toOption(productRecord));
        }
        return options;
    }

    private static List<ProductOption> defaultProducts() {
        List<Id> popularIds = new List<Id>();
        for (AggregateResult row : [
            SELECT Product__c productId
            FROM LeadProduct__c
            WHERE Product__c != null
            WITH USER_MODE
            GROUP BY Product__c
            ORDER BY COUNT(Id) DESC
            LIMIT 50
        ]) {
            popularIds.add((Id) row.get('productId'));
        }

        Map<Id, Product2> popularProducts = new Map<Id, Product2>([
            SELECT Id, Name, ProductCode, ItemFamily__c, ProductClassCode__c
            FROM Product2
            WHERE IsActive = true
            AND Id IN :popularIds
            WITH USER_MODE
        ]);
        List<ProductOption> options = new List<ProductOption>();
        for (Id productId : popularIds) {
            if (popularProducts.containsKey(productId)) {
                options.add(toOption(popularProducts.get(productId)));
            }
        }

        Integer remaining = 50 - options.size();
        if (remaining > 0) {
            for (Product2 productRecord : [
                SELECT Id, Name, ProductCode, ItemFamily__c, ProductClassCode__c
                FROM Product2
                WHERE IsActive = true
                AND ItemFamily__c != null
                AND Id NOT IN :popularProducts.keySet()
                WITH USER_MODE
                ORDER BY Name
                LIMIT :remaining
            ]) {
                options.add(toOption(productRecord));
            }
        }
        return options;
    }

    private static ProductOption toOption(Product2 productRecord) {
        ProductOption option = new ProductOption();
        option.id = productRecord.Id;
        option.name = productRecord.Name;
        option.productCode = productRecord.ProductCode;
        option.productFamily = productRecord.ItemFamily__c;
        option.productClassCode = productRecord.ProductClassCode__c;
        return option;
    }
    /**
     * @description GC-3541 result for the custom Lead page. The standard Lead page does not use this.
     */
    public class DuplicatePreview {
        @AuraEnabled public String status;
        @AuraEnabled public String reason;
        @AuraEnabled public String message;
        @AuraEnabled public Boolean blockSave = false;
        @AuraEnabled public Boolean requiresConfirmation = false;
        @AuraEnabled public List<DuplicateMatchView> matches = new List<DuplicateMatchView>();
    }

    public class DuplicateMatchView {
        @AuraEnabled public String recordId;
        @AuraEnabled public String name;
        @AuraEnabled public String email;
        @AuraEnabled public String phone;
        @AuraEnabled public String recordType;
        @AuraEnabled public String accountId;
        @AuraEnabled public String accountName;
    }

    /**
     * @description Checks the Lead that custom page is about to save. Does not insert it.
     * @param leadRecord Lead fields from the custom page.
     * @return Whether the page should block the save or ask the user to continue.
     */
    @AuraEnabled
    public static DuplicatePreview previewLeadDuplicate(Lead leadRecord) {
        DuplicatePreview preview = new DuplicatePreview();
        if (leadRecord == null) {
            return preview;
        }
        leadRecord.Id = null;
        LeadDuplicateService.MatchResult result = LeadDuplicateService.findDuplicates(new List<Lead>{ leadRecord })[0];
        preview.status = result.status;
        preview.reason = result.reason;
        preview.message = result.buildDetail();
        preview.blockSave = result.status == LeadDuplicateService.STATUS_DEFINITIVE;
        preview.requiresConfirmation = result.status == LeadDuplicateService.STATUS_POTENTIAL
            || result.status == LeadDuplicateService.STATUS_AMBIGUOUS;
        preview.matches = toMatchViews(result.matchedRecords);
        return preview;
    }

    private static List<DuplicateMatchView> toMatchViews(List<LeadDuplicateService.MatchedRecord> rows) {
        List<DuplicateMatchView> views = new List<DuplicateMatchView>();
        if (rows == null) {
            return views;
        }
        Integer shown = Math.min(rows.size(), 25);
        for (Integer i = 0; i < shown; i++) {
            LeadDuplicateService.MatchedRecord row = rows[i];
            DuplicateMatchView view = new DuplicateMatchView();
            view.recordId = row.recordId == null ? null : String.valueOf(row.recordId);
            view.recordType = row.recordType;
            view.name = String.isBlank(row.name) ? row.recordType : row.name;
            view.email = row.email;
            view.phone = row.phone;
            view.accountId = row.accountId == null ? null : String.valueOf(row.accountId);
            view.accountName = row.company;
            views.add(view);
        }
        return views;
    }

    /**
     * @description Inserts the Lead, inserts any Products that were entered, and enqueues routing.
     *              A failure rolls the inserts back. TAS is not called in this transaction.
     * @param leadRecord Lead fields from the wizard.
     * @param productsJson JSON list of ProductInput. Empty is allowed.
     * @return Id of the new Lead.
     */
    public static Id createLeadWithProducts(Lead leadRecord, String productsJson) {
        return createLeadWithProducts(leadRecord, productsJson, false);
    }

    /**
     * @description Saves from custom page. An exact email match is blocked. A possible
     *              match is saved only after the user chooses to continue. After that check,
     *              the insert allows the standard duplicate alert so a GC-3541 no-match is not blocked.
     * @param leadRecord Lead fields from the wizard.
     * @param productsJson JSON list of ProductInput. Empty is allowed.
     * @param duplicateConfirmed True when the user chose to continue after a possible match.
     * @return Id of the new Lead.
     */
    @AuraEnabled
    public static Id createLeadWithProducts(Lead leadRecord, String productsJson, Boolean duplicateConfirmed) {
        if (leadRecord == null) {
            raise(System.Label.LeadCreateFailedMessage);
        }
        List<ProductInput> products = String.isBlank(productsJson)
            ? new List<ProductInput>()
            : (List<ProductInput>) JSON.deserialize(productsJson, List<ProductInput>.class);
        List<LeadProduct__c> productRows = new List<LeadProduct__c>();
        if (products != null) {
            for (ProductInput input : products) {
                if (input == null || input.productId == null) {
                    continue;
                }
                productRows.add(new LeadProduct__c(
                    Product__c = input.productId,
                    ParentCategory__c = input.parentCategory,
                    ProductCategory__c = input.productCategory
                ));
            }
        }

        if (leadRecord.Auto_Assign_Lead__c && productRows.isEmpty()) {
            raise(System.Label.LeadAutoAssignNoProductMessage);
        }

        leadRecord.Id = null;
        leadRecord.OwnerId = UserInfo.getUserId();
        enforceCustomPageDuplicate(leadRecord, duplicateConfirmed);

        Savepoint savepoint = Database.setSavepoint();
        try {
            LeadService.skipInsertTas = true;
            Database.DMLOptions options = new Database.DMLOptions();
            options.DuplicateRuleHeader.allowSave = true;
            Database.insert(leadRecord, options);

            if (!productRows.isEmpty()) {
                for (LeadProduct__c productRow : productRows) {
                    productRow.Lead__c = leadRecord.Id;
                }
                insert productRows;
            }

            if (leadRecord.HubSpot_Lead__c || LeadAutoAssignService.isEligible(leadRecord)) {
                System.enqueueJob(new LeadRoutingQueueable(leadRecord.Id));
            }
            return leadRecord.Id;
        } catch (Exception ex) {
            Database.rollback(savepoint);
            String message = ex instanceof DmlException
                ? ((DmlException) ex).getDmlMessage(0)
                : ex.getMessage();
            raise(String.isBlank(message) ? System.Label.LeadCreateFailedMessage : message);
            return null;
        }
    }

    private static void enforceCustomPageDuplicate(Lead leadRecord, Boolean duplicateConfirmed) {
        LeadDuplicateService.MatchResult result = LeadDuplicateService.findDuplicates(new List<Lead>{ leadRecord })[0];
        if (result.status == LeadDuplicateService.STATUS_DEFINITIVE) {
            raise(result.buildDetail());
        }
        Boolean reviewMatch = result.status == LeadDuplicateService.STATUS_POTENTIAL
            || result.status == LeadDuplicateService.STATUS_AMBIGUOUS;
        if (reviewMatch && duplicateConfirmed != true) {
            raise(result.buildDetail());
        }
    }

    private static void raise(String message) {
        AuraHandledException ex = new AuraHandledException(message);
        ex.setMessage(message);
        throw ex;
    }
}