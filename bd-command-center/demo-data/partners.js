// Demo partners for the CEO presentation (2026-09-30). Every record is tagged with MARKER in
// Description and listed in manifest.json so cleanup.md can remove it all afterwards.
// Phones use the reserved 555-01xx block and emails use example.com: nothing can reach a person.
const MARKER = 'BD DEMO DATA - delete after CEO demo';

// [first, last, company, industry, stage, areaCode, lineSuffix]
const PARTNERS = [
    ['Priya', 'Shah', 'Keystone Realty Tampa Bay', 'Realtor', 'Meeting Set', '813', '0142'],
    ['Dana', 'Whitfield', 'Harbor & Main Realty', 'Realtor', 'Contacted', '813', '0151'],
    ['Marcus', 'Ortega', 'Ortega Tax Group', 'CPA', 'Contacted', '727', '0163'],
    ['Kelsey', 'Lin', 'Suncoast Title Partners', 'Title Agent', 'Active Partner', '813', '0174'],
    ['Jordan', 'Pierce', 'Pierce Insurance Group', 'Insurance Agent', 'Contacted', '727', '0185'],
    ['Greg', 'Ellison', 'Ellison Wealth Partners', 'Financial Planner', 'Met', '813', '0196'],
    ['Nora', 'Castillo', 'Gulf Coast Title Co.', 'Title Agent', 'Met', '727', '0107'],
    ['Ben', 'Alvarez', 'Bayside Realty Group', 'Realtor', 'Active Partner', '813', '0118'],
    ['Sam', 'Patel', 'Sunshine Homes Realty', 'Realtor', 'Contacted', '954', '0129'],
    ['Tom', 'Nguyen', 'Nguyen & Associates CPAs', 'CPA', 'Meeting Set', '954', '0131'],
    ['Rachel', 'Kim', 'Harborline Insurance', 'Insurance Agent', 'Prospect', '727', '0145'],
    ['Alicia', 'Brenner', 'Coastal Premier Properties', 'Realtor', 'Prospect', '813', '0156'],
    ['Michael', 'Reyes', 'Reyes Family Law', 'Attorney', 'Contacted', '813', '0167'],
    ['Laura', 'Chen', 'Chen Custom Homes', 'Builder', 'Dormant', '954', '0178'],
    ['Derek', 'Foster', 'Foster CPA Group', 'CPA', 'Met', '727', '0189']
];

module.exports = { MARKER, PARTNERS };

if (require.main === module) {
    const records = PARTNERS.map(([first, last, company, industry, stage, area, line]) => ({
        attributes: { type: 'Account', referenceId: (first + last).replace(/\W/g, '') },
        RecordTypeId: '012f20000010aScAAI',
        FirstName: first,
        LastName: last,
        PersonTitle: company,
        PersonMobilePhone: `(${area}) 555-${line}`,
        PersonEmail: `${first}.${last}`.toLowerCase() + '@example.com',
        BD_Rep__c: '005Qi00000iOSkzIAG',
        OwnerId: '005Qi00000iOSkzIAG',
        BD_Industry__c: industry,
        BD_Stage__c: stage,
        Type__c: 'Other',
        Description: MARKER
    }));
    require('fs').writeFileSync(__dirname + '/accounts.json', JSON.stringify({ records }, null, 2));
    console.log(records.length + ' partners written to accounts.json');
}
