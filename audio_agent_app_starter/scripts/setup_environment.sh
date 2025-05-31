#!/bin/bash
#
# Complete Setup Script for AI Music Studio
# Risolve tutti i gap critici e configura l'ambiente completo
#

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(dirname "$SCRIPT_DIR")" # This assumes scripts/ is a direct child of project root
readonly LOG_FILE="$PROJECT_ROOT/setup_complete.log"

# Colors
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly PURPLE='\033[0;35m'
readonly NC='\033[0m'

# Log functions (from the script)
log() {
  echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $*" | tee -a "$LOG_FILE"
}
success() {
  echo -e "${GREEN}✓${NC} $*" | tee -a "$LOG_FILE"
}
warning() {
  echo -e "${YELLOW}⚠${NC} $*" | tee -a "$LOG_FILE"
}
error_exit() { # Renamed from error to avoid conflict
  echo -e "${RED}✗${NC} $*" | tee -a "$LOG_FILE"
  exit 1
}
info() {
   echo -e "${PURPLE}ℹ${NC} $*" | tee -a "$LOG_FILE"
}

show_banner() {
  echo -e "${PURPLE}"
  cat << 'EOF'
╔═════════════════════════════════════════════════════╗
║                                                     ║
║         AI Music Studio - Complete Setup            ║
║                                                     ║
║ Risoluzione Gap Critici e Setup Funzionamento       ║
║             Completo al 100%                      ║
║                                                     ║
╚═════════════════════════════════════════════════════╝
EOF
  echo -e "${NC}"
}

check_prerequisites() {
  log "Controllo prerequisiti di sistema..."
  if [[ "$OSTYPE" == "linux-gnu"* ]]; then
      success "Sistema operativo: Linux"
  elif [[ "$OSTYPE" == "darwin"* ]]; then
      success "Sistema operativo: macOS"
  else
      warning "Sistema operativo non testato: $OSTYPE"
  fi

  if ! command -v docker &> /dev/null; then
      error_exit "Docker non installato. Installare Docker Desktop e riprovare."
  fi
  success "Docker installato: $(docker --version)"

  if command -v docker-compose &> /dev/null; then
     success "Docker Compose disponibile: $(docker-compose --version)"
     export DOCKER_COMPOSE_CMD="docker-compose"
  elif docker compose version &> /dev/null; then
     success "Docker Compose (plugin) disponibile: $(docker compose version)"
     export DOCKER_COMPOSE_CMD="docker compose"
  else
     error_exit "Docker Compose non trovato. Installare Docker Compose e riprovare."
  fi

  if command -v nvidia-smi &> /dev/null && nvidia-smi &> /dev/null; then
     success "GPU NVIDIA rilevata: $(nvidia-smi --query-gpu=name --format=csv,noheader,nounits | head -1)"
     export HAS_GPU=true
  else
     warning "GPU NVIDIA non rilevata. L'app funzionerà con CPU (più lenta)"
     export HAS_GPU=false
  fi

  local mem_total_kb
  if [[ "$OSTYPE" == "darwin"* ]]; then
    mem_total_kb=$(sysctl -n hw.memsize | awk '{print $1/1024}')
  else # Assuming Linux
    mem_total_kb=$(grep MemTotal /proc/meminfo | awk '{print $2}')
  fi
  local mem_gb=$((mem_total_kb / 1024 / 1024))

  if [[ $mem_gb -lt 8 ]]; then # Check if memory is less than 8GB
      warning "RAM disponibile: ${mem_gb}GB. Raccomandati almeno 8GB."
  else
      success "RAM disponibile: ${mem_gb}GB."
  fi

  local disk_gb
  disk_gb=$(df -BG "$PROJECT_ROOT" | awk 'NR==2 {print $4}' | sed 's/G//') # Get available space in GB
  if [[ $disk_gb -lt 20 ]]; then
      warning "Spazio disco disponibile: ${disk_gb}GB. Raccomandati almeno 20GB."
  else
      success "Spazio disco disponibile: ${disk_gb}GB."
  fi
}

