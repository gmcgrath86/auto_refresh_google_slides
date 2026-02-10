/**
 * Outbound-only trigger relay for dual-machine Slides automation.
 *
 * Deployment target: Google Apps Script Web App.
 * Access level: Anyone with the URL.
 * Security gate: shared secret.
 */

const RELAY_SECRET_KEY = 'RELAY_SECRET';
const LATEST_EVENT_KEY = 'LATEST_EVENT';

function doGet(e) {
  const secret = getSecretFromRequest(e, null);
  if (!isAuthorized(secret)) {
    return jsonOut({ ok: false, error: 'unauthorized' });
  }

  const state = readLatestEvent();
  return jsonOut({ ok: true, ...state });
}

function doPost(e) {
  const requestBody = parseBody(e);
  const secret = getSecretFromRequest(e, requestBody);

  if (!isAuthorized(secret)) {
    return jsonOut({ ok: false, error: 'unauthorized' });
  }

  const event = {
    eventId: requestBody.eventId || Utilities.getUuid(),
    action: requestBody.action || 'refresh_slides',
    source: requestBody.source || 'unknown',
    triggeredAt: new Date().toISOString(),
  };

  writeLatestEvent(event);
  return jsonOut({ ok: true, ...event });
}

function setupRelay(secret) {
  if (!secret) {
    throw new Error('Provide a secret string.');
  }

  const props = PropertiesService.getScriptProperties();
  props.setProperty(RELAY_SECRET_KEY, secret);

  const initialEvent = {
    eventId: '',
    action: '',
    source: 'setup',
    triggeredAt: new Date().toISOString(),
  };

  props.setProperty(LATEST_EVENT_KEY, JSON.stringify(initialEvent));
}

function readLatestEvent() {
  const raw = PropertiesService.getScriptProperties().getProperty(LATEST_EVENT_KEY);
  if (!raw) {
    return {
      eventId: '',
      action: '',
      source: 'empty',
      triggeredAt: new Date().toISOString(),
    };
  }

  try {
    const parsed = JSON.parse(raw);
    return {
      eventId: parsed.eventId || '',
      action: parsed.action || '',
      source: parsed.source || 'unknown',
      triggeredAt: parsed.triggeredAt || new Date().toISOString(),
    };
  } catch (error) {
    return {
      eventId: '',
      action: '',
      source: 'parse_error',
      triggeredAt: new Date().toISOString(),
    };
  }
}

function writeLatestEvent(event) {
  PropertiesService.getScriptProperties().setProperty(LATEST_EVENT_KEY, JSON.stringify(event));
}

function parseBody(e) {
  if (!e || !e.postData || !e.postData.contents) {
    return {};
  }

  try {
    return JSON.parse(e.postData.contents);
  } catch (error) {
    return {};
  }
}

function getSecretFromRequest(e, requestBody) {
  if (requestBody && requestBody.secret) {
    return requestBody.secret;
  }

  if (e && e.parameter && e.parameter.secret) {
    return e.parameter.secret;
  }

  return '';
}

function isAuthorized(secret) {
  const expected = PropertiesService.getScriptProperties().getProperty(RELAY_SECRET_KEY);
  return Boolean(expected) && secret === expected;
}

function jsonOut(data) {
  return ContentService
    .createTextOutput(JSON.stringify(data))
    .setMimeType(ContentService.MimeType.JSON);
}
