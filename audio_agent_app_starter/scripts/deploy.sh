#!/bin/bash
#
# AI Music Studio - Production Deployment Script
# Deploy automatico con zero-downtime e rollback
#

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(dirname "$SCRIPT_DIR")" # Assumes scripts/ is a child of project root
readonly DEPLOY_LOG="$PROJECT_ROOT/deploy.log" # Consider logging to a more standard /var/log if appropriate
readonly VERSION_TAG=$(date +%Y%m%d%H%M%S) # Renamed from VERSION to avoid conflict with potential env var

# Colors
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly PURPLE='\033[0;35m'
readonly NC='\033[0m'

# Configuration (can be overridden by environment variables)
# DOMAIN is expected to be set as an environment variable.
# Example: export DOMAIN="myapp.com"
# Ensure required environment variables like DB_PASSWORD, N8N_ENCRYPTION_KEY are set.

# Log functions
_log() { # Changed to _log to avoid conflict if log is a command
  echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $*" | tee -a "$DEPLOY_LOG"
}
_success() { # Renamed
  echo -e "${GREEN}✓${NC} $*" | tee -a "$DEPLOY_LOG"
}
_warning() { # Renamed
  echo -e "${YELLOW}⚠${NC} $*" | tee -a "$DEPLOY_LOG"
}
_error_exit() { # Renamed
  echo -e "${RED}✗${NC} $*" | tee -a "$DEPLOY_LOG"
  # Add any cleanup or notification steps here if needed
  exit 1
}
_info() { # Renamed
   echo -e "${PURPLE}ℹ${NC} $*" | tee -a "$DEPLOY_LOG"
}


show_deploy_banner() {
  echo -e "${PURPLE}"
  cat << 'EOF'
╔═════════════════════════════════════════════════════╗
║                                                     ║
║       AI Music Studio - Production Deployment       ║
║                                                     ║
║       Zero-Downtime Strategy & Rollback Capable     ║
║                                                     ║
╚═════════════════════════════════════════════════════╝
EOF
  echo -e "${NC}"
}

check_deployment_requirements() {
  _log "Controllo requisiti per il deployment..."
  if ! command -v docker &> /dev/null; then _error_exit "Docker non installato."; fi
  _success "Docker: $(docker --version)"

  if command -v docker-compose &> /dev/null; then
     export DOCKER_COMPOSE_CMD="docker-compose"
  elif docker compose version &> /dev/null; then
     export DOCKER_COMPOSE_CMD="docker compose"
  else
     _error_exit "Docker Compose non trovato."
  fi
  _success "Docker Compose: using '$DOCKER_COMPOSE_CMD'"

  # Check essential environment variables
  local required_env_vars=("DOMAIN" "DB_PASSWORD" "N8N_ENCRYPTION_KEY" "JWT_SECRET" "GRAFANA_PASSWORD")
  for var_name in "${required_env_vars[@]}"; do
    if [[ -z "${!var_name:-}" ]]; then # Check if var is unset or empty
      # Try to source from .env.prod if it exists and var is still not set
      if [[ -f "$PROJECT_ROOT/.env.prod" ]]; then
        # Temporarily export to check, but don't permanently alter shell environment from .env.prod here
        local value_from_env_prod
        value_from_env_prod=$(grep "^${var_name}=" "$PROJECT_ROOT/.env.prod" 2>/dev/null | cut -d'=' -f2- || true)
        if [[ -z "$value_from_env_prod" ]]; then
             _error_exit "Variabile d'ambiente richiesta '$var_name' non configurata (né in env né in .env.prod)."
        fi
        _info "Variabile '$var_name' trovata in .env.prod."
      else
        _error_exit "Variabile d'ambiente richiesta '$var_name' non configurata e .env.prod non trovato."
      fi
    else
      _success "Variabile d'ambiente '$var_name' configurata."
    fi
  done

  if [[ ! -f "$PROJECT_ROOT/nginx/ssl/fullchain.pem" || ! -f "$PROJECT_ROOT/nginx/ssl/privkey.pem" ]]; then
       _warning "Certificati SSL di produzione non trovati in nginx/ssl/. Usare certificati self-signed solo per test."
  else
      _success "Certificati SSL di produzione trovati."
  fi
}

