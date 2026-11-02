import { LightningElement, api } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import PIPELINE_ICON from '@salesforce/resourceUrl/DealerPipelineIcon';
import ACTIVE_ICON from '@salesforce/resourceUrl/DealerActiveIcon';
import getHome from '@salesforce/apex/DealerOpportunityController.getHome';

const STAGE_BAR = {
    Evaluation: 'bar-fill bar-gold',
    Proposal: 'bar-fill bar-green',
    Commit: 'bar-fill bar-orange'
};

export default class DealerPortalHome extends NavigationMixin(LightningElement) {
    @api opportunitiesPageApiName = 'My_Opportunities';
    pipelineIconUrl = PIPELINE_ICON;
    activeIconUrl = ACTIVE_ICON;
    home;
    errorMessage;
    isCreateOpen = false;

    connectedCallback() {
        this.loadHome();
    }

    loadHome() {
        getHome()
            .then((home) => {
                this.home = home;
                this.errorMessage = null;
            })
            .catch((error) => {
                this.errorMessage = error?.body?.message || 'Unable to load the dealer home page.';
            });
    }

    get summary() {
        return this.home?.summary || {};
    }

    get openPipelineLabel() {
        return compactCurrency(this.summary.openPipelineValue);
    }

    get openCountLabel() {
        return String(this.summary.openCount || 0);
    }

    get closedWonLabel() {
        return compactCurrency(this.summary.closedWonValue);
    }

    get closedWonCountLabel() {
        return `${this.summary.closedWonCount || 0} won`;
    }

    get recentOpportunities() {
        return this.home?.recentOpportunities || [];
    }

    get pastDueOpportunities() {
        return this.home?.pastDueOpportunities || [];
    }

    get hasStageChart() {
        return this.stageBars.length > 0;
    }

    get hasQuarterChart() {
        return this.quarterBars.length > 0;
    }

    get hasCountryChart() {
        return this.countryBars.length > 0;
    }

    get stageBars() {
        return toBars(this.home?.stageChart, (item) => item.amount, (item) => ({
            stageName: item.stageName,
            className: STAGE_BAR[item.stageName] || 'bar-fill bar-blue',
            valueLabel: compactCurrency(item.amount)
        }));
    }

    get quarterBars() {
        return toBars(this.home?.quarterChart, (item) => item.value, (item) => ({
            label: item.label,
            valueLabel: compactCurrency(item.value)
        }));
    }

    get countryBars() {
        return toBars(this.home?.countryChart, (item) => item.value, (item) => ({
            label: item.label,
            valueLabel: compactCurrency(item.value)
        }));
    }

    openCreate() {
        this.isCreateOpen = true;
    }

    closeCreate() {
        this.isCreateOpen = false;
    }

    handleCreated() {
        this.isCreateOpen = false;
        this.loadHome();
    }

    viewOpportunities() {
        this.openOpportunityPage(false);
    }

    viewAllPastDue() {
        this.openOpportunityPage(true);
    }

    openOpportunityPage(pastDue) {
        this[NavigationMixin.Navigate]({
            type: 'comm__namedPage',
            attributes: { name: this.opportunitiesPageApiName },
            state: pastDue ? { pastDue: 'true' } : {}
        });
    }
}

function toBars(items, valueOf, mapItem) {
    const source = items || [];
    const maxValue = source.reduce((max, item) => Math.max(max, Number(valueOf(item)) || 0), 0);
    return source
        .filter((item) => Number(valueOf(item)) > 0)
        .map((item) => {
            const width = maxValue === 0 ? 0 : Math.max(8, Math.round((Number(valueOf(item)) / maxValue) * 100));
            return {
                ...mapItem(item),
                style: `width:${width}%`
            };
        });
}

function compactCurrency(amount) {
    const value = Number(amount || 0);
    if (Math.abs(value) >= 1000) {
        const thousands = value / 1000;
        const digits = Math.abs(thousands) >= 10 ? 0 : 1;
        return `$${thousands.toFixed(digits).replace(/\.0$/, '')}K`;
    }
    return new Intl.NumberFormat('en-US', {
        style: 'currency',
        currency: 'USD',
        maximumFractionDigits: 0
    }).format(value);
}