# AI Music Studio - Troubleshooting Guide

This guide provides solutions to common issues you might encounter while setting up or using AI Music Studio.

## General Setup & Docker Issues

**1. Docker / Docker Compose Not Found**
   - **Symptom**: Errors like `docker: command not found` or `docker-compose: command not found`.
   - **Solution**: Ensure Docker Desktop (or Docker Engine + Docker Compose CLI plugin) is installed correctly for your operating system and that the `docker` and `docker-compose` (or `docker compose`) commands are in your system's PATH.
     - Visit [Docker's official website](https://www.docker.com/products/docker-desktop) for installation instructions.

**2. Services Fail to Start (Port Conflicts)**
   - **Symptom**: `docker-compose up` fails with errors like `Bind for 0.0.0.0:5678 failed: port is already allocated` or similar for ports 3000, 8080, 9090, 3001, 5432, 6379.
   - **Solution**: Another application on your system is using one of the ports AI Music Studio requires.
     - Identify the conflicting service:
       - Linux/macOS: `sudo lsof -i :<port_number>` or `sudo netstat -tulnp | grep <port_number>`
       - Windows: `netstat -ano | findstr :<port_number>`
     - Stop the conflicting application or change the port mapping in the `docker-compose.yml` file for the AI Music Studio service. For example, to change n8n's external port from 5678 to 5679:
       ```yaml
       # In docker-compose.yml
       services:
         n8n:
           ports:
             - "5679:5678" # Host port 5679 maps to container port 5678
       ```
       Remember to update your access URLs accordingly (e.g., `http://localhost:5679` for n8n).

**3. Insufficient System Resources (RAM, Disk Space)**
   - **Symptom**: Services crash, Docker build fails, slow performance, "out of memory" errors in logs.
   - **Solution**:
     - **RAM**: AI Music Studio (especially Audiocraft) can be memory-intensive. Ensure your system meets the minimum RAM requirements (8GB, 16GB+ recommended). Close other memory-heavy applications. If using Docker Desktop, increase the memory allocated to Docker in its settings.
     - **Disk Space**: Ensure you have sufficient free disk space (20GB+ recommended) for Docker images, volumes, and generated audio files. Use `docker system prune -af` to remove unused Docker data, but be cautious as this removes all unused images, containers, networks, and build cache.

**4. Permission Denied Errors (Volume Mounts, Script Execution)**
   - **Symptom**: Errors related to file access, script execution (`permission denied`), or Docker volume mounts.
   - **Solution**:
     - **Scripts**: Ensure all shell scripts (`.sh`) in the `scripts/` directory are executable: `chmod +x scripts/*.sh`. Python scripts run via `python3 script.py` don't always need execute bit but it's good practice for entrypoint scripts.
     - **Docker Volumes on Linux**: If you encounter permission issues with Docker writing to mounted host directories (like `./data` or `./models`), it might be due to UID/GID mismatches between the host user and the container user.
       - The Dockerfiles attempt to use non-root users. If issues persist, ensure the host directories (e.g., `audio_agent_app_starter/data`) are writable by the UID/GID used inside the containers (often 1000 or 1001).
       - Quick fix (use with caution): `sudo chmod -R 777 ./data ./models`. A better fix involves matching UIDs or using Docker volume drivers that handle permissions.
     - **SELinux/AppArmor**: If on a Linux system with SELinux or AppArmor enabled, security policies might interfere with Docker operations or file access. Check system logs (`audit.log` for SELinux) and adjust policies if necessary (e.g., `chcon -Rt svirt_sandbox_file_t ./data` for SELinux if context is the issue).

## AI Music Generation (Audiocraft) Issues

**1. GPU Not Detected / CUDA Errors**
   - **Symptom**: Audiocraft logs show errors like "CUDA not available", "No GPU found", or CUDA-specific error codes. Generation falls back to CPU (slow) or fails.
   - **Solution**:
     - **NVIDIA Drivers**: Ensure you have the latest NVIDIA drivers installed on your host machine.
     - **NVIDIA Container Toolkit**: Verify that the [NVIDIA Container Toolkit](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html) (formerly nvidia-docker2) is installed and configured correctly. This allows Docker containers to access NVIDIA GPUs.
     - **Docker Configuration**: Your Docker daemon might need to be configured to use the NVIDIA runtime as default, or you need to specify runtime in `docker-compose.yml` for the `audiocraft` service (though the `deploy.resources.reservations.devices` section in `docker-compose.yml` usually handles this for modern Docker versions).
     - **CUDA Version**: The `audiocraft/Dockerfile` is built for a specific CUDA version (e.g., 12.1.1). Ensure your host NVIDIA driver is compatible with this CUDA version. Driver version compatibility can be checked on NVIDIA's website.
     - **`CUDA_VISIBLE_DEVICES`**: Check the `.env` file. If you have multiple GPUs, ensure `CUDA_VISIBLE_DEVICES` is set to the correct GPU index(es) or leave it unset to use all available.
     - **Audiocraft Logs**: Check `docker-compose logs audiocraft` for detailed error messages.

**2. Slow Generation / High CPU Usage (Even with GPU)**
   - **Symptom**: Generation takes a very long time, and CPU usage is high while GPU usage is low.
   - **Solution**:
     - This might indicate that PyTorch or Audiocraft is not correctly utilizing the GPU. Double-check all GPU setup steps above.
     - Ensure the correct PyTorch version with CUDA support was installed in the `audiocraft` Docker image.
     - Check for any warnings during Audiocraft model loading in the logs.

**3. "Out of Memory" Errors (OOM)**
   - **Symptom**: Audiocraft container crashes or logs show "OutOfMemoryError", "CUDA out of memory".
   - **Solution**:
     - **GPU VRAM**: Music generation models can be VRAM-intensive.
       - Use smaller models (e.g., `facebook/musicgen-small` if `medium` or `large` cause OOM). This can be configured in `config/audio_settings.json` or passed via API.
       - Reduce batch size or other memory-affecting parameters if configurable in `musicgen_stem.py`.
       - Ensure no other applications are heavily using GPU VRAM.
     - **System RAM**: If it's system RAM OOM (less likely for the generation part itself if GPU is used, but possible for data handling), ensure sufficient RAM is allocated to Docker (Docker Desktop settings) and available on the host.
     - The `PYTORCH_CUDA_ALLOC_CONF: "max_split_size_mb:512"` in `docker-compose.yml` for `audiocraft` attempts to mitigate fragmentation but might need tuning.

**4. Low Quality Audio / Unexpected Results**
   - **Symptom**: Generated audio is noisy, distorted, silent, or not matching the prompt.
   - **Solution**:
     - **Prompt Engineering**: Experiment with more detailed and specific prompts. Include BPM, key, mood, and specific instrument characteristics.
     - **Temperature**: Adjust the `temperature` parameter in the API request. Lower values (e.g., 0.7-0.9) are more predictable; higher values (e.g., 1.0-1.2) are more creative but can be chaotic.
     - **Model Choice**: Try different models (small, medium, large) if available and resources permit. Larger models may yield better quality for complex prompts.
     - **Post-processing**: The `musicgen_stem.py` script includes some post-processing. If issues are consistent for an instrument, these settings might need adjustment in the script.
     - **Input Duration**: Very short durations might not give the model enough time to develop an idea. MusicGen models often perform best with durations around 5-30 seconds for a single pass.

## n8n Workflow & API Issues

**1. n8n Webhook Not Triggering / API Endpoint Unresponsive**
   - **Symptom**: Sending requests to API endpoints (e.g., `/api/mcp/generate-melody`) results in 404 Not Found or connection errors.
   - **Solution**:
     - **Nginx Running**: Ensure the `nginx` service is running: `docker-compose ps nginx`.
     - **n8n Running**: Ensure the `n8n` service is running and healthy: `docker-compose ps n8n`. Check its logs: `docker-compose logs n8n`.
     - **Nginx Configuration**: Verify `nginx/nginx.conf` correctly proxies requests to the `n8n` service (upstream `n8n_service` should point to `n8n:5678`).
     - **Webhook Paths**: Ensure the paths in `nginx.conf` (e.g., `/api/mcp/generate-melody`) correctly map to the webhook paths defined in your n8n workflows (e.g., `generate-melody` in the Webhook node). The `n8n_mcp_workflows.json` uses relative paths like `generate-melody`. Nginx should prepend `/api/mcp` or similar if that's your desired external API structure. The provided `nginx.conf` proxies `/api/...` and `/webhook/...` to n8n. The n8n workflow webhooks are defined with paths like `generate-melody`. So, Nginx needs to route, for example, `/api/mcp/generate-melody` to `http://n8n:5678/generate-melody` (or whatever the n8n webhook node's actual path is, often `/webhook/generate-melody`).
       - The provided `nginx.conf` has `location ~ ^/(api|webhook|webhook-test|rest|healthz)/ { proxy_pass http://n8n_service; }`. This means a request to `https://domain/api/mcp/generate-melody` would be proxied to `http://n8n:5678/api/mcp/generate-melody`. The n8n webhook node must be configured with the path `/api/mcp/generate-melody`.
       - **Correction**: The n8n workflows use paths like `generate-melody`. Nginx should proxy `/api/mcp/generate-melody` to `http://n8n:5678/webhook/generate-melody` if n8n webhooks are automatically prefixed with `/webhook/`. Or, n8n webhook path should be `/api/mcp/generate-melody`. The provided n8n JSON has `path: "generate-melody"`. So Nginx should route `/api/mcp/generate-melody` to `http://n8n_service/generate-melody`.
         The `nginx.conf` proxies `/api/` to `n8n_service`. So a request to `/api/mcp/generate-melody` goes to `n8n_service/api/mcp/generate-melody`. The n8n webhook node path should be `mcp/generate-melody` and the `N8N_PATH_PREFIX=/api/` env var could be set for n8n. Or, adjust Nginx `proxy_pass` to strip `/api/mcp`.
         Simplest: n8n webhook path is `generate-melody`. Nginx: `location /api/mcp/generate-melody { proxy_pass http://n8n_service/generate-melody; }`. The current `nginx.conf` is more generic.

