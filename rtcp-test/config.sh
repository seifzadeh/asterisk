#!/usr/bin/env bash
set -Eeuo pipefail

ASTERISK_ETC="${ASTERISK_ETC:-/etc/asterisk}"
BACKUP_DIR="${ASTERISK_ETC}/rtcp-test-backup-$(date +%Y%m%d_%H%M%S)"
PJSIP_MAIN="${ASTERISK_ETC}/pjsip.conf"
EXTENSIONS_MAIN="${ASTERISK_ETC}/extensions.conf"
LOGGER_MAIN="${ASTERISK_ETC}/logger.conf"

if [[ ${EUID} -ne 0 ]]; then
    echo "ERROR: config.sh must run as root."
    exit 1
fi

if [[ ! -d "${ASTERISK_ETC}" ]]; then
    echo "ERROR: ${ASTERISK_ETC} does not exist."
    exit 1
fi

apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends     tcpdump iptables iproute2

mkdir -p "${BACKUP_DIR}"
for file in "${PJSIP_MAIN}" "${EXTENSIONS_MAIN}" "${LOGGER_MAIN}"; do
    if [[ -f "${file}" ]]; then
        cp -a "${file}" "${BACKUP_DIR}/"
    else
        touch "${file}"
    fi
done

cat > "${ASTERISK_ETC}/rtcp-test-pjsip.conf" <<'EOF'
; RTCP issue #2012 reproduction endpoints
; Register phones to the Asterisk VM on UDP port 5062.

[rtcp-test-transport]
type=transport
protocol=udp
bind=0.0.0.0:5062

[1001]
type=endpoint
transport=rtcp-test-transport
context=rtcp-test
disallow=all
allow=ulaw
auth=1001-auth
aors=1001
direct_media=no
rtp_symmetric=yes
force_rport=yes
rewrite_contact=yes
rtcp_mux=no

[1001-auth]
type=auth
auth_type=userpass
username=1001
password=RtcpTest1001

[1001]
type=aor
max_contacts=1
remove_existing=yes
qualify_frequency=30

[1002]
type=endpoint
transport=rtcp-test-transport
context=rtcp-test
disallow=all
allow=ulaw
auth=1002-auth
aors=1002
direct_media=no
rtp_symmetric=yes
force_rport=yes
rewrite_contact=yes
rtcp_mux=no

[1002-auth]
type=auth
auth_type=userpass
username=1002
password=RtcpTest1002

[1002]
type=aor
max_contacts=1
remove_existing=yes
qualify_frequency=30
EOF

cat > "${ASTERISK_ETC}/rtcp-test-extensions.conf" <<'EOF'
[rtcp-test]
; Normal calls between the two test phones.
exten => 1001,1,NoOp(RTCP test call to endpoint 1001)
 same => n,Dial(PJSIP/1001,60)
 same => n,Hangup()

exten => 1002,1,NoOp(RTCP test call to endpoint 1002)
 same => n,Dial(PJSIP/1002,60)
 same => n,Hangup()

; Call 700 from either endpoint, then run blockrtp.sh for that endpoint.
; Echo keeps bidirectional RTP active without requiring sound files or MOH.
exten => 700,1,NoOp(RTCP issue 2012 reproduction)
 same => n,Answer()
 same => n,Set(RTP_DEST=${CHANNEL(rtp,dest)})
 same => n,Verbose(1,RTCP-TEST channel=${CHANNEL(name)} rtp_dest=${RTP_DEST})
 same => n,Echo()
 same => n,Hangup()
EOF

cat > "${ASTERISK_ETC}/rtcp-test-logger.conf" <<'EOF'
[logfiles]
full => notice,warning,error,debug,verbose,dtmf
EOF

ensure_include() {
    local main_file="$1"
    local include_file="$2"
    local include_line="#include \"${include_file}\""

    if ! grep -Fqx "${include_line}" "${main_file}"; then
        printf '\n; Added by rtcp-test/config.sh\n%s\n' "${include_line}" >> "${main_file}"
    fi
}

ensure_include "${PJSIP_MAIN}" "rtcp-test-pjsip.conf"
ensure_include "${EXTENSIONS_MAIN}" "rtcp-test-extensions.conf"
ensure_include "${LOGGER_MAIN}" "rtcp-test-logger.conf"

chmod 0640     "${ASTERISK_ETC}/rtcp-test-pjsip.conf"     "${ASTERISK_ETC}/rtcp-test-extensions.conf"     "${ASTERISK_ETC}/rtcp-test-logger.conf"

if getent group asterisk >/dev/null; then
    chown root:asterisk         "${ASTERISK_ETC}/rtcp-test-pjsip.conf"         "${ASTERISK_ETC}/rtcp-test-extensions.conf"         "${ASTERISK_ETC}/rtcp-test-logger.conf"
fi

systemctl restart asterisk
systemctl --no-pager --full status asterisk

echo
echo "RTCP test configuration is ready."
echo "Backup: ${BACKUP_DIR}"
echo
echo "Endpoint 1001: password RtcpTest1001, server <VM-IP>:5062/UDP"
echo "Endpoint 1002: password RtcpTest1002, server <VM-IP>:5062/UDP"
echo "Test extension: 700"
echo
/usr/sbin/asterisk -rx "pjsip show endpoints"