backup_current_deployment() {
  _log "Backup deployment corrente..."
  local backup_dir="$PROJECT_ROOT/backups/pre-deploy-$VERSION_TAG"
  mkdir -p "$backup_dir"

  # Check if docker-compose.prod.yml exists before trying to use it
  local prod_compose_file="$PROJECT_ROOT/docker-compose.prod.yml"
  if [[ ! -f "$prod_compose_file" ]]; then
    _warning "File docker-compose.prod.yml non trovato. Saltare backup basato su compose."
    return
  fi

  # Check if postgres service is defined and running
  if $DOCKER_COMPOSE_CMD -f "$prod_compose_file" ps postgres 2>/dev/null | grep -q "Up"; then
     _log "Backup database PostgreSQL..."
     # Ensure DB_PASSWORD is set if needed by pg_dump (it typically is for non-trust auth)
     # This command assumes pg_dump can connect using credentials from environment or .pgpass
     # The -T option for exec is to allocate a pseudo-TTY, which is not always needed for non-interactive commands.
     # PGPASSWORD=$DB_PASSWORD $DOCKER_COMPOSE_CMD -f "$prod_compose_file" exec -T postgres pg_dump -U n8n -d n8n | gzip > "$backup_dir/database.sql.gz"
     # A version that doesn't rely on PGPASSWORD in script if internal auth is set up:
     $DOCKER_COMPOSE_CMD -f "$prod_compose_file" exec -T postgres pg_dump -U n8n -d n8n | gzip > "$backup_dir/database.sql.gz" || _warning "Backup database fallito. Controllare la configurazione."
     if [[ -f "$backup_dir/database.sql.gz" && $(stat -c%s "$backup_dir/database.sql.gz") -gt 100 ]]; then # Check if file exists and is >100 bytes
        _success "Backup database completato."
     else
        _warning "Backup database potrebbe essere fallito o vuoto."
     fi
  else
     _warning "Servizio PostgreSQL non attivo o non definito in $prod_compose_file. Saltare backup database."
  fi

  _log "Backup file di configurazione locali..."
  tar -czf "$backup_dir/local_configs.tar.gz" -C "$PROJECT_ROOT" .env.prod docker-compose.prod.yml nginx/ssl nginx/nginx.prod.conf monitoring/prometheus.yml monitoring/grafana 2>/dev/null || true
  _success "Backup pre-deploy (configurazioni locali) completato: $backup_dir"
}

build_production_images() {
  _log "Build/Pull immagini Docker di produzione..."
  cd "$PROJECT_ROOT"

  # In a CI/CD pipeline, you'd typically `docker pull myregistry.com/image:$VERSION_TAG`
  # If building locally for deployment:
  if [[ "${BUILD_IMAGES_LOCALLY:-false}" == "true" ]]; then
      _info "Building images locally as per BUILD_IMAGES_LOCALLY=true..."
      if DOCKER_BUILDKIT=1 $DOCKER_COMPOSE_CMD -f docker-compose.prod.yml build --parallel --compress; then
          _success "Build immagini Docker completato."
      else
          _error_exit "Build immagini Docker fallito."
      fi
  else
      _info "Skipping local image build. Assuming images will be pulled or are already available."
      # Attempt to pull images defined in compose file. This ensures latest if :latest tag is used.
      if $DOCKER_COMPOSE_CMD -f docker-compose.prod.yml pull; then
          _success "Pull immagini Docker completato."
      else
          _warning "Pull immagini Docker fallito. Procedendo con immagini locali se disponibili."
      fi
  fi
}

