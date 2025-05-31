// frontend/src/App.js - Versione Ottimizzata con Error Boundaries e Performance
import React, { useState, useEffect, useRef, useCallback, useMemo, Suspense, lazy } from 'react';
import { motion, AnimatePresence } from 'framer-motion';
import { Toaster, toast } from 'react-hot-toast';
import {
  Play, Pause, Square, Download, Zap, Music, Sliders, Settings, // Added Settings
  Headphones, Cpu, HardDrive, Activity, Loader, AlertCircle
} from 'lucide-react';

// Lazy load componenti pesanti
const WaveformVisualizer = lazy(() => import('./components/WaveformVisualizer'));
const AudioPlayer = lazy(() => import('./components/AudioPlayer'));

// Error Boundary Component
class ErrorBoundary extends React.Component {
  constructor(props) {
    super(props);
    this.state = { hasError: false, error: null, errorInfo: null }; // Added errorInfo
  }

 static getDerivedStateFromError(error) {
   return { hasError: true, error }; // Keep simple, actual error object is passed
 }

 componentDidCatch(error, errorInfo) {
   console.error('Error caught by boundary:', error, errorInfo);
   this.setState({ errorInfo }); // Store errorInfo for more detailed debugging if needed
   // You might want to log this to an error reporting service here
 }

 render() {
  if (this.state.hasError) {
    return (
      <div className="min-h-screen bg-gradient-to-br from-gray-900 via-purple-900 to-blue-900 flex items-center justify-center text-white p-4">
       <div className="text-center p-8 bg-black/30 backdrop-blur-lg rounded-xl max-w-md">
        <AlertCircle className="w-16 h-16 text-red-500 mx-auto mb-4" />
        <h2 className="text-2xl font-bold text-white mb-2">Oops! Something went wrong.</h2>
        <p className="text-gray-300 mb-4">
          An unexpected error occurred. Please try refreshing the page.
          If the problem persists, please contact support.
        </p>
        <button
          onClick={() => window.location.reload()}
          className="bg-purple-600 hover:bg-purple-700 text-white px-6 py-3 rounded-lg font-semibold transition-colors duration-150"
        >
          Refresh Page
        </button>
        {process.env.NODE_ENV === 'development' && this.state.error && (
          <details className="mt-4 text-left text-xs">
            <summary className="cursor-pointer text-gray-400 hover:text-white">Error Details (Dev Mode)</summary>
            <pre className="mt-2 p-2 bg-gray-800 rounded overflow-auto max-h-32">
              {this.state.error.toString()}
              {this.state.errorInfo && this.state.errorInfo.componentStack}
            </pre>
          </details>
        )}
       </div>
      </div>
    );
  }
  return this.props.children;
 }
}


// API Service ottimizzato con retry e caching
class APIService {
  constructor() {
    this.baseURL = process.env.REACT_APP_API_URL || '/api'; // Use relative path for proxy
    this.wsURL = process.env.REACT_APP_WS_URL ||
                 (window.location.protocol === "https:" ? "wss://" : "ws://") +
                 window.location.host + "/ws"; // Relative WebSocket URL

    this.cache = new Map();
    this.pendingRequests = new Map();
  }

  async request(endpoint, options = {}, retries = 2) { // Reduced default retries
    const method = options.method || 'GET';
    const cacheKey = method === 'GET' ? `${endpoint}-${JSON.stringify(options.body || {})}` : null;

    if (cacheKey && this.cache.has(cacheKey)) {
      const cached = this.cache.get(cacheKey);
      if (Date.now() - cached.timestamp < 300000) { // 5 min cache
        return cached.data;
      }
    }

    if (cacheKey && this.pendingRequests.has(cacheKey)) {
      return this.pendingRequests.get(cacheKey);
    }

    const requestPromise = this._makeRequest(endpoint, options, retries);
    if (cacheKey) {
        this.pendingRequests.set(cacheKey, requestPromise);
    }

    try {
      const result = await requestPromise;
      if (cacheKey) {
        this.cache.set(cacheKey, { data: result, timestamp: Date.now() });
      }
      return result;
    } finally {
      if (cacheKey) {
        this.pendingRequests.delete(cacheKey);
      }
    }
  }

  async _makeRequest(endpoint, options, retries) {
    for (let attempt = 0; attempt <= retries; attempt++) { // loop up to retries times
      try {
        const response = await fetch(`${this.baseURL}${endpoint}`, {
          ...options,
          headers: {
            'Content-Type': 'application/json',
            ...(options.headers || {}),
          },
          body: options.body ? JSON.stringify(options.body) : undefined
        });

        if (!response.ok) {
          const errorBody = await response.text(); // Try to get error body
          throw new Error(`HTTP ${response.status}: ${response.statusText}. Body: ${errorBody.substring(0,100)}`);
        }
        // Handle cases where response might be empty for 204 etc.
        const contentType = response.headers.get("content-type");
        if (contentType && contentType.indexOf("application/json") !== -1) {
            return await response.json();
        } else {
            return await response.text(); // Or handle as appropriate
        }

      } catch (error) {
        console.error(`Request to ${endpoint} failed (attempt ${attempt + 1}/${retries + 1}):`, error);
        if (attempt === retries) throw error; // Last attempt, rethrow
        await new Promise(resolve => setTimeout(resolve, 1000 * Math.pow(2, attempt))); // Exponential backoff
      }
    }
  }

