import express, { Request, Response } from 'express';
import cors from 'cors';
import dotenv from 'dotenv';

dotenv.config();

const app = express();
const PORT = process.env.PORT || 3003;

app.use(cors());
app.use(express.json());

// In-memory storage for stub implementation
interface Message {
  id: string;
  matchId: string;
  senderId: string;
  text: string;
  timestamp: Date;
}

interface Match {
  id: string;
  userId1: string;
  userId2: string;
  createdAt: Date;
}

const messages: Message[] = [];
const matches: Match[] = [];

// Health check endpoint
app.get('/health', (req: Request, res: Response) => {
  res.json({ status: 'ok', service: 'chat-service' });
});

// Get matches for a user
app.get('/matches/:userId', (req: Request, res: Response) => {
  try {
    const { userId } = req.params;
    
    const userMatches = matches.filter(
      match => match.userId1 === userId || match.userId2 === userId
    );
    
    res.json({ success: true, matches: userMatches });
  } catch (error) {
    res.status(500).json({ success: false, error: 'Failed to retrieve matches' });
  }
});

// Create a match (stub)
app.post('/matches', (req: Request, res: Response) => {
  try {
    const { userId1, userId2 } = req.body;
    
    if (!userId1 || !userId2) {
      return res.status(400).json({ success: false, error: 'Both userIds are required' });
    }
    
    const match: Match = {
      id: `match_${Date.now()}`,
      userId1,
      userId2,
      createdAt: new Date()
    };
    
    matches.push(match);
    
    res.json({ success: true, match });
  } catch (error) {
    res.status(500).json({ success: false, error: 'Failed to create match' });
  }
});

// Get messages for a match
app.get('/messages/:matchId', (req: Request, res: Response) => {
  try {
    const { matchId } = req.params;
    
    const matchMessages = messages.filter(msg => msg.matchId === matchId);
    
    res.json({ success: true, messages: matchMessages });
  } catch (error) {
    res.status(500).json({ success: false, error: 'Failed to retrieve messages' });
  }
});

// Send a message (stub)
app.post('/messages', (req: Request, res: Response) => {
  try {
    const { matchId, senderId, text } = req.body;
    
    if (!matchId || !senderId || !text) {
      return res.status(400).json({ success: false, error: 'matchId, senderId, and text are required' });
    }
    
    const message: Message = {
      id: `msg_${Date.now()}`,
      matchId,
      senderId,
      text,
      timestamp: new Date()
    };
    
    messages.push(message);
    
    res.json({ success: true, message });
  } catch (error) {
    res.status(500).json({ success: false, error: 'Failed to send message' });
  }
});

app.listen(PORT, () => {
  console.log(`Chat service running on port ${PORT}`);
});
