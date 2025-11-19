import dotenv from 'dotenv';
// Load environment variables first
dotenv.config();

// Initialize Sentry before any other imports
import * as Sentry from '@sentry/node';

if (process.env.SENTRY_DSN) {
  Sentry.init({
    dsn: process.env.SENTRY_DSN,
    environment: process.env.NODE_ENV || 'development',
    tracesSampleRate: 0.1, // 10% of transactions
  });
}

import express, { Request, Response } from 'express';
import cors from 'cors';
import helmet from 'helmet';
import multer from 'multer';
import { Pool } from 'pg';
import { authMiddleware } from './middleware/auth';
import { validateProfile, validateProfileUpdate } from './middleware/validation';
import logger from './utils/logger';
import { generalLimiter, profileCreationLimiter, discoveryLimiter } from './middleware/rate-limiter';
import {
  initializeUploadDirectory,
  validateImage,
  processImage,
  deleteImage,
  getPhotoIdFromUrl,
  canUploadMorePhotos,
  MAX_PHOTOS_PER_PROFILE,
} from './utils/image-handler';

const app = express();
const PORT = process.env.PORT || 3002;

// Log initialization
if (process.env.SENTRY_DSN) {
  logger.info('Sentry error tracking enabled', { environment: process.env.NODE_ENV || 'development' });
} else {
  logger.info('Sentry error tracking disabled (SENTRY_DSN not set)');
}

// In test environment, these are set in tests/setup.ts
if (!process.env.DATABASE_URL && process.env.NODE_ENV !== 'test') {
  logger.error('DATABASE_URL environment variable is required');
  process.exit(1);
}

if (!process.env.JWT_SECRET && process.env.NODE_ENV !== 'test') {
  logger.error('JWT_SECRET environment variable is required');
  process.exit(1);
}

// CORS origin from environment variable
const CORS_ORIGIN = process.env.CORS_ORIGIN || 'http://localhost:19006';

// Security middleware
app.use(helmet());
app.use(cors({
  origin: CORS_ORIGIN,
  credentials: true,
  methods: ['GET', 'POST', 'PUT', 'DELETE', 'OPTIONS'],
  allowedHeaders: ['Content-Type', 'Authorization']
}));
app.use(express.json({ limit: '10kb' }));

// Serve static files (uploaded images)
app.use('/uploads', express.static('uploads'));

// Configure multer for file uploads (memory storage for processing with sharp)
const upload = multer({
  storage: multer.memoryStorage(),
  limits: {
    fileSize: 10 * 1024 * 1024, // 10MB
    files: 1, // Single file per request
  },
});

// Initialize PostgreSQL connection pool with proper configuration
const pool = new Pool({
  connectionString: process.env.DATABASE_URL,
  max: 20, // Maximum number of clients in the pool
  idleTimeoutMillis: 30000, // Close idle clients after 30 seconds
  connectionTimeoutMillis: 2000, // Return an error after 2 seconds if connection cannot be established
  ssl: process.env.DATABASE_URL?.includes('railway')
    ? { rejectUnauthorized: true }
    : false,
});

// Database connection event handlers
pool.on('connect', (client) => {
  logger.info('New database connection established');
});

pool.on('acquire', (client) => {
  logger.debug('Database client acquired from pool');
});

pool.on('remove', (client) => {
  logger.debug('Database client removed from pool');
});

pool.on('error', (err, client) => {
  logger.error('Unexpected database connection error', {
    error: err.message,
    stack: err.stack
  });
});

// Health check endpoint
app.get('/health', (req: Request, res: Response) => {
  res.json({ status: 'ok', service: 'profile-service' });
});

// Create profile - Extract userId from JWT token, not request body
app.post('/profile', authMiddleware, profileCreationLimiter, validateProfile, async (req: Request, res: Response) => {
  try {
    // Get userId from authenticated JWT token, not from request body
    const userId = req.user!.userId;
    const { name, age, bio, photos, interests } = req.body;

    const result = await pool.query(
      `INSERT INTO profiles (user_id, name, age, bio, photos, interests)
       VALUES ($1, $2, $3, $4, $5, $6)
       RETURNING user_id, name, age, bio, photos, interests, created_at, updated_at`,
      [userId, name, age, bio, photos || [], interests || []]
    );

    const profile = result.rows[0];

    res.json({
      success: true,
      profile: {
        userId: profile.user_id,
        name: profile.name,
        age: profile.age,
        bio: profile.bio,
        photos: profile.photos,
        interests: profile.interests
      }
    });
  } catch (error) {
    logger.error('Failed to save profile', { error, userId: req.user?.userId });
    res.status(500).json({ success: false, error: 'Failed to save profile' });
  }
});

