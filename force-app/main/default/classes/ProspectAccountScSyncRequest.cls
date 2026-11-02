/**
 * @description GC-3441 / GC-3500 - Outbound payload DTO for Prospect Account
 *              sync to Sales Connection via Boomi.
 */
public with sharing class ProspectAccountScSyncRequest {
    public String accountId { get; private set; }
    public String accountName { get; private set; }
    public String priceListId { get; private set; }
    public String orgId { get; private set; }
    public String billingStreet { get; private set; }
    public String billingCity { get; private set; }
    public String billingState { get; private set; }
    public String billingPostalCode { get; private set; }
    public String billingCountry { get; private set; }
    public String customerClassCode { get; private set; }
    public String modifiedBy { get; private set; }
    public String modifiedDate { get; private set; }
    public String createdBy { get; private set; }
    public String createdDate { get; private set; }

    public static ProspectAccountScSyncRequest create(
        String accountId,
        String accountName,
        String priceListId,
        String orgId,
        String billingStreet,
        String billingCity,
        String billingState,
        String billingPostalCode,
        String billingCountry,
        String customerClassCode,
        String modifiedBy,
        String modifiedDate,
        String createdBy,
        String createdDate
    ) {
        ProspectAccountScSyncRequest request = new ProspectAccountScSyncRequest();
        request.accountId = accountId;
        request.accountName = accountName;
        request.priceListId = priceListId;
        request.orgId = orgId;
        request.billingStreet = billingStreet;
        request.billingCity = billingCity;
        request.billingState = billingState;
        request.billingPostalCode = billingPostalCode;
        request.billingCountry = billingCountry;
        request.customerClassCode = customerClassCode;
        request.modifiedBy = modifiedBy;
        request.modifiedDate = modifiedDate;
        request.createdBy = createdBy;
        request.createdDate = createdDate;
        return request;
    }

    /**
     * @description Serializes the payload with the agreed JSON keys.
     */
    public Map<String, Object> toJsonMap() {
        return new Map<String, Object>{
            'accountId' => accountId,
            'accountName' => accountName,
            'priceListId' => priceListId,
            'orgId' => orgId,
            'billingAddressLine1' => billingStreet,
            'billingCity' => billingCity,
            'billingState' => billingState,
            'billingPostalCode' => billingPostalCode,
            'billingCountry' => billingCountry,
            'customerClassCode' => customerClassCode,
            'modifiedBy' => modifiedBy,
            'modifiedDate' => modifiedDate,
            'createdBy' => createdBy,
            'createdDate' => createdDate
        };
    }
}