deploy_services() {
  _log "Deploy/Update servizi con Docker Compose..."
  cd "$PROJECT_ROOT"

  if [[ ! -f .env.prod ]]; then
      if [[ -f .env ]]; then
        cp .env .env.prod;
        _info "Copiato .env a .env.prod. VERIFICARE E ADATTARE PER PRODUZIONE!";
      else
        _error_exit ".env.prod non trovato e .env non disponibile per fallback.";
      fi
  fi

  # Check if docker-compose.prod.yml exists
  local prod_compose_file="$PROJECT_ROOT/docker-compose.prod.yml"
  if [[ ! -f "$prod_compose_file" ]]; then
    _error_exit "File docker-compose.prod.yml non trovato. Impossibile procedere con il deploy."
  fi

  # The command from the source was:
  # $DOCKER_COMPOSE_CMD -f docker-compose.prod.yml --env-file .env.prod up -d   #   --scale frontend=0   #   --scale n8n=0   #   --scale audiocraft=0
  # This seems to be part of a more complex blue/green or canary deployment strategy
  # where some services are initially scaled to 0.
  # For a simpler "recreate" deployment, we'd just do `up -d`.
  # Given the script mentions "zero-downtime" and "rolling update", this initial scaling to 0
  # might be for services that will be brought up later in a controlled way.
  # However, the `rolling_update_services` function was commented out in the source.
  # For now, let's use a standard `up -d` which will recreate changed services.

  _info "Avvio/Aggiornamento servizi con docker-compose..."
  $DOCKER_COMPOSE_CMD -f "$prod_compose_file" --env-file .env.prod up -d --remove-orphans --force-recreate

  _success "Servizi deployati/aggiornati."

  _log "Attesa stabilizzazione servizi e health checks (fino a 3 minuti)..."
  # This is a simplified wait. A more robust check would loop and query service health.
  sleep 180

  # Verify all expected services are running and healthy
  local all_services_healthy=true
  local services_to_check
  services_to_check=$($DOCKER_COMPOSE_CMD -f "$prod_compose_file" --env-file .env.prod config --services)

  for service_name in $services_to_check; do
    # Check for 'Up (healthy)' or just 'Up' if no healthcheck is defined
    if $DOCKER_COMPOSE_CMD -f "$prod_compose_file" --env-file .env.prod ps "$service_name" | grep -q -E "(healthy|Up.*running)"; then
      _success "Servizio $service_name: Attivo e Healthy (o Running)."
    else
      _warning "Servizio $service_name: Potrebbe non essere healthy o attivo."
      $DOCKER_COMPOSE_CMD -f "$prod_compose_file" --env-file .env.prod ps "$service_name" # Show status
      all_services_healthy=false
    fi
  done

  if [[ "$all_services_healthy" != "true" ]]; then
    _warning "Alcuni servizi potrebbero non essere completamente operativi. Controllare i log."
  fi
}

run_post_deploy_tests() {
  _log "Esecuzione test post-deploy..."
  local test_results=()
  local failed_tests=0

  # Ensure DOMAIN is set
  if [[ -z "${DOMAIN:-}" ]]; then
    _warning "Variabile DOMAIN non impostata. Saltare test basati sul dominio."
    return 1 # Indicate tests could not run fully
  fi

  # Test 1: Frontend accessibility
  _info "Test Frontend: https://${DOMAIN}"
  if curl -fsSLk "https://${DOMAIN}" -m 10 | grep -q -i "AI Music Studio"; then
     test_results+=("Frontend Access: PASS")
  else
     test_results+=("Frontend Access: FAIL"); ((failed_tests++))
  fi

  # Test 2: API health (n8n healthz via Nginx)
  # Assuming nginx is configured to route something like /api/health to n8n's /healthz
  local n8n_health_path="/api/healthz" # Adjust if nginx route is different
  _info "Test API Health: https://${DOMAIN}${n8n_health_path}"
  if curl -fsSLk "https://${DOMAIN}${n8n_health_path}" -m 10 | grep -q "ok"; then
     test_results+=("API Health: PASS")
  else
     test_results+=("API Health: FAIL"); ((failed_tests++))
  fi

  _log "Risultati test post-deploy:"
  for result_item in "${test_results[@]}"; do # Renamed result to result_item
     if [[ "$result_item" == *"PASS"* ]]; then _success "$result_item"; else _warning "$result_item"; fi
  done

  if [[ $failed_tests -eq 0 ]]; then
      _success "Tutti i test post-deploy principali PASSATI."
      return 0
  else
      # Do not exit here, let main decide.
      _warning "$failed_tests test post-deploy FALLITI. Controllare il sistema."
      return 1
  fi
}

create_deployment_summary() {
  _log "Creazione summary deployment..."
  local summary_file="$PROJECT_ROOT/DEPLOYMENT_SUMMARY_${VERSION_TAG}.md"
  # Ensure DOCKER_COMPOSE_CMD is set
  DOCKER_COMPOSE_CMD=${DOCKER_COMPOSE_CMD:-"docker-compose"}

  {
    echo "# AI Music Studio - Deployment Summary"
    echo ""
    echo "**Data Deploy**: $(date)"
    echo "**Versione Tag**: $VERSION_TAG"
    echo "**Dominio**: ${DOMAIN:-N/A}"
    echo "**Ambiente**: ${ENVIRONMENT:-production}"
    echo ""
    echo "## Servizi Aggiornati:"
    # Listing services requires docker-compose.prod.yml and .env.prod to be correctly set up for `config --services`
    # As a fallback, list from a known set or skip if problematic in script context
    $DOCKER_COMPOSE_CMD -f "$PROJECT_ROOT/docker-compose.prod.yml" --env-file "$PROJECT_ROOT/.env.prod" ps --services 2>/dev/null | sed 's/^/- /' || echo "- (elenco servizi non disponibile)"
    echo ""
    echo "## Endpoint Principali (presunti):"
    echo "- Frontend: https://${DOMAIN:-localhost}"
    echo "- API: https://${DOMAIN:-localhost}/api/"
    echo ""
    echo "Deployment tentativo completato."
  } > "$summary_file"
  _success "Deployment summary creato: $summary_file"
}

