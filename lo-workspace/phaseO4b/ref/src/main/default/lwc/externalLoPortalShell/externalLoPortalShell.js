import { LightningElement, wire } from 'lwc';
import { CurrentPageReference, NavigationMixin } from 'lightning/navigation';
import { refreshApex } from '@salesforce/apex';
import { getRecord } from 'lightning/uiRecordApi';
import USER_NAME from '@salesforce/schema/User.Name';
import userId from '@salesforce/user/Id';
import getNavBadges from '@salesforce/apex/ExternalLoPortalController.getNavBadges';
import getAccountWorkspaceView from '@salesforce/apex/ExternalLoPortalController.getAccountWorkspaceView';
import getOnboardingState from '@salesforce/apex/ExternalLoWorkspaceController.getOnboardingState';
import getGateState from '@salesforce/apex/ExternalLoWorkspaceController.getGateState';
import getConnectionIssues from '@salesforce/apex/ExternalLoWorkspaceController.getConnectionIssues';

const ISSUES_DISMISSED_KEY = 'loWsConnectionIssuesDismissed';
import {
    PORTAL_VIEWS,
    defaultFilterForView,
    isExperienceCloudContext,
    loadPortalFont,
    parsePortalState,
    portalHomePageRef,
    portalStatesEqual,
    reduceApexError
} from 'c/portalUtils';
import EXTLO_NAV_MY_ACTIVITY from '@salesforce/label/c.ExtLO_Nav_My_Activity';
import EXTLO_NAV_BIZ_DEV from '@salesforce/label/c.ExtLO_Nav_Biz_Dev';
import EXTLO_NAV_PIPELINE from '@salesforce/label/c.ExtLO_Nav_Pipeline';
import EXTLO_NAV_PERFECT_DAY from '@salesforce/label/c.ExtLO_Nav_Perfect_Day';
import EXTLO_NAV_MY_PROGRESS from '@salesforce/label/c.ExtLO_Nav_My_Progress';
import EXTLO_NAV_MY_PERFECT_WEEK from '@salesforce/label/c.ExtLO_Nav_My_Perfect_Week';
import EXTLO_NAV_REALTOR_PROSPECTS from '@salesforce/label/c.ExtLO_Nav_Realtor_Prospects';
import EXTLO_NAV_MY_REALTORS from '@salesforce/label/c.ExtLO_Nav_My_Realtors';
import EXTLO_NAV_PAST_CLIENTS from '@salesforce/label/c.ExtLO_Nav_Past_Clients';
import EXTLO_NAV_IMPORT_DATA from '@salesforce/label/c.ExtLO_Nav_Import_Data';
import EXTLO_NAV_MY_LEADS from '@salesforce/label/c.ExtLO_Nav_My_Leads';
import EXTLO_NAV_MY_PRE_APPROVALS from '@salesforce/label/c.ExtLO_Nav_My_Pre_Approvals';
import EXTLO_NAV_MY_LOANS from '@salesforce/label/c.ExtLO_Nav_My_Loans';
import EXTLO_SHELL_BRAND_TITLE from '@salesforce/label/c.ExtLO_Shell_Brand_Title';
import EXTLO_SHELL_BRAND_SUBTITLE from '@salesforce/label/c.ExtLO_Shell_Brand_Subtitle';
import EXTLO_SHELL_USER_ROLE from '@salesforce/label/c.ExtLO_Shell_User_Role';
import EXTLO_SHELL_LOADING from '@salesforce/label/c.ExtLO_Shell_Loading';
import EXTLO_SHELL_NAV_ARIA from '@salesforce/label/c.ExtLO_Shell_Nav_Aria';
import EXTLO_SHELL_OPEN_NAV from '@salesforce/label/c.ExtLO_Shell_Open_Nav';
import EXTLO_SHELL_CLOSE_NAV from '@salesforce/label/c.ExtLO_Shell_Close_Nav';
import EXTLO_SHELL_LOG_OUT from '@salesforce/label/c.ExtLO_Shell_Log_Out';