// Get profile by userId - Allow viewing other users' public profiles
// This endpoint returns public profile data for discovery and matches
app.get('/profile/:userId', authMiddleware, generalLimiter, async (req: Request, res: Response) => {
  try {
    const requestedUserId = req.params.userId;
    const authenticatedUserId = req.user!.userId;
    const isOwnProfile = requestedUserId === authenticatedUserId;

    // Fetch profile from database
    const result = await pool.query(
      `SELECT user_id, name, age, bio, photos, interests, created_at, updated_at
       FROM profiles
       WHERE user_id = $1`,
      [requestedUserId]
    );

    if (result.rows.length === 0) {
      return res.status(404).json({ success: false, error: 'Profile not found' });
    }

    const profile = result.rows[0];

    // Return profile data
    // Note: Currently all profile fields are public (name, age, bio, photos, interests)
    // If we add sensitive fields (email, phone, etc.) in the future, we must filter them out
    // when isOwnProfile is false to maintain privacy
    res.json({
      success: true,
      profile: {
        userId: profile.user_id,
        name: profile.name,
        age: profile.age,
        bio: profile.bio,
        photos: profile.photos,
        interests: profile.interests
      },
      isOwnProfile: isOwnProfile
    });
  } catch (error) {
    logger.error('Failed to retrieve profile', { error, requestedUserId: req.params.userId });
    res.status(500).json({ success: false, error: 'Failed to retrieve profile' });
  }
});

// Update profile - Only allow users to update their own profile
app.put('/profile/:userId', authMiddleware, generalLimiter, validateProfileUpdate, async (req: Request, res: Response) => {
  try {
    const requestedUserId = req.params.userId;
    const authenticatedUserId = req.user!.userId;

    // Authorization check: user can only update their own profile
    if (requestedUserId !== authenticatedUserId) {
      return res.status(403).json({
        success: false,
        error: 'Forbidden: Cannot modify other users\' profiles'
      });
    }

    const { name, age, bio, photos, interests } = req.body;

    const result = await pool.query(
      `UPDATE profiles
       SET name = COALESCE($2, name),
           age = COALESCE($3, age),
           bio = COALESCE($4, bio),
           photos = COALESCE($5, photos),
           interests = COALESCE($6, interests),
           updated_at = CURRENT_TIMESTAMP
       WHERE user_id = $1
       RETURNING user_id, name, age, bio, photos, interests, created_at, updated_at`,
      [requestedUserId, name, age, bio, photos, interests]
    );

    if (result.rows.length === 0) {
      return res.status(404).json({ success: false, error: 'Profile not found' });
    }

    const profile = result.rows[0];

    res.json({
      success: true,
      profile: {
        userId: profile.user_id,
        name: profile.name,
        age: profile.age,
        bio: profile.bio,
        photos: profile.photos,
        interests: profile.interests
      }
    });
  } catch (error) {
    logger.error('Failed to update profile', { error, requestedUserId: req.params.userId });
    res.status(500).json({ success: false, error: 'Failed to update profile' });
  }
});

// Delete profile - Only allow users to delete their own profile
app.delete('/profile/:userId', authMiddleware, generalLimiter, async (req: Request, res: Response) => {
  try {
    const requestedUserId = req.params.userId;
    const authenticatedUserId = req.user!.userId;

    // Authorization check: user can only delete their own profile
    if (requestedUserId !== authenticatedUserId) {
      return res.status(403).json({
        success: false,
        error: 'Forbidden: Cannot delete other users\' profiles'
      });
    }

    const result = await pool.query(
      `DELETE FROM profiles WHERE user_id = $1 RETURNING user_id`,
      [requestedUserId]
    );

    if (result.rows.length === 0) {
      return res.status(404).json({ success: false, error: 'Profile not found' });
    }

    res.json({ success: true, message: 'Profile deleted' });
  } catch (error) {
    logger.error('Failed to delete profile', { error, requestedUserId: req.params.userId });
    res.status(500).json({ success: false, error: 'Failed to delete profile' });
  }
});

// ===== LOCATION ENDPOINTS =====

