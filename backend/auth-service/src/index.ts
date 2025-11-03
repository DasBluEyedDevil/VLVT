import express, { Request, Response } from 'express';
import cors from 'cors';
import jwt from 'jsonwebtoken';
import dotenv from 'dotenv';

dotenv.config();

const app = express();
const PORT = process.env.PORT || 3001;
if (!process.env.JWT_SECRET) {
  console.error('ERROR: JWT_SECRET environment variable is required');
  process.exit(1);
}
const JWT_SECRET = process.env.JWT_SECRET;

app.use(cors());
app.use(express.json());

// Health check endpoint
app.get('/health', (req: Request, res: Response) => {
  res.json({ status: 'ok', service: 'auth-service' });
});

// Sign in with Apple endpoint (stub)
app.post('/auth/apple', async (req: Request, res: Response) => {
  try {
    const { identityToken } = req.body;
    
    // In production, verify the Apple identity token
    // For now, we'll create a stub response
    
    const userId = `apple_${Date.now()}`;
    const token = jwt.sign(
      { userId, provider: 'apple', email: `user@apple.example.com` },
      JWT_SECRET,
      { expiresIn: '7d' }
    );
    
    res.json({
      success: true,
      token,
      userId,
      provider: 'apple'
    });
  } catch (error) {
    res.status(500).json({ success: false, error: 'Authentication failed' });
  }
});

// Sign in with Google endpoint (stub)
app.post('/auth/google', async (req: Request, res: Response) => {
  try {
    const { idToken } = req.body;
    
    // In production, verify the Google ID token
    // For now, we'll create a stub response
    
    const userId = `google_${Date.now()}`;
    const token = jwt.sign(
      { userId, provider: 'google', email: `user@google.example.com` },
      JWT_SECRET,
      { expiresIn: '7d' }
    );
    
    res.json({
      success: true,
      token,
      userId,
      provider: 'google'
    });
  } catch (error) {
    res.status(500).json({ success: false, error: 'Authentication failed' });
  }
});

// Verify token endpoint
app.post('/auth/verify', (req: Request, res: Response) => {
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
