#!/usr/bin/env python3
"""
LMMS Headless Rendering Script with Template Management
"""

import argparse
import json
import logging
import os
import subprocess
import sys
import tempfile
# import xml.etree.ElementTree as ET # This was imported but not used in the provided script
from pathlib import Path
from typing import Dict, List, Optional # Dict and List were imported from typing but not used

logging.basicConfig(level=logging.INFO, format='%(levelname)s: %(message)s') # Simpler format
logger = logging.getLogger(__name__)

class LMMSRenderer:
   def __init__(self, templates_dir: str = "/templates", soundfonts_dir: str = "/soundfonts"):
     self.templates_dir = Path(templates_dir)
     self.soundfonts_dir = Path(soundfonts_dir) # Added soundfonts dir
     self.temp_dir = Path(tempfile.mkdtemp(prefix="lmms_render_")) # Added prefix for clarity

     # Ensure LMMS can find soundfonts
     # This might be better handled by LMMS config or env vars if LMMS supports it directly
     # For now, this is a common workaround pattern if LMMS scans default locations.
     # os.environ["LMMS_SOUNDFONT_DIR"] = str(self.soundfonts_dir) # Example, actual env var might differ

   def list_templates(self) -> List[str]: # Corrected typing hint
       """List available LMMS templates."""
       templates = []
       if not self.templates_dir.exists():
           logger.warning(f"Templates directory not found: {self.templates_dir}")
           return templates
       for template_file in self.templates_dir.glob("*.mmpz"): # Ensure it's template_file
           templates.append(template_file.stem)
       return templates

   def load_template(self, template_name: str) -> Optional[Path]:
    """Load and prepare LMMS template."""
    template_path = self.templates_dir / f"{template_name}.mmpz"

    if not template_path.exists():
       logger.error(f"Template not found: {template_path}")
       return None

    # Copy template to temp directory for modification (if any modifications were planned)
    # For now, the script doesn't modify, so direct usage might be okay, but temp copy is safer.
    try:
        temp_template_path = self.temp_dir / f"{template_name}_{os.getpid()}.mmpz"
        temp_template_path.write_bytes(template_path.read_bytes())
        logger.info(f"Loaded template: {template_name} to {temp_template_path}")
        return temp_template_path
    except Exception as e:
        logger.error(f"Failed to copy template {template_name} to temp dir: {e}")
        return None


   def modify_template( # This function was a no-op in the original, kept for structure
       self,
       template_path: Path,
       bpm: Optional[int] = None,
       key: Optional[str] = None,
       time_signature: Optional[str] = None
   ) -> Path:
       """Modify template parameters (Placeholder - original script did not implement this)."""
       # Actual modification of .mmpz (a compressed XML) is complex.
       # It would require unzipping, parsing XML, modifying, and rezipping.
       # This was not implemented in the provided script.
       if any([bpm, key, time_signature]):
           logger.info(f"Template modification requested (BPM: {bpm}, Key: {key}, TimeSig: {time_signature}) but not implemented in this version.")
       return template_path

   def render_project(
      self,
      project_path: Path,
      output_path: Path,
      output_format: str = "wav", # Renamed from format_type for clarity
      sample_rate: int = 44100,
      bit_depth: int = 16,
      render_tracks: bool = False, # This option seems specific to LMMS CLI if it supports it
      track_name: Optional[str] = None
   ) -> bool:
       """Render LMMS project to audio."""
       if not project_path.exists():
           logger.error(f"Project file for rendering not found: {project_path}")
           return False

       try:
           # Ensure output directory exists
           output_path.parent.mkdir(parents=True, exist_ok=True)

           # Prepare LMMS command
           # The original script had a complex structure for cmd based on render_tracks,
           # but LMMS `render` command might not distinguish tracks this way.
           # Typically, for stems, one might export tracks individually or use a DAW feature.
           # The `rendertracks` command mentioned seems hypothetical for LMMS CLI.
           # Sticking to the 'render' command which is standard.
           # If specific track rendering is needed, it usually involves project modification or specific LMMS features.

           cmd = [
               "lmms", "render", str(project_path),
               "--output", str(output_path),
               "--format", output_format,
               "--samplerate", str(sample_rate),
               "--bitdepth", str(bit_depth)
           ]
           # The --track option for `lmms render` or a separate `rendertracks` command is not standard.
           # If only a specific track is needed, the LMMS project itself should be set up for that,
           # or a more advanced interaction with LMMS (e.g. scripting within LMMS) is required.
           # For this script, we assume `lmms render` renders the whole project.
           if render_tracks and track_name:
               logger.warning(f"Specific track rendering ('{track_name}') requested but might not be supported by LMMS CLI 'render' command directly. Rendering whole project.")
               # If LMMS CLI had a way: cmd.extend(["--track", track_name])

           # Set environment for headless rendering
           env = os.environ.copy()
           env.update({
               "DISPLAY": ":99", # Assumes Xvfb is running on display 99
               "QT_QPA_PLATFORM": "offscreen", # Important for headless Qt apps
               # "LMMS_SOUNDFONT_DIR": str(self.soundfonts_dir) # If LMMS uses this
           })

           logger.info(f"Rendering command: {' '.join(cmd)}")

           # Execute rendering
           # Increased timeout as rendering can be slow
           process = subprocess.run(
               cmd,
               env=env,
               capture_output=True,
               text=True,
               timeout=600 # 10 minutes timeout
           )

           if process.returncode == 0:
               logger.info(f"Rendering successful: {output_path}")
               if not output_path.exists() or output_path.stat().st_size == 0:
                   logger.error(f"LMMS reported success, but output file is missing or empty: {output_path}")
                   logger.error(f"LMMS stdout: {process.stdout}")
                   logger.error(f"LMMS stderr: {process.stderr}")
                   return False
               return True
           else:
               logger.error(f"LMMS rendering failed with exit code {process.returncode}")
               logger.error(f"LMMS stdout: {process.stdout}")
               logger.error(f"LMMS stderr: {process.stderr}") # Stderr is crucial for LMMS errors
               return False

       except subprocess.TimeoutExpired:
           logger.error(f"LMMS rendering timed out after 600 seconds for {project_path}")
           return False
       except Exception as e:
           logger.error(f"An unexpected error occurred during rendering: {e}")
           return False

   # This method was in the original but seems to duplicate render_project functionality
   # with a confusing "TODO: Inject stem into template".
   # Removing it for clarity unless a specific use case for it is defined.
   # def render_with_stem( ... )

   def cleanup(self):
       """Clean up temporary files."""
       import shutil # Moved import here as it's only used here
       if self.temp_dir.exists():
           try:
               shutil.rmtree(self.temp_dir)
               logger.info(f"Cleaned up temp directory: {self.temp_dir}")
           except Exception as e:
               logger.error(f"Failed to cleanup temp directory {self.temp_dir}: {e}")

