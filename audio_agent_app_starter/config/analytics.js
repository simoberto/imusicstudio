// audio_agent_app_starter/config/analytics.js

/**
 * AI Music Studio - Analytics Configuration and Tracking
 *
 * This module centralizes the configuration for analytics services (e.g., Google Analytics, Mixpanel)
 * and provides a unified function to track events.
 *
 * Environment variables are used to enable/disable services and set IDs/tokens,
 * allowing different configurations for development, staging, and production.
 *
 * Example Usage in a React Component:
 * import { trackEvent, analyticsConfig } from './config/analytics'; // Adjust path as needed
 *
 * const MyComponent = () => {
 *   const handleClick = () => {
 *     trackEvent(analyticsConfig.events.GENERATION_STARTED, { instrument: 'guitar', complexity: 5 });
 *   };
 *   return <button onClick={handleClick}>Generate Guitar</button>;
 * };
 */

export const analyticsConfig = {
  // Google Analytics (GA4 typically)
  googleAnalytics: {
    measurementId: process.env.REACT_APP_GA_MEASUREMENT_ID || null, // e.g., 'G-XXXXXXXXXX'
    enabled: process.env.NODE_ENV === 'production' && !!process.env.REACT_APP_GA_MEASUREMENT_ID,
  },

  // Mixpanel
  mixpanel: {
    token: process.env.REACT_APP_MIXPANEL_TOKEN || null, // Your Mixpanel project token
    enabled: process.env.NODE_ENV === 'production' && !!process.env.REACT_APP_MIXPANEL_TOKEN,
  },

  // Placeholder for other analytics services like Amplitude, Segment, etc.
  // amplitude: {
  //   apiKey: process.env.REACT_APP_AMPLITUDE_API_KEY || null,
  //   enabled: process.env.NODE_ENV === 'production' && !!process.env.REACT_APP_AMPLITUDE_API_KEY,
  // },

  // Custom backend analytics endpoint (if you have one for server-side logging of events)
  customAnalyticsEndpoint: {
    url: process.env.REACT_APP_CUSTOM_ANALYTICS_URL || '/api/analytics/track', // Example endpoint
    enabled: !!process.env.REACT_APP_CUSTOM_ANALYTICS_URL, // Enable if URL is set
  },

  // Standardized event names
  // Using a structure helps maintain consistency across the application.
  events: {
    // User Authentication & Account
    USER_REGISTERED: 'user_registered',
    USER_LOGIN: 'user_login_success',
    USER_LOGOUT: 'user_logout',
    USER_PASSWORD_RESET_REQUEST: 'user_password_reset_request',
    USER_PROFILE_UPDATED: 'user_profile_updated',
    SUBSCRIPTION_STARTED: 'subscription_started',    // e.g., { plan: 'pro', term: 'monthly' }
    SUBSCRIPTION_CANCELLED: 'subscription_cancelled',// e.g., { plan: 'pro' }
    SUBSCRIPTION_UPGRADED: 'subscription_upgraded',  // e.g., { from_plan: 'free', to_plan: 'pro' }
    SUBSCRIPTION_DOWNGRADED: 'subscription_downgraded',

    // Core Music Generation Actions
    GENERATION_STARTED: 'generation_started',        // e.g., { type: 'stem', instrument: 'bass', duration: 30 }
                                                     // e.g., { type: 'composition', style: 'electronic', bpm: 120 }
    GENERATION_COMPLETED: 'generation_completed',    // e.g., { type: 'stem', file_id: 'xyz', quality_score: 85 }
    GENERATION_FAILED: 'generation_failed',          // e.g., { type: 'stem', error_message: 'GPU timeout' }
    TRACK_PLAYED: 'track_played',                    // e.g., { track_id: 'xyz', source: 'history' }
    TRACK_DOWNLOADED: 'track_downloaded',            // e.g., { track_id: 'xyz', format: 'wav' }
    TRACK_SHARED: 'track_shared',                    // e.g., { track_id: 'xyz', platform: 'twitter' }
    TRACK_FAVORITED: 'track_favorited',              // e.g., { track_id: 'xyz' }

    // Mixing and Mastering
    MIXING_SESSION_STARTED: 'mixing_session_started',// e.g., { stem_count: 3 }
    MIXING_SESSION_COMPLETED: 'mixing_session_completed',// e.g., { output_track_id: 'abc' }
    MASTERING_APPLIED: 'mastering_applied',          // e.g., { preset: 'loud_and_clear' }

    // UI Interactions
    UI_BUTTON_CLICK: 'ui_button_click',              // e.g., { button_name: 'save_project' }
    UI_TAB_VIEWED: 'ui_tab_viewed',                  // e.g., { tab_name: 'compose' }
    UI_MODAL_OPENED: 'ui_modal_opened',              // e.g., { modal_name: 'settings' }
    UI_SETTINGS_CHANGED: 'ui_settings_changed',      // e.g., { setting_name: 'theme', value: 'dark' }

    // Errors (client-side)
    CLIENT_ERROR_CAUGHT: 'client_error_caught',      // e.g., { component: 'AudioPlayer', message: '...' }
  }
};

