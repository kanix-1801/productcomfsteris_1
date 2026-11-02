/**
 * @author PSL
 * @date 11-20-2025
 * @description Handles assignment of case team members based on order information and assignment rules
 */
public with sharing class CaseAssignmentHandler {

    // Centralized role labels to avoid hardcoding throughout the class
    private static final Map<String, String> ROLE_LABELS = new Map<String, String>{
        'OM_USER' => 'OM User',
        'OM_MANAGER' => 'OM Manager',
        'BL_USER' => 'BL User',
        'BL_MANAGER' => 'BL Manager',
        'LOGISTICS_USER' => 'Logistics User',
        'LOGISTICS_MANAGER' => 'Logistics Manager'
    };

    /**
     * @description Assign case team members based on:
     * - Legacy: Order.BookedBy__c or DefaultEmployeeNumber label (OM User/OM Manager)
     * - New: CaseAssignmentRule__mdt matching TurnsProject__c, SalesChannel__c, and RegionName__c via single SOQL on OrderLineContact__c
     *
     * Role mapping by CMDT.DeveloperName:
     * - contains 'BacklogRule' => 'BL User' and 'BL Manager'
     * - contains 'LogisticsRule' => 'Logistics User' and 'Logistics Manager'
     * CMDT.User__c stores employee number of base user to add (manager auto-added).
     *
     * NEW: If OrderClassification__c == 'RMA' or 'No Charge' (case-insensitive), skip adding legacy OM User & OM Manager.
     * @param newCases List of Case records to assign team members to
     */
    public static void assignTeamMembers(List<Case> newCases) {
        try {
            if (newCases == null || newCases.isEmpty()) {
                return;
            }

            // Only those cases that reference an Order
            List<Case> targetCases = new List<Case>();
            // Collect Order Ids
            Set<Id> orderIds = new Set<Id>();
            // Build CaseId -> OrderId map
            Map<Id, Id> caseIdToOrderId = new Map<Id, Id>();
            for (Case c : newCases) {
                if (c.Order__c != null) {
                    targetCases.add(c);
                    orderIds.add(c.Order__c);
                    caseIdToOrderId.put(c.Id, c.Order__c);
                }
            }
            if (targetCases.isEmpty()) {
                return;
            }

            // Single SOQL via OrderLineContact__c to fetch RegionName__c and Order fields (TurnsProject__c, SalesChannel__c, BookedBy__c, OrderClassification__c)
            Map<Id, Set<String>> orderIdToRegions = new Map<Id, Set<String>>();
            Map<Id, OrderWrapper> ordersByIdLite = new Map<Id, OrderWrapper>();
            if (!orderIds.isEmpty()) {
                for (OrderLineContact__c olc : [
                    SELECT Id,
                           RegionName__c,
                           OrderLine__r.OrderId,
                           OrderLine__r.Order.TurnsProject__c,
                           OrderLine__r.Order.SalesChannel__c,
                           OrderLine__r.Order.BookedBy__c,
                           OrderLine__r.Order.OrderClassification__c
                    FROM OrderLineContact__c
                    WHERE OrderLine__r.OrderId IN :orderIds
                ]) {
                    Id ordId = (olc.OrderLine__r != null) ? olc.OrderLine__r.OrderId : null;
                    if (ordId == null) continue;

                    // Regions
                    if (String.isNotBlank(olc.RegionName__c)) {
                        Set<String> regs = orderIdToRegions.get(ordId);
                        if (regs == null) {
                            regs = new Set<String>();
                            orderIdToRegions.put(ordId, regs);
                        }
                        regs.add(normalizeToken(olc.RegionName__c));
                    }

                    // Order fields (first non-null wins)
                    OrderWrapper ow = ordersByIdLite.get(ordId);
                    if (ow == null) {
                        ow = new OrderWrapper();
                        ordersByIdLite.put(ordId, ow);
                    }
                    if (olc.OrderLine__r.Order != null) {
                        if (ow.turnVsProject == null)
                            ow.turnVsProject = normalizeToken(olc.OrderLine__r.Order.TurnsProject__c);
                        if (ow.salesChannel == null)
                            ow.salesChannel = normalizeToken(olc.OrderLine__r.Order.SalesChannel__c);
                        if (ow.srcSysCreatedBy == null)
                            ow.srcSysCreatedBy = olc.OrderLine__r.Order.BookedBy__c;

                        // NEW: capture Order_Classification for RMA or No Charge check
                        if (ow.orderClassification == null)
                            ow.orderClassification = normalizeToken(olc.OrderLine__r.Order.OrderClassification__c);
                    }
                }
            }

            // Legacy still needs BookedBy__c. If not populated from OLC, fallback to direct Order query.
            Set<Id> ordersNeedingSrc = new Set<Id>();
            Set<Id> ordersNeedingOrderClass = new Set<Id>(); // NEW
            for (Id oid : orderIds) {
                OrderWrapper ow = ordersByIdLite.get(oid);
                if (ow == null) { ow = new OrderWrapper(); ordersByIdLite.put(oid, ow); }
                if (ow.srcSysCreatedBy == null)      ordersNeedingSrc.add(oid);
                if (ow.orderClassification == null) ordersNeedingOrderClass.add(oid);
            }

            if (!ordersNeedingSrc.isEmpty() || !ordersNeedingOrderClass.isEmpty()) {
                Set<Id> neededOrders = new Set<Id>();
                neededOrders.addAll(ordersNeedingSrc);
                neededOrders.addAll(ordersNeedingOrderClass);

                for (Order o : [
                    SELECT Id,
                           BookedBy__c,
                           OrderClassification__c
                    FROM Order
                    WHERE Id IN :neededOrders
                ]) {
                    OrderWrapper ow = ordersByIdLite.get(o.Id);
                    if (ow == null) { ow = new OrderWrapper(); ordersByIdLite.put(o.Id, ow); }
                    if (ow.srcSysCreatedBy == null)
                        ow.srcSysCreatedBy = o.BookedBy__c;
                    if (ow.orderClassification == null)
                        ow.orderClassification = normalizeToken(o.OrderClassification__c);
                }
            }

            // Determine employee number key for each Case
            String defaultEmp = System.Label.DefaultEmployeeNumber;
            Map<Id, String> caseIdToEmpNumber = new Map<Id, String>();
            Set<String> employeeNumbers = new Set<String>();
            employeeNumbers.add(defaultEmp.trim()); //To add default employee number always, so can be used in fall through.
            for (Case c : targetCases) {
                OrderWrapper ow = ordersByIdLite.get(c.Order__c);
                String keyEmp = (ow != null && String.isNotBlank(ow.srcSysCreatedBy))
                    ? ow.srcSysCreatedBy
                    : defaultEmp;
                if (String.isNotBlank(keyEmp)) {
                    keyEmp = keyEmp.trim();
                    caseIdToEmpNumber.put(c.Id, keyEmp);
                    employeeNumbers.add(keyEmp);
                }
            }

            // Find users by EmployeeNumber__c (active only) and their managers
            Map<String, User> userByEmp = new Map<String, User>();
            for (User u : [
                SELECT Id, ManagerId, EmployeeNumber__c
                FROM User
                WHERE EmployeeNumber__c IN :employeeNumbers
                AND IsActive = true
            ]) {
                if (String.isNotBlank(u.EmployeeNumber__c) && !userByEmp.containsKey(u.EmployeeNumber__c)) {
                    userByEmp.put(u.EmployeeNumber__c, u);
                }
            }
            
            /*if (userByEmp.isEmpty()) {
                return;
            }*/ //Commented as RMA cases will not have any OM user and manager.

            // Collect manager Ids
            Set<Id> managerIds = new Set<Id>();
            for (User u : userByEmp.values()) {
                if (u.ManagerId != null) {
                    managerIds.add(u.ManagerId);
                }
            }

            // Query active managers
            Map<Id, User> managersById = new Map<Id, User>();
            if (!managerIds.isEmpty()) {
                for (User m : [
                    SELECT Id
                    FROM User
                    WHERE Id IN :managerIds
                    AND IsActive = true
                ]) {
                    managersById.put(m.Id, m);
                }
            }

            // Resolve Case Team Roles (legacy + new)
            Set<String> roleNames = new Set<String>(ROLE_LABELS.values());
            Map<String, Id> roleNameToId = new Map<String, Id>();
            for (CaseTeamRole ctr : [
                SELECT Id, Name
                FROM CaseTeamRole
                WHERE Name IN :roleNames
            ]) {
                roleNameToId.put(ctr.Name, ctr.Id);
            }
            Id omUserRoleId = roleNameToId.get(ROLE_LABELS.get('OM_USER'));
            Id omManagerRoleId = roleNameToId.get(ROLE_LABELS.get('OM_MANAGER'));

            // Existing team members for dedupe
            Set<Id> caseIds = new Set<Id>(caseIdToEmpNumber.keySet());
            Map<Id, Set<Id>> existingMembersByCase = new Map<Id, Set<Id>>();
            // New: also track existing roles per case to avoid adding multiple users with the same role
            Map<Id, Set<Id>> existingRolesByCase = new Map<Id, Set<Id>>();
            if (!caseIds.isEmpty()) {
                for (CaseTeamMember ctm : [
                    SELECT Id, ParentId, MemberId, TeamRoleId
                    FROM CaseTeamMember
                    WHERE ParentId IN :caseIds
                ]) {
                    // Track existing members
                    Set<Id> members = existingMembersByCase.get(ctm.ParentId);
                    if (members == null) {
                        members = new Set<Id>();
                        existingMembersByCase.put(ctm.ParentId, members);
                    }
                    members.add(ctm.MemberId);

                    // Track existing roles
                    if (ctm.TeamRoleId != null) {
                        Set<Id> roles = existingRolesByCase.get(ctm.ParentId);
                        if (roles == null) {
                            roles = new Set<Id>();
                            roles.add(ctm.TeamRoleId);
                            existingRolesByCase.put(ctm.ParentId, roles);
                        }
                    }
                }
            }

            // Pre-load CMDT Active rules and referenced users (by Email as per feedback)
            List<CaseAssignmentRule__mdt> allRules = [
                SELECT DeveloperName, IsProject__c, SalesChannelList__c, SalesRegionList__c, MatchType__c, User__c
                FROM CaseAssignmentRule__mdt
                WHERE IsActive__c = true ORDER BY MatchType__c
            ];
            Set<String> cmdtEmpNums = new Set<String>();
            for (CaseAssignmentRule__mdt r : allRules) {
                if (String.isNotBlank(r.User__c)) {
                    cmdtEmpNums.add(r.User__c.trim());
                }
            }

            // Resolve active users by Email
            Map<String, User> userByEmpNum = new Map<String, User>();
            if (!cmdtEmpNums.isEmpty()) {
                for (User u2 : [
                    SELECT Id, ManagerId, Email, IsActive
                    FROM User
                    WHERE IsActive = true AND Email IN :cmdtEmpNums
                ]) {
                    if (String.isNotBlank(u2.Email) && !userByEmpNum.containsKey(u2.Email)) {
                        userByEmpNum.put(u2.Email, u2);
                    }
                }
            }

            // ensure managers for those users are available in managersById
            Set<Id> extraMgr = new Set<Id>();
            for (User u3 : userByEmpNum.values()) if (u3.ManagerId != null) extraMgr.add(u3.ManagerId);
            if (!extraMgr.isEmpty()) {
                for (User m2 : [
                    SELECT Id, IsActive
                    FROM User
                    WHERE IsActive = true AND Id IN :extraMgr
                ]) {
                    managersById.put(m2.Id, m2);
                }
            }

            // Build CTMs to insert (legacy + new)
            List<CaseTeamMember> toInsert = new List<CaseTeamMember>();
            for (Id caseId : caseIds) {
                String emp = caseIdToEmpNumber.get(caseId);
                //User targetUser = userByEmp.get(emp);
                User targetUser = userByEmp.get(emp) != null ? userByEmp.get(emp) : userByEmp.get(defaultEmp.trim());
                Set<Id> existingForCase = existingMembersByCase.containsKey(caseId)
                    ? existingMembersByCase.get(caseId)
                    : new Set<Id>();
                // Track existing roles for this case (for role-level dedupe)
                Set<Id> existingRolesForCase = existingRolesByCase.containsKey(caseId)
                    ? existingRolesByCase.get(caseId)
                    : new Set<Id>();

                // skip for OM roles based on  OrderClassification__c== 'RMA' or 'No Charge'
                Id ordId = caseIdToOrderId.get(caseId);
                OrderWrapper ow = ordId != null ? ordersByIdLite.get(ordId) : null;
                Boolean skipRmaMembers = isRma(ow != null ? ow.orderClassification : null);
                if(isNoCharge(ow != null ? ow.orderClassification : null)){
                    targetUser = userByEmp.get(defaultEmp.trim());
                }
                // Legacy members — now guarded by RMA or No Charge check
                if (!skipRmaMembers && targetUser != null) {
                    if (!existingForCase.contains(targetUser.Id)) {
                        CaseTeamMember userCtm = new CaseTeamMember();
                        userCtm.ParentId = caseId;
                        userCtm.MemberId = targetUser.Id;
                        if (omUserRoleId != null) userCtm.TeamRoleId = omUserRoleId;
                        toInsert.add(userCtm);
                        existingForCase.add(targetUser.Id);
                    }
                    if (targetUser.ManagerId != null) {
                        User mgr = managersById.get(targetUser.ManagerId);
                        if (mgr != null && !existingForCase.contains(mgr.Id)) {
                            CaseTeamMember mgrCtm = new CaseTeamMember();
                            mgrCtm.ParentId = caseId;
                            mgrCtm.MemberId = mgr.Id;
                            if (omManagerRoleId != null) mgrCtm.TeamRoleId = omManagerRoleId;
                            toInsert.add(mgrCtm);
                            existingForCase.add(mgr.Id);
                        }
                    }
                }

                // New CMDT-driven members
                String orderClass = ow != null ? ow.turnVsProject : null; // Turns vs Projects
                String salesChannel = ow != null ? ow.salesChannel : null;
                Set<String> regions = orderIdToRegions.containsKey(ordId) ? orderIdToRegions.get(ordId) : new Set<String>();
                for (CaseAssignmentRule__mdt rule : allRules) {
                    if (!isRuleEligibleByProject(rule.IsProject__c, orderClass)) continue;
                    if (!matchesRule(rule.MatchType__c, salesChannel, regions, rule.SalesChannelList__c, rule.SalesRegionList__c)) continue;

                    // DeveloperName mapping -> role pair
                    String dn = rule.DeveloperName != null ? rule.DeveloperName.toLowerCase() : '';
                    String userRoleName;
                    String mgrRoleName;
                    if (dn.contains('backlogrule')) {
                        userRoleName = ROLE_LABELS.get('BL_USER'); mgrRoleName = ROLE_LABELS.get('BL_MANAGER');
                    } else if (dn.contains('logisticsrule')) {
                        userRoleName = ROLE_LABELS.get('LOGISTICS_USER'); mgrRoleName = ROLE_LABELS.get('LOGISTICS_MANAGER');
                    } else {
                        continue;
                    }

                    Id userRoleId = roleNameToId.get(userRoleName);
                    Id mgrRoleId = roleNameToId.get(mgrRoleName);

                    // Resolve base user by Email (User__c from CMDT stores Email)
                    String empKey = rule.User__c != null ? rule.User__c.trim() : null;
                    User baseUser = empKey != null ? userByEmpNum.get(empKey) : null;
                    if (baseUser == null) continue;

                    // Skip adding another user with the same role if role already present on this case
                    Boolean canAddRuleUser = (userRoleId == null) || !existingRolesForCase.contains(userRoleId);
                    if (canAddRuleUser && !existingForCase.contains(baseUser.Id)) {
                        CaseTeamMember ctm = new CaseTeamMember();
                        ctm.ParentId = caseId;
                        ctm.MemberId = baseUser.Id;
                        if (userRoleId != null) {
                            ctm.TeamRoleId = userRoleId;
                            existingRolesForCase.add(userRoleId);
                        }
                        toInsert.add(ctm);
                        existingForCase.add(baseUser.Id);
                    }

                    if (baseUser.ManagerId != null) {
                        User m = managersById.get(baseUser.ManagerId);
                        Boolean canAddRuleMgr = (mgrRoleId == null) || !existingRolesForCase.contains(mgrRoleId);
                        if (m != null && canAddRuleMgr && !existingForCase.contains(m.Id)) {
                            CaseTeamMember ctmM = new CaseTeamMember();
                            ctmM.ParentId = caseId;
                            ctmM.MemberId = m.Id;
                            if (mgrRoleId != null) {
                                ctmM.TeamRoleId = mgrRoleId;
                                existingRolesForCase.add(mgrRoleId);
                            }
                            toInsert.add(ctmM);
                            existingForCase.add(m.Id);
                        }
                    }
                }

                existingMembersByCase.put(caseId, existingForCase);
                existingRolesByCase.put(caseId, existingRolesForCase);
            }

            if (!toInsert.isEmpty()) {
                // Attempt to insert with partial success allowed
                Database.SaveResult[] saveResults = Database.insert(toInsert, false);
                for (Database.SaveResult sr : saveResults) {
                    if (!sr.isSuccess()) {
                        for (Database.Error err : sr.getErrors()) {
                            // Log the exception with recordId if available
                            ErrorLogger.logMessage(err.getMessage(), 'CaseAssignmentHandler', 'assignTeamMembers', ErrorLogger.Level.ERROR, null, null);
                        }
                    }
                }
            }
            
 
		defaultCaseMembers(caseIds);  
            

        } catch (Exception ex) {
            // Log the exception with recordId if available
            ErrorLogger.logException(ex, 'CaseAssignmentHandler', 'assignTeamMembers', ErrorLogger.Level.ERROR, null, null);
            // Re-throw the exception to maintain original behavior
            throw ex;
        }
    }

    // Single-record convenience overload
    public static void assignTeamMembers(Case c) {
        try {
            if (c == null) {
                return;
            }
            assignTeamMembers(new List<Case>{ c });
        } catch (Exception ex) {
            // Log the exception with recordId if available
            ErrorLogger.logException(ex, 'CaseAssignmentHandler', 'assignTeamMembers', ErrorLogger.Level.ERROR, c != null ? c.Id : null, null);
            // Re-throw the exception to maintain original behavior
            throw ex;
        }
    }

    // Helpers and wrapper
    private class OrderWrapper {
        String turnVsProject;   // Turns vs Projects (used for CMDT eligibility checks)
        String salesChannel;
        String srcSysCreatedBy;

        // NEW: actual Order_Classification (e.g., RMA) used to skip legacy OM roles
        String orderClassification;
    }

    @TestVisible
    private static Boolean isRuleEligibleByProject(String isProject, String turnVsProject) {
        String isProj = normalizeToken(isProject);
        String ord = normalizeToken(turnVsProject);
        if (isProj == 'not applicable') return true;
        if (ord == 'projects' && isProj == 'y') return true;
        if (ord == 'turns' && isProj == 'n') return true;
        return false;
    }

    @TestVisible
    private static Boolean matchesRule(String matchType, String salesChannel, Set<String> regions, String channelList, String regionList) {
        String mt = normalizeToken(matchType);
        Set<String> channelTokens = tokenizeCommaListToSet(channelList);
        Set<String> regionTokens = tokenizeCommaListToSet(regionList);

        Boolean channelMatch = (salesChannel != null && channelTokens.contains(salesChannel));
        Boolean regionMatch = false;
        if (!regions.isEmpty() && !regionTokens.isEmpty()) {
            for (String r : regions) { if (regionTokens.contains(r)) { regionMatch = true; break; } }
        }

        if (mt == 'saleschannelonly') return channelMatch;
        if (mt == 'salesregiononly') return regionMatch;
        return false;
    }

    @TestVisible
    private static Set<String> tokenizeCommaListToSet(String listText) {
        Set<String> out = new Set<String>();
        if (String.isBlank(listText)) return out;
        for (String t : listText.split(',')) {
            String n = normalizeToken(t);
            if (String.isNotBlank(n)) out.add(n);
        }
        return out;
    }

    @TestVisible
    private static String normalizeToken(String s) {
        if (String.isBlank(s)) return null;
        return s.trim().toLowerCase();
    }

    // NEW: small helper for RMA check (keeps null-safe comparisons clean)
    @TestVisible
    private static Boolean isRma(String classification) {
        return 'rma'.equals(normalizeToken(classification));
    }

    // NEW: small helper for No Charge check (keeps null-safe comparisons clean)
    @TestVisible
    private static Boolean isNoCharge(String classification) {
        return 'no charge'.equals(normalizeToken(classification));
    }
    
    
     /**
     * @description Assign case team members:
     * -New: assigning default OM,BL and Logistics user if none of these present
     * @param newCases List of Case records to assign team members to
     */
    
   public static void defaultCaseMembers(final Set<Id> caseIds) {
    if (caseIds == null || caseIds.isEmpty()) {
        return;
    }

    final Set<String> roleKeys = new Set<String>{ 'OM', 'BL', 'Logistics' };

    List<CBM_Generic_Configuration__mdt> cfgRows = [
        SELECT DeveloperName, Key__c
        FROM CBM_Generic_Configuration__mdt
        WHERE DeveloperName IN :roleKeys
    ];

    Map<String, String> roleKeyToUsername = new Map<String, String>();
    for (CBM_Generic_Configuration__mdt row : cfgRows) {
        if (!String.isBlank(row.DeveloperName)) {
            roleKeyToUsername.put(row.DeveloperName, row.Key__c);
        }
    }

    Map<String, String> roleKeyToExactUsername = new Map<String, String>();
    Map<String, String> roleKeyToLikePattern  = new Map<String, String>();
    Set<String> exactUsernames = new Set<String>();
    Set<String> likePatterns   = new Set<String>();

    for (String rk : roleKeys) {
        String uname = roleKeyToUsername.get(rk);
        if (!String.isBlank(uname)) {
            roleKeyToExactUsername.put(rk, uname);
            exactUsernames.add(uname);
            Integer idx = uname.toLowerCase().indexOf('.cbm');
            String base = (idx > -1) ? uname.substring(0, idx) : uname;
            if (!String.isBlank(base)) {
                String pattern = base + '.cbm%';
                roleKeyToLikePattern.put(rk, pattern);
                likePatterns.add(pattern);
            }
        }
    }

    Map<String, User> usernameToUser = new Map<String, User>();
    if (!exactUsernames.isEmpty()) {
        for (User u : [
            SELECT Id, Username, IsActive
            FROM User
            WHERE Username IN :exactUsernames
              AND IsActive = true
        ]) {
            if (u != null && !String.isBlank(u.Username)) {
                usernameToUser.put(u.Username, u);
            }
        }
    }

    List<User> likeMatchedUsers = new List<User>();
    if (!likePatterns.isEmpty()) {
        for (String pat : likePatterns) {
            if (!String.isBlank(pat)) {
                for (User u : [
                    SELECT Id, Username, IsActive
                    FROM User
                    WHERE Username LIKE :pat
                      AND IsActive = true
                ]) {
                    likeMatchedUsers.add(u);
                }
            }
        }
    }

    Map<String, Id> roleKeyToUserId = new Map<String, Id>();
    for (String rk : roleKeys) {
        String exact = roleKeyToExactUsername.get(rk);
        String likePat = roleKeyToLikePattern.get(rk);
        if (!String.isBlank(exact)) {
            User exactU = usernameToUser.get(exact);
            if (exactU != null) {
                roleKeyToUserId.put(rk, exactU.Id);
                continue;
            }
        }
        if (!String.isBlank(likePat)) {
            Integer idx = likePat.toLowerCase().indexOf('.cbm%');
            String base = (idx > -1) ? likePat.substring(0, idx) : null;
            if (!String.isBlank(base)) {
                String baseLower = base.toLowerCase();
                for (User cand : likeMatchedUsers) {
                    if (cand != null && !String.isBlank(cand.Username)) {
                        String unameLower = cand.Username.toLowerCase();
                        if (unameLower.startsWith(baseLower + '.cbm')) {
                            roleKeyToUserId.put(rk, cand.Id);
                            break;
                        }
                    }
                }
            }
        }
    }

    Map<String, String> roleKeyToUserRoleName = new Map<String, String>();
    roleKeyToUserRoleName.put('OM',        'OM User');
    roleKeyToUserRoleName.put('BL',        'BL User');
    roleKeyToUserRoleName.put('Logistics', 'Logistics User');

    Set<String> userRoleNames = new Set<String>();
    for (String rk : roleKeys) {
        String roleName = roleKeyToUserRoleName.get(rk);
        if (!String.isBlank(roleName)) {
            userRoleNames.add(roleName);
        }
    }

    Map<String, CaseTeamRole> nameToTeamRole = new Map<String, CaseTeamRole>();
    if (!userRoleNames.isEmpty()) {
        for (CaseTeamRole ctr : [
            SELECT Id, Name
            FROM CaseTeamRole
            WHERE Name IN :userRoleNames
        ]) {
            if (ctr != null && !String.isBlank(ctr.Name)) {
                nameToTeamRole.put(ctr.Name, ctr);
            }
        }
    }

    Map<String, Id> roleKeyToUserTeamRoleId = new Map<String, Id>();
    for (String rk : roleKeys) {
        String roleName = roleKeyToUserRoleName.get(rk);
        CaseTeamRole ctr = nameToTeamRole.get(roleName);
        if (ctr != null) {
            roleKeyToUserTeamRoleId.put(rk, ctr.Id);
        }
    }

    Set<Id> targetTeamRoleIds = new Set<Id>(roleKeyToUserTeamRoleId.values());

    List<CaseTeamMember> existing = new List<CaseTeamMember>();
    if (!targetTeamRoleIds.isEmpty()) {
        existing = [
            SELECT Id, ParentId, TeamRoleId, MemberId
            FROM CaseTeamMember
            WHERE ParentId IN :caseIds
              AND TeamRoleId IN :targetTeamRoleIds
        ];
    }

    Map<Id, Set<Id>> caseIdToPresentUserRoleIds = new Map<Id, Set<Id>>();
    for (CaseTeamMember ctm : existing) {
        if (!caseIdToPresentUserRoleIds.containsKey(ctm.ParentId)) {
            caseIdToPresentUserRoleIds.put(ctm.ParentId, new Set<Id>());
        }
        caseIdToPresentUserRoleIds.get(ctm.ParentId).add(ctm.TeamRoleId);
    }

    List<CaseTeamMember> toInsertNew = new List<CaseTeamMember>();
    for (Id caseId : caseIds) {
        Set<Id> present = caseIdToPresentUserRoleIds.get(caseId);
        if (present == null) {
            present = new Set<Id>();
        }
        for (String rk : roleKeys) {
            Id userId = roleKeyToUserId.get(rk);
            Id userRoleId = roleKeyToUserTeamRoleId.get(rk);
            if (userId != null && userRoleId != null) {
                if (!present.contains(userRoleId)) {
                    toInsertNew.add(new CaseTeamMember(
                        ParentId   = caseId,
                        MemberId   = userId,
                        TeamRoleId = userRoleId
                    ));
                    present.add(userRoleId);
                }
            }
        }
    }

    if (!toInsertNew.isEmpty()) {
        Database.insert(toInsertNew, false);
    }
}
}