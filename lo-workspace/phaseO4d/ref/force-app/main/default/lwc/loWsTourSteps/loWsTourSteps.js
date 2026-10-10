// LO Workspace guided tour script (O4b). Source of truth for every bubble: lo-workspace/onboarding/TOUR-SCRIPT.md
// (decision 33: wording changes = edit this file + quick deploy). Never write "External" or "Outside" here.
//
// Stop fields:
//   id      script id (PD-01, A-03, ...)
//   view    shell view to navigate to first (portalUtils PORTAL_VIEWS)
//   record  true = needs a record page in that view; the tour opens the first card/row (hook open-first)
//   clicks  hooks clicked before spotlighting (tabs, modals), in order
//   hooks   data-tour hooks to spotlight (one hole each)
//   need    hook that proves there is data; missing = show the screenshot instead of a spotlight
//   after   hooks clicked when leaving the stop (closes what clicks opened)
//   shot    screenshot id in LoWsTourAssets/screens (empty-state fallback); shotAlways = never spotlight
//   rcOnly  shown only to LOs set up with Reach's RingCentral (User.LoWs_RingCentral_Required__c)
// Buttons follow the position (script section 1): first stop of the full run = Let's go / Skip tour,
// last = Back / Finish; chapters = Back / Next / Exit chapter, last = Back / Done.

const P = 'perfectDay';
const LEADS = 'leads';
const LOANS = 'loans';
const REALTORS = 'realtors';

const s = (id, view, hooks, pose, text, extra = {}) => ({ id, view, hooks, pose, text, ...extra });
const lead = (id, hooks, pose, text, extra = {}) => s(id, LEADS, hooks, pose, text, { record: true, ...extra });
const reuse = (stop, id, extra = {}) => ({ ...stop, id, ...extra });

const T = {
    PD01: "Hi, I'm Bran, your LO Workspace coach! Give me two minutes and I'll walk you through a Perfect Day from first coffee to wrap-up.",
    PD02: "Start every morning right here: this bar shows how many of today's goals you've hit and whether you're on pace. The cards and the Pipeline snapshot below tell you where the money is today.",
    PD03: "This is your to-do list, ranked by impact: documents to review sit at the very top as urgent actions, then new leads, follow-ups due today and weekly touches. Follow-ups you set show up here on the day they're due, so work it top to bottom every day.",
    PD04: "Every call, text, meeting or post goes in with Log activity, and it counts toward today's goals. When a borrower or agent texts back, their reply shows at the top of Recent activity, so check it between calls.",
    PD05: 'My Active Leads shows every working lead by stage. Open a card to work it, or use Move to… to change its stage right from the board.',
    PD06: 'Everything about one borrower lives here: set the status at the top and tap Log communication after every touch. Overview holds Contact and Pre-Approval Details; the other tabs hold documents, calls, texts, emails and notes.',
    PD07: 'Book a Zoom with this borrower right from the Schedule a Zoom card: it goes on your calendar and they get the invite. If it ever says Connect your Zoom, follow the steps in the card and click Try again.',
    PD08: "Texts shows what Reach texted the borrower and their agent automatically, plus their replies. You can't reply from here, so use the number under Reply from your phone.",
    PD09: 'Document requests is where you ask for paperwork and review what comes back. Tap Start review, then Approve, Reject or Not Needed, and the borrower gets your comment on anything you reject.',
    PD10: "Pre-Approval Letter works once the lead reaches Pre-Approval or any later status; before that, the button tells you exactly what to do to unlock it. A lead that's already been converted to a loan can't get a new letter.",
    PD11: "Application Summary is the borrower's story, built from your call summaries. Fix anything that's wrong and add what's missing; later calls add to it and never overwrite what you write.",
    PD12: "Convert to transaction checks six things: Borrower name, Borrower income, Borrower SSN, Subject property, Estimated property value and Loan amount. Whatever's already in Salesforce fills in by itself; mark the rest Info received only when you really have it, then Confirm conversion.",
    PD13: 'Converted files land in My Loans, grouped by milestone from Application to Closing. A Needs update badge means the processor is waiting on you, so open that loan first.',
    PD14: "My Realtors is your referral engine: set each agent's stage and hit Log touch every time you reach out. Follow-up due shows who's going cold, and your list is yours alone.",
    PD15: 'Upcoming appointments shows your next 7 days, including the Zooms you book, and Open calendar gives you the full month. Click any appointment to jump straight to that borrower or realtor.',
    PD16: "That's a Perfect Day: work Up Next, log every touch, set the follow-up, repeat! Want a refresher? Take the tour under your name, or the ? on this banner, replays any part.",
    // Decision 61: RingCentral stop, only for LOs on Reach's company RingCentral.
    RC: "Calls you make in Reach's RingCentral log here automatically and count toward your goals."
};

