// GET /api/addon/uhdnow/homeStats?serverUrl=..  ->  { metrics: [ { label, value } ] }
//
// 这是"逻辑上服务端"的示范：把原 uhdnow-traffic 插件里 data 表达不了的有状态/需计算
// 流程（登录换 token → 带 token 拉流量 → 算剩余 → 格式化 GB）搬到这里。
//
// 凭据存储优先级：
//   1) KV（推荐）：绑定名 ADDON_KV 的 KV 命名空间，键 `uhdnow:<serverUrl>` -> {username,password}。
//      支持多用户各存各的、且不重新部署即可更新（用 config 端点写入）。
//   2) 环境变量回退（单账号便捷）：UHDNOW_USERNAME / UHDNOW_PASSWORD。
// 两者都不进 App、不经 query 明文传输。
//
// 接口（同原插件，逆向自 www.uhdnow.com，已实测）：
//   POST /api/v1/auth/login {username,password} -> { ok, data:{ token } }
//   GET  /api/v1/traffic/me (Header Authorization: <token>) -> { ok, data:{ used_bytes, limit_bytes } }

const API_BASE = 'https://www.uhdnow.com';
const GiB = 1073741824;

function json(body) {
  return new Response(JSON.stringify(body), {
    headers: { 'Content-Type': 'application/json' },
  });
}

const gb = (bytes) => (Number(bytes) || 0) / GiB;

// 取该 serverUrl 对应的凭据：先 KV，后环境变量。
async function resolveCreds(env, serverUrl) {
  if (env.ADDON_KV) {
    try {
      const hit = await env.ADDON_KV.get(`uhdnow:${serverUrl}`, { type: 'json' });
      if (hit && hit.username && hit.password) return hit;
    } catch (_) {
      /* KV 读失败则回退环境变量 */
    }
  }
  if (env.UHDNOW_USERNAME && env.UHDNOW_PASSWORD) {
    return { username: env.UHDNOW_USERNAME, password: env.UHDNOW_PASSWORD };
  }
  return null;
}

export async function onRequestGet({ request, env }) {
  const serverUrl = new URL(request.url).searchParams.get('serverUrl') || '';
  // 只对 uhdnow 线路显示（与原插件门槛一致）。
  if (!serverUrl.toLowerCase().includes('uhdnow')) {
    return json({ metrics: [] });
  }

  const creds = await resolveCreds(env, serverUrl);
  if (!creds) {
    return json({ metrics: [{ label: '流量', value: '未配置' }] });
  }

  try {
    const loginRes = await fetch(`${API_BASE}/api/v1/auth/login`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'User-Agent': 'Linplayer/1.0.0' },
      body: JSON.stringify({ username: creds.username, password: creds.password }),
    });
    const loginBody = await loginRes.json().catch(() => ({}));
    const token = loginBody && loginBody.ok && loginBody.data && loginBody.data.token;
    if (!token) {
      return json({ metrics: [{ label: '流量', value: '登录失败' }] });
    }

    const trafficRes = await fetch(`${API_BASE}/api/v1/traffic/me`, {
      headers: { Authorization: token, 'User-Agent': 'Linplayer/1.0.0' },
    });
    const trafficBody = await trafficRes.json().catch(() => ({}));
    if (!(trafficBody && trafficBody.ok && trafficBody.data)) {
      return json({ metrics: [{ label: '流量', value: '获取失败' }] });
    }

    const used = gb(trafficBody.data.used_bytes);
    const limit = gb(trafficBody.data.limit_bytes);
    const remaining = Math.max(0, limit - used);
    return json({
      metrics: [
        { label: '剩余流量', value: `${remaining.toFixed(1)} GB` },
        { label: '总流量', value: `${limit.toFixed(0)} GB` },
      ],
    });
  } catch (e) {
    return json({ metrics: [{ label: '流量', value: '网络错误' }] });
  }
}
