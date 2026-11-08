#!/bin/sh
# FreedomNAS WebUI supervisor -- init-agnostic, circuit breaker after 5 failures.
# Next to the WebUI it keeps `python3 -m freedomnas serve` running, which
# checks the modules and retries or blocks the failing ones: each loop counts
# its own failures, so one stopping never stops the other. serve exits with
# 75 when the installed modules change, to be started again with the new set.
# A restart the WebUI asks for itself (System -> Restart WebUI, or the notice
# after an update) leaves the marker <config>/webui-restart before it exits:
# that exit is not a failure, and the WebUI starts again at once.
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
# api.serve answers a plain http:// request on the WebUI's port with a redirect
# to https://; a WebUI from before it has only uvicorn.
if [ -f "$WEBUI_DIR/api/serve.py" ]; then
    WEBUI_CMD="python3 -m api.serve --host 0.0.0.0 --port 8080"
else
    WEBUI_CMD="python3 -m uvicorn api.main:app --host 0.0.0.0 --port 8080"
fi

# HTTP Basic sends the administrator's password on every request, so the WebUI
# speaks TLS whenever the certificate is there. An installation from before
# the certificate existed keeps working over plain HTTP rather than refusing
# to start.
TLS_DIR=$(python3 -m freedomnas path tls)
RESTART_MARKER="$(python3 -m freedomnas path config)/webui-restart"
rm -f "$RESTART_MARKER"
TLS_CERT="$TLS_DIR/cert.pem"
TLS_KEY="$TLS_DIR/key.pem"

# The app mounts its static files and templates by relative path, so it has
# to run from its own directory. `python3 -m` then puts that directory on
# sys.path as well, which is what makes `api.main` importable.
cd "$WEBUI_DIR" || exit 1

serve_loop() {
    failures=0
    while true; do
        python3 -m freedomnas serve
        code=$?
        if [ $code -eq 75 ]; then
            failures=0
            continue
        fi
        if [ $code -ne 0 ]; then
            failures=$((failures + 1))
            echo "[$(date)] Module checks exited with code $code (failure $failures/$MAX_FAILURES)"
            if [ $failures -ge $MAX_FAILURES ]; then
                echo "[$(date)] Module checks stopped after $MAX_FAILURES failures"
                return 1
            fi
        fi
        sleep 5
    done
}
serve_loop </dev/null &

# Checked before every start, not only at boot: an update installed without
# a reboot (or a restart from the WebUI after it) gets FreedomNAS's CA and a
# certificate for this host's names and addresses at once.
while true; do
    python3 -m freedomnas ensure-tls >/dev/null || echo "[$(date)] WARNING: could not check the TLS certificate"
    if [ -r "$TLS_CERT" ] && [ -r "$TLS_KEY" ]; then
        $WEBUI_CMD --ssl-certfile "$TLS_CERT" --ssl-keyfile "$TLS_KEY"
    else
        $WEBUI_CMD
    fi
    EXIT=$?
    if [ -e "$RESTART_MARKER" ]; then
        rm -f "$RESTART_MARKER"
        FAILURES=0
        echo "[$(date)] WebUI restarted on request (exit code $EXIT)"
    elif [ $EXIT -ne 0 ]; then
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