const PD = {
    p01: s('PD-01', P, ['pd-banner'], 'waving', T.PD01),
    p02: s('PD-02', P, ['pd-progress', 'pd-metrics'], 'presenting', T.PD02),
    p03: s('PD-03', P, ['up-next'], 'pointing', T.PD03, { need: 'up-next-actions', shot: 'SS-UPNEXT' }),
    p04: s('PD-04', P, ['pd-log-activity', 'recent-log'], 'hands-on-hips', T.PD04, { need: 'recent-reply', shot: 'SS-RECENT' }),
    rc: s('PD-RC', P, ['recent-log'], 'thinking', T.RC, { rcOnly: true }),
    p05: s('PD-05', LEADS, ['leads-board', 'leads-move-to'], 'presenting', T.PD05, { need: 'open-first', shot: 'SS-BOARD' }),
    p06: lead('PD-06', ['lead-status', 'lead-log-communication', 'lead-tabs'], 'pointing', T.PD06, { shot: 'SS-LEAD' }),
    p07: lead('PD-07', ['lead-zoom'], 'hands-on-hips', T.PD07, { clicks: ['lead-tab-overview'], shot: 'SS-ZOOM' }),
    p08: lead('PD-08', ['comms-texts'], 'thinking', T.PD08, { clicks: ['lead-tab-comms', 'comms-texts'], need: 'comms-text-row', shot: 'SS-TEXTS' }),
    p09: lead('PD-09', ['doc-req'], 'thinking', T.PD09, { clicks: ['lead-tab-requests'], shot: 'SS-DOCREQ' }),
    p10: lead('PD-10', ['lead-letter'], 'pointing', T.PD10, { shot: 'SS-LETTER' }),
    p11: lead('PD-11', ['lead-app-summary'], 'presenting', T.PD11, { shot: 'SS-APPSUM' }),
    p12: lead('PD-12', ['lead-convert'], 'arms-crossed', T.PD12, { shot: 'SS-TRID' }),
    p13: s('PD-13', LOANS, ['loans-board'], 'presenting', T.PD13, { need: 'open-first', shot: 'SS-LOANS' }),
    p14: s('PD-14', REALTORS, ['list-rows'], 'pointing', T.PD14, { shot: 'SS-REALTORS' }),
    p15: s('PD-15', P, ['appointments'], 'thinking', T.PD15, { need: 'appointment-row', shot: 'SS-CAL' }),
    p16: s('PD-16', P, ['tour-menu', 'pd-tour-help'], 'double-thumbs', T.PD16)
};

export const FULL_RUN_ID = 'PD';

