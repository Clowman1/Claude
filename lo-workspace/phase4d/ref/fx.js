const x=require('fs').readFileSync(process.argv[2],'utf8');
console.log('TEMPLATE', (x.match(/<pageTemplate>([^<]*)/)||[])[1], 'TYPE', (x.match(/<type>(RecordPage|AppPage)[^<]*/)||[])[0]);
const re=/<itemInstances>\s*<componentInstance>([\s\S]*?)<\/componentInstance>\s*<\/itemInstances>/g;let m;
while(m=re.exec(x)){const b=m[1];const cn=(b.match(/<componentName>([^<]*)/)||[])[1];if(/fieldSection|flexipage:column/.test(cn))continue;
const props=[...b.matchAll(/<componentInstanceProperties>\s*<name>([^<]*)<\/name>\s*(?:<type>[^<]*<\/type>\s*)?(?:<value>([^<]*)<\/value>)?/g)].map(p=>p[1]+'='+(p[2]||'').slice(0,50)).join(' | ');
const vis=(b.match(/<visibilityRule>[\s\S]*?<\/visibilityRule>/)||[''])[0].replace(/\s+/g,' ').replace(/<\/?(criteria|visibilityRule)>/g,'').slice(0,300);
console.log((x.slice(0,m.index).split('\n').length)+': '+cn+' :: '+(b.match(/<identifier>([^<]*)/)||[])[1]+' :: '+props+' '+vis);}
const av=[...x.matchAll(/<value>([A-Za-z_]+\.[A-Za-z_]+|[A-Z][A-Za-z_]+)<\/value>/g)];
