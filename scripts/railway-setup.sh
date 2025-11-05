#!/bin/bash

# Railway Setup Helper Script
# This script helps set up and verify Railway deployment

set -e  # Exit on error

echo "🚀 NoBS Dating - Railway Setup Helper"
echo "======================================"
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check if Railway CLI is installed
check_railway_cli() {
    if ! command -v railway &> /dev/null; then
        echo -e "${RED}✗${NC} Railway CLI not found"
        echo ""
        echo "Install Railway CLI:"
        echo "  macOS/Linux: sh -c \"\$(curl -fsSL https://railway.app/install.sh)\""
        echo "  Windows: iwr https://railway.app/install.ps1 | iex"
        echo "  npm: npm install -g @railway/cli"
        echo ""
        exit 1
    else
        echo -e "${GREEN}✓${NC} Railway CLI installed"
    fi
}

# Check if logged in to Railway
check_railway_auth() {
    if railway whoami &> /dev/null; then
        echo -e "${GREEN}✓${NC} Logged in to Railway"
        railway whoami
    else
        echo -e "${YELLOW}⚠${NC} Not logged in to Railway"
        echo "Run: railway login"
        exit 1
    fi
}

# Generate JWT secret
generate_jwt_secret() {
    echo ""
    echo "📝 Generate JWT Secret"
    echo "======================"
    JWT_SECRET=$(openssl rand -base64 64 | tr -d '\n')
    echo ""
    echo "Your JWT Secret (copy this):"
    echo -e "${GREEN}${JWT_SECRET}${NC}"
    echo ""
    echo "Add this to Railway:"
    echo "  Dashboard → Auth Service → Variables → JWT_SECRET"
    echo ""
}

# Display environment variables template
show_env_template() {
    echo ""
    echo "📋 Environment Variables Template"
    echo "================================="
    echo ""
    echo "AUTH SERVICE:"
    echo "  PORT=3001"
    echo "  JWT_SECRET=<paste-generated-secret>"
    echo "  DATABASE_URL=\${{Postgres.DATABASE_URL}}"
    echo "  NODE_ENV=production"
    echo "  CORS_ORIGIN=*"
    echo ""
    echo "PROFILE SERVICE:"
    echo "  PORT=3002"
    echo "  DATABASE_URL=\${{Postgres.DATABASE_URL}}"
    echo "  NODE_ENV=production"
    echo "  CORS_ORIGIN=*"
    echo ""
    echo "CHAT SERVICE:"
    echo "  PORT=3003"
    echo "  DATABASE_URL=\${{Postgres.DATABASE_URL}}"
    echo "  NODE_ENV=production"
    echo "  CORS_ORIGIN=*"
    echo ""
}

# Run database migrations
run_migrations() {
    echo ""
    echo "🗄️  Run Database Migrations"
    echo "=========================="
    echo ""

    # Check if DATABASE_URL is set
    if [ -z "$DATABASE_URL" ]; then
        echo "Getting DATABASE_URL from Railway..."
        export DATABASE_URL=$(railway variables get DATABASE_URL 2>/dev/null || echo "")
    fi

    if [ -z "$DATABASE_URL" ]; then
        echo -e "${YELLOW}⚠${NC} DATABASE_URL not found"
        echo ""
        echo "Get it with: railway variables get DATABASE_URL"
        echo "Or link your project: railway link"
        echo ""
        echo "Then set it:"
        echo "  export DATABASE_URL=\"postgresql://...\""
        echo "  ./scripts/railway-setup.sh migrate"
        return 1
    fi

    echo "Running migrations..."
    cd backend/migrations

    for migration in *.sql; do
        echo "  → Running $migration"
        psql "$DATABASE_URL" -f "$migration" -q
    done

    cd ../..
    echo -e "${GREEN}✓${NC} Migrations complete"
}

# Verify deployment
verify_deployment() {
    echo ""
    echo "✅ Verify Deployment"
    echo "==================="
    echo ""

    read -p "Enter Auth Service URL: " AUTH_URL
    read -p "Enter Profile Service URL: " PROFILE_URL
    read -p "Enter Chat Service URL: " CHAT_URL

    echo ""
    echo "Testing endpoints..."

    # Test auth service
    echo -n "  Auth Service... "
    if curl -s -f "$AUTH_URL/health" > /dev/null; then
        echo -e "${GREEN}✓${NC}"
    else
        echo -e "${RED}✗${NC}"
    fi

    # Test profile service
    echo -n "  Profile Service... "
    if curl -s -f "$PROFILE_URL/health" > /dev/null; then
        echo -e "${GREEN}✓${NC}"
    else
        echo -e "${RED}✗${NC}"
    fi

    # Test chat service
    echo -n "  Chat Service... "
    if curl -s -f "$CHAT_URL/health" > /dev/null; then
        echo -e "${GREEN}✓${NC}"
    else
        echo -e "${RED}✗${NC}"
    fi

    echo ""
}

# Main menu
show_menu() {
    echo ""
    echo "What would you like to do?"
    echo ""
    echo "1) Generate JWT Secret"
    echo "2) Show Environment Variables Template"
    echo "3) Run Database Migrations"
    echo "4) Verify Deployment"
    echo "5) All of the above (recommended)"
    echo "6) Exit"
    echo ""
    read -p "Choice [1-6]: " choice

    case $choice in
        1)
            generate_jwt_secret
            ;;
        2)
            show_env_template
            ;;
        3)
            run_migrations
            ;;
        4)
            verify_deployment
            ;;
        5)
            generate_jwt_secret
            show_env_template
            echo ""
            read -p "Press enter to continue to migrations (make sure env vars are set first)..."
            run_migrations
            verify_deployment
            ;;
        6)
            echo "Goodbye!"
            exit 0
            ;;
        *)
            echo "Invalid choice"
            show_menu
            ;;
    esac
}

# Handle command line arguments
case "${1:-}" in
    "check")
        check_railway_cli
        check_railway_auth
        ;;
    "jwt")
        generate_jwt_secret
        ;;
    "env")
        show_env_template
        ;;
    "migrate")
        run_migrations
        ;;
    "verify")
        verify_deployment
        ;;
    *)
        check_railway_cli
        check_railway_auth
        show_menu
        ;;
esac

echo ""
echo "Done! 🎉"
echo ""
echo "Next steps:"
echo "  1. Deploy services in Railway dashboard"
echo "  2. Set environment variables"
echo "  3. Run migrations (if not already done)"
echo "  4. Update Flutter app config with Railway URLs"
echo ""
echo "See RAILWAY_QUICKSTART.md for detailed instructions"
echo ""
