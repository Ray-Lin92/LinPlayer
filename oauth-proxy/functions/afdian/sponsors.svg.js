// GET /afdian/sponsors.svg — 实时渲染爱发电赞助者名单为一张自包含 SVG。
//
// 头像以 base64 内联进 SVG，这样 GitHub 的图片代理(Camo)能正常显示（否则外链头像会被拦）。
// 需要在 Cloudflare Pages 环境变量里配置：
//   AFDIAN_USER_ID  你的爱发电 user_id（dashboard/dev 里的「user_id」）
//   AFDIAN_TOKEN    你的爱发电 token（dashboard/dev 里的「token」，务必设为 Encrypted）
// 该路由在 /api/ 之外，不受共享密钥保护，可直接被 README 图片引用。
//
// ponytail: 免费版 CF 每请求子请求上限 ~50，这里最多取 40 位赞助者(+分页) 以留余量；
//           要展示更多就升级 Workers 付费版并调大 MAX_SPONSORS。

const MAX_SPONSORS = 40;
const MAX_PAGES = 2;
const COLS = 6;

export async function onRequestGet({ env }) {
  const userId = env.AFDIAN_USER_ID;
  const token = env.AFDIAN_TOKEN;
  if (!userId || !token) {
    return svgResponse(messageSvg('未配置 AFDIAN_USER_ID / AFDIAN_TOKEN'));
  }

  let sponsors;
  try {
    sponsors = await fetchSponsors(userId, token);
  } catch (e) {
    return svgResponse(messageSvg('拉取失败：' + String(e && e.message || e)));
  }
  if (!sponsors.length) {
    return svgResponse(messageSvg('还没有赞助者，成为第一个 ❤️'));
  }

  sponsors = sponsors.slice(0, MAX_SPONSORS);
  await inlineAvatars(sponsors);
  return svgResponse(renderSvg(sponsors));
}

// ---- 爱发电 API ----

async function fetchSponsors(userId, token) {
  const out = [];
  for (let page = 1; page <= MAX_PAGES; page++) {
    const params = JSON.stringify({ page });
    const ts = Math.floor(Date.now() / 1000);
    const sign = md5(`${token}params${params}ts${ts}user_id${userId}`);
    const resp = await fetch('https://afdian.com/api/open/query-sponsor', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ user_id: userId, params, ts, sign }),
    });
    const json = await resp.json();
    if (json.ec !== 200) throw new Error(json.em || ('ec=' + json.ec));
    const data = json.data || {};
    for (const item of data.list || []) {
      const u = item.user || {};
      out.push({
        name: u.name || '匿名',
        avatar: u.avatar || '',
        amount: item.all_sum_amount || '0',
      });
      if (out.length >= MAX_SPONSORS) return out;
    }
    if (page >= (data.total_page || 1)) break;
  }
  return out;
}

async function inlineAvatars(sponsors) {
  await Promise.all(sponsors.map(async (s) => {
    if (!s.avatar) return;
    try {
      const r = await fetch(s.avatar);
      if (!r.ok) return;
      const type = r.headers.get('content-type') || 'image/jpeg';
      const buf = new Uint8Array(await r.arrayBuffer());
      s.dataUri = `data:${type};base64,${bytesToBase64(buf)}`;
    } catch (_) { /* 头像失败就退回首字母圆点 */ }
  }));
}

// ---- SVG 渲染 ----

function renderSvg(sponsors) {
  const cellW = 110, cellH = 96, avatar = 48, padTop = 56, padX = 16;
  const rows = Math.ceil(sponsors.length / COLS);
  const width = COLS * cellW + padX * 2;
  const height = padTop + rows * cellH + 12;
  const colors = ['#f78fb3', '#7ec8e3', '#a3d9a5', '#f6c177', '#c3a6ff', '#ff9f7f'];

  let cells = '';
  sponsors.forEach((s, i) => {
    const col = i % COLS, row = (i / COLS) | 0;
    const cx = padX + col * cellW + cellW / 2;
    const cy = padTop + row * cellH + avatar / 2;
    const r = avatar / 2;
    const name = escapeXml(truncate(s.name, 8));
    const amount = '¥' + fmtAmount(s.amount);
    if (s.dataUri) {
      cells += `<clipPath id="c${i}"><circle cx="${cx}" cy="${cy}" r="${r}"/></clipPath>` +
        `<image href="${s.dataUri}" x="${cx - r}" y="${cy - r}" width="${avatar}" height="${avatar}" clip-path="url(#c${i})" preserveAspectRatio="xMidYMid slice"/>` +
        `<circle cx="${cx}" cy="${cy}" r="${r}" fill="none" stroke="#e2c4d0" stroke-width="1.5"/>`;
    } else {
      const bg = colors[i % colors.length];
      const letter = escapeXml((s.name || '?').slice(0, 1).toUpperCase());
      cells += `<circle cx="${cx}" cy="${cy}" r="${r}" fill="${bg}"/>` +
        `<text x="${cx}" y="${cy}" font-size="20" fill="#fff" text-anchor="middle" dominant-baseline="central" font-family="sans-serif">${letter}</text>`;
    }
    const ty = cy + r + 16;
    cells += `<text x="${cx}" y="${ty}" font-size="12" fill="#24292f" text-anchor="middle" font-family="sans-serif">${name}</text>` +
      `<text x="${cx}" y="${ty + 15}" font-size="11" fill="#d1477a" text-anchor="middle" font-family="sans-serif" font-weight="600">${amount}</text>`;
  });

  return `<svg xmlns="http://www.w3.org/2000/svg" width="${width}" height="${height}" viewBox="0 0 ${width} ${height}" font-family="sans-serif">` +
    `<rect x="0.5" y="0.5" width="${width - 1}" height="${height - 1}" rx="12" fill="#fbf7f9" stroke="#e6d3dc"/>` +
    `<text x="${padX}" y="34" font-size="16" fill="#24292f" font-weight="700">❤️ 爱发电赞助者 · ${sponsors.length}</text>` +
    cells +
    `</svg>`;
}