**2. n8n Workflow Executions Failing**
   - **Symptom**: API requests return 200 OK (due to `onReceived` mode), but no output is generated, or WebSocket notifications indicate failure.
   - **Solution**:
     - **Check n8n UI**: Open n8n (`http://localhost:5678`), go to "Executions", and inspect failed workflow runs for error messages and problematic nodes.
     - **Docker Exec Nodes**: Ensure the `docker exec` commands in "Execute Command" nodes are correct:
       - Service names (`aimusic-audiocraft`, `aimusic-lmms`) must match `container_name` in `docker-compose.yml`.
       - Script paths (`/scripts/musicgen_stem.py`, `/scripts/mix_master.sh`) must be correct within the containers.
       - File paths (`/data/...`) must be accessible and correctly passed.
     - **Permissions for Docker Exec**: The user running the n8n Docker container might need permission to execute `docker exec` commands if n8n is not running as root *and* is not configured to access the Docker socket securely. This is usually handled by Docker-in-Docker setups or by mounting the Docker socket (`/var/run/docker.sock`) into the n8n container (with security implications). The provided setup does not explicitly mount `docker.sock` to n8n, so `docker exec` from n8n to other containers on the same host network should work if n8n container has docker CLI and appropriate network access.
     - **Script Errors**: Check logs of the target containers (`audiocraft`, `lmms`) for errors from the Python/bash scripts: `docker-compose logs audiocraft`.

