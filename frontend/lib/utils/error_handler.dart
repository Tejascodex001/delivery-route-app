import 'dart:convert';
import 'package:flutter/material.dart';

class ErrorHandler {
  /// Check if response body contains HTML error page
  static bool isHtmlError(String body) {
    if (body.isEmpty) return false;
    
    // Common HTML error indicators
    final htmlIndicators = [
      '<html',
      '<!DOCTYPE html',
      '<head>',
      '<body>',
      '<title>',
      '<h1>',
      '<p>',
      '<div',
      '<span',
      'Error',
      'Not Found',
      'Internal Server Error',
      'Bad Request',
      'Unauthorized',
      'Forbidden',
      'Method Not Allowed',
      'Not Acceptable',
      'Request Timeout',
      'Conflict',
      'Gone',
      'Length Required',
      'Precondition Failed',
      'Request Entity Too Large',
      'Request-URI Too Long',
      'Unsupported Media Type',
      'Requested Range Not Satisfiable',
      'Expectation Failed',
      'I\'m a teapot',
      'Misdirected Request',
      'Unprocessable Entity',
      'Locked',
      'Failed Dependency',
      'Too Early',
      'Upgrade Required',
      'Precondition Required',
      'Too Many Requests',
      'Request Header Fields Too Large',
      'Unavailable For Legal Reasons',
      'Internal Server Error',
      'Not Implemented',
      'Bad Gateway',
      'Service Unavailable',
      'Gateway Timeout',
      'HTTP Version Not Supported',
      'Variant Also Negotiates',
      'Insufficient Storage',
      'Loop Detected',
      'Not Extended',
      'Network Authentication Required'
    ];
    
    final lowerBody = body.toLowerCase();
    return htmlIndicators.any((indicator) => lowerBody.contains(indicator.toLowerCase()));
  }
  
  /// Extract meaningful error message from HTML response
  static String extractErrorMessage(String htmlBody, int statusCode) {
    if (htmlBody.isEmpty) {
      return _getDefaultErrorMessage(statusCode);
    }
    
    // Try to extract error message from HTML
    try {
      // Look for common error message patterns in HTML
      final patterns = [
        RegExp(r'<title[^>]*>(.*?)</title>', caseSensitive: false),
        RegExp(r'<h1[^>]*>(.*?)</h1>', caseSensitive: false),
        RegExp(r'<h2[^>]*>(.*?)</h2>', caseSensitive: false),
        RegExp(r'<p[^>]*>(.*?)</p>', caseSensitive: false),
        RegExp(r'<div[^>]*class="[^"]*error[^"]*"[^>]*>(.*?)</div>', caseSensitive: false),
        RegExp(r'<span[^>]*class="[^"]*error[^"]*"[^>]*>(.*?)</span>', caseSensitive: false),
      ];
      
      for (final pattern in patterns) {
        final match = pattern.firstMatch(htmlBody);
        if (match != null) {
          final extracted = match.group(1)?.trim();
          if (extracted != null && extracted.isNotEmpty && extracted.length < 200) {
            // Clean up HTML entities and tags
            return _cleanHtmlText(extracted);
          }
        }
      }
      
      // If no specific error found, return generic message
      return _getDefaultErrorMessage(statusCode);
    } catch (e) {
      return _getDefaultErrorMessage(statusCode);
    }
  }
  
  /// Clean HTML text by removing tags and entities
  static String _cleanHtmlText(String text) {
    return text
        .replaceAll(RegExp(r'<[^>]*>'), '') // Remove HTML tags
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&amp;', '&')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&nbsp;', ' ')
        .trim();
  }
  
  /// Get default error message based on status code
  static String _getDefaultErrorMessage(int statusCode) {
    switch (statusCode) {
      case 400:
        return 'Bad Request - Please check your input';
      case 401:
        return 'Unauthorized - Please sign in again';
      case 403:
        return 'Forbidden - Access denied';
      case 404:
        return 'Not Found - The requested resource was not found';
      case 405:
        return 'Method Not Allowed';
      case 408:
        return 'Request Timeout - Please try again';
      case 409:
        return 'Conflict - Resource already exists';
      case 422:
        return 'Invalid Input - Please check your data';
      case 429:
        return 'Too Many Requests - Please wait and try again';
      case 500:
        return 'Internal Server Error - Please try again later';
      case 502:
        return 'Bad Gateway - Server is temporarily unavailable';
      case 503:
        return 'Service Unavailable - Please try again later';
      case 504:
        return 'Gateway Timeout - Please try again';
      default:
        if (statusCode >= 400 && statusCode < 500) {
          return 'Client Error - Please check your request';
        } else if (statusCode >= 500) {
          return 'Server Error - Please try again later';
        } else {
          return 'Unknown Error - Please try again';
        }
    }
  }
  
  /// Handle API response and extract proper error message
  static String handleApiResponse(String body, int statusCode) {
    // If it's a successful response, return empty string
    if (statusCode >= 200 && statusCode < 300) {
      return '';
    }
    
    // Check if response is HTML error page
    if (isHtmlError(body)) {
      return extractErrorMessage(body, statusCode);
    }
    
    // Try to parse as JSON for structured error
    try {
      final jsonData = jsonDecode(body);
      if (jsonData is Map<String, dynamic>) {
        // Look for common error fields
        final errorFields = ['error', 'message', 'detail', 'description', 'reason'];
        for (final field in errorFields) {
          if (jsonData.containsKey(field)) {
            final errorMsg = jsonData[field];
            if (errorMsg is String && errorMsg.isNotEmpty) {
              return errorMsg;
            }
          }
        }
      }
    } catch (e) {
      // If JSON parsing fails, treat as plain text
      if (body.isNotEmpty && body.length < 200) {
        return body.trim();
      }
    }
    
    // Fallback to status code message
    return _getDefaultErrorMessage(statusCode);
  }
  
  /// Show user-friendly error message
  static void showErrorSnackBar(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 4),
        action: SnackBarAction(
          label: 'Dismiss',
          textColor: Colors.white,
          onPressed: () {
            ScaffoldMessenger.of(context).hideCurrentSnackBar();
          },
        ),
      ),
    );
  }
  
  /// Show success message
  static void showSuccessSnackBar(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 2),
      ),
    );
  }
  
  /// Show info message
  static void showInfoSnackBar(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.blue,
        duration: const Duration(seconds: 3),
      ),
    );
  }
}