export const CHAPTERS = [
    {
        id: FULL_RUN_ID,
        title: 'The full Perfect Day',
        full: true,
        stops: [PD.p01, PD.p02, PD.p03, PD.p04, PD.rc, PD.p05, PD.p06, PD.p07, PD.p08, PD.p09, PD.p10, PD.p11, PD.p12, PD.p13, PD.p14, PD.p15, PD.p16]
    },
    {
        id: 'A',
        title: 'Perfect Day & Up Next',
        stops: [
            reuse(PD.p02, 'A-01'),
            reuse(PD.p03, 'A-02'),
            s('A-03', P, ['up-next-actions'], 'thinking', 'Log it done records the touch, Mark complete closes a follow-up, and Tomorrow pushes the card to the morning. Use Tomorrow sparingly: a new lead you push may miss its contact window.', { shot: 'SS-UPNEXT' }),
            s('A-04', P, ['pd-pipeline-snapshot'], 'presenting', "Pipeline snapshot counts what's waiting in each queue, and anything red is urgent. Click a row to open that exact list."),
            s('A-05', P, ['log-modal-category'], 'hands-on-hips', "Your turn: every call, text, meeting or post goes in with Log activity, and it counts toward today's goals. Calls and texts from your own phone aren't captured automatically, so log them here.", { clicks: ['pd-log-activity'], after: ['log-modal-close'] }),
            reuse(PD.rc, 'A-RC'),
            s('A-06', P, ['today-plan', 'recent-log'], 'thumbs-up', "Today's Plan splits your weekly targets into today's share, with a Log button on each line. Recent activity shows everything you log, and borrower and agent text replies land at the top with the number to reply from your phone.", { need: 'recent-reply', shot: 'SS-RECENT' })
        ]
    },
    {
        id: 'B',
        title: 'My Active Leads',
        stops: [
            reuse(PD.p05, 'B-01'),
            s('B-02', LEADS, ['leads-layout-toggle'], 'thinking', 'Prefer rows? Switch to List, and LO Workspace remembers your choice. The search box finds any lead by name or source.', { need: 'open-first', shot: 'SS-BOARD' }),
            s('B-03', LEADS, ['leads-add'], 'hands-on-hips', 'Met someone at an open house? Add lead takes first and last name, phone, email and loan purpose, and you can pick the referring realtor so they get the credit.'),
            s('B-04', 'nurtured', ['nav-nurtured'], 'thinking', 'Leads you Move to… Nurture leave your active board and wait here. Check in on them now and then, because today\'s "not yet" is next season\'s buyer.')
        ]
    },
    {
        id: 'C',
        title: 'A lead page',
        stops: [
            reuse(PD.p06, 'C-01'),
            lead('C-02', ['lead-contact-card', 'lead-pre-approval-details'], 'hands-on-hips', "Keep Contact and Pre-Approval Details current, and add every co-borrower with + Add borrower. A borrower without an email can't get document requests.", { clicks: ['lead-tab-overview'], shot: 'SS-LEAD' }),
            reuse(PD.p07, 'C-03'),
            lead('C-04', ['lead-calls'], 'thinking', 'Recorded calls and Zoom meetings with this borrower show up here with their summaries. Anything you logged by hand sits under Logged calls.', { clicks: ['lead-tab-calls'], shot: 'SS-LEAD' }),
            lead('C-05', ['comms-subtabs'], 'presenting', "Communications shows every call, text and email anyone at Reach has had with this borrower, newest first. Read it before you call so you're never caught off guard.", { clicks: ['lead-tab-comms'], shot: 'SS-LEAD' }),
            reuse(PD.p08, 'C-06'),
            reuse(PD.p11, 'C-07'),
            lead('C-08', ['lead-notes-new'], 'pointing', "Tap New to drop a quick note, and pin the important ones to the top. The lead's team gets an email copy, so keep it clear and short.", { clicks: ['lead-tab-notes'], shot: 'SS-LEAD' })
        ]
    },
    {
        id: 'D',
        title: 'Document requests',
        stops: [
            s('D-01', P, ['up-next-alert'], 'arms-crossed', "When a borrower uploads documents, a red High alert lands at the very top of Up Next. There's no timer on it, but it stays on top as your most urgent action until you review them.", { shot: 'SS-ALERT' }),
            lead('D-02', ['doc-req-add'], 'hands-on-hips', 'Start with Add Conditions to list what you need from the borrower. Assign each item to the right borrower so nobody gets asked for someone else\'s paperwork.', { clicks: ['lead-tab-requests'], shot: 'SS-DOCREQ' }),
            lead('D-03', ['doc-req-send'], 'pointing', 'Send Request Email gives each borrower their own list and their own upload link. When they upload, the review shows up at the top of Up Next.', { clicks: ['lead-tab-requests'], shot: 'SS-DOCREQ' }),
            lead('D-04', ['doc-req-start-review'], 'thinking', T.PD09, { clicks: ['lead-tab-requests'], shot: 'SS-DOCREQ' })
        ]
    },
    {
        id: 'E',
        title: 'Pre-approvals & the letter',
        stops: [
            s('E-01', 'preApprovals', ['nav-preApprovals'], 'presenting', "My Pre-Approvals holds every borrower who's approved and shopping. These are your closest deals to a contract, so they get a touch every single week.", { need: 'list-rows', shot: 'SS-PREAPP' }),
            s('E-02', 'preApprovals', ['list-filters'], 'arms-crossed', "Weekly touch due means it's been 7 days or more since you last talked to them. Clear this list every week, and they'll show up in Up Next until you do.", { need: 'list-rows', shot: 'SS-PREAPP' }),
            reuse(PD.p10, 'E-03')
        ]
    },
    {
        id: 'F',
        title: 'Converting to a loan & the Submission Form',
        stops: [
            reuse(PD.p12, 'F-01'),
            s('F-02', LOANS, ['loan-submission'], 'hands-on-hips', "After you convert, the Submission form appears on the loan. Complete it once the loan is imported and, if you're locking, locked with the investor you chose.", { record: true, shot: 'SS-SUBMIT' }),
            // The tour never opens the wizard (it could not close it again): screenshot only.
            s('F-03', LOANS, [], 'thinking', 'It walks you through investor, loan, property, borrowers, realtors and title, and anything we already know comes in prefilled. You can come back and edit it until Disclosures Out.', { record: true, shot: 'SS-SUBMIT', shotAlways: true })
        ]
    },
    {
        id: 'G',
        title: 'My Loans',
        stops: [
            reuse(PD.p13, 'G-01'),
            s('G-02', LOANS, ['list-filters'], 'thinking', 'Funded files move to My Closed Loans and fall-throughs to My Cancelled Loans. If a purchase cancels for a reason we can still fix, the borrower comes back to you as a Pre-Approval lead.', { need: 'open-first', shot: 'SS-LOANS' }),
            s('G-03', LOANS, ['loan-milestone', 'loan-tabs'], 'pointing', 'The chip at the top shows exactly where the loan stands. Conditions shows what\'s still outstanding, and the processor clears them as they come in.', { record: true, shot: 'SS-LOAN' }),
            s('G-04', LOANS, ['appraisal-tracker', 'appraisal-messages'], 'presenting', 'Appraisal shows the order status, the key dates and the property map. Need something from the appraiser? Message them right here and it\'s saved on the order.', { record: true, clicks: ['loan-tab-appraisal'], shot: 'SS-LOAN' }),
            s('G-05', LOANS, ['comms-texts'], 'thinking', 'On a loan, Texts shows the milestone updates Reach sends the agent automatically, and anything they text back. Reply from your own phone using the number shown.', { record: true, clicks: ['loan-tab-comms', 'comms-texts'], need: 'comms-text-row', shot: 'SS-TEXTS-LOAN' }),
            s('G-06', LOANS, ['loan-coc'], 'arms-crossed', "Amount, value, rate or program changed? Change of circumstance sends a COC to Reach's COC team. Never make changes with the investor yourself; the lock desk and COC team handle that.", { record: true, shot: 'SS-LOAN' })
        ]
    },
    {
        id: 'H',
        title: 'My Realtors & tagging',
        stops: [
            reuse(PD.p14, 'H-01'),
            s('H-02', REALTORS, ['list-filters'], 'thinking', 'Your list builds itself from the touches you log, so keep touching an agent and they stay on it. Follow-up due is the filter to check every morning.', { need: 'list-rows', shot: 'SS-REALTORS' }),
            s('H-03', REALTORS, ['realtors-add'], 'hands-on-hips', "Add partner checks Reach's shared list first. If the agent is already here, tap Tag me instead of creating a duplicate, and they join your list with your own stage.", { need: 'list-rows', shot: 'SS-REALTORS' }),
            s('H-04', REALTORS, ['realtor-stage', 'realtor-shared-pipeline'], 'presenting', "Move My stage forward as the relationship grows: you can set Active Partner yourself, and it moves there automatically when they send you a lead. Shared pipeline shows every borrower they've sent you.", { record: true, shot: 'SS-REALTOR' }),
            s('H-05', REALTORS, ['realtor-texts'], 'thinking', 'The Texts card shows what Reach texted this agent about your leads and loans, and their replies. Answer from your phone with the number under Reply from your phone.', { record: true, need: 'comms-text-row', shot: 'SS-REALTOR' }),
            s('H-06', REALTORS, ['realtor-zoom'], 'hands-on-hips', 'Want a face-to-face? Schedule a Zoom books it with this agent and puts it on your calendar. Other Contacts in the menu works the same way for title, insurance and other pros.', { record: true, shot: 'SS-REALTOR' })
        ]
    },
    {
        id: 'I',
        title: 'Past clients & CSV import',
        stops: [
            s('I-01', 'pastClients', ['nav-pastClients'], 'presenting', "Past Clients are the people you've already closed, and they're your easiest next deal and best referral source. Open one to log a call."),
            s('I-02', 'pastClients', ['past-client-new-lead', 'past-client-zoom'], 'pointing', 'Thinking of buying again or refinancing? Tap New lead for this client, or book a check-in with Schedule a Zoom, with their loan history right beside you.', { record: true, shot: 'SS-PASTCLIENT' }),
            s('I-03', 'importData', ['import-consumer'], 'hands-on-hips', 'Bring your book with you: export a CSV from your old CRM and upload it under Leads & past clients. Use the Type column to mark each row Lead or Past Client.'),
            s('I-04', 'importData', ['import-partner'], 'thinking', "Your agents go under Realtors & partners, and PartnerType sorts them into partners and prospects. We check for duplicates and never overwrite anyone else's relationships.")
        ]
    },
    {
        id: 'J',
        title: 'Calendar, follow-ups & in-person events',
        stops: [
            reuse(PD.p15, 'J-01'),
            s('J-02', P, ['calendar-views'], 'presenting', 'Switch between Month, Week and Day, and click any appointment to jump straight to that borrower or realtor.', { clicks: ['appointments-open-calendar'], after: ['calendar-close'], shot: 'SS-CAL' }),
            // The follow-up picker only shows when the log is tied to a record, so this stop uses a lead's Log communication.
            lead('J-03', ['follow-up-picker'], 'arms-crossed', "Never end a conversation without a next step: a General follow-up shows up in Up Next on the day it's due, and an Exact time puts an appointment on your calendar. There are no pop-up reminders, so Up Next is where you'll find them.", { clicks: ['lead-log-communication'], after: ['comm-modal-close'] }),
            s('J-04', P, ['in-person-events'], 'presenting', "Hosting a lunch-and-learn or happy hour? Your upcoming events and who's said yes live right here.", { shot: 'SS-EVENTS' }),
            s('J-05', P, ['pd-in-person-invite'], 'hands-on-hips', 'Tap In Person Invite, pick your agents, set the date and place, and hit Send invites. We send a branded invite with Yes / No buttons and the reminders for you.', { shot: 'SS-EVENTS' })
        ]
    },
    {
        id: 'K',
        title: 'My Perfect Week & My Progress',
        stops: [
            s('K-01', 'perfectWeek', ['perfect-week-this-week'], 'presenting', 'My Perfect Week compares what you\'ve done against the weekly targets you set. Glance at it Monday morning and again on Friday.'),
            s('K-02', 'perfectWeek', ['perfect-week-edit-plan'], 'pointing', 'Business changed? Edit my plan reopens your setup questions so you can change your focus, activities and targets any time.'),
            s('K-03', 'progress', ['progress-period', 'progress-coaching'], 'thumbs-up', "My Progress shows your actual numbers against your own targets, with a coaching focus where you're behind. Pull out the Volume tab on the edge any time for closed, pre-approved and new-lead totals."),
            s('K-04', P, ['pd-goal-progress'], 'thinking', 'Goal Progress on Perfect Day is the quick version of all this. Green means goal met, and keep Overdue tasks at zero.')
        ]
    },
    {
        id: 'L',
        title: 'Approved Investors',
        stops: [
            s('L-01', P, [], 'presenting', 'Approved Investors, the tab next to Perfect Day at the top, lists every investor we can send a loan to, with their products, channels and account executives.', { shot: 'SS-INVESTORS', shotAlways: true }),
            s('L-02', P, [], 'thinking', 'Check it before you pick an investor on the Submission form, so the channel and product match.', { shot: 'SS-INVESTORS', shotAlways: true })
        ]
    },
    {
        id: 'M',
        title: 'LO Workspace on your phone',
        stops: [
            s('M-01', P, [], 'presenting', 'LO Workspace comes with you on the Salesforce mobile app. Download it, sign in with your Reach login, and open LO Workspace from the app menu.', { shot: 'SS-PHONE-1', shotAlways: true }),
            s('M-02', P, [], 'pointing', "Perfect Day opens first, just like here, and Log activity sits right at the top. Log every call the moment you hang up, while it's fresh.", { shot: 'SS-PHONE-2', shotAlways: true }),
            s('M-03', P, [], 'thinking', "Tap the ☰ menu for My Active Leads, My Loans and My Realtors. It's the same menu you use on your desktop.", { shot: 'SS-PHONE-3', shotAlways: true }),
            s('M-04', P, [], 'thumbs-up', "Turn on notifications and you'll hear about a new lead the moment it lands. Your desktop is still home base for document reviews and the Submission form.", { shot: 'SS-PHONE-4', shotAlways: true })
        ]
    }
];

/** Stops this user sees in a chapter (drops the RingCentral stop unless they are on Reach's RingCentral). */
export function stopsFor(chapter, ringCentral) {
    return chapter.stops.filter((stop) => ringCentral || !stop.rcOnly);
}

export const SKIP_CONFIRM = 'Skip the tour? You can replay it any time from Take the tour.';