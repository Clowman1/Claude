#!/usr/bin/env node
// Provision (or reconcile) an External Loan Officer in Reach prod.
//
//   node provision-external-lo.js hire.json            -> dry run: checks + plan, changes nothing
//   node provision-external-lo.js hire.json --apply    -> does it
//
// hire.json (see hire.example.json):
//   firstName, lastName, email (their RHL mailbox; also the Username), nmls, licensedStates [..],
//   phone?, mobile?, headshotUrl?, emailSignature?, ringCentral (bool), twilioSeat (bool)
//
// If a user with that Username already exists it RECONCILES: adds missing licences/permsets only,
// never overwrites fields (it reports differences instead).
// Decisions: lo-workspace/onboarding/ONBOARDING-GRILL.md (Q1, Q19-Q24).

const { execFileSync } = require('child_process');
const fs = require('fs');
const os = require('os');
const path = require('path');

const ORG = 'Production';
const API = '/services/data/v62.0';
const IDS = {
  profile: '00eQi00000CLknJIAT',        // External Loan Officer Profile
  role: '00EQi000003on2DMAQ',           // External Loan Officer
  psg: '0PGQi00000037jJOAQ',            // PSG External_Loan_Officer
  eacPsl: '0PLf2000000spdaGAA',         // Standard Einstein Activity Capture User (licence)
  eacPermset: '0PSf2000001ZdX6GAK',     // StandardEinsteinActivityCapturePsl (permset) - not in the PSG
  twilioPkg: '0505x000000H9JsAAK',      // TwilioSF package licence
  twilioPermset: '0PS5x000001UHPFGA4',  // Twilio_User
  ringCentralCallCenter: '04vAJ0000008OJSYA2',
};
const STATES = 'AL AK AZ AR CA CO CT DE DC FL GA HI ID IL IN IA KS KY LA ME MD MA MI MN MS MO MT NE NV NH NJ NM NY NC ND OH OK OR PA PR RI SC SD TN TX UT VT VA WA WV WI WY'.split(' ');

