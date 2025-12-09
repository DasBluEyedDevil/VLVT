# VLVT - Known Issues

**Last Updated**: 2025-12-09
**Current Beta Phase**: Ready for Launch
**App Version**: Beta v0.2.0

## Overview

This document tracks known issues, limitations, and planned improvements for VLVT. We update this regularly as we discover and resolve issues.

---

## Critical Issues (P0)

> Showstopper issues that severely impact core functionality.

**Currently: None reported**

---

## High Priority Issues (P1)

> Issues that significantly impact user experience.

### Push Notifications
- **Status**: Infrastructure ready, awaiting Firebase console setup
- **Impact**: Users won't receive notifications until configured
- **ETA**: Pre-launch configuration task

---

## Medium Priority Issues (P2)

> Minor issues or edge cases.

**None reported**

---

## Low Priority Issues (P3)

> Cosmetic issues and enhancement requests.

**None reported**

---

## Features Implemented

The following features are **COMPLETE** and working:

### Core Features
- **Authentication**: Apple, Google, Email/Password, Instagram OAuth
- **Profile Management**: Photo uploads with EXIF stripping, bio, interests
- **Discovery**: Swipe interface with distance filtering
- **Matching**: Mutual like detection, match creation
- **Chat**: Real-time messaging via WebSocket
- **Read Receipts**: Sent, Delivered, Read status tracking
- **Read Receipt UI**: Visual indicators (grey checks for sent/delivered, gold for read)
- **Typing Indicators**: Real-time display with auto-hide
- **Dark Mode**: Comprehensive VlvtColors theme system
- **Empty States**: Concierge-style actionable empty states
- **Location Services**: GPS capture, distance filtering (Haversine)
- **Offline Message Queue**: Auto-retry with 3 attempts, 24h expiration
- **Push Notifications**: Backend triggers for new matches and messages (awaiting Firebase setup)
- **Deep Linking**: Navigate to chat/matches from notification taps
- **Safety**: Block, Report, Emergency Contacts
- **Subscriptions**: RevenueCat integration (sandbox mode)

### Security & Privacy
- **EXIF Stripping**: All photo metadata removed
- **Delete Account**: Full cascade delete of all user data
- **HTTPS**: Enforced on all endpoints
- **Rate Limiting**: Applied to all public endpoints
- **JWT Authentication**: Secure token-based auth

### Legal
- **Terms of Service**: Finalized (Delaware jurisdiction)
- **Privacy Policy**: GDPR/CCPA compliant

---

## Features in Development (Phase 2+)

### Phase 2: Active Development
1. **Golden Ticket Referrals** - Viral growth mechanism (partial)
2. **Propose a Date** - In-chat date planning (partial)
3. **Verified Selfies** - AWS Rekognition verification (partial)

### Phase 3: Backlog
1. **Video Chat** - WebRTC video calls
2. **Voice Messages** - Audio message support
3. **GIF/Sticker Support** - Rich media in chat
4. **AI Icebreakers** - Conversation starters
5. **Admin Dashboard** - Internal moderation tools

---

## Platform-Specific Notes

### iOS
- Requires APNs configuration for push notifications
- TestFlight build ready for beta distribution

### Android
- Requires SHA fingerprints registered in Firebase
- Play Console internal testing track ready

---

## How to Report Issues

1. Use the in-app feedback widget (Profile screen)
2. Email: beta@getvlvt.vip
3. GitHub Issues: [Repository Link]

### Include:
- Device model and OS version
- App version/build number
- Steps to reproduce
- Screenshots or videos

---

## Issue Resolution Timeline

| Priority | Response | Target Resolution |
|----------|----------|-------------------|
| P0 (Critical) | < 4 hours | < 24 hours |
| P1 (High) | < 8 hours | < 3 days |
| P2 (Medium) | < 24 hours | < 1 week |
| P3 (Low) | < 48 hours | Post-launch |

---

## Changelog

### 2025-12-09 (v0.2.0)
- Implemented Offline Message Queue (auto-retry, 24h expiration)
- Implemented Read Receipt UI (gold double-checks for read status)
- Implemented Push Notification triggers (new match, new message)
- Implemented Deep Linking from notifications
- Updated documentation to reflect Beta readiness

### 2025-12-09
- Major update: Documented all implemented features
- Removed outdated "not implemented" items
- Updated to reflect Phase 0 completion

### 2025-11-13
- Initial document created
