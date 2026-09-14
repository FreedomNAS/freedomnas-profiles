#!/bin/sh
# FreedomNAS WebUI supervisor -- init-agnostic, circuit breaker after 5 failures.
FAILURES=0
MAX_FAILURES=5
WEBUI_DIR="/usr/lib/freedomnas/webui"

# The WebUI imports freedomnas-core, which is on no interpreter's default path
# -- see firstboot.sh.
PYTHONPATH="/usr/lib/freedomnas/core${PYTHONPATH:+:$PYTHONPATH}"
export PYTHONPATH
WEBUI_CMD="python3 -m uvicorn api.main:app --host 0.0.0.0 --port 8080"

# HTTP Basic sends the administrator's password on every request, so the WebUI
# speaks TLS whenever the certificate is there. An installation from before
# the certificate existed keeps working over plain HTTP rather than refusing
# to start.
TLS_CERT="/etc/freedomnas/tls/cert.pem"
TLS_KEY="/etc/freedomnas/tls/key.pem"
if [ -r "$TLS_CERT" ] && [ -r "$TLS_KEY" ]; then
    WEBUI_CMD="$WEBUI_CMD --ssl-certfile $TLS_CERT --ssl-keyfile $TLS_KEY"
fi

# The app mounts its static files and templates by relative path, so it has
# to run from its own directory. `python3 -m` then puts that directory on
# sys.path as well, which is what makes `api.main` importable.
cd "$WEBUI_DIR" || exit 1

while true; do
    $WEBUI_CMD
    EXIT=$?
    if [ $EXIT -ne 0 ]; then
        FAILURES=$((FAILURES + 1))
        echo "[$(date)] WebUI exited with code $EXIT (failure $FAILURES/$MAX_FAILURES)"
        if [ $FAILURES -ge $MAX_FAILURES ]; then
            echo "[$(date)] Circuit breaker OPEN -- stopping supervisor"
            exit 1
        fi
        sleep 5
    else
        FAILURES=0
    fi
done