  // Specific API calls
  async generateStem(params) { return this.request('/mcp/generate-melody', { method: 'POST', body: params }); }
  async composeTrack(params) { return this.request('/mcp/compose-track', { method: 'POST', body: params }); }
  async mixStems(params) { return this.request('/mcp/mix-master', { method: 'POST', body: params }); }

  connectWebSocket(onMessage) {
    let ws;
    let reconnectTimeoutId;
    let currentReconnectAttempts = 0;
    const maxReconnectAttempts = 5;

    const connect = () => {
      try {
        ws = new WebSocket(this.wsURL);
        ws.onopen = () => {
          console.log('WebSocket connected');
          currentReconnectAttempts = 0; // Reset attempts on successful connection
          toast.success('Real-time updates connected!');
        };
        ws.onmessage = (event) => {
          try {
            const data = JSON.parse(event.data);
            onMessage(data);
          } catch (error) { console.error('Failed to parse WebSocket message:', error); }
        };
        ws.onclose = (event) => {
          console.log('WebSocket disconnected. Code:', event.code, 'Reason:', event.reason);
          if (currentReconnectAttempts < maxReconnectAttempts) {
            const delay = 3000 * Math.pow(2, currentReconnectAttempts);
            toast.error(`Real-time connection lost. Reconnecting in ${delay/1000}s...`, { id: 'ws-reconnect' });
            reconnectTimeoutId = setTimeout(() => {
              currentReconnectAttempts++;
              connect();
            }, delay);
          } else {
            toast.error('Could not reconnect to real-time updates. Please refresh.', { duration: 10000, id: 'ws-reconnect-fail'});
          }
        };
        ws.onerror = (error) => {
          console.error('WebSocket error:', error);
          toast.error('Real-time connection error.', { id: 'ws-error'});
          // ws.close(); // Ensure it's closed before attempting reconnect on next onclose
        };
      } catch (error) {
        console.error('Failed to initialize WebSocket connection:', error);
      }
    };
    connect();
    return {
      close: () => {
        clearTimeout(reconnectTimeoutId);
        if (ws) { ws.close(1000, "User closed connection"); }
      },
      send: (message) => { // Optional: if frontend needs to send messages
        if (ws && ws.readyState === WebSocket.OPEN) {
          ws.send(JSON.stringify(message));
        } else {
          console.warn("WebSocket not open. Message not sent:", message);
        }
      }
    };
  }
}