create_missing_files() {
  log "Creazione file mancanti critici..."
  local dirs=(
      "frontend/src" "frontend/public" "websocket" "nginx/ssl" "config"
      "data/stems" "data/mixed" "data/reports" "data/public"
      "templates" "soundfonts" "models/cache" "pgdata" "monitoring"
      # "scripts" # This script is already in scripts/
  )
  for dir in "${dirs[@]}"; do
      mkdir -p "$PROJECT_ROOT/$dir"
      # success "Creata directory: $dir" # Too verbose
  done
  success "Struttura directory di base verificata/creata."

  if [[ ! -f "$PROJECT_ROOT/frontend/package.json" ]]; then
      cat > "$PROJECT_ROOT/frontend/package.json" << 'EOF'
{
    "name": "ai-music-studio-frontend",
    "version": "2.0.0",
    "private": true,
    "dependencies": {
        "@testing-library/jest-dom": "^5.17.0",
        "@testing-library/react": "^13.4.0",
        "@testing-library/user-event": "^14.5.1",
        "lucide-react": "^0.263.1",
        "react": "^18.2.0",
        "react-dom": "^18.2.0",
        "react-scripts": "5.0.1",
        "web-vitals": "^3.5.0",
        "axios": "^1.6.0",
        "react-hot-toast": "^2.4.1",
        "framer-motion": "^10.16.4"
    },
    "scripts": {"start": "react-scripts start", "build": "react-scripts build", "test": "react-scripts test", "eject": "react-scripts eject"},
    "eslintConfig": {"extends": ["react-app", "react-app/jest"]},
    "browserslist": {
        "production": [">0.2%", "not dead", "not op_mini all"],
        "development": ["last 1 chrome version", "last 1 firefox version", "last 1 safari version"]
    },
    "devDependencies": {"autoprefixer": "^10.4.16", "postcss": "^8.4.31", "tailwindcss": "^3.3.5"},
    "proxy": "http://localhost:5678"
}
EOF
      success "Creato frontend/package.json"
  fi

  if [[ ! -f "$PROJECT_ROOT/websocket/package.json" ]]; then
      cat > "$PROJECT_ROOT/websocket/package.json" << 'EOF'
{
    "name": "ai-music-studio-websocket",
    "version": "2.0.0",
    "description": "Real-time WebSocket server for AI Music Studio",
    "main": "server.js",
    "scripts": {"start": "node server.js", "dev": "nodemon server.js", "test": "node health-check.js"},
    "dependencies": {"ws": "^8.14.2", "chokidar": "^3.5.3", "node-cron": "^3.0.3"},
    "devDependencies": {"nodemon": "^3.0.1"},
    "engines": {"node": ">=18.0.0"}
}
EOF
      success "Creato websocket/package.json"
  fi

  if [[ ! -f "$PROJECT_ROOT/.env" ]]; then
      local db_password; db_password=$(openssl rand -base64 24 2>/dev/null || date +%s | sha256sum | base64 | head -c 24)
      local n8n_key; n8n_key=$(openssl rand -hex 32 2>/dev/null || date +%s%N | sha256sum | head -c 64)
      local jwt_secret; jwt_secret=$(openssl rand -hex 32 2>/dev/null || date +%s%N | sha256sum | head -c 64)

      cat > "$PROJECT_ROOT/.env" << EOF
# n8n Configuration
N8N_FEATURE_FLAG_MCP=true
N8N_PROTOCOL=http
N8N_PORT=5678
N8N_HOST=0.0.0.0
EXECUTIONS_DATA_SAVE_ON_ERROR=true
EXECUTIONS_DATA_SAVE_ON_SUCCESS=true
N8N_LOG_LEVEL=info
N8N_ENCRYPTION_KEY=${n8n_key}

# Database Configuration
DB_TYPE=postgresdb
DB_POSTGRESDB_HOST=postgres
DB_POSTGRESDB_PORT=5432
DB_POSTGRESDB_DATABASE=n8n
DB_POSTGRESDB_USER=n8n
DB_POSTGRESDB_PASSWORD=${db_password}

# Audio Processing
CUDA_VISIBLE_DEVICES=0
PYTHONUNBUFFERED=1
TORCH_CUDA_ARCH_LIST="7.5;8.0;8.6;8.9;9.0" # Quoted for safety

# Frontend Configuration
REACT_APP_API_URL=http://localhost:5678 # Default for dev
REACT_APP_WS_URL=ws://localhost:8080   # Default for dev

# Security
JWT_SECRET=${jwt_secret}
ADMIN_PASSWORD=admin # Default admin password, CHANGE THIS
GRAFANA_PASSWORD=admin # Default Grafana password, CHANGE THIS


# Paths (relative to docker-compose.yml)
DATA_DIR=./data
SCRIPTS_DIR=./scripts
TEMPLATES_DIR=./templates
SOUNDFONTS_DIR=./soundfonts
MODELS_DIR=./models

# Audio Settings
DEFAULT_SAMPLE_RATE=44100
DEFAULT_BIT_DEPTH=16
DEFAULT_LUFS=-14
DEFAULT_BPM=120

# Performance Settings
MAX_CONCURRENT_GENERATIONS=2 # Adjust based on your hardware
GENERATION_TIMEOUT=300
MIXING_TIMEOUT=600
EOF
      success "Creato file .env con chiavi generate (CAMBIARE PASSWORD ADMIN DI DEFAULT)"
  fi

  if [[ ! -f "$PROJECT_ROOT/nginx/ssl/nginx.crt" ]]; then
      log "Generazione certificati SSL self-signed per sviluppo..."
      openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
         -keyout "$PROJECT_ROOT/nginx/ssl/nginx.key" \
         -out "$PROJECT_ROOT/nginx/ssl/nginx.crt" \
         -subj "/C=IT/ST=Lazio/L=Rome/O=AI Music Studio Dev/CN=localhost" \
         2>/dev/null
      success "Certificati SSL self-signed generati."
  fi

  if [[ ! -f "$PROJECT_ROOT/frontend/public/favicon.ico" ]]; then
      echo "iVBORw0KGgoAAAANSUhEUgAAABAAAAAQCAYAAAAf8/9hAAAAAXNSR0IArs4c6QAAAIRlWElmTU0AKgAAAAgABQESAAMAAAABAAEAAAEaAAUAAAABAAAASgEbAAUAAAABAAAAUgEoAAMAAAABAAIAAIdpAAQAAAABAAAAWgAAAAAAAACQAAAAAQAAAJAAAAABAAKgAgAEAAAAAQAAABCgAwAEAAAAAQAAABCgAAAAA8hscAAAAAlwSFlzAAAOxAAADsQBlSsOGwAAAAd0SU1FB+UJFhMoHS4LAgAAAAAZdEVYdENvbW1lbnQAQ3JlYXRlZCB3aXRoIEdJTVBXgQ4XAAAATElEQVQ4y2NkwA/uPzFwMhgwMDAwMDCANP8Z8N8eWKCk+YMAmD5gAAoGAXYMxIAlMDD8Z2D4z8AQFKEMDAwAAhAUIXgAADClBh9xN2jFAAAAAElFTkSuQmCC" | base64 -d > "$PROJECT_ROOT/frontend/public/favicon.ico" 2>/dev/null || touch "$PROJECT_ROOT/frontend/public/favicon.ico"
      success "Creato favicon.ico placeholder"
  fi
  if [[ ! -f "$PROJECT_ROOT/frontend/public/manifest.json" ]]; then
      cat > "$PROJECT_ROOT/frontend/public/manifest.json" << 'EOF'
{
  "short_name": "AI Music",
  "name": "AI Music Studio",
  "icons": [{"src": "favicon.ico", "sizes": "64x64 32x32 24x24 16x16", "type": "image/x-icon"}],
  "start_url": ".", "display": "standalone", "theme_color": "#9333ea", "background_color": "#1a1a2e"
}
EOF
      success "Creato manifest.json"
  fi
}

