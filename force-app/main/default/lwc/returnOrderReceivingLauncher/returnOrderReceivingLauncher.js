import { LightningElement } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';

const RETURN_ORDER_RECEIVING_TAB_API = 'Return_Order_Receiving';

export default class ReturnOrderReceivingLauncher extends NavigationMixin(LightningElement) {
    handleLaunch() {
        this[NavigationMixin.Navigate]({
            type: 'standard__navItemPage',
            attributes: {
                apiName: RETURN_ORDER_RECEIVING_TAB_API
            }
        });
    }
}