// Update user location - P1 Feature
app.put('/profile/:userId/location', authMiddleware, generalLimiter, async (req: Request, res: Response) => {
  try {
    const requestedUserId = req.params.userId;
    const authenticatedUserId = req.user!.userId;

    // Authorization check: user can only update their own location
    if (requestedUserId !== authenticatedUserId) {
      return res.status(403).json({
        success: false,
        error: 'Forbidden: Cannot update other users\' location'
      });
    }

    const { latitude, longitude } = req.body;

    // Validate latitude and longitude
    if (typeof latitude !== 'number' || typeof longitude !== 'number') {
      return res.status(400).json({
        success: false,
        error: 'Invalid location data: latitude and longitude must be numbers'
      });
    }

    if (latitude < -90 || latitude > 90) {
      return res.status(400).json({
        success: false,
        error: 'Invalid latitude: must be between -90 and 90'
      });
    }

    if (longitude < -180 || longitude > 180) {
      return res.status(400).json({
        success: false,
        error: 'Invalid longitude: must be between -180 and 180'
      });
    }

    const result = await pool.query(
      `UPDATE profiles
       SET latitude = $2,
           longitude = $3,
           location_updated_at = CURRENT_TIMESTAMP,
           updated_at = CURRENT_TIMESTAMP
       WHERE user_id = $1
       RETURNING user_id, latitude, longitude, location_updated_at`,
      [requestedUserId, latitude, longitude]
    );

    if (result.rows.length === 0) {
      return res.status(404).json({ success: false, error: 'Profile not found' });
    }

    logger.info('Location updated', {
      userId: requestedUserId,
      latitude,
      longitude
    });

    res.json({
      success: true,
      location: {
        userId: result.rows[0].user_id,
        latitude: result.rows[0].latitude,
        longitude: result.rows[0].longitude,
        updatedAt: result.rows[0].location_updated_at
      }
    });
  } catch (error) {
    logger.error('Failed to update location', {
      error,
      requestedUserId: req.params.userId
    });
    res.status(500).json({ success: false, error: 'Failed to update location' });
  }
});

// ===== PHOTO UPLOAD ENDPOINTS =====

// Upload photo - Only allow users to upload photos to their own profile
app.post('/profile/photos/upload', authMiddleware, generalLimiter, upload.single('photo'), async (req: Request, res: Response) => {
  try {
    const authenticatedUserId = req.user!.userId;

    // Check if file was uploaded
    if (!req.file) {
      return res.status(400).json({ success: false, error: 'No file uploaded' });
    }

    // Validate image
    const validation = validateImage(req.file);
    if (!validation.valid) {
      return res.status(400).json({ success: false, error: validation.error });
    }

    // Get current profile to check photo count
    const profileResult = await pool.query(
      'SELECT photos FROM profiles WHERE user_id = $1',
      [authenticatedUserId]
    );

    if (profileResult.rows.length === 0) {
      return res.status(404).json({ success: false, error: 'Profile not found' });
    }

    const currentPhotos = profileResult.rows[0].photos || [];

    // Check photo limit
    if (!canUploadMorePhotos(currentPhotos.length)) {
      return res.status(400).json({
        success: false,
        error: `Maximum ${MAX_PHOTOS_PER_PROFILE} photos allowed`
      });
    }

    // Process and save image
    const processedImage = await processImage(req.file, authenticatedUserId);

    // Update profile with new photo URL
    const updatedPhotos = [...currentPhotos, processedImage.url];
    await pool.query(
      'UPDATE profiles SET photos = $1, updated_at = CURRENT_TIMESTAMP WHERE user_id = $2',
      [updatedPhotos, authenticatedUserId]
    );

    res.json({
      success: true,
      photo: {
        url: processedImage.url,
        thumbnailUrl: processedImage.thumbnailUrl,
      },
      totalPhotos: updatedPhotos.length,
    });
  } catch (error) {
    logger.error('Failed to upload photo', { error, userId: req.user?.userId });
    res.status(500).json({ success: false, error: 'Failed to upload photo' });
  }
});

// Delete photo - Only allow users to delete their own photos
app.delete('/profile/photos/:photoId', authMiddleware, generalLimiter, async (req: Request, res: Response) => {
  try {
    const authenticatedUserId = req.user!.userId;
    const photoId = req.params.photoId;

    // Get current profile
    const profileResult = await pool.query(
      'SELECT photos FROM profiles WHERE user_id = $1',
      [authenticatedUserId]
    );

    if (profileResult.rows.length === 0) {
      return res.status(404).json({ success: false, error: 'Profile not found' });
    }

    const currentPhotos: string[] = profileResult.rows[0].photos || [];

    // Find photo URL containing the photoId
    const photoToDelete = currentPhotos.find(url => url.includes(photoId));

    if (!photoToDelete) {
      return res.status(404).json({ success: false, error: 'Photo not found' });
    }

    // Remove photo from array
    const updatedPhotos = currentPhotos.filter(url => url !== photoToDelete);

    // Update database
    await pool.query(
      'UPDATE profiles SET photos = $1, updated_at = CURRENT_TIMESTAMP WHERE user_id = $2',
      [updatedPhotos, authenticatedUserId]
    );

    // Delete physical files (best effort - don't fail if files are missing)
    await deleteImage(photoToDelete);

    res.json({
      success: true,
      message: 'Photo deleted',
      totalPhotos: updatedPhotos.length,
    });
  } catch (error) {
    logger.error('Failed to delete photo', { error, userId: req.user?.userId });
    res.status(500).json({ success: false, error: 'Failed to delete photo' });
  }
});

