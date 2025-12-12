/**
 * Profile Completion Check Utility
 * Checks if a user's profile is complete and ID verified for messaging
 */

import { Pool } from 'pg';
import logger from './logger';

export interface ProfileCompletionResult {
  isComplete: boolean;
  missingFields: string[];
  message: string;
}

/**
 * Check if a user's profile is complete for messaging
 * Requirements: name, age, bio, at least 1 photo, and ID verification
 */
export async function isProfileComplete(
  pool: Pool,
  userId: string
): Promise<ProfileCompletionResult> {
  try {
    // Query both profiles and users tables to check all requirements
    const result = await pool.query(
      `SELECT 
        p.name,
        p.age,
        p.bio,
        p.photos,
        u.id_verified
      FROM profiles p
      INNER JOIN users u ON p.user_id = u.id
      WHERE p.user_id = $1`,
      [userId]
    );

    if (result.rows.length === 0) {
      return {
        isComplete: false,
        missingFields: ['profile'],
        message: 'Profile not found. Please complete your profile setup.'
      };
    }

    const profile = result.rows[0];
    const missingFields: string[] = [];

    // Check required fields
    if (!profile.name || profile.name.trim().length === 0) {
      missingFields.push('name');
    }

    if (!profile.age || profile.age < 18) {
      missingFields.push('age');
    }

    if (!profile.bio || profile.bio.trim().length === 0) {
      missingFields.push('bio');
    }

    if (!profile.photos || !Array.isArray(profile.photos) || profile.photos.length === 0) {
      missingFields.push('photos');
    }

    if (!profile.id_verified) {
      missingFields.push('id_verification');
    }

    if (missingFields.length > 0) {
      const fieldNames = missingFields.map(field => {
        switch (field) {
          case 'name':
            return 'name';
          case 'age':
            return 'age';
          case 'bio':
            return 'bio';
          case 'photos':
            return 'at least one photo';
          case 'id_verification':
            return 'ID verification';
          default:
            return field;
        }
      });

      let message = 'Please complete your profile to start messaging: ';
      message += fieldNames.join(', ');

      return {
        isComplete: false,
        missingFields,
        message
      };
    }

    return {
      isComplete: true,
      missingFields: [],
      message: 'Profile is complete'
    };
  } catch (error) {
    logger.error('Error checking profile completion', {
      error: error instanceof Error ? error.message : 'Unknown error',
      userId
    });
    // Fail closed - don't allow messaging if we can't verify profile
    return {
      isComplete: false,
      missingFields: ['unknown'],
      message: 'Unable to verify profile completion. Please try again.'
    };
  }
}

