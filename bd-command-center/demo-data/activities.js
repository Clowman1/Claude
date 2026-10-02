// Builds the demo touches for the partners in manifest.json. Run: node activities.js
// Dates are relative to 2026-09-29 (Eastern, UTC-4) so the "needs a touch" queue has a spread.
const fs = require('fs');
const { MARKER } = require('./partners');
const manifest = JSON.parse(fs.readFileSync(__dirname + '/manifest.json', 'utf8'));
const FRED = '005Qi00000iOSkzIAG';
const FRED_NUMBER = '+17542901871';
const TODAY = new Date(Date.UTC(2026, 8, 29));

const acc = {};
manifest.accounts.forEach((a) => { acc[a.name.split(' ')[0]] = a; });
const phone = {
    Priya: '+18135550142', Dana: '+18135550151', Marcus: '+17275550163', Kelsey: '+18135550174', Jordan: '+17275550185',
    Greg: '+18135550196', Nora: '+17275550107', Ben: '+18135550118', Sam: '+19545550129', Tom: '+19545550131',
    Michael: '+18135550167', Laura: '+19545550178', Derek: '+17275550189'
};

function at(daysAgo, hour, minute = 0) {
    const d = new Date(TODAY.getTime() - daysAgo * 86400000);
    d.setUTCHours(hour + 4, minute, 0, 0);
    return d.toISOString().replace('.000Z', '.000+0000');
}
const day = (iso) => iso.slice(0, 10);

let n = 0;
const tasks = [];
function call(who, daysAgo, hour, minute, direction, seconds, note) {
    const start = at(daysAgo, hour, minute);
    const inbound = direction === 'Inbound';
    tasks.push({
        attributes: { type: 'Task', referenceId: 'T' + (++n) },
        OwnerId: FRED,
        WhatId: who ? acc[who].id : null,
        Subject: inbound ? 'Inbound Call' : 'Outbound Call',
        InteractionType__c: 'Call',
        CallType: direction,
        CallDurationInSeconds: seconds,
        rcsfl__call_start_time__c: start,
        rcsfl__from_number__c: inbound ? (who ? phone[who] : note.number) : FRED_NUMBER,
        rcsfl__to_number__c: inbound ? FRED_NUMBER : (who ? phone[who] : note.number),
        Status: 'Completed',
        ActivityDate: day(start),
        Description: who ? note : null
    });
}
function text(who, daysAgo, hour, minute, direction, body) {
    const start = at(daysAgo, hour, minute);
    const inbound = direction === 'Inbound';
    tasks.push({
        attributes: { type: 'Task', referenceId: 'T' + (++n) },
        OwnerId: FRED,
        WhatId: acc[who].id,
        Subject: inbound ? 'Inbound SMS' : 'Outbound SMS',
        InteractionType__c: 'Sms',
        CallType: direction,
        rcsfl__call_start_time__c: start,
        rcsfl__from_number__c: inbound ? phone[who] : FRED_NUMBER,
        rcsfl__to_number__c: inbound ? FRED_NUMBER : phone[who],
        Status: 'Completed',
        ActivityDate: day(start),
        Description: body
    });
}

