// frontend/src/components/AudioPlayer.js
import React, { useEffect, useRef, useState, useCallback } from 'react';
import { Play, Pause, Square, Download, Volume2, RotateCcw, VolumeX, Volume1 } from 'lucide-react'; // Added more volume icons
import { motion } from 'framer-motion';
import toast from 'react-hot-toast';


const AudioPlayer = ({ currentTrack, isPlaying, onPlayPause, onStop }) => {
  const audioRef = useRef(null);
  const [currentTime, setCurrentTime] = useState(0);
  const [duration, setDuration] = useState(0);
  const [volume, setVolume] = useState(0.8);
  const [isLoaded, setIsLoaded] = useState(false);
  const [isSeeking, setIsSeeking] = useState(false);


  // Effect to handle playing/pausing when isPlaying or currentTrack changes
  useEffect(() => {
    const audio = audioRef.current;
    if (!audio || !currentTrack) return;

    if (isPlaying && audio.src) {
      audio.play().catch(error => {
        console.error("Error playing audio:", error);
        toast.error("Could not play audio. File might be missing or corrupt.");
        onPlayPause(); // Toggle back the play state
      });
    } else {
      audio.pause();
    }
  }, [isPlaying, currentTrack, onPlayPause]);

  // Effect to load new track
  useEffect(() => {
    const audio = audioRef.current;
    if (!audio) return;

    setIsLoaded(false);
    setCurrentTime(0);
    setDuration(0);

    if (currentTrack && currentTrack.file) {
      // Construct URL carefully. Assuming /api/audio/ is handled by Nginx to serve from /data/
      // The file path in currentTrack.file might be absolute like /data/stems/file.wav
      // or relative. Nginx alias should handle this.
      // For local dev, proxy might be needed if /api/audio isn't set up in webpack dev server.
      const audioUrl = currentTrack.file.startsWith('/data/') ?
                       `/api/audio${currentTrack.file.substring(5)}` : // if path is /data/stems/file.wav -> /api/audio/stems/file.wav
                       `/api/audio/${currentTrack.file}`; // Fallback for just filename
      audio.src = audioUrl;
      audio.load(); // Explicitly load
    } else {
      audio.removeAttribute('src'); // Clear src if no track
    }
  }, [currentTrack]);


  // Effect for audio event listeners
  useEffect(() => {
    const audio = audioRef.current;
    if (!audio) return;

    const handleTimeUpdate = () => { if (!isSeeking) setCurrentTime(audio.currentTime); };
    const handleLoadedMetadata = () => { setDuration(audio.duration); setIsLoaded(true); };
    const handleEnded = () => { onStop(); setCurrentTime(audio.duration); }; // Set to end for progress bar
    const handleError = (e) => {
        console.error("Audio Player Error:", e);
        toast.error("Error loading or playing audio track.");
        setIsLoaded(false); // Reset loaded state
    };


    audio.addEventListener('timeupdate', handleTimeUpdate);
    audio.addEventListener('loadedmetadata', handleLoadedMetadata);
    audio.addEventListener('ended', handleEnded);
    audio.addEventListener('error', handleError);

    return () => {
      audio.removeEventListener('timeupdate', handleTimeUpdate);
      audio.removeEventListener('loadedmetadata', handleLoadedMetadata);
      audio.removeEventListener('ended', handleEnded);
      audio.removeEventListener('error', handleError);
    };
  }, [onStop, isSeeking]);

  // Effect for volume changes
  useEffect(() => {
    if (audioRef.current) {
      audioRef.current.volume = volume;
    }
  }, [volume]);

  const formatTime = useCallback((timeInSeconds) => {
    if (isNaN(timeInSeconds) || timeInSeconds === Infinity) return '0:00';
    const minutes = Math.floor(timeInSeconds / 60);
    const seconds = Math.floor(timeInSeconds % 60);
    return `${minutes}:${seconds.toString().padStart(2, '0')}`;
  }, []);

  const handleSeek = useCallback((event) => {
    const audio = audioRef.current;
    if (!audio || !duration || !isLoaded) return;

    const progressBar = event.currentTarget;
    const clickPosition = event.clientX - progressBar.getBoundingClientRect().left;
    const percentage = Math.max(0, Math.min(1, clickPosition / progressBar.offsetWidth));
    const newTime = percentage * duration;

    audio.currentTime = newTime;
    setCurrentTime(newTime); // Update UI immediately
  }, [duration, isLoaded]);

  const handleVolumeChange = useCallback((event) => {
    setVolume(parseFloat(event.target.value));
  }, []);

  const handleDownload = useCallback(() => {
    if (currentTrack?.file) {
      const fileName = currentTrack.title || currentTrack.instrument || 'track';
      // Similar to src, construct download URL
      const downloadUrl = currentTrack.file.startsWith('/data/') ?
                         `/api/download${currentTrack.file.substring(5)}` :
                         `/api/download/${currentTrack.file}`;

      const a = document.createElement('a');
      a.href = downloadUrl;
      // Ensure the filename has an extension, default to .wav if not obvious
      a.download = fileName.includes('.') ? fileName : `${fileName}.wav`;
      document.body.appendChild(a);
      a.click();
      document.body.removeChild(a);
      toast.success(`Downloading ${a.download}`);
    } else {
      toast.error("No track file available for download.");
    }
  }, [currentTrack]);

  const VolumeIcon = volume === 0 ? VolumeX : volume < 0.5 ? Volume1 : Volume2;

  if (!currentTrack) {
    return (
        <div className="text-center text-gray-500 py-4 text-sm">
            No track selected.
        </div>
    );
  }

  return (
    <div className="bg-gray-800/50 p-4 rounded-lg shadow-md space-y-3">
      <audio ref={audioRef} preload="metadata" />

      <div className="flex items-center justify-center space-x-3">
        <motion.button onClick={onPlayPause} disabled={!isLoaded}
          className="p-2.5 bg-gradient-to-br from-purple-600 to-blue-600 hover:from-purple-700 hover:to-blue-700 rounded-full text-white disabled:opacity-50 disabled:cursor-not-allowed"
          whileHover={{ scale: isLoaded ? 1.1 : 1 }} whileTap={{ scale: isLoaded ? 0.9 : 1 }}>
          {isPlaying ? <Pause className="w-5 h-5" /> : <Play className="w-5 h-5" />}
        </motion.button>
        <motion.button onClick={onStop} disabled={!isLoaded}
          className="p-2.5 bg-gray-600 hover:bg-gray-700 rounded-full text-white disabled:opacity-50"
          whileHover={{ scale: isLoaded ? 1.1 : 1 }} whileTap={{ scale: isLoaded ? 0.9 : 1 }}>
          <Square className="w-5 h-5" />
        </motion.button>
        <motion.button onClick={handleDownload} disabled={!currentTrack?.file}
          className="p-2.5 bg-green-600 hover:bg-green-700 rounded-full text-white disabled:opacity-50"
          whileHover={{ scale: currentTrack?.file ? 1.1 : 1 }} whileTap={{ scale: currentTrack?.file ? 0.9 : 1 }}>
          <Download className="w-5 h-5" />
        </motion.button>
      </div>

      <div className="space-y-1">
        <div className="flex justify-between text-xs text-gray-400 px-1">
          <span>{formatTime(currentTime)}</span>
          <span>{formatTime(duration)}</span>
        </div>
        <div className="w-full h-2 bg-gray-700 rounded-full cursor-pointer"
             onMouseDown={() => setIsSeeking(true)}
             onMouseUp={() => setIsSeeking(false)}
             onMouseMove={(e) => { if(isSeeking) handleSeek(e);}}
             onClick={handleSeek} // For click seek
        >
          <motion.div className="h-full bg-gradient-to-r from-purple-500 to-blue-500 rounded-full"
            style={{ width: `${duration && isLoaded ? (currentTime / duration) * 100 : 0}%` }}
            transition={{ duration: 0.05, ease: "linear" }} />
        </div>
      </div>

      <div className="flex items-center space-x-2 justify-center">
        <VolumeIcon className="w-4 h-4 text-gray-400 cursor-pointer" onClick={() => setVolume(v => v > 0 ? 0 : 0.8)}/>
        <input type="range" min="0" max="1" step="0.01" value={volume}
          onChange={handleVolumeChange}
          className="w-20 h-1.5 accent-purple-500 bg-gray-600 rounded-lg appearance-none cursor-pointer" />
        <span className="text-xs text-gray-400 w-8 text-right">{Math.round(volume * 100)}%</span>
      </div>
      {!isLoaded && !isPlaying && currentTrack?.file && (
        <div className="text-center text-xs text-yellow-400 animate-pulse">Loading audio...</div>
      )}
    </div>
  );
};

export default React.memo(AudioPlayer);
