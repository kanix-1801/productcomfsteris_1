// Launch tile in the style of the Price Management "Pricing Spotlight" tiles.
// Place it on the Price Management Home page (Lightning App Builder); clicking it opens the target tab.
import { LightningElement, api } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';

export default class PricingLaunchTile extends NavigationMixin(LightningElement) {
    @api tileTitle = 'Pricing Programs';
    @api tileDescription = 'Create and maintain pricing programs, Mobile Van programs and inclusion rules.';
    @api tabApiName = 'Pricing_Programs';
    @api iconName = 'standard:pricebook';
    @api matchSpotlight = false;   // true = light-blue band like the Pricing Spotlight panel

    get bandClass() {
        return this.matchSpotlight ? 'band spotlight' : 'band';
    }

    handleOpen() {
        this[NavigationMixin.Navigate]({
            type: 'standard__navItemPage',
            attributes: { apiName: this.tabApiName }
        });
    }
}