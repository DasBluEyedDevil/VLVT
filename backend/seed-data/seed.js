#!/usr/bin/env node

/**
 * NoBS Dating Test Database Seeding Script
 *
 * This script populates the database with realistic test users, profiles,
 * matches, and messages for comprehensive testing.
 *
 * Usage:
 *   node seed.js                    # Seed the database
 *   node seed.js --clean            # Clean test data first, then seed
 *   node seed.js --clean-only       # Only clean test data
 *
 * Environment Variables:
 *   DATABASE_URL - PostgreSQL connection string
 */

const { Pool } = require('pg');
const fs = require('fs');
const path = require('path');

// Database connection
const pool = new Pool({
  connectionString: process.env.DATABASE_URL || 'postgresql://postgres:postgres@localhost:5432/nobsdating',
});

// Parse command line arguments
const args = process.argv.slice(2);
const shouldClean = args.includes('--clean');
const cleanOnly = args.includes('--clean-only');

/**
 * Clean existing test data
 */
async function cleanTestData() {
  console.log('🧹 Cleaning existing test data...');

  const client = await pool.connect();

  try {
    await client.query('BEGIN');

    // Delete in correct order due to foreign key constraints
    await client.query("DELETE FROM messages WHERE match_id LIKE 'test_%'");
    console.log('  ✓ Removed test messages');

    await client.query("DELETE FROM matches WHERE id LIKE 'test_%'");
    console.log('  ✓ Removed test matches');

    await client.query("DELETE FROM blocks WHERE user_id LIKE 'google_test%' OR blocked_user_id LIKE 'google_test%'");
    console.log('  ✓ Removed test blocks');

    await client.query("DELETE FROM reports WHERE reporter_id LIKE 'google_test%' OR reported_user_id LIKE 'google_test%'");
    console.log('  ✓ Removed test reports');

    await client.query("DELETE FROM profiles WHERE user_id LIKE 'google_test%'");
    console.log('  ✓ Removed test profiles');

    await client.query("DELETE FROM users WHERE id LIKE 'google_test%'");
    console.log('  ✓ Removed test users');

    await client.query('COMMIT');
    console.log('✅ Test data cleaned successfully!\n');
  } catch (error) {
    await client.query('ROLLBACK');
    console.error('❌ Error cleaning test data:', error.message);
    throw error;
  } finally {
    client.release();
  }
}

/**
 * Seed the database with test data
 */
async function seedDatabase() {
  console.log('🌱 Seeding database with test data...');

  // Read the SQL file
  const sqlPath = path.join(__dirname, 'seed.sql');
  const sql = fs.readFileSync(sqlPath, 'utf8');

  // Remove comments and split by statement
  const statements = sql
    .split('\n')
    .filter(line => !line.trim().startsWith('--'))
    .join('\n')
    .split(';')
    .filter(stmt => stmt.trim().length > 0);

  const client = await pool.connect();

  try {
    await client.query('BEGIN');

    for (const statement of statements) {
      const trimmed = statement.trim();
      if (trimmed.length > 0) {
        await client.query(trimmed);
      }
    }

    await client.query('COMMIT');

    // Count what was created
    const userCount = await client.query("SELECT COUNT(*) FROM users WHERE id LIKE 'google_test%'");
    const profileCount = await client.query("SELECT COUNT(*) FROM profiles WHERE user_id LIKE 'google_test%'");
    const matchCount = await client.query("SELECT COUNT(*) FROM matches WHERE id LIKE 'test_%'");
    const messageCount = await client.query("SELECT COUNT(*) FROM messages WHERE match_id LIKE 'test_%'");

    console.log('\n✅ Database seeded successfully!');
    console.log(`  ✓ Created ${userCount.rows[0].count} test users`);
    console.log(`  ✓ Created ${profileCount.rows[0].count} test profiles`);
    console.log(`  ✓ Created ${matchCount.rows[0].count} test matches`);
    console.log(`  ✓ Created ${messageCount.rows[0].count} test messages`);

  } catch (error) {
    await client.query('ROLLBACK');
    console.error('❌ Error seeding database:', error.message);
    throw error;
  } finally {
    client.release();
  }
}

/**
 * Display test user information
 */
async function displayTestUsers() {
  console.log('\n📋 Test Users Available:');
  console.log('═══════════════════════════════════════════════════════════════\n');

  const client = await pool.connect();

  try {
    const result = await client.query(`
      SELECT u.id, u.email, p.name, p.age, p.bio
      FROM users u
      LEFT JOIN profiles p ON u.id = p.user_id
      WHERE u.id LIKE 'google_test%'
      ORDER BY u.id
    `);

    result.rows.forEach((user, index) => {
      console.log(`${index + 1}. ${user.name || 'No Name'} (${user.age || '?'})`);
      console.log(`   ID: ${user.id}`);
      console.log(`   Email: ${user.email}`);
      if (user.bio) {
        console.log(`   Bio: ${user.bio.substring(0, 60)}...`);
      }
      console.log('');
    });

    console.log('═══════════════════════════════════════════════════════════════');
    console.log('\n💡 To use these test accounts:');
    console.log('   1. Use the test login endpoint: POST /auth/test-login');
    console.log('      Body: { "userId": "google_test001" }');
    console.log('   2. Or generate JWT tokens manually using the auth service');
    console.log('\n   See backend/seed-data/README.md for detailed instructions.\n');

  } catch (error) {
    console.error('❌ Error fetching test users:', error.message);
  } finally {
    client.release();
  }
}

/**
 * Main execution
 */
async function main() {
  try {
    console.log('\n🚀 NoBS Dating Test Data Seeder\n');

    if (cleanOnly) {
      await cleanTestData();
    } else {
      if (shouldClean) {
        await cleanTestData();
      }
      await seedDatabase();
      await displayTestUsers();
    }

    await pool.end();
    process.exit(0);
  } catch (error) {
    console.error('\n💥 Fatal error:', error);
    await pool.end();
    process.exit(1);
  }
}

// Run the script
main();
