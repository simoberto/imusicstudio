-- AI Music Studio Database Schema
-- PostgreSQL initialization script

-- Create extensions if they don't already exist
CREATE EXTENSION IF NOT EXISTS "uuid-ossp"; -- For generating UUIDs
CREATE EXTENSION IF NOT EXISTS "pgcrypto";  -- For cryptographic functions like gen_salt

-- Create custom ENUM types for status, instrument, and format
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'generation_status') THEN
        CREATE TYPE generation_status AS ENUM ('pending', 'processing', 'completed', 'failed', 'cancelled');
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'instrument_type') THEN
        CREATE TYPE instrument_type AS ENUM ('bass', 'drums', 'guitar', 'piano', 'synth', 'vocal', 'other');
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'audio_format') THEN
        CREATE TYPE audio_format AS ENUM ('wav', 'mp3', 'flac', 'ogg');
    END IF;
END$$;

-- Users table (for future user management and tracking generation ownership)
CREATE TABLE IF NOT EXISTS users (
   id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
   email VARCHAR(255) UNIQUE NOT NULL,
   username VARCHAR(100) UNIQUE NOT NULL,
   password_hash VARCHAR(255) NOT NULL, -- Should store hashed passwords
   created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
   updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
   is_active BOOLEAN DEFAULT true,
   subscription_tier VARCHAR(50) DEFAULT 'free',
   usage_count INTEGER DEFAULT 0,
   last_login TIMESTAMP WITH TIME ZONE
);

-- Audio generations table (for individual stems or short generations)
CREATE TABLE IF NOT EXISTS audio_generations (
   id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
   user_id UUID REFERENCES users(id) ON DELETE SET NULL, -- SET NULL if user is deleted, or CASCADE
   execution_id VARCHAR(255) UNIQUE NOT NULL, -- Important for tracking
   instrument instrument_type, -- Can be NULL if it's not a stem
   prompt TEXT NOT NULL,
   duration_seconds INTEGER NOT NULL DEFAULT 30,
   temperature DECIMAL(3,2) DEFAULT 1.0,
   quality_threshold INTEGER DEFAULT 70,
   status generation_status DEFAULT 'pending',
   file_path VARCHAR(500), -- Relative path within the /data volume
   file_size_bytes BIGINT,
   output_format audio_format DEFAULT 'wav',
   quality_score INTEGER,
   generation_time_seconds DECIMAL(8,2),
   created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
   started_at TIMESTAMP WITH TIME ZONE,
   completed_at TIMESTAMP WITH TIME ZONE,
   error_message TEXT,
   metadata JSONB DEFAULT '{}'::jsonb -- For storing extra parameters, model used, etc.
);

-- Audio compositions table (for full tracks composed of multiple stems)
CREATE TABLE IF NOT EXISTS audio_compositions (
   id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
   user_id UUID REFERENCES users(id) ON DELETE SET NULL,
   execution_id VARCHAR(255) UNIQUE NOT NULL,
   title VARCHAR(255) NOT NULL,
   style VARCHAR(100),
   bpm INTEGER,
   musical_key VARCHAR(50), -- Increased size for "C# minor" etc.
   duration_seconds INTEGER,
   complexity INTEGER,
   status generation_status DEFAULT 'pending',
   final_file_path VARCHAR(500), -- Path to the master mixed/mastered track
   final_file_size_bytes BIGINT,
   output_format audio_format DEFAULT 'wav',
   quality_score INTEGER, -- Overall quality of the composition
   processing_time_seconds DECIMAL(8,2),
   stems_info JSONB DEFAULT '[]'::jsonb, -- Array of objects detailing stems used (paths, instruments)
   created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
   started_at TIMESTAMP WITH TIME ZONE,
   completed_at TIMESTAMP WITH TIME ZONE,
   error_message TEXT,
   metadata JSONB DEFAULT '{}'::jsonb -- Genre, mood, tags, etc.
);

-- Mix sessions table (if mixing is a separate step from composition)
CREATE TABLE IF NOT EXISTS mix_sessions (
   id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
   user_id UUID REFERENCES users(id) ON DELETE SET NULL,
   composition_id UUID REFERENCES audio_compositions(id) ON DELETE CASCADE, -- Link to a composition
   execution_id VARCHAR(255) UNIQUE NOT NULL,
   input_stems_paths JSONB NOT NULL, -- Array of file paths for stems
   target_lufs DECIMAL(4,1) DEFAULT -14.0,
   reference_track_path VARCHAR(500),
   status generation_status DEFAULT 'pending',
   output_file_path VARCHAR(500),
   output_file_size_bytes BIGINT,
   output_format audio_format DEFAULT 'wav',
   quality_score INTEGER,
   processing_time_seconds DECIMAL(8,2),
   created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
   started_at TIMESTAMP WITH TIME ZONE,
   completed_at TIMESTAMP WITH TIME ZONE,
   report_data JSONB DEFAULT '{}'::jsonb, -- Store analysis from mix_master.sh
   error_message TEXT
);

