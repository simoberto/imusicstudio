# AI Music Studio - API Reference

This document provides detailed information about the API endpoints available in AI Music Studio. All endpoints are accessed via the Nginx reverse proxy, which routes requests to the n8n backend workflows.

**Base URL for API requests (via Nginx):** `/api/mcp/` (e.g., `https://yourdomain.com/api/mcp/`)

## 1. Generate Melody/Stem

Generates a single audio stem for a specific instrument based on a text prompt and other parameters.

-   **Endpoint**: `POST /api/mcp/generate-melody`
-   **Content-Type**: `application/json`

**Request Body:**

```json
{
  "instrument": "bass",
  "prompt": "deep funky bass line, 120 BPM, E minor, groovy",
  "duration": 30,
  "temperature": 1.0,
  "topK": 250,
  "quality_threshold": 70
}
```

**Parameters:**

| Parameter           | Type    | Required | Default | Description                                                                                                | Example Values                                  |
| :------------------ | :------ | :------- | :------ | :--------------------------------------------------------------------------------------------------------- | :---------------------------------------------- |
| `instrument`        | String  | Yes      |         | Target instrument.                                                                                         | `bass`, `drums`, `guitar`, `piano`, `synth`, `vocal`, `other` |
| `prompt`            | String  | Yes      |         | Textual description of the desired music/sound. Include style, mood, BPM, key if relevant.                 | "energetic rock guitar solo in A minor"         |
| `duration`          | Integer | No       | 30      | Desired duration of the audio stem in seconds. Min: 5, Max: 300 (MusicGen typically optimal < 30-60s per pass). | `15`, `30`, `60`                                |
| `temperature`       | Float   | No       | 1.0     | Controls randomness/creativity. Higher values = more diverse/surprising. Range: 0.1 - 2.0.                  | `0.8`, `1.0`, `1.25`                            |
| `topK`              | Integer | No       | 250     | Nucleus sampling parameter. Reduces vocabulary to top K tokens. Range: 50 - 500.                           | `200`, `250`, `300`                             |
| `quality_threshold` | Integer | No       | 70      | Minimum quality score (0-100) for the generated audio. The system may retry if below this.                 | `60`, `70`, `85`                                |

**Success Response (200 OK):**

The n8n workflow is `onReceived`, so it will respond immediately with a 200 OK if the request is accepted. The actual result of the generation will be available asynchronously (e.g., via WebSocket notification or by polling if such an endpoint is implemented). The initial response might just confirm receipt.

However, if the n8n workflow were changed to respond *after* generation (synchronous, not recommended for long tasks), it would look like this:

```json
{
  "success": true,
  "file": "/data/stems/xxxxxxxx-xxxx_bass.wav", // Path accessible within the Docker volume structure
  "instrument": "bass",
  "duration": 30.05, // Actual generated duration
  "sample_rate": 44100,
  "generation_time": 25.67, // Time in seconds
  "quality_score": 88.2,
  "executionId": "xxxxxxxx-xxxx",
  "metadata_file": "xxxxxxxx-xxxx_bass.json" // Path to a JSON file with more details
}
```
*Actual synchronous response structure depends on the final "Format Response" node in the n8n workflow.*

**Error Responses:**

-   `400 Bad Request`: If required parameters are missing or invalid (e.g., invalid instrument type).
    ```json
    {
      "success": false,
      "error": "Missing required parameters: instrument and prompt",
      "executionId": "xxxxxxxx-xxxx"
    }
    ```
-   `500 Internal Server Error`: If an error occurs during the generation process within the backend.
    ```json
    {
      "success": false,
      "error": "GPU out of memory during generation", // Or other specific error
      "details": "Optional stack trace or more info...",
      "executionId": "xxxxxxxx-xxxx"
    }
    ```

## 2. Mix & Master Stems

Mixes multiple audio stems and applies mastering processing to produce a final track.

-   **Endpoint**: `POST /api/mcp/mix-master`
-   **Content-Type**: `application/json`

**Request Body:**

```json
{
  "stems": [
    "/data/stems/execId1_bass.wav",
    "/data/stems/execId2_drums.wav",
    "/data/stems/execId3_synth.wav"
  ],
  "targetLUFS": -14,
  "referenceTrack": "/data/references/my_reference_track.wav", // Optional
  "outputFormat": "wav" // Optional: "wav", "mp3", "flac"
}
```

**Parameters:**

| Parameter        | Type    | Required | Default | Description                                                                                             |
| :--------------- | :------ | :------- | :------ | :------------------------------------------------------------------------------------------------------ |
| `stems`          | Array   | Yes      |         | An array of strings, where each string is the absolute path (within the `/data` volume) to an input stem file. |
| `targetLUFS`     | Float   | No       | -14.0   | Target Integrated Loudness (LUFS) for mastering.                                                        |
| `referenceTrack` | String  | No       | `null`  | Optional path to a reference track for AI-powered mastering (e.g., Matchering).                         |
| `outputFormat`   | String  | No       | `wav`   | Desired output format for the final track.                                                              |

**Success Response (200 OK - Asynchronous):**

Similar to generate-melody, the initial response confirms request receipt. The final mixed/mastered track details would be sent via WebSocket or another mechanism. If synchronous:

```json
{
  "success": true,
  "file": "/data/mixed/master_xxxxxxxx-xxxx.wav", // Path to the final mixed/mastered track
  "execution_id": "xxxxxxxx-xxxx",
  "report_file": "/data/reports/mix_report_xxxxxxxx-xxxx.json", // Path to the mixing analysis report
  "quality_score": 92.5, // Overall quality score of the mix/master
  "processing_timestamp_completed": "YYYY-MM-DDTHH:MM:SSZ",
  "specs": {
    "target_lufs": -14.0,
    "sample_rate": 44100,
    "bit_depth": 16,
    "output_format": "wav"
  },
  "stems_processed_count": 3
}
```