const NAV_GROUPS = [
    {
        id: 'activity',
        label: EXTLO_NAV_MY_ACTIVITY,
        items: [
            { id: PORTAL_VIEWS.PERFECT_DAY, label: EXTLO_NAV_PERFECT_DAY, iconName: 'home', badgeField: null },
            { id: PORTAL_VIEWS.PROGRESS, label: EXTLO_NAV_MY_PROGRESS, iconName: 'trending-up', badgeField: null },
            { id: PORTAL_VIEWS.PERFECT_WEEK, label: EXTLO_NAV_MY_PERFECT_WEEK, iconName: 'sliders-horizontal', badgeField: null }
        ]
    },
    {
        id: 'bizdev',
        label: EXTLO_NAV_BIZ_DEV,
        items: [
            { id: PORTAL_VIEWS.REALTOR_PROSPECTS, label: EXTLO_NAV_REALTOR_PROSPECTS, iconName: 'target', badgeField: null },
            { id: PORTAL_VIEWS.REALTORS, label: EXTLO_NAV_MY_REALTORS, iconName: 'building', badgeField: 'dueRealtors' },
            { id: PORTAL_VIEWS.OTHER_CONTACTS, label: 'Other Contacts', iconName: 'handshake', badgeField: null, workspaceOnly: true },
            { id: PORTAL_VIEWS.PAST_CLIENTS, label: EXTLO_NAV_PAST_CLIENTS, iconName: 'history', badgeField: null },
            { id: PORTAL_VIEWS.IMPORT_DATA, label: EXTLO_NAV_IMPORT_DATA, iconName: 'upload-cloud', badgeField: null }
        ]
    },
    {
        id: 'pipeline',
        label: EXTLO_NAV_PIPELINE,
        items: [
            { id: PORTAL_VIEWS.LEADS, label: EXTLO_NAV_MY_LEADS, iconName: 'users', badgeField: 'newLeads' },
            { id: PORTAL_VIEWS.PRE_APPROVALS, label: EXTLO_NAV_MY_PRE_APPROVALS, iconName: 'file-check-2', badgeField: 'preApprovals' },
            // LO Workspace only: Nurture-status leads live here, not in My Active Leads.
            { id: PORTAL_VIEWS.NURTURED, label: 'Nurtured Leads', iconName: 'history', badgeField: null, workspaceOnly: true },
            { id: PORTAL_VIEWS.LOANS, label: EXTLO_NAV_MY_LOANS, iconName: 'wallet-cards', badgeField: null }
        ]
    }
];

export default class ExternalLoPortalShell extends NavigationMixin(LightningElement) {
    labels = {
        // Same shell runs in the Partner Workspace portal and in the internal LO Workspace app.
        brandTitle: isExperienceCloudContext() ? EXTLO_SHELL_BRAND_TITLE : 'LO Workspace',
        brandSubtitle: EXTLO_SHELL_BRAND_SUBTITLE,
        // The label says "External Loan Officer"; LO Workspace users never see that wording.
        userRole: isExperienceCloudContext() ? EXTLO_SHELL_USER_ROLE : 'Loan Officer',
        loading: EXTLO_SHELL_LOADING,
        navAria: EXTLO_SHELL_NAV_ARIA,
        openNav: EXTLO_SHELL_OPEN_NAV,
        closeNav: EXTLO_SHELL_CLOSE_NAV,
        logOut: EXTLO_SHELL_LOG_OUT
    };

    activeView = PORTAL_VIEWS.PERFECT_DAY;
    leadsTab = null;
    activeFilter;
    activeRecordId;
    mobileNavOpen = false;
    badges = {};
    wiredBadgesResult;
    wiredOnboardingResult;
    onboardingState;
    loadError;
    dataRefreshKey = 0;
    homeRefreshKey = 0;
    userDisplayName = 'Loan Officer';
    userInitials = 'LO';
    pendingNav;
    urlReady = false;

    @wire(getRecord, { recordId: userId, fields: [USER_NAME] })
    wiredUser({ data }) {
        if (data?.fields?.Name?.value) {
            this.userDisplayName = data.fields.Name.value;
            const parts = this.userDisplayName.split(' ').filter(Boolean);
            this.userInitials = parts.slice(0, 2).map((part) => part[0]).join('').toUpperCase() || 'LO';
        }
    }

    connectedCallback() {
        this.activeFilter = defaultFilterForView(this.activeView);
        loadPortalFont(this);
        this.loadGate();
    }

    // First-login gate (O2): LO Workspace only; the Partner Workspace portal never calls it.
    gateState;
    gateLoading = !isExperienceCloudContext();
    connectionIssues = [];

    async loadGate() {
        if (isExperienceCloudContext()) {
            return;
        }
        try {
            this.gateState = await getGateState();
        } catch (e) {
            this.gateState = undefined; // never lock someone out because the check itself failed
        } finally {
            this.gateLoading = false;
        }
        if (!this.gateState?.applies && !this.issuesDismissed()) {
            try {
                this.connectionIssues = (await getConnectionIssues()) || [];
            } catch (e) {
                this.connectionIssues = [];
            }
        }
    }

    get showGate() {
        return this.gateState?.applies === true && this.gateState.passed !== true;
    }

    get showConnectionBanner() {
        return this.isPerfectDay && this.connectionIssues.length > 0;
    }

    handleGatePassed() {
        this.gateState = { ...this.gateState, passed: true };
    }

