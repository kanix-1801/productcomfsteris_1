import { LightningElement, api } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import basePath from '@salesforce/community/basePath';
import PIPELINE_ICON from '@salesforce/resourceUrl/DealerPipelineIcon';
import ACTIVE_ICON from '@salesforce/resourceUrl/DealerActiveIcon';
import getHome from '@salesforce/apex/DealerOpportunityController.getHome';

const STAGE_COLOR = {
    Discovery: '#3d92cf',
    Evaluation: '#2f8f62',
    Proposal: '#2cb5be',
    Commit: '#e8882f'
};
const UNIT_COLORS = ['#f59e0b', '#3b82f6', '#14b8a6', '#8b5cf6', '#22c55e', '#fb923c'];
const COLUMN_COLOR = '#2f89e6';

export default class DealerPortalHome extends NavigationMixin(LightningElement) {
    @api opportunitiesPageApiName = 'My_Opportunities__c';
    pipelineIconUrl = PIPELINE_ICON;
    activeIconUrl = ACTIVE_ICON;
    home;
    errorMessage;
    isFlowOpen = false;

    get keepPickerInSiteBundle() {
        return false;
    }

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

    get stageCountCards() {
        const counts = new Map((this.summary.stages || []).map((stage) => [stage.stageName, stage.recordCount || 0]));
        return [
            { stageName: 'Evaluation', mark: '#', iconClass: 'metric-icon metric-evaluation' },
            { stageName: 'Proposal', mark: '#', iconClass: 'metric-icon metric-proposal' },
            { stageName: 'Commit', mark: '#', iconClass: 'metric-icon metric-commit' }
        ].map((card) => ({
            ...card,
            label: `${card.stageName} Opportunities`,
            count: String(counts.get(card.stageName) || 0)
        }));
    }

    get recentOpportunities() {
        return this.home?.recentOpportunities || [];
    }

    get pastDueOpportunities() {
        return this.home?.pastDueOpportunities || [];
    }

    get hasStageChart() {
        return this.stageFunnel.length > 0;
    }

    get hasQuarterChart() {
        return this.quarterColumns.length > 0;
    }

    get hasBusinessUnitChart() {
        return this.businessUnitBars.length > 0;
    }

    get stageFunnel() {
        const stages = (this.home?.stageChart || []).filter((item) => Number(item.amount) > 0);
        const total = stages.reduce((sum, item) => sum + Number(item.amount || 0), 0);
        return stages.map((item, index) => {
            const amount = Number(item.amount || 0);
            const color = STAGE_COLOR[item.stageName] || '#3d92cf';
            const percent = total === 0 ? 0 : (amount / total) * 100;
            return {
                stageName: item.stageName,
                valueLabel: `${compactCurrency(amount)} (${percent.toFixed(2)}%)`,
                style: funnelStyle(index, stages.length, color),
                swatchStyle: `background:${color}`
            };
        });
    }

    get stageTotalLabel() {
        const total = (this.home?.stageChart || []).reduce((sum, item) => sum + Number(item.amount || 0), 0);
        return compactCurrency(total);
    }

    get quarterColumns() {
        const points = (this.home?.quarterChart || []).filter((item) => Number(item.value) > 0);
        const axisMax = this.quarterAxisMax;
        return points.map((item) => {
            const value = Number(item.value) || 0;
            const height = axisMax === 0 ? 0 : Math.max(2, (value / axisMax) * 100);
            return {
                label: item.label,
                valueLabel: compactCurrency(value),
                style: `height:${height}%;background:${COLUMN_COLOR}`
            };
        });
    }

    get quarterAxis() {
        const axisMax = this.quarterAxisMax;
        return [1, 0.75, 0.5, 0.25, 0].map((ratio) => ({
            key: String(ratio),
            label: ratio === 0 ? '$0' : compactCurrency(axisMax * ratio)
        }));
    }

    get quarterAxisMax() {
        const maxValue = (this.home?.quarterChart || []).reduce(
            (max, item) => Math.max(max, Number(item.value) || 0),
            0
        );
        return niceAxisMax(maxValue);
    }

    get businessUnitBars() {
        const source = (this.home?.businessUnitChart || []).filter((item) => Number(item.value) > 0);
        const maxValue = source.reduce((max, item) => Math.max(max, Number(item.value) || 0), 0);
        return source.map((item, index) => {
            const value = Number(item.value) || 0;
            const width = maxValue === 0 ? 0 : Math.max(8, Math.round((value / maxValue) * 100));
            return {
                label: item.label,
                valueLabel: compactCurrency(value),
                style: `width:${width}%;background:${UNIT_COLORS[index % UNIT_COLORS.length]}`
            };
        });
    }

    openCreateFlow() {
        this.isFlowOpen = true;
    }

    closeCreateFlow() {
        this.isFlowOpen = false;
    }

    stopFlowClose(event) {
        event.stopPropagation();
    }

    handleFlowStatusChange(event) {
        const status = event.detail && event.detail.status;
        if (status !== 'FINISHED' && status !== 'FINISHED_SCREEN') {
            return;
        }
        const recordId = outputValue(event.detail, 'createdOpportunityId');
        this.isFlowOpen = false;
        if (!recordId) {
            this.loadHome();
            return;
        }
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId,
                objectApiName: 'Opportunity',
                actionName: 'view'
            }
        });
    }

    openOpportunityPage(event) {
        const query = event.currentTarget.dataset.pastDue === 'true' ? '?pastDue=true' : '';
        this[NavigationMixin.Navigate]({
            type: 'standard__webPage',
            attributes: {
                url: `${basePath}/my-opportunities${query}`
            }
        });
    }
}

function outputValue(detail, name) {
    const outputs = detail && detail.outputVariables;
    if (!outputs) {
        return null;
    }
    const match = outputs.find((item) => item.name === name);
    return match && match.value ? match.value : null;
}

function funnelStyle(index, count, color) {
    const taper = count <= 1 ? 18 : 42;
    const step = taper / Math.max(count, 1);
    const top = count <= 1 ? 6 : index * step;
    const bottom = count <= 1 ? 18 : (index + 1) * step;
    return `--top:${top}%;--bottom:${bottom}%;background:${color}`;
}

function niceAxisMax(value) {
    if (value <= 0) {
        return 1;
    }
    const exponent = Math.pow(10, Math.floor(Math.log10(value)));
    const fraction = value / exponent;
    let nice = 10;
    if (fraction <= 1) {
        nice = 1;
    } else if (fraction <= 2) {
        nice = 2;
    } else if (fraction <= 2.5) {
        nice = 2.5;
    } else if (fraction <= 5) {
        nice = 5;
    }
    return nice * exponent;
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