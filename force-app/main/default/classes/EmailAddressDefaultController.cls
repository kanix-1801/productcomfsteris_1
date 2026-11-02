/**
 * @author PSL
 * @date 11-27-2025
 * @description Controller class for setting default email addresses for various email types
 */
public with sharing class EmailAddressDefaultController {

    /**
     * @description Sets default email addresses for SOA emails
     * @param sendEmailDefaults QuickAction send email defaults object
     * @param c Case object for which email defaults are being set
     */
    public static void defaultSOAEmailAddresses(QuickAction.SendEmailQuickActionDefaults sendEmailDefaults, Case c) {
        try {
        
            Map<String, String> emailTypeToTemplateName = new Map<String, String>{
                'SOA'           => 'US SOA',
                'No Charge SOA' => 'No Charge SOA'
            };

            String requiredTemplateName = emailTypeToTemplateName.get(c.EmailType__c);

            if (String.isNotBlank(requiredTemplateName)) {
                List<EmailTemplate> matchingTemplates = [
                    SELECT Id, Name
                    FROM EmailTemplate
                    WHERE Name = :requiredTemplateName
                    LIMIT 1
                ];

                if (!matchingTemplates.isEmpty()) {
                    sendEmailDefaults.setTemplateId(matchingTemplates[0].Id);
                    sendEmailDefaults.setInsertTemplateBody(true);
                }
            }      
        
        EmailConditionsConfiguration__mdt config = [
            SELECT ToInternal__c, CCInternal__c, GIReprocessingFixedEmailIds__c,
                   ProceduralFixedEmailIds__c, ReprocessingFixedEmailIds__c, CaseTeamMember__c
            FROM EmailConditionsConfiguration__mdt
            WHERE EmailType__c = :c.EmailType__c LIMIT 1
        ];

        Set<String> toAddresses = new Set<String>();
        Set<String> ccAddresses = new Set<String>();

        
        Set<String> toRoles = new Set<String>();
        Set<String> ccRoles = new Set<String>();
        set<string> caseTeamRolesConfig= new set<string>();


        if (String.isNotBlank(config.CaseTeamMember__c)) {
            for (String role : config.CaseTeamMember__c.split(',')) {
                if (String.isNotBlank(role)) caseTeamRolesConfig.add(role.trim());
            }
        }

        if (String.isNotBlank(config.ToInternal__c)) {
            for (String role : config.ToInternal__c.split(',')) {
                if (String.isNotBlank(role)) toRoles.add(role.trim());
            }
        }
        if (String.isNotBlank(config.CCInternal__c)) {
            for (String role : config.CCInternal__c.split(',')) {
                if (String.isNotBlank(role)) ccRoles.add(role.trim());
            }
        }

        
        List<OrderLineContact__c> olContacts = [
            SELECT SalesRep__r.Email, RSD__r.Email, AVP__r.Email, PDM__r.Email, SDS__r.Email,
                   OrderLine__r.OrderLineType__c
            FROM OrderLineContact__c
            WHERE OrderLine__r.OrderId = :c.Order__c
        ];

        for (OrderLineContact__c olc : olContacts) {
            String lineType = olc.OrderLine__r.OrderLineType__c;

            
            if (ccRoles.contains('Service Line Sales Rep') && lineType == 'Service – Installation') {
                if (olc.SalesRep__r.Email != null) ccAddresses.add(olc.SalesRep__r.Email.trim());
            } else {
                if (toRoles.contains('Capital Line Sales Rep') && olc.SalesRep__r.Email != null) {
                    toAddresses.add(olc.SalesRep__r.Email.trim());
                }
            }
			//CBM-914
            if(lineType != 'Service – Installation'){
                if (ccRoles.contains('RSD') && olc.RSD__r.Email != null) ccAddresses.add(olc.RSD__r.Email.trim());
                if (ccRoles.contains('AVP') && olc.AVP__r.Email != null) ccAddresses.add(olc.AVP__r.Email.trim());
            }
            if (ccRoles.contains('PDM') && olc.PDM__r.Email != null) ccAddresses.add(olc.PDM__r.Email.trim());
            if (ccRoles.contains('SDS') && olc.SDS__r.Email != null) ccAddresses.add(olc.SDS__r.Email.trim());
           
            if (lineType == 'GI Reprocessing' && String.isNotBlank(config.GIReprocessingFixedEmailIds__c)) {
                for (String email : config.GIReprocessingFixedEmailIds__c.split(',')) {
                    if (String.isNotBlank(email)) ccAddresses.add(email.trim());
                }
            }
            if (lineType == 'Procedural' && String.isNotBlank(config.ProceduralFixedEmailIds__c)) {
                for (String email : config.ProceduralFixedEmailIds__c.split(',')) {
                    if (String.isNotBlank(email)) ccAddresses.add(email.trim());
                }
            }
            if (lineType == 'Reprocessing' && String.isNotBlank(config.ReprocessingFixedEmailIds__c)) {
                for (String email : config.ReprocessingFixedEmailIds__c.split(',')) {
                    if (String.isNotBlank(email)) ccAddresses.add(email.trim());
                }
            }
        }
           

        
        if (String.isNotBlank(config.CaseTeamMember__c)) {
            List<CaseTeamMember> teamMembers = [
                select TeamRole.Name ,ParentId, member.Email,MemberId from CaseTeamMember
                WHERE ParentId = :c.Id
            ];
        
				 for (CaseTeamMember member : teamMembers) {
                if (caseTeamRolesConfig.contains(member.TeamRole.Name) && member.Member.Email != null) {
                    ccAddresses.add(member.Member.Email.trim());
                }
            }
        }

       
        ccAddresses.removeAll(toAddresses);

        // 5. Set To and CC on EmailMessage
        EmailMessage emailMessage = (EmailMessage) sendEmailDefaults.getTargetSObject();
        emailMessage.ToAddress = String.join(new List<String>(toAddresses), ';');
        emailMessage.CcAddress = String.join(new List<String>(ccAddresses), ';');
        emailMessage.BccAddress ='';

       
        } catch (Exception ex) {
            ErrorLogger.logException(ex, 'EmailAddressDefaultController', 'defaultSOAEmailAddresses');
            throw ex;
        }
    }
    

    /**
     * @description Sets default email addresses for COA Project emails
     * @param sendEmailDefaults QuickAction send email defaults object
     * @param c Case object for which email defaults are being set
     */
    public static void defaultCOAProjectEmailAddresses(QuickAction.SendEmailQuickActionDefaults sendEmailDefaults, Case c) {
    try {

        // 2. Get configuration from Custom Metadata
        EmailConditionsConfiguration__mdt config = [
            SELECT ToExternal__c
            FROM EmailConditionsConfiguration__mdt
            WHERE EmailType__c = 'COA Project'
            LIMIT 1
        ];

        Set<String> toAddresses = new Set<String>();

        // 3. If ToExternal__c is populated, query CaseContactRole for matching role
        if (String.isNotBlank(config.ToExternal__c)) {
            List<CaseContactRole> caseContactRoles = [
                SELECT Id, Role, Contact.Email, CasesId
                FROM CaseContactRole
                WHERE CasesId = :c.Id
                AND Role = :config.ToExternal__c
            ];

            for (CaseContactRole ccRole : caseContactRoles) {
                if (ccRole.Contact.Email != null) {
                    toAddresses.add(ccRole.Contact.Email.trim());
                }
            }
        }

        // 4. Set ToAddress on EmailMessage
        EmailMessage emailMessage = (EmailMessage) sendEmailDefaults.getTargetSObject();
        emailMessage.ToAddress = String.join(new List<String>(toAddresses), ';');
        emailMessage.BccAddress ='';

    } catch (Exception ex) {
        ErrorLogger.logException(ex, 'EmailAddressDefaultController', 'defaultCOAProjectEmailAddresses');
        throw ex;
    }
}
    
    /**
     * @description Sets default email addresses for COA Turns emails
     * @param sendEmailDefaults QuickAction send email defaults object
     * @param c Case object for which email defaults are being set
     */
    public static void defaultCOATurnsEmailAddresses(QuickAction.SendEmailQuickActionDefaults sendEmailDefaults, Case c) {
    try {


        // 2. Get configuration from Custom Metadata
        EmailConditionsConfiguration__mdt config = [
            SELECT ToExternal__c
            FROM EmailConditionsConfiguration__mdt
            WHERE EmailType__c = 'COA Turns'
            LIMIT 1
        ];

        Set<String> toAddresses = new Set<String>();

        // 3. If ToExternal__c is populated, split roles and query CaseContactRole
        if (String.isNotBlank(config.ToExternal__c)) {
            List<String> roles = config.ToExternal__c.split(','); // Split by comma and trim spaces

            List<CaseContactRole> caseContactRoles = [
                SELECT Id, Role, Contact.Email, CasesId
                FROM CaseContactRole
                WHERE CasesId = :c.Id
                AND Role IN :roles
            ];

            for (CaseContactRole ccRole : caseContactRoles) {
                if (ccRole.Contact.Email != null) {
                    toAddresses.add(ccRole.Contact.Email.trim());
                }
            }
        }

        // 4. Set ToAddress on EmailMessage
        EmailMessage emailMessage = (EmailMessage) sendEmailDefaults.getTargetSObject();
        emailMessage.ToAddress = String.join(new List<String>(toAddresses), ';');
         emailMessage.BccAddress ='';

    } catch (Exception ex) {
        ErrorLogger.logException(ex, 'EmailAddressDefaultController', 'defaultCOATurnsEmailAddresses');
        throw ex;
    }
}
  
    /**
     * @description Sets default email addresses for C1 emails
     * @param sendEmailDefaults QuickAction send email defaults object
     * @param c Case object for which email defaults are being set
     */
    public static void defaultC1EmailAddresses(QuickAction.SendEmailQuickActionDefaults sendEmailDefaults, Case c) {
    try {
        // 1. Get Email Template for C1
        EmailTemplate template = [SELECT Id FROM EmailTemplate WHERE Name = 'C1US' LIMIT 1];
        sendEmailDefaults.setInsertTemplateBody(true);
        sendEmailDefaults.setTemplateId(template.Id);

        // 2. Get configuration from Custom Metadata
        EmailConditionsConfiguration__mdt config = [
            SELECT ToExternal__c, CCInternal__c, ToInternal__c
            FROM EmailConditionsConfiguration__mdt
            WHERE EmailType__c = 'C1'
            LIMIT 1
        ];

        Set<String> toAddresses = new Set<String>();
        Set<String> ccAddresses = new Set<String>();

        Set<String> toRoles = new Set<String>();
        Set<String> ccRoles = new Set<String>();

        // Parse metadata roles
        if (String.isNotBlank(config.ToInternal__c)) {
            for (String role : config.ToInternal__c.split(',')) {
                if (String.isNotBlank(role)) toRoles.add(role.trim());
            }
        }
        if (String.isNotBlank(config.CCInternal__c)) {
            for (String role : config.CCInternal__c.split(',')) {
                if (String.isNotBlank(role)) ccRoles.add(role.trim());
            }
        }

        // 3. External contacts from CaseContactRole
        if (String.isNotBlank(config.ToExternal__c)) {
            List<String> externalRoles = new List<String>();
            for (String role : config.ToExternal__c.split(',')) {
                externalRoles.add(role.trim());
            }

            List<CaseContactRole> externalContacts = [
                SELECT Contact.Email
                FROM CaseContactRole
                WHERE CasesId = :c.Id AND Role IN :externalRoles
            ];

            for (CaseContactRole ccRole : externalContacts) {
                if (ccRole.Contact.Email != null) {
                    toAddresses.add(ccRole.Contact.Email.trim());
                }
            }
        }

        // 4. Internal contacts from OrderLineContact__c (Capital Line Sales Rep)
        List<OrderLineContact__c> olContacts = [
            SELECT SalesRep__r.Email, OrderLine__r.CreateSubcase__c
            FROM OrderLineContact__c
            WHERE OrderLine__r.OrderId = :c.Order__c
        ];

        for (OrderLineContact__c olc : olContacts) {
            String lineType = olc.OrderLine__r.CreateSubcase__c;

           
            if (ccRoles.contains('Capital Line Sales Rep') && lineType == 'yes - Capital line' && olc.SalesRep__r.Email != null) {
                ccAddresses.add(olc.SalesRep__r.Email.trim());
            }
        }

        // Remove duplicates between To and CC
        

        // 5. Set To and CC on EmailMessage
        EmailMessage emailMessage = (EmailMessage) sendEmailDefaults.getTargetSObject();
        emailMessage.ToAddress = String.join(new List<String>(toAddresses), ';');
        emailMessage.CcAddress = String.join(new List<String>(ccAddresses), ';');
        emailMessage.BccAddress = '';

    } catch (Exception ex) {
        ErrorLogger.logException(ex, 'EmailAddressDefaultController', 'defaultC1EmailAddresses');
        throw ex;
    }
}

    /**
     * @description Sets default email addresses for C2 emails
     * @param sendEmailDefaults QuickAction send email defaults object
     * @param c Case object for which email defaults are being set
     */
    public static void defaultC2EmailAddresses(QuickAction.SendEmailQuickActionDefaults sendEmailDefaults, Case c) {
    try {
        // 1) Choose C2 template (adjust name if your org uses 'C2 US')
        EmailTemplate template = [SELECT Id FROM EmailTemplate WHERE Name = 'C2US' LIMIT 1];
        sendEmailDefaults.setInsertTemplateBody(true);
        sendEmailDefaults.setTemplateId(template.Id);

        // 2) Load Custom Metadata for the case's EmailType (e.g., 'C2')
        EmailConditionsConfiguration__mdt config = [
            SELECT ToInternal__c, CCInternal__c, GIReprocessingFixedEmailIds__c,
                   ProceduralFixedEmailIds__c, ReprocessingFixedEmailIds__c, CaseTeamMember__c
            FROM EmailConditionsConfiguration__mdt
            WHERE EmailType__c = :c.EmailType__c
            LIMIT 1
        ];

        // Containers
        Set<String> toAddresses = new Set<String>();
        Set<String> ccAddresses = new Set<String>();
        Set<String> toRoles = new Set<String>();
        Set<String> ccRoles = new Set<String>();
        Set<String> caseTeamRolesConfig = new Set<String>();

        // 3) Parse roles from metadata safely
        if (config != null) {
            if (String.isNotBlank(config.ToInternal__c)) {
                for (String role : config.ToInternal__c.split(',')) {
                    if (String.isNotBlank(role)) toRoles.add(role.trim());
                }
            }
            if (String.isNotBlank(config.CCInternal__c)) {
                for (String role : config.CCInternal__c.split(',')) {
                    if (String.isNotBlank(role)) ccRoles.add(role.trim());
                }
            }
            if (String.isNotBlank(config.CaseTeamMember__c)) {
                for (String role : config.CaseTeamMember__c.split(',')) {
                    if (String.isNotBlank(role)) caseTeamRolesConfig.add(role.trim());
                }
            }
        }

        // 4) Collect Order Line level contacts
        List<OrderLineContact__c> olContacts = [
            SELECT SalesRep__r.Email, RSD__r.Email, AVP__r.Email, PDM__r.Email, SDS__r.Email,
                   OrderLine__r.CreateSubcase__c,OrderLine__r.OrderLineType__c
            FROM OrderLineContact__c
            WHERE OrderLine__r.OrderId = :c.Order__c
        ];

        for (OrderLineContact__c olc : olContacts) {
            String lineType = olc.OrderLine__r.OrderLineType__c;
            string lineTypeMain=olc.OrderLine__r.CreateSubcase__c;
            Boolean isServiceInstallation = (lineTypeMain == 'yes - Capital line' || lineTypeMain == 'yes - Service Installation'  );
            boolean isConsumables = (lineType=='Consumables');
            // ---- TO ----
            // Add Sales Rep to TO based on ToInternal__c roles & line type
            if (toRoles.contains('Service Line Sales Rep') && isServiceInstallation && olc.SalesRep__r.Email != null) {
                toAddresses.add(olc.SalesRep__r.Email.trim());
            }
            if (toRoles.contains('Capital Line Sales Rep') && !isServiceInstallation && !isConsumables  && olc.SalesRep__r.Email != null) {
                toAddresses.add(olc.SalesRep__r.Email.trim());
            }
             if (ccRoles.contains('Consumable Line Sales Rep') && isConsumables && olc.SalesRep__r.Email != null) {
                ccAddresses.add(olc.SalesRep__r.Email.trim());
            }

            // ---- CC ---- (managerial roles via CCInternal__c)
            if (ccRoles.contains('RSD') && olc.RSD__r.Email != null) ccAddresses.add(olc.RSD__r.Email.trim());
            if (ccRoles.contains('AVP') && olc.AVP__r.Email != null) ccAddresses.add(olc.AVP__r.Email.trim());
            if (ccRoles.contains('PDM') && olc.PDM__r.Email != null) ccAddresses.add(olc.PDM__r.Email.trim());
            if (ccRoles.contains('SDS') && olc.SDS__r.Email != null) ccAddresses.add(olc.SDS__r.Email.trim());

            // Fixed email lists per line type
            if (lineType == 'GI Reprocessing' && String.isNotBlank(config.GIReprocessingFixedEmailIds__c)) {
                for (String email : config.GIReprocessingFixedEmailIds__c.split(',')) {
                    if (String.isNotBlank(email)) ccAddresses.add(email.trim());
                     
                }
            }
            
            
            if (lineType == 'Procedural' && String.isNotBlank(config.ProceduralFixedEmailIds__c)) {
                for (String email : config.ProceduralFixedEmailIds__c.split(',')) {
                    if (String.isNotBlank(email)) ccAddresses.add(email.trim());
                }
            }
            if (lineType == 'Reprocessing' && String.isNotBlank(config.ReprocessingFixedEmailIds__c)) {
                for (String email : config.ReprocessingFixedEmailIds__c.split(',')) {
                    if (String.isNotBlank(email)) ccAddresses.add(email.trim());
                }
            }
        }

        // 5) Case Team Members (add to CC if configured)
        if (!caseTeamRolesConfig.isEmpty()) {
            List<CaseTeamMember> teamMembers = [
                SELECT TeamRole.Name, ParentId, Member.Email, MemberId
                FROM CaseTeamMember
                WHERE ParentId = :c.Id
            ];
            for (CaseTeamMember member : teamMembers) {
                if (caseTeamRolesConfig.contains(member.TeamRole.Name) && member.Member.Email != null) {
                    ccAddresses.add(member.Member.Email.trim());
                }
            }
        }

        

         
        
        // 6) Apply To/CC/BCC on EmailMessage
        EmailMessage emailMessage = (EmailMessage) sendEmailDefaults.getTargetSObject();
        emailMessage.ToAddress  = String.join(new List<String>(toAddresses), ';');
        emailMessage.CcAddress  = String.join(new List<String>(ccAddresses), ';');
        
       
        emailMessage.BccAddress = '';
    } catch (Exception ex) {
        ErrorLogger.logException(ex, 'EmailAddressDefaultController', 'defaultC2EmailAddresses');
        throw ex;
    }
}
    /**
     * @description Sets default email addresses for DF emails
     * @param sendEmailDefaults QuickAction send email defaults object
     * @param c Case object for which email defaults are being set
     */
    
    public static void defaultDFEmailAddresses(QuickAction.SendEmailQuickActionDefaults sendEmailDefaults, Case c) {
        try {
            
            // ---- Guards ----
            if (sendEmailDefaults == null || c == null) {
                return;
            }

            // ---- DF Email Template ----
            EmailTemplate template = [
                SELECT Id
                FROM EmailTemplate
                WHERE Name = 'DF'
                LIMIT 1
            ];
            sendEmailDefaults.setInsertTemplateBody(true);
            sendEmailDefaults.setTemplateId(template.Id);

            // ---- Configuration (CMDT) ----
            EmailConditionsConfiguration__mdt config;
            try {
                config = [
                    SELECT ToInternal__c, CCInternal__c,
                           ToExternal__c, CCExternal__c,
                           GIExternalCC__c, ProceduralExternalCC__c, ReprocessingExternalCC__c,
                           GIReprocessingFixedEmailIds__c, ProceduralFixedEmailIds__c, ReprocessingFixedEmailIds__c,
                           CaseTeamMember__c, EmailType__c
                    FROM EmailConditionsConfiguration__mdt
                    WHERE EmailType__c = :c.EmailType__c
                    LIMIT 1
                ];
            } catch (Exception ign) {
                // If no config exists for this EmailType, proceed with empty sets.
                config = null;
            }

            Set<String> toAddresses = new Set<String>();
            Set<String> ccAddresses = new Set<String>();

            // ---- Parse role tokens from config (keep inline, no helpers) ----
            Set<String> toInternalRoles = new Set<String>();
            Set<String> ccInternalRoles = new Set<String>();
            Set<String> toExternalRoles = new Set<String>();
            Set<String> ccExternalRoles = new Set<String>();
            Set<String> caseTeamRolesConfig = new Set<String>(); // if you later include CaseTeamMember CCs

            if (config != null) {
                if (String.isNotBlank(config.CaseTeamMember__c)) {
                    for (String role : config.CaseTeamMember__c.split(',')) {
                        if (String.isNotBlank(role)) caseTeamRolesConfig.add(role.trim());
                    }
                }
                if (String.isNotBlank(config.ToInternal__c)) {
                    for (String role : config.ToInternal__c.split(',')) {
                        if (String.isNotBlank(role)) toInternalRoles.add(role.trim());
                    }
                }
                if (String.isNotBlank(config.CCInternal__c)) {
                    for (String role : config.CCInternal__c.split(',')) {
                        if (String.isNotBlank(role)) ccInternalRoles.add(role.trim());
                    }
                }
                if (String.isNotBlank(config.ToExternal__c)) {
                    for (String role : config.ToExternal__c.split(',')) {
                        if (String.isNotBlank(role)) toExternalRoles.add(role.trim());
                    }
                }
                if (String.isNotBlank(config.CCExternal__c)) {
                    for (String role : config.CCExternal__c.split(',')) {
                        if (String.isNotBlank(role)) ccExternalRoles.add(role.trim());
                    }
                }
            }

            // ---- Internal recipients via OrderLineContact__c (Sales Rep + leadership) ----
            List<OrderLineContact__c> olContacts = [
                SELECT SalesRep__r.Email, RSD__r.Email, AVP__r.Email, PDM__r.Email, SDS__r.Email,
                       OrderLine__r.OrderLineType__c,
                       OrderLine__r.CreateSubcase__c
                FROM OrderLineContact__c
                WHERE OrderLine__r.OrderId = :c.Order__c
            ];

            for (OrderLineContact__c olc : olContacts) {
                String lineType = olc.OrderLine__r.OrderLineType__c;
                String createSub = olc.OrderLine__r.CreateSubcase__c;

                // --- To: Sales Rep(s) ---
                if (toInternalRoles.contains('Capital Line Sales Rep') && olc.SalesRep__r != null && String.isNotBlank(olc.SalesRep__r.Email)) {
                    toAddresses.add(olc.SalesRep__r.Email.trim());
                }
                if (toInternalRoles.contains('Service Line Sales Rep')
                    && lineType == 'Service – Installation'
                    && olc.SalesRep__r != null && String.isNotBlank(olc.SalesRep__r.Email)) {
                    toAddresses.add(olc.SalesRep__r.Email.trim());
                }

                // --- CC: Sales Rep(s) gated by CreateSubcase__c (Capital) ---
                if (ccInternalRoles.contains('Capital Line Sales Rep')
                    && createSub == 'yes - Capital line'
                    && olc.SalesRep__r != null && String.isNotBlank(olc.SalesRep__r.Email)) {
                    ccAddresses.add(olc.SalesRep__r.Email.trim());
                }
                // Leadership CCs
                if (ccInternalRoles.contains('RSD') && olc.RSD__r != null && String.isNotBlank(olc.RSD__r.Email)) {
                    ccAddresses.add(olc.RSD__r.Email.trim());
                }
                if (ccInternalRoles.contains('AVP') && olc.AVP__r != null && String.isNotBlank(olc.AVP__r.Email)) {
                    ccAddresses.add(olc.AVP__r.Email.trim());
                }
                if (ccInternalRoles.contains('PDM') && olc.PDM__r != null && String.isNotBlank(olc.PDM__r.Email)) {
                    ccAddresses.add(olc.PDM__r.Email.trim());
                }
                if (ccInternalRoles.contains('SDS') && olc.SDS__r != null && String.isNotBlank(olc.SDS__r.Email)) {
                    ccAddresses.add(olc.SDS__r.Email.trim());
                }

                // --- External fixed CCs by line type (if configured) ---
                if (config != null) {
                    if (lineType == 'GI Reprocessing' && String.isNotBlank(config.GIExternalCC__c)) {
                        for (String email : config.GIExternalCC__c.split(',')) {
                            if (String.isNotBlank(email)) ccAddresses.add(email.trim());
                        }
                    }
                    if (lineType == 'Procedural' && String.isNotBlank(config.ProceduralExternalCC__c)) {
                        for (String email : config.ProceduralExternalCC__c.split(',')) {
                            if (String.isNotBlank(email)) ccAddresses.add(email.trim());
                        }
                    }
                    if (lineType == 'Reprocessing' && String.isNotBlank(config.ReprocessingExternalCC__c)) {
                        for (String email : config.ReprocessingExternalCC__c.split(',')) {
                            if (String.isNotBlank(email)) ccAddresses.add(email.trim());
                        }
                    }
                }
            }

            // ---- External To/CC via CaseContactRole (Receiving / Install / Department) ----
            if (!toExternalRoles.isEmpty() || !ccExternalRoles.isEmpty()) {
                // One query for all roles, build a map role -> emails
                List<CaseContactRole> roleRows = [
                    SELECT Role, Contact.Email
                    FROM CaseContactRole
                    WHERE CasesId = :c.Id
                          AND Contact.Email != null
                ];

                Map<String, Set<String>> emailsByRoleLc = new Map<String, Set<String>>();
                for (CaseContactRole row : roleRows) {
                    String roleKey = (row.Role == null) ? null : row.Role.toLowerCase();
                    if (String.isBlank(roleKey)) continue;
                    if (!emailsByRoleLc.containsKey(roleKey)) {
                        emailsByRoleLc.put(roleKey, new Set<String>());
                    }
                    String email = row.Contact.Email == null ? null : row.Contact.Email.trim();
                    if (String.isNotBlank(email)) {
                        emailsByRoleLc.get(roleKey).add(email);
                    }
                }

                // Apply To External
                for (String token : toExternalRoles) {
                    String key = (token == null) ? null : token.trim().toLowerCase();
                    if (String.isBlank(key)) continue;
                    if (emailsByRoleLc.containsKey(key)) {
                        toAddresses.addAll(emailsByRoleLc.get(key));
                    }
                }
                // Apply CC External
                for (String token : ccExternalRoles) {
                    String key = (token == null) ? null : token.trim().toLowerCase();
                    if (String.isBlank(key)) continue;
                    if (emailsByRoleLc.containsKey(key)) {
                        ccAddresses.addAll(emailsByRoleLc.get(key));
                    }
                }
            }

            // ---- De-duplicate CC from To ----
            ccAddresses.removeAll(toAddresses);

            // ---- Populate EmailMessage from defaults ----
            EmailMessage emailMessage = (EmailMessage) sendEmailDefaults.getTargetSObject();
            emailMessage.ToAddress  = String.join(new List<String>(toAddresses), ';');
            emailMessage.CcAddress  = String.join(new List<String>(ccAddresses), ';');
            emailMessage.BccAddress = '';

    
        } catch (Exception ex) {
            ErrorLogger.logException(ex, 'EmailAddressDefaultController', 'defaultDFEmailAddresses');
            throw ex;
        }
    }
    
    /**
     * @description Sets default email addresses for Ship date notifications emails and Pre-Ship email for Story : 1386
     * @param sendEmailDefaults QuickAction send email defaults object
     * @param c Case object for which email defaults are being set
     */

	public static void defaultSDNEmailAddresses(QuickAction.SendEmailQuickActionDefaults sendEmailDefaults, Case c,String templateName) {
        try {
           
			if (sendEmailDefaults == null || c == null) {
                return;
            }
			
            EmailTemplate template = [SELECT Id,Name from EmailTemplate WHERE Name =: templateName  LIMIT 1];
               sendEmailDefaults.setInsertTemplateBody(true);
               sendEmailDefaults.setTemplateId(template.Id);
            
            // ---- DF Email Template ----
          /*  EmailTemplate template = [
                SELECT Id
                FROM EmailTemplate
                WHERE Name = 'Ship Date Notification'
                LIMIT 1
            ]; */
           // sendEmailDefaults.setInsertTemplateBody(true);
           // sendEmailDefaults.setTemplateId(template.Id);

            // ---- Configuration (CMDT) ----
            EmailConditionsConfiguration__mdt config;
            try {
                config = [
                    SELECT ToInternal__c, CCInternal__c,
                           ToExternal__c, CCExternal__c,
                           GIExternalCC__c, ProceduralExternalCC__c, ReprocessingExternalCC__c,
                           GIReprocessingFixedEmailIds__c, ProceduralFixedEmailIds__c, ReprocessingFixedEmailIds__c,
                           CaseTeamMember__c, EmailType__c
                    FROM EmailConditionsConfiguration__mdt
                    WHERE EmailType__c = :c.EmailType__c
                    LIMIT 1
                ];
            } catch (Exception ign) {
                config = null; // proceed without config
            }

            Set<String> toAddresses = new Set<String>();
            Set<String> ccAddresses = new Set<String>();

            // ---- Parse role tokens from config (inline) ----
            Set<String> toInternalRoles  = new Set<String>();
            Set<String> ccInternalRoles  = new Set<String>();
            Set<String> toExternalRoles  = new Set<String>();
            Set<String> ccExternalRoles  = new Set<String>();
            // If you later need Case Team, you can use this:
            Set<String> caseTeamRolesConfig = new Set<String>();

            if (config != null) {
                if (String.isNotBlank(config.CaseTeamMember__c)) {
                    for (String role : config.CaseTeamMember__c.split(',')) {
                        if (String.isNotBlank(role)) caseTeamRolesConfig.add(role.trim());
                    }
                }
                if (String.isNotBlank(config.ToInternal__c)) {
                    for (String role : config.ToInternal__c.split(',')) {
                        if (String.isNotBlank(role)) toInternalRoles.add(role.trim());
                    }
                }
                if (String.isNotBlank(config.CCInternal__c)) {
                    for (String role : config.CCInternal__c.split(',')) {
                        if (String.isNotBlank(role)) ccInternalRoles.add(role.trim());
                    }
                }
                if (String.isNotBlank(config.ToExternal__c)) {
                    for (String role : config.ToExternal__c.split(',')) {
                        if (String.isNotBlank(role)) toExternalRoles.add(role.trim());
                    }
                }
                if (String.isNotBlank(config.CCExternal__c)) {
                    for (String role : config.CCExternal__c.split(',')) {
                        if (String.isNotBlank(role)) ccExternalRoles.add(role.trim());
                    }
                }
            }

            
            // We will use this map for both general External To/CC AND line-type specific External CCs.
            Map<String, Set<String>> emailsByRoleLc = new Map<String, Set<String>>();
            {
                List<CaseContactRole> caseConRole = [
                    SELECT Role, Contact.Email
                    FROM CaseContactRole
                    WHERE CasesId = :c.Id
                          AND Contact.Email != null
                ];
                for (CaseContactRole row : caseConRole) {
                    String roleKey = (row.Role == null) ? null : row.Role.toLowerCase();
                    if (String.isBlank(roleKey)) continue;
                    if (!emailsByRoleLc.containsKey(roleKey)) {
                        emailsByRoleLc.put(roleKey, new Set<String>());
                    }
                    String email = row.Contact.Email == null ? null : row.Contact.Email.trim();
                    if (String.isNotBlank(email)) {
                        emailsByRoleLc.get(roleKey).add(email);
                    }
                }
            }

            // ---- Internal recipients via OrderLineContact__c ----
            List<OrderLineContact__c> olContacts = [
                SELECT SalesRep__r.Email, RSD__r.Email, AVP__r.Email, PDM__r.Email, SDS__r.Email,
                       OrderLine__r.OrderLineType__c,
                       OrderLine__r.CreateSubcase__c
                FROM OrderLineContact__c
                WHERE OrderLine__r.OrderId = :c.Order__c
            ];

            // Pre-parse line-type specific External CC role tokens from CMDT
            // (These are role names, NOT emails.)
            Set<String> giExternalRoleTokens   = new Set<String>();
            Set<String> procExternalRoleTokens = new Set<String>();
            Set<String> repExternalRoleTokens  = new Set<String>();

            if (config != null) {
                if (String.isNotBlank(config.GIExternalCC__c)) {
                    for (String t : config.GIExternalCC__c.split(',')) {
                        if (String.isNotBlank(t)) giExternalRoleTokens.add(t.trim());
                    }
                }
                if (String.isNotBlank(config.ProceduralExternalCC__c)) {
                    for (String t : config.ProceduralExternalCC__c.split(',')) {
                        if (String.isNotBlank(t)) procExternalRoleTokens.add(t.trim());
                    }
                }
                if (String.isNotBlank(config.ReprocessingExternalCC__c)) {
                    for (String t : config.ReprocessingExternalCC__c.split(',')) {
                        if (String.isNotBlank(t)) repExternalRoleTokens.add(t.trim());
                    }
                }
            }

            for (OrderLineContact__c olc : olContacts) {
                String lineType  = olc.OrderLine__r.OrderLineType__c;
                String createSub = olc.OrderLine__r.CreateSubcase__c;

                // --- To: Sales Rep(s) ---
                // Capital → compare using CreateSubcase__c
                if (toInternalRoles.contains('Capital Line Sales Rep')
                    && createSub == 'yes - Capital line'
                    && olc.SalesRep__r != null
                    && String.isNotBlank(olc.SalesRep__r.Email)) {
                    toAddresses.add(olc.SalesRep__r.Email.trim());
                }

                // Service → compare using OrderLineType__c
                if (toInternalRoles.contains('Service Line Sales Rep')
                    && lineType == 'Service – Installation'
                    && olc.SalesRep__r != null
                    && String.isNotBlank(olc.SalesRep__r.Email)) {
                    toAddresses.add(olc.SalesRep__r.Email.trim());
                }

                // --- CC: Sales Rep(s) ---
                // Capital → gated by CreateSubcase__c
                if (ccInternalRoles.contains('Capital Line Sales Rep')
                    && createSub == 'yes - Capital line'
                    && olc.SalesRep__r != null
                    && String.isNotBlank(olc.SalesRep__r.Email)) {
                    ccAddresses.add(olc.SalesRep__r.Email.trim());
                }

                // Service → gated by OrderLineType__c
                if (ccInternalRoles.contains('Service Line Sales Rep')
                    && lineType == 'Service – Installation'
                    && olc.SalesRep__r != null
                    && String.isNotBlank(olc.SalesRep__r.Email)) {
                    ccAddresses.add(olc.SalesRep__r.Email.trim());
                }

                // --- Leadership CCs ---
                if (ccInternalRoles.contains('RSD') && olc.RSD__r != null && String.isNotBlank(olc.RSD__r.Email)) {
                    ccAddresses.add(olc.RSD__r.Email.trim());
                }
                if (ccInternalRoles.contains('AVP') && olc.AVP__r != null && String.isNotBlank(olc.AVP__r.Email)) {
                    ccAddresses.add(olc.AVP__r.Email.trim());
                }
                if (ccInternalRoles.contains('PDM') && olc.PDM__r != null && String.isNotBlank(olc.PDM__r.Email)) {
                    ccAddresses.add(olc.PDM__r.Email.trim());
                }
                if (ccInternalRoles.contains('SDS') && olc.SDS__r != null && String.isNotBlank(olc.SDS__r.Email)) {
                    ccAddresses.add(olc.SDS__r.Email.trim());
                }

                // --- External CCs by line type using CaseContactRole role tokens ---
                // These CMDT fields contain role labels, not emails.
                if (config != null) {
                    if (lineType == 'GI Reprocessing') {
                        for (String token : giExternalRoleTokens) {
                            String key = (token == null) ? null : token.trim().toLowerCase();
                            if (String.isBlank(key)) continue;
                            if (emailsByRoleLc.containsKey(key)) {
                                ccAddresses.addAll(emailsByRoleLc.get(key));
                            }
                        }
                    } else if (lineType == 'Procedural') {
                        for (String token : procExternalRoleTokens) {
                            String key = (token == null) ? null : token.trim().toLowerCase();
                            if (String.isBlank(key)) continue;
                            if (emailsByRoleLc.containsKey(key)) {
                                ccAddresses.addAll(emailsByRoleLc.get(key));
                            }
                        }
                    } else if (lineType == 'Reprocessing') {
                        for (String token : repExternalRoleTokens) {
                            String key = (token == null) ? null : token.trim().toLowerCase();
                            if (String.isBlank(key)) continue;
                            if (emailsByRoleLc.containsKey(key)) {
                                ccAddresses.addAll(emailsByRoleLc.get(key));
                            }
                        }
                    }
                    // Fixed email lists per line type
                    if (lineType == 'GI Reprocessing' && String.isNotBlank(config.GIReprocessingFixedEmailIds__c)) {
                        for (String email : config.GIReprocessingFixedEmailIds__c.split(',')) {
                            if (String.isNotBlank(email)) ccAddresses.add(email.trim());
                        }
                    }
                }
            }

            // ---- General External To/CC via CaseContactRole (independent of line type) ----
            if (!toExternalRoles.isEmpty() || !ccExternalRoles.isEmpty()) {
                // Apply To External
                for (String token : toExternalRoles) {
                    String key = (token == null) ? null : token.trim().toLowerCase();
                    if (String.isBlank(key)) continue;
                    if (emailsByRoleLc.containsKey(key)) {
                        toAddresses.addAll(emailsByRoleLc.get(key));
                    }
                }
                // Apply CC External
                for (String token : ccExternalRoles) {
                    String key = (token == null) ? null : token.trim().toLowerCase();
                    if (String.isBlank(key)) continue;
                    if (emailsByRoleLc.containsKey(key)) {
                        ccAddresses.addAll(emailsByRoleLc.get(key));
                    }
                }
            }
            
              if (!caseTeamRolesConfig.isEmpty()) {
            List<CaseTeamMember> teamMembers = [
                SELECT TeamRole.Name, ParentId, Member.Email, MemberId
                FROM CaseTeamMember
                WHERE ParentId = :c.Id
            ];
            for (CaseTeamMember member : teamMembers) {
                if (caseTeamRolesConfig.contains(member.TeamRole.Name) && member.Member.Email != null) {
                    ccAddresses.add(member.Member.Email.trim());
                }
            }
        }


            // ---- De-duplicate CC from To ----
            ccAddresses.removeAll(toAddresses);

            // ---- Populate EmailMessage from defaults ----
            EmailMessage emailMessage = (EmailMessage) sendEmailDefaults.getTargetSObject();
            emailMessage.ToAddress  = String.join(new List<String>(toAddresses), ';');
            emailMessage.CcAddress  = String.join(new List<String>(ccAddresses), ';');
            emailMessage.BccAddress = '';

        }catch(exception ex){
            ErrorLogger.logException(ex, 'EmailAddressDefaultController', 'defaultSDNEmailAddresses');
            throw ex;
        }
    }

		/**
     * @description Sets default email addresses for Go no Go emails
     * @param sendEmailDefaults QuickAction send email defaults object
     * @param c Case object for which email defaults are being set
     */
	
	public static void defaultGoNoGoEmailAddresses(QuickAction.SendEmailQuickActionDefaults sendEmailDefaults, Case c) {
    	try {
            if (sendEmailDefaults == null || c == null) {
                return;
            }
            
            EmailTemplate template = [
                SELECT Id
                FROM EmailTemplate
                WHERE Name = 'Go No-Go'
                LIMIT 1
            ];
       

        sendEmailDefaults.setInsertTemplateBody(true);
        sendEmailDefaults.setTemplateId(template.Id);

        // --- 2) Load EmailConditionsConfiguration for this Case's EmailType ---
        // Primary filter: EmailType__c matches Case.EmailType__c
        // Fallback: DeveloperName = 'GoNoGo' (from your screenshot)
        EmailConditionsConfiguration__mdt config;
        List<EmailConditionsConfiguration__mdt> cfgs = [
            SELECT ToInternal__c, CCInternal__c, GIReprocessingFixedEmailIds__c,
                   ProceduralFixedEmailIds__c, ReprocessingFixedEmailIds__c,
                   CaseTeamMember__c, ToExternal__c, CCExternal__c,
                   EmailType__c, DeveloperName
            FROM EmailConditionsConfiguration__mdt
            WHERE EmailType__c = :c.EmailType__c               
            LIMIT 1
        ];
        if (!cfgs.isEmpty()) {
            config = cfgs[0];
        } else {
            throw new AuraHandledException('Email Conditions Configuration for Go/No-Go not found. Ensure a record exists (EmailType__c or DeveloperName=GoNoGo).');
        }

        // --- 3) Prepare working sets ---
        Set<String> toAddresses = new Set<String>();
        Set<String> ccAddresses = new Set<String>();

        Set<String> toRoles = new Set<String>();
        Set<String> ccRoles = new Set<String>();
        Set<String> caseTeamRolesConfig = new Set<String>();

        // Helper to split CSV/semicolon strings into Sets
        // (local lambda-style helpers using inline loops)
        if (String.isNotBlank(config.CaseTeamMember__c)) {
            for (String role : config.CaseTeamMember__c.split('[,;]')) {
                if (String.isNotBlank(role)) caseTeamRolesConfig.add(role.trim());
            }
        }
        if (String.isNotBlank(config.ToInternal__c)) {
            for (String role : config.ToInternal__c.split('[,;]')) {
                if (String.isNotBlank(role)) toRoles.add(role.trim());
            }
        }
        if (String.isNotBlank(config.CCInternal__c)) {
            for (String role : config.CCInternal__c.split('[,;]')) {
                if (String.isNotBlank(role)) ccRoles.add(role.trim());
            }
        }

        // --- 4) Bring in OrderLine contacts (Sales role emails) ---
        // This matches your SOA logic
        List<OrderLineContact__c> olContacts = new List<OrderLineContact__c>();
        if (c.Order__c != null) {
            olContacts = [
                SELECT SalesRep__r.Email, RSD__r.Email, AVP__r.Email, PDM__r.Email, SDS__r.Email,
                       OrderLine__r.OrderLineType__c,OrderLine__r.CreateSubcase__c
                FROM OrderLineContact__c
                WHERE OrderLine__r.OrderId = :c.Order__c
            ];
        }

        for (OrderLineContact__c olc : olContacts) {
            String lineType = olc.OrderLine__r.OrderLineType__c;
            String createSub = olc.OrderLine__r.CreateSubcase__c;
            
            // Apply the same business logic as SOA for internal roles
            // 1) Sales Rep routing
            if (toRoles.contains('Service Line Sales Rep') && lineType == 'Service – Installation') {
                if (olc.SalesRep__r != null && String.isNotBlank(olc.SalesRep__r.Email))
                    toAddresses.add(olc.SalesRep__r.Email.trim());
            } else {
                if (toRoles.contains('Capital Line Sales Rep') && createSub== 'yes - Capital line' && olc.SalesRep__r != null && String.isNotBlank(olc.SalesRep__r.Email)) {
                    toAddresses.add(olc.SalesRep__r.Email.trim());
                }
            }
            // 2) Other internal roles to CC
            if (ccRoles.contains('RSD') && olc.RSD__r != null && String.isNotBlank(olc.RSD__r.Email)) ccAddresses.add(olc.RSD__r.Email.trim());
            if (ccRoles.contains('AVP') && olc.AVP__r != null && String.isNotBlank(olc.AVP__r.Email)) ccAddresses.add(olc.AVP__r.Email.trim());
            if (ccRoles.contains('PDM') && olc.PDM__r != null && String.isNotBlank(olc.PDM__r.Email)) ccAddresses.add(olc.PDM__r.Email.trim());
            if (ccRoles.contains('SDS') && olc.SDS__r != null && String.isNotBlank(olc.SDS__r.Email)) ccAddresses.add(olc.SDS__r.Email.trim());

            // 3) Fixed emails by line type -> CC
            if (lineType == 'GI Reprocessing' && String.isNotBlank(config.GIReprocessingFixedEmailIds__c)) {
                for (String email : config.GIReprocessingFixedEmailIds__c.split('[,;]')) {
                    if (String.isNotBlank(email)) ccAddresses.add(email.trim());
                }
            }
            if (lineType == 'Procedural' && String.isNotBlank(config.ProceduralFixedEmailIds__c)) {
                for (String email : config.ProceduralFixedEmailIds__c.split('[,;]')) {
                    if (String.isNotBlank(email)) ccAddresses.add(email.trim());
                }
            }
            if (lineType == 'Reprocessing' && String.isNotBlank(config.ReprocessingFixedEmailIds__c)) {
                for (String email : config.ReprocessingFixedEmailIds__c.split('[,;]')) {
                    if (String.isNotBlank(email)) ccAddresses.add(email.trim());
                }
            }
        }

        // --- 5) Case Team Members based on configured roles -> CC ---
        if (!caseTeamRolesConfig.isEmpty()) {
            List<CaseTeamMember> teamMembers = [
                SELECT TeamRole.Name, ParentId, Member.Email, MemberId
                FROM CaseTeamMember
                WHERE ParentId = :c.Id
            ];
            for (CaseTeamMember member : teamMembers) {
                String roleName = (member.TeamRole != null) ? member.TeamRole.Name : null;
                String mEmail   = (member.Member != null)   ? member.Member.Email  : null;
                if (String.isNotBlank(roleName) && caseTeamRolesConfig.contains(roleName) && String.isNotBlank(mEmail)) {
                    ccAddresses.add(mEmail.trim());
                }
            }
        }

        

        // --- 7) Apply to the Lightning Email Composer defaults ---
        EmailMessage emailMessage = (EmailMessage) sendEmailDefaults.getTargetSObject();
        emailMessage.ToAddress  = (toAddresses.isEmpty() ? '' : String.join(new List<String>(toAddresses), ';'));
        emailMessage.CcAddress  = (ccAddresses.isEmpty() ? '' : String.join(new List<String>(ccAddresses), ';'));
        emailMessage.BccAddress = '';

    } catch (Exception ex) {
        // Keep your existing structured logging
        ErrorLogger.logException(ex, 'EmailAddressDefaultController', 'defaultGoNoGoEmailAddresses');
        throw ex;
    }
}
    
}