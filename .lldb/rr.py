import lldb
import logging
import subprocess

logger = logging.getLogger(__name__)

def rr(debugger, command, result, _):
    # Let Ctrl-C go to the inferior, not the LLDB interpreter
    debugger.HandleCommand("process handle SIGINT -p true -s false -n false")

    # Kill if something is already running
    try:
        proc = debugger.GetSelectedTarget().process
        if proc and proc.IsValid() and proc.state not in (lldb.eStateExited, lldb.eStateDetached):
            proc.Kill()
    except Exception as e:
        logger.warn(e)

    # Build outside of LLDB so TTY and signals stay clean
    try:
        subprocess.run("zig build".split(), check=True)
    except subprocess.CalledProcessError as e:
        result.SetError(f"[rr] build failed: {e}")
        return
    lldb.debugger.HandleCommand("run")
