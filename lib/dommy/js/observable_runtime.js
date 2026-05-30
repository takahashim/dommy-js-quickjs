// Observable / Subscriber polyfill (WICG Observable) + EventTarget.prototype.when.
//
// QuickJS is a real JS engine, so the reactive primitive is implemented in JS
// and evaluated into the VM after the DOM interface prototypes are seeded (so
// `EventTarget.prototype` exists). The only host integration points are
// EventTarget (addEventListener/removeEventListener), AbortController/AbortSignal,
// and reporting an unhandled exception to the global error handler.
(function () {
  "use strict";
  if (typeof globalThis.Observable === "function") return;

  const kInternal = Symbol("observable-internal");

  // "Report the exception" — dispatch an `error` ErrorEvent on the global so
  // `self.addEventListener("error", …)` sees unhandled Observable errors.
  function reportException(error) {
    // A thrown value with no stack (e.g. a string) reports lineno/colno 0;
    // a real Error carries a stack we parse for a positive position.
    let lineno = 0, colno = 0, filename = "";
    const stack = error && typeof error === "object" ? error.stack : undefined;
    if (typeof stack === "string") {
      const m = stack.match(/\(?([^()\s]*):(\d+):(\d+)\)?/);
      if (m) {
        filename = m[1] || "";
        lineno = parseInt(m[2], 10) || 0;
        colno = parseInt(m[3], 10) || 0;
      }
    }
    const message = (error && typeof error === "object" && "message" in error)
      ? String(error.message) : String(error);
    const g = globalThis.window || globalThis;
    let event;
    try {
      if (typeof globalThis.ErrorEvent === "function") {
        event = new ErrorEvent("error", { error, message, lineno, colno, filename, cancelable: true });
      } else {
        event = new Event("error", { cancelable: true });
        event.error = error;
        event.message = message;
        event.lineno = lineno;
        event.colno = colno;
        event.filename = filename;
      }
      if (g && typeof g.dispatchEvent === "function") g.dispatchEvent(event);
    } catch (_e) {
      // Best effort: swallow — reporting must never throw into the caller.
    }
  }

  function isCallable(v) { return typeof v === "function"; }

  // take()/drop() counts are WebIDL `unsigned long long`: a negative value
  // wraps to the maximum (effectively unlimited), as does a non-finite value.
  function toUnsignedCount(amount) {
    const n = Math.trunc(Number(amount));
    if (!isFinite(n) || n < 0) return Infinity;
    return n;
  }

  // TC39 GetMethod(value, key): undefined for an absent (null/undefined)
  // property, the function if callable, and a TypeError if present but not
  // callable. The property read may itself throw (a getter) — that propagates.
  function getMethod(value, key) {
    const method = value[key];
    if (method === undefined || method === null) return undefined;
    if (!isCallable(method)) throw new TypeError(String(key) + " is not a function");
    return method;
  }

  // The Subscriber handed to an Observable's initializer. Not constructible from
  // script. Uses #private fields so a detached `next`/`error`/`complete`
  // (called with no receiver) throws TypeError — matching the WebIDL receiver
  // check the spec mandates.
  class Subscriber {
    #token;
    #ac;
    #signal;
    #next;
    #error;
    #complete;
    #teardowns = [];
    #closed = false;

    constructor(token, observer) {
      if (token !== kInternal) throw new TypeError("Illegal constructor");
      this.#token = token;
      this.#ac = new AbortController();
      this.#signal = this.#ac.signal;
      this.#next = isCallable(observer && observer.next) ? observer.next : null;
      this.#error = isCallable(observer && observer.error) ? observer.error : null;
      this.#complete = isCallable(observer && observer.complete) ? observer.complete : null;
    }

    get active() { return !this.#signal.aborted; }
    get signal() { return this.#signal; }

    next(value) {
      // Touch a private field first so a receiver-less call throws TypeError.
      void this.#token;
      if (arguments.length < 1) throw new TypeError("Subscriber.next requires 1 argument");
      if (this.#signal.aborted) return;
      if (this.#next) {
        try { this.#next.call(undefined, value); }
        catch (e) { reportException(e); }
      }
    }

    error(err) {
      void this.#token;
      if (arguments.length < 1) throw new TypeError("Subscriber.error requires 1 argument");
      if (this.#signal.aborted) { reportException(err); return; }
      const cb = this.#error;
      this.#close(err);
      if (cb) {
        try { cb.call(undefined, err); }
        catch (e) { reportException(e); }
      } else {
        reportException(err);
      }
    }

    complete() {
      void this.#token;
      if (this.#signal.aborted) return;
      const cb = this.#complete;
      this.#close(undefined);
      if (cb) {
        try { cb.call(undefined); }
        catch (e) { reportException(e); }
      }
    }

    addTeardown(teardown) {
      void this.#token;
      if (!isCallable(teardown)) return;
      if (this.#signal.aborted) {
        try { teardown.call(undefined); } catch (e) { reportException(e); }
      } else {
        this.#teardowns.push(teardown);
      }
    }

    // Abort the subscriber's signal (reason for error()), then run teardowns
    // LIFO. After this, active is false and the signal is aborted — before any
    // observer complete()/error() callback is invoked.
    #close(reason) {
      if (this.#closed) return;
      this.#closed = true;
      try { this.#ac.abort(reason); } catch (_e) {}
      const teardowns = this.#teardowns;
      this.#teardowns = [];
      for (let i = teardowns.length - 1; i >= 0; i--) {
        try { teardowns[i].call(undefined); } catch (e) { reportException(e); }
      }
    }

    // Internal: abort because the consumer's signal aborted (unsubscribe).
    _abortConsumer(reason) { this.#close(reason); }
  }

  Object.defineProperty(Subscriber.prototype, Symbol.toStringTag, {
    value: "Subscriber", configurable: true,
  });

  function normalizeObserver(observer) {
    if (isCallable(observer)) return { next: observer };
    if (observer && typeof observer === "object") return observer;
    return {};
  }

  class Observable {
    #subscribeCallback;

    constructor(subscribeCallback) {
      if (!isCallable(subscribeCallback)) {
        throw new TypeError("Observable constructor requires a callback function");
      }
      this.#subscribeCallback = subscribeCallback;
    }

    // Public subscribe(). observer may be a next-callback, an observer object,
    // or omitted. options may carry an AbortSignal.
    subscribe(observer, options) {
      this._subscribeWith(normalizeObserver(observer), options || {});
    }

    // Internal subscribe used by subscribe() and by operators. internalObserver
    // is a plain {next?, error?, complete?}.
    _subscribeWith(internalObserver, options) {
      const subscriber = new Subscriber(kInternal, internalObserver);
      const outer = options && options.signal;
      if (outer) {
        if (outer.aborted) {
          subscriber._abortConsumer(outer.reason);
        } else {
          outer.addEventListener("abort", () => subscriber._abortConsumer(outer.reason),
            { once: true });
        }
      }
      try {
        this.#subscribeCallback.call(undefined, subscriber);
      } catch (e) {
        subscriber.error(e);
      }
      return subscriber;
    }

    static from(value) {
      if (value instanceof Observable) return value;
      if (value === null || (typeof value !== "object" && typeof value !== "function")) {
        throw new TypeError("Observable.from: value is not convertible to an Observable");
      }

      // Commit to a conversion by probing the protocol method (TC39 GetMethod:
      // a present-but-not-callable @@asyncIterator/@@iterator is a TypeError,
      // not a silent fall-through to the next branch). The method is re-read at
      // subscribe time too — it is never cached.
      if (getMethod(value, Symbol.asyncIterator) !== undefined) {
        return new Observable((subscriber) => {
          const method = getMethod(value, Symbol.asyncIterator);
          if (method === undefined) { subscriber.error(new TypeError("@@asyncIterator was removed")); return; }
          let iterator;
          try { iterator = method.call(value); }
          catch (e) { subscriber.error(e); return; }
          subscriber.addTeardown(() => {
            if (iterator && isCallable(iterator.return)) {
              try { Promise.resolve(iterator.return()).then(undefined, () => {}); } catch (_e) {}
            }
          });
          const pump = () => {
            if (subscriber.signal.aborted) return;
            let p;
            try { p = iterator.next(); }
            catch (e) { subscriber.error(e); return; }
            Promise.resolve(p).then(
              (result) => {
                if (subscriber.signal.aborted) return;
                if (result === null || typeof result !== "object") {
                  subscriber.error(new TypeError("Iterator result is not an object"));
                  return;
                }
                if (result.done) { subscriber.complete(); return; }
                subscriber.next(result.value);
                pump();
              },
              (e) => subscriber.error(e),
            );
          };
          pump();
        });
      }

      if (getMethod(value, Symbol.iterator) !== undefined) {
        return new Observable((subscriber) => {
          let method;
          try { method = getMethod(value, Symbol.iterator); }
          catch (e) { subscriber.error(e); return; }
          if (method === undefined) { subscriber.error(new TypeError("@@iterator was removed")); return; }
          let iterator;
          try { iterator = method.call(value); }
          catch (e) { subscriber.error(e); return; }
          subscriber.addTeardown(() => {
            if (iterator && isCallable(iterator.return)) {
              try { iterator.return(); } catch (_e) {}
            }
          });
          while (true) {
            if (subscriber.signal.aborted) return;
            let result;
            try { result = iterator.next(); }
            catch (e) { subscriber.error(e); return; }
            if (result === null || typeof result !== "object") {
              subscriber.error(new TypeError("Iterator result is not an object"));
              return;
            }
            if (result.done) { subscriber.complete(); return; }
            subscriber.next(result.value);
          }
        });
      }

      if (isCallable(value.then)) {
        return new Observable((subscriber) => {
          Promise.resolve(value).then(
            (v) => { subscriber.next(v); subscriber.complete(); },
            (e) => subscriber.error(e),
          );
        });
      }

      throw new TypeError("Observable.from: value is not convertible to an Observable");
    }

    // ---- transform operators (return an Observable) ----

    map(mapper) {
      if (!isCallable(mapper)) throw new TypeError("map: mapper must be a function");
      const source = this;
      return new Observable((subscriber) => {
        let index = 0;
        source._subscribeWith({
          next: (value) => {
            let mapped;
            try { mapped = mapper(value, index++); }
            catch (e) { subscriber.error(e); return; }
            subscriber.next(mapped);
          },
          error: (e) => subscriber.error(e),
          complete: () => subscriber.complete(),
        }, { signal: subscriber.signal });
      });
    }

    filter(predicate) {
      if (!isCallable(predicate)) throw new TypeError("filter: predicate must be a function");
      const source = this;
      return new Observable((subscriber) => {
        let index = 0;
        source._subscribeWith({
          next: (value) => {
            let keep;
            try { keep = predicate(value, index++); }
            catch (e) { subscriber.error(e); return; }
            if (keep) subscriber.next(value);
          },
          error: (e) => subscriber.error(e),
          complete: () => subscriber.complete(),
        }, { signal: subscriber.signal });
      });
    }

    take(amount) {
      amount = toUnsignedCount(amount);
      const source = this;
      return new Observable((subscriber) => {
        if (amount === 0) { subscriber.complete(); return; }
        let remaining = amount;
        source._subscribeWith({
          next: (value) => {
            subscriber.next(value);
            if (--remaining === 0) subscriber.complete();
          },
          error: (e) => subscriber.error(e),
          complete: () => subscriber.complete(),
        }, { signal: subscriber.signal });
      });
    }

    drop(amount) {
      amount = toUnsignedCount(amount);
      const source = this;
      return new Observable((subscriber) => {
        let remaining = amount;
        source._subscribeWith({
          next: (value) => {
            if (remaining > 0) { remaining--; return; }
            subscriber.next(value);
          },
          error: (e) => subscriber.error(e),
          complete: () => subscriber.complete(),
        }, { signal: subscriber.signal });
      });
    }

    flatMap(mapper) {
      if (!isCallable(mapper)) throw new TypeError("flatMap: mapper must be a function");
      const source = this;
      return new Observable((subscriber) => {
        let index = 0;
        let outerComplete = false;
        let active = 0;
        const queue = [];
        let subscribing = false;

        const subscribeToInner = (value) => {
          active++;
          let inner;
          try { inner = Observable.from(mapper(value, index++)); }
          catch (e) { subscriber.error(e); return; }
          inner._subscribeWith({
            next: (v) => subscriber.next(v),
            error: (e) => subscriber.error(e),
            complete: () => {
              active--;
              if (queue.length > 0) {
                subscribeToInner(queue.shift());
              } else if (outerComplete && active === 0) {
                subscriber.complete();
              }
            },
          }, { signal: subscriber.signal });
        };

        source._subscribeWith({
          next: (value) => {
            if (active > 0) queue.push(value);
            else subscribeToInner(value);
          },
          error: (e) => subscriber.error(e),
          complete: () => {
            outerComplete = true;
            if (active === 0 && queue.length === 0) subscriber.complete();
          },
        }, { signal: subscriber.signal });
      });
    }

    switchMap(mapper) {
      if (!isCallable(mapper)) throw new TypeError("switchMap: mapper must be a function");
      const source = this;
      return new Observable((subscriber) => {
        let index = 0;
        let outerComplete = false;
        let innerController = null;
        let innerActive = false;

        const startInner = (value) => {
          if (innerController) innerController.abort();
          innerController = new AbortController();
          innerActive = true;
          let inner;
          try { inner = Observable.from(mapper(value, index++)); }
          catch (e) { subscriber.error(e); return; }
          inner._subscribeWith({
            next: (v) => subscriber.next(v),
            error: (e) => subscriber.error(e),
            complete: () => {
              innerActive = false;
              if (outerComplete) subscriber.complete();
            },
          }, { signal: AbortSignal.any([subscriber.signal, innerController.signal]) });
        };

        source._subscribeWith({
          next: (value) => startInner(value),
          error: (e) => subscriber.error(e),
          complete: () => {
            outerComplete = true;
            if (!innerActive) subscriber.complete();
          },
        }, { signal: subscriber.signal });
      });
    }

    takeUntil(notifier) {
      const source = this;
      return new Observable((subscriber) => {
        const notifierObs = Observable.from(notifier);
        // The notifier's first next() OR error() completes the subscriber (the
        // error is NOT mirrored); the notifier completing is a no-op.
        notifierObs._subscribeWith({
          next: () => subscriber.complete(),
          error: () => subscriber.complete(),
          complete: () => {},
        }, { signal: subscriber.signal });
        if (subscriber.signal.aborted) return;
        source._subscribeWith({
          next: (v) => subscriber.next(v),
          error: (e) => subscriber.error(e),
          complete: () => subscriber.complete(),
        }, { signal: subscriber.signal });
      });
    }

    catch(handler) {
      if (!isCallable(handler)) throw new TypeError("catch: handler must be a function");
      const source = this;
      return new Observable((subscriber) => {
        source._subscribeWith({
          next: (v) => subscriber.next(v),
          error: (err) => {
            let next;
            try { next = Observable.from(handler(err)); }
            catch (e) { subscriber.error(e); return; }
            next._subscribeWith({
              next: (v) => subscriber.next(v),
              error: (e) => subscriber.error(e),
              complete: () => subscriber.complete(),
            }, { signal: subscriber.signal });
          },
          complete: () => subscriber.complete(),
        }, { signal: subscriber.signal });
      });
    }

    finally(callback) {
      if (!isCallable(callback)) throw new TypeError("finally: callback must be a function");
      const source = this;
      return new Observable((subscriber) => {
        subscriber.addTeardown(() => callback());
        source._subscribeWith({
          next: (v) => subscriber.next(v),
          error: (e) => subscriber.error(e),
          complete: () => subscriber.complete(),
        }, { signal: subscriber.signal });
      });
    }

    inspect(inspector) {
      const source = this;
      const cfg = isCallable(inspector) ? { next: inspector } : (inspector || {});
      return new Observable((subscriber) => {
        try { if (isCallable(cfg.subscribe)) cfg.subscribe(); }
        catch (e) { subscriber.error(e); return; }
        if (isCallable(cfg.abort)) {
          subscriber.signal.addEventListener("abort", () => {
            try { cfg.abort(subscriber.signal.reason); } catch (_e) {}
          }, { once: true });
        }
        source._subscribeWith({
          next: (v) => {
            try { if (isCallable(cfg.next)) cfg.next(v); }
            catch (e) { subscriber.error(e); return; }
            subscriber.next(v);
          },
          error: (e) => {
            try { if (isCallable(cfg.error)) cfg.error(e); } catch (_e) {}
            subscriber.error(e);
          },
          complete: () => {
            try { if (isCallable(cfg.complete)) cfg.complete(); }
            catch (e) { subscriber.error(e); return; }
            subscriber.complete();
          },
        }, { signal: subscriber.signal });
      });
    }

    // ---- promise-returning operators ----

    toArray(options) {
      const source = this;
      return new Promise((resolve, reject) => {
        const controller = new AbortController();
        const signal = consumerSignal(options, controller);
        if (signal.aborted) { reject(signal.reason); return; }
        signal.addEventListener("abort", () => reject(signal.reason), { once: true });
        const values = [];
        source._subscribeWith({
          next: (v) => values.push(v),
          error: (e) => reject(e),
          complete: () => resolve(values),
        }, { signal });
      });
    }

    forEach(callback, options) {
      const source = this;
      return new Promise((resolve, reject) => {
        if (!isCallable(callback)) { reject(new TypeError("forEach: callback must be a function")); return; }
        const controller = new AbortController();
        const signal = consumerSignal(options, controller);
        if (signal.aborted) { reject(signal.reason); return; }
        // Per spec the returned promise rejects when the (consumer) signal is
        // aborted; the reject is queued before the subscriber's own teardown
        // abort fires, giving the documented microtask ordering.
        signal.addEventListener("abort", () => reject(signal.reason), { once: true });
        let index = 0;
        source._subscribeWith({
          next: (v) => {
            try { callback(v, index++); }
            catch (e) { reject(e); controller.abort(e); }
          },
          error: (e) => reject(e),
          complete: () => resolve(undefined),
        }, { signal });
      });
    }

    first(options) {
      const source = this;
      return new Promise((resolve, reject) => {
        const controller = new AbortController();
        const signal = consumerSignal(options, controller);
        if (signal.aborted) { reject(signal.reason); return; }
        signal.addEventListener("abort", () => reject(signal.reason), { once: true });
        source._subscribeWith({
          next: (v) => { resolve(v); controller.abort(); },
          error: (e) => reject(e),
          complete: () => reject(new RangeError("first(): source completed without emitting a value")),
        }, { signal });
      });
    }

    last(options) {
      const source = this;
      return new Promise((resolve, reject) => {
        const controller = new AbortController();
        const signal = consumerSignal(options, controller);
        if (signal.aborted) { reject(signal.reason); return; }
        signal.addEventListener("abort", () => reject(signal.reason), { once: true });
        let has = false; let lastValue;
        source._subscribeWith({
          next: (v) => { has = true; lastValue = v; },
          error: (e) => reject(e),
          complete: () => {
            if (has) resolve(lastValue);
            else reject(new RangeError("last(): source completed without emitting a value"));
          },
        }, { signal });
      });
    }

    find(predicate, options) {
      const source = this;
      return new Promise((resolve, reject) => {
        if (!isCallable(predicate)) { reject(new TypeError("find: predicate must be a function")); return; }
        const controller = new AbortController();
        const signal = consumerSignal(options, controller);
        if (signal.aborted) { reject(signal.reason); return; }
        signal.addEventListener("abort", () => reject(signal.reason), { once: true });
        let index = 0;
        source._subscribeWith({
          next: (v) => {
            let matched;
            try { matched = predicate(v, index++); }
            catch (e) { reject(e); controller.abort(); return; }
            if (matched) { resolve(v); controller.abort(); }
          },
          error: (e) => reject(e),
          complete: () => resolve(undefined),
        }, { signal });
      });
    }

    some(predicate, options) {
      const source = this;
      return new Promise((resolve, reject) => {
        if (!isCallable(predicate)) { reject(new TypeError("some: predicate must be a function")); return; }
        const controller = new AbortController();
        const signal = consumerSignal(options, controller);
        if (signal.aborted) { reject(signal.reason); return; }
        signal.addEventListener("abort", () => reject(signal.reason), { once: true });
        let index = 0;
        source._subscribeWith({
          next: (v) => {
            let matched;
            try { matched = predicate(v, index++); }
            catch (e) { reject(e); controller.abort(); return; }
            if (matched) { resolve(true); controller.abort(); }
          },
          error: (e) => reject(e),
          complete: () => resolve(false),
        }, { signal });
      });
    }

    every(predicate, options) {
      const source = this;
      return new Promise((resolve, reject) => {
        if (!isCallable(predicate)) { reject(new TypeError("every: predicate must be a function")); return; }
        const controller = new AbortController();
        const signal = consumerSignal(options, controller);
        if (signal.aborted) { reject(signal.reason); return; }
        signal.addEventListener("abort", () => reject(signal.reason), { once: true });
        let index = 0;
        source._subscribeWith({
          next: (v) => {
            let matched;
            try { matched = predicate(v, index++); }
            catch (e) { reject(e); controller.abort(); return; }
            if (!matched) { resolve(false); controller.abort(); }
          },
          error: (e) => reject(e),
          complete: () => resolve(true),
        }, { signal });
      });
    }

    reduce(reducer, initialValue) {
      const source = this;
      const hasInitial = arguments.length >= 2;
      // The options bag is not part of reduce(reducer, initialValue); signal
      // support is omitted to keep the 2-arg contract.
      return new Promise((resolve, reject) => {
        if (!isCallable(reducer)) { reject(new TypeError("reduce: reducer must be a function")); return; }
        let acc = initialValue;
        let hasAcc = hasInitial;
        let index = 0;
        source._subscribeWith({
          next: (v) => {
            if (!hasAcc) { acc = v; hasAcc = true; index++; return; }
            try { acc = reducer(acc, v, index++); }
            catch (e) { reject(e); }
          },
          error: (e) => reject(e),
          complete: () => {
            if (!hasAcc) reject(new TypeError("reduce: no values and no initial value"));
            else resolve(acc);
          },
        }, {});
      });
    }
  }

  // The signal a promise-returning operator subscribes with: a fresh controller
  // (so the operator can unsubscribe on resolve) merged with the caller's signal.
  function consumerSignal(options, controller) {
    const outer = options && options.signal;
    return outer ? AbortSignal.any([outer, controller.signal]) : controller.signal;
  }

  Object.defineProperty(Observable.prototype, Symbol.toStringTag, {
    value: "Observable", configurable: true,
  });

  globalThis.Observable = Observable;
  globalThis.Subscriber = Subscriber;

  // EventTarget.prototype.when(type, options) → Observable of events.
  if (typeof globalThis.EventTarget === "function") {
    Object.defineProperty(EventTarget.prototype, "when", {
      configurable: true, writable: true,
      value: function when(type, options) {
        const target = this;
        const opts = options || {};
        return new Observable((subscriber) => {
          const handler = (event) => subscriber.next(event);
          target.addEventListener(type, handler, {
            signal: subscriber.signal,
            capture: !!opts.capture,
            passive: opts.passive,
          });
        });
      },
    });
  }
})();
