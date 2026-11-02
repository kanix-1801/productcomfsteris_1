/**
 * @author Abhishek Mishra
 * @date 04-06-2026
 * @description TAS Account response item for territory assignment details.
 *
 *              Responsibilities:
 *              1. Store Account context assigned during TAS response processing.
 *              2. Represent TAS territory, sales representative, region, zone, and business unit data.
 *              3. Support AccountTeamMember and OrderLineContact__c creation logic.
 *
 *              This class is a data transfer object and does not contain business logic.
 */
public class TasAccountResponseItem {

    public Id accountId;
    
    public String prospectId;

    public String classCode;
    public String tasSalesCategory;
    public String tasSalesCategoryDescription;

    public String territoryId;
    public String territoryNumber;
    public String territoryDescription;

    public String salesRepId;
    public String salesRepEmployeeNumber;
    public String salesRepName;

    public String regionName;
    public String regionManagerEmployeeNumber;
    public String regionManagerName;

    public String zoneName;
    public String zoneManagerEmployeeNumber;
    public String zoneManagerName;

    public String gbuName;
    public String buName;
}