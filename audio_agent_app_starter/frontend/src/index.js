// frontend/src/index.js
import React, { Suspense } from 'react'; // Added Suspense
import ReactDOM from 'react-dom/client';
import './index.css';
import App from './App'; // App itself is not lazy loaded, but components within it are
// import reportWebVitals from './reportWebVitals'; // The file AI-Music-Studio-_parte2_.txt does not mention reportWebVitals.js
import { Toaster } from 'react-hot-toast';


// Performance monitoring (simplified, assuming no reportWebVitals.js for now)
// If you have a reportWebVitals.js, you can import and use it here.
// For now, let's define a simple performance logger.
const logPerformanceMetric = ({ name, value, delta, id }) => {
  // Example: send to an analytics endpoint or console.log
  // In a real app, you might filter for specific metrics or send to a service.
  if (process.env.NODE_ENV === 'development') {
    console.log(`Perf: ${name} (${id}): ${value.toFixed(2)}ms, Delta: ${delta.toFixed(2)}`);
  }
};

// Basic web-vitals reporting (if you want to include it without the separate file)
// import { getCLS, getFID, getFCP, getLCP, getTTFB } from 'web-vitals';
// getCLS(logPerformanceMetric);
// getFID(logPerformanceMetric);
// getFCP(logPerformanceMetric);
// getLCP(logPerformanceMetric);
// getTTFB(logPerformanceMetric);


// Error boundary for the entire app - though App.js has its own. This can be a root fallback.
class RootErrorBoundary extends React.Component {
  constructor(props) {
    super(props);
    this.state = { hasError: false, error: null };
  }

  static getDerivedStateFromError(error) {
    return { hasError: true, error };
  }

  componentDidCatch(error, errorInfo) {
    console.error("Root Error Boundary Caught:", error, errorInfo);
    // Log to an error reporting service
  }

  render() {
    if (this.state.hasError) {
      return (
        <div style={{ padding: '20px', textAlign: 'center', color: 'white', background: '#1a1a2e', minHeight: '100vh' }}>
          <h1>Application Error</h1>
          <p>Sorry, something went critically wrong. Please try refreshing the application.</p>
          <button onClick={() => window.location.reload()} style={{padding: '10px', background: '#764ba2', border: 'none', color: 'white', borderRadius: '5px', cursor: 'pointer'}}>
            Refresh
          </button>
          {process.env.NODE_ENV === 'development' && this.state.error && (
            <pre style={{ marginTop: '20px', background: '#333', padding: '10px', borderRadius: '5px', overflowX: 'auto' }}>
              {this.state.error.toString()}
            </pre>
          )}
        </div>
      );
    }
    return this.props.children;
  }
}

const root = ReactDOM.createRoot(document.getElementById('root'));

// Main render function
root.render(
  <React.StrictMode>
    <RootErrorBoundary>
      <Suspense fallback={
        <div style={{ display: 'flex', justifyContent: 'center', alignItems: 'center', height: '100vh', background: 'linear-gradient(135deg, #1a1a2e 0%, #16213e 50%, #0f3460 100%)', color: 'white', fontFamily: 'sans-serif' }}>
          <div style={{ textAlign: 'center' }}>
            <div style={{ width: '50px', height: '50px', border: '3px solid rgba(255,255,255,0.1)', borderTopColor: '#667eea', borderRadius: '50%', animation: 'spin 1s linear infinite', margin: '0 auto 20px auto' }}></div>
            Loading AI Music Studio...
          </div>
          <style>{`
            @keyframes spin { to { transform: rotate(360deg); } }
          `}</style>
        </div>
      }>
        <App />
      </Suspense>
      <Toaster
        position="bottom-right" // Changed from top-right in App.js for variety, or keep consistent
        toastOptions={{
          duration: 4000,
          style: {
            background: 'rgba(25, 25, 40, 0.85)', // Slightly different style for global toaster
            color: '#e0e0e0',
            backdropFilter: 'blur(8px)',
            border: '1px solid rgba(255, 255, 255, 0.15)',
            boxShadow: '0 4px 12px rgba(0,0,0,0.3)',
            borderRadius: '8px',
            fontSize: '14px',
            padding: '12px 18px',
          },
          success: {
            iconTheme: { primary: '#34d399', secondary: '#1f2937' }, // Tailwind green-400
          },
          error: {
            iconTheme: { primary: '#f87171', secondary: '#1f2937' }, // Tailwind red-400
          },
          loading: { // Added loading theme
            iconTheme: { primary: '#8b5cf6', secondary: '#1f2937' } // Tailwind violet-500
          }
        }}
      />
    </RootErrorBoundary>
  </React.StrictMode>
);

// If you want to start measuring performance in your app, pass a function
// to log results (for example: reportWebVitals(console.log))
// or send to an analytics endpoint. Learn more: https://bit.ly/CRA-vitals
// reportWebVitals(logPerformanceMetric); // Uncomment if you have reportWebVitals.js and want to use it.

// Global error handlers (optional, as ErrorBoundary should catch most React errors)
window.addEventListener('error', (event) => {
  console.error('Global unhandled error:', event.error, event.message);
  // Log to external service
});
window.addEventListener('unhandledrejection', (event) => {
  console.error('Global unhandled promise rejection:', event.reason);
  // Log to external service
});

// Remove loading screen once React app is fully initialized
window.addEventListener('load', () => {
  const loadingScreen = document.getElementById('loading-screen');
  if (loadingScreen) {
    loadingScreen.style.opacity = '0';
    setTimeout(() => {
      loadingScreen.style.display = 'none';
      document.body.classList.add('app-loaded'); // From index.html
    }, 500); // Match CSS transition
  }
});
