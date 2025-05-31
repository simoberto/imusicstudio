# AI Music Studio - Production Grade

![AI Music Studio Banner](docs/images/banner.png) <!-- Placeholder for a banner image -->

**Transform your musical ideas into reality with AI Music Studio, a professional-grade, AI-powered music production platform. Generate unique stems, compose full tracks, and achieve broadcast-quality mixes and masters, all within a seamless, containerized environment.**

AI Music Studio democratizes music creation, making it accessible for content creators, musicians, producers, businesses, and anyone with a passion for music—no prior musical experience required!

## Core Features

-   🚀 **Advanced AI Music Generation**: Leverages MusicGen-Stem for instrument-specific audio generation (bass, drums, guitar, piano, synth, vocals, etc.).
-   🎧 **Intelligent Mixing & Mastering**: Automated analysis and adaptive processing (EQ, compression) for optimized sound, plus LUFS normalization to industry standards (-14 LUFS Spotify, -13 LUFS YouTube). Includes Matchering integration for AI-powered reference mastering.
-   🎼 **Full Composition System**: End-to-end track creation from text prompts, featuring intelligent arrangement by genre (Electronic, Rock, Jazz, Ambient, Hip-Hop) and complexity scaling.
-   🔧 **DAW Integration (Headless LMMS)**: Utilizes LMMS for professional and versatile headless rendering, supported by a template system for various instruments and styles.
-   🌐 **Modern Web Interface**: Intuitive React-based frontend with real-time WebSocket updates, waveform visualizations, and an integrated audio player.
-   🤖 **MCP Server Integration**: Control core functionalities directly via natural language with tools like Claude or other MCP-compatible interfaces.
-   ⚙️ **Workflow Orchestration (n8n)**: Robust backend logic managed by n8n, handling API requests, job queuing (Redis), and execution of audio tasks.
-   🐳 **Containerized & Scalable**: Easy deployment with Docker Compose, designed for production with multi-container architecture, health checks, and GPU acceleration.
-   📊 **Monitoring & Analytics**: Built-in Prometheus and Grafana stack for system metrics, performance tracking, and optional user analytics.
-   🛡️ **Security Focused**: Non-root users in containers, environment variable-based secrets, Nginx reverse proxy with security headers.

## Quick Start (Local Development)