// Main App Component
function App() {
  const [state, setState] = useState({
    activeTab: 'generate',
    isGenerating: false, // Unified loading state
    isPlaying: false,
    currentTrack: null,
    stems: [],
    generationHistory: [], // Limited size handled in update
    systemStatus: {
      gpu: { status: 'checking', usage: 0, memory: '0/0 GB' },
      cpu: { status: 'checking', usage: 0, cores: 0 },
      storage: { usage: 0, free: '0 GB' }
    }
  });

  const [generateForm, setGenerateForm] = useState({
    instrument: 'bass', prompt: '', duration: 30, temperature: 1.0, quality_threshold: 70
  });
  const [compositionForm, setCompositionForm] = useState({
    style: 'electronic', bpm: 128, key: 'C major', duration: 60, complexity: 7, title: ''
  });

  const apiService = useRef(new APIService());
  const wsConnection = useRef(null);

  // Memoized form validation
  const isFormValid = useMemo(() => ({
    generate: generateForm.prompt.trim().length >= 3 && generateForm.prompt.trim().length <= 500,
    compose: compositionForm.bpm >= 60 && compositionForm.bpm <= 200 &&
             (compositionForm.title.trim().length === 0 || compositionForm.title.trim().length <= 100) // Title optional, but limited if present
  }), [generateForm.prompt, compositionForm.bpm, compositionForm.title]);


  useEffect(() => {
    wsConnection.current = apiService.current.connectWebSocket(handleWebSocketMessage);
    return () => { if (wsConnection.current) wsConnection.current.close(); };
  }, []); // Empty dependency array ensures this runs only once

  const updateState = useCallback((updater) => {
    setState(prevState => typeof updater === 'function' ? updater(prevState) : {...prevState, ...updater});
  }, []);

  const handleWebSocketMessage = useCallback((data) => {
    switch (data.type) {
      case 'generation_progress':
        updateState({ isGenerating: data.progress < 100 });
        // Could update a progress bar here if data.progress is a percentage
        break;
      case 'generation_complete': // This could be for stems or full compositions
        const newTrack = data.result; // Assuming data.result is the track/stem object
        updateState(prev => ({
          ...prev,
          stems: newTrack.instrument ? [...prev.stems, newTrack] : prev.stems, // Add to stems if it's an instrument stem
          generationHistory: [newTrack, ...prev.generationHistory].slice(0, 20), // Keep last 20 items
          isGenerating: false,
          // Optionally, set currentTrack to the new item if desired
          // currentTrack: newTrack
        }));
        toast.success(`New ${newTrack.instrument || 'track'} ready: ${newTrack.title || newTrack.file || 'Unknown'}`);
        break;
      case 'system_status':
        updateState({ systemStatus: data.status });
        break;
      case 'error':
        toast.error(data.message || 'An error occurred via WebSocket.');
        updateState({ isGenerating: false });
        break;
      default:
        console.log('Unknown WebSocket message type:', data.type, data);
    }
  }, [updateState]);

  const commonApiCall = async (apiFn, params, toastId, successMsg) => {
    updateState({ isGenerating: true });
    toast.loading(successMsg.pending, { id: toastId });
    try {
      const result = await apiFn(params);
      if (result.success || (result.mcp_response && result.mcp_response.success)) { // n8n might wrap response
        const trackData = result.mcp_response || result; // Use unwrapped if direct

        updateState(prev => ({
          ...prev,
          currentTrack: trackData.file ? trackData : (trackData.composition ? trackData.composition : prev.currentTrack), // Handle different response structures
          generationHistory: [trackData, ...prev.generationHistory].slice(0, 20),
          stems: trackData.instrument ? [...prev.stems, trackData] : prev.stems
        }));
        toast.success(successMsg.success, { id: toastId });
        return trackData; // Return the actual data for further use if needed
      } else {
        throw new Error(result.error || result.message || 'API operation failed');
      }
    } catch (error) {
      console.error(`${toastId} error:`, error);
      toast.error(`${successMsg.error}: ${error.message}`, { id: toastId });
      return null; // Indicate failure
    } finally {
      updateState({ isGenerating: false });
    }
  };

  const generateStem = useCallback(async () => {
    if (!isFormValid.generate) {
      toast.error('Prompt must be 3-500 chars.'); return;
    }
    const result = await commonApiCall(
      (params) => apiService.current.generateStem(params),
      generateForm,
      'generate_stem',
      { pending: 'Generating AI stem...', success: 'Stem generated!', error: 'Stem generation failed' }
    );
    if (result) setGenerateForm(prev => ({ ...prev, prompt: '' })); // Clear prompt on success
  }, [generateForm, isFormValid.generate, commonApiCall]);

  const composeTrack = useCallback(async () => {
    if (!isFormValid.compose) {
      toast.error('Invalid composition parameters.'); return;
    }
    await commonApiCall(
      (params) => apiService.current.composeTrack(params),
      { ...compositionForm, title: compositionForm.title || `AI ${compositionForm.style} Track ${Date.now()}` },
      'compose_track',
      { pending: 'Composing full track...', success: 'Track composed!', error: 'Composition failed' }
    );
  }, [compositionForm, isFormValid.compose, commonApiCall]);

  const mixStems = useCallback(async () => {
    if (state.stems.length === 0) {
      toast.error('No stems to mix.'); return;
    }
    await commonApiCall(
      (params) => apiService.current.mixStems(params),
      { stems: state.stems.map(s => s.file), targetLUFS: -14 }, // Assuming s.file is the path/identifier
      'mix_stems',
      { pending: 'Mixing & mastering...', success: 'Mix complete!', error: 'Mixing failed' }
    );
  }, [state.stems, commonApiCall]);


  // Audio Controls
  const playTrack = useCallback((track) => {
    updateState({ currentTrack: track, isPlaying: true });
  }, [updateState]);

  const togglePlayback = useCallback(() => {
    updateState(prev => ({ ...prev, isPlaying: !prev.isPlaying }));
  }, [updateState]);

  const stopPlayback = useCallback(() => {
    updateState({ isPlaying: false });
    // The AudioPlayer component should also set its internal audio.currentTime = 0
  }, [updateState]);


  return (
    <ErrorBoundary>
      <div className="min-h-screen bg-gradient-to-br from-gray-900 via-purple-900 to-blue-900 text-white flex flex-col">
        <header className="bg-black/50 backdrop-blur-lg border-b border-purple-500/20 p-4 sticky top-0 z-40">
          <div className="flex items-center justify-between max-w-7xl mx-auto">
            <motion.div className="flex items-center space-x-3" initial={{ opacity: 0, x: -20 }} animate={{ opacity: 1, x: 0 }} transition={{ duration: 0.5 }}>
              <div className="bg-gradient-to-r from-purple-500 to-blue-500 p-2 rounded-lg shadow-lg">
                <Music className="w-8 h-8" />
              </div>
              <h1 className="text-2xl font-bold bg-gradient-to-r from-purple-400 to-blue-400 bg-clip-text text-transparent">
                AI Music Studio
              </h1>
            </motion.div>
            <motion.div className="flex items-center space-x-4 sm:space-x-6" initial={{ opacity: 0, x: 20 }} animate={{ opacity: 1, x: 0 }} transition={{ duration: 0.5, delay: 0.2 }}>
              <StatusIndicator icon={Cpu} label="GPU" value={`${state.systemStatus.gpu.usage}%`} status={state.systemStatus.gpu.status} />
              <StatusIndicator icon={Activity} label="CPU" value={`${state.systemStatus.cpu.usage}%`} status={state.systemStatus.cpu.status} />
              <StatusIndicator icon={HardDrive} label="Disk" value={state.systemStatus.storage.free} status="online" />
            </motion.div>
          </div>
        </header>

        <main className="max-w-7xl w-full mx-auto p-4 sm:p-6 flex-grow">
          <div className="grid grid-cols-1 lg:grid-cols-3 gap-6 h-full">
            <div className="lg:col-span-2 space-y-6">
              <TabNavigation activeTab={state.activeTab} onTabChange={(tab) => updateState({ activeTab: tab })} />
              <AnimatePresence mode="wait">
                {state.activeTab === 'generate' && (
                  <GeneratePanel form={generateForm} onChange={setGenerateForm} onSubmit={generateStem} isGenerating={state.isGenerating} isValid={isFormValid.generate} />
                )}
                {state.activeTab === 'compose' && (
                  <ComposePanel form={compositionForm} onChange={setCompositionForm} onSubmit={composeTrack} isGenerating={state.isGenerating} isValid={isFormValid.compose} />
                )}
                {state.activeTab === 'mix' && (
                  <MixPanel stems={state.stems} onMix={mixStems} isGenerating={state.isGenerating} onPlayStem={playTrack} />
                )}
              </AnimatePresence>
            </div>

            <div className="space-y-6">
              <Suspense fallback={<LoadingCard title="Player Loading..." />}>
                <CurrentTrackPlayer currentTrack={state.currentTrack} isPlaying={state.isPlaying} onPlayPause={togglePlayback} onStop={stopPlayback} />
              </Suspense>
              <GenerationHistory history={state.generationHistory} onSelectTrack={playTrack} />
              <SystemMonitor systemStatus={state.systemStatus} />
            </div>
          </div>
        </main>

        {state.isGenerating && <LoadingOverlay />}
        <Toaster position="bottom-right" toastOptions={{
            duration: 5000,
            style: { background: 'rgba(30,41,59,0.9)', color: '#fff', backdropFilter: 'blur(5px)', border: '1px solid rgba(255,255,255,0.1)'},
            success: { iconTheme: { primary: '#22c55e', secondary: '#fff' }},
            error: { iconTheme: { primary: '#ef4444', secondary: '#fff' }},
            loading: { iconTheme: { primary: '#6366f1', secondary: '#fff'}}
        }}/>
      </div>
    </ErrorBoundary>
  );
}

