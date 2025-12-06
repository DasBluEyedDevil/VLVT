import sharp from 'sharp';
import { v4 as uuidv4 } from 'uuid';
import fs from 'fs/promises';
import path from 'path';
import logger from './logger';

// Configuration
const MAX_FILE_SIZE = 10 * 1024 * 1024; // 10MB
const ALLOWED_MIME_TYPES = ['image/jpeg', 'image/jpg', 'image/png', 'image/heic', 'image/heif', 'image/webp'];
const MAX_PHOTOS_PER_PROFILE = 6;
const UPLOAD_DIR = process.env.UPLOAD_DIR || path.join(__dirname, '../../uploads');

// Image sizes for optimization
const IMAGE_SIZES = {
  thumbnail: { width: 200, height: 200 },
  medium: { width: 800, height: 800 },
  large: { width: 1200, height: 1200 },
};

export interface ProcessedImage {
  id: string;
  url: string;
  thumbnailUrl: string;
  originalSize: number;
  processedSize: number;
}

/**
 * Initialize upload directory
 */
export async function initializeUploadDirectory(): Promise<void> {
  try {
    await fs.mkdir(UPLOAD_DIR, { recursive: true });
    await fs.mkdir(path.join(UPLOAD_DIR, 'thumbnails'), { recursive: true });
    logger.info('Upload directory initialized', { path: UPLOAD_DIR });
  } catch (error) {
    logger.error('Failed to initialize upload directory', { error });
    throw error;
  }
}

/**
 * Validate uploaded image file
 */
export function validateImage(file: Express.Multer.File): { valid: boolean; error?: string } {
  // Check file size
  if (file.size > MAX_FILE_SIZE) {
    return { valid: false, error: `File size exceeds ${MAX_FILE_SIZE / 1024 / 1024}MB limit` };
  }

  // Check MIME type
  if (!ALLOWED_MIME_TYPES.includes(file.mimetype.toLowerCase())) {
    return { valid: false, error: 'Invalid file type. Only JPEG, PNG, HEIC, HEIF, and WebP images are allowed' };
  }

  return { valid: true };
}

/**
 * Process and optimize image
 * Creates thumbnail and optimized versions
 * Supports both memory storage (file.buffer) and disk storage (file.path)
 */
export async function processImage(file: Express.Multer.File, userId: string): Promise<ProcessedImage> {
  const photoId = uuidv4();
  const ext = 'jpg'; // Always convert to JPEG for consistency

  // Determine input source: disk storage uses file.path, memory storage uses file.buffer
  const inputSource = file.path || file.buffer;
  const usingDiskStorage = !!file.path;

  try {
    // Process main image (large size)
    const largeFilename = `${userId}_${photoId}.${ext}`;
    const largePath = path.join(UPLOAD_DIR, largeFilename);

    const largeImage = await sharp(inputSource)
      .rotate() // Auto-rotate based on EXIF orientation AND strip all EXIF metadata (including GPS location)
      .resize(IMAGE_SIZES.large.width, IMAGE_SIZES.large.height, {
        fit: 'inside',
        withoutEnlargement: true,
      })
      .jpeg({ quality: 85, progressive: true })
      .withMetadata({}) // Explicitly remove all metadata for privacy
      .toFile(largePath);

    // Process thumbnail
    const thumbnailFilename = `${userId}_${photoId}_thumb.${ext}`;
    const thumbnailPath = path.join(UPLOAD_DIR, 'thumbnails', thumbnailFilename);

    await sharp(inputSource)
      .rotate() // Auto-rotate and strip EXIF from thumbnail too
      .resize(IMAGE_SIZES.thumbnail.width, IMAGE_SIZES.thumbnail.height, {
        fit: 'cover',
        position: 'center',
      })
      .jpeg({ quality: 80 })
      .withMetadata({}) // Remove metadata from thumbnail
      .toFile(thumbnailPath);

    logger.info('Image processed successfully', {
      photoId,
      originalSize: file.size,
      processedSize: largeImage.size,
      userId,
      storageType: usingDiskStorage ? 'disk' : 'memory',
    });

    // Clean up temp file if using disk storage
    if (usingDiskStorage && file.path) {
      try {
        await fs.unlink(file.path);
        logger.debug('Cleaned up temp upload file', { path: file.path });
      } catch (cleanupError) {
        logger.warn('Failed to clean up temp upload file', { path: file.path, error: cleanupError });
      }
    }

    return {
      id: photoId,
      url: `/uploads/${largeFilename}`,
      thumbnailUrl: `/uploads/thumbnails/${thumbnailFilename}`,
      originalSize: file.size,
      processedSize: largeImage.size,
    };
  } catch (error) {
    // Clean up temp file even on error if using disk storage
    if (usingDiskStorage && file.path) {
      try {
        await fs.unlink(file.path);
      } catch (cleanupError) {
        logger.warn('Failed to clean up temp file after error', { path: file.path });
      }
    }
    logger.error('Failed to process image', { error, userId });
    throw new Error('Failed to process image');
  }
}

/**
 * Delete image files from disk
 */
export async function deleteImage(photoUrl: string): Promise<void> {
  try {
    // Extract filename from URL
    const filename = path.basename(photoUrl);
    const filePath = path.join(UPLOAD_DIR, filename);

    // Delete main image
    await fs.unlink(filePath).catch(() => {
      logger.warn('Main image file not found', { filePath });
    });

    // Delete thumbnail
    const thumbnailFilename = filename.replace(/\.(jpg|jpeg|png)$/i, '_thumb.jpg');
    const thumbnailPath = path.join(UPLOAD_DIR, 'thumbnails', thumbnailFilename);
    await fs.unlink(thumbnailPath).catch(() => {
      logger.warn('Thumbnail file not found', { thumbnailPath });
    });

    logger.info('Image deleted successfully', { photoUrl });
  } catch (error) {
    logger.error('Failed to delete image', { error, photoUrl });
    // Don't throw - deletion is best effort
  }
}

/**
 * Get photo ID from URL
 */
export function getPhotoIdFromUrl(url: string): string | null {
  const match = url.match(/[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}/i);
  return match ? match[0] : null;
}

/**
 * Check if user can upload more photos
 */
export function canUploadMorePhotos(currentPhotoCount: number): boolean {
  return currentPhotoCount < MAX_PHOTOS_PER_PROFILE;
}

export { MAX_PHOTOS_PER_PROFILE };
