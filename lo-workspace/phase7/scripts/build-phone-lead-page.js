// Builds LO_Workspace_Lead_Phone_Record_Page from a fresh prod retrieve of Lead_Record_Page in ../ref.
// Re-run after a fresh retrieve: node scripts/build-phone-lead-page.js
const fs = require('fs');
const path = require('path');
const ROOT = path.join(__dirname, '..');
const SRC = path.join(ROOT, 'ref/src/main/default/flexipages/Lead_Record_Page.flexipage-meta.xml');
const OUT = path.join(ROOT, 'force-app/main/default/flexipages/LO_Workspace_Lead_Phone_Record_Page.flexipage-meta.xml');

let x = fs.readFileSync(SRC, 'utf8');
const ITEM = /\s*<itemInstances>(?:(?!<itemInstances>)[\s\S])*?<\/itemInstances>/g;
for (const id of ['homeToolsDrawer_main', 'TwilioSF_TwoWayMessages']) {
    const hit = (x.match(ITEM) || []).find(i => i.includes(`<identifier>${id}</identifier>`));
    if (hit) x = x.replace(hit, '');
    else console.log('not on the page (nothing to strip):', id);
}
if (/homeToolsDrawer|TwilioSF/.test(x)) throw new Error('drawer/Twilio still present');
x = x.replace(/<masterLabel>[^<]*<\/masterLabel>/, '<masterLabel>LO Workspace Lead Phone Record Page</masterLabel>');
fs.writeFileSync(OUT, x);
console.log('wrote', path.basename(OUT));