// Helper Components (Memoized for performance)
const StatusIndicator = React.memo(({ icon: Icon, label, value, status }) => (
  <div className="flex items-center space-x-1.5 sm:space-x-2" title={`${label} Status: ${status}`}>
    <Icon className={`w-4 h-4 sm:w-5 sm:h-5 ${status === 'online' ? 'text-green-400' : status === 'checking' ? 'text-yellow-400 animate-pulse' : 'text-red-400'}`} />
    <span className="text-xs sm:text-sm"><span className="hidden sm:inline">{label}: </span>{value}</span>
  </div>
));

const TabNavigation = React.memo(({ activeTab, onTabChange }) => (
  <motion.div className="bg-black/30 backdrop-blur-md rounded-xl p-1 border border-purple-500/30" initial={{ opacity: 0, y: -20 }} animate={{ opacity: 1, y: 0 }} transition={{ duration: 0.4 }}>
    <div className="flex space-x-1">
      {[
        { id: 'generate', label: 'Generate Stem', icon: Zap },
        { id: 'compose', label: 'Full Composition', icon: Music },
        { id: 'mix', label: 'Mix & Master', icon: Sliders }
      ].map(tab => (
        <motion.button
          key={tab.id}
          onClick={() => onTabChange(tab.id)}
          className={`flex-1 sm:flex-none flex items-center justify-center space-x-2 px-3 sm:px-4 py-2.5 sm:py-3 rounded-lg font-medium text-sm sm:text-base transition-all duration-200 ease-out
            ${activeTab === tab.id ? 'bg-gradient-to-r from-purple-600 to-blue-600 text-white shadow-xl' : 'text-gray-300 hover:text-white hover:bg-white/10'}`}
          whileHover={{ scale: activeTab === tab.id ? 1 : 1.03 }}
          whileTap={{ scale: 0.97 }}
          layout // Animate layout changes
        >
          <tab.icon className="w-4 h-4 sm:w-5 sm:h-5" />
          <span>{tab.label}</span>
        </motion.button>
      ))}
    </div>
  </motion.div>
));

