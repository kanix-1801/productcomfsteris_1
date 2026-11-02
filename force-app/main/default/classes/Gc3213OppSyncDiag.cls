/**
 * Temporary GC-3213 diagnostic - remove after investigation.
 */
public class Gc3213OppSyncDiag {
    public static void run(Id opportunityId) {
        Opportunity o = [
            SELECT Id, AccountId, IsClosed, IDN_Account__c, GPO_Account__c
            FROM Opportunity
            WHERE Id = :opportunityId
        ];
        Account a = [
            SELECT Id, IDN_Account__c, GPO_Account__c
            FROM Account
            WHERE Id = :o.AccountId
        ];
        System.debug(LoggingLevel.ERROR, 'DIAG opp closed=' + o.IsClosed
            + ' idn=' + o.IDN_Account__c + ' gpo=' + o.GPO_Account__c);
        System.debug(LoggingLevel.ERROR, 'DIAG acct idn=' + a.IDN_Account__c
            + ' gpo=' + a.GPO_Account__c);

        Opportunity patch = new Opportunity(
            Id = o.Id,
            IDN_Account__c = a.IDN_Account__c,
            GPO_Account__c = a.GPO_Account__c
        );
        Database.SaveResult sr = Database.update(patch, false);
        System.debug(LoggingLevel.ERROR, 'DIAG success=' + sr.isSuccess());
        if (!sr.isSuccess()) {
            for (Database.Error e : sr.getErrors()) {
                System.debug(LoggingLevel.ERROR, 'DIAG ERR '
                    + e.getStatusCode() + ' ' + e.getMessage() + ' ' + e.getFields());
            }
        }
    }
}