// Reorder photos - Only allow users to reorder their own photos
app.put('/profile/photos/reorder', authMiddleware, generalLimiter, async (req: Request, res: Response) => {
  try {
    const authenticatedUserId = req.user!.userId;
    const { photos } = req.body;

    if (!Array.isArray(photos)) {
      return res.status(400).json({ success: false, error: 'photos must be an array' });
    }

    // Get current profile to verify all photos belong to user
    const profileResult = await pool.query(
      'SELECT photos FROM profiles WHERE user_id = $1',
      [authenticatedUserId]
    );

    if (profileResult.rows.length === 0) {
      return res.status(404).json({ success: false, error: 'Profile not found' });
    }

    const currentPhotos: string[] = profileResult.rows[0].photos || [];

    // Verify all provided photos are valid
    const invalidPhotos = photos.filter(url => !currentPhotos.includes(url));
    if (invalidPhotos.length > 0) {
      return res.status(400).json({ success: false, error: 'Invalid photo URLs provided' });
    }

    // Update database with reordered photos
    await pool.query(
      'UPDATE profiles SET photos = $1, updated_at = CURRENT_TIMESTAMP WHERE user_id = $2',
      [photos, authenticatedUserId]
    );

    res.json({
      success: true,
      message: 'Photos reordered',
      photos: photos,
    });
  } catch (error) {
    logger.error('Failed to reorder photos', { error, userId: req.user?.userId });
    res.status(500).json({ success: false, error: 'Failed to reorder photos' });
  }
});

// ===== DISCOVERY ENDPOINTS =====

