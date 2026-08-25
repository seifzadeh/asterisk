#!/usr/bin/env bash
set -Eeuo pipefail

ENDPOINT="${1:-1002}"
DURATION="${2:-60}"
WAIT_SECONDS="${WAIT_SECONDS:-120}"
AST="/usr/sbin/asterisk"
FULL_LOG="/var/log/asterisk/full"
RESULT_ROOT="${RESULT_ROOT:-/var/log/asterisk/rtcp-test}"
STAMP="$(date +%Y%m%d_%H%M%S)"
RESULT_DIR="${RESULT_ROOT}/issue2012_${STAMP}"
CHANNEL=""
PEER_IP=""
RTP_PORT=""
RTCP_PORT=""
IFACE=""
TCPDUMP_PID=""
RULE_ADDED=0

if [[ ${EUID} -ne 0 ]]; then
    echo "ERROR: blockrtp.sh must run as root."
    exit 1
fi

if [[ ! "${ENDPOINT}" =~ ^[0-9A-Za-z_.-]+$ ]]; then
    echo "ERROR: invalid endpoint name."
    exit 1
fi

if [[ ! "${DURATION}" =~ ^[0-9]+$ ]] || (( DURATION < 5 )); then
    echo "ERROR: duration must be an integer of at least 5 seconds."
    exit 1
fi

for command in ip iptables tcpdump awk sed grep; do
    command -v "${command}" >/dev/null || {
        echo "ERROR: missing command: ${command}"
        exit 1
    }
done

mkdir -p "${RESULT_DIR}"

cleanup() {
    local exit_code=$?
    set +e

    if (( RULE_ADDED == 1 )); then
        iptables -D OUTPUT -p udp -d "${PEER_IP}" --dport "${RTP_PORT}" -j DROP
    fi

    if [[ -n "${TCPDUMP_PID}" ]]; then
        kill -INT "${TCPDUMP_PID}" 2>/dev/null
        wait "${TCPDUMP_PID}" 2>/dev/null
    fi

    "${AST}" -rx "rtp set debug off" >/dev/null 2>&1
    "${AST}" -rx "rtcp set debug off" >/dev/null 2>&1

    if [[ -f "${FULL_LOG}" ]]; then
        cp -a "${FULL_LOG}" "${RESULT_DIR}/issue2012_${STAMP}_full.log"
    fi

    {
        echo "endpoint=${ENDPOINT}"
        echo "channel=${CHANNEL}"
        echo "peer_ip=${PEER_IP}"
        echo "rtp_port=${RTP_PORT}"
        echo "rtcp_port=${RTCP_PORT}"
        echo "interface=${IFACE}"
        echo "duration=${DURATION}"
        echo "exit_code=${exit_code}"
    } > "${RESULT_DIR}/metadata.txt"

    echo
    echo "Results: ${RESULT_DIR}"
    exit "${exit_code}"
}
trap cleanup EXIT INT TERM

"${AST}" -rx "logger rotate" >/dev/null
"${AST}" -rx "rtcp set debug on"
"${AST}" -rx "rtp set debug on"

echo "Waiting up to ${WAIT_SECONDS}s for endpoint ${ENDPOINT} to call extension 700..."

deadline=$((SECONDS + WAIT_SECONDS))
while (( SECONDS < deadline )); do
    CHANNEL="$("${AST}" -rx "core show channels concise" |
        awk -F'!' -v prefix="PJSIP/${ENDPOINT}-"             'index($1, prefix) == 1 { print $1; exit }')"

    if [[ -n "${CHANNEL}" ]]; then
        RTP_DEST="$("${AST}" -rx "core show channel ${CHANNEL}" |
            sed -n 's/^[[:space:]]*RTP_DEST=//p' | head -n1)"

        if [[ "${RTP_DEST}" =~ ^([0-9]{1,3}(\.[0-9]{1,3}){3}):([0-9]+)$ ]]; then
            PEER_IP="${BASH_REMATCH[1]}"
            RTP_PORT="${BASH_REMATCH[3]}"
            break
        fi
    fi
    sleep 1
done

if [[ -z "${PEER_IP}" || -z "${RTP_PORT}" ]]; then
    echo "ERROR: no active RTCP test call with RTP_DEST was detected."
    echo "Register endpoint ${ENDPOINT}, call 700, and keep the call active."
    exit 1
fi

RTCP_PORT=$((RTP_PORT + 1))
IFACE="$(ip route get "${PEER_IP}" | awk     '{for (i=1; i<=NF; i++) if ($i=="dev") {print $(i+1); exit}}')"

if [[ -z "${IFACE}" ]]; then
    echo "ERROR: could not determine the route to ${PEER_IP}."
    exit 1
fi

echo "Channel : ${CHANNEL}"
echo "RTP     : ${PEER_IP}:${RTP_PORT}"
echo "RTCP    : ${PEER_IP}:${RTCP_PORT}"
echo "Device  : ${IFACE}"
echo "Capture : ${DURATION}s"

tcpdump -ni "${IFACE}" -s0 -U     -w "${RESULT_DIR}/issue2012_${STAMP}_rtcp.pcap"     "host ${PEER_IP} and udp port ${RTCP_PORT}"     > "${RESULT_DIR}/tcpdump.log" 2>&1 &
TCPDUMP_PID=$!

sleep 1
kill -0 "${TCPDUMP_PID}" 2>/dev/null || {
    echo "ERROR: tcpdump failed to start."
    exit 1
}

iptables -I OUTPUT 1 -p udp -d "${PEER_IP}" --dport "${RTP_PORT}" -j DROP
RULE_ADDED=1

echo "Outbound RTP is now blocked. SIP, inbound RTP, and RTCP remain available."
sleep "${DURATION}"

echo "Capture completed."
