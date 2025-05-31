#!/usr/bin/env python3
"""
Advanced Audio Analyzer for AI Music Studio
Provides detailed spectral analysis, quality metrics, and instrument detection
"""

import argparse
import json
import logging
import warnings
from pathlib import Path
from typing import Dict, Any, Tuple # Optional was imported but not used directly in type hints here

import numpy as np
import librosa
# import librosa.display # Not used in the script
# from scipy import signal, stats # signal and stats from scipy not used
# from scipy.signal import find_peaks # Not used
import soundfile as sf

# Suppress warnings
warnings.filterwarnings('ignore', category=UserWarning)
warnings.filterwarnings('ignore', category=FutureWarning)

# Configure logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(name)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

class AudioAnalyzer:
   """Advanced audio analysis with ML-based feature extraction"""

   def __init__(self, sample_rate: int = 44100):
    self.sample_rate = sample_rate
    self.n_fft = 2048
    self.hop_length = 512
    self.n_mels = 128 # Defined but not explicitly used in provided methods, common for MFCC or MelSpectrogram

   def load_audio(self, file_path: str) -> Tuple[np.ndarray, int]:
    """Load audio file with error handling and resampling to target sample rate."""
    try:
       y, sr_orig = librosa.load(file_path, sr=None, mono=True) # Load with original sample rate
       if sr_orig != self.sample_rate:
           y = librosa.resample(y, orig_sr=sr_orig, target_sr=self.sample_rate)
           logger.info(f"Resampled audio from {sr_orig}Hz to {self.sample_rate}Hz.")
       logger.info(f"Loaded audio: {file_path}, Duration: {len(y)/self.sample_rate:.2f}s at {self.sample_rate}Hz")
       return y, self.sample_rate
    except Exception as e:
       logger.warning(f"Librosa failed to load {file_path}, trying soundfile: {e}")
       try:
          y_sf, sr_sf_orig = sf.read(file_path, dtype='float32') # Read as float32 for consistency
          if y_sf.ndim > 1: # Convert to mono if stereo
              y_sf = np.mean(y_sf, axis=1)
          if sr_sf_orig != self.sample_rate:
              y_sf = librosa.resample(y_sf, orig_sr=sr_sf_orig, target_sr=self.sample_rate)
          logger.info(f"Loaded audio with soundfile: {file_path}, Duration: {len(y_sf)/self.sample_rate:.2f}s")
          return y_sf, self.sample_rate
       except Exception as e2:
          logger.error(f"Failed to load audio {file_path} with both librosa and soundfile: {e2}")
          raise RuntimeError(f"Failed to load audio: {file_path}") from e2


   def analyze_basic_properties(self, y: np.ndarray, sr: int) -> Dict[str, Any]:
    """Extract basic audio properties"""
    if len(y) == 0: # Handle empty audio array
        logger.warning("Empty audio array provided for basic analysis.")
        return {
           'duration': 0.0, 'sample_rate': int(sr), 'peak': 0.0, 'peak_db': -np.inf,
           'rms': 0.0, 'rms_db': -np.inf, 'dynamic_range': 0.0, # Corrected dynamic_range to dynamic_range_db potentially
           'zero_crossing_rate_mean': 0.0, 'zero_crossing_rate_std': 0.0,
           'silence_ratio': 1.0, 'clipping_ratio': 0.0
        }

    duration = len(y) / sr
    peak = float(np.max(np.abs(y))) if len(y) > 0 else 0.0
    rms = float(np.sqrt(np.mean(y**2))) if len(y) > 0 else 0.0

    rms_frames = librosa.feature.rms(y=y, frame_length=self.n_fft, hop_length=self.hop_length)[0]
    # dynamic_range = float(np.max(rms_frames) - np.min(rms_frames)) if len(rms_frames) > 0 else 0.0 # Linear DR
    dynamic_range_db_val = 0.0
    if len(rms_frames) > 0 and np.min(rms_frames) > 1e-7 and np.max(rms_frames) > 1e-7 : # avoid log of zero or neg
        min_rms_db = 20 * np.log10(np.min(rms_frames) + 1e-7)
        max_rms_db = 20 * np.log10(np.max(rms_frames) + 1e-7)
        dynamic_range_db_val = max_rms_db - min_rms_db


    zcr = librosa.feature.zero_crossing_rate(y, frame_length=self.n_fft, hop_length=self.hop_length)[0]
    zcr_mean = float(np.mean(zcr)) if len(zcr) > 0 else 0.0
    zcr_std = float(np.std(zcr)) if len(zcr) > 0 else 0.0

    silence_threshold = 0.01
    silence_ratio = float(np.sum(np.abs(y) < silence_threshold) / len(y)) if len(y) > 0 else 1.0

    clipping_threshold = 0.99
    clipping_ratio = float(np.sum(np.abs(y) >= clipping_threshold) / len(y)) if len(y) > 0 else 0.0

    return {
       'duration': duration,
       'sample_rate': int(sr),
       'peak': peak,
       'peak_db': 20 * np.log10(peak + 1e-7) if peak > 1e-7 else -np.inf,
       'rms': rms,
       'rms_db': 20 * np.log10(rms + 1e-7) if rms > 1e-7 else -np.inf,
       'dynamic_range_db': dynamic_range_db_val,
       'zero_crossing_rate_mean': zcr_mean,
       'zero_crossing_rate_std': zcr_std,
       'silence_ratio': silence_ratio,
       'clipping_ratio': clipping_ratio
    }

   def analyze_spectral_features(self, y: np.ndarray, sr: int) -> Dict[str, Any]:
    """Extract advanced spectral features"""
    if len(y) == 0:
        logger.warning("Empty audio array provided for spectral analysis.")
        return {
            'spectral_centroid_mean': 0.0, 'spectral_centroid_std': 0.0,
            'spectral_rolloff_mean': 0.0, 'spectral_rolloff_std': 0.0,
            'spectral_bandwidth_mean': 0.0, 'spectral_bandwidth_std': 0.0,
            'spectral_contrast_mean': 0.0, 'spectral_contrast_std': 0.0,
            'spectral_flatness_mean': 0.0, 'spectral_flatness_std': 0.0,
            'chroma_mean': [0.0]*12, 'mfcc_mean': [0.0]*13,
            'frequency_bands': {
                'sub_bass': 0.0, 'bass': 0.0, 'low_mid': 0.0, 'mid': 0.0,
                'high_mid': 0.0, 'presence': 0.0, 'brilliance': 0.0
            }
        }

    stft = librosa.stft(y, n_fft=self.n_fft, hop_length=self.hop_length)
    magnitude = np.abs(stft)
    freqs = librosa.fft_frequencies(sr=sr, n_fft=self.n_fft)

    spectral_centroid = librosa.feature.spectral_centroid(y=y, sr=sr, n_fft=self.n_fft, hop_length=self.hop_length)[0]
    spectral_rolloff = librosa.feature.spectral_rolloff(y=y, sr=sr, n_fft=self.n_fft, hop_length=self.hop_length, roll_percent=0.85)[0] # common to use 0.85 or 0.95
    spectral_bandwidth = librosa.feature.spectral_bandwidth(y=y, sr=sr, n_fft=self.n_fft, hop_length=self.hop_length)[0]
    spectral_contrast = librosa.feature.spectral_contrast(y=y, sr=sr, n_fft=self.n_fft, hop_length=self.hop_length)
    spectral_flatness = librosa.feature.spectral_flatness(y=y, n_fft=self.n_fft, hop_length=self.hop_length)[0]
    chroma = librosa.feature.chroma_stft(y=y, sr=sr, n_fft=self.n_fft, hop_length=self.hop_length)
    mfcc = librosa.feature.mfcc(y=y, sr=sr, n_fft=self.n_fft, hop_length=self.hop_length, n_mels=self.n_mels, n_mfcc=13)

    def safe_mean_std(arr, default_val=0.0):
        # For spectral_contrast, which is (n_bands, T), calculate mean across time first for each band, then overall mean/std of these means
        if arr.ndim > 1 and arr.shape[0] > 1 : # like spectral_contrast or chroma
             mean_per_band = np.mean(arr, axis=1)
             return float(np.mean(mean_per_band)) if mean_per_band.size > 0 else default_val, float(np.std(mean_per_band)) if mean_per_band.size > 0 else default_val
        return float(np.mean(arr)) if arr.size > 0 else default_val, float(np.std(arr)) if arr.size > 0 else default_val


    sc_mean, sc_std = safe_mean_std(spectral_centroid)
    sroff_mean, sroff_std = safe_mean_std(spectral_rolloff)
    sbw_mean, sbw_std = safe_mean_std(spectral_bandwidth)
    scont_mean, scont_std = safe_mean_std(spectral_contrast)
    sflat_mean, sflat_std = safe_mean_std(spectral_flatness)

    chroma_mean_vals = [float(x) for x in np.mean(chroma, axis=1)] if chroma.size > 0 else [0.0]*chroma.shape[0]
    mfcc_mean_vals = [float(x) for x in np.mean(mfcc, axis=1)] if mfcc.size > 0 else [0.0]*mfcc.shape[0]

    energy_bands = {
        'sub_bass': float(np.mean(magnitude[freqs < 60])) if magnitude.size > 0 and np.any(freqs < 60) else 0.0,
        'bass': float(np.mean(magnitude[(freqs >= 60) & (freqs < 250)])) if magnitude.size > 0 and np.any((freqs >= 60) & (freqs < 250)) else 0.0,
        'low_mid': float(np.mean(magnitude[(freqs >= 250) & (freqs < 500)])) if magnitude.size > 0 and np.any((freqs >= 250) & (freqs < 500)) else 0.0,
        'mid': float(np.mean(magnitude[(freqs >= 500) & (freqs < 2000)])) if magnitude.size > 0 and np.any((freqs >= 500) & (freqs < 2000)) else 0.0,
        'high_mid': float(np.mean(magnitude[(freqs >= 2000) & (freqs < 4000)])) if magnitude.size > 0 and np.any((freqs >= 2000) & (freqs < 4000)) else 0.0,
        'presence': float(np.mean(magnitude[(freqs >= 4000) & (freqs < 6000)])) if magnitude.size > 0 and np.any((freqs >= 4000) & (freqs < 6000)) else 0.0,
        'brilliance': float(np.mean(magnitude[freqs >= 6000])) if magnitude.size > 0 and np.any(freqs >= 6000) else 0.0
    }

    return {
       'spectral_centroid_mean': sc_mean, 'spectral_centroid_std': sc_std,
       'spectral_rolloff_mean': sroff_mean, 'spectral_rolloff_std': sroff_std,
       'spectral_bandwidth_mean': sbw_mean, 'spectral_bandwidth_std': sbw_std,
       'spectral_contrast_mean': scont_mean, 'spectral_contrast_std': scont_std,
       'spectral_flatness_mean': sflat_mean, 'spectral_flatness_std': sflat_std,
       'chroma_mean': chroma_mean_vals, 'mfcc_mean': mfcc_mean_vals,
       'frequency_bands': energy_bands
    }

   def analyze_rhythm_and_tempo(self, y: np.ndarray, sr: int) -> Dict[str, Any]:
    """Analyze rhythmic content and tempo"""
    default_rhythm = {
        'tempo': 0.0, 'beat_count': 0, 'onset_count': 0,
        'rhythm_regularity': 0.0, 'pulse_clarity': 0.0, 'beats_per_second': 0.0
    }
    if len(y) < self.hop_length * 4: # Need at least a few frames for tempogram/beat tracking
        logger.warning(f"Audio too short ({len(y)} samples) for robust rhythm analysis.")
        return default_rhythm
    try:
       tempo, beats_idx = librosa.beat.beat_track(y=y, sr=sr, hop_length=self.hop_length)
       beats_time = librosa.frames_to_time(beats_idx, sr=sr, hop_length=self.hop_length)
       onsets_time = librosa.onset.onset_detect(y=y, sr=sr, hop_length=self.hop_length, units='time')

       rhythm_regularity = 0.0
       if len(beats_time) > 1:
           beat_intervals = np.diff(beats_time)
           if np.mean(beat_intervals) > 1e-6 : # Avoid division by zero
             std_dev_intervals = np.std(beat_intervals)
             if std_dev_intervals > 1e-6 : # Avoid division by zero for CoV
                # Coefficient of variation, smaller is more regular. Inverse for regularity score.
                rhythm_regularity = float(np.mean(beat_intervals) / std_dev_intervals)


       pulse_clarity_val = 0.0
       try: # Pulse clarity can sometimes fail on very sparse audio
            tempogram = librosa.feature.tempogram(y=y, sr=sr, hop_length=self.hop_length)
            if tempogram.size > 0 and np.mean(tempogram) > 1e-8:
                 # pulse_clarity = librosa.feature.pulse_clarity(tempogram, sr=sr) # This seems to not be a direct function
                 # A common way to estimate pulse clarity is from the tempogram's autocorrelation or max value.
                 # For simplicity, let's use a placeholder or a simplified version.
                 # The original script used np.max(tempogram) / (np.mean(tempogram) + 1e-8)
                 pulse_clarity_val = float(np.max(tempogram) / (np.mean(tempogram) + 1e-8))

       except Exception as pc_e:
            logger.warning(f"Could not calculate pulse clarity: {pc_e}")


       return {
          'tempo': float(tempo) if tempo is not None and tempo.size > 0 else 0.0,
          'beat_count': len(beats_time),
          'onset_count': len(onsets_time),
          'rhythm_regularity': min(rhythm_regularity, 10.0), # Cap score for stability
          'pulse_clarity': pulse_clarity_val,
          'beats_per_second': float(len(beats_time) / (len(y) / sr)) if len(y) > 0 else 0.0
       }
    except Exception as e:
      logger.warning(f"Rhythm analysis failed: {e}. Returning default values.")
      return default_rhythm

   def detect_instrument_type(self, features: Dict[str, Any]) -> Dict[str, Any]:
    """Heuristic instrument detection based on extracted features."""
    basic_props = features.get('basic_properties', {})
    spectral = features.get('spectral_features', {}) # Corrected variable name
    rhythm = features.get('rhythm_features', {})

    sc_mean = spectral.get('spectral_centroid_mean', 1500.0)
    freq_bands = spectral.get('frequency_bands', {})
    zcr_mean = basic_props.get('zero_crossing_rate_mean', 0.1)
    onset_count = rhythm.get('onset_count', 0)
    duration = basic_props.get('duration', 1.0)
    onset_density = onset_count / max(duration, 1e-6)

    instrument_scores = {
        'bass': 0.0, 'drums': 0.0, 'guitar': 0.0, 'piano': 0.0,
        'synth': 0.0, 'vocal': 0.0, 'other': 0.05 # Small base for other
    }

    # Bass
    bass_energy = freq_bands.get('sub_bass', 0) + freq_bands.get('bass', 0)
    mid_energy = freq_bands.get('low_mid',0) + freq_bands.get('mid',0)
    if sc_mean < 700 and bass_energy > (mid_energy + 1e-6):
        instrument_scores['bass'] += 0.6
    if rhythm.get('tempo',0) > 0 and rhythm.get('rhythm_regularity',0) > 0.5 : instrument_scores['bass'] +=0.2 # Rhythmic bass

    # Drums
    if onset_density > 2.5 and zcr_mean > 0.12 and spectral.get('spectral_bandwidth_mean',0) > 1800:
        instrument_scores['drums'] += 0.7
    if spectral.get('spectral_flatness_mean',0) > 0.2 : instrument_scores['drums'] +=0.1 # Noisy

    # Guitar/Piano
    if 600 < sc_mean < 4000:
        harmonicity = 1.0 - spectral.get('spectral_flatness_mean', 1.0) # Simple harmonicity proxy
        if harmonicity > 0.7: # More tonal
            instrument_scores['piano'] += 0.5 * harmonicity
            instrument_scores['guitar'] += 0.3 * harmonicity
        else: # More noisy/complex
            instrument_scores['guitar'] += 0.4
        # If it has clear beats, could be piano chords or guitar strumming
        if rhythm.get('beat_count',0) > duration * 0.5 :
            instrument_scores['piano'] +=0.1
            instrument_scores['guitar'] +=0.1


    # Synth
    if sc_mean > 3000 or spectral.get('spectral_flatness_mean', 0) > 0.5 or spectral.get('spectral_bandwidth_mean',0) > 3000:
        instrument_scores['synth'] += 0.6
    if freq_bands.get('brilliance',0) > 0.05 : instrument_scores['synth']+=0.2

    # Vocal (very rough heuristics)
    # MFCCs are typically better for this. For a simple heuristic:
    # Vocals often have strong formants in mid-range, and are somewhat harmonic.
    if 1000 < sc_mean < 3500 and (freq_bands.get('mid',0)+freq_bands.get('high_mid',0)) > (bass_energy + 1e-6):
        mfccs = spectral.get('mfcc_mean', [0]*13)
        if len(mfccs) >= 4 and -10 < mfccs[1] < 5 and -5 < mfccs[2] < 5: # Example check on first few MFCCs
             instrument_scores['vocal'] += 0.4


    # Normalize scores to sum to 1 for confidence (or use softmax if preferred)
    total_score = sum(instrument_scores.values()) + 1e-6 # add epsilon for safety
    for k in instrument_scores:
        instrument_scores[k] /= total_score

    predicted_instrument = max(instrument_scores, key=instrument_scores.get)
    confidence = instrument_scores[predicted_instrument]

    return {
       'predicted_instrument': predicted_instrument,
       'confidence': float(confidence),
       'scores': {k: float(v) for k, v in instrument_scores.items()}
    }

   def calculate_quality_score(self, features: Dict[str, Any]) -> float:
    """Calculate overall audio quality score (0-100) based on features."""
    score = 100.0
    basic_props = features.get('basic_properties', {})
    spectral = features.get('spectral_features', {})
    # rhythm = features.get('rhythm_features', {}) # Rhythm not directly used in this quality score version

    # Clipping
    score -= basic_props.get('clipping_ratio', 0) * 250 # Heavy penalty, max 250*0.X

    # Silence
    silence_ratio = basic_props.get('silence_ratio', 0)
    if silence_ratio > 0.9: score -= 70 # Almost entirely silent
    elif silence_ratio > 0.5: score -= 30
    elif silence_ratio > 0.2: score -= 10

    # Loudness (Peak and RMS)
    peak_db = basic_props.get('peak_db', -6.0)
    rms_db = basic_props.get('rms_db', -20.0)
    if peak_db < -25.0: score -= (abs(peak_db) - 25) * 0.5 # Penalize if too quiet
    if rms_db < -35.0: score -= (abs(rms_db) - 35) * 0.5

    # Dynamic Range
    dr_db = basic_props.get('dynamic_range_db', 12.0)
    if dr_db < 5.0: score -= 20 # Too compressed
    elif dr_db > 25.0: score -= 10 # Potentially too dynamic / inconsistent for some use cases

    # Spectral Balance
    bands = spectral.get('frequency_bands', {})
    total_energy = sum(bands.values()) + 1e-7

    # Avoid extreme lack of low or high frequencies if there's content
    if basic_props.get('duration', 0) > 0.5 and total_energy > 1e-5: # Only if there's some audio
        low_energy_ratio = (bands.get('sub_bass',0) + bands.get('bass',0)) / total_energy
        high_energy_ratio = (bands.get('presence',0) + bands.get('brilliance',0)) / total_energy
        if low_energy_ratio < 0.01: score -= 10 # Missing lows
        if high_energy_ratio < 0.005: score -= 10 # Missing highs
        # Check for overly dominant single band (e.g. only sub_bass)
        if bands.get('sub_bass',0)/total_energy > 0.8 : score -=15


    # Check for NaN/Inf in key features that would indicate problems
    for key_feature_dict in [basic_props, spectral, spectral.get('frequency_bands', {})]:
        for k, v in key_feature_dict.items():
            if isinstance(v, float) and (np.isnan(v) or np.isinf(v)):
                logger.warning(f"Invalid numeric value in features: {k}={v}. Penalizing quality.")
                score -= 25 # Significant penalty for calculation errors
                break
        else: # Python's for/else: if loop completed without break
            continue
        break # Break outer loop if inner broke

    return max(0.0, min(100.0, float(score)))


   def analyze_file(self, file_path_str: str, verbose: bool = False) -> Dict[str, Any]:
    """Complete audio analysis pipeline for a given file path."""
    file_path = Path(file_path_str)
    if not file_path.exists():
        logger.error(f"File not found for analysis: {file_path}")
        return {'file_path': str(file_path), 'error': 'File not found', 'analysis_type': 'failed'}
    if file_path.stat().st_size < 1024 and file_path.suffix.lower() in ['.wav','.mp3','.flac','.ogg']: # 1KB, check common audio types
        logger.warning(f"File {file_path} is very small (<1KB), likely not valid audio.")
        # return {'file_path': str(file_path), 'error': 'File too small or invalid', 'analysis_type': 'failed'}


    try:
       y, sr = self.load_audio(str(file_path))
       if y is None or len(y) == 0:
           logger.error(f"Audio data is empty after loading: {file_path}")
           return {'file_path': str(file_path), 'error': 'Empty audio data after load', 'analysis_type': 'failed'}


       if verbose: logger.info(f"Analyzing basic properties for {file_path.name}...")
       basic_props = self.analyze_basic_properties(y, sr)

       if verbose: logger.info(f"Analyzing spectral features for {file_path.name}...")
       spectral_features = self.analyze_spectral_features(y, sr)

       if verbose: logger.info(f"Analyzing rhythm and tempo for {file_path.name}...")
       rhythm_features = self.analyze_rhythm_and_tempo(y, sr)

       all_features_for_detection = {
           'basic_properties': basic_props,
           'spectral_features': spectral_features,
           'rhythm_features': rhythm_features
       }

       if verbose: logger.info(f"Detecting instrument type for {file_path.name}...")
       instrument_detection = self.detect_instrument_type(all_features_for_detection)

       if verbose: logger.info(f"Calculating quality score for {file_path.name}...")
       quality_score = self.calculate_quality_score(all_features_for_detection)

       result = {
         'file_path': str(file_path.resolve()),
         'analysis_timestamp_utc': np.datetime_as_string(np.datetime64('now', 's'), unit='s', timezone='UTC'),
         'basic_properties': basic_props,
         'spectral_features': spectral_features,
         'rhythm_features': rhythm_features,
         'instrument_detection': instrument_detection,
         'quality_score': float(quality_score),
         'analysis_type': 'advanced_v2.1' # Version marker
       }
       if verbose:
          logger.info(f"Analysis complete for {file_path.name}. Quality: {quality_score:.1f}, Instrument: {instrument_detection['predicted_instrument']} (Conf: {instrument_detection['confidence']:.2f})")
       return result

    except Exception as e:
      logger.error(f"Analysis failed for {file_path}: {e}", exc_info=verbose)
      return {
         'file_path': str(file_path.resolve()),
         'error': str(e),
         'analysis_type': 'failed'
      }

