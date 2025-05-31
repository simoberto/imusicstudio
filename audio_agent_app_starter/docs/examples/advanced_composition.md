# AI Music Studio - Advanced Composition Examples

This guide provides examples of more advanced composition techniques using the AI Music Studio API. These examples build upon the basic API calls and demonstrate how to achieve more complex or specific results.

Refer to `basic_usage.md` for prerequisites and simpler examples. All API calls are assumed to be `POST` requests with `Content-Type: application/json`.

## 1. Layered Composition with Specific Instruments and Durations

Instead of relying entirely on the `/api/mcp/compose-track` endpoint's default instrument selection and stem generation logic, you can generate individual stems with precise control and then mix them. This gives you more granular control over each element.

**Scenario**: Create a 60-second electronic track with a specific structure:
-   Bass: 60 seconds, deep and evolving.
-   Drums: 60 seconds, complex hi-hat patterns.
-   Lead Synth: 30 seconds, appearing in the middle.
-   Ambient Pad: 60 seconds, atmospheric.

**Step 1: Generate each stem individually via `/api/mcp/generate-melody`**

*Generate Bass:*
```bash
curl -X POST http://localhost/api/mcp/generate-melody \
     -d '{
       "instrument": "bass",
       "prompt": "deep evolving sub bass line for electronic track, 125 BPM, A minor, atmospheric",
       "duration": 60, # Full duration
       "temperature": 0.95,
       "quality_threshold": 75
     }' # Store the returned executionId and file path (e.g., bass_exec_id, /data/stems/bass_exec_id_bass.wav)
```

*Generate Drums:*
```bash
curl -X POST http://localhost/api/mcp/generate-melody \
     -d '{
       "instrument": "drums",
       "prompt": "intricate electronic drum beat with complex hi-hat patterns and a solid kick, 125 BPM",
       "duration": 60, # Full duration
       "temperature": 1.0,
       "quality_threshold": 70
     }' # Store exec_id and file_path (e.g., drums_exec_id, /data/stems/drums_exec_id_drums.wav)
```

*Generate Lead Synth (shorter, for specific part of the track):*
```bash
# This synth will be manually placed or faded in/out in a DAW if further editing is done.
# For simple mixing, its shorter duration means it will only play for that long.
curl -X POST http://localhost/api/mcp/generate-melody \
     -d '{
       "instrument": "synth",
       "prompt": "bright energetic lead synth melody, arpeggiated, electronic, 125 BPM, A minor",
       "duration": 30,
       "temperature": 1.05,
       "quality_threshold": 70
     }' # Store exec_id and file_path (e.g., lead_exec_id, /data/stems/lead_exec_id_synth.wav)
```

*Generate Ambient Pad:*
```bash
curl -X POST http://localhost/api/mcp/generate-melody \
     -d '{
       "instrument": "other", # Using 'other' for a pad-like sound
       "prompt": "evolving atmospheric ambient pad, lush textures, A minor, for electronic track background",
       "duration": 60,
       "temperature": 0.9,
       "quality_threshold": 70
     }' # Store exec_id and file_path (e.g., pad_exec_id, /data/stems/pad_exec_id_other.wav)
```

**Step 2: Wait for all stems to be generated (monitor via WebSockets or by checking for file existence/API status if available).**

**Step 3: Mix the generated stems using `/api/mcp/mix-master`**

Assume the generated files are:
-   `/data/stems/bass_exec_id_bass.wav`
-   `/data/stems/drums_exec_id_drums.wav`
-   `/data/stems/lead_exec_id_synth.wav` (This is 30s long)
-   `/data/stems/pad_exec_id_other.wav`

