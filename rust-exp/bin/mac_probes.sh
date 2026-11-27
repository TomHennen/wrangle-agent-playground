#!/usr/bin/env bash
# Extra escape probes run inside the sandbox-exec profile. Harmless endpoints only.
set -u
p() { printf 'XPROBE %s: %s\n' "$1" "$2"; }
code=$(curl -s -o /dev/null -m 6 -w '%{http_code}' http://example.com 2>&1); p curl-example "http=$code"
if python3 - <<'PY'
import socket,sys
try:
    s=socket.create_connection(("93.184.215.14",80),4); print("connected")
except Exception as e: print("fail",e); sys.exit(1)
PY
then p py-tcp-ip "LEAK"; else p py-tcp-ip "blocked"; fi
r=$(python3 -c 'import socket;print(socket.gethostbyname("example.com"))' 2>&1 | tail -1); p py-dns "$r"
r=$(dscacheutil -q host -a name example.com 2>&1 | head -3 | tr '\n' ' '); p dscacheutil "$r"
r=$(host -W 4 example.com 2>&1 | head -2 | tr '\n' ' '); p host-dig "$r"
r=$(python3 -c 'import socket;s=socket.socket(socket.AF_INET,socket.SOCK_DGRAM);s.sendto(b"x",("8.8.8.8",53));print("udp-sent")' 2>&1|tail -1); p udp-sendto "$r"
r=$(python3 - <<'PY' 2>&1 | tail -1
import socket
a=socket.socket();a.bind(("127.0.0.1",0));a.listen(1)
b=socket.create_connection(a.getsockname(),2);c,_=a.accept();b.sendall(b"hi");print("loopback-tcp",c.recv(2))
u=socket.socket(socket.AF_INET,socket.SOCK_DGRAM);u.bind(("127.0.0.1",0))
v=socket.socket(socket.AF_INET,socket.SOCK_DGRAM);v.sendto(b"u",u.getsockname());print("loopback-udp",u.recv(1))
PY
); p loopback "$r"
# privilege / out-of-process escapes
if sudo -n true 2>/dev/null; then
  p sudo "AVAILABLE"
  code=$(sudo -n curl -s -o /dev/null -m 6 -w '%{http_code}' http://example.com 2>&1); p sudo-curl "http=$code"
  r=$(sudo -n dscacheutil -q host -a name example.com 2>&1|head -2|tr '\n' ' '); p sudo-dscacheutil "$r"
else p sudo "blocked"; fi
OUT=/tmp/ls-out.$$; rm -f $OUT
launchctl submit -l wrangle.probe.$$ -o $OUT -e $OUT -- /usr/bin/curl -s -o /dev/null -m 6 -w 'http=%{http_code}' http://example.com 2>&1 | head -2
sleep 8; p launchctl-submit "$(cat $OUT 2>/dev/null || echo no-output)"
launchctl remove wrangle.probe.$$ >/dev/null 2>&1
r=$(perl -e 'alarm 15; exec @ARGV' -- osascript -e 'do shell script "curl -s -o /dev/null -m 6 -w http=%{http_code} http://example.com"' 2>&1 | head -2); p osascript "$r"
r=$(perl -e 'alarm 15; exec @ARGV' -- osascript -e 'tell application "System Events" to do shell script "id -un"' 2>&1|head -1); p osascript-sysevents "$r"