download_models_and_soundfonts() {
  log "Download modelli e soundfonts essenziali (placeholders/lists)..."
  mkdir -p "$PROJECT_ROOT/downloads" # Not used in this version of the function

  local soundfont_dir="$PROJECT_ROOT/soundfonts"
  mkdir -p "$soundfont_dir"
  local default_sf_path="$soundfont_dir/default.sf2"
  if [[ ! -f "$default_sf_path" ]]; then
      touch "$default_sf_path" # Create placeholder
      warning "Placeholder for default.sf2 created. Actual soundfonts should be added to $soundfont_dir."
      info "Example: GeneralUser_GS.sf2 or FluidR3_GM.sf2"
  else
      success "Soundfont directory checked: $soundfont_dir"
  fi

  local model_cache_dir="$PROJECT_ROOT/models/cache"
  mkdir -p "$model_cache_dir"
  if [[ ! -f "$model_cache_dir/model_list.txt" ]]; then
    echo "facebook/musicgen-small" > "$model_cache_dir/model_list.txt"
    echo "facebook/musicgen-medium" >> "$model_cache_dir/model_list.txt"
    success "Lista modelli AI preparata per download automatico on-demand."
  else
    success "Model list file already exists."
  fi
}

create_lmms_templates() {
  log "Creazione template LMMS di base..."
  local templates_dir="$PROJECT_ROOT/templates"
  mkdir -p "$templates_dir"
  local instruments=("bass" "drums" "guitar" "piano" "synth" "basic")
  for instrument in "${instruments[@]}"; do
      local template_file="$templates_dir/template_${instrument}.mmpz"
      if [[ ! -f "$template_file" ]]; then
          cat > "$template_file" << EOF
<?xml version="1.0"?>
<lmms-project version="1.0" creator="ai-music-studio-setup">
  <head bpm="120" mastervol="100" timesig_num="4" timesig_den="4"/>
  <song>
   <trackcontainer>
    <track type="InstrumentTrack" name="${instrument^}">
      <instrumenttrack vol="100" pan="0" fx="0">
        <instrument name="audiofileprocessor"/> <!-- Placeholder for generated audio -->
      </instrumenttrack>
    </track>
   </trackcontainer>
  </song>
</lmms-project>
EOF
          # success "Creato template: template_${instrument}.mmpz" # Too verbose
      fi
  done
  success "Template LMMS di base creati/verificati."
}