def main():
   parser = argparse.ArgumentParser(description="Advanced Audio Analyzer for AI Music Studio. Analyzes an audio file and outputs features as JSON.")
   parser.add_argument('--input', '-i', required=True, help='Input audio file path.')
   parser.add_argument('--output', '-o', required=True, help='Output JSON file path for analysis results.')
   parser.add_argument('--verbose', '-v', action='store_true', help='Enable verbose logging output to stderr.')
   parser.add_argument('--sample-rate', type=int, default=44100, help='Target sample rate for analysis (default: 44100).')

   args = parser.parse_args()

   # Setup logger based on verbosity
   if args.verbose:
      # Configure logger to output to stderr for verbose messages
      # The root logger is already configured, this ensures this specific logger also respects verbosity for its messages
      logger.setLevel(logging.DEBUG)
   else:
      logger.setLevel(logging.INFO)


   input_file = Path(args.input)
   output_file = Path(args.output)

   if not input_file.is_file(): # Check if it's a file specifically
      logger.error(f"Input path is not a file or does not exist: {input_file}")
      error_json = {'file_path': str(input_file), 'error': 'Input path is not a file or does not exist.', 'success': False}
      try:
          output_file.parent.mkdir(parents=True, exist_ok=True)
          with open(output_file, 'w') as f_err:
              json.dump(error_json, f_err, indent=2)
      except Exception as e_io:
          logger.error(f"Could not write error JSON to output file {output_file}: {e_io}")
          print(json.dumps(error_json)) # Fallback to stdout
      sys.exit(1)

   output_file.parent.mkdir(parents=True, exist_ok=True)

   analyzer = AudioAnalyzer(sample_rate=args.sample_rate)
   analysis_result = analyzer.analyze_file(str(input_file), verbose=args.verbose)

   analysis_result['success'] = 'error' not in analysis_result

   try:
      with open(output_file, 'w') as f:
         # Custom JSON encoder for numpy types if any sneak through (though most are converted to float/int)
         class NumpyEncoder(json.JSONEncoder):
            def default(self, obj):
                if isinstance(obj, np.integer): return int(obj)
                elif isinstance(obj, np.floating): return float(obj)
                elif isinstance(obj, np.ndarray): return obj.tolist()
                return super(NumpyEncoder, self).default(obj)
         json.dump(analysis_result, f, indent=2, cls=NumpyEncoder)

      if args.verbose:
         logger.info(f"Analysis results saved to: {output_file}")

      # For n8n ExecuteCommand node, the primary output should be to STDOUT
      print(json.dumps(analysis_result, cls=NumpyEncoder)) # Print result to stdout as well

      sys.exit(0 if analysis_result['success'] else 1)

   except Exception as e:
      logger.error(f"Failed to save or print analysis results for {output_file}: {e}")
      # Fallback: print error to stdout if file save fails
      error_output = {'file_path': str(input_file), 'error': f'Failed to save/print JSON: {e}', 'success': False}
      print(json.dumps(error_output))
      sys.exit(1)

if __name__ == '__main__':
   main()
