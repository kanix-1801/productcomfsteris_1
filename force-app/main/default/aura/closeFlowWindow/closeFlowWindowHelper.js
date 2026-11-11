({
    goToRecord : function(recordId) {
        if (recordId) {
            window.open("/lightning/r/" + recordId + "/view", "_self");
        }
    }
})