// InputField Component
const InputField = React.memo(({ label, type = "text", value, onChange, placeholder, min, max, step, rows, maxLength, showMaxLength = false }) => (
  <div>
    <label className="block text-sm font-medium text-gray-300 mb-1.5">{label}</label>
    {type === "textarea" ? (
      <textarea value={value} onChange={onChange} placeholder={placeholder} rows={rows} maxLength={maxLength}
        className="w-full bg-gray-800/60 border border-gray-700 rounded-lg px-3.5 py-2.5 text-white focus:border-purple-500 focus:ring-1 focus:ring-purple-500 transition-colors duration-150 resize-none" />
    ) : type === "range" ? (
      <input type="range" min={min} max={max} step={step} value={value} onChange={onChange} className="w-full accent-purple-500 h-2 bg-gray-700 rounded-lg appearance-none cursor-pointer"/>
    ) : type === "select" ? (
      <select value={value} onChange={onChange} className="w-full bg-gray-800/60 border border-gray-700 rounded-lg px-3.5 py-2.5 text-white focus:border-purple-500 focus:ring-1 focus:ring-purple-500 transition-colors duration-150">
        {maxLength.map(opt => <option key={opt.value} value={opt.value}>{opt.label}</option>)} {/* Assuming maxLength here is misused for options array */}
      </select>
    ) : (
      <input type={type} value={value} onChange={onChange} placeholder={placeholder} min={min} max={max} step={step} maxLength={maxLength}
        className="w-full bg-gray-800/60 border border-gray-700 rounded-lg px-3.5 py-2.5 text-white focus:border-purple-500 focus:ring-1 focus:ring-purple-500 transition-colors duration-150" />
    )}
    {maxLength && type !== "range" && showMaxLength && (
      <p className="text-right text-xs text-gray-500 mt-1">{String(value).length}/{maxLength}</p>
    )}
  </div>
));


const GeneratePanel = React.memo(({ form, onChange, onSubmit, isGenerating, isValid }) => (
  <motion.div className="bg-black/30 backdrop-blur-md rounded-xl p-6 border border-purple-500/30 space-y-5" initial={{ opacity: 0, x: -20 }} animate={{ opacity: 1, x: 0 }} exit={{ opacity: 0, x: 20 }} transition={{ duration: 0.3 }}>
    <h2 className="text-xl font-semibold mb-2 flex items-center"><Zap className="w-6 h-6 mr-2.5 text-yellow-400" />Generate AI Stem</h2>
    <div className="grid grid-cols-1 md:grid-cols-2 gap-5">
      <InputField label="Instrument" type="select" value={form.instrument} onChange={(e) => onChange({ ...form, instrument: e.target.value })}
        maxLength={[ // Misusing maxLength for options array here as per original structure of InputField
            {value: "bass", label: "Bass"}, {value: "drums", label: "Drums"}, {value: "guitar", label: "Guitar"},
            {value: "piano", label: "Piano"}, {value: "synth", label: "Synth"}, {value: "vocal", label: "Vocal"}, {value: "other", label: "Other"}
        ]}/>
      <InputField label={`Duration: ${form.duration}s`} type="range" min="5" max="60" value={form.duration} onChange={(e) => onChange({ ...form, duration: parseInt(e.target.value) })} />
    </div>
    <InputField label="Musical Prompt" type="textarea" value={form.prompt} onChange={(e) => onChange({ ...form, prompt: e.target.value })} placeholder="e.g., 'funky bass line, 120 BPM, groovy'" rows="3" maxLength="500" showMaxLength={true}/>
    <div className="grid grid-cols-1 md:grid-cols-2 gap-5">
      <InputField label={`Creativity (Temperature): ${form.temperature}`} type="range" min="0.1" max="2.0" step="0.1" value={form.temperature} onChange={(e) => onChange({ ...form, temperature: parseFloat(e.target.value) })} />
      <InputField label={`Quality Threshold: ${form.quality_threshold}%`} type="range" min="50" max="95" value={form.quality_threshold} onChange={(e) => onChange({ ...form, quality_threshold: parseInt(e.target.value) })} />
    </div>
    <motion.button onClick={onSubmit} disabled={isGenerating || !isValid}
      className={`w-full font-bold py-3 px-6 rounded-lg transition-all duration-200 flex items-center justify-center text-base
        ${isGenerating || !isValid ? 'bg-gray-600/70 cursor-not-allowed text-gray-400' : 'bg-gradient-to-r from-purple-600 to-blue-600 hover:from-purple-700 hover:to-blue-700 text-white shadow-lg hover:shadow-xl'}`}
      whileHover={!isGenerating && isValid ? { scale: 1.02, boxShadow: "0px 0px 15px rgba(192, 132, 252, 0.5)" } : {}}
      whileTap={!isGenerating && isValid ? { scale: 0.98 } : {}}>
      {isGenerating ? <><Loader className="w-5 h-5 mr-2.5 animate-spin" />Generating...</> : <><Zap className="w-5 h-5 mr-2.5" />Generate Stem</>}
    </motion.button>
  </motion.div>
));

