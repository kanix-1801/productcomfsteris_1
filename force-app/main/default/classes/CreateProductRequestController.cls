/**
 * @description Aura entry point for the mobile Create Product Request screen.
 */
public with sharing class CreateProductRequestController {
    /**
     * @description Loads the screen context for a Work Order or a standalone replenishment.
     * @param workOrderId Work Order Id. Blank for a standalone request.
     * @param userId Running user. Blank uses the current user.
     * @return Screen context.
     * @throws AuraHandledException when the context cannot be loaded.
     * @example
     * CreateProductRequestController.getContext(workOrderId, userId);
     */
    @AuraEnabled(cacheable=true)
    public static CreateProductRequestService.ContextResult getContext(Id workOrderId, Id userId) {
        try {
            return CreateProductRequestService.getContext(workOrderId, userId);
        } catch (Exception e) {
            throw auraException(e);
        }
    }

    /**
     * @description Loads technician addresses after the Service Resource changes.
     * @param serviceResourceId Selected Service Resource.
     * @param userId Running user. Blank uses the current user.
     * @param workOrderId Work Order Id when the resource comes from that Work Order. Blank for replenishment.
     * @return Address choices for that resource.
     * @throws AuraHandledException when the addresses cannot be loaded.
     * @example
     * CreateProductRequestController.getAddresses(serviceResourceId, userId, workOrderId);
     */
    @AuraEnabled(cacheable=true)
    public static CreateProductRequestService.AddressResult getAddresses(
        Id serviceResourceId,
        Id userId,
        Id workOrderId
    ) {
        try {
            return CreateProductRequestService.getAddresses(serviceResourceId, userId, workOrderId);
        } catch (Exception e) {
            throw auraException(e);
        }
    }

    /**
     * @description Searches active Part products by name or product code.
     * @param searchTerm Text or number entered by the technician.
     * @return Matching parts.
     * @throws AuraHandledException when the search fails.
     * @example
     * CreateProductRequestController.searchParts('PC-4471');
     */
    @AuraEnabled(cacheable=true)
    public static List<CreateProductRequestService.PartRow> searchParts(String searchTerm) {
        try {
            return CreateProductRequestService.searchParts(searchTerm);
        } catch (Exception e) {
            throw auraException(e);
        }
    }

    /**
     * @description Creates the Draft Product Request and its lines.
     * @param request Values entered on the screen.
     * @return The new Product Request Id and number.
     * @throws AuraHandledException when the request cannot be saved.
     * @example
     * CreateProductRequestController.createProductRequest(request);
     */
    @AuraEnabled
    public static CreateProductRequestService.CreateResult createProductRequest(
        CreateProductRequestService.CreateRequest request
    ) {
        try {
            return CreateProductRequestService.createRequest(request);
        } catch (Exception e) {
            throw auraException(e);
        }
    }

    /**
     * @description Creates the Draft Product Request from the JSON posted by the mobile screen.
     * @param requestJson Screen values, including each part and quantity.
     * @return The new Product Request Id and number.
     * @throws AuraHandledException when the request cannot be saved.
     * @example
     * CreateProductRequestController.createProductRequestFromJson(requestJson);
     */
    @AuraEnabled
    public static CreateProductRequestService.CreateResult createProductRequestFromJson(String requestJson) {
        try {
            return CreateProductRequestService.createRequest(requestJson);
        } catch (Exception e) {
            throw auraException(e);
        }
    }

    /**
     * @description Marks the new Product Request to be submitted to Oracle.
     * @param productRequestId Product Request created by this screen.
     * @throws AuraHandledException when the update fails.
     * @example
     * CreateProductRequestController.submitProductRequest(productRequestId);
     */
    @AuraEnabled
    public static void submitProductRequest(Id productRequestId) {
        try {
            CreateProductRequestService.submitToErp(productRequestId);
        } catch (Exception e) {
            throw auraException(e);
        }
    }

    /**
     * @description Loads Oracle eligibility and the prior integration result.
     * @param productRequestId Product Request created by this screen.
     * @return Whether the confirm screen can offer Submit Create.
     * @throws AuraHandledException when the Product Request cannot be read.
     * @example
     * CreateProductRequestController.getOracleSubmitPreview(productRequestId);
     */
    @AuraEnabled
    public static CreateProductRequestService.OracleSubmitPreview getOracleSubmitPreview(Id productRequestId) {
        try {
            return CreateProductRequestService.getOracleSubmitPreview(productRequestId);
        } catch (Exception e) {
            throw auraException(e);
        }
    }

    private static AuraHandledException auraException(Exception e) {
        String message = e instanceof CreateProductRequestException
            ? e.getMessage()
            : Label.CreateProductRequest_Unexpected;
        AuraHandledException auraError = new AuraHandledException(message);
        auraError.setMessage(message);
        return auraError;
    }
}