#!/usr/bin/env bash
set -Eeuo pipefail

RESULT_DIR="${1:-}"
if [[ -z "${RESULT_DIR}" || ! -d "${RESULT_DIR}" ]]; then
    echo "Usage: $0 /var/log/asterisk/rtcp-test/issue2012_TIMESTAMP"
    exit 1
fi

LOG_FILE="$(find "${RESULT_DIR}" -maxdepth 1 -type f -name '*_full.log' | head -n1)"
if [[ -z "${LOG_FILE}" ]]; then
    echo "ERROR: full log was not found in ${RESULT_DIR}."
    exit 1
fi

echo "Key RTCP report values"
echo "======================"
grep -E     'RTCP got report|Packets lost so far|Highest sequence number|lost:|SPC:|RTT|jitter'     "${LOG_FILE}" || true

echo
echo "Expected reproduction signature"
echo "==============================="
echo "Highest sequence number: 0"
echo "Packets lost so far: 1"
echo "lost: 1.000000000"
echo
echo "PCAP files:"
find "${RESULT_DIR}" -maxdepth 1 -type f -name '*.pcap' -print