    issuesDismissed() {
        try {
            return window.sessionStorage.getItem(ISSUES_DISMISSED_KEY) === '1';
        } catch (e) {
            return false;
        }
    }

    dismissConnectionBanner() {
        this.connectionIssues = [];
        try {
            window.sessionStorage.setItem(ISSUES_DISMISSED_KEY, '1');
        } catch (e) {
            // per-session convenience only
        }
    }

    @wire(CurrentPageReference)
    handlePageReference(pageRef) {
        this.pendingNav = parsePortalState(pageRef);
        this.applyPendingNav();
    }

    @wire(getNavBadges)
    wiredBadges(result) {
        this.wiredBadgesResult = result;
        if (result.data) {
            this.badges = result.data;
        }
    }

    @wire(getOnboardingState)
    wiredOnboarding(result) {
        this.wiredOnboardingResult = result;
        if (result.data) {
            this.onboardingState = result.data;
            this.loadError = undefined;
            this.applyPendingNav();
        } else if (result.error) {
            this.loadError = reduceApexError(result.error);
        }
    }

    // Internal Salesforce has its own logout in the user menu; only the portal needs this button.
    get showLogout() {
        return isExperienceCloudContext();
    }

    get showWorkspace() {
        return !!this.onboardingState;
    }

    get isSetupComplete() {
        return this.onboardingState?.complete === true;
    }

    get isOnboardingLoading() {
        return (!this.onboardingState || this.gateLoading) && !this.loadError;
    }

    get navGroups() {
        const setupOnly = !this.isSetupComplete;
        return NAV_GROUPS.map((group) => {
            const items = group.items
                .filter((item) => !setupOnly || item.id === PORTAL_VIEWS.PERFECT_DAY || item.id === PORTAL_VIEWS.PERFECT_WEEK)
                .filter((item) => !item.workspaceOnly || !isExperienceCloudContext())
                .map((item) => {
                    const count = item.badgeField ? this.badges[item.badgeField] : null;
                    return {
                        ...item,
                        label: item.id === PORTAL_VIEWS.LEADS && !isExperienceCloudContext() ? 'My Active Leads' : item.label,
                        navClass: item.id === this.activeView ? 'nav-item nav-item-active' : 'nav-item',
                        isActive: item.id === this.activeView,
                        showBadge: typeof count === 'number' && count > 0,
                        badgeLabel: count
                    };
                });
            return { ...group, items };
        }).filter((group) => group.items.length > 0);
    }

    get isPerfectDay() { return this.activeView === PORTAL_VIEWS.PERFECT_DAY; }
    get isProgress() { return this.activeView === PORTAL_VIEWS.PROGRESS; }
    get isPerfectWeek() { return this.activeView === PORTAL_VIEWS.PERFECT_WEEK; }
    get isRealtorProspects() { return this.activeView === PORTAL_VIEWS.REALTOR_PROSPECTS; }
    get isRealtors() { return this.activeView === PORTAL_VIEWS.REALTORS; }
    get isOtherContacts() { return this.activeView === PORTAL_VIEWS.OTHER_CONTACTS; }
    get isPastClients() { return this.activeView === PORTAL_VIEWS.PAST_CLIENTS; }
    get isImportData() { return this.activeView === PORTAL_VIEWS.IMPORT_DATA; }
    get isLeads() { return this.activeView === PORTAL_VIEWS.LEADS; }
    get isPreApprovals() { return this.activeView === PORTAL_VIEWS.PRE_APPROVALS; }
    get isNurtured() { return this.activeView === PORTAL_VIEWS.NURTURED; }
    get isLoans() { return this.activeView === PORTAL_VIEWS.LOANS; }
    // Volume drawer: LO Workspace main screens only (home, My Loans, Pre-Approvals, Leads, Realtors, Other Contacts).
    get showVolumeDrawer() {
        return !isExperienceCloudContext() && [
            PORTAL_VIEWS.PERFECT_DAY, PORTAL_VIEWS.LOANS, PORTAL_VIEWS.PRE_APPROVALS, PORTAL_VIEWS.LEADS, PORTAL_VIEWS.REALTORS,
            PORTAL_VIEWS.OTHER_CONTACTS
        ].includes(this.activeView);
    }

    get leadsFilter() {
        return this.isLeads ? this.activeFilter || 'all' : 'all';
    }
    get realtorsFilter() {
        return this.isRealtors ? this.activeFilter || 'all' : 'all';
    }
    get preApprovalsFilter() {
        return this.isPreApprovals ? this.activeFilter || 'all' : 'all';
    }
    get loansFilter() {
        return this.isLoans ? this.activeFilter || 'all' : 'all';
    }
    get leadsRecordId() {
        return this.isLeads ? this.activeRecordId : null;
    }
    get nurturedRecordId() {
        return this.isNurtured ? this.activeRecordId : null;
    }
    get realtorsRecordId() {
        return this.isRealtors ? this.activeRecordId : null;
    }
    get otherContactsFilter() {
        return this.isOtherContacts ? this.activeFilter || 'all' : 'all';
    }
    get otherContactsRecordId() {
        return this.isOtherContacts ? this.activeRecordId : null;
    }
    get pastClientsRecordId() {
        return this.isPastClients ? this.activeRecordId : null;
    }
    get loansRecordId() {
        return this.isLoans ? this.activeRecordId : null;
    }

