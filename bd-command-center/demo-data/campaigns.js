// Demo events for the CEO presentation, built the way the realtor event engine builds them.
// Step 1: node campaigns.js campaigns        -> campaigns.json (import, then)
// Step 2: node campaigns.js children         -> statuses.json, members.json, calendar.json
// RSVP_Reminder_Sent_At__c / Event_Reminder_Sent_At__c are pre-stamped so the nightly reminder
// batch never emails these example.com invitees.
const fs = require('fs');
const { MARKER } = require('./partners');
const manifest = JSON.parse(fs.readFileSync(__dirname + '/manifest.json', 'utf8'));
const FRED = '005Qi00000iOSkzIAG';
const contact = {};
manifest.accounts.forEach((a) => { contact[a.name.split(' ')[0]] = a.contactId; });

// [ref, name, date, time, minutes, location, outcome, members {first: status}]
const EVENTS = [
    ['E1', 'Coffee with Fred · Priya Shah', '2026-10-01', '08:30', 60, 'Kahwa Coffee, Central Ave', null, { Priya: 'Yes - Attending' }],
    ['E2', 'Lunch with Fred · Tom Nguyen', '2026-10-05', '12:00', 60, 'Ciccio, Water Street', null, { Tom: 'Invitation Sent' }],
    ['E3', 'Happy Hour: CPA & Title Partner Mixer', '2026-10-02', '17:30', 120, 'Ciccio Water Street rooftop', null,
        { Marcus: 'Yes - Attending', Derek: 'Yes - Attending', Kelsey: 'Yes - Attending', Greg: 'Yes - Attending',
          Nora: 'No - Unable to Attend', Tom: 'Invitation Sent', Jordan: 'Invitation Sent' }],
    ['E4', 'Coffee with Fred · Nora Castillo', '2026-09-22', '09:00', 60, 'Buddy Brew, Kennedy Blvd', 'Held', { Nora: 'Yes - Attending' }],
    ['E5', 'Lunch with Fred · Greg Ellison', '2026-09-23', '12:00', 60, 'Oxford Exchange', null, { Greg: 'Yes - Attending' }],
    ['E6', 'Coffee with Fred · Ben Alvarez', '2026-09-10', '08:00', 60, 'Kahwa Coffee, Central Ave', 'Held', { Ben: 'Yes - Attending' }]
];
const STATUSES = [
    ['Invite List', false], ['Invitation Queued', false], ['Invitation Sent', false],
    ['Yes - Attending', true], ['No - Unable to Attend', true]
];
const strip = (k, v) => (v === null ? undefined : v);

if (process.argv[2] === 'campaigns') {
    const records = EVENTS.map(([ref, name, date, time, , location, outcome]) => ({
        attributes: { type: 'Campaign', referenceId: ref },
        Name: name, Type: 'Event', Status: date < '2026-09-29' ? 'Completed' : 'Planned', IsActive: true,
        StartDate: date, EndDate: date, Event_Time__c: time + ':00.000Z', OwnerId: FRED,
        Description: 'Location: ' + location, BD_Outcome__c: outcome
    }));
    fs.writeFileSync(__dirname + '/campaigns.json', JSON.stringify({ records }, strip, 2));
    console.log(records.length + ' campaigns');
} else {
    const imported = JSON.parse(fs.readFileSync(__dirname + '/import-campaigns.json', 'utf8').replace(/^[^{]*/, '')).result;
    const idOf = {};
    imported.forEach((r) => { idOf[r.refId] = r.id; });
    const statuses = [], members = [], calendar = [];
    EVENTS.forEach(([ref, name, date, time, minutes, location, , invited]) => {
        STATUSES.forEach(([label, responded], i) => statuses.push({
            attributes: { type: 'CampaignMemberStatus', referenceId: ref + 'S' + i },
            CampaignId: idOf[ref], Label: label, SortOrder: 3 + i, IsDefault: false, HasResponded: responded
        }));
        const invitedAt = new Date(new Date(date + 'T12:00:00Z').getTime() - 6 * 86400000).toISOString().replace('.000Z', '.000+0000');
        Object.keys(invited).forEach((first, i) => members.push({
            attributes: { type: 'CampaignMember', referenceId: ref + 'M' + i },
            CampaignId: idOf[ref], ContactId: contact[first], Status: invited[first],
            Event_Invite_Token__c: 'demo' + ref + i, Invite_Email_Sent_At__c: invitedAt, Invite_SMS_Sent_At__c: invitedAt,
            RSVP_Reminder_Sent_At__c: invitedAt, Event_Reminder_Sent_At__c: invitedAt
        }));
        const start = new Date(`${date}T${time}:00-04:00`);
        calendar.push({
            attributes: { type: 'Event', referenceId: ref + 'C' },
            WhatId: idOf[ref], OwnerId: FRED, Subject: name, Location: location, Description: MARKER,
            StartDateTime: start.toISOString().replace('.000Z', '.000+0000'),
            EndDateTime: new Date(start.getTime() + minutes * 60000).toISOString().replace('.000Z', '.000+0000')
        });
    });
    fs.writeFileSync(__dirname + '/statuses.json', JSON.stringify({ records: statuses }, strip, 2));
    fs.writeFileSync(__dirname + '/members.json', JSON.stringify({ records: members }, strip, 2));
    fs.writeFileSync(__dirname + '/calendar.json', JSON.stringify({ records: calendar }, strip, 2));
    console.log(statuses.length + ' statuses, ' + members.length + ' members, ' + calendar.length + ' calendar events');
}
