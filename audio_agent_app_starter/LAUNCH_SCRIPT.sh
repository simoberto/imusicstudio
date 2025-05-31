#!/bin/bash
#
# AI Music Studio - LAUNCH SCRIPT
# Script finale per il lancio pubblico worldwide
#

set -euo pipefail # Ensure script exits on error and undefined variables

# Readonly variables for script paths and project root
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$SCRIPT_DIR" # Assuming LAUNCH_SCRIPT.sh is at the project root

# Colors for better terminal output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly PURPLE='\033[0;35m'
readonly BOLD='\033[1m'
readonly NC='\033[0m' # No Color

# Logging/message functions
_log_msg() { # Generic message logger
    echo -e "${BLUE}[LAUNCH_SCRIPT]${NC} $1"
}
_log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}
_log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}
_log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}


show_launch_banner() {
  clear
  echo -e "${PURPLE}${BOLD}"
  cat << 'EOF'
╔═══════════════════════════════════════════════════════════════╗
║                                                               ║
║      ██████╗ ██╗███╗   ███╗██╗   ██╗███████╗██╗ ██████╗        ║
║      ██╔══██╗██║████╗ ████║██║   ██║██╔════╝██║██╔════╝        ║
║      ██████╔╝██║██╔████╔██║██║   ██║███████╗██║██║  ███╗       ║
║      ██╔═══╝ ██║██║╚██╔╝██║██║   ██║╚════██║██║██║   ██║       ║
║      ██║     ██║██║ ╚═╝ ██║╚██████╔╝███████║██║╚██████╔╝       ║
║      ╚═╝     ╚═╝╚═╝     ╚═╝ ╚═════╝ ╚══════╝╚═╝ ╚═════╝        ║
║                  MUSIC STUDIO - FINAL LAUNCH                  ║
║                                                               ║
║            Ready for Local Setup or Global Publication        ║
╚═══════════════════════════════════════════════════════════════╝
EOF
  echo -e "${NC}"
  echo ""
  _log_msg "${BOLD}Welcome to the AI Music Studio Launch Control!${NC}"
  _log_msg "This script will guide you through setup and deployment."
  echo ""
}

check_final_readiness() {
  echo ""
  _log_msg "${YELLOW}${BOLD}FINAL READINESS CHECK...${NC}"
  local checks_passed=0
  local total_checks=7 # Adjusted based on essential checks for this script's actions

  # Check 1: Essential scripts
  if [[ -x "$PROJECT_ROOT/scripts/setup_environment.sh" &&         -x "$PROJECT_ROOT/scripts/deploy.sh" &&         -x "$PROJECT_ROOT/scripts/publish.sh" ]]; then
      _log_success "Core scripts (setup, deploy, publish) are present and executable."
      ((checks_passed++))
  else
      _log_warning "One or more core scripts (setup_environment.sh, deploy.sh, publish.sh) are missing or not executable in scripts/."
      _log_warning "Please ensure they exist and have execute permissions (chmod +x scripts/*.sh)."
  fi

  # Check 2: Docker Compose files
  if [[ -f "$PROJECT_ROOT/docker-compose.yml" && -f "$PROJECT_ROOT/docker-compose.prod.yml" ]]; then
      _log_success "Docker Compose files (docker-compose.yml, docker-compose.prod.yml) are present."
      ((checks_passed++))
  else
      _log_warning "docker-compose.yml or docker-compose.prod.yml is missing."
  fi

  # Check 3: .env file (for local development at least)
  if [[ -f "$PROJECT_ROOT/.env" ]]; then
     _log_success "Base .env file present (for local development)."
     ((checks_passed++))
  else
     _log_warning ".env file is missing. Local development setup will attempt to create it."
     # This is not a hard fail as setup_environment.sh can create it.
     ((checks_passed++)) # Count as passed if setup can create it.
  fi

  # Check 4: Docker operational
  if docker info >/dev/null 2>&1; then
     _log_success "Docker system operational."
     ((checks_passed++))
  else
     _log_error "Docker daemon is not responding. Please start Docker Desktop."
     # This is a hard requirement.
  fi

  # Check 5: Frontend source structure (basic)
   if [[ -d "$PROJECT_ROOT/frontend/src" && -f "$PROJECT_ROOT/frontend/package.json" ]]; then
       _log_success "Frontend application source structure looks OK."
       ((checks_passed++))
   else
       _log_warning "Frontend source structure (frontend/src, frontend/package.json) seems incomplete."
   fi

  # Check 6: n8n Workflows
  if [[ -f "$PROJECT_ROOT/workflows/n8n_mcp_workflows.json" ]]; then
      _log_success "n8n workflow file (workflows/n8n_mcp_workflows.json) present."
      ((checks_passed++))
  else
      _log_warning "n8n workflow file (workflows/n8n_mcp_workflows.json) is missing. Import will be manual."
  fi

  # Check 7: Scripts directory
  if [[ -d "$PROJECT_ROOT/scripts" ]]; then
      _log_success "Scripts directory present."
      ((checks_passed++))
  else
      _log_error "Critical 'scripts' directory is missing!"
  fi


  echo ""
  _log_msg "${BOLD}READINESS SCORE: ${checks_passed}/${total_checks}${NC}"

  if [[ $checks_passed -ge 5 ]]; then # Allow progressing if most things are fine, setup can fix some.
      _log_success "${GREEN}${BOLD}SYSTEM IS SUFFICIENTLY READY TO PROCEED!${NC}"
      return 0
  else
      _log_error "${RED}${BOLD}SYSTEM NOT READY - CRITICAL COMPONENTS MISSING OR DOCKER DOWN.${NC}"
      _log_error "Please address the warnings/errors above or run a full Git clone if this is a partial checkout."
      return 1
  fi
}

