#!/usr/bin/env python3
"""Colo 探测脚本：扫描 CF /24 段采样 IP，通过 cf-ray 响应头统计各 Colo 可达性。
用法: python3 py/scan_colo.py [采样数/段] [并发数]
输出: 各 Colo 代码 -> 可用 IP 数 + 延迟排序前 5 IP 示例
"""
import asyncio, sys, re
import aiohttp, ssl

SAMPLE_PER_CIDR = int(sys.argv[1]) if len(sys.argv) > 1 else 4
CONCURRENCY = int(sys.argv[2]) if len(sys.argv) > 2 else 200
TIMEOUT = 8

async def probe(sem, session, ip, results):
    async with sem:
        try:
            async with session.get(f"https://{ip}/", ssl=False, timeout=aiohttp.ClientTimeout(total=TIMEOUT)) as resp:
                ray = resp.headers.get("cf-ray", "")
                m = re.search(r"-([A-Z]{3})$", ray)
                if m:
                    results.append((m.group(1), ip, resp.headers.get("cf-request-id", ""), ""))
        except Exception:
            pass

async def main():
    cidrs = [l.strip() for l in open("ip/Cloudflare-IP.txt") if l.strip()]
    sem = asyncio.Semaphore(CONCURRENCY)
    conn = aiohttp.TCPConnector(limit=CONCURRENCY, limit_per_host=0)
    results = []
    async with aiohttp.ClientSession(connector=conn) as session:
        tasks = []
        for c in cidrs:
            base = ".".join(c.split(".")[:3])
            for i in range(1, SAMPLE_PER_CIDR + 1):
                tasks.append(probe(sem, session, f"{base}.{i}", results))
        # 分批执行，避免内存过大
        for i in range(0, len(tasks), 2000):
            await asyncio.gather(*tasks[i:i+2000])
            print(f"[progress] {min(i+2000, len(tasks))}/{len(tasks)}", file=sys.stderr)
    # 统计
    from collections import defaultdict
    by_colo = defaultdict(list)
    for colo, ip, _, _ in results:
        by_colo[colo].append(ip)
    print(f"\n=== Colo 统计 (总有效 {len(results)} IP, 采样 {len(cidrs)} 段) ===")
    for colo in sorted(by_colo, key=lambda c: -len(by_colo[c])):
        ips = by_colo[colo]
        print(f"{colo}: {len(ips)} 个 IP | 示例: {', '.join(ips[:3])}")

if __name__ == "__main__":
    asyncio.run(main())
