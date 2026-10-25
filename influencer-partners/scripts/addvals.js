// One-off: add the Influencer picklist values to the freshly retrieved metadata. Run from influencer-partners/.
const fs = require('fs');
const base = 'force-app/main/default/';
function edit(path, fn) {
    const p = base + path;
    const s = fs.readFileSync(p, 'utf8');
    const o = fn(s);
    if (o === s) throw new Error('no change ' + path);
    fs.writeFileSync(p, o);
}
function rt(path, picklist, value) {
    const tag = '<picklist>' + picklist + '</picklist>';
    edit(path, s => {
        const i = s.indexOf(tag);
        if (i < 0) throw new Error('no picklist ' + picklist + ' in ' + path);
        return s.slice(0, i + tag.length) +
            `\n        <values>\n            <fullName>${value}</fullName>\n            <default>false</default>\n        </values>` +
            s.slice(i + tag.length);
    });
}
function fieldValue(path, value) {
    edit(path, s => s.replace('</valueSetDefinition>',
        `    <value>\n                <fullName>${value}</fullName>\n                <default>false</default>\n                <label>${value}</label>\n            </value>\n        </valueSetDefinition>`));
}
edit('standardValueSets/LeadSource.standardValueSet-meta.xml', s => s.replace('</StandardValueSet>',
    `    <standardValue>\n        <fullName>Influencer Partners</fullName>\n        <default>false</default>\n        <label>Influencer Partners</label>\n    </standardValue>\n</StandardValueSet>`));
for (const r of ['Consumer_Lead_record_type', 'Realtor_Lead_record_type', 'Loan_Officer_Lead_Record_Type'])
    rt(`objects/Lead/recordTypes/${r}.recordType-meta.xml`, 'LeadSource', 'Influencer Partners');
fieldValue('objects/Transaction__c/fields/Lead_Source__c.field-meta.xml', 'Influencer Partners');
for (const r of ['Brokered', 'Correspondent'])
    rt(`objects/Transaction__c/recordTypes/${r}.recordType-meta.xml`, 'Lead_Source__c', 'Influencer Partners');
fieldValue('objects/Account/fields/Type__c.field-meta.xml', 'Influencer Partner');
rt('objects/PersonAccount/recordTypes/PersonAccount.recordType-meta.xml', 'Type__c', 'Influencer Partner');
console.log('ok');
