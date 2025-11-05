import { Router } from 'express';
import { Client } from 'pg';
import fs from 'fs';
import path from 'path';

const router = Router();

// TEMPORARY: Remove this endpoint after migrations are done!
router.post('/run-migrations', async (req, res) => {
  const { secret } = req.body;

  // Simple security check
  if (secret !== process.env.MIGRATION_SECRET) {
    return res.status(403).json({ error: 'Unauthorized' });
  }

  const migrations = [
    '001_create_users_and_profiles.sql',
    '002_create_matches_and_messages.sql',
    '003_create_safety_tables.sql'
  ];

  const client = new Client({
    connectionString: process.env.DATABASE_URL,
    ssl: process.env.DATABASE_URL?.includes('railway') ? { rejectUnauthorized: false } : false
  });

  try {
    await client.connect();
    const results = [];

    for (const migration of migrations) {
      const migrationPath = path.join(__dirname, '..', migration);
      const sql = fs.readFileSync(migrationPath, 'utf8');

      try {
        await client.query(sql);
        results.push({ migration, status: 'success' });
      } catch (error: any) {
        results.push({ migration, status: 'failed', error: error.message });
      }
    }

    await client.end();

    return res.json({
      message: 'Migrations completed',
      results
    });

  } catch (error: any) {
    return res.status(500).json({
      error: 'Migration failed',
      message: error.message
    });
  }
});

export default router;
