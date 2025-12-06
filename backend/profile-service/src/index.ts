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
import path from 'path';
import fs from 'fs';
import os from 'os';
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

// Trust proxy - required for Railway/production environments behind reverse proxy
// This allows express-rate-limit to correctly identify users via X-Forwarded-For
app.set('trust proxy', 1);

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
app.use(helmet({
  hidePoweredBy: true // Explicitly hide X-Powered-By header
}));
app.use(cors({
  origin: CORS_ORIGIN,
  credentials: true,
  methods: ['GET', 'POST', 'PUT', 'DELETE', 'OPTIONS'],
  allowedHeaders: ['Content-Type', 'Authorization']
}));
app.use(express.json({ limit: '10kb' }));

// Serve static files (uploaded images)
app.use('/uploads', express.static('uploads'));

// Configure multer for file uploads using disk storage to prevent OOM attacks
// Files are stored in temp directory and cleaned up after processing
const UPLOAD_TEMP_DIR = process.env.UPLOAD_TEMP_DIR || path.join(os.tmpdir(), 'vlvt-uploads');

// Ensure temp upload directory exists
if (!fs.existsSync(UPLOAD_TEMP_DIR)) {
  fs.mkdirSync(UPLOAD_TEMP_DIR, { recursive: true });
  logger.info('Created temp upload directory', { path: UPLOAD_TEMP_DIR });
}

const diskStorage = multer.diskStorage({
  destination: (req, file, cb) => {
    cb(null, UPLOAD_TEMP_DIR);
  },
  filename: (req, file, cb) => {
    // Generate unique filename to prevent collisions
    const uniqueSuffix = `${Date.now()}-${Math.round(Math.random() * 1E9)}`;
    const ext = path.extname(file.originalname) || '.tmp';
    cb(null, `upload-${uniqueSuffix}${ext}`);
  }
});

const upload = multer({
  storage: diskStorage,
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
    ? { rejectUnauthorized: false }
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
      // Use subquery to filter by calculated distance (can't use HAVING without GROUP BY)
      query = `
        SELECT * FROM (
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
        ) AS profiles_with_distance
        WHERE distance <= $${paramIndex + 2}
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

// ===== SEARCH ENDPOINTS (for free users to see user counts) =====

// Search for count of users matching criteria
app.post('/profiles/search/count', authMiddleware, generalLimiter, async (req: Request, res: Response) => {
  try {
    const authenticatedUserId = req.user!.userId;
    const { maxDistance, genders, sexualPreferences, intents } = req.body;

    // Get current user's location for distance filtering
    const locationResult = await pool.query(
      'SELECT latitude, longitude FROM profiles WHERE user_id = $1',
      [authenticatedUserId]
    );

    let userLocation: { latitude: number; longitude: number } | null = null;
    if (locationResult.rows.length > 0 &&
        locationResult.rows[0].latitude !== null &&
        locationResult.rows[0].longitude !== null) {
      userLocation = {
        latitude: locationResult.rows[0].latitude,
        longitude: locationResult.rows[0].longitude
      };
    }

    // Build WHERE clause conditions
    const conditions = [
      'user_id != $1', // Exclude self
      // Exclude users who blocked me
      `user_id NOT IN (SELECT user_id FROM blocks WHERE blocked_user_id = $1)`,
      // Exclude users I blocked
      `user_id NOT IN (SELECT blocked_user_id FROM blocks WHERE user_id = $1)`
    ];
    const params: any[] = [authenticatedUserId];
    let paramIndex = 2;

    // Distance filter - convert miles to km (1 mile = 1.60934 km)
    let distanceFilter = '';
    if (userLocation && maxDistance) {
      const maxDistanceKm = maxDistance * 1.60934;
      distanceFilter = `
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
      params.push(userLocation.latitude, userLocation.longitude, maxDistanceKm);
      paramIndex += 3;
    }

    // Note: Gender, sexual preference, and intent filters would require
    // those columns to exist in the profiles table. For now, we count
    // all profiles within distance. These can be added when the schema
    // is updated to include these fields.

    const whereClause = conditions.join(' AND ');

    const countQuery = `
      SELECT COUNT(*) as count
      FROM profiles
      WHERE ${whereClause}
      ${distanceFilter}
    `;

    const result = await pool.query(countQuery, params);
    const count = parseInt(result.rows[0].count);

    logger.info('Search count executed', {
      userId: authenticatedUserId,
      maxDistance,
      hasLocation: userLocation !== null,
      count
    });

    res.json({ success: true, count });
  } catch (error) {
    logger.error('Failed to search user count', { error, userId: req.user?.userId });
    res.status(500).json({ success: false, error: 'Failed to search' });
  }
});

