"use strict";
(() => {
  var __defProp = Object.defineProperty;
  var __defProps = Object.defineProperties;
  var __getOwnPropDescs = Object.getOwnPropertyDescriptors;
  var __getOwnPropSymbols = Object.getOwnPropertySymbols;
  var __hasOwnProp = Object.prototype.hasOwnProperty;
  var __propIsEnum = Object.prototype.propertyIsEnumerable;
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

  // src/core/event_listener.ts
  var EventListener = class {
    constructor(eventTarget, eventName, eventOptions) {
      this.eventTarget = eventTarget;
      this.eventName = eventName;
      this.eventOptions = eventOptions;
      this.unorderedBindings = /* @__PURE__ */ new Set();
    }
    connect() {
      this.eventTarget.addEventListener(this.eventName, this, this.eventOptions);
    }
    disconnect() {
      this.eventTarget.removeEventListener(this.eventName, this, this.eventOptions);
    }
    // Binding observer delegate
    bindingConnected(binding) {
      this.unorderedBindings.add(binding);
    }
    bindingDisconnected(binding) {
      this.unorderedBindings.delete(binding);
    }
    handleEvent(event) {
      const extendedEvent = extendEvent(event);
      for (const binding of this.bindings) {
        if (extendedEvent.immediatePropagationStopped) {
          break;
        } else {
          binding.handleEvent(extendedEvent);
        }
      }
    }
    hasBindings() {
      return this.unorderedBindings.size > 0;
    }
    get bindings() {
      return Array.from(this.unorderedBindings).sort((left, right) => {
        const leftIndex = left.index, rightIndex = right.index;
        return leftIndex < rightIndex ? -1 : leftIndex > rightIndex ? 1 : 0;
      });
    }
  };
  function extendEvent(event) {
    if ("immediatePropagationStopped" in event) {
      return event;
    } else {
      const { stopImmediatePropagation } = event;
      return Object.assign(event, {
        immediatePropagationStopped: false,
        stopImmediatePropagation() {
          this.immediatePropagationStopped = true;
          stopImmediatePropagation.call(this);
        }
      });
    }
  }

  // src/core/dispatcher.ts
  var Dispatcher = class {
    constructor(application) {
      this.application = application;
      this.eventListenerMaps = /* @__PURE__ */ new Map();
      this.started = false;
    }
    start() {
      if (!this.started) {
        this.started = true;
        this.eventListeners.forEach((eventListener) => eventListener.connect());
      }
    }
    stop() {
      if (this.started) {
        this.started = false;
        this.eventListeners.forEach((eventListener) => eventListener.disconnect());
      }
    }
    get eventListeners() {
      return Array.from(this.eventListenerMaps.values()).reduce(
        (listeners, map) => listeners.concat(Array.from(map.values())),
        []
      );
    }
    // Binding observer delegate
    bindingConnected(binding) {
      this.fetchEventListenerForBinding(binding).bindingConnected(binding);
    }
    bindingDisconnected(binding, clearEventListeners = false) {
      this.fetchEventListenerForBinding(binding).bindingDisconnected(binding);
      if (clearEventListeners) this.clearEventListenersForBinding(binding);
    }
    // Error handling
    handleError(error2, message, detail = {}) {
      this.application.handleError(error2, `Error ${message}`, detail);
    }
    clearEventListenersForBinding(binding) {
      const eventListener = this.fetchEventListenerForBinding(binding);
      if (!eventListener.hasBindings()) {
        eventListener.disconnect();
        this.removeMappedEventListenerFor(binding);
      }
    }
    removeMappedEventListenerFor(binding) {
      const { eventTarget, eventName, eventOptions } = binding;
      const eventListenerMap = this.fetchEventListenerMapForEventTarget(eventTarget);
      const cacheKey = this.cacheKey(eventName, eventOptions);
      eventListenerMap.delete(cacheKey);
      if (eventListenerMap.size == 0) this.eventListenerMaps.delete(eventTarget);
    }
    fetchEventListenerForBinding(binding) {
      const { eventTarget, eventName, eventOptions } = binding;
      return this.fetchEventListener(eventTarget, eventName, eventOptions);
    }
    fetchEventListener(eventTarget, eventName, eventOptions) {
      const eventListenerMap = this.fetchEventListenerMapForEventTarget(eventTarget);
      const cacheKey = this.cacheKey(eventName, eventOptions);
      let eventListener = eventListenerMap.get(cacheKey);
      if (!eventListener) {
        eventListener = this.createEventListener(eventTarget, eventName, eventOptions);
        eventListenerMap.set(cacheKey, eventListener);
      }
      return eventListener;
    }
    createEventListener(eventTarget, eventName, eventOptions) {
      const eventListener = new EventListener(eventTarget, eventName, eventOptions);
      if (this.started) {
        eventListener.connect();
      }
      return eventListener;
    }
    fetchEventListenerMapForEventTarget(eventTarget) {
      let eventListenerMap = this.eventListenerMaps.get(eventTarget);
      if (!eventListenerMap) {
        eventListenerMap = /* @__PURE__ */ new Map();
        this.eventListenerMaps.set(eventTarget, eventListenerMap);
      }
      return eventListenerMap;
    }
    cacheKey(eventName, eventOptions) {
      const parts = [eventName];
      Object.keys(eventOptions).sort().forEach((key) => {
        parts.push(`${eventOptions[key] ? "" : "!"}${key}`);
      });
      return parts.join(":");
    }
  };

  // src/core/action_descriptor.ts
  var defaultActionDescriptorFilters = {
    stop({ event, value }) {
      if (value) event.stopPropagation();
      return true;
    },
    prevent({ event, value }) {
      if (value) event.preventDefault();
      return true;
    },
    self({ event, value, element }) {
      if (value) {
        return element === event.target;
      } else {
        return true;
      }
    }
  };
  var descriptorPattern = /^(?:(?:([^.]+?)\+)?(.+?)(?:\.(.+?))?(?:@(window|document))?->)?(.+?)(?:#([^:]+?))(?::(.+))?$/;
  function parseActionDescriptorString(descriptorString) {
    const source = descriptorString.trim();
    const matches = source.match(descriptorPattern) || [];
    let eventName = matches[2];
    let keyFilter = matches[3];
    if (keyFilter && !["keydown", "keyup", "keypress"].includes(eventName)) {
      eventName += `.${keyFilter}`;
      keyFilter = "";
    }
    return {
      eventTarget: parseEventTarget(matches[4]),
      eventName,
      eventOptions: matches[7] ? parseEventOptions(matches[7]) : {},
      identifier: matches[5],
      methodName: matches[6],
      keyFilter: matches[1] || keyFilter
    };
  }
  function parseEventTarget(eventTargetName) {
    if (eventTargetName == "window") {
      return window;
    } else if (eventTargetName == "document") {
      return document;
    }
  }
  function parseEventOptions(eventOptions) {
    return eventOptions.split(":").reduce((options, token) => Object.assign(options, { [token.replace(/^!/, "")]: !/^!/.test(token) }), {});
  }
  function stringifyEventTarget(eventTarget) {
    if (eventTarget == window) {
      return "window";
    } else if (eventTarget == document) {
      return "document";
    }
  }

  // src/core/string_helpers.ts
  function camelize(value) {
    return value.replace(/(?:[_-])([a-z0-9])/g, (_, char) => char.toUpperCase());
  }
  function namespaceCamelize(value) {
    return camelize(value.replace(/--/g, "-").replace(/__/g, "_"));
  }
  function capitalize(value) {
    return value.charAt(0).toUpperCase() + value.slice(1);
  }
  function dasherize(value) {
    return value.replace(/([A-Z])/g, (_, char) => `-${char.toLowerCase()}`);
  }
  function tokenize(value) {
    return value.match(/[^\s]+/g) || [];
  }

  // src/core/utils.ts
  function isSomething(object) {
    return object !== null && object !== void 0;
  }
  function hasProperty(object, property) {
    return Object.prototype.hasOwnProperty.call(object, property);
  }

  // src/core/action.ts
  var allModifiers = ["meta", "ctrl", "alt", "shift"];
  var Action = class {
    static forToken(token, schema) {
      return new this(token.element, token.index, parseActionDescriptorString(token.content), schema);
    }
    constructor(element, index, descriptor, schema) {
      this.element = element;
      this.index = index;
      this.eventTarget = descriptor.eventTarget || element;
      this.eventName = descriptor.eventName || getDefaultEventNameForElement(element) || error("missing event name");
      this.eventOptions = descriptor.eventOptions || {};
      this.identifier = descriptor.identifier || error("missing identifier");
      this.methodName = descriptor.methodName || error("missing method name");
      this.keyFilter = descriptor.keyFilter || "";
      this.schema = schema;
    }
    toString() {
      const eventFilter = this.keyFilter ? `.${this.keyFilter}` : "";
      const eventTarget = this.eventTargetName ? `@${this.eventTargetName}` : "";
      return `${this.eventName}${eventFilter}${eventTarget}->${this.identifier}#${this.methodName}`;
    }
    shouldIgnoreKeyboardEvent(event) {
      if (!this.keyFilter) {
        return false;
      }
      const filters = this.keyFilter.split("+");
      if (this.keyFilterDissatisfied(event, filters)) {
        return true;
      }
      const standardFilter = filters.filter((key) => !allModifiers.includes(key))[0];
      if (!standardFilter) {
        return false;
      }
      if (!hasProperty(this.keyMappings, standardFilter)) {
        error(`contains unknown key filter: ${this.keyFilter}`);
      }
      return this.keyMappings[standardFilter].toLowerCase() !== event.key.toLowerCase();
    }
    shouldIgnoreMouseEvent(event) {
      if (!this.keyFilter) {
        return false;
      }
      const filters = [this.keyFilter];
      if (this.keyFilterDissatisfied(event, filters)) {
        return true;
      }
      return false;
    }
    get params() {
      const params = {};
      const pattern = new RegExp(`^data-${this.identifier}-(.+)-param$`, "i");
      for (const { name, value } of Array.from(this.element.attributes)) {
        const match = name.match(pattern);
        const key = match && match[1];
        if (key) {
          params[camelize(key)] = typecast(value);
        }
      }
      return params;
    }
    get eventTargetName() {
      return stringifyEventTarget(this.eventTarget);
    }
    get keyMappings() {
      return this.schema.keyMappings;
    }
    keyFilterDissatisfied(event, filters) {
      const [meta, ctrl, alt, shift] = allModifiers.map((modifier) => filters.includes(modifier));
      return event.metaKey !== meta || event.ctrlKey !== ctrl || event.altKey !== alt || event.shiftKey !== shift;
    }
  };
  var defaultEventNames = {
    a: () => "click",
    button: () => "click",
    form: () => "submit",
    details: () => "toggle",
    input: (e) => e.getAttribute("type") == "submit" ? "click" : "input",
    select: () => "change",
    textarea: () => "input"
  };
  function getDefaultEventNameForElement(element) {
    const tagName = element.tagName.toLowerCase();
    if (tagName in defaultEventNames) {
      return defaultEventNames[tagName](element);
    }
  }
  function error(message) {
    throw new Error(message);
  }
  function typecast(value) {
    try {
      return JSON.parse(value);
    } catch (o_O) {
      return value;
    }
  }

  // src/core/binding.ts
  var Binding = class {
    constructor(context, action) {
      this.context = context;
      this.action = action;
    }
    get index() {
      return this.action.index;
    }
    get eventTarget() {
      return this.action.eventTarget;
    }
    get eventOptions() {
      return this.action.eventOptions;
    }
    get identifier() {
      return this.context.identifier;
    }
    handleEvent(event) {
      const actionEvent = this.prepareActionEvent(event);
      if (this.willBeInvokedByEvent(event) && this.applyEventModifiers(actionEvent)) {
        this.invokeWithEvent(actionEvent);
      }
    }
    get eventName() {
      return this.action.eventName;
    }
    get method() {
      const method = this.controller[this.methodName];
      if (typeof method == "function") {
        return method;
      }
      throw new Error(`Action "${this.action}" references undefined method "${this.methodName}"`);
    }
    applyEventModifiers(event) {
      const { element } = this.action;
      const { actionDescriptorFilters } = this.context.application;
      const { controller } = this.context;
      let passes = true;
      for (const [name, value] of Object.entries(this.eventOptions)) {
        if (name in actionDescriptorFilters) {
          const filter = actionDescriptorFilters[name];
          passes = passes && filter({ name, value, event, element, controller });
        } else {
          continue;
        }
      }
      return passes;
    }
    prepareActionEvent(event) {
      return Object.assign(event, { params: this.action.params });
    }
    invokeWithEvent(event) {
      const { target, currentTarget } = event;
      try {
        this.method.call(this.controller, event);
        this.context.logDebugActivity(this.methodName, { event, target, currentTarget, action: this.methodName });
      } catch (error2) {
        const { identifier, controller, element, index } = this;
        const detail = { identifier, controller, element, index, event };
        this.context.handleError(error2, `invoking action "${this.action}"`, detail);
      }
    }
    willBeInvokedByEvent(event) {
      const eventTarget = event.target;
      if (event instanceof KeyboardEvent && this.action.shouldIgnoreKeyboardEvent(event)) {
        return false;
      }
      if (event instanceof MouseEvent && this.action.shouldIgnoreMouseEvent(event)) {
        return false;
      }
      if (this.element === eventTarget) {
        return true;
      } else if (eventTarget instanceof Element && this.element.contains(eventTarget)) {
        return this.scope.containsElement(eventTarget);
      } else {
        return this.scope.containsElement(this.action.element);
      }
    }
    get controller() {
      return this.context.controller;
    }
    get methodName() {
      return this.action.methodName;
    }
    get element() {
      return this.scope.element;
    }
    get scope() {
      return this.context.scope;
    }
  };

  // src/mutation-observers/element_observer.ts
  var ElementObserver = class {
    constructor(element, delegate) {
      this.mutationObserverInit = { attributes: true, childList: true, subtree: true };
      this.element = element;
      this.started = false;
      this.delegate = delegate;
      this.elements = /* @__PURE__ */ new Set();
      this.mutationObserver = new MutationObserver((mutations) => this.processMutations(mutations));
    }
    start() {
      if (!this.started) {
        this.started = true;
        this.mutationObserver.observe(this.element, this.mutationObserverInit);
        this.refresh();
      }
    }
    pause(callback) {
      if (this.started) {
        this.mutationObserver.disconnect();
        this.started = false;
      }
      callback();
      if (!this.started) {
        this.mutationObserver.observe(this.element, this.mutationObserverInit);
        this.started = true;
      }
    }
    stop() {
      if (this.started) {
        this.mutationObserver.takeRecords();
        this.mutationObserver.disconnect();
        this.started = false;
      }
    }
    refresh() {
      if (this.started) {
        const matches = new Set(this.matchElementsInTree());
        for (const element of Array.from(this.elements)) {
          if (!matches.has(element)) {
            this.removeElement(element);
          }
        }
        for (const element of Array.from(matches)) {
          this.addElement(element);
        }
      }
    }
    // Mutation record processing
    processMutations(mutations) {
      if (this.started) {
        for (const mutation of mutations) {
          this.processMutation(mutation);
        }
      }
    }
    processMutation(mutation) {
      if (mutation.type == "attributes") {
        this.processAttributeChange(mutation.target, mutation.attributeName);
      } else if (mutation.type == "childList") {
        this.processRemovedNodes(mutation.removedNodes);
        this.processAddedNodes(mutation.addedNodes);
      }
    }
    processAttributeChange(element, attributeName) {
      if (this.elements.has(element)) {
        if (this.delegate.elementAttributeChanged && this.matchElement(element)) {
          this.delegate.elementAttributeChanged(element, attributeName);
        } else {
          this.removeElement(element);
        }
      } else if (this.matchElement(element)) {
        this.addElement(element);
      }
    }
    processRemovedNodes(nodes) {
      for (const node of Array.from(nodes)) {
        const element = this.elementFromNode(node);
        if (element) {
          this.processTree(element, this.removeElement);
        }
      }
    }
    processAddedNodes(nodes) {
      for (const node of Array.from(nodes)) {
        const element = this.elementFromNode(node);
        if (element && this.elementIsActive(element)) {
          this.processTree(element, this.addElement);
        }
      }
    }
    // Element matching
    matchElement(element) {
      return this.delegate.matchElement(element);
    }
    matchElementsInTree(tree = this.element) {
      return this.delegate.matchElementsInTree(tree);
    }
    processTree(tree, processor) {
      for (const element of this.matchElementsInTree(tree)) {
        processor.call(this, element);
      }
    }
    elementFromNode(node) {
      if (node.nodeType == Node.ELEMENT_NODE) {
        return node;
      }
    }
    elementIsActive(element) {
      if (element.isConnected != this.element.isConnected) {
        return false;
      } else {
        return this.element.contains(element);
      }
    }
    // Element tracking
    addElement(element) {
      if (!this.elements.has(element)) {
        if (this.elementIsActive(element)) {
          this.elements.add(element);
          if (this.delegate.elementMatched) {
            this.delegate.elementMatched(element);
          }
        }
      }
    }
    removeElement(element) {
      if (this.elements.has(element)) {
        this.elements.delete(element);
        if (this.delegate.elementUnmatched) {
          this.delegate.elementUnmatched(element);
        }
      }
    }
  };

  // src/mutation-observers/attribute_observer.ts
  var AttributeObserver = class {
    constructor(element, attributeName, delegate) {
      this.attributeName = attributeName;
      this.delegate = delegate;
      this.elementObserver = new ElementObserver(element, this);
    }
    get element() {
      return this.elementObserver.element;
    }
    get selector() {
      return `[${this.attributeName}]`;
    }
    start() {
      this.elementObserver.start();
    }
    pause(callback) {
      this.elementObserver.pause(callback);
    }
    stop() {
      this.elementObserver.stop();
    }
    refresh() {
      this.elementObserver.refresh();
    }
    get started() {
      return this.elementObserver.started;
    }
    // Element observer delegate
    matchElement(element) {
      return element.hasAttribute(this.attributeName);
    }
    matchElementsInTree(tree) {
      const match = this.matchElement(tree) ? [tree] : [];
      const matches = Array.from(tree.querySelectorAll(this.selector));
      return match.concat(matches);
    }
    elementMatched(element) {
      if (this.delegate.elementMatchedAttribute) {
        this.delegate.elementMatchedAttribute(element, this.attributeName);
      }
    }
    elementUnmatched(element) {
      if (this.delegate.elementUnmatchedAttribute) {
        this.delegate.elementUnmatchedAttribute(element, this.attributeName);
      }
    }
    elementAttributeChanged(element, attributeName) {
      if (this.delegate.elementAttributeValueChanged && this.attributeName == attributeName) {
        this.delegate.elementAttributeValueChanged(element, attributeName);
      }
    }
  };

  // src/multimap/set_operations.ts
  function add(map, key, value) {
    fetch(map, key).add(value);
  }
  function del(map, key, value) {
    fetch(map, key).delete(value);
    prune(map, key);
  }
  function fetch(map, key) {
    let values = map.get(key);
    if (!values) {
      values = /* @__PURE__ */ new Set();
      map.set(key, values);
    }
    return values;
  }
  function prune(map, key) {
    const values = map.get(key);
    if (values != null && values.size == 0) {
      map.delete(key);
    }
  }

  // src/multimap/multimap.ts
  var Multimap = class {
    constructor() {
      this.valuesByKey = /* @__PURE__ */ new Map();
    }
    get keys() {
      return Array.from(this.valuesByKey.keys());
    }
    get values() {
      const sets = Array.from(this.valuesByKey.values());
      return sets.reduce((values, set) => values.concat(Array.from(set)), []);
    }
    get size() {
      const sets = Array.from(this.valuesByKey.values());
      return sets.reduce((size, set) => size + set.size, 0);
    }
    add(key, value) {
      add(this.valuesByKey, key, value);
    }
    delete(key, value) {
      del(this.valuesByKey, key, value);
    }
    has(key, value) {
      const values = this.valuesByKey.get(key);
      return values != null && values.has(value);
    }
    hasKey(key) {
      return this.valuesByKey.has(key);
    }
    hasValue(value) {
      const sets = Array.from(this.valuesByKey.values());
      return sets.some((set) => set.has(value));
    }
    getValuesForKey(key) {
      const values = this.valuesByKey.get(key);
      return values ? Array.from(values) : [];
    }
    getKeysForValue(value) {
      return Array.from(this.valuesByKey).filter(([_key, values]) => values.has(value)).map(([key, _values]) => key);
    }
  };

  // src/mutation-observers/selector_observer.ts
  var SelectorObserver = class {
    constructor(element, selector, delegate, details) {
      this._selector = selector;
      this.details = details;
      this.elementObserver = new ElementObserver(element, this);
      this.delegate = delegate;
      this.matchesByElement = new Multimap();
    }
    get started() {
      return this.elementObserver.started;
    }
    get selector() {
      return this._selector;
    }
    set selector(selector) {
      this._selector = selector;
      this.refresh();
    }
    start() {
      this.elementObserver.start();
    }
    pause(callback) {
      this.elementObserver.pause(callback);
    }
    stop() {
      this.elementObserver.stop();
    }
    refresh() {
      this.elementObserver.refresh();
    }
    get element() {
      return this.elementObserver.element;
    }
    // Element observer delegate
    matchElement(element) {
      const { selector } = this;
      if (selector) {
        const matches = element.matches(selector);
        if (this.delegate.selectorMatchElement) {
          return matches && this.delegate.selectorMatchElement(element, this.details);
        }
        return matches;
      } else {
        return false;
      }
    }
    matchElementsInTree(tree) {
      const { selector } = this;
      if (selector) {
        const match = this.matchElement(tree) ? [tree] : [];
        const matches = Array.from(tree.querySelectorAll(selector)).filter((match2) => this.matchElement(match2));
        return match.concat(matches);
      } else {
        return [];
      }
    }
    elementMatched(element) {
      const { selector } = this;
      if (selector) {
        this.selectorMatched(element, selector);
      }
    }
    elementUnmatched(element) {
      const selectors = this.matchesByElement.getKeysForValue(element);
      for (const selector of selectors) {
        this.selectorUnmatched(element, selector);
      }
    }
    elementAttributeChanged(element, _attributeName) {
      const { selector } = this;
      if (selector) {
        const matches = this.matchElement(element);
        const matchedBefore = this.matchesByElement.has(selector, element);
        if (matches && !matchedBefore) {
          this.selectorMatched(element, selector);
        } else if (!matches && matchedBefore) {
          this.selectorUnmatched(element, selector);
        }
      }
    }
    // Selector management
    selectorMatched(element, selector) {
      this.delegate.selectorMatched(element, selector, this.details);
      this.matchesByElement.add(selector, element);
    }
    selectorUnmatched(element, selector) {
      this.delegate.selectorUnmatched(element, selector, this.details);
      this.matchesByElement.delete(selector, element);
    }
  };

  // src/mutation-observers/string_map_observer.ts
  var StringMapObserver = class {
    constructor(element, delegate) {
      this.element = element;
      this.delegate = delegate;
      this.started = false;
      this.stringMap = /* @__PURE__ */ new Map();
      this.mutationObserver = new MutationObserver((mutations) => this.processMutations(mutations));
    }
    start() {
      if (!this.started) {
        this.started = true;
        this.mutationObserver.observe(this.element, { attributes: true, attributeOldValue: true });
        this.refresh();
      }
    }
    stop() {
      if (this.started) {
        this.mutationObserver.takeRecords();
        this.mutationObserver.disconnect();
        this.started = false;
      }
    }
    refresh() {
      if (this.started) {
        for (const attributeName of this.knownAttributeNames) {
          this.refreshAttribute(attributeName, null);
        }
      }
    }
    // Mutation record processing
    processMutations(mutations) {
      if (this.started) {
        for (const mutation of mutations) {
          this.processMutation(mutation);
        }
      }
    }
    processMutation(mutation) {
      const attributeName = mutation.attributeName;
      if (attributeName) {
        this.refreshAttribute(attributeName, mutation.oldValue);
      }
    }
    // State tracking
    refreshAttribute(attributeName, oldValue) {
      const key = this.delegate.getStringMapKeyForAttribute(attributeName);
      if (key != null) {
        if (!this.stringMap.has(attributeName)) {
          this.stringMapKeyAdded(key, attributeName);
        }
        const value = this.element.getAttribute(attributeName);
        if (this.stringMap.get(attributeName) != value) {
          this.stringMapValueChanged(value, key, oldValue);
        }
        if (value == null) {
          const oldValue2 = this.stringMap.get(attributeName);
          this.stringMap.delete(attributeName);
          if (oldValue2) this.stringMapKeyRemoved(key, attributeName, oldValue2);
        } else {
          this.stringMap.set(attributeName, value);
        }
      }
    }
    stringMapKeyAdded(key, attributeName) {
      if (this.delegate.stringMapKeyAdded) {
        this.delegate.stringMapKeyAdded(key, attributeName);
      }
    }
    stringMapValueChanged(value, key, oldValue) {
      if (this.delegate.stringMapValueChanged) {
        this.delegate.stringMapValueChanged(value, key, oldValue);
      }
    }
    stringMapKeyRemoved(key, attributeName, oldValue) {
      if (this.delegate.stringMapKeyRemoved) {
        this.delegate.stringMapKeyRemoved(key, attributeName, oldValue);
      }
    }
    get knownAttributeNames() {
      return Array.from(new Set(this.currentAttributeNames.concat(this.recordedAttributeNames)));
    }
    get currentAttributeNames() {
      return Array.from(this.element.attributes).map((attribute) => attribute.name);
    }
    get recordedAttributeNames() {
      return Array.from(this.stringMap.keys());
    }
  };

  // src/mutation-observers/token_list_observer.ts
  var TokenListObserver = class {
    constructor(element, attributeName, delegate) {
      this.attributeObserver = new AttributeObserver(element, attributeName, this);
      this.delegate = delegate;
      this.tokensByElement = new Multimap();
    }
    get started() {
      return this.attributeObserver.started;
    }
    start() {
      this.attributeObserver.start();
    }
    pause(callback) {
      this.attributeObserver.pause(callback);
    }
    stop() {
      this.attributeObserver.stop();
    }
    refresh() {
      this.attributeObserver.refresh();
    }
    get element() {
      return this.attributeObserver.element;
    }
    get attributeName() {
      return this.attributeObserver.attributeName;
    }
    // Attribute observer delegate
    elementMatchedAttribute(element) {
      this.tokensMatched(this.readTokensForElement(element));
    }
    elementAttributeValueChanged(element) {
      const [unmatchedTokens, matchedTokens] = this.refreshTokensForElement(element);
      this.tokensUnmatched(unmatchedTokens);
      this.tokensMatched(matchedTokens);
    }
    elementUnmatchedAttribute(element) {
      this.tokensUnmatched(this.tokensByElement.getValuesForKey(element));
    }
    tokensMatched(tokens) {
      tokens.forEach((token) => this.tokenMatched(token));
    }
    tokensUnmatched(tokens) {
      tokens.forEach((token) => this.tokenUnmatched(token));
    }
    tokenMatched(token) {
      this.delegate.tokenMatched(token);
      this.tokensByElement.add(token.element, token);
    }
    tokenUnmatched(token) {
      this.delegate.tokenUnmatched(token);
      this.tokensByElement.delete(token.element, token);
    }
    refreshTokensForElement(element) {
      const previousTokens = this.tokensByElement.getValuesForKey(element);
      const currentTokens = this.readTokensForElement(element);
      const firstDifferingIndex = zip(previousTokens, currentTokens).findIndex(
        ([previousToken, currentToken]) => !tokensAreEqual(previousToken, currentToken)
      );
      if (firstDifferingIndex == -1) {
        return [[], []];
      } else {
        return [previousTokens.slice(firstDifferingIndex), currentTokens.slice(firstDifferingIndex)];
      }
    }
    readTokensForElement(element) {
      const attributeName = this.attributeName;
      const tokenString = element.getAttribute(attributeName) || "";
      return parseTokenString(tokenString, element, attributeName);
    }
  };
  function parseTokenString(tokenString, element, attributeName) {
    return tokenString.trim().split(/\s+/).filter((content) => content.length).map((content, index) => ({ element, attributeName, content, index }));
  }
  function zip(left, right) {
    const length = Math.max(left.length, right.length);
    return Array.from({ length }, (_, index) => [left[index], right[index]]);
  }
  function tokensAreEqual(left, right) {
    return left && right && left.index == right.index && left.content == right.content;
  }

  // src/mutation-observers/value_list_observer.ts
  var ValueListObserver = class {
    constructor(element, attributeName, delegate) {
      this.tokenListObserver = new TokenListObserver(element, attributeName, this);
      this.delegate = delegate;
      this.parseResultsByToken = /* @__PURE__ */ new WeakMap();
      this.valuesByTokenByElement = /* @__PURE__ */ new WeakMap();
    }
    get started() {
      return this.tokenListObserver.started;
    }
    start() {
      this.tokenListObserver.start();
    }
    stop() {
      this.tokenListObserver.stop();
    }
    refresh() {
      this.tokenListObserver.refresh();
    }
    get element() {
      return this.tokenListObserver.element;
    }
    get attributeName() {
      return this.tokenListObserver.attributeName;
    }
    tokenMatched(token) {
      const { element } = token;
      const { value } = this.fetchParseResultForToken(token);
      if (value) {
        this.fetchValuesByTokenForElement(element).set(token, value);
        this.delegate.elementMatchedValue(element, value);
      }
    }
    tokenUnmatched(token) {
      const { element } = token;
      const { value } = this.fetchParseResultForToken(token);
      if (value) {
        this.fetchValuesByTokenForElement(element).delete(token);
        this.delegate.elementUnmatchedValue(element, value);
      }
    }
    fetchParseResultForToken(token) {
      let parseResult = this.parseResultsByToken.get(token);
      if (!parseResult) {
        parseResult = this.parseToken(token);
        this.parseResultsByToken.set(token, parseResult);
      }
      return parseResult;
    }
    fetchValuesByTokenForElement(element) {
      let valuesByToken = this.valuesByTokenByElement.get(element);
      if (!valuesByToken) {
        valuesByToken = /* @__PURE__ */ new Map();
        this.valuesByTokenByElement.set(element, valuesByToken);
      }
      return valuesByToken;
    }
    parseToken(token) {
      try {
        const value = this.delegate.parseValueForToken(token);
        return { value };
      } catch (error2) {
        return { error: error2 };
      }
    }
  };

  // src/core/binding_observer.ts
  var BindingObserver = class {
    constructor(context, delegate) {
      this.context = context;
      this.delegate = delegate;
      this.bindingsByAction = /* @__PURE__ */ new Map();
    }
    start() {
      if (!this.valueListObserver) {
        this.valueListObserver = new ValueListObserver(this.element, this.actionAttribute, this);
        this.valueListObserver.start();
      }
    }
    stop() {
      if (this.valueListObserver) {
        this.valueListObserver.stop();
        delete this.valueListObserver;
        this.disconnectAllActions();
      }
    }
    get element() {
      return this.context.element;
    }
    get identifier() {
      return this.context.identifier;
    }
    get actionAttribute() {
      return this.schema.actionAttribute;
    }
    get schema() {
      return this.context.schema;
    }
    get bindings() {
      return Array.from(this.bindingsByAction.values());
    }
    connectAction(action) {
      const binding = new Binding(this.context, action);
      this.bindingsByAction.set(action, binding);
      this.delegate.bindingConnected(binding);
    }
    disconnectAction(action) {
      const binding = this.bindingsByAction.get(action);
      if (binding) {
        this.bindingsByAction.delete(action);
        this.delegate.bindingDisconnected(binding);
      }
    }
    disconnectAllActions() {
      this.bindings.forEach((binding) => this.delegate.bindingDisconnected(binding, true));
      this.bindingsByAction.clear();
    }
    // Value observer delegate
    parseValueForToken(token) {
      const action = Action.forToken(token, this.schema);
      if (action.identifier == this.identifier) {
        return action;
      }
    }
    elementMatchedValue(element, action) {
      this.connectAction(action);
    }
    elementUnmatchedValue(element, action) {
      this.disconnectAction(action);
    }
  };

  // src/core/value_observer.ts
  var ValueObserver = class {
    constructor(context, receiver) {
      this.context = context;
      this.receiver = receiver;
      this.stringMapObserver = new StringMapObserver(this.element, this);
      this.valueDescriptorMap = this.controller.valueDescriptorMap;
    }
    start() {
      this.stringMapObserver.start();
      this.invokeChangedCallbacksForDefaultValues();
    }
    stop() {
      this.stringMapObserver.stop();
    }
    get element() {
      return this.context.element;
    }
    get controller() {
      return this.context.controller;
    }
    // String map observer delegate
    getStringMapKeyForAttribute(attributeName) {
      if (attributeName in this.valueDescriptorMap) {
        return this.valueDescriptorMap[attributeName].name;
      }
    }
    stringMapKeyAdded(key, attributeName) {
      const descriptor = this.valueDescriptorMap[attributeName];
      if (!this.hasValue(key)) {
        this.invokeChangedCallback(key, descriptor.writer(this.receiver[key]), descriptor.writer(descriptor.defaultValue));
      }
    }
    stringMapValueChanged(value, name, oldValue) {
      const descriptor = this.valueDescriptorNameMap[name];
      if (value === null) return;
      if (oldValue === null) {
        oldValue = descriptor.writer(descriptor.defaultValue);
      }
      this.invokeChangedCallback(name, value, oldValue);
    }
    stringMapKeyRemoved(key, attributeName, oldValue) {
      const descriptor = this.valueDescriptorNameMap[key];
      if (this.hasValue(key)) {
        this.invokeChangedCallback(key, descriptor.writer(this.receiver[key]), oldValue);
      } else {
        this.invokeChangedCallback(key, descriptor.writer(descriptor.defaultValue), oldValue);
      }
    }
    invokeChangedCallbacksForDefaultValues() {
      for (const { key, name, defaultValue, writer } of this.valueDescriptors) {
        if (defaultValue != void 0 && !this.controller.data.has(key)) {
          this.invokeChangedCallback(name, writer(defaultValue), void 0);
        }
      }
    }
    invokeChangedCallback(name, rawValue, rawOldValue) {
      const changedMethodName = `${name}Changed`;
      const changedMethod = this.receiver[changedMethodName];
      if (typeof changedMethod == "function") {
        const descriptor = this.valueDescriptorNameMap[name];
        try {
          const value = descriptor.reader(rawValue);
          let oldValue = rawOldValue;
          if (rawOldValue) {
            oldValue = descriptor.reader(rawOldValue);
          }
          changedMethod.call(this.receiver, value, oldValue);
        } catch (error2) {
          if (error2 instanceof TypeError) {
            error2.message = `Stimulus Value "${this.context.identifier}.${descriptor.name}" - ${error2.message}`;
          }
          throw error2;
        }
      }
    }
    get valueDescriptors() {
      const { valueDescriptorMap } = this;
      return Object.keys(valueDescriptorMap).map((key) => valueDescriptorMap[key]);
    }
    get valueDescriptorNameMap() {
      const descriptors = {};
      Object.keys(this.valueDescriptorMap).forEach((key) => {
        const descriptor = this.valueDescriptorMap[key];
        descriptors[descriptor.name] = descriptor;
      });
      return descriptors;
    }
    hasValue(attributeName) {
      const descriptor = this.valueDescriptorNameMap[attributeName];
      const hasMethodName = `has${capitalize(descriptor.name)}`;
      return this.receiver[hasMethodName];
    }
  };

  // src/core/target_observer.ts
  var TargetObserver = class {
    constructor(context, delegate) {
      this.context = context;
      this.delegate = delegate;
      this.targetsByName = new Multimap();
    }
    start() {
      if (!this.tokenListObserver) {
        this.tokenListObserver = new TokenListObserver(this.element, this.attributeName, this);
        this.tokenListObserver.start();
      }
    }
    stop() {
      if (this.tokenListObserver) {
        this.disconnectAllTargets();
        this.tokenListObserver.stop();
        delete this.tokenListObserver;
      }
    }
    // Token list observer delegate
    tokenMatched({ element, content: name }) {
      if (this.scope.containsElement(element)) {
        this.connectTarget(element, name);
      }
    }
    tokenUnmatched({ element, content: name }) {
      this.disconnectTarget(element, name);
    }
    // Target management
    connectTarget(element, name) {
      var _a;
      if (!this.targetsByName.has(name, element)) {
        this.targetsByName.add(name, element);
        (_a = this.tokenListObserver) == null ? void 0 : _a.pause(() => this.delegate.targetConnected(element, name));
      }
    }
    disconnectTarget(element, name) {
      var _a;
      if (this.targetsByName.has(name, element)) {
        this.targetsByName.delete(name, element);
        (_a = this.tokenListObserver) == null ? void 0 : _a.pause(() => this.delegate.targetDisconnected(element, name));
      }
    }
    disconnectAllTargets() {
      for (const name of this.targetsByName.keys) {
        for (const element of this.targetsByName.getValuesForKey(name)) {
          this.disconnectTarget(element, name);
        }
      }
    }
    // Private
    get attributeName() {
      return `data-${this.context.identifier}-target`;
    }
    get element() {
      return this.context.element;
    }
    get scope() {
      return this.context.scope;
    }
  };

  // src/core/inheritable_statics.ts
  function readInheritableStaticArrayValues(constructor, propertyName) {
    const ancestors = getAncestorsForConstructor(constructor);
    return Array.from(
      ancestors.reduce((values, constructor2) => {
        getOwnStaticArrayValues(constructor2, propertyName).forEach((name) => values.add(name));
        return values;
      }, /* @__PURE__ */ new Set())
    );
  }
  function readInheritableStaticObjectPairs(constructor, propertyName) {
    const ancestors = getAncestorsForConstructor(constructor);
    return ancestors.reduce((pairs, constructor2) => {
      pairs.push(...getOwnStaticObjectPairs(constructor2, propertyName));
      return pairs;
    }, []);
  }
  function getAncestorsForConstructor(constructor) {
    const ancestors = [];
    while (constructor) {
      ancestors.push(constructor);
      constructor = Object.getPrototypeOf(constructor);
    }
    return ancestors.reverse();
  }
  function getOwnStaticArrayValues(constructor, propertyName) {
    const definition = constructor[propertyName];
    return Array.isArray(definition) ? definition : [];
  }
  function getOwnStaticObjectPairs(constructor, propertyName) {
    const definition = constructor[propertyName];
    return definition ? Object.keys(definition).map((key) => [key, definition[key]]) : [];
  }

  // src/core/outlet_observer.ts
  var OutletObserver = class {
    constructor(context, delegate) {
      this.started = false;
      this.context = context;
      this.delegate = delegate;
      this.outletsByName = new Multimap();
      this.outletElementsByName = new Multimap();
      this.selectorObserverMap = /* @__PURE__ */ new Map();
      this.attributeObserverMap = /* @__PURE__ */ new Map();
    }
    start() {
      if (!this.started) {
        this.outletDefinitions.forEach((outletName) => {
          this.setupSelectorObserverForOutlet(outletName);
          this.setupAttributeObserverForOutlet(outletName);
        });
        this.started = true;
        this.dependentContexts.forEach((context) => context.refresh());
      }
    }
    refresh() {
      this.selectorObserverMap.forEach((observer) => observer.refresh());
      this.attributeObserverMap.forEach((observer) => observer.refresh());
    }
    stop() {
      if (this.started) {
        this.started = false;
        this.disconnectAllOutlets();
        this.stopSelectorObservers();
        this.stopAttributeObservers();
      }
    }
    stopSelectorObservers() {
      if (this.selectorObserverMap.size > 0) {
        this.selectorObserverMap.forEach((observer) => observer.stop());
        this.selectorObserverMap.clear();
      }
    }
    stopAttributeObservers() {
      if (this.attributeObserverMap.size > 0) {
        this.attributeObserverMap.forEach((observer) => observer.stop());
        this.attributeObserverMap.clear();
      }
    }
    // Selector observer delegate
    selectorMatched(element, _selector, { outletName }) {
      const outlet = this.getOutlet(element, outletName);
      if (outlet) {
        this.connectOutlet(outlet, element, outletName);
      }
    }
    selectorUnmatched(element, _selector, { outletName }) {
      const outlet = this.getOutletFromMap(element, outletName);
      if (outlet) {
        this.disconnectOutlet(outlet, element, outletName);
      }
    }
    selectorMatchElement(element, { outletName }) {
      const selector = this.selector(outletName);
      const hasOutlet = this.hasOutlet(element, outletName);
      const hasOutletController = element.matches(`[${this.schema.controllerAttribute}~=${outletName}]`);
      if (selector) {
        return hasOutlet && hasOutletController && element.matches(selector);
      } else {
        return false;
      }
    }
    // Attribute observer delegate
    elementMatchedAttribute(_element, attributeName) {
      const outletName = this.getOutletNameFromOutletAttributeName(attributeName);
      if (outletName) {
        this.updateSelectorObserverForOutlet(outletName);
      }
    }
    elementAttributeValueChanged(_element, attributeName) {
      const outletName = this.getOutletNameFromOutletAttributeName(attributeName);
      if (outletName) {
        this.updateSelectorObserverForOutlet(outletName);
      }
    }
    elementUnmatchedAttribute(_element, attributeName) {
      const outletName = this.getOutletNameFromOutletAttributeName(attributeName);
      if (outletName) {
        this.updateSelectorObserverForOutlet(outletName);
      }
    }
    // Outlet management
    connectOutlet(outlet, element, outletName) {
      var _a;
      if (!this.outletElementsByName.has(outletName, element)) {
        this.outletsByName.add(outletName, outlet);
        this.outletElementsByName.add(outletName, element);
        (_a = this.selectorObserverMap.get(outletName)) == null ? void 0 : _a.pause(() => this.delegate.outletConnected(outlet, element, outletName));
      }
    }
    disconnectOutlet(outlet, element, outletName) {
      var _a;
      if (this.outletElementsByName.has(outletName, element)) {
        this.outletsByName.delete(outletName, outlet);
        this.outletElementsByName.delete(outletName, element);
        (_a = this.selectorObserverMap.get(outletName)) == null ? void 0 : _a.pause(() => this.delegate.outletDisconnected(outlet, element, outletName));
      }
    }
    disconnectAllOutlets() {
      for (const outletName of this.outletElementsByName.keys) {
        for (const element of this.outletElementsByName.getValuesForKey(outletName)) {
          for (const outlet of this.outletsByName.getValuesForKey(outletName)) {
            this.disconnectOutlet(outlet, element, outletName);
          }
        }
      }
    }
    // Observer management
    updateSelectorObserverForOutlet(outletName) {
      const observer = this.selectorObserverMap.get(outletName);
      if (observer) {
        observer.selector = this.selector(outletName);
      }
    }
    setupSelectorObserverForOutlet(outletName) {
      const selector = this.selector(outletName);
      const selectorObserver = new SelectorObserver(document.body, selector, this, { outletName });
      this.selectorObserverMap.set(outletName, selectorObserver);
      selectorObserver.start();
    }
    setupAttributeObserverForOutlet(outletName) {
      const attributeName = this.attributeNameForOutletName(outletName);
      const attributeObserver = new AttributeObserver(this.scope.element, attributeName, this);
      this.attributeObserverMap.set(outletName, attributeObserver);
      attributeObserver.start();
    }
    // Private
    selector(outletName) {
      return this.scope.outlets.getSelectorForOutletName(outletName);
    }
    attributeNameForOutletName(outletName) {
      return this.scope.schema.outletAttributeForScope(this.identifier, outletName);
    }
    getOutletNameFromOutletAttributeName(attributeName) {
      return this.outletDefinitions.find((outletName) => this.attributeNameForOutletName(outletName) === attributeName);
    }
    get outletDependencies() {
      const dependencies = new Multimap();
      this.router.modules.forEach((module) => {
        const constructor = module.definition.controllerConstructor;
        const outlets = readInheritableStaticArrayValues(constructor, "outlets");
        outlets.forEach((outlet) => dependencies.add(outlet, module.identifier));
      });
      return dependencies;
    }
    get outletDefinitions() {
      return this.outletDependencies.getKeysForValue(this.identifier);
    }
    get dependentControllerIdentifiers() {
      return this.outletDependencies.getValuesForKey(this.identifier);
    }
    get dependentContexts() {
      const identifiers = this.dependentControllerIdentifiers;
      return this.router.contexts.filter((context) => identifiers.includes(context.identifier));
    }
    hasOutlet(element, outletName) {
      return !!this.getOutlet(element, outletName) || !!this.getOutletFromMap(element, outletName);
    }
    getOutlet(element, outletName) {
      return this.application.getControllerForElementAndIdentifier(element, outletName);
    }
    getOutletFromMap(element, outletName) {
      return this.outletsByName.getValuesForKey(outletName).find((outlet) => outlet.element === element);
    }
    get scope() {
      return this.context.scope;
    }
    get schema() {
      return this.context.schema;
    }
    get identifier() {
      return this.context.identifier;
    }
    get application() {
      return this.context.application;
    }
    get router() {
      return this.application.router;
    }
  };

  // src/core/context.ts
  var Context = class {
    constructor(module, scope) {
      // Debug logging
      this.logDebugActivity = (functionName, detail = {}) => {
        const { identifier, controller, element } = this;
        detail = Object.assign({ identifier, controller, element }, detail);
        this.application.logDebugActivity(this.identifier, functionName, detail);
      };
      this.module = module;
      this.scope = scope;
      this.controller = new module.controllerConstructor(this);
      this.bindingObserver = new BindingObserver(this, this.dispatcher);
      this.valueObserver = new ValueObserver(this, this.controller);
      this.targetObserver = new TargetObserver(this, this);
      this.outletObserver = new OutletObserver(this, this);
      try {
        this.controller.initialize();
        this.logDebugActivity("initialize");
      } catch (error2) {
        this.handleError(error2, "initializing controller");
      }
    }
    connect() {
      this.bindingObserver.start();
      this.valueObserver.start();
      this.targetObserver.start();
      this.outletObserver.start();
      try {
        this.controller.connect();
        this.logDebugActivity("connect");
      } catch (error2) {
        this.handleError(error2, "connecting controller");
      }
    }
    refresh() {
      this.outletObserver.refresh();
    }
    disconnect() {
      try {
        this.controller.disconnect();
        this.logDebugActivity("disconnect");
      } catch (error2) {
        this.handleError(error2, "disconnecting controller");
      }
      this.outletObserver.stop();
      this.targetObserver.stop();
      this.valueObserver.stop();
      this.bindingObserver.stop();
    }
    get application() {
      return this.module.application;
    }
    get identifier() {
      return this.module.identifier;
    }
    get schema() {
      return this.application.schema;
    }
    get dispatcher() {
      return this.application.dispatcher;
    }
    get element() {
      return this.scope.element;
    }
    get parentElement() {
      return this.element.parentElement;
    }
    // Error handling
    handleError(error2, message, detail = {}) {
      const { identifier, controller, element } = this;
      detail = Object.assign({ identifier, controller, element }, detail);
      this.application.handleError(error2, `Error ${message}`, detail);
    }
    // Target observer delegate
    targetConnected(element, name) {
      this.invokeControllerMethod(`${name}TargetConnected`, element);
    }
    targetDisconnected(element, name) {
      this.invokeControllerMethod(`${name}TargetDisconnected`, element);
    }
    // Outlet observer delegate
    outletConnected(outlet, element, name) {
      this.invokeControllerMethod(`${namespaceCamelize(name)}OutletConnected`, outlet, element);
    }
    outletDisconnected(outlet, element, name) {
      this.invokeControllerMethod(`${namespaceCamelize(name)}OutletDisconnected`, outlet, element);
    }
    // Private
    invokeControllerMethod(methodName, ...args) {
      const controller = this.controller;
      if (typeof controller[methodName] == "function") {
        controller[methodName](...args);
      }
    }
  };

  // src/core/blessing.ts
  function bless(constructor) {
    return shadow(constructor, getBlessedProperties(constructor));
  }
  function shadow(constructor, properties) {
    const shadowConstructor = extend(constructor);
    const shadowProperties = getShadowProperties(constructor.prototype, properties);
    Object.defineProperties(shadowConstructor.prototype, shadowProperties);
    return shadowConstructor;
  }
  function getBlessedProperties(constructor) {
    const blessings = readInheritableStaticArrayValues(constructor, "blessings");
    return blessings.reduce((blessedProperties, blessing) => {
      const properties = blessing(constructor);
      for (const key in properties) {
        const descriptor = blessedProperties[key] || {};
        blessedProperties[key] = Object.assign(descriptor, properties[key]);
      }
      return blessedProperties;
    }, {});
  }
  function getShadowProperties(prototype, properties) {
    return getOwnKeys(properties).reduce((shadowProperties, key) => {
      const descriptor = getShadowedDescriptor(prototype, properties, key);
      if (descriptor) {
        Object.assign(shadowProperties, { [key]: descriptor });
      }
      return shadowProperties;
    }, {});
  }
  function getShadowedDescriptor(prototype, properties, key) {
    const shadowingDescriptor = Object.getOwnPropertyDescriptor(prototype, key);
    const shadowedByValue = shadowingDescriptor && "value" in shadowingDescriptor;
    if (!shadowedByValue) {
      const descriptor = Object.getOwnPropertyDescriptor(properties, key).value;
      if (shadowingDescriptor) {
        descriptor.get = shadowingDescriptor.get || descriptor.get;
        descriptor.set = shadowingDescriptor.set || descriptor.set;
      }
      return descriptor;
    }
  }
  var getOwnKeys = (() => {
    if (typeof Object.getOwnPropertySymbols == "function") {
      return (object) => [...Object.getOwnPropertyNames(object), ...Object.getOwnPropertySymbols(object)];
    } else {
      return Object.getOwnPropertyNames;
    }
  })();
  var extend = (() => {
    function extendWithReflect(constructor) {
      function extended() {
        return Reflect.construct(constructor, arguments, new.target);
      }
      extended.prototype = Object.create(constructor.prototype, {
        constructor: { value: extended }
      });
      Reflect.setPrototypeOf(extended, constructor);
      return extended;
    }
    function testReflectExtension() {
      const a = function() {
        this.a.call(this);
      };
      const b = extendWithReflect(a);
      b.prototype.a = function() {
      };
      return new b();
    }
    try {
      testReflectExtension();
      return extendWithReflect;
    } catch (error2) {
      return (constructor) => class extended extends constructor {
      };
    }
  })();

  // src/core/definition.ts
  function blessDefinition(definition) {
    return {
      identifier: definition.identifier,
      controllerConstructor: bless(definition.controllerConstructor)
    };
  }

  // src/core/module.ts
  var Module = class {
    constructor(application, definition) {
      this.application = application;
      this.definition = blessDefinition(definition);
      this.contextsByScope = /* @__PURE__ */ new WeakMap();
      this.connectedContexts = /* @__PURE__ */ new Set();
    }
    get identifier() {
      return this.definition.identifier;
    }
    get controllerConstructor() {
      return this.definition.controllerConstructor;
    }
    get contexts() {
      return Array.from(this.connectedContexts);
    }
    connectContextForScope(scope) {
      const context = this.fetchContextForScope(scope);
      this.connectedContexts.add(context);
      context.connect();
    }
    disconnectContextForScope(scope) {
      const context = this.contextsByScope.get(scope);
      if (context) {
        this.connectedContexts.delete(context);
        context.disconnect();
      }
    }
    fetchContextForScope(scope) {
      let context = this.contextsByScope.get(scope);
      if (!context) {
        context = new Context(this, scope);
        this.contextsByScope.set(scope, context);
      }
      return context;
    }
  };

  // src/core/class_map.ts
  var ClassMap = class {
    constructor(scope) {
      this.scope = scope;
    }
    has(name) {
      return this.data.has(this.getDataKey(name));
    }
    get(name) {
      return this.getAll(name)[0];
    }
    getAll(name) {
      const tokenString = this.data.get(this.getDataKey(name)) || "";
      return tokenize(tokenString);
    }
    getAttributeName(name) {
      return this.data.getAttributeNameForKey(this.getDataKey(name));
    }
    getDataKey(name) {
      return `${name}-class`;
    }
    get data() {
      return this.scope.data;
    }
  };

  // src/core/data_map.ts
  var DataMap = class {
    constructor(scope) {
      this.scope = scope;
    }
    get element() {
      return this.scope.element;
    }
    get identifier() {
      return this.scope.identifier;
    }
    get(key) {
      const name = this.getAttributeNameForKey(key);
      return this.element.getAttribute(name);
    }
    set(key, value) {
      const name = this.getAttributeNameForKey(key);
      this.element.setAttribute(name, value);
      return this.get(key);
    }
    has(key) {
      const name = this.getAttributeNameForKey(key);
      return this.element.hasAttribute(name);
    }
    delete(key) {
      if (this.has(key)) {
        const name = this.getAttributeNameForKey(key);
        this.element.removeAttribute(name);
        return true;
      } else {
        return false;
      }
    }
    getAttributeNameForKey(key) {
      return `data-${this.identifier}-${dasherize(key)}`;
    }
  };

  // src/core/guide.ts
  var Guide = class {
    constructor(logger) {
      this.warnedKeysByObject = /* @__PURE__ */ new WeakMap();
      this.logger = logger;
    }
    warn(object, key, message) {
      let warnedKeys = this.warnedKeysByObject.get(object);
      if (!warnedKeys) {
        warnedKeys = /* @__PURE__ */ new Set();
        this.warnedKeysByObject.set(object, warnedKeys);
      }
      if (!warnedKeys.has(key)) {
        warnedKeys.add(key);
        this.logger.warn(message, object);
      }
    }
  };

  // src/core/selectors.ts
  function attributeValueContainsToken(attributeName, token) {
    return `[${attributeName}~="${token}"]`;
  }

  // src/core/target_set.ts
  var TargetSet = class {
    constructor(scope) {
      this.scope = scope;
    }
    get element() {
      return this.scope.element;
    }
    get identifier() {
      return this.scope.identifier;
    }
    get schema() {
      return this.scope.schema;
    }
    has(targetName) {
      return this.find(targetName) != null;
    }
    find(...targetNames) {
      return targetNames.reduce(
        (target, targetName) => target || this.findTarget(targetName) || this.findLegacyTarget(targetName),
        void 0
      );
    }
    findAll(...targetNames) {
      return targetNames.reduce(
        (targets, targetName) => [
          ...targets,
          ...this.findAllTargets(targetName),
          ...this.findAllLegacyTargets(targetName)
        ],
        []
      );
    }
    findTarget(targetName) {
      const selector = this.getSelectorForTargetName(targetName);
      return this.scope.findElement(selector);
    }
    findAllTargets(targetName) {
      const selector = this.getSelectorForTargetName(targetName);
      return this.scope.findAllElements(selector);
    }
    getSelectorForTargetName(targetName) {
      const attributeName = this.schema.targetAttributeForScope(this.identifier);
      return attributeValueContainsToken(attributeName, targetName);
    }
    findLegacyTarget(targetName) {
      const selector = this.getLegacySelectorForTargetName(targetName);
      return this.deprecate(this.scope.findElement(selector), targetName);
    }
    findAllLegacyTargets(targetName) {
      const selector = this.getLegacySelectorForTargetName(targetName);
      return this.scope.findAllElements(selector).map((element) => this.deprecate(element, targetName));
    }
    getLegacySelectorForTargetName(targetName) {
      const targetDescriptor = `${this.identifier}.${targetName}`;
      return attributeValueContainsToken(this.schema.targetAttribute, targetDescriptor);
    }
    deprecate(element, targetName) {
      if (element) {
        const { identifier } = this;
        const attributeName = this.schema.targetAttribute;
        const revisedAttributeName = this.schema.targetAttributeForScope(identifier);
        this.guide.warn(
          element,
          `target:${targetName}`,
          `Please replace ${attributeName}="${identifier}.${targetName}" with ${revisedAttributeName}="${targetName}". The ${attributeName} attribute is deprecated and will be removed in a future version of Stimulus.`
        );
      }
      return element;
    }
    get guide() {
      return this.scope.guide;
    }
  };

  // src/core/outlet_set.ts
  var OutletSet = class {
    constructor(scope, controllerElement) {
      this.scope = scope;
      this.controllerElement = controllerElement;
    }
    get element() {
      return this.scope.element;
    }
    get identifier() {
      return this.scope.identifier;
    }
    get schema() {
      return this.scope.schema;
    }
    has(outletName) {
      return this.find(outletName) != null;
    }
    find(...outletNames) {
      return outletNames.reduce(
        (outlet, outletName) => outlet || this.findOutlet(outletName),
        void 0
      );
    }
    findAll(...outletNames) {
      return outletNames.reduce(
        (outlets, outletName) => [...outlets, ...this.findAllOutlets(outletName)],
        []
      );
    }
    getSelectorForOutletName(outletName) {
      const attributeName = this.schema.outletAttributeForScope(this.identifier, outletName);
      return this.controllerElement.getAttribute(attributeName);
    }
    findOutlet(outletName) {
      const selector = this.getSelectorForOutletName(outletName);
      if (selector) return this.findElement(selector, outletName);
    }
    findAllOutlets(outletName) {
      const selector = this.getSelectorForOutletName(outletName);
      return selector ? this.findAllElements(selector, outletName) : [];
    }
    findElement(selector, outletName) {
      const elements = this.scope.queryElements(selector);
      return elements.filter((element) => this.matchesElement(element, selector, outletName))[0];
    }
    findAllElements(selector, outletName) {
      const elements = this.scope.queryElements(selector);
      return elements.filter((element) => this.matchesElement(element, selector, outletName));
    }
    matchesElement(element, selector, outletName) {
      const controllerAttribute = element.getAttribute(this.scope.schema.controllerAttribute) || "";
      return element.matches(selector) && controllerAttribute.split(" ").includes(outletName);
    }
  };

  // src/core/scope.ts
  var Scope = class _Scope {
    constructor(schema, element, identifier, logger) {
      this.targets = new TargetSet(this);
      this.classes = new ClassMap(this);
      this.data = new DataMap(this);
      this.containsElement = (element) => {
        return element.closest(this.controllerSelector) === this.element;
      };
      this.schema = schema;
      this.element = element;
      this.identifier = identifier;
      this.guide = new Guide(logger);
      this.outlets = new OutletSet(this.documentScope, element);
    }
    findElement(selector) {
      return this.element.matches(selector) ? this.element : this.queryElements(selector).find(this.containsElement);
    }
    findAllElements(selector) {
      return [
        ...this.element.matches(selector) ? [this.element] : [],
        ...this.queryElements(selector).filter(this.containsElement)
      ];
    }
    queryElements(selector) {
      return Array.from(this.element.querySelectorAll(selector));
    }
    get controllerSelector() {
      return attributeValueContainsToken(this.schema.controllerAttribute, this.identifier);
    }
    get isDocumentScope() {
      return this.element === document.documentElement;
    }
    get documentScope() {
      return this.isDocumentScope ? this : new _Scope(this.schema, document.documentElement, this.identifier, this.guide.logger);
    }
  };

  // src/core/scope_observer.ts
  var ScopeObserver = class {
    constructor(element, schema, delegate) {
      this.element = element;
      this.schema = schema;
      this.delegate = delegate;
      this.valueListObserver = new ValueListObserver(this.element, this.controllerAttribute, this);
      this.scopesByIdentifierByElement = /* @__PURE__ */ new WeakMap();
      this.scopeReferenceCounts = /* @__PURE__ */ new WeakMap();
    }
    start() {
      this.valueListObserver.start();
    }
    stop() {
      this.valueListObserver.stop();
    }
    get controllerAttribute() {
      return this.schema.controllerAttribute;
    }
    // Value observer delegate
    parseValueForToken(token) {
      const { element, content: identifier } = token;
      return this.parseValueForElementAndIdentifier(element, identifier);
    }
    parseValueForElementAndIdentifier(element, identifier) {
      const scopesByIdentifier = this.fetchScopesByIdentifierForElement(element);
      let scope = scopesByIdentifier.get(identifier);
      if (!scope) {
        scope = this.delegate.createScopeForElementAndIdentifier(element, identifier);
        scopesByIdentifier.set(identifier, scope);
      }
      return scope;
    }
    elementMatchedValue(element, value) {
      const referenceCount = (this.scopeReferenceCounts.get(value) || 0) + 1;
      this.scopeReferenceCounts.set(value, referenceCount);
      if (referenceCount == 1) {
        this.delegate.scopeConnected(value);
      }
    }
    elementUnmatchedValue(element, value) {
      const referenceCount = this.scopeReferenceCounts.get(value);
      if (referenceCount) {
        this.scopeReferenceCounts.set(value, referenceCount - 1);
        if (referenceCount == 1) {
          this.delegate.scopeDisconnected(value);
        }
      }
    }
    fetchScopesByIdentifierForElement(element) {
      let scopesByIdentifier = this.scopesByIdentifierByElement.get(element);
      if (!scopesByIdentifier) {
        scopesByIdentifier = /* @__PURE__ */ new Map();
        this.scopesByIdentifierByElement.set(element, scopesByIdentifier);
      }
      return scopesByIdentifier;
    }
  };

  // src/core/router.ts
  var Router = class {
    constructor(application) {
      this.application = application;
      this.scopeObserver = new ScopeObserver(this.element, this.schema, this);
      this.scopesByIdentifier = new Multimap();
      this.modulesByIdentifier = /* @__PURE__ */ new Map();
    }
    get element() {
      return this.application.element;
    }
    get schema() {
      return this.application.schema;
    }
    get logger() {
      return this.application.logger;
    }
    get controllerAttribute() {
      return this.schema.controllerAttribute;
    }
    get modules() {
      return Array.from(this.modulesByIdentifier.values());
    }
    get contexts() {
      return this.modules.reduce((contexts, module) => contexts.concat(module.contexts), []);
    }
    start() {
      this.scopeObserver.start();
    }
    stop() {
      this.scopeObserver.stop();
    }
    loadDefinition(definition) {
      this.unloadIdentifier(definition.identifier);
      const module = new Module(this.application, definition);
      this.connectModule(module);
      const afterLoad = definition.controllerConstructor.afterLoad;
      if (afterLoad) {
        afterLoad.call(definition.controllerConstructor, definition.identifier, this.application);
      }
    }
    unloadIdentifier(identifier) {
      const module = this.modulesByIdentifier.get(identifier);
      if (module) {
        this.disconnectModule(module);
      }
    }
    getContextForElementAndIdentifier(element, identifier) {
      const module = this.modulesByIdentifier.get(identifier);
      if (module) {
        return module.contexts.find((context) => context.element == element);
      }
    }
    proposeToConnectScopeForElementAndIdentifier(element, identifier) {
      const scope = this.scopeObserver.parseValueForElementAndIdentifier(element, identifier);
      if (scope) {
        this.scopeObserver.elementMatchedValue(scope.element, scope);
      } else {
        console.error(`Couldn't find or create scope for identifier: "${identifier}" and element:`, element);
      }
    }
    // Error handler delegate
    handleError(error2, message, detail) {
      this.application.handleError(error2, message, detail);
    }
    // Scope observer delegate
    createScopeForElementAndIdentifier(element, identifier) {
      return new Scope(this.schema, element, identifier, this.logger);
    }
    scopeConnected(scope) {
      this.scopesByIdentifier.add(scope.identifier, scope);
      const module = this.modulesByIdentifier.get(scope.identifier);
      if (module) {
        module.connectContextForScope(scope);
      }
    }
    scopeDisconnected(scope) {
      this.scopesByIdentifier.delete(scope.identifier, scope);
      const module = this.modulesByIdentifier.get(scope.identifier);
      if (module) {
        module.disconnectContextForScope(scope);
      }
    }
    // Modules
    connectModule(module) {
      this.modulesByIdentifier.set(module.identifier, module);
      const scopes = this.scopesByIdentifier.getValuesForKey(module.identifier);
      scopes.forEach((scope) => module.connectContextForScope(scope));
    }
    disconnectModule(module) {
      this.modulesByIdentifier.delete(module.identifier);
      const scopes = this.scopesByIdentifier.getValuesForKey(module.identifier);
      scopes.forEach((scope) => module.disconnectContextForScope(scope));
    }
  };

  // src/core/schema.ts
  var defaultSchema = {
    controllerAttribute: "data-controller",
    actionAttribute: "data-action",
    targetAttribute: "data-target",
    targetAttributeForScope: (identifier) => `data-${identifier}-target`,
    outletAttributeForScope: (identifier, outlet) => `data-${identifier}-${outlet}-outlet`,
    keyMappings: __spreadValues(__spreadValues({
      enter: "Enter",
      tab: "Tab",
      esc: "Escape",
      space: " ",
      up: "ArrowUp",
      down: "ArrowDown",
      left: "ArrowLeft",
      right: "ArrowRight",
      home: "Home",
      end: "End",
      page_up: "PageUp",
      page_down: "PageDown"
    }, objectFromEntries("abcdefghijklmnopqrstuvwxyz".split("").map((c) => [c, c]))), objectFromEntries("0123456789".split("").map((n) => [n, n])))
  };
  function objectFromEntries(array) {
    return array.reduce((memo, [k, v]) => __spreadProps(__spreadValues({}, memo), { [k]: v }), {});
  }

  // src/core/application.ts
  var Application = class {
    constructor(element = document.documentElement, schema = defaultSchema) {
      this.logger = console;
      this.debug = false;
      // Debug logging
      this.logDebugActivity = (identifier, functionName, detail = {}) => {
        if (this.debug) {
          this.logFormattedMessage(identifier, functionName, detail);
        }
      };
      this.element = element;
      this.schema = schema;
      this.dispatcher = new Dispatcher(this);
      this.router = new Router(this);
      this.actionDescriptorFilters = __spreadValues({}, defaultActionDescriptorFilters);
    }
    static start(element, schema) {
      const application = new this(element, schema);
      application.start();
      return application;
    }
    async start() {
      await domReady();
      this.logDebugActivity("application", "starting");
      this.dispatcher.start();
      this.router.start();
      this.logDebugActivity("application", "start");
    }
    stop() {
      this.logDebugActivity("application", "stopping");
      this.dispatcher.stop();
      this.router.stop();
      this.logDebugActivity("application", "stop");
    }
    register(identifier, controllerConstructor) {
      this.load({ identifier, controllerConstructor });
    }
    registerActionOption(name, filter) {
      this.actionDescriptorFilters[name] = filter;
    }
    load(head, ...rest) {
      const definitions = Array.isArray(head) ? head : [head, ...rest];
      definitions.forEach((definition) => {
        if (definition.controllerConstructor.shouldLoad) {
          this.router.loadDefinition(definition);
        }
      });
    }
    unload(head, ...rest) {
      const identifiers = Array.isArray(head) ? head : [head, ...rest];
      identifiers.forEach((identifier) => this.router.unloadIdentifier(identifier));
    }
    // Controllers
    get controllers() {
      return this.router.contexts.map((context) => context.controller);
    }
    getControllerForElementAndIdentifier(element, identifier) {
      const context = this.router.getContextForElementAndIdentifier(element, identifier);
      return context ? context.controller : null;
    }
    // Error handling
    handleError(error2, message, detail) {
      var _a;
      this.logger.error(`%s

%o

%o`, message, error2, detail);
      (_a = window.onerror) == null ? void 0 : _a.call(window, message, "", 0, 0, error2);
    }
    logFormattedMessage(identifier, functionName, detail = {}) {
      detail = Object.assign({ application: this }, detail);
      this.logger.groupCollapsed(`${identifier} #${functionName}`);
      this.logger.log("details:", __spreadValues({}, detail));
      this.logger.groupEnd();
    }
  };
  function domReady() {
    return new Promise((resolve) => {
      if (document.readyState == "loading") {
        document.addEventListener("DOMContentLoaded", () => resolve());
      } else {
        resolve();
      }
    });
  }

  // src/tests/cases/test_case.ts
  var TestCase = class {
    static defineModule(moduleName = this.name, qUnit = QUnit) {
      qUnit.module(moduleName, (_hooks) => {
        this.manifest.forEach(([type, name]) => {
          type = this.shouldSkipTest(name) ? "skip" : type;
          const method = qUnit[type];
          const test = this.getTest(name);
          method.call(qUnit, name, test);
        });
      });
    }
    static getTest(testName) {
      return async (assert) => this.runTest(testName, assert);
    }
    static runTest(testName, assert) {
      const testCase = new this(assert);
      return testCase.runTest(testName);
    }
    static shouldSkipTest(_testName) {
      return false;
    }
    static get manifest() {
      return this.testPropertyNames.map((name) => [name.slice(0, 4), name.slice(5)]);
    }
    static get testNames() {
      return this.manifest.map(([_type, name]) => name);
    }
    static get testPropertyNames() {
      return Object.getOwnPropertyNames(this.prototype).filter((name) => name.match(/^(skip|test|todo) /));
    }
    constructor(assert) {
      this.assert = assert;
    }
    async runTest(testName) {
      try {
        await this.setup();
        await this.runTestBody(testName);
      } finally {
        await this.teardown();
      }
    }
    async runTestBody(testName) {
      const testCase = this[`test ${testName}`] || this[`todo ${testName}`];
      if (typeof testCase == "function") {
        return testCase.call(this);
      } else {
        return Promise.reject(`test not found: "${testName}"`);
      }
    }
    async setup() {
    }
    async teardown() {
    }
  };

  // src/tests/cases/dom_test_case.ts
  var defaultTriggerEventOptions = {
    bubbles: true,
    setDefaultPrevented: true
  };
  var DOMTestCase = class extends TestCase {
    constructor() {
      super(...arguments);
      this.fixtureSelector = "#qunit-fixture";
      this.fixtureHTML = "";
    }
    async runTest(testName) {
      await this.renderFixture();
      await super.runTest(testName);
    }
    async renderFixture(fixtureHTML = this.fixtureHTML) {
      this.fixtureElement.innerHTML = fixtureHTML;
      return this.nextFrame;
    }
    get fixtureElement() {
      const element = document.querySelector(this.fixtureSelector);
      if (element) {
        return element;
      } else {
        throw new Error(`missing fixture element "${this.fixtureSelector}"`);
      }
    }
    async triggerEvent(selectorOrTarget, type, options = {}) {
      const { bubbles, setDefaultPrevented } = __spreadValues(__spreadValues({}, defaultTriggerEventOptions), options);
      const eventTarget = typeof selectorOrTarget == "string" ? this.findElement(selectorOrTarget) : selectorOrTarget;
      const event = document.createEvent("Events");
      event.initEvent(type, bubbles, true);
      if (setDefaultPrevented) {
        event.preventDefault = function() {
          Object.defineProperty(this, "defaultPrevented", { get: () => true, configurable: true });
        };
      }
      eventTarget.dispatchEvent(event);
      await this.nextFrame;
      return event;
    }
    async triggerMouseEvent(selectorOrTarget, type, options = {}) {
      const eventTarget = typeof selectorOrTarget == "string" ? this.findElement(selectorOrTarget) : selectorOrTarget;
      const event = new MouseEvent(type, options);
      eventTarget.dispatchEvent(event);
      await this.nextFrame;
      return event;
    }
    async triggerKeyboardEvent(selectorOrTarget, type, options = {}) {
      const eventTarget = typeof selectorOrTarget == "string" ? this.findElement(selectorOrTarget) : selectorOrTarget;
      const event = new KeyboardEvent(type, options);
      eventTarget.dispatchEvent(event);
      await this.nextFrame;
      return event;
    }
    async setAttribute(selectorOrElement, name, value) {
      const element = typeof selectorOrElement == "string" ? this.findElement(selectorOrElement) : selectorOrElement;
      element.setAttribute(name, value);
      await this.nextFrame;
    }
    async removeAttribute(selectorOrElement, name) {
      const element = typeof selectorOrElement == "string" ? this.findElement(selectorOrElement) : selectorOrElement;
      element.removeAttribute(name);
      await this.nextFrame;
    }
    async appendChild(selectorOrElement, child) {
      const parent = typeof selectorOrElement == "string" ? this.findElement(selectorOrElement) : selectorOrElement;
      parent.appendChild(child);
      await this.nextFrame;
    }
    async remove(selectorOrElement) {
      const element = typeof selectorOrElement == "string" ? this.findElement(selectorOrElement) : selectorOrElement;
      element.remove();
      await this.nextFrame;
    }
    findElement(selector) {
      const element = this.fixtureElement.querySelector(selector);
      if (element) {
        return element;
      } else {
        throw new Error(`couldn't find element "${selector}"`);
      }
    }
    findElements(...selectors) {
      return selectors.map((selector) => this.findElement(selector));
    }
    get nextFrame() {
      return new Promise((resolve) => requestAnimationFrame(resolve));
    }
  };

  // src/tests/cases/application_test_case.ts
  var TestApplication = class extends Application {
    handleError(error2, _message, _detail) {
      throw error2;
    }
  };
  var ApplicationTestCase = class extends DOMTestCase {
    constructor() {
      super(...arguments);
      this.schema = defaultSchema;
    }
    async runTest(testName) {
      try {
        this.application = new TestApplication(this.fixtureElement, this.schema);
        this.setupApplication();
        this.application.start();
        await super.runTest(testName);
      } finally {
        this.application.stop();
      }
    }
    setupApplication() {
    }
  };

  // src/core/class_properties.ts
  function ClassPropertiesBlessing(constructor) {
    const classes = readInheritableStaticArrayValues(constructor, "classes");
    return classes.reduce((properties, classDefinition) => {
      return Object.assign(properties, propertiesForClassDefinition(classDefinition));
    }, {});
  }
  function propertiesForClassDefinition(key) {
    return {
      [`${key}Class`]: {
        get() {
          const { classes } = this;
          if (classes.has(key)) {
            return classes.get(key);
          } else {
            const attribute = classes.getAttributeName(key);
            throw new Error(`Missing attribute "${attribute}"`);
          }
        }
      },
      [`${key}Classes`]: {
        get() {
          return this.classes.getAll(key);
        }
      },
      [`has${capitalize(key)}Class`]: {
        get() {
          return this.classes.has(key);
        }
      }
    };
  }

  // src/core/outlet_properties.ts
  function OutletPropertiesBlessing(constructor) {
    const outlets = readInheritableStaticArrayValues(constructor, "outlets");
    return outlets.reduce((properties, outletDefinition) => {
      return Object.assign(properties, propertiesForOutletDefinition(outletDefinition));
    }, {});
  }
  function getOutletController(controller, element, identifier) {
    return controller.application.getControllerForElementAndIdentifier(element, identifier);
  }
  function getControllerAndEnsureConnectedScope(controller, element, outletName) {
    let outletController = getOutletController(controller, element, outletName);
    if (outletController) return outletController;
    controller.application.router.proposeToConnectScopeForElementAndIdentifier(element, outletName);
    outletController = getOutletController(controller, element, outletName);
    if (outletController) return outletController;
  }
  function propertiesForOutletDefinition(name) {
    const camelizedName = namespaceCamelize(name);
    return {
      [`${camelizedName}Outlet`]: {
        get() {
          const outletElement = this.outlets.find(name);
          const selector = this.outlets.getSelectorForOutletName(name);
          if (outletElement) {
            const outletController = getControllerAndEnsureConnectedScope(this, outletElement, name);
            if (outletController) return outletController;
            throw new Error(
              `The provided outlet element is missing an outlet controller "${name}" instance for host controller "${this.identifier}"`
            );
          }
          throw new Error(
            `Missing outlet element "${name}" for host controller "${this.identifier}". Stimulus couldn't find a matching outlet element using selector "${selector}".`
          );
        }
      },
      [`${camelizedName}Outlets`]: {
        get() {
          const outlets = this.outlets.findAll(name);
          if (outlets.length > 0) {
            return outlets.map((outletElement) => {
              const outletController = getControllerAndEnsureConnectedScope(this, outletElement, name);
              if (outletController) return outletController;
              console.warn(
                `The provided outlet element is missing an outlet controller "${name}" instance for host controller "${this.identifier}"`,
                outletElement
              );
            }).filter((controller) => controller);
          }
          return [];
        }
      },
      [`${camelizedName}OutletElement`]: {
        get() {
          const outletElement = this.outlets.find(name);
          const selector = this.outlets.getSelectorForOutletName(name);
          if (outletElement) {
            return outletElement;
          } else {
            throw new Error(
              `Missing outlet element "${name}" for host controller "${this.identifier}". Stimulus couldn't find a matching outlet element using selector "${selector}".`
            );
          }
        }
      },
      [`${camelizedName}OutletElements`]: {
        get() {
          return this.outlets.findAll(name);
        }
      },
      [`has${capitalize(camelizedName)}Outlet`]: {
        get() {
          return this.outlets.has(name);
        }
      }
    };
  }

  // src/core/target_properties.ts
  function TargetPropertiesBlessing(constructor) {
    const targets = readInheritableStaticArrayValues(constructor, "targets");
    return targets.reduce((properties, targetDefinition) => {
      return Object.assign(properties, propertiesForTargetDefinition(targetDefinition));
    }, {});
  }
  function propertiesForTargetDefinition(name) {
    return {
      [`${name}Target`]: {
        get() {
          const target = this.targets.find(name);
          if (target) {
            return target;
          } else {
            throw new Error(`Missing target element "${name}" for "${this.identifier}" controller`);
          }
        }
      },
      [`${name}Targets`]: {
        get() {
          return this.targets.findAll(name);
        }
      },
      [`has${capitalize(name)}Target`]: {
        get() {
          return this.targets.has(name);
        }
      }
    };
  }

  // src/core/value_properties.ts
  function ValuePropertiesBlessing(constructor) {
    const valueDefinitionPairs = readInheritableStaticObjectPairs(constructor, "values");
    const propertyDescriptorMap = {
      valueDescriptorMap: {
        get() {
          return valueDefinitionPairs.reduce((result, valueDefinitionPair) => {
            const valueDescriptor = parseValueDefinitionPair(valueDefinitionPair, this.identifier);
            const attributeName = this.data.getAttributeNameForKey(valueDescriptor.key);
            return Object.assign(result, { [attributeName]: valueDescriptor });
          }, {});
        }
      }
    };
    return valueDefinitionPairs.reduce((properties, valueDefinitionPair) => {
      return Object.assign(properties, propertiesForValueDefinitionPair(valueDefinitionPair));
    }, propertyDescriptorMap);
  }
  function propertiesForValueDefinitionPair(valueDefinitionPair, controller) {
    const definition = parseValueDefinitionPair(valueDefinitionPair, controller);
    const { key, name, reader: read, writer: write } = definition;
    return {
      [name]: {
        get() {
          const value = this.data.get(key);
          if (value !== null) {
            return read(value);
          } else {
            return definition.defaultValue;
          }
        },
        set(value) {
          if (value === void 0) {
            this.data.delete(key);
          } else {
            this.data.set(key, write(value));
          }
        }
      },
      [`has${capitalize(name)}`]: {
        get() {
          return this.data.has(key) || definition.hasCustomDefaultValue;
        }
      }
    };
  }
  function parseValueDefinitionPair([token, typeDefinition], controller) {
    return valueDescriptorForTokenAndTypeDefinition({
      controller,
      token,
      typeDefinition
    });
  }
  function parseValueTypeConstant(constant) {
    switch (constant) {
      case Array:
        return "array";
      case Boolean:
        return "boolean";
      case Number:
        return "number";
      case Object:
        return "object";
      case String:
        return "string";
    }
  }
  function parseValueTypeDefault(defaultValue) {
    switch (typeof defaultValue) {
      case "boolean":
        return "boolean";
      case "number":
        return "number";
      case "string":
        return "string";
    }
    if (Array.isArray(defaultValue)) return "array";
    if (Object.prototype.toString.call(defaultValue) === "[object Object]") return "object";
  }
  function parseValueTypeObject(payload) {
    const { controller, token, typeObject } = payload;
    const hasType = isSomething(typeObject.type);
    const hasDefault = isSomething(typeObject.default);
    const fullObject = hasType && hasDefault;
    const onlyType = hasType && !hasDefault;
    const onlyDefault = !hasType && hasDefault;
    const typeFromObject = parseValueTypeConstant(typeObject.type);
    const typeFromDefaultValue = parseValueTypeDefault(payload.typeObject.default);
    if (onlyType) return typeFromObject;
    if (onlyDefault) return typeFromDefaultValue;
    if (typeFromObject !== typeFromDefaultValue) {
      const propertyPath = controller ? `${controller}.${token}` : token;
      throw new Error(
        `The specified default value for the Stimulus Value "${propertyPath}" must match the defined type "${typeFromObject}". The provided default value of "${typeObject.default}" is of type "${typeFromDefaultValue}".`
      );
    }
    if (fullObject) return typeFromObject;
  }
  function parseValueTypeDefinition(payload) {
    const { controller, token, typeDefinition } = payload;
    const typeObject = { controller, token, typeObject: typeDefinition };
    const typeFromObject = parseValueTypeObject(typeObject);
    const typeFromDefaultValue = parseValueTypeDefault(typeDefinition);
    const typeFromConstant = parseValueTypeConstant(typeDefinition);
    const type = typeFromObject || typeFromDefaultValue || typeFromConstant;
    if (type) return type;
    const propertyPath = controller ? `${controller}.${typeDefinition}` : token;
    throw new Error(`Unknown value type "${propertyPath}" for "${token}" value`);
  }
  function defaultValueForDefinition(typeDefinition) {
    const constant = parseValueTypeConstant(typeDefinition);
    if (constant) return defaultValuesByType[constant];
    const hasDefault = hasProperty(typeDefinition, "default");
    const hasType = hasProperty(typeDefinition, "type");
    const typeObject = typeDefinition;
    if (hasDefault) return typeObject.default;
    if (hasType) {
      const { type } = typeObject;
      const constantFromType = parseValueTypeConstant(type);
      if (constantFromType) return defaultValuesByType[constantFromType];
    }
    return typeDefinition;
  }
  function valueDescriptorForTokenAndTypeDefinition(payload) {
    const { token, typeDefinition } = payload;
    const key = `${dasherize(token)}-value`;
    const type = parseValueTypeDefinition(payload);
    return {
      type,
      key,
      name: camelize(key),
      get defaultValue() {
        return defaultValueForDefinition(typeDefinition);
      },
      get hasCustomDefaultValue() {
        return parseValueTypeDefault(typeDefinition) !== void 0;
      },
      reader: readers[type],
      writer: writers[type] || writers.default
    };
  }
  var defaultValuesByType = {
    get array() {
      return [];
    },
    boolean: false,
    number: 0,
    get object() {
      return {};
    },
    string: ""
  };
  var readers = {
    array(value) {
      const array = JSON.parse(value);
      if (!Array.isArray(array)) {
        throw new TypeError(
          `expected value of type "array" but instead got value "${value}" of type "${parseValueTypeDefault(array)}"`
        );
      }
      return array;
    },
    boolean(value) {
      return !(value == "0" || String(value).toLowerCase() == "false");
    },
    number(value) {
      return Number(value.replace(/_/g, ""));
    },
    object(value) {
      const object = JSON.parse(value);
      if (object === null || typeof object != "object" || Array.isArray(object)) {
        throw new TypeError(
          `expected value of type "object" but instead got value "${value}" of type "${parseValueTypeDefault(object)}"`
        );
      }
      return object;
    },
    string(value) {
      return value;
    }
  };
  var writers = {
    default: writeString,
    array: writeJSON,
    object: writeJSON
  };
  function writeJSON(value) {
    return JSON.stringify(value);
  }
  function writeString(value) {
    return `${value}`;
  }

  // src/core/controller.ts
  var Controller = class {
    static get shouldLoad() {
      return true;
    }
    static afterLoad(_identifier, _application) {
      return;
    }
    constructor(context) {
      this.context = context;
    }
    get application() {
      return this.context.application;
    }
    get scope() {
      return this.context.scope;
    }
    get element() {
      return this.scope.element;
    }
    get identifier() {
      return this.scope.identifier;
    }
    get targets() {
      return this.scope.targets;
    }
    get outlets() {
      return this.scope.outlets;
    }
    get classes() {
      return this.scope.classes;
    }
    get data() {
      return this.scope.data;
    }
    initialize() {
    }
    connect() {
    }
    disconnect() {
    }
    dispatch(eventName, {
      target = this.element,
      detail = {},
      prefix = this.identifier,
      bubbles = true,
      cancelable = true
    } = {}) {
      const type = prefix ? `${prefix}:${eventName}` : eventName;
      const event = new CustomEvent(type, { detail, bubbles, cancelable });
      target.dispatchEvent(event);
      return event;
    }
  };
  Controller.blessings = [
    ClassPropertiesBlessing,
    TargetPropertiesBlessing,
    ValuePropertiesBlessing,
    OutletPropertiesBlessing
  ];
  Controller.targets = [];
  Controller.outlets = [];
  Controller.values = {};

  // src/tests/cases/controller_test_case.ts
  var ControllerTests = class extends ApplicationTestCase {
    constructor() {
      super(...arguments);
      this.identifier = "test";
      this.fixtureHTML = `<div data-controller="${this.identifiers.join(" ")}">`;
    }
    setupApplication() {
      this.identifiers.forEach((identifier) => {
        this.application.register(identifier, this.controllerConstructor);
      });
    }
    get controller() {
      const controller = this.controllers[0];
      if (controller) {
        return controller;
      } else {
        throw new Error("no controller connected");
      }
    }
    get identifiers() {
      if (typeof this.identifier == "string") {
        return [this.identifier];
      } else {
        return this.identifier;
      }
    }
    get controllers() {
      return this.application.controllers;
    }
  };
  function ControllerTestCase(constructor) {
    return class extends ControllerTests {
      constructor() {
        super(...arguments);
        this.controllerConstructor = constructor || Controller;
      }
    };
  }

  // src/tests/controllers/log_controller.ts
  var LogController = class extends Controller {
    constructor() {
      super(...arguments);
      this.initializeCount = 0;
      this.connectCount = 0;
      this.disconnectCount = 0;
    }
    initialize() {
      this.initializeCount++;
    }
    connect() {
      this.connectCount++;
    }
    disconnect() {
      this.disconnectCount++;
    }
    log(event) {
      this.recordAction("log", event);
    }
    log2(event) {
      this.recordAction("log2", event);
    }
    log3(event) {
      this.recordAction("log3", event);
    }
    logPassive(event) {
      event.preventDefault();
      if (event.defaultPrevented) {
        this.recordAction("logPassive", event, false);
      } else {
        this.recordAction("logPassive", event, true);
      }
    }
    stop(event) {
      this.recordAction("stop", event);
      event.stopImmediatePropagation();
    }
    get actionLog() {
      return this.constructor.actionLog;
    }
    recordAction(name, event, passive) {
      this.actionLog.push({
        name,
        controller: this,
        identifier: this.identifier,
        eventType: event.type,
        currentTarget: event.currentTarget,
        params: event.params,
        defaultPrevented: event.defaultPrevented,
        passive: passive || false
      });
    }
  };
  LogController.actionLog = [];

  // src/tests/cases/log_controller_test_case.ts
  var LogControllerTestCase = class extends ControllerTestCase(LogController) {
    async setup() {
      this.controllerConstructor.actionLog = [];
      await super.setup();
    }
    assertActions(...actions) {
      this.assert.equal(this.actionLog.length, actions.length);
      actions.forEach((expected, index) => {
        const keys = Object.keys(expected);
        const actual = slice(this.actionLog[index] || {}, keys);
        const result = keys.every((key) => deepEqual(expected[key], actual[key]));
        this.assert.pushResult({ result, actual, expected, message: "" });
      });
    }
    assertNoActions() {
      this.assert.equal(this.actionLog.length, 0);
    }
    get actionLog() {
      return this.controllerConstructor.actionLog;
    }
  };
  function slice(object, keys) {
    return keys.reduce((result, key) => (result[key] = object[key], result), {});
  }
  function deepEqual(obj1, obj2) {
    if (obj1 === obj2) {
      return true;
    } else if (typeof obj1 === "object" && typeof obj2 === "object") {
      if (Object.keys(obj1).length !== Object.keys(obj2).length) {
        return false;
      }
      for (const prop in obj1) {
        if (!deepEqual(obj1[prop], obj2[prop])) {
          return false;
        }
      }
      return true;
    } else {
      return false;
    }
  }

  // src/tests/modules/core/action_click_filter_tests.ts
  var ActionClickFilterTests = class extends LogControllerTestCase {
    constructor() {
      super(...arguments);
      this.identifier = ["a"];
      this.fixtureHTML = `
    <div data-controller="a">
      <button id="ctrl" data-action="click->a#log ctrl+click->a#log2 meta+click->a#log3"></button>
    </div>
  `;
    }
    async "test ignoring clicks with unmatched modifier"() {
      const button = this.findElement("#ctrl");
      await this.triggerMouseEvent(button, "click", { ctrlKey: true });
      await this.nextFrame;
      this.assertActions(
        { name: "log", identifier: "a", eventType: "click", currentTarget: button },
        { name: "log2", identifier: "a", eventType: "click", currentTarget: button }
      );
    }
  };

  // src/tests/modules/core/action_keyboard_filter_tests.ts
  var customSchema = __spreadProps(__spreadValues({}, defaultSchema), { keyMappings: __spreadProps(__spreadValues({}, defaultSchema.keyMappings), { a: "a", b: "b" }) });
  var ActionKeyboardFilterTests = class extends LogControllerTestCase {
    constructor() {
      super(...arguments);
      this.schema = customSchema;
      this.application = new TestApplication(this.fixtureElement, this.schema);
      this.identifier = ["a"];
      this.fixtureHTML = `
    <div data-controller="a" data-action="keydown.esc@document->a#log">
      <button id="button1" data-action="keydown.enter->a#log keydown.space->a#log2 keydown->a#log3"></button>
      <button id="button2" data-action="keydown.tab->a#log   keydown.esc->a#log2   keydown->a#log3"></button>
      <button id="button3" data-action="keydown.up->a#log    keydown.down->a#log2  keydown->a#log3"></button>
      <button id="button4" data-action="keydown.left->a#log  keydown.right->a#log2 keydown->a#log3"></button>
      <button id="button5" data-action="keydown.home->a#log  keydown.end->a#log2   keydown->a#log3"></button>
      <button id="button6" data-action="keyup.end->a#log     keyup->a#log3"></button>
      <button id="button7"></button>
      <button id="button8" data-action="keydown.a->a#log keydown.b->a#log2"></button>
      <button id="button9" data-action="keydown.shift+a->a#log keydown.a->a#log2 keydown.ctrl+shift+a->a#log3">
      <button id="button10" data-action="jquery.custom.event->a#log jquery.a->a#log2">
    </div>
  `;
    }
    async "test ignore event handlers associated with modifiers other than Enter"() {
      const button = this.findElement("#button1");
      await this.nextFrame;
      await this.triggerKeyboardEvent(button, "keydown", { key: "Enter" });
      this.assertActions(
        { name: "log", identifier: "a", eventType: "keydown", currentTarget: button },
        { name: "log3", identifier: "a", eventType: "keydown", currentTarget: button }
      );
    }
    async "test ignore event handlers associated with modifiers other than Space"() {
      const button = this.findElement("#button1");
      await this.nextFrame;
      await this.triggerKeyboardEvent(button, "keydown", { key: " " });
      this.assertActions(
        { name: "log2", identifier: "a", eventType: "keydown", currentTarget: button },
        { name: "log3", identifier: "a", eventType: "keydown", currentTarget: button }
      );
    }
    async "test ignore event handlers associated with modifiers other than Tab"() {
      const button = this.findElement("#button2");
      await this.nextFrame;
      await this.triggerKeyboardEvent(button, "keydown", { key: "Tab" });
      this.assertActions(
        { name: "log", identifier: "a", eventType: "keydown", currentTarget: button },
        { name: "log3", identifier: "a", eventType: "keydown", currentTarget: button }
      );
    }
    async "test ignore event handlers associated with modifiers other than Escape"() {
      const button = this.findElement("#button2");
      await this.nextFrame;
      await this.triggerKeyboardEvent(button, "keydown", { key: "Escape" });
      this.assertActions(
        { name: "log2", identifier: "a", eventType: "keydown", currentTarget: button },
        { name: "log3", identifier: "a", eventType: "keydown", currentTarget: button }
      );
    }
    async "test ignore event handlers associated with modifiers other than ArrowUp"() {
      const button = this.findElement("#button3");
      await this.nextFrame;
      await this.triggerKeyboardEvent(button, "keydown", { key: "ArrowUp" });
      this.assertActions(
        { name: "log", identifier: "a", eventType: "keydown", currentTarget: button },
        { name: "log3", identifier: "a", eventType: "keydown", currentTarget: button }
      );
    }
    async "test ignore event handlers associated with modifiers other than ArrowDown"() {
      const button = this.findElement("#button3");
      await this.nextFrame;
      await this.triggerKeyboardEvent(button, "keydown", { key: "ArrowDown" });
      this.assertActions(
        { name: "log2", identifier: "a", eventType: "keydown", currentTarget: button },
        { name: "log3", identifier: "a", eventType: "keydown", currentTarget: button }
      );
    }
    async "test ignore event handlers associated with modifiers other than ArrowLeft"() {
      const button = this.findElement("#button4");
      await this.nextFrame;
      await this.triggerKeyboardEvent(button, "keydown", { key: "ArrowLeft" });
      this.assertActions(
        { name: "log", identifier: "a", eventType: "keydown", currentTarget: button },
        { name: "log3", identifier: "a", eventType: "keydown", currentTarget: button }
      );
    }
    async "test ignore event handlers associated with modifiers other than ArrowRight"() {
      const button = this.findElement("#button4");
      await this.nextFrame;
      await this.triggerKeyboardEvent(button, "keydown", { key: "ArrowRight" });
      this.assertActions(
        { name: "log2", identifier: "a", eventType: "keydown", currentTarget: button },
        { name: "log3", identifier: "a", eventType: "keydown", currentTarget: button }
      );
    }
    async "test ignore event handlers associated with modifiers other than Home"() {
      const button = this.findElement("#button5");
      await this.nextFrame;
      await this.triggerKeyboardEvent(button, "keydown", { key: "Home" });
      this.assertActions(
        { name: "log", identifier: "a", eventType: "keydown", currentTarget: button },
        { name: "log3", identifier: "a", eventType: "keydown", currentTarget: button }
      );
    }
    async "test ignore event handlers associated with modifiers other than End"() {
      const button = this.findElement("#button5");
      await this.nextFrame;
      await this.triggerKeyboardEvent(button, "keydown", { key: "End" });
      this.assertActions(
        { name: "log2", identifier: "a", eventType: "keydown", currentTarget: button },
        { name: "log3", identifier: "a", eventType: "keydown", currentTarget: button }
      );
    }
    async "test keyup"() {
      const button = this.findElement("#button6");
      await this.nextFrame;
      await this.triggerKeyboardEvent(button, "keyup", { key: "End" });
      this.assertActions(
        { name: "log", identifier: "a", eventType: "keyup", currentTarget: button },
        { name: "log3", identifier: "a", eventType: "keyup", currentTarget: button }
      );
    }
    async "test global event"() {
      const button = this.findElement("#button7");
      await this.nextFrame;
      await this.triggerKeyboardEvent(button, "keydown", { key: "Escape", bubbles: true });
      this.assertActions({ name: "log", identifier: "a", eventType: "keydown", currentTarget: document });
    }
    async "test custom keymapping: a"() {
      const button = this.findElement("#button8");
      await this.nextFrame;
      await this.triggerKeyboardEvent(button, "keydown", { key: "a" });
      this.assertActions({ name: "log", identifier: "a", eventType: "keydown", currentTarget: button });
    }
    async "test custom keymapping: b"() {
      const button = this.findElement("#button8");
      await this.nextFrame;
      await this.triggerKeyboardEvent(button, "keydown", { key: "b" });
      this.assertActions({ name: "log2", identifier: "a", eventType: "keydown", currentTarget: button });
    }
    async "test custom keymapping: unknown c"() {
      const button = this.findElement("#button8");
      await this.nextFrame;
      await this.triggerKeyboardEvent(button, "keydown", { key: "c" });
      this.assertActions();
    }
    async "test ignore event handlers associated with modifiers other than shift+a"() {
      const button = this.findElement("#button9");
      await this.nextFrame;
      await this.triggerKeyboardEvent(button, "keydown", { key: "A", shiftKey: true });
      this.assertActions({ name: "log", identifier: "a", eventType: "keydown", currentTarget: button });
    }
    async "test ignore event handlers associated with modifiers other than a"() {
      const button = this.findElement("#button9");
      await this.nextFrame;
      await this.triggerKeyboardEvent(button, "keydown", { key: "a" });
      this.assertActions({ name: "log2", identifier: "a", eventType: "keydown", currentTarget: button });
    }
    async "test ignore event handlers associated with modifiers other than ctrol+shift+a"() {
      const button = this.findElement("#button9");
      await this.nextFrame;
      await this.triggerKeyboardEvent(button, "keydown", { key: "A", ctrlKey: true, shiftKey: true });
      this.assertActions({ name: "log3", identifier: "a", eventType: "keydown", currentTarget: button });
    }
    async "test ignore filter syntax when not a keyboard event"() {
      const button = this.findElement("#button10");
      await this.nextFrame;
      await this.triggerEvent(button, "jquery.custom.event");
      this.assertActions({ name: "log", identifier: "a", eventType: "jquery.custom.event", currentTarget: button });
    }
    async "test ignore filter syntax when not a keyboard event (case2)"() {
      const button = this.findElement("#button10");
      await this.nextFrame;
      await this.triggerEvent(button, "jquery.a");
      this.assertActions({ name: "log2", identifier: "a", eventType: "jquery.a", currentTarget: button });
    }
  };

  // src/tests/modules/core/action_ordering_tests.ts
  var ActionOrderingTests = class extends LogControllerTestCase {
    constructor() {
      super(...arguments);
      this.identifier = ["c", "d"];
      this.fixtureHTML = `
    <div data-controller="c d" data-action="click->c#log">
      <button data-action="c#log d#log2"></button>
    </div>
  `;
    }
    async "test adding an action to the right"() {
      this.actionValue = "c#log d#log2 c#log3";
      await this.nextFrame;
      await this.triggerEvent(this.buttonElement, "click");
      this.assertActions(
        { name: "log", identifier: "c", eventType: "click", currentTarget: this.buttonElement },
        { name: "log2", identifier: "d", eventType: "click", currentTarget: this.buttonElement },
        { name: "log3", identifier: "c", eventType: "click", currentTarget: this.buttonElement },
        { name: "log", identifier: "c", eventType: "click", currentTarget: this.element }
      );
    }
    async "test adding an action to the left"() {
      this.actionValue = "c#log3 c#log d#log2";
      await this.nextFrame;
      await this.triggerEvent(this.buttonElement, "click");
      this.assertActions(
        { name: "log3", identifier: "c", eventType: "click", currentTarget: this.buttonElement },
        { name: "log", identifier: "c", eventType: "click", currentTarget: this.buttonElement },
        { name: "log2", identifier: "d", eventType: "click", currentTarget: this.buttonElement },
        { name: "log", identifier: "c", eventType: "click", currentTarget: this.element }
      );
    }
    async "test removing an action from the right"() {
      this.actionValue = "c#log d#log2";
      await this.nextFrame;
      await this.triggerEvent(this.buttonElement, "click");
      this.assertActions(
        { name: "log", identifier: "c", eventType: "click", currentTarget: this.buttonElement },
        { name: "log2", identifier: "d", eventType: "click", currentTarget: this.buttonElement },
        { name: "log", identifier: "c", eventType: "click", currentTarget: this.element }
      );
    }
    async "test removing an action from the left"() {
      this.actionValue = "d#log2 c#log3";
      await this.nextFrame;
      await this.triggerEvent(this.buttonElement, "click");
      this.assertActions(
        { name: "log2", identifier: "d", eventType: "click", currentTarget: this.buttonElement },
        { name: "log3", identifier: "c", eventType: "click", currentTarget: this.buttonElement },
        { name: "log", identifier: "c", eventType: "click", currentTarget: this.element }
      );
    }
    async "test replacing an action on the left"() {
      this.actionValue = "d#log2 c#log3";
      await this.nextFrame;
      this.actionValue = "c#log d#log2 c#log3";
      await this.nextFrame;
      await this.triggerEvent(this.buttonElement, "click");
      this.assertActions(
        { name: "log", identifier: "c", eventType: "click", currentTarget: this.buttonElement },
        { name: "log2", identifier: "d", eventType: "click", currentTarget: this.buttonElement },
        { name: "log3", identifier: "c", eventType: "click", currentTarget: this.buttonElement },
        { name: "log", identifier: "c", eventType: "click", currentTarget: this.element }
      );
    }
    async "test stopping an action"() {
      this.actionValue = "c#log d#stop c#log3";
      await this.nextFrame;
      await this.triggerEvent(this.buttonElement, "click");
      this.assertActions(
        { name: "log", identifier: "c", eventType: "click", currentTarget: this.buttonElement },
        { name: "stop", identifier: "d", eventType: "click", currentTarget: this.buttonElement }
      );
    }
    async "test disconnecting a controller disconnects its actions"() {
      this.controllerValue = "c";
      await this.nextFrame;
      await this.triggerEvent(this.buttonElement, "click");
      this.assertActions(
        { name: "log", identifier: "c", eventType: "click", currentTarget: this.buttonElement },
        { name: "log", identifier: "c", eventType: "click", currentTarget: this.element }
      );
    }
    set controllerValue(value) {
      this.element.setAttribute("data-controller", value);
    }
    set actionValue(value) {
      this.buttonElement.setAttribute("data-action", value);
    }
    get element() {
      return this.findElement("div");
    }
    get buttonElement() {
      return this.findElement("button");
    }
  };

  // src/tests/modules/core/action_params_tests.ts
  var ActionParamsTests = class extends LogControllerTestCase {
    constructor() {
      super(...arguments);
      this.identifier = ["c", "d"];
      this.fixtureHTML = `
    <div data-controller="c d">
      <button data-c-id-param="123"
              data-c-multi-word-example-param="/path"
              data-c-active-param="true"
              data-c-inactive-param="false"
              data-c-empty-param=""
              data-c-payload-param='${JSON.stringify({ value: 1 })}'
              data-c-param-something="not-reported"
              data-something-param="not-reported"
              data-d-id-param="234">
        <div id="nested"></div>
      </button>
    </div>
    <div id="outside"></div>
  `;
      this.expectedParamsForC = {
        id: 123,
        multiWordExample: "/path",
        payload: {
          value: 1
        },
        active: true,
        empty: "",
        inactive: false
      };
    }
    async "test clicking on the element does return its params"() {
      this.actionValue = "click->c#log";
      await this.nextFrame;
      await this.triggerEvent(this.buttonElement, "click");
      this.assertActions({ identifier: "c", params: this.expectedParamsForC });
    }
    async "test global event return element params where the action is defined"() {
      this.actionValue = "keydown@window->c#log";
      await this.nextFrame;
      await this.triggerEvent("#outside", "keydown");
      this.assertActions({ identifier: "c", params: this.expectedParamsForC });
    }
    async "test passing params to namespaced controller"() {
      this.actionValue = "click->c#log click->d#log2";
      await this.nextFrame;
      await this.triggerEvent(this.buttonElement, "click");
      this.assertActions({ identifier: "c", params: this.expectedParamsForC }, { identifier: "d", params: { id: 234 } });
    }
    async "test updating manually the params values"() {
      this.actionValue = "click->c#log";
      await this.nextFrame;
      await this.triggerEvent(this.buttonElement, "click");
      this.assertActions({ identifier: "c", params: this.expectedParamsForC });
      this.buttonElement.setAttribute("data-c-id-param", "234");
      this.buttonElement.setAttribute("data-c-new-param", "new");
      this.buttonElement.removeAttribute("data-c-payload-param");
      this.triggerEvent(this.buttonElement, "click");
      this.assertActions(
        { identifier: "c", params: this.expectedParamsForC },
        {
          identifier: "c",
          params: {
            id: 234,
            new: "new",
            multiWordExample: "/path",
            active: true,
            empty: "",
            inactive: false
          }
        }
      );
    }
    async "test clicking on a nested element does return the params of the actionable element"() {
      this.actionValue = "click->c#log";
      await this.nextFrame;
      await this.triggerEvent(this.nestedElement, "click");
      this.assertActions({ identifier: "c", params: this.expectedParamsForC });
    }
    set actionValue(value) {
      this.buttonElement.setAttribute("data-action", value);
    }
    get element() {
      return this.findElement("div");
    }
    get buttonElement() {
      return this.findElement("button");
    }
    get nestedElement() {
      return this.findElement("#nested");
    }
  };

  // src/tests/modules/core/action_params_case_insensitive_tests.ts
  var ActionParamsCaseInsensitiveTests = class extends ActionParamsTests {
    constructor() {
      super(...arguments);
      this.identifier = ["CamelCase", "AnotherOne"];
      this.fixtureHTML = `
    <div data-controller="CamelCase AnotherOne">
      <button data-CamelCase-id-param="123"
              data-CamelCase-multi-word-example-param="/path"
              data-CamelCase-active-param="true"
              data-CamelCase-inactive-param="false"
              data-CamelCase-empty-param=""
              data-CamelCase-payload-param='${JSON.stringify({ value: 1 })}'
              data-CamelCase-param-something="not-reported"
              data-Something-param="not-reported"
              data-AnotherOne-id-param="234">
        <div id="nested"></div>
      </button>
    </div>
    <div id="outside"></div>
  `;
      this.expectedParamsForCamelCase = {
        id: 123,
        multiWordExample: "/path",
        payload: {
          value: 1
        },
        active: true,
        empty: "",
        inactive: false
      };
    }
    async "test clicking on the element does return its params"() {
      this.actionValue = "click->CamelCase#log";
      await this.nextFrame;
      await this.triggerEvent(this.buttonElement, "click");
      this.assertActions({ identifier: "CamelCase", params: this.expectedParamsForCamelCase });
    }
    async "test global event return element params where the action is defined"() {
      this.actionValue = "keydown@window->CamelCase#log";
      await this.nextFrame;
      await this.triggerEvent("#outside", "keydown");
      this.assertActions({ identifier: "CamelCase", params: this.expectedParamsForCamelCase });
    }
    async "test passing params to namespaced controller"() {
      this.actionValue = "click->CamelCase#log click->AnotherOne#log2";
      await this.nextFrame;
      await this.triggerEvent(this.buttonElement, "click");
      this.assertActions(
        { identifier: "CamelCase", params: this.expectedParamsForCamelCase },
        { identifier: "AnotherOne", params: { id: 234 } }
      );
    }
  };

  // src/tests/modules/core/action_tests.ts
  var ActionTests = class extends LogControllerTestCase {
    constructor() {
      super(...arguments);
      this.identifier = "c";
      this.fixtureHTML = `
    <div data-controller="c" data-action="keydown@window->c#log">
      <button data-action="c#log"><span>Log</span></button>
      <div id="outer" data-action="click->c#log">
        <div id="inner" data-controller="c" data-action="click->c#log keyup@window->c#log"></div>
      </div>
      <div id="multiple" data-action="click->c#log click->c#log2 mousedown->c#log"></div>
    </div>
    <div id="outside"></div>
    <svg id="svgRoot" data-controller="c" data-action="click->c#log">
      <circle id="svgChild" data-action="mousedown->c#log" cx="5" cy="5" r="5">
    </svg>
  `;
    }
    async "test default event"() {
      await this.triggerEvent("button", "click");
      this.assertActions({ name: "log", eventType: "click" });
    }
    async "test bubbling events"() {
      await this.triggerEvent("span", "click");
      this.assertActions({ eventType: "click", currentTarget: this.findElement("button") });
    }
    async "test non-bubbling events"() {
      await this.triggerEvent("span", "click", { bubbles: false });
      this.assertNoActions();
      await this.triggerEvent("button", "click", { bubbles: false });
      this.assertActions({ eventType: "click" });
    }
    async "test nested actions"() {
      const innerController = this.controllers[1];
      await this.triggerEvent("#inner", "click");
      this.assert.ok(true);
      this.assertActions({ controller: innerController, eventType: "click" });
    }
    async "test global actions"() {
      await this.triggerEvent("#outside", "keydown");
      this.assertActions({ name: "log", eventType: "keydown" });
    }
    async "test nested global actions"() {
      const innerController = this.controllers[1];
      await this.triggerEvent("#outside", "keyup");
      this.assertActions({ controller: innerController, eventType: "keyup" });
    }
    async "test multiple actions"() {
      await this.triggerEvent("#multiple", "mousedown");
      await this.triggerEvent("#multiple", "click");
      this.assertActions(
        { name: "log", eventType: "mousedown" },
        { name: "log", eventType: "click" },
        { name: "log2", eventType: "click" }
      );
    }
    async "test actions on svg elements"() {
      await this.triggerEvent("#svgRoot", "click");
      await this.triggerEvent("#svgChild", "mousedown");
      this.assertActions({ name: "log", eventType: "click" }, { name: "log", eventType: "mousedown" });
    }
  };

  // src/tests/modules/core/action_timing_tests.ts
  var ActionTimingController = class extends Controller {
    connect() {
      this.buttonTarget.click();
    }
    record(event) {
      this.event = event;
    }
  };
  ActionTimingController.targets = ["button"];
  var ActionTimingTests = class extends ControllerTestCase(ActionTimingController) {
    constructor() {
      super(...arguments);
      this.controllerConstructor = ActionTimingController;
      this.identifier = "c";
      this.fixtureHTML = `
    <div data-controller="c">
      <button data-c-target="button" data-action="c#record">Log</button>
    </div>
  `;
    }
    async "test triggering an action on connect"() {
      const { event } = this.controller;
      this.assert.ok(event);
      this.assert.equal(event && event.type, "click");
    }
  };

  // src/tests/cases/observer_test_case.ts
  var ObserverTestCase = class extends DOMTestCase {
    constructor() {
      super(...arguments);
      this.calls = [];
      this.setupCallCount = 0;
    }
    async setup() {
      this.observer.start();
      await this.nextFrame;
      this.setupCallCount = this.calls.length;
    }
    async teardown() {
      this.observer.stop();
    }
    get testCalls() {
      return this.calls.slice(this.setupCallCount);
    }
    recordCall(methodName, ...args) {
      this.calls.push([methodName, ...args]);
    }
  };

  // src/tests/modules/core/application_start_tests.ts
  var ApplicationStartTests = class extends DOMTestCase {
    async setup() {
      this.iframe = document.createElement("iframe");
      this.iframe.src = "/base/src/tests/fixtures/application_start/index.html";
      this.fixtureElement.appendChild(this.iframe);
    }
    async "test starting an application when the document is loading"() {
      const message = await this.messageFromStartState("loading");
      this.assertIn(message.connectState, ["interactive", "complete"]);
      this.assert.equal(message.targetCount, 3);
    }
    async "test starting an application when the document is interactive"() {
      const message = await this.messageFromStartState("interactive");
      this.assertIn(message.connectState, ["interactive", "complete"]);
      this.assert.equal(message.targetCount, 3);
    }
    async "test starting an application when the document is complete"() {
      const message = await this.messageFromStartState("complete");
      this.assertIn(message.connectState, ["complete"]);
      this.assert.equal(message.targetCount, 3);
    }
    messageFromStartState(startState) {
      return new Promise((resolve) => {
        const receiveMessage = (event) => {
          if (event.source == this.iframe.contentWindow) {
            const message = JSON.parse(event.data);
            if (message.startState == startState) {
              removeEventListener("message", receiveMessage);
              resolve(message);
            }
          }
        };
        addEventListener("message", receiveMessage);
      });
    }
    assertIn(actual, expected) {
      const state = expected.indexOf(actual) > -1;
      const message = `${JSON.stringify(actual)} is not in ${JSON.stringify(expected)}`;
      this.assert.ok(state, message);
    }
  };

  // src/tests/modules/core/application_tests.ts
  var AController = class extends LogController {
  };
  var BController = class extends LogController {
  };
  var ApplicationTests = class extends ApplicationTestCase {
    constructor() {
      super(...arguments);
      this.fixtureHTML = `<div data-controller="a"><div data-controller="b">`;
      this.definitions = [
        { controllerConstructor: AController, identifier: "a" },
        { controllerConstructor: BController, identifier: "b" }
      ];
    }
    async "test Application#register"() {
      this.assert.equal(this.controllers.length, 0);
      this.application.register("log", LogController);
      await this.renderFixture(`<div data-controller="log">`);
      this.assert.equal(this.controllers[0].initializeCount, 1);
      this.assert.equal(this.controllers[0].connectCount, 1);
    }
    "test Application#load"() {
      this.assert.equal(this.controllers.length, 0);
      this.application.load(this.definitions);
      this.assert.equal(this.controllers.length, 2);
      this.assert.ok(this.controllers[0] instanceof AController);
      this.assert.equal(this.controllers[0].initializeCount, 1);
      this.assert.equal(this.controllers[0].connectCount, 1);
      this.assert.ok(this.controllers[1] instanceof BController);
      this.assert.equal(this.controllers[1].initializeCount, 1);
      this.assert.equal(this.controllers[1].connectCount, 1);
    }
    "test Application#unload"() {
      this.application.load(this.definitions);
      const originalControllers = this.controllers;
      this.application.unload("a");
      this.assert.equal(originalControllers[0].disconnectCount, 1);
      this.assert.equal(this.controllers.length, 1);
      this.assert.ok(this.controllers[0] instanceof BController);
    }
    get controllers() {
      return this.application.controllers;
    }
  };

  // src/tests/controllers/class_controller.ts
  var BaseClassController = class extends Controller {
  };
  BaseClassController.classes = ["active"];
  var ClassController = class extends BaseClassController {
  };
  ClassController.classes = ["enabled", "loading", "success"];

  // src/tests/modules/core/class_tests.ts
  var ClassTests = class extends ControllerTestCase(ClassController) {
    constructor() {
      super(...arguments);
      this.fixtureHTML = `
    <div data-controller="${this.identifier}"
      data-${this.identifier}-active-class="test--active"
      data-${this.identifier}-loading-class="busy"
      data-${this.identifier}-success-class="bg-green-400 border border-green-600"
      data-loading-class="xxx"
    ></div>
  `;
    }
    "test accessing a class property"() {
      this.assert.ok(this.controller.hasActiveClass);
      this.assert.equal(this.controller.activeClass, "test--active");
      this.assert.deepEqual(this.controller.activeClasses, ["test--active"]);
    }
    "test accessing a missing class property throws an error"() {
      this.assert.notOk(this.controller.hasEnabledClass);
      this.assert.raises(() => this.controller.enabledClass);
      this.assert.equal(this.controller.enabledClasses.length, 0);
    }
    "test classes must be scoped by identifier"() {
      this.assert.equal(this.controller.loadingClass, "busy");
    }
    "test multiple classes map to array"() {
      this.assert.deepEqual(this.controller.successClasses, ["bg-green-400", "border", "border-green-600"]);
    }
    "test accessing a class property returns first class if multiple classes are used"() {
      this.assert.equal(this.controller.successClass, "bg-green-400");
    }
  };

  // src/tests/modules/core/data_tests.ts
  var DataTests = class extends ControllerTestCase() {
    constructor() {
      super(...arguments);
      this.fixtureHTML = `
    <div data-controller="${this.identifier}"
      data-${this.identifier}-alpha="hello world"
      data-${this.identifier}-beta-gamma="123">
    </div>
  `;
    }
    "test DataSet#get"() {
      this.assert.equal(this.controller.data.get("alpha"), "hello world");
      this.assert.equal(this.controller.data.get("betaGamma"), "123");
      this.assert.equal(this.controller.data.get("nonexistent"), null);
    }
    "test DataSet#set"() {
      this.assert.equal(this.controller.data.set("alpha", "ok"), "ok");
      this.assert.equal(this.controller.data.get("alpha"), "ok");
      this.assert.equal(this.findElement("div").getAttribute(`data-${this.identifier}-alpha`), "ok");
    }
    "test DataSet#has"() {
      this.assert.ok(this.controller.data.has("alpha"));
      this.assert.ok(this.controller.data.has("betaGamma"));
      this.assert.notOk(this.controller.data.has("nonexistent"));
    }
    "test DataSet#delete"() {
      this.controller.data.delete("alpha");
      this.assert.equal(this.controller.data.get("alpha"), null);
      this.assert.notOk(this.controller.data.has("alpha"));
      this.assert.notOk(this.findElement("div").hasAttribute(`data-${this.identifier}-alpha`));
    }
  };

  // src/tests/controllers/default_value_controller.ts
  var DefaultValueController = class extends Controller {
    constructor() {
      super(...arguments);
      this.lifecycleCallbacks = [];
    }
    initialize() {
      this.lifecycleCallbacks.push("initialize");
    }
    connect() {
      this.lifecycleCallbacks.push("connect");
    }
    defaultBooleanValueChanged() {
      this.lifecycleCallbacks.push("defaultBooleanValueChanged");
    }
  };
  DefaultValueController.values = {
    defaultBoolean: false,
    defaultBooleanTrue: { type: Boolean, default: true },
    defaultBooleanFalse: { type: Boolean, default: false },
    defaultBooleanOverride: true,
    defaultString: "",
    defaultStringHello: { type: String, default: "Hello" },
    defaultStringOverride: "Override me",
    defaultNumber: 0,
    defaultNumberThousand: { type: Number, default: 1e3 },
    defaultNumberZero: { type: Number, default: 0 },
    defaultNumberOverride: 9999,
    defaultArray: [],
    defaultArrayFilled: { type: Array, default: [1, 2, 3] },
    defaultArrayOverride: [9, 9, 9],
    defaultObject: {},
    defaultObjectPerson: { type: Object, default: { name: "David" } },
    defaultObjectOverride: { override: "me" }
  };

  // src/tests/modules/core/default_value_tests.ts
  var DefaultValueTests = class extends ControllerTestCase(DefaultValueController) {
    constructor() {
      super(...arguments);
      this.fixtureHTML = `
    <div data-controller="${this.identifier}"
      data-${this.identifier}-default-string-override-value="I am the expected value"
      data-${this.identifier}-default-boolean-override-value="false"
      data-${this.identifier}-default-number-override-value="42"
      data-${this.identifier}-default-array-override-value="[9,8,7]"
      data-${this.identifier}-default-object-override-value='{"expected":"value"}'
    </div>
  `;
    }
    // Booleans
    "test custom default boolean values"() {
      this.assert.deepEqual(this.controller.defaultBooleanValue, false);
      this.assert.ok(this.controller.hasDefaultBooleanValue);
      this.assert.deepEqual(this.get("default-boolean-value"), null);
      this.assert.deepEqual(this.controller.defaultBooleanTrueValue, true);
      this.assert.ok(this.controller.hasDefaultBooleanTrueValue);
      this.assert.deepEqual(this.get("default-boolean-true-value"), null);
      this.assert.deepEqual(this.controller.defaultBooleanFalseValue, false);
      this.assert.ok(this.controller.hasDefaultBooleanFalseValue);
      this.assert.deepEqual(this.get("default-boolean-false-value"), null);
    }
    "test should be able to set a new value for custom default boolean values"() {
      this.assert.deepEqual(this.get("default-boolean-true-value"), null);
      this.assert.deepEqual(this.controller.defaultBooleanTrueValue, true);
      this.assert.ok(this.controller.hasDefaultBooleanTrueValue);
      this.controller.defaultBooleanTrueValue = false;
      this.assert.deepEqual(this.get("default-boolean-true-value"), "false");
      this.assert.deepEqual(this.controller.defaultBooleanTrueValue, false);
      this.assert.ok(this.controller.hasDefaultBooleanTrueValue);
    }
    "test should override custom default boolean value with given data-attribute"() {
      this.assert.deepEqual(this.get("default-boolean-override-value"), "false");
      this.assert.deepEqual(this.controller.defaultBooleanOverrideValue, false);
      this.assert.ok(this.controller.hasDefaultBooleanOverrideValue);
    }
    // Strings
    "test custom default string values"() {
      this.assert.deepEqual(this.controller.defaultStringValue, "");
      this.assert.ok(this.controller.hasDefaultStringValue);
      this.assert.deepEqual(this.get("default-string-value"), null);
      this.assert.deepEqual(this.controller.defaultStringHelloValue, "Hello");
      this.assert.ok(this.controller.hasDefaultStringHelloValue);
      this.assert.deepEqual(this.get("default-string-hello-value"), null);
    }
    "test should be able to set a new value for custom default string values"() {
      this.assert.deepEqual(this.get("default-string-value"), null);
      this.assert.deepEqual(this.controller.defaultStringValue, "");
      this.assert.ok(this.controller.hasDefaultStringValue);
      this.controller.defaultStringValue = "New Value";
      this.assert.deepEqual(this.get("default-string-value"), "New Value");
      this.assert.deepEqual(this.controller.defaultStringValue, "New Value");
      this.assert.ok(this.controller.hasDefaultStringValue);
    }
    "test should override custom default string value with given data-attribute"() {
      this.assert.deepEqual(this.get("default-string-override-value"), "I am the expected value");
      this.assert.deepEqual(this.controller.defaultStringOverrideValue, "I am the expected value");
      this.assert.ok(this.controller.hasDefaultStringOverrideValue);
    }
    // Numbers
    "test custom default number values"() {
      this.assert.deepEqual(this.controller.defaultNumberValue, 0);
      this.assert.ok(this.controller.hasDefaultNumberValue);
      this.assert.deepEqual(this.get("default-number-value"), null);
      this.assert.deepEqual(this.controller.defaultNumberThousandValue, 1e3);
      this.assert.ok(this.controller.hasDefaultNumberThousandValue);
      this.assert.deepEqual(this.get("default-number-thousand-value"), null);
      this.assert.deepEqual(this.controller.defaultNumberZeroValue, 0);
      this.assert.ok(this.controller.hasDefaultNumberZeroValue);
      this.assert.deepEqual(this.get("default-number-zero-value"), null);
    }
    "test should be able to set a new value for custom default number values"() {
      this.assert.deepEqual(this.get("default-number-value"), null);
      this.assert.deepEqual(this.controller.defaultNumberValue, 0);
      this.assert.ok(this.controller.hasDefaultNumberValue);
      this.controller.defaultNumberValue = 123;
      this.assert.deepEqual(this.get("default-number-value"), "123");
      this.assert.deepEqual(this.controller.defaultNumberValue, 123);
      this.assert.ok(this.controller.hasDefaultNumberValue);
    }
    "test should override custom default number value with given data-attribute"() {
      this.assert.deepEqual(this.get("default-number-override-value"), "42");
      this.assert.deepEqual(this.controller.defaultNumberOverrideValue, 42);
      this.assert.ok(this.controller.hasDefaultNumberOverrideValue);
    }
    // Arrays
    "test custom default array values"() {
      this.assert.deepEqual(this.controller.defaultArrayValue, []);
      this.assert.ok(this.controller.hasDefaultArrayValue);
      this.assert.deepEqual(this.get("default-array-value"), null);
      this.assert.deepEqual(this.controller.defaultArrayFilledValue, [1, 2, 3]);
      this.assert.ok(this.controller.hasDefaultArrayFilledValue);
      this.assert.deepEqual(this.get("default-array-filled-value"), null);
    }
    "test should be able to set a new value for custom default array values"() {
      this.assert.deepEqual(this.get("default-array-value"), null);
      this.assert.deepEqual(this.controller.defaultArrayValue, []);
      this.assert.ok(this.controller.hasDefaultArrayValue);
      this.controller.defaultArrayValue = [1, 2];
      this.assert.deepEqual(this.get("default-array-value"), "[1,2]");
      this.assert.deepEqual(this.controller.defaultArrayValue, [1, 2]);
      this.assert.ok(this.controller.hasDefaultArrayValue);
    }
    "test should override custom default array value with given data-attribute"() {
      this.assert.deepEqual(this.get("default-array-override-value"), "[9,8,7]");
      this.assert.deepEqual(this.controller.defaultArrayOverrideValue, [9, 8, 7]);
      this.assert.ok(this.controller.hasDefaultArrayOverrideValue);
    }
    // Objects
    "test custom default object values"() {
      this.assert.deepEqual(this.controller.defaultObjectValue, {});
      this.assert.ok(this.controller.hasDefaultObjectValue);
      this.assert.deepEqual(this.get("default-object-value"), null);
      this.assert.deepEqual(this.controller.defaultObjectPersonValue, { name: "David" });
      this.assert.ok(this.controller.hasDefaultObjectPersonValue);
      this.assert.deepEqual(this.get("default-object-filled-value"), null);
    }
    "test should be able to set a new value for custom default object values"() {
      this.assert.deepEqual(this.get("default-object-value"), null);
      this.assert.deepEqual(this.controller.defaultObjectValue, {});
      this.assert.ok(this.controller.hasDefaultObjectValue);
      this.controller.defaultObjectValue = { new: "value" };
      this.assert.deepEqual(this.get("default-object-value"), '{"new":"value"}');
      this.assert.deepEqual(this.controller.defaultObjectValue, { new: "value" });
      this.assert.ok(this.controller.hasDefaultObjectValue);
    }
    "test should override custom default object value with given data-attribute"() {
      this.assert.deepEqual(this.get("default-object-override-value"), '{"expected":"value"}');
      this.assert.deepEqual(this.controller.defaultObjectOverrideValue, { expected: "value" });
      this.assert.ok(this.controller.hasDefaultObjectOverrideValue);
    }
    "test [name]ValueChanged callbacks fire after initialize and before connect"() {
      this.assert.deepEqual(this.controller.lifecycleCallbacks, ["initialize", "defaultBooleanValueChanged", "connect"]);
    }
    has(name) {
      return this.element.hasAttribute(this.attr(name));
    }
    get(name) {
      return this.element.getAttribute(this.attr(name));
    }
    set(name, value) {
      return this.element.setAttribute(this.attr(name), value);
    }
    attr(name) {
      return `data-${this.identifier}-${name}`;
    }
    get element() {
      return this.controller.element;
    }
  };

  // src/tests/modules/core/error_handler_tests.ts
  var MockLogger = class {
    constructor() {
      this.errors = [];
      this.logs = [];
      this.warns = [];
    }
    log(event) {
      this.logs.push(event);
    }
    error(event) {
      this.errors.push(event);
    }
    warn(event) {
      this.warns.push(event);
    }
    groupCollapsed() {
    }
    groupEnd() {
    }
  };
  var ErrorWhileConnectingController = class extends Controller {
    connect() {
      throw new Error("bad!");
    }
  };
  var TestApplicationWithDefaultErrorBehavior = class extends Application {
  };
  var ErrorHandlerTests = class extends ControllerTestCase(ErrorWhileConnectingController) {
    constructor() {
      super(...arguments);
      this.controllerConstructor = ErrorWhileConnectingController;
    }
    async setupApplication() {
      const logger = new MockLogger();
      this.application = new TestApplicationWithDefaultErrorBehavior(this.fixtureElement, this.schema);
      this.application.logger = logger;
      window.onerror = function(message, source, lineno, colno, _error) {
        logger.log(
          `error from window.onerror. message = ${message}, source = ${source}, lineno = ${lineno}, colno = ${colno}`
        );
      };
      super.setupApplication();
    }
    async "test errors in connect are thrown and handled by built in logger"() {
      const mockLogger = this.application.logger;
      this.assert.equal(1, mockLogger.errors.length);
    }
    async "test errors in connect are thrown and handled by window.onerror"() {
      const mockLogger = this.application.logger;
      this.assert.equal(1, mockLogger.logs.length);
      this.assert.equal(
        "error from window.onerror. message = Error connecting controller, source = , lineno = 0, colno = 0",
        mockLogger.logs[0]
      );
    }
  };

  // src/tests/modules/core/es6_tests.ts
  var ES6Tests = class extends LogControllerTestCase {
    constructor() {
      super(...arguments);
      this.fixtureHTML = `
    <div data-controller="es6">
      <button data-action="es6#log">Log</button>
    </div>
  `;
      this.fixtureScript = `
    _stimulus.application.register("es6", class extends _stimulus.LogController {})
  `;
    }
    static shouldSkipTest(_testName) {
      return !(supportsES6Classes() && supportsReflectConstruct());
    }
    async renderFixture() {
      ;
      window["_stimulus"] = { LogController, application: this.application };
      await super.renderFixture();
      const scriptElement = document.createElement("script");
      scriptElement.textContent = this.fixtureScript;
      this.fixtureElement.appendChild(scriptElement);
      await this.nextFrame;
    }
    async teardown() {
      this.application.unload("test");
      delete window["_stimulus"];
    }
    async "test ES6 controller classes"() {
      await this.triggerEvent("button", "click");
      this.assertActions({ eventType: "click", currentTarget: this.findElement("button") });
    }
  };
  function supportsES6Classes() {
    try {
      return eval("(class {}), true");
    } catch (error2) {
      return false;
    }
  }
  function supportsReflectConstruct() {
    return typeof Reflect == "object" && typeof Reflect.construct == "function";
  }

  // src/tests/modules/core/event_options_tests.ts
  var EventOptionsTests = class extends LogControllerTestCase {
    constructor() {
      super(...arguments);
      this.identifier = ["c", "d"];
      this.fixtureHTML = `
    <div data-controller="c d">
      <button></button>
      <details></details>
    </div>
    <div id="outside"></div>
  `;
    }
    async "test different syntaxes for once action"() {
      await this.setAction(this.buttonElement, "click->c#log:once d#log2:once c#log3:once");
      await this.triggerEvent(this.buttonElement, "click");
      await this.triggerEvent(this.buttonElement, "click");
      this.assertActions(
        { name: "log", identifier: "c", eventType: "click", currentTarget: this.buttonElement },
        { name: "log2", identifier: "d", eventType: "click", currentTarget: this.buttonElement },
        { name: "log3", identifier: "c", eventType: "click", currentTarget: this.buttonElement }
      );
    }
    async "test mix once and standard actions"() {
      await this.setAction(this.buttonElement, "c#log:once d#log2 c#log3");
      await this.triggerEvent(this.buttonElement, "click");
      await this.triggerEvent(this.buttonElement, "click");
      this.assertActions(
        { name: "log", identifier: "c", eventType: "click", currentTarget: this.buttonElement },
        { name: "log2", identifier: "d", eventType: "click", currentTarget: this.buttonElement },
        { name: "log3", identifier: "c", eventType: "click", currentTarget: this.buttonElement },
        { name: "log2", identifier: "d", eventType: "click", currentTarget: this.buttonElement },
        { name: "log3", identifier: "c", eventType: "click", currentTarget: this.buttonElement }
      );
    }
    async "test stop propagation with once"() {
      await this.setAction(this.buttonElement, "c#stop:once c#log");
      await this.triggerEvent(this.buttonElement, "click");
      this.assertActions({ name: "stop", identifier: "c", eventType: "click", currentTarget: this.buttonElement });
      await this.nextFrame;
      await this.triggerEvent(this.buttonElement, "click");
      this.assertActions(
        { name: "stop", identifier: "c", eventType: "click", currentTarget: this.buttonElement },
        { name: "log", identifier: "c", eventType: "click", currentTarget: this.buttonElement }
      );
    }
    async "test global once actions"() {
      await this.setAction(this.buttonElement, "keydown@window->c#log:once");
      await this.triggerEvent("#outside", "keydown");
      await this.triggerEvent("#outside", "keydown");
      this.assertActions({ name: "log", eventType: "keydown" });
    }
    async "test edge case when updating action list with setAttribute preserves once history"() {
      await this.setAction(this.buttonElement, "c#log:once");
      await this.triggerEvent(this.buttonElement, "click");
      await this.triggerEvent(this.buttonElement, "click");
      await this.setAction(this.buttonElement, "c#log2 c#log:once d#log");
      await this.triggerEvent(this.buttonElement, "click");
      this.assertActions(
        { name: "log", identifier: "c" },
        { name: "log2", identifier: "c" },
        { name: "log", identifier: "d" }
      );
    }
    async "test default passive action"() {
      await this.setAction(this.buttonElement, "scroll->c#logPassive:passive");
      await this.triggerEvent(this.buttonElement, "scroll", { setDefaultPrevented: false });
      this.assertActions({ name: "logPassive", eventType: "scroll", passive: true });
    }
    async "test global passive actions"() {
      await this.setAction(this.buttonElement, "mouseup@window->c#logPassive:passive");
      await this.triggerEvent("#outside", "mouseup", { setDefaultPrevented: false });
      this.assertActions({ name: "logPassive", eventType: "mouseup", passive: true });
    }
    async "test passive false actions"() {
      await this.setAction(this.buttonElement, "touchmove@window->c#logPassive:!passive");
      await this.triggerEvent("#outside", "touchmove", { setDefaultPrevented: false });
      this.assertActions({ name: "logPassive", eventType: "touchmove", passive: false });
    }
    async "test multiple options"() {
      await this.setAction(this.buttonElement, "touchmove@window->c#logPassive:once:!passive");
      await this.triggerEvent("#outside", "touchmove", { setDefaultPrevented: false });
      await this.triggerEvent("#outside", "touchmove", { setDefaultPrevented: false });
      this.assertActions({ name: "logPassive", eventType: "touchmove", passive: false });
    }
    async "test wrong options are silently ignored"() {
      await this.setAction(this.buttonElement, "c#log:wrong:verywrong");
      await this.triggerEvent(this.buttonElement, "click");
      await this.triggerEvent(this.buttonElement, "click");
      this.assertActions({ name: "log", identifier: "c" }, { name: "log", identifier: "c" });
    }
    async "test stop option with implicit event"() {
      await this.setAction(this.element, "click->c#log");
      await this.setAction(this.buttonElement, "c#log2:stop");
      await this.triggerEvent(this.buttonElement, "click");
      this.assertActions({ name: "log2", eventType: "click" });
    }
    async "test stop option with explicit event"() {
      await this.setAction(this.element, "keydown->c#log");
      await this.setAction(this.buttonElement, "keydown->c#log2:stop");
      await this.triggerEvent(this.buttonElement, "keydown");
      this.assertActions({ name: "log2", eventType: "keydown" });
    }
    async "test event propagation without stop option"() {
      await this.setAction(this.element, "click->c#log");
      await this.setAction(this.buttonElement, "c#log2");
      await this.triggerEvent(this.buttonElement, "click");
      this.assertActions({ name: "log2", eventType: "click" }, { name: "log", eventType: "click" });
    }
    async "test prevent option with implicit event"() {
      await this.setAction(this.buttonElement, "c#log:prevent");
      await this.triggerEvent(this.buttonElement, "click");
      this.assertActions({ name: "log", eventType: "click", defaultPrevented: true });
    }
    async "test prevent option with explicit event"() {
      await this.setAction(this.buttonElement, "keyup->c#log:prevent");
      await this.triggerEvent(this.buttonElement, "keyup");
      this.assertActions({ name: "log", eventType: "keyup", defaultPrevented: true });
    }
    async "test self option"() {
      await this.setAction(this.buttonElement, "click->c#log:self");
      await this.triggerEvent(this.buttonElement, "click");
      this.assertActions({ name: "log", eventType: "click" });
    }
    async "test self option on parent"() {
      await this.setAction(this.element, "click->c#log:self");
      await this.triggerEvent(this.buttonElement, "click");
      this.assertNoActions();
    }
    async "test custom action option callback params contain the controller instance"() {
      let lastActionOptions = {};
      const mockCallback2 = (options) => {
        lastActionOptions = options;
      };
      this.application.registerActionOption("all", (options) => {
        mockCallback2(options);
        return true;
      });
      await this.setAction(this.buttonElement, "click->c#log:all");
      await this.triggerEvent(this.buttonElement, "click");
      this.assertActions({ name: "log", identifier: "c", eventType: "click", currentTarget: this.buttonElement });
      this.assert.deepEqual(["name", "value", "event", "element", "controller"], Object.keys(lastActionOptions));
      this.assert.equal(
        lastActionOptions.controller,
        this.application.getControllerForElementAndIdentifier(this.element, "c")
      );
      this.controllerConstructor.actionLog = [];
      await this.setAction(this.buttonElement, "click->d#log:all");
      await this.triggerEvent(this.buttonElement, "click");
      this.assertActions({ name: "log", identifier: "d", eventType: "click", currentTarget: this.buttonElement });
      this.assert.deepEqual(["name", "value", "event", "element", "controller"], Object.keys(lastActionOptions));
      this.assert.equal(
        lastActionOptions.controller,
        this.application.getControllerForElementAndIdentifier(this.element, "d")
      );
    }
    async "test custom option"() {
      this.application.registerActionOption("open", ({ value, event: { type, target } }) => {
        switch (type) {
          case "toggle":
            return target instanceof HTMLDetailsElement && target.open == value;
          default:
            return true;
        }
      });
      await this.setAction(this.detailsElement, "toggle->c#log:open");
      await this.toggleElement(this.detailsElement);
      await this.toggleElement(this.detailsElement);
      await this.toggleElement(this.detailsElement);
      this.assertActions({ name: "log", eventType: "toggle" }, { name: "log", eventType: "toggle" });
    }
    async "test inverted custom option"() {
      this.application.registerActionOption("open", ({ value, event: { type, target } }) => {
        switch (type) {
          case "toggle":
            return target instanceof HTMLDetailsElement && target.open == value;
          default:
            return true;
        }
      });
      await this.setAction(this.detailsElement, "toggle->c#log:!open");
      await this.toggleElement(this.detailsElement);
      await this.toggleElement(this.detailsElement);
      await this.toggleElement(this.detailsElement);
      this.assertActions({ name: "log", eventType: "toggle" });
    }
    async "test custom action option callback event contains params"() {
      let lastActionEventParams = {};
      const mockCallback2 = ({ event: { params = {} } = {} }) => {
        lastActionEventParams = __spreadValues({}, params);
      };
      this.application.registerActionOption("all", (options) => {
        mockCallback2(options);
        return true;
      });
      this.buttonElement.setAttribute("data-c-custom-number-param", "41");
      this.buttonElement.setAttribute("data-c-custom-string-param", "validation");
      this.buttonElement.setAttribute("data-c-custom-boolean-param", "true");
      this.buttonElement.setAttribute("data-d-should-ignore-param", "_IGNORED_");
      await this.setAction(this.buttonElement, "click->c#log:all");
      await this.triggerEvent(this.buttonElement, "click");
      this.assertActions({ name: "log", identifier: "c", eventType: "click", currentTarget: this.buttonElement });
      const expectedEventParams = {
        customBoolean: true,
        customNumber: 41,
        customString: "validation"
      };
      this.assert.deepEqual(this.controllerConstructor.actionLog[0].params, expectedEventParams);
      this.assert.deepEqual(lastActionEventParams, expectedEventParams);
    }
    setAction(element, value) {
      element.setAttribute("data-action", value);
      return this.nextFrame;
    }
    toggleElement(details) {
      details.toggleAttribute("open");
      return this.nextFrame;
    }
    get element() {
      return this.findElement("div");
    }
    get buttonElement() {
      return this.findElement("button");
    }
    get detailsElement() {
      return this.findElement("details");
    }
  };

  // src/tests/modules/core/extending_application_tests.ts
  var mockCallback = (label) => {
    mockCallback.lastCall = label;
  };
  mockCallback.lastCall = null;
  var TestApplicationWithCustomBehavior = class extends Application {
    registerActionOption(name, filter) {
      mockCallback(`registerActionOption:${name}`);
      super.registerActionOption(name, filter);
    }
  };
  var ExtendingApplicationTests = class extends DOMTestCase {
    async runTest(testName) {
      try {
        this.application = TestApplicationWithCustomBehavior.start(this.fixtureElement);
        await super.runTest(testName);
      } finally {
        this.application.stop();
      }
    }
    async setup() {
      mockCallback.lastCall = null;
    }
    async teardown() {
      mockCallback.lastCall = null;
    }
    async "test extended class method is supported when using MyApplication.start()"() {
      this.assert.equal(mockCallback.lastCall, null);
      const mockTrue = () => true;
      this.application.registerActionOption("kbd", mockTrue);
      this.assert.equal(this.application.actionDescriptorFilters["kbd"], mockTrue);
      this.assert.equal(mockCallback.lastCall, "registerActionOption:kbd");
      const mockFalse = () => false;
      this.application.registerActionOption("xyz", mockFalse);
      this.assert.equal(this.application.actionDescriptorFilters["xyz"], mockFalse);
      this.assert.equal(mockCallback.lastCall, "registerActionOption:xyz");
    }
  };

  // src/tests/controllers/target_controller.ts
  var BaseTargetController = class extends Controller {
  };
  BaseTargetController.targets = ["alpha"];
  var TargetController = class extends BaseTargetController {
    constructor() {
      super(...arguments);
      this.inputTargetConnectedCallCountValue = 0;
      this.inputTargetDisconnectedCallCountValue = 0;
      this.recursiveTargetConnectedCallCountValue = 0;
      this.recursiveTargetDisconnectedCallCountValue = 0;
    }
    inputTargetConnected(element) {
      if (this.hasConnectedClass) element.classList.add(this.connectedClass);
      this.inputTargetConnectedCallCountValue++;
    }
    inputTargetDisconnected(element) {
      if (this.hasDisconnectedClass) element.classList.add(this.disconnectedClass);
      this.inputTargetDisconnectedCallCountValue++;
    }
    recursiveTargetConnected(element) {
      element.remove();
      this.recursiveTargetConnectedCallCountValue++;
      this.element.append(element);
    }
    recursiveTargetDisconnected(_element) {
      this.recursiveTargetDisconnectedCallCountValue++;
    }
  };
  TargetController.classes = ["connected", "disconnected"];
  TargetController.targets = ["beta", "input", "recursive"];
  TargetController.values = {
    inputTargetConnectedCallCount: Number,
    inputTargetDisconnectedCallCount: Number,
    recursiveTargetConnectedCallCount: Number,
    recursiveTargetDisconnectedCallCount: Number
  };

  // src/tests/modules/core/legacy_target_tests.ts
  var LegacyTargetTests = class extends ControllerTestCase(TargetController) {
    constructor() {
      super(...arguments);
      this.fixtureHTML = `
    <div data-controller="${this.identifier}">
      <div data-target="${this.identifier}.alpha" id="alpha1"></div>
      <div data-target="${this.identifier}.alpha" id="alpha2"></div>
      <div data-target="${this.identifier}.beta" data-${this.identifier}-target="gamma" id="beta1">
        <div data-target="${this.identifier}.gamma" id="gamma1"></div>
      </div>
      <div data-controller="${this.identifier}" id="child">
        <div data-target="${this.identifier}.delta" id="delta1"></div>
      </div>
      <textarea data-target="${this.identifier}.input" id="input1"></textarea>
    </div>
  `;
      this.warningCount = 0;
    }
    async setupApplication() {
      super.setupApplication();
      this.application.logger = Object.create(console, {
        warn: {
          value: () => this.warningCount++
        }
      });
    }
    "test TargetSet#find"() {
      this.assert.equal(this.controller.targets.find("alpha"), this.findElement("#alpha1"));
      this.assert.equal(this.warningCount, 1);
    }
    "test TargetSet#find prefers scoped target attributes"() {
      this.assert.equal(this.controller.targets.find("gamma"), this.findElement("#beta1"));
      this.assert.equal(this.warningCount, 0);
    }
    "test TargetSet#findAll"() {
      this.assert.deepEqual(this.controller.targets.findAll("alpha"), this.findElements("#alpha1", "#alpha2"));
      this.assert.equal(this.warningCount, 2);
    }
    "test TargetSet#findAll prioritizes scoped target attributes"() {
      this.assert.deepEqual(this.controller.targets.findAll("gamma"), this.findElements("#beta1", "#gamma1"));
      this.assert.equal(this.warningCount, 1);
    }
    "test TargetSet#findAll with multiple arguments"() {
      this.assert.deepEqual(
        this.controller.targets.findAll("alpha", "beta"),
        this.findElements("#alpha1", "#alpha2", "#beta1")
      );
      this.assert.equal(this.warningCount, 3);
    }
    "test TargetSet#has"() {
      this.assert.equal(this.controller.targets.has("gamma"), true);
      this.assert.equal(this.controller.targets.has("delta"), false);
      this.assert.equal(this.warningCount, 0);
    }
    "test TargetSet#find ignores child controller targets"() {
      this.assert.equal(this.controller.targets.find("delta"), null);
      this.findElement("#child").removeAttribute("data-controller");
      this.assert.equal(this.controller.targets.find("delta"), this.findElement("#delta1"));
      this.assert.equal(this.warningCount, 1);
    }
    "test linked target properties"() {
      this.assert.equal(this.controller.betaTarget, this.findElement("#beta1"));
      this.assert.deepEqual(this.controller.betaTargets, this.findElements("#beta1"));
      this.assert.equal(this.controller.hasBetaTarget, true);
      this.assert.equal(this.warningCount, 1);
    }
    "test inherited linked target properties"() {
      this.assert.equal(this.controller.alphaTarget, this.findElement("#alpha1"));
      this.assert.deepEqual(this.controller.alphaTargets, this.findElements("#alpha1", "#alpha2"));
      this.assert.equal(this.warningCount, 2);
    }
    "test singular linked target property throws an error when no target is found"() {
      this.findElement("#beta1").removeAttribute("data-target");
      this.assert.equal(this.controller.hasBetaTarget, false);
      this.assert.equal(this.controller.betaTargets.length, 0);
      this.assert.throws(() => this.controller.betaTarget);
    }
  };

  // src/tests/modules/core/lifecycle_tests.ts
  var LifecycleTests = class extends LogControllerTestCase {
    async setup() {
      this.controllerElement = this.controller.element;
    }
    async "test Controller#initialize"() {
      const controller = this.controller;
      this.assert.equal(controller.initializeCount, 1);
      await this.reconnectControllerElement();
      this.assert.equal(this.controller, controller);
      this.assert.equal(controller.initializeCount, 1);
    }
    async "test Controller#connect"() {
      this.assert.equal(this.controller.connectCount, 1);
      await this.reconnectControllerElement();
      this.assert.equal(this.controller.connectCount, 2);
    }
    async "test Controller#disconnect"() {
      const controller = this.controller;
      this.assert.equal(controller.disconnectCount, 0);
      await this.disconnectControllerElement();
      this.assert.equal(controller.disconnectCount, 1);
    }
    async reconnectControllerElement() {
      await this.disconnectControllerElement();
      await this.connectControllerElement();
    }
    async connectControllerElement() {
      this.fixtureElement.appendChild(this.controllerElement);
      await this.nextFrame;
    }
    async disconnectControllerElement() {
      this.fixtureElement.removeChild(this.controllerElement);
      await this.nextFrame;
    }
  };

  // src/tests/modules/core/loading_tests.ts
  var UnloadableController = class extends LogController {
    static get shouldLoad() {
      return false;
    }
  };
  var LoadableController = class extends LogController {
    static get shouldLoad() {
      return true;
    }
  };
  var AfterLoadController = class extends LogController {
    static afterLoad(identifier, application) {
      const newElement = document.createElement("div");
      newElement.classList.add("after-load-test");
      newElement.setAttribute(application.schema.controllerAttribute, identifier);
      application.element.append(newElement);
      document.dispatchEvent(
        new CustomEvent("test", {
          detail: { identifier, application, exampleDefault: this.values.example.default, controller: this }
        })
      );
    }
  };
  AfterLoadController.values = {
    example: { default: "demo", type: String }
  };
  var ApplicationTests2 = class extends ApplicationTestCase {
    constructor() {
      super(...arguments);
      this.fixtureHTML = `<div data-controller="loadable"><div data-controller="unloadable">`;
    }
    "test module with false shouldLoad should not load when registering"() {
      this.application.register("unloadable", UnloadableController);
      this.assert.equal(this.controllers.length, 0);
    }
    "test module with true shouldLoad should load when registering"() {
      this.application.register("loadable", LoadableController);
      this.assert.equal(this.controllers.length, 1);
    }
    "test module with afterLoad method should be triggered when registered"() {
      let data = {};
      document.addEventListener("test", ({ detail }) => {
        data = detail;
      });
      this.assert.equal(data.application, void 0);
      this.assert.equal(data.controller, void 0);
      this.assert.equal(data.exampleDefault, void 0);
      this.assert.equal(data.identifier, void 0);
      this.application.register("after-load", AfterLoadController);
      this.assert.equal(this.findElements('[data-controller="after-load"]').length, 1);
      this.assert.equal(data.application, this.application);
      this.assert.equal(data.controller, AfterLoadController);
      this.assert.equal(data.exampleDefault, "demo");
      this.assert.equal(data.identifier, "after-load");
    }
    get controllers() {
      return this.application.controllers;
    }
  };

  // src/tests/modules/core/memory_tests.ts
  var MemoryTests = class extends ControllerTestCase() {
    constructor() {
      super(...arguments);
      this.fixtureHTML = `
    <div data-controller="${this.identifier}">
      <button data-action="${this.identifier}#doLog">Log</button>
      <button data-action="${this.identifier}#doAlert">Alert</button>
    </div>
  `;
    }
    async setup() {
      this.controllerElement = this.controller.element;
    }
    async "test removing a controller clears dangling eventListeners"() {
      this.assert.equal(this.application.dispatcher.eventListeners.length, 2);
      await this.fixtureElement.removeChild(this.controllerElement);
      this.assert.equal(this.application.dispatcher.eventListeners.length, 0);
    }
  };

  // src/tests/controllers/outlet_controller.ts
  var BaseOutletController = class extends Controller {
  };
  BaseOutletController.outlets = ["alpha"];
  var OutletController = class extends BaseOutletController {
    constructor() {
      super(...arguments);
      this.alphaOutletConnectedCallCountValue = 0;
      this.alphaOutletDisconnectedCallCountValue = 0;
      this.betaOutletConnectedCallCountValue = 0;
      this.betaOutletDisconnectedCallCountValue = 0;
      this.betaOutletsInConnectValue = 0;
      this.gammaOutletConnectedCallCountValue = 0;
      this.gammaOutletDisconnectedCallCountValue = 0;
      this.namespacedEpsilonOutletConnectedCallCountValue = 0;
      this.namespacedEpsilonOutletDisconnectedCallCountValue = 0;
    }
    connect() {
      this.betaOutletsInConnectValue = this.betaOutlets.length;
    }
    alphaOutletConnected(_outlet, element) {
      if (this.hasConnectedClass) element.classList.add(this.connectedClass);
      this.alphaOutletConnectedCallCountValue++;
    }
    alphaOutletDisconnected(_outlet, element) {
      if (this.hasDisconnectedClass) element.classList.add(this.disconnectedClass);
      this.alphaOutletDisconnectedCallCountValue++;
    }
    betaOutletConnected(_outlet, element) {
      if (this.hasConnectedClass) element.classList.add(this.connectedClass);
      this.betaOutletConnectedCallCountValue++;
    }
    betaOutletDisconnected(_outlet, element) {
      if (this.hasDisconnectedClass) element.classList.add(this.disconnectedClass);
      this.betaOutletDisconnectedCallCountValue++;
    }
    gammaOutletConnected(_outlet, element) {
      if (this.hasConnectedClass) element.classList.add(this.connectedClass);
      this.gammaOutletConnectedCallCountValue++;
    }
    namespacedEpsilonOutletConnected(_outlet, element) {
      if (this.hasConnectedClass) element.classList.add(this.connectedClass);
      this.namespacedEpsilonOutletConnectedCallCountValue++;
    }
    namespacedEpsilonOutletDisconnected(_outlet, element) {
      if (this.hasDisconnectedClass) element.classList.add(this.disconnectedClass);
      this.namespacedEpsilonOutletDisconnectedCallCountValue++;
    }
  };
  OutletController.classes = ["connected", "disconnected"];
  OutletController.outlets = ["beta", "gamma", "delta", "omega", "namespaced--epsilon"];
  OutletController.values = {
    alphaOutletConnectedCallCount: Number,
    alphaOutletDisconnectedCallCount: Number,
    betaOutletConnectedCallCount: Number,
    betaOutletDisconnectedCallCount: Number,
    betaOutletsInConnect: Number,
    gammaOutletConnectedCallCount: Number,
    gammaOutletDisconnectedCallCount: Number,
    namespacedEpsilonOutletConnectedCallCount: Number,
    namespacedEpsilonOutletDisconnectedCallCount: Number
  };

  // src/tests/modules/core/outlet_order_tests.ts
  var connectOrder = [];
  var OutletOrderController = class extends OutletController {
    connect() {
      connectOrder.push(`${this.identifier}-${this.element.id}-start`);
      super.connect();
      connectOrder.push(`${this.identifier}-${this.element.id}-end`);
    }
  };
  var OutletOrderTests = class extends ControllerTestCase(OutletOrderController) {
    constructor() {
      super(...arguments);
      this.fixtureHTML = `
    <div data-controller="alpha" id="alpha1" data-alpha-beta-outlet=".beta">Search</div>
    <div data-controller="beta" id="beta-1" class="beta">Beta</div>
    <div data-controller="beta" id="beta-2" class="beta">Beta</div>
    <div data-controller="beta" id="beta-3" class="beta">Beta</div>
  `;
    }
    get identifiers() {
      return ["alpha", "beta"];
    }
    async "test can access outlets in connect() even if they are referenced before they are connected"() {
      this.assert.equal(this.controller.betaOutletsInConnectValue, 3);
      this.controller.betaOutlets.forEach((outlet) => {
        this.assert.equal(outlet.identifier, "beta");
        this.assert.equal(Array.from(outlet.element.classList.values()), "beta");
      });
      this.assert.deepEqual(connectOrder, [
        "alpha-alpha1-start",
        "beta-beta-1-start",
        "beta-beta-1-end",
        "beta-beta-2-start",
        "beta-beta-2-end",
        "beta-beta-3-start",
        "beta-beta-3-end",
        "alpha-alpha1-end"
      ]);
    }
  };

  // src/tests/modules/core/outlet_tests.ts
  var OutletTests = class extends ControllerTestCase(OutletController) {
    constructor() {
      super(...arguments);
      this.fixtureHTML = `
    <div id="container">
      <div data-controller="alpha" class="alpha" id="alpha1"></div>
      <div data-controller="alpha" class="alpha" id="alpha2"></div>

      <div data-controller="beta" class="beta" id="beta1">
        <div data-controller="beta" class="beta" id="beta2"></div>
        <div id="beta3"></div>
        <div data-controller="beta" id="beta4"></div>
      </div>

      <div
        data-controller="${this.identifier}"
        data-${this.identifier}-connected-class="connected"
        data-${this.identifier}-disconnected-class="disconnected"
        data-${this.identifier}-alpha-outlet="#alpha1,#alpha2"
        data-${this.identifier}-beta-outlet=".beta"
        data-${this.identifier}-delta-outlet=".delta"
        data-${this.identifier}-namespaced--epsilon-outlet=".epsilon"
      >
        <div data-controller="gamma" class="gamma" id="gamma2"></div>
      </div>

      <div data-controller="delta gamma" class="delta gamma" id="delta1">
        <div data-controller="gamma" class="gamma" id="gamma1"></div>
      </div>

      <div data-controller="namespaced--epsilon" class="epsilon" id="epsilon1"></div>

      <div data-controller="namespaced--epsilon" class="epsilon" id="epsilon2"></div>

      <div class="beta" id="beta5"></div>
    </div>
  `;
    }
    get identifiers() {
      return ["test", "alpha", "beta", "gamma", "delta", "omega", "namespaced--epsilon"];
    }
    "test OutletSet#find"() {
      this.assert.equal(this.controller.outlets.find("alpha"), this.findElement("#alpha1"));
      this.assert.equal(this.controller.outlets.find("beta"), this.findElement("#beta1"));
      this.assert.equal(this.controller.outlets.find("delta"), this.findElement("#delta1"));
      this.assert.equal(this.controller.outlets.find("namespaced--epsilon"), this.findElement("#epsilon1"));
    }
    "test OutletSet#findAll"() {
      this.assert.deepEqual(this.controller.outlets.findAll("alpha"), this.findElements("#alpha1", "#alpha2"));
      this.assert.deepEqual(this.controller.outlets.findAll("beta"), this.findElements("#beta1", "#beta2"));
      this.assert.deepEqual(
        this.controller.outlets.findAll("namespaced--epsilon"),
        this.findElements("#epsilon1", "#epsilon2")
      );
    }
    "test OutletSet#findAll with multiple arguments"() {
      this.assert.deepEqual(
        this.controller.outlets.findAll("alpha", "beta", "namespaced--epsilon"),
        this.findElements("#alpha1", "#alpha2", "#beta1", "#beta2", "#epsilon1", "#epsilon2")
      );
    }
    "test OutletSet#has"() {
      this.assert.equal(this.controller.outlets.has("alpha"), true);
      this.assert.equal(this.controller.outlets.has("beta"), true);
      this.assert.equal(this.controller.outlets.has("gamma"), false);
      this.assert.equal(this.controller.outlets.has("delta"), true);
      this.assert.equal(this.controller.outlets.has("omega"), false);
      this.assert.equal(this.controller.outlets.has("namespaced--epsilon"), true);
    }
    "test OutletSet#has when attribute gets added later"() {
      this.assert.equal(this.controller.outlets.has("gamma"), false);
      this.controller.element.setAttribute(`data-${this.identifier}-gamma-outlet`, ".gamma");
      this.assert.equal(this.controller.outlets.has("gamma"), true);
    }
    "test OutletSet#has when no element with selector exists"() {
      this.controller.element.setAttribute(`data-${this.identifier}-gamma-outlet`, "#doesntexist");
      this.assert.equal(this.controller.outlets.has("gamma"), false);
    }
    "test OutletSet#has when selector matches but element doesn't have the right controller"() {
      this.controller.element.setAttribute(`data-${this.identifier}-gamma-outlet`, ".alpha");
      this.assert.equal(this.controller.outlets.has("gamma"), false);
    }
    "test linked outlet properties"() {
      const element = this.findElement("#beta1");
      const betaOutlet = this.controller.application.getControllerForElementAndIdentifier(element, "beta");
      this.assert.equal(this.controller.betaOutlet, betaOutlet);
      this.assert.equal(this.controller.betaOutletElement, element);
      const elements = this.findElements("#beta1", "#beta2");
      const betaOutlets = elements.map(
        (element2) => this.controller.application.getControllerForElementAndIdentifier(element2, "beta")
      );
      this.assert.deepEqual(this.controller.betaOutlets, betaOutlets);
      this.assert.deepEqual(this.controller.betaOutletElements, elements);
      this.assert.equal(this.controller.hasBetaOutlet, true);
    }
    "test inherited linked outlet properties"() {
      const element = this.findElement("#alpha1");
      const alphaOutlet = this.controller.application.getControllerForElementAndIdentifier(element, "alpha");
      this.assert.equal(this.controller.alphaOutlet, alphaOutlet);
      this.assert.equal(this.controller.alphaOutletElement, element);
      const elements = this.findElements("#alpha1", "#alpha2");
      const alphaOutlets = elements.map(
        (element2) => this.controller.application.getControllerForElementAndIdentifier(element2, "alpha")
      );
      this.assert.deepEqual(this.controller.alphaOutlets, alphaOutlets);
      this.assert.deepEqual(this.controller.alphaOutletElements, elements);
    }
    "test singular linked outlet property throws an error when no outlet is found"() {
      this.findElements("#alpha1", "#alpha2").forEach((e) => {
        e.removeAttribute("id");
        e.removeAttribute("class");
        e.removeAttribute("data-controller");
      });
      this.assert.equal(this.controller.hasAlphaOutlet, false);
      this.assert.equal(this.controller.alphaOutlets.length, 0);
      this.assert.equal(this.controller.alphaOutletElements.length, 0);
      this.assert.throws(() => this.controller.alphaOutlet);
      this.assert.throws(() => this.controller.alphaOutletElement);
    }
    async "test outlet connected callback fires"() {
      const alphaOutlets = this.controller.alphaOutletElements.filter((outlet) => outlet.classList.contains("connected"));
      this.assert.equal(alphaOutlets.length, 2);
      this.assert.equal(this.controller.alphaOutletConnectedCallCountValue, 2);
    }
    "test outlet connected callback fires for namespaced outlets"() {
      const epsilonOutlets = this.controller.namespacedEpsilonOutletElements.filter(
        (outlet) => outlet.classList.contains("connected")
      );
      this.assert.equal(epsilonOutlets.length, 2);
      this.assert.equal(this.controller.namespacedEpsilonOutletConnectedCallCountValue, 2);
    }
    async "test outlet connected callback when element is inserted"() {
      const betaOutletElement = document.createElement("div");
      await this.setAttribute(betaOutletElement, "class", "beta");
      await this.setAttribute(betaOutletElement, "data-controller", "beta");
      this.assert.equal(this.controller.betaOutletConnectedCallCountValue, 2);
      await this.appendChild(this.controller.element, betaOutletElement);
      this.assert.equal(this.controller.betaOutletConnectedCallCountValue, 3);
      this.assert.ok(
        betaOutletElement.classList.contains("connected"),
        `expected "${betaOutletElement.className}" to contain "connected"`
      );
      this.assert.ok(betaOutletElement.isConnected, "element is present in document");
      await this.appendChild("#container", betaOutletElement.cloneNode(true));
      this.assert.equal(this.controller.betaOutletConnectedCallCountValue, 4);
    }
    async "test outlet connected callback when present element adds matching outlet selector attribute"() {
      const element = this.findElement("#beta3");
      this.assert.equal(this.controller.betaOutletConnectedCallCountValue, 2);
      await this.setAttribute(element, "data-controller", "beta");
      await this.setAttribute(element, "class", "beta");
      this.assert.equal(this.controller.betaOutletConnectedCallCountValue, 3);
      this.assert.ok(element.classList.contains("connected"), `expected "${element.className}" to contain "connected"`);
      this.assert.ok(element.isConnected, "element is still present in document");
    }
    async "test outlet connected callback when present element already has connected controller and adds matching outlet selector attribute"() {
      const element = this.findElement("#beta4");
      this.assert.equal(this.controller.betaOutletConnectedCallCountValue, 2);
      await this.setAttribute(element, "class", "beta");
      this.assert.equal(this.controller.betaOutletConnectedCallCountValue, 3);
      this.assert.ok(element.classList.contains("connected"), `expected "${element.className}" to contain "connected"`);
      this.assert.ok(element.isConnected, "element is still present in document");
    }
    async "test outlet connect callback when an outlet present in the document adds a matching data-controller attribute"() {
      const element = this.findElement("#beta5");
      this.assert.equal(this.controller.betaOutletConnectedCallCountValue, 2);
      await this.setAttribute(element, "data-controller", "beta");
      this.assert.equal(this.controller.betaOutletConnectedCallCountValue, 3);
      this.assert.ok(element.classList.contains("connected"), `expected "${element.className}" to contain "connected"`);
      this.assert.ok(element.isConnected, "element is still present in document");
    }
    async "test outlet disconnected callback fires when calling disconnect() on the controller"() {
      this.assert.equal(
        this.controller.alphaOutletElements.filter((outlet) => outlet.classList.contains("disconnected")).length,
        0
      );
      this.assert.equal(this.controller.alphaOutletDisconnectedCallCountValue, 0);
      this.controller.context.disconnect();
      await this.nextFrame;
      this.assert.equal(
        this.controller.alphaOutletElements.filter((outlet) => outlet.classList.contains("disconnected")).length,
        2
      );
      this.assert.equal(this.controller.alphaOutletDisconnectedCallCountValue, 2);
    }
    async "test outlet disconnected callback when element is removed"() {
      const disconnectedAlpha = this.findElement("#alpha1");
      this.assert.equal(this.controller.alphaOutletDisconnectedCallCountValue, 0);
      this.assert.notOk(
        disconnectedAlpha.classList.contains("disconnected"),
        `expected "${disconnectedAlpha.className}" not to contain "disconnected"`
      );
      await this.remove(disconnectedAlpha);
      this.assert.equal(this.controller.alphaOutletDisconnectedCallCountValue, 1);
      this.assert.ok(
        disconnectedAlpha.classList.contains("disconnected"),
        `expected "${disconnectedAlpha.className}" to contain "disconnected"`
      );
      this.assert.notOk(disconnectedAlpha.isConnected, "element is not present in document");
    }
    async "test outlet disconnected callback when element is removed with namespaced outlet"() {
      const disconnectedEpsilon = this.findElement("#epsilon1");
      this.assert.equal(this.controller.namespacedEpsilonOutletDisconnectedCallCountValue, 0);
      this.assert.notOk(
        disconnectedEpsilon.classList.contains("disconnected"),
        `expected "${disconnectedEpsilon.className}" not to contain "disconnected"`
      );
      await this.remove(disconnectedEpsilon);
      this.assert.equal(this.controller.namespacedEpsilonOutletDisconnectedCallCountValue, 1);
      this.assert.ok(
        disconnectedEpsilon.classList.contains("disconnected"),
        `expected "${disconnectedEpsilon.className}" to contain "disconnected"`
      );
      this.assert.notOk(disconnectedEpsilon.isConnected, "element is not present in document");
    }
    async "test outlet disconnected callback when an outlet present in the document removes the selector attribute"() {
      const element = this.findElement("#alpha1");
      this.assert.equal(this.controller.alphaOutletDisconnectedCallCountValue, 0);
      this.assert.notOk(
        element.classList.contains("disconnected"),
        `expected "${element.className}" not to contain "disconnected"`
      );
      await this.removeAttribute(element, "id");
      this.assert.equal(this.controller.alphaOutletDisconnectedCallCountValue, 1);
      this.assert.ok(
        element.classList.contains("disconnected"),
        `expected "${element.className}" to contain "disconnected"`
      );
      this.assert.ok(element.isConnected, "element is still present in document");
    }
    async "test outlet disconnected callback when an outlet present in the document removes the data-controller attribute"() {
      const element = this.findElement("#alpha1");
      this.assert.equal(this.controller.alphaOutletDisconnectedCallCountValue, 0);
      this.assert.notOk(
        element.classList.contains("disconnected"),
        `expected "${element.className}" not to contain "disconnected"`
      );
      await this.removeAttribute(element, "data-controller");
      this.assert.equal(this.controller.alphaOutletDisconnectedCallCountValue, 1);
      this.assert.ok(
        element.classList.contains("disconnected"),
        `expected "${element.className}" to contain "disconnected"`
      );
      this.assert.ok(element.isConnected, "element is still present in document");
    }
    async "test outlet connect callback when the controlled element's outlet attribute is added"() {
      const gamma2 = this.findElement("#gamma2");
      await this.setAttribute(this.controller.element, `data-${this.identifier}-gamma-outlet`, "#gamma2");
      this.assert.equal(this.controller.gammaOutletConnectedCallCountValue, 1);
      this.assert.ok(gamma2.isConnected, "#gamma2 is still present in document");
      this.assert.ok(gamma2.classList.contains("connected"), `expected "${gamma2.className}" to contain "connected"`);
    }
    async "test outlet connect callback doesn't get trigged when any attribute gets added to the controller element"() {
      this.assert.equal(this.controller.alphaOutletConnectedCallCountValue, 2);
      this.assert.equal(this.controller.betaOutletConnectedCallCountValue, 2);
      this.assert.equal(this.controller.gammaOutletConnectedCallCountValue, 0);
      this.assert.equal(this.controller.namespacedEpsilonOutletConnectedCallCountValue, 2);
      await this.setAttribute(this.controller.element, "data-some-random-attribute", "#alpha1");
      this.assert.equal(this.controller.alphaOutletConnectedCallCountValue, 2);
      this.assert.equal(this.controller.betaOutletConnectedCallCountValue, 2);
      this.assert.equal(this.controller.gammaOutletConnectedCallCountValue, 0);
      this.assert.equal(this.controller.namespacedEpsilonOutletConnectedCallCountValue, 2);
      this.assert.equal(this.controller.alphaOutletDisconnectedCallCountValue, 0);
      this.assert.equal(this.controller.betaOutletDisconnectedCallCountValue, 0);
      this.assert.equal(this.controller.gammaOutletDisconnectedCallCountValue, 0);
      this.assert.equal(this.controller.namespacedEpsilonOutletDisconnectedCallCountValue, 0);
    }
    async "test outlet connect callback when the controlled element's outlet attribute is changed"() {
      const alpha1 = this.findElement("#alpha1");
      const alpha2 = this.findElement("#alpha2");
      await this.setAttribute(this.controller.element, `data-${this.identifier}-alpha-outlet`, "#alpha1");
      this.assert.equal(this.controller.alphaOutletConnectedCallCountValue, 2);
      this.assert.equal(this.controller.alphaOutletDisconnectedCallCountValue, 1);
      this.assert.ok(alpha1.isConnected, "alpha1 is still present in document");
      this.assert.ok(alpha2.isConnected, "alpha2 is still present in document");
      this.assert.ok(alpha1.classList.contains("connected"), `expected "${alpha1.className}" to contain "connected"`);
      this.assert.notOk(
        alpha1.classList.contains("disconnected"),
        `expected "${alpha1.className}" to contain "disconnected"`
      );
      this.assert.ok(
        alpha2.classList.contains("disconnected"),
        `expected "${alpha2.className}" to contain "disconnected"`
      );
    }
    async "test outlet disconnected callback when the controlled element's outlet attribute is removed"() {
      const alpha1 = this.findElement("#alpha1");
      const alpha2 = this.findElement("#alpha2");
      await this.removeAttribute(this.controller.element, `data-${this.identifier}-alpha-outlet`);
      this.assert.equal(this.controller.alphaOutletDisconnectedCallCountValue, 2);
      this.assert.ok(alpha1.isConnected, "#alpha1 is still present in document");
      this.assert.ok(alpha2.isConnected, "#alpha2 is still present in document");
      this.assert.ok(
        alpha1.classList.contains("disconnected"),
        `expected "${alpha1.className}" to contain "disconnected"`
      );
      this.assert.ok(
        alpha2.classList.contains("disconnected"),
        `expected "${alpha2.className}" to contain "disconnected"`
      );
    }
  };

  // src/tests/modules/core/string_helpers_tests.ts
  var StringHelpersTests = class extends TestCase {
    "test should camelize strings"() {
      this.assert.equal(camelize("underscore_value"), "underscoreValue");
      this.assert.equal(camelize("Underscore_value"), "UnderscoreValue");
      this.assert.equal(camelize("underscore_Value"), "underscore_Value");
      this.assert.equal(camelize("Underscore_Value"), "Underscore_Value");
      this.assert.equal(camelize("multi_underscore_value"), "multiUnderscoreValue");
      this.assert.equal(camelize("dash-value"), "dashValue");
      this.assert.equal(camelize("Dash-value"), "DashValue");
      this.assert.equal(camelize("dash-Value"), "dash-Value");
      this.assert.equal(camelize("Dash-Value"), "Dash-Value");
      this.assert.equal(camelize("multi-dash-value"), "multiDashValue");
    }
    "test should namespace camelize strings"() {
      this.assert.equal(namespaceCamelize("underscore__value"), "underscoreValue");
      this.assert.equal(namespaceCamelize("Underscore__value"), "UnderscoreValue");
      this.assert.equal(namespaceCamelize("underscore__Value"), "underscore_Value");
      this.assert.equal(namespaceCamelize("Underscore__Value"), "Underscore_Value");
      this.assert.equal(namespaceCamelize("multi__underscore__value"), "multiUnderscoreValue");
      this.assert.equal(namespaceCamelize("dash--value"), "dashValue");
      this.assert.equal(namespaceCamelize("Dash--value"), "DashValue");
      this.assert.equal(namespaceCamelize("dash--Value"), "dash-Value");
      this.assert.equal(namespaceCamelize("Dash--Value"), "Dash-Value");
      this.assert.equal(namespaceCamelize("multi--dash--value"), "multiDashValue");
    }
    "test should dasherize strings"() {
      this.assert.equal(dasherize("camelizedValue"), "camelized-value");
      this.assert.equal(dasherize("longCamelizedValue"), "long-camelized-value");
    }
    "test should capitalize strings"() {
      this.assert.equal(capitalize("lowercase"), "Lowercase");
      this.assert.equal(capitalize("Uppercase"), "Uppercase");
    }
    "test should tokenize strings"() {
      this.assert.deepEqual(tokenize(""), []);
      this.assert.deepEqual(tokenize("one"), ["one"]);
      this.assert.deepEqual(tokenize("two words"), ["two", "words"]);
      this.assert.deepEqual(tokenize("a_lot of-words with special--chars mixed__in"), [
        "a_lot",
        "of-words",
        "with",
        "special--chars",
        "mixed__in"
      ]);
    }
  };

  // src/tests/modules/core/target_tests.ts
  var TargetTests = class extends ControllerTestCase(TargetController) {
    constructor() {
      super(...arguments);
      this.fixtureHTML = `
    <div data-controller="${this.identifier}" data-${this.identifier}-connected-class="connected" data-${this.identifier}-disconnected-class="disconnected">
      <div data-${this.identifier}-target="alpha" id="alpha1"></div>
      <div data-${this.identifier}-target="alpha" id="alpha2"></div>
      <div data-${this.identifier}-target="beta" id="beta1">
        <div data-${this.identifier}-target="gamma" id="gamma1"></div>
      </div>
      <div data-controller="${this.identifier}" id="child">
        <div data-${this.identifier}-target="delta" id="delta1"></div>
      </div>
      <textarea data-${this.identifier}-target="omega input" id="input1"></textarea>
    </div>
  `;
    }
    "test TargetSet#find"() {
      this.assert.equal(this.controller.targets.find("alpha"), this.findElement("#alpha1"));
    }
    "test TargetSet#findAll"() {
      this.assert.deepEqual(this.controller.targets.findAll("alpha"), this.findElements("#alpha1", "#alpha2"));
    }
    "test TargetSet#findAll with multiple arguments"() {
      this.assert.deepEqual(
        this.controller.targets.findAll("alpha", "beta"),
        this.findElements("#alpha1", "#alpha2", "#beta1")
      );
    }
    "test TargetSet#has"() {
      this.assert.equal(this.controller.targets.has("gamma"), true);
      this.assert.equal(this.controller.targets.has("delta"), false);
    }
    "test TargetSet#find ignores child controller targets"() {
      this.assert.equal(this.controller.targets.find("delta"), null);
      this.findElement("#child").removeAttribute("data-controller");
      this.assert.equal(this.controller.targets.find("delta"), this.findElement("#delta1"));
    }
    "test linked target properties"() {
      this.assert.equal(this.controller.betaTarget, this.findElement("#beta1"));
      this.assert.deepEqual(this.controller.betaTargets, this.findElements("#beta1"));
      this.assert.equal(this.controller.hasBetaTarget, true);
    }
    "test inherited linked target properties"() {
      this.assert.equal(this.controller.alphaTarget, this.findElement("#alpha1"));
      this.assert.deepEqual(this.controller.alphaTargets, this.findElements("#alpha1", "#alpha2"));
    }
    "test singular linked target property throws an error when no target is found"() {
      this.findElement("#beta1").removeAttribute(`data-${this.identifier}-target`);
      this.assert.equal(this.controller.hasBetaTarget, false);
      this.assert.equal(this.controller.betaTargets.length, 0);
      this.assert.throws(() => this.controller.betaTarget);
    }
    "test target connected callback fires after initialize() and when calling connect()"() {
      const connectedInputs = this.controller.inputTargets.filter((target) => target.classList.contains("connected"));
      this.assert.equal(connectedInputs.length, 1);
      this.assert.equal(this.controller.inputTargetConnectedCallCountValue, 1);
    }
    async "test target connected callback when element is inserted"() {
      const connectedInput = document.createElement("input");
      connectedInput.setAttribute(`data-${this.controller.identifier}-target`, "input");
      this.assert.equal(this.controller.inputTargetConnectedCallCountValue, 1);
      this.controller.element.appendChild(connectedInput);
      await this.nextFrame;
      this.assert.equal(this.controller.inputTargetConnectedCallCountValue, 2);
      this.assert.ok(
        connectedInput.classList.contains("connected"),
        `expected "${connectedInput.className}" to contain "connected"`
      );
      this.assert.ok(connectedInput.isConnected, "element is present in document");
    }
    async "test target connected callback when present element adds the target attribute"() {
      const element = this.findElement("#alpha1");
      this.assert.equal(this.controller.inputTargetConnectedCallCountValue, 1);
      element.setAttribute(`data-${this.controller.identifier}-target`, "input");
      await this.nextFrame;
      this.assert.equal(this.controller.inputTargetConnectedCallCountValue, 2);
      this.assert.ok(element.classList.contains("connected"), `expected "${element.className}" to contain "connected"`);
      this.assert.ok(element.isConnected, "element is still present in document");
    }
    async "test target connected callback when element adds a token to an existing target attribute"() {
      const element = this.findElement("#alpha1");
      this.assert.equal(this.controller.inputTargetConnectedCallCountValue, 1);
      element.setAttribute(`data-${this.controller.identifier}-target`, "alpha input");
      await this.nextFrame;
      this.assert.equal(this.controller.inputTargetConnectedCallCountValue, 2);
      this.assert.ok(element.classList.contains("connected"), `expected "${element.className}" to contain "connected"`);
      this.assert.ok(element.isConnected, "element is still present in document");
    }
    async "test target disconnected callback fires when calling disconnect() on the controller"() {
      this.assert.equal(
        this.controller.inputTargets.filter((target) => target.classList.contains("disconnected")).length,
        0
      );
      this.assert.equal(this.controller.inputTargetDisconnectedCallCountValue, 0);
      this.controller.context.disconnect();
      await this.nextFrame;
      this.assert.equal(
        this.controller.inputTargets.filter((target) => target.classList.contains("disconnected")).length,
        1
      );
      this.assert.equal(this.controller.inputTargetDisconnectedCallCountValue, 1);
    }
    async "test target disconnected callback when element is removed"() {
      var _a;
      const disconnectedInput = this.findElement("#input1");
      this.assert.equal(this.controller.inputTargetDisconnectedCallCountValue, 0);
      this.assert.notOk(
        disconnectedInput.classList.contains("disconnected"),
        `expected "${disconnectedInput.className}" not to contain "disconnected"`
      );
      (_a = disconnectedInput.parentElement) == null ? void 0 : _a.removeChild(disconnectedInput);
      await this.nextFrame;
      this.assert.equal(this.controller.inputTargetDisconnectedCallCountValue, 1);
      this.assert.ok(
        disconnectedInput.classList.contains("disconnected"),
        `expected "${disconnectedInput.className}" to contain "disconnected"`
      );
      this.assert.notOk(disconnectedInput.isConnected, "element is not present in document");
    }
    async "test target disconnected callback when an element present in the document removes the target attribute"() {
      const element = this.findElement("#input1");
      this.assert.equal(this.controller.inputTargetDisconnectedCallCountValue, 0);
      this.assert.notOk(
        element.classList.contains("disconnected"),
        `expected "${element.className}" not to contain "disconnected"`
      );
      element.removeAttribute(`data-${this.controller.identifier}-target`);
      await this.nextFrame;
      this.assert.equal(this.controller.inputTargetDisconnectedCallCountValue, 1);
      this.assert.ok(
        element.classList.contains("disconnected"),
        `expected "${element.className}" to contain "disconnected"`
      );
      this.assert.ok(element.isConnected, "element is still present in document");
    }
    async "test target disconnected(), then connected() callback fired when the target name is present after the attribute change"() {
      const element = this.findElement("#input1");
      this.assert.equal(this.controller.inputTargetConnectedCallCountValue, 1);
      this.assert.equal(this.controller.inputTargetDisconnectedCallCountValue, 0);
      this.assert.notOk(
        element.classList.contains("disconnected"),
        `expected "${element.className}" not to contain "disconnected"`
      );
      element.setAttribute(`data-${this.controller.identifier}-target`, "input");
      await this.nextFrame;
      this.assert.equal(this.controller.inputTargetConnectedCallCountValue, 2);
      this.assert.equal(this.controller.inputTargetDisconnectedCallCountValue, 1);
      this.assert.ok(
        element.classList.contains("disconnected"),
        `expected "${element.className}" to contain "disconnected"`
      );
      this.assert.ok(element.isConnected, "element is still present in document");
    }
    async "test [target]Connected() and [target]Disconnected() do not loop infinitely"() {
      this.controller.element.insertAdjacentHTML(
        "beforeend",
        `
      <div data-${this.identifier}-target="recursive" id="recursive2"></div>
    `
      );
      await this.nextFrame;
      this.assert.ok(!!this.fixtureElement.querySelector("#recursive2"));
      this.assert.equal(this.controller.recursiveTargetConnectedCallCountValue, 1);
      this.assert.equal(this.controller.recursiveTargetDisconnectedCallCountValue, 0);
    }
  };

  // src/tests/controllers/value_controller.ts
  var BaseValueController = class extends Controller {
  };
  BaseValueController.values = {
    shadowedBoolean: String,
    string: String,
    numeric: Number
  };
  var ValueController = class extends BaseValueController {
    constructor() {
      super(...arguments);
      this.loggedNumericValues = [];
      this.oldLoggedNumericValues = [];
      this.loggedMissingStringValues = [];
      this.oldLoggedMissingStringValues = [];
      this.optionsValues = [];
      this.oldOptionsValues = [];
    }
    numericValueChanged(value, oldValue) {
      this.loggedNumericValues.push(value);
      this.oldLoggedNumericValues.push(oldValue);
    }
    missingStringValueChanged(value, oldValue) {
      this.loggedMissingStringValues.push(value);
      this.oldLoggedMissingStringValues.push(oldValue);
    }
    optionsValueChanged(value, oldValue) {
      this.optionsValues.push(value);
      this.oldOptionsValues.push(oldValue);
    }
  };
  ValueController.values = {
    shadowedBoolean: Boolean,
    missingString: String,
    ids: Array,
    options: Object,
    "time-24hr": Boolean
  };

  // src/tests/modules/core/value_properties_tests.ts
  var ValuePropertiesTests = class extends ControllerTestCase(ValueController) {
    "test parseValueTypeConstant"() {
      this.assert.equal(parseValueTypeConstant(String), "string");
      this.assert.equal(parseValueTypeConstant(Boolean), "boolean");
      this.assert.equal(parseValueTypeConstant(Array), "array");
      this.assert.equal(parseValueTypeConstant(Object), "object");
      this.assert.equal(parseValueTypeConstant(Number), "number");
      this.assert.equal(parseValueTypeConstant(""), void 0);
      this.assert.equal(parseValueTypeConstant({}), void 0);
      this.assert.equal(parseValueTypeConstant([]), void 0);
      this.assert.equal(parseValueTypeConstant(true), void 0);
      this.assert.equal(parseValueTypeConstant(false), void 0);
      this.assert.equal(parseValueTypeConstant(0), void 0);
      this.assert.equal(parseValueTypeConstant(1), void 0);
      this.assert.equal(parseValueTypeConstant(null), void 0);
      this.assert.equal(parseValueTypeConstant(void 0), void 0);
    }
    "test parseValueTypeDefault"() {
      this.assert.equal(parseValueTypeDefault(""), "string");
      this.assert.equal(parseValueTypeDefault("Some string"), "string");
      this.assert.equal(parseValueTypeDefault(true), "boolean");
      this.assert.equal(parseValueTypeDefault(false), "boolean");
      this.assert.equal(parseValueTypeDefault([]), "array");
      this.assert.equal(parseValueTypeDefault([1, 2, 3]), "array");
      this.assert.equal(parseValueTypeDefault([true, false, true]), "array");
      this.assert.equal(parseValueTypeDefault([{}, {}, {}]), "array");
      this.assert.equal(parseValueTypeDefault({}), "object");
      this.assert.equal(parseValueTypeDefault({ one: "key" }), "object");
      this.assert.equal(parseValueTypeDefault(-1), "number");
      this.assert.equal(parseValueTypeDefault(0), "number");
      this.assert.equal(parseValueTypeDefault(1), "number");
      this.assert.equal(parseValueTypeDefault(-0.1), "number");
      this.assert.equal(parseValueTypeDefault(0), "number");
      this.assert.equal(parseValueTypeDefault(0.1), "number");
      this.assert.equal(parseValueTypeDefault(null), void 0);
      this.assert.equal(parseValueTypeDefault(void 0), void 0);
    }
    "test parseValueTypeObject"() {
      const typeObject = (object) => {
        return parseValueTypeObject({
          controller: this.controller.identifier,
          token: "url",
          typeObject: object
        });
      };
      this.assert.equal(typeObject({ type: String, default: "" }), "string");
      this.assert.equal(typeObject({ type: String, default: "123" }), "string");
      this.assert.equal(typeObject({ type: String }), "string");
      this.assert.equal(typeObject({ default: "" }), "string");
      this.assert.equal(typeObject({ default: "123" }), "string");
      this.assert.equal(typeObject({ type: Number, default: 0 }), "number");
      this.assert.equal(typeObject({ type: Number, default: 1 }), "number");
      this.assert.equal(typeObject({ type: Number, default: -1 }), "number");
      this.assert.equal(typeObject({ type: Number }), "number");
      this.assert.equal(typeObject({ default: 0 }), "number");
      this.assert.equal(typeObject({ default: 1 }), "number");
      this.assert.equal(typeObject({ default: -1 }), "number");
      this.assert.equal(typeObject({ type: Array, default: [] }), "array");
      this.assert.equal(typeObject({ type: Array, default: [1] }), "array");
      this.assert.equal(typeObject({ type: Array }), "array");
      this.assert.equal(typeObject({ default: [] }), "array");
      this.assert.equal(typeObject({ default: [1] }), "array");
      this.assert.equal(typeObject({ type: Object, default: {} }), "object");
      this.assert.equal(typeObject({ type: Object, default: { some: "key" } }), "object");
      this.assert.equal(typeObject({ type: Object }), "object");
      this.assert.equal(typeObject({ default: {} }), "object");
      this.assert.equal(typeObject({ default: { some: "key" } }), "object");
      this.assert.equal(typeObject({ type: Boolean, default: true }), "boolean");
      this.assert.equal(typeObject({ type: Boolean, default: false }), "boolean");
      this.assert.equal(typeObject({ type: Boolean }), "boolean");
      this.assert.equal(typeObject({ default: false }), "boolean");
      this.assert.throws(() => typeObject({ type: Boolean, default: "something else" }), {
        name: "Error",
        message: `The specified default value for the Stimulus Value "test.url" must match the defined type "boolean". The provided default value of "something else" is of type "string".`
      });
      this.assert.throws(() => typeObject({ type: Boolean, default: "true" }), {
        name: "Error",
        message: `The specified default value for the Stimulus Value "test.url" must match the defined type "boolean". The provided default value of "true" is of type "string".`
      });
    }
    "test parseValueTypeDefinition booleans"() {
      const typeDefinition = (definition) => {
        return parseValueTypeDefinition({
          controller: this.controller.identifier,
          token: "url",
          typeDefinition: definition
        });
      };
      this.assert.equal(typeDefinition(Boolean), "boolean");
      this.assert.equal(typeDefinition(true), "boolean");
      this.assert.equal(typeDefinition(false), "boolean");
      this.assert.equal(typeDefinition({ type: Boolean, default: false }), "boolean");
      this.assert.equal(typeDefinition({ type: Boolean }), "boolean");
      this.assert.equal(typeDefinition({ default: true }), "boolean");
      this.assert.equal(typeDefinition({ default: null }), "object");
      this.assert.equal(typeDefinition({ default: void 0 }), "object");
      this.assert.equal(typeDefinition({}), "object");
      this.assert.equal(typeDefinition(""), "string");
      this.assert.equal(typeDefinition([]), "array");
      this.assert.throws(() => typeDefinition(null));
      this.assert.throws(() => typeDefinition(void 0));
    }
    "test defaultValueForDefinition"() {
      this.assert.deepEqual(defaultValueForDefinition(String), "");
      this.assert.deepEqual(defaultValueForDefinition(Boolean), false);
      this.assert.deepEqual(defaultValueForDefinition(Object), {});
      this.assert.deepEqual(defaultValueForDefinition(Array), []);
      this.assert.deepEqual(defaultValueForDefinition(Number), 0);
      this.assert.deepEqual(defaultValueForDefinition({ type: String }), "");
      this.assert.deepEqual(defaultValueForDefinition({ type: Boolean }), false);
      this.assert.deepEqual(defaultValueForDefinition({ type: Object }), {});
      this.assert.deepEqual(defaultValueForDefinition({ type: Array }), []);
      this.assert.deepEqual(defaultValueForDefinition({ type: Number }), 0);
      this.assert.deepEqual(defaultValueForDefinition({ type: String, default: null }), null);
      this.assert.deepEqual(defaultValueForDefinition({ type: Boolean, default: null }), null);
      this.assert.deepEqual(defaultValueForDefinition({ type: Object, default: null }), null);
      this.assert.deepEqual(defaultValueForDefinition({ type: Array, default: null }), null);
      this.assert.deepEqual(defaultValueForDefinition({ type: Number, default: null }), null);
      this.assert.deepEqual(defaultValueForDefinition({ type: String, default: "some string" }), "some string");
      this.assert.deepEqual(defaultValueForDefinition({ type: Boolean, default: true }), true);
      this.assert.deepEqual(defaultValueForDefinition({ type: Object, default: { some: "key" } }), { some: "key" });
      this.assert.deepEqual(defaultValueForDefinition({ type: Array, default: [1, 2, 3] }), [1, 2, 3]);
      this.assert.deepEqual(defaultValueForDefinition({ type: Number, default: 99 }), 99);
      this.assert.deepEqual(defaultValueForDefinition("some string"), "some string");
      this.assert.deepEqual(defaultValueForDefinition(true), true);
      this.assert.deepEqual(defaultValueForDefinition({ some: "key" }), { some: "key" });
      this.assert.deepEqual(defaultValueForDefinition([1, 2, 3]), [1, 2, 3]);
      this.assert.deepEqual(defaultValueForDefinition(99), 99);
      this.assert.deepEqual(defaultValueForDefinition({ default: "some string" }), "some string");
      this.assert.deepEqual(defaultValueForDefinition({ default: true }), true);
      this.assert.deepEqual(defaultValueForDefinition({ default: { some: "key" } }), { some: "key" });
      this.assert.deepEqual(defaultValueForDefinition({ default: [1, 2, 3] }), [1, 2, 3]);
      this.assert.deepEqual(defaultValueForDefinition({ default: 99 }), 99);
      this.assert.deepEqual(defaultValueForDefinition({ default: null }), null);
      this.assert.deepEqual(defaultValueForDefinition({ default: void 0 }), void 0);
    }
  };

  // src/tests/modules/core/value_tests.ts
  var ValueTests = class extends ControllerTestCase(ValueController) {
    constructor() {
      super(...arguments);
      this.fixtureHTML = `
    <div data-controller="${this.identifier}"
      data-${this.identifier}-shadowed-boolean-value="true"
      data-${this.identifier}-numeric-value="123"
      data-${this.identifier}-string-value="ok"
      data-${this.identifier}-ids-value="[1,2,3]"
      data-${this.identifier}-options-value='{"one":[2,3]}'
      data-${this.identifier}-time-24hr-value="true">
    </div>
  `;
    }
    "test string values"() {
      this.assert.deepEqual(this.controller.stringValue, "ok");
      this.controller.stringValue = "cool";
      this.assert.deepEqual(this.controller.stringValue, "cool");
      this.assert.deepEqual(this.get("string-value"), "cool");
    }
    "test numeric values"() {
      this.assert.deepEqual(this.controller.numericValue, 123);
      this.controller.numericValue = 456;
      this.assert.deepEqual(this.controller.numericValue, 456);
      this.assert.deepEqual(this.get("numeric-value"), "456");
      this.controller.numericValue = "789";
      this.assert.deepEqual(this.controller.numericValue, 789);
      this.controller.numericValue = 1.23;
      this.assert.deepEqual(this.controller.numericValue, 1.23);
      this.assert.deepEqual(this.get("numeric-value"), "1.23");
      this.controller.numericValue = Infinity;
      this.assert.deepEqual(this.controller.numericValue, Infinity);
      this.assert.deepEqual(this.get("numeric-value"), "Infinity");
      this.controller.numericValue = "garbage";
      this.assert.ok(isNaN(this.controller.numericValue));
      this.assert.equal(this.get("numeric-value"), "garbage");
      this.controller.numericValue = "";
      this.assert.equal(this.controller.numericValue, 0);
      this.assert.equal(this.get("numeric-value"), "");
      this.set("numeric-value", "7_150");
      this.assert.equal(this.controller.numericValue, 7150);
      this.controller.numericValue = 10500;
      this.assert.deepEqual(this.get("numeric-value"), "10500");
    }
    "test boolean values"() {
      this.assert.deepEqual(this.controller.shadowedBooleanValue, true);
      this.controller.shadowedBooleanValue = false;
      this.assert.deepEqual(this.controller.shadowedBooleanValue, false);
      this.assert.deepEqual(this.get("shadowed-boolean-value"), "false");
      this.controller.shadowedBooleanValue = "";
      this.assert.deepEqual(this.controller.shadowedBooleanValue, true);
      this.assert.deepEqual(this.get("shadowed-boolean-value"), "");
      this.controller.shadowedBooleanValue = 0;
      this.assert.deepEqual(this.controller.shadowedBooleanValue, false);
      this.assert.deepEqual(this.get("shadowed-boolean-value"), "0");
      this.controller.shadowedBooleanValue = 1;
      this.assert.deepEqual(this.controller.shadowedBooleanValue, true);
      this.assert.deepEqual(this.get("shadowed-boolean-value"), "1");
      this.controller.shadowedBooleanValue = "False";
      this.assert.deepEqual(this.controller.shadowedBooleanValue, false);
      this.assert.deepEqual(this.get("shadowed-boolean-value"), "False");
    }
    "test array values"() {
      this.assert.deepEqual(this.controller.idsValue, [1, 2, 3]);
      this.controller.idsValue.push(4);
      this.assert.deepEqual(this.controller.idsValue, [1, 2, 3]);
      this.controller.idsValue = [];
      this.assert.deepEqual(this.controller.idsValue, []);
      this.assert.deepEqual(this.get("ids-value"), "[]");
      this.controller.idsValue = null;
      this.assert.throws(() => this.controller.idsValue);
      this.controller.idsValue = {};
      this.assert.throws(() => this.controller.idsValue);
    }
    "test object values"() {
      this.assert.deepEqual(this.controller.optionsValue, { one: [2, 3] });
      this.controller.optionsValue["one"] = 0;
      this.assert.deepEqual(this.controller.optionsValue, { one: [2, 3] });
      this.controller.optionsValue = {};
      this.assert.deepEqual(this.controller.optionsValue, {});
      this.assert.deepEqual(this.get("options-value"), "{}");
      this.controller.optionsValue = null;
      this.assert.throws(() => this.controller.optionsValue);
      this.controller.optionsValue = [];
      this.assert.throws(() => this.controller.optionsValue);
    }
    "test accessing a string value returns the empty string when the attribute is missing"() {
      this.controller.stringValue = void 0;
      this.assert.notOk(this.has("string-value"));
      this.assert.deepEqual(this.controller.stringValue, "");
    }
    "test accessing a numeric value returns zero when the attribute is missing"() {
      this.controller.numericValue = void 0;
      this.assert.notOk(this.has("numeric-value"));
      this.assert.deepEqual(this.controller.numericValue, 0);
    }
    "test accessing a boolean value returns false when the attribute is missing"() {
      this.controller.shadowedBooleanValue = void 0;
      this.assert.notOk(this.has("shadowed-boolean-value"));
      this.assert.deepEqual(this.controller.shadowedBooleanValue, false);
    }
    "test accessing an array value returns an empty array when the attribute is missing"() {
      this.controller.idsValue = void 0;
      this.assert.notOk(this.has("ids-value"));
      this.assert.deepEqual(this.controller.idsValue, []);
      this.controller.idsValue.push(1);
      this.assert.deepEqual(this.controller.idsValue, []);
    }
    "test accessing an object value returns an empty object when the attribute is missing"() {
      this.controller.optionsValue = void 0;
      this.assert.notOk(this.has("options-value"));
      this.assert.deepEqual(this.controller.optionsValue, {});
      this.controller.optionsValue.hello = true;
      this.assert.deepEqual(this.controller.optionsValue, {});
    }
    async "test changed callbacks"() {
      this.assert.deepEqual(this.controller.loggedNumericValues, [123]);
      this.assert.deepEqual(this.controller.oldLoggedNumericValues, [0]);
      this.controller.numericValue = 0;
      await this.nextFrame;
      this.assert.deepEqual(this.controller.loggedNumericValues, [123, 0]);
      this.assert.deepEqual(this.controller.oldLoggedNumericValues, [0, 123]);
      this.set("numeric-value", "1");
      await this.nextFrame;
      this.assert.deepEqual(this.controller.loggedNumericValues, [123, 0, 1]);
      this.assert.deepEqual(this.controller.oldLoggedNumericValues, [0, 123, 0]);
    }
    async "test changed callbacks for object"() {
      this.assert.deepEqual(this.controller.optionsValues, [{ one: [2, 3] }]);
      this.assert.deepEqual(this.controller.oldOptionsValues, [{}]);
      this.controller.optionsValue = { person: { name: "John", age: 42, active: true } };
      await this.nextFrame;
      this.assert.deepEqual(this.controller.optionsValues, [
        { one: [2, 3] },
        { person: { name: "John", age: 42, active: true } }
      ]);
      this.assert.deepEqual(this.controller.oldOptionsValues, [{}, { one: [2, 3] }]);
      this.set("options-value", "{}");
      await this.nextFrame;
      this.assert.deepEqual(this.controller.optionsValues, [
        { one: [2, 3] },
        { person: { name: "John", age: 42, active: true } },
        {}
      ]);
      this.assert.deepEqual(this.controller.oldOptionsValues, [
        {},
        { one: [2, 3] },
        { person: { name: "John", age: 42, active: true } }
      ]);
    }
    async "test default values trigger changed callbacks"() {
      this.assert.deepEqual(this.controller.loggedMissingStringValues, [""]);
      this.assert.deepEqual(this.controller.oldLoggedMissingStringValues, [void 0]);
      this.controller.missingStringValue = "hello";
      await this.nextFrame;
      this.assert.deepEqual(this.controller.loggedMissingStringValues, ["", "hello"]);
      this.assert.deepEqual(this.controller.oldLoggedMissingStringValues, [void 0, ""]);
      this.controller.missingStringValue = void 0;
      await this.nextFrame;
      this.assert.deepEqual(this.controller.loggedMissingStringValues, ["", "hello", ""]);
      this.assert.deepEqual(this.controller.oldLoggedMissingStringValues, [void 0, "", "hello"]);
    }
    "test keys may be specified in kebab-case"() {
      this.assert.equal(this.controller.time24hrValue, true);
    }
    has(name) {
      return this.element.hasAttribute(this.attr(name));
    }
    get(name) {
      return this.element.getAttribute(this.attr(name));
    }
    set(name, value) {
      return this.element.setAttribute(this.attr(name), value);
    }
    attr(name) {
      return `data-${this.identifier}-${name}`;
    }
    get element() {
      return this.controller.element;
    }
  };

  // src/tests/modules/mutation-observers/attribute_observer_tests.ts
  var AttributeObserverTests = class extends ObserverTestCase {
    constructor() {
      super(...arguments);
      this.attributeName = "data-test";
      this.fixtureHTML = `<div id="outer" ${this.attributeName}><div id="inner"></div></div>`;
      this.observer = new AttributeObserver(this.fixtureElement, this.attributeName, this);
    }
    async "test elementMatchedAttribute"() {
      this.assert.deepEqual(this.calls, [["elementMatchedAttribute", this.outerElement, this.attributeName]]);
    }
    async "test elementAttributeValueChanged"() {
      this.outerElement.setAttribute(this.attributeName, "hello");
      await this.nextFrame;
      this.assert.deepEqual(this.calls, [
        ["elementMatchedAttribute", this.outerElement, this.attributeName],
        ["elementAttributeValueChanged", this.outerElement, this.attributeName]
      ]);
    }
    async "test elementUnmatchedAttribute"() {
      this.outerElement.removeAttribute(this.attributeName);
      await this.nextFrame;
      this.assert.deepEqual(this.calls, [
        ["elementMatchedAttribute", this.outerElement, this.attributeName],
        ["elementUnmatchedAttribute", this.outerElement, this.attributeName]
      ]);
    }
    async "test observes attribute changes to child elements"() {
      this.innerElement.setAttribute(this.attributeName, "hello");
      await this.nextFrame;
      this.assert.deepEqual(this.calls, [
        ["elementMatchedAttribute", this.outerElement, this.attributeName],
        ["elementMatchedAttribute", this.innerElement, this.attributeName]
      ]);
    }
    async "test ignores other attributes"() {
      this.outerElement.setAttribute(this.attributeName + "-x", "hello");
      await this.nextFrame;
      this.assert.deepEqual(this.calls, [["elementMatchedAttribute", this.outerElement, this.attributeName]]);
    }
    async "test observes removal of nested matched element HTML"() {
      const { innerElement, outerElement } = this;
      innerElement.setAttribute(this.attributeName, "");
      await this.nextFrame;
      this.fixtureElement.innerHTML = "";
      await this.nextFrame;
      this.assert.deepEqual(this.calls, [
        ["elementMatchedAttribute", outerElement, this.attributeName],
        ["elementMatchedAttribute", innerElement, this.attributeName],
        ["elementUnmatchedAttribute", outerElement, this.attributeName],
        ["elementUnmatchedAttribute", innerElement, this.attributeName]
      ]);
    }
    async "test ignores synchronously disconnected elements"() {
      const { innerElement, outerElement } = this;
      outerElement.removeChild(innerElement);
      innerElement.setAttribute(this.attributeName, "");
      await this.nextFrame;
      this.assert.deepEqual(this.calls, [["elementMatchedAttribute", outerElement, this.attributeName]]);
    }
    async "test ignores synchronously moved elements"() {
      const { innerElement, outerElement } = this;
      document.body.appendChild(innerElement);
      innerElement.setAttribute(this.attributeName, "");
      await this.nextFrame;
      this.assert.deepEqual(this.calls, [["elementMatchedAttribute", outerElement, this.attributeName]]);
      document.body.removeChild(innerElement);
    }
    get outerElement() {
      return this.findElement("#outer");
    }
    get innerElement() {
      return this.findElement("#inner");
    }
    // Attribute observer delegate
    elementMatchedAttribute(element, attributeName) {
      this.recordCall("elementMatchedAttribute", element, attributeName);
    }
    elementAttributeValueChanged(element, attributeName) {
      this.recordCall("elementAttributeValueChanged", element, attributeName);
    }
    elementUnmatchedAttribute(element, attributeName) {
      this.recordCall("elementUnmatchedAttribute", element, attributeName);
    }
  };

  // src/tests/modules/mutation-observers/selector_observer_tests.ts
  var SelectorObserverTests = class extends ObserverTestCase {
    constructor() {
      super(...arguments);
      this.attributeName = "data-test";
      this.selector = "div[data-test~=two]";
      this.details = { some: "details" };
      this.fixtureHTML = `
    <div id="container" ${this.attributeName}="one two">
      <div id="div1" ${this.attributeName}="one"></div>
      <div id="div2" ${this.attributeName}="two"></div>
      <span id="span1" ${this.attributeName}="one"></span>
      <span id="span2" ${this.attributeName}="two"></span>
    </div>
  `;
      this.observer = new SelectorObserver(this.fixtureElement, this.selector, this, this.details);
    }
    async "test should match when observer starts"() {
      this.assert.deepEqual(this.calls, [
        ["selectorMatched", this.element, this.selector, this.details],
        ["selectorMatched", this.div2, this.selector, this.details]
      ]);
    }
    async "test should match when element gets appended"() {
      const element1 = document.createElement("div");
      const element2 = document.createElement("div");
      element1.dataset.test = "one two";
      element2.dataset.test = "three four";
      this.element.appendChild(element1);
      this.element.appendChild(element2);
      await this.nextFrame;
      this.assert.deepEqual(this.calls, [
        ["selectorMatched", this.element, this.selector, this.details],
        ["selectorMatched", this.div2, this.selector, this.details],
        ["selectorMatched", element1, this.selector, this.details]
      ]);
    }
    async "test should not match/unmatch when the attribute gets updated and matching selector persists"() {
      this.element.setAttribute(this.attributeName, "two three");
      await this.nextFrame;
      this.assert.deepEqual(this.testCalls, []);
    }
    async "test should match when attribute gets updated and start to matche selector"() {
      this.div1.setAttribute(this.attributeName, "updated two");
      await this.nextFrame;
      this.assert.deepEqual(this.testCalls, [["selectorMatched", this.div1, this.selector, this.details]]);
    }
    async "test should unmatch when attribute gets updated but matching attribute value gets removed"() {
      this.div2.setAttribute(this.attributeName, "updated");
      await this.nextFrame;
      this.assert.deepEqual(this.testCalls, [["selectorUnmatched", this.div2, this.selector, this.details]]);
    }
    async "test should unmatch when attribute gets removed"() {
      this.element.removeAttribute(this.attributeName);
      this.div2.removeAttribute(this.attributeName);
      await this.nextFrame;
      this.assert.deepEqual(this.testCalls, [
        ["selectorUnmatched", this.element, this.selector, this.details],
        ["selectorUnmatched", this.div2, this.selector, this.details]
      ]);
    }
    async "test should unmatch when element gets removed"() {
      const element = this.element;
      const div1 = this.div1;
      const div2 = this.div2;
      element.remove();
      div1.remove();
      div2.remove();
      await this.nextFrame;
      this.assert.deepEqual(this.testCalls, [
        ["selectorUnmatched", element, this.selector, this.details],
        ["selectorUnmatched", div2, this.selector, this.details]
      ]);
    }
    async "test should not match/unmatch when observer is paused"() {
      this.observer.pause(() => {
        this.div2.remove();
        const element = document.createElement("div");
        element.dataset.test = "one two";
        this.element.appendChild(element);
      });
      await this.nextFrame;
      this.assert.deepEqual(this.testCalls, []);
    }
    get element() {
      return this.findElement("#container");
    }
    get div1() {
      return this.findElement("#div1");
    }
    get div2() {
      return this.findElement("#div2");
    }
    // Selector observer delegate
    selectorMatched(element, selector, details) {
      this.recordCall("selectorMatched", element, selector, details);
    }
    selectorUnmatched(element, selector, details) {
      this.recordCall("selectorUnmatched", element, selector, details);
    }
  };

  // src/tests/modules/mutation-observers/token_list_observer_tests.ts
  var TokenListObserverTests = class extends ObserverTestCase {
    constructor() {
      super(...arguments);
      this.attributeName = "data-test";
      this.fixtureHTML = `<div ${this.attributeName}="one two"></div>`;
      this.observer = new TokenListObserver(this.fixtureElement, this.attributeName, this);
    }
    async "test tokenMatched"() {
      this.assert.deepEqual(this.calls, [
        ["tokenMatched", this.element, this.attributeName, "one", 0],
        ["tokenMatched", this.element, this.attributeName, "two", 1]
      ]);
    }
    async "test adding a token to the right"() {
      this.tokenString = "one two three";
      await this.nextFrame;
      this.assert.deepEqual(this.testCalls, [["tokenMatched", this.element, this.attributeName, "three", 2]]);
    }
    async "test inserting a token in the middle"() {
      this.tokenString = "one three two";
      await this.nextFrame;
      this.assert.deepEqual(this.testCalls, [
        ["tokenUnmatched", this.element, this.attributeName, "two", 1],
        ["tokenMatched", this.element, this.attributeName, "three", 1],
        ["tokenMatched", this.element, this.attributeName, "two", 2]
      ]);
    }
    async "test removing the leftmost token"() {
      this.tokenString = "two";
      await this.nextFrame;
      this.assert.deepEqual(this.testCalls, [
        ["tokenUnmatched", this.element, this.attributeName, "one", 0],
        ["tokenUnmatched", this.element, this.attributeName, "two", 1],
        ["tokenMatched", this.element, this.attributeName, "two", 0]
      ]);
    }
    async "test removing the rightmost token"() {
      this.tokenString = "one";
      await this.nextFrame;
      this.assert.deepEqual(this.testCalls, [["tokenUnmatched", this.element, this.attributeName, "two", 1]]);
    }
    async "test removing the only token"() {
      this.tokenString = "one";
      await this.nextFrame;
      this.tokenString = "";
      await this.nextFrame;
      this.assert.deepEqual(this.testCalls, [
        ["tokenUnmatched", this.element, this.attributeName, "two", 1],
        ["tokenUnmatched", this.element, this.attributeName, "one", 0]
      ]);
    }
    get element() {
      return this.findElement("div");
    }
    set tokenString(value) {
      this.element.setAttribute(this.attributeName, value);
    }
    // Token observer delegate
    tokenMatched(token) {
      this.recordCall("tokenMatched", token.element, token.attributeName, token.content, token.index);
    }
    tokenUnmatched(token) {
      this.recordCall("tokenUnmatched", token.element, token.attributeName, token.content, token.index);
    }
  };

  // src/tests/modules/mutation-observers/value_list_observer_tests.ts
  var ValueListObserverTests = class extends ObserverTestCase {
    constructor() {
      super(...arguments);
      this.attributeName = "data-test";
      this.fixtureHTML = `<div ${this.attributeName}="one"></div>`;
      this.observer = new ValueListObserver(this.fixtureElement, this.attributeName, this);
      this.lastValueId = 0;
    }
    async "test elementMatchedValue"() {
      this.assert.deepEqual(this.calls, [["elementMatchedValue", this.element, 1, "one"]]);
    }
    async "test adding a token to the right"() {
      this.valueString = "one two";
      await this.nextFrame;
      this.assert.deepEqual(this.testCalls, [["elementMatchedValue", this.element, 2, "two"]]);
    }
    async "test adding a token to the left"() {
      this.valueString = "two one";
      await this.nextFrame;
      this.assert.deepEqual(this.testCalls, [
        ["elementUnmatchedValue", this.element, 1, "one"],
        ["elementMatchedValue", this.element, 2, "two"],
        ["elementMatchedValue", this.element, 3, "one"]
      ]);
    }
    async "test removing a token from the right"() {
      this.valueString = "one two";
      await this.nextFrame;
      this.valueString = "one";
      await this.nextFrame;
      this.assert.deepEqual(this.testCalls, [
        ["elementMatchedValue", this.element, 2, "two"],
        ["elementUnmatchedValue", this.element, 2, "two"]
      ]);
    }
    async "test removing a token from the left"() {
      this.valueString = "one two";
      await this.nextFrame;
      this.valueString = "two";
      await this.nextFrame;
      this.assert.deepEqual(this.testCalls, [
        ["elementMatchedValue", this.element, 2, "two"],
        ["elementUnmatchedValue", this.element, 1, "one"],
        ["elementUnmatchedValue", this.element, 2, "two"],
        ["elementMatchedValue", this.element, 3, "two"]
      ]);
    }
    async "test removing the only token"() {
      this.valueString = "";
      await this.nextFrame;
      this.assert.deepEqual(this.testCalls, [["elementUnmatchedValue", this.element, 1, "one"]]);
    }
    async "test removing and re-adding a token produces a new value"() {
      this.valueString = "";
      await this.nextFrame;
      this.valueString = "one";
      await this.nextFrame;
      this.assert.deepEqual(this.testCalls, [
        ["elementUnmatchedValue", this.element, 1, "one"],
        ["elementMatchedValue", this.element, 2, "one"]
      ]);
    }
    get element() {
      return this.findElement("div");
    }
    set valueString(value) {
      this.element.setAttribute(this.attributeName, value);
    }
    // Value observer delegate
    parseValueForToken(token) {
      return { id: ++this.lastValueId, token };
    }
    elementMatchedValue(element, value) {
      this.recordCall("elementMatchedValue", element, value.id, value.token.content);
    }
    elementUnmatchedValue(element, value) {
      this.recordCall("elementUnmatchedValue", element, value.id, value.token.content);
    }
  };

  // src/tests/conformance.entry.ts
  var MODULES = [ActionClickFilterTests, ActionKeyboardFilterTests, ActionOrderingTests, ActionParamsCaseInsensitiveTests, ActionParamsTests, ActionTests, ActionTimingTests, ApplicationStartTests, ApplicationTests, ClassTests, DataTests, DefaultValueTests, ErrorHandlerTests, ES6Tests, EventOptionsTests, ExtendingApplicationTests, LegacyTargetTests, LifecycleTests, ApplicationTests2, MemoryTests, OutletOrderTests, OutletTests, StringHelpersTests, TargetTests, ValuePropertiesTests, ValueTests, AttributeObserverTests, SelectorObserverTests, TokenListObserverTests, ValueListObserverTests];
  MODULES.forEach((c) => c.defineModule());
})();
