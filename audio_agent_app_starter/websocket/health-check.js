// websocket/health-check.js
const WebSocket = require('ws');

// Default port, can be overridden by an environment variable if needed for flexibility
const PORT = process.env.PORT || 8080;
const HEALTH_CHECK_URL = `ws://localhost:${PORT}`; // Check against localhost from within the container

const checkHealth = () => {
  return new Promise((resolve, reject) => {
    let ws;
    try {
      ws = new WebSocket(HEALTH_CHECK_URL);

      const timeout = setTimeout(() => {
        if (ws) {
          ws.terminate(); // Ensure WebSocket is terminated on timeout
        }
        reject(new Error(`Health check timed out after 3 seconds connecting to ${HEALTH_CHECK_URL}`));
      }, 3000); // 3-second timeout for the connection attempt

      ws.on('open', () => {
        clearTimeout(timeout);
        // Optional: Send a ping or a specific health check message if the server supports it
        // ws.ping((err) => {
        //   if (err) {
        //     reject(new Error('Ping failed'));
        //   } else {
        //     resolve(true);
        //   }
        //   ws.close();
        // });
        // For a simple health check, just opening the connection is often enough.
        ws.close(1000, "Health check successful"); // Close gracefully
        resolve(true);
      });

      ws.on('error', (error) => {
        clearTimeout(timeout);
        reject(error); // The error object from 'ws' usually has good details
      });

    } catch (error) {
      // Catch synchronous errors during WebSocket creation (e.g., invalid URL)
      reject(error);
    }
  });
};

checkHealth()
  .then(() => {
    console.log(`WebSocket server at ${HEALTH_CHECK_URL} is healthy.`);
    process.exit(0); // Exit with 0 for success
  })
  .catch((error) => {
    console.error(`Health check failed for ${HEALTH_CHECK_URL}: ${error.message}`);
    process.exit(1); // Exit with 1 for failure
  });
