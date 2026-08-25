# RTCP issue #2012 test environment

This directory reproduces [Asterisk issue #2012](https://github.com/asterisk/asterisk/issues/2012): an endpoint receives no outbound RTP, continues sending RTCP reports with an extended highest sequence number of zero, while Asterisk keeps the reported loss at one.

## 1. Install the test configuration

Run from the Asterisk source checkout:

```bash
cd rtcp-test
chmod +x config.sh blockrtp.sh analyze.sh
./config.sh
```

The script preserves the existing Asterisk configuration and adds three include files:

- `/etc/asterisk/rtcp-test-pjsip.conf`
- `/etc/asterisk/rtcp-test-extensions.conf`
- `/etc/asterisk/rtcp-test-logger.conf`

A timestamped backup of the original include hosts is also created under `/etc/asterisk`.

## 2. Register two SIP phones

Use the Asterisk VM address and UDP port 5062.

| Extension | Password |
| --- | --- |
| 1001 | RtcpTest1001 |
| 1002 | RtcpTest1002 |

Extensions 1001 and 1002 can call each other. Extension 700 is the isolated RTCP reproduction dialplan.

## 3. Reproduce the issue

Start the collector before or immediately after calling 700:

```bash
cd rtcp-test
./blockrtp.sh 1002 60
```

Then call extension 700 from phone 1002 and keep the call active. Echo() produces bidirectional media without depending on MOH or sound files. The script detects `RTP_DEST`, captures RTCP, and blocks only outbound RTP from Asterisk to the phone. Its trap always removes the iptables rule and disables RTP/RTCP debugging.

Results are stored under:

```text
/var/log/asterisk/rtcp-test/issue2012_TIMESTAMP/
```

Each result contains the full Asterisk log, RTCP PCAP, tcpdump output, and metadata.

## 4. Inspect the result

```bash
./analyze.sh /var/log/asterisk/rtcp-test/issue2012_TIMESTAMP
```

The original reproduction signature was:

```text
RTCP got report ...
Packets lost so far: 1
Highest sequence number: 0
lost: 1.000000000
```
