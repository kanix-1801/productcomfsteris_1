/**
 * @author PSL
 * @date 11-26-2025
 * @description Controller class for SOA email related functionality
 */
public with sharing class SOAEmailController {


    public String orderId { get; set; }
    Public class SOAException extends Exception{}
        @testVisible
    private void throwIfTestException(){
        if(Test.isRunningTest() && 'FORCE_EXCEPTION'.equals(orderID)){
            throw new SOAException('Forced Exception for Unit Test');
        }
    }
    
   
    
    
    /**
     * @description Gets account manager names for capital line orders
     * @return String of account manager names separated by '/'
     */
    public string getAccountManagerNames(){
        try {
    
            Set<String> AMStr = new Set<String>();

            
            for (OrderLineContact__c olc : [
                SELECT SalesRep__r.Name,SalesRep__r.FirstName  
                FROM OrderLineContact__c  
                WHERE OrderLine__r.OrderId = :orderId 
                AND OrderLine__r.CreateSubcase__c = 'yes - Capital line'
            ]) {
                AMStr.add(olc.SalesRep__r.FirstName );
            }

            
            String AMString = String.join(new List<String>(AMStr), '/');
      
            throwIfTestException();
        return AMString;
            
            
        } catch (Exception ex) {
            ErrorLogger.logException(ex, 'SOAEmailController', 'getAccountManagerNames');
            throw ex;
        }
    }

    /**
     * @description Gets the earliest required ship date for capital line orders
     * @return string of soonest request date
     */
    public string getCapLineReqShipDate(){
        try {                        
        
            List<OrderItem> orderItems = [
                SELECT RequestDate__c
                FROM OrderItem
                WHERE OrderId = :orderId 
                AND CreateSubcase__c = 'yes - Capital line'
                AND Subcase__r.PreInstallItem__c = false
                AND Active__c = true
                ORDER BY RequestDate__c ASC
            ];

            
            String soonestDate = '';
            for (OrderItem oi : orderItems) {
                if (oi.RequestDate__c != null) {
                    soonestDate = DateTime.newInstance(oi.RequestDate__c.year(), oi.RequestDate__c.month(), oi.RequestDate__c.day()).format('MM/dd/yyyy');
                    break;
                }
            }
            
            throwIfTestException();
            return soonestDate;
        } catch (Exception ex) {
            ErrorLogger.logException(ex, 'SOAEmailController', 'getCapLineReqShipDate');
            throw ex;
        }

    }

            
    /**
     * @description Checks if there are GI Reprocessing orders
     * @return True if GI Reprocessing orders exist, false otherwise
     */
    public Boolean getGiReprocessingOrders() {
        try {
            List<OrderItem> items = [
                SELECT Id
                FROM OrderItem
                WHERE OrderId = :orderId
                AND Warehouse__c = 'DRO'
                AND OrderLineType__c = 'GI Reprocessing'
                LIMIT 1
            ];
			 throwIfTestException();
            return !items.isEmpty();
        } catch (Exception ex) {
            ErrorLogger.logException(ex, 'SOAEmailController', 'getGiReprocessingOrders');
            throw ex;
        }
        }

         

    /**
     * @description Gets the list of reason codes for orders
     * @return List of ReasonWrapper objects
     */
    public List<ReasonWrapper> getReasonCodeList() {
    try {
    List<ReasonWrapper> reasonList = new List<ReasonWrapper>();
    for (OrderAndOrderLineHold__c hold : [
        SELECT  toLabel(ReasonCode__c), ReasonDescription__c
        FROM OrderAndOrderLineHold__c
        WHERE Order__C = :orderId
        AND  IncludeInSOAMail__c = true
        AND Active__C = true
    ]) {
        reasonList.add(new ReasonWrapper(hold.ReasonCode__c, hold.ReasonDescription__c));
    }
         throwIfTestException();
    return reasonList;
    } catch (Exception ex) {
        ErrorLogger.logException(ex, 'SOAEmailController', 'getReasonCodeList');
        throw ex;
    }
}

public class ReasonWrapper {
    public String reasonCode { get; set; }
    public String reasonDescription { get; set; }
    public ReasonWrapper(String code, String desc1) {
        this.reasonCode = code;
        this.reasonDescription = desc1;
    }
}


    /**
     * @description Checks if there is a service line sales rep for the order
     * @return True if no service line sales rep found, false otherwise
     */
    public Boolean getServiceLineSalesRep() {
        try {

           list<OrderLineContact__c> olConList= [SELECT SalesRep__c
                FROM OrderLineContact__c  
                WHERE  OrderLine__r.OrderId = :orderId and OrderLine__r.CreateSubcase__c = 'yes - Service Installation' and SalesRep__c !=null];
				 throwIfTestException();
                return olConList.isEmpty();
        } catch (Exception ex) {
            ErrorLogger.logException(ex, 'SOAEmailController', 'getServiceLineSalesRep');
            throw ex;
        }

    }
        
    public String getBannerUrlSOA() {
            // Use the CMDT DeveloperName (no spaces), e.g., 'COAFrench'
            String devName = 'AcknowldgementBanner' ;
            return EmailControllerHelper.bannerLoader(devName);
        }
        
    public String getBannerUrlNoChargeSOA() {
            // Use the CMDT DeveloperName (no spaces), e.g., 'COAFrench'
            String devName = 'NoChargeSOABanner' ;
            return EmailControllerHelper.bannerLoader(devName);
        }
       
}