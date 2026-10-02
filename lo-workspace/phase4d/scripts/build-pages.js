// Builds the three LO Workspace record pages from fresh prod retrieves in ../ref.
// Re-run after a fresh retrieve: node scripts/build-pages.js
const fs = require('fs');
const path = require('path');
const ROOT = path.join(__dirname, '..');
const SRC = path.join(ROOT, 'ref/mdapi/unpackaged/unpackaged/flexipages');
const OUT = path.join(ROOT, 'force-app/main/default/flexipages');
fs.mkdirSync(OUT, { recursive: true });

const ITEM = /<itemInstances>(?:(?!<itemInstances>)[\s\S])*?<\/itemInstances>\s*/g;

function regionBlocks(x) {
    return [...x.matchAll(/<flexiPageRegions>[\s\S]*?<\/flexiPageRegions>\s*/g)].map(m => m[0]);
}
function regionName(block) {
    return [...block.matchAll(/<name>([^<]*)<\/name>\s*<type>(?:Region|Facet)<\/type>/g)].pop()[1];
}
// Remove one itemInstance by identifier, then any facet regions it (transitively) referenced.
function removeItem(x, identifier) {
    let removed = null;
    const regions = regionBlocks(x);
    for (const block of regions) {
        const items = block.match(ITEM) || [];
        const hit = items.find(i => i.includes(`<identifier>${identifier}</identifier>`));
        if (hit) {
            removed = hit;
            x = x.replace(block, block.replace(hit, ''));
            break;
        }
    }
    if (!removed) throw new Error('identifier not found: ' + identifier);
    const facets = [...removed.matchAll(/<value>([^<]+)<\/value>/g)].map(m => m[1]);
    for (const f of facets) x = removeFacet(x, f);
    return x;
}
function removeFacet(x, name) {
    const block = regionBlocks(x).find(b => regionName(b) === name && /<type>Facet<\/type>/.test(b));
    if (!block) return x;
    x = x.replace(block, '');
    for (const item of block.match(ITEM) || []) {
        for (const m of item.matchAll(/<value>([^<]+)<\/value>/g)) x = removeFacet(x, m[1]);
    }
    return x;
}
function replaceInItem(x, identifier, fn) {
    const item = (x.match(ITEM) || []).find(i => i.includes(`<identifier>${identifier}</identifier>`));
    if (!item) throw new Error('identifier not found: ' + identifier);
    const next = fn(item);
    if (next === item) throw new Error('no change for ' + identifier);
    return x.replace(item, next);
}
function relabel(x, label) {
    return x.replace(/<masterLabel>[^<]*<\/masterLabel>/, `<masterLabel>${label}</masterLabel>`);
}
function write(name, x) {
    fs.writeFileSync(path.join(OUT, name + '.flexipage-meta.xml'), x);
    console.log('wrote', name);
}
const read = n => fs.readFileSync(path.join(SRC, n + '.flexipage'), 'utf8');

const IS_PERSON = `<visibilityRule>
                    <criteria>
                        <leftValue>{!Record.IsPersonAccount}</leftValue>
                        <operator>EQUAL</operator>
                        <rightValue>true</rightValue>
                    </criteria>
                </visibilityRule>
            </componentInstance>`;

// ---- Lead ----
let lead = read('Lead_Expandable_Record_Page');
for (const id of ['homeToolsDrawer_main', 'TwilioSF_TwoWayMessages']) lead = removeItem(lead, id);
write('LO_Workspace_Lead_Record_Page', relabel(lead, 'LO Workspace Lead Record Page'));

// ---- Transaction ----
let tx = read('Transaction_Expandable_Record_Page');
for (const id of [
    'homeToolsDrawer_main',      // Command Center drawer
    'c_transactionDocuSign',     // DocuSign
    'flexipage_tab7',            // Conditions (ops; hidden from LO profiles anyway)
    'flexipage_tab10',           // IRS Form 1098 (admin)
    'flexipage_tab11',           // Submission Quality (editable for non-"Loan Officer Profile" ids; writes the loan)
    'flexipage_tab4',            // Checklist (opener / post-closing / closing+funding update actions)
    'flexipage_tab5',            // Wire Request walk-through
    'console_relatedRecord3'     // Active Appraisal Order update action
]) tx = removeItem(tx, id);
// Highlights panel: drop the Edit dynamic action.
tx = replaceInItem(tx, 'force_highlightsPanel', i => i.replace(
    /(<name>actionNames<\/name>)\s*<valueList>[\s\S]*?<\/valueList>/, '$1'));
// Path: no "Mark Status as Complete" (needs Edit).
tx = replaceInItem(tx, 'runtime_sales_pathassistant_pathAssistant', i => i.replace(
    /(<name>hideUpdateButton<\/name>\s*<value>)false/, '$1true'));
// Action strip: allowlist.
tx = replaceInItem(tx, 'transactionQuickActions', i => i.replace(
    '<componentInstance>',
    `<componentInstance>
                <componentInstanceProperties>
                    <name>allowedActions</name>
                    <value>Transaction__c.Application_Template,Transaction__c.Submission_Form_Modern,Transaction__c.Change_of_Circumstances,Transaction__c.Back_Under_Contract</value>
                </componentInstanceProperties>`));
// Appraisal tab: view + comments panel instead of the ordering component.
tx = replaceInItem(tx, 'c_AppraisalOrder', i => i
    .replace('<componentName>AppraisalOrder</componentName>', '<componentName>loWsAppraisalPanel</componentName>')
    .replace('<identifier>c_AppraisalOrder</identifier>', '<identifier>c_loWsAppraisalPanel</identifier>'));
write('LO_Workspace_Transaction_Record_Page', relabel(tx, 'LO Workspace Transaction Record Page'));

// ---- Account (Person Account page; business accounts also land here in this app) ----
let acct = read('Person_Account_Record_Page');
for (const id of ['homeToolsDrawer_main', 'TwilioSF_TwoWayMessages', 'c_bdLogTouchCard']) acct = removeItem(acct, id);
for (const id of ['c_accountRecordHero', 'c_accountActivityAssistant']) {
    acct = replaceInItem(acct, id, i => /<visibilityRule>/.test(i) ? i : i.replace(/<\/componentInstance>/, IS_PERSON));
}
write('LO_Workspace_Account_Record_Page', relabel(acct, 'LO Workspace Account Record Page'));