function messageSvg(text) {
  const t = escapeXml(text);
  return `<svg xmlns="http://www.w3.org/2000/svg" width="420" height="70" viewBox="0 0 420 70" font-family="sans-serif">` +
    `<rect x="0.5" y="0.5" width="419" height="69" rx="12" fill="#fbf7f9" stroke="#e6d3dc"/>` +
    `<text x="20" y="40" font-size="14" fill="#8a6070">❤️ 爱发电赞助者：${t}</text></svg>`;
}

function svgResponse(svg) {
  return new Response(svg, {
    headers: {
      'Content-Type': 'image/svg+xml; charset=utf-8',
      // 让浏览器/Camo 每 ~10 分钟回源刷新一次
      'Cache-Control': 'public, max-age=600, s-maxage=600',
    },
  });
}

// ---- 工具 ----

function truncate(s, n) { return s.length > n ? s.slice(0, n) + '…' : s; }
function fmtAmount(a) { const n = parseFloat(a); return Number.isInteger(n) ? String(n) : n.toFixed(2); }
function escapeXml(s) {
  return String(s).replace(/[&<>"']/g, (c) =>
    ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
}
function bytesToBase64(bytes) {
  let bin = '';
  const chunk = 0x8000;
  for (let i = 0; i < bytes.length; i += chunk) {
    bin += String.fromCharCode.apply(null, bytes.subarray(i, i + chunk));
  }
  return btoa(bin);
}

// 爱发电签名要求 MD5，而 Web Crypto 不提供 MD5，故内联一份紧凑实现（Joseph Myers 版）。
function md5(str) {
  function cmn(q, a, b, x, s, t) { a = add32(add32(a, q), add32(x, t)); return add32((a << s) | (a >>> (32 - s)), b); }
  function ff(a, b, c, d, x, s, t) { return cmn((b & c) | (~b & d), a, b, x, s, t); }
  function gg(a, b, c, d, x, s, t) { return cmn((b & d) | (c & ~d), a, b, x, s, t); }
  function hh(a, b, c, d, x, s, t) { return cmn(b ^ c ^ d, a, b, x, s, t); }
  function ii(a, b, c, d, x, s, t) { return cmn(c ^ (b | ~d), a, b, x, s, t); }
  function md5cycle(x, k) {
    let a = x[0], b = x[1], c = x[2], d = x[3];
    a = ff(a, b, c, d, k[0], 7, -680876936); d = ff(d, a, b, c, k[1], 12, -389564586); c = ff(c, d, a, b, k[2], 17, 606105819); b = ff(b, c, d, a, k[3], 22, -1044525330);
    a = ff(a, b, c, d, k[4], 7, -176418897); d = ff(d, a, b, c, k[5], 12, 1200080426); c = ff(c, d, a, b, k[6], 17, -1473231341); b = ff(b, c, d, a, k[7], 22, -45705983);
    a = ff(a, b, c, d, k[8], 7, 1770035416); d = ff(d, a, b, c, k[9], 12, -1958414417); c = ff(c, d, a, b, k[10], 17, -42063); b = ff(b, c, d, a, k[11], 22, -1990404162);
    a = ff(a, b, c, d, k[12], 7, 1804603682); d = ff(d, a, b, c, k[13], 12, -40341101); c = ff(c, d, a, b, k[14], 17, -1502002290); b = ff(b, c, d, a, k[15], 22, 1236535329);
    a = gg(a, b, c, d, k[1], 5, -165796510); d = gg(d, a, b, c, k[6], 9, -1069501632); c = gg(c, d, a, b, k[11], 14, 643717713); b = gg(b, c, d, a, k[0], 20, -373897302);
    a = gg(a, b, c, d, k[5], 5, -701558691); d = gg(d, a, b, c, k[10], 9, 38016083); c = gg(c, d, a, b, k[15], 14, -660478335); b = gg(b, c, d, a, k[4], 20, -405537848);
    a = gg(a, b, c, d, k[9], 5, 568446438); d = gg(d, a, b, c, k[14], 9, -1019803690); c = gg(c, d, a, b, k[3], 14, -187363961); b = gg(b, c, d, a, k[8], 20, 1163531501);
    a = gg(a, b, c, d, k[13], 5, -1444681467); d = gg(d, a, b, c, k[2], 9, -51403784); c = gg(c, d, a, b, k[7], 14, 1735328473); b = gg(b, c, d, a, k[12], 20, -1926607734);
    a = hh(a, b, c, d, k[5], 4, -378558); d = hh(d, a, b, c, k[8], 11, -2022574463); c = hh(c, d, a, b, k[11], 16, 1839030562); b = hh(b, c, d, a, k[14], 23, -35309556);
    a = hh(a, b, c, d, k[1], 4, -1530992060); d = hh(d, a, b, c, k[4], 11, 1272893353); c = hh(c, d, a, b, k[7], 16, -155497632); b = hh(b, c, d, a, k[10], 23, -1094730640);
    a = hh(a, b, c, d, k[13], 4, 681279174); d = hh(d, a, b, c, k[0], 11, -358537222); c = hh(c, d, a, b, k[3], 16, -722521979); b = hh(b, c, d, a, k[6], 23, 76029189);
    a = hh(a, b, c, d, k[9], 4, -640364487); d = hh(d, a, b, c, k[12], 11, -421815835); c = hh(c, d, a, b, k[15], 16, 530742520); b = hh(b, c, d, a, k[2], 23, -995338651);
    a = ii(a, b, c, d, k[0], 6, -198630844); d = ii(d, a, b, c, k[7], 10, 1126891415); c = ii(c, d, a, b, k[14], 15, -1416354905); b = ii(b, c, d, a, k[5], 21, -57434055);
    a = ii(a, b, c, d, k[12], 6, 1700485571); d = ii(d, a, b, c, k[3], 10, -1894986606); c = ii(c, d, a, b, k[10], 15, -1051523); b = ii(b, c, d, a, k[1], 21, -2054922799);
    a = ii(a, b, c, d, k[8], 6, 1873313359); d = ii(d, a, b, c, k[15], 10, -30611744); c = ii(c, d, a, b, k[6], 15, -1560198380); b = ii(b, c, d, a, k[13], 21, 1309151649);
    a = ii(a, b, c, d, k[4], 6, -145523070); d = ii(d, a, b, c, k[11], 10, -1120210379); c = ii(c, d, a, b, k[2], 15, 718787259); b = ii(b, c, d, a, k[9], 21, -343485551);
    x[0] = add32(a, x[0]); x[1] = add32(b, x[1]); x[2] = add32(c, x[2]); x[3] = add32(d, x[3]);
  }
  function md5blk(s) { const b = []; for (let i = 0; i < 64; i += 4) b[i >> 2] = s.charCodeAt(i) + (s.charCodeAt(i + 1) << 8) + (s.charCodeAt(i + 2) << 16) + (s.charCodeAt(i + 3) << 24); return b; }
  function md51(s) {
    const n = s.length, state = [1732584193, -271733879, -1732584194, 271733878]; let i;
    for (i = 64; i <= n; i += 64) md5cycle(state, md5blk(s.substring(i - 64, i)));
    s = s.substring(i - 64);
    const tail = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0];
    for (i = 0; i < s.length; i++) tail[i >> 2] |= s.charCodeAt(i) << ((i % 4) << 3);
    tail[i >> 2] |= 0x80 << ((i % 4) << 3);
    if (i > 55) { md5cycle(state, tail); for (i = 0; i < 16; i++) tail[i] = 0; }
    tail[14] = n * 8;
    md5cycle(state, tail);
    return state;
  }
  const hexChr = '0123456789abcdef'.split('');
  function rhex(x) { let s = ''; for (let j = 0; j < 4; j++) s += hexChr[(x >> (j * 8 + 4)) & 15] + hexChr[(x >> (j * 8)) & 15]; return s; }
  function add32(a, b) { return (a + b) & 0xFFFFFFFF; }
  const bytes = unescape(encodeURIComponent(str)); // UTF-8
  const st = md51(bytes);
  return rhex(st[0]) + rhex(st[1]) + rhex(st[2]) + rhex(st[3]);
}
