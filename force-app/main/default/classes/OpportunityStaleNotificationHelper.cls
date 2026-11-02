public class OpportunityStaleNotificationHelper {

    public static void sendStaleOpportunityEmails(List<Opportunity> staleOpps, Map<Id, 
                                                  OpportunityStaleConfigSettings__mdt> configByOppId) {
        Set<Id> oppIds = new Set<Id>();
        System.debug('===insider Notification Helper===');
        System.debug('====List of optys :: '+staleOpps);
        System.debug('====Config :: '+configByOppId);
        for (Opportunity opp : staleOpps) {
            oppIds.add(opp.Id);
        }

        Map<Id, Opportunity> oppById = new Map<Id, Opportunity>([
            SELECT Id,
                   Name,
                   OwnerId,
                   Owner.Name,
                   Owner.Email,
                   Owner.ManagerId,
                   Owner.Manager.Name,
                   Owner.Manager.Email,
                   CloseDate,
                   StageName,
                   StaleReason__c,
                   DaysSinceLastActivity__c,
                   DaysSinceLastStageChange__c
            FROM Opportunity
            WHERE Id IN :oppIds
        ]);
        System.debug('====Opportunity data in helper oppById:: '+oppById);
        List<Messaging.SingleEmailMessage> emails = new List<Messaging.SingleEmailMessage>();

        for (Opportunity opp : staleOpps) {

            Opportunity fullOpp = oppById.get(opp.Id);
            OpportunityStaleConfigSettings__mdt config = configByOppId.get(opp.Id);

            if (fullOpp == null || config == null) {
                continue;
            }

            if (config.OwnerNotificationEnabled__c == true && fullOpp.Owner.Email != null ) {
                
                emails.add(buildEmail(
                    fullOpp.Owner.Email,
                    fullOpp.Owner.Name,
                    fullOpp
                ));
                System.debug('===emails for owner :: '+emails);
            }

            if (config.ManagerNotificationEnabled__c == true && fullOpp.Owner.ManagerId != null &&
                fullOpp.Owner.Manager.Email != null
            ) {
                emails.add(buildEmail(
                    fullOpp.Owner.Manager.Email,
                    fullOpp.Owner.Manager.Name,
                    fullOpp
                ));
                System.debug('===emails for manager :: '+emails);
            }
        }

        if (!emails.isEmpty()) {
            Messaging.sendEmail(emails);
            System.debug('===Email Sent');
        }
    }

    private static Messaging.SingleEmailMessage buildEmail( String toAddress, String recipientName, Opportunity opp ) {
        Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
        System.debug('===insider build Email :: toAddress :: '+toAddress+' recipientName :: '+recipientName+' opp'+opp);
        email.setToAddresses(new List<String>{ toAddress });
        email.setSubject('Stale Opportunity Alert: ' + opp.Name);

        email.setPlainTextBody(
            'Hello ' + recipientName + ',' + '\n\n' +
            'The following Opportunity has been marked as stale.' + '\n\n' +
            'Opportunity Name: ' + opp.Name + '\n' +
            'Stage: ' + opp.StageName + '\n' +
            'Close Date: ' + String.valueOf(opp.CloseDate) + '\n' +
            'Stale Reason: ' + opp.StaleReason__c + '\n' +
            'Days Since Last Activity: ' + String.valueOf(opp.DaysSinceLastActivity__c) + '\n' +
            'Days Since Last Stage Movement: ' + String.valueOf(opp.DaysSinceLastStageChange__c) + '\n' +
            'Please review this Opportunity and take the required action.' + '\n\n' +
            'This notification is sent once while the Opportunity remains stale.'
        );
        System.debug('===formatted email :: '+email);
        return email;
    }
}