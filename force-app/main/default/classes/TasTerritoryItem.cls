/**
 * @author Abhishek Mishra
 * @date 04-06-2026
 * @description TAS territory assignment item returned in assignment responses.
 *
 *              Responsibilities:
 *              1. Store record context assigned during TAS response processing.
 *              2. Represent TAS territory, sales representative, region, zone, and business unit data.
 *              3. Support AccountTeamMember and OrderLineContact__c creation logic.
 */
public class TasTerritoryItem {

    public Id accountId;

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