**3. File Not Found Errors in n8n Workflows or Scripts**
   - **Symptom**: Workflows or scripts fail because they can't find input files or write output files.
   - **Solution**:
     - **Volume Mounts**: Verify that the `./data:/data` volume mount is correctly configured for all services that need to access shared audio files (n8n, audiocraft, lmms, nginx for serving).
     - **Path Consistency**: Ensure that file paths used in n8n workflows (e.g., `/data/stems/output.wav`) are consistent with paths used inside scripts and how volumes are mounted. All services should refer to shared files using the same absolute path within their container (e.g., `/data/...`).

## Frontend (React App) Issues

**1. Frontend Not Loading / "Cannot GET /"**
   - **Symptom**: Browser shows a "Cannot GET /" error or a blank page.
   - **Solution**:
     - **Frontend Service**: Ensure the `frontend` service is running: `docker-compose ps frontend`.
     - **Nginx Proxy**: If Nginx is not proxying to the frontend correctly, this can happen. Check `nginx` logs (`docker-compose logs nginx`) and `nginx/nginx.conf`. Ensure `proxy_pass http://frontend:3000;` (or the correct internal port for the frontend service) is correct.
     - **React Build**: If you built a static version, ensure Nginx is configured to serve `index.html` for all SPA routes (e.g., using `try_files $uri /index.html;`). The `frontend/Dockerfile` uses Nginx to serve the build; check its internal `nginx.conf`.

