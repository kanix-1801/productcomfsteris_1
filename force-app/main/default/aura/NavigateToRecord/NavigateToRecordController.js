({
    invoke : function(component, event, helper) {
        var navService = component.find("navService");
        var recordId = component.get("v.recordId");

        var pageReference = {
            type: 'standard__recordPage',
            attributes: {
                recordId: recordId,
                actionName: 'view'
            }
        };

        navService.navigate(pageReference);
    }
})