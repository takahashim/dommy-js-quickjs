(() => {
  var __defProp = Object.defineProperty;
  var __defProps = Object.defineProperties;
  var __getOwnPropDescs = Object.getOwnPropertyDescriptors;
  var __getOwnPropSymbols = Object.getOwnPropertySymbols;
  var __hasOwnProp = Object.prototype.hasOwnProperty;
  var __propIsEnum = Object.prototype.propertyIsEnumerable;
  var __typeError = (msg) => {
    throw TypeError(msg);
  };
  var __defNormalProp = (obj, key, value) => key in obj ? __defProp(obj, key, { enumerable: true, configurable: true, writable: true, value }) : obj[key] = value;
  var __spreadValues = (a, b) => {
    for (var prop in b || (b = {}))
      if (__hasOwnProp.call(b, prop))
        __defNormalProp(a, prop, b[prop]);
    if (__getOwnPropSymbols)
      for (var prop of __getOwnPropSymbols(b)) {
        if (__propIsEnum.call(b, prop))
          __defNormalProp(a, prop, b[prop]);
      }
    return a;
  };
  var __spreadProps = (a, b) => __defProps(a, __getOwnPropDescs(b));
  var __objRest = (source, exclude) => {
    var target = {};
    for (var prop in source)
      if (__hasOwnProp.call(source, prop) && exclude.indexOf(prop) < 0)
        target[prop] = source[prop];
    if (source != null && __getOwnPropSymbols)
      for (var prop of __getOwnPropSymbols(source)) {
        if (exclude.indexOf(prop) < 0 && __propIsEnum.call(source, prop))
          target[prop] = source[prop];
      }
    return target;
  };
  var __export = (target, all) => {
    for (var name in all)
      __defProp(target, name, { get: all[name], enumerable: true });
  };
  var __publicField = (obj, key, value) => __defNormalProp(obj, typeof key !== "symbol" ? key + "" : key, value);
  var __accessCheck = (obj, member, msg) => member.has(obj) || __typeError("Cannot " + msg);
  var __privateGet = (obj, member, getter) => (__accessCheck(obj, member, "read from private field"), getter ? getter.call(obj) : member.get(obj));
  var __privateAdd = (obj, member, value) => member.has(obj) ? __typeError("Cannot add the same private member more than once") : member instanceof WeakSet ? member.add(obj) : member.set(obj, value);
  var __privateSet = (obj, member, value, setter) => (__accessCheck(obj, member, "write to private field"), setter ? setter.call(obj, value) : member.set(obj, value), value);
  var __privateMethod = (obj, member, method) => (__accessCheck(obj, member, "access private method"), method);

  // src/index.js
  var src_exports = {};
  __export(src_exports, {
    FetchEnctype: () => FetchEnctype,
    FetchMethod: () => FetchMethod,
    FetchRequest: () => FetchRequest,
    FetchResponse: () => FetchResponse,
    FrameElement: () => FrameElement,
    FrameLoadingStyle: () => FrameLoadingStyle,
    FrameRenderer: () => FrameRenderer,
    PageRenderer: () => PageRenderer,
    PageSnapshot: () => PageSnapshot,
    StreamActions: () => StreamActions,
    StreamElement: () => StreamElement,
    StreamSourceElement: () => StreamSourceElement,
    cache: () => cache,
    config: () => config,
    connectStreamSource: () => connectStreamSource,
    disconnectStreamSource: () => disconnectStreamSource,
    fetch: () => fetchWithTurboHeaders,
    fetchEnctypeFromString: () => fetchEnctypeFromString,
    fetchMethodFromString: () => fetchMethodFromString,
    isSafe: () => isSafe,
    morphBodyElements: () => morphBodyElements,
    morphChildren: () => morphChildren,
    morphElements: () => morphElements,
    morphTurboFrameElements: () => morphTurboFrameElements,
    navigator: () => sessionNavigator,
    registerAdapter: () => registerAdapter,
    renderStreamMessage: () => renderStreamMessage,
    session: () => session,
    setConfirmMethod: () => setConfirmMethod,
    setFormMode: () => setFormMode,
    setProgressBarDelay: () => setProgressBarDelay,
    start: () => start,
    visit: () => visit
  });

  // src/elements/frame_element.js
  var FrameLoadingStyle = {
    eager: "eager",
    lazy: "lazy"
  };
  var _FrameElement = class _FrameElement extends HTMLElement {
    constructor() {
      super();
      __publicField(this, "loaded", Promise.resolve());
      this.delegate = new _FrameElement.delegateConstructor(this);
    }
    static get observedAttributes() {
      return ["disabled", "loading", "src"];
    }
    connectedCallback() {
      this.delegate.connect();
    }
    disconnectedCallback() {
      this.delegate.disconnect();
    }
    reload() {
      return this.delegate.sourceURLReloaded();
    }
    attributeChangedCallback(name) {
      if (name == "loading") {
        this.delegate.loadingStyleChanged();
      } else if (name == "src") {
        this.delegate.sourceURLChanged();
      } else if (name == "disabled") {
        this.delegate.disabledChanged();
      }
    }
    /**
     * Gets the URL to lazily load source HTML from
     */
    get src() {
      return this.getAttribute("src");
    }
    /**
     * Sets the URL to lazily load source HTML from
     */
    set src(value) {
      if (value) {
        this.setAttribute("src", value);
      } else {
        this.removeAttribute("src");
      }
    }
    /**
     * Gets the refresh mode for the frame.
     */
    get refresh() {
      return this.getAttribute("refresh");
    }
    /**
     * Sets the refresh mode for the frame.
     */
    set refresh(value) {
      if (value) {
        this.setAttribute("refresh", value);
      } else {
        this.removeAttribute("refresh");
      }
    }
    get shouldReloadWithMorph() {
      return this.src && this.refresh === "morph";
    }
    /**
     * Determines if the element is loading
     */
    get loading() {
      return frameLoadingStyleFromString(this.getAttribute("loading") || "");
    }
    /**
     * Sets the value of if the element is loading
     */
    set loading(value) {
      if (value) {
        this.setAttribute("loading", value);
      } else {
        this.removeAttribute("loading");
      }
    }
    /**
     * Gets the disabled state of the frame.
     *
     * If disabled, no requests will be intercepted by the frame.
     */
    get disabled() {
      return this.hasAttribute("disabled");
    }
    /**
     * Sets the disabled state of the frame.
     *
     * If disabled, no requests will be intercepted by the frame.
     */
    set disabled(value) {
      if (value) {
        this.setAttribute("disabled", "");
      } else {
        this.removeAttribute("disabled");
      }
    }
    /**
     * Gets the autoscroll state of the frame.
     *
     * If true, the frame will be scrolled into view automatically on update.
     */
    get autoscroll() {
      return this.hasAttribute("autoscroll");
    }
    /**
     * Sets the autoscroll state of the frame.
     *
     * If true, the frame will be scrolled into view automatically on update.
     */
    set autoscroll(value) {
      if (value) {
        this.setAttribute("autoscroll", "");
      } else {
        this.removeAttribute("autoscroll");
      }
    }
    /**
     * Determines if the element has finished loading
     */
    get complete() {
      return !this.delegate.isLoading;
    }
    /**
     * Gets the active state of the frame.
     *
     * If inactive, source changes will not be observed.
     */
    get isActive() {
      return this.ownerDocument === document && !this.isPreview;
    }
    /**
     * Sets the active state of the frame.
     *
     * If inactive, source changes will not be observed.
     */
    get isPreview() {
      var _a, _b;
      return (_b = (_a = this.ownerDocument) == null ? void 0 : _a.documentElement) == null ? void 0 : _b.hasAttribute("data-turbo-preview");
    }
  };
  __publicField(_FrameElement, "delegateConstructor");
  var FrameElement = _FrameElement;
  function frameLoadingStyleFromString(style) {
    switch (style.toLowerCase()) {
      case "lazy":
        return FrameLoadingStyle.lazy;
      default:
        return FrameLoadingStyle.eager;
    }
  }

  // src/core/config/drive.js
  var drive = {
    enabled: true,
    progressBarDelay: 500,
    unvisitableExtensions: /* @__PURE__ */ new Set(
      [
        ".7z",
        ".aac",
        ".apk",
        ".avi",
        ".bmp",
        ".bz2",
        ".css",
        ".csv",
        ".deb",
        ".dmg",
        ".doc",
        ".docx",
        ".exe",
        ".gif",
        ".gz",
        ".heic",
        ".heif",
        ".ico",
        ".iso",
        ".jpeg",
        ".jpg",
        ".js",
        ".json",
        ".m4a",
        ".mkv",
        ".mov",
        ".mp3",
        ".mp4",
        ".mpeg",
        ".mpg",
        ".msi",
        ".ogg",
        ".ogv",
        ".pdf",
        ".pkg",
        ".png",
        ".ppt",
        ".pptx",
        ".rar",
        ".rtf",
        ".svg",
        ".tar",
        ".tif",
        ".tiff",
        ".txt",
        ".wav",
        ".webm",
        ".webp",
        ".wma",
        ".wmv",
        ".xls",
        ".xlsx",
        ".xml",
        ".zip"
      ]
    )
  };

  // src/util.js
  function activateScriptElement(element) {
    if (element.getAttribute("data-turbo-eval") == "false") {
      return element;
    } else {
      const createdScriptElement = document.createElement("script");
      const cspNonce = getCspNonce();
      if (cspNonce) {
        createdScriptElement.nonce = cspNonce;
      }
      createdScriptElement.textContent = element.textContent;
      createdScriptElement.async = false;
      copyElementAttributes(createdScriptElement, element);
      return createdScriptElement;
    }
  }
  function copyElementAttributes(destinationElement, sourceElement) {
    for (const { name, value } of sourceElement.attributes) {
      destinationElement.setAttribute(name, value);
    }
  }
  function createDocumentFragment(html) {
    const template = document.createElement("template");
    template.innerHTML = html;
    return template.content;
  }
  function dispatch(eventName, { target, cancelable, detail } = {}) {
    const event = new CustomEvent(eventName, {
      cancelable,
      bubbles: true,
      composed: true,
      detail
    });
    if (target && target.isConnected) {
      target.dispatchEvent(event);
    } else {
      document.documentElement.dispatchEvent(event);
    }
    return event;
  }
  function cancelEvent(event) {
    event.preventDefault();
    event.stopImmediatePropagation();
  }
  function nextRepaint() {
    if (document.visibilityState === "hidden") {
      return nextEventLoopTick();
    } else {
      return nextAnimationFrame();
    }
  }
  function nextAnimationFrame() {
    return new Promise((resolve) => requestAnimationFrame(() => resolve()));
  }
  function nextEventLoopTick() {
    return new Promise((resolve) => setTimeout(() => resolve(), 0));
  }
  function parseHTMLDocument(html = "") {
    return new DOMParser().parseFromString(html, "text/html");
  }
  function unindent(strings, ...values) {
    const lines = interpolate(strings, values).replace(/^\n/, "").split("\n");
    const match = lines[0].match(/^\s+/);
    const indent = match ? match[0].length : 0;
    return lines.map((line) => line.slice(indent)).join("\n");
  }
  function interpolate(strings, values) {
    return strings.reduce((result, string, i) => {
      const value = values[i] == void 0 ? "" : values[i];
      return result + string + value;
    }, "");
  }
  function uuid() {
    return Array.from({ length: 36 }).map((_, i) => {
      if (i == 8 || i == 13 || i == 18 || i == 23) {
        return "-";
      } else if (i == 14) {
        return "4";
      } else if (i == 19) {
        return (Math.floor(Math.random() * 4) + 8).toString(16);
      } else {
        return Math.floor(Math.random() * 16).toString(16);
      }
    }).join("");
  }
  function getAttribute(attributeName, ...elements) {
    for (const value of elements.map((element) => element == null ? void 0 : element.getAttribute(attributeName))) {
      if (typeof value == "string") return value;
    }
    return null;
  }
  function hasAttribute(attributeName, ...elements) {
    return elements.some((element) => element && element.hasAttribute(attributeName));
  }
  function markAsBusy(...elements) {
    for (const element of elements) {
      if (element.localName == "turbo-frame") {
        element.setAttribute("busy", "");
      }
      element.setAttribute("aria-busy", "true");
    }
  }
  function clearBusyState(...elements) {
    for (const element of elements) {
      if (element.localName == "turbo-frame") {
        element.removeAttribute("busy");
      }
      element.removeAttribute("aria-busy");
    }
  }
  function waitForLoad(element, timeoutInMilliseconds = 2e3) {
    return new Promise((resolve) => {
      const onComplete = () => {
        element.removeEventListener("error", onComplete);
        element.removeEventListener("load", onComplete);
        resolve();
      };
      element.addEventListener("load", onComplete, { once: true });
      element.addEventListener("error", onComplete, { once: true });
      setTimeout(resolve, timeoutInMilliseconds);
    });
  }
  function getHistoryMethodForAction(action) {
    switch (action) {
      case "replace":
        return history.replaceState;
      case "advance":
      case "restore":
        return history.pushState;
    }
  }
  function isAction(action) {
    return action == "advance" || action == "replace" || action == "restore";
  }
  function getVisitAction(...elements) {
    const action = getAttribute("data-turbo-action", ...elements);
    return isAction(action) ? action : null;
  }
  function getMetaElement(name) {
    return document.querySelector(`meta[name="${name}"]`);
  }
  function getMetaContent(name) {
    const element = getMetaElement(name);
    return element && element.content;
  }
  function getCspNonce() {
    const element = getMetaElement("csp-nonce");
    if (element) {
      const { nonce, content } = element;
      return nonce == "" ? content : nonce;
    }
  }
  function setMetaContent(name, content) {
    let element = getMetaElement(name);
    if (!element) {
      element = document.createElement("meta");
      element.setAttribute("name", name);
      document.head.appendChild(element);
    }
    element.setAttribute("content", content);
    return element;
  }
  function findClosestRecursively(element, selector) {
    var _a;
    if (element instanceof Element) {
      return element.closest(selector) || findClosestRecursively(element.assignedSlot || ((_a = element.getRootNode()) == null ? void 0 : _a.host), selector);
    }
  }
  function elementIsFocusable(element) {
    const inertDisabledOrHidden = "[inert], :disabled, [hidden], details:not([open]), dialog:not([open])";
    return !!element && element.closest(inertDisabledOrHidden) == null && typeof element.focus == "function";
  }
  function queryAutofocusableElement(elementOrDocumentFragment) {
    return Array.from(elementOrDocumentFragment.querySelectorAll("[autofocus]")).find(elementIsFocusable);
  }
  async function around(callback, reader) {
    const before = reader();
    callback();
    await nextAnimationFrame();
    const after = reader();
    return [before, after];
  }
  function doesNotTargetIFrame(name) {
    if (name === "_blank") {
      return false;
    } else if (name) {
      for (const element of document.getElementsByName(name)) {
        if (element instanceof HTMLIFrameElement) return false;
      }
      return true;
    } else {
      return true;
    }
  }
  function findLinkFromClickTarget(target) {
    const link = findClosestRecursively(target, "a[href], a[xlink\\:href]");
    if (!link) return null;
    if (link.href.startsWith("#")) return null;
    if (link.hasAttribute("download")) return null;
    const linkTarget = link.getAttribute("target");
    if (linkTarget && linkTarget !== "_self") return null;
    return link;
  }
  function debounce(fn, delay) {
    let timeoutId = null;
    return (...args) => {
      const callback = () => fn.apply(this, args);
      clearTimeout(timeoutId);
      timeoutId = setTimeout(callback, delay);
    };
  }

  // src/core/config/forms.js
  var submitter = {
    "aria-disabled": {
      beforeSubmit: (submitter2) => {
        submitter2.setAttribute("aria-disabled", "true");
        submitter2.addEventListener("click", cancelEvent);
      },
      afterSubmit: (submitter2) => {
        submitter2.removeAttribute("aria-disabled");
        submitter2.removeEventListener("click", cancelEvent);
      }
    },
    "disabled": {
      beforeSubmit: (submitter2) => submitter2.disabled = true,
      afterSubmit: (submitter2) => submitter2.disabled = false
    }
  };
  var _submitter;
  var Config = class {
    constructor(config2) {
      __privateAdd(this, _submitter, null);
      Object.assign(this, config2);
    }
    get submitter() {
      return __privateGet(this, _submitter);
    }
    set submitter(value) {
      __privateSet(this, _submitter, submitter[value] || value);
    }
  };
  _submitter = new WeakMap();
  var forms = new Config({
    mode: "on",
    submitter: "disabled"
  });

  // src/core/config/index.js
  var config = {
    drive,
    forms
  };

  // src/core/url.js
  function expandURL(locatable) {
    return new URL(locatable.toString(), document.baseURI);
  }
  function getAnchor(url) {
    let anchorMatch;
    if (url.hash) {
      return url.hash.slice(1);
    } else if (anchorMatch = url.href.match(/#(.*)$/)) {
      return anchorMatch[1];
    }
  }
  function getAction(form, submitter2) {
    const action = (submitter2 == null ? void 0 : submitter2.getAttribute("formaction")) || form.getAttribute("action") || form.action;
    return expandURL(action);
  }
  function getExtension(url) {
    return (getLastPathComponent(url).match(/\.[^.]*$/) || [])[0] || "";
  }
  function isPrefixedBy(baseURL, url) {
    const prefix = addTrailingSlash(url.origin + url.pathname);
    return addTrailingSlash(baseURL.href) === prefix || baseURL.href.startsWith(prefix);
  }
  function locationIsVisitable(location2, rootLocation) {
    return isPrefixedBy(location2, rootLocation) && !config.drive.unvisitableExtensions.has(getExtension(location2));
  }
  function getLocationForLink(link) {
    return expandURL(link.getAttribute("href") || "");
  }
  function getRequestURL(url) {
    const anchor = getAnchor(url);
    return anchor != null ? url.href.slice(0, -(anchor.length + 1)) : url.href;
  }
  function toCacheKey(url) {
    return getRequestURL(url);
  }
  function urlsAreEqual(left, right) {
    return expandURL(left).href == expandURL(right).href;
  }
  function getPathComponents(url) {
    return url.pathname.split("/").slice(1);
  }
  function getLastPathComponent(url) {
    return getPathComponents(url).slice(-1)[0];
  }
  function addTrailingSlash(value) {
    return value.endsWith("/") ? value : value + "/";
  }

  // src/http/fetch_response.js
  var FetchResponse = class {
    constructor(response) {
      this.response = response;
    }
    get succeeded() {
      return this.response.ok;
    }
    get failed() {
      return !this.succeeded;
    }
    get clientError() {
      return this.statusCode >= 400 && this.statusCode <= 499;
    }
    get serverError() {
      return this.statusCode >= 500 && this.statusCode <= 599;
    }
    get redirected() {
      return this.response.redirected;
    }
    get location() {
      return expandURL(this.response.url);
    }
    get isHTML() {
      return this.contentType && this.contentType.match(/^(?:text\/([^\s;,]+\b)?html|application\/xhtml\+xml)\b/);
    }
    get statusCode() {
      return this.response.status;
    }
    get contentType() {
      return this.header("Content-Type");
    }
    get responseText() {
      return this.response.clone().text();
    }
    get responseHTML() {
      if (this.isHTML) {
        return this.response.clone().text();
      } else {
        return Promise.resolve(void 0);
      }
    }
    header(name) {
      return this.response.headers.get(name);
    }
  };

  // src/core/drive/limited_set.js
  var LimitedSet = class extends Set {
    constructor(maxSize) {
      super();
      this.maxSize = maxSize;
    }
    add(value) {
      if (this.size >= this.maxSize) {
        const iterator = this.values();
        const oldestValue = iterator.next().value;
        this.delete(oldestValue);
      }
      super.add(value);
    }
  };

  // src/http/fetch.js
  var recentRequests = new LimitedSet(20);
  function fetchWithTurboHeaders(url, options = {}) {
    const modifiedHeaders = new Headers(options.headers || {});
    const requestUID = uuid();
    recentRequests.add(requestUID);
    modifiedHeaders.append("X-Turbo-Request-Id", requestUID);
    return window.fetch(url, __spreadProps(__spreadValues({}, options), {
      headers: modifiedHeaders
    }));
  }

  // src/http/fetch_request.js
  function fetchMethodFromString(method) {
    switch (method.toLowerCase()) {
      case "get":
        return FetchMethod.get;
      case "post":
        return FetchMethod.post;
      case "put":
        return FetchMethod.put;
      case "patch":
        return FetchMethod.patch;
      case "delete":
        return FetchMethod.delete;
    }
  }
  var FetchMethod = {
    get: "get",
    post: "post",
    put: "put",
    patch: "patch",
    delete: "delete"
  };
  function fetchEnctypeFromString(encoding) {
    switch (encoding.toLowerCase()) {
      case FetchEnctype.multipart:
        return FetchEnctype.multipart;
      case FetchEnctype.plain:
        return FetchEnctype.plain;
      default:
        return FetchEnctype.urlEncoded;
    }
  }
  var FetchEnctype = {
    urlEncoded: "application/x-www-form-urlencoded",
    multipart: "multipart/form-data",
    plain: "text/plain"
  };
  var _resolveRequestPromise, _FetchRequest_instances, allowRequestToBeIntercepted_fn, willDelegateErrorHandling_fn;
  var FetchRequest = class {
    constructor(delegate, method, location2, requestBody = new URLSearchParams(), target = null, enctype = FetchEnctype.urlEncoded) {
      __privateAdd(this, _FetchRequest_instances);
      __publicField(this, "abortController", new AbortController());
      __privateAdd(this, _resolveRequestPromise, (_value) => {
      });
      var _a;
      const [url, body] = buildResourceAndBody(expandURL(location2), method, requestBody, enctype);
      this.delegate = delegate;
      this.url = url;
      this.target = target;
      this.fetchOptions = {
        credentials: "same-origin",
        redirect: "follow",
        method: method.toUpperCase(),
        headers: __spreadValues({}, this.defaultHeaders),
        body,
        signal: this.abortSignal,
        referrer: (_a = this.delegate.referrer) == null ? void 0 : _a.href
      };
      this.enctype = enctype;
    }
    get method() {
      return this.fetchOptions.method;
    }
    set method(value) {
      const fetchBody = this.isSafe ? this.url.searchParams : this.fetchOptions.body || new FormData();
      const fetchMethod = fetchMethodFromString(value) || FetchMethod.get;
      this.url.search = "";
      const [url, body] = buildResourceAndBody(this.url, fetchMethod, fetchBody, this.enctype);
      this.url = url;
      this.fetchOptions.body = body;
      this.fetchOptions.method = fetchMethod.toUpperCase();
    }
    get headers() {
      return this.fetchOptions.headers;
    }
    set headers(value) {
      this.fetchOptions.headers = value;
    }
    get body() {
      if (this.isSafe) {
        return this.url.searchParams;
      } else {
        return this.fetchOptions.body;
      }
    }
    set body(value) {
      this.fetchOptions.body = value;
    }
    get location() {
      return this.url;
    }
    get params() {
      return this.url.searchParams;
    }
    get entries() {
      return this.body ? Array.from(this.body.entries()) : [];
    }
    cancel() {
      this.abortController.abort();
    }
    async perform() {
      const { fetchOptions } = this;
      this.delegate.prepareRequest(this);
      const event = await __privateMethod(this, _FetchRequest_instances, allowRequestToBeIntercepted_fn).call(this, fetchOptions);
      try {
        this.delegate.requestStarted(this);
        if (event.detail.fetchRequest) {
          this.response = event.detail.fetchRequest.response;
        } else {
          this.response = fetchWithTurboHeaders(this.url.href, fetchOptions);
        }
        const response = await this.response;
        return await this.receive(response);
      } catch (error) {
        if (error.name !== "AbortError") {
          if (__privateMethod(this, _FetchRequest_instances, willDelegateErrorHandling_fn).call(this, error)) {
            this.delegate.requestErrored(this, error);
          }
          throw error;
        }
      } finally {
        this.delegate.requestFinished(this);
      }
    }
    async receive(response) {
      const fetchResponse = new FetchResponse(response);
      const event = dispatch("turbo:before-fetch-response", {
        cancelable: true,
        detail: { fetchResponse },
        target: this.target
      });
      if (event.defaultPrevented) {
        this.delegate.requestPreventedHandlingResponse(this, fetchResponse);
      } else if (fetchResponse.succeeded) {
        this.delegate.requestSucceededWithResponse(this, fetchResponse);
      } else {
        this.delegate.requestFailedWithResponse(this, fetchResponse);
      }
      return fetchResponse;
    }
    get defaultHeaders() {
      return {
        Accept: "text/html, application/xhtml+xml"
      };
    }
    get isSafe() {
      return isSafe(this.method);
    }
    get abortSignal() {
      return this.abortController.signal;
    }
    acceptResponseType(mimeType) {
      this.headers["Accept"] = [mimeType, this.headers["Accept"]].join(", ");
    }
  };
  _resolveRequestPromise = new WeakMap();
  _FetchRequest_instances = new WeakSet();
  allowRequestToBeIntercepted_fn = async function(fetchOptions) {
    const requestInterception = new Promise((resolve) => __privateSet(this, _resolveRequestPromise, resolve));
    const event = dispatch("turbo:before-fetch-request", {
      cancelable: true,
      detail: {
        fetchOptions,
        url: this.url,
        resume: __privateGet(this, _resolveRequestPromise)
      },
      target: this.target
    });
    this.url = event.detail.url;
    if (event.defaultPrevented) await requestInterception;
    return event;
  };
  willDelegateErrorHandling_fn = function(error) {
    const event = dispatch("turbo:fetch-request-error", {
      target: this.target,
      cancelable: true,
      detail: { request: this, error }
    });
    return !event.defaultPrevented;
  };
  function isSafe(fetchMethod) {
    return fetchMethodFromString(fetchMethod) == FetchMethod.get;
  }
  function buildResourceAndBody(resource, method, requestBody, enctype) {
    const searchParams = Array.from(requestBody).length > 0 ? new URLSearchParams(entriesExcludingFiles(requestBody)) : resource.searchParams;
    if (isSafe(method)) {
      return [mergeIntoURLSearchParams(resource, searchParams), null];
    } else if (enctype == FetchEnctype.urlEncoded) {
      return [resource, searchParams];
    } else {
      return [resource, requestBody];
    }
  }
  function entriesExcludingFiles(requestBody) {
    const entries = [];
    for (const [name, value] of requestBody) {
      if (value instanceof File) continue;
      else entries.push([name, value]);
    }
    return entries;
  }
  function mergeIntoURLSearchParams(url, requestBody) {
    const searchParams = new URLSearchParams(entriesExcludingFiles(requestBody));
    url.search = searchParams.toString();
    return url;
  }

  // src/observers/appearance_observer.js
  var AppearanceObserver = class {
    constructor(delegate, element) {
      __publicField(this, "started", false);
      __publicField(this, "intersect", (entries) => {
        const lastEntry = entries.slice(-1)[0];
        if (lastEntry == null ? void 0 : lastEntry.isIntersecting) {
          this.delegate.elementAppearedInViewport(this.element);
        }
      });
      this.delegate = delegate;
      this.element = element;
      this.intersectionObserver = new IntersectionObserver(this.intersect);
    }
    start() {
      if (!this.started) {
        this.started = true;
        this.intersectionObserver.observe(this.element);
      }
    }
    stop() {
      if (this.started) {
        this.started = false;
        this.intersectionObserver.unobserve(this.element);
      }
    }
  };

  // src/core/streams/stream_message.js
  var StreamMessage = class {
    static wrap(message) {
      if (typeof message == "string") {
        return new this(createDocumentFragment(message));
      } else {
        return message;
      }
    }
    constructor(fragment) {
      this.fragment = importStreamElements(fragment);
    }
  };
  __publicField(StreamMessage, "contentType", "text/vnd.turbo-stream.html");
  function importStreamElements(fragment) {
    for (const element of fragment.querySelectorAll("turbo-stream")) {
      const streamElement = document.importNode(element, true);
      for (const inertScriptElement of streamElement.templateElement.content.querySelectorAll("script")) {
        inertScriptElement.replaceWith(activateScriptElement(inertScriptElement));
      }
      element.replaceWith(streamElement);
    }
    return fragment;
  }

  // src/core/lru_cache.js
  var identity = (key) => key;
  var _toCacheKey;
  var LRUCache = class {
    constructor(size, toCacheKey2 = identity) {
      __publicField(this, "keys", []);
      __publicField(this, "entries", {});
      __privateAdd(this, _toCacheKey);
      this.size = size;
      __privateSet(this, _toCacheKey, toCacheKey2);
    }
    has(key) {
      return __privateGet(this, _toCacheKey).call(this, key) in this.entries;
    }
    get(key) {
      if (this.has(key)) {
        const entry = this.read(key);
        this.touch(key);
        return entry;
      }
    }
    put(key, entry) {
      this.write(key, entry);
      this.touch(key);
      return entry;
    }
    clear() {
      for (const key of Object.keys(this.entries)) {
        this.evict(key);
      }
    }
    // Private
    read(key) {
      return this.entries[__privateGet(this, _toCacheKey).call(this, key)];
    }
    write(key, entry) {
      this.entries[__privateGet(this, _toCacheKey).call(this, key)] = entry;
    }
    touch(key) {
      key = __privateGet(this, _toCacheKey).call(this, key);
      const index = this.keys.indexOf(key);
      if (index > -1) this.keys.splice(index, 1);
      this.keys.unshift(key);
      this.trim();
    }
    trim() {
      for (const key of this.keys.splice(this.size)) {
        this.evict(key);
      }
    }
    evict(key) {
      delete this.entries[key];
    }
  };
  _toCacheKey = new WeakMap();

  // src/core/drive/prefetch_cache.js
  var PREFETCH_DELAY = 100;
  var _prefetchTimeout, _maxAges;
  var PrefetchCache = class extends LRUCache {
    constructor(size = 1, prefetchDelay = PREFETCH_DELAY) {
      super(size, toCacheKey);
      __privateAdd(this, _prefetchTimeout, null);
      __privateAdd(this, _maxAges, {});
      this.prefetchDelay = prefetchDelay;
    }
    putLater(url, request, ttl) {
      __privateSet(this, _prefetchTimeout, setTimeout(() => {
        request.perform();
        this.put(url, request, ttl);
        __privateSet(this, _prefetchTimeout, null);
      }, this.prefetchDelay));
    }
    put(url, request, ttl = cacheTtl) {
      super.put(url, request);
      __privateGet(this, _maxAges)[toCacheKey(url)] = new Date((/* @__PURE__ */ new Date()).getTime() + ttl);
    }
    clear() {
      super.clear();
      if (__privateGet(this, _prefetchTimeout)) clearTimeout(__privateGet(this, _prefetchTimeout));
    }
    evict(key) {
      super.evict(key);
      delete __privateGet(this, _maxAges)[key];
    }
    has(key) {
      if (super.has(key)) {
        const maxAge = __privateGet(this, _maxAges)[toCacheKey(key)];
        return maxAge && maxAge > Date.now();
      } else {
        return false;
      }
    }
  };
  _prefetchTimeout = new WeakMap();
  _maxAges = new WeakMap();
  var cacheTtl = 10 * 1e3;
  var prefetchCache = new PrefetchCache();

  // src/core/drive/form_submission.js
  var FormSubmissionState = {
    initialized: "initialized",
    requesting: "requesting",
    waiting: "waiting",
    receiving: "receiving",
    stopping: "stopping",
    stopped: "stopped"
  };
  var FormSubmission = class _FormSubmission {
    constructor(delegate, formElement, submitter2, mustRedirect = false) {
      __publicField(this, "state", FormSubmissionState.initialized);
      const method = getMethod(formElement, submitter2);
      const action = getAction2(getFormAction(formElement, submitter2), method);
      const body = buildFormData(formElement, submitter2);
      const enctype = getEnctype(formElement, submitter2);
      this.delegate = delegate;
      this.formElement = formElement;
      this.submitter = submitter2;
      this.fetchRequest = new FetchRequest(this, method, action, body, formElement, enctype);
      this.mustRedirect = mustRedirect;
    }
    static confirmMethod(message) {
      return Promise.resolve(confirm(message));
    }
    get method() {
      return this.fetchRequest.method;
    }
    set method(value) {
      this.fetchRequest.method = value;
    }
    get action() {
      return this.fetchRequest.url.toString();
    }
    set action(value) {
      this.fetchRequest.url = expandURL(value);
    }
    get body() {
      return this.fetchRequest.body;
    }
    get enctype() {
      return this.fetchRequest.enctype;
    }
    get isSafe() {
      return this.fetchRequest.isSafe;
    }
    get location() {
      return this.fetchRequest.url;
    }
    // The submission process
    async start() {
      const { initialized, requesting } = FormSubmissionState;
      const confirmationMessage = getAttribute("data-turbo-confirm", this.submitter, this.formElement);
      if (typeof confirmationMessage === "string") {
        const confirmMethod = typeof config.forms.confirm === "function" ? config.forms.confirm : _FormSubmission.confirmMethod;
        const answer = await confirmMethod(confirmationMessage, this.formElement, this.submitter);
        if (!answer) {
          return;
        }
      }
      if (this.state == initialized) {
        this.state = requesting;
        return this.fetchRequest.perform();
      }
    }
    stop() {
      const { stopping, stopped } = FormSubmissionState;
      if (this.state != stopping && this.state != stopped) {
        this.state = stopping;
        this.fetchRequest.cancel();
        return true;
      }
    }
    // Fetch request delegate
    prepareRequest(request) {
      if (!request.isSafe) {
        const token = getCookieValue(getMetaContent("csrf-param")) || getMetaContent("csrf-token");
        if (token) {
          request.headers["X-CSRF-Token"] = token;
        }
      }
      if (this.requestAcceptsTurboStreamResponse(request)) {
        request.acceptResponseType(StreamMessage.contentType);
      }
    }
    requestStarted(_request) {
      this.state = FormSubmissionState.waiting;
      if (this.submitter) config.forms.submitter.beforeSubmit(this.submitter);
      this.setSubmitsWith();
      markAsBusy(this.formElement);
      dispatch("turbo:submit-start", {
        target: this.formElement,
        detail: { formSubmission: this }
      });
      this.delegate.formSubmissionStarted(this);
    }
    requestPreventedHandlingResponse(request, response) {
      prefetchCache.clear();
      this.result = { success: response.succeeded, fetchResponse: response };
    }
    requestSucceededWithResponse(request, response) {
      if (response.clientError || response.serverError) {
        this.delegate.formSubmissionFailedWithResponse(this, response);
        return;
      }
      prefetchCache.clear();
      if (this.requestMustRedirect(request) && responseSucceededWithoutRedirect(response)) {
        const error = new Error("Form responses must redirect to another location");
        this.delegate.formSubmissionErrored(this, error);
      } else {
        this.state = FormSubmissionState.receiving;
        this.result = { success: true, fetchResponse: response };
        this.delegate.formSubmissionSucceededWithResponse(this, response);
      }
    }
    requestFailedWithResponse(request, response) {
      this.result = { success: false, fetchResponse: response };
      this.delegate.formSubmissionFailedWithResponse(this, response);
    }
    requestErrored(request, error) {
      this.result = { success: false, error };
      this.delegate.formSubmissionErrored(this, error);
    }
    requestFinished(_request) {
      this.state = FormSubmissionState.stopped;
      if (this.submitter) config.forms.submitter.afterSubmit(this.submitter);
      this.resetSubmitterText();
      clearBusyState(this.formElement);
      dispatch("turbo:submit-end", {
        target: this.formElement,
        detail: __spreadValues({ formSubmission: this }, this.result)
      });
      this.delegate.formSubmissionFinished(this);
    }
    // Private
    setSubmitsWith() {
      if (!this.submitter || !this.submitsWith) return;
      if (this.submitter.matches("button")) {
        this.originalSubmitText = this.submitter.innerHTML;
        this.submitter.innerHTML = this.submitsWith;
      } else if (this.submitter.matches("input")) {
        const input = this.submitter;
        this.originalSubmitText = input.value;
        input.value = this.submitsWith;
      }
    }
    resetSubmitterText() {
      if (!this.submitter || !this.originalSubmitText) return;
      if (this.submitter.matches("button")) {
        this.submitter.innerHTML = this.originalSubmitText;
      } else if (this.submitter.matches("input")) {
        const input = this.submitter;
        input.value = this.originalSubmitText;
      }
    }
    requestMustRedirect(request) {
      return !request.isSafe && this.mustRedirect;
    }
    requestAcceptsTurboStreamResponse(request) {
      return !request.isSafe || hasAttribute("data-turbo-stream", this.submitter, this.formElement);
    }
    get submitsWith() {
      var _a;
      return (_a = this.submitter) == null ? void 0 : _a.getAttribute("data-turbo-submits-with");
    }
  };
  function buildFormData(formElement, submitter2) {
    const formData = new FormData(formElement);
    const name = submitter2 == null ? void 0 : submitter2.getAttribute("name");
    const value = submitter2 == null ? void 0 : submitter2.getAttribute("value");
    if (name) {
      formData.append(name, value || "");
    }
    return formData;
  }
  function getCookieValue(cookieName) {
    if (cookieName != null) {
      const cookies = document.cookie ? document.cookie.split("; ") : [];
      const cookie = cookies.find((cookie2) => cookie2.startsWith(cookieName));
      if (cookie) {
        const value = cookie.split("=").slice(1).join("=");
        return value ? decodeURIComponent(value) : void 0;
      }
    }
  }
  function responseSucceededWithoutRedirect(response) {
    return response.statusCode == 200 && !response.redirected;
  }
  function getFormAction(formElement, submitter2) {
    const formElementAction = typeof formElement.action === "string" ? formElement.action : null;
    if (submitter2 == null ? void 0 : submitter2.hasAttribute("formaction")) {
      return submitter2.getAttribute("formaction") || "";
    } else {
      return formElement.getAttribute("action") || formElementAction || "";
    }
  }
  function getAction2(formAction, fetchMethod) {
    const action = expandURL(formAction);
    if (isSafe(fetchMethod)) {
      action.search = "";
    }
    return action;
  }
  function getMethod(formElement, submitter2) {
    const method = (submitter2 == null ? void 0 : submitter2.getAttribute("formmethod")) || formElement.getAttribute("method") || "";
    return fetchMethodFromString(method.toLowerCase()) || FetchMethod.get;
  }
  function getEnctype(formElement, submitter2) {
    return fetchEnctypeFromString((submitter2 == null ? void 0 : submitter2.getAttribute("formenctype")) || formElement.enctype);
  }

  // src/core/snapshot.js
  var Snapshot = class {
    constructor(element) {
      this.element = element;
    }
    get activeElement() {
      return this.element.ownerDocument.activeElement;
    }
    get children() {
      return [...this.element.children];
    }
    hasAnchor(anchor) {
      return this.getElementForAnchor(anchor) != null;
    }
    getElementForAnchor(anchor) {
      return anchor ? this.element.querySelector(`[id='${anchor}'], a[name='${anchor}']`) : null;
    }
    get isConnected() {
      return this.element.isConnected;
    }
    get firstAutofocusableElement() {
      return queryAutofocusableElement(this.element);
    }
    get permanentElements() {
      return queryPermanentElementsAll(this.element);
    }
    getPermanentElementById(id) {
      return getPermanentElementById(this.element, id);
    }
    getPermanentElementMapForSnapshot(snapshot) {
      const permanentElementMap = {};
      for (const currentPermanentElement of this.permanentElements) {
        const { id } = currentPermanentElement;
        const newPermanentElement = snapshot.getPermanentElementById(id);
        if (newPermanentElement) {
          permanentElementMap[id] = [currentPermanentElement, newPermanentElement];
        }
      }
      return permanentElementMap;
    }
  };
  function getPermanentElementById(node, id) {
    return node.querySelector(`#${id}[data-turbo-permanent]`);
  }
  function queryPermanentElementsAll(node) {
    return node.querySelectorAll("[id][data-turbo-permanent]");
  }

  // src/observers/form_submit_observer.js
  var FormSubmitObserver = class {
    constructor(delegate, eventTarget) {
      __publicField(this, "started", false);
      __publicField(this, "submitCaptured", () => {
        this.eventTarget.removeEventListener("submit", this.submitBubbled, false);
        this.eventTarget.addEventListener("submit", this.submitBubbled, false);
      });
      __publicField(this, "submitBubbled", (event) => {
        if (!event.defaultPrevented) {
          const form = event.target instanceof HTMLFormElement ? event.target : void 0;
          const submitter2 = event.submitter || void 0;
          if (form && submissionDoesNotDismissDialog(form, submitter2) && submissionDoesNotTargetIFrame(form, submitter2) && this.delegate.willSubmitForm(form, submitter2)) {
            event.preventDefault();
            event.stopImmediatePropagation();
            this.delegate.formSubmitted(form, submitter2);
          }
        }
      });
      this.delegate = delegate;
      this.eventTarget = eventTarget;
    }
    start() {
      if (!this.started) {
        this.eventTarget.addEventListener("submit", this.submitCaptured, true);
        this.started = true;
      }
    }
    stop() {
      if (this.started) {
        this.eventTarget.removeEventListener("submit", this.submitCaptured, true);
        this.started = false;
      }
    }
  };
  function submissionDoesNotDismissDialog(form, submitter2) {
    const method = (submitter2 == null ? void 0 : submitter2.getAttribute("formmethod")) || form.getAttribute("method");
    return method != "dialog";
  }
  function submissionDoesNotTargetIFrame(form, submitter2) {
    const target = (submitter2 == null ? void 0 : submitter2.getAttribute("formtarget")) || form.getAttribute("target");
    return doesNotTargetIFrame(target);
  }

  // src/core/view.js
  var _resolveRenderPromise, _resolveInterceptionPromise;
  var View = class {
    constructor(delegate, element) {
      __privateAdd(this, _resolveRenderPromise, (_value) => {
      });
      __privateAdd(this, _resolveInterceptionPromise, (_value) => {
      });
      this.delegate = delegate;
      this.element = element;
    }
    // Scrolling
    scrollToAnchor(anchor) {
      const element = this.snapshot.getElementForAnchor(anchor);
      if (element) {
        this.focusElement(element);
        this.scrollToElement(element);
      } else {
        this.scrollToPosition({ x: 0, y: 0 });
      }
    }
    scrollToAnchorFromLocation(location2) {
      this.scrollToAnchor(getAnchor(location2));
    }
    scrollToElement(element) {
      element.scrollIntoView();
    }
    focusElement(element) {
      if (element instanceof HTMLElement) {
        if (element.hasAttribute("tabindex")) {
          element.focus();
        } else {
          element.setAttribute("tabindex", "-1");
          element.focus();
          element.removeAttribute("tabindex");
        }
      }
    }
    scrollToPosition({ x, y }) {
      this.scrollRoot.scrollTo(x, y);
    }
    scrollToTop() {
      this.scrollToPosition({ x: 0, y: 0 });
    }
    get scrollRoot() {
      return window;
    }
    // Rendering
    async render(renderer) {
      const { isPreview, shouldRender, willRender, newSnapshot: snapshot } = renderer;
      const shouldInvalidate = willRender;
      if (shouldRender) {
        try {
          this.renderPromise = new Promise((resolve) => __privateSet(this, _resolveRenderPromise, resolve));
          this.renderer = renderer;
          await this.prepareToRenderSnapshot(renderer);
          const renderInterception = new Promise((resolve) => __privateSet(this, _resolveInterceptionPromise, resolve));
          const options = { resume: __privateGet(this, _resolveInterceptionPromise), render: this.renderer.renderElement, renderMethod: this.renderer.renderMethod };
          const immediateRender = this.delegate.allowsImmediateRender(snapshot, options);
          if (!immediateRender) await renderInterception;
          await this.renderSnapshot(renderer);
          this.delegate.viewRenderedSnapshot(snapshot, isPreview, this.renderer.renderMethod);
          this.delegate.preloadOnLoadLinksForView(this.element);
          this.finishRenderingSnapshot(renderer);
        } finally {
          delete this.renderer;
          __privateGet(this, _resolveRenderPromise).call(this, void 0);
          delete this.renderPromise;
        }
      } else if (shouldInvalidate) {
        this.invalidate(renderer.reloadReason);
      }
    }
    invalidate(reason) {
      this.delegate.viewInvalidated(reason);
    }
    async prepareToRenderSnapshot(renderer) {
      this.markAsPreview(renderer.isPreview);
      await renderer.prepareToRender();
    }
    markAsPreview(isPreview) {
      if (isPreview) {
        this.element.setAttribute("data-turbo-preview", "");
      } else {
        this.element.removeAttribute("data-turbo-preview");
      }
    }
    markVisitDirection(direction) {
      this.element.setAttribute("data-turbo-visit-direction", direction);
    }
    unmarkVisitDirection() {
      this.element.removeAttribute("data-turbo-visit-direction");
    }
    async renderSnapshot(renderer) {
      await renderer.render();
    }
    finishRenderingSnapshot(renderer) {
      renderer.finishRendering();
    }
  };
  _resolveRenderPromise = new WeakMap();
  _resolveInterceptionPromise = new WeakMap();

  // src/core/frames/frame_view.js
  var FrameView = class extends View {
    missing() {
      this.element.innerHTML = `<strong class="turbo-frame-error">Content missing</strong>`;
    }
    get snapshot() {
      return new Snapshot(this.element);
    }
  };

  // src/core/frames/link_interceptor.js
  var LinkInterceptor = class {
    constructor(delegate, element) {
      __publicField(this, "clickBubbled", (event) => {
        if (this.clickEventIsSignificant(event)) {
          this.clickEvent = event;
        } else {
          delete this.clickEvent;
        }
      });
      __publicField(this, "linkClicked", (event) => {
        if (this.clickEvent && this.clickEventIsSignificant(event)) {
          if (this.delegate.shouldInterceptLinkClick(event.target, event.detail.url, event.detail.originalEvent)) {
            this.clickEvent.preventDefault();
            event.preventDefault();
            this.delegate.linkClickIntercepted(event.target, event.detail.url, event.detail.originalEvent);
          }
        }
        delete this.clickEvent;
      });
      __publicField(this, "willVisit", (_event) => {
        delete this.clickEvent;
      });
      this.delegate = delegate;
      this.element = element;
    }
    start() {
      this.element.addEventListener("click", this.clickBubbled);
      document.addEventListener("turbo:click", this.linkClicked);
      document.addEventListener("turbo:before-visit", this.willVisit);
    }
    stop() {
      this.element.removeEventListener("click", this.clickBubbled);
      document.removeEventListener("turbo:click", this.linkClicked);
      document.removeEventListener("turbo:before-visit", this.willVisit);
    }
    clickEventIsSignificant(event) {
      var _a;
      const target = event.composed ? (_a = event.target) == null ? void 0 : _a.parentElement : event.target;
      const element = findLinkFromClickTarget(target) || target;
      return element instanceof Element && element.closest("turbo-frame, html") == this.element;
    }
  };

  // src/observers/link_click_observer.js
  var LinkClickObserver = class {
    constructor(delegate, eventTarget) {
      __publicField(this, "started", false);
      __publicField(this, "clickCaptured", () => {
        this.eventTarget.removeEventListener("click", this.clickBubbled, false);
        this.eventTarget.addEventListener("click", this.clickBubbled, false);
      });
      __publicField(this, "clickBubbled", (event) => {
        if (event instanceof MouseEvent && this.clickEventIsSignificant(event)) {
          const target = event.composedPath && event.composedPath()[0] || event.target;
          const link = findLinkFromClickTarget(target);
          if (link && doesNotTargetIFrame(link.target)) {
            const location2 = getLocationForLink(link);
            if (this.delegate.willFollowLinkToLocation(link, location2, event)) {
              event.preventDefault();
              this.delegate.followedLinkToLocation(link, location2);
            }
          }
        }
      });
      this.delegate = delegate;
      this.eventTarget = eventTarget;
    }
    start() {
      if (!this.started) {
        this.eventTarget.addEventListener("click", this.clickCaptured, true);
        this.started = true;
      }
    }
    stop() {
      if (this.started) {
        this.eventTarget.removeEventListener("click", this.clickCaptured, true);
        this.started = false;
      }
    }
    clickEventIsSignificant(event) {
      return !(event.target && event.target.isContentEditable || event.defaultPrevented || event.which > 1 || event.altKey || event.ctrlKey || event.metaKey || event.shiftKey);
    }
  };

  // src/observers/form_link_click_observer.js
  var FormLinkClickObserver = class {
    constructor(delegate, element) {
      this.delegate = delegate;
      this.linkInterceptor = new LinkClickObserver(this, element);
    }
    start() {
      this.linkInterceptor.start();
    }
    stop() {
      this.linkInterceptor.stop();
    }
    // Link hover observer delegate
    canPrefetchRequestToLocation(link, location2) {
      return false;
    }
    prefetchAndCacheRequestToLocation(link, location2) {
      return;
    }
    // Link click observer delegate
    willFollowLinkToLocation(link, location2, originalEvent) {
      return this.delegate.willSubmitFormLinkToLocation(link, location2, originalEvent) && (link.hasAttribute("data-turbo-method") || link.hasAttribute("data-turbo-stream"));
    }
    followedLinkToLocation(link, location2) {
      const form = document.createElement("form");
      const type = "hidden";
      for (const [name, value] of location2.searchParams) {
        form.append(Object.assign(document.createElement("input"), { type, name, value }));
      }
      const action = Object.assign(location2, { search: "" });
      form.setAttribute("data-turbo", "true");
      form.setAttribute("action", action.href);
      form.setAttribute("hidden", "");
      const method = link.getAttribute("data-turbo-method");
      if (method) form.setAttribute("method", method);
      const turboFrame = link.getAttribute("data-turbo-frame");
      if (turboFrame) form.setAttribute("data-turbo-frame", turboFrame);
      const turboAction = getVisitAction(link);
      if (turboAction) form.setAttribute("data-turbo-action", turboAction);
      const turboConfirm = link.getAttribute("data-turbo-confirm");
      if (turboConfirm) form.setAttribute("data-turbo-confirm", turboConfirm);
      const turboStream = link.hasAttribute("data-turbo-stream");
      if (turboStream) form.setAttribute("data-turbo-stream", "");
      this.delegate.submittedFormLinkToLocation(link, location2, form);
      document.body.appendChild(form);
      form.addEventListener("turbo:submit-end", () => form.remove(), { once: true });
      requestAnimationFrame(() => form.requestSubmit());
    }
  };

  // src/core/bardo.js
  var Bardo = class {
    static async preservingPermanentElements(delegate, permanentElementMap, callback) {
      const bardo = new this(delegate, permanentElementMap);
      bardo.enter();
      await callback();
      bardo.leave();
    }
    constructor(delegate, permanentElementMap) {
      this.delegate = delegate;
      this.permanentElementMap = permanentElementMap;
    }
    enter() {
      for (const id in this.permanentElementMap) {
        const [currentPermanentElement, newPermanentElement] = this.permanentElementMap[id];
        this.delegate.enteringBardo(currentPermanentElement, newPermanentElement);
        this.replaceNewPermanentElementWithPlaceholder(newPermanentElement);
      }
    }
    leave() {
      for (const id in this.permanentElementMap) {
        const [currentPermanentElement] = this.permanentElementMap[id];
        this.replaceCurrentPermanentElementWithClone(currentPermanentElement);
        this.replacePlaceholderWithPermanentElement(currentPermanentElement);
        this.delegate.leavingBardo(currentPermanentElement);
      }
    }
    replaceNewPermanentElementWithPlaceholder(permanentElement) {
      const placeholder = createPlaceholderForPermanentElement(permanentElement);
      permanentElement.replaceWith(placeholder);
    }
    replaceCurrentPermanentElementWithClone(permanentElement) {
      const clone = permanentElement.cloneNode(true);
      permanentElement.replaceWith(clone);
    }
    replacePlaceholderWithPermanentElement(permanentElement) {
      const placeholder = this.getPlaceholderById(permanentElement.id);
      placeholder == null ? void 0 : placeholder.replaceWith(permanentElement);
    }
    getPlaceholderById(id) {
      return this.placeholders.find((element) => element.content == id);
    }
    get placeholders() {
      return [...document.querySelectorAll("meta[name=turbo-permanent-placeholder][content]")];
    }
  };
  function createPlaceholderForPermanentElement(permanentElement) {
    const element = document.createElement("meta");
    element.setAttribute("name", "turbo-permanent-placeholder");
    element.setAttribute("content", permanentElement.id);
    return element;
  }

  // src/core/renderer.js
  var _activeElement;
  var Renderer = class {
    constructor(currentSnapshot, newSnapshot, isPreview, willRender = true) {
      __privateAdd(this, _activeElement, null);
      this.currentSnapshot = currentSnapshot;
      this.newSnapshot = newSnapshot;
      this.isPreview = isPreview;
      this.willRender = willRender;
      this.renderElement = this.constructor.renderElement;
      this.promise = new Promise((resolve, reject) => this.resolvingFunctions = { resolve, reject });
    }
    static renderElement(currentElement, newElement) {
    }
    get shouldRender() {
      return true;
    }
    get shouldAutofocus() {
      return true;
    }
    get reloadReason() {
      return;
    }
    prepareToRender() {
      return;
    }
    render() {
    }
    finishRendering() {
      if (this.resolvingFunctions) {
        this.resolvingFunctions.resolve();
        delete this.resolvingFunctions;
      }
    }
    async preservingPermanentElements(callback) {
      await Bardo.preservingPermanentElements(this, this.permanentElementMap, callback);
    }
    focusFirstAutofocusableElement() {
      if (this.shouldAutofocus) {
        const element = this.connectedSnapshot.firstAutofocusableElement;
        if (element) {
          element.focus();
        }
      }
    }
    // Bardo delegate
    enteringBardo(currentPermanentElement) {
      if (__privateGet(this, _activeElement)) return;
      if (currentPermanentElement.contains(this.currentSnapshot.activeElement)) {
        __privateSet(this, _activeElement, this.currentSnapshot.activeElement);
      }
    }
    leavingBardo(currentPermanentElement) {
      if (currentPermanentElement.contains(__privateGet(this, _activeElement)) && __privateGet(this, _activeElement) instanceof HTMLElement) {
        __privateGet(this, _activeElement).focus();
        __privateSet(this, _activeElement, null);
      }
    }
    get connectedSnapshot() {
      return this.newSnapshot.isConnected ? this.newSnapshot : this.currentSnapshot;
    }
    get currentElement() {
      return this.currentSnapshot.element;
    }
    get newElement() {
      return this.newSnapshot.element;
    }
    get permanentElementMap() {
      return this.currentSnapshot.getPermanentElementMapForSnapshot(this.newSnapshot);
    }
    get renderMethod() {
      return "replace";
    }
  };
  _activeElement = new WeakMap();

  // src/core/frames/frame_renderer.js
  var FrameRenderer = class extends Renderer {
    static renderElement(currentElement, newElement) {
      var _a;
      const destinationRange = document.createRange();
      destinationRange.selectNodeContents(currentElement);
      destinationRange.deleteContents();
      const frameElement = newElement;
      const sourceRange = (_a = frameElement.ownerDocument) == null ? void 0 : _a.createRange();
      if (sourceRange) {
        sourceRange.selectNodeContents(frameElement);
        currentElement.appendChild(sourceRange.extractContents());
      }
    }
    constructor(delegate, currentSnapshot, newSnapshot, renderElement, isPreview, willRender = true) {
      super(currentSnapshot, newSnapshot, renderElement, isPreview, willRender);
      this.delegate = delegate;
    }
    get shouldRender() {
      return true;
    }
    async render() {
      await nextRepaint();
      this.preservingPermanentElements(() => {
        this.loadFrameElement();
      });
      this.scrollFrameIntoView();
      await nextRepaint();
      this.focusFirstAutofocusableElement();
      await nextRepaint();
      this.activateScriptElements();
    }
    loadFrameElement() {
      this.delegate.willRenderFrame(this.currentElement, this.newElement);
      this.renderElement(this.currentElement, this.newElement);
    }
    scrollFrameIntoView() {
      if (this.currentElement.autoscroll || this.newElement.autoscroll) {
        const element = this.currentElement.firstElementChild;
        const block = readScrollLogicalPosition(this.currentElement.getAttribute("data-autoscroll-block"), "end");
        const behavior = readScrollBehavior(this.currentElement.getAttribute("data-autoscroll-behavior"), "auto");
        if (element) {
          element.scrollIntoView({ block, behavior });
          return true;
        }
      }
      return false;
    }
    activateScriptElements() {
      for (const inertScriptElement of this.newScriptElements) {
        const activatedScriptElement = activateScriptElement(inertScriptElement);
        inertScriptElement.replaceWith(activatedScriptElement);
      }
    }
    get newScriptElements() {
      return this.currentElement.querySelectorAll("script");
    }
  };
  function readScrollLogicalPosition(value, defaultValue) {
    if (value == "end" || value == "start" || value == "center" || value == "nearest") {
      return value;
    } else {
      return defaultValue;
    }
  }
  function readScrollBehavior(value, defaultValue) {
    if (value == "auto" || value == "smooth") {
      return value;
    } else {
      return defaultValue;
    }
  }

  // node_modules/idiomorph/dist/idiomorph.esm.js
  var Idiomorph = function() {
    "use strict";
    const noOp = () => {
    };
    const defaults = {
      morphStyle: "outerHTML",
      callbacks: {
        beforeNodeAdded: noOp,
        afterNodeAdded: noOp,
        beforeNodeMorphed: noOp,
        afterNodeMorphed: noOp,
        beforeNodeRemoved: noOp,
        afterNodeRemoved: noOp,
        beforeAttributeUpdated: noOp
      },
      head: {
        style: "merge",
        shouldPreserve: (elt) => elt.getAttribute("im-preserve") === "true",
        shouldReAppend: (elt) => elt.getAttribute("im-re-append") === "true",
        shouldRemove: noOp,
        afterHeadMorphed: noOp
      },
      restoreFocus: true
    };
    function morph(oldNode, newContent, config2 = {}) {
      oldNode = normalizeElement(oldNode);
      const newNode = normalizeParent(newContent);
      const ctx = createMorphContext(oldNode, newNode, config2);
      const morphedNodes = saveAndRestoreFocus(ctx, () => {
        return withHeadBlocking(
          ctx,
          oldNode,
          newNode,
          /** @param {MorphContext} ctx */
          (ctx2) => {
            if (ctx2.morphStyle === "innerHTML") {
              morphChildren2(ctx2, oldNode, newNode);
              return Array.from(oldNode.childNodes);
            } else {
              return morphOuterHTML(ctx2, oldNode, newNode);
            }
          }
        );
      });
      ctx.pantry.remove();
      return morphedNodes;
    }
    function morphOuterHTML(ctx, oldNode, newNode) {
      const oldParent = normalizeParent(oldNode);
      morphChildren2(
        ctx,
        oldParent,
        newNode,
        // these two optional params are the secret sauce
        oldNode,
        // start point for iteration
        oldNode.nextSibling
        // end point for iteration
      );
      return Array.from(oldParent.childNodes);
    }
    function saveAndRestoreFocus(ctx, fn) {
      var _a;
      if (!ctx.config.restoreFocus) return fn();
      let activeElement = (
        /** @type {HTMLInputElement|HTMLTextAreaElement|null} */
        document.activeElement
      );
      if (!(activeElement instanceof HTMLInputElement || activeElement instanceof HTMLTextAreaElement)) {
        return fn();
      }
      const { id: activeElementId, selectionStart, selectionEnd } = activeElement;
      const results = fn();
      if (activeElementId && activeElementId !== ((_a = document.activeElement) == null ? void 0 : _a.getAttribute("id"))) {
        activeElement = ctx.target.querySelector(`[id="${activeElementId}"]`);
        activeElement == null ? void 0 : activeElement.focus();
      }
      if (activeElement && !activeElement.selectionEnd && selectionEnd) {
        activeElement.setSelectionRange(selectionStart, selectionEnd);
      }
      return results;
    }
    const morphChildren2 = /* @__PURE__ */ function() {
      function morphChildren3(ctx, oldParent, newParent, insertionPoint = null, endPoint = null) {
        if (oldParent instanceof HTMLTemplateElement && newParent instanceof HTMLTemplateElement) {
          oldParent = oldParent.content;
          newParent = newParent.content;
        }
        insertionPoint || (insertionPoint = oldParent.firstChild);
        for (const newChild of newParent.childNodes) {
          if (insertionPoint && insertionPoint != endPoint) {
            const bestMatch = findBestMatch(
              ctx,
              newChild,
              insertionPoint,
              endPoint
            );
            if (bestMatch) {
              if (bestMatch !== insertionPoint) {
                removeNodesBetween(ctx, insertionPoint, bestMatch);
              }
              morphNode(bestMatch, newChild, ctx);
              insertionPoint = bestMatch.nextSibling;
              continue;
            }
          }
          if (newChild instanceof Element) {
            const newChildId = (
              /** @type {String} */
              newChild.getAttribute("id")
            );
            if (ctx.persistentIds.has(newChildId)) {
              const movedChild = moveBeforeById(
                oldParent,
                newChildId,
                insertionPoint,
                ctx
              );
              morphNode(movedChild, newChild, ctx);
              insertionPoint = movedChild.nextSibling;
              continue;
            }
          }
          const insertedNode = createNode(
            oldParent,
            newChild,
            insertionPoint,
            ctx
          );
          if (insertedNode) {
            insertionPoint = insertedNode.nextSibling;
          }
        }
        while (insertionPoint && insertionPoint != endPoint) {
          const tempNode = insertionPoint;
          insertionPoint = insertionPoint.nextSibling;
          removeNode(ctx, tempNode);
        }
      }
      function createNode(oldParent, newChild, insertionPoint, ctx) {
        if (ctx.callbacks.beforeNodeAdded(newChild) === false) return null;
        if (ctx.idMap.has(newChild)) {
          const newEmptyChild = document.createElement(
            /** @type {Element} */
            newChild.tagName
          );
          oldParent.insertBefore(newEmptyChild, insertionPoint);
          morphNode(newEmptyChild, newChild, ctx);
          ctx.callbacks.afterNodeAdded(newEmptyChild);
          return newEmptyChild;
        } else {
          const newClonedChild = document.importNode(newChild, true);
          oldParent.insertBefore(newClonedChild, insertionPoint);
          ctx.callbacks.afterNodeAdded(newClonedChild);
          return newClonedChild;
        }
      }
      const findBestMatch = /* @__PURE__ */ function() {
        function findBestMatch2(ctx, node, startPoint, endPoint) {
          let softMatch = null;
          let nextSibling = node.nextSibling;
          let siblingSoftMatchCount = 0;
          let cursor = startPoint;
          while (cursor && cursor != endPoint) {
            if (isSoftMatch(cursor, node)) {
              if (isIdSetMatch(ctx, cursor, node)) {
                return cursor;
              }
              if (softMatch === null) {
                if (!ctx.idMap.has(cursor)) {
                  softMatch = cursor;
                }
              }
            }
            if (softMatch === null && nextSibling && isSoftMatch(cursor, nextSibling)) {
              siblingSoftMatchCount++;
              nextSibling = nextSibling.nextSibling;
              if (siblingSoftMatchCount >= 2) {
                softMatch = void 0;
              }
            }
            if (ctx.activeElementAndParents.includes(cursor)) break;
            cursor = cursor.nextSibling;
          }
          return softMatch || null;
        }
        function isIdSetMatch(ctx, oldNode, newNode) {
          let oldSet = ctx.idMap.get(oldNode);
          let newSet = ctx.idMap.get(newNode);
          if (!newSet || !oldSet) return false;
          for (const id of oldSet) {
            if (newSet.has(id)) {
              return true;
            }
          }
          return false;
        }
        function isSoftMatch(oldNode, newNode) {
          var _a, _b, _c;
          const oldElt = (
            /** @type {Element} */
            oldNode
          );
          const newElt = (
            /** @type {Element} */
            newNode
          );
          return oldElt.nodeType === newElt.nodeType && oldElt.tagName === newElt.tagName && // If oldElt has an `id` with possible state and it doesn't match newElt.id then avoid morphing.
          // We'll still match an anonymous node with an IDed newElt, though, because if it got this far,
          // its not persistent, and new nodes can't have any hidden state.
          // We can't use .id because of form input shadowing, and we can't count on .getAttribute's presence because it could be a document-fragment
          (!((_a = oldElt.getAttribute) == null ? void 0 : _a.call(oldElt, "id")) || ((_b = oldElt.getAttribute) == null ? void 0 : _b.call(oldElt, "id")) === ((_c = newElt.getAttribute) == null ? void 0 : _c.call(newElt, "id")));
        }
        return findBestMatch2;
      }();
      function removeNode(ctx, node) {
        var _a;
        if (ctx.idMap.has(node)) {
          moveBefore(ctx.pantry, node, null);
        } else {
          if (ctx.callbacks.beforeNodeRemoved(node) === false) return;
          (_a = node.parentNode) == null ? void 0 : _a.removeChild(node);
          ctx.callbacks.afterNodeRemoved(node);
        }
      }
      function removeNodesBetween(ctx, startInclusive, endExclusive) {
        let cursor = startInclusive;
        while (cursor && cursor !== endExclusive) {
          let tempNode = (
            /** @type {Node} */
            cursor
          );
          cursor = cursor.nextSibling;
          removeNode(ctx, tempNode);
        }
        return cursor;
      }
      function moveBeforeById(parentNode, id, after, ctx) {
        var _a, _b;
        const target = (
          /** @type {Element} - will always be found */
          // ctx.target.id unsafe because of form input shadowing
          // ctx.target could be a document fragment which doesn't have `getAttribute`
          ((_b = (_a = ctx.target).getAttribute) == null ? void 0 : _b.call(_a, "id")) === id && ctx.target || ctx.target.querySelector(`[id="${id}"]`) || ctx.pantry.querySelector(`[id="${id}"]`)
        );
        removeElementFromAncestorsIdMaps(target, ctx);
        moveBefore(parentNode, target, after);
        return target;
      }
      function removeElementFromAncestorsIdMaps(element, ctx) {
        const id = (
          /** @type {String} */
          element.getAttribute("id")
        );
        while (element = element.parentNode) {
          let idSet = ctx.idMap.get(element);
          if (idSet) {
            idSet.delete(id);
            if (!idSet.size) {
              ctx.idMap.delete(element);
            }
          }
        }
      }
      function moveBefore(parentNode, element, after) {
        if (parentNode.moveBefore) {
          try {
            parentNode.moveBefore(element, after);
          } catch (e) {
            parentNode.insertBefore(element, after);
          }
        } else {
          parentNode.insertBefore(element, after);
        }
      }
      return morphChildren3;
    }();
    const morphNode = /* @__PURE__ */ function() {
      function morphNode2(oldNode, newContent, ctx) {
        if (ctx.ignoreActive && oldNode === document.activeElement) {
          return null;
        }
        if (ctx.callbacks.beforeNodeMorphed(oldNode, newContent) === false) {
          return oldNode;
        }
        if (oldNode instanceof HTMLHeadElement && ctx.head.ignore) {
        } else if (oldNode instanceof HTMLHeadElement && ctx.head.style !== "morph") {
          handleHeadElement(
            oldNode,
            /** @type {HTMLHeadElement} */
            newContent,
            ctx
          );
        } else {
          morphAttributes(oldNode, newContent, ctx);
          if (!ignoreValueOfActiveElement(oldNode, ctx)) {
            morphChildren2(ctx, oldNode, newContent);
          }
        }
        ctx.callbacks.afterNodeMorphed(oldNode, newContent);
        return oldNode;
      }
      function morphAttributes(oldNode, newNode, ctx) {
        let type = newNode.nodeType;
        if (type === 1) {
          const oldElt = (
            /** @type {Element} */
            oldNode
          );
          const newElt = (
            /** @type {Element} */
            newNode
          );
          const oldAttributes = oldElt.attributes;
          const newAttributes = newElt.attributes;
          for (const newAttribute of newAttributes) {
            if (ignoreAttribute(newAttribute.name, oldElt, "update", ctx)) {
              continue;
            }
            if (oldElt.getAttribute(newAttribute.name) !== newAttribute.value) {
              oldElt.setAttribute(newAttribute.name, newAttribute.value);
            }
          }
          for (let i = oldAttributes.length - 1; 0 <= i; i--) {
            const oldAttribute = oldAttributes[i];
            if (!oldAttribute) continue;
            if (!newElt.hasAttribute(oldAttribute.name)) {
              if (ignoreAttribute(oldAttribute.name, oldElt, "remove", ctx)) {
                continue;
              }
              oldElt.removeAttribute(oldAttribute.name);
            }
          }
          if (!ignoreValueOfActiveElement(oldElt, ctx)) {
            syncInputValue(oldElt, newElt, ctx);
          }
        }
        if (type === 8 || type === 3) {
          if (oldNode.nodeValue !== newNode.nodeValue) {
            oldNode.nodeValue = newNode.nodeValue;
          }
        }
      }
      function syncInputValue(oldElement, newElement, ctx) {
        if (oldElement instanceof HTMLInputElement && newElement instanceof HTMLInputElement && newElement.type !== "file") {
          let newValue = newElement.value;
          let oldValue = oldElement.value;
          syncBooleanAttribute(oldElement, newElement, "checked", ctx);
          syncBooleanAttribute(oldElement, newElement, "disabled", ctx);
          if (!newElement.hasAttribute("value")) {
            if (!ignoreAttribute("value", oldElement, "remove", ctx)) {
              oldElement.value = "";
              oldElement.removeAttribute("value");
            }
          } else if (oldValue !== newValue) {
            if (!ignoreAttribute("value", oldElement, "update", ctx)) {
              oldElement.setAttribute("value", newValue);
              oldElement.value = newValue;
            }
          }
        } else if (oldElement instanceof HTMLOptionElement && newElement instanceof HTMLOptionElement) {
          syncBooleanAttribute(oldElement, newElement, "selected", ctx);
        } else if (oldElement instanceof HTMLTextAreaElement && newElement instanceof HTMLTextAreaElement) {
          let newValue = newElement.value;
          let oldValue = oldElement.value;
          if (ignoreAttribute("value", oldElement, "update", ctx)) {
            return;
          }
          if (newValue !== oldValue) {
            oldElement.value = newValue;
          }
          if (oldElement.firstChild && oldElement.firstChild.nodeValue !== newValue) {
            oldElement.firstChild.nodeValue = newValue;
          }
        }
      }
      function syncBooleanAttribute(oldElement, newElement, attributeName, ctx) {
        const newLiveValue = newElement[attributeName], oldLiveValue = oldElement[attributeName];
        if (newLiveValue !== oldLiveValue) {
          const ignoreUpdate = ignoreAttribute(
            attributeName,
            oldElement,
            "update",
            ctx
          );
          if (!ignoreUpdate) {
            oldElement[attributeName] = newElement[attributeName];
          }
          if (newLiveValue) {
            if (!ignoreUpdate) {
              oldElement.setAttribute(attributeName, "");
            }
          } else {
            if (!ignoreAttribute(attributeName, oldElement, "remove", ctx)) {
              oldElement.removeAttribute(attributeName);
            }
          }
        }
      }
      function ignoreAttribute(attr, element, updateType, ctx) {
        if (attr === "value" && ctx.ignoreActiveValue && element === document.activeElement) {
          return true;
        }
        return ctx.callbacks.beforeAttributeUpdated(attr, element, updateType) === false;
      }
      function ignoreValueOfActiveElement(possibleActiveElement, ctx) {
        return !!ctx.ignoreActiveValue && possibleActiveElement === document.activeElement && possibleActiveElement !== document.body;
      }
      return morphNode2;
    }();
    function withHeadBlocking(ctx, oldNode, newNode, callback) {
      if (ctx.head.block) {
        const oldHead = oldNode.querySelector("head");
        const newHead = newNode.querySelector("head");
        if (oldHead && newHead) {
          const promises = handleHeadElement(oldHead, newHead, ctx);
          return Promise.all(promises).then(() => {
            const newCtx = Object.assign(ctx, {
              head: {
                block: false,
                ignore: true
              }
            });
            return callback(newCtx);
          });
        }
      }
      return callback(ctx);
    }
    function handleHeadElement(oldHead, newHead, ctx) {
      let added = [];
      let removed = [];
      let preserved = [];
      let nodesToAppend = [];
      let srcToNewHeadNodes = /* @__PURE__ */ new Map();
      for (const newHeadChild of newHead.children) {
        srcToNewHeadNodes.set(newHeadChild.outerHTML, newHeadChild);
      }
      for (const currentHeadElt of oldHead.children) {
        let inNewContent = srcToNewHeadNodes.has(currentHeadElt.outerHTML);
        let isReAppended = ctx.head.shouldReAppend(currentHeadElt);
        let isPreserved = ctx.head.shouldPreserve(currentHeadElt);
        if (inNewContent || isPreserved) {
          if (isReAppended) {
            removed.push(currentHeadElt);
          } else {
            srcToNewHeadNodes.delete(currentHeadElt.outerHTML);
            preserved.push(currentHeadElt);
          }
        } else {
          if (ctx.head.style === "append") {
            if (isReAppended) {
              removed.push(currentHeadElt);
              nodesToAppend.push(currentHeadElt);
            }
          } else {
            if (ctx.head.shouldRemove(currentHeadElt) !== false) {
              removed.push(currentHeadElt);
            }
          }
        }
      }
      nodesToAppend.push(...srcToNewHeadNodes.values());
      let promises = [];
      for (const newNode of nodesToAppend) {
        let newElt = (
          /** @type {ChildNode} */
          document.createRange().createContextualFragment(newNode.outerHTML).firstChild
        );
        if (ctx.callbacks.beforeNodeAdded(newElt) !== false) {
          if ("href" in newElt && newElt.href || "src" in newElt && newElt.src) {
            let resolve;
            let promise = new Promise(function(_resolve) {
              resolve = _resolve;
            });
            newElt.addEventListener("load", function() {
              resolve();
            });
            promises.push(promise);
          }
          oldHead.appendChild(newElt);
          ctx.callbacks.afterNodeAdded(newElt);
          added.push(newElt);
        }
      }
      for (const removedElement of removed) {
        if (ctx.callbacks.beforeNodeRemoved(removedElement) !== false) {
          oldHead.removeChild(removedElement);
          ctx.callbacks.afterNodeRemoved(removedElement);
        }
      }
      ctx.head.afterHeadMorphed(oldHead, {
        added,
        kept: preserved,
        removed
      });
      return promises;
    }
    const createMorphContext = /* @__PURE__ */ function() {
      function createMorphContext2(oldNode, newContent, config2) {
        const { persistentIds, idMap } = createIdMaps(oldNode, newContent);
        const mergedConfig = mergeDefaults(config2);
        const morphStyle = mergedConfig.morphStyle || "outerHTML";
        if (!["innerHTML", "outerHTML"].includes(morphStyle)) {
          throw `Do not understand how to morph style ${morphStyle}`;
        }
        return {
          target: oldNode,
          newContent,
          config: mergedConfig,
          morphStyle,
          ignoreActive: mergedConfig.ignoreActive,
          ignoreActiveValue: mergedConfig.ignoreActiveValue,
          restoreFocus: mergedConfig.restoreFocus,
          idMap,
          persistentIds,
          pantry: createPantry(),
          activeElementAndParents: createActiveElementAndParents(oldNode),
          callbacks: mergedConfig.callbacks,
          head: mergedConfig.head
        };
      }
      function mergeDefaults(config2) {
        let finalConfig = Object.assign({}, defaults);
        Object.assign(finalConfig, config2);
        finalConfig.callbacks = Object.assign(
          {},
          defaults.callbacks,
          config2.callbacks
        );
        finalConfig.head = Object.assign({}, defaults.head, config2.head);
        return finalConfig;
      }
      function createPantry() {
        const pantry = document.createElement("div");
        pantry.hidden = true;
        document.body.insertAdjacentElement("afterend", pantry);
        return pantry;
      }
      function createActiveElementAndParents(oldNode) {
        let activeElementAndParents = [];
        let elt = document.activeElement;
        if ((elt == null ? void 0 : elt.tagName) !== "BODY" && oldNode.contains(elt)) {
          while (elt) {
            activeElementAndParents.push(elt);
            if (elt === oldNode) break;
            elt = elt.parentElement;
          }
        }
        return activeElementAndParents;
      }
      function findIdElements(root) {
        var _a;
        let elements = Array.from(root.querySelectorAll("[id]"));
        if ((_a = root.getAttribute) == null ? void 0 : _a.call(root, "id")) {
          elements.push(root);
        }
        return elements;
      }
      function populateIdMapWithTree(idMap, persistentIds, root, elements) {
        for (const elt of elements) {
          const id = (
            /** @type {String} */
            elt.getAttribute("id")
          );
          if (persistentIds.has(id)) {
            let current = elt;
            while (current) {
              let idSet = idMap.get(current);
              if (idSet == null) {
                idSet = /* @__PURE__ */ new Set();
                idMap.set(current, idSet);
              }
              idSet.add(id);
              if (current === root) break;
              current = current.parentElement;
            }
          }
        }
      }
      function createIdMaps(oldContent, newContent) {
        const oldIdElements = findIdElements(oldContent);
        const newIdElements = findIdElements(newContent);
        const persistentIds = createPersistentIds(oldIdElements, newIdElements);
        let idMap = /* @__PURE__ */ new Map();
        populateIdMapWithTree(idMap, persistentIds, oldContent, oldIdElements);
        const newRoot = newContent.__idiomorphRoot || newContent;
        populateIdMapWithTree(idMap, persistentIds, newRoot, newIdElements);
        return { persistentIds, idMap };
      }
      function createPersistentIds(oldIdElements, newIdElements) {
        let duplicateIds = /* @__PURE__ */ new Set();
        let oldIdTagNameMap = /* @__PURE__ */ new Map();
        for (const { id, tagName } of oldIdElements) {
          if (oldIdTagNameMap.has(id)) {
            duplicateIds.add(id);
          } else {
            oldIdTagNameMap.set(id, tagName);
          }
        }
        let persistentIds = /* @__PURE__ */ new Set();
        for (const { id, tagName } of newIdElements) {
          if (persistentIds.has(id)) {
            duplicateIds.add(id);
          } else if (oldIdTagNameMap.get(id) === tagName) {
            persistentIds.add(id);
          }
        }
        for (const id of duplicateIds) {
          persistentIds.delete(id);
        }
        return persistentIds;
      }
      return createMorphContext2;
    }();
    const { normalizeElement, normalizeParent } = /* @__PURE__ */ function() {
      const generatedByIdiomorph = /* @__PURE__ */ new WeakSet();
      function normalizeElement2(content) {
        if (content instanceof Document) {
          return content.documentElement;
        } else {
          return content;
        }
      }
      function normalizeParent2(newContent) {
        if (newContent == null) {
          return document.createElement("div");
        } else if (typeof newContent === "string") {
          return normalizeParent2(parseContent(newContent));
        } else if (generatedByIdiomorph.has(
          /** @type {Element} */
          newContent
        )) {
          return (
            /** @type {Element} */
            newContent
          );
        } else if (newContent instanceof Node) {
          if (newContent.parentNode) {
            return (
              /** @type {any} */
              new SlicedParentNode(newContent)
            );
          } else {
            const dummyParent = document.createElement("div");
            dummyParent.append(newContent);
            return dummyParent;
          }
        } else {
          const dummyParent = document.createElement("div");
          for (const elt of [...newContent]) {
            dummyParent.append(elt);
          }
          return dummyParent;
        }
      }
      class SlicedParentNode {
        /** @param {Node} node */
        constructor(node) {
          this.originalNode = node;
          this.realParentNode = /** @type {Element} */
          node.parentNode;
          this.previousSibling = node.previousSibling;
          this.nextSibling = node.nextSibling;
        }
        /** @returns {Node[]} */
        get childNodes() {
          const nodes = [];
          let cursor = this.previousSibling ? this.previousSibling.nextSibling : this.realParentNode.firstChild;
          while (cursor && cursor != this.nextSibling) {
            nodes.push(cursor);
            cursor = cursor.nextSibling;
          }
          return nodes;
        }
        /**
         * @param {string} selector
         * @returns {Element[]}
         */
        querySelectorAll(selector) {
          return this.childNodes.reduce(
            (results, node) => {
              if (node instanceof Element) {
                if (node.matches(selector)) results.push(node);
                const nodeList = node.querySelectorAll(selector);
                for (let i = 0; i < nodeList.length; i++) {
                  results.push(nodeList[i]);
                }
              }
              return results;
            },
            /** @type {Element[]} */
            []
          );
        }
        /**
         * @param {Node} node
         * @param {Node} referenceNode
         * @returns {Node}
         */
        insertBefore(node, referenceNode) {
          return this.realParentNode.insertBefore(node, referenceNode);
        }
        /**
         * @param {Node} node
         * @param {Node} referenceNode
         * @returns {Node}
         */
        moveBefore(node, referenceNode) {
          return this.realParentNode.moveBefore(node, referenceNode);
        }
        /**
         * for later use with populateIdMapWithTree to halt upwards iteration
         * @returns {Node}
         */
        get __idiomorphRoot() {
          return this.originalNode;
        }
      }
      function parseContent(newContent) {
        let parser = new DOMParser();
        let contentWithSvgsRemoved = newContent.replace(
          /<svg(\s[^>]*>|>)([\s\S]*?)<\/svg>/gim,
          ""
        );
        if (contentWithSvgsRemoved.match(/<\/html>/) || contentWithSvgsRemoved.match(/<\/head>/) || contentWithSvgsRemoved.match(/<\/body>/)) {
          let content = parser.parseFromString(newContent, "text/html");
          if (contentWithSvgsRemoved.match(/<\/html>/)) {
            generatedByIdiomorph.add(content);
            return content;
          } else {
            let htmlElement = content.firstChild;
            if (htmlElement) {
              generatedByIdiomorph.add(htmlElement);
            }
            return htmlElement;
          }
        } else {
          let responseDoc = parser.parseFromString(
            "<body><template>" + newContent + "</template></body>",
            "text/html"
          );
          let content = (
            /** @type {HTMLTemplateElement} */
            responseDoc.body.querySelector("template").content
          );
          generatedByIdiomorph.add(content);
          return content;
        }
      }
      return { normalizeElement: normalizeElement2, normalizeParent: normalizeParent2 };
    }();
    return {
      morph,
      defaults
    };
  }();

  // src/core/morphing.js
  function morphElements(currentElement, newElement, _a = {}) {
    var _b = _a, { callbacks } = _b, options = __objRest(_b, ["callbacks"]);
    Idiomorph.morph(currentElement, newElement, __spreadProps(__spreadValues({}, options), {
      callbacks: new DefaultIdiomorphCallbacks(callbacks)
    }));
  }
  function morphChildren(currentElement, newElement, options = {}) {
    morphElements(currentElement, newElement.childNodes, __spreadProps(__spreadValues({}, options), {
      morphStyle: "innerHTML"
    }));
  }
  function shouldRefreshFrameWithMorphing(currentFrame, newFrame) {
    return currentFrame instanceof FrameElement && currentFrame.shouldReloadWithMorph && (!newFrame || areFramesCompatibleForRefreshing(currentFrame, newFrame)) && !currentFrame.closest("[data-turbo-permanent]");
  }
  function areFramesCompatibleForRefreshing(currentFrame, newFrame) {
    return newFrame instanceof Element && newFrame.nodeName === "TURBO-FRAME" && currentFrame.id === newFrame.id && (!newFrame.getAttribute("src") || urlsAreEqual(currentFrame.src, newFrame.getAttribute("src")));
  }
  function closestFrameReloadableWithMorphing(node) {
    return node.parentElement.closest("turbo-frame[src][refresh=morph]");
  }
  var _beforeNodeMorphed;
  var DefaultIdiomorphCallbacks = class {
    constructor({ beforeNodeMorphed } = {}) {
      __privateAdd(this, _beforeNodeMorphed);
      __publicField(this, "beforeNodeAdded", (node) => {
        return !(node.id && node.hasAttribute("data-turbo-permanent") && document.getElementById(node.id));
      });
      __publicField(this, "beforeNodeMorphed", (currentElement, newElement) => {
        if (currentElement instanceof Element) {
          if (!currentElement.hasAttribute("data-turbo-permanent") && __privateGet(this, _beforeNodeMorphed).call(this, currentElement, newElement)) {
            const event = dispatch("turbo:before-morph-element", {
              cancelable: true,
              target: currentElement,
              detail: { currentElement, newElement }
            });
            return !event.defaultPrevented;
          } else {
            return false;
          }
        }
      });
      __publicField(this, "beforeAttributeUpdated", (attributeName, target, mutationType) => {
        const event = dispatch("turbo:before-morph-attribute", {
          cancelable: true,
          target,
          detail: { attributeName, mutationType }
        });
        return !event.defaultPrevented;
      });
      __publicField(this, "beforeNodeRemoved", (node) => {
        return this.beforeNodeMorphed(node);
      });
      __publicField(this, "afterNodeMorphed", (currentElement, newElement) => {
        if (currentElement instanceof Element) {
          dispatch("turbo:morph-element", {
            target: currentElement,
            detail: { currentElement, newElement }
          });
        }
      });
      __privateSet(this, _beforeNodeMorphed, beforeNodeMorphed || (() => true));
    }
  };
  _beforeNodeMorphed = new WeakMap();

  // src/core/frames/morphing_frame_renderer.js
  var MorphingFrameRenderer = class extends FrameRenderer {
    static renderElement(currentElement, newElement) {
      dispatch("turbo:before-frame-morph", {
        target: currentElement,
        detail: { currentElement, newElement }
      });
      morphChildren(currentElement, newElement, {
        callbacks: {
          beforeNodeMorphed: (node, newNode) => {
            if (shouldRefreshFrameWithMorphing(node, newNode) && closestFrameReloadableWithMorphing(node) === currentElement) {
              node.reload();
              return false;
            }
            return true;
          }
        }
      });
    }
    async preservingPermanentElements(callback) {
      return await callback();
    }
  };

  // src/core/index.js
  var core_exports = {};
  __export(core_exports, {
    FrameRenderer: () => FrameRenderer,
    PageRenderer: () => PageRenderer,
    PageSnapshot: () => PageSnapshot,
    cache: () => cache,
    config: () => config,
    connectStreamSource: () => connectStreamSource,
    disconnectStreamSource: () => disconnectStreamSource,
    fetch: () => fetchWithTurboHeaders,
    morphBodyElements: () => morphBodyElements,
    morphChildren: () => morphChildren,
    morphElements: () => morphElements,
    morphTurboFrameElements: () => morphTurboFrameElements,
    navigator: () => sessionNavigator,
    registerAdapter: () => registerAdapter,
    renderStreamMessage: () => renderStreamMessage,
    session: () => session,
    setConfirmMethod: () => setConfirmMethod,
    setFormMode: () => setFormMode,
    setProgressBarDelay: () => setProgressBarDelay,
    start: () => start,
    visit: () => visit
  });

  // src/core/drive/progress_bar.js
  var _ProgressBar = class _ProgressBar {
    constructor() {
      __publicField(this, "hiding", false);
      __publicField(this, "value", 0);
      __publicField(this, "visible", false);
      __publicField(this, "trickle", () => {
        this.setValue(this.value + Math.random() / 100);
      });
      this.stylesheetElement = this.createStylesheetElement();
      this.progressElement = this.createProgressElement();
      this.installStylesheetElement();
      this.setValue(0);
    }
    /*ms*/
    static get defaultCSS() {
      return unindent`
      .turbo-progress-bar {
        position: fixed;
        display: block;
        top: 0;
        left: 0;
        height: 3px;
        background: #0076ff;
        z-index: 2147483647;
        transition:
          width ${_ProgressBar.animationDuration}ms ease-out,
          opacity ${_ProgressBar.animationDuration / 2}ms ${_ProgressBar.animationDuration / 2}ms ease-in;
        transform: translate3d(0, 0, 0);
      }
    `;
    }
    show() {
      if (!this.visible) {
        this.visible = true;
        this.installProgressElement();
        this.startTrickling();
      }
    }
    hide() {
      if (this.visible && !this.hiding) {
        this.hiding = true;
        this.fadeProgressElement(() => {
          this.uninstallProgressElement();
          this.stopTrickling();
          this.visible = false;
          this.hiding = false;
        });
      }
    }
    setValue(value) {
      this.value = value;
      this.refresh();
    }
    // Private
    installStylesheetElement() {
      document.head.insertBefore(this.stylesheetElement, document.head.firstChild);
    }
    installProgressElement() {
      this.progressElement.style.width = "0";
      this.progressElement.style.opacity = "1";
      document.documentElement.insertBefore(this.progressElement, document.body);
      this.refresh();
    }
    fadeProgressElement(callback) {
      this.progressElement.style.opacity = "0";
      setTimeout(callback, _ProgressBar.animationDuration * 1.5);
    }
    uninstallProgressElement() {
      if (this.progressElement.parentNode) {
        document.documentElement.removeChild(this.progressElement);
      }
    }
    startTrickling() {
      if (!this.trickleInterval) {
        this.trickleInterval = window.setInterval(this.trickle, _ProgressBar.animationDuration);
      }
    }
    stopTrickling() {
      window.clearInterval(this.trickleInterval);
      delete this.trickleInterval;
    }
    refresh() {
      requestAnimationFrame(() => {
        this.progressElement.style.width = `${10 + this.value * 90}%`;
      });
    }
    createStylesheetElement() {
      const element = document.createElement("style");
      element.type = "text/css";
      element.textContent = _ProgressBar.defaultCSS;
      const cspNonce = getCspNonce();
      if (cspNonce) {
        element.nonce = cspNonce;
      }
      return element;
    }
    createProgressElement() {
      const element = document.createElement("div");
      element.className = "turbo-progress-bar";
      return element;
    }
  };
  __publicField(_ProgressBar, "animationDuration", 300);
  var ProgressBar = _ProgressBar;

  // src/core/drive/head_snapshot.js
  var HeadSnapshot = class extends Snapshot {
    constructor() {
      super(...arguments);
      __publicField(this, "detailsByOuterHTML", this.children.filter((element) => !elementIsNoscript(element)).map((element) => elementWithoutNonce(element)).reduce((result, element) => {
        const { outerHTML } = element;
        const details = outerHTML in result ? result[outerHTML] : {
          type: elementType(element),
          tracked: elementIsTracked(element),
          elements: []
        };
        return __spreadProps(__spreadValues({}, result), {
          [outerHTML]: __spreadProps(__spreadValues({}, details), {
            elements: [...details.elements, element]
          })
        });
      }, {}));
    }
    get trackedElementSignature() {
      return Object.keys(this.detailsByOuterHTML).filter((outerHTML) => this.detailsByOuterHTML[outerHTML].tracked).join("");
    }
    getScriptElementsNotInSnapshot(snapshot) {
      return this.getElementsMatchingTypeNotInSnapshot("script", snapshot);
    }
    getStylesheetElementsNotInSnapshot(snapshot) {
      return this.getElementsMatchingTypeNotInSnapshot("stylesheet", snapshot);
    }
    getElementsMatchingTypeNotInSnapshot(matchedType, snapshot) {
      return Object.keys(this.detailsByOuterHTML).filter((outerHTML) => !(outerHTML in snapshot.detailsByOuterHTML)).map((outerHTML) => this.detailsByOuterHTML[outerHTML]).filter(({ type }) => type == matchedType).map(({ elements: [element] }) => element);
    }
    get provisionalElements() {
      return Object.keys(this.detailsByOuterHTML).reduce((result, outerHTML) => {
        const { type, tracked, elements } = this.detailsByOuterHTML[outerHTML];
        if (type == null && !tracked) {
          return [...result, ...elements];
        } else if (elements.length > 1) {
          return [...result, ...elements.slice(1)];
        } else {
          return result;
        }
      }, []);
    }
    getMetaValue(name) {
      const element = this.findMetaElementByName(name);
      return element ? element.getAttribute("content") : null;
    }
    findMetaElementByName(name) {
      return Object.keys(this.detailsByOuterHTML).reduce((result, outerHTML) => {
        const {
          elements: [element]
        } = this.detailsByOuterHTML[outerHTML];
        return elementIsMetaElementWithName(element, name) ? element : result;
      }, void 0 | void 0);
    }
  };
  function elementType(element) {
    if (elementIsScript(element)) {
      return "script";
    } else if (elementIsStylesheet(element)) {
      return "stylesheet";
    }
  }
  function elementIsTracked(element) {
    return element.getAttribute("data-turbo-track") == "reload";
  }
  function elementIsScript(element) {
    const tagName = element.localName;
    return tagName == "script";
  }
  function elementIsNoscript(element) {
    const tagName = element.localName;
    return tagName == "noscript";
  }
  function elementIsStylesheet(element) {
    const tagName = element.localName;
    return tagName == "style" || tagName == "link" && element.getAttribute("rel") == "stylesheet";
  }
  function elementIsMetaElementWithName(element, name) {
    const tagName = element.localName;
    return tagName == "meta" && element.getAttribute("name") == name;
  }
  function elementWithoutNonce(element) {
    if (element.hasAttribute("nonce")) {
      element.setAttribute("nonce", "");
    }
    return element;
  }

  // src/core/drive/page_snapshot.js
  var PageSnapshot = class _PageSnapshot extends Snapshot {
    static fromHTMLString(html = "") {
      return this.fromDocument(parseHTMLDocument(html));
    }
    static fromElement(element) {
      return this.fromDocument(element.ownerDocument);
    }
    static fromDocument({ documentElement, body, head }) {
      return new this(documentElement, body, new HeadSnapshot(head));
    }
    constructor(documentElement, body, headSnapshot) {
      super(body);
      this.documentElement = documentElement;
      this.headSnapshot = headSnapshot;
    }
    clone() {
      const clonedElement = this.element.cloneNode(true);
      const selectElements = this.element.querySelectorAll("select");
      const clonedSelectElements = clonedElement.querySelectorAll("select");
      for (const [index, source] of selectElements.entries()) {
        const clone = clonedSelectElements[index];
        for (const option of clone.selectedOptions) option.selected = false;
        for (const option of source.selectedOptions) clone.options[option.index].selected = true;
      }
      for (const clonedPasswordInput of clonedElement.querySelectorAll('input[type="password"]')) {
        clonedPasswordInput.value = "";
      }
      for (const clonedNoscriptElement of clonedElement.querySelectorAll("noscript")) {
        clonedNoscriptElement.remove();
      }
      return new _PageSnapshot(this.documentElement, clonedElement, this.headSnapshot);
    }
    get lang() {
      return this.documentElement.getAttribute("lang");
    }
    get dir() {
      return this.documentElement.getAttribute("dir");
    }
    get headElement() {
      return this.headSnapshot.element;
    }
    get rootLocation() {
      var _a;
      const root = (_a = this.getSetting("root")) != null ? _a : "/";
      return expandURL(root);
    }
    get cacheControlValue() {
      return this.getSetting("cache-control");
    }
    get isPreviewable() {
      return this.cacheControlValue != "no-preview";
    }
    get isCacheable() {
      return this.cacheControlValue != "no-cache";
    }
    get isVisitable() {
      return this.getSetting("visit-control") != "reload";
    }
    get prefersViewTransitions() {
      const viewTransitionEnabled = this.getSetting("view-transition") === "true" || this.headSnapshot.getMetaValue("view-transition") === "same-origin";
      return viewTransitionEnabled && !window.matchMedia("(prefers-reduced-motion: reduce)").matches;
    }
    get refreshMethod() {
      return this.getSetting("refresh-method");
    }
    get refreshScroll() {
      return this.getSetting("refresh-scroll");
    }
    // Private
    getSetting(name) {
      return this.headSnapshot.getMetaValue(`turbo-${name}`);
    }
  };

  // src/core/drive/view_transitioner.js
  var _viewTransitionStarted, _lastOperation;
  var ViewTransitioner = class {
    constructor() {
      __privateAdd(this, _viewTransitionStarted, false);
      __privateAdd(this, _lastOperation, Promise.resolve());
    }
    renderChange(useViewTransition, render) {
      if (useViewTransition && this.viewTransitionsAvailable && !__privateGet(this, _viewTransitionStarted)) {
        __privateSet(this, _viewTransitionStarted, true);
        __privateSet(this, _lastOperation, __privateGet(this, _lastOperation).then(async () => {
          await document.startViewTransition(render).finished;
        }));
      } else {
        __privateSet(this, _lastOperation, __privateGet(this, _lastOperation).then(render));
      }
      return __privateGet(this, _lastOperation);
    }
    get viewTransitionsAvailable() {
      return document.startViewTransition;
    }
  };
  _viewTransitionStarted = new WeakMap();
  _lastOperation = new WeakMap();

  // src/core/drive/visit.js
  var defaultOptions = {
    action: "advance",
    historyChanged: false,
    visitCachedSnapshot: () => {
    },
    willRender: true,
    updateHistory: true,
    shouldCacheSnapshot: true,
    acceptsStreamResponse: false,
    refresh: {}
  };
  var TimingMetric = {
    visitStart: "visitStart",
    requestStart: "requestStart",
    requestEnd: "requestEnd",
    visitEnd: "visitEnd"
  };
  var VisitState = {
    initialized: "initialized",
    started: "started",
    canceled: "canceled",
    failed: "failed",
    completed: "completed"
  };
  var SystemStatusCode = {
    networkFailure: 0,
    timeoutFailure: -1,
    contentTypeMismatch: -2
  };
  var Direction = {
    advance: "forward",
    restore: "back",
    replace: "none"
  };
  var Visit = class {
    constructor(delegate, location2, restorationIdentifier, options = {}) {
      __publicField(this, "identifier", uuid());
      // Required by turbo-ios
      __publicField(this, "timingMetrics", {});
      __publicField(this, "followedRedirect", false);
      __publicField(this, "historyChanged", false);
      __publicField(this, "scrolled", false);
      __publicField(this, "shouldCacheSnapshot", true);
      __publicField(this, "acceptsStreamResponse", false);
      __publicField(this, "snapshotCached", false);
      __publicField(this, "state", VisitState.initialized);
      __publicField(this, "viewTransitioner", new ViewTransitioner());
      this.delegate = delegate;
      this.location = location2;
      this.restorationIdentifier = restorationIdentifier || uuid();
      const {
        action,
        historyChanged,
        referrer,
        snapshot,
        snapshotHTML,
        response,
        visitCachedSnapshot,
        willRender,
        updateHistory,
        shouldCacheSnapshot,
        acceptsStreamResponse,
        direction,
        refresh
      } = __spreadValues(__spreadValues({}, defaultOptions), options);
      this.action = action;
      this.historyChanged = historyChanged;
      this.referrer = referrer;
      this.snapshot = snapshot;
      this.snapshotHTML = snapshotHTML;
      this.response = response;
      this.isPageRefresh = this.view.isPageRefresh(this);
      this.visitCachedSnapshot = visitCachedSnapshot;
      this.willRender = willRender;
      this.updateHistory = updateHistory;
      this.scrolled = !willRender;
      this.shouldCacheSnapshot = shouldCacheSnapshot;
      this.acceptsStreamResponse = acceptsStreamResponse;
      this.direction = direction || Direction[action];
      this.refresh = refresh;
    }
    get adapter() {
      return this.delegate.adapter;
    }
    get view() {
      return this.delegate.view;
    }
    get history() {
      return this.delegate.history;
    }
    get restorationData() {
      return this.history.getRestorationDataForIdentifier(this.restorationIdentifier);
    }
    start() {
      if (this.state == VisitState.initialized) {
        this.recordTimingMetric(TimingMetric.visitStart);
        this.state = VisitState.started;
        this.adapter.visitStarted(this);
        this.delegate.visitStarted(this);
      }
    }
    cancel() {
      if (this.state == VisitState.started) {
        if (this.request) {
          this.request.cancel();
        }
        this.cancelRender();
        this.state = VisitState.canceled;
      }
    }
    complete() {
      if (this.state == VisitState.started) {
        this.recordTimingMetric(TimingMetric.visitEnd);
        this.adapter.visitCompleted(this);
        this.state = VisitState.completed;
        this.followRedirect();
        if (!this.followedRedirect) {
          this.delegate.visitCompleted(this);
        }
      }
    }
    fail() {
      if (this.state == VisitState.started) {
        this.state = VisitState.failed;
        this.adapter.visitFailed(this);
        this.delegate.visitCompleted(this);
      }
    }
    changeHistory() {
      var _a;
      if (!this.historyChanged && this.updateHistory) {
        const actionForHistory = this.location.href === ((_a = this.referrer) == null ? void 0 : _a.href) ? "replace" : this.action;
        const method = getHistoryMethodForAction(actionForHistory);
        this.history.update(method, this.location, this.restorationIdentifier);
        this.historyChanged = true;
      }
    }
    issueRequest() {
      if (this.hasPreloadedResponse()) {
        this.simulateRequest();
      } else if (this.shouldIssueRequest() && !this.request) {
        this.request = new FetchRequest(this, FetchMethod.get, this.location);
        this.request.perform();
      }
    }
    simulateRequest() {
      if (this.response) {
        this.startRequest();
        this.recordResponse();
        this.finishRequest();
      }
    }
    startRequest() {
      this.recordTimingMetric(TimingMetric.requestStart);
      this.adapter.visitRequestStarted(this);
    }
    recordResponse(response = this.response) {
      this.response = response;
      if (response) {
        const { statusCode } = response;
        if (isSuccessful(statusCode)) {
          this.adapter.visitRequestCompleted(this);
        } else {
          this.adapter.visitRequestFailedWithStatusCode(this, statusCode);
        }
      }
    }
    finishRequest() {
      this.recordTimingMetric(TimingMetric.requestEnd);
      this.adapter.visitRequestFinished(this);
    }
    loadResponse() {
      if (this.response) {
        const { statusCode, responseHTML } = this.response;
        this.render(async () => {
          if (this.shouldCacheSnapshot) this.cacheSnapshot();
          if (this.view.renderPromise) await this.view.renderPromise;
          if (isSuccessful(statusCode) && responseHTML != null) {
            const snapshot = PageSnapshot.fromHTMLString(responseHTML);
            await this.renderPageSnapshot(snapshot, false);
            this.adapter.visitRendered(this);
            this.complete();
          } else {
            await this.view.renderError(PageSnapshot.fromHTMLString(responseHTML), this);
            this.adapter.visitRendered(this);
            this.fail();
          }
        });
      }
    }
    getCachedSnapshot() {
      const snapshot = this.view.getCachedSnapshotForLocation(this.location) || this.getPreloadedSnapshot();
      if (snapshot && (!getAnchor(this.location) || snapshot.hasAnchor(getAnchor(this.location)))) {
        if (this.action == "restore" || snapshot.isPreviewable) {
          return snapshot;
        }
      }
    }
    getPreloadedSnapshot() {
      if (this.snapshotHTML) {
        return PageSnapshot.fromHTMLString(this.snapshotHTML);
      }
    }
    hasCachedSnapshot() {
      return this.getCachedSnapshot() != null;
    }
    loadCachedSnapshot() {
      const snapshot = this.getCachedSnapshot();
      if (snapshot) {
        const isPreview = this.shouldIssueRequest();
        this.render(async () => {
          this.cacheSnapshot();
          if (this.isPageRefresh) {
            this.adapter.visitRendered(this);
          } else {
            if (this.view.renderPromise) await this.view.renderPromise;
            await this.renderPageSnapshot(snapshot, isPreview);
            this.adapter.visitRendered(this);
            if (!isPreview) {
              this.complete();
            }
          }
        });
      }
    }
    followRedirect() {
      var _a;
      if (this.redirectedToLocation && !this.followedRedirect && ((_a = this.response) == null ? void 0 : _a.redirected)) {
        this.adapter.visitProposedToLocation(this.redirectedToLocation, {
          action: "replace",
          response: this.response,
          shouldCacheSnapshot: false,
          willRender: false
        });
        this.followedRedirect = true;
      }
    }
    // Fetch request delegate
    prepareRequest(request) {
      if (this.acceptsStreamResponse) {
        request.acceptResponseType(StreamMessage.contentType);
      }
    }
    requestStarted() {
      this.startRequest();
    }
    requestPreventedHandlingResponse(_request, _response) {
    }
    async requestSucceededWithResponse(request, response) {
      const responseHTML = await response.responseHTML;
      const { redirected, statusCode } = response;
      if (responseHTML == void 0) {
        this.recordResponse({
          statusCode: SystemStatusCode.contentTypeMismatch,
          redirected
        });
      } else {
        this.redirectedToLocation = response.redirected ? response.location : void 0;
        this.recordResponse({ statusCode, responseHTML, redirected });
      }
    }
    async requestFailedWithResponse(request, response) {
      const responseHTML = await response.responseHTML;
      const { redirected, statusCode } = response;
      if (responseHTML == void 0) {
        this.recordResponse({
          statusCode: SystemStatusCode.contentTypeMismatch,
          redirected
        });
      } else {
        this.recordResponse({ statusCode, responseHTML, redirected });
      }
    }
    requestErrored(_request, _error) {
      this.recordResponse({
        statusCode: SystemStatusCode.networkFailure,
        redirected: false
      });
    }
    requestFinished() {
      this.finishRequest();
    }
    // Scrolling
    performScroll() {
      if (!this.scrolled && !this.view.forceReloaded && !this.view.shouldPreserveScrollPosition(this)) {
        if (this.action == "restore") {
          this.scrollToRestoredPosition() || this.scrollToAnchor() || this.view.scrollToTop();
        } else {
          this.scrollToAnchor() || this.view.scrollToTop();
        }
        this.scrolled = true;
      }
    }
    scrollToRestoredPosition() {
      const { scrollPosition } = this.restorationData;
      if (scrollPosition) {
        this.view.scrollToPosition(scrollPosition);
        return true;
      }
    }
    scrollToAnchor() {
      const anchor = getAnchor(this.location);
      if (anchor != null) {
        this.view.scrollToAnchor(anchor);
        return true;
      }
    }
    // Instrumentation
    recordTimingMetric(metric) {
      this.timingMetrics[metric] = (/* @__PURE__ */ new Date()).getTime();
    }
    getTimingMetrics() {
      return __spreadValues({}, this.timingMetrics);
    }
    // Private
    hasPreloadedResponse() {
      return typeof this.response == "object";
    }
    shouldIssueRequest() {
      if (this.action == "restore") {
        return !this.hasCachedSnapshot();
      } else {
        return this.willRender;
      }
    }
    cacheSnapshot() {
      if (!this.snapshotCached) {
        this.view.cacheSnapshot(this.snapshot).then((snapshot) => snapshot && this.visitCachedSnapshot(snapshot));
        this.snapshotCached = true;
      }
    }
    async render(callback) {
      this.cancelRender();
      await new Promise((resolve) => {
        this.frame = document.visibilityState === "hidden" ? setTimeout(() => resolve(), 0) : requestAnimationFrame(() => resolve());
      });
      await callback();
      delete this.frame;
    }
    async renderPageSnapshot(snapshot, isPreview) {
      await this.viewTransitioner.renderChange(this.view.shouldTransitionTo(snapshot), async () => {
        await this.view.renderPage(snapshot, isPreview, this.willRender, this);
        this.performScroll();
      });
    }
    cancelRender() {
      if (this.frame) {
        cancelAnimationFrame(this.frame);
        delete this.frame;
      }
    }
  };
  function isSuccessful(statusCode) {
    return statusCode >= 200 && statusCode < 300;
  }

  // src/core/native/browser_adapter.js
  var BrowserAdapter = class {
    constructor(session2) {
      __publicField(this, "progressBar", new ProgressBar());
      __publicField(this, "showProgressBar", () => {
        this.progressBar.show();
      });
      this.session = session2;
    }
    visitProposedToLocation(location2, options) {
      if (locationIsVisitable(location2, this.navigator.rootLocation)) {
        this.navigator.startVisit(location2, (options == null ? void 0 : options.restorationIdentifier) || uuid(), options);
      } else {
        window.location.href = location2.toString();
      }
    }
    visitStarted(visit2) {
      this.location = visit2.location;
      this.redirectedToLocation = null;
      visit2.loadCachedSnapshot();
      visit2.issueRequest();
    }
    visitRequestStarted(visit2) {
      this.progressBar.setValue(0);
      if (visit2.hasCachedSnapshot() || visit2.action != "restore") {
        this.showVisitProgressBarAfterDelay();
      } else {
        this.showProgressBar();
      }
    }
    visitRequestCompleted(visit2) {
      visit2.loadResponse();
      if (visit2.response.redirected) {
        this.redirectedToLocation = visit2.redirectedToLocation;
      }
    }
    visitRequestFailedWithStatusCode(visit2, statusCode) {
      switch (statusCode) {
        case SystemStatusCode.networkFailure:
        case SystemStatusCode.timeoutFailure:
        case SystemStatusCode.contentTypeMismatch:
          return this.reload({
            reason: "request_failed",
            context: {
              statusCode
            }
          });
        default:
          return visit2.loadResponse();
      }
    }
    visitRequestFinished(_visit) {
    }
    visitCompleted(_visit) {
      this.progressBar.setValue(1);
      this.hideVisitProgressBar();
    }
    pageInvalidated(reason) {
      this.reload(reason);
    }
    visitFailed(_visit) {
      this.progressBar.setValue(1);
      this.hideVisitProgressBar();
    }
    visitRendered(_visit) {
    }
    // Link prefetching
    linkPrefetchingIsEnabledForLocation(location2) {
      return true;
    }
    // Form Submission Delegate
    formSubmissionStarted(_formSubmission) {
      this.progressBar.setValue(0);
      this.showFormProgressBarAfterDelay();
    }
    formSubmissionFinished(_formSubmission) {
      this.progressBar.setValue(1);
      this.hideFormProgressBar();
    }
    // Private
    showVisitProgressBarAfterDelay() {
      this.visitProgressBarTimeout = window.setTimeout(this.showProgressBar, this.session.progressBarDelay);
    }
    hideVisitProgressBar() {
      this.progressBar.hide();
      if (this.visitProgressBarTimeout != null) {
        window.clearTimeout(this.visitProgressBarTimeout);
        delete this.visitProgressBarTimeout;
      }
    }
    showFormProgressBarAfterDelay() {
      if (this.formProgressBarTimeout == null) {
        this.formProgressBarTimeout = window.setTimeout(this.showProgressBar, this.session.progressBarDelay);
      }
    }
    hideFormProgressBar() {
      this.progressBar.hide();
      if (this.formProgressBarTimeout != null) {
        window.clearTimeout(this.formProgressBarTimeout);
        delete this.formProgressBarTimeout;
      }
    }
    reload(reason) {
      var _a;
      dispatch("turbo:reload", { detail: reason });
      window.location.href = ((_a = this.redirectedToLocation || this.location) == null ? void 0 : _a.toString()) || window.location.href;
    }
    get navigator() {
      return this.session.navigator;
    }
  };

  // src/observers/cache_observer.js
  var CacheObserver = class {
    constructor() {
      __publicField(this, "selector", "[data-turbo-temporary]");
      __publicField(this, "started", false);
      __publicField(this, "removeTemporaryElements", (_event) => {
        for (const element of this.temporaryElements) {
          element.remove();
        }
      });
    }
    start() {
      if (!this.started) {
        this.started = true;
        addEventListener("turbo:before-cache", this.removeTemporaryElements, false);
      }
    }
    stop() {
      if (this.started) {
        this.started = false;
        removeEventListener("turbo:before-cache", this.removeTemporaryElements, false);
      }
    }
    get temporaryElements() {
      return [...document.querySelectorAll(this.selector)];
    }
  };

  // src/core/frames/frame_redirector.js
  var _FrameRedirector_instances, shouldSubmit_fn, shouldRedirect_fn, findFrameElement_fn;
  var FrameRedirector = class {
    constructor(session2, element) {
      __privateAdd(this, _FrameRedirector_instances);
      this.session = session2;
      this.element = element;
      this.linkInterceptor = new LinkInterceptor(this, element);
      this.formSubmitObserver = new FormSubmitObserver(this, element);
    }
    start() {
      this.linkInterceptor.start();
      this.formSubmitObserver.start();
    }
    stop() {
      this.linkInterceptor.stop();
      this.formSubmitObserver.stop();
    }
    // Link interceptor delegate
    shouldInterceptLinkClick(element, _location, _event) {
      return __privateMethod(this, _FrameRedirector_instances, shouldRedirect_fn).call(this, element);
    }
    linkClickIntercepted(element, url, event) {
      const frame = __privateMethod(this, _FrameRedirector_instances, findFrameElement_fn).call(this, element);
      if (frame) {
        frame.delegate.linkClickIntercepted(element, url, event);
      }
    }
    // Form submit observer delegate
    willSubmitForm(element, submitter2) {
      return element.closest("turbo-frame") == null && __privateMethod(this, _FrameRedirector_instances, shouldSubmit_fn).call(this, element, submitter2) && __privateMethod(this, _FrameRedirector_instances, shouldRedirect_fn).call(this, element, submitter2);
    }
    formSubmitted(element, submitter2) {
      const frame = __privateMethod(this, _FrameRedirector_instances, findFrameElement_fn).call(this, element, submitter2);
      if (frame) {
        frame.delegate.formSubmitted(element, submitter2);
      }
    }
  };
  _FrameRedirector_instances = new WeakSet();
  shouldSubmit_fn = function(form, submitter2) {
    var _a;
    const action = getAction(form, submitter2);
    const meta = this.element.ownerDocument.querySelector(`meta[name="turbo-root"]`);
    const rootLocation = expandURL((_a = meta == null ? void 0 : meta.content) != null ? _a : "/");
    return __privateMethod(this, _FrameRedirector_instances, shouldRedirect_fn).call(this, form, submitter2) && locationIsVisitable(action, rootLocation);
  };
  shouldRedirect_fn = function(element, submitter2) {
    const isNavigatable = element instanceof HTMLFormElement ? this.session.submissionIsNavigatable(element, submitter2) : this.session.elementIsNavigatable(element);
    if (isNavigatable) {
      const frame = __privateMethod(this, _FrameRedirector_instances, findFrameElement_fn).call(this, element, submitter2);
      return frame ? frame != element.closest("turbo-frame") : false;
    } else {
      return false;
    }
  };
  findFrameElement_fn = function(element, submitter2) {
    const id = (submitter2 == null ? void 0 : submitter2.getAttribute("data-turbo-frame")) || element.getAttribute("data-turbo-frame");
    if (id && id != "_top") {
      const frame = this.element.querySelector(`#${id}:not([disabled])`);
      if (frame instanceof FrameElement) {
        return frame;
      }
    }
  };

  // src/core/drive/history.js
  var History = class {
    constructor(delegate) {
      __publicField(this, "location");
      __publicField(this, "restorationIdentifier", uuid());
      __publicField(this, "restorationData", {});
      __publicField(this, "started", false);
      __publicField(this, "currentIndex", 0);
      // Event handlers
      __publicField(this, "onPopState", (event) => {
        const { turbo } = event.state || {};
        this.location = new URL(window.location.href);
        if (turbo) {
          const { restorationIdentifier, restorationIndex } = turbo;
          this.restorationIdentifier = restorationIdentifier;
          const direction = restorationIndex > this.currentIndex ? "forward" : "back";
          this.delegate.historyPoppedToLocationWithRestorationIdentifierAndDirection(this.location, restorationIdentifier, direction);
          this.currentIndex = restorationIndex;
        } else {
          this.currentIndex++;
          this.delegate.historyPoppedWithEmptyState(this.location);
        }
      });
      this.delegate = delegate;
    }
    start() {
      var _a, _b;
      if (!this.started) {
        addEventListener("popstate", this.onPopState, false);
        this.currentIndex = ((_b = (_a = history.state) == null ? void 0 : _a.turbo) == null ? void 0 : _b.restorationIndex) || 0;
        this.started = true;
        this.replace(new URL(window.location.href));
      }
    }
    stop() {
      if (this.started) {
        removeEventListener("popstate", this.onPopState, false);
        this.started = false;
      }
    }
    push(location2, restorationIdentifier) {
      this.update(history.pushState, location2, restorationIdentifier);
    }
    replace(location2, restorationIdentifier) {
      this.update(history.replaceState, location2, restorationIdentifier);
    }
    update(method, location2, restorationIdentifier = uuid()) {
      if (method === history.pushState) ++this.currentIndex;
      const state = { turbo: { restorationIdentifier, restorationIndex: this.currentIndex } };
      method.call(history, state, "", location2.href);
      this.location = location2;
      this.restorationIdentifier = restorationIdentifier;
    }
    // Restoration data
    getRestorationDataForIdentifier(restorationIdentifier) {
      return this.restorationData[restorationIdentifier] || {};
    }
    updateRestorationData(additionalData) {
      const { restorationIdentifier } = this;
      const restorationData = this.restorationData[restorationIdentifier];
      this.restorationData[restorationIdentifier] = __spreadValues(__spreadValues({}, restorationData), additionalData);
    }
    // Scroll restoration
    assumeControlOfScrollRestoration() {
      var _a;
      if (!this.previousScrollRestoration) {
        this.previousScrollRestoration = (_a = history.scrollRestoration) != null ? _a : "auto";
        history.scrollRestoration = "manual";
      }
    }
    relinquishControlOfScrollRestoration() {
      if (this.previousScrollRestoration) {
        history.scrollRestoration = this.previousScrollRestoration;
        delete this.previousScrollRestoration;
      }
    }
  };

  // src/observers/link_prefetch_observer.js
  var _prefetchedLink, _enable, _tryToPrefetchRequest, _cancelRequestIfObsolete, _cancelPrefetchRequest, _tryToUsePrefetchedRequest, _LinkPrefetchObserver_instances, cacheTtl_get, isPrefetchable_fn;
  var LinkPrefetchObserver = class {
    constructor(delegate, eventTarget) {
      __privateAdd(this, _LinkPrefetchObserver_instances);
      __publicField(this, "started", false);
      __privateAdd(this, _prefetchedLink, null);
      __privateAdd(this, _enable, () => {
        this.eventTarget.addEventListener("mouseenter", __privateGet(this, _tryToPrefetchRequest), {
          capture: true,
          passive: true
        });
        this.eventTarget.addEventListener("mouseleave", __privateGet(this, _cancelRequestIfObsolete), {
          capture: true,
          passive: true
        });
        this.eventTarget.addEventListener("turbo:before-fetch-request", __privateGet(this, _tryToUsePrefetchedRequest), true);
        this.started = true;
      });
      __privateAdd(this, _tryToPrefetchRequest, (event) => {
        if (getMetaContent("turbo-prefetch") === "false") return;
        const target = event.target;
        const isLink = target.matches && target.matches("a[href]:not([target^=_]):not([download])");
        if (isLink && __privateMethod(this, _LinkPrefetchObserver_instances, isPrefetchable_fn).call(this, target)) {
          const link = target;
          const location2 = getLocationForLink(link);
          if (this.delegate.canPrefetchRequestToLocation(link, location2)) {
            __privateSet(this, _prefetchedLink, link);
            const fetchRequest = new FetchRequest(
              this,
              FetchMethod.get,
              location2,
              new URLSearchParams(),
              target
            );
            fetchRequest.fetchOptions.priority = "low";
            prefetchCache.putLater(location2, fetchRequest, __privateGet(this, _LinkPrefetchObserver_instances, cacheTtl_get));
          }
        }
      });
      __privateAdd(this, _cancelRequestIfObsolete, (event) => {
        if (event.target === __privateGet(this, _prefetchedLink)) __privateGet(this, _cancelPrefetchRequest).call(this);
      });
      __privateAdd(this, _cancelPrefetchRequest, () => {
        prefetchCache.clear();
        __privateSet(this, _prefetchedLink, null);
      });
      __privateAdd(this, _tryToUsePrefetchedRequest, (event) => {
        if (event.target.tagName !== "FORM" && event.detail.fetchOptions.method === "GET") {
          const cached = prefetchCache.get(event.detail.url);
          if (cached) {
            event.detail.fetchRequest = cached;
          }
          prefetchCache.clear();
        }
      });
      this.delegate = delegate;
      this.eventTarget = eventTarget;
    }
    start() {
      if (this.started) return;
      if (this.eventTarget.readyState === "loading") {
        this.eventTarget.addEventListener("DOMContentLoaded", __privateGet(this, _enable), { once: true });
      } else {
        __privateGet(this, _enable).call(this);
      }
    }
    stop() {
      if (!this.started) return;
      this.eventTarget.removeEventListener("mouseenter", __privateGet(this, _tryToPrefetchRequest), {
        capture: true,
        passive: true
      });
      this.eventTarget.removeEventListener("mouseleave", __privateGet(this, _cancelRequestIfObsolete), {
        capture: true,
        passive: true
      });
      this.eventTarget.removeEventListener("turbo:before-fetch-request", __privateGet(this, _tryToUsePrefetchedRequest), true);
      this.started = false;
    }
    prepareRequest(request) {
      const link = request.target;
      request.headers["X-Sec-Purpose"] = "prefetch";
      const turboFrame = link.closest("turbo-frame");
      const turboFrameTarget = link.getAttribute("data-turbo-frame") || (turboFrame == null ? void 0 : turboFrame.getAttribute("target")) || (turboFrame == null ? void 0 : turboFrame.id);
      if (turboFrameTarget && turboFrameTarget !== "_top") {
        request.headers["Turbo-Frame"] = turboFrameTarget;
      }
    }
    // Fetch request interface
    requestSucceededWithResponse() {
    }
    requestStarted(fetchRequest) {
    }
    requestErrored(fetchRequest) {
    }
    requestFinished(fetchRequest) {
    }
    requestPreventedHandlingResponse(fetchRequest, fetchResponse) {
    }
    requestFailedWithResponse(fetchRequest, fetchResponse) {
    }
  };
  _prefetchedLink = new WeakMap();
  _enable = new WeakMap();
  _tryToPrefetchRequest = new WeakMap();
  _cancelRequestIfObsolete = new WeakMap();
  _cancelPrefetchRequest = new WeakMap();
  _tryToUsePrefetchedRequest = new WeakMap();
  _LinkPrefetchObserver_instances = new WeakSet();
  cacheTtl_get = function() {
    return Number(getMetaContent("turbo-prefetch-cache-time")) || cacheTtl;
  };
  isPrefetchable_fn = function(link) {
    const href = link.getAttribute("href");
    if (!href) return false;
    if (unfetchableLink(link)) return false;
    if (linkToTheSamePage(link)) return false;
    if (linkOptsOut(link)) return false;
    if (nonSafeLink(link)) return false;
    if (eventPrevented(link)) return false;
    return true;
  };
  var unfetchableLink = (link) => {
    return link.origin !== document.location.origin || !["http:", "https:"].includes(link.protocol) || link.hasAttribute("target");
  };
  var linkToTheSamePage = (link) => {
    return link.pathname + link.search === document.location.pathname + document.location.search || link.href.startsWith("#");
  };
  var linkOptsOut = (link) => {
    if (link.getAttribute("data-turbo-prefetch") === "false") return true;
    if (link.getAttribute("data-turbo") === "false") return true;
    const turboPrefetchParent = findClosestRecursively(link, "[data-turbo-prefetch]");
    if (turboPrefetchParent && turboPrefetchParent.getAttribute("data-turbo-prefetch") === "false") return true;
    return false;
  };
  var nonSafeLink = (link) => {
    const turboMethod = link.getAttribute("data-turbo-method");
    if (turboMethod && turboMethod.toLowerCase() !== "get") return true;
    if (isUJS(link)) return true;
    if (link.hasAttribute("data-turbo-confirm")) return true;
    if (link.hasAttribute("data-turbo-stream")) return true;
    return false;
  };
  var isUJS = (link) => {
    return link.hasAttribute("data-remote") || link.hasAttribute("data-behavior") || link.hasAttribute("data-confirm") || link.hasAttribute("data-method");
  };
  var eventPrevented = (link) => {
    const event = dispatch("turbo:before-prefetch", { target: link, cancelable: true });
    return event.defaultPrevented;
  };

  // src/core/drive/navigator.js
  var _Navigator_instances, getActionForFormSubmission_fn, getDefaultAction_fn;
  var Navigator = class {
    constructor(delegate) {
      __privateAdd(this, _Navigator_instances);
      this.delegate = delegate;
    }
    proposeVisit(location2, options = {}) {
      if (this.delegate.allowsVisitingLocationWithAction(location2, options.action)) {
        this.delegate.visitProposedToLocation(location2, options);
      }
    }
    startVisit(locatable, restorationIdentifier, options = {}) {
      this.stop();
      this.currentVisit = new Visit(this, expandURL(locatable), restorationIdentifier, __spreadValues({
        referrer: this.location
      }, options));
      this.currentVisit.start();
    }
    submitForm(form, submitter2) {
      this.stop();
      this.formSubmission = new FormSubmission(this, form, submitter2, true);
      this.formSubmission.start();
    }
    stop() {
      if (this.formSubmission) {
        this.formSubmission.stop();
        delete this.formSubmission;
      }
      if (this.currentVisit) {
        this.currentVisit.cancel();
        delete this.currentVisit;
      }
    }
    get adapter() {
      return this.delegate.adapter;
    }
    get view() {
      return this.delegate.view;
    }
    get rootLocation() {
      return this.view.snapshot.rootLocation;
    }
    get history() {
      return this.delegate.history;
    }
    // Form submission delegate
    formSubmissionStarted(formSubmission) {
      if (typeof this.adapter.formSubmissionStarted === "function") {
        this.adapter.formSubmissionStarted(formSubmission);
      }
    }
    async formSubmissionSucceededWithResponse(formSubmission, fetchResponse) {
      if (formSubmission == this.formSubmission) {
        const responseHTML = await fetchResponse.responseHTML;
        if (responseHTML) {
          const shouldCacheSnapshot = formSubmission.isSafe;
          if (!shouldCacheSnapshot) {
            this.view.clearSnapshotCache();
          }
          const { statusCode, redirected } = fetchResponse;
          const action = __privateMethod(this, _Navigator_instances, getActionForFormSubmission_fn).call(this, formSubmission, fetchResponse);
          const visitOptions = {
            action,
            shouldCacheSnapshot,
            response: { statusCode, responseHTML, redirected }
          };
          this.proposeVisit(fetchResponse.location, visitOptions);
        }
      }
    }
    async formSubmissionFailedWithResponse(formSubmission, fetchResponse) {
      const responseHTML = await fetchResponse.responseHTML;
      if (responseHTML) {
        const snapshot = PageSnapshot.fromHTMLString(responseHTML);
        if (fetchResponse.serverError) {
          await this.view.renderError(snapshot, this.currentVisit);
        } else {
          await this.view.renderPage(snapshot, false, true, this.currentVisit);
        }
        if (snapshot.refreshScroll !== "preserve") {
          this.view.scrollToTop();
        }
        this.view.clearSnapshotCache();
      }
    }
    formSubmissionErrored(formSubmission, error) {
      console.error(error);
    }
    formSubmissionFinished(formSubmission) {
      if (typeof this.adapter.formSubmissionFinished === "function") {
        this.adapter.formSubmissionFinished(formSubmission);
      }
    }
    // Link prefetching
    linkPrefetchingIsEnabledForLocation(location2) {
      if (typeof this.adapter.linkPrefetchingIsEnabledForLocation === "function") {
        return this.adapter.linkPrefetchingIsEnabledForLocation(location2);
      }
      return true;
    }
    // Visit delegate
    visitStarted(visit2) {
      this.delegate.visitStarted(visit2);
    }
    visitCompleted(visit2) {
      this.delegate.visitCompleted(visit2);
      delete this.currentVisit;
    }
    // Same-page links are no longer handled with a Visit.
    // This method is still needed for Turbo Native adapters.
    locationWithActionIsSamePage(location2, action) {
      return false;
    }
    // Visits
    get location() {
      return this.history.location;
    }
    get restorationIdentifier() {
      return this.history.restorationIdentifier;
    }
  };
  _Navigator_instances = new WeakSet();
  getActionForFormSubmission_fn = function(formSubmission, fetchResponse) {
    const { submitter: submitter2, formElement } = formSubmission;
    return getVisitAction(submitter2, formElement) || __privateMethod(this, _Navigator_instances, getDefaultAction_fn).call(this, fetchResponse);
  };
  getDefaultAction_fn = function(fetchResponse) {
    var _a;
    const sameLocationRedirect = fetchResponse.redirected && fetchResponse.location.href === ((_a = this.location) == null ? void 0 : _a.href);
    return sameLocationRedirect ? "replace" : "advance";
  };

  // src/observers/page_observer.js
  var PageStage = {
    initial: 0,
    loading: 1,
    interactive: 2,
    complete: 3
  };
  var PageObserver = class {
    constructor(delegate) {
      __publicField(this, "stage", PageStage.initial);
      __publicField(this, "started", false);
      __publicField(this, "interpretReadyState", () => {
        const { readyState } = this;
        if (readyState == "interactive") {
          this.pageIsInteractive();
        } else if (readyState == "complete") {
          this.pageIsComplete();
        }
      });
      __publicField(this, "pageWillUnload", () => {
        this.delegate.pageWillUnload();
      });
      this.delegate = delegate;
    }
    start() {
      if (!this.started) {
        if (this.stage == PageStage.initial) {
          this.stage = PageStage.loading;
        }
        document.addEventListener("readystatechange", this.interpretReadyState, false);
        addEventListener("pagehide", this.pageWillUnload, false);
        this.started = true;
      }
    }
    stop() {
      if (this.started) {
        document.removeEventListener("readystatechange", this.interpretReadyState, false);
        removeEventListener("pagehide", this.pageWillUnload, false);
        this.started = false;
      }
    }
    pageIsInteractive() {
      if (this.stage == PageStage.loading) {
        this.stage = PageStage.interactive;
        this.delegate.pageBecameInteractive();
      }
    }
    pageIsComplete() {
      this.pageIsInteractive();
      if (this.stage == PageStage.interactive) {
        this.stage = PageStage.complete;
        this.delegate.pageLoaded();
      }
    }
    get readyState() {
      return document.readyState;
    }
  };

  // src/observers/scroll_observer.js
  var ScrollObserver = class {
    constructor(delegate) {
      __publicField(this, "started", false);
      __publicField(this, "onScroll", () => {
        this.updatePosition({ x: window.pageXOffset, y: window.pageYOffset });
      });
      this.delegate = delegate;
    }
    start() {
      if (!this.started) {
        addEventListener("scroll", this.onScroll, false);
        this.onScroll();
        this.started = true;
      }
    }
    stop() {
      if (this.started) {
        removeEventListener("scroll", this.onScroll, false);
        this.started = false;
      }
    }
    // Private
    updatePosition(position) {
      this.delegate.scrollPositionChanged(position);
    }
  };

  // src/core/streams/stream_message_renderer.js
  var StreamMessageRenderer = class {
    render({ fragment }) {
      Bardo.preservingPermanentElements(this, getPermanentElementMapForFragment(fragment), () => {
        withAutofocusFromFragment(fragment, () => {
          withPreservedFocus(() => {
            document.documentElement.appendChild(fragment);
          });
        });
      });
    }
    // Bardo delegate
    enteringBardo(currentPermanentElement, newPermanentElement) {
      newPermanentElement.replaceWith(currentPermanentElement.cloneNode(true));
    }
    leavingBardo() {
    }
  };
  function getPermanentElementMapForFragment(fragment) {
    const permanentElementsInDocument = queryPermanentElementsAll(document.documentElement);
    const permanentElementMap = {};
    for (const permanentElementInDocument of permanentElementsInDocument) {
      const { id } = permanentElementInDocument;
      for (const streamElement of fragment.querySelectorAll("turbo-stream")) {
        const elementInStream = getPermanentElementById(streamElement.templateElement.content, id);
        if (elementInStream) {
          permanentElementMap[id] = [permanentElementInDocument, elementInStream];
        }
      }
    }
    return permanentElementMap;
  }
  async function withAutofocusFromFragment(fragment, callback) {
    const generatedID = `turbo-stream-autofocus-${uuid()}`;
    const turboStreams = fragment.querySelectorAll("turbo-stream");
    const elementWithAutofocus = firstAutofocusableElementInStreams(turboStreams);
    let willAutofocusId = null;
    if (elementWithAutofocus) {
      if (elementWithAutofocus.id) {
        willAutofocusId = elementWithAutofocus.id;
      } else {
        willAutofocusId = generatedID;
      }
      elementWithAutofocus.id = willAutofocusId;
    }
    callback();
    await nextRepaint();
    const hasNoActiveElement = document.activeElement == null || document.activeElement == document.body;
    if (hasNoActiveElement && willAutofocusId) {
      const elementToAutofocus = document.getElementById(willAutofocusId);
      if (elementIsFocusable(elementToAutofocus)) {
        elementToAutofocus.focus();
      }
      if (elementToAutofocus && elementToAutofocus.id == generatedID) {
        elementToAutofocus.removeAttribute("id");
      }
    }
  }
  async function withPreservedFocus(callback) {
    const [activeElementBeforeRender, activeElementAfterRender] = await around(callback, () => document.activeElement);
    const restoreFocusTo = activeElementBeforeRender && activeElementBeforeRender.id;
    if (restoreFocusTo) {
      const elementToFocus = document.getElementById(restoreFocusTo);
      if (elementIsFocusable(elementToFocus) && elementToFocus != activeElementAfterRender) {
        elementToFocus.focus();
      }
    }
  }
  function firstAutofocusableElementInStreams(nodeListOfStreamElements) {
    for (const streamElement of nodeListOfStreamElements) {
      const elementWithAutofocus = queryAutofocusableElement(streamElement.templateElement.content);
      if (elementWithAutofocus) return elementWithAutofocus;
    }
    return null;
  }

  // src/observers/stream_observer.js
  var _started;
  var StreamObserver = class {
    constructor(delegate) {
      __publicField(this, "sources", /* @__PURE__ */ new Set());
      __privateAdd(this, _started, false);
      __publicField(this, "inspectFetchResponse", (event) => {
        const response = fetchResponseFromEvent(event);
        if (response && fetchResponseIsStream(response)) {
          event.preventDefault();
          this.receiveMessageResponse(response);
        }
      });
      __publicField(this, "receiveMessageEvent", (event) => {
        if (__privateGet(this, _started) && typeof event.data == "string") {
          this.receiveMessageHTML(event.data);
        }
      });
      this.delegate = delegate;
    }
    start() {
      if (!__privateGet(this, _started)) {
        __privateSet(this, _started, true);
        addEventListener("turbo:before-fetch-response", this.inspectFetchResponse, false);
      }
    }
    stop() {
      if (__privateGet(this, _started)) {
        __privateSet(this, _started, false);
        removeEventListener("turbo:before-fetch-response", this.inspectFetchResponse, false);
      }
    }
    connectStreamSource(source) {
      if (!this.streamSourceIsConnected(source)) {
        this.sources.add(source);
        source.addEventListener("message", this.receiveMessageEvent, false);
      }
    }
    disconnectStreamSource(source) {
      if (this.streamSourceIsConnected(source)) {
        this.sources.delete(source);
        source.removeEventListener("message", this.receiveMessageEvent, false);
      }
    }
    streamSourceIsConnected(source) {
      return this.sources.has(source);
    }
    async receiveMessageResponse(response) {
      const html = await response.responseHTML;
      if (html) {
        this.receiveMessageHTML(html);
      }
    }
    receiveMessageHTML(html) {
      this.delegate.receivedMessageFromStream(StreamMessage.wrap(html));
    }
  };
  _started = new WeakMap();
  function fetchResponseFromEvent(event) {
    var _a;
    const fetchResponse = (_a = event.detail) == null ? void 0 : _a.fetchResponse;
    if (fetchResponse instanceof FetchResponse) {
      return fetchResponse;
    }
  }
  function fetchResponseIsStream(response) {
    var _a;
    const contentType = (_a = response.contentType) != null ? _a : "";
    return contentType.startsWith(StreamMessage.contentType);
  }

  // src/core/drive/error_renderer.js
  var ErrorRenderer = class extends Renderer {
    static renderElement(currentElement, newElement) {
      const { documentElement, body } = document;
      documentElement.replaceChild(newElement, body);
    }
    async render() {
      this.replaceHeadAndBody();
      this.activateScriptElements();
    }
    replaceHeadAndBody() {
      const { documentElement, head } = document;
      documentElement.replaceChild(this.newHead, head);
      this.renderElement(this.currentElement, this.newElement);
    }
    activateScriptElements() {
      for (const replaceableElement of this.scriptElements) {
        const parentNode = replaceableElement.parentNode;
        if (parentNode) {
          const element = activateScriptElement(replaceableElement);
          parentNode.replaceChild(element, replaceableElement);
        }
      }
    }
    get newHead() {
      return this.newSnapshot.headSnapshot.element;
    }
    get scriptElements() {
      return document.documentElement.querySelectorAll("script");
    }
  };

  // src/core/drive/page_renderer.js
  var _PageRenderer_instances, setLanguage_fn;
  var PageRenderer = class extends Renderer {
    constructor() {
      super(...arguments);
      __privateAdd(this, _PageRenderer_instances);
    }
    static renderElement(currentElement, newElement) {
      if (document.body && newElement instanceof HTMLBodyElement) {
        document.body.replaceWith(newElement);
      } else {
        document.documentElement.appendChild(newElement);
      }
    }
    get shouldRender() {
      return this.newSnapshot.isVisitable && this.trackedElementsAreIdentical;
    }
    get reloadReason() {
      if (!this.newSnapshot.isVisitable) {
        return {
          reason: "turbo_visit_control_is_reload"
        };
      }
      if (!this.trackedElementsAreIdentical) {
        return {
          reason: "tracked_element_mismatch"
        };
      }
    }
    async prepareToRender() {
      __privateMethod(this, _PageRenderer_instances, setLanguage_fn).call(this);
      await this.mergeHead();
    }
    async render() {
      if (this.willRender) {
        await this.replaceBody();
      }
    }
    finishRendering() {
      super.finishRendering();
      if (!this.isPreview) {
        this.focusFirstAutofocusableElement();
      }
    }
    get currentHeadSnapshot() {
      return this.currentSnapshot.headSnapshot;
    }
    get newHeadSnapshot() {
      return this.newSnapshot.headSnapshot;
    }
    get newElement() {
      return this.newSnapshot.element;
    }
    async mergeHead() {
      const mergedHeadElements = this.mergeProvisionalElements();
      const newStylesheetElements = this.copyNewHeadStylesheetElements();
      this.copyNewHeadScriptElements();
      await mergedHeadElements;
      await newStylesheetElements;
      if (this.willRender) {
        this.removeUnusedDynamicStylesheetElements();
      }
    }
    async replaceBody() {
      await this.preservingPermanentElements(async () => {
        this.activateNewBody();
        await this.assignNewBody();
      });
    }
    get trackedElementsAreIdentical() {
      return this.currentHeadSnapshot.trackedElementSignature == this.newHeadSnapshot.trackedElementSignature;
    }
    async copyNewHeadStylesheetElements() {
      const loadingElements = [];
      for (const element of this.newHeadStylesheetElements) {
        loadingElements.push(waitForLoad(element));
        document.head.appendChild(element);
      }
      await Promise.all(loadingElements);
    }
    copyNewHeadScriptElements() {
      for (const element of this.newHeadScriptElements) {
        document.head.appendChild(activateScriptElement(element));
      }
    }
    removeUnusedDynamicStylesheetElements() {
      for (const element of this.unusedDynamicStylesheetElements) {
        document.head.removeChild(element);
      }
    }
    async mergeProvisionalElements() {
      const newHeadElements = [...this.newHeadProvisionalElements];
      for (const element of this.currentHeadProvisionalElements) {
        if (!this.isCurrentElementInElementList(element, newHeadElements)) {
          document.head.removeChild(element);
        }
      }
      for (const element of newHeadElements) {
        document.head.appendChild(element);
      }
    }
    isCurrentElementInElementList(element, elementList) {
      for (const [index, newElement] of elementList.entries()) {
        if (element.tagName == "TITLE") {
          if (newElement.tagName != "TITLE") {
            continue;
          }
          if (element.innerHTML == newElement.innerHTML) {
            elementList.splice(index, 1);
            return true;
          }
        }
        if (newElement.isEqualNode(element)) {
          elementList.splice(index, 1);
          return true;
        }
      }
      return false;
    }
    removeCurrentHeadProvisionalElements() {
      for (const element of this.currentHeadProvisionalElements) {
        document.head.removeChild(element);
      }
    }
    copyNewHeadProvisionalElements() {
      for (const element of this.newHeadProvisionalElements) {
        document.head.appendChild(element);
      }
    }
    activateNewBody() {
      document.adoptNode(this.newElement);
      this.removeNoscriptElements();
      this.activateNewBodyScriptElements();
    }
    removeNoscriptElements() {
      for (const noscriptElement of this.newElement.querySelectorAll("noscript")) {
        noscriptElement.remove();
      }
    }
    activateNewBodyScriptElements() {
      for (const inertScriptElement of this.newBodyScriptElements) {
        const activatedScriptElement = activateScriptElement(inertScriptElement);
        inertScriptElement.replaceWith(activatedScriptElement);
      }
    }
    async assignNewBody() {
      await this.renderElement(this.currentElement, this.newElement);
    }
    get unusedDynamicStylesheetElements() {
      return this.oldHeadStylesheetElements.filter((element) => {
        return element.getAttribute("data-turbo-track") === "dynamic";
      });
    }
    get oldHeadStylesheetElements() {
      return this.currentHeadSnapshot.getStylesheetElementsNotInSnapshot(this.newHeadSnapshot);
    }
    get newHeadStylesheetElements() {
      return this.newHeadSnapshot.getStylesheetElementsNotInSnapshot(this.currentHeadSnapshot);
    }
    get newHeadScriptElements() {
      return this.newHeadSnapshot.getScriptElementsNotInSnapshot(this.currentHeadSnapshot);
    }
    get currentHeadProvisionalElements() {
      return this.currentHeadSnapshot.provisionalElements;
    }
    get newHeadProvisionalElements() {
      return this.newHeadSnapshot.provisionalElements;
    }
    get newBodyScriptElements() {
      return this.newElement.querySelectorAll("script");
    }
  };
  _PageRenderer_instances = new WeakSet();
  setLanguage_fn = function() {
    const { documentElement } = this.currentSnapshot;
    const { dir, lang } = this.newSnapshot;
    if (lang) {
      documentElement.setAttribute("lang", lang);
    } else {
      documentElement.removeAttribute("lang");
    }
    if (dir) {
      documentElement.setAttribute("dir", dir);
    } else {
      documentElement.removeAttribute("dir");
    }
  };

  // src/core/drive/morphing_page_renderer.js
  var MorphingPageRenderer = class extends PageRenderer {
    static renderElement(currentElement, newElement) {
      morphElements(currentElement, newElement, {
        callbacks: {
          beforeNodeMorphed: (node, newNode) => {
            if (shouldRefreshFrameWithMorphing(node, newNode) && !closestFrameReloadableWithMorphing(node)) {
              node.reload();
              return false;
            }
            return true;
          }
        }
      });
      dispatch("turbo:morph", { detail: { currentElement, newElement } });
    }
    async preservingPermanentElements(callback) {
      return await callback();
    }
    get renderMethod() {
      return "morph";
    }
    get shouldAutofocus() {
      return false;
    }
  };

  // src/core/drive/snapshot_cache.js
  var SnapshotCache = class extends LRUCache {
    constructor(size) {
      super(size, toCacheKey);
    }
    get snapshots() {
      return this.entries;
    }
  };

  // src/core/drive/page_view.js
  var PageView = class extends View {
    constructor() {
      super(...arguments);
      __publicField(this, "snapshotCache", new SnapshotCache(10));
      __publicField(this, "lastRenderedLocation", new URL(location.href));
      __publicField(this, "forceReloaded", false);
    }
    shouldTransitionTo(newSnapshot) {
      return this.snapshot.prefersViewTransitions && newSnapshot.prefersViewTransitions;
    }
    renderPage(snapshot, isPreview = false, willRender = true, visit2) {
      var _a;
      const shouldMorphPage = this.isPageRefresh(visit2) && (((_a = visit2 == null ? void 0 : visit2.refresh) == null ? void 0 : _a.method) || this.snapshot.refreshMethod) === "morph";
      const rendererClass = shouldMorphPage ? MorphingPageRenderer : PageRenderer;
      const renderer = new rendererClass(this.snapshot, snapshot, isPreview, willRender);
      if (!renderer.shouldRender) {
        this.forceReloaded = true;
      } else {
        visit2 == null ? void 0 : visit2.changeHistory();
      }
      return this.render(renderer);
    }
    renderError(snapshot, visit2) {
      visit2 == null ? void 0 : visit2.changeHistory();
      const renderer = new ErrorRenderer(this.snapshot, snapshot, false);
      return this.render(renderer);
    }
    clearSnapshotCache() {
      this.snapshotCache.clear();
    }
    async cacheSnapshot(snapshot = this.snapshot) {
      if (snapshot.isCacheable) {
        this.delegate.viewWillCacheSnapshot();
        const { lastRenderedLocation: location2 } = this;
        await nextEventLoopTick();
        const cachedSnapshot = snapshot.clone();
        this.snapshotCache.put(location2, cachedSnapshot);
        return cachedSnapshot;
      }
    }
    getCachedSnapshotForLocation(location2) {
      return this.snapshotCache.get(location2);
    }
    isPageRefresh(visit2) {
      return !visit2 || this.lastRenderedLocation.pathname === visit2.location.pathname && visit2.action === "replace";
    }
    shouldPreserveScrollPosition(visit2) {
      var _a;
      return this.isPageRefresh(visit2) && (((_a = visit2 == null ? void 0 : visit2.refresh) == null ? void 0 : _a.scroll) || this.snapshot.refreshScroll) === "preserve";
    }
    get snapshot() {
      return PageSnapshot.fromElement(this.element);
    }
  };

  // src/core/drive/preloader.js
  var _preloadAll;
  var Preloader = class {
    constructor(delegate, snapshotCache) {
      __publicField(this, "selector", "a[data-turbo-preload]");
      __privateAdd(this, _preloadAll, () => {
        this.preloadOnLoadLinksForView(document.body);
      });
      this.delegate = delegate;
      this.snapshotCache = snapshotCache;
    }
    start() {
      if (document.readyState === "loading") {
        document.addEventListener("DOMContentLoaded", __privateGet(this, _preloadAll));
      } else {
        this.preloadOnLoadLinksForView(document.body);
      }
    }
    stop() {
      document.removeEventListener("DOMContentLoaded", __privateGet(this, _preloadAll));
    }
    preloadOnLoadLinksForView(element) {
      for (const link of element.querySelectorAll(this.selector)) {
        if (this.delegate.shouldPreloadLink(link)) {
          this.preloadURL(link);
        }
      }
    }
    async preloadURL(link) {
      const location2 = new URL(link.href);
      if (this.snapshotCache.has(location2)) {
        return;
      }
      const fetchRequest = new FetchRequest(this, FetchMethod.get, location2, new URLSearchParams(), link);
      await fetchRequest.perform();
    }
    // Fetch request delegate
    prepareRequest(fetchRequest) {
      fetchRequest.headers["X-Sec-Purpose"] = "prefetch";
    }
    async requestSucceededWithResponse(fetchRequest, fetchResponse) {
      try {
        const responseHTML = await fetchResponse.responseHTML;
        const snapshot = PageSnapshot.fromHTMLString(responseHTML);
        this.snapshotCache.put(fetchRequest.url, snapshot);
      } catch (_) {
      }
    }
    requestStarted(fetchRequest) {
    }
    requestErrored(fetchRequest) {
    }
    requestFinished(fetchRequest) {
    }
    requestPreventedHandlingResponse(fetchRequest, fetchResponse) {
    }
    requestFailedWithResponse(fetchRequest, fetchResponse) {
    }
  };
  _preloadAll = new WeakMap();

  // src/core/cache.js
  var _Cache_instances, setCacheControl_fn;
  var Cache = class {
    constructor(session2) {
      __privateAdd(this, _Cache_instances);
      this.session = session2;
    }
    clear() {
      this.session.clearCache();
    }
    resetCacheControl() {
      __privateMethod(this, _Cache_instances, setCacheControl_fn).call(this, "");
    }
    exemptPageFromCache() {
      __privateMethod(this, _Cache_instances, setCacheControl_fn).call(this, "no-cache");
    }
    exemptPageFromPreview() {
      __privateMethod(this, _Cache_instances, setCacheControl_fn).call(this, "no-preview");
    }
  };
  _Cache_instances = new WeakSet();
  setCacheControl_fn = function(value) {
    setMetaContent("turbo-cache-control", value);
  };

  // src/core/session.js
  var _pageRefreshDebouncePeriod;
  var Session = class {
    constructor(recentRequests2) {
      __publicField(this, "navigator", new Navigator(this));
      __publicField(this, "history", new History(this));
      __publicField(this, "view", new PageView(this, document.documentElement));
      __publicField(this, "adapter", new BrowserAdapter(this));
      __publicField(this, "pageObserver", new PageObserver(this));
      __publicField(this, "cacheObserver", new CacheObserver());
      __publicField(this, "linkPrefetchObserver", new LinkPrefetchObserver(this, document));
      __publicField(this, "linkClickObserver", new LinkClickObserver(this, window));
      __publicField(this, "formSubmitObserver", new FormSubmitObserver(this, document));
      __publicField(this, "scrollObserver", new ScrollObserver(this));
      __publicField(this, "streamObserver", new StreamObserver(this));
      __publicField(this, "formLinkClickObserver", new FormLinkClickObserver(this, document.documentElement));
      __publicField(this, "frameRedirector", new FrameRedirector(this, document.documentElement));
      __publicField(this, "streamMessageRenderer", new StreamMessageRenderer());
      __publicField(this, "cache", new Cache(this));
      __publicField(this, "enabled", true);
      __publicField(this, "started", false);
      __privateAdd(this, _pageRefreshDebouncePeriod, 150);
      this.recentRequests = recentRequests2;
      this.preloader = new Preloader(this, this.view.snapshotCache);
      this.debouncedRefresh = this.refresh;
      this.pageRefreshDebouncePeriod = this.pageRefreshDebouncePeriod;
    }
    start() {
      if (!this.started) {
        this.pageObserver.start();
        this.cacheObserver.start();
        this.linkPrefetchObserver.start();
        this.formLinkClickObserver.start();
        this.linkClickObserver.start();
        this.formSubmitObserver.start();
        this.scrollObserver.start();
        this.streamObserver.start();
        this.frameRedirector.start();
        this.history.start();
        this.preloader.start();
        this.started = true;
        this.enabled = true;
      }
    }
    disable() {
      this.enabled = false;
    }
    stop() {
      if (this.started) {
        this.pageObserver.stop();
        this.cacheObserver.stop();
        this.linkPrefetchObserver.stop();
        this.formLinkClickObserver.stop();
        this.linkClickObserver.stop();
        this.formSubmitObserver.stop();
        this.scrollObserver.stop();
        this.streamObserver.stop();
        this.frameRedirector.stop();
        this.history.stop();
        this.preloader.stop();
        this.started = false;
      }
    }
    registerAdapter(adapter3) {
      this.adapter = adapter3;
    }
    visit(location2, options = {}) {
      const frameElement = options.frame ? document.getElementById(options.frame) : null;
      if (frameElement instanceof FrameElement) {
        const action = options.action || getVisitAction(frameElement);
        frameElement.delegate.proposeVisitIfNavigatedWithAction(frameElement, action);
        frameElement.src = location2.toString();
      } else {
        this.navigator.proposeVisit(expandURL(location2), options);
      }
    }
    refresh(url, options = {}) {
      options = typeof options === "string" ? { requestId: options } : options;
      const { method, requestId, scroll } = options;
      const isRecentRequest = requestId && this.recentRequests.has(requestId);
      const isCurrentUrl = url === document.baseURI;
      if (!isRecentRequest && !this.navigator.currentVisit && isCurrentUrl) {
        this.visit(url, { action: "replace", shouldCacheSnapshot: false, refresh: { method, scroll } });
      }
    }
    connectStreamSource(source) {
      this.streamObserver.connectStreamSource(source);
    }
    disconnectStreamSource(source) {
      this.streamObserver.disconnectStreamSource(source);
    }
    renderStreamMessage(message) {
      this.streamMessageRenderer.render(StreamMessage.wrap(message));
    }
    clearCache() {
      this.view.clearSnapshotCache();
    }
    setProgressBarDelay(delay) {
      console.warn(
        "Please replace `session.setProgressBarDelay(delay)` with `session.progressBarDelay = delay`. The function is deprecated and will be removed in a future version of Turbo.`"
      );
      this.progressBarDelay = delay;
    }
    set progressBarDelay(delay) {
      config.drive.progressBarDelay = delay;
    }
    get progressBarDelay() {
      return config.drive.progressBarDelay;
    }
    set drive(value) {
      config.drive.enabled = value;
    }
    get drive() {
      return config.drive.enabled;
    }
    set formMode(value) {
      config.forms.mode = value;
    }
    get formMode() {
      return config.forms.mode;
    }
    get location() {
      return this.history.location;
    }
    get restorationIdentifier() {
      return this.history.restorationIdentifier;
    }
    get pageRefreshDebouncePeriod() {
      return __privateGet(this, _pageRefreshDebouncePeriod);
    }
    set pageRefreshDebouncePeriod(value) {
      this.refresh = debounce(this.debouncedRefresh.bind(this), value);
      __privateSet(this, _pageRefreshDebouncePeriod, value);
    }
    // Preloader delegate
    shouldPreloadLink(element) {
      const isUnsafe = element.hasAttribute("data-turbo-method");
      const isStream = element.hasAttribute("data-turbo-stream");
      const frameTarget = element.getAttribute("data-turbo-frame");
      const frame = frameTarget == "_top" ? null : document.getElementById(frameTarget) || findClosestRecursively(element, "turbo-frame:not([disabled])");
      if (isUnsafe || isStream || frame instanceof FrameElement) {
        return false;
      } else {
        const location2 = new URL(element.href);
        return this.elementIsNavigatable(element) && locationIsVisitable(location2, this.snapshot.rootLocation);
      }
    }
    // History delegate
    historyPoppedToLocationWithRestorationIdentifierAndDirection(location2, restorationIdentifier, direction) {
      if (this.enabled) {
        this.navigator.startVisit(location2, restorationIdentifier, {
          action: "restore",
          historyChanged: true,
          direction
        });
      } else {
        this.adapter.pageInvalidated({
          reason: "turbo_disabled"
        });
      }
    }
    historyPoppedWithEmptyState(location2) {
      this.history.replace(location2);
      this.view.lastRenderedLocation = location2;
      this.view.cacheSnapshot();
    }
    // Scroll observer delegate
    scrollPositionChanged(position) {
      this.history.updateRestorationData({ scrollPosition: position });
    }
    // Form click observer delegate
    willSubmitFormLinkToLocation(link, location2) {
      return this.elementIsNavigatable(link) && locationIsVisitable(location2, this.snapshot.rootLocation);
    }
    submittedFormLinkToLocation() {
    }
    // Link hover observer delegate
    canPrefetchRequestToLocation(link, location2) {
      return this.elementIsNavigatable(link) && locationIsVisitable(location2, this.snapshot.rootLocation) && this.navigator.linkPrefetchingIsEnabledForLocation(location2);
    }
    // Link click observer delegate
    willFollowLinkToLocation(link, location2, event) {
      return this.elementIsNavigatable(link) && locationIsVisitable(location2, this.snapshot.rootLocation) && this.applicationAllowsFollowingLinkToLocation(link, location2, event);
    }
    followedLinkToLocation(link, location2) {
      const action = this.getActionForLink(link);
      const acceptsStreamResponse = link.hasAttribute("data-turbo-stream");
      this.visit(location2.href, { action, acceptsStreamResponse });
    }
    // Navigator delegate
    allowsVisitingLocationWithAction(location2, action) {
      return this.applicationAllowsVisitingLocation(location2);
    }
    visitProposedToLocation(location2, options) {
      extendURLWithDeprecatedProperties(location2);
      this.adapter.visitProposedToLocation(location2, options);
    }
    // Visit delegate
    visitStarted(visit2) {
      if (!visit2.acceptsStreamResponse) {
        markAsBusy(document.documentElement);
        this.view.markVisitDirection(visit2.direction);
      }
      extendURLWithDeprecatedProperties(visit2.location);
      this.notifyApplicationAfterVisitingLocation(visit2.location, visit2.action);
    }
    visitCompleted(visit2) {
      this.view.unmarkVisitDirection();
      clearBusyState(document.documentElement);
      this.notifyApplicationAfterPageLoad(visit2.getTimingMetrics());
    }
    // Form submit observer delegate
    willSubmitForm(form, submitter2) {
      const action = getAction(form, submitter2);
      return this.submissionIsNavigatable(form, submitter2) && locationIsVisitable(expandURL(action), this.snapshot.rootLocation);
    }
    formSubmitted(form, submitter2) {
      this.navigator.submitForm(form, submitter2);
    }
    // Page observer delegate
    pageBecameInteractive() {
      this.view.lastRenderedLocation = this.location;
      this.notifyApplicationAfterPageLoad();
    }
    pageLoaded() {
      this.history.assumeControlOfScrollRestoration();
    }
    pageWillUnload() {
      this.history.relinquishControlOfScrollRestoration();
    }
    // Stream observer delegate
    receivedMessageFromStream(message) {
      this.renderStreamMessage(message);
    }
    // Page view delegate
    viewWillCacheSnapshot() {
      this.notifyApplicationBeforeCachingSnapshot();
    }
    allowsImmediateRender({ element }, options) {
      const event = this.notifyApplicationBeforeRender(element, options);
      const {
        defaultPrevented,
        detail: { render }
      } = event;
      if (this.view.renderer && render) {
        this.view.renderer.renderElement = render;
      }
      return !defaultPrevented;
    }
    viewRenderedSnapshot(_snapshot, _isPreview, renderMethod) {
      this.view.lastRenderedLocation = this.history.location;
      this.notifyApplicationAfterRender(renderMethod);
    }
    preloadOnLoadLinksForView(element) {
      this.preloader.preloadOnLoadLinksForView(element);
    }
    viewInvalidated(reason) {
      this.adapter.pageInvalidated(reason);
    }
    // Frame element
    frameLoaded(frame) {
      this.notifyApplicationAfterFrameLoad(frame);
    }
    frameRendered(fetchResponse, frame) {
      this.notifyApplicationAfterFrameRender(fetchResponse, frame);
    }
    // Application events
    applicationAllowsFollowingLinkToLocation(link, location2, ev) {
      const event = this.notifyApplicationAfterClickingLinkToLocation(link, location2, ev);
      return !event.defaultPrevented;
    }
    applicationAllowsVisitingLocation(location2) {
      const event = this.notifyApplicationBeforeVisitingLocation(location2);
      return !event.defaultPrevented;
    }
    notifyApplicationAfterClickingLinkToLocation(link, location2, event) {
      return dispatch("turbo:click", {
        target: link,
        detail: { url: location2.href, originalEvent: event },
        cancelable: true
      });
    }
    notifyApplicationBeforeVisitingLocation(location2) {
      return dispatch("turbo:before-visit", {
        detail: { url: location2.href },
        cancelable: true
      });
    }
    notifyApplicationAfterVisitingLocation(location2, action) {
      return dispatch("turbo:visit", { detail: { url: location2.href, action } });
    }
    notifyApplicationBeforeCachingSnapshot() {
      return dispatch("turbo:before-cache");
    }
    notifyApplicationBeforeRender(newBody, options) {
      return dispatch("turbo:before-render", {
        detail: __spreadValues({ newBody }, options),
        cancelable: true
      });
    }
    notifyApplicationAfterRender(renderMethod) {
      return dispatch("turbo:render", { detail: { renderMethod } });
    }
    notifyApplicationAfterPageLoad(timing = {}) {
      return dispatch("turbo:load", {
        detail: { url: this.location.href, timing }
      });
    }
    notifyApplicationAfterFrameLoad(frame) {
      return dispatch("turbo:frame-load", { target: frame });
    }
    notifyApplicationAfterFrameRender(fetchResponse, frame) {
      return dispatch("turbo:frame-render", {
        detail: { fetchResponse },
        target: frame,
        cancelable: true
      });
    }
    // Helpers
    submissionIsNavigatable(form, submitter2) {
      if (config.forms.mode == "off") {
        return false;
      } else {
        const submitterIsNavigatable = submitter2 ? this.elementIsNavigatable(submitter2) : true;
        if (config.forms.mode == "optin") {
          return submitterIsNavigatable && form.closest('[data-turbo="true"]') != null;
        } else {
          return submitterIsNavigatable && this.elementIsNavigatable(form);
        }
      }
    }
    elementIsNavigatable(element) {
      const container = findClosestRecursively(element, "[data-turbo]");
      const withinFrame = findClosestRecursively(element, "turbo-frame");
      if (config.drive.enabled || withinFrame) {
        if (container) {
          return container.getAttribute("data-turbo") != "false";
        } else {
          return true;
        }
      } else {
        if (container) {
          return container.getAttribute("data-turbo") == "true";
        } else {
          return false;
        }
      }
    }
    // Private
    getActionForLink(link) {
      return getVisitAction(link) || "advance";
    }
    get snapshot() {
      return this.view.snapshot;
    }
  };
  _pageRefreshDebouncePeriod = new WeakMap();
  function extendURLWithDeprecatedProperties(url) {
    Object.defineProperties(url, deprecatedLocationPropertyDescriptors);
  }
  var deprecatedLocationPropertyDescriptors = {
    absoluteURL: {
      get() {
        return this.toString();
      }
    }
  };

  // src/core/index.js
  var session = new Session(recentRequests);
  var { cache, navigator: sessionNavigator } = session;
  function start() {
    session.start();
  }
  function registerAdapter(adapter3) {
    session.registerAdapter(adapter3);
  }
  function visit(location2, options) {
    session.visit(location2, options);
  }
  function connectStreamSource(source) {
    session.connectStreamSource(source);
  }
  function disconnectStreamSource(source) {
    session.disconnectStreamSource(source);
  }
  function renderStreamMessage(message) {
    session.renderStreamMessage(message);
  }
  function setProgressBarDelay(delay) {
    console.warn(
      "Please replace `Turbo.setProgressBarDelay(delay)` with `Turbo.config.drive.progressBarDelay = delay`. The top-level function is deprecated and will be removed in a future version of Turbo.`"
    );
    config.drive.progressBarDelay = delay;
  }
  function setConfirmMethod(confirmMethod) {
    console.warn(
      "Please replace `Turbo.setConfirmMethod(confirmMethod)` with `Turbo.config.forms.confirm = confirmMethod`. The top-level function is deprecated and will be removed in a future version of Turbo.`"
    );
    config.forms.confirm = confirmMethod;
  }
  function setFormMode(mode) {
    console.warn(
      "Please replace `Turbo.setFormMode(mode)` with `Turbo.config.forms.mode = mode`. The top-level function is deprecated and will be removed in a future version of Turbo.`"
    );
    config.forms.mode = mode;
  }
  function morphBodyElements(currentBody, newBody) {
    MorphingPageRenderer.renderElement(currentBody, newBody);
  }
  function morphTurboFrameElements(currentFrame, newFrame) {
    MorphingFrameRenderer.renderElement(currentFrame, newFrame);
  }

  // src/core/errors.js
  var TurboFrameMissingError = class extends Error {
  };

  // src/core/frames/frame_controller.js
  var _currentFetchRequest, _resolveVisitPromise, _connected, _hasBeenLoaded, _ignoredAttributes, _shouldMorphFrame, _FrameController_instances, loadSourceURL_fn, loadFrameResponse_fn, visit_fn, navigateFrame_fn, handleUnvisitableFrameResponse_fn, willHandleFrameMissingFromResponse_fn, handleFrameMissingFromResponse_fn, throwFrameMissingError_fn, visitResponse_fn, findFrameElement_fn2, formActionIsVisitable_fn, shouldInterceptNavigation_fn, isIgnoringChangesTo_fn, ignoringChangesToAttribute_fn, withCurrentNavigationElement_fn, getFrameElementById_fn;
  var FrameController = class {
    constructor(element) {
      __privateAdd(this, _FrameController_instances);
      __publicField(this, "fetchResponseLoaded", (_fetchResponse) => Promise.resolve());
      __privateAdd(this, _currentFetchRequest, null);
      __privateAdd(this, _resolveVisitPromise, () => {
      });
      __privateAdd(this, _connected, false);
      __privateAdd(this, _hasBeenLoaded, false);
      __privateAdd(this, _ignoredAttributes, /* @__PURE__ */ new Set());
      __privateAdd(this, _shouldMorphFrame, false);
      __publicField(this, "action", null);
      __publicField(this, "visitCachedSnapshot", ({ element }) => {
        const frame = element.querySelector("#" + this.element.id);
        if (frame && this.previousFrameElement) {
          frame.replaceChildren(...this.previousFrameElement.children);
        }
        delete this.previousFrameElement;
      });
      this.element = element;
      this.view = new FrameView(this, this.element);
      this.appearanceObserver = new AppearanceObserver(this, this.element);
      this.formLinkClickObserver = new FormLinkClickObserver(this, this.element);
      this.linkInterceptor = new LinkInterceptor(this, this.element);
      this.restorationIdentifier = uuid();
      this.formSubmitObserver = new FormSubmitObserver(this, this.element);
    }
    // Frame delegate
    connect() {
      if (!__privateGet(this, _connected)) {
        __privateSet(this, _connected, true);
        if (this.loadingStyle == FrameLoadingStyle.lazy) {
          this.appearanceObserver.start();
        } else {
          __privateMethod(this, _FrameController_instances, loadSourceURL_fn).call(this);
        }
        this.formLinkClickObserver.start();
        this.linkInterceptor.start();
        this.formSubmitObserver.start();
      }
    }
    disconnect() {
      var _a;
      if (__privateGet(this, _connected)) {
        __privateSet(this, _connected, false);
        this.appearanceObserver.stop();
        this.formLinkClickObserver.stop();
        this.linkInterceptor.stop();
        this.formSubmitObserver.stop();
        if (!this.element.hasAttribute("recurse")) {
          (_a = __privateGet(this, _currentFetchRequest)) == null ? void 0 : _a.cancel();
        }
      }
    }
    disabledChanged() {
      var _a;
      if (this.disabled) {
        (_a = __privateGet(this, _currentFetchRequest)) == null ? void 0 : _a.cancel();
      } else if (this.loadingStyle == FrameLoadingStyle.eager) {
        __privateMethod(this, _FrameController_instances, loadSourceURL_fn).call(this);
      }
    }
    sourceURLChanged() {
      var _a;
      if (__privateMethod(this, _FrameController_instances, isIgnoringChangesTo_fn).call(this, "src")) return;
      if (!this.sourceURL) {
        (_a = __privateGet(this, _currentFetchRequest)) == null ? void 0 : _a.cancel();
      }
      if (this.element.isConnected) {
        this.complete = false;
      }
      if (this.loadingStyle == FrameLoadingStyle.eager || __privateGet(this, _hasBeenLoaded)) {
        __privateMethod(this, _FrameController_instances, loadSourceURL_fn).call(this);
      }
    }
    sourceURLReloaded() {
      const { refresh, src } = this.element;
      __privateSet(this, _shouldMorphFrame, src && refresh === "morph");
      this.element.removeAttribute("complete");
      this.element.src = null;
      this.element.src = src;
      return this.element.loaded;
    }
    loadingStyleChanged() {
      if (this.loadingStyle == FrameLoadingStyle.lazy) {
        this.appearanceObserver.start();
      } else {
        this.appearanceObserver.stop();
        __privateMethod(this, _FrameController_instances, loadSourceURL_fn).call(this);
      }
    }
    async loadResponse(fetchResponse) {
      if (fetchResponse.redirected || fetchResponse.succeeded && fetchResponse.isHTML) {
        this.sourceURL = fetchResponse.response.url;
      }
      try {
        const html = await fetchResponse.responseHTML;
        if (html) {
          const document2 = parseHTMLDocument(html);
          const pageSnapshot = PageSnapshot.fromDocument(document2);
          if (pageSnapshot.isVisitable) {
            await __privateMethod(this, _FrameController_instances, loadFrameResponse_fn).call(this, fetchResponse, document2);
          } else {
            await __privateMethod(this, _FrameController_instances, handleUnvisitableFrameResponse_fn).call(this, fetchResponse);
          }
        }
      } finally {
        __privateSet(this, _shouldMorphFrame, false);
        this.fetchResponseLoaded = () => Promise.resolve();
      }
    }
    // Appearance observer delegate
    elementAppearedInViewport(element) {
      this.proposeVisitIfNavigatedWithAction(element, getVisitAction(element));
      __privateMethod(this, _FrameController_instances, loadSourceURL_fn).call(this);
    }
    // Form link click observer delegate
    willSubmitFormLinkToLocation(link) {
      return __privateMethod(this, _FrameController_instances, shouldInterceptNavigation_fn).call(this, link);
    }
    submittedFormLinkToLocation(link, _location, form) {
      const frame = __privateMethod(this, _FrameController_instances, findFrameElement_fn2).call(this, link);
      if (frame) form.setAttribute("data-turbo-frame", frame.id);
    }
    // Link interceptor delegate
    shouldInterceptLinkClick(element, _location, _event) {
      return __privateMethod(this, _FrameController_instances, shouldInterceptNavigation_fn).call(this, element);
    }
    linkClickIntercepted(element, location2) {
      __privateMethod(this, _FrameController_instances, navigateFrame_fn).call(this, element, location2);
    }
    // Form submit observer delegate
    willSubmitForm(element, submitter2) {
      return element.closest("turbo-frame") == this.element && __privateMethod(this, _FrameController_instances, shouldInterceptNavigation_fn).call(this, element, submitter2);
    }
    formSubmitted(element, submitter2) {
      if (this.formSubmission) {
        this.formSubmission.stop();
      }
      this.formSubmission = new FormSubmission(this, element, submitter2);
      const { fetchRequest } = this.formSubmission;
      const frame = __privateMethod(this, _FrameController_instances, findFrameElement_fn2).call(this, element, submitter2);
      this.prepareRequest(fetchRequest, frame);
      this.formSubmission.start();
    }
    // Fetch request delegate
    prepareRequest(request, frame = this) {
      var _a;
      request.headers["Turbo-Frame"] = frame.id;
      if ((_a = this.currentNavigationElement) == null ? void 0 : _a.hasAttribute("data-turbo-stream")) {
        request.acceptResponseType(StreamMessage.contentType);
      }
    }
    requestStarted(_request) {
      markAsBusy(this.element);
    }
    requestPreventedHandlingResponse(_request, _response) {
      __privateGet(this, _resolveVisitPromise).call(this);
    }
    async requestSucceededWithResponse(request, response) {
      await this.loadResponse(response);
      __privateGet(this, _resolveVisitPromise).call(this);
    }
    async requestFailedWithResponse(request, response) {
      await this.loadResponse(response);
      __privateGet(this, _resolveVisitPromise).call(this);
    }
    requestErrored(request, error) {
      console.error(error);
      __privateGet(this, _resolveVisitPromise).call(this);
    }
    requestFinished(_request) {
      clearBusyState(this.element);
    }
    // Form submission delegate
    formSubmissionStarted({ formElement }) {
      markAsBusy(formElement, __privateMethod(this, _FrameController_instances, findFrameElement_fn2).call(this, formElement));
    }
    formSubmissionSucceededWithResponse(formSubmission, response) {
      const frame = __privateMethod(this, _FrameController_instances, findFrameElement_fn2).call(this, formSubmission.formElement, formSubmission.submitter);
      frame.delegate.proposeVisitIfNavigatedWithAction(frame, getVisitAction(formSubmission.submitter, formSubmission.formElement, frame));
      frame.delegate.loadResponse(response);
      if (!formSubmission.isSafe) {
        session.clearCache();
      }
    }
    formSubmissionFailedWithResponse(formSubmission, fetchResponse) {
      this.element.delegate.loadResponse(fetchResponse);
      session.clearCache();
    }
    formSubmissionErrored(formSubmission, error) {
      console.error(error);
    }
    formSubmissionFinished({ formElement }) {
      clearBusyState(formElement, __privateMethod(this, _FrameController_instances, findFrameElement_fn2).call(this, formElement));
    }
    // View delegate
    allowsImmediateRender({ element: newFrame }, options) {
      const event = dispatch("turbo:before-frame-render", {
        target: this.element,
        detail: __spreadValues({ newFrame }, options),
        cancelable: true
      });
      const {
        defaultPrevented,
        detail: { render }
      } = event;
      if (this.view.renderer && render) {
        this.view.renderer.renderElement = render;
      }
      return !defaultPrevented;
    }
    viewRenderedSnapshot(_snapshot, _isPreview, _renderMethod) {
    }
    preloadOnLoadLinksForView(element) {
      session.preloadOnLoadLinksForView(element);
    }
    viewInvalidated() {
    }
    // Frame renderer delegate
    willRenderFrame(currentElement, _newElement) {
      this.previousFrameElement = currentElement.cloneNode(true);
    }
    proposeVisitIfNavigatedWithAction(frame, action = null) {
      this.action = action;
      if (this.action) {
        const pageSnapshot = PageSnapshot.fromElement(frame).clone();
        const { visitCachedSnapshot } = frame.delegate;
        frame.delegate.fetchResponseLoaded = async (fetchResponse) => {
          if (frame.src) {
            const { statusCode, redirected } = fetchResponse;
            const responseHTML = await fetchResponse.responseHTML;
            const response = { statusCode, redirected, responseHTML };
            const options = {
              response,
              visitCachedSnapshot,
              willRender: false,
              updateHistory: false,
              restorationIdentifier: this.restorationIdentifier,
              snapshot: pageSnapshot
            };
            if (this.action) options.action = this.action;
            session.visit(frame.src, options);
          }
        };
      }
    }
    changeHistory() {
      if (this.action) {
        const method = getHistoryMethodForAction(this.action);
        session.history.update(method, expandURL(this.element.src || ""), this.restorationIdentifier);
      }
    }
    async extractForeignFrameElement(container) {
      let element;
      const id = CSS.escape(this.id);
      try {
        element = activateElement(container.querySelector(`turbo-frame#${id}`), this.sourceURL);
        if (element) {
          return element;
        }
        element = activateElement(container.querySelector(`turbo-frame[src][recurse~=${id}]`), this.sourceURL);
        if (element) {
          await element.loaded;
          return await this.extractForeignFrameElement(element);
        }
      } catch (error) {
        console.error(error);
        return new FrameElement();
      }
      return null;
    }
    // Computed properties
    get id() {
      return this.element.id;
    }
    get disabled() {
      return this.element.disabled;
    }
    get enabled() {
      return !this.disabled;
    }
    get sourceURL() {
      if (this.element.src) {
        return this.element.src;
      }
    }
    set sourceURL(sourceURL) {
      __privateMethod(this, _FrameController_instances, ignoringChangesToAttribute_fn).call(this, "src", () => {
        this.element.src = sourceURL != null ? sourceURL : null;
      });
    }
    get loadingStyle() {
      return this.element.loading;
    }
    get isLoading() {
      return this.formSubmission !== void 0 || __privateGet(this, _resolveVisitPromise).call(this) !== void 0;
    }
    get complete() {
      return this.element.hasAttribute("complete");
    }
    set complete(value) {
      if (value) {
        this.element.setAttribute("complete", "");
      } else {
        this.element.removeAttribute("complete");
      }
    }
    get isActive() {
      return this.element.isActive && __privateGet(this, _connected);
    }
    get rootLocation() {
      var _a;
      const meta = this.element.ownerDocument.querySelector(`meta[name="turbo-root"]`);
      const root = (_a = meta == null ? void 0 : meta.content) != null ? _a : "/";
      return expandURL(root);
    }
  };
  _currentFetchRequest = new WeakMap();
  _resolveVisitPromise = new WeakMap();
  _connected = new WeakMap();
  _hasBeenLoaded = new WeakMap();
  _ignoredAttributes = new WeakMap();
  _shouldMorphFrame = new WeakMap();
  _FrameController_instances = new WeakSet();
  loadSourceURL_fn = async function() {
    if (this.enabled && this.isActive && !this.complete && this.sourceURL) {
      this.element.loaded = __privateMethod(this, _FrameController_instances, visit_fn).call(this, expandURL(this.sourceURL));
      this.appearanceObserver.stop();
      await this.element.loaded;
      __privateSet(this, _hasBeenLoaded, true);
    }
  };
  loadFrameResponse_fn = async function(fetchResponse, document2) {
    const newFrameElement = await this.extractForeignFrameElement(document2.body);
    const rendererClass = __privateGet(this, _shouldMorphFrame) ? MorphingFrameRenderer : FrameRenderer;
    if (newFrameElement) {
      const snapshot = new Snapshot(newFrameElement);
      const renderer = new rendererClass(this, this.view.snapshot, snapshot, false, false);
      if (this.view.renderPromise) await this.view.renderPromise;
      this.changeHistory();
      await this.view.render(renderer);
      this.complete = true;
      session.frameRendered(fetchResponse, this.element);
      session.frameLoaded(this.element);
      await this.fetchResponseLoaded(fetchResponse);
    } else if (__privateMethod(this, _FrameController_instances, willHandleFrameMissingFromResponse_fn).call(this, fetchResponse)) {
      __privateMethod(this, _FrameController_instances, handleFrameMissingFromResponse_fn).call(this, fetchResponse);
    }
  };
  visit_fn = async function(url) {
    var _a;
    const request = new FetchRequest(this, FetchMethod.get, url, new URLSearchParams(), this.element);
    (_a = __privateGet(this, _currentFetchRequest)) == null ? void 0 : _a.cancel();
    __privateSet(this, _currentFetchRequest, request);
    return new Promise((resolve) => {
      __privateSet(this, _resolveVisitPromise, () => {
        __privateSet(this, _resolveVisitPromise, () => {
        });
        __privateSet(this, _currentFetchRequest, null);
        resolve();
      });
      request.perform();
    });
  };
  navigateFrame_fn = function(element, url, submitter2) {
    const frame = __privateMethod(this, _FrameController_instances, findFrameElement_fn2).call(this, element, submitter2);
    frame.delegate.proposeVisitIfNavigatedWithAction(frame, getVisitAction(submitter2, element, frame));
    __privateMethod(this, _FrameController_instances, withCurrentNavigationElement_fn).call(this, element, () => {
      frame.src = url;
    });
  };
  handleUnvisitableFrameResponse_fn = async function(fetchResponse) {
    console.warn(
      `The response (${fetchResponse.statusCode}) from <turbo-frame id="${this.element.id}"> is performing a full page visit due to turbo-visit-control.`
    );
    await __privateMethod(this, _FrameController_instances, visitResponse_fn).call(this, fetchResponse.response);
  };
  willHandleFrameMissingFromResponse_fn = function(fetchResponse) {
    this.element.setAttribute("complete", "");
    const response = fetchResponse.response;
    const visit2 = async (url, options) => {
      if (url instanceof Response) {
        __privateMethod(this, _FrameController_instances, visitResponse_fn).call(this, url);
      } else {
        session.visit(url, options);
      }
    };
    const event = dispatch("turbo:frame-missing", {
      target: this.element,
      detail: { response, visit: visit2 },
      cancelable: true
    });
    return !event.defaultPrevented;
  };
  handleFrameMissingFromResponse_fn = function(fetchResponse) {
    this.view.missing();
    __privateMethod(this, _FrameController_instances, throwFrameMissingError_fn).call(this, fetchResponse);
  };
  throwFrameMissingError_fn = function(fetchResponse) {
    const message = `The response (${fetchResponse.statusCode}) did not contain the expected <turbo-frame id="${this.element.id}"> and will be ignored. To perform a full page visit instead, set turbo-visit-control to reload.`;
    throw new TurboFrameMissingError(message);
  };
  visitResponse_fn = async function(response) {
    const wrapped = new FetchResponse(response);
    const responseHTML = await wrapped.responseHTML;
    const { location: location2, redirected, statusCode } = wrapped;
    return session.visit(location2, { response: { redirected, statusCode, responseHTML } });
  };
  findFrameElement_fn2 = function(element, submitter2) {
    const id = getAttribute("data-turbo-frame", submitter2, element) || this.element.getAttribute("target");
    const target = __privateMethod(this, _FrameController_instances, getFrameElementById_fn).call(this, id);
    return target instanceof FrameElement ? target : this.element;
  };
  formActionIsVisitable_fn = function(form, submitter2) {
    const action = getAction(form, submitter2);
    return locationIsVisitable(expandURL(action), this.rootLocation);
  };
  shouldInterceptNavigation_fn = function(element, submitter2) {
    const id = getAttribute("data-turbo-frame", submitter2, element) || this.element.getAttribute("target");
    if (element instanceof HTMLFormElement && !__privateMethod(this, _FrameController_instances, formActionIsVisitable_fn).call(this, element, submitter2)) {
      return false;
    }
    if (!this.enabled || id == "_top") {
      return false;
    }
    if (id) {
      const frameElement = __privateMethod(this, _FrameController_instances, getFrameElementById_fn).call(this, id);
      if (frameElement) {
        return !frameElement.disabled;
      } else if (id == "_parent") {
        return false;
      }
    }
    if (!session.elementIsNavigatable(element)) {
      return false;
    }
    if (submitter2 && !session.elementIsNavigatable(submitter2)) {
      return false;
    }
    return true;
  };
  isIgnoringChangesTo_fn = function(attributeName) {
    return __privateGet(this, _ignoredAttributes).has(attributeName);
  };
  ignoringChangesToAttribute_fn = function(attributeName, callback) {
    __privateGet(this, _ignoredAttributes).add(attributeName);
    callback();
    __privateGet(this, _ignoredAttributes).delete(attributeName);
  };
  withCurrentNavigationElement_fn = function(element, callback) {
    this.currentNavigationElement = element;
    callback();
    delete this.currentNavigationElement;
  };
  getFrameElementById_fn = function(id) {
    if (id != null) {
      const element = id === "_parent" ? this.element.parentElement.closest("turbo-frame") : document.getElementById(id);
      if (element instanceof FrameElement) {
        return element;
      }
    }
  };
  function activateElement(element, currentURL) {
    if (element) {
      const src = element.getAttribute("src");
      if (src != null && currentURL != null && urlsAreEqual(src, currentURL)) {
        throw new Error(`Matching <turbo-frame id="${element.id}"> element has a source URL which references itself`);
      }
      if (element.ownerDocument !== document) {
        element = document.importNode(element, true);
      }
      if (element instanceof FrameElement) {
        element.connectedCallback();
        element.disconnectedCallback();
        return element;
      }
    }
  }

  // src/core/streams/stream_actions.js
  var StreamActions = {
    after() {
      this.removeDuplicateTargetSiblings();
      this.targetElements.forEach((e) => {
        var _a;
        return (_a = e.parentElement) == null ? void 0 : _a.insertBefore(this.templateContent, e.nextSibling);
      });
    },
    append() {
      this.removeDuplicateTargetChildren();
      this.targetElements.forEach((e) => e.append(this.templateContent));
    },
    before() {
      this.removeDuplicateTargetSiblings();
      this.targetElements.forEach((e) => {
        var _a;
        return (_a = e.parentElement) == null ? void 0 : _a.insertBefore(this.templateContent, e);
      });
    },
    prepend() {
      this.removeDuplicateTargetChildren();
      this.targetElements.forEach((e) => e.prepend(this.templateContent));
    },
    remove() {
      this.targetElements.forEach((e) => e.remove());
    },
    replace() {
      const method = this.getAttribute("method");
      this.targetElements.forEach((targetElement) => {
        if (method === "morph") {
          morphElements(targetElement, this.templateContent);
        } else {
          targetElement.replaceWith(this.templateContent);
        }
      });
    },
    update() {
      const method = this.getAttribute("method");
      this.targetElements.forEach((targetElement) => {
        if (method === "morph") {
          morphChildren(targetElement, this.templateContent);
        } else {
          targetElement.innerHTML = "";
          targetElement.append(this.templateContent);
        }
      });
    },
    refresh() {
      const method = this.getAttribute("method");
      const requestId = this.requestId;
      const scroll = this.getAttribute("scroll");
      session.refresh(this.baseURI, { method, requestId, scroll });
    }
  };

  // src/elements/stream_element.js
  var _StreamElement_instances, raise_fn;
  var _StreamElement = class _StreamElement extends HTMLElement {
    constructor() {
      super(...arguments);
      __privateAdd(this, _StreamElement_instances);
    }
    static async renderElement(newElement) {
      await newElement.performAction();
    }
    async connectedCallback() {
      try {
        await this.render();
      } catch (error) {
        console.error(error);
      } finally {
        this.disconnect();
      }
    }
    async render() {
      var _a;
      return (_a = this.renderPromise) != null ? _a : this.renderPromise = (async () => {
        const event = this.beforeRenderEvent;
        if (this.dispatchEvent(event)) {
          await nextRepaint();
          await event.detail.render(this);
        }
      })();
    }
    disconnect() {
      try {
        this.remove();
      } catch (e) {
      }
    }
    /**
     * Removes duplicate children (by ID)
     */
    removeDuplicateTargetChildren() {
      this.duplicateChildren.forEach((c) => c.remove());
    }
    /**
     * Gets the list of duplicate children (i.e. those with the same ID)
     */
    get duplicateChildren() {
      var _a;
      const existingChildren = this.targetElements.flatMap((e) => [...e.children]).filter((c) => !!c.getAttribute("id"));
      const newChildrenIds = [...((_a = this.templateContent) == null ? void 0 : _a.children) || []].filter((c) => !!c.getAttribute("id")).map((c) => c.getAttribute("id"));
      return existingChildren.filter((c) => newChildrenIds.includes(c.getAttribute("id")));
    }
    /**
    * Removes duplicate siblings (by ID)
    */
    removeDuplicateTargetSiblings() {
      this.duplicateSiblings.forEach((c) => c.remove());
    }
    /**
    * Gets the list of duplicate siblings (i.e. those with the same ID)
    */
    get duplicateSiblings() {
      var _a;
      const existingChildren = this.targetElements.flatMap((e) => [...e.parentElement.children]).filter((c) => !!c.id);
      const newChildrenIds = [...((_a = this.templateContent) == null ? void 0 : _a.children) || []].filter((c) => !!c.id).map((c) => c.id);
      return existingChildren.filter((c) => newChildrenIds.includes(c.id));
    }
    /**
     * Gets the action function to be performed.
     */
    get performAction() {
      if (this.action) {
        const actionFunction = StreamActions[this.action];
        if (actionFunction) {
          return actionFunction;
        }
        __privateMethod(this, _StreamElement_instances, raise_fn).call(this, "unknown action");
      }
      __privateMethod(this, _StreamElement_instances, raise_fn).call(this, "action attribute is missing");
    }
    /**
     * Gets the target elements which the template will be rendered to.
     */
    get targetElements() {
      if (this.target) {
        return this.targetElementsById;
      } else if (this.targets) {
        return this.targetElementsByQuery;
      } else {
        __privateMethod(this, _StreamElement_instances, raise_fn).call(this, "target or targets attribute is missing");
      }
    }
    /**
     * Gets the contents of the main `<template>`.
     */
    get templateContent() {
      return this.templateElement.content.cloneNode(true);
    }
    /**
     * Gets the main `<template>` used for rendering
     */
    get templateElement() {
      if (this.firstElementChild === null) {
        const template = this.ownerDocument.createElement("template");
        this.appendChild(template);
        return template;
      } else if (this.firstElementChild instanceof HTMLTemplateElement) {
        return this.firstElementChild;
      }
      __privateMethod(this, _StreamElement_instances, raise_fn).call(this, "first child element must be a <template> element");
    }
    /**
     * Gets the current action.
     */
    get action() {
      return this.getAttribute("action");
    }
    /**
     * Gets the current target (an element ID) to which the result will
     * be rendered.
     */
    get target() {
      return this.getAttribute("target");
    }
    /**
     * Gets the current "targets" selector (a CSS selector)
     */
    get targets() {
      return this.getAttribute("targets");
    }
    /**
     * Reads the request-id attribute
     */
    get requestId() {
      return this.getAttribute("request-id");
    }
    get description() {
      var _a, _b;
      return (_b = ((_a = this.outerHTML.match(/<[^>]+>/)) != null ? _a : [])[0]) != null ? _b : "<turbo-stream>";
    }
    get beforeRenderEvent() {
      return new CustomEvent("turbo:before-stream-render", {
        bubbles: true,
        cancelable: true,
        detail: { newStream: this, render: _StreamElement.renderElement }
      });
    }
    get targetElementsById() {
      var _a;
      const element = (_a = this.ownerDocument) == null ? void 0 : _a.getElementById(this.target);
      if (element !== null) {
        return [element];
      } else {
        return [];
      }
    }
    get targetElementsByQuery() {
      var _a;
      const elements = (_a = this.ownerDocument) == null ? void 0 : _a.querySelectorAll(this.targets);
      if (elements.length !== 0) {
        return Array.prototype.slice.call(elements);
      } else {
        return [];
      }
    }
  };
  _StreamElement_instances = new WeakSet();
  raise_fn = function(message) {
    throw new Error(`${this.description}: ${message}`);
  };
  var StreamElement = _StreamElement;

  // src/elements/stream_source_element.js
  var StreamSourceElement = class extends HTMLElement {
    constructor() {
      super(...arguments);
      __publicField(this, "streamSource", null);
    }
    connectedCallback() {
      this.streamSource = this.src.match(/^ws{1,2}:/) ? new WebSocket(this.src) : new EventSource(this.src);
      connectStreamSource(this.streamSource);
    }
    disconnectedCallback() {
      if (this.streamSource) {
        this.streamSource.close();
        disconnectStreamSource(this.streamSource);
      }
    }
    get src() {
      return this.getAttribute("src") || "";
    }
  };

  // src/elements/index.js
  FrameElement.delegateConstructor = FrameController;
  if (customElements.get("turbo-frame") === void 0) {
    customElements.define("turbo-frame", FrameElement);
  }
  if (customElements.get("turbo-stream") === void 0) {
    customElements.define("turbo-stream", StreamElement);
  }
  if (customElements.get("turbo-stream-source") === void 0) {
    customElements.define("turbo-stream-source", StreamSourceElement);
  }

  // src/script_warning.js
  (() => {
    const scriptElement = document.currentScript;
    if (!scriptElement) return;
    if (scriptElement.hasAttribute("data-turbo-suppress-warning")) return;
    let element = scriptElement.parentElement;
    while (element) {
      if (element == document.body) {
        return console.warn(
          unindent`
        You are loading Turbo from a <script> element inside the <body> element. This is probably not what you meant to do!

        Load your application’s JavaScript bundle inside the <head> element instead. <script> elements in <body> are evaluated with each page change.

        For more information, see: https://turbo.hotwired.dev/handbook/building#working-with-script-elements

        ——
        Suppress this warning by adding a "data-turbo-suppress-warning" attribute to: %s
      `,
          scriptElement.outerHTML
        );
      }
      element = element.parentElement;
    }
  })();

  // src/index.js
  window.Turbo = __spreadProps(__spreadValues({}, core_exports), { StreamActions });
  start();

  // ../../../../../../../../Users/maki/git/dommy-js-quickjs/test/support/openwc_testing_shim.js
  var assert = globalThis.__assert;

  // src/tests/unit/deprecated_adapter_support_tests.js
  globalThis.__setModule("deprecated_adapter_support_tests");
  var DeprecatedAdapterSupportTest = class {
    constructor() {
      __publicField(this, "locations", []);
    }
    // Adapter interface
    visitProposedToLocation(location2, _options) {
      this.locations.push(location2);
    }
    visitStarted(visit2) {
      this.locations.push(visit2.location);
      visit2.cancel();
    }
    visitCompleted(_visit) {
    }
    visitFailed(_visit) {
    }
    visitRequestStarted(_visit) {
    }
    visitRequestCompleted(_visit) {
    }
    visitRequestFailedWithStatusCode(_visit, _statusCode) {
    }
    visitRequestFinished(_visit) {
    }
    visitRendered(_visit) {
    }
    formSubmissionStarted(_formSubmission) {
    }
    formSubmissionFinished(_formSubmission) {
    }
    pageInvalidated() {
    }
  };
  var adapter;
  setup(() => {
    adapter = new DeprecatedAdapterSupportTest();
    registerAdapter(adapter);
  });
  test("visit proposal location includes deprecated absoluteURL property", async () => {
    sessionNavigator.proposeVisit(new URL(window.location.toString()));
    assert.equal(adapter.locations.length, 1);
    const [location2] = adapter.locations;
    assert.equal(location2.toString(), location2.absoluteURL);
  });
  test("visit start location includes deprecated absoluteURL property", async () => {
    sessionNavigator.startVisit(window.location.toString(), "123");
    assert.equal(adapter.locations.length, 1);
    const [location2] = adapter.locations;
    assert.equal(location2.toString(), location2.absoluteURL);
  });

  // src/tests/unit/export_tests.js
  globalThis.__setModule("export_tests");
  test("Turbo interface", () => {
    assert.equal(typeof StreamActions, "object");
    assert.equal(typeof start, "function");
    assert.equal(typeof registerAdapter, "function");
    assert.equal(typeof visit, "function");
    assert.equal(typeof connectStreamSource, "function");
    assert.equal(typeof disconnectStreamSource, "function");
    assert.equal(typeof renderStreamMessage, "function");
    assert.equal(typeof setProgressBarDelay, "function");
    assert.equal(typeof setConfirmMethod, "function");
    assert.equal(typeof setFormMode, "function");
    assert.equal(typeof cache, "object");
    assert.equal(typeof config, "object");
    assert.equal(typeof cache.clear, "function");
    assert.equal(typeof sessionNavigator, "object");
    assert.equal(typeof session, "object");
    assert.equal(typeof session.drive, "boolean");
    assert.equal(typeof session.formMode, "string");
    assert.equal(typeof fetchWithTurboHeaders, "function");
    assert.equal(typeof morphElements, "function");
    assert.equal(typeof morphChildren, "function");
    assert.equal(typeof morphBodyElements, "function");
    assert.equal(typeof morphTurboFrameElements, "function");
  });
  test("Session interface", () => {
    const { session: session2, config: config2 } = src_exports;
    assert.equal(true, session2.drive);
    assert.equal(true, config2.drive.enabled);
    assert.equal("on", session2.formMode);
    assert.equal("on", config2.forms.mode);
    session2.drive = false;
    session2.formMode = "off";
    assert.equal(false, session2.drive);
    assert.equal(false, config2.drive.enabled);
    assert.equal("off", session2.formMode);
    assert.equal("off", config2.forms.mode);
  });
  test("StreamActions interface", () => {
    assert.equal(typeof StreamActions, "object");
  });

  // src/tests/unit/limited_set_tests.js
  globalThis.__setModule("limited_set_tests");
  test("add a limited number of elements", () => {
    const set = new LimitedSet(3);
    set.add(1);
    set.add(2);
    set.add(3);
    set.add(4);
    assert.equal(set.size, 3);
    assert.notInclude(set, 1);
    assert.include(set, 2);
    assert.include(set, 3);
    assert.include(set, 4);
  });

  // src/tests/unit/native_adapter_support_tests.js
  globalThis.__setModule("native_adapter_support_tests");
  var NativeAdapterSupportTest = class {
    constructor() {
      __publicField(this, "proposedVisits", []);
      __publicField(this, "startedVisits", []);
      __publicField(this, "completedVisits", []);
      __publicField(this, "startedVisitRequests", []);
      __publicField(this, "completedVisitRequests", []);
      __publicField(this, "failedVisitRequests", []);
      __publicField(this, "finishedVisitRequests", []);
      __publicField(this, "startedFormSubmissions", []);
      __publicField(this, "finishedFormSubmissions", []);
      __publicField(this, "linkPrefetchRequests", []);
    }
    // Adapter interface
    visitProposedToLocation(location2, options) {
      this.proposedVisits.push({ location: location2, options });
    }
    visitStarted(visit2) {
      this.startedVisits.push(visit2);
    }
    visitCompleted(visit2) {
      this.completedVisits.push(visit2);
    }
    visitRequestStarted(visit2) {
      this.startedVisitRequests.push(visit2);
    }
    visitRequestCompleted(visit2) {
      this.completedVisitRequests.push(visit2);
    }
    visitRequestFailedWithStatusCode(visit2, _statusCode) {
      this.failedVisitRequests.push(visit2);
    }
    visitRequestFinished(visit2) {
      this.finishedVisitRequests.push(visit2);
    }
    visitRendered(_visit) {
    }
    formSubmissionStarted(formSubmission) {
      this.startedFormSubmissions.push(formSubmission);
    }
    formSubmissionFinished(formSubmission) {
      this.finishedFormSubmissions.push(formSubmission);
    }
    pageInvalidated() {
    }
    linkPrefetchingIsEnabledForLocation(location2) {
      this.linkPrefetchRequests.push(location2);
    }
  };
  var adapter2;
  setup(() => {
    adapter2 = new NativeAdapterSupportTest();
    registerAdapter(adapter2);
  });
  test("navigator adapter is native adapter", async () => {
    assert.equal(adapter2, sessionNavigator.adapter);
  });
  test("visit proposal location is proposed to adapter", async () => {
    const url = new URL(window.location.toString());
    sessionNavigator.proposeVisit(url);
    assert.equal(adapter2.proposedVisits.length, 1);
    const [visit2] = adapter2.proposedVisits;
    assert.equal(visit2.location, url);
  });
  test("visit proposal external location is proposed to adapter", async () => {
    const url = new URL("https://example.com/");
    sessionNavigator.proposeVisit(url);
    assert.equal(adapter2.proposedVisits.length, 1);
    const [visit2] = adapter2.proposedVisits;
    assert.equal(visit2.location, url);
  });
  test("visit started notifies adapter", async () => {
    const locatable = window.location.toString();
    sessionNavigator.startVisit(locatable);
    assert.equal(adapter2.startedVisits.length, 1);
    const [visit2] = adapter2.startedVisits;
    assert.equal(visit2.location, locatable);
  });
  test("test visit has cached snapshot returns boolean", async () => {
    const locatable = window.location.toString();
    await sessionNavigator.startVisit(locatable);
    const [visit2] = adapter2.startedVisits;
    assert.equal(visit2.hasCachedSnapshot(), false);
  });
  test("visit completed notifies adapter", async () => {
    const locatable = window.location.toString();
    sessionNavigator.startVisit(locatable);
    const [startedVisit] = adapter2.startedVisits;
    startedVisit.complete();
    const [completedVisit] = adapter2.completedVisits;
    assert.equal(completedVisit.location, locatable);
  });
  test("visit request started notifies adapter", async () => {
    const locatable = window.location.toString();
    sessionNavigator.startVisit(locatable);
    const [startedVisit] = adapter2.startedVisits;
    startedVisit.startRequest();
    assert.equal(adapter2.startedVisitRequests.length, 1);
    const [startedVisitRequest] = adapter2.startedVisitRequests;
    assert.equal(startedVisitRequest.location, locatable);
  });
  test("visit request completed notifies adapter", async () => {
    const locatable = window.location.toString();
    sessionNavigator.startVisit(locatable);
    const [startedVisit] = adapter2.startedVisits;
    startedVisit.recordResponse({ statusCode: 200, responseHTML: "responseHtml", redirected: false });
    assert.equal(adapter2.completedVisitRequests.length, 1);
    const [completedVisitRequest] = adapter2.completedVisitRequests;
    assert.equal(completedVisitRequest.location, locatable);
  });
  test("visit request failed notifies adapter", async () => {
    const locatable = window.location.toString();
    sessionNavigator.startVisit(locatable);
    const [startedVisit] = adapter2.startedVisits;
    startedVisit.recordResponse({ statusCode: 404, responseHTML: "responseHtml", redirected: false });
    assert.equal(adapter2.failedVisitRequests.length, 1);
    const [failedVisitRequest] = adapter2.failedVisitRequests;
    assert.equal(failedVisitRequest.location, locatable);
  });
  test("visit request finished notifies adapter", async () => {
    const locatable = window.location.toString();
    sessionNavigator.startVisit(locatable);
    const [startedVisit] = adapter2.startedVisits;
    startedVisit.finishRequest();
    assert.equal(adapter2.finishedVisitRequests.length, 1);
    const [finishedVisitRequest] = adapter2.finishedVisitRequests;
    assert.equal(finishedVisitRequest.location, locatable);
  });
  test("form submission started notifies adapter", async () => {
    sessionNavigator.formSubmissionStarted("formSubmissionStub");
    assert.equal(adapter2.startedFormSubmissions.length, 1);
    const [startedFormSubmission] = adapter2.startedFormSubmissions;
    assert.equal(startedFormSubmission, "formSubmissionStub");
  });
  test("form submission finished notifies adapter", async () => {
    sessionNavigator.formSubmissionFinished("formSubmissionStub");
    assert.equal(adapter2.finishedFormSubmissions.length, 1);
    const [finishedFormSubmission] = adapter2.finishedFormSubmissions;
    assert.equal(finishedFormSubmission, "formSubmissionStub");
  });
  test("visit follows redirect and proposes replace visit to adapter", async () => {
    const locatable = window.location.toString();
    const redirectedLocation = "https://example.com";
    sessionNavigator.startVisit(locatable);
    const [startedVisit] = adapter2.startedVisits;
    startedVisit.redirectedToLocation = redirectedLocation;
    startedVisit.recordResponse({ statusCode: 200, responseHTML: "responseHtml", redirected: true });
    startedVisit.complete();
    assert.equal(adapter2.completedVisitRequests.length, 1);
    assert.equal(adapter2.proposedVisits.length, 1);
    const [visit2] = adapter2.proposedVisits;
    assert.equal(visit2.location, redirectedLocation);
    assert.equal(visit2.options.action, "replace");
  });
  test("link prefetch requests verify with adapter", async () => {
    const locatable = window.location.toString();
    sessionNavigator.linkPrefetchingIsEnabledForLocation(locatable);
    assert.equal(adapter2.linkPrefetchRequests.length, 1);
    const [location2] = adapter2.linkPrefetchRequests;
    assert.equal(location2, locatable);
  });

  // src/tests/helpers/dom_test_case.js
  var DOMTestCase = class {
    constructor() {
      __publicField(this, "fixtureElement", document.createElement("main"));
    }
    async setup() {
      this.fixtureElement.hidden = true;
      document.body.insertAdjacentElement("afterbegin", this.fixtureElement);
    }
    async teardown() {
      this.fixtureElement.innerHTML = "";
      this.fixtureElement.remove();
    }
    append(node) {
      this.fixtureElement.appendChild(node);
    }
    find(selector) {
      return this.fixtureElement.querySelector(selector);
    }
    get fixtureHTML() {
      return this.fixtureElement.innerHTML;
    }
    set fixtureHTML(html) {
      this.fixtureElement.innerHTML = html;
    }
  };

  // src/tests/helpers/page.js
  function sleep(timeout = 0) {
    return new Promise((resolve) => setTimeout(() => resolve(void 0), timeout));
  }

  // src/tests/unit/stream_element_tests.js
  globalThis.__setModule("stream_element_tests");
  function createStreamElement(action, target, templateElement, attributes = {}) {
    const element = new StreamElement();
    if (action) element.setAttribute("action", action);
    if (target) element.setAttribute("target", target);
    if (templateElement) element.appendChild(templateElement);
    Object.entries(attributes).forEach((attribute) => element.setAttribute(...attribute));
    return element;
  }
  function createTemplateElement(html) {
    const element = document.createElement("template");
    element.innerHTML = html;
    return element;
  }
  var StreamElementTests = class extends DOMTestCase {
  };
  var subject;
  setup(() => {
    subject = new StreamElementTests();
    subject.setup();
    subject.fixtureHTML = `<div><div id="hello">Hello Turbo</div></div>`;
  });
  test("action=append", async () => {
    var _a, _b, _c;
    const element = createStreamElement("append", "hello", createTemplateElement("<span> Streams</span>"));
    const element2 = createStreamElement("append", "hello", createTemplateElement("<span> and more</span>"));
    assert.equal((_a = subject.find("#hello")) == null ? void 0 : _a.textContent, "Hello Turbo");
    subject.append(element);
    await nextAnimationFrame();
    assert.equal((_b = subject.find("#hello")) == null ? void 0 : _b.textContent, "Hello Turbo Streams");
    assert.isNull(element.parentElement);
    subject.append(element2);
    await nextAnimationFrame();
    assert.equal((_c = subject.find("#hello")) == null ? void 0 : _c.textContent, "Hello Turbo Streams and more");
    assert.isNull(element2.parentElement);
  });
  test("action=append with a form template containing an input named id", async () => {
    var _a, _b, _c;
    const element = createStreamElement(
      "append",
      "hello",
      createTemplateElement(' <form id="child_1"><input type="hidden" name="id" value="First"></form> tail1 ')
    );
    const element2 = createStreamElement(
      "append",
      "hello",
      createTemplateElement(
        '<form id="child_1"><input type="hidden" name="id" value="New First"></form> <form id="child_2"><input type="hidden" name="id" value="Second"></form> tail2 '
      )
    );
    assert.equal((_a = subject.find("#hello")) == null ? void 0 : _a.textContent, "Hello Turbo");
    subject.append(element);
    await nextAnimationFrame();
    assert.equal((_b = subject.find("#hello")) == null ? void 0 : _b.innerHTML, 'Hello Turbo <form id="child_1"><input type="hidden" name="id" value="First"></form> tail1 ');
    assert.isNull(element.parentElement);
    subject.append(element2);
    await nextAnimationFrame();
    assert.equal((_c = subject.find("#hello")) == null ? void 0 : _c.innerHTML, 'Hello Turbo  tail1 <form id="child_1"><input type="hidden" name="id" value="New First"></form> <form id="child_2"><input type="hidden" name="id" value="Second"></form> tail2 ');
  });
  test("action=append with children ID already present in target", async () => {
    var _a, _b, _c;
    const element = createStreamElement("append", "hello", createTemplateElement(' <div id="child_1">First</div> tail1 '));
    const element2 = createStreamElement(
      "append",
      "hello",
      createTemplateElement('<div id="child_1">New First</div> <div id="child_2">Second</div> tail2 ')
    );
    assert.equal((_a = subject.find("#hello")) == null ? void 0 : _a.textContent, "Hello Turbo");
    subject.append(element);
    await nextAnimationFrame();
    assert.equal((_b = subject.find("#hello")) == null ? void 0 : _b.textContent, "Hello Turbo First tail1 ");
    assert.isNull(element.parentElement);
    subject.append(element2);
    await nextAnimationFrame();
    assert.equal((_c = subject.find("#hello")) == null ? void 0 : _c.textContent, "Hello Turbo  tail1 New First Second tail2 ");
  });
  test("action=prepend", async () => {
    var _a, _b, _c;
    const element = createStreamElement("prepend", "hello", createTemplateElement("<span>Streams </span>"));
    const element2 = createStreamElement("prepend", "hello", createTemplateElement("<span>and more </span>"));
    assert.equal((_a = subject.find("#hello")) == null ? void 0 : _a.textContent, "Hello Turbo");
    subject.append(element);
    await nextAnimationFrame();
    assert.equal((_b = subject.find("#hello")) == null ? void 0 : _b.textContent, "Streams Hello Turbo");
    assert.isNull(element.parentElement);
    subject.append(element2);
    await nextAnimationFrame();
    assert.equal((_c = subject.find("#hello")) == null ? void 0 : _c.textContent, "and more Streams Hello Turbo");
    assert.isNull(element.parentElement);
  });
  test("action=prepend with a form template containing an input named id", async () => {
    var _a, _b, _c;
    const element = createStreamElement("prepend", "hello", createTemplateElement('<form id="child_1"><input type="hidden" name="id" value="First"></form> tail1 '));
    const element2 = createStreamElement(
      "prepend",
      "hello",
      createTemplateElement(
        '<form id="child_1"><input type="hidden" name="id" value="New First"></form> <form id="child_2"><input type="hidden" name="id" value="Second"></form> tail2 '
      )
    );
    assert.equal((_a = subject.find("#hello")) == null ? void 0 : _a.textContent, "Hello Turbo");
    subject.append(element);
    await nextAnimationFrame();
    assert.equal((_b = subject.find("#hello")) == null ? void 0 : _b.innerHTML, '<form id="child_1"><input type="hidden" name="id" value="First"></form> tail1 Hello Turbo');
    assert.isNull(element.parentElement);
    subject.append(element2);
    await nextAnimationFrame();
    assert.equal((_c = subject.find("#hello")) == null ? void 0 : _c.innerHTML, '<form id="child_1"><input type="hidden" name="id" value="New First"></form> <form id="child_2"><input type="hidden" name="id" value="Second"></form> tail2  tail1 Hello Turbo');
  });
  test("action=prepend with children ID already present in target", async () => {
    var _a, _b, _c;
    const element = createStreamElement("prepend", "hello", createTemplateElement('<div id="child_1">First</div> tail1 '));
    const element2 = createStreamElement(
      "prepend",
      "hello",
      createTemplateElement('<div id="child_1">New First</div> <div id="child_2">Second</div> tail2 ')
    );
    assert.equal((_a = subject.find("#hello")) == null ? void 0 : _a.textContent, "Hello Turbo");
    subject.append(element);
    await nextAnimationFrame();
    assert.equal((_b = subject.find("#hello")) == null ? void 0 : _b.textContent, "First tail1 Hello Turbo");
    assert.isNull(element.parentElement);
    subject.append(element2);
    await nextAnimationFrame();
    assert.equal((_c = subject.find("#hello")) == null ? void 0 : _c.textContent, "New First Second tail2  tail1 Hello Turbo");
  });
  test("action=remove", async () => {
    const element = createStreamElement("remove", "hello");
    assert.ok(subject.find("#hello"));
    subject.append(element);
    await nextAnimationFrame();
    assert.notOk(subject.find("#hello"));
    assert.isNull(element.parentElement);
  });
  test("action=replace", async () => {
    var _a, _b;
    const element = createStreamElement("replace", "hello", createTemplateElement(`<h1 id="hello">Hello Turbo</h1>`));
    assert.equal((_a = subject.find("#hello")) == null ? void 0 : _a.textContent, "Hello Turbo");
    assert.ok(subject.find("div#hello"));
    subject.append(element);
    await nextAnimationFrame();
    assert.equal((_b = subject.find("#hello")) == null ? void 0 : _b.textContent, "Hello Turbo");
    assert.notOk(subject.find("div#hello"));
    assert.ok(subject.find("h1#hello"));
    assert.isNull(element.parentElement);
  });
  test("action=update", async () => {
    var _a, _b;
    const element = createStreamElement("update", "hello", createTemplateElement("Goodbye Turbo"));
    assert.equal((_a = subject.find("#hello")) == null ? void 0 : _a.textContent, "Hello Turbo");
    subject.append(element);
    await nextAnimationFrame();
    assert.equal((_b = subject.find("#hello")) == null ? void 0 : _b.textContent, "Goodbye Turbo");
    assert.isNull(element.parentElement);
  });
  test("action=after", async () => {
    var _a, _b, _c;
    const element = createStreamElement("after", "hello", createTemplateElement(`<h1 id="after">After Turbo</h1>`));
    assert.equal((_a = subject.find("#hello")) == null ? void 0 : _a.textContent, "Hello Turbo");
    subject.append(element);
    await nextAnimationFrame();
    assert.equal((_c = (_b = subject.find("#hello")) == null ? void 0 : _b.nextSibling) == null ? void 0 : _c.textContent, "After Turbo");
    assert.ok(subject.find("div#hello"));
    assert.ok(subject.find("h1#after"));
    assert.isNull(element.parentElement);
  });
  test("action=after with children ID already present in target", async () => {
    var _a;
    subject.fixtureHTML = `<div id="hello"><div id="top">Top</div><div id="middle">Middle</div><div id="bottom">Bottom</div></div>`;
    const element = createStreamElement("after", "top", createTemplateElement(' <div id="middle">New Middle</div> tail1 '));
    subject.append(element);
    await nextAnimationFrame();
    assert.equal((_a = subject.find("#hello")) == null ? void 0 : _a.textContent, "Top New Middle tail1 Bottom");
  });
  test("action=before", async () => {
    var _a, _b, _c;
    const element = createStreamElement("before", "hello", createTemplateElement(`<h1 id="before">Before Turbo</h1>`));
    assert.equal((_a = subject.find("#hello")) == null ? void 0 : _a.textContent, "Hello Turbo");
    subject.append(element);
    await nextAnimationFrame();
    assert.equal((_c = (_b = subject.find("#hello")) == null ? void 0 : _b.previousSibling) == null ? void 0 : _c.textContent, "Before Turbo");
    assert.ok(subject.find("div#hello"));
    assert.ok(subject.find("h1#before"));
    assert.isNull(element.parentElement);
  });
  test("action=before with children ID already present in target", async () => {
    var _a;
    subject.fixtureHTML = `<div id="hello"><div id="top">Top</div><div id="middle">Middle</div><div id="bottom">Bottom</div></div>`;
    const element = createStreamElement("before", "bottom", createTemplateElement(' <div id="middle">New Middle</div> tail1 '));
    subject.append(element);
    await nextAnimationFrame();
    assert.equal((_a = subject.find("#hello")) == null ? void 0 : _a.textContent, "Top New Middle tail1 Bottom");
  });
  test("test action=refresh", async () => {
    document.body.setAttribute("data-modified", "");
    assert.ok(document.body.hasAttribute("data-modified"));
    const element = createStreamElement("refresh");
    subject.append(element);
    await sleep(250);
    assert.notOk(document.body.hasAttribute("data-modified"));
  });
  test("test action=refresh discarded when matching request id", async () => {
    session.recentRequests.add("123");
    document.body.setAttribute("data-modified", "");
    assert.ok(document.body.hasAttribute("data-modified"));
    const element = createStreamElement("refresh");
    element.setAttribute("request-id", "123");
    subject.append(element);
    await sleep(250);
    assert.ok(document.body.hasAttribute("data-modified"));
  });
  test("action=replace method=morph", async () => {
    var _a, _b;
    const templateElement = createTemplateElement(`<h1 id="hello">Hello Turbo Morphed</h1>`);
    const element = createStreamElement("replace", "hello", templateElement, { method: "morph" });
    assert.equal((_a = subject.find("div#hello")) == null ? void 0 : _a.textContent, "Hello Turbo");
    subject.append(element);
    await nextAnimationFrame();
    assert.notOk(subject.find("div#hello"));
    assert.equal((_b = subject.find("h1#hello")) == null ? void 0 : _b.textContent, "Hello Turbo Morphed");
  });
  test("action=replace method=morph with text content change", async () => {
    var _a, _b;
    const templateElement = createTemplateElement(`<div id="hello">Hello Turbo Morphed</div>`);
    const element = createStreamElement("replace", "hello", templateElement, { method: "morph" });
    assert.equal((_a = subject.find("div#hello")) == null ? void 0 : _a.textContent, "Hello Turbo");
    subject.append(element);
    await nextAnimationFrame();
    assert.ok(subject.find("div#hello"));
    assert.equal((_b = subject.find("div#hello")) == null ? void 0 : _b.textContent, "Hello Turbo Morphed");
  });
  test("action=update method=morph", async () => {
    const templateElement = createTemplateElement(`<h1 id="hello-child-element">Hello Turbo Morphed</h1>`);
    const element = createStreamElement("update", "hello", templateElement, { method: "morph" });
    const target = subject.find("div#hello");
    assert.equal(target == null ? void 0 : target.textContent, "Hello Turbo");
    element.setAttribute("children-only", true);
    subject.append(element);
    await nextAnimationFrame();
    assert.ok(subject.find("div#hello"));
    assert.ok(subject.find("div#hello > h1#hello-child-element"));
    assert.equal(subject.find("div#hello > h1#hello-child-element").textContent, "Hello Turbo Morphed");
  });
})();