**2. API Calls Failing from Frontend**
   - **Symptom**: Network errors in browser console for API requests (e.g., to `/api/mcp/...`).
   - **Solution**:
     - **Proxy Setup**: The `frontend/package.json` includes `"proxy": "http://localhost:5678"`. This is for `npm start` development mode. For Dockerized Nginx, ensure Nginx correctly proxies `/api/mcp/...` requests to the `n8n` service.
     - **CORS Issues**: If frontend and backend are on different "origins" (domains/ports) without Nginx as a unified entry point, you might face CORS errors. Nginx reverse proxy should handle this by making them appear as same-origin. If direct calls are made in some setup, n8n might need CORS headers configured (e.g., via environment variables like `N8N_CORS_ALLOWED_ORIGINS`).
     - **`REACT_APP_API_URL`**: Ensure this environment variable is correctly set for the frontend container if it makes absolute URL calls (though relative calls proxied by Nginx are common).

**3. WebSocket Connection Failed**
   - **Symptom**: Real-time updates not working, browser console shows WebSocket connection errors.
   - **Solution**:
     - **WebSocket Service**: Ensure `websocket` service is running: `docker-compose ps websocket`. Check its logs: `docker-compose logs websocket`.
     - **Nginx Proxy for WebSocket**: Verify `nginx/nginx.conf` has the correct `location /ws/ { ... }` block with `proxy_set_header Upgrade $http_upgrade;` and `proxy_set_header Connection "upgrade";`.
     - **`REACT_APP_WS_URL`**: Ensure this env var in the frontend points to the correct WebSocket URL (e.g., `ws://localhost/ws/` if Nginx is on port 80, or `ws://localhost:8080/` if connecting directly to the WebSocket service during local dev without Nginx). The `App.js` tries to construct this dynamically.

## General Debugging Tips

-   **Check Container Logs**: The first step for any issue is to check the logs of the relevant service(s):
    `docker-compose logs <service_name>` (e.g., `docker-compose logs n8n`).
    Add `-f` for live log tailing: `docker-compose logs -f <service_name>`.
-   **Docker PS**: See running containers and their status: `docker-compose ps`.
-   **Exec into Container**: Access a running container's shell for debugging:
    `docker-compose exec <service_name> /bin/sh` (or `/bin/bash`).
-   **Restart Services**: `docker-compose restart <service_name>` or `docker-compose up -d --force-recreate <service_name>`.
-   **Clean Rebuild**: If things are very broken, try a clean rebuild (this will remove data in Docker volumes unless they are external):
    `docker-compose down -v` (stops and removes containers, networks, volumes)
    `docker system prune -af` (removes all unused Docker data)
    `docker-compose build --no-cache`
    `docker-compose up -d`
-   **Increase Docker Resources**: In Docker Desktop settings, allocate more CPU, Memory, and Disk space if you suspect resource exhaustion.

If you encounter an issue not covered here, please provide detailed logs and steps to reproduce when seeking help.
