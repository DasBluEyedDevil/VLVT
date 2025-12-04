import nodemailer from 'nodemailer';
import type { Transporter } from 'nodemailer';
import logger from '../utils/logger';

type EmailProvider = 'console' | 'smtp' | 'sendgrid' | 'resend';

interface EmailOptions {
  to: string;
  subject: string;
  html: string;
  text?: string;
}

interface EmailConfig {
  provider: EmailProvider;
  from: string;
  appName: string;
  appUrl: string;
  smtp?: {
    host: string;
    port: number;
    user: string;
    pass: string;
  };
  sendgrid?: {
    apiKey: string;
  };
  resend?: {
    apiKey: string;
  };
}

class EmailService {
  private config: EmailConfig;
  private transporter: Transporter | null = null;

  constructor() {
    this.config = this.loadConfig();
    this.initializeTransporter();
  }

  private loadConfig(): EmailConfig {
    const provider = (process.env.EMAIL_PROVIDER || 'console') as EmailProvider;

    const config: EmailConfig = {
      provider,
      from: process.env.EMAIL_FROM || 'noreply@getvlvt.vip',
      appName: process.env.APP_NAME || 'VLVT',
      appUrl: process.env.APP_URL || 'https://getvlvt.vip',
    };

    if (provider === 'smtp') {
      const host = process.env.SMTP_HOST;
      const user = process.env.SMTP_USER;
      const pass = process.env.SMTP_PASS;

      if (!host || !user || !pass) {
        logger.warn('SMTP configuration incomplete, falling back to console mode');
        config.provider = 'console';
      } else {
        config.smtp = {
          host,
          port: parseInt(process.env.SMTP_PORT || '587', 10),
          user,
          pass,
        };
      }
    } else if (provider === 'sendgrid') {
      const apiKey = process.env.SENDGRID_API_KEY;

      if (!apiKey) {
        logger.warn('SendGrid configuration incomplete, falling back to console mode');
        config.provider = 'console';
      } else {
        config.sendgrid = {
          apiKey,
        };
      }
    } else if (provider === 'resend') {
      const apiKey = process.env.RESEND_API_KEY;

      if (!apiKey) {
        logger.warn('Resend configuration incomplete, falling back to console mode');
        config.provider = 'console';
      } else {
        config.resend = {
          apiKey,
        };
      }
    }

    return config;
  }

  private initializeTransporter(): void {
    if (this.config.provider === 'console') {
      // No transporter needed for console mode
      return;
    }

    if (this.config.provider === 'smtp' && this.config.smtp) {
      this.transporter = nodemailer.createTransport({
        host: this.config.smtp.host,
        port: this.config.smtp.port,
        secure: this.config.smtp.port === 465,
        auth: {
          user: this.config.smtp.user,
          pass: this.config.smtp.pass,
        },
      });
    } else if (this.config.provider === 'sendgrid' && this.config.sendgrid) {
      this.transporter = nodemailer.createTransport({
        host: 'smtp.sendgrid.net',
        port: 587,
        secure: false,
        auth: {
          user: 'apikey',
          pass: this.config.sendgrid.apiKey,
        },
      });
    } else if (this.config.provider === 'resend' && this.config.resend) {
      this.transporter = nodemailer.createTransport({
        host: 'smtp.resend.com',
        port: 587,
        secure: false,
        auth: {
          user: 'resend',
          pass: this.config.resend.apiKey,
        },
      });
    }
  }

  async sendEmail(options: EmailOptions): Promise<boolean> {
    try {
      if (this.config.provider === 'console') {
        logger.info('EMAIL (Console Mode)', {
          to: options.to,
          subject: options.subject,
          text: options.text || 'No text version',
          htmlLength: options.html.length
        });
        return true;
      }

      if (!this.transporter) {
        logger.error('Email transporter not initialized');
        return false;
      }

      await this.transporter.sendMail({
        from: this.config.from,
        to: options.to,
        subject: options.subject,
        text: options.text,
        html: options.html,
      });

      logger.info('Email sent successfully', { to: options.to });
      return true;
    } catch (error) {
      logger.error('Error sending email', { error, to: options.to });
      return false;
    }
  }

  async sendVerificationEmail(email: string, token: string): Promise<boolean> {
    const verificationUrl = `${this.config.appUrl}/verify?token=${token}`;

    const html = this.getVerificationEmailTemplate(verificationUrl);
    const text = `Welcome to ${this.config.appName}!\n\nPlease verify your email address by clicking the following link:\n${verificationUrl}\n\nThis link will expire in 24 hours.\n\nIf you didn't create an account, you can safely ignore this email.`;

    return this.sendEmail({
      to: email,
      subject: `Verify your ${this.config.appName} account`,
      html,
      text,
    });
  }

