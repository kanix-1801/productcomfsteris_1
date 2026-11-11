({
    handleAccess: function (component, event) {
        var detail = event.getParam('detail') || {};
        component.set('v.accountId', detail.recordId);
        component.set('v.accessLevel', detail.accessLevel === 'Base' ? 'Base' : 'Full');
    }
})