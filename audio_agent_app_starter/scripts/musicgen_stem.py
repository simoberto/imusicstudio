#!/usr/bin/env python3
"""
Advanced MusicGen-Stem Generator with Robust Error Handling and
Optimization
"""

import argparse
import gc
import json
import logging
import os
import sys
import time
import traceback
import psutil
from contextlib import contextmanager
from pathlib import Path
from typing import Optional, Tuple, Dict, Any
import warnings

import torch
import torchaudio
import numpy as np
from audiocraft.models import MusicGen
# from audiocraft.data.audio_utils import convert_audio # This import seems unused in the provided script

# Suppress warnings
warnings.filterwarnings('ignore', category=UserWarning)
warnings.filterwarnings('ignore', category=FutureWarning)

# Configure logging
logging.basicConfig(
  level=logging.INFO,
  format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

class GPUMemoryManager:
   """Advanced GPU memory management with monitoring"""

   def __init__(self):
    self.device = 'cuda' if torch.cuda.is_available() else 'cpu'
    self.initial_memory = None
    if self.device == 'cuda':
        self.initial_memory = torch.cuda.memory_allocated()


   @contextmanager
   def managed_memory(self):
    """Context manager for automatic memory cleanup"""
    try:
       if self.device == 'cuda':
          torch.cuda.empty_cache()
          torch.cuda.synchronize()
          # It's better to record initial memory inside the context if it's meant to track memory for that block
          # self.initial_memory = torch.cuda.memory_allocated()
       yield
    finally:
       if self.device == 'cuda':
          torch.cuda.empty_cache()
          torch.cuda.synchronize()
          gc.collect()

          # Force cleanup if memory usage is high compared to the start of this specific block
          # This logic might be tricky if initial_memory is set in __init__ and not updated per block.
          # For simplicity, the original logic is kept, but this is a point of potential refinement.
          if self.initial_memory is not None: # Ensure initial_memory was set
            current_memory = torch.cuda.memory_allocated()
            if current_memory > self.initial_memory * 1.5: # Check against memory at init or last major cleanup
                logger.warning("High memory usage detected, forcing cleanup")
                self._force_cleanup()


   def _force_cleanup(self):
    """Force aggressive memory cleanup"""
    if self.device == 'cuda':
       torch.cuda.empty_cache()
       torch.cuda.synchronize()
       # Clear all caches
       for i in range(torch.cuda.device_count()):
          with torch.cuda.device(i):
              torch.cuda.empty_cache()

   def get_memory_stats(self) -> Dict[str, float]:
    """Get current memory statistics"""
    if self.device == 'cuda':
       return {
          'allocated': torch.cuda.memory_allocated() / 1024**3, # GB
          'reserved': torch.cuda.memory_reserved() / 1024**3, # GB
          'max_allocated': torch.cuda.max_memory_allocated() / 1024**3, # GB
       }
    return {'cpu_percent': psutil.virtual_memory().percent}

class MusicGenStemGenerator:
   """Advanced MusicGen-Stem generator with robustness features"""

   def __init__(self, model_name: str = 'facebook/musicgen-medium'):
    self.model_name = model_name
    self.model = None
    self.memory_manager = GPUMemoryManager()
    self.device = self.memory_manager.device
    self.generation_history = []

    logger.info(f"Initialized generator with device: {self.device}")

   def load_model(self, max_retries: int = 3) -> bool:
     """Load model with retry logic and error handling"""
     for attempt in range(max_retries):
        try:
           with self.memory_manager.managed_memory():
             logger.info(f"Loading model: {self.model_name} (attempt {attempt + 1})")

             # Load model with optimizations
             self.model = MusicGen.get_pretrained(self.model_name)
             self.model.to(self.device)

             # Optimize for inference
             if hasattr(self.model, 'eval'):
                self.model.eval()

             # Enable optimizations
             if self.device == 'cuda':
                torch.backends.cudnn.benchmark = True
                torch.backends.cudnn.deterministic = False

                # Enable mixed precision if supported
                try:
                   # This is a context manager, should be used with `with` or applied if it modifies state
                   # For now, assuming it sets a global state or is not strictly necessary for basic FP16
                   # torch.cuda.amp.autocast(enabled=True)
                   logger.info("Mixed precision potentially enabled (if model supports it)")
                except Exception:
                   logger.warning("Mixed precision not available or applicable")

             # Warm up model
             self._warmup_model()

             logger.info("Model loaded successfully")
             # Update initial memory after successful load and warmup for more accurate tracking by GPUMemoryManager
             if self.device == 'cuda':
                 self.memory_manager.initial_memory = torch.cuda.memory_allocated()
             return True

        except Exception as e:
          logger.error(f"Model loading attempt {attempt + 1} failed: {e}")
          if attempt < max_retries - 1:
             time.sleep(2 ** attempt) # Exponential backoff
             self._cleanup_failed_load()
          else:
             logger.error(f"Failed to load model after {max_retries} attempts")
             return False
     return False # Should not be reached if loop completes

   def _warmup_model(self):
    """Warm up model with a short generation"""
    try:
       logger.info("Warming up model...")
       if self.model is None:
           logger.warning("Model not loaded, skipping warmup.")
           return
       with torch.no_grad():
         self.model.set_generation_params(duration=1) # Short duration for warmup
         _ = self.model.generate(['test warmup'], progress=False)
       logger.info("Model warmup completed")
    except Exception as e:
       logger.warning(f"Model warmup failed: {e}")

   def _cleanup_failed_load(self):
    """Clean up after failed model load"""
    if self.model:
       del self.model
       self.model = None
    gc.collect()
    if self.device == 'cuda':
       torch.cuda.empty_cache()

   def generate_stem(
     self,
     prompt: str,
     instrument: str = 'bass',
     duration: int = 30,
     temperature: float = 1.0,
     top_k: int = 250,
     top_p: float = 0.0, # top_p is part of MusicGen params but not used in the script's set_generation_params
     seed: Optional[int] = None
   ) -> Optional[Tuple[torch.Tensor, int]]:
     """Generate stem with advanced parameters and error handling"""

     if self.model is None:
        if not self.load_model():
           return None

     generation_id = f"{instrument}_{int(time.time())}"

     try:
        with self.memory_manager.managed_memory():
          # Set seed for reproducibility
          if seed is not None:
             torch.manual_seed(seed)
             if self.device == 'cuda':
                torch.cuda.manual_seed_all(seed) # Use manual_seed_all for all GPUs

          # Enhanced prompt
          enhanced_prompt = self._enhance_prompt(prompt, instrument)
          logger.info(f"Generating {generation_id}: '{enhanced_prompt}' for {duration}s")

          # Monitor memory before generation
          mem_stats_before = self.memory_manager.get_memory_stats()
          logger.debug(f"Memory before generation: {mem_stats_before}")

          # Set generation parameters
          self.model.set_generation_params(
            duration=duration,
            temperature=temperature,
            top_k=top_k,
            # top_p=top_p, # top_p is available in MusicGen
            # cfg_coef=3.0, # Example of another common param, not used here
          )

          # Generate with progress tracking
          start_time = time.time()

          # Autocast for mixed precision if on CUDA
          autocast_enabled = self.device == 'cuda' # and self.model supports fp16
          with torch.cuda.amp.autocast(enabled=autocast_enabled):
              with torch.no_grad():
                 wav = self.model.generate([enhanced_prompt], progress=True)

          generation_time = time.time() - start_time

          # Extract audio tensor
          if isinstance(wav, list) and len(wav) > 0:
              audio_tensor = wav[0]
          elif torch.is_tensor(wav):
              audio_tensor = wav
          else:
              logger.error("Generation output is not in expected format.")
              return None

          # If batched output, take the first one (generate expects a list of prompts)
          if audio_tensor.dim() == 3 and audio_tensor.shape[0] == 1: # (B, C, T)
              audio_tensor = audio_tensor.squeeze(0) # (C, T)
          elif audio_tensor.dim() != 2: # Expect (C,T)
              logger.error(f"Unexpected audio tensor dimensions: {audio_tensor.shape}")
              return None


          # Get sample rate
          sample_rate = self.model.sample_rate

          # Post-process audio
          audio_tensor_processed = self._post_process_audio(audio_tensor.clone(), instrument, sample_rate) # Pass sr

          # Validate audio quality
          quality_score = self._validate_audio_quality(audio_tensor_processed, sample_rate)

          # Store generation info
          mem_stats_after = self.memory_manager.get_memory_stats()
          logger.debug(f"Memory after generation: {mem_stats_after}")
          generation_info = {
            'id': generation_id,
            'instrument': instrument,
            'duration': duration,
            'generation_time': generation_time,
            'quality_score': quality_score,
            'memory_stats_before': mem_stats_before,
            'memory_stats_after': mem_stats_after
          }
          self.generation_history.append(generation_info)

          logger.info(f"Generated {generation_id} in {generation_time:.2f}s, quality: {quality_score:.2f}")
          return audio_tensor_processed, sample_rate

     except torch.cuda.OutOfMemoryError as e:
        logger.error(f"GPU out of memory: {e}")
        self.memory_manager._force_cleanup()
        return None
     except Exception as e:
        logger.error(f"Generation failed: {e}")
        logger.debug(traceback.format_exc())
        return None

   def _enhance_prompt(self, prompt: str, instrument: str) -> str:
     """Enhanced prompt engineering with instrument-specific context"""
     instrument_enhancements = {
        'bass': {
           'descriptors': ['deep bass', 'low frequency', 'sub bass', 'bass foundation', 'funky bass line', 'walking bass'],
           'techniques': ['fingerstyle', 'slap bass', 'picked bass', 'fretless bass'],
           'freq_focus': 'low-end rich, clear fundamental frequencies'
        },
        'drums': {
           'descriptors': ['percussion', 'rhythmic drums', 'punchy drums', 'tight groove', 'drum beat', 'drum solo'],
           'techniques': ['live drums', 'programmed drums', 'acoustic kit', 'electronic drums', 'drum machine'],
           'freq_focus': 'full spectrum percussion, crisp hi-hats, deep kick'
        },
        'guitar': {
           'descriptors': ['guitar melody', 'chord progression', 'guitar riff', 'lead guitar solo', 'acoustic guitar strumming'],
           'techniques': ['fingerpicking guitar', 'strumming chords', 'palm muting riff', 'distorted electric guitar', 'clean electric guitar'],
           'freq_focus': 'midrange focused, articulate notes, clear chords'
        },
        'piano': {
           'descriptors': ['piano melody', 'piano chord progression', 'harmonic piano', 'keyboard solo', 'grand piano sound'],
           'techniques': ['classical piano', 'jazz piano chords', 'contemporary piano piece', 'synth pad like piano'],
           'freq_focus': 'wide frequency range, rich harmonics, clear tonality'
        },
        'synth': {
           'descriptors': ['synthesizer lead', 'electronic pad', 'ambient synth texture', 'arpeggiated synth'],
           'techniques': ['analog synth sound', 'digital synth patch', 'FM synthesis bells', 'wavetable pad'],
           'freq_focus': 'electronic textures, evolving soundscapes, defined synth waves'
        },
        'vocal': {
           'descriptors': ['vocal melody', 'harmonic vocals', 'vocal texture', 'lead vocal line', 'choir ahhs'],
           'techniques': ['clean lead vocals', 'processed background vocals', 'harmonized choir', 'operatic soprano'],
           'freq_focus': 'vocal frequency range, clear diction, expressive intonation'
        },
        'other': {
           'descriptors': ['melodic accompaniment', 'harmonic support', 'textural element', 'orchestral strings section'],
           'techniques': ['ambient soundscape', 'special effects', 'atmospheric drone', 'rhythmic percussion loop'],
           'freq_focus': 'complementary frequencies, supportive role in mix'
        }
     }
     enhancement_data = instrument_enhancements.get(instrument.lower(), instrument_enhancements['other'])

     # Add instrument context if not present
     enhanced = prompt
     if instrument.lower() not in prompt.lower():
         descriptor = np.random.choice(enhancement_data['descriptors'])
         enhanced = f"{descriptor}, {prompt}"

     # Add a random technique for variety if not mentioned
     # This could be made more sophisticated
     # if not any(tech.lower() in prompt.lower() for tech in enhancement_data['techniques']):
     #    technique = np.random.choice(enhancement_data['techniques'])
     #    enhanced = f"{enhanced}, {technique}"


     # Add frequency focus hint
     enhanced = f"{enhanced}, {enhancement_data['freq_focus']}"
     return enhanced

   def _post_process_audio(self, audio_tensor: torch.Tensor, instrument: str, sample_rate: int) -> torch.Tensor:
     """Enhanced post-processing with instrument-specific optimization"""
     if audio_tensor.dim() == 1: # (T) -> (C, T)
        audio_tensor = audio_tensor.unsqueeze(0)
     if audio_tensor.dim() != 2: # Should be (C,T)
         logger.warning(f"Unexpected audio tensor dimensions for post-processing: {audio_tensor.shape}")
         return audio_tensor

     # Ensure audio is on CPU for numpy conversion, keep as tensor for torchaudio effects
     # audio_np = audio_tensor.detach().cpu().numpy()

     # Example using torchaudio effects (more robust than manual numpy)
     # Instrument-specific processing
     if instrument.lower() == 'bass':
         # High-pass filter to remove DC offset and very low rumble
         audio_tensor = torchaudio.functional.highpass_biquad(audio_tensor, sample_rate, cutoff_freq=30.0)
         # Optional: slight low-pass to tame harshness if needed
         # audio_tensor = torchaudio.functional.lowpass_biquad(audio_tensor, sample_rate, cutoff_freq=5000.0)
     elif instrument.lower() == 'drums':
         # For drums, might want to preserve transients, so minimal filtering
         pass # Add specific drum processing if needed, e.g., transient shaping (complex)

     # Normalize with headroom
     peak = audio_tensor.abs().max()
     if peak > 1e-5: # Avoid division by zero or tiny numbers
        audio_tensor = audio_tensor / peak * 0.95 # Leave 5% headroom
     else:
        logger.warning("Audio tensor seems to be near silence, skipping normalization.")


     # Apply gentle fade in/out to prevent clicks
     fade_ms = 50
     fade_samples = int(fade_ms / 1000 * sample_rate)
     if audio_tensor.shape[-1] > fade_samples * 2:
        fade_in_shape = torch.linspace(0, 1, fade_samples, device=audio_tensor.device)
        fade_out_shape = torch.linspace(1, 0, fade_samples, device=audio_tensor.device)

        audio_tensor[..., :fade_samples] *= fade_in_shape
        audio_tensor[..., -fade_samples:] *= fade_out_shape

     return audio_tensor

   # Numpy based filters (kept for reference, torchaudio preferred)
   def _apply_highpass_np(self, audio: np.ndarray, cutoff: float, sr: int) -> np.ndarray:
    # Simple one-pole highpass filter (Butterworth can be better)
    rc = 1.0 / (cutoff * 2 * np.pi)
    dt = 1.0 / sr
    alpha = dt / (rc + dt)
    filtered = np.zeros_like(audio)
    if audio.ndim == 1:
        filtered[0] = audio[0]
        for j in range(1, audio.shape[0]):
            filtered[j] = alpha * (filtered[j-1] + audio[j] - audio[j-1])
    elif audio.ndim == 2: # Assuming (channels, samples)
        for i in range(audio.shape[0]):
            filtered[i, 0] = audio[i, 0]
            for j in range(1, audio.shape[1]):
                filtered[i, j] = alpha * (filtered[i, j-1] + audio[i, j] - audio[i, j-1])
    return filtered

   def _validate_audio_quality(self, audio: torch.Tensor, sample_rate: int) -> float:
     """Validate and score audio quality"""
     try:
        # Ensure tensor is on CPU for numpy conversion if needed by some metrics
        audio_np = audio.detach().cpu().numpy().flatten() # Flatten for 1D metrics

        quality_score = 100.0

        # 1. Peak level
        peak_level = np.max(np.abs(audio_np))
        if peak_level < 0.01: # Too quiet
            quality_score -= 20
        if peak_level > 0.99: # Clipping
            quality_score -= 30 * (np.sum(np.abs(audio_np) > 0.99) / len(audio_np)) # Penalize by clipping amount

        # 2. RMS level (loudness)
        rms_level = np.sqrt(np.mean(audio_np ** 2))
        if rms_level < 0.005: # Very quiet / near silence
            quality_score -= 30

        # 3. Dynamic range (simplified: peak to RMS ratio in dB)
        if rms_level > 1e-6: # Avoid log(0)
            dynamic_range_db = 20 * np.log10(peak_level / rms_level)
            if dynamic_range_db < 6: # Too compressed
                quality_score -= 15
            elif dynamic_range_db > 20: # Potentially too dynamic for some stems
                quality_score -= 5
        else: # Silent or near silent
            dynamic_range_db = 0
            quality_score -= 10


        # 4. Silence Ratio
        silence_threshold = 0.001
        silence_ratio = np.sum(np.abs(audio_np) < silence_threshold) / len(audio_np)
        if silence_ratio > 0.5: # More than 50% silent
            quality_score -= 25 * silence_ratio

        # 5. Check for NaNs or Infs
        if np.isnan(audio_np).any() or np.isinf(audio_np).any():
            logger.warning("Audio contains NaN or Inf values.")
            quality_score = 0.0 # Severe penalty

        # 6. Duration check (already handled by generation params, but good to have)
        actual_duration_s = len(audio_np) / sample_rate
        # Example: if actual_duration_s < self.config.duration * 0.8:
        #    quality_score -= 20

        return max(0.0, min(100.0, quality_score))

     except Exception as e:
        logger.warning(f"Quality validation failed: {e}")
        return 50.0 # Default score on error

   def save_audio(
     self,
     audio: torch.Tensor, # Expects (C,T) or (T)
     sample_rate: int,
     output_path: str,
     metadata: Dict[str, Any] = None
   ) -> bool:
     """Save audio with enhanced metadata and validation"""
     try:
        output_path_obj = Path(output_path)
        output_path_obj.parent.mkdir(parents=True, exist_ok=True)

        # Ensure audio is on CPU
        if audio.is_cuda:
           audio = audio.cpu()

        # Reshape to (C, T) if it's mono (T)
        if audio.dim() == 1:
            audio = audio.unsqueeze(0)

        # Final validation before saving
        if torch.isnan(audio).any() or torch.isinf(audio).any():
            logger.error("Audio contains NaN or Inf values. Cannot save.")
            return False

        torchaudio.save(
          str(output_path_obj),
          audio,
          sample_rate,
          format='wav',
          encoding='PCM_S', # Signed 16-bit PCM
          bits_per_sample=16
        )

        # Save metadata if provided
        if metadata:
           metadata_path = output_path_obj.with_suffix('.json')
           with open(metadata_path, 'w') as f:
             # Convert numpy specific types to standard types for JSON serialization
             def convert_types(obj):
                if isinstance(obj, np.integer):
                    return int(obj)
                elif isinstance(obj, np.floating):
                    return float(obj)
                elif isinstance(obj, np.ndarray):
                    return obj.tolist()
                elif isinstance(obj, Path):
                    return str(obj)
                return obj
             json.dump(metadata, f, indent=2, default=convert_types)

        logger.info(f"Audio saved successfully: {output_path_obj}")
        return True

     except Exception as e:
        logger.error(f"Failed to save audio: {e}")
        logger.debug(traceback.format_exc())
        return False

def main():
   parser = argparse.ArgumentParser(
     description="Advanced MusicGen-Stem Generator with Robustness Features"
   )
   parser.add_argument(
     '--instrument',
     required=True,
     choices=['bass', 'drums', 'guitar', 'piano', 'synth', 'vocal', 'other'],
     help='Target instrument for generation'
   )
   parser.add_argument(
     '--prompt',
     required=True,
     help='Text prompt describing the desired music'
   )
   parser.add_argument(
     '--out',
     required=True,
     help='Output file path (WAV format)'
   )
   parser.add_argument(
     '--duration',
     type=int,
     default=30,
     help='Duration in seconds (5-300, default: 30)'
   )
   parser.add_argument(
     '--model',
     default='facebook/musicgen-medium',
     choices=['facebook/musicgen-small', 'facebook/musicgen-medium', 'facebook/musicgen-large'],
     help='Model to use (default: facebook/musicgen-medium)'
   )
   parser.add_argument(
     '--temperature',
     type=float,
     default=1.0,
     help='Sampling temperature (0.1-2.0, default: 1.0)'
   )
   parser.add_argument(
     '--top-k',
     type=int,
     default=250,
     help='Top-k sampling (50-500, default: 250)'
   )
   parser.add_argument(
     '--seed',
     type=int,
     help='Random seed for reproducible generation'
   )
   parser.add_argument(
     '--quality-threshold',
     type=float,
     default=60.0,
     help='Minimum quality score (0-100, default: 60)'
   )
   parser.add_argument(
     '--max-retries',
     type=int,
     default=3,
     help='Maximum generation retries (default: 3)'
   )
   parser.add_argument(
     '--verbose',
     action='store_true',
     help='Enable verbose logging'
   )

   args = parser.parse_args()

   if args.verbose:
      logging.getLogger().setLevel(logging.DEBUG)
      logger.setLevel(logging.DEBUG)


   # Validate parameters
   if not (5 <= args.duration <= 300): # Max duration for musicgen is typically 30s for single pass, longer needs continuation
      logger.error("Duration must be between 5 and 300 seconds (MusicGen typically max 30s per pass).")
      # Forcing duration to 30 if above, as the model might not support longer directly
      # args.duration = min(args.duration, 30)
      # logger.warning(f"Adjusted duration to {args.duration}s for single pass generation.")
      # sys.exit(1) # Or adjust, for now let's allow it and see model behavior.

   if not (0.1 <= args.temperature <= 2.0):
      logger.error("Temperature must be between 0.1 and 2.0")
      sys.exit(1)

   if not (50 <= args.top_k <= 500): # MusicGen default top_k is 250
      logger.error("Top-k must be between 50 and 500")
      sys.exit(1)

   # Initialize generator
   generator = MusicGenStemGenerator(args.model)

   # Generation loop with retry logic
   best_result_tuple = None # Renamed to avoid conflict
   best_quality = 0.0 # Ensure float

   for attempt in range(args.max_retries):
      logger.info(f"Generation attempt {attempt + 1}/{args.max_retries}")
      current_seed = args.seed + attempt if args.seed is not None else None


      # Update initial memory for the manager before this attempt's generation
      if generator.device == 'cuda' and generator.model: # Ensure model is loaded to get accurate post-load memory
        generator.memory_manager.initial_memory = torch.cuda.memory_allocated()


      stem_result = generator.generate_stem( # Renamed to avoid conflict
        prompt=args.prompt,
        instrument=args.instrument,
        duration=args.duration,
        temperature=args.temperature,
        top_k=args.top_k,
        seed=current_seed # Use potentially incremented seed
      )

      if stem_result is None:
          logger.warning(f"Attempt {attempt + 1} failed to generate audio.")
          if attempt < args.max_retries - 1:
              time.sleep(1) # Wait a bit before retrying
          continue

      audio, sample_rate = stem_result
      # Assuming generation_time is part of what generate_stem might return or calculate internally
      # For now, it's part of the metadata dict. Let's find it from history.
      generation_info = next((h for h in reversed(generator.generation_history) if h['instrument'] == args.instrument), None)
      generation_time = generation_info['generation_time'] if generation_info else 0


      # Validate quality (already done in generate_stem, quality_score is in generation_info)
      quality_score = generation_info['quality_score'] if generation_info else 0.0


      if quality_score > best_quality:
         best_result_tuple = (audio, sample_rate, generation_time, quality_score)
         best_quality = quality_score

      # Check if quality meets threshold
      if quality_score >= args.quality_threshold:
         logger.info(f"Quality threshold met: {quality_score:.2f}")
         break
      else:
         logger.warning(f"Quality below threshold: {quality_score:.2f} < {args.quality_threshold}")
         if attempt == args.max_retries - 1:
             logger.warning(f"Max retries reached. Using best result with quality {best_quality:.2f}.")


   if best_result_tuple is None:
      logger.error("All generation attempts failed or produced no valid audio.")
      output_data = {
         'file': args.out,
         'error': 'Generation failed after all retries',
         'success': False,
         'attempts': args.max_retries,
         'instrument': args.instrument, # Add instrument info to error
         'prompt': args.prompt
      }
      print(json.dumps(output_data))
      sys.exit(1)

   final_audio, final_sample_rate, final_generation_time, final_quality_score = best_result_tuple

   # Prepare metadata
   metadata = {
     'file': args.out, # Use the intended output path for metadata
     'instrument': args.instrument,
     'prompt': args.prompt,
     'duration_requested': args.duration,
     'actual_duration': len(final_audio[0] if final_audio.ndim > 1 else final_audio) / final_sample_rate, # Correct duration from tensor
     'model': args.model,
     'generation_params': {
        'temperature': args.temperature,
        'top_k': args.top_k,
        'seed_initial': args.seed # Original seed if provided
     },
     'quality_score': float(final_quality_score),
     'generation_time_seconds': float(final_generation_time),
     'sample_rate': int(final_sample_rate),
     'timestamp_iso': time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
     'generator_version': '2.0_advanced' # Version marker
   }

   # Save result
   if generator.save_audio(final_audio, final_sample_rate, args.out, metadata):
      output_data = {
         'file': args.out,
         'instrument': args.instrument,
         'duration': metadata['actual_duration'], # Use actual duration
         'sample_rate': final_sample_rate,
         'generation_time': round(final_generation_time, 2),
         'quality_score': round(final_quality_score, 2),
         'success': True,
         'metadata_file': Path(args.out).with_suffix('.json').name # Provide metadata filename
      }
      # The python script itself should print the JSON to stdout for n8n
      print(json.dumps(output_data))
   else:
      error_data = {
         'file': args.out,
         'error': 'Failed to save audio file',
         'success': False,
         'quality_score': round(final_quality_score, 2),
         'instrument': args.instrument,
         'prompt': args.prompt
      }
      print(json.dumps(error_data))
      sys.exit(1)

if __name__ == '__main__':
   main()
