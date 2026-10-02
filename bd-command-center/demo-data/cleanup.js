// Removes every demo record listed in manifest.json, children first.
//   node cleanup.js          -> writes one CRLF csv per object into ./cleanup and prints the commands
// Deletes go to the Recycle Bin (15 days), so a mistake is recoverable.
const fs = require('fs');
const m = JSON.parse(fs.readFileSync(__dirname + '/manifest.json', 'utf8'));
const ORDER = [
    ['campaignMembers', 'CampaignMember'],
    ['campaignMemberStatuses', 'CampaignMemberStatus'],
    ['events', 'Event'],
    ['tasks', 'Task'],
    ['emailMessages', 'EmailMessage'],
    ['callInsights', 'Call_Insight__c'],
    ['callLogs', 'Call_Log__c'],
    ['campaigns', 'Campaign'],
    ['accounts', 'Account']
];
fs.mkdirSync(__dirname + '/cleanup', { recursive: true });
ORDER.forEach(([key, sobject], i) => {
    const ids = key === 'accounts' ? m.accounts.map((a) => a.id) : m[key];
    // CampaignMemberStatus rows go with their campaign; the "Sent/Responded" defaults cannot be deleted directly.
    if (!ids || !ids.length || sobject === 'CampaignMemberStatus') return;
    const file = `cleanup/${i + 1}-${sobject}.csv`;
    fs.writeFileSync(__dirname + '/' + file, ['Id'].concat(ids).join('\r\n') + '\r\n');
    console.log(`sf data delete bulk -o Production -s ${sobject} -f ${file} -w 10`);
});
console.log('\nThen: any activities automation added later to these partners go with the Account delete.');
console.log('Optional: turn Marketing User back off for clowman@reachhomeloans.com (see manifest notes).');
