#添加NSS状态界面
#!/usr/bin/env bash

echo ">>> 集成 NSS 状态页面到 LuCI"

# 1. 清理旧菜单/旧 CGI 的 uci-defaults 脚本（首次启动时自动执行）
mkdir -p files/etc/uci-defaults
cat > files/etc/uci-defaults/99-nss-clean << 'CLEAN_EOF'
#!/bin/sh
rm -f /usr/share/luci/menu.d/60_nss_status.json
rm -f /www/cgi-bin/nss_status
while uci show luci 2>/dev/null | grep -q "nss_status"; do
  idx=$(uci show luci | grep "nss_status" | head -1 | cut -d'[' -f2 | cut -d']' -f1)
  uci delete luci.@entry[$idx] 2>/dev/null
done
uci commit luci 2>/dev/null
/etc/init.d/uhttpd restart 2>/dev/null
rm -rf /tmp/luci-*
exit 0
CLEAN_EOF
chmod +x files/etc/uci-defaults/99-nss-clean

# 2. LuCI 控制器（用 template() 直接渲染模板，不重定向到 CGI）
# template() action 不会自动附加布局，所以模板内用 <%+header%>/<%+footer%> 引入 LuCI 顶栏侧栏
mkdir -p files/usr/lib/lua/luci/controller
cat > files/usr/lib/lua/luci/controller/nss_status.lua << 'LUA_EOF'
module("luci.controller.nss_status", package.seeall)
function index()
    entry({"admin", "nss_status"}, template("nss_status"), _("NSS 状态"), 60).leaf = true
end
LUA_EOF

# 3. LuCI 模板（<%+header%>/<%+footer%> 保留 LuCI 顶栏侧栏，不跳转独立页面）
# 数据采集在模板的 <% %> 块内完成，用 luci.sys.exec 调用 nss_diag / lsmod
mkdir -p files/usr/lib/lua/luci/view
cat > files/usr/lib/lua/luci/view/nss_status.htm << 'HTM_EOF'
<% local sys = require "luci.sys" -%>
<%
local raw, fw_ver, stats, stats_src, engine
if sys.exec("command -v nss_diag 2>/dev/null") ~= "" then
    raw = sys.exec("nss_diag 2>&1")
    stats = raw
    stats_src = "nss_diag"
    fw_ver = "未检测到"
    for line in raw:gmatch("[^\r\n]+") do
        local v = line:match("NSS FW:%s*(%S+)")
        if v then fw_ver = v break end
    end
else
    stats, stats_src, fw_ver = "无法获取统计信息。", "无可用命令", "未检测到"
end
if sys.exec("lsmod 2>/dev/null | grep -q nss_core && echo 1") ~= "" then
    engine = "已启用"
elseif sys.exec("test -d /proc/sys/dev/nss && echo 1") ~= "" then
    engine = "已加载"
else
    engine = "未检测到"
end
local badge = (engine == "已启用") and "on" or "off"
-%>
<%+header%>
<h2><%:NSS 状态信息%></h2>
<style>
  .nss-card { background:#fff; border-radius:10px; box-shadow:0 2px 10px rgba(0,0,0,.06); padding:24px; margin-bottom:24px; }
  .nss-card h3 { border-bottom:2px solid #0078d4; padding-bottom:8px; color:#0078d4; margin-top:0; }
  .nss-row { display:flex; padding:10px 0; border-bottom:1px solid #f0f0f0; }
  .nss-row:last-child { border-bottom:none; }
  .nss-label { width:140px; font-weight:600; color:#555; }
  .nss-badge { padding:4px 12px; border-radius:20px; font-size:14px; }
  .nss-badge.on  { background:#d2f5d2; color:#1e7b1e; }
  .nss-badge.off { background:#ffe3e3; color:#b30000; }
  .nss-pre { background:#f5f5f5; padding:16px; border-radius:6px; overflow-x:auto; white-space:pre-wrap; border:1px solid #e0e0e0; margin:0; }
  .nss-src { font-size:13px; color:#888; margin-top:8px; }
  .nss-gentime { text-align:right; font-size:13px; color:#aaa; margin-top:16px; }
</style>
<div class="nss-card">
  <h3><%:NSS 引擎状态%></h3>
  <div class="nss-row">
    <span class="nss-label"><%:引擎状态%></span>
    <span><span class="nss-badge <%=badge%>"><%=engine%></span></span>
  </div>
</div>
<div class="nss-card">
  <h3><%:NSS 固件版本%></h3>
  <div class="nss-row">
    <span class="nss-label"><%:NSS FW 版本%></span>
    <span><%=fw_ver%></span>
  </div>
</div>
<div class="nss-card">
  <h3><%:NSS 负载 / 流量统计%></h3>
  <pre class="nss-pre"><%=stats%></pre>
  <div class="nss-src"><%:数据源%>: <%=stats_src%></div>
</div>
<div class="nss-gentime"><%:页面生成%>: <%=os.date("%Y-%m-%d %H:%M:%S")%></div>
<%+footer%>
HTM_EOF

echo ">>> NSS 状态页面集成完毕"