const ComposePanel = React.memo(({ form, onChange, onSubmit, isGenerating, isValid }) => (
    <motion.div className="bg-black/30 backdrop-blur-md rounded-xl p-6 border border-purple-500/30 space-y-5" initial={{ opacity: 0, x: -20 }} animate={{ opacity: 1, x: 0 }} exit={{ opacity: 0, x: 20 }} transition={{ duration: 0.3 }}>
        <h2 className="text-xl font-semibold mb-2 flex items-center"><Music className="w-6 h-6 mr-2.5 text-blue-400" />AI Full Composition</h2>
        <div className="grid grid-cols-1 md:grid-cols-3 gap-5">
            <InputField label="Style" type="select" value={form.style} onChange={e => onChange({...form, style: e.target.value})}
                maxLength={[ // Misusing for options
                    {value: "electronic", label: "Electronic"}, {value: "rock", label: "Rock"}, {value: "jazz", label: "Jazz"},
                    {value: "ambient", label: "Ambient"}, {value: "hip-hop", label: "Hip-Hop"}
                ]}/>
            <InputField label="BPM" type="number" min="60" max="200" value={form.bpm} onChange={e => onChange({...form, bpm: parseInt(e.target.value) || 120})} />
            <InputField label="Key" type="select" value={form.key} onChange={e => onChange({...form, key: e.target.value})}
                maxLength={[ // Misusing for options
                    'C major', 'G major', 'D major', 'A major', 'E major', 'F major', 'Bb major', 'Eb major',
                    'A minor', 'E minor', 'B minor', 'F# minor', 'C# minor', 'D minor', 'G minor', 'C minor'
                ].map(k => ({value: k, label: k}))}/>
        </div>
        <InputField label="Track Title (Optional)" type="text" value={form.title} onChange={e => onChange({...form, title: e.target.value})} placeholder="e.g., 'Cyberpunk Dreams'" maxLength="100" showMaxLength={true}/>
        <div className="grid grid-cols-1 md:grid-cols-2 gap-5">
            <InputField label={`Duration: ${form.duration}s`} type="range" min="30" max="180" value={form.duration} onChange={e => onChange({...form, duration: parseInt(e.target.value)})} />
            <InputField label={`Complexity: ${form.complexity}`} type="range" min="1" max="10" value={form.complexity} onChange={e => onChange({...form, complexity: parseInt(e.target.value)})} />
        </div>
        <motion.button onClick={onSubmit} disabled={isGenerating || !isValid}
            className={`w-full font-bold py-3 px-6 rounded-lg transition-all duration-200 flex items-center justify-center text-base
              ${isGenerating || !isValid ? 'bg-gray-600/70 cursor-not-allowed text-gray-400' : 'bg-gradient-to-r from-blue-600 to-purple-600 hover:from-blue-700 hover:to-purple-700 text-white shadow-lg hover:shadow-xl'}`}
            whileHover={!isGenerating && isValid ? { scale: 1.02, boxShadow: "0px 0px 15px rgba(129, 140, 248, 0.5)" } : {}}
            whileTap={!isGenerating && isValid ? { scale: 0.98 } : {}}>
            {isGenerating ? <><Loader className="w-5 h-5 mr-2.5 animate-spin" />Composing...</> : <><Music className="w-5 h-5 mr-2.5" />Compose Full Track</>}
        </motion.button>
    </motion.div>
));

