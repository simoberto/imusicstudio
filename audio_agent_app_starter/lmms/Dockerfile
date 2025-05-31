# lmms/Dockerfile - Based on lmms/Dockerfile.prod from AI-Music-Studio-_parte2_.txt
FROM ubuntu:22.04 AS production

ENV DEBIAN_FRONTEND=noninteractive
ENV DISPLAY=:99
ENV QT_QPA_PLATFORM=offscreen
ENV LMMS_DISABLE_SPLASH=1

# Install LMMS and dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
   lmms \
   xvfb \
   pulseaudio \
   alsa-utils \
   libasound2-dev \
   libpulse-dev \
   sox \
   ffmpeg \
   fluid-soundfont-gm \
   fluid-soundfont-gs \
   timgm6mb-soundfont \
   freepats \
   python3 \
   python3-pip \
   curl \
   supervisor \
   && apt-get clean \
   && rm -rf /var/lib/apt/lists/*

# Install Python dependencies for any helper scripts (if needed by lmms_render.py)
# Assuming lmms_render.py might need these, as seen in the original AI-Music-Studio.txt
RUN pip3 install --no-cache-dir librosa soundfile numpy scipy

# Create directories
RUN mkdir -p /templates /soundfonts /data /scripts /var/log/supervisor

# Configure PulseAudio for headless
RUN echo "default-server = unix:/tmp/pulse-socket" > /etc/pulse/client.conf

# Copy scripts (These will be mounted via volumes in docker-compose.yml, but good to have in image if run standalone)
# COPY scripts/lmms_render.py /scripts/lmms_render.py
# COPY scripts/start_lmms.sh /scripts/start_lmms.sh
# RUN chmod +x /scripts/*.py /scripts/*.sh

# Create supervisor configuration to manage Xvfb and PulseAudio
RUN cat > /etc/supervisor/conf.d/lmms_headless.conf << 'EOF'
[program:xvfb]
command=/usr/bin/Xvfb :99 -screen 0 1024x768x24 -ac +extension GLX +render -noreset
autostart=true
autorestart=true
stdout_logfile=/var/log/supervisor/xvfb.log
stderr_logfile=/var/log/supervisor/xvfb.log

[program:pulseaudio]
command=/usr/bin/pulseaudio --start --exit-idle-time=-1 --system=false --disallow-exit
autostart=true
autorestart=true
stdout_logfile=/var/log/supervisor/pulseaudio.log
stderr_logfile=/var/log/supervisor/pulseaudio.log
EOF

# Create non-root user
RUN groupadd -r lmms && useradd -r -g lmms lmms
RUN chown -R lmms:lmms /templates /soundfonts /data /scripts /var/log/supervisor

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
  CMD pgrep -f "Xvfb" > /dev/null || exit 1

# Labels
LABEL maintainer="AI Music Studio Team"
LABEL version="2.0.0" # Assuming version from App.js
LABEL description="AI Music Studio - LMMS Headless Renderer"

# Switch to non-root user
USER lmms

WORKDIR /scripts

# Start supervisor (which starts Xvfb and PulseAudio)
# The actual lmms command will be run by n8n using 'docker exec' or similar.
# This container just needs to provide the environment.
CMD ["/usr/bin/supervisord", "-n", "-c", "/etc/supervisor/supervisord.conf"]
