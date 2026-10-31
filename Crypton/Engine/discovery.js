'use strict';
// Use the same SDK identity formatter as ME. The wallet owns lookup and trust;
// this adapter cannot publish certificates, consult wallet contacts or make payments.
window.runDiscovery = async request => {
  const operation = request.id; active = operation;
  try {
    let certificates = [];
    const lookup = async (call, args) => {
      const response = await deliveryRpc(operation,'walletDiscovery',{call,args});
      certificates = response.certificates;
      return response;
    };
    const client = new bsv.IdentityClient({
      discoverByAttributes:args=>lookup('discoverByAttributes',args),
      discoverByIdentityKey:args=>lookup('discoverByIdentityKey',args)
    });
    const results = request.method === 'discoverByIdentityKey'
      ? await client.resolveByIdentityKey(request.args,false)
      : await client.resolveByAttributes(request.args,false);
    live(operation);
    const result = results.map((identity,index)=>({
      key:identity.identityKey,name:identity.name || identity.identityKey,
      certification:identity.badgeLabel || 'Certificate returned by your wallet',
      certifier:certificates[index].certifier,certificateType:certificates[index].type
    }));
    active = null; post({event:'result',id:operation,result});
  } catch {
    if (active === operation) {
      active = null;
      post({event:'error',id:operation,message:'Recipient search failed. Return from ME, check wallet access and your connection, then retry.'});
    }
  }
};
