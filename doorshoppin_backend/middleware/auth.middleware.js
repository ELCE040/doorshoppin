import jwt from 'jsonwebtoken';

function getJwtSecret() {
  const secret = process.env.JWT_SECRET;
  if (!secret) {
    throw new Error('JWT_SECRET is not configured');
  }
  return secret;
}

/**
 * Authentication middleware
 * Extracts and verifies JWT token from Authorization header
 * Adds userId to req.userId for use in route handlers
 */
export const authenticate = (req, res, next) => {
  try {
    // Get token from Authorization header
    const authHeader = req.headers.authorization;
    
    if (!authHeader) {
      return res.status(401).json({
        success: false,
        error: 'No authorization token provided',
      });
    }

    // Extract token from "Bearer <token>" format
    const token = authHeader.startsWith('Bearer ')
      ? authHeader.substring(7)
      : authHeader;

    if (!token) {
      return res.status(401).json({
        success: false,
        error: 'Invalid authorization header format',
      });
    }

    // Verify token
    const decoded = jwt.verify(token, getJwtSecret());

    // Extract userId from token payload
    if (!decoded.userId) {
      return res.status(401).json({
        success: false,
        error: 'Invalid token: missing userId',
      });
    }

    // Add userId to request object
    req.userId = decoded.userId;
    req.userEmail = decoded.email;

    // Continue to next middleware/route
    next();
  } catch (error) {
    if (error.name === 'JsonWebTokenError') {
      return res.status(401).json({
        success: false,
        error: 'Invalid token',
      });
    }
    if (error.name === 'TokenExpiredError') {
      return res.status(401).json({
        success: false,
        error: 'Token expired',
      });
    }
    
    console.error('❌ Auth middleware error:', error);
    return res.status(500).json({
      success: false,
      error: 'Authentication error',
      message: error.message,
    });
  }
};

/**
 * Optional authentication middleware
 * Tries to authenticate but doesn't fail if token is missing
 * Useful for routes that work for both authenticated and anonymous users
 */
export const optionalAuthenticate = (req, res, next) => {
  try {
    const authHeader = req.headers.authorization;
    
    if (!authHeader) {
      // No token provided, continue without authentication
      req.userId = null;
      req.userEmail = null;
      return next();
    }

    const token = authHeader.startsWith('Bearer ')
      ? authHeader.substring(7)
      : authHeader;

    if (!token) {
      req.userId = null;
      req.userEmail = null;
      return next();
    }

    const decoded = jwt.verify(token, getJwtSecret());

    req.userId = decoded.userId || null;
    req.userEmail = decoded.email || null;

    next();
  } catch (error) {
    // If token is invalid, continue without authentication
    req.userId = null;
    req.userEmail = null;
    next();
  }
};

/**
 * Admin authentication middleware
 * Verifies JWT from Authorization header and expects adminId in payload (from admin login).
 * Use for admin-only routes (e.g. product create/update/delete).
 */
export const authenticateAdmin = (req, res, next) => {
  try {
    const authHeader = req.headers.authorization;
    if (!authHeader) {
      return res.status(401).json({
        success: false,
        error: 'Admin authorization required',
      });
    }
    const token = authHeader.startsWith('Bearer ')
      ? authHeader.substring(7)
      : authHeader;
    if (!token) {
      return res.status(401).json({
        success: false,
        error: 'Invalid authorization header',
      });
    }
    const decoded = jwt.verify(token, getJwtSecret());
    if (!decoded.adminId) {
      return res.status(401).json({
        success: false,
        error: 'Invalid token: admin only',
      });
    }
    req.adminId = decoded.adminId;
    req.adminUsername = decoded.username;
    next();
  } catch (error) {
    if (error.name === 'JsonWebTokenError') {
      return res.status(401).json({ success: false, error: 'Invalid token' });
    }
    if (error.name === 'TokenExpiredError') {
      return res.status(401).json({ success: false, error: 'Token expired' });
    }
    console.error('Admin auth error:', error);
    return res.status(500).json({
      success: false,
      error: 'Authentication error',
      message: error.message,
    });
  }
};

/**
 * Allows either a customer token or an admin token.
 * Use for sensitive reads where admins can inspect any resource and users can inspect their own.
 */
export const authenticateUserOrAdmin = (req, res, next) => {
  try {
    const authHeader = req.headers.authorization;
    if (!authHeader) {
      return res.status(401).json({
        success: false,
        error: 'Authorization required',
      });
    }
    const token = authHeader.startsWith('Bearer ')
      ? authHeader.substring(7)
      : authHeader;
    if (!token) {
      return res.status(401).json({
        success: false,
        error: 'Invalid authorization header',
      });
    }
    const decoded = jwt.verify(token, getJwtSecret());
    if (decoded.adminId) {
      req.adminId = decoded.adminId;
      req.adminUsername = decoded.username;
      return next();
    }
    if (decoded.userId) {
      req.userId = decoded.userId;
      req.userEmail = decoded.email;
      return next();
    }
    return res.status(401).json({
      success: false,
      error: 'Invalid token',
    });
  } catch (error) {
    if (error.name === 'JsonWebTokenError') {
      return res.status(401).json({ success: false, error: 'Invalid token' });
    }
    if (error.name === 'TokenExpiredError') {
      return res.status(401).json({ success: false, error: 'Token expired' });
    }
    console.error('Auth middleware error:', error);
    return res.status(500).json({
      success: false,
      error: 'Authentication error',
      message: error.message,
    });
  }
};
