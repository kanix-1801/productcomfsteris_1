/**
 * @author PSL
 * @date 01-15-2026
 * @description Controller for Go No Go emails. Provides VF-accessible getters
 *              for contact details, service/procedural flags, account manager display names,
 *              equipment and trade-in line items, email signature, and Go No Go banner.
 *              Delegates business logic to EmailControllerHelper.
 */

public without sharing class GoNoGoEmailController {
    public id caseId { get; set; }
    
    public String getBannerUrlGoNoGo() {
            // Use the CMDT DeveloperName (no spaces), e.g., 'COAFrench'
            String devName = 'OrderPreparationbanner' ;
            return EmailControllerHelper.bannerLoader(devName);
        }
    
    
    public String getReplyUrlGoNoGo() {
            // Use the CMDT DeveloperName (no spaces), e.g., 'COAFrench'
            String devName = 'TextToReply' ;
            return EmailControllerHelper.bannerLoader(devName);
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
     * @description Returns the email signature for the current running user or context.
     * @return String HTML/text signature block
     */
	public string getEmailSignature(){
        return EmailControllerHelper.emailSignature(caseId);
    }
    
    /**
     * @description Returns the email breakpoint for the GoNoGo.
     * @return String breakpoint
     */
	public string getEmailBreakpoint(){
        return System.Label.EmailBreakPoint;
    }

     /**
     * @description Returns the email breakpoint for the GoNoGo end line.
     * @return String breakpoint 
     */
	public string getEmailBreakpointEndLine(){
        return System.Label.CBMGoNoGoEmailEnd;
    }
    
	private List<LineItem> shippingLineItems;

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
            this.shipDate = shipDate;
            this.street = street;
            this.city = city;
            this.state = state;
            this.postalCode = postalCode;
            this.country = country;
        }
    }

}