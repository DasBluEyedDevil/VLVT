# Gemini Context: NoBS Dating Project

This document provides essential context about the NoBS Dating project for Gemini AI.

## 1. Project Overview

**NoBS Dating** is a mobile dating application designed with a "straightforward" philosophy. It is built as a microservices-based system.

*   **Frontend**: A cross-platform mobile application built with **Flutter**. It handles user authentication, profile viewing/swiping (discovery), matching, and chatting. It uses the Provider pattern for state management and integrates with RevenueCat for subscription gating.

*   **Backend**: A set of **Node.js/TypeScript** microservices running on **Express**. Each service is containerized with Docker.
    *   **Auth Service (`:3001`)**: Manages user authentication via Google/Apple and issues JWTs.
    *   **Profile Service (`:3002`)**: Manages user profile data (creation, updates, and discovery).
    *   **Chat Service (`:3003`)**: A placeholder service intended to manage matches and messages.

*   **Database**: A **PostgreSQL** database, containerized via Docker, serves as the central data store for all backend services.

The overall architecture is documented in detail in `docs/ARCHITECTURE.md`.

## 2. Building and Running

### Full-Stack Quick Start (Recommended)

This process uses Docker Compose to run the entire backend and Flutter for the frontend.

1.  **Start the Backend (Database & Services):**
    From the project root, run the provided shell script. This will build and start the Docker containers for PostgreSQL, auth-service, profile-service, and chat-service.

    ```bash
    ./start-backend.sh
    # or
    # docker-compose up --build
    ```

2.  **Run the Frontend App:**
    Navigate to the `frontend` directory, install dependencies, and run the app. API keys for services like RevenueCat may need to be provided via `--dart-define`.

    ```bash
    cd frontend
    flutter pub get
    flutter run
    ```

### Individual Service Development

#### Backend Services

Each backend service can be run independently for development.

1.  **Run Migrations:**
    To set up the database schema, run the migration script first. Ensure the PostgreSQL container is running.

    ```bash
    cd backend/migrations
    npm install
    npm run migrate
    ```

2.  **Run a Specific Service (e.g., auth-service):**

    ```bash
    cd backend/auth-service
    npm install
    npm run dev
    ```
    The `npm run dev` script uses `ts-node` for live reloading.

#### Frontend

Standard Flutter commands are used.

```bash
cd frontend
flutter test
flutter run
```

## 3. Development Conventions

*   **Backend:**
    *   **Language:** TypeScript
    *   **Build Process:** Code is compiled from `src/` to `dist/` using `npm run build`. The production server runs the compiled JS with `npm start`.
    *   **Testing:** Unit and integration tests are run with Jest (`npm test`).
    *   **Database:** Schema changes are managed via SQL files and a simple Node.js migration runner in `backend/migrations`.

*   **Frontend:**
    *   **Language:** Dart (Flutter)
    *   **State Management:** The `provider` package is the primary tool for state management. Services (`AuthService`, `ProfileApiService`, etc.) are provided at the top level in `lib/main.dart`.
    *   **Dependencies:** Managed via `pubspec.yaml`. Run `flutter pub get` after any changes.
    *   **Code Style:** Conforms to `flutter_lints`.
    *   **Secure Storage:** `flutter_secure_storage` is used to persist JWTs.

*   **API & Communication:**
    *   The frontend communicates with the backend services via a REST API.
    *   Authentication is handled via JWTs sent in the `Authorization` header.
    *   The app uses RevenueCat for managing premium subscription status.
