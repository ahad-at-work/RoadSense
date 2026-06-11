/**
 * Google Apps Script endpoint for SmartRoadSense trip logging.
 *
 * Setup:
 * 1) Create a Google Sheet and copy its ID from URL.
 * 2) Open Extensions > Apps Script, paste this file.
 * 3) Set SHEET_ID and optionally API_KEY.
 * 4) Deploy as Web App (Execute as: Me, Access: Anyone with link).
 * 5) Use the deployment URL as the app API endpoint.
 */

const SHEET_ID = '1Omg2fiLwT7J7aXqmq0qW440SFSrKYTme63w1R0Blvg0';
const SHEET_NAME = 'trip_points';
const API_KEY = ''; // Optional: set and validate X-API-Key header.

function doGet() {
  return _jsonResponse({ ok: true, service: 'trip-logger', ts: new Date().toISOString() });
}

function doPost(e) {
  try {
    if (API_KEY) {
      const apiKey = _header(e, 'x-api-key');
      if (apiKey !== API_KEY) {
        return _jsonResponse({ ok: false, error: 'Unauthorized' });
      }
    }

    if (!e || !e.postData || !e.postData.contents) {
      return _jsonResponse({ ok: false, error: 'Missing body' });
    }

    const payload = JSON.parse(e.postData.contents);
    if (payload.dataType && payload.dataType !== 'trip_gps') {
      // Allow other app payloads to hit same endpoint without failing hard.
      return _jsonResponse({ ok: true, skipped: true, reason: 'Unsupported dataType' });
    }

    const validation = _validateTripPayload(payload);
    if (!validation.ok) {
      return _jsonResponse({ ok: false, error: validation.error });
    }

    const sheet = _getOrCreateSheet();
    _ensureHeader(sheet);

    sheet.appendRow([
      payload.trip_id,
      payload.timestamp_utc,
      payload.latitude,
      payload.longitude,
      payload.speed_mps,
      payload.bearing_deg,
      payload.accuracy_m,
      payload.altitude_m,
      payload.route_type,
      payload.device || '',
      new Date().toISOString(),
    ]);

    return _jsonResponse({ ok: true });
  } catch (err) {
    return _jsonResponse({ ok: false, error: String(err) });
  }
}

function _validateTripPayload(payload) {
  const required = [
    'trip_id',
    'timestamp_utc',
    'latitude',
    'longitude',
    'speed_mps',
    'bearing_deg',
    'accuracy_m',
    'altitude_m',
    'route_type',
  ];

  for (const key of required) {
    if (!(key in payload)) {
      return { ok: false, error: `Missing field: ${key}` };
    }
  }

  if (typeof payload.latitude !== 'number' || payload.latitude < -90 || payload.latitude > 90) {
    return { ok: false, error: 'Invalid latitude' };
  }
  if (typeof payload.longitude !== 'number' || payload.longitude < -180 || payload.longitude > 180) {
    return { ok: false, error: 'Invalid longitude' };
  }

  return { ok: true };
}

function _getOrCreateSheet() {
  const spreadsheet = SpreadsheetApp.openById(SHEET_ID);
  let sheet = spreadsheet.getSheetByName(SHEET_NAME);
  if (!sheet) {
    sheet = spreadsheet.insertSheet(SHEET_NAME);
  }
  return sheet;
}

function _ensureHeader(sheet) {
  if (sheet.getLastRow() > 0) {
    return;
  }

  sheet.appendRow([
    'trip_id',
    'timestamp_utc',
    'latitude',
    'longitude',
    'speed_mps',
    'bearing_deg',
    'accuracy_m',
    'altitude_m',
    'route_type',
    'device',
    'received_at_utc',
  ]);
}

function _header(e, headerName) {
  const headers = (e && e.parameter) || {};
  const target = String(headerName || '').toLowerCase();
  for (const key in headers) {
    if (String(key).toLowerCase() === target) {
      return headers[key];
    }
  }
  return '';
}

function _jsonResponse(payload) {
  return ContentService.createTextOutput(JSON.stringify(payload)).setMimeType(ContentService.MimeType.JSON);
}