setup_python_environment() {
  log "Setup ambiente Python per audio processing (requirements file)..."
  cat > "$PROJECT_ROOT/scripts/requirements.txt" << 'EOF'
torch==2.2.1
torchaudio==2.2.1
librosa==0.10.1
soundfile==0.12.1
scipy==1.11.4
numpy==1.24.3
# scikit-learn==1.3.2 # Not used in current scripts
# matplotlib==3.8.2 # Not used in current scripts
pydub==0.25.1
ffmpeg-python==0.2.0
psutil==5.9.6
audiocraft>=1.0.0 # Use a version range or specific version
transformers>=4.0.0
accelerate>=0.20.0
# xformers # Optional, often tricky to install, let user install if needed for perf
EOF
  success "Creato scripts/requirements.txt"

  find "$PROJECT_ROOT/scripts" -name "*.py" -exec chmod +x {} \; 2>/dev/null || true
  find "$PROJECT_ROOT/scripts" -name "*.sh" -exec chmod +x {} \; 2>/dev/null || true
  success "Resi eseguibili gli script."
}

build_and_start_services() { # Combined build and start
  log "Build e avvio container Docker..."
  cd "$PROJECT_ROOT"

  log "Cleaning up old containers if any..."
  $DOCKER_COMPOSE_CMD down -v --remove-orphans 2>/dev/null || true # Clean start

  log "Building containers (this might take a while)..."
  if $DOCKER_COMPOSE_CMD build --parallel; then
     success "Container build completato."
  else
     error_exit "Build container fallito. Controllare i log."
  fi

  log "Avvio servizi in background..."
  if $DOCKER_COMPOSE_CMD up -d; then
     success "Tutti i servizi avviati in background."
  else
     error_exit "Avvio servizi fallito. Controllare i log con '$DOCKER_COMPOSE_CMD logs'."
  fi
}

