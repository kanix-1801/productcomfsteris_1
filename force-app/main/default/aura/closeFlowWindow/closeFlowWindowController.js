({
    invoke : function(component, event, helper) {
        var recordId = component.get("v.recordId");
        var workspaceAPI = component.find("workspace");
        if (!workspaceAPI) {
            helper.goToRecord(recordId);
            return;
        }
        workspaceAPI.isConsoleNavigation().then(function(isConsole) {
            if (!isConsole) {
                helper.goToRecord(recordId);
                return;
            }
            workspaceAPI.getFocusedTabInfo().then(function(response) {
                workspaceAPI.closeTab({ tabId: response.tabId });
            }).catch(function() {
                helper.goToRecord(recordId);
            });
        }).catch(function() {
            helper.goToRecord(recordId);
        });
    }
})