// ---- calls and texts (Sunday 9/27 onward counts as "this week")
call('Priya', 2, 10, 14, 'Outbound', 372, 'Walked through our 10-day close and the pre-approval portal. Has 3 buyers shopping, wants to meet.');
text('Priya', 2, 10, 32, 'Outbound', 'Great talking today! Coffee Thursday 8:30 at Kahwa on Central work for you?');
text('Priya', 2, 11, 5, 'Inbound', 'Perfect, see you Thursday!');
call('Priya', 6, 16, 52, 'Inbound', 160, 'Returned my intro voicemail. Frustrated with her current lender on communication.');
call('Dana', 21, 13, 20, 'Outbound', 0, 'No answer, left voicemail.');
text('Dana', 22, 9, 45, 'Outbound', 'Hi Dana, Fred with Reach Home Loans. Would love to buy you a coffee and hear what your buyers need.');
call('Marcus', 17, 11, 0, 'Outbound', 245, 'Tax season prep. Open to referring self-employed clients who need bank-statement loans.');
call('Kelsey', 36, 15, 10, 'Outbound', 410, 'Title turn times and our closing calendar. Very responsive team.');
call('Jordan', 15, 14, 5, 'Outbound', 198, 'Bundling homeowners quotes into our pre-approval packet. Wants a one-pager.');
call('Greg', 8, 10, 30, 'Inbound', 305, 'Clients relocating from NY with large down payments. Confirmed lunch.');
text('Nora', 7, 12, 15, 'Outbound', 'Thanks again for coffee Nora. Sending over our closing checklist now.');
call('Ben', 1, 17, 40, 'Inbound', 486, 'Two new buyers ready to go. Sending them over tomorrow.');
call('Ben', 12, 9, 15, 'Outbound', 223, 'Checked in on the Palma Ceia listing. Buyer financing questions.');
call('Sam', 1, 11, 25, 'Outbound', 110, 'Intro call. Busy week, asked to reconnect after his open house.');
call('Tom', 4, 15, 45, 'Outbound', 318, 'Discussed first-time-buyer clients. Lunch invite going out.');
call('Michael', 19, 10, 0, 'Outbound', 132, 'Divorce refinances and buyouts. Wants to understand the timeline.');
call('Laura', 62, 13, 30, 'Outbound', 95, 'New build construction-to-perm question. Paused her spec homes this year.');
call('Derek', 0, 9, 10, 'Outbound', 0, 'No answer, left voicemail about the happy hour.');
text('Derek', 0, 9, 12, 'Outbound', 'Hi Derek, looking forward to Friday! Parking is free after 5 at the garage on Water St.');
// ---- two calls Salesforce can't match to anyone yet (Unmatched calls tray)
call(null, 0, 11, 48, 'Inbound', 142, { number: '+18135550199' });
call(null, 1, 14, 20, 'Inbound', 67, { number: '+17275550192' });
// ---- logged in-person touch
tasks.push({
    attributes: { type: 'Task', referenceId: 'T' + (++n) }, OwnerId: FRED, WhatId: acc.Derek.id,
    Subject: 'BD Touch: In person', Status: 'Completed', ActivityDate: day(at(10, 12)),
    Description: 'Coffee at Oxford Exchange. Introduced us to two partners at his firm.'
});

// ---- past calendar meetings on the partner (touch = start time)
const events = [];
function meeting(who, daysAgo, hour, subject, location, minutes = 60) {
    const start = at(daysAgo, hour);
    const end = new Date(new Date(start.replace('+0000', 'Z')).getTime() + minutes * 60000).toISOString().replace('.000Z', '.000+0000');
    events.push({
        attributes: { type: 'Event', referenceId: 'E' + (events.length + 1) },
        OwnerId: FRED, WhatId: acc[who].id, Subject: subject, Location: location,
        StartDateTime: start, EndDateTime: end, Description: 'Demo meeting'
    });
}
meeting('Kelsey', 34, 12, 'Lunch with Kelsey Lin', 'Ulele, Highland Ave');
meeting('Derek', 10, 8, 'Coffee with Derek Foster', 'Oxford Exchange');
meeting('Laura', 60, 11, 'Site visit: Chen Custom Homes', 'South Tampa model home');

// ---- logged emails
const emails = [];
function email(who, daysAgo, hour, incoming, subject, body) {
    const a = manifest.accounts.find((x) => x.name.startsWith(who));
    const addr = a.name.toLowerCase().replace(' ', '.') + '@example.com';
    emails.push({
        attributes: { type: 'EmailMessage', referenceId: 'M' + (emails.length + 1) },
        RelatedToId: a.id, Subject: subject, TextBody: body, HtmlBody: '<p>' + body + '</p>',
        FromName: incoming ? a.name : 'Fred Carlton', FromAddress: incoming ? addr : 'fred@reachhomeloans.com',
        ToAddress: incoming ? 'fred@reachhomeloans.com' : addr, MessageDate: at(daysAgo, hour),
        Status: '3', Incoming: incoming
    });
}
email('Marcus', 18, 9, false, 'Bank-statement loans for your self-employed clients', 'Marcus, great connecting. Attached is our one-page overview of bank-statement and P&L programs.');
email('Ben', 3, 16, true, 'Buyer intro: the Hendersons', 'Fred, introducing you to the Hendersons. Pre-approval needed by Friday for a Seminole Heights offer.');
email('Tom', 4, 17, false, 'Lunch next week?', 'Tom, thanks for the call today. I sent a lunch invite for next Monday at Ciccio.');
email('Greg', 5, 10, true, 'Re: Relocation clients', 'Fred, sending two relocation clients your way after our lunch. Both have 30%+ down.');

