#!/usr/bin/env bash
# Out-of-process escapes attempted from inside the P4 sandbox. Harmless GET to example.com only.
set -u
p() { printf 'ESC %s: %s\n' "$1" "$2"; }
W() { perl -e 'alarm 20; exec @ARGV' -- "$@"; }
r=$(W osascript -e 'tell application "System Events" to do shell script "curl -s -o /dev/null -m 6 -w http=%{http_code} http://example.com"' 2>&1|head -2); p sysevents-curl "$r"
r=$(W osascript -e 'tell application "System Events" to do shell script "sudo -n curl -s -o /dev/null -m 6 -w http=%{http_code} http://example.com"' 2>&1|head -2); p sysevents-sudo-curl "$r"
rm -f /tmp/esc-open.txt
r=$(W osascript -l JavaScript -e 'var a=Application.currentApplication();a.includeStandardAdditions=true;a.doShellScript("curl -s -o /dev/null -m 6 -w http=%{http_code} http://example.com")' 2>&1|head -2); p jxa-curl "$r"
# launchd via python/xpc-free route: launchctl bootstrap a user agent plist
cat > /tmp/esc.plist <<PL
<?xml version="1.0" encoding="UTF-8"?><!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd"><plist version="1.0"><dict><key>Label</key><string>esc.probe</string><key>ProgramArguments</key><array><string>/bin/sh</string><string>-c</string><string>curl -s -o /dev/null -m 6 -w http=%{http_code} http://example.com > /tmp/esc-launchd.txt</string></array><key>RunAtLoad</key><true/></dict></plist>
PL
rm -f /tmp/esc-launchd.txt
r=$(launchctl bootstrap gui/$(id -u) /tmp/esc.plist 2>&1; echo rc=$?); p launchctl-bootstrap "$r"
r=$(launchctl load /tmp/esc.plist 2>&1; echo rc=$?); p launchctl-load "$r"
sleep 8; p launchd-job-result "$(cat /tmp/esc-launchd.txt 2>&1)"
r=$(W open -a TextEdit /tmp/esc.plist 2>&1; echo rc=$?); p open-app "$r"
r=$(at -h 2>&1 | head -1); p at "$r"
r=$(W /usr/bin/ssh -o BatchMode=yes -o ConnectTimeout=4 -o StrictHostKeyChecking=no git@github.com 2>&1 | head -1); p ssh "$r"
