/**
 * @author PWC Developer
 * @date 2026/07/08
 *
 * @group Generate Quote
 *
 * @description Outbound Refresh Quote request DTO for Boomi / Sales Connection integration.
 */
public with sharing class RefreshQuoteRequest {
    public String opportunitySfId;
    public String sourceSystem;
    public String classCode;

    private static final String DEFAULT_SOURCE_SYSTEM = 'GlobalSF';
    private static final String DEFAULT_CLASS_CODE = 'HC';

    /**
     * @description Builds a refresh quote request for an Opportunity.
     * @param opportunityId Salesforce Opportunity Id.
     * @return Refresh quote request payload.
     */
    public static RefreshQuoteRequest fromOpportunityId(Id opportunityId) {
        RefreshQuoteRequest requestBody = new RefreshQuoteRequest();
        requestBody.opportunitySfId = String.valueOf(opportunityId);
        requestBody.sourceSystem = DEFAULT_SOURCE_SYSTEM;
        requestBody.classCode = DEFAULT_CLASS_CODE;
        return requestBody;
    }

    /**
     * @description Serializes the request using integration field names.
     * @return Map ready for JSON serialization.
     */
    public Map<String, Object> toJsonMap() {
        return new Map<String, Object>{
            'opportunitySfId' => opportunitySfId,
            'sourceSystem' => sourceSystem,
            'classCode' => classCode
        };
    }
}