**Error Responses:**

-   `400 Bad Request`: If `stems` array is missing, empty, or contains invalid paths.
    ```json
    {
      "success": false,
      "error": "`stems` parameter is required and must be a non-empty array of valid file paths."
    }
    ```
-   `500 Internal Server Error`: If mixing/mastering process fails.
    ```json
    {
      "success": false,
      "error": "Mixing process failed: Could not process one of the stems."
    }
    ```

## 3. Full Track Composition

Generates a complete musical track based on style, BPM, key, and other parameters. This involves generating multiple stems and then mixing them.

-   **Endpoint**: `POST /api/mcp/compose-track`
-   **Content-Type**: `application/json`

**Request Body:**

```json
{
  "style": "electronic",
  "bpm": 128,
  "key": "A minor",
  "duration": 120,
  "complexity": 7,
  "title": "Cybernetic Dreams",
  "instruments": ["bass", "drums", "lead_synth", "pad_synth", "fx"] // Optional: override default instruments for style
}
```

**Parameters:**

| Parameter     | Type    | Required | Default                                  | Description                                                                                                | Example Values                                |
| :------------ | :------ | :------- | :--------------------------------------- | :--------------------------------------------------------------------------------------------------------- | :-------------------------------------------- |
| `style`       | String  | No       | `electronic`                             | Musical style/genre.                                                                                       | `electronic`, `rock`, `jazz`, `ambient`, `hip-hop` |
| `bpm`         | Integer | No       | 120                                      | Beats Per Minute. Range: 60 - 200.                                                                         | `90`, `128`, `140`                              |
| `key`         | String  | No       | `C major`                                | Musical key (e.g., "C major", "A minor").                                                                  | `A minor`, `G# major`, `F Dorian`             |
| `duration`    | Integer | No       | 60                                       | Desired total duration of the track in seconds. Range: 30 - 300.                                           | `60`, `120`, `180`                              |
| `complexity`  | Integer | No       | 5                                        | Arrangement complexity (1-10). Higher values may result in more variation and richer harmonies.              | `3`, `5`, `8`                                   |
| `title`       | String  | No       | `AI [style] Track [timestamp]`           | Desired title for the track.                                                                               | "Cosmic Journey"                              |
| `instruments` | Array   | No       | Based on `style` (see n8n workflow logic) | Optional array of strings to specify exact instruments. Overrides style defaults.                          | `["kick", "snare", "sub_bass", "arp_synth"]`  |

**Success Response (200 OK - Asynchronous):**

Initial response confirms receipt. Final composition details via WebSocket/other. If synchronous:

```json
{
  "success": true,
  "executionId": "xxxxxxxx-xxxx",
  "composition": {
    "title": "Cybernetic Dreams",
    "file": "/data/mixed/master_composition_xxxxxxxx-xxxx.wav", // Path to the final composed track
    "report_file": "/data/reports/mix_report_composition_xxxxxxxx-xxxx.json",
    "quality_score": 90.1,
    "duration": 120,
    "bpm": 128,
    "key": "A minor",
    "style": "electronic",
    "stems_generated_paths": [ // List of paths for the individual stems created
      "/data/stems/execId_stem1_bass.wav",
      "/data/stems/execId_stem2_drums.wav",
      // ... more stems
    ],
    "all_stems_succeeded": true // Indicates if all requested stems were generated successfully
  }
}
```

**Error Responses:**

-   `400 Bad Request`: Invalid parameters (e.g., BPM out of range).
    ```json
    {
      "success": false,
      "error": "Invalid parameter: BPM must be between 60 and 200."
    }
    ```
-   `500 Internal Server Error`: If any part of the composition process (stem generation or mixing) fails.
    ```json
    {
      "success": false,
      "error": "Full composition failed: Error during stem generation phase."
    }
    ```

## 4. Health Check

Checks the health/status of the n8n service (which underlies the API).

-   **Endpoint**: `GET /api/healthz` (Note: Nginx configuration routes this to n8n's `/healthz`)
-   **Content-Type**: Not applicable

**Success Response (200 OK):**

```json
{
  "message": "ok",
  "uptime": 12345.67, // Uptime in seconds
  "version": "1.88.0" // n8n version
}
```

**Error Responses:**

-   `503 Service Unavailable`: If n8n service is down or unhealthy.

## General Notes

-   **Asynchronous Operations**: Endpoints like `generate-melody`, `mix-master`, and `compose-track` involve potentially long-running processes. The n8n workflows are configured with `responseMode: "onReceived"`, meaning they will return an HTTP 200 OK immediately upon receiving the request if it's valid, and then process the task in the background. The actual results (e.g., file paths, status updates) should be communicated back to the client via another channel, such as:
    -   **WebSockets**: The frontend connects to the WebSocket server (`websocket/server.js`) for real-time progress and completion notifications.
    -   **Polling**: The client could poll a status endpoint (not defined in this API doc, but could be added) using the `executionId` returned in the initial response.
-   **File Paths**: File paths returned in API responses (e.g., `/data/stems/...`) are relative to the Docker volume structure accessible by the services. The Nginx service is configured to serve files from a specific sub-directory of `/data` (e.g., `/data/public`) via `/api/audio/` and `/api/download/` endpoints.
-   **Error Handling**: API errors should return a JSON body with `{"success": false, "error": "Error message"}`. HTTP status codes should reflect the nature of the error (4xx for client errors, 5xx for server errors).
-   **Authentication/Authorization**: These endpoints are currently unauthenticated. In a production system, appropriate authentication (e.g., API keys, JWT tokens) should be implemented, potentially at the Nginx or n8n level.