function sf(args) {
  const out = execFileSync('sf', [...args, '-o', ORG, '--json'], { encoding: 'utf8', shell: true, stdio: ['ignore', 'pipe', 'ignore'] });
  return JSON.parse(out);
}
function query(soql) {
  return sf(['data', 'query', '-q', `"${soql}"`]).result.records;
}
function post(sobject, body) {
  const f = path.join(os.tmpdir(), `prov-${Date.now()}.json`);
  fs.writeFileSync(f, JSON.stringify(body));
  try {
    // `api request rest` has no --json flag and prints the raw REST response. -b takes the body itself;
    // '@' makes it read the file (without it the path string is sent as the body).
    const out = execFileSync('sf', ['api', 'request', 'rest', `${API}/sobjects/${sobject}`, '-X', 'POST', '-b', `"@${f}"`, '-o', ORG],
      { encoding: 'utf8', shell: true, stdio: ['ignore', 'pipe', 'ignore'] });
    const res = JSON.parse(out.slice(out.search(/[[{]/)));
    if (!res.id) throw new Error(JSON.stringify(res));
    return res.id;
  } finally { fs.unlinkSync(f); }
}
const q = (s) => String(s).replace(/'/g, "\\'");

// ---------- validate input (trust boundary) ----------
const [file, flag] = process.argv.slice(2);
if (!file) { console.error('usage: node provision-external-lo.js hire.json [--apply]'); process.exit(2); }
const apply = flag === '--apply';
const hire = JSON.parse(fs.readFileSync(file, 'utf8'));
const errors = [];
for (const k of ['firstName', 'lastName', 'email', 'nmls']) if (!hire[k]) errors.push(`missing ${k}`);
if ('loanPartner' in hire || 'Loan_Partner__c' in hire) errors.push('Loan Partner must stay blank for outside LOs (Q24) - remove it');
if ('groups' in hire) errors.push('outside LOs are never added to sharing groups (Q24) - remove it');
const email = String(hire.email || '').trim().toLowerCase();
if (email && !/^[^@\s]+@reachhomeloans\.com$/.test(email)) errors.push('email must be their own @reachhomeloans.com mailbox');
if (hire.nmls && !/^\d{4,10}$/.test(String(hire.nmls))) errors.push('nmls must be digits');
const states = (hire.licensedStates || []).map((s) => String(s).toUpperCase());
if (!states.length) errors.push('licensedStates is empty');
const badStates = states.filter((s) => !STATES.includes(s));
if (badStates.length) errors.push(`unknown states: ${badStates.join(', ')}`);
if (errors.length) { console.error('INPUT ERRORS:\n - ' + errors.join('\n - ')); process.exit(1); }

// ---------- read org state ----------
console.log(`Checking prod for ${email} ...`);
const existing = query(`SELECT Id, IsActive, Email, ProfileId, UserRoleId, Loan_Partner__c, CallCenterId, NMLS__c, Licensed_States__c, LoWs_RingCentral_Required__c FROM User WHERE Username = '${q(email)}'`)[0];
const emailTwins = query(`SELECT Id, Username FROM User WHERE IsActive = true AND Email = '${q(email)}'`).filter((u) => !existing || u.Id !== existing.Id);
const sfLic = query(`SELECT TotalLicenses, UsedLicenses FROM UserLicense WHERE Name = 'Salesforce'`)[0];
const pkg = query(`SELECT AllowedLicenses, UsedLicenses FROM PackageLicense WHERE Id = '${IDS.twilioPkg}'`)[0];

let has = { psl: false, psg: false, eac: false, twilio: false, twilioPs: false };
let groups = [];
if (existing) {
  const id = existing.Id;
  has.psl = query(`SELECT Id FROM PermissionSetLicenseAssign WHERE AssigneeId = '${id}' AND PermissionSetLicenseId = '${IDS.eacPsl}'`).length > 0;
  const psa = query(`SELECT PermissionSetId, PermissionSetGroupId FROM PermissionSetAssignment WHERE AssigneeId = '${id}'`);
  has.psg = psa.some((a) => a.PermissionSetGroupId === IDS.psg);
  has.eac = psa.some((a) => a.PermissionSetId === IDS.eacPermset);
  has.twilioPs = psa.some((a) => a.PermissionSetId === IDS.twilioPermset);
  has.twilio = query(`SELECT Id FROM UserPackageLicense WHERE UserId = '${id}' AND PackageLicenseId = '${IDS.twilioPkg}'`).length > 0;
  groups = query(`SELECT Group.Name, Group.Type FROM GroupMember WHERE UserOrGroupId = '${id}'`);
}

// ---------- plan ----------
const blockers = [];
const warnings = [];
const plan = [];
if (emailTwins.length) blockers.push(`another active user already uses Email ${email} (${emailTwins.map((u) => u.Username).join(', ')}) - landing-page matching and email tools break`);

if (!existing) {
  if (sfLic.TotalLicenses - sfLic.UsedLicenses < 1) blockers.push(`no Salesforce licence free (${sfLic.UsedLicenses}/${sfLic.TotalLicenses})`);
  plan.push('create user (External Loan Officer Profile + role)');
} else {
  if (!existing.IsActive) blockers.push('user exists but is INACTIVE - reactivate in Setup first');
  if (existing.ProfileId !== IDS.profile) blockers.push('existing user is not on External Loan Officer Profile');
  if (existing.UserRoleId !== IDS.role) blockers.push('existing user is not in the External Loan Officer role');
  if (existing.Loan_Partner__c) blockers.push('existing user has User.Loan_Partner__c set - clear it in Setup (their leads would get a default Loan Partner)');
  if ((existing.Email || '').toLowerCase() !== email) warnings.push(`user Email is ${existing.Email}, not ${email} - landing-page email matching needs their own mailbox (not overwritten)`);
  if (existing.NMLS__c !== String(hire.nmls)) warnings.push(`NMLS on record is ${existing.NMLS__c || 'blank'} (hire says ${hire.nmls}) - not overwritten`);
  const have = (existing.Licensed_States__c || '').split(';').filter(Boolean).sort().join(';');
  if (have !== [...states].sort().join(';')) warnings.push(`Licensed states on record are ${have || 'blank'} (hire says ${states.join(';')}) - not overwritten`);
  if (hire.ringCentral && existing.CallCenterId !== IDS.ringCentralCallCenter) plan.push('set RingCentral call center');
  if (!!hire.ringCentral !== !!existing.LoWs_RingCentral_Required__c) warnings.push(`RingCentral-required gate flag on record is ${!!existing.LoWs_RingCentral_Required__c} (hire says ${!!hire.ringCentral}) - not overwritten; change User.LoWs_RingCentral_Required__c in Setup if intended`);
  const internal = groups.filter((g) => g.Group.Type === 'Regular' || g.Group.Type === 'Queue');
  if (internal.length) warnings.push(`user is in groups/queues: ${internal.map((g) => g.Group.Name).join(', ')} - outside LOs must not be (remove in Setup)`);
}
if (!has.psl) plan.push('assign Einstein Activity Capture licence');
if (!has.psg) plan.push('assign permission set group External_Loan_Officer');
if (!has.eac) plan.push('assign permission set StandardEinsteinActivityCapturePsl');
if (hire.twilioSeat) {
  if (!has.twilio) {
    if (pkg.AllowedLicenses - pkg.UsedLicenses < 1) blockers.push(`no Twilio seat free (${pkg.UsedLicenses}/${pkg.AllowedLicenses})`);
    plan.push('assign Twilio seat');
  }
  if (!has.twilioPs) plan.push('assign permission set Twilio_User');
}

console.log(`\n${existing ? 'RECONCILE existing user ' + existing.Id : 'NEW user'}  |  Salesforce licences ${sfLic.UsedLicenses}/${sfLic.TotalLicenses}  |  Twilio seats ${pkg.UsedLicenses}/${pkg.AllowedLicenses}`);
if (warnings.length) console.log('\nWARNINGS:\n - ' + warnings.join('\n - '));
if (blockers.length) { console.log('\nBLOCKED (nothing changed):\n - ' + blockers.join('\n - ')); process.exit(1); }
console.log('\nPLAN:\n' + (plan.length ? plan.map((p) => ' - ' + p).join('\n') : ' - nothing to do, already provisioned'));
if (!apply) { console.log('\nDry run - re-run with --apply to make these changes.'); process.exit(0); }

// ---------- apply ----------
let userId = existing && existing.Id;
if (!existing) {
  const alias = (hire.firstName[0] + hire.lastName).replace(/[^A-Za-z]/g, '').slice(0, 8).toLowerCase();
  const user = {
    Username: email, Email: email, FirstName: hire.firstName, LastName: hire.lastName, Alias: alias,
    ProfileId: IDS.profile, UserRoleId: IDS.role,
    TimeZoneSidKey: 'America/New_York', LocaleSidKey: 'en_US', EmailEncodingKey: 'ISO-8859-1', LanguageLocaleKey: 'en_US',
    Title: 'Loan Officer', Department: 'Sales',
    NMLS__c: String(hire.nmls), Licensed_States__c: states.join(';'),
    Enhanced_Note_Role__c: 'Loan Officer', Intake_Form_Notification__c: true, Include_in_Lead_Stagnant_Alerts__c: true,
  };
  if (hire.phone) user.Phone = hire.phone;
  if (hire.mobile) user.MobilePhone = hire.mobile;
  if (hire.headshotUrl) user.Headshot_URL__c = hire.headshotUrl;
  if (hire.emailSignature) user.Email_Signature__c = hire.emailSignature;
  if (hire.ringCentral) { user.CallCenterId = IDS.ringCentralCallCenter; user.LoWs_RingCentral_Required__c = true; } // RingCentral becomes a required first-login gate row (O2)
  userId = post('User', user);
  console.log(` + user created ${userId}`);
} else if (hire.ringCentral && existing.CallCenterId !== IDS.ringCentralCallCenter) {
  console.log(' ! set the RingCentral call center on the user in Setup (script does not overwrite existing users)');
}
// Order matters: the licence before the permset that needs it.
if (!has.psl) { post('PermissionSetLicenseAssign', { AssigneeId: userId, PermissionSetLicenseId: IDS.eacPsl }); console.log(' + EAC licence'); }
if (!has.psg) { post('PermissionSetAssignment', { AssigneeId: userId, PermissionSetGroupId: IDS.psg }); console.log(' + External_Loan_Officer PSG'); }
if (!has.eac) { post('PermissionSetAssignment', { AssigneeId: userId, PermissionSetId: IDS.eacPermset }); console.log(' + StandardEinsteinActivityCapturePsl'); }
if (hire.twilioSeat && !has.twilio) { post('UserPackageLicense', { UserId: userId, PackageLicenseId: IDS.twilioPkg }); console.log(' + Twilio seat'); }
if (hire.twilioSeat && !has.twilioPs) { post('PermissionSetAssignment', { AssigneeId: userId, PermissionSetId: IDS.twilioPermset }); console.log(' + Twilio_User'); }

console.log(`
DONE. Manual steps left for ${hire.firstName} ${hire.lastName} (${userId}):
 1. Setup > Users > ${email} > Reset Password  (API-created users get no welcome email)
 2. Setup > Einstein Activity Capture > Configurations > add the user  (Setup-only)
 3. Landing page: send marketing the endpoint + their username (${email}); the secret is in
    Setup > Custom Metadata Types > LO Landing Page Config > Default
 4. Zoom: create their user on Reach's Zoom account (${email}) - Chris
${hire.ringCentral ? ' 5. RingCentral: create their user/extension - Chris; they authorize the call-log sync on first login\n' : ''} Then Day 1 belongs to the LO: first login, MFA, Salesforce mobile app, Get connected, setup Q&A, tour.`);
