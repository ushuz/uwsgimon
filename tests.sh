#!/bin/bash

# add app.py / udp-server.py for tests
cat << EOF > app.py
def app(environ, start_response):
    data = b"Hello, World!\n"
    start_response("200 OK", [
        ("Content-Type", "text/plain"),
        ("Content-Length", str(len(data)))
    ])
    return iter([data])
EOF

cat << EOF > udp-server.py
from __future__ import print_function
import re
import socket
import sys
def main():
    if len(sys.argv) < 3:
        return sys.stderr.write('usage: udp-server.py port regex\n')
    pattern = re.compile(bytes(bytearray(sys.argv[2], 'latin-1')))
    address = ('0.0.0.0', int(sys.argv[1]))
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    s.bind(address)
    retry = 5
    while retry:
        data, addr = s.recvfrom(2048)
        print('received={} from={}'.format(repr(data), ':'.join(map(str, addr))))
        if pattern.search(data):
            break
        retry -= 1
    s.close()
    if not retry:
        sys.exit(1)
if __name__ == '__main__':
    main()
EOF

PORT_UWSGI=8080
PORT_UDP=31500

# launch uwsgi / uwsgimon
export UWSGI_HTTP11_SOCKET=":${PORT_UWSGI}"
export UWSGI_MODULE="app:app"
export UWSGIMON_FREQ=".5"
export UWSGIMON_UDP="127.0.0.1:${PORT_UDP}"

uwsgimon-launcher &
_UWSGI_PID="$!"

cleanup () {
  kill $_UWSGI_PID
  rm app.py udp-server.py
}

# assert req=0
python udp-server.py "$PORT_UDP" "req=0"
status="$?"
if [ $status -ne 0 ]; then
  cleanup
  exit $status
fi

# assert req=2
curl -sSL "http://127.0.0.1:${PORT_UWSGI}"
curl -sSL "http://127.0.0.1:${PORT_UWSGI}"

python udp-server.py "$PORT_UDP" "req=2"
status="$?"
if [ $status -ne 0 ]; then
  cleanup
  exit $status
fi

# all passed
cleanup