const MixPanel = React.memo(({ stems, onMix, isGenerating, onPlayStem }) => (
    <motion.div className="bg-black/30 backdrop-blur-md rounded-xl p-6 border border-purple-500/30 space-y-5" initial={{ opacity: 0, x: -20 }} animate={{ opacity: 1, x: 0 }} exit={{ opacity: 0, x: 20 }} transition={{ duration: 0.3 }}>
        <h2 className="text-xl font-semibold mb-2 flex items-center"><Sliders className="w-6 h-6 mr-2.5 text-green-400" />Mix & Master</h2>
        <div className="space-y-3 max-h-96 overflow-y-auto pr-2">
            {stems.length === 0 ? (
                <div className="text-center py-10 text-gray-400"><Music className="w-12 h-12 mx-auto mb-3 opacity-40" /><p>No stems available. Generate some stems first!</p></div>
            ) : (
                stems.map((stem, index) => (
                    <motion.div key={stem.file || index} // Use stem.file if available and unique
                        className="bg-gray-800/60 rounded-lg p-3.5 flex items-center justify-between hover:bg-gray-700/60 transition-colors"
                        initial={{ opacity: 0, y: 15 }} animate={{ opacity: 1, y: 0 }} transition={{ duration: 0.3, delay: index * 0.07 }}>
                        <div className="flex items-center space-x-3.5 flex-1 min-w-0">
                            <div className={`w-2.5 h-2.5 rounded-full ${stem.instrument === 'bass' ? 'bg-red-500' : stem.instrument === 'drums' ? 'bg-yellow-500' : stem.instrument === 'guitar' ? 'bg-blue-500' : stem.instrument === 'piano' ? 'bg-purple-500' : 'bg-green-500'}`} />
                            <span className="font-medium capitalize truncate text-sm">{stem.instrument || 'Unknown Stem'}</span>
                            <span className="text-xs text-gray-400 truncate">Q: {stem.quality_score || 'N/A'}%</span>
                        </div>
                        <motion.button onClick={() => onPlayStem(stem)}
                            className="p-2 bg-purple-600/30 hover:bg-purple-600/50 rounded-md transition-colors"
                            whileHover={{ scale: 1.1 }} whileTap={{ scale: 0.9 }}>
                            <Play className="w-4 h-4" />
                        </motion.button>
                    </motion.div>
                ))
            )}
        </div>
        <motion.button onClick={onMix} disabled={isGenerating || stems.length === 0}
            className={`w-full font-bold py-3 px-6 rounded-lg transition-all duration-200 flex items-center justify-center text-base
              ${isGenerating || stems.length === 0 ? 'bg-gray-600/70 cursor-not-allowed text-gray-400' : 'bg-gradient-to-r from-green-600 to-blue-600 hover:from-green-700 hover:to-blue-700 text-white shadow-lg hover:shadow-xl'}`}
            whileHover={(isGenerating || stems.length === 0) ? {} : { scale: 1.02, boxShadow: "0px 0px 15px rgba(34, 197, 94, 0.5)" }}
            whileTap={(isGenerating || stems.length === 0) ? {} : { scale: 0.98 }}>
            {isGenerating ? <><Loader className="w-5 h-5 mr-2.5 animate-spin" />Mixing...</> : <><Sliders className="w-5 h-5 mr-2.5" />Mix & Master ({stems.length} stems)</>}
        </motion.button>
    </motion.div>
));

const CurrentTrackPlayer = React.memo(({ currentTrack, isPlaying, onPlayPause, onStop }) => (
    <motion.div className="bg-black/30 backdrop-blur-md rounded-xl p-6 border border-purple-500/30" initial={{ opacity: 0, x: 20 }} animate={{ opacity: 1, x: 0 }} transition={{ duration: 0.4, delay: 0.1 }}>
        <h3 className="text-lg font-semibold mb-3 flex items-center"><Headphones className="w-5 h-5 mr-2.5 text-purple-400" />Now Playing</h3>
        {currentTrack ? (
            <div className="space-y-3.5">
                <div className="text-center">
                    <h4 className="font-medium text-purple-300 truncate" title={currentTrack.title || currentTrack.metadata?.title || 'Untitled Track'}>{currentTrack.title || currentTrack.metadata?.title || 'Untitled Track'}</h4>
                    <p className="text-xs text-gray-400">{currentTrack.duration || 30}s • Quality: {currentTrack.quality_score || 'N/A'}%</p>
                </div>
                <Suspense fallback={<div className="h-20 bg-gray-800/50 rounded-lg animate-pulse"></div>}>
                    <WaveformVisualizer src={currentTrack.file} isActive={isPlaying} className="w-full h-20" />
                </Suspense>
                <Suspense fallback={<div className="h-16 bg-gray-800/50 rounded-lg animate-pulse"></div>}>
                    <AudioPlayer currentTrack={currentTrack} isPlaying={isPlaying} onPlayPause={onPlayPause} onStop={onStop} />
                </Suspense>
            </div>
        ) : (
            <div className="text-center py-10 text-gray-400"><Music className="w-12 h-12 mx-auto mb-3 opacity-40" /><p>No track loaded.</p><p className="text-sm">Generate or compose something!</p></div>
        )}
    </motion.div>
));

