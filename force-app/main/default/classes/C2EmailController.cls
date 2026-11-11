/**
 * @author PSL
 * @date 12-05-2025
 * @description Controller class for handling C2 email related functionality
 */
public with sharing class C2EmailController {
    public String caseId { get; set; }

    /**
     * @description Gets the account manager, capacity service line, and sales rep for a case
     * @param caseId The ID of the case to retrieve information for
     * @return String containing the account manager, capacity service line, and sales rep information
     */
    public String getAccountManagerCapSerLineSalesRep() {
        if (String.isNotBlank(caseId)) {
            return EmailControllerHelper.getAccountManagerCapSerLineSalesRep(caseId);
        }
        return '';
    }
    
    /**
     * @description Gets the receiving and install case contacts
     * @param caseId The ID of the case to retrieve contacts for
     * @return List of CaseContactRole records
     */
    public List<CaseContactRole> getCaseContactRoles() {
        if (String.isNotBlank(caseId)) {
            return EmailControllerHelper.getReceivingAndInstallContacts(caseId);
        }
        return new List<CaseContactRole>();
    }
    
    /**
     * @description Checks if there are GI reprocessing orders for a case
     * @param caseId The ID of the case to check
     * @return Boolean indicating if there are GI reprocessing orders
     */
    public boolean getGiReprocessingOrders() {
        if (String.isNotBlank(caseId)) {
            return EmailControllerHelper.getGiReprocessingOrders(caseId);
        }
        return False;
    }
    
    /**
     * @description Gets all active holds for a case
     * @param caseId The ID of the case to retrieve holds for
     * @return String containing active holds information
     */
     public string getActiveHolds() {
        if (String.isNotBlank(caseId)) {
            return EmailControllerHelper.activeHolds(caseId);
        }
        return '';
    }
    
    
    /**
     * @description Checks if there is any active planning hold for a case
     * @param caseId The ID of the case to check
     * @return String 'Yes' if there is an active planning hold, 'No' otherwise
     */
     public string getIsPlannigHold() {
        if (String.isNotBlank(caseId)) {
            if(EmailControllerHelper.isPlannigHold(caseId)){
                 return 'Yes';
            }
           
        }
        return 'No';
    }
    
    /**
     * @description Gets planning hold details for a case
     * @param caseId The ID of the case to retrieve planning hold details for
     * @return String containing planning hold details
     */
    public string getPlanningHoldDetails() {
        if (String.isNotBlank(caseId)) {
            return EmailControllerHelper.planningHoldDetails(caseId);
           
        }
        return '';
    }
    
    /**
     * @description Gets the BL user for signature
     * @param caseId The ID of the case to retrieve BL user for
     * @return String containing the BL user information
     */
      public string getBlUser() {
        if (String.isNotBlank(caseId)) {
            return EmailControllerHelper.getRegionalSalesCoOrdinatorBlUser(caseId,true);
           
        }
        return '';
    }
    
    /**
     * @description Checks if service line is present for a case
     * @param caseId The ID of the case to check
     * @return Boolean indicating if service line is present
     */
    public boolean getisServiceLine() {
        if (String.isNotBlank(caseId)) {
            return EmailControllerHelper.isServiceLine(caseId);
           
        }
        return false;
    }
    
    
    /**
     * @description Gets the install contact for a case
     * @param caseId The ID of the case to retrieve install contact for
     * @return String containing the install contact information
     */
    public string getinstallContact() {
        if (String.isNotBlank(caseId)) {
            return EmailControllerHelper.installContact(caseId);
           
        }
        return '';
    }
    
    public String getC2OrderPreparationBanner() {
            // Use the CMDT DeveloperName (no spaces), e.g., 'COAFrench'
            String devName = 'OrderPreparationbanner' ;
            return EmailControllerHelper.bannerLoader(devName);
        }
    
    /**
     * @description Returns the email signature for the current running user or context.
     * @return String HTML/text signature block
     */
	public string getEmailSignature(){
        return EmailControllerHelper.emailSignature(caseId);
    }

	private List<LineItem> shippingLineItems;
    private List<LineItem> openLineItems;
    
    // Equipment Shipping table data
    /**
     * @description Returns equipment shipping line items mapped for VF rendering.
     * @param caseId Controller property used to identify the Case
     * @return List<LineItem> Shipping line items
     */
    public List<LineItem> getShippingLineItems() {
        if (shippingLineItems == null) {
            shippingLineItems = new List<LineItem>();
            if (caseId != null) {
                List<OrderItem> ship = EmailControllerHelper.equipmentScheduleDetails(caseId);
                shippingLineItems = mapOrderItems(ship);
            }
        }
        return shippingLineItems;
    }
    
    // Equipment Shipping table data
    /**
     * @description Returns equipment shipping line items mapped for VF rendering.
     * @param caseId Controller property used to identify the Case
     * @return List<LineItem> open line items
     */
    public List<LineItem> getOpenLineItems() {
        if (openLineItems == null) {
            openLineItems = new List<LineItem>();
            if (caseId != null) {
                List<OrderItem> ship = EmailControllerHelper.equipmentScheduleDetail(caseId);
                openLineItems = mapOrderItems(ship);
            }
        }
        return openLineItems;
    }
    
    /**
     * @description Maps OrderItem records to LineItem view-models for VF display.
     * @param raw List<OrderItem> Raw order items to transform
     * @return List<LineItem> Transformed view-model list
     */
	private List<LineItem> mapOrderItems(List<OrderItem> raw) {
        List<LineItem> mapped = new List<LineItem>();
        for (OrderItem oi : raw) {
            String itemNumber = (oi.Product2 != null) ? oi.Product2.ProductCode : null;
            String lineNumber = (oi.LineNumber__c != null) ? String.valueOf(oi.LineNumber__c) : null;
            String descr      = (oi.Product2 != null) ? oi.Product2.Description : null;
            Decimal qty       = oi.Quantity;
            Date shipDate     = oi.ScheduledDate__c;
            String street = oi.ShipToAddressID__r.Street;
            String city = oi.ShipToAddressID__r.City;
            String state = oi.ShipToAddressID__r.State;
            String postalCode = oi.ShipToAddressID__r.PostalCode;
            String country = oi.ShipToAddressID__r.Country;
            mapped.add(new LineItem(itemNumber, lineNumber, descr, qty, shipDate, street, city, state, postalCode, country));
        }
        return mapped;
    }
    
    public class LineItem {
        public String itemNumber { get; private set; }
        public String lineNumber { get; private set; }
        public String itemDescription { get; private set; }
        public Decimal qty { get; private set; }
        public Date shipDate { get; private set; }
        public String street { get; private set; }
        public String city { get; private set; }
        public String state { get; private set; }
        public String postalCode { get; private set; }
        public String country { get; private set; }

        public LineItem(String itemNumber, String lineNumber, String itemDescription, Decimal qty, Date shipDateString, String street, String city, String state, String postalCode, String country) {
            this.itemNumber = itemNumber;
            this.lineNumber = lineNumber;
            this.itemDescription = itemDescription;
            this.qty = qty;
            this.shipDate = shipDateString;
            this.street = street;
            this.city = city;
            this.state = state;
            this.postalCode = postalCode;
            this.country = country;
        }
    }

    /**
     * @description Calculates First Scheduled ship date based on product line and lead-time rules.
     * @param caseId Controller property used to identify the Case
     * @return DateTime Calculated Scheduled ship date
     */
    public dateTime getFirstScheduledShipDate(){
        return EmailControllerHelper.calculateScheduledShipDate(caseId, true);
    }

    /**
     * @description Calculates Last Scheduled ship date based on product line and lead-time rules.
     * @param caseId Controller property used to identify the Case
     * @return DateTime Calculated Scheduled ship date
     */
    public dateTime getLastScheduledShipDate(){
        return EmailControllerHelper.calculateScheduledShipDate(caseId, false);
    }
    
    /**
     * @description Calculates First non pre-install schedule date.
     * @param caseId Controller property used to identify the Case
     * @return DateTime Calculated Scheduled ship date
     */
    public dateTime getNonPreInstallScheduleDate() {
        return EmailControllerHelper.firstNonPreInstallScheduleDate(caseId);
    }
    
}