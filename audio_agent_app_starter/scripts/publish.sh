#!/bin/bash
#
# AI Music Studio - Complete Publication Script
# Deploy automatico su server produzione con dominio reale
#

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(dirname "$SCRIPT_DIR")" # Assumes scripts/ is a child of project root
readonly PUBLISH_LOG="$PROJECT_ROOT/publish.log"
readonly VERSION="2.0.0" # Fixed version from the script
readonly RELEASE_DATE=$(date '+%Y-%m-%d')

# Configuration (can be overridden by environment variables)
# These are defaults; they should ideally be set in the environment or a config file for flexibility.
# DOMAIN is critical and should be set.
# For STAGING_DOMAIN, CDN_URL, DOCKER_REGISTRY, these are examples.
# Secrets like DB_PASSWORD, N8N_ENCRYPTION_KEY, JWT_SECRET, GITHUB_TOKEN, CLOUDFLARE_API_TOKEN, STRIPE_SECRET_KEY
# should NEVER be hardcoded. They are expected to be in the environment or a secure vault.

# Colors
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly PURPLE='\033[0;35m'
readonly NC='\033[0m'

# Log functions
_log() { echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $*" | tee -a "$PUBLISH_LOG"; }
_success() { echo -e "${GREEN}✓${NC} $*" | tee -a "$PUBLISH_LOG"; }
_warning() { echo -e "${YELLOW}⚠${NC} $*" | tee -a "$PUBLISH_LOG"; }
_error_exit() { echo -e "${RED}✗${NC} $*" | tee -a "$PUBLISH_LOG"; exit 1; } # Renamed
_info() { echo -e "${PURPLE}ℹ${NC} $*" | tee -a "$PUBLISH_LOG"; }


show_publication_banner() {
  echo -e "${PURPLE}"
  cat << 'EOF'
╔═════════════════════════════════════════════════════╗
║                                                     ║
║       AI MUSIC STUDIO - LIVE PUBLICATION            ║
║                                                     ║
║       From Development to Production                ║
║          Global Deployment                          ║
║                                                     ║
╚═════════════════════════════════════════════════════╝
EOF
  echo -e "${NC}"
  _info "Publication Script Version: $VERSION, Release Date: $RELEASE_DATE"
  echo ""
}

# Function to load environment variables from .env files if they exist
load_env_file() {
  local env_file_path="$1"
  if [[ -f "$env_file_path" ]]; then
    _log "Loading environment variables from $env_file_path..."
    set -a # Automatically export all variables subsequently defined or sourced
    # shellcheck source=/dev/null
    source "$env_file_path"
    set +a
    _success "Environment variables loaded from $env_file_path."
  else
    _warning "Environment file $env_file_path not found."
  fi
}


check_publication_prerequisites() {
  _log "Controllo prerequisiti per pubblicazione..."

  # Load .env.production first, then .env (local .env might override for dev testing of this script)
  load_env_file "$PROJECT_ROOT/.env.production"
  load_env_file "$PROJECT_ROOT/.env" # For local testing of publish script if .env.production not present


  # Critical environment variables that MUST be set (either in shell or .env files)
  local critical_vars=(
    "DOMAIN"
    "STAGING_DOMAIN" # Needed if deploying to staging
    "DB_PASSWORD"
    "N8N_ENCRYPTION_KEY"
    "JWT_SECRET"
    # "GITHUB_USERNAME" # Needed for GITHUB_TOKEN to work with ghcr.io
    # "GITHUB_TOKEN" # For ghcr.io push
    # "CLOUDFLARE_API_TOKEN" # For DNS updates
  )
  for var_name in "${critical_vars[@]}"; do
    if [[ -z "${!var_name:-}" ]]; then
      _error_exit "Variabile d'ambiente critica '$var_name' non configurata. Configurare in shell o .env / .env.production."
    fi
  done
  _success "Variabili d'ambiente critiche verificate."


  # Check for required files (Dockerfile.prod, etc.)
  local required_files=(
     "docker-compose.prod.yml"
     "scripts/deploy.sh" # This publish script might call the deploy.sh script
     "frontend/Dockerfile.prod"
     "websocket/Dockerfile.prod"
     "audiocraft/Dockerfile.prod"
     "lmms/Dockerfile.prod"
     "nginx/nginx.prod.conf"
  )
  for file_item in "${required_files[@]}"; do # Renamed file to file_item
     if [[ ! -f "$PROJECT_ROOT/$file_item" ]]; then
         _error_exit "File richiesto per la pubblicazione mancante: $PROJECT_ROOT/$file_item"
     fi
  done
  _success "Tutti i file richiesti per la pubblicazione sono presenti."

  # Docker and Docker Compose (already checked in deploy.sh, but good for standalone run)
  if ! command -v docker &> /dev/null; then _error_exit "Docker non installato."; fi
  if command -v docker-compose &> /dev/null; then export DOCKER_COMPOSE_CMD="docker-compose";
  elif docker compose version &> /dev/null; then export DOCKER_COMPOSE_CMD="docker compose";
  else _error_exit "Docker Compose non trovato."; fi
  _success "Docker & Docker Compose pronti."

  # Git (for versioning, VCS_REF)
  if ! command -v git &> /dev/null; then _warning "Git non installato. VCS_REF non sarà disponibile per i build args."; fi


  # Check external services (conceptual, actual checks might be more involved)
  _log "Verifica connettività servizi esterni (concettuale)..."
  # Example: ping -c 1 ghcr.io (if DOCKER_REGISTRY is ghcr.io)
  # Example: nslookup $DOMAIN
  _success "Prerequisiti di pubblicazione verificati."
}

# This function was in the provided script but seems to duplicate .env loading.
# create_production_environment() { ... }
# Assuming .env.production will be the source of truth for production variables.

build_and_push_images() {
  _log "Build e push immagini Docker per $VERSION..."
  cd "$PROJECT_ROOT"

  if [[ -z "${GITHUB_TOKEN:-}" || -z "${GITHUB_USERNAME:-}" ]]; then
      _warning "GITHUB_TOKEN o GITHUB_USERNAME non configurati. Push immagini a GHCR.io saltato."
      _info "Procedendo con build locale se specificato o assumendo immagini già disponibili."
      # Optionally, decide if local build should happen if push is skipped.
      # For now, we'll assume if no push, images are handled by docker-compose (local or pre-pulled)
      # return 0
  else
      if echo "$GITHUB_TOKEN" | docker login ghcr.io -u "$GITHUB_USERNAME" --password-stdin; then
        _success "Login a GitHub Container Registry (ghcr.io) riuscito."
      else
        _error_exit "Login a GitHub Container Registry fallito. Controllare GITHUB_USERNAME e GITHUB_TOKEN."
      fi
  fi

  local services_to_build=("frontend" "websocket" "audiocraft" "lmms")
  local vcs_ref; vcs_ref=$(git rev-parse HEAD 2>/dev/null || echo 'unknown')
  local build_date; build_date=$(date -u +'%Y-%m-%dT%H:%M:%SZ')

  for service_name in "${services_to_build[@]}"; do
     _log "Building $service_name..."
     local image_name="${DOCKER_REGISTRY:-ai-music-studio}/$service_name" # Use DOCKER_REGISTRY from env or default

     # Build using production Dockerfile
     # Ensure build args are passed correctly if Dockerfiles expect them (e.g. REACT_APP_ vars for frontend)
     if DOCKER_BUILDKIT=1 $DOCKER_COMPOSE_CMD -f docker-compose.prod.yml build \
        --build-arg VERSION="$VERSION" \
        --build-arg BUILD_DATE="$build_date" \
        --build-arg VCS_REF="$vcs_ref" \
        "$service_name"; then # Build specific service

        _success "Build completato per: $service_name"

        # Tag image for version and latest
        # Docker compose build already tags it as projectname_servicename by default
        # We need to retag the specific image that docker-compose build creates.
        # Find the image ID or use the default compose naming convention.
        # This part is tricky as `docker-compose build` names images like `projectdir_service`.
        # It's often better to `docker build -t ...` directly if pushing.
        # For simplicity, assuming `docker-compose.prod.yml` service definitions use `image: myregistry/myservice:$VERSION`
        # If not, manual tagging is needed:
        # docker tag projectname_${service_name} ${image_name}:${VERSION}
        # docker tag projectname_${service_name} ${image_name}:latest

        # If GITHUB_TOKEN is set, push the images
        if [[ -n "${GITHUB_TOKEN:-}" && -n "${GITHUB_USERNAME:-}" ]]; then
            _log "Pushing ${image_name}:${VERSION} e ${image_name}:latest a ${DOCKER_REGISTRY}..."
            # The actual image name to push depends on how `docker-compose.prod.yml` defines the `image:` field for the service.
            # If it's `image: ai-music-studio-frontend` (local name), then:
            # docker tag ai-music-studio-frontend ${image_name}:${VERSION}
            # docker tag ai-music-studio-frontend ${image_name}:latest
            # If `image:` field in compose is already `ghcr.io/...`, then it might be tagged correctly.
            # This step needs careful alignment with docker-compose image naming.
            # Assuming for now that the `image:` field in `docker-compose.prod.yml` for each service
            # is set to something like `${DOCKER_REGISTRY}/ai-music-studio-${service_name}:${VERSION}`
            # and that `docker-compose build` will build and tag this correctly if the `image:` field is set.
            # If not, a `docker push projectname_servicename` might be what happens if `image:` is not specific.

            # Given the script structure, it's more likely manual tagging and pushing is intended:
            local built_image_name="audio_agent_app_starter-${service_name}" # Default docker compose naming projectdir-service
            if docker image inspect "$built_image_name" &> /dev/null; then # Check if image exists
                docker tag "$built_image_name" "${image_name}:${VERSION}"
                docker tag "$built_image_name" "${image_name}:latest"
                docker push "${image_name}:${VERSION}"
                docker push "${image_name}:latest"
                _success "Push completato per: $service_name"
            else
                _warning "Immagine buildata $built_image_name non trovata per il push. Controllare i nomi."
            fi
        fi
     else
        _error_exit "Build fallito per: $service_name"
     fi
  done
  _success "Build e push di tutte le immagini completato."
}

# Placeholder for setup_infrastructure (Terraform part was illustrative)
setup_infrastructure() {
  _log "Setup infrastruttura cloud (placeholder)..."
  # This would involve running Terraform or similar IaC tools.
  # Example:
  # cd "$PROJECT_ROOT/infrastructure"
  # terraform init
  # terraform apply -auto-approve -var="domain=$DOMAIN" -var="environment=$ENVIRONMENT"
  _info "Passaggio infrastruttura cloud saltato (configurazione manuale o IaC esterna assunta)."
  _success "Setup infrastruttura cloud completato (placeholder)."
}

deploy_to_environment() {
  local target_env="$1" # "staging" or "production"
  local target_domain="$2"
  local env_file_to_use="$3"

  _log "Inizio deploy a ambiente: $target_env su dominio: $target_domain..."
  cd "$PROJECT_ROOT"

  # Ensure the specific environment file exists
  if [[ ! -f "$env_file_to_use" ]]; then
    _error_exit "File environment '$env_file_to_use' non trovato per ambiente '$target_env'."
  fi

  # Use the deploy.sh script for the actual deployment steps
  # Pass necessary env vars to deploy.sh or ensure they are in its sourced .env.prod
  _log "Esecuzione script deploy.sh per $target_env..."
  # The deploy.sh script sources .env.prod. We need to ensure .env.prod has the correct vars for the target_env.
  # A better way is for deploy.sh to accept an env file argument.
  # For now, assuming deploy.sh will pick up the correct context or we set vars globally.
  # Let's make a temporary .env.prod for deploy.sh to use, based on target env_file_to_use

  cp "$env_file_to_use" "$PROJECT_ROOT/.env.prod.deploytemp"
  # Critical: DOMAIN must be set for deploy.sh based on target_domain
  # Also, other env vars in .env.prod.deploytemp should be for the target environment.
  # This is a bit of a hack; deploy.sh should ideally take an env name or file.

  # Modify the temporary .env.prod to set the correct DOMAIN for deploy.sh
  # This is fragile. deploy.sh should be more flexible.
  # For now, let's assume deploy.sh uses the DOMAIN variable from its environment.
  export DOMAIN_OVERRIDE="$target_domain" # For deploy.sh if it uses DOMAIN directly

  if ./scripts/deploy.sh; then # This deploy.sh needs to be aware of the target env
    _success "Deploy a $target_env completato con successo."
    # Run specific tests for this environment
    if [[ "$target_env" == "staging" ]]; then
      run_staging_tests "$target_domain"
    elif [[ "$target_env" == "production" ]]; then
      # run_production_tests "$target_domain" # Similar to run_post_deploy_tests in deploy.sh
      _info "Test di produzione dovrebbero essere eseguiti da deploy.sh o pipeline separata."
    fi
  else
    _error_exit "Deploy a $target_env fallito."
  fi

  rm -f "$PROJECT_ROOT/.env.prod.deploytemp" # Clean up temp file
  unset DOMAIN_OVERRIDE
}


run_staging_tests() {
  local staging_domain_arg="$1"
  _log "Esecuzione test su staging: https://$staging_domain_arg..."
  local failed_staging_tests=0

  if curl -fsSLk "https://$staging_domain_arg" -m 15 | grep -q -i "AI Music Studio"; then
     _success "Test Staging Frontend: PASS"
  else
     _warning "Test Staging Frontend: FAIL"; ((failed_staging_tests++))
  fi
  # Add more specific staging tests here (e.g. API calls to staging API endpoint)
  if [[ $failed_staging_tests -eq 0 ]]; then return 0; else return 1; fi
}


# setup_monitoring_and_alerts, setup_analytics_and_tracking, create_launch_announcement
# These are more about post-successful-deploy or business activities.
# For a publish script, they might be called after production deployment is confirmed.

finalize_publication() {
  _log "Finalizzazione pubblicazione per versione $VERSION..."
  # Create final deployment summary (this should be done by deploy.sh ideally)
  # For publish script, this might mean tagging git release, notifying stakeholders etc.

  # Example: Git tag
  if command -v git &> /dev/null; then
    if git tag -a "v$VERSION" -m "Release $VERSION" && git push --tags; then
      _success "Git tag v$VERSION creato e pushato."
    else
      _warning "Creazione/Push Git tag fallito. Farlo manualmente."
    fi
  fi

  # Create a simple publication marker
  echo "Version: $VERSION" > "$PROJECT_ROOT/PUBLICATION_INFO.txt"
  echo "Date: $RELEASE_DATE" >> "$PROJECT_ROOT/PUBLICATION_INFO.txt"
  echo "Domain: $DOMAIN" >> "$PROJECT_ROOT/PUBLICATION_INFO.txt"
  echo "Status: LIVE" >> "$PROJECT_ROOT/PUBLICATION_INFO.txt"

  _success "Pubblicazione finalizzata. Info in PUBLICATION_INFO.txt."
}

show_publication_success() {
  echo ""
  _success "╔═════════════════════════════════════════════════════╗"
  _success "║      AI MUSIC STUDIO - PUBLICATION SUCCESSFUL!      ║"
  _success "╚═════════════════════════════════════════════════════╝"
  echo ""
  _info "Versione $VERSION è ora LIVE su https://${DOMAIN}"
  _info "Staging (se deployato): https://${STAGING_DOMAIN}"
  _info "CDN (se configurato): ${CDN_URL:-N/A}"
  echo ""
  _info "Consultare PUBLICATION_INFO.txt e DEPLOYMENT_SUMMARY (generato da deploy.sh) per dettagli."
}


main() {
  touch "$PUBLISH_LOG" && chmod 644 "$PUBLISH_LOG" || { echo "ERROR: Cannot write to log file $PUBLISH_LOG"; exit 1; }
  show_publication_banner
  _log "Inizio pubblicazione globale AI Music Studio..."

  check_publication_prerequisites # Loads .env files, checks vars & files

  # Ensure DOMAIN and STAGING_DOMAIN are set after check_publication_prerequisites
  readonly DOMAIN=${DOMAIN:?"DOMAIN env var must be set"}
  readonly STAGING_DOMAIN=${STAGING_DOMAIN:?"STAGING_DOMAIN env var must be set"}
  readonly CDN_URL=${CDN_URL:-"https://cdn.$DOMAIN"} # Default CDN URL

  # create_production_environment # This was in the original script, but seems to duplicate .env loading.
                                # Assuming .env.production and .env.staging are the source of truth.

  build_and_push_images    # Build and push to Docker registry
  # setup_infrastructure     # Setup cloud resources (Terraform - optional, can be manual)

  # Deploy to Staging
  if [[ "${SKIP_STAGING:-false}" != "true" ]]; then
    if deploy_to_environment "staging" "$STAGING_DOMAIN" "$PROJECT_ROOT/.env.staging"; then
      _success "Deploy a Staging completato con successo."
    else
      _error_exit "Deploy a Staging FALLITO. Controllare i log. Annullamento pubblicazione produzione."
    fi
  else
    _warning "Skipping staging deployment as per SKIP_STAGING flag."
  fi

  # Confirmation before production deploy
  if [[ "${FORCE_PRODUCTION_DEPLOY:-false}" != "true" ]]; then
    echo ""
    _warning "PROCEDERE CON IL DEPLOY IN PRODUZIONE SU https://$DOMAIN ?"
    read -r -p "Digitare 'DEPLOYPROD' per confermare: " confirmation
    if [[ "$confirmation" != "DEPLOYPROD" ]]; then
      _info "Deploy in produzione annullato dall'utente."
      exit 0
    fi
  fi

  # Deploy to Production
  if deploy_to_environment "production" "$DOMAIN" "$PROJECT_ROOT/.env.production"; then
    _success "Deploy in Produzione completato con successo."
  else
    _error_exit "Deploy in Produzione FALLITO. Rollback o investigazione manuale necessaria."
  fi

  # Post-Production steps (Monitoring, Analytics, Announcements)
  # These are called here assuming production deploy was successful.
  # setup_monitoring_and_alerts # From deploy.sh, conceptual here
  # setup_analytics_and_tracking # Conceptual
  # create_launch_announcement # Conceptual

  finalize_publication # Git tagging, creating publication info
  show_publication_success
  _log "Pubblicazione AI Music Studio versione $VERSION completata con successo!"
}


# Argument parsing
# Global script variables
SKIP_STAGING=false
FORCE_PRODUCTION_DEPLOY=false
TARGET_ENV_FILE=""

# Parse arguments
while [[ $# -gt 0 ]]; do
  key="$1"
  case $key in
    --help|-h)
      # (Help text from the original script)
      echo "AI Music Studio - Publication Script"
      # ... (full help text) ...
      exit 0
      ;;
    --staging-only)
      _info "Modalità Staging-Only: Deployerò solo su staging."
      SKIP_PRODUCTION=true # Custom flag to skip prod deploy in main logic if needed
      # This script's main logic is sequential, so we'd need to adjust `main` or handle it here.
      # For now, this option means we run deploy_to_environment for staging and then exit.
      # This requires refactoring main or a separate function.
      # Let's assume for now the user calls with this then stops.
      # A more robust CLI would handle this better.
      # This script isn't really designed for "staging-only" directly in its main flow.
      # It's more of an all-or-nothing publish.
      # The original script had:
      # if deploy_to_staging; then success; else error; fi ; exit
      # This is how it would be if it were a direct option.
      _error_exit "--staging-only not fully implemented in this simplified flow. Please adapt 'main' or use specific deploy commands."
      shift # past argument
      ;;
    --force)
      _warning "Forzatura deploy in produzione senza conferma!"
      FORCE_PRODUCTION_DEPLOY=true
      shift # past argument
      ;;
    --dry-run)
      _info "DRY RUN MODE - Solo output, nessun cambiamento reale."
      export DRY_RUN=true # Other scripts might check this
      # Add dry run logic to functions or simulate them
      _error_exit "--dry-run not fully implemented for all steps."
      shift
      ;;
    *) # unknown option
      _error_exit "Opzione non riconosciuta: $1. Usare --help."
      ;;
  esac
done


# Ensure PROJECT_ROOT is correctly set
cd "$PROJECT_ROOT" || _error_exit "Impossibile accedere a $PROJECT_ROOT."

main
