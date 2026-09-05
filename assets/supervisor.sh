#!/bin/sh
# FreedomNAS WebUI supervisor -- init-agnostic, circuit breaker after 5 failures.
FAILURES=0
MAX_FAILURES=5
WEBUI_CMD="python3 -m uvicorn --app-dir /usr/lib/freedomnas/webui api.main:app --host 0.0.0.0 --port 8080"

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
