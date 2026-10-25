import { LightningElement, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import getWebinarMarketingDashboard from '@salesforce/apex/PipelineCommandCenterController.getWebinarMarketingDashboard';
import getSocialMediaMarketingDashboard from '@salesforce/apex/PipelineCommandCenterController.getSocialMediaMarketingDashboard';
import getMarketingRawData from '@salesforce/apex/PipelineCommandCenterController.getMarketingRawData';
import canSeeInfluencers from '@salesforce/customPermission/Influencer_Partners';

export default class WebinarMarketingCommandCenter extends LightningElement {
    activeMasterTab = 'webinar';
    webinarData;
    socialData;
    webinarWire;
    socialWire;
    error;
    isRefreshing = false;
    isRawDataOpen = false;
    isRawDataLoading = false;
    rawDataTitle;
    rawDataRows = [];

    @wire(getWebinarMarketingDashboard)
    wiredWebinar(result) {
        this.webinarWire = result;
        if (result.data) {
            this.webinarData = result.data;
            this.error = undefined;
        } else if (result.error) {
            this.error = this.reduceError(result.error);
        }
    }

    @wire(getSocialMediaMarketingDashboard)
    wiredSocial(result) {
        this.socialWire = result;
        if (result.data) {
            this.socialData = result.data;
            this.error = undefined;
        } else if (result.error) {
            this.error = this.reduceError(result.error);
        }
    }

    get activeData() {
        if (this.isInfluencerTab) return null;
        return this.activeMasterTab === 'social' ? this.socialData : this.webinarData;
    }

    // Influencer Partners is a working tab (c-influencer-partners), not a KPI cohort view.
    get showInfluencerTab() {
        return canSeeInfluencers === true;
    }

    get isInfluencerTab() {
        return this.activeMasterTab === 'influencer';
    }

    get influencerTabClass() {
        return `wmcc-master-tab ${this.isInfluencerTab ? 'wmcc-master-tab-active' : ''}`;
    }

    get isWebinarTab() {
        return this.activeMasterTab === 'webinar';
    }

    get isSocialTab() {
        return this.activeMasterTab === 'social';
    }

    get webinarTabClass() {
        return `wmcc-master-tab ${this.isWebinarTab ? 'wmcc-master-tab-active' : ''}`;
    }

    get socialTabClass() {
        return `wmcc-master-tab ${this.isSocialTab ? 'wmcc-master-tab-active' : ''}`;
    }

    get refreshLabel() {
        return this.isRefreshing ? 'Refreshing...' : 'Refresh data';
    }

    get cohortHeading() {
        return this.isWebinarTab ? 'Webinar Date' : 'Lead Source';
    }

    get cohortSubtitle() {
        return this.isWebinarTab
            ? 'Consumer Webinar cohorts, grouped by Webinar Date.'
            : 'Social media performance, grouped by the original Salesforce Lead Source.';
    }

    get hasCohorts() {
        return Boolean(this.activeData && this.activeData.cohorts && this.activeData.cohorts.length);
    }

    get noDataMessage() {
        return this.isWebinarTab
            ? 'No Consumer Webinar leads or transactions are available yet.'
            : 'No social media leads or transactions are available for the configured sources yet.';
    }

    get hasRawDataRows() {
        return this.rawDataRows.length > 0;
    }

    handleMasterTab(event) {
        this.activeMasterTab = event.currentTarget.dataset.tab;
    }

    async handleRefresh() {
        this.isRefreshing = true;
        try {
            await Promise.all([refreshApex(this.webinarWire), refreshApex(this.socialWire)]);
        } finally {
            this.isRefreshing = false;
        }
    }

    async handleOpenRawData(event) {
        const metric = event.currentTarget.dataset.metric;
        const cohort = event.currentTarget.dataset.cohort || 'ALL';
        const metricLabels = {
            leads: 'Leads',
            preApproved: 'Pre-Approved Leads',
            transactions: 'Transactions',
            funded: 'Funded / Post-Closed Transactions',
            showedThenNurtured: 'Showed for Appt, then Nurturing'
        };
        const viewLabel = this.isWebinarTab ? 'Consumer Webinar' : 'Social Media';
        const cohortLabel = cohort === 'ALL' ? 'All cohorts' : cohort;
        this.rawDataTitle = `${viewLabel} — ${cohortLabel} — ${metricLabels[metric]}`;
        this.rawDataRows = [];
        this.isRawDataOpen = true;
        this.isRawDataLoading = true;
        try {
            const rows = await getMarketingRawData({
                dashboardType: this.activeMasterTab,
                cohortLabel: cohort,
                metric
            });
            this.rawDataRows = rows.map((row) => ({
                ...row,
                recordUrl: `/lightning/r/${row.recordType === 'Lead' ? 'Lead' : 'Transaction__c'}/${row.recordId}/view`
            }));
        } catch (error) {
            this.error = this.reduceError(error);
            this.closeRawData();
        } finally {
            this.isRawDataLoading = false;
        }
    }

    closeRawData() {
        this.isRawDataOpen = false;
        this.isRawDataLoading = false;
        this.rawDataRows = [];
    }

    reduceError(error) {
        if (Array.isArray(error?.body)) {
            return error.body.map((item) => item.message).join(', ');
        }
        return error?.body?.message || error?.message || 'Unable to load marketing data.';
    }
}