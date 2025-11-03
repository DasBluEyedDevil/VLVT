import express, { Request, Response } from 'express';
import cors from 'cors';
import dotenv from 'dotenv';
import { Pool } from 'pg';
import rateLimit from 'express-rate-limit';

dotenv.config();

const app = express();
const PORT = process.env.PORT || 3003;

if (!process.env.DATABASE_URL) {
  console.error('ERROR: DATABASE_URL environment variable is required');
  process.exit(1);
}

// Rate limiter for match creation endpoint
const matchLimiter = rateLimit({
  windowMs: 15 * 60 * 1000, // 15 minutes
  max: 15, // limit each IP to 15 match creation attempts per windowMs (reasonable for a dating app)
  message: 'Too many match requests, please try again later'
});

app.use(cors());
app.use(express.json());

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

// Health check endpoint
app.get('/health', (req: Request, res: Response) => {
  res.json({ status: 'ok', service: 'chat-service' });
});

// Get matches for a user
app.get('/matches/:userId', async (req: Request, res: Response) => {
  try {
    const { userId } = req.params;
    
    const result = await pool.query(
      `SELECT id, user_id_1, user_id_2, created_at 
       FROM matches 
       WHERE user_id_1 = $1 OR user_id_2 = $1`,
      [userId]
    );
    
    const matches = result.rows.map(match => ({
      id: match.id,
      userId1: match.user_id_1,
      userId2: match.user_id_2,
      createdAt: match.created_at
    }));
    
    res.json({ success: true, matches });
  } catch (error) {
    console.error('Failed to retrieve matches:', error);
    res.status(500).json({ success: false, error: 'Failed to retrieve matches' });
  }
});

// Create a match
app.post('/matches', matchLimiter, async (req: Request, res: Response) => {
  try {
    const { userId1, userId2 } = req.body;
    
    if (!userId1 || !userId2) {
      return res.status(400).json({ success: false, error: 'Both userIds are required' });
    }
    
    // Check for existing match in both directions
    const existingMatch = await pool.query(
      `SELECT id, user_id_1, user_id_2, created_at 
       FROM matches 
       WHERE (user_id_1 = $1 AND user_id_2 = $2) 
          OR (user_id_1 = $2 AND user_id_2 = $1)`,
      [userId1, userId2]
    );
    
    // If match already exists, return the existing match
    if (existingMatch.rows.length > 0) {
      const match = existingMatch.rows[0];
      return res.json({ 
        success: true, 
        match: {
          id: match.id,
          userId1: match.user_id_1,
          userId2: match.user_id_2,
          createdAt: match.created_at
        },
        alreadyExists: true
      });
    }
    
    // Create new match only if it doesn't exist
    const matchId = `match_${Date.now()}`;
    
    const result = await pool.query(
      `INSERT INTO matches (id, user_id_1, user_id_2) 
       VALUES ($1, $2, $3) 
       RETURNING id, user_id_1, user_id_2, created_at`,
      [matchId, userId1, userId2]
    );
    
    const match = result.rows[0];
    
    res.json({ 
      success: true, 
      match: {
        id: match.id,
        userId1: match.user_id_1,
        userId2: match.user_id_2,
        createdAt: match.created_at
      }
    });
  } catch (error) {
    console.error('Failed to create match:', error);
    res.status(500).json({ success: false, error: 'Failed to create match' });
  }
});

// Get messages for a match
app.get('/messages/:matchId', async (req: Request, res: Response) => {
  try {
    const { matchId } = req.params;
    
    const result = await pool.query(
      `SELECT id, match_id, sender_id, text, created_at 
       FROM messages 
       WHERE match_id = $1 
       ORDER BY created_at ASC`,
      [matchId]
    );
    
    const messages = result.rows.map(msg => ({
      id: msg.id,
      matchId: msg.match_id,
      senderId: msg.sender_id,
      text: msg.text,
      timestamp: msg.created_at
    }));
    
    res.json({ success: true, messages });
  } catch (error) {
    console.error('Failed to retrieve messages:', error);
    res.status(500).json({ success: false, error: 'Failed to retrieve messages' });
  }
});

// Send a message
app.post('/messages', async (req: Request, res: Response) => {
  try {
    const { matchId, senderId, text } = req.body;
    
    if (!matchId || !senderId || !text) {
      return res.status(400).json({ success: false, error: 'matchId, senderId, and text are required' });
    }
    
    const messageId = `msg_${Date.now()}`;
    
    const result = await pool.query(
      `INSERT INTO messages (id, match_id, sender_id, text) 
       VALUES ($1, $2, $3, $4) 
       RETURNING id, match_id, sender_id, text, created_at`,
      [messageId, matchId, senderId, text]
    );
    
    const message = result.rows[0];
    
    res.json({ 
      success: true, 
      message: {
        id: message.id,
        matchId: message.match_id,
        senderId: message.sender_id,
        text: message.text,
        timestamp: message.created_at
      }
    });
  } catch (error) {
    console.error('Failed to send message:', error);
    res.status(500).json({ success: false, error: 'Failed to send message' });
  }
});

app.listen(PORT, () => {
  console.log(`Chat service running on port ${PORT}`);
});