show_launch_options() {
   echo ""
   _log_msg "${BLUE}${BOLD}LAUNCH OPTIONS:${NC}"
   echo ""
   echo -e " ${BOLD}1.${NC} ${GREEN}Local Development Setup & Run${NC} (Recommended for first-time users)"
   echo -e "    ${GREEN}└─ Uses 'scripts/setup_environment.sh' then starts services via 'docker-compose up'.${NC}"
   echo ""
   echo -e " ${BOLD}2.${NC} ${YELLOW}Staging Environment Deployment${NC}"
   echo -e "    ${YELLOW}└─ Uses 'scripts/publish.sh --staging-only' (requires .env.staging & prior setup).${NC}"
   echo ""
   echo -e " ${BOLD}3.${NC} ${RED}PRODUCTION Environment Launch${NC} ${BOLD}(WARNING: LIVE DEPLOYMENT!)${NC}"
   echo -e "    ${RED}└─ Uses 'scripts/publish.sh' (requires .env.production & full setup).${NC}"
   echo ""
   echo -e " ${BOLD}4.${NC} ${BLUE}Run Only 'setup_environment.sh'${NC} (Initial local setup without starting services)"
   echo -e "    ${BLUE}└─ Prepares local environment, creates .env, etc.${NC}"
   echo ""
   echo -e " ${BOLD}5.${NC} ${PURPLE}Cancel & Exit${NC}"
   echo ""
}

run_script() {
    local script_path="$1"
    shift # Remove script_path from arguments, pass the rest
    local script_args=("$@")

    if [[ -x "$script_path" ]]; then
        _log_msg "Executing: $script_path ${script_args[*]}..."
        # Execute in a subshell or directly depending on needs
        # If scripts modify current shell env and we need it, source them (careful).
        # For standalone operations, direct execution is fine.
        "$script_path" "${script_args[@]}"
        local exit_code=$?
        if [[ $exit_code -eq 0 ]]; then
            _log_success "Script $script_path completed successfully."
        else
            _log_error "Script $script_path exited with error code $exit_code."
        fi
        return $exit_code
    else
        _log_error "Script not found or not executable: $script_path"
        return 1
    fi
}


launch_local_development() {
   _log_msg "${GREEN}${BOLD}LAUNCHING LOCAL DEVELOPMENT ENVIRONMENT...${NC}"
   # First, run the complete setup script
   if run_script "$PROJECT_ROOT/scripts/setup_environment.sh"; then
        _log_msg "Local setup complete. Starting services with docker-compose..."
        # Then, start services using the main docker-compose.yml
        # DOCKER_COMPOSE_CMD should be set by setup_environment.sh or check_final_readiness
        local compose_cmd=${DOCKER_COMPOSE_CMD:-"docker-compose"} # Fallback
        if $compose_cmd -f "$PROJECT_ROOT/docker-compose.yml" --env-file "$PROJECT_ROOT/.env" up -d --build; then
            _log_success "Local development services started successfully!"
            _log_msg "Access Frontend: http://localhost:3000"
            _log_msg "Access n8n: http://localhost:5678"
        else
            _log_error "Failed to start local development services with docker-compose."
        fi
   else
        _log_error "Local setup script (setup_environment.sh) failed. Cannot start services."
   fi
}

