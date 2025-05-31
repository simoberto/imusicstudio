# AI Music Studio - Basic Usage Examples

This guide provides basic examples of how to interact with the AI Music Studio API using `curl`. These examples assume the application is running locally and Nginx is listening on `http://localhost` (or `http://localhost:80`). If you've mapped Nginx to a different port, adjust the URLs accordingly.

For production, replace `http://localhost` with your actual domain (e.g., `https://yourdomain.com`).

## Prerequisites

-   AI Music Studio application stack is running (use `LAUNCH_SCRIPT.sh` or `docker-compose up -d`).
-   `curl` command-line tool is installed.
-   `jq` command-line tool is installed for pretty-printing JSON responses (optional, but recommended).

## 1. Generate a Single Audio Stem

This example demonstrates how to generate a short bass guitar stem.

**Request:**

```bash
curl -X POST http://localhost/api/mcp/generate-melody \
     -H "Content-Type: application/json" \
     -d '{
       "instrument": "bass",
       "prompt": "slow and deep reggae bass line, 100 BPM, G minor, 8 bars",
       "duration": 15,
       "temperature": 0.9,
       "quality_threshold": 65
     }' | jq .
```

**Explanation:**

-   `POST http://localhost/api/mcp/generate-melody`: Sends a POST request to the melody generation endpoint.
-   `-H "Content-Type: application/json"`: Specifies that the request body is JSON.
-   `-d '{...}'`: The JSON payload containing the generation parameters:
    -   `instrument: "bass"`: We want a bass sound.
    -   `prompt: "..."`: A detailed description of the desired bass line.
    -   `duration: 15`: Requesting a 15-second audio clip.
    -   `temperature: 0.9`: Sets the generation creativity (slightly less than default 1.0 for more predictability).
    -   `quality_threshold: 65`: The system will try to ensure the output meets at least this quality score.
-   `| jq .`: Pipes the JSON response to `jq` for pretty-printing (optional).

**Expected Initial Response (Asynchronous):**

Since n8n workflows are set to `onReceived`, you'll get an immediate acknowledgment. The actual content of this initial ACK can vary but usually indicates the request was accepted for processing.

```json
{
  "message": "Webhook received and workflow started.",
  "executionId": "xxxxxxxx-xxxx" // Example: n8n might return the execution ID
}
```

**Actual Result (Asynchronous):**

The generation happens in the background. You would typically receive a WebSocket notification when the process is complete, containing details like this:

```json
// This is what the final data would look like, delivered via WebSocket or another mechanism
{
  "success": true,
  "file": "/data/stems/xxxxxxxx-xxxx_bass.wav", // Path within Docker volume
  "instrument": "bass",
  "duration": 15.02, // Actual generated duration
  "sample_rate": 44100,
  "generation_time": 18.5, // Time in seconds for this step
  "quality_score": 75.0,
  "executionId": "xxxxxxxx-xxxx", // Corresponds to the initial execution
  "metadata_file": "xxxxxxxx-xxxx_bass.json" // Path to a JSON file with more details
}
```

The generated file (`xxxxxxxx-xxxx_bass.wav`) would be saved inside the Docker `data/stems/` volume. You can access it via Nginx if configured (e.g., `http://localhost/api/audio/stems/xxxxxxxx-xxxx_bass.wav`).

## 2. Mix Multiple Stems

This example shows how to send a list of existing stem files (presumably generated in previous steps or uploaded) to be mixed and mastered.

**Prerequisite**: You need at least two audio stem files (e.g., `.wav`) accessible by the application within its `/data/stems/` directory (or other `/data/...` subdirectories known to the system). Let's assume you have:
-   `/data/stems/my_awesome_bass.wav`
-   `/data/stems/my_killer_drums.wav`

**Request:**

```bash
curl -X POST http://localhost/api/mcp/mix-master \
     -H "Content-Type: application/json" \
     -d '{
       "stems": [
         "/data/stems/my_awesome_bass.wav",
         "/data/stems/my_killer_drums.wav"
       ],
       "targetLUFS": -14.0,
       "outputFormat": "wav"
     }' | jq .
```

**Explanation:**

-   `stems`: An array of full paths *as seen by the containers* (i.e., starting with `/data/`).
-   `targetLUFS`: Desired loudness for the final master.
-   `outputFormat`: The format for the mixed track (e.g., wav, mp3).

**Expected Initial Response (Asynchronous):**

```json
{
  "message": "Webhook received and workflow started.",
  "executionId": "yyyyyyyy-yyyy"
}
```

**Actual Result (Asynchronous, via WebSocket or other mechanism):**

```json
// Final data structure
{
  "success": true,
  "file": "/data/mixed/master_yyyyyyyy-yyyy.wav", // Path to the final mixed/mastered track
  "execution_id": "yyyyyyyy-yyyy",
  "report_file": "/data/reports/mix_report_yyyyyyyy-yyyy.json", // Path to the mixing analysis report
  "quality_score": 89.0, // Overall quality score of the mix/master
  "specs": {
    "target_lufs": -14.0,
    "sample_rate": 44100,
    "bit_depth": 16,
    "output_format": "wav"
  },
  "stems_processed_count": 2
}
```
The mixed file (`master_yyyyyyyy-yyyy.wav`) will be in the `data/mixed/` volume.

## 3. Compose a Full Track

This example demonstrates composing a short electronic track from scratch.

**Request:**

```bash
curl -X POST http://localhost/api/mcp/compose-track \
     -H "Content-Type: application/json" \
     -d '{
       "style": "electronic",
       "bpm": 130,
       "key": "C minor",
       "duration": 45,
       "complexity": 6,
       "title": "My First AI Jam"
     }' | jq .
```

**Explanation:**

-   Parameters like `style`, `bpm`, `key`, `duration` (for the final track), `complexity`, and an optional `title` guide the AI composer.

**Expected Initial Response (Asynchronous):**

```json
{
  "message": "Webhook received and workflow started.",
  "executionId": "zzzzzzzz-zzzz"
}
```

**Actual Result (Asynchronous, via WebSocket or other mechanism):**

```json
// Final data structure
{
  "success": true,
  "executionId": "zzzzzzzz-zzzz",
  "composition": {
    "title": "My First AI Jam",
    "file": "/data/mixed/master_composition_zzzzzzzz-zzzz.wav", // Path to the final composed track
    "report_file": "/data/reports/mix_report_composition_zzzzzzzz-zzzz.json",
    "quality_score": 85.5,
    "duration": 45,
    "bpm": 130,
    "key": "C minor",
    "style": "electronic",
    "stems_generated_paths": [ // List of paths for the individual stems created
      "/data/stems/execId_stem_abc_bass.wav",
      "/data/stems/execId_stem_def_drums.wav",
      "/data/stems/execId_stem_ghi_synth.wav"
      // ... other stems
    ],
    "all_stems_succeeded": true // Indicates if all requested stems were generated successfully
  }
}
```
The composed track will be in `data/mixed/`, and the individual stems created during the process will be in `data/stems/`.

## Checking API Health

You can check the health of the underlying n8n service (which powers the API).

**Request:**

```bash
curl http://localhost/api/healthz | jq .
```

**Expected Response:**

```json
{
  "message": "ok",
  "uptime": 3456.78, # Example uptime in seconds
  "version": "1.88.0" # Example n8n version
}
```

These examples should help you get started with the basic functionalities of the AI Music Studio API. For more advanced scenarios and parameter details, please refer to the `api_reference.md`. Remember that file paths like `/data/stems/...` are internal to the Docker environment; how these are accessed externally depends on your Nginx setup (e.g., via `/api/audio/...` or `/api/download/...` URLs).