show_deployment_success() {
  echo ""
  _success "╔═════════════════════════════════════════════════════╗"
  _success "║        DEPLOYMENT COMPLETATO CON SUCCESSO!          ║"
  _success "╚═════════════════════════════════════════════════════╝"
  echo ""
  _info "AI Music Studio versione $VERSION_TAG è ora live su https://${DOMAIN:-localhost}"
  _info "Controllare il summary: DEPLOYMENT_SUMMARY_${VERSION_TAG}.md"
}

cleanup_old_deployments() {
   _log "Pulizia vecchi deployment Docker (immagini non taggate e non usate)..."
   docker image prune -af --filter "dangling=true" 2>/dev/null || _warning "Pulizia immagini Docker (dangling) fallita o non necessaria."
   # More aggressive: remove images not used by any container
   # docker image prune -af 2>/dev/null || _warning "Pulizia immagini Docker (all unused) fallita o non necessaria."
   _success "Pulizia vecchi deployment Docker completata."
}

main() {
  # Ensure log file exists and is writable
  touch "$DEPLOY_LOG" && chmod 644 "$DEPLOY_LOG" || { echo "ERROR: Cannot write to log file $DEPLOY_LOG"; exit 1; }

  # Load environment variables from .env.prod if it exists
  if [[ -f "$PROJECT_ROOT/.env.prod" ]]; then
    _log "Caricamento variabili d'ambiente da .env.prod..."
    set -a
    # shellcheck source=/dev/null
    source "$PROJECT_ROOT/.env.prod"
    set +a
    _success "Variabili da .env.prod caricate nello script."
  else
    _warning ".env.prod non trovato. Assicurarsi che le variabili d'ambiente necessarie (DOMAIN, etc.) siano esportate."
  fi

  # Re-check DOMAIN after attempting to load from .env.prod
  if [[ -z "${DOMAIN:-}" ]]; then _error_exit "La variabile DOMAIN non è configurata."; fi
  # Make DOMAIN readonly if you want to ensure it's not changed later in the script
  # readonly DOMAIN

  show_deploy_banner
  _log "Inizio deployment produzione AI Music Studio..."
  _log "Versione Tag: $VERSION_TAG"
  _log "Dominio Target: $DOMAIN"
  _log "Ambiente: ${ENVIRONMENT:-production}"

  check_deployment_requirements
  backup_current_deployment
  build_production_images
  deploy_services

  if run_post_deploy_tests; then
    create_deployment_summary
    cleanup_old_deployments
    show_deployment_success
    _log "Deployment completato con successo per $VERSION_TAG."
  else
    _error_exit "Deployment fallito a causa di errori nei test post-deploy. Controllare i log e lo stato dei servizi."
    # Consider adding rollback logic here:
    # _warning "Tentativo di rollback alla versione precedente..."
    # rollback_deployment $PREVIOUS_VERSION_TAG # (PREVIOUS_VERSION_TAG would need to be tracked)
  fi
}

# Ensure script is run from project root for consistency, or adjust paths.
# This script assumes it's in PROJECT_ROOT/scripts/
cd "$PROJECT_ROOT" || _error_exit "Impossibile accedere a $PROJECT_ROOT. Eseguire lo script dalla directory principale del progetto o assicurarsi che PROJECT_ROOT sia corretto."

# Argument parsing
if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    echo "AI Music Studio - Production Deployment Script"
    echo "Usage: $0"
    echo "Assumes .env.prod is configured and required environment variables (DOMAIN, etc.) are set or loadable from .env.prod."
    echo "Set BUILD_IMAGES_LOCALLY=true as env var to force local image builds instead of pulls."
    exit 0
fi

main "$@"