-- System metrics table (for monitoring application performance)
CREATE TABLE IF NOT EXISTS system_metrics (
   id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
   metric_time TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP, -- Renamed from timestamp to avoid conflict
   cpu_usage_percent DECIMAL(5,2),
   gpu_usage_percent DECIMAL(5,2),
   gpu_memory_used_mb BIGINT,
   gpu_memory_total_mb BIGINT,
   ram_usage_percent DECIMAL(5,2),
   disk_usage_percent DECIMAL(5,2), -- For relevant disk
   active_generations INTEGER DEFAULT 0,
   queue_length INTEGER DEFAULT 0,
   uptime_seconds BIGINT, -- Uptime of the metrics reporting service or overall app
   metadata JSONB DEFAULT '{}'::jsonb -- For extra context like service name if per-service metrics
);

-- Usage analytics table (for tracking user interactions and feature usage)
CREATE TABLE IF NOT EXISTS usage_analytics (
   id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
   user_id UUID REFERENCES users(id) ON DELETE SET NULL,
   event_type VARCHAR(100) NOT NULL,
   event_data JSONB DEFAULT '{}'::jsonb,
   event_timestamp TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP, -- Renamed
   session_id VARCHAR(255),
   ip_address INET,
   user_agent TEXT
);

-- Create indexes for performance optimization on frequently queried columns
-- Users table
CREATE INDEX IF NOT EXISTS idx_users_email ON users(email);
CREATE INDEX IF NOT EXISTS idx_users_username ON users(username);

-- Audio generations table
CREATE INDEX IF NOT EXISTS idx_audio_generations_user_id ON audio_generations(user_id);
CREATE INDEX IF NOT EXISTS idx_audio_generations_status ON audio_generations(status);
CREATE INDEX IF NOT EXISTS idx_audio_generations_created_at ON audio_generations(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_audio_generations_execution_id ON audio_generations(execution_id);
CREATE INDEX IF NOT EXISTS idx_audio_generations_instrument ON audio_generations(instrument);


-- Audio compositions table
CREATE INDEX IF NOT EXISTS idx_audio_compositions_user_id ON audio_compositions(user_id);
CREATE INDEX IF NOT EXISTS idx_audio_compositions_status ON audio_compositions(status);
CREATE INDEX IF NOT EXISTS idx_audio_compositions_created_at ON audio_compositions(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_audio_compositions_style ON audio_compositions(style);


-- Mix sessions table
CREATE INDEX IF NOT EXISTS idx_mix_sessions_user_id ON mix_sessions(user_id);
CREATE INDEX IF NOT EXISTS idx_mix_sessions_status ON mix_sessions(status);
CREATE INDEX IF NOT EXISTS idx_mix_sessions_composition_id ON mix_sessions(composition_id);

-- System metrics table
CREATE INDEX IF NOT EXISTS idx_system_metrics_metric_time ON system_metrics(metric_time DESC);

-- Usage analytics table
CREATE INDEX IF NOT EXISTS idx_usage_analytics_user_id ON usage_analytics(user_id);
CREATE INDEX IF NOT EXISTS idx_usage_analytics_event_timestamp ON usage_analytics(event_timestamp DESC);
CREATE INDEX IF NOT EXISTS idx_usage_analytics_event_type ON usage_analytics(event_type);


-- Function to automatically update the 'updated_at' timestamp on users table
CREATE OR REPLACE FUNCTION update_modified_column()
RETURNS TRIGGER AS $$
BEGIN
   NEW.updated_at = CURRENT_TIMESTAMP;
   RETURN NEW;
END;
$$ language 'plpgsql';

CREATE TRIGGER update_users_modtime
BEFORE UPDATE ON users
FOR EACH ROW
EXECUTE PROCEDURE update_modified_column();

-- (The other functions and materialized views from the original SQL are more for advanced operations/analytics
-- and might be added later. For initial setup, the tables and basic indexes are key.)

-- Insert a default admin user (for development/testing, CHANGE IN PRODUCTION)
-- Password is 'admin_password_to_change' hashed with pgcrypto's crypt function.
-- Ensure pgcrypto is enabled.
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM users WHERE username = 'admin') THEN
        INSERT INTO users (email, username, password_hash, subscription_tier, is_active)
        VALUES (
           'admin@aimusic.studio',
           'admin',
           crypt('admin_password_to_change', gen_salt('bf', 8)), -- Example: Blowfish hash
           'enterprise',
           true
        );
    END IF;
END$$;

-- Grant permissions to the n8n user (defined in docker-compose.yml)
-- This should match DB_USER environment variable.
-- The user 'n8n' is created by the postgres Docker image if POSTGRES_USER=n8n.
-- Permissions are usually granted by default to the database owner.
-- Explicit grants can be added if a different user structure is used.
-- Example:
-- GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO n8n;
-- GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO n8n;
-- GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO n8n;


-- Final setup message (will appear in PostgreSQL logs during init)
DO $$
BEGIN
   RAISE NOTICE 'AI Music Studio database schema initialized successfully.';
   RAISE NOTICE 'Default admin user created: admin / admin_password_to_change (CHANGE THIS PASSWORD).';
END $$;
