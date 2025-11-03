import express, { Request, Response } from 'express';
import cors from 'cors';
import jwt from 'jsonwebtoken';
import dotenv from 'dotenv';
import { Pool } from 'pg';
import rateLimit from 'express-rate-limit';
import { OAuth2Client } from 'google-auth-library';

dotenv.config();

const app = express();
const PORT = process.env.PORT || 3001;
if (!process.env.JWT_SECRET) {
  console.error('ERROR: JWT_SECRET environment variable is required');
  process.exit(1);
}
if (!process.env.DATABASE_URL) {
  console.error('ERROR: DATABASE_URL environment variable is required');
  process.exit(1);
}
const JWT_SECRET = process.env.JWT_SECRET;

// Initialize Google OAuth2 client
const googleClient = new OAuth2Client();

// Initialize PostgreSQL connection pool
const pool = new Pool({
  connectionString: process.env.DATABASE_URL,
});

// Test database connection
pool.on('connect', () => {
  console.log('Connected to PostgreSQL database');
});

pool.on('error', (err) => {
  console.error('PostgreSQL connection error:', err);
});

// Rate limiter for authentication endpoints
const authLimiter = rateLimit({
  windowMs: 15 * 60 * 1000, // 15 minutes
  max: 10, // limit each IP to 10 auth attempts per windowMs
  message: 'Too many authentication attempts, please try again later'
});

// Rate limiter for /auth/verify endpoint
const verifyLimiter = rateLimit({
  windowMs: 15 * 60 * 1000, // 15 minutes
  max: 100, // limit each IP to 100 requests per windowMs
  message: 'Too many verification requests, please try again later'
});

app.use(cors());
app.use(express.json());

// Health check endpoint
app.get('/health', (req: Request, res: Response) => {
  res.json({ status: 'ok', service: 'auth-service' });
});

// Sign in with Apple endpoint
app.post('/auth/apple', authLimiter, async (req: Request, res: Response) => {
  try {
    const { identityToken } = req.body;
    
    if (!identityToken) {
      return res.status(400).json({ success: false, error: 'identityToken is required' });
    }
    
    // Decode the Apple identity token (JWT)
    // SECURITY WARNING: In production, you MUST verify the token signature 
    // against Apple's public keys fetched from https://appleid.apple.com/auth/keys
    // to prevent token forgery attacks. This current implementation only decodes
    // the token without verification and should not be used in production.
    // Consider using a library like 'apple-signin-auth' for full verification.
    const decoded = jwt.decode(identityToken) as { sub?: string; email?: string } | null;
    
    if (!decoded || !decoded.sub) {
      return res.status(401).json({ success: false, error: 'Invalid identity token' });
    }
    
    // Extract real providerId and email from decoded token
    const providerId = `apple_${decoded.sub}`;
    const email = decoded.email || `user_${decoded.sub}@apple.example.com`;
    const provider = 'apple';
    
    // Upsert user in database
    const result = await pool.query(
      `INSERT INTO users (id, provider, email) 
       VALUES ($1, $2, $3) 
       ON CONFLICT (id) 
       DO UPDATE SET updated_at = CURRENT_TIMESTAMP, email = $3
       RETURNING id, provider, email`,
      [providerId, provider, email]
    );
    
    const user = result.rows[0];
    const token = jwt.sign(
      { userId: user.id, provider: user.provider, email: user.email },
      JWT_SECRET,
      { expiresIn: '7d' }
    );
    
    res.json({
      success: true,
      token,
      userId: user.id,
      provider: user.provider
    });
  } catch (error) {
    console.error('Apple authentication error:', error);
    res.status(500).json({ success: false, error: 'Authentication failed' });
  }
});

// Sign in with Google endpoint
app.post('/auth/google', authLimiter, async (req: Request, res: Response) => {
  try {
    const { idToken } = req.body;
    
    if (!idToken) {
      return res.status(400).json({ success: false, error: 'idToken is required' });
    }
    
    // Verify the Google ID token
    const ticket = await googleClient.verifyIdToken({
      idToken: idToken,
      audience: process.env.GOOGLE_CLIENT_ID, // Optional: verify audience
    });
    
    const payload = ticket.getPayload();
    if (!payload || !payload.sub) {
      return res.status(401).json({ success: false, error: 'Invalid token payload' });
    }
    
    // Extract real providerId and email from verified token
    const providerId = `google_${payload.sub}`;
    const email = payload.email || `user_${payload.sub}@google.example.com`;
    const provider = 'google';
    
    // Upsert user in database
    const result = await pool.query(
      `INSERT INTO users (id, provider, email) 
       VALUES ($1, $2, $3) 
       ON CONFLICT (id) 
       DO UPDATE SET updated_at = CURRENT_TIMESTAMP, email = $3
       RETURNING id, provider, email`,
      [providerId, provider, email]
    );
    
    const user = result.rows[0];
    const token = jwt.sign(
      { userId: user.id, provider: user.provider, email: user.email },
      JWT_SECRET,
      { expiresIn: '7d' }
    );
    
    res.json({
      success: true,
      token,
      userId: user.id,
      provider: user.provider
    });
  } catch (error) {
    console.error('Google authentication error:', error);
    res.status(500).json({ success: false, error: 'Authentication failed' });
  }
});

// Verify token endpoint (with rate limiting)
app.post('/auth/verify', verifyLimiter, (req: Request, res: Response) => {
  try {
    const { token } = req.body;
    
    if (!token) {
      return res.status(401).json({ success: false, error: 'No token provided' });
    }
    
    const decoded = jwt.verify(token, JWT_SECRET);
    res.json({ success: true, decoded });
  } catch (error) {
    res.status(401).json({ success: false, error: 'Invalid token' });
  }
});

app.listen(PORT, () => {
  console.log(`Auth service running on port ${PORT}`);
});
