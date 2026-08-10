#!/bin/bash
# ============================================================
# 更新 9 国 Cloudflare 节点 (国内用户可用性优先, 方向A)
# 流程: 关VPN → 断网真实测速9国 → 验证TXT → 开VPN → push → 关VPN
# 用法: sh scripts/update_nodes.sh
# 依赖: macOS scutil (控制 Shadowrocket VPN), git, python3
# ============================================================
set -e
export PATH="/usr/sbin:/usr/bin:/bin:$PATH"
cd "$(dirname "$0")/.."

VPN="Shadowrocket"
COUNTRY="SG JP DE US NL HK KR TW TR"
LOG="scripts/update_nodes.log"

log() { echo "[$(date '+%F %T')] $*" | tee -a "$LOG"; }

# ---------- 0. 记录初始 VPN 状态 (结束后恢复, 不改用户状态) ----------
INIT_STATE=$(/usr/sbin/scutil --nc status "$VPN" 2>/dev/null | head -1)
log "=== 0. 运行前 VPN 状态: $INIT_STATE (结束后将恢复) ==="

# ---------- 1. 强制关 VPN (测速需要真实网络) ----------
log "=== 1. 关闭 VPN ($VPN) 用于测速 ==="
/usr/sbin/scutil --nc stop "$VPN" 2>/dev/null
sleep 3
VPN_STATE=$(/usr/sbin/scutil --nc status "$VPN" 2>/dev/null | head -1)
log "VPN 状态: $VPN_STATE"
if [ "$VPN_STATE" != "Disconnected" ]; then
  log "ERROR: VPN 未能关闭, 中止 (避免假速测)"
  exit 1
fi

# ---------- 2. 断网测速 9 国 ----------
log "=== 2. 断 VPN 真实测速 9 国 ==="
for c in $COUNTRY; do
  if python3 "py/${c}.py" >/dev/null 2>&1; then
    N=$(wc -l < "${c}.txt" 2>/dev/null || echo 0)
    log "  ${c}.py  OK, ${c}.txt ${N} 行"
  else
    log "  ${c}.py  失败!"
  fi
done

# ---------- 3. 验证 TXT 有效性 ----------
log "=== 3. 验证 TXT (非空且首行格式正确) ==="
FAIL=0
for c in $COUNTRY; do
  FIRST=$(head -1 "${c}.txt" 2>/dev/null)
  if [ -z "$FIRST" ] || echo "$FIRST" | grep -qE "拉取|抽取|Error|Traceback"; then
    log "  ❌ ${c}.txt 异常: [$FIRST]"
    FAIL=1
  else
    log "  ✅ ${c}.txt: $FIRST"
  fi
done
if [ "$FAIL" = "1" ]; then
  log "ERROR: 部分 TXT 异常, 中止 (不 push 异常数据)"
  exit 1
fi

# ---------- 4. 开 VPN (push 需要) ----------
log "=== 4. 开启 VPN ($VPN) 用于推送 ==="
/usr/sbin/scutil --nc start "$VPN" 2>/dev/null
sleep 5
VPN_STATE=$(/usr/sbin/scutil --nc status "$VPN" 2>/dev/null | head -1)
log "VPN 状态: $VPN_STATE"
if [ "$VPN_STATE" != "Connected" ]; then
  log "WARN: VPN 未连上, 尝试 push (可能需要你手动开)"
fi

# ---------- 5. commit + push ----------
log "=== 5. 提交并推送 9 国 TXT ==="
git add SG.txt JP.txt DE.txt US.txt NL.txt HK.txt KR.txt TW.txt TR.txt
if git diff --cached --quiet; then
  log "  TXT 无变化, 跳过 push"
else
  git commit -m "Update 9-country nodes (domestic-optimized speed test) [skip ci]" || true
  # 方向A: 本地测速为准. rebase冲突时强制以本地覆盖远程(丢弃Actions改动)再push
  if git pull --rebase origin main 2>/dev/null; then
    :
  else
    log "  ⚠️ rebase冲突 -> 强制以本地为准(reset --hard origin/main)"
    git fetch origin main 2>/dev/null || true
    git reset --hard origin/main 2>/dev/null
    git commit -am "Update 9-country nodes (domestic-optimized speed test) [skip ci]" 2>/dev/null || true
  fi
  if git push origin main 2>&1 | tee -a "$LOG"; then
    log "  ✅ push 成功"
  else
    log "  ❌ push 失败"
  fi
fi

# ---------- 6. 恢复 VPN 到运行前状态 ----------
log "=== 6. 恢复 VPN (初始: $INIT_STATE) ==="
if [ "$INIT_STATE" = "Connected" ]; then
  /usr/sbin/scutil --nc start "$VPN" 2>/dev/null
  sleep 4
else
  /usr/sbin/scutil --nc stop "$VPN" 2>/dev/null
  sleep 3
fi
FINAL_STATE=$(/usr/sbin/scutil --nc status "$VPN" 2>/dev/null | head -1)
log "最终 VPN: $FINAL_STATE (期望回到: $INIT_STATE)"
if [ "$FINAL_STATE" != "$INIT_STATE" ]; then
  log "WARN: VPN 未恢复到初始状态, 请检查"
fi
log "=== 完成 ==="