const GenerationHistory = React.memo(({ history, onSelectTrack }) => (
    <motion.div className="bg-black/30 backdrop-blur-md rounded-xl p-6 border border-purple-500/30" initial={{ opacity: 0, x: 20 }} animate={{ opacity: 1, x: 0 }} transition={{ duration: 0.4, delay: 0.2 }}>
        <h3 className="text-lg font-semibold mb-3 flex items-center justify-between">
            <span className="flex items-center"><Activity className="w-5 h-5 mr-2.5 text-blue-400" />Recent Generations</span>
            <span className="text-sm text-gray-400 bg-gray-700/50 px-2 py-0.5 rounded-full">{history.length}</span>
        </h3>
        <div className="space-y-2.5 max-h-60 overflow-y-auto pr-1">
            {history.length === 0 ? (
                <div className="text-center py-5 text-gray-400"><p className="text-sm">No generations yet.</p></div>
            ) : (
                history.map((item, index) => ( // No reverse, new items added to front
                    <motion.div key={item.file || index} // Use unique ID if available
                        className="bg-gray-800/60 rounded-lg p-3 hover:bg-gray-700/60 transition-colors cursor-pointer"
                        initial={{ opacity: 0, y: 10 }} animate={{ opacity: 1, y: 0 }} transition={{ duration: 0.25, delay: index * 0.03 }}
                        onClick={() => onSelectTrack(item)}>
                        <div className="flex items-center justify-between">
                            <div className="min-w-0">
                                <p className="font-medium text-sm truncate" title={item.title || (item.instrument ? `${item.instrument} stem` : 'Composition')}>{item.title || (item.instrument ? `${item.instrument} stem` : 'Composition')}</p>
                                <p className="text-xs text-gray-400">{(item.generation_time || item.processing_time?.total || 0).toFixed(1)}s • Q: {item.quality_score || 'N/A'}%</p>
                            </div>
                            <div className="flex items-center space-x-1.5 flex-shrink-0">
                                <motion.button onClick={(e) => { e.stopPropagation(); onSelectTrack(item); }} className="p-1.5 hover:bg-purple-600/40 rounded transition-colors" whileHover={{ scale: 1.1 }} whileTap={{ scale: 0.9 }}><Play className="w-3.5 h-3.5" /></motion.button>
                                <motion.button onClick={(e) => { e.stopPropagation(); if (item.file) { const a = document.createElement('a'); a.href = `/api/download/${item.file}`; a.download = `${item.title || item.instrument || 'track'}.wav`; a.click(); } }} className="p-1.5 hover:bg-green-600/40 rounded transition-colors" whileHover={{ scale: 1.1 }} whileTap={{ scale: 0.9 }}><Download className="w-3.5 h-3.5" /></motion.button>
                            </div>
                        </div>
                    </motion.div>
                ))
            )}
        </div>
    </motion.div>
));

const SystemMonitor = React.memo(({ systemStatus }) => (
    <motion.div className="bg-black/30 backdrop-blur-md rounded-xl p-6 border border-purple-500/30" initial={{ opacity: 0, x: 20 }} animate={{ opacity: 1, x: 0 }} transition={{ duration: 0.4, delay: 0.3 }}>
        <h3 className="text-lg font-semibold mb-4 flex items-center"><Settings className="w-5 h-5 mr-2.5 text-gray-400" />System Status</h3>
        <div className="space-y-3.5">
            {['gpu', 'cpu', 'storage'].map(key => (
                <div key={key}>
                    <div className="flex items-center justify-between mb-1 text-sm">
                        <span className="capitalize">{key}</span>
                        <span className="font-medium">{systemStatus[key].usage}% {key === 'storage' ? `(${systemStatus[key].free} free)` : `(${systemStatus[key].memory || systemStatus[key].cores + ' cores'})`}</span>
                    </div>
                    <div className="w-full bg-gray-700/70 rounded-full h-2.5 overflow-hidden">
                        <motion.div
                            className={`h-full rounded-full
                                ${key === 'gpu' ? 'bg-gradient-to-r from-green-500 to-yellow-500' :
                                  key === 'cpu' ? 'bg-gradient-to-r from-blue-500 to-purple-500' :
                                                  'bg-gradient-to-r from-yellow-500 to-red-500'}`}
                            initial={{ width: 0 }}
                            animate={{ width: `${systemStatus[key].usage}%` }}
                            transition={{ duration: 0.5, ease: "easeOut" }}
                        />
                    </div>
                </div>
            ))}
        </div>
    </motion.div>
));

const LoadingCard = React.memo(({title = "Loading..."}) => (
  <div className="bg-black/30 backdrop-blur-md rounded-xl p-6 border border-purple-500/30">
    <div className="animate-pulse">
      <div className="h-5 bg-gray-700/50 rounded w-3/5 mb-4"></div>
      <div className="h-20 bg-gray-700/50 rounded mb-4"></div>
      <div className="h-12 bg-gray-700/50 rounded"></div>
      <p className="text-center text-sm text-gray-500 mt-2">{title}</p>
    </div>
  </div>
));

const LoadingOverlay = () => (
  <motion.div className="fixed inset-0 bg-black/70 backdrop-blur-sm flex items-center justify-center z-50" initial={{ opacity: 0 }} animate={{ opacity: 1 }} exit={{ opacity: 0 }}>
    <motion.div className="bg-gray-900/80 backdrop-blur-lg rounded-xl p-8 text-center border border-purple-500/50 shadow-2xl" initial={{ scale: 0.7, opacity: 0 }} animate={{ scale: 1, opacity: 1 }} exit={{ scale: 0.7, opacity: 0 }} transition={{ type: "spring", stiffness: 260, damping: 20 }}>
      <div className="relative mb-5">
        <motion.div className="w-16 h-16 border-4 border-purple-500/30 border-t-purple-500 rounded-full animate-spin mx-auto"
          animate={{ rotate: 360 }} transition={{ duration: 0.8, repeat: Infinity, ease: "linear" }} />
        <Music className="w-8 h-8 text-blue-400 absolute top-1/2 left-1/2 transform -translate-x-1/2 -translate-y-1/2" />
      </div>
      <h3 className="text-xl font-semibold mb-1.5 text-white">AI is creating music...</h3>
      <p className="text-gray-400 text-sm">This may take a few moments.</p>
    </motion.div>
  </motion.div>
);

export default App;
