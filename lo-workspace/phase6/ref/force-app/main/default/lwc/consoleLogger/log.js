/**
 * Pulse Console Logger — styled console logger for LWC components.
 * Displays a two-tone badge: purple component name + level-colored message.
 *
 * LWS (Lightning Web Security) wraps objects in BoundaryProxyHandler proxies.
 * %O displays enumerable properties through the proxy — works for plain objects and arrays.
 * Native Error objects are the exception: .message/.stack are non-enumerable, so %O shows {}.
 * normalizeError() extracts Error properties into a plain object for those cases.
 *
 * @example
 * import { plog } from 'c/consoleLogger';
 *
 * // Simple message
 * plog.info('ConditionsViewer', 'Cache cleared');
 *
 * // Message with data
 * plog.info('ConditionsViewer', { message: 'Loaded', data: records });
 *
 * // Error with context
 * plog.error('ConditionsViewer', { message: 'Failed to load', error: e });
 *
 * // Both data and error
 * plog.error('ConditionsViewer', { message: 'Request failed', data: response, error: e });
 */
const COMPONENT_BADGE = 'background:#5f43b2;color:#fff;padding:2px 6px;border-radius:3px;font-weight:bold';
const COMPONENT_BADGE_LEFT = 'background:#5f43b2;color:#fff;padding:2px 6px;border-radius:3px 0 0 3px;font-weight:bold';

const LEVELS = {
  error: {
    label: 'background:#fce4e4;color:#c23934;padding:2px 6px;border-radius:0 3px 3px 0;font-weight:normal',
    method: 'error'
  },
  warn: {
    label: 'background:#fff3e0;color:#fe9339;padding:2px 6px;border-radius:0 3px 3px 0;font-weight:normal',
    method: 'warn'
  },
  info: {
    label: 'background:#e1f0fd;color:#0176d3;padding:2px 6px;border-radius:0 3px 3px 0;font-weight:normal',
    method: 'log'
  }
};


/**
 * Builder that accumulates styled console.log format segments.
 * Each method returns `this` for chaining; call {@link LogEntry#print} to flush.
 */
class LogEntry {
  /**
   * @param {'error'|'warn'|'info'} level - Log severity level
   */
  constructor(level) {
    this.level = LEVELS[level];
    this.componentName = '';
    this.formats = [];
    this.args = [];
    this.hasLabel = false;
  }

  /**
   * Sets the component name shown in the purple badge.
   * @param {string} name - Component name (e.g. 'CaseDetail')
   * @returns {LogEntry}
   */
  component(name) {
    this.componentName = name;
    return this;
  }

  /**
   * Adds a text message in the level-colored badge.
   * @param {string} text - Human-readable message
   * @returns {LogEntry}
   */
  message(text) {
    if (!text) {
      return this;
    }
    this.hasLabel = true;
    this.formats.push('%c %s ');
    this.args.push(this.level.label, text);
    return this;
  }

  /**
   * Appends an arbitrary data payload (%O formatted).
   * @param {*} value - Any serializable value (object, array, primitive)
   * @returns {LogEntry}
   */
  data(value) {
    return this._appendObject(value);
  }

  /**
   * Appends an error payload (%O formatted).
   * @param {Error|Object} value - Error or plain object with error details
   * @returns {LogEntry}
   */
  error(value) {
    return this._appendObject(value);
  }

  /** Flushes the accumulated segments to the browser console. */
  print() {
    const badge = this.hasLabel ? COMPONENT_BADGE_LEFT : COMPONENT_BADGE;
    const format = '%c %s ' + this.formats.join('');
    console[this.level.method](format, badge, this.componentName, ...this.args);
  }

  /**
   * @private Appends a %O-formatted object segment.
   * @param {*} value
   * @returns {LogEntry}
   */
  _appendObject(value) {
    if (value === undefined) {
      return this;
    }
    this._ensureLabel();
    this.formats.push('%c %O');
    this.args.push('', value);
    return this;
  }

  /** @private Inserts an empty level badge when data/error is added without a message. */
  _ensureLabel() {
    if (!this.hasLabel) {
      this.hasLabel = true;
      this.formats.push('%c ');
      this.args.push(this.level.label);
    }
  }
}

/**
 * Internal dispatcher — builds a {@link LogEntry}, applies options, and prints.
 * @param {'error'|'warn'|'info'} level - Severity
 * @param {string} component - Component name for the badge
 * @param {string|{message?: string, data?: *, error?: Error|Object}} [options] - Log payload
 */
function log(level, component, options) {
  const entry = new LogEntry(level).component(component);

  if (options === undefined) {
    entry.print();
    return;
  }

  if (typeof options === 'string') {
    entry.message(options).print();
    return;
  }

  entry.message(options.message).data(options.data).error(options.error).print();
}

/**
 * Pulse styled console logger.
 * @namespace plog
 */
export const plog = {
  /**
   * Logs at **error** level (red badge, `console.error`).
   * @param {string} component - Component name
   * @param {string|{message?: string, data?: *, error?: Error|Object}} [options] - Log payload
   */
  error(component, options) {
    log('error', component, options);
  },
  /**
   * Logs at **warn** level (orange badge, `console.warn`).
   * @param {string} component - Component name
   * @param {string|{message?: string, data?: *, error?: Error|Object}} [options] - Log payload
   */
  warn(component, options) {
    log('warn', component, options);
  },
  /**
   * Logs at **info** level (blue badge, `console.log`).
   * @param {string} component - Component name
   * @param {string|{message?: string, data?: *, error?: Error|Object}} [options] - Log payload
   */
  info(component, options) {
    log('info', component, options);
  }
};