launch_staging() {
   _log_msg "${YELLOW}${BOLD}INITIATING STAGING ENVIRONMENT DEPLOYMENT...${NC}"
   _log_warning "Ensure '.env.staging' is correctly configured and all prerequisites for publish.sh are met."
   run_script "$PROJECT_ROOT/scripts/publish.sh" "--staging-only" # Assuming publish.sh handles this flag
}

launch_production() {
   _log_msg "${RED}${BOLD}INITIATING PRODUCTION ENVIRONMENT LAUNCH...${NC}"
   _log_warning "${BOLD}WARNING: This is a LIVE deployment to production!${NC}"
   _log_warning "Ensure '.env.production' is correctly configured and you are authorized."

   read -p "Are you absolutely sure you want to launch to PRODUCTION? (type 'YESPROD' to confirm): " confirm
   if [[ "$confirm" == "YESPROD" ]]; then
      run_script "$PROJECT_ROOT/scripts/publish.sh" # publish.sh should handle its own production confirmation if needed
   else
      _log_warning "Production launch cancelled by user."
   fi
}


main() {
    show_launch_banner

    if ! check_final_readiness; then
        _log_error "Cannot proceed with launch options due to readiness check failure."
        exit 1
    fi

    # Ensure DOCKER_COMPOSE_CMD is available from readiness check or set a default
    # This is mainly for the local development option. publish.sh/deploy.sh should set their own.
     if [[ -z "${DOCKER_COMPOSE_CMD:-}" ]]; then
        if command -v docker-compose &> /dev/null; then export DOCKER_COMPOSE_CMD="docker-compose";
        elif docker compose version &> /dev/null; then export DOCKER_COMPOSE_CMD="docker compose";
        else _log_warning "Docker Compose command not determined, local start might fail."; fi
     fi


    while true; do
      show_launch_options
      read -r -p "Select launch option (1-5): " choice

      case $choice in
        1)
             launch_local_development
             break
             ;;
        2)
             launch_staging
             break
             ;;
        3)
             launch_production
             break
             ;;
        4)
             _log_msg "Running only 'setup_environment.sh'..."
             run_script "$PROJECT_ROOT/scripts/setup_environment.sh"
             _log_msg "Local setup script execution finished. You may need to start services manually if not done by script."
             break
             ;;
        5)
             _log_msg "${PURPLE}Launch process cancelled. Goodbye!${NC}"
             exit 0
             ;;
        *)
             _log_error "Invalid option. Please select a number from 1 to 5."
             sleep 1 # Brief pause before re-displaying options
             ;;
      esac
    done

    echo ""
    _log_success "Launch script operations concluded."
}

# Handle command line arguments for direct action (optional)
case "${1:-}" in
  --local)
     show_launch_banner; check_final_readiness && launch_local_development || exit 1 ;;
  --staging)
     show_launch_banner; check_final_readiness && launch_staging || exit 1 ;;
  --production)
     show_launch_banner; check_final_readiness && launch_production || exit 1 ;;
  --setup-only)
     show_launch_banner; check_final_readiness && run_script "$PROJECT_ROOT/scripts/setup_environment.sh" || exit 1 ;;
  --help|-h)
     echo "AI Music Studio - Launch Control Script"
     echo "Usage: $0 [option]"
     echo ""
     echo "Options (can also be chosen interactively if no option is given):"
     echo "  --local         Run local development setup and start services."
     echo "  --staging       Deploy to the staging environment via publish.sh."
     echo "  --production    Deploy to the production environment via publish.sh (with confirmation)."
     echo "  --setup-only    Run only the local setup script (scripts/setup_environment.sh)."
     echo "  --help, -h      Show this help message."
     echo ""
     echo "Interactive mode (default):"
     echo "  $0              Show interactive menu to choose an option."
     exit 0
     ;;
  "") # No arguments, run interactive main
     main
     ;;
  *)
     _log_error "Unknown option: $1"
     _log_error "Use '$0 --help' for available options."
     exit 1
     ;;
esac
