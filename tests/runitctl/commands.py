import shlex
import sys
from pathlib import Path

core, profiles, edition = sys.argv[1:4]
sys.path[:] = [p for p in sys.path if not (Path(p or ".") / "freedomnas" / "__init__.py").is_file()]
sys.path.insert(0, core)
from engine import FreedomNASEngine

engine = FreedomNASEngine.for_target(edition, profile_dir=profiles, init_system="runit")
for action in ("start", "stop", "restart", "enable", "disable", "enable_offline", "disable_offline",
               "status", "is_enabled", "reload", "list_all", "is_running", "list_managed"):
    command = engine.get_command("services", action, service_name="fnastest")
    print(f"cmd_{action}={shlex.quote(command)}")
