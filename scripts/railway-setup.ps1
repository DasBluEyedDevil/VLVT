# Railway Setup Helper Script (PowerShell)
# This script helps set up and verify Railway deployment

Write-Host "🚀 NoBS Dating - Railway Setup Helper" -ForegroundColor Cyan
Write-Host "======================================" -ForegroundColor Cyan
Write-Host ""

# Check if Railway CLI is installed
function Check-RailwayCLI {
    if (!(Get-Command railway -ErrorAction SilentlyContinue)) {
        Write-Host "✗ Railway CLI not found" -ForegroundColor Red
        Write-Host ""
        Write-Host "Install Railway CLI:"
        Write-Host "  iwr https://railway.app/install.ps1 | iex"
        Write-Host ""
        exit 1
    }
    else {
        Write-Host "✓ Railway CLI installed" -ForegroundColor Green
    }
}

# Check if logged in to Railway
function Check-RailwayAuth {
    try {
        $whoami = railway whoami 2>&1
        Write-Host "✓ Logged in to Railway" -ForegroundColor Green
        Write-Host $whoami
    }
    catch {
        Write-Host "⚠ Not logged in to Railway" -ForegroundColor Yellow
        Write-Host "Run: railway login"
        exit 1
    }
}

# Generate JWT secret
function Generate-JWTSecret {
    Write-Host ""
    Write-Host "📝 Generate JWT Secret" -ForegroundColor Cyan
    Write-Host "======================"
    Write-Host ""

    # Generate random bytes and convert to base64
    $bytes = New-Object byte[] 48
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    $rng.GetBytes($bytes)
    $jwtSecret = [Convert]::ToBase64String($bytes)

    Write-Host "Your JWT Secret (copy this):"
    Write-Host $jwtSecret -ForegroundColor Green
    Write-Host ""
    Write-Host "Add this to Railway:"
    Write-Host "  Dashboard → Auth Service → Variables → JWT_SECRET"
    Write-Host ""

    # Copy to clipboard if available
    try {
        Set-Clipboard -Value $jwtSecret
        Write-Host "✓ Copied to clipboard!" -ForegroundColor Green
        Write-Host ""
    }
    catch {
        # Clipboard not available, that's okay
    }
}

# Display environment variables template
function Show-EnvTemplate {
    Write-Host ""
    Write-Host "📋 Environment Variables Template" -ForegroundColor Cyan
    Write-Host "================================="
    Write-Host ""
    Write-Host "AUTH SERVICE:"
    Write-Host "  PORT=3001"
    Write-Host "  JWT_SECRET=<paste-generated-secret>"
    Write-Host '  DATABASE_URL=${{Postgres.DATABASE_URL}}'
    Write-Host "  NODE_ENV=production"
    Write-Host "  CORS_ORIGIN=*"
    Write-Host ""
    Write-Host "PROFILE SERVICE:"
    Write-Host "  PORT=3002"
    Write-Host '  DATABASE_URL=${{Postgres.DATABASE_URL}}'
    Write-Host "  NODE_ENV=production"
    Write-Host "  CORS_ORIGIN=*"
    Write-Host ""
    Write-Host "CHAT SERVICE:"
    Write-Host "  PORT=3003"
    Write-Host '  DATABASE_URL=${{Postgres.DATABASE_URL}}'
    Write-Host "  NODE_ENV=production"
    Write-Host "  CORS_ORIGIN=*"
    Write-Host ""
}

# Run database migrations
function Run-Migrations {
    Write-Host ""
    Write-Host "🗄️  Run Database Migrations" -ForegroundColor Cyan
    Write-Host "=========================="
    Write-Host ""

    # Check if DATABASE_URL is set
    if (!$env:DATABASE_URL) {
        Write-Host "Getting DATABASE_URL from Railway..."
        try {
            $env:DATABASE_URL = railway variables get DATABASE_URL
        }
        catch {
            # Failed to get DATABASE_URL
        }
    }

    if (!$env:DATABASE_URL) {
        Write-Host "⚠ DATABASE_URL not found" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "Get it with: railway variables get DATABASE_URL"
        Write-Host "Or link your project: railway link"
        Write-Host ""
        Write-Host "Then set it:"
        Write-Host '  $env:DATABASE_URL="postgresql://..."'
        Write-Host "  .\scripts\railway-setup.ps1"
        return
    }

    Write-Host "Running migrations..."
    Push-Location backend\migrations

    Get-ChildItem -Filter "*.sql" | ForEach-Object {
        Write-Host "  → Running $($_.Name)"
        psql $env:DATABASE_URL -f $_.Name -q
    }

    Pop-Location
    Write-Host "✓ Migrations complete" -ForegroundColor Green
}