/**
 * Initializes analytics providers like Google Analytics or Mixpanel.
 * This function should be called once when the application starts (e.g., in index.js or App.js).
 */
export const initAnalytics = () => {
  if (analyticsConfig.googleAnalytics.enabled && analyticsConfig.googleAnalytics.measurementId) {
    // Initialize Google Analytics (GA4 example)
    // This usually involves adding the GA script to index.html and then configuring gtag
    // For example, in index.html:
    // <script async src="https://www.googletagmanager.com/gtag/js?id=YOUR_GA_ID"></script>
    // <script>
    //   window.dataLayer = window.dataLayer || [];
    //   function gtag(){dataLayer.push(arguments);}
    //   gtag('js', new Date());
    //   gtag('config', 'YOUR_GA_ID');
    // </script>
    // And then here you might ensure gtag is available or send a page_view
    if (window.gtag) {
      console.log(`Google Analytics initialized with ID: ${analyticsConfig.googleAnalytics.measurementId}`);
      // gtag('config', analyticsConfig.googleAnalytics.measurementId, { 'send_page_view': false }); // if page views handled by router
    } else {
      console.warn("Google Analytics gtag function not found. Ensure GA script is loaded in index.html.");
    }
  }

  if (analyticsConfig.mixpanel.enabled && analyticsConfig.mixpanel.token) {
    // Initialize Mixpanel (example)
    // import mixpanel from 'mixpanel-browser'; // Would need to install mixpanel-browser
    // mixpanel.init(analyticsConfig.mixpanel.token, {debug: process.env.NODE_ENV === 'development'});
    // mixpanel.track('App Loaded');
    console.log(`Mixpanel initialized with token: ${analyticsConfig.mixpanel.token.substring(0,5)}...`);
    // Placeholder for actual Mixpanel init
  }

  console.log("Analytics services initialized (if enabled and configured).");
};


/**
 * Tracks a custom event with various analytics providers.
 * @param {string} eventName - The name of the event to track (use constants from analyticsConfig.events).
 * @param {object} properties - An object containing additional properties for the event.
 */
export const trackEvent = (eventName, properties = {}) => {
  if (!eventName) {
    console.warn("trackEvent called without eventName.");
    return;
  }

  if (process.env.NODE_ENV === 'development') {
    console.log(`[Analytics Event]: ${eventName}`, properties);
  }

  // Google Analytics (gtag.js)
  if (analyticsConfig.googleAnalytics.enabled && window.gtag) {
    try {
      window.gtag('event', eventName, {
        ...properties, // Spread event-specific properties
        // Standard GA4 event parameters can be added here if needed
        // event_category: properties.category || 'AppInteraction', // Example category
        // event_label: properties.label || eventName, // Example label
        // value: properties.value // Example value
      });
    } catch (e) {
      console.error("Error sending event to Google Analytics:", e);
    }
  }

  // Mixpanel
  if (analyticsConfig.mixpanel.enabled /* && window.mixpanel */) { // Assuming mixpanel is globally available if initialized
    try {
      // window.mixpanel.track(eventName, properties);
      // Placeholder for actual Mixpanel call
      if (window.mixpanel) { // Check if mixpanel object exists
        window.mixpanel.track(eventName, properties);
      } else {
        // console.warn("Mixpanel not fully initialized for tracking event:", eventName);
      }
    } catch (e) {
      console.error("Error sending event to Mixpanel:", e);
    }
  }

  // Custom Backend Analytics Endpoint
  if (analyticsConfig.customAnalyticsEndpoint.enabled && analyticsConfig.customAnalyticsEndpoint.url) {
    try {
      navigator.sendBeacon( // Use sendBeacon for reliability on page unload
        analyticsConfig.customAnalyticsEndpoint.url,
        JSON.stringify({
          event: eventName,
          properties,
          timestamp: new Date().toISOString(),
          // Add user context if available: userId, sessionId, etc.
        })
      );
    } catch (e) {
      // sendBeacon errors are hard to catch, but good to have a try-catch
      console.error("Error sending event to custom analytics endpoint:", e);
    }
  }
};

// Example of a utility function to track page views if using a router
export const trackPageView = (path) => {
  if (analyticsConfig.googleAnalytics.enabled && window.gtag && analyticsConfig.googleAnalytics.measurementId) {
    window.gtag('config', analyticsConfig.googleAnalytics.measurementId, {
      page_path: path,
      // page_title: document.title // Optional: if title is dynamic
    });
    if (process.env.NODE_ENV === 'development') {
      console.log(`[Analytics PageView]: ${path}`);
    }
  }
  // Add other page view tracking for Mixpanel, etc. if needed
  // if (analyticsConfig.mixpanel.enabled && window.mixpanel) {
  //   window.mixpanel.track_pageview({page: path});
  // }
};
