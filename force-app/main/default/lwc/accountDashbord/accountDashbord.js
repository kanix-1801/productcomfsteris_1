import { LightningElement, api } from 'lwc';

export default class AccountDashboard extends LightningElement {
    /** Set when hosted inside Customer 360 tabs (narrow panel, not full record page width). */
    @api embedded = false;

    @api recordId;

    get displayKpiCards() {
        return this.kpiCards.map((card) => {
            let footerLine2 = '\u00A0';
            let footerLine2Class = 'slds-text-body_small slds-text-color_weak';
            let showTrendIcon = false;

            if (card.subtext2) {
                footerLine2 = card.subtext2;
            } else if (card.showTrend) {
                footerLine2 = card.trend;
                footerLine2Class = 'slds-text-body_small slds-text-color_error slds-text-title_bold';
                showTrendIcon = true;
            }

            return {
                ...card,
                footerLine1: card.subtext || '\u00A0',
                footerLine1Class: card.subtext
                    ? card.subtextClass
                    : 'slds-text-body_small slds-text-color_weak',
                footerLine2,
                footerLine2Class,
                showTrendIcon
            };
        });
    }

    kpiCards = [
        {
            id: 'pipeline',
            label: 'PIPELINE',
            value: '$3.8M',
            subtext: 'Commit $1.1M',
            subtextClass: 'slds-text-body_small slds-text-color_weak',
            icon: 'standard:opportunity',
            iconThemeClass:
                'slds-icon_container slds-icon_container_circle slds-p-around_xx-small slds-theme_warning',
            showTrend: false
        },
        {
            id: 'activityHealth',
            label: 'ACTIVITY HEALTH',
            value: '82%',
            subtext: 'Healthy',
            subtextClass: 'slds-text-body_small slds-text-color_success',
            icon: 'standard:report',
            iconThemeClass:
                'slds-icon_container slds-icon_container_circle slds-p-around_xx-small slds-theme_offline',
            showTrend: false
        },
        {
            id: 'wonCy',
            label: 'WON (CY)',
            value: '$400k',
            subtext: 'vs PY $550K',
            subtextClass: 'slds-text-body_small slds-text-color_weak',
            icon: 'standard:reward',
            iconThemeClass:
                'slds-icon_container slds-icon_container_circle slds-p-around_xx-small slds-theme_success',
            trend: '-27% YoY',
            showTrend: true
        },
        {
            id: 'serviceCases',
            label: 'SERVICE CASES',
            value: '35',
            subtext: 'Active',
            subtext2: '15 Critical',
            subtextClass: 'slds-text-body_small slds-text-color_weak',
            icon: 'standard:case',
            iconThemeClass:
                'slds-icon_container slds-icon_container_circle slds-p-around_xx-small slds-theme_info',
            showTrend: false
        }
    ];

    appointments = [
        {
            id: '1',
            month: 'MAY',
            day: '21',
            title: 'SPD Equipment Review (Onsite Visit)'
        },
        {
            id: '2',
            month: 'MAY',
            day: '24',
            title: 'OR Integration Demo'
        },
        {
            id: '3',
            month: 'JUN',
            day: '06',
            title: 'Service Contract Follow-up'
        },
        {
            id: '4',
            month: 'JUN',
            day: '08',
            title: 'Washer Disinfector Setup'
        }
    ];

    pipelineStages = [
        { id: 'discovery', name: 'Discovery', amount: '$900K', count: 4 },
        { id: 'evaluation', name: 'Evaluation', amount: '$700K', count: 3 },
        { id: 'proposal', name: 'Proposal', amount: '$1.1M', count: 4 },
        { id: 'commit', name: 'Commit', amount: '$1.1M', count: 3 }
    ];

    pipelineSummary = {
        total: '$3.8M',
        won: '$400k',
        py: '$550K',
        gap: '-$150K(-27%)'
    };

    handleRefresh() {
        // Prototype no-op
    }

    handleViewAllAppointments(event) {
        event.preventDefault();
    }

    handleViewAllPipeline(event) {
        event.preventDefault();
    }
}