# Verify deployment
function Verify-Deployment {
    Write-Host ""
    Write-Host "✅ Verify Deployment" -ForegroundColor Cyan
    Write-Host "==================="
    Write-Host ""

    $authUrl = Read-Host "Enter Auth Service URL"
    $profileUrl = Read-Host "Enter Profile Service URL"
    $chatUrl = Read-Host "Enter Chat Service URL"

    Write-Host ""
    Write-Host "Testing endpoints..."

    # Test auth service
    Write-Host "  Auth Service... " -NoNewline
    try {
        $response = Invoke-WebRequest -Uri "$authUrl/health" -UseBasicParsing -TimeoutSec 10
        if ($response.StatusCode -eq 200) {
            Write-Host "✓" -ForegroundColor Green
        }
        else {
            Write-Host "✗" -ForegroundColor Red
        }
    }
    catch {
        Write-Host "✗" -ForegroundColor Red
    }

    # Test profile service
    Write-Host "  Profile Service... " -NoNewline
    try {
        $response = Invoke-WebRequest -Uri "$profileUrl/health" -UseBasicParsing -TimeoutSec 10
        if ($response.StatusCode -eq 200) {
            Write-Host "✓" -ForegroundColor Green
        }
        else {
            Write-Host "✗" -ForegroundColor Red
        }
    }
    catch {
        Write-Host "✗" -ForegroundColor Red
    }

    # Test chat service
    Write-Host "  Chat Service... " -NoNewline
    try {
        $response = Invoke-WebRequest -Uri "$chatUrl/health" -UseBasicParsing -TimeoutSec 10
        if ($response.StatusCode -eq 200) {
            Write-Host "✓" -ForegroundColor Green
        }
        else {
            Write-Host "✗" -ForegroundColor Red
        }
    }
    catch {
        Write-Host "✗" -ForegroundColor Red
    }

    Write-Host ""
}

# Main menu
function Show-Menu {
    Write-Host ""
    Write-Host "What would you like to do?"
    Write-Host ""
    Write-Host "1) Generate JWT Secret"
    Write-Host "2) Show Environment Variables Template"
    Write-Host "3) Run Database Migrations"
    Write-Host "4) Verify Deployment"
    Write-Host "5) All of the above (recommended)"
    Write-Host "6) Exit"
    Write-Host ""
    $choice = Read-Host "Choice [1-6]"

    switch ($choice) {
        "1" {
            Generate-JWTSecret
        }
        "2" {
            Show-EnvTemplate
        }
        "3" {
            Run-Migrations
        }
        "4" {
            Verify-Deployment
        }
        "5" {
            Generate-JWTSecret
            Show-EnvTemplate
            Write-Host ""
            Read-Host "Press enter to continue to migrations (make sure env vars are set first)"
            Run-Migrations
            Verify-Deployment
        }
        "6" {
            Write-Host "Goodbye!"
            exit 0
        }
        default {
            Write-Host "Invalid choice"
            Show-Menu
        }
    }
}

# Handle command line arguments
param(
    [Parameter(Position = 0)]
    [string]$Command
)

switch ($Command) {
    "check" {
        Check-RailwayCLI
        Check-RailwayAuth
    }
    "jwt" {
        Generate-JWTSecret
    }
    "env" {
        Show-EnvTemplate
    }
    "migrate" {
        Run-Migrations
    }
    "verify" {
        Verify-Deployment
    }
    default {
        Check-RailwayCLI
        Check-RailwayAuth
        Show-Menu
    }
}

Write-Host ""
Write-Host "Done! 🎉"
Write-Host ""
Write-Host "Next steps:"
Write-Host "  1. Deploy services in Railway dashboard"
Write-Host "  2. Set environment variables"
Write-Host "  3. Run migrations (if not already done)"
Write-Host "  4. Update Flutter app config with Railway URLs"
Write-Host ""
Write-Host "See RAILWAY_QUICKSTART.md for detailed instructions"
Write-Host ""
