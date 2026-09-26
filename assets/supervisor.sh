#!/bin/sh
# FreedomNAS WebUI supervisor -- init-agnostic, circuit breaker after 5 failures.
FAILURES=0
MAX_FAILURES=5
# <install_root>/profiles/assets/supervisor.sh, or a copy in
# <install_root>/webui/bin: the root is three levels up from the real file.
INSTALL_ROOT=$(dirname "$(dirname "$(dirname "$(realpath "$0")")")")
WEBUI_DIR="$INSTALL_ROOT/webui"

# The WebUI imports freedomnas-core, which is on no interpreter's default path
# -- see firstboot.sh.
PYTHONPATH="$INSTALL_ROOT/core${PYTHONPATH:+:$PYTHONPATH}"
export PYTHONPATH
WEBUI_CMD="python3 -m uvicorn api.main:app --host 0.0.0.0 --port 8080"

# HTTP Basic sends the administrator's password on every request, so the WebUI
# speaks TLS whenever the certificate is there. An installation from before
# the certificate existed keeps working over plain HTTP rather than refusing
# to start.
TLS_DIR=$(python3 -m freedomnas path tls)
TLS_CERT="$TLS_DIR/cert.pem"
TLS_KEY="$TLS_DIR/key.pem"
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
