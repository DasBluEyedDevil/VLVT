/**
 * Express type extensions for VLVT microservices
 */

export interface JWTPayload {
  userId: string;
  provider: string;
  email: string;
}

declare global {
  namespace Express {
    interface Request {
      user?: JWTPayload;
    }
  }
}

export {};
