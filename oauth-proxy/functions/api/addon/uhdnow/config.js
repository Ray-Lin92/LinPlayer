// POST /api/addon/uhdnow/config   body: { serverUrl, username, password }
//
// 把某台 uhdnow 服务器对应的账号密码写入 KV（绑定名 ADDON_KV），供 homeStats 端点
// 登录取流量。支持多用户各存各的，且不重新部署即可更新。
//
// 安全：本端点受 _middleware.js 的可选共享密钥（LINPLAYER_PROXY_KEY）保护；建议开启。
// 传 password:'' 或省略可清除该 serverUrl 的凭据。
//
// 前置：Cloudflare Pages → Settings → Functions → KV namespace bindings，
//       绑定一个 KV 命名空间，变量名填 ADDON_KV。
export async function onRequestPost({ request, env }) {
  if (!env.ADDON_KV) {
    return new Response(
      JSON.stringify({ error: 'KV 未绑定（需绑定 ADDON_KV 命名空间）' }),
      { status: 500, headers: { 'Content-Type': 'application/json' } },
    );
  }

  const input = await request.json().catch(() => ({}));
  const serverUrl = (input.serverUrl || '').trim();
  if (!serverUrl) {
    return new Response(JSON.stringify({ error: 'serverUrl required' }), {
      status: 400,
      headers: { 'Content-Type': 'application/json' },
    });
  }

  const key = `uhdnow:${serverUrl}`;
  if (!input.username || !input.password) {
    await env.ADDON_KV.delete(key);
    return new Response(JSON.stringify({ ok: true, cleared: true }), {
      headers: { 'Content-Type': 'application/json' },
    });
  }

  await env.ADDON_KV.put(
    key,
    JSON.stringify({ username: input.username, password: input.password }),
  );
  return new Response(JSON.stringify({ ok: true }), {
    headers: { 'Content-Type': 'application/json' },
  });
}