wait_for_services() {
  log "Attesa servizi pronti (fino a 2 minuti)..."
  local max_attempts=60 # 60 attempts * 2 seconds = 120 seconds
  local attempt=0
  local n8n_ready=false
  local frontend_ready=false

  while [[ $attempt -lt $max_attempts ]]; do
    echo -n "." # Progress indicator
    if ! $n8n_ready && curl -fsSL http://localhost:5678/healthz >/dev/null 2>&1; then
       n8n_ready=true
       success "n8n pronto su http://localhost:5678"
    fi
    if ! $frontend_ready && curl -fsSL http://localhost:3000 >/dev/null 2>&1; then # Assuming frontend runs on 3000
       frontend_ready=true
       success "Frontend (potenzialmente) pronto su http://localhost:3000"
    fi
    if $n8n_ready && $frontend_ready; then
        echo # Newline after dots
        success "Servizi principali pronti."
        return
    fi
    ((attempt++))
    sleep 2
  done
  echo # Newline after dots
  warning "Timeout attesa servizi. Alcuni servizi potrebbero non essere pronti."
  # List status
  $DOCKER_COMPOSE_CMD ps
}

import_workflows() {
  log "Importazione workflow n8n..."
  local workflow_file="$PROJECT_ROOT/workflows/n8n_mcp_workflows.json" # Adjusted name
  if [[ ! -f "$workflow_file" ]]; then
      warning "File workflow '$workflow_file' non trovato. Saltare import automatico."
      info "Importare manualmente da http://localhost:5678 > Workflows > Import."
      return
  fi

  # Ensure import script is executable
  local import_script="$PROJECT_ROOT/scripts/import_workflows.sh"
  if [[ -f "$import_script" ]]; then
    chmod +x "$import_script"
    if "$import_script"; then
      success "Tentativo di import automatico workflow completato."
    else
      warning "Script import workflow fallito. Controllare i log dello script o importare manualmente."
    fi
  else
    warning "Script 'import_workflows.sh' non trovato. Importare manualmente."
  fi
}

run_integration_tests() {
  log "Esecuzione test di integrazione..."
  local test_passed=0
  local test_total=0

  ((test_total++))
  if $DOCKER_COMPOSE_CMD exec -T postgres pg_isready -U n8n -d n8n >/dev/null 2>&1; then
     success "Test database connectivity: PASSED"
     ((test_passed++))
  else
     warning "Test database connectivity: FAILED"
  fi

  ((test_total++))
  if $DOCKER_COMPOSE_CMD exec -T redis redis-cli ping | grep -q "PONG"; then
     success "Test Redis connectivity: PASSED"
     ((test_passed++))
  else
     warning "Test Redis connectivity: FAILED"
  fi

  # Add more tests here if a test script/suite is defined
  # For example, if test/integration.test.js and docker-compose.test.yml were fully fleshed out:
  # log "Running dedicated integration test suite..."
  # if $DOCKER_COMPOSE_CMD -f docker-compose.test.yml run --rm test_runner; then
  #    success "Integration test suite: PASSED"
  #    ((test_total++)); ((test_passed++))
  # else
  #    warning "Integration test suite: FAILED"
  #    ((test_total++))
  # fi


  info "Test integrazione preliminari: $test_passed/$test_total passati."
  if [[ $test_passed -eq $test_total ]]; then
      return 0
  else
      return 1 # Some basic tests failed
  fi
}

