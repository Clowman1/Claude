// One-off: writes the Influencer Partners field metadata. Run from influencer-partners/.
const fs = require('fs');
const base = 'force-app/main/default/objects/';
const head = '<?xml version="1.0" encoding="UTF-8"?>\n<CustomField xmlns="http://soap.sforce.com/2006/04/metadata">\n';
const esc = s => s.replace(/&/g, '&amp;');
function picklist(values) {
    return '    <type>Picklist</type>\n    <valueSet>\n        <restricted>true</restricted>\n        <valueSetDefinition>\n            <sorted>false</sorted>\n' +
        values.map(v => `            <value>\n                <fullName>${esc(v)}</fullName>\n                <default>false</default>\n                <label>${esc(v)}</label>\n            </value>\n`).join('') +
        '        </valueSetDefinition>\n    </valueSet>\n';
}
function write(obj, name, label, body, description) {
    fs.mkdirSync(base + obj + '/fields', { recursive: true });
    fs.writeFileSync(`${base}${obj}/fields/${name}.field-meta.xml`,
        head + `    <fullName>${name}</fullName>\n` + (description ? `    <description>${esc(description)}</description>\n` : '') +
        `    <label>${esc(label)}</label>\n` + body + '</CustomField>\n');
}
const text = len => `    <length>${len}</length>\n    <required>false</required>\n    <type>Text</type>\n`;
const plain = type => `    <required>false</required>\n    <type>${type}</type>\n`;

write('Account', 'Influencer_Stage__c', 'Influencer Stage', plain('').replace('    <type></type>\n', '') + picklist([
    'Target', 'Contacted', 'Meeting Booked', 'Follow Up', 'Marketing Agreement Signed',
    'Landing Page Launched & Tested', 'Active', 'Lost'
]), 'Influencer Partners pipeline stage. Set = this account is an influencer partner (never key off Type__c).');
write('Account', 'Influencer_Lost_Reason__c', 'Influencer Lost Reason', plain('').replace('    <type></type>\n', '') + picklist([
    'No response', 'Not interested', 'Audience not a fit', 'Terms declined', 'Went with competitor', 'Other'
]));
write('Account', 'Influencer_Lost_From_Stage__c', 'Influencer Lost From Stage', text(60), 'Stage the partner was in when marked Lost; Reopen returns here.');
write('Account', 'Influencer_Lost_Date__c', 'Influencer Lost Date', plain('Date'), 'Stops the monthly fee in cost math.');
write('Account', 'Biggest_Channel__c', 'Biggest Social Channel', plain('').replace('    <type></type>\n', '') + picklist([
    'YouTube', 'Instagram', 'TikTok', 'Facebook', 'Podcast', 'X', 'Other'
]));
write('Account', 'Channel_URL__c', 'Channel URL', plain('Url'));
write('Account', 'Audience_Size__c', 'Audience Size', '    <precision>12</precision>\n    <required>false</required>\n    <scale>0</scale>\n    <type>Number</type>\n    <unique>false</unique>\n');
write('Account', 'Offer_Website__c', 'Offer Website', plain('Url'));
write('Account', 'Influencer_Assigned_LO__c', 'Influencer Assigned LO',
    '    <deleteConstraint>SetNull</deleteConstraint>\n    <referenceTo>User</referenceTo>\n    <relationshipName>Influencer_Partner_Accounts</relationshipName>\n    <required>false</required>\n    <type>Lookup</type>\n',
    'Owns the borrower leads from this partner\'s intake link.');
write('Account', 'Influencer_Partner_Code__c', 'Influencer Partner Code',
    '    <caseSensitive>false</caseSensitive>\n    <externalId>false</externalId>\n' + text(40) + '    <unique>true</unique>\n',
    'Public intake link code (?partner=). Locks once the first lead arrives.');
write('Account', 'Influencer_Agreement_Signed__c', 'Influencer Agreement Signed', plain('Date'));
write('Account', 'Influencer_Monthly_Fee__c', 'Influencer Monthly Fee',
    '    <precision>10</precision>\n    <required>false</required>\n    <scale>2</scale>\n    <type>Currency</type>\n',
    'Flat monthly marketing fee (RESPA 8: never per lead or per loan).');
write('Account', 'Influencer_Notes__c', 'Influencer Notes', '    <length>5000</length>\n    <type>LongTextArea</type>\n    <visibleLines>5</visibleLines>\n');
write('Lead', 'Influencer_Partner_Code__c', 'Influencer Partner Code', text(40),
    'Set by the intake form from ?partner=. LeadInfluencerAttribution turns it into Referral Source + Lead Source.');
console.log('ok');