    applyPendingNav() {
        if (!this.onboardingState || !this.pendingNav) {
            return;
        }
        const requested = this.pendingNav;
        const next = this.gateView(requested.view, requested.filter, requested.recordId);
        if (!portalStatesEqual(next, this.currentNavState())) {
            this.activeView = next.view;
            this.activeFilter = next.filter;
            this.activeRecordId = next.recordId;
        }
        this.urlReady = true;
        if (!portalStatesEqual(next, requested)) {
            this.syncUrl(next);
        }
    }

    currentNavState() {
        return {
            view: this.activeView,
            filter: this.activeFilter || null,
            recordId: this.activeRecordId || null
        };
    }

    gateView(view, filter, recordId) {
        let nextView = view || PORTAL_VIEWS.PERFECT_DAY;
        if (!this.isSetupComplete && nextView !== PORTAL_VIEWS.PERFECT_DAY && nextView !== PORTAL_VIEWS.PERFECT_WEEK) {
            nextView = PORTAL_VIEWS.PERFECT_DAY;
        }
        return {
            view: nextView,
            filter: filter ?? defaultFilterForView(nextView),
            recordId: recordId || null
        };
    }

    handleNavSelect(event) {
        this.navigateTo(event.detail.view, defaultFilterForView(event.detail.view), null);
        this.mobileNavOpen = false;
    }

    async handlePortalNavigate(event) {
        const { filter, recordId, tab, accountFallback } = event.detail;
        let { view } = event.detail;
        // LO Workspace: an Account sent to My Realtors (Perfect Day drawers, Up Next, calendar) opens
        // the past client page when it is my imported past client. accountFallback 'record' (calendar)
        // opens anything that has no workspace page on its record page, as before.
        if (view === PORTAL_VIEWS.REALTORS && recordId && String(recordId).startsWith('001') && !isExperienceCloudContext()) {
            let target = null;
            try {
                target = await getAccountWorkspaceView({ accountId: recordId });
            } catch (e) {
                target = null;
            }
            if (target === PORTAL_VIEWS.PAST_CLIENTS) {
                view = target;
            } else if (!target && accountFallback === 'record') {
                this[NavigationMixin.Navigate]({ type: 'standard__recordPage', attributes: { recordId, actionName: 'view' } });
                return;
            }
        }
        // Optional detail tab to open on (e.g. a high alert opens Document requests).
        this.leadsTab = tab || null;
        this.navigateTo(view, filter ?? defaultFilterForView(view), recordId ?? null);
    }

    navigateTo(view, filter, recordId) {
        const next = this.gateView(view, filter, recordId);
        const current = this.currentNavState();
        if (portalStatesEqual(next, current) && this.urlReady) {
            this.mobileNavOpen = false;
            return;
        }
        this.activeView = next.view;
        this.activeFilter = next.filter;
        this.activeRecordId = next.recordId;
        this.mobileNavOpen = false;
        if (next.view === PORTAL_VIEWS.PERFECT_DAY) {
            refreshApex(this.wiredBadgesResult);
        }
        this.syncUrl(next);
    }

    syncUrl(next) {
        if (!this.urlReady) {
            return;
        }
        const pageRef = portalHomePageRef(next.view, next.filter, next.recordId);
        this.pendingNav = next;
        this[NavigationMixin.Navigate](pageRef);
    }

    handleOnboardingCompleted(event) {
        if (event?.detail?.state) {
            this.onboardingState = event.detail.state;
        }
        this.homeRefreshKey = Date.now();
        this.dataRefreshKey = Date.now();
        refreshApex(this.wiredOnboardingResult);
        refreshApex(this.wiredBadgesResult);
        this.navigateTo(PORTAL_VIEWS.PERFECT_DAY, null, null);
    }

    handleImportDone() {
        this.dataRefreshKey = Date.now();
        refreshApex(this.wiredBadgesResult);
    }

    openMobileNav() {
        this.mobileNavOpen = true;
    }

    closeMobileNav() {
        this.mobileNavOpen = false;
    }

    // Ends the session; with no custom logout URL on the network this lands on the login page.
    handleLogout() {
        this[NavigationMixin.Navigate]({ type: 'comm__loginPage', attributes: { actionName: 'logout' } });
    }
}