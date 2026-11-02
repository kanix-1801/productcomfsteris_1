({
    doInit: function (component) {
        var pageReference = component.get("v.pageReference");
        var recordTypeId = pageReference && pageReference.state
            ? pageReference.state.recordTypeId
            : null;
        component.set("v.recordTypeId", recordTypeId);
    }
})