1.  **Prerequisites**:
    *   [Docker Desktop](https://www.docker.com/products/docker-desktop/) installed and running.
    *   Git installed.
    *   Sufficient resources (min 8GB RAM, 20GB disk; NVIDIA GPU highly recommended for performance).

2.  **Clone & Setup**:
    ```bash
    git clone https://github.com/your-username/ai-music-studio.git audio_agent_app_starter # Replace with your repo URL
    cd audio_agent_app_starter
    chmod +x LAUNCH_SCRIPT.sh scripts/*.sh scripts/*.py
    ./LAUNCH_SCRIPT.sh
    # Choose option 1 (Local Development Setup & Run) or 4 (Run Only setup_environment.sh)
    # If you chose option 4, then run: docker-compose up -d --build
    ```

3.  **Access Services**:
    *   **Frontend App**: [http://localhost:3000](http://localhost:3000)
    *   **n8n Admin/Editor**: [http://localhost:5678](http://localhost:5678)
    *   **Grafana Monitoring**: [http://localhost:3001](http://localhost:3001) (admin/admin or as set in `.env`)
    *   **Prometheus Metrics**: [http://localhost:9090](http://localhost:9090)

4.  **Import n8n Workflows (if not done by setup script)**:
    *   Navigate to n8n: [http://localhost:5678](http://localhost:5678)
    *   Go to "Workflows" > "Import".
    *   Upload `workflows/n8n_mcp_workflows.json`.
    *   Ensure the imported workflows ("Generate Melody API", "Mix Master API", "Full Composition API") are **active**.

5.  **Test Generation**:
    *   Open the Frontend App ([http://localhost:3000](http://localhost:3000)).
    *   Go to the "Generate Stem" tab.
    *   Instrument: `bass`, Prompt: `funky slap bass groove, 120 BPM, E minor`
    *   Click "Generate Stem". Wait for the process to complete.

## System Requirements

| Component        | Minimum                               | Recommended                                   |
| :--------------- | :------------------------------------ | :-------------------------------------------- |
| **OS**           | Linux, macOS (Windows via WSL2)       | Ubuntu 22.04 LTS                              |
| **CPU**          | 4 Cores                               | 8+ Cores (modern CPU)                         |
| **RAM**          | 8 GB                                  | 16+ GB                                        |
| **GPU**          | Optional (CPU fallback)               | NVIDIA RTX 3060+ (12GB+ VRAM) for AI tasks    |
| **Storage**      | 20 GB SSD                             | 50+ GB NVMe SSD                               |
| **Software**     | Docker & Docker Compose               | Latest versions                               |
| **GPU Driver**   | (If using GPU) NVIDIA Driver 525.xx+  | Latest NVIDIA Studio or Datacenter Driver     |
| **CUDA Toolkit** | (If using GPU) CUDA 12.1+ compatible  | CUDA 12.1+ (as per Audiocraft Dockerfile)     |

## Project Structure

A brief overview of the main directories:

```
audio_agent_app_starter/
├── audiocraft/             # AI Music Generation (Audiocraft Docker setup)
├── config/                 # Configuration files (Postgres init, Nginx, app settings)
├── data/                   # Persistent data (generated audio, reports - gitignored by default)
├── docs/                   # Project documentation
├── frontend/               # React frontend application
├── lmms/                   # LMMS Headless DAW (Docker setup)
├── monitoring/             # Prometheus & Grafana configurations
├── nginx/                  # Nginx reverse proxy configurations
├── scripts/                # Backend scripts, setup, deployment utilities
├── templates/              # LMMS project templates
├── test/                   # Integration and E2E tests
├── websocket/              # WebSocket server for real-time communication
├── workflows/              # n8n workflow definitions
├── .env                    # Local environment variables (generated by setup, gitignored)
├── docker-compose.yml      # Main Docker Compose for development/base services
├── docker-compose.prod.yml # Docker Compose overrides for production
├── LAUNCH_SCRIPT.sh        # Main interactive script for setup/deployment
└── README.md               # This file
```

## API Endpoints (via Nginx Reverse Proxy)

All API endpoints are prefixed with `/api/mcp/` when accessed externally. Internally, n8n webhooks are configured at the root path.

*   **Generate Melody/Stem**: `POST /api/mcp/generate-melody`
    *   **Body**: `{ "instrument": "bass", "prompt": "deep house bass line", "duration": 30, "temperature": 1.0 }`
*   **Mix & Master Stems**: `POST /api/mcp/mix-master`
    *   **Body**: `{ "stems": ["/data/stems/id1_bass.wav", "/data/stems/id2_drums.wav"], "targetLUFS": -14 }`
*   **Full Track Composition**: `POST /api/mcp/compose-track`
    *   **Body**: `{ "style": "electronic", "bpm": 128, "key": "A minor", "duration": 120, "complexity": 7, "title": "My AI Track" }`

See `docs/api_reference.md` for detailed API documentation.

## Technology Stack

-   **Frontend**: React 18, Tailwind CSS, Framer Motion, Axios, Lucide Icons
-   **Backend Orchestration**: n8n (Workflow Automation)
-   **AI Music Generation**: Meta Audiocraft (MusicGen)
-   **DAW Processing**: LMMS (Linux MultiMedia Studio - Headless)
-   **Real-time Communication**: Node.js + WebSocket (ws library)
-   **Database**: PostgreSQL 15
-   **Caching/Queueing**: Redis 7
-   **Reverse Proxy**: Nginx
-   **Containerization**: Docker, Docker Compose
-   **System Monitoring**: Prometheus, Grafana
-   **Audio Manipulation (Scripts)**: Python (Librosa, PyTorch, NumPy, Pydub), Bash (SoX, FFmpeg)
-   **Testing**: Mocha, Chai, Axios (Integration); Puppeteer (E2E - conceptual)

## Configuration

-   **Local Environment**: Managed via `.env` file (generated by `setup_environment.sh`).
-   **Production Environment**: Managed via `.env.production` (see `scripts/publish.sh` for details).
-   **Application Settings**: `config/audio_settings.json`, `config/lmms_config.xml`.
-   **Nginx**: `nginx/nginx.conf` (dev), `nginx/nginx.prod.conf` (prod).
-   **Docker**: `docker-compose.yml`, `docker-compose.prod.yml`, service-specific Dockerfiles.

## Development

1.  Ensure Docker Desktop is running.
2.  Run `./LAUNCH_SCRIPT.sh` and choose option 1 for local setup and start.
3.  Frontend development server (with hot-reloading): `cd frontend && npm start` (after initial setup).
4.  Backend changes (Python scripts, n8n workflows) might require restarting relevant Docker containers.
    *   `docker-compose restart n8n audiocraft lmms websocket`

## Testing

-   **Integration Tests**: Run using the test runner service defined in `docker-compose.test.yml`.
    ```bash
    # Ensure main application is running
    docker-compose -f docker-compose.yml -f docker-compose.test.yml run --rm test_runner
    ```
-   **E2E Tests**: (Conceptual) Would use a framework like Puppeteer or Cypress against the running frontend.

See `test/integration.test.js` for examples.

## Production Deployment

Deployment to staging and production is managed by `scripts/publish.sh`. This script orchestrates:
- Building production Docker images.
- Pushing images to a container registry (e.g., GHCR).
- (Conceptually) Provisioning cloud infrastructure via IaC tools like Terraform.
- Deploying the application stack using `docker-compose.prod.yml` and `scripts/deploy.sh`.
- Setting up SSL, DNS, monitoring, and backups.

**Prerequisites for Production Deployment**:
-   Configured `.env.production` and `.env.staging` files with all necessary secrets and parameters.
-   Access to a Docker container registry.
-   Cloud provider account and CLI tools if using IaC.
-   Domain name and DNS management access.
-   SSL certificates (e.g., from Let's Encrypt).

Refer to `scripts/publish.sh` and `scripts/deploy.sh` for more details.

## Troubleshooting

-   **Service not starting**: Check logs with `docker-compose logs <service_name>`.
-   **GPU issues (Audiocraft)**: Ensure NVIDIA drivers, CUDA toolkit, and NVIDIA Container Toolkit are correctly installed on the host if using a local GPU. Verify `CUDA_VISIBLE_DEVICES` in `.env`.
-   **n8n Workflow Errors**: Check n8n editor (Executions panel) for detailed error messages.
-   **File Permission Issues**: Ensure scripts are executable (`chmod +x scripts/*.sh`). Docker volume mounts might sometimes cause permission conflicts depending on the OS; the Dockerfiles attempt to use non-root users to mitigate this.

See `docs/troubleshooting.md` for more detailed solutions.

## Contributing

We welcome contributions! Please follow these steps:
1.  Fork the repository.
2.  Create a new feature branch (`git checkout -b feature/your-amazing-feature`).
3.  Make your changes and commit them (`git commit -m 'Add some amazing feature'`).
4.  Push to your branch (`git push origin feature/your-amazing-feature`).
5.  Open a Pull Request for review.

Please ensure your code adheres to existing style and includes tests where appropriate.

## License

This project is licensed under the MIT License - see the `LICENSE` file for details (assuming MIT, a `LICENSE` file should be added).

## Acknowledgments

-   The [Audiocraft](https://github.com/facebookresearch/audiocraft) team at Meta AI for the foundational music generation models.
-   The [n8n.io](https://n8n.io/) team for their powerful workflow automation tool.
-   The [LMMS](https://lmms.io/) community for a versatile open-source DAW.
-   All the open-source libraries and tools that make this project possible.

---

**AI Music Studio** - Create, Compose, Captivate.
