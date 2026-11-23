/**
 * @author PSL
 * @date 01-15-2026
 * @description Controller for Ship Date Notification (SDN) emails. Provides VF-accessible getters
 *              for contact details, service/procedural flags, account manager display names,
 *              equipment and trade-in line items, email signature, and SDN banner.
 *              Delegates business logic to EmailControllerHelper.
 */
public without sharing class ShipDNEmailController {

    public Id caseId { get; set; }

    /**
     * @description Returns receiving contact display name for the bound Case.
     * @return String Display name of the receiving contact.
     */
    public String getRecevingContactName() {
        return EmailControllerHelper.getReceivingContactDisplayName(caseId);
    }

    /**
     * @description Indicates whether the Case has at least one Procedural line.
     * @return Boolean True if a procedural line exists; otherwise false.
     */
    public Boolean getIsProcedural() {
        return EmailControllerHelper.isProcedural(caseId);
    }

    /**
     * @description Returns install contact name associated with the bound Case.
     * @return String Name of the install contact.
     */
    public String getInstallConName() {
        return EmailControllerHelper.installConName(caseId);
    }

    /**
     * @description Returns install contact phone associated with the bound Case.
     * @return String Phone number of the install contact.
     */
    public String getInstallConPhone() {
        return EmailControllerHelper.installConPhone(caseId);
    }

    /**
     * @description Indicates whether the Case has at least one Service line.
     * @return Boolean True if a service line exists; otherwise false.
     */
    public Boolean getIsServiceLine() {
        return EmailControllerHelper.isServiceLine(caseId);
    }

    /**
     * @description Returns Account Manager/Sales Rep display name for Service line.
     *              Extracts the name from a "Name at email" formatted string.
     * @return String Display name of the Service line Account Manager/Sales Rep.
     */
    public String getAccountManagerSerLineSalesRep() {
        String raw =
            EmailControllerHelper.getAccountManagerSerLineSalesRep(caseId);

        if (String.isBlank(raw)) {
            return '';
        }

        Integer indexOfEmailSeparator = raw.indexOf(' at ');

        return indexOfEmailSeparator > -1
            ? raw.left(indexOfEmailSeparator)
            : raw;
    }

    /**
     * @description Returns Account Manager/Sales Rep display name for Capital line.
     *              Extracts the name from a "Name at email" formatted string.
     * @return String Display name of the Capital line Account Manager/Sales Rep.
     */
    public String getAccountManagerCapLineSalesRep() {
        String raw =
            EmailControllerHelper.getAccountManagerCapLineSalesRep(caseId);

        if (String.isBlank(raw)) {
            return '';
        }

        Integer indexOfEmailSeparator = raw.indexOf(' at ');

        return indexOfEmailSeparator > -1
            ? raw.left(indexOfEmailSeparator)
            : raw;
    }

    /**
     * @description Indicates whether there are Trade-In order lines for the bound Case.
     * @return Boolean True if Trade-In lines exist; otherwise false.
     */
    public Boolean getIsTradeInLine() {
        if (caseId == null) {
            return false;
        }

        List<OrderItem> items =
            EmailControllerHelper.tradeInEquipmentDetails(caseId);

        return !items.isEmpty();
    }

    /**
     * @description Calculates actual ship date based on product line and lead-time rules.
     * @return Datetime Calculated actual ship date.
     */
    public Datetime getcalculateActualShipDate() {
        return EmailControllerHelper.calculateActualShipDate(caseId);
    }

    /**
     * @description View model used by Visualforce email components.
     */
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
        public Decimal extendedPrice { get; private set; }

        /**
         * @description Existing constructor used by SDN and existing Trade-In emails.
         */
        public LineItem(
            String itemNumber,
            String lineNumber,
            String itemDescription,
            Decimal qty,
            String street,
            String city,
            String state,
            String postalCode,
            String country
        ) {
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

        /**
         * @description CBM-1416: Creates a cancelled Trade-In line item
         *              containing the values required by the cancellation email.
         * @param lineNumber Trade-In Order Line number.
         * @param itemDescription Trade-In item description.
         * @param extendedPrice Trade-In extended line price.
         */
        public LineItem(
            String lineNumber,
            String itemDescription,
            Decimal extendedPrice
        ) {
            this.lineNumber = lineNumber;
            this.itemDescription = itemDescription;
            this.extendedPrice = extendedPrice;
        }
    }

    // Backing fields for Visualforce email components.
    private List<LineItem> shippingLineItems;
    private List<LineItem> tradeInLineItems;
    private List<LineItem> closedTradeInLineItems;

    // CBM-1416: Cancelled Trade-In lines.
    private List<LineItem> cancellationTradeInLineItems;

    /**
     * @description Maps OrderItem records to LineItem view-models for VF display.
     * @param raw Raw Order Items to transform.
     * @return List<LineItem> Transformed view-model list.
     */
    private List<LineItem> mapOrderItems(List<OrderItem> raw) {
        List<LineItem> mapped = new List<LineItem>();

        for (OrderItem orderItemRecord : raw) {
            String itemNumber =
                orderItemRecord.Product2 != null
                ? orderItemRecord.Product2.ProductCode
                : null;

            String lineNumber =
                orderItemRecord.LineNumber__c != null
                ? String.valueOf(orderItemRecord.LineNumber__c)
                : null;

            String itemDescription =
                orderItemRecord.Product2 != null
                ? orderItemRecord.Product2.Description
                : null;

            Decimal quantity = orderItemRecord.Quantity;

            String street =
                orderItemRecord.ShipToAddressID__r != null
                ? orderItemRecord.ShipToAddressID__r.Street
                : null;

            String city =
                orderItemRecord.ShipToAddressID__r != null
                ? orderItemRecord.ShipToAddressID__r.City
                : null;

            String state =
                orderItemRecord.ShipToAddressID__r != null
                ? orderItemRecord.ShipToAddressID__r.State
                : null;

            String postalCode =
                orderItemRecord.ShipToAddressID__r != null
                ? orderItemRecord.ShipToAddressID__r.PostalCode
                : null;

            String country =
                orderItemRecord.ShipToAddressID__r != null
                ? orderItemRecord.ShipToAddressID__r.Country
                : null;

            mapped.add(
                new LineItem(
                    itemNumber,
                    lineNumber,
                    itemDescription,
                    quantity,
                    street,
                    city,
                    state,
                    postalCode,
                    country
                )
            );
        }

        return mapped;
    }

    /**
     * @description Returns equipment shipping line items mapped for VF rendering.
     * @return List<LineItem> Shipping line items.
     */
    public List<LineItem> getShippingLineItems() {
        if (shippingLineItems == null) {
            shippingLineItems = new List<LineItem>();

            if (caseId != null) {
                List<OrderItem> shippingItems =
                    EmailControllerHelper.equipmentShippingDetails(caseId);

                shippingLineItems = mapOrderItems(shippingItems);
            }
        }

        return shippingLineItems;
    }

    /**
     * @description Returns Trade-In equipment line items mapped for VF rendering.
     * @return List<LineItem> Trade-In line items.
     */
    public List<LineItem> getTradeInLineItems() {
        if (tradeInLineItems == null) {
            tradeInLineItems = new List<LineItem>();

            if (caseId != null) {
                List<OrderItem> tradeInItems =
                    EmailControllerHelper.tradeInEquipmentDetails(caseId);

                tradeInLineItems = mapOrderItems(tradeInItems);
            }
        }

        return tradeInLineItems;
    }

    /**
     * @description Returns closed Trade-In line items mapped for VF rendering.
     * @return List<LineItem> Closed Trade-In line items.
     */
    public List<LineItem> getClosedTradeInLineItems() {
        if (closedTradeInLineItems == null) {
            closedTradeInLineItems = new List<LineItem>();

            if (caseId != null) {
                List<OrderItem> closedTradeInItems =
                    EmailControllerHelper.closedTradeInEquipmentDetails(
                        caseId
                    );

                closedTradeInLineItems =
                    mapOrderItems(closedTradeInItems);
            }
        }

        return closedTradeInLineItems;
    }

    /**
     * @description CBM-1416: Returns cancelled Trade-In line items for the
     *              Trade-In Cancellation email.
     * @return List<LineItem> Cancelled Trade-In lines containing line
     *         number, item description, and extended price.
     */
    public List<LineItem> getCancellationTradeInLineItems() {
        if (cancellationTradeInLineItems == null) {
            cancellationTradeInLineItems = new List<LineItem>();

            if (caseId != null) {
                List<OrderItem> cancelledTradeInLines =
                    EmailControllerHelper.cancelledTradeInEquipmentDetails(caseId);

                for (
                    OrderItem orderItemRecord :
                    cancelledTradeInLines
                ) {
                    String lineNumber =
                        orderItemRecord.LineNumber__c == null
                        ? ''
                        : String.valueOf(
                            orderItemRecord.LineNumber__c
                        );

                    String itemDescription =
                        orderItemRecord.Product2 == null
                        ? ''
                        : orderItemRecord.Product2.Description;

                    cancellationTradeInLineItems.add(
                        new LineItem(
                            lineNumber,
                            itemDescription,
                            orderItemRecord.TotalPrice
                        )
                    );
                }
            }
        }

        return cancellationTradeInLineItems;
    }

    /**
     * @description Returns the email signature for the current running user.
     * @return String HTML/text signature block.
     */
    public String getEmailSignature() {
        return EmailControllerHelper.emailSignature(caseId);
    }

    /**
     * @description Retrieves the SDN banner using CMDT DeveloperName.
     * @return String Banner URL.
     */
    public String getBannerUrlSDN() {
        String developerName = 'ShipmentBanner';

        return EmailControllerHelper.bannerLoader(developerName);
    }

    /**
     * @description Retrieves Shipping Instructions from the related Order.
     * @return String ShippingInstructions__c value or an empty string.
     */
    public String getShippingInstructions() {
        try {
            Order orderRecord = [
                SELECT ShippingInstructions__c
                FROM Order
                WHERE ParentCase__c = :caseId
                LIMIT 1
            ];

            if (
                orderRecord != null &&
                !String.isBlank(
                    orderRecord.ShippingInstructions__c
                )
            ) {
                return orderRecord.ShippingInstructions__c;
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

    /**
     * @description Retrieves Trade-In Contact first names related to the Case.
     * @return String First names separated by "/", or an empty string.
     */
    public String getFirstName() {
        try {
            List<CaseContactRole> caseContactRoles =
                CaseContactRolesSelector.caseContactRecord(caseId);

            List<String> firstNames = new List<String>();

            if (caseContactRoles == null) {
                return '';
            }

            for (
                CaseContactRole caseContactRole :
                caseContactRoles
            ) {
                if (
                    caseContactRole.Contact != null &&
                    String.isNotBlank(
                        caseContactRole.Contact.FirstName
                    )
                ) {
                    firstNames.add(
                        caseContactRole.Contact.FirstName
                    );
                }
            }

            if (!firstNames.isEmpty()) {
                return String.join(firstNames, '/');
            }

            return '';
        } catch (Exception ex) {
            ErrorLogger.logException(
                ex,
                'ShipDNEmailController',
                'getFirstName'
            );
            throw ex;
        }
    }

    /**
     * @description Returns the Order Number related to the Case.
     * @return String Order Number or an empty string.
     */
    public String getOrderNumber() {
        try {
            List<Order> orderList =
                OrderSelector.orderRecord(caseId);

            if (
                orderList != null &&
                !orderList.isEmpty()
            ) {
                return orderList[0].OrderNumber__c;
            }

            return '';
        } catch (Exception ex) {
            ErrorLogger.logException(
                ex,
                'ShipDNEmailController',
                'getOrderNumber'
            );
            throw ex;
        }
    }

    /**
     * @description CBM-1486: Returns first names of Capital and Service
     *              line Sales Reps for the CAN Credit Notification greeting.
     * @return String Sales Rep first names joined with " / ".
     */
    public String getAccountManagerFirstName() {
        if (caseId == null) {
            return '';
        }

        return EmailControllerHelper.getAccountManagerCapSerLineSalesRep(caseId);
    }

    public Integer getEmailTypeDays() {
        Case cs = [SELECT id,EmailType__c from Case WHERE id=: caseId LIMIT 1];
        if (cs != null)
           return getReminderDays(cs.EmailType__c);
        return 0;
    }
    
    public Integer getReminderDays(String EmailType) { 
        switch on EmailType {         
            when 'TRADEINREMINDER_30D' { return 30; }         
            when 'TRADEINREMINDER_60D' { return 60; } 
            when 'TRADEINREMINDER_90D' { return 90; }       
            when else { return 0; } 
        }
    }
    
    public Boolean getHasOpenTradeInLinesCanada() {
        if (String.isBlank(caseId)) {
            return false;
        }

        return EmailControllerHelper.hasOpenTradeInLines(caseId);
    }

}