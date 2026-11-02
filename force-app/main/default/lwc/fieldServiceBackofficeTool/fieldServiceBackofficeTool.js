import { LightningElement } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';

export default class FieldServiceBackofficeTool extends NavigationMixin(LightningElement) {
    handleNavigate(event) {
        const apiName = event.target.dataset.tab;
        if (!apiName) {
            return;
        }
        this[NavigationMixin.Navigate]({
            type: 'standard__navItemPage',
            attributes: {
                apiName
            }
        });
    }
}