/**
 * @author PSL
 * @date 01-15-2026
 * @description Controller for Ship Date Notification (SDN) emails. Provides VF-accessible getters
 *              for contact details, service/procedural flags, account manager display names,
 *              equipment and trade-in line items, email signature, and SDN banner.
 *              Delegates business logic to EmailControllerHelper.
 */
public without sharing class ShipDNEmailController {
	public id caseId { get; set; }
    
    /**
     * @description Returns receiving contact display name for the bound Case.
     * @param caseId Controller property used to identify the Case
     * @return String Display name of the receiving contact
     */
    public string getRecevingContactName(){
        return EmailControllerHelper.getReceivingContactDisplayName(caseId);
    }
    
    /**
     * @description Indicates whether the Case has at least one Procedural line.
     * @param caseId Controller property used to identify the Case
     * @return Boolean True if procedural line exists; otherwise false
     */
    public boolean getIsProcedural(){
        return EmailControllerHelper.isProcedural(caseId);
    }
    
    /**
     * @description Returns install contact name associated with the bound Case.
     * @param caseId Controller property used to identify the Case
     * @return String Name of the install contact
     */
     public string getInstallConName(){
        return EmailControllerHelper.installConName(caseId);
    }
    
    /**
     * @description Returns install contact phone associated with the bound Case.
     * @param caseId Controller property used to identify the Case
     * @return String Phone number of the install contact
     */
    public string getInstallConPhone(){
        return EmailControllerHelper.installConPhone(caseId);
    }
    
    /**
     * @description Indicates whether the Case has at least one Service line.
     * @param caseId Controller property used to identify the Case
     * @return Boolean True if service line exists; otherwise false
     */
     public boolean getIsServiceLine(){
        return EmailControllerHelper.isServiceLine(caseId);
    }
    
    /**
     * @description Returns Account Manager/Sales Rep display name for Service line.
     *              Extracts name from a "Name at email" formatted string.
     * @param caseId Controller property used to identify the Case
     * @return String Display name of the Service line Account Manager/Sales Rep
     */
     public string getAccountManagerSerLineSalesRep(){
        
        String raw = EmailControllerHelper.getAccountManagerSerLineSalesRep(caseId);
            if (String.isBlank(raw)) return '';
            // Expecting format: "Name at email"
            Integer idx = raw.indexOf(' at ');
            return (idx > -1) ? raw.left(idx) : raw; 

    }

    /**
     * @description Returns Account Manager/Sales Rep display name for Capital line.
     *              Extracts name from a "Name at email" formatted string.
     * @param caseId Controller property used to identify the Case
     * @return String Display name of the Capital line Account Manager/Sales Rep
     */
    public string getAccountManagerCapLineSalesRep(){
        
        String raw = EmailControllerHelper.getAccountManagerCapLineSalesRep(caseId);
            if (String.isBlank(raw)) return '';
            // Expecting format: "Name at email"
            Integer idx = raw.indexOf(' at ');
            return (idx > -1) ? raw.left(idx) : raw; 

    }
    
    
    /**
     * @description Indicates whether there are Trade-In order lines for the bound Case.
     * @param caseId Controller property used to identify the Case
     * @return Boolean True if trade-in lines exist; otherwise false
     */
    public Boolean getIsTradeInLine() {
        if (caseId == null) return false;
        List<OrderItem> items = EmailControllerHelper.tradeInEquipmentDetails(caseId);
        if(items.size()>0){
            return true;
        }
        return false;
    }

    /**
     * @description Calculates actual ship date based on product line and lead-time rules.
     * @param caseId Controller property used to identify the Case
     * @return DateTime Calculated actual ship date
     */
    public dateTime getcalculateActualShipDate(){
        return EmailControllerHelper.calculateActualShipDate(caseId);
    }

    
	
    
    
    public class LineItem {
            public String itemNumber { get; private set; }
            public String lineNumber { get; private set; }
            public String itemDescription { get; private set; }
            public Decimal qty { get; private set; }
            public String street { get; private set; }
            public String city { get; private set; }
            public String state { get; private set; }
            public String postalCode { get; private set; }
            public String country { get; private set; }
    
            public LineItem(String itemNumber, String lineNumber, String itemDescription, Decimal qty, String street, String city, String state, String postalCode, String country) {
                this.itemNumber = itemNumber;
                this.lineNumber = lineNumber;
                this.itemDescription = itemDescription;
                this.qty = qty;
                this.street = street;
                this.city = city;
                this.state = state;
                this.postalCode = postalCode;
                this.country = country;
            }
        }


    // Backing field for the VF <apex:repeat value="{!lineItems}">
    
	private List<LineItem> shippingLineItems;
    private List<LineItem> tradeInLineItems;


	
   
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
            String street = oi.ShipToAddressID__r.Street;
            String city = oi.ShipToAddressID__r.City;
            String state = oi.ShipToAddressID__r.State;
            String postalCode = oi.ShipToAddressID__r.PostalCode;
            String country = oi.ShipToAddressID__r.Country;
            mapped.add(new LineItem(itemNumber, lineNumber, descr, qty, street, city, state, postalCode, country));
        }
        return mapped;
    }

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
                List<OrderItem> ship = EmailControllerHelper.equipmentShippingDetails(caseId);
                shippingLineItems = mapOrderItems(ship);
            }
        }
        return shippingLineItems;
    }

    
    
    /**
     * @description Returns trade-in equipment line items mapped for VF rendering.
     * @param caseId Controller property used to identify the Case
     * @return List<LineItem> Trade-in line items
     */
	public List<LineItem> getTradeInLineItems() {
        if (tradeInLineItems == null) {
            tradeInLineItems = new List<LineItem>();
            if (caseId != null) {
                List<OrderItem> trade = EmailControllerHelper.tradeInEquipmentDetails(caseId);
                tradeInLineItems = mapOrderItems(trade);            
            }
        }
        return tradeInLineItems;
    }
    
    
    /**
     * @description Returns the email signature for the current running user or context.
     * @return String HTML/text signature block
     */
	public string getEmailSignature(){
        return EmailControllerHelper.emailSignature(caseId);
    }
    
    /**
     * @description Retrieves SDN banner using CMDT DeveloperName.
     * @param none Uses fixed CMDT DeveloperName 'ShipmentBanner'
     * @return String Banner URL or HTML content
     */
    public String getBannerUrlSDN() {
            // Use the CMDT DeveloperName (no spaces), e.g., 'COAFrench'
            String devName = 'ShipmentBanner' ;
            return EmailControllerHelper.bannerLoader(devName);
        }

        /**
         * @description Retrieves Shipping Instructions from Order related to the given Case.
         * @param caseId Case Id used to locate the related Order
         * @return String ShippingInstructions__c value or empty string if not found
         */
                   
        public String getShippingInstructions() {
            try {
                Order ord = [
                    SELECT ShippingInstructions__c
                    FROM Order
                    WHERE parentCase__c = :caseId
                    LIMIT 1
                ];
        
                if (ord != null &&
                    !String.isBlank(ord.ShippingInstructions__c)
                ) {
                    return ord.ShippingInstructions__c;
                }
        
               
                return '';
            } catch (Exception ex) {
                ErrorLogger.logException(
                    ex,
                    'ShipDNEmailController',
                    'getShippingInstructions'
                );
                throw ex;
            }
        }
   
}