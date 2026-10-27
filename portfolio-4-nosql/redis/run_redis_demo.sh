#!/usr/bin/env bash
# =====================================================================
# Portfolio 4 | run_redis_demo.sh   (OPTIONAL key-value example)
# Key-value uses of Redis in The Homes: temporary room holds, availability
# cache, sessions, rate limiting and a spend leaderboard.
# Needs redis-cli and a running Redis server (Linux, WSL, Docker or a cloud instance):
#   bash redis/run_redis_demo.sh | tee results/06_redis_output.txt
# Set REDIS_CLI to use another connection, for example: REDIS_CLI="redis-cli -h myhost -p 6379"
# =====================================================================
R="${REDIS_CLI:-redis-cli}"
say() { printf '\n--- %s\n' "$1"; }
run() { printf '> %s\n' "$*"; out=$($R "$@"); [ -z "$out" ] && out="(nil)"; echo "$out"; }

$R FLUSHDB >/dev/null

say "K1  ROOM HOLD: reserve room 42 for 10 minutes while the guest pays (SET NX EX)"
run SET hold:room:42:2027-04-10:2027-04-13 guest:77 NX EX 600
say "A second guest tries the same room and dates: NX refuses (nil)"
run SET hold:room:42:2027-04-10:2027-04-13 guest:88 NX EX 600
run GET hold:room:42:2027-04-10:2027-04-13
run TTL hold:room:42:2027-04-10:2027-04-13
say "Payment succeeds: remove the hold (the relational booking is written in PostgreSQL)"
run DEL hold:room:42:2027-04-10:2027-04-13

say "K2  HOLD EXPIRY: an abandoned checkout releases itself (2-second hold)"
run SET hold:room:43:2027-04-10:2027-04-13 guest:99 NX EX 2
run EXISTS hold:room:43:2027-04-10:2027-04-13
sleep 3
run EXISTS hold:room:43:2027-04-10:2027-04-13

say "K3  AVAILABILITY CACHE: free rooms per type, refreshed every 5 minutes (hash + expiry)"
run HSET availability:hotel:1:2026-12-20 standard_single 3 standard_double 1 twin 0 deluxe 4 suite 1
run EXPIRE availability:hotel:1:2026-12-20 300
run HGETALL availability:hotel:1:2026-12-20
say "A deluxe room is booked: decrement the cached count atomically"
run HINCRBY availability:hotel:1:2026-12-20 deluxe -1
run HGET availability:hotel:1:2026-12-20 deluxe

say "K4  SESSION: login token with 30-minute lifetime"
run SET session:abc123 guest:77 EX 1800
run GET session:abc123
run TTL session:abc123

say "K5  RATE LIMIT: at most 5 booking attempts per guest per minute (INCR + EXPIRE)"
for i in 1 2 3 4 5 6 7; do
  n=$($R INCR ratelimit:guest:77)
  [ "$n" = "1" ] && $R EXPIRE ratelimit:guest:77 60 >/dev/null
  if [ "$n" -le 5 ]; then echo "attempt $i -> allowed (count $n)"; else echo "attempt $i -> BLOCKED (count $n)"; fi
done

say "K6  LEADERBOARD: top spenders this month (sorted set)"
run ZADD topspenders:2026-10 1250.50 guest:77 980.00 guest:12 2210.75 guest:5 640.20 guest:31 1790.00 guest:100
run ZINCRBY topspenders:2026-10 300 guest:12
run ZREVRANGE topspenders:2026-10 0 2 WITHSCORES

say "Keys currently stored"
run DBSIZE
