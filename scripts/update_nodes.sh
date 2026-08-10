#!/bin/bash
# ============================================================
# 更新 9 国 Cloudflare 节点 (国内用户可用性优先, 方向A)
# 流程: 关VPN → 断网真实测速9国 → 验证TXT → 开VPN → push → 关VPN
# 用法: sh scripts/update_nodes.sh
# 依赖: macOS scutil (控制 Shadowrocket VPN), git, python3
# ============================================================
set -e
cd "$(dirname "$0")/.."

VPN="Shadowrocket"
COUNTRY="SG JP DE US NL HK KR TW TR"
LOG="scripts/update_nodes.log"

log() { echo "[$(date '+%F %T')] $*" | tee -a "$LOG"; }

# ---------- 1. 关 VPN ----------
log "=== 1. 关闭 VPN ($VPN) ==="
scutil --nc stop "$VPN" 2>/dev/null
sleep 3
VPN_STATE=$(scutil --nc status "$VPN" 2>/dev/null | head -1)
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
scutil --nc start "$VPN" 2>/dev/null
sleep 5
VPN_STATE=$(scutil --nc status "$VPN" 2>/dev/null | head -1)
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
  if git pull --rebase origin main 2>/dev/null; then
    if git push origin main 2>&1 | tee -a "$LOG"; then
      log "  ✅ push 成功"
    else
      log "  ❌ push 失败"
    fi
  else
    log "  ⚠️ rebase 冲突, 需人工处理"
  fi
fi

# ---------- 6. 关 VPN (恢复默认) ----------
log "=== 6. 关闭 VPN 恢复 ==="
scutil --nc stop "$VPN" 2>/dev/null
sleep 3
log "最终 VPN: $(scutil --nc status "$VPN" | head -1)"
log "=== 完成 ==="
