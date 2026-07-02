// GET /api/addon/uhdnow/manifest.json  —— addon 元信息（Stremio/Forward 风格）。
// App 的 AddonPluginRuntime 先取本文件确认能力，再调各 resource 端点。
export async function onRequestGet() {
  return new Response(
    JSON.stringify({
      id: 'com.linplayer.uhdnow-traffic-addon',
      name: 'UHDNow 流量统计',
      resources: ['homeStats'],
    }),
    { headers: { 'Content-Type': 'application/json' } },
  );
}
