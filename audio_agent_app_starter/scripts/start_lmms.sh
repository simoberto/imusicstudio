#!/bin/bash
#
# LMMS Headless Startup Script
# Sets up Xvfb and PulseAudio for headless LMMS operations.
# This script is typically used as the CMD or ENTRYPOINT for the LMMS Docker container.

set -euo pipefail

# Log function
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] [start_lmms.sh]: $*"
}

log "Starting LMMS headless environment setup..."

# Start Xvfb for headless display
# -screen 0 1024x768x24: Creates a virtual screen 0 with 1024x768 resolution and 24-bit color.
# -ac: Disables access control, allowing any client to connect.
# +extension GLX: Enables GLX extension for OpenGL support if needed by LMMS.
# +render: Enables RENDER extension.
# -noreset: Prevents server reset on client disconnect.
log "Starting Xvfb display server on :99..."
Xvfb :99 -screen 0 1024x768x24 -ac +extension GLX +render -noreset &
XVFB_PID=$!
log "Xvfb PID: $XVFB_PID"

# Start PulseAudio
# --start: Starts PulseAudio as a daemon.
# --exit-idle-time=-1: Prevents PulseAudio from exiting when idle.
# --system=false: Runs PulseAudio as a user service, not system-wide. Recommended.
# --disallow-exit: Prevents clients from requesting PulseAudio to exit.
log "Starting PulseAudio server..."
pulseaudio --start --exit-idle-time=-1 --system=false --disallow-exit &
PULSE_PID=$!
log "PulseAudio PID: $PULSE_PID"

# Wait for services to be ready
# A short delay to allow Xvfb and PulseAudio to initialize properly.
log "Waiting for services to initialize (5 seconds)..."
sleep 5

# Export display environment variable for applications to find Xvfb
export DISPLAY=:99
log "DISPLAY environment variable set to :99"

# Verify LMMS can find the display and is operational (optional basic check)
log "Verifying LMMS headless capability..."
if lmms --version > /dev/null 2>&1; then
    log "LMMS version check successful."
else
    log "Warning: 'lmms --version' command failed or LMMS not found in PATH. Ensure LMMS is correctly installed."
    # Depending on strictness, you might choose to exit here if this check is critical.
    # For now, it's a warning as the container might still function if lmms is found by other means.
fi

log "LMMS headless environment setup complete. Services are running."
log "Xvfb (PID: $XVFB_PID) and PulseAudio (PID: $PULSE_PID) should be active."

# Function to cleanup on exit
# This ensures that Xvfb and PulseAudio are terminated when the script/container exits.
cleanup() {
   log "Caught signal, cleaning up Xvfb and PulseAudio..."
   # Kill processes gracefully first, then forcefully if needed
   if kill $PULSE_PID $XVFB_PID 2>/dev/null; then
       log "PulseAudio and Xvfb signaled to terminate."
   else
       log "PulseAudio and Xvfb might have already exited or failed to signal."
   fi
   # Wait a moment for them to shut down
   sleep 2
   # Force kill if still running
   kill -9 $PULSE_PID $XVFB_PID 2>/dev/null || true
   log "Cleanup complete."
   wait # Wait for any child processes to ensure they are reaped
}

# Trap signals to ensure cleanup runs on script termination
trap cleanup EXIT SIGINT SIGTERM

# Keep the script running (and thus the container alive if this is the main process)
# This loop keeps the container running. If this script is just an initializer
# and another process takes over (like supervisord in the lmms/Dockerfile.prod example),
# this loop might not be necessary or might be replaced by `exec "$@"`.
# Given the lmms/Dockerfile.prod uses supervisord, this script would be run by supervisord,
# or parts of its logic incorporated into how supervisord starts these services.
# If this script IS the CMD of a simpler Dockerfile, then this loop is essential.
log "Container is now running with Xvfb and PulseAudio."
log "This script will keep running to maintain the services."
log "To stop, send SIGINT or SIGTERM to this script/container."

while true; do
  # Check if Xvfb or PulseAudio are still running; if not, maybe exit or restart them.
  # Basic check:
  if ! kill -0 $XVFB_PID 2>/dev/null; then
    log "Xvfb (PID: $XVFB_PID) is no longer running! Exiting."
    exit 1 # Or attempt to restart Xvfb
  fi
  if ! kill -0 $PULSE_PID 2>/dev/null; then
    log "PulseAudio (PID: $PULSE_PID) is no longer running! Exiting."
    exit 1 # Or attempt to restart PulseAudio
  fi
  sleep 30 # Check every 30 seconds
done