// ===== SWIPE ENDPOINTS =====

// Record a swipe (like/pass) and check for mutual match
app.post('/swipes', authMiddleware, generalLimiter, async (req: Request, res: Response) => {
  try {
    const authenticatedUserId = req.user!.userId;
    const { targetUserId, action } = req.body;

    // Validate input
    if (!targetUserId || !action) {
      return res.status(400).json({
        success: false,
        error: 'targetUserId and action are required'
      });
    }

    if (!['like', 'pass'].includes(action)) {
      return res.status(400).json({
        success: false,
        error: 'action must be "like" or "pass"'
      });
    }

    if (targetUserId === authenticatedUserId) {
      return res.status(400).json({
        success: false,
        error: 'Cannot swipe on yourself'
      });
    }

    // Check if target user exists
    const targetUserResult = await pool.query(
      'SELECT user_id FROM profiles WHERE user_id = $1',
      [targetUserId]
    );

    if (targetUserResult.rows.length === 0) {
      return res.status(404).json({
        success: false,
        error: 'Target user not found'
      });
    }

    // Record the swipe (upsert to handle re-swipes)
    await pool.query(
      `INSERT INTO swipes (user_id, target_user_id, action, created_at)
       VALUES ($1, $2, $3, CURRENT_TIMESTAMP)
       ON CONFLICT (user_id, target_user_id)
       DO UPDATE SET action = $3, created_at = CURRENT_TIMESTAMP`,
      [authenticatedUserId, targetUserId, action]
    );

    logger.info('Swipe recorded', {
      userId: authenticatedUserId,
      targetUserId,
      action
    });

    // If action is 'like', check for mutual like
    let isMatch = false;
    if (action === 'like') {
      const mutualLikeResult = await pool.query(
        `SELECT id FROM swipes
         WHERE user_id = $1 AND target_user_id = $2 AND action = 'like'`,
        [targetUserId, authenticatedUserId]
      );

      isMatch = mutualLikeResult.rows.length > 0;

      if (isMatch) {
        logger.info('Mutual match detected', {
          userId: authenticatedUserId,
          targetUserId
        });
      }
    }

    res.json({
      success: true,
      action,
      isMatch,
      message: isMatch ? 'It\'s a match!' : (action === 'like' ? 'Like recorded' : 'Pass recorded')
    });
  } catch (error) {
    logger.error('Failed to record swipe', {
      error,
      userId: req.user?.userId,
      targetUserId: req.body.targetUserId
    });
    res.status(500).json({ success: false, error: 'Failed to record swipe' });
  }
});

// Get users who have liked the current user (for "See who likes you" feature)
app.get('/swipes/received', authMiddleware, generalLimiter, async (req: Request, res: Response) => {
  try {
    const authenticatedUserId = req.user!.userId;

    const result = await pool.query(
      `SELECT s.user_id, s.created_at, p.name, p.age, p.photos
       FROM swipes s
       JOIN profiles p ON p.user_id = s.user_id
       WHERE s.target_user_id = $1 AND s.action = 'like'
       ORDER BY s.created_at DESC`,
      [authenticatedUserId]
    );

    const likes = result.rows.map(row => ({
      userId: row.user_id,
      name: row.name,
      age: row.age,
      photos: row.photos,
      likedAt: row.created_at
    }));

    res.json({ success: true, likes });
  } catch (error) {
    logger.error('Failed to get received likes', { error, userId: req.user?.userId });
    res.status(500).json({ success: false, error: 'Failed to get received likes' });
  }
});

// Get users the current user has liked (sent likes - for matches screen)
app.get('/swipes/sent', authMiddleware, generalLimiter, async (req: Request, res: Response) => {
  try {
    const authenticatedUserId = req.user!.userId;

    const result = await pool.query(
      `SELECT s.target_user_id, s.created_at, p.name, p.age, p.photos
       FROM swipes s
       JOIN profiles p ON p.user_id = s.target_user_id
       WHERE s.user_id = $1 AND s.action = 'like'
       ORDER BY s.created_at DESC`,
      [authenticatedUserId]
    );

    const likes = result.rows.map(row => ({
      target_user_id: row.target_user_id,
      name: row.name,
      age: row.age,
      photos: row.photos,
      created_at: row.created_at
    }));

    res.json({ success: true, likes });
  } catch (error) {
    logger.error('Failed to get sent likes', { error, userId: req.user?.userId });
    res.status(500).json({ success: false, error: 'Failed to get sent likes' });
  }
});