  async sendPasswordResetEmail(email: string, token: string): Promise<boolean> {
    const resetUrl = `${this.config.appUrl}/reset-password?token=${token}`;

    const html = this.getPasswordResetEmailTemplate(resetUrl);
    const text = `Password Reset Request\n\nWe received a request to reset your password for your ${this.config.appName} account.\n\nClick the following link to reset your password:\n${resetUrl}\n\nThis link will expire in 1 hour.\n\nIf you didn't request a password reset, you can safely ignore this email.`;

    return this.sendEmail({
      to: email,
      subject: `Reset your ${this.config.appName} password`,
      html,
      text,
    });
  }

  private getVerificationEmailTemplate(verificationUrl: string): string {
    return `
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Verify Your Email</title>
  <style>
    body {
      font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, 'Helvetica Neue', Arial, sans-serif;
      line-height: 1.6;
      color: #333;
      max-width: 600px;
      margin: 0 auto;
      padding: 20px;
      background-color: #f5f5f5;
    }
    .container {
      background-color: #ffffff;
      border-radius: 8px;
      padding: 40px;
      box-shadow: 0 2px 4px rgba(0, 0, 0, 0.1);
    }
    .header {
      text-align: center;
      margin-bottom: 30px;
    }
    .logo {
      font-size: 32px;
      font-weight: bold;
      color: #6B46C1;
      margin-bottom: 10px;
    }
    h1 {
      color: #333;
      font-size: 24px;
      margin-bottom: 20px;
    }
    .button {
      display: inline-block;
      padding: 14px 32px;
      background-color: #6B46C1;
      color: #ffffff;
      text-decoration: none;
      border-radius: 6px;
      font-weight: 600;
      margin: 20px 0;
    }
    .button:hover {
      background-color: #553399;
    }
    .footer {
      margin-top: 30px;
      padding-top: 20px;
      border-top: 1px solid #e0e0e0;
      font-size: 14px;
      color: #666;
    }
    .link {
      color: #6B46C1;
      word-break: break-all;
    }
  </style>
</head>
<body>
  <div class="container">
    <div class="header">
      <div class="logo">${this.config.appName}</div>
    </div>

    <h1>Welcome to ${this.config.appName}!</h1>

    <p>Thank you for signing up. To complete your registration and start using your account, please verify your email address.</p>

    <div style="text-align: center;">
      <a href="${verificationUrl}" class="button">Verify Email Address</a>
    </div>

    <p>Or copy and paste this link into your browser:</p>
    <p class="link">${verificationUrl}</p>

    <div class="footer">
      <p>This verification link will expire in 24 hours.</p>
      <p>If you didn't create an account with ${this.config.appName}, you can safely ignore this email.</p>
    </div>
  </div>
</body>
</html>
    `.trim();
  }

  private getPasswordResetEmailTemplate(resetUrl: string): string {
    return `
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Reset Your Password</title>
  <style>
    body {
      font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, 'Helvetica Neue', Arial, sans-serif;
      line-height: 1.6;
      color: #333;
      max-width: 600px;
      margin: 0 auto;
      padding: 20px;
      background-color: #f5f5f5;
    }
    .container {
      background-color: #ffffff;
      border-radius: 8px;
      padding: 40px;
      box-shadow: 0 2px 4px rgba(0, 0, 0, 0.1);
    }
    .header {
      text-align: center;
      margin-bottom: 30px;
    }
    .logo {
      font-size: 32px;
      font-weight: bold;
      color: #6B46C1;
      margin-bottom: 10px;
    }
    h1 {
      color: #333;
      font-size: 24px;
      margin-bottom: 20px;
    }
    .button {
      display: inline-block;
      padding: 14px 32px;
      background-color: #6B46C1;
      color: #ffffff;
      text-decoration: none;
      border-radius: 6px;
      font-weight: 600;
      margin: 20px 0;
    }
    .button:hover {
      background-color: #553399;
    }
    .footer {
      margin-top: 30px;
      padding-top: 20px;
      border-top: 1px solid #e0e0e0;
      font-size: 14px;
      color: #666;
    }
    .link {
      color: #6B46C1;
      word-break: break-all;
    }
    .warning {
      background-color: #fff3cd;
      border: 1px solid #ffc107;
      border-radius: 4px;
      padding: 12px;
      margin: 20px 0;
      color: #856404;
    }
  </style>
</head>
<body>
  <div class="container">
    <div class="header">
      <div class="logo">${this.config.appName}</div>
    </div>

    <h1>Password Reset Request</h1>

    <p>We received a request to reset the password for your ${this.config.appName} account.</p>

    <div style="text-align: center;">
      <a href="${resetUrl}" class="button">Reset Password</a>
    </div>

    <p>Or copy and paste this link into your browser:</p>
    <p class="link">${resetUrl}</p>

    <div class="warning">
      <strong>Security Notice:</strong> This password reset link will expire in 1 hour for your security.
    </div>

    <div class="footer">
      <p>If you didn't request a password reset, you can safely ignore this email. Your password will remain unchanged.</p>
      <p>If you're having trouble with the button above, copy and paste the URL into your web browser.</p>
    </div>
  </div>
</body>
</html>
    `.trim();
  }
}

// Export as singleton
export const emailService = new EmailService();
