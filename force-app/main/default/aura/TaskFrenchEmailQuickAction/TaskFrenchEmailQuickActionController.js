({
    doInit: function(cmp) {
        var dismissActionPanel = $A.get("e.force:closeQuickAction");
        dismissActionPanel.fire();
    },

    handleComplete: function(component, event, helper) {
        var quickActionAPI = component.find("quickActionAPI");
        if (quickActionAPI && quickActionAPI.closeQuickAction) {
            try { quickActionAPI.closeQuickAction(); } catch (e) {}
        }

        // Get Case Id from event detail
        var caseId = event.getParam("caseId");
        if (!caseId) {
            console.error("No Case Id passed from LWC");
            return;
        }

        // Navigate to Case record Collaboration tab
        var navService = component.find("navService");
        var pageRef = {
            type: "standard__recordPage",
            attributes: {
                recordId: caseId,
                objectApiName: "Case",
                actionName: "view"
            },
            state: {
                tab: "Collaboration" // replace with actual DeveloperName of your tab
            }
        };
        navService.navigate(pageRef);
    
        window.setTimeout(function() {
            const refreshEvent = $A.get('e.force:refreshView');
            if (refreshEvent) {
                refreshEvent.fire();
            }
        }, 600);
       
    }
})