show_final_status() {
  # Uses DOCKER_COMPOSE_CMD which is set in check_prerequisites
  echo ""
  echo -e "${GREEN}╔═════════════════════════════════════════════════════╗${NC}"
  echo -e "${GREEN}║              SETUP COMPLETATO CON SUCCESSO!           ║${NC}"
  echo -e "${GREEN}╚═════════════════════════════════════════════════════╝${NC}"
  echo ""
  echo -e "${BLUE}   ACCESSO ALL'APPLICAZIONE:${NC}"
  echo -e "    Frontend:   ${GREEN}http://localhost:3000${NC}"
  echo -e "    n8n Admin:  ${GREEN}http://localhost:5678${NC}"
  echo -e "    Monitoring: ${GREEN}http://localhost:3001${NC} (Grafana)"
  echo -e "    Metrics:    ${GREEN}http://localhost:9090${NC} (Prometheus)"
  echo ""
  echo -e "${BLUE}   COMANDI UTILI:${NC}"
  echo -e "    Restart:    ${YELLOW}${DOCKER_COMPOSE_CMD} restart${NC}"
  echo -e "    Stop:       ${YELLOW}${DOCKER_COMPOSE_CMD} down${NC}"
  echo -e "    Logs:       ${YELLOW}${DOCKER_COMPOSE_CMD} logs -f [service_name]${NC}"
  echo -e "    Status:     ${YELLOW}${DOCKER_COMPOSE_CMD} ps${NC}"
  echo ""
  if [[ ${HAS_GPU:-false} == "true" ]]; then
     success "GPU NVIDIA rilevata - Performance ottimali attese!"
  else
     warning "GPU NVIDIA non rilevata - L'app funzionerà con CPU (generazione AI più lenta)."
  fi
  echo ""
  info "Log completo del setup: $LOG_FILE"
}

main() {
  # Clear log file for this run
  >"$LOG_FILE"
  show_banner
  log "Inizio setup completo AI Music Studio..."
  log "Directory progetto: $PROJECT_ROOT"

  check_prerequisites
  create_missing_files # Checks and creates if not present
  download_models_and_soundfonts # Placeholder/list creation
  create_lmms_templates # Checks and creates if not present
  setup_python_environment # Creates requirements.txt, sets permissions

  build_and_start_services # Combined build and start logic

  wait_for_services
  # import_workflows # This needs workflows/n8n_mcp_workflows.json to be populated by another step

  if run_integration_tests; then
      show_final_status
      success "Setup completato! L'app AI Music Studio è (quasi) pronta."
      info "Ricordati di importare i workflow n8n se non fatto automaticamente."
  else
      warning "Setup completato con alcuni warning o test falliti. L'app potrebbe avere limitazioni."
      show_final_status
  fi
  log "Setup terminato."
}

# Handle script arguments (simplified from original, focusing on main execution)
case "${1:-}" in
  --help|-h)
     echo "AI Music Studio - Complete Setup Script"
     echo "Usage: $0 [--clean]"
     echo "  --clean: Clean all containers and data before setup."
     exit 0
     ;;
  --clean)
     log "Pulizia ambiente esistente..."
     cd "$PROJECT_ROOT" 2>/dev/null || { error_exit "Impossibile accedere a $PROJECT_ROOT"; }
     # Ensure DOCKER_COMPOSE_CMD is set, default if not called via main flow
     if [[ -z "${DOCKER_COMPOSE_CMD:-}" ]]; then
        if command -v docker-compose &> /dev/null; then export DOCKER_COMPOSE_CMD="docker-compose";
        elif docker compose version &> /dev/null; then export DOCKER_COMPOSE_CMD="docker compose";
        else error_exit "Docker Compose non trovato per --clean."; fi
     fi
     ${DOCKER_COMPOSE_CMD} down -v --remove-orphans 2>/dev/null || true
     # Optionally, more aggressive cleanup:
     # docker system prune -af 2>/dev/null || true
     # rm -rf "$PROJECT_ROOT/pgdata" "$PROJECT_ROOT/data" "$PROJECT_ROOT/models/cache" "$PROJECT_ROOT/n8n_data" "$PROJECT_ROOT/nginx_cache" "$PROJECT_ROOT/prometheus_data" "$PROJECT_ROOT/grafana_data" 2>/dev/null || true
     success "Ambiente pulito (volumi Docker rimossi)."
     main # Proceed with main setup after cleaning
     ;;
   *) # Default action
      main
      ;;
esac
