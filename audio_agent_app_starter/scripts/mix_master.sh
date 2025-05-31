#!/usr/bin/env bash
#
# Enhanced Mix and Master Script with Advanced Features
# Supports AI-powered mixing, real-time analysis, and professional mastering
#

set -euo pipefail

# Configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly TEMP_DIR="$(mktemp -d)"
readonly LOG_FILE="/tmp/mix_master_$(date +%s).log" # Consider making this path configurable or relative to data/
readonly WEBSOCKET_URL="ws://websocket:8080" # Assuming websocket service is named 'websocket'

# Audio processing parameters
readonly TARGET_LUFS=${TARGET_LUFS_PARAM:--14} # Allow override via env var
readonly TARGET_PEAK=${TARGET_PEAK_PARAM:--1}  # Allow override
readonly SAMPLE_RATE=${SAMPLE_RATE_PARAM:-44100}
readonly BIT_DEPTH=${BIT_DEPTH_PARAM:-16}
readonly QUALITY_THRESHOLD=${QUALITY_THRESHOLD_PARAM:-70}

# Advanced processing tools
# readonly SOX_EFFECTS_CHAIN=() # This was defined but not used; specific effects are applied directly.
readonly PYTHON_ANALYZER="${SCRIPT_DIR}/audio_analyzer.py" # Ensure this script exists or is created

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly PURPLE='\033[0;35m'
readonly NC='\033[0m' # No Color

# Logging functions
log() {
  echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $*" | tee -a "$LOG_FILE"
}

success() {
  echo -e "${GREEN}✓${NC} $*" | tee -a "$LOG_FILE"
}

warning() {
  echo -e "${YELLOW}⚠${NC} $*" | tee -a "$LOG_FILE"
}

error_exit() { # Renamed from error to avoid conflict with error messages
  log "${RED}ERROR: $1${NC}" # Ensure NC is applied correctly
  # Send error status via WebSocket before exiting
  send_websocket_update "mixing_error" "failed" "{\"error_message\": \"$1\"}"
  cleanup
  exit 1
}

info() {
   echo -e "${PURPLE}ℹ${NC} $*" | tee -a "$LOG_FILE"
}

cleanup() {
   log "Cleaning up temporary directory: $TEMP_DIR"
   rm -rf "$TEMP_DIR"
   # Note: WebSocket update for completion should be in the main logic, not duplicated here if also trapped.
}

# Trap cleanup on exit
trap cleanup EXIT SIGINT SIGTERM

# WebSocket communication
send_websocket_update() {
  local event_type="$1"
  local status="$2"
  local data_json="${3:-{\}}" # Default to empty JSON object

  # Ensure data_json is valid JSON, escape quotes if it's a simple string not meant as JSON object
  # For simplicity, assuming $3 will be a JSON string or empty.

  # Check if curl is available
  if ! command -v curl &> /dev/null; then
    log "curl command not found, cannot send WebSocket update."
    return 1
  fi

  # Check if websocket service is resolvable/available (basic check)
  # This is a simple check; a more robust solution might involve netcat or similar.
  # local ws_host_port=$(echo "$WEBSOCKET_URL" | sed -n 's|ws://\([^/]*\)/.*||p' || echo "websocket:8080")
  # if ! curl --output /dev/null --silent --head --fail "http://${ws_host_port}"; then
  #   log "WebSocket server at $WEBSOCKET_URL not reachable."
  #   # return 1 # Decide if this should be fatal or just a warning
  # fi


  # Use an HTTP endpoint on the websocket server if it supports it for non-ws messages,
  # or use a command-line websocket client if available (e.g., wscat, websocat).
  # The example used http POST, which might not be how the websocket server is set up to receive these.
  # For now, assuming an HTTP endpoint on the websocket server for simplicity as per the original script.
  # This is a common pattern for servers to accept non-WebSocket messages.
  local http_post_url=$(echo "$WEBSOCKET_URL" | sed 's|ws://|http://|')/update # Assuming an /update endpoint

  log "Sending WebSocket update: $event_type - $status"
  curl -s -X POST "$http_post_url" \
     -H "Content-Type: application/json" \
     -d "{\"type\":\"$event_type\",\"status\":\"$status\",\"data\":${data_json}}" \
     --max-time 5 \
     2>/dev/null || log "Failed to send WebSocket update to $http_post_url"
}


