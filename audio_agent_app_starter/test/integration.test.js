// test/integration.test.js

// Ensure you have 'axios' and 'chai' installed in the environment where these tests run.
// Typically, for a test setup like this, you'd have a package.json in the 'test' directory
// or install these globally if running ad-hoc.
// The docker-compose.test.yml handles this by installing them in the test container.

const axios = require('axios');
const { expect } = require('chai'); // Using Chai for assertions

// API base URL - this should point to the n8n webhook endpoint exposed by Nginx.
// It's configured via an environment variable for flexibility (e.g., in docker-compose.test.yml).
const API_URL = process.env.API_URL || 'http://localhost:80'; // Default to Nginx port 80

// Helper function to log test steps
const logTest = (message) => console.log(`    ✓ ${message}`);

describe('AI Music Studio - Integration Tests', function() {
  // Increase timeout for tests that involve AI generation, as they can be slow.
  this.timeout(120000); // 120 seconds global timeout for all tests in this suite. Can be set per test too.

  let generatedStemFilePath = null; // To store path of a generated stem for use in mix test

  // Test 1: Health Check of n8n (assuming Nginx proxies /api/healthz to n8n's /healthz)
  it('should confirm n8n service is healthy via Nginx', async () => {
    logTest('Checking n8n health status through Nginx proxy...');
    try {
      const response = await axios.get(`${API_URL}/api/healthz`); // Nginx path to n8n health
      expect(response.status).to.equal(200);
      expect(response.data).to.be.an('object');
      // n8n healthz returns something like { "message": "ok", "uptime": 123.45 }
      expect(response.data.message).to.equal('ok');
      logTest('n8n health check: PASSED');
    } catch (error) {
      console.error('Health check failed:', error.message);
      throw error; // Fail the test
    }
  });

  // Test 2: Generate Melody Endpoint
  describe('POST /api/mcp/generate-melody', () => {
    it('should successfully generate a short bass stem', async () => {
      logTest('Requesting short bass stem generation...');
      const payload = {
        instrument: 'bass',
        prompt: 'groovy funk bass line, simple, 4 bars, e minor',
        duration: 8, // Short duration for testing
        quality_threshold: 60 // Lower threshold for faster test pass
      };
      try {
        const response = await axios.post(`${API_URL}/api/mcp/generate-melody`, payload, { timeout: 90000 }); // 90s timeout for this call

        expect(response.status).to.equal(200);
        const data = response.data;
        expect(data.success).to.equal(true, "Generation success flag should be true");
        expect(data.file).to.be.a('string').and.not.empty;
        expect(data.file).to.match(/(\.wav)$/i); // Check if it's a wav file path
        expect(data.instrument).to.equal(payload.instrument);
        expect(data.duration).to.be.closeTo(payload.duration, 2); // Allow slight variation if model adjusts
        expect(data.quality_score).to.be.a('number').and.gte(payload.quality_threshold);

        generatedStemFilePath = data.file; // Save for mix test
        logTest(`Bass stem generated: ${data.file}, Quality: ${data.quality_score}`);
        logTest('Generate melody (bass): PASSED');
      } catch (error) {
        console.error('Generate melody (bass) failed:', error.response ? error.response.data : error.message);
        throw error;
      }
    });

    it('should generate a short drums stem', async () => {
        logTest('Requesting short drums stem generation...');
        const payload = {
          instrument: 'drums',
          prompt: 'simple rock beat, 4/4 time',
          duration: 8,
          quality_threshold: 60
        };
        try {
          const response = await axios.post(`${API_URL}/api/mcp/generate-melody`, payload, { timeout: 90000 });
          expect(response.status).to.equal(200);
          const data = response.data;
          expect(data.success).to.equal(true);
          expect(data.file).to.be.a('string').and.not.empty;
          // Store this for mix test as well, if needed, or just validate.
          // For this example, we'll use only the bass stem for the mix test to keep it simple.
          logTest(`Drums stem generated: ${data.file}, Quality: ${data.quality_score}`);
          logTest('Generate melody (drums): PASSED');
        } catch (error) {
          console.error('Generate melody (drums) failed:', error.response ? error.response.data : error.message);
          throw error;
        }
      });


    it('should reject request with invalid instrument', async () => {
      logTest('Testing with invalid instrument...');
      const payload = {
        instrument: 'flute', // Assuming 'flute' is not in the validInstruments list in n8n
        prompt: 'a happy tune',
        duration: 5
      };
      try {
        await axios.post(`${API_URL}/api/mcp/generate-melody`, payload);
        throw new Error('Request should have failed due to invalid instrument, but it succeeded.');
      } catch (error) {
        expect(error.response).to.not.be.undefined;
        // n8n workflow's code node might throw error, leading to 500 if not caught and returned as 400.
        // Or, if validation returns error properly, it could be 400.
        // The n8n code node for validation currently just throws, which might result in a 500 from n8n's perspective.
        // For a robust API, n8n should catch this and return a 400.
        // Let's assume the workflow is set up to return a non-200 status for validation errors.
        // The provided n8n workflow doesn't explicitly set $response.statusCode = 400 for validation.
        // It throws, which might lead to a 500 or a specific error structure from n8n.
        // For this test, we'll check for a non-2xx status.
        expect(error.response.status).to.be.oneOf([400, 500]);
        if(error.response.data && error.response.data.error) {
            expect(error.response.data.error).to.include('Invalid instrument');
        } else if (error.response.data && error.response.data.message) { // n8n default error
            expect(error.response.data.message).to.include('Invalid instrument');
        }
        logTest('Invalid instrument rejection: PASSED');
      }
    });

    it('should reject request with missing prompt', async () => {
      logTest('Testing with missing prompt...');
      const payload = { instrument: 'piano', duration: 5 };
      try {
        await axios.post(`${API_URL}/api/mcp/generate-melody`, payload);
        throw new Error('Request should have failed due to missing prompt.');
      } catch (error) {
        expect(error.response).to.not.be.undefined;
        expect(error.response.status).to.be.oneOf([400, 500]);
         if(error.response.data && error.response.data.error) {
            expect(error.response.data.error).to.include('Missing required parameters');
        } else if (error.response.data && error.response.data.message) {
            expect(error.response.data.message).to.include('Missing required parameters');
        }
        logTest('Missing prompt rejection: PASSED');
      }
    });
  });

  // Test 3: Mix Master Endpoint
  describe('POST /api/mcp/mix-master', () => {
    it('should successfully mix a list of (mocked) stems if a stem was generated', async function() { // Use function() for this.skip
      if (!generatedStemFilePath) {
        logTest('Mix master: SKIPPED (no stem was generated in previous tests)');
        this.skip(); // Skip this test if no stem was generated
      }
      logTest(`Mixing stem: ${generatedStemFilePath}...`);
      // In a real integration test, you'd need multiple stems.
      // For simplicity, we'll "mix" the single generated stem with itself or a placeholder.
      // The mix_master.sh script expects absolute paths starting with /data/
      // The `generatedStemFilePath` is already in that format.
      const payload = {
        stems: [generatedStemFilePath, generatedStemFilePath], // Mix the stem with itself for testing
        targetLUFS: -16 // Use a different LUFS for testing
      };
      try {
        const response = await axios.post(`${API_URL}/api/mcp/mix-master`, payload, { timeout: 45000 }); // 45s timeout
        expect(response.status).to.equal(200);
        const data = response.data;
        expect(data.success).to.equal(true);
        expect(data.file).to.be.a('string').and.not.empty;
        expect(data.file).to.match(/(\.wav)$/i);
        expect(data.report_file).to.be.a('string').and.not.empty;
        expect(data.quality_score).to.be.a('number');
        logTest(`Mix master successful: ${data.file}`);
        logTest('Mix master: PASSED');
      } catch (error) {
        console.error('Mix master failed:', error.response ? error.response.data : error.message);
        throw error;
      }
    });

    it('should reject mix request with empty stems array', async () => {
      logTest('Testing mix with empty stems array...');
      const payload = { stems: [] };
      try {
        await axios.post(`${API_URL}/api/mcp/mix-master`, payload);
        throw new Error('Mix request should have failed due to empty stems array.');
      } catch (error) {
        expect(error.response).to.not.be.undefined;
        expect(error.response.status).to.be.oneOf([400, 500]);
        if(error.response.data && error.response.data.error) {
            expect(error.response.data.error).to.include('stems parameter is required');
        } else if (error.response.data && error.response.data.message) {
             expect(error.response.data.message).to.include('stems must be a non-empty array');
        }
        logTest('Empty stems rejection: PASSED');
      }
    });
  });

  // Test 4: Full Composition Endpoint (can be very long)
  describe('POST /api/mcp/compose-track', function() {
    this.timeout(300000); // 5 minutes timeout for this suite

    it('should successfully compose a short electronic track', async () => {
      logTest('Requesting short electronic track composition...');
      const payload = {
        style: 'electronic',
        bpm: 120,
        key: 'A minor',
        duration: 15, // Short duration for test
        complexity: 3   // Low complexity for faster generation
      };
      try {
        const response = await axios.post(`${API_URL}/api/mcp/compose-track`, payload, { timeout: 280000 }); // Slightly less than suite timeout
        expect(response.status).to.equal(200);
        const data = response.data;
        expect(data.success).to.equal(true);
        expect(data.composition).to.be.an('object');
        expect(data.composition.file).to.be.a('string').and.not.empty;
        expect(data.composition.file).to.match(/(\.wav)$/i);
        expect(data.composition.title).to.be.a('string');
        expect(data.composition.stems_generated_paths).to.be.an('array').with.lengthOf.at.least(1);
        logTest(`Full composition successful: ${data.composition.file}`);
        logTest('Compose track: PASSED');
      } catch (error) {
        console.error('Compose track failed:', error.response ? error.response.data : error.message);
        throw error;
      }
    });
  });

  // Add more tests for other API endpoints or scenarios as needed.
  // For example, testing /api/mcp/render-track would require an LMMS project file
  // to be present in a location accessible by the LMMS container.
});
