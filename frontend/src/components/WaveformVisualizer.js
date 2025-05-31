// frontend/src/components/WaveformVisualizer.js
import React, { useEffect, useRef } from 'react';
import { motion } from 'framer-motion'; // Added for consistency if animations are desired here

const WaveformVisualizer = ({ src, isActive, className = 'w-full h-20' }) => {
  const canvasRef = useRef(null);
  const animationFrameId = useRef(null); // For cleaning up animation frame

  useEffect(() => {
    if (!canvasRef.current) return;

    const canvas = canvasRef.current;
    const ctx = canvas.getContext('2d');
    let audioContext;
    let analyser;
    let source;
    let dataArray;

    // If a real audio source `src` is provided and meant to be analyzed:
    // This part would require loading the actual audio data and analyzing its frequencies.
    // The original script had a placeholder random animation.
    // For a more meaningful visualizer tied to `src`, you'd use Web Audio API.
    // However, since `src` is just a file path and not an audio element,
    // the random animation is more feasible without complex audio loading here.

    const drawRandomWaveform = () => {
      if (!canvasRef.current) return; // Ensure canvas still exists
      const width = canvas.width;
      const height = canvas.height;
      ctx.clearRect(0, 0, width, height);

      const barCount = isActive ? 60 : 40; // More bars when active
      const barWidth = width / barCount;
      const time = Date.now() * 0.002; // Time factor for animation

      for (let i = 0; i < barCount; i++) {
        const normalizedI = i / barCount;
        // Create a more dynamic and visually appealing random height
        const randomFactor = Math.sin(normalizedI * Math.PI * 2 + time + Math.sin(time * 0.5 + i * 0.3)) * 0.4 + 0.6;
        const barHeight = randomFactor * height * (isActive ? 0.75 : 0.25);

        const x = i * barWidth;
        const y = (height - barHeight) / 2;

        // Dynamic coloring
        const hue = (normalizedI * 100 + time * 30) % 360;
        const saturation = isActive ? 70 : 40;
        const lightness = isActive ? 55 : 30;
        ctx.fillStyle = `hsl(${hue}, ${saturation}%, ${lightness}%)`;

        ctx.fillRect(x, y, barWidth -1, barHeight); // barWidth -1 for small gap
      }
      animationFrameId.current = requestAnimationFrame(drawRandomWaveform);
    };

    drawRandomWaveform(); // Start the animation

    return () => {
      if (animationFrameId.current) {
        cancelAnimationFrame(animationFrameId.current);
      }
      if (source) source.disconnect();
      if (audioContext) audioContext.close();
    };
  }, [isActive, src]); // Redraw when isActive or src changes (though src isn't used for data here)

  return (
    <motion.canvas
      ref={canvasRef}
      width={300} // Intrinsic width
      height={80}  // Intrinsic height
      className={`${className} bg-gray-800/50 rounded-lg shadow-inner`}
      initial={{ opacity: 0.5 }}
      animate={{ opacity: 1 }}
      transition={{ duration: 0.4 }}
    />
  );
};

export default React.memo(WaveformVisualizer); // Memoize for performance