// Get random profiles for discovery - Requires authentication
// P1: Now supports distance filtering based on user location
app.get('/profiles/discover', authMiddleware, discoveryLimiter, async (req: Request, res: Response) => {
  try {
    const authenticatedUserId = req.user!.userId;

    // Parse optional query parameters
    const minAge = req.query.minAge ? parseInt(req.query.minAge as string) : null;
    const maxAge = req.query.maxAge ? parseInt(req.query.maxAge as string) : null;
    const maxDistance = req.query.maxDistance ? parseFloat(req.query.maxDistance as string) : null; // P1: Distance in km
    const interests = req.query.interests ? (req.query.interests as string).split(',') : null;
    const excludeIds = req.query.exclude ? (req.query.exclude as string).split(',') : [];

    // Get current user's location for distance filtering
    let userLocation: { latitude: number; longitude: number } | null = null;
    if (maxDistance !== null) {
      const locationResult = await pool.query(
        'SELECT latitude, longitude FROM profiles WHERE user_id = $1',
        [authenticatedUserId]
      );

      if (locationResult.rows.length > 0 &&
          locationResult.rows[0].latitude !== null &&
          locationResult.rows[0].longitude !== null) {
        userLocation = {
          latitude: locationResult.rows[0].latitude,
          longitude: locationResult.rows[0].longitude
        };
      }
    }

    // Build WHERE clause conditions
    const conditions = [
      'user_id != $1',
      // Exclude users who blocked me (for privacy and safety)
      `user_id NOT IN (SELECT user_id FROM blocks WHERE blocked_user_id = $1)`,
      // Exclude users I blocked
      `user_id NOT IN (SELECT blocked_user_id FROM blocks WHERE user_id = $1)`
    ];
    const params: any[] = [authenticatedUserId];
    let paramIndex = 2;

    // Age filter
    if (minAge !== null) {
      conditions.push(`age >= $${paramIndex}`);
      params.push(minAge);
      paramIndex++;
    }
    if (maxAge !== null) {
      conditions.push(`age <= $${paramIndex}`);
      params.push(maxAge);
      paramIndex++;
    }

    // Interests filter
    if (interests && interests.length > 0) {
      conditions.push(`interests && $${paramIndex}::text[]`);
      params.push(interests);
      paramIndex++;
    }

    // Exclude specific user IDs
    if (excludeIds.length > 0) {
      conditions.push(`user_id != ALL($${paramIndex}::text[])`);
      params.push(excludeIds);
      paramIndex++;
    }

    const whereClause = conditions.join(' AND ');

    // Fetch profiles with or without distance calculation
    let query: string;
    let countQuery: string;
    let totalCount = 0;

    // First, get total count of matching profiles for efficient random offset
    if (userLocation && maxDistance) {
      // Count profiles within distance (more expensive due to distance calculation)
      countQuery = `
        SELECT COUNT(*) as count
        FROM profiles
        WHERE ${whereClause}
          AND latitude IS NOT NULL
          AND longitude IS NOT NULL
          AND (
            6371 * acos(
              cos(radians($${paramIndex})) * cos(radians(latitude)) *
              cos(radians(longitude) - radians($${paramIndex + 1})) +
              sin(radians($${paramIndex})) * sin(radians(latitude))
            )
          ) <= $${paramIndex + 2}
      `;
      const countResult = await pool.query(countQuery, [...params, userLocation.latitude, userLocation.longitude, maxDistance]);
      totalCount = parseInt(countResult.rows[0].count);
    } else {
      // Simple count for non-distance queries
      countQuery = `SELECT COUNT(*) as count FROM profiles WHERE ${whereClause}`;
      const countResult = await pool.query(countQuery, params);
      totalCount = parseInt(countResult.rows[0].count);
    }

    // Calculate random offset (ensure we have enough profiles for LIMIT 20)
    const limit = 20;
    const maxOffset = Math.max(0, totalCount - limit);
    const randomOffset = Math.floor(Math.random() * (maxOffset + 1));

    if (userLocation && maxDistance) {
      // P1: Use Haversine formula to calculate distance and filter
      // Optimized with OFFSET instead of ORDER BY RANDOM()
      query = `
        SELECT
          user_id, name, age, bio, photos, interests, latitude, longitude,
          (
            6371 * acos(
              cos(radians($${paramIndex})) * cos(radians(latitude)) *
              cos(radians(longitude) - radians($${paramIndex + 1})) +
              sin(radians($${paramIndex})) * sin(radians(latitude))
            )
          ) AS distance
        FROM profiles
        WHERE ${whereClause}
          AND latitude IS NOT NULL
          AND longitude IS NOT NULL
        HAVING distance <= $${paramIndex + 2}
        ORDER BY user_id
        OFFSET ${randomOffset}
        LIMIT ${limit}
      `;
      params.push(userLocation.latitude, userLocation.longitude, maxDistance);
    } else {
      // Optimized with OFFSET instead of ORDER BY RANDOM()
      query = `
        SELECT user_id, name, age, bio, photos, interests, latitude, longitude
        FROM profiles
        WHERE ${whereClause}
        ORDER BY user_id
        OFFSET ${randomOffset}
        LIMIT ${limit}
      `;
    }

    const result = await pool.query(query, params);

    const profiles = result.rows.map(profile => {
      const profileData: any = {
        userId: profile.user_id,
        name: profile.name,
        age: profile.age,
        bio: profile.bio,
        photos: profile.photos,
        interests: profile.interests
      };

      // P1: Include distance if calculated
      if (profile.distance !== undefined) {
        profileData.distance = Math.round(profile.distance * 10) / 10; // Round to 1 decimal
      }

      return profileData;
    });

    logger.info('Discovery profiles fetched', {
      userId: authenticatedUserId,
      count: profiles.length,
      filters: {
        minAge,
        maxAge,
        maxDistance,
        hasInterests: interests !== null,
        excludeCount: excludeIds.length
      }
    });

    res.json({ success: true, profiles });
  } catch (error) {
    logger.error('Failed to retrieve profiles', { error });
    res.status(500).json({ success: false, error: 'Failed to retrieve profiles' });
  }
});

// Sentry error handler - must be after all routes but before generic error handler
if (process.env.SENTRY_DSN) {
  Sentry.setupExpressErrorHandler(app);
}

// Generic error handler (optional - for catching any remaining errors)
app.use((err: any, req: Request, res: Response, next: any) => {
  logger.error('Unhandled error', {
    error: err.message,
    stack: err.stack,
    path: req.path,
    method: req.method
  });
  res.status(500).json({ success: false, error: 'Internal server error' });
});

// Only start server if not in test environment
if (process.env.NODE_ENV !== 'test') {
  // Initialize upload directory before starting server
  initializeUploadDirectory()
    .then(() => {
      app.listen(PORT, () => {
        logger.info(`Profile service started`, { port: PORT, environment: process.env.NODE_ENV || 'development' });
      });
    })
    .catch((error) => {
      logger.error('Failed to initialize upload directory', { error });
      process.exit(1);
    });
}

// Export for testing
export default app;
