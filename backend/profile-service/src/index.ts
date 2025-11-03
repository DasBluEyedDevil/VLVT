import express, { Request, Response } from 'express';
import cors from 'cors';
import dotenv from 'dotenv';

dotenv.config();

const app = express();
const PORT = process.env.PORT || 3002;

app.use(cors());
app.use(express.json());

// In-memory storage for stub implementation
interface Profile {
  userId: string;
  name?: string;
  age?: number;
  bio?: string;
  photos?: string[];
  interests?: string[];
}

const profiles: Map<string, Profile> = new Map();

// Health check endpoint
app.get('/health', (req: Request, res: Response) => {
  res.json({ status: 'ok', service: 'profile-service' });
});

// Create or update profile
app.post('/profile', (req: Request, res: Response) => {
  try {
    const { userId, name, age, bio, photos, interests } = req.body;
    
    if (!userId) {
      return res.status(400).json({ success: false, error: 'userId is required' });
    }
    
    const profile: Profile = {
      userId,
      name,
      age,
      bio,
      photos: photos || [],
      interests: interests || []
    };
    
    profiles.set(userId, profile);
    
    res.json({ success: true, profile });
  } catch (error) {
    res.status(500).json({ success: false, error: 'Failed to save profile' });
  }
});

// Get profile by userId
app.get('/profile/:userId', (req: Request, res: Response) => {
  try {
    const { userId } = req.params;
    
    const profile = profiles.get(userId);
    
    if (!profile) {
      return res.status(404).json({ success: false, error: 'Profile not found' });
    }
    
    res.json({ success: true, profile });
  } catch (error) {
    res.status(500).json({ success: false, error: 'Failed to retrieve profile' });
  }
});

// Update profile
app.put('/profile/:userId', (req: Request, res: Response) => {
  try {
    const { userId } = req.params;
    const updates = req.body;
    
    const existingProfile = profiles.get(userId);
    
    if (!existingProfile) {
      return res.status(404).json({ success: false, error: 'Profile not found' });
    }
    
    const updatedProfile = { ...existingProfile, ...updates, userId };
    profiles.set(userId, updatedProfile);
    
    res.json({ success: true, profile: updatedProfile });
  } catch (error) {
    res.status(500).json({ success: false, error: 'Failed to update profile' });
  }
});

// Delete profile
app.delete('/profile/:userId', (req: Request, res: Response) => {
  try {
    const { userId } = req.params;
    
    if (!profiles.has(userId)) {
      return res.status(404).json({ success: false, error: 'Profile not found' });
    }
    
    profiles.delete(userId);
    
    res.json({ success: true, message: 'Profile deleted' });
  } catch (error) {
    res.status(500).json({ success: false, error: 'Failed to delete profile' });
  }
});

// Get random profiles for discovery (stub)
app.get('/profiles/discover', (req: Request, res: Response) => {
  try {
    const allProfiles = Array.from(profiles.values());
    // Return up to 10 random profiles
    const randomProfiles = allProfiles.slice(0, 10);
    
    res.json({ success: true, profiles: randomProfiles });
  } catch (error) {
    res.status(500).json({ success: false, error: 'Failed to retrieve profiles' });
  }
});

app.listen(PORT, () => {
  console.log(`Profile service running on port ${PORT}`);
});