// ---- RingSense (ACE) insights on the richest calls
const insights = [];
function insight(who, daysAgo, hour, minute, direction, duration, title, summary, bullets, highlights, next, score) {
    insights.push({
        attributes: { type: 'Call_Insight__c', referenceId: 'I' + (insights.length + 1) },
        Account__c: acc[who].id, Salesforce_User__c: FRED, Title__c: title, Direction__c: direction,
        Duration__c: duration, Recording_Start_DateTime__c: at(daysAgo, hour, minute), AI_Score__c: score,
        Summary__c: '<p>' + summary + '</p>',
        Bulleted_Summary__c: '<ul>' + bullets.map((b) => '<li>' + b + '</li>').join('') + '</ul>',
        HighLights__c: '<ul>' + highlights.map((b) => '<li>' + b + '</li>').join('') + '</ul>',
        Next_Steps__c: '<ul>' + next.map((b) => '<li>' + b + '</li>').join('') + '</ul>',
        Transcript__c: 'Demo transcript. ' + MARKER
    });
}
insight('Priya', 2, 10, 14, 'Outbound', '6m 12s', 'Intro call with Priya Shah (Keystone Realty)',
    'Fred introduced Reach Home Loans and the 10-day close. Priya has three buyers actively shopping and is unhappy with communication from her current lender. She agreed to meet for coffee Thursday.',
    ['Three active buyers, two first-time', 'Current lender slow to return calls', 'Interested in the borrower document portal'],
    ['"If you can get my buyers pre-approved same day, I will send you everything."'],
    ['Coffee Thursday 8:30 at Kahwa', 'Send portal walkthrough video before the meeting'], 8.7);
insight('Ben', 1, 17, 40, 'Inbound', '8m 06s', 'Ben Alvarez: two new buyer referrals',
    'Ben called with two new buyers ready to move. One needs a pre-approval by Friday for a Seminole Heights offer. Ben praised the last closing and wants to co-host an open house.',
    ['Two referrals incoming', 'Pre-approval deadline Friday', 'Open-house co-marketing idea'],
    ['"Your team made my last closing the easiest one this year."'],
    ['Watch for the Henderson intro email', 'Propose open-house date in October'], 9.2);
insight('Tom', 4, 15, 45, 'Outbound', '5m 18s', 'Tom Nguyen: first-time buyer clients',
    'Tom works with many young professionals filing first-year returns. He is open to referring clients but wants to understand how self-employment income is documented.',
    ['Young-professional client base', 'Needs clarity on self-employed documentation'],
    ['"Half my new clients ask me about buying their first home."'],
    ['Lunch next Monday at Ciccio', 'Bring self-employed documentation checklist'], 7.9);
insight('Marcus', 17, 11, 0, 'Outbound', '4m 05s', 'Marcus Ortega: bank-statement loans',
    'Marcus referred clients elsewhere in the past and is open to a new lender. Interested in bank-statement programs for self-employed clients.',
    ['Self-employed client base', 'Previously referred to a competitor'],
    ['"My self-employed folks get turned down constantly."'],
    ['Follow up after tax deadline', 'Invite to the CPA and Title mixer'], 7.4);

fs.writeFileSync(__dirname + '/tasks.json', JSON.stringify({ records: tasks }, (k, v) => (v === null ? undefined : v), 2));
fs.writeFileSync(__dirname + '/events.json', JSON.stringify({ records: events }, (k, v) => (v === null ? undefined : v), 2));
fs.writeFileSync(__dirname + '/emails.json', JSON.stringify({ records: emails }, (k, v) => (v === null ? undefined : v), 2));
fs.writeFileSync(__dirname + '/insights.json', JSON.stringify({ records: insights }, (k, v) => (v === null ? undefined : v), 2));
console.log(tasks.length + ' tasks, ' + events.length + ' events, ' + emails.length + ' emails, ' + insights.length + ' insights');