def main():
  parser = argparse.ArgumentParser(description="LMMS Headless Renderer")
  parser.add_argument("--project", help="Path to LMMS project file (.mmpz)")
  parser.add_argument("--template", help="Name of the template to use (from templates_dir, without .mmpz)")
  # --track argument might be misleading if LMMS 'render' command doesn't support it.
  # Consider removing or clarifying its behavior. For now, kept as in original.
  parser.add_argument("--track", help="Specific track to render (behavior depends on LMMS capabilities)")
  parser.add_argument("--output", required=True, help="Output audio file path (e.g., /data/output.wav)")
  parser.add_argument("--bpm", type=int, default=120, help="BPM (default: 120) - for template modification (if implemented)")
  parser.add_argument("--key", default="C", help="Musical key (default: C) - for template modification (if implemented)")
  parser.add_argument("--format", default="wav", choices=['wav', 'mp3', 'ogg', 'flac'], help="Output format (default: wav)")
  parser.add_argument("--samplerate", type=int, default=44100, help="Sample rate (default: 44100)")
  parser.add_argument("--bitdepth", type=int, default=16, choices=[16, 24, 32], help="Bit depth (default: 16)")
  parser.add_argument("--list-templates", action="store_true", help="List available LMMS templates")
  parser.add_argument("--verbose", action="store_true", help="Enable verbose logging")

  args = parser.parse_args()

  if args.verbose:
     logger.setLevel(logging.DEBUG)

  renderer = LMMSRenderer()
  output_json = {
      "success": False,
      "file": None,
      "template_used": args.template,
      "project_used": args.project,
      "error": None,
      "specs": {
          "bpm": args.bpm, # Included even if not used for modification, for record
          "key": args.key,
          "format": args.format,
          "sample_rate": args.samplerate,
          "bit_depth": args.bitdepth
      }
  }

  try:
     if args.list_templates:
        templates = renderer.list_templates()
        print(json.dumps({"templates": templates, "success": True}))
        sys.exit(0)

     if not args.project and not args.template:
        parser.error("Either --project or --template must be specified.") # Exits

     output_path = Path(args.output)

     project_to_render = None
     if args.project:
         project_to_render = Path(args.project)
         if not project_to_render.exists():
             output_json["error"] = f"Project file not found: {project_to_render}"
             logger.error(output_json["error"])
             print(json.dumps(output_json))
             sys.exit(1)
     elif args.template:
         temp_template_path = renderer.load_template(args.template)
         if not temp_template_path:
             output_json["error"] = f"Failed to load template: {args.template}"
             # Logger error already happened in load_template
             print(json.dumps(output_json))
             sys.exit(1)
         # Modify template (currently a no-op placeholder)
         project_to_render = renderer.modify_template(
             temp_template_path,
             bpm=args.bpm,
             key=args.key
         )
         output_json["template_used"] = args.template # Record which template was intended

     if project_to_render:
        render_success = renderer.render_project(
            project_to_render,
            output_path,
            output_format=args.format,
            sample_rate=args.samplerate,
            bit_depth=args.bitdepth,
            render_tracks=bool(args.track), # Passing these along
            track_name=args.track
        )
        output_json["success"] = render_success
        if render_success:
            output_json["file"] = str(output_path.resolve())
        else:
            output_json["error"] = output_json["error"] or "LMMS rendering process failed."
            # Specific error logged within render_project

  except Exception as e:
     logger.error(f"Unhandled exception in main: {e}", exc_info=True)
     output_json["error"] = str(e)
  finally:
     renderer.cleanup()
     print(json.dumps(output_json))
     sys.exit(0 if output_json["success"] else 1)

if __name__ == "__main__":
   main()
