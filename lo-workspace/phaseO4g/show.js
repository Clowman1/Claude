const j=require('./validate.json');const r=j.result||{};const id=r.id||(j.data&&j.data.deployId);console.log(id,r.status||j.message);
