# Repository Guidelines

## Project Structure & Module Organization
- `frontend/`: Flutter app (`lib/` feature code, `assets/` static, `test/` widget/unit suites).
- `backend/`: Node.js/TypeScript microservices — `auth-service`, `profile-service`, `chat-service` (Express under `src/`, Jest in `tests/`), `shared/` helpers, `migrations/` + `database/` SQL, `seed-data/` personas.
- `docs/`: Architecture, setup, security, and testing references (see `docs/README.md`, `docs/ARCHITECTURE.md`).
- `docker-compose.yml` + `start-backend.sh`: spin up Postgres and all services; `.env.example` / `.env.railway.example` list required secrets.

## Build, Run, and Test Commands
- Backend stack: `cp .env.example .env` then `./start-backend.sh` (wraps `docker-compose up --build`) to start Postgres + all services on 3001/3002/3003.
- Service dev loop: `cd backend/<service> && npm install && npm run dev`; production: `npm run build && npm start`; migrations where present: `npm run migrate`; tests: `npm test` or `npm run test:coverage` (Jest + supertest).
- Seed personas for manual/E2E flows: `cd backend/seed-data && npm install && npm run seed` with Postgres running.
- Flutter: `cd frontend && flutter pub get && flutter run --dart-define=REVENUECAT_API_KEY=...`; checks: `flutter analyze` and `flutter test`.

## Coding Style & Naming Conventions
- TypeScript: 2-space indents, single quotes, async/await, slim controllers. Keep new modules under `src/` (e.g., `utils/logger.ts`); PascalCase for classes/types, camelCase for functions/vars.
- Flutter: follows `analysis_options.yaml` (flutter_lints). Files use `snake_case.dart`; widgets/classes in PascalCase; use shared colors/components from `lib/theme/` and recent VLVT UI tokens.

## Testing Guidelines
- Backend: Jest suites live in `backend/*/tests`; start Postgres (docker) first. Cover new endpoints with supertest and include unhappy paths; use seed personas for matching/chat checks.
- Frontend: widget tests in `frontend/test/widgets` and peers; favor mocked services instead of live APIs. Keep the “Test Users (Dev Only)” login path working for manual runs.

## Commit & Pull Request Guidelines
- Use Conventional Commits with scope (e.g., `feat(vlvt): ...`, `fix(auth-service): ...`) as seen in `git log`.
- PRs: add a concise summary, linked ticket, screenshots/recordings for UI changes, and a short “Tests” list. Call out env/config changes; keep PRs narrowly scoped.

## Security & Configuration Tips
- Never commit secrets; copy from `.env.example`/`.env.railway.example` and keep `.env` local. `JWT_SECRET`, DB creds, RevenueCat keys, and Sentry DSN must be set per environment.
- Reuse input validation and rate-limit/logging middlewares when adding routes. Refer to `docs/SECURITY.md` and `docs/SECURITY_QUICK_REFERENCE.md` before new integrations.