// Seed test profiles endpoint (ONLY FOR DEVELOPMENT/TESTING/BETA)
if (process.env.NODE_ENV !== 'production' || process.env.ENABLE_TEST_ENDPOINTS === 'true') {
  app.post('/profile/seed-test-profiles', async (req: Request, res: Response) => {
    try {
      const seedSQL = `
INSERT INTO profiles (user_id, name, age, bio, photos, interests, created_at, updated_at) VALUES
('google_test001', 'Alex Chen', 28, 'Software engineer by day, amateur chef by night. Love exploring new restaurants and trying to recreate the dishes at home. Always up for spontaneous road trips!', ARRAY['https://i.pravatar.cc/300?img=1'], ARRAY['Cooking', 'Technology', 'Travel', 'Photography', 'Hiking'], NOW() - INTERVAL '30 days', NOW() - INTERVAL '5 days'),
('google_test002', 'Jordan Rivera', 25, 'Yoga instructor and meditation enthusiast. Believer in positive vibes and good coffee. Let''s grab matcha and talk about life!', ARRAY['https://i.pravatar.cc/300?img=2'], ARRAY['Yoga', 'Fitness', 'Coffee', 'Reading', 'Nature'], NOW() - INTERVAL '28 days', NOW() - INTERVAL '3 days'),
('google_test003', 'Sam Patel', 31, 'Marketing strategist with a passion for live music. Concert regular and vinyl collector. Can''t resist a good pun.', ARRAY['https://i.pravatar.cc/300?img=3'], ARRAY['Music', 'Concerts', 'Marketing', 'Vinyl Records', 'Comedy'], NOW() - INTERVAL '25 days', NOW() - INTERVAL '7 days'),
('google_test004', 'Taylor Kim', 27, 'Graphic designer who loves turning coffee into creativity. Weekend warrior at local art galleries. Looking for someone to explore the city with.', ARRAY['https://i.pravatar.cc/300?img=4'], ARRAY['Art', 'Design', 'Coffee', 'Museums', 'Illustration'], NOW() - INTERVAL '22 days', NOW() - INTERVAL '2 days'),
('google_test005', 'Morgan Santos', 29, 'Outdoor enthusiast and rock climbing addict. If I''m not at the gym, I''m probably at the crag. Let''s belay each other through life!', ARRAY['https://i.pravatar.cc/300?img=5'], ARRAY['Climbing', 'Outdoor Adventures', 'Fitness', 'Photography', 'Travel'], NOW() - INTERVAL '20 days', NOW() - INTERVAL '1 days'),
('google_test006', 'Casey Nguyen', 26, 'Elementary school teacher with a love for board games and terrible dad jokes. Looking for a Player 2!', ARRAY['https://i.pravatar.cc/300?img=6'], ARRAY['Board Games', 'Teaching', 'Reading', 'Comedy', 'Cooking'], NOW() - INTERVAL '18 days', NOW() - INTERVAL '4 days'),
('google_test007', 'Riley Anderson', 30, 'Data scientist trying to make sense of the world, one dataset at a time. Love sci-fi, craft beer, and philosophical conversations.', ARRAY['https://i.pravatar.cc/300?img=7'], ARRAY['Science', 'Beer', 'Books', 'Technology', 'Philosophy'], NOW() - INTERVAL '15 days', NOW() - INTERVAL '1 days'),
('google_test008', 'Avery Williams', 24, 'Aspiring photographer capturing the beauty in everyday moments. Dog lover (I have a golden retriever named Sunny). Let''s go on photo walks!', ARRAY['https://i.pravatar.cc/300?img=8'], ARRAY['Photography', 'Dogs', 'Nature', 'Art', 'Walking'], NOW() - INTERVAL '12 days', NOW() - INTERVAL '2 days'),
('google_test009', 'Drew Martinez', 32, 'Entrepreneur building the next big thing. Work hard, play harder. Looking for someone ambitious who can keep up!', ARRAY['https://i.pravatar.cc/300?img=9'], ARRAY['Entrepreneurship', 'Travel', 'Fitness', 'Technology', 'Wine'], NOW() - INTERVAL '10 days', NOW() - INTERVAL '1 days'),
('google_test010', 'Charlie Lee', 28, 'Bookworm and aspiring novelist. If you can recommend a good book, you''ve already won me over. Favorite genre: magical realism.', ARRAY['https://i.pravatar.cc/300?img=10'], ARRAY['Reading', 'Writing', 'Books', 'Coffee', 'Art'], NOW() - INTERVAL '8 days', NOW() - INTERVAL '1 days'),
('google_test011', 'Jamie Brown', 26, 'Personal trainer helping people crush their fitness goals. Meal prep enthusiast and smoothie expert. Let''s get healthy together!', ARRAY['https://i.pravatar.cc/300?img=11'], ARRAY['Fitness', 'Health', 'Cooking', 'Running', 'Yoga'], NOW() - INTERVAL '6 days', NOW() - INTERVAL '6 hours'),
('google_test012', 'Quinn Davis', 29, 'Architect designing spaces where life happens. Lover of modern design and mid-century furniture. Can talk about buildings for hours.', ARRAY['https://i.pravatar.cc/300?img=12'], ARRAY['Architecture', 'Design', 'Art', 'Travel', 'Photography'], NOW() - INTERVAL '5 days', NOW() - INTERVAL '12 hours'),
('google_test013', 'Reese Garcia', 27, 'Marine biologist passionate about ocean conservation. Scuba certified and always planning the next dive trip. Let''s save the oceans together!', ARRAY['https://i.pravatar.cc/300?img=13'], ARRAY['Scuba Diving', 'Ocean', 'Travel', 'Science', 'Photography'], NOW() - INTERVAL '4 days', NOW() - INTERVAL '4 hours'),
('google_test014', 'Skylar Wilson', 25, 'Pastry chef who believes life is too short for bad desserts. Weekend brunch enthusiast. I''ll bake you cookies on the first date!', ARRAY['https://i.pravatar.cc/300?img=14'], ARRAY['Baking', 'Cooking', 'Food', 'Coffee', 'Travel'], NOW() - INTERVAL '3 days', NOW() - INTERVAL '3 hours'),
('google_test015', 'Blake Moore', 30, 'Lawyer by profession, comedian by heart. Improv classes keep me sane. Looking for someone who appreciates good humor and better debates.', ARRAY['https://i.pravatar.cc/300?img=15'], ARRAY['Comedy', 'Improv', 'Debate', 'Theater', 'Reading'], NOW() - INTERVAL '2 days', NOW() - INTERVAL '2 hours'),
('google_test016', 'Phoenix Taylor', 28, 'DJ spinning records and good vibes. Music festival regular. Life''s a party, and I''m always looking for the next adventure.', ARRAY['https://i.pravatar.cc/300?img=16'], ARRAY['Music', 'DJing', 'Festivals', 'Dancing', 'Travel'], NOW() - INTERVAL '1 days', NOW() - INTERVAL '1 hour'),
('google_test017', 'Sage Jackson', 26, 'Veterinarian who thinks all animals are perfect. Proud plant parent with 30+ houseplants. Let''s talk about your pets for hours!', ARRAY['https://i.pravatar.cc/300?img=17'], ARRAY['Animals', 'Veterinary', 'Plants', 'Nature', 'Hiking'], NOW() - INTERVAL '12 hours', NOW() - INTERVAL '30 minutes'),
('google_test018', 'Dakota White', 31, 'Financial advisor who actually makes money interesting. Love traveling on points and finding the best deals. Let me plan our vacation!', ARRAY['https://i.pravatar.cc/300?img=18'], ARRAY['Travel', 'Finance', 'Hiking', 'Wine', 'Photography'], NOW() - INTERVAL '6 hours', NOW() - INTERVAL '15 minutes'),
('google_test019', 'River Harris', 24, 'Video game developer living the dream. Gamer, anime fan, and bubble tea addict. Looking for a co-op partner in life!', ARRAY['https://i.pravatar.cc/300?img=19'], ARRAY['Gaming', 'Anime', 'Technology', 'Coding', 'Esports'], NOW() - INTERVAL '3 hours', NOW() - INTERVAL '10 minutes'),
('google_test020', 'Ocean Clark', 27, 'Environmental scientist fighting climate change. Vegan foodie and zero-waste advocate. Let''s make the world a better place, one date at a time.', ARRAY['https://i.pravatar.cc/300?img=20'], ARRAY['Environment', 'Sustainability', 'Vegan', 'Science', 'Activism'], NOW() - INTERVAL '1 hour', NOW() - INTERVAL '5 minutes')
ON CONFLICT (user_id) DO NOTHING;
      `;

      await pool.query(seedSQL);

      res.json({ success: true, message: 'Test profiles seeded successfully' });
      logger.info('Test profiles seeded');
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : 'Unknown error';
      logger.error('Seed profiles error', { error: errorMessage, fullError: error });
      res.status(500).json({ success: false, error: `Seed failed: ${errorMessage}` });
    }
  });

  logger.warn('Test profile seed endpoint enabled (NOT FOR PRODUCTION)');
}

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