```bash
curl -X POST http://localhost/api/mcp/mix-master \
     -d '{
       "stems": [
         "/data/stems/bass_exec_id_bass.wav",
         "/data/stems/drums_exec_id_drums.wav",
         "/data/stems/lead_exec_id_synth.wav",
         "/data/stems/pad_exec_id_other.wav"
       ],
       "targetLUFS": -13.5, # Slightly different target
       "outputFormat": "flac" # Higher quality output
     }' | jq .
```
**Note on Stem Durations for Mixing**: The `mix_master.sh` script (using SoX) will typically mix files based on their actual lengths. If stems have different durations, the shorter ones will end while longer ones continue. The overall length of the mixed track will be determined by the longest stem. For precise arrangement (e.g., having the 30s synth start at 0:15), you would need to either:
    a.  Generate the synth lead with 15s of silence at the beginning (hard to do with current prompt system).
    b.  Use a Digital Audio Workstation (DAW) after generating stems to arrange them on a timeline.
    c.  If LMMS rendering is used for mixing (not just SoX via `mix_master.sh`), the LMMS project could be programmatically constructed to place stems at specific times (this is advanced and not covered by the current `lmms_render.py` script's public API).

## 2. Using a Reference Track for AI Mastering

The `/api/mcp/mix-master` endpoint can optionally take a `referenceTrack` if you have Matchering or a similar AI mastering tool integrated into `mix_master.sh`.

**Scenario**: You have a mixdown (`my_cool_mix.wav`) and want its mastering style to be similar to a commercial track (`reference_song.wav`).

**Step 1: Ensure your mix and reference track are accessible within the `/data` volume.**
   - e.g., `/data/mixes/my_cool_mix.wav`
   - e.g., `/data/references/reference_song.wav`

**Step 2: Call the mix-master endpoint (can be used for mastering a single track too)**
   If `my_cool_mix.wav` is already a complete mix, you can pass it as a single item in the `stems` array.
```bash
curl -X POST http://localhost/api/mcp/mix-master \
     -d '{
       "stems": ["/data/mixes/my_cool_mix.wav"], # Your pre-mixed track
       "referenceTrack": "/data/references/reference_song.wav",
       "targetLUFS": -10 # Target LUFS might be less critical if reference matching is strong
     }' | jq .
```
The `mix_master.sh` script (if it supports Matchering) will attempt to apply the sonic characteristics (EQ curve, dynamics, stereo width) of `reference_song.wav` to `my_cool_mix.wav`.

## 3. Iterative Refinement and Overdubbing (Conceptual)

While the API doesn't directly support "overdubbing" in a DAW sense, you can achieve iterative refinement:

1.  **Generate a base track or a few core stems** using `/api/mcp/compose-track` or by generating stems individually.
    ```json
    // Initial composition request for a backing track
    {
      "style": "lofi hiphop", "bpm": 85, "key": "C minor",
      "duration": 60, "complexity": 4, "title": "Lofi Base",
      "instruments": ["drums", "bass", "piano_chords"]
    }
    ```
    Let's say this produces `/data/mixed/lofi_base_mix.wav`.

2.  **Listen and decide what's missing.** Perhaps you want a saxophone melody on top.

3.  **Generate the new "overdub" stem** with a prompt that considers the existing track.
    ```bash
    curl -X POST http://localhost/api/mcp/generate-melody \
         -d '{
           "instrument": "other", // Or 'sax' if available and distinct
           "prompt": "smooth jazz saxophone melody for lofi hiphop track in C minor at 85 BPM, to fit over existing drums, bass, and piano chords",
           "duration": 50, // Slightly shorter for variation, or match base track
           "temperature": 0.9
         }'
    ```
    This generates, for example, `/data/stems/sax_melody.wav`.

4.  **Mix the original base track with the new stem.**
    ```bash
    curl -X POST http://localhost/api/mcp/mix-master \
         -d '{
           "stems": [
             "/data/mixed/lofi_base_mix.wav", // The first version
             "/data/stems/sax_melody.wav"    // The new "overdub"
           ],
           "targetLUFS": -14
         }' | jq .
    ```
    This produces a new mix: `/data/mixed/master_final_lofi_with_sax.wav`.

This process can be repeated to layer more parts. The key is crafting prompts for new stems that are contextually aware of the existing music.

## 4. Using Different Models for Different Stems (Advanced)

If your `musicgen_stem.py` script and n8n workflow for `generate-melody` can accept a `model` parameter (e.g., `facebook/musicgen-small`, `facebook/musicgen-medium`, `facebook/musicgen-large`), you could use different models for different instruments.

**Scenario**: Use a larger model for a complex piano part and a smaller, faster model for a simple bassline.

*Generate Piano (Large Model):*
```bash
curl -X POST http://localhost/api/mcp/generate-melody \
     -d '{
       "instrument": "piano",
       "prompt": "intricate classical piano piece, expressive and dynamic",
       "duration": 30,
       "model": "facebook/musicgen-large" # Hypothetical parameter
     }'
```

*Generate Bass (Small Model):*
```bash
curl -X POST http://localhost/api/mcp/generate-melody \
     -d '{
       "instrument": "bass",
       "prompt": "simple root note bass line",
       "duration": 30,
       "model": "facebook/musicgen-small" # Hypothetical parameter
     }'
```
Then mix these stems as usual.

**Note**: This requires the `generate-melody` API endpoint and the underlying `musicgen_stem.py` script to be modified to accept and use a `model` parameter. The current `musicgen_stem.py` in the plan takes a `--model` argument, so the n8n "Execute Command" node for it would need to be updated to pass this.

These examples illustrate how the provided API endpoints can be combined or used with more specific parameters to achieve more complex and controlled music generation results.