# Advanced dependency checking
check_dependencies() {
  log "Checking dependencies and system capabilities..."

  local deps=("sox" "ffmpeg" "jq" "python3" "bc") # Added bc for calculations
  local optional_deps=("matchering" "rubberband") # Removed ladspa-sdk as it's too broad
  local missing_deps=()
  local missing_optional=()

  for dep in "${deps[@]}"; do
     if ! command -v "$dep" &> /dev/null; then
         missing_deps+=("$dep")
     else
         success "Found $dep"
     fi
  done

  for dep in "${optional_deps[@]}"; do
     if ! command -v "$dep" &> /dev/null; then
         missing_optional+=("$dep")
     else
         success "Found optional: $dep"
     fi
  done

  if [[ ${#missing_deps[@]} -gt 0 ]]; then
      error_exit "Missing required dependencies: ${missing_deps[*]}"
  fi

  if [[ ${#missing_optional[@]} -gt 0 ]]; then
      warning "Missing optional dependencies: ${missing_optional[*]}"
      info "Some advanced features may not be available (e.g., AI mastering with Matchering)"
  fi

  # Check SoX capabilities
  check_sox_capabilities
  success "Dependency check completed"
}

check_sox_capabilities() {
  if ! command -v sox &> /dev/null; then return 1; fi
  local sox_formats
  sox_formats=$(sox --help 2>&1 | grep -i "AUDIO FILE FORMATS" -A 20 | tail -n +2 | head -n 20 || echo "")

  if echo "$sox_formats" | grep -q "flac"; then
     info "SoX: FLAC support available"
  fi

  if echo "$sox_formats" | grep -q "mp3"; then
     info "SoX: MP3 support available"
  else
     warning "SoX: MP3 support not available (install libsox-fmt-mp3 or similar)"
  fi
}

# Enhanced JSON parsing with validation
parse_and_validate_stems() {
  local stems_json="$1"
  local stems_array
  local validated_stems=()

  if ! stems_array=$(echo "$stems_json" | jq -r '.[] // empty' 2>/dev/null); then # Handle empty array
      error_exit "Invalid JSON format for stems: $stems_json"
  fi

  if [[ -z "$stems_array" ]]; then
      log "No stems provided in JSON input."
      # Depending on requirements, this could be an error or handled gracefully.
      # For now, allow empty, but mix_stems_parallel will error if no valid stems.
      return # Exit function if no stems
  fi

  while IFS= read -r stem_file_path; do # Renamed to avoid conflict
    if [[ -z "$stem_file_path" ]]; then
        continue
    fi

    # Basic path validation (more can be added)
    if [[ "$stem_file_path" != /* && "$stem_file_path" != ./* ]]; then
        warning "Stem path '$stem_file_path' might be relative without ./ ; ensure it's accessible."
    fi

    # Ensure it's a file and not a directory
    if [[ ! -f "$stem_file_path" ]]; then
        error_exit "Stem file not found or is a directory: $stem_file_path"
    fi

    # Check if it's an audio file (basic check, can be improved with `file` command)
    if ! soxi "$stem_file_path" >/dev/null 2>&1; then # soxi is good for checking audio properties
        warning "File may not be a valid audio format recognized by SoX: $stem_file_path"
        # Optionally, skip this file or try to convert it
        # continue
    fi

    local file_size
    file_size=$(stat -c%s "$stem_file_path" 2>/dev/null || stat -f%z "$stem_file_path" 2>/dev/null || echo "0")
    if [[ $file_size -lt 1000 ]]; then # 1KB
        warning "Very small file, may be corrupted or empty: $stem_file_path ($file_size bytes)"
    fi

    if command -v soxi &> /dev/null; then
       local duration
       duration=$(soxi -D "$stem_file_path" 2>/dev/null || echo "0")
       if (( $(echo "$duration < 0.1" | bc -l 2>/dev/null || echo "1") )); then # Less than 0.1s
           warning "Very short audio file (or error reading duration): $stem_file_path (${duration}s)"
       fi
    fi

    validated_stems+=("$stem_file_path")
    success "Validated stem: $(basename "$stem_file_path")"
  done <<< "$stems_array"

  # This check is now more critical if the function can return without error on empty input
  # if [[ ${#validated_stems[@]} -eq 0 && -n "$stems_array" ]]; then
  #     error_exit "No valid stems found after parsing and validation, though input was not empty."
  # fi

  printf '%s\n' "${validated_stems[@]}" # Ensure each stem is on a new line
}


# Advanced audio analysis using Python
analyze_stem_advanced() {
  local stem_file="$1"
  local stem_basename
  stem_basename=$(basename "$stem_file")
  # Sanitize basename for filename: replace non-alphanumeric with underscore
  local sanitized_basename="${stem_basename//[^a-zA-Z0-9_.-]/_}"
  local analysis_output="$TEMP_DIR/analysis_${sanitized_basename}.json"


  log "Performing advanced analysis on $stem_basename"

  if [[ ! -f "$PYTHON_ANALYZER" ]]; then
      warning "Python analyzer script '$PYTHON_ANALYZER' not found. Falling back to basic analysis."
      analyze_stem_basic "$stem_file" # Call the basic version
      return 1 # Indicate that advanced analysis was not performed
  fi

  if python3 "$PYTHON_ANALYZER" --input "$stem_file" --output "$analysis_output" --verbose; then
     success "Advanced analysis completed for $stem_basename"
     echo "$analysis_output"
     return 0
  else
     warning "Advanced analysis failed for $stem_basename, using basic analysis."
     analyze_stem_basic "$stem_file" # Call the basic version
     return 1 # Indicate fallback
  fi
}

# Fallback basic analysis
analyze_stem_basic() {
  local stem_file="$1"
  local stem_basename
  stem_basename=$(basename "$stem_file")
  local sanitized_basename="${stem_basename//[^a-zA-Z0-9_.-]/_}"
  local analysis_file="$TEMP_DIR/analysis_${sanitized_basename}.json" # Use sanitized name

  log "Performing basic SoX-based analysis for $stem_basename"

  local duration peak rms
  duration=$(soxi -D "$stem_file" 2>/dev/null || echo "30") # Default duration if soxi fails
  # Capture SoX stats output
  local sox_stats_output
  sox_stats_output=$(sox "$stem_file" -n stats 2>&1 || echo "") # Ensure it doesn't exit script on sox error

  peak=$(echo "$sox_stats_output" | grep "Maximum amplitude" | awk '{print $3}' || echo "0.5")
  rms=$(echo "$sox_stats_output" | grep "RMS.*amplitude" | awk '{print $4}' || echo "0.1")

  # Ensure numeric values, default if parsing fails
  duration=$(echo "$duration" | bc -l 2>/dev/null || echo "30")
  peak=$(echo "$peak" | bc -l 2>/dev/null || echo "0.5")
  rms=$(echo "$rms" | bc -l 2>/dev/null || echo "0.1")

  local dynamic_range_val
  dynamic_range_val=$(echo "$peak - $rms" | bc -l 2>/dev/null || echo "0.4")


  # Create basic analysis JSON
  # Using jq for safer JSON creation
  jq -n --arg file "$stem_file" \
        --argjson dur "$duration" \
        --argjson pk "$peak" \
        --argjson r_m_s "$rms" \
        --argjson dr "$dynamic_range_val" \
        '{file: $file, duration: $dur, peak: $pk, rms: $r_m_s, dynamic_range: $dr, analysis_type: "basic"}' > "$analysis_file"

  success "Basic analysis completed for $stem_basename"
  echo "$analysis_file" # Return the path to the analysis file
}


# AI-powered intelligent mixing
apply_intelligent_mixing() {
  local stem_file="$1"
  local analysis_file_path="$2" # Renamed to avoid conflict
  local output_file="$3"

  log "Applying intelligent mixing to $(basename "$stem_file")"

  if [[ ! -f "$analysis_file_path" ]]; then
      warning "Analysis file '$analysis_file_path' not found for $stem_file. Skipping intelligent mixing."
      cp "$stem_file" "$output_file" # Just copy if no analysis
      return
  fi

  local analysis_content
  analysis_content=$(cat "$analysis_file_path")

  # Extract key metrics using jq for safety
  local peak rms spectral_centroid energy_low energy_mid energy_high
  peak=$(echo "$analysis_content" | jq -r '.peak // 0.5')
  rms=$(echo "$analysis_content" | jq -r '.rms // 0.1')
  spectral_centroid=$(echo "$analysis_content" | jq -r '.spectral_features.spectral_centroid_mean // .basic_properties.spectral_centroid_mean // .spectral_centroid_mean // 1000')
  energy_low=$(echo "$analysis_content" | jq -r '.spectral_features.frequency_bands.bass // .energy_distribution.low // 0.1')
  energy_mid=$(echo "$analysis_content" | jq -r '.spectral_features.frequency_bands.mid // .energy_distribution.mid // 0.1')
  energy_high=$(echo "$analysis_content" | jq -r '.spectral_features.frequency_bands.presence // .spectral_features.frequency_bands.brilliance // .energy_distribution.high // 0.1')


  local instrument_type
  # Prefer instrument detection from advanced analysis if available
  instrument_type=$(echo "$analysis_content" | jq -r '.instrument_detection.predicted_instrument // empty')
  if [[ -z "$instrument_type" ]]; then # Fallback to filename detection
      instrument_type=$(detect_instrument_type_from_filename "$stem_file") # Simpler filename based detection
  fi
  log "Detected instrument type for mixing: $instrument_type"


  local sox_effects=("highpass" "20") # Universal cleanup: Remove DC offset and subsonic rumble

  case "$instrument_type" in
     "bass")
       sox_effects+=("lowpass" "250") # Slightly higher cutoff for more presence if needed
       if (( $(echo "$energy_low < 0.05" | bc -l 2>/dev/null || echo 0) )); then # Check if low energy is too low
           sox_effects+=("bass" "+2dB") # Gentle bass boost
       fi
       sox_effects+=("compand" "0.1,0.3" "6:-70,-50,-20" "-3" "-90" "0.1") # Tuned compression for bass
       ;;
     "drums")
       sox_effects+=("compand" "0.005,0.05" "6:-70,-60,-30" "-6" "-90" "0.02") # Fast compression for transients
       if (( $(echo "$energy_high < 0.05" | bc -l 2>/dev/null || echo 0) )); then
           sox_effects+=("treble" "+1.5dB") # Slight treble boost for cymbals/hats
       fi
       ;;
     "guitar"|"piano")
       if (( $(echo "$spectral_centroid > 2500" | bc -l 2>/dev/null || echo 0) )); then # If instrument is bright
           sox_effects+=("highpass" "80") # Cut some lows
       fi
       sox_effects+=("compand" "0.2,0.8" "6:-70,-50,-25" "-4" "-90" "0.15") # Gentle compression
       ;;
      "synth"|"other"|"vocal") # Added vocal here as it might need similar general processing
         if (( $(echo "$spectral_centroid > 3500" | bc -l 2>/dev/null || echo 0) )); then
             sox_effects+=("highpass" "100")
         fi
         if (( $(echo "$energy_mid < 0.03" | bc -l 2>/dev/null || echo 0) )); then # If mids are lacking
             sox_effects+=("equalizer" "1000" "1.5q" "+1dB") # Boost mids slightly
         fi
         ;;
    esac

    # Adaptive gain staging based on peak
    if (( $(echo "$peak > 0.9" | bc -l 2>/dev/null || echo 0) )); then
        sox_effects+=("gain" "-3dB")
    elif (( $(echo "$peak < 0.2" | bc -l 2>/dev/null || echo 0) && $(echo "$peak > 0.01" | bc -l 2>/dev/null || echo 0) )); then # Avoid over-boosting silence
        sox_effects+=("gain" "+3dB")
    fi
    sox_effects+=("norm" "-1") # Normalize to -1dB peak as a final step

    if [[ ${#sox_effects[@]} -gt 2 ]]; then # Check if more than just the initial highpass was added
        info "Applying effects to $instrument_type ($(basename "$stem_file")): ${sox_effects[*]}"
        sox "$stem_file" "$output_file" "${sox_effects[@]}" || {
            warning "SoX processing failed for $(basename "$stem_file"). Copying original."
            cp "$stem_file" "$output_file"
        }
    else
        log "No specific intelligent mixing effects applied for $(basename "$stem_file"), copying and normalizing."
        sox "$stem_file" "$output_file" norm -1 || cp "$stem_file" "$output_file" # Normalize if no other effects
    fi
    success "Intelligent mixing applied to $(basename "$stem_file")"
}

# Simplified instrument detection from filename for fallback
detect_instrument_type_from_filename() {
  local stem_file="$1"
  local filename
  filename=$(basename "$stem_file" | tr '[:upper:]' '[:lower:]')

  if [[ "$filename" =~ bass ]]; then echo "bass"
  elif [[ "$filename" =~ drum ]]; then echo "drums"
  elif [[ "$filename" =~ guitar ]]; then echo "guitar"
  elif [[ "$filename" =~ piano|keyboard ]]; then echo "piano"
  elif [[ "$filename" =~ synth ]]; then echo "synth"
  elif [[ "$filename" =~ vocal ]]; then echo "vocal"
  else echo "other"; fi
}


# Advanced mixing with parallel processing
mix_stems_parallel() {
  local stems_array_str="$1" # Expecting a string with newlines
  local output_file="$2"

  log "Starting parallel stem processing..."
  send_websocket_update "mixing_progress" "processing_stems" "{\"stem_count\": $(echo -n "$stems_array_str" | wc -l)}"


  local processed_stems_files=() # Store paths to files listing processed stems
  local pids=()
  local stem_count=0

  # Create a temporary file for each stem's processing result path
  # This avoids issues with direct array appends from subshells

  # Ensure stems_array_str is not empty before proceeding
  if [[ -z "$stems_array_str" ]]; then
      error_exit "No stems provided to mix_stems_parallel."
  fi

  while IFS= read -r stem; do
     if [[ -z "$stem" ]]; then continue; fi # Skip empty lines
     ((stem_count++))

     # Path for the temp file that will store the processed stem's path and its analysis file path
     local result_file_path="$TEMP_DIR/result_path_${stem_count}.txt"

     (
       log "Processing stem $stem_count: $(basename "$stem")"
       local processed_stem_path="$TEMP_DIR/processed_$(printf "%02d" "$stem_count")_$(basename "$stem")"

       # Analyze stem
       local analysis_file_path # Declared to store path from analyze_stem_advanced
       analysis_file_path=$(analyze_stem_advanced "$stem") # This now returns the path

       # Apply intelligent mixing
       apply_intelligent_mixing "$stem" "$analysis_file_path" "$processed_stem_path"

       # Validate output
       if [[ -f "$processed_stem_path" && -s "$processed_stem_path" ]]; then
           echo "$processed_stem_path" > "$result_file_path" # Store only processed stem path
           # Analysis file path could be stored too if needed later: echo "$processed_stem_path|$analysis_file_path"
       else
           warning "Failed to process stem: $stem. It will be excluded from the mix."
           # Optionally, create an empty result file to signify failure for this stem
           # > "$result_file_path" # Or handle differently
       fi
     ) &
    pids+=($!)

    # Limit concurrent processes (e.g., to number of CPU cores or a fixed number)
    # This is a simple way; more advanced would use `nproc` or similar
    if [[ $(jobs -p | wc -l) -ge $(nproc 2>/dev/null || echo 4) ]]; then
        wait -n # Wait for any job to complete
    fi
  done <<< "$stems_array_str"

  # Wait for all remaining background jobs
  for pid in "${pids[@]}"; do
     wait "$pid" || log "A stem processing job failed (PID: $pid)"
  done

  # Collect results
  local final_processed_stems_for_mix=()
  for i in $(seq 1 $stem_count); do
     local result_path_file="$TEMP_DIR/result_path_$i.txt"
     if [[ -f "$result_path_file" && -s "$result_path_file" ]]; then
         local processed_stem_path_from_file
         processed_stem_path_from_file=$(cat "$result_path_file")
         if [[ -n "$processed_stem_path_from_file" && -f "$processed_stem_path_from_file" ]]; then
             final_processed_stems_for_mix+=("$processed_stem_path_from_file")
             success "Collected processed stem: $(basename "$processed_stem_path_from_file")"
         fi
     fi
  done

  if [[ ${#final_processed_stems_for_mix[@]} -eq 0 ]]; then
      error_exit "No stems were successfully processed. Cannot create a mix."
  fi

  log "Mixing ${#final_processed_stems_for_mix[@]} processed stems..."
  send_websocket_update "mixing_progress" "final_mix" "{\"mix_stem_count\": ${#final_processed_stems_for_mix[@]}}"


  if [[ ${#final_processed_stems_for_mix[@]} -eq 1 ]]; then
      cp "${final_processed_stems_for_mix[0]}" "$output_file"
  else
      mix_with_balancing "${final_processed_stems_for_mix[@]}" "$output_file"
  fi
  success "Parallel stem processing and mixing completed."
}

# Advanced mixing with automatic level balancing
mix_with_balancing() {
  local output_file="${@: -1}" # Last argument
  local stems=("${@:1:$#-1}") # All arguments except the last

  log "Performing advanced mix with automatic balancing for ${#stems[@]} stems..."

  if [[ ${#stems[@]} -eq 0 ]]; then
    error_exit "No stems provided to mix_with_balancing."
  fi

  # Analyze RMS levels of all stems to find a reference for balancing
  local levels_str=""
  local total_rms=0
  local count_rms=0

  for stem in "${stems[@]}"; do
     # Using sox stat, redirect stderr to stdout for parsing
     local rms_level
     rms_level=$(sox "$stem" -n stat 2>&1 | grep "RMS.*amplitude" | awk '{print $4}' | tr -d '\n' || echo "0.00001")
     # Ensure rms_level is not empty or non-numeric before adding
     if [[ -n "$rms_level" ]] && [[ "$rms_level" =~ ^[0-9.]+$ ]]; then
        levels_str+="$rms_level " # Store for later use if needed
        total_rms=$(echo "$total_rms + $rms_level" | bc -l)
        ((count_rms++))
     else
        log "Warning: Could not determine RMS for $stem, using 0.00001"
        levels_str+="0.00001 "
        total_rms=$(echo "$total_rms + 0.00001" | bc -l)
        ((count_rms++))
     fi
  done

  local avg_rms=0.00001 # Default to a very small number to avoid division by zero
  if [[ $count_rms -gt 0 ]] && (( $(echo "$total_rms > 0" | bc -l 2>/dev/null || echo 0) )); then
    avg_rms=$(echo "scale=5; $total_rms / $count_rms" | bc -l)
  fi
  log "Average RMS for balancing: $avg_rms"


  local mix_cmd_array=("sox" "-m")
  local current_stem_rms
  local gain_db

  for stem in "${stems[@]}"; do
    current_stem_rms=$(sox "$stem" -n stat 2>&1 | grep "RMS.*amplitude" | awk '{print $4}' | tr -d '\n' || echo "0.00001")
    if [[ -z "$current_stem_rms" ]] || ! [[ "$current_stem_rms" =~ ^[0-9.]+$ ]]; then
        current_stem_rms="0.00001" # Fallback if RMS cannot be read
    fi

    # Calculate gain adjustment in dB to bring current_stem_rms to avg_rms
    # gain_db = 20 * log10(target_rms / current_rms)
    if (( $(echo "$current_stem_rms > 0.000001 && $avg_rms > 0.000001" | bc -l 2>/dev/null || echo 0) )); then # Avoid log(0) or division by zero
        gain_db=$(echo "scale=2; 20 * l($avg_rms / $current_stem_rms) / l(10)" | bc -l 2>/dev/null || echo "0")
    else
        gain_db="0" # No gain adjustment if RMS is too low or zero
    fi

    log "Balancing $(basename "$stem"): current RMS $current_stem_rms, target avg RMS $avg_rms, gain ${gain_db}dB"

    # Create a temporary file for the gain-adjusted stem
    local temp_stem_path="$TEMP_DIR/balanced_$(basename "$stem")"
    # Apply gain using SoX `vol` effect which takes linear factor, or `gain` for dB
    # SoX `vol` effect takes a linear factor. gain_factor = 10^(gain_db / 20)
    # However, sox `gain` effect directly takes dB.
    sox "$stem" "$temp_stem_path" gain "$gain_db" || {
        warning "Gain adjustment failed for $(basename "$stem"). Using original."
        cp "$stem" "$temp_stem_path" # Fallback to original if gain fails
    }
    mix_cmd_array+=("$temp_stem_path")
  done

  mix_cmd_array+=("$output_file") # Add output file path

  # Execute mix command
  "${mix_cmd_array[@]}" || error_exit "Advanced mixing command failed: ${mix_cmd_array[*]}"

  success "Advanced mixing with RMS balancing completed: $output_file"
}


# AI-powered mastering with multiple algorithms
master_audio_advanced() {
  local input_file="$1"
  local reference_track="$2" # Optional reference track
  local output_file="$3"
  local target_lufs_for_mastering="${4:-$TARGET_LUFS}" # Use specific var name

  log "Starting advanced mastering process for $(basename "$input_file"). Target LUFS: $target_lufs_for_mastering"
  send_websocket_update "mixing_progress" "mastering" "{\"input\": \"$(basename "$input_file")\"}"


  local current_stage_file="$input_file"
  local next_stage_file

  # Stage 1: Pre-mastering analysis (already done for mix_file if it's the input)
  # If input_file is a raw mix, it might be good to analyze it here.
  # local analysis_file_path=$(analyze_stem_advanced "$current_stage_file")

  # Stage 2: Dynamic range optimization (gentle compression)
  log "Applying dynamic range optimization..."
  next_stage_file="$TEMP_DIR/master_stage1_dynamics.wav"
  sox "$current_stage_file" "$next_stage_file" compand 0.01,0.05 -60,-60,-30,-15,-20 -5 -90 0.05 remix - || {
    warning "Dynamics optimization failed. Using previous stage."
    cp "$current_stage_file" "$next_stage_file" # Fallback
  }
  current_stage_file="$next_stage_file"

  # Stage 3: Frequency balancing (subtle EQ)
  log "Applying frequency balancing..."
  next_stage_file="$TEMP_DIR/master_stage2_eq.wav"
  # Example: subtle high shelf for clarity, low cut for mud removal
  sox "$current_stage_file" "$next_stage_file" equalizer 8000 0.5q +1 equalizer 100 1.0q -1.5 highpass 30 || {
     warning "Frequency balancing failed. Using previous stage."
     cp "$current_stage_file" "$next_stage_file"
  }
  current_stage_file="$next_stage_file"

  # Stage 4: Stereo enhancement (if stereo and Matchering is not used)
  local channels
  channels=$(soxi -c "$current_stage_file" 2>/dev/null || echo 1)
  if [[ $channels -eq 2 ]] && ! ( [[ -n "$reference_track" && -f "$reference_track" ]] && command -v matchering &> /dev/null ); then
      log "Applying stereo enhancement..."
      next_stage_file="$TEMP_DIR/master_stage3_stereo.wav"
      # Example: mid-side EQ or subtle stereo widener. SoX `oops` is more for karaoke.
      # Using `remix` for a very subtle width increase - this is just an example.
      # A real stereo widener is more complex.
      sox "$current_stage_file" "$next_stage_file" remix 1,2v0.9 1,2v1.1 || { # This is a placeholder for actual stereo enhancement
          warning "Stereo enhancement failed. Using previous stage."
          cp "$current_stage_file" "$next_stage_file"
      }
      current_stage_file="$next_stage_file"
  fi

  # Stage 5: Reference-based mastering or Standard LUFS Normalization
  local final_normalized_file="$TEMP_DIR/master_stage4_normalized.wav"
  if [[ -n "$reference_track" && -f "$reference_track" ]] && command -v matchering &> /dev/null; then
      log "Applying AI mastering with Matchering using reference: $(basename "$reference_track")"
      # Matchering will handle LUFS target based on reference.
      matchering "$current_stage_file" "$reference_track" "$final_normalized_file" \
         --dont_save_config \
         --log_level WARNING || {
           warning "Matchering AI mastering failed. Falling back to standard normalization."
           # Fallback to standard normalization if Matchering fails
           ffmpeg-normalize "$current_stage_file" -o "$final_normalized_file" \
             -t "$target_lufs_for_mastering" -p "$TARGET_PEAK" -ar "$SAMPLE_RATE" -b:a "${BIT_DEPTH}k" \
             -c:a pcm_s${BIT_DEPTH}le -f wav -v error || {
               error_exit "Standard normalization fallback also failed after Matchering failure."
             }
         }
  else
      if [[ -n "$reference_track" && -f "$reference_track" ]]; then
          log "Matchering not available. Applying reference-based processing (fallback) for $(basename "$reference_track")"
          apply_reference_based_processing_fallback "$current_stage_file" "$reference_track" "$final_normalized_file" "$target_lufs_for_mastering"
      else
          log "Applying standard LUFS normalization. Target LUFS: $target_lufs_for_mastering"
          ffmpeg-normalize "$current_stage_file" -o "$final_normalized_file" \
            -t "$target_lufs_for_mastering" -p "$TARGET_PEAK" -ar "$SAMPLE_RATE" \
            -c:a pcm_s${BIT_DEPTH}le -f wav -v error || { # Added -v error for less verbose ffmpeg
              error_exit "Standard LUFS normalization failed."
            }
      fi
  fi
  current_stage_file="$final_normalized_file"

  # Final Limiting (Brickwall Limiter)
  log "Applying final peak limiting..."
  next_stage_file="$TEMP_DIR/master_final_limited.wav"
  # SoX compand can act as a limiter: compand attack,decay thresh_in,thresh_out gain knee output_gain delay
  # This sets a very fast attack/decay, high ratio (implicit via thresholds) for anything above -1.1dBFS
  # and then brings it down to -1.0dBFS.
  sox "$current_stage_file" "$next_stage_file" compand 0.001,0.005 -inf,-1.1,-1.1 -1.0 -90 0.001 gain -0.1 || {
      warning "Final limiting failed. Using previous stage."
      cp "$current_stage_file" "$next_stage_file"
  }
  current_stage_file="$next_stage_file"


  # Final quality check and copy
  if [[ -f "$current_stage_file" && -s "$current_stage_file" ]]; then
      local quality_score
      quality_score=$(validate_master_quality "$current_stage_file") # This function needs to be robust

      if (( $(echo "$quality_score >= $QUALITY_THRESHOLD" | bc -l 2>/dev/null || echo 0) )); then
         cp "$current_stage_file" "$output_file" # Use cp instead of mv to keep temp file for inspection
         success "Mastering completed. Output: $(basename "$output_file"). Quality score: $quality_score"
      else
         warning "Mastered audio quality score ($quality_score) is below threshold ($QUALITY_THRESHOLD)."
         # Decide if to use this output or attempt correction. For now, using it.
         cp "$current_stage_file" "$output_file"
         warning "Using output despite low quality score. Output: $(basename "$output_file")"
         # apply_quality_correction "$current_stage_file" "$output_file" # This was defined but might be too aggressive
      fi
  else
      error_exit "Mastering process failed to produce a valid final output file."
  fi
}

# Reference-based processing fallback (simpler version)
apply_reference_based_processing_fallback() {
  local input_file="$1"
  local reference_file="$2"
  local output_file="$3"
  local target_lufs="$4" # Added target LUFS for this fallback

  log "Analyzing reference track for fallback processing: $(basename "$reference_file")"
  local ref_analysis_path
  ref_analysis_path=$(analyze_stem_advanced "$reference_file") # Returns path

  if [[ ! -f "$ref_analysis_path" ]]; then
      warning "Could not analyze reference track. Using standard normalization."
      ffmpeg-normalize "$input_file" -o "$output_file" \
        -t "$target_lufs" -p "$TARGET_PEAK" -ar "$SAMPLE_RATE" \
        -c:a pcm_s${BIT_DEPTH}le -f wav -v error || error_exit "Standard normalization failed in fallback."
      return
  fi

  local ref_analysis_content
  ref_analysis_content=$(cat "$ref_analysis_path")

  local ref_spectral_centroid
  ref_spectral_centroid=$(echo "$ref_analysis_content" | jq -r '.spectral_features.spectral_centroid_mean // 2000')

  local effects=()
  # Example: if reference is much brighter, add a slight high shelf
  if (( $(echo "$ref_spectral_centroid > 2800" | bc -l 2>/dev/null || echo 0) )); then
      effects+=("treble" "+0.5dB")
  elif (( $(echo "$ref_spectral_centroid < 1200" | bc -l 2>/dev/null || echo 0) )); then
      effects+=("bass" "+0.5dB")
  fi

  local temp_processed_file="$TEMP_DIR/ref_processed_fallback.wav"
  if [[ ${#effects[@]} -gt 0 ]]; then
      sox "$input_file" "$temp_processed_file" "${effects[@]}" || {
          warning "Reference-based EQ failed. Using input for normalization."
          cp "$input_file" "$temp_processed_file"
      }
  else
      cp "$input_file" "$temp_processed_file"
  fi

  ffmpeg-normalize "$temp_processed_file" -o "$output_file" \
    -t "$target_lufs" -p "$TARGET_PEAK" -ar "$SAMPLE_RATE" \
    -c:a pcm_s${BIT_DEPTH}le -f wav -v error || error_exit "Normalization failed in reference fallback."

  success "Reference-based processing fallback applied for $(basename "$input_file")"
}


# Validate mastering quality (more robust)
validate_master_quality() {
  local audio_file="$1"
  if [[ ! -f "$audio_file" || ! -s "$audio_file" ]]; then echo 0; return; fi

  local peak rms duration lufs loudness_stats
  # Use ffmpeg for LUFS if available, otherwise sox stats
  if command -v ffmpeg &> /dev/null; then
      loudness_stats=$(ffmpeg -i "$audio_file" -af loudnorm=I=-23:LRA=7:TP=-2:print_format=json -f null - 2>&1 | grep Parsed_loudnorm_ || echo "")
      lufs=$(echo "$loudness_stats" | jq -r '.input_i // empty' | sed 's/ LUFS//' || echo "")
  fi

  local sox_stats_output
  sox_stats_output=$(sox "$audio_file" -n stat 2>&1 || echo "")
  peak=$(echo "$sox_stats_output" | grep "Maximum amplitude" | awk '{print $3}' || echo 1.0) # Default to 1 if error
  rms=$(echo "$sox_stats_output" | grep "RMS.*amplitude" | awk '{print $4}' || echo 0.001) # Default to low RMS
  duration=$(soxi -D "$audio_file" 2>/dev/null || echo 0)

  # Ensure numeric, provide defaults
  peak=$(echo "$peak" | bc -l 2>/dev/null || echo 1.0)
  rms=$(echo "$rms" | bc -l 2>/dev/null || echo 0.001)
  duration=$(echo "$duration" | bc -l 2>/dev/null || echo 0)
  lufs_num=$(echo "$lufs" | bc -l 2>/dev/null || echo -23) # Default to a low LUFS if not found


  local quality_score=100.0 # Start with float

  # Clipping: If peak is > -0.1dBFS (SoX peak is linear, 0.988 is approx -0.1dBFS)
  if (( $(echo "$peak > 0.988" | bc -l 2>/dev/null || echo 0) )); then
       quality_score=$(echo "$quality_score - 20" | bc -l)
  fi

  # Silence / Very Low RMS: If RMS is below -40dBFS (linear approx 0.01)
  if (( $(echo "$rms < 0.01" | bc -l 2>/dev/null || echo 0) )); then
      quality_score=$(echo "$quality_score - 30" | bc -l)
  fi

  # Duration: Penalize if less than 5 seconds
  if (( $(echo "$duration < 5" | bc -l 2>/dev/null || echo 0) )); then
      quality_score=$(echo "$quality_score - 15" | bc -l)
  fi

  # LUFS Target Check (e.g. if target is -14 LUFS)
  if [[ -n "$lufs" ]]; then # Only if LUFS was measured
      local lufs_diff
      lufs_diff=$(echo "$lufs_num - $TARGET_LUFS" | bc -l) # Use actual target LUFS
      lufs_diff_abs=$(echo "scale=1; sqrt($lufs_diff^2)" | bc -l) # Absolute difference
      if (( $(echo "$lufs_diff_abs > 2.0" | bc -l 2>/dev/null || echo 0) )); then # If more than 2 LUFS off
          quality_score=$(echo "$quality_score - (10 * $lufs_diff_abs / 2)" | bc -l) # Penalize proportionally
      fi
  else
      log "LUFS not measured for quality validation, skipping LUFS check."
  fi

  # Ensure score is within 0-100
  if (( $(echo "$quality_score < 0" | bc -l 2>/dev/null || echo 0) )); then quality_score=0; fi
  if (( $(echo "$quality_score > 100" | bc -l 2>/dev/null || echo 0) )); then quality_score=100; fi

  printf "%.0f" "$quality_score" # Return as integer
}


# Generate comprehensive analysis report
generate_detailed_report() {
  local output_file="$1"
  local execution_id="$2"
  local stems_info_json="$3" # Expecting JSON string of stems info

  local report_file="/data/reports/mix_report_${execution_id}.json" # Save to data/reports

  log "Generating comprehensive analysis report for $execution_id..."
  send_websocket_update "mixing_progress" "generating_report" "{\"file\": \"$(basename "$report_file")\"}"


  # Final audio analysis
  local final_analysis_path # Path to the JSON file from analyze_stem_advanced
  final_analysis_path=$(analyze_stem_advanced "$output_file")
  local final_analysis_content="{\"error\": \"Analysis failed for final output\"}" # Default if analysis fails
  if [[ -f "$final_analysis_path" ]]; then
      final_analysis_content=$(cat "$final_analysis_path")
  fi

  # System information
  local sox_version
  sox_version=$(sox --version 2>&1 | head -n 1 || echo "SoX version not found")
  local python_version
  python_version=$(python3 --version 2>&1 || echo "Python3 version not found")

  local system_info_json
  system_info_json=$(jq -n \
    --arg pt "$(date +%s)" \
    --arg proc "$(uname -m)" \
    --arg os_name "$(uname -s)" \
    --arg sv "$sox_version" \
    --arg pv "$python_version" \
    --arg td "$TEMP_DIR" \
    --arg lf "$LOG_FILE" \
    '{processing_timestamp: $pt, processor: $proc, os: $os_name, sox_version: $sv, python_version: $pv, temp_dir: $td, log_file: $lf}')


  # Combine all information using jq
  jq -n \
    --arg exec_id "$execution_id" \
    --arg out_file "$output_file" \
    --argjson final_analysis "$final_analysis_content" \
    --argjson sys_info "$system_info_json" \
    --argjson stems_json "$stems_info_json" \
    --argjson quality "$(validate_master_quality "$output_file")" \
    '{
       execution_id: $exec_id,
       timestamp_completed_iso: now | todate,
       output_file: $out_file,
       final_audio_analysis: $final_analysis,
       system_info: $sys_info,
       stems_processed_info: ($stems_json | fromjson? // []),
       overall_quality_score: ($quality | tonumber),
       processing_status: "completed"
    }' > "$report_file"

  success "Comprehensive report generated: $report_file"
  echo "$report_file"
}


# Main execution function
main() {
  local stems_json_input="$1" # Renamed for clarity
  local reference_track_input="${2:-}" # Renamed
  local execution_id="${3:-$(date +%s%N | sha256sum | head -c 16)}" # More unique default ID
  local target_lufs_main="${4:-$TARGET_LUFS}" # Renamed

  log "Starting enhanced mix and master process (v2.0)"
  log "Execution ID: $execution_id"
  log "Target LUFS: $target_lufs_main"
  send_websocket_update "mixing_started" "initializing" "{\"execution_id\": \"$execution_id\"}"


  check_dependencies # Check dependencies first

  log "Parsing and validating stems..."
  local stems_array_string # Will store newline-separated validated stem paths
  stems_array_string=$(parse_and_validate_stems "$stems_json_input")

  local stem_count
  stem_count=$(echo -n "$stems_array_string" | grep -c '^') # Count non-empty lines

  if [[ $stem_count -eq 0 ]]; then
      warning "No valid stems to process after validation. Exiting."
      # Output a JSON error for n8n
      jq -n --arg exec_id "$execution_id" --arg err_msg "No valid stems provided or found."          '{execution_id: $exec_id, success: false, error: $err_msg, file: null, report: null}'
      send_websocket_update "mixing_error" "no_valid_stems" "{\"execution_id\": \"$execution_id\"}"
      exit 0 # Exit gracefully for n8n if no stems
  fi
  info "Processing $stem_count stems for mixing."

  local mix_output_file="$TEMP_DIR/mix_${execution_id}.wav" # Temporary mix output
  local final_master_file="/data/mastered/master_${execution_id}.wav" # Final output in data/mastered

  # Ensure output directory for final master exists
  mkdir -p "$(dirname "$final_master_file")"


  mix_stems_parallel "$stems_array_string" "$mix_output_file"
  master_audio_advanced "$mix_output_file" "$reference_track_input" "$final_master_file" "$target_lufs_main"

  # Prepare stems info for report (convert newline string to JSON array)
  local stems_info_report_json
  stems_info_report_json=$(echo "$stems_array_string" | jq -R . | jq -s .)


  local report_file_path # Renamed
  report_file_path=$(generate_detailed_report "$final_master_file" "$execution_id" "$stems_info_report_json")

  local final_quality_score # Renamed
  final_quality_score=$(validate_master_quality "$final_master_file")

  send_websocket_update "mixing_complete" "success" "{"execution_id": "$execution_id", "file": "$final_master_file", "quality_score": $final_quality_score}"


  # Output JSON for n8n
  jq -n \
     --arg file "$final_master_file" \
     --arg exec_id "$execution_id" \
     --arg report "$report_file_path" \
     --argjson quality "$final_quality_score" \
     --argjson target_lufs_val "$target_lufs_main" \
     --argjson sc "$stem_count" \
     '{
         file: $file,
         execution_id: $exec_id,
         report_file: $report, # Changed key to report_file for clarity
         success: true,
         quality_score: $quality,
         processing_timestamp_completed: now, # Add completion timestamp
         specs: {
            target_lufs: $target_lufs_val,
            sample_rate: '"$SAMPLE_RATE"', # Use variables
            bit_depth: '"$BIT_DEPTH"',
            output_format: "wav"
         },
         stems_processed_count: $sc,
         script_version: "2.0_advanced"
     }'

  success "Enhanced mix and master process completed successfully for $execution_id."
}

# Script entry point
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # Strict mode for arguments: require at least stems_json
    if [[ $# -lt 1 ]]; then
        echo -e "${RED}Usage: $0 <stems_json_string> [reference_track_path] [execution_id] [target_lufs]${NC}" >&2
        echo "Example: $0 '[\"/path/to/bass.wav\",\"/path/to/drums.wav\"]' '/path/to/ref.wav' 'exec123' -13" >&2
        exit 1
    fi
    main "$@"
fi
