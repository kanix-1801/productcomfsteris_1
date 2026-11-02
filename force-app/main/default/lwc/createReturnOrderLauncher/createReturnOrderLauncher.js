import { LightningElement } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';

const CREATE_RETURN_ORDER_TAB_API = 'Create_Return_Order';

export default class CreateReturnOrderLauncher extends NavigationMixin(LightningElement) {
    handleLaunch() {
        this[NavigationMixin.Navigate]({
            type: 'standard__navItemPage',
            attributes: {
                apiName: CREATE_RETURN_ORDER_TAB_API
            }
        });
    }
}