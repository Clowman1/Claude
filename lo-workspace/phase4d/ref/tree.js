const x=require('fs').readFileSync(process.argv[2],'utf8');
const regions={};const order=[];
for(const r of x.matchAll(/<flexiPageRegions>([\s\S]*?)<\/flexiPageRegions>/g)){
 const b=r[1]; const name=[...b.matchAll(/<name>([^<]*)<\/name>\s*<type>(Region|Facet)<\/type>/g)].pop();
 const items=[...b.matchAll(/<itemInstances>([\s\S]*?)<\/itemInstances>/g)].map(i=>{
  const c=i[1]; const cn=(c.match(/<componentName>([^<]*)/)||c.match(/<fieldItem>([^<]*)/)||[])[1];
  const id=(c.match(/<identifier>([^<]*)/)||[])[1];
  const facets=[...c.matchAll(/<value>(Facet-[^<]*|[a-zA-Z]+Content|tabs|maintabs|sidebartabs|detailTabContent)<\/value>/g)].map(m=>m[1]);
  const title=(c.match(/<name>(?:title|label)<\/name>\s*<value>([^<]*)/)||[])[1];
  const vis=/<visibilityRule>/.test(c)?' [VIS]':'';
  return {cn,id,facets,title,vis};});
 regions[name[1]]={type:name[2],items}; if(name[2]==='Region')order.push(name[1]);}
function pr(n,d){const r=regions[n];if(!r)return;let fields=0;
 for(const it of r.items){ if(!it.cn||/^Record\./.test(it.cn)){fields++;continue;}
  console.log('  '.repeat(d)+it.cn+(it.title?' "'+it.title+'"':'')+' #'+it.id+it.vis); for(const f of it.facets)pr(f,d+1);}
 if(fields)console.log('  '.repeat(d)+'('+fields+' fields)');}
for(const o of order){console.log('REGION '+o);pr(o,1);}
