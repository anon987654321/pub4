(function(global, factory) {
  typeof exports === "object" && typeof module !== "undefined" ? factory(exports, require("@hotwired/stimulus"), require("cable_ready"), require("@rails/actioncable")) : typeof define === "function" && define.amd ? define([ "exports", "@hotwired/stimulus", "cable_ready", "@rails/actioncable" ], factory) : (global = typeof globalThis !== "undefined" ? globalThis : global || self, 
  factory(global.StimulusReflex = {}, global.Stimulus, global.CableReady, global.ActionCable));
})(this, (function(exports, stimulus, CableReady, actioncable) {
  "use strict";
  /*!
   * Toastify js 1.12.0
   * https://github.com/apvarun/toastify-js
   * @license MIT licensed
   *
   * Copyright (C) 2018 Varun A P
   */  class Toastify {
    defaults={
      oldestFirst: true,
      text: "Toastify is awesome!",
      node: undefined,
      duration: 3e3,
      selector: undefined,
      callback: function() {},
      destination: undefined,
      newWindow: false,
      close: false,
      gravity: "toastify-top",
      positionLeft: false,
      position: "",
      backgroundColor: "",
      avatar: "",
      className: "",
      stopOnFocus: true,
      onClick: function() {},
      offset: {
        x: 0,
        y: 0
      },
      escapeMarkup: true,
      ariaLive: "polite",
      style: {
        background: ""
      }
    };
    constructor(options) {
      this.version = "1.12.0";
      this.options = {};
      this.toastElement = null;
      this._rootElement = document.body;
      this._init(options);
    }
    showToast() {
      this.toastElement = this._buildToast();
      if (typeof this.options.selector === "string") {
        this._rootElement = document.getElementById(this.options.selector);
      } else if (this.options.selector instanceof HTMLElement || this.options.selector instanceof ShadowRoot) {
        this._rootElement = this.options.selector;
      } else {
        this._rootElement = document.body;
      }
      if (!this._rootElement) {
        throw "Root element is not defined";
      }
      this._rootElement.insertBefore(this.toastElement, this._rootElement.firstChild);
      this._reposition();
      if (this.options.duration > 0) {
        this.toastElement.timeOutValue = window.setTimeout((() => {
          this._removeElement(this.toastElement);
        }), this.options.duration);
      }
      return this;
    }
    hideToast() {
      if (this.toastElement.timeOutValue) {
        clearTimeout(this.toastElement.timeOutValue);
      }
      this._removeElement(this.toastElement);
    }
    _init(options) {
      this.options = Object.assign(this.defaults, options);
      if (this.options.backgroundColor) {
        console.warn('DEPRECATION NOTICE: "backgroundColor" is being deprecated. Please use the "style.background" property.');
      }
      this.toastElement = null;
      this.options.gravity = options.gravity === "bottom" ? "toastify-bottom" : "toastify-top";
      this.options.stopOnFocus = options.stopOnFocus === undefined ? true : options.stopOnFocus;
      if (options.backgroundColor) {
        this.options.style.background = options.backgroundColor;
      }
    }
    _buildToast() {
      if (!this.options) {
        throw "Toastify is not initialized";
      }
      let divElement = document.createElement("div");
      divElement.className = `toastify on ${this.options.className}`;
      divElement.className += ` toastify-${this.options.position}`;
      divElement.className += ` ${this.options.gravity}`;
      for (const property in this.options.style) {
        divElement.style[property] = this.options.style[property];
      }
      if (this.options.ariaLive) {
        divElement.setAttribute("aria-live", this.options.ariaLive);
      }
      if (this.options.node && this.options.node.nodeType === Node.ELEMENT_NODE) {
        divElement.appendChild(this.options.node);
      } else {
        if (this.options.escapeMarkup) {
          divElement.innerText = this.options.text;
        } else {
          divElement.innerHTML = this.options.text;
        }
        if (this.options.avatar !== "") {
          let avatarElement = document.createElement("img");
          avatarElement.src = this.options.avatar;
          avatarElement.className = "toastify-avatar";
          if (this.options.position == "left") {
            divElement.appendChild(avatarElement);
          } else {
            divElement.insertAdjacentElement("afterbegin", avatarElement);
          }
        }
      }
      if (this.options.close === true) {
        let closeElement = document.createElement("button");
        closeElement.type = "button";
        closeElement.setAttribute("aria-label", "Close");
        closeElement.className = "toast-close";
        closeElement.innerHTML = "&#10006;";
        closeElement.addEventListener("click", (event => {
          event.stopPropagation();
          this._removeElement(this.toastElement);
          window.clearTimeout(this.toastElement.timeOutValue);
        }));
        const width = window.innerWidth > 0 ? window.innerWidth : screen.width;
        if (this.options.position == "left" && width > 360) {
          divElement.insertAdjacentElement("afterbegin", closeElement);
        } else {
          divElement.appendChild(closeElement);
        }
      }
      if (this.options.stopOnFocus && this.options.duration > 0) {
        divElement.addEventListener("mouseover", (event => {
          window.clearTimeout(divElement.timeOutValue);
        }));
        divElement.addEventListener("mouseleave", (() => {
          divElement.timeOutValue = window.setTimeout((() => {
            this._removeElement(divElement);
          }), this.options.duration);
        }));
      }
      if (typeof this.options.destination !== "undefined") {
        divElement.addEventListener("click", (event => {
          event.stopPropagation();
          if (this.options.newWindow === true) {
            window.open(this.options.destination, "_blank");
          } else {
            window.location = this.options.destination;
          }
        }));
      }
      if (typeof this.options.onClick === "function" && typeof this.options.destination === "undefined") {
        divElement.addEventListener("click", (event => {
          event.stopPropagation();
          this.options.onClick();
        }));
      }
      if (typeof this.options.offset === "object") {
        const x = this._getAxisOffsetAValue("x", this.options);
        const y = this._getAxisOffsetAValue("y", this.options);
        const xOffset = this.options.position == "left" ? x : `-${x}`;
        const yOffset = this.options.gravity == "toastify-top" ? y : `-${y}`;
        divElement.style.transform = `translate(${xOffset},${yOffset})`;
      }
      return divElement;
    }
    _removeElement(toastElement) {
      toastElement.className = toastElement.className.replace(" on", "");
      window.setTimeout((() => {
        if (this.options.node && this.options.node.parentNode) {
          this.options.node.parentNode.removeChild(this.options.node);
        }
        if (toastElement.parentNode) {
          toastElement.parentNode.removeChild(toastElement);
        }
        this.options.callback.call(toastElement);
        this._reposition();
      }), 400);
    }
    _reposition() {
      let topLeftOffsetSize = {
        top: 15,
        bottom: 15
      };
      let topRightOffsetSize = {
        top: 15,
        bottom: 15
      };
      let offsetSize = {
        top: 15,
        bottom: 15
      };
      let allToasts = this._rootElement.querySelectorAll(".toastify");
      let classUsed;
      for (let i = 0; i < allToasts.length; i++) {
        if (allToasts[i].classList.contains("toastify-top") === true) {
          classUsed = "toastify-top";
        } else {
          classUsed = "toastify-bottom";
        }
        let height = allToasts[i].offsetHeight;
        classUsed = classUsed.substr(9, classUsed.length - 1);
        let offset = 15;
        let width = window.innerWidth > 0 ? window.innerWidth : screen.width;
        if (width <= 360) {
          allToasts[i].style[classUsed] = `${offsetSize[classUsed]}px`;
          offsetSize[classUsed] += height + offset;
        } else {
          if (allToasts[i].classList.contains("toastify-left") === true) {
            allToasts[i].style[classUsed] = `${topLeftOffsetSize[classUsed]}px`;
            topLeftOffsetSize[classUsed] += height + offset;
          } else {
            allToasts[i].style[classUsed] = `${topRightOffsetSize[classUsed]}px`;
            topRightOffsetSize[classUsed] += height + offset;
          }
        }
      }
    }
    _getAxisOffsetAValue(axis, options) {
      if (options.offset[axis]) {
        if (isNaN(options.offset[axis])) {
          return options.offset[axis];
        } else {
          return `${options.offset[axis]}px`;
        }
      }
      return "0px";
    }
  }
  function StartToastifyInstance(options) {
    return new Toastify(options);
  }
  CableReady.operations.stimulusReflexVersionMismatch = operation => {
    const levels = {
      info: {},
      success: {
        background: "#198754",
        color: "white"
      },
      warn: {
        background: "#ffc107",
        color: "black"
      },
      error: {
        background: "#dc3545",
        color: "white"
      }
    };
    const defaults = {
      selector: setupToastify(),
      close: true,
      duration: 30 * 1e3,
      gravity: "bottom",
      position: "right",
      newWindow: true,
      style: levels[operation.level || "info"]
    };
    StartToastifyInstance({
      ...defaults,
      ...operation
    }).showToast();
  };
  function setupToastify() {
    const id = "stimulus-reflex-toast-element";
    let element = document.querySelector(`#${id}`);
    if (!element) {
      element = document.createElement("div");
      element.id = id;
      document.documentElement.appendChild(element);
      const styles = document.createElement("style");
      styles.innerHTML = `\n      #${id} .toastify {\n         padding: 12px 20px;\n         color: #ffffff;\n         display: inline-block;\n         background: -webkit-linear-gradient(315deg, #73a5ff, #5477f5);\n         background: linear-gradient(135deg, #73a5ff, #5477f5);\n         position: fixed;\n         opacity: 0;\n         transition: all 0.4s cubic-bezier(0.215, 0.61, 0.355, 1);\n         border-radius: 2px;\n         cursor: pointer;\n         text-decoration: none;\n         max-width: calc(50% - 20px);\n         z-index: 2147483647;\n         bottom: -150px;\n         right: 15px;\n      }\n\n      #${id} .toastify.on {\n        opacity: 1;\n      }\n\n      #${id} .toast-close {\n        background: transparent;\n        border: 0;\n        color: white;\n        cursor: pointer;\n        font-family: inherit;\n        font-size: 1em;\n        opacity: 0.4;\n        padding: 0 5px;\n      }\n    `;
      document.head.appendChild(styles);
    }
    return element;
  }
  let deprecationWarnings = true;
  var Deprecate = {
    get enabled() {
      return deprecationWarnings;
    },
    get disabled() {
      return !deprecationWarnings;
    },
    get value() {
      return deprecationWarnings;
    },
    set(value) {
      deprecationWarnings = !!value;
    },
    set deprecate(value) {
      deprecationWarnings = !!value;
    }
  };
  let debugging = false;
  var Debug$1 = {
    get enabled() {
      return debugging;
    },
    get disabled() {
      return !debugging;
    },
    get value() {
      return debugging;
    },
    set(value) {
      debugging = !!value;
    },
    set debug(value) {
      debugging = !!value;
    }
  };
  const defaultSchema = {
    reflexAttribute: "data-reflex",
    reflexPermanentAttribute: "data-reflex-permanent",
    reflexRootAttribute: "data-reflex-root",
    reflexSuppressLoggingAttribute: "data-reflex-suppress-logging",
    reflexDatasetAttribute: "data-reflex-dataset",
    reflexDatasetAllAttribute: "data-reflex-dataset-all",
    reflexSerializeFormAttribute: "data-reflex-serialize-form",
    reflexFormSelectorAttribute: "data-reflex-form-selector",
    reflexIncludeInnerHtmlAttribute: "data-reflex-include-inner-html",
    reflexIncludeTextContentAttribute: "data-reflex-include-text-content"
  };
  let schema = {};
  var Schema = {
    set(application) {
      schema = {
        ...defaultSchema,
        ...application.schema
      };
      for (const attribute in schema) {
        const attributeName = attribute.slice(0, -9);
        Object.defineProperty(this, attributeName, {
          get: () => schema[attribute],
          configurable: true
        });
      }
    }
  };
  const {debounce: debounce, dispatch: dispatch, xpathToElement: xpathToElement, xpathToElementArray: xpathToElementArray} = CableReady.Utils;
  const uuidv4 = () => {
    const crypto = window.crypto || window.msCrypto;
    return ([ 1e7 ] + -1e3 + -4e3 + -8e3 + -1e11).replace(/[018]/g, (c => (c ^ crypto.getRandomValues(new Uint8Array(1))[0] & 15 >> c / 4).toString(16)));
  };
  const serializeForm = (form, options = {}) => {
    if (!form) return "";
    const w = options.w || window;
    const {element: element} = options;
    const formData = new w.FormData(form);
    const data = Array.from(formData, (e => e.map(encodeURIComponent).join("=")));
    const submitButton = form.querySelector("input[type=submit]");
    if (element && element.name && element.nodeName === "INPUT" && element.type === "submit") {
      data.push(`${encodeURIComponent(element.name)}=${encodeURIComponent(element.value)}`);
    } else if (submitButton && submitButton.name) {
      data.push(`${encodeURIComponent(submitButton.name)}=${encodeURIComponent(submitButton.value)}`);
    }
    return Array.from(data).join("&");
  };
  const camelize = (value, uppercaseFirstLetter = true) => {
    if (typeof value !== "string") return "";
    value = value.replace(/[\s_](.)/g, ($1 => $1.toUpperCase())).replace(/[\s_]/g, "").replace(/^(.)/, ($1 => $1.toLowerCase()));
    if (uppercaseFirstLetter) value = value.substr(0, 1).toUpperCase() + value.substr(1);
    return value;
  };
  const XPathToElement = xpathToElement;
  const XPathToArray = xpathToElementArray;
  const emitEvent = (name, detail = {}) => dispatch(document, name, detail);
  const extractReflexName = reflexString => {
    const match = reflexString.match(/(?:.*->)?(.*?)(?:Reflex)?#/);
    return match ? match[1] : "";
  };
  const elementToXPath = element => {
    if (element.id !== "") return "//*[@id='" + element.id + "']";
    if (element === document.body) return "/html/body";
    if (element.nodeName === "HTML") return "/html";
    let ix = 0;
    const siblings = element && element.parentNode ? element.parentNode.childNodes : [];
    for (var i = 0; i < siblings.length; i++) {
      const sibling = siblings[i];
      if (sibling === element) {
        const computedPath = elementToXPath(element.parentNode);
        const tagName = element.tagName.toLowerCase();
        const ixInc = ix + 1;
        return `${computedPath}/${tagName}[${ixInc}]`;
      }
      if (sibling.nodeType === 1 && sibling.tagName === element.tagName) {
        ix++;
      }
    }
  };
  const elementInvalid = element => element.type === "number" && element.validity && element.validity.badInput;
  const getReflexElement = (args, element) => args[0] && args[0].nodeType === Node.ELEMENT_NODE ? args.shift() : element;
  const getReflexOptions = args => {
    const options = {};
    if (args[0] && typeof args[0] === "object" && Object.keys(args[0]).filter((key => [ "id", "attrs", "selectors", "reflexId", "resolveLate", "serializeForm", "suppressLogging", "includeInnerHTML", "includeTextContent" ].includes(key))).length) {
      const opts = args.shift();
      Object.keys(opts).forEach((o => {
        if (o === "reflexId") {
          if (Deprecate.enabled) console.warn("reflexId option will be removed in v4. Use id instead.");
          options["id"] = opts["reflexId"];
        } else options[o] = opts[o];
      }));
    }
    return options;
  };
  const getReflexRoots = element => {
    let list = [];
    while (list.length === 0 && element) {
      let reflexRoot = element.getAttribute(Schema.reflexRoot);
      if (reflexRoot) {
        if (reflexRoot.length === 0 && element.id) reflexRoot = `#${element.id}`;
        const selectors = reflexRoot.split(",").filter((s => s.trim().length));
        if (Debug$1.enabled && selectors.length === 0) {
          console.error(`No value found for ${Schema.reflexRoot}. Add an #id to the element or provide a value for ${Schema.reflexRoot}.`, element);
        }
        list = list.concat(selectors.filter((s => document.querySelector(s))));
      }
      element = element.parentElement ? element.parentElement.closest(`[${Schema.reflexRoot}]`) : null;
    }
    return list;
  };
  const reflexNameToControllerIdentifier = reflexName => reflexName.replace(/([a-z0–9])([A-Z])/g, "$1-$2").replace(/(::)/g, "--").replace(/-reflex$/gi, "").toLowerCase();
  const stages = [ "created", "before", "delivered", "queued", "after", "finalized", "success", "error", "halted", "forbidden" ];
  let lastReflex;
  const reflexes = new Proxy({}, {
    get: function(target, prop) {
      if (stages.includes(prop)) return Object.fromEntries(Object.entries(target).filter((([_, reflex]) => reflex.stage === prop))); else if (prop === "last") return lastReflex; else if (prop === "all") return target;
      return Reflect.get(...arguments);
    },
    set: function(target, prop, value) {
      target[prop] = value;
      lastReflex = value;
      return true;
    }
  });
  const invokeLifecycleMethod = (reflex, stage) => {
    const specificLifecycleMethod = reflex.controller[[ "before", "after", "finalize" ].includes(stage) ? `${stage}${camelize(reflex.action)}` : `${camelize(reflex.action, false)}${camelize(stage)}`];
    const genericLifecycleMethod = reflex.controller[[ "before", "after", "finalize" ].includes(stage) ? `${stage}Reflex` : `reflex${camelize(stage)}`];
    if (typeof specificLifecycleMethod === "function") {
      specificLifecycleMethod.call(reflex.controller, reflex.element, reflex.target, reflex.error, reflex.id, reflex.payload);
    }
    if (typeof genericLifecycleMethod === "function") {
      genericLifecycleMethod.call(reflex.controller, reflex.element, reflex.target, reflex.error, reflex.id, reflex.payload);
    }
  };
  const dispatchLifecycleEvent = (reflex, stage) => {
    if (!reflex.controller.element.parentElement) {
      if (Debug$1.enabled && !reflex.warned) {
        console.warn(`StimulusReflex was not able execute callbacks or emit events for "${stage}" or later life-cycle stages for this Reflex. The StimulusReflex Controller Element is no longer present in the DOM. Could you move the StimulusReflex Controller to an element higher in your DOM?`);
        reflex.warned = true;
      }
      return;
    }
    reflex.stage = stage;
    reflex.lifecycle.push(stage);
    const event = `stimulus-reflex:${stage}`;
    const action = `${event}:${reflex.action}`;
    const detail = {
      reflex: reflex.target,
      controller: reflex.controller,
      id: reflex.id,
      element: reflex.element,
      payload: reflex.payload
    };
    const options = {
      bubbles: true,
      cancelable: false,
      detail: detail
    };
    reflex.controller.element.dispatchEvent(new CustomEvent(event, options));
    reflex.controller.element.dispatchEvent(new CustomEvent(action, options));
    if (window.jQuery) {
      window.jQuery(reflex.controller.element).trigger(event, detail);
      window.jQuery(reflex.controller.element).trigger(action, detail);
    }
  };
  document.addEventListener("stimulus-reflex:before", (event => invokeLifecycleMethod(reflexes[event.detail.id], "before")), true);
  document.addEventListener("stimulus-reflex:queued", (event => invokeLifecycleMethod(reflexes[event.detail.id], "queued")), true);
  document.addEventListener("stimulus-reflex:delivered", (event => invokeLifecycleMethod(reflexes[event.detail.id], "delivered")), true);
  document.addEventListener("stimulus-reflex:success", (event => {
    const reflex = reflexes[event.detail.id];
    invokeLifecycleMethod(reflex, "success");
    dispatchLifecycleEvent(reflex, "after");
  }), true);
  document.addEventListener("stimulus-reflex:nothing", (event => dispatchLifecycleEvent(reflexes[event.detail.id], "success")), true);
  document.addEventListener("stimulus-reflex:error", (event => {
    const reflex = reflexes[event.detail.id];
    invokeLifecycleMethod(reflex, "error");
    dispatchLifecycleEvent(reflex, "after");
  }), true);
  document.addEventListener("stimulus-reflex:halted", (event => invokeLifecycleMethod(reflexes[event.detail.id], "halted")), true);
  document.addEventListener("stimulus-reflex:forbidden", (event => invokeLifecycleMethod(reflexes[event.detail.id], "forbidden")), true);
  document.addEventListener("stimulus-reflex:after", (event => invokeLifecycleMethod(reflexes[event.detail.id], "after")), true);
  document.addEventListener("stimulus-reflex:finalize", (event => invokeLifecycleMethod(reflexes[event.detail.id], "finalize")), true);
  let app = {};
  var App = {
    get app() {
      return app;
    },
    set(application) {
      app = application;
    }
  };
  let isolationMode = false;
  var IsolationMode = {
    get disabled() {
      return !isolationMode;
    },
    set(value) {
      isolationMode = value;
      if (Deprecate.enabled && !isolationMode) {
        document.addEventListener("DOMContentLoaded", (() => console.warn("Deprecation warning: the next version of StimulusReflex will standardize isolation mode, and the isolate option will be removed.\nPlease update your applications to assume that every tab will be isolated. Use CableReady operations to broadcast updates to other tabs and users.")), {
          once: true
        });
      }
    }
  };
  class Reflex {
    constructor(data, controller) {
      this.data = data.valueOf();
      this.controller = controller;
      this.element = data.reflexElement;
      this.id = data.id;
      this.error = null;
      this.payload = null;
      this.stage = "created";
      this.lifecycle = [ "created" ];
      this.warned = false;
      this.target = data.target;
      this.action = data.target.split("#")[1];
      this.selector = null;
      this.morph = null;
      this.operation = null;
      this.timestamp = new Date;
      this.cloned = false;
    }
    get getPromise() {
      const promise = new Promise(((resolve, reject) => {
        this.promise = {
          resolve: resolve,
          reject: reject,
          data: this.data
        };
      }));
      promise.id = this.id;
      Object.defineProperty(promise, "reflexId", {
        get() {
          if (Deprecate.enabled) console.warn("reflexId is deprecated and will be removed from v4. Use id instead.");
          return this.id;
        }
      });
      promise.reflex = this;
      if (Debug$1.enabled) promise.catch((() => {}));
      return promise;
    }
  }
  const received = data => {
    if (!data.cableReady) return;
    if (data.version.replace(".pre", "-pre").replace(".rc", "-rc") !== CableReady.version) {
      const mismatch = `CableReady failed to execute your reflex action due to a version mismatch between your gem and JavaScript version. Package versions must match exactly.\n\ncable_ready gem: ${data.version}\ncable_ready npm: ${CableReady.version}`;
      console.error(mismatch);
      if (Debug$1.enabled) {
        CableReady.operations.stimulusReflexVersionMismatch({
          text: mismatch,
          level: "error"
        });
      }
      return;
    }
    let reflexOperations = [];
    for (let i = data.operations.length - 1; i >= 0; i--) {
      if (data.operations[i].stimulusReflex) {
        reflexOperations.push(data.operations[i]);
        data.operations.splice(i, 1);
      }
    }
    if (reflexOperations.some((operation => operation.stimulusReflex.url !== location.href))) {
      if (Debug$1.enabled) {
        console.error("Reflex failed due to mismatched URL.");
        return;
      }
    }
    let reflexData;
    if (reflexOperations.length) {
      reflexData = reflexOperations[0].stimulusReflex;
      reflexData.payload = reflexOperations[0].payload;
    }
    if (reflexData) {
      const {id: id, payload: payload} = reflexData;
      let reflex;
      if (!reflexes[id] && IsolationMode.disabled) {
        const controllerElement = XPathToElement(reflexData.xpathController);
        const reflexElement = XPathToElement(reflexData.xpathElement);
        controllerElement.reflexController = controllerElement.reflexController || {};
        controllerElement.reflexData = controllerElement.reflexData || {};
        controllerElement.reflexError = controllerElement.reflexError || {};
        const controller = App.app.getControllerForElementAndIdentifier(controllerElement, reflexData.reflexController);
        controllerElement.reflexController[id] = controller;
        controllerElement.reflexData[id] = reflexData;
        reflex = new Reflex(reflexData, controller);
        reflexes[id] = reflex;
        reflex.cloned = true;
        reflex.element = reflexElement;
        controller.lastReflex = reflex;
        dispatchLifecycleEvent(reflex, "before");
        reflex.getPromise;
      } else {
        reflex = reflexes[id];
      }
      if (reflex) {
        reflex.payload = payload;
        reflex.totalOperations = reflexOperations.length;
        reflex.pendingOperations = reflexOperations.length;
        reflex.completedOperations = 0;
        reflex.piggybackOperations = data.operations;
        CableReady.perform(reflexOperations);
      }
    } else {
      if (data.operations.length && reflexes[data.operations[0].reflexId]) {
        CableReady.perform(data.operations);
      }
    }
  };
  let consumer;
  let params;
  let subscription;
  let active;
  const initialize$1 = (consumerValue, paramsValue) => {
    consumer = consumerValue;
    params = paramsValue;
    document.addEventListener("DOMContentLoaded", (() => {
      active = false;
      connectionStatusClass();
      if (Deprecate.enabled && consumerValue) console.warn("Deprecation warning: the next version of StimulusReflex will obtain a reference to consumer via the Stimulus application object.\nPlease add 'application.consumer = consumer' to your index.js after your Stimulus application has been established, and remove the consumer key from your StimulusReflex initialize() options object.");
    }));
    document.addEventListener("turbolinks:load", connectionStatusClass);
    document.addEventListener("turbo:load", connectionStatusClass);
  };
  const subscribe = controller => {
    if (subscription) return;
    consumer = consumer || controller.application.consumer || actioncable.createConsumer();
    const {channel: channel} = controller.StimulusReflex;
    const request = {
      channel: channel,
      ...params
    };
    const identifier = JSON.stringify(request);
    subscription = consumer.subscriptions.findAll(identifier)[0] || consumer.subscriptions.create(request, {
      received: received,
      connected: connected,
      rejected: rejected,
      disconnected: disconnected
    });
  };
  const connected = () => {
    active = true;
    connectionStatusClass();
    emitEvent("stimulus-reflex:connected");
    Object.values(reflexes.queued).forEach((reflex => {
      subscription.send(reflex.data);
      dispatchLifecycleEvent(reflex, "delivered");
    }));
  };
  const rejected = () => {
    active = false;
    connectionStatusClass();
    emitEvent("stimulus-reflex:rejected");
    if (Debug.enabled) console.warn("Channel subscription was rejected.");
  };
  const disconnected = willAttemptReconnect => {
    active = false;
    connectionStatusClass();
    emitEvent("stimulus-reflex:disconnected", willAttemptReconnect);
  };
  const deliver = reflex => {
    if (active) {
      subscription.send(reflex.data);
      dispatchLifecycleEvent(reflex, "delivered");
    } else dispatchLifecycleEvent(reflex, "queued");
  };
  const connectionStatusClass = () => {
    const list = document.body.classList;
    if (!(list.contains("stimulus-reflex-connected") || list.contains("stimulus-reflex-disconnected"))) {
      list.add(active ? "stimulus-reflex-connected" : "stimulus-reflex-disconnected");
      return;
    }
    if (active) {
      list.replace("stimulus-reflex-disconnected", "stimulus-reflex-connected");
    } else {
      list.replace("stimulus-reflex-connected", "stimulus-reflex-disconnected");
    }
  };
  var ActionCableTransport = {
    subscribe: subscribe,
    deliver: deliver,
    initialize: initialize$1
  };
  const request = reflex => {
    if (Debug$1.disabled || reflex.data.suppressLogging) return;
    console.log(`↑ stimulus ↑ ${reflex.target}`, {
      id: reflex.id,
      args: reflex.data.args,
      controller: reflex.controller.identifier,
      element: reflex.element,
      controllerElement: reflex.controller.element
    });
  };
  const success = reflex => {
    if (Debug$1.disabled || reflex.data.suppressLogging) return;
    const output = {
      id: reflex.id,
      morph: reflex.morph,
      payload: reflex.payload
    };
    if (reflex.operation !== "dispatch_event") output.operation = reflex.operation;
    console.log(`↓ reflex ↓ ${reflex.target} → ${reflex.selector || "∞"}${progress(reflex)} ${duration(reflex)}`, output);
  };
  const halted$1 = reflex => {
    if (Debug$1.disabled || reflex.data.suppressLogging) return;
    console.log(`↓ reflex ↓ ${reflex.target} ${duration(reflex)} %cHALTED`, "color: #ffa500;", {
      id: reflex.id,
      payload: reflex.payload
    });
  };
  const forbidden$1 = reflex => {
    if (Debug$1.disabled || reflex.data.suppressLogging) return;
    console.log(`↓ reflex ↓ ${reflex.target} ${duration(reflex)} %cFORBIDDEN`, "color: #BF40BF;", {
      id: reflex.id,
      payload: reflex.payload
    });
  };
  const error$1 = reflex => {
    if (Debug$1.disabled || reflex.data.suppressLogging) return;
    console.log(`↓ reflex ↓ ${reflex.target} ${duration(reflex)} %cERROR: ${reflex.error}`, "color: #f00;", {
      id: reflex.id,
      payload: reflex.payload
    });
  };
  const duration = reflex => !reflex.cloned ? `in ${new Date - reflex.timestamp}ms` : "CLONED";
  const progress = reflex => reflex.totalOperations > 1 ? ` ${reflex.completedOperations}/${reflex.totalOperations}` : "";
  var Log = {
    request: request,
    success: success,
    halted: halted$1,
    forbidden: forbidden$1,
    error: error$1
  };
  const multipleInstances = element => {
    if ([ "checkbox", "radio" ].includes(element.type)) {
      return document.querySelectorAll(`input[type="${element.type}"][name="${element.name}"]`).length > 1;
    }
    return false;
  };
  const collectCheckedOptions = element => Array.from(element.querySelectorAll("option:checked")).concat(Array.from(document.querySelectorAll(`input[type="${element.type}"][name="${element.name}"]`)).filter((elem => elem.checked))).map((o => o.value));
  const attributeValue = (values = []) => {
    const value = Array.from(new Set(values.filter((v => v && String(v).length)).map((v => v.trim())))).join(" ").trim();
    return value.length > 0 ? value : null;
  };
  const attributeValues = value => {
    if (!value) return [];
    if (!value.length) return [];
    return value.split(" ").filter((v => v.trim().length));
  };
  const extractElementAttributes = element => {
    let attrs = Array.from(element.attributes).reduce(((memo, attr) => {
      memo[attr.name] = attr.value;
      return memo;
    }), {});
    attrs.checked = !!element.checked;
    attrs.selected = !!element.selected;
    attrs.tag_name = element.tagName;
    if (element.tagName.match(/select/i) || multipleInstances(element)) {
      const collectedOptions = collectCheckedOptions(element);
      attrs.values = collectedOptions;
      attrs.value = collectedOptions.join(",");
    } else {
      attrs.value = element.value;
    }
    return attrs;
  };
  const getElementsFromTokens = (element, tokens) => {
    if (!tokens || tokens.length === 0) return [];
    let elements = [ element ];
    const xPath = elementToXPath(element);
    tokens.forEach((token => {
      try {
        switch (token) {
         case "combined":
          if (Deprecate.enabled) console.warn("In the next version of StimulusReflex, the 'combined' option to data-reflex-dataset will become 'ancestors'.");
          elements = [ ...elements, ...XPathToArray(`${xPath}/ancestor::*`, true) ];
          break;

         case "ancestors":
          elements = [ ...elements, ...XPathToArray(`${xPath}/ancestor::*`, true) ];
          break;

         case "parent":
          elements = [ ...elements, ...XPathToArray(`${xPath}/parent::*`) ];
          break;

         case "siblings":
          elements = [ ...elements, ...XPathToArray(`${xPath}/preceding-sibling::*|${xPath}/following-sibling::*`) ];
          break;

         case "children":
          elements = [ ...elements, ...XPathToArray(`${xPath}/child::*`) ];
          break;

         case "descendants":
          elements = [ ...elements, ...XPathToArray(`${xPath}/descendant::*`) ];
          break;

         default:
          elements = [ ...elements, ...document.querySelectorAll(token) ];
        }
      } catch (error) {
        if (Debug$1.enabled) console.error(error);
      }
    }));
    return elements;
  };
  const extractElementDataset = element => {
    const dataset = element.attributes[Schema.reflexDataset];
    const allDataset = element.attributes[Schema.reflexDatasetAll];
    const tokens = dataset && dataset.value.split(" ") || [];
    const allTokens = allDataset && allDataset.value.split(" ") || [];
    const datasetElements = getElementsFromTokens(element, tokens);
    const datasetAllElements = getElementsFromTokens(element, allTokens);
    const datasetAttributes = datasetElements.reduce(((acc, ele) => ({
      ...extractDataAttributes(ele),
      ...acc
    })), {});
    const reflexElementAttributes = extractDataAttributes(element);
    const elementDataset = {
      dataset: {
        ...reflexElementAttributes,
        ...datasetAttributes
      },
      datasetAll: {}
    };
    datasetAllElements.forEach((element => {
      const elementAttributes = extractDataAttributes(element);
      Object.keys(elementAttributes).forEach((key => {
        const value = elementAttributes[key];
        if (elementDataset.datasetAll[key] && Array.isArray(elementDataset.datasetAll[key])) {
          elementDataset.datasetAll[key].push(value);
        } else {
          elementDataset.datasetAll[key] = [ value ];
        }
      }));
    }));
    return elementDataset;
  };
  const extractDataAttributes = element => {
    let attrs = {};
    if (element && element.attributes) {
      Array.from(element.attributes).forEach((attr => {
        if (attr.name.startsWith("data-")) {
          attrs[attr.name] = attr.value;
        }
      }));
    }
    return attrs;
  };
  var name = "stimulus_reflex";
  var version = "3.5.5";
  var description = "Build reactive applications with the Rails tooling you already know and love.";
  var keywords = [ "ruby", "rails", "websockets", "actioncable", "turbolinks", "reactive", "cable", "ujs", "ssr", "stimulus", "reflex", "stimulus_reflex", "dom", "morphdom" ];
  var homepage = "https://docs.stimulusreflex.com";
  var bugs = "https://github.com/stimulusreflex/stimulus_reflex/issues";
  var repository = "https://github.com/stimulusreflex/stimulus_reflex";
  var license = "MIT";
  var author = "Nathan Hopkins <natehop@gmail.com>";
  var contributors = [ "Andrew Mason <andrewmcodes@protonmail.com>", "Julian Rubisch <julian@julianrubisch.at>", "Marco Roth <marco.roth@intergga.ch>", "Nathan Hopkins <natehop@gmail.com>" ];
  var main = "./dist/stimulus_reflex.js";
  var module = "./dist/stimulus_reflex.js";
  var browser = "./dist/stimulus_reflex.js";
  var unpkg = "./dist/stimulus_reflex.umd.js";
  var umd = "./dist/stimulus_reflex.umd.js";
  var files = [ "dist/*", "javascript/*" ];
  var scripts = {
    lint: "yarn run format --check",
    format: "yarn run prettier-standard ./javascript/**/*.js rollup.config.mjs",
    build: "yarn rollup -c",
    "build:watch": "yarn rollup -wc",
    watch: "yarn build:watch",
    test: "web-test-runner javascript/test/**/*.test.js",
    "test:watch": "yarn test --watch",
    "docs:dev": "vitepress dev docs",
    "docs:build": "vitepress build docs && cp docs/_redirects docs/.vitepress/dist",
    "docs:preview": "vitepress preview docs"
  };
  var peerDependencies = {
    "@hotwired/stimulus": ">= 3.0"
  };
  var dependencies = {
    "@hotwired/stimulus": "^3",
    "@rails/actioncable": "^6 || ^7 || ^8",
    cable_ready: "^5.0.6"
  };
  var devDependencies = {
    "@open-wc/testing": "^4.0.0",
    "@rollup/plugin-json": "^6.1.0",
    "@rollup/plugin-node-resolve": "^15.3.0",
    "@rollup/plugin-terser": "^0.4.4",
    "@web/dev-server-esbuild": "^1.0.2",
    "@web/dev-server-rollup": "^0.6.4",
    "@web/test-runner": "^0.19.0",
    "prettier-standard": "^16.4.1",
    rollup: "^4.22.4",
    "toastify-js": "^1.12.0",
    vitepress: "^1.0.0-beta.1"
  };
  var packageInfo = {
    name: name,
    version: version,
    description: description,
    keywords: keywords,
    homepage: homepage,
    bugs: bugs,
    repository: repository,
    license: license,
    author: author,
    contributors: contributors,
    main: main,
    module: module,
    browser: browser,
    import: "./dist/stimulus_reflex.js",
    unpkg: unpkg,
    umd: umd,
    files: files,
    scripts: scripts,
    peerDependencies: peerDependencies,
    dependencies: dependencies,
    devDependencies: devDependencies
  };
  class ReflexData {
    constructor(options, reflexElement, controllerElement, reflexController, permanentAttributeName, target, args, url, tabId) {
      this.options = options;
      this.reflexElement = reflexElement;
      this.controllerElement = controllerElement;
      this.reflexController = reflexController;
      this.permanentAttributeName = permanentAttributeName;
      this.target = target;
      this.args = args;
      this.url = url;
      this.tabId = tabId;
    }
    get attrs() {
      this._attrs = this._attrs || this.options["attrs"] || extractElementAttributes(this.reflexElement);
      return this._attrs;
    }
    get id() {
      this._id = this._id || this.options["id"] || uuidv4();
      return this._id;
    }
    get selectors() {
      this._selectors = this._selectors || this.options["selectors"] || getReflexRoots(this.reflexElement);
      return typeof this._selectors === "string" ? [ this._selectors ] : this._selectors;
    }
    get resolveLate() {
      return this.options["resolveLate"] || false;
    }
    get dataset() {
      this._dataset = this._dataset || extractElementDataset(this.reflexElement);
      return this._dataset;
    }
    get innerHTML() {
      return this.includeInnerHtml ? this.reflexElement.innerHTML : "";
    }
    get textContent() {
      return this.includeTextContent ? this.reflexElement.textContent : "";
    }
    get xpathController() {
      return elementToXPath(this.controllerElement);
    }
    get xpathElement() {
      return elementToXPath(this.reflexElement);
    }
    get formSelector() {
      const attr = this.reflexElement.attributes[Schema.reflexFormSelector] ? this.reflexElement.attributes[Schema.reflexFormSelector].value : undefined;
      return this.options["formSelector"] || attr;
    }
    get includeInnerHtml() {
      const attr = this.reflexElement.attributes[Schema.reflexIncludeInnerHtml] || false;
      return this.options["includeInnerHTML"] || attr ? attr.value !== "false" : false;
    }
    get includeTextContent() {
      const attr = this.reflexElement.attributes[Schema.reflexIncludeTextContent] || false;
      return this.options["includeTextContent"] || attr ? attr.value !== "false" : false;
    }
    get suppressLogging() {
      return this.options["suppressLogging"] || this.reflexElement.attributes[Schema.reflexSuppressLogging] || false;
    }
    valueOf() {
      return {
        attrs: this.attrs,
        dataset: this.dataset,
        selectors: this.selectors,
        id: this.id,
        resolveLate: this.resolveLate,
        suppressLogging: this.suppressLogging,
        xpathController: this.xpathController,
        xpathElement: this.xpathElement,
        inner_html: this.innerHTML,
        text_content: this.textContent,
        formSelector: this.formSelector,
        reflexController: this.reflexController,
        permanentAttributeName: this.permanentAttributeName,
        target: this.target,
        args: this.args,
        url: this.url,
        tabId: this.tabId,
        version: packageInfo.version
      };
    }
  }
  let transport = {};
  var Transport = {
    get plugin() {
      return transport;
    },
    set(newTransport) {
      transport = newTransport;
    }
  };
  const beforeDOMUpdate = event => {
    const {stimulusReflex: stimulusReflex} = event.detail || {};
    if (!stimulusReflex) return;
    const reflex = reflexes[stimulusReflex.id];
    reflex.pendingOperations--;
    if (reflex.pendingOperations > 0) return;
    if (!stimulusReflex.resolveLate) setTimeout((() => reflex.promise.resolve({
      element: reflex.element,
      event: event,
      data: reflex.data,
      payload: reflex.payload,
      id: reflex.id,
      toString: () => ""
    })));
    setTimeout((() => dispatchLifecycleEvent(reflex, "success")));
  };
  const afterDOMUpdate = event => {
    const {stimulusReflex: stimulusReflex} = event.detail || {};
    if (!stimulusReflex) return;
    const reflex = reflexes[stimulusReflex.id];
    reflex.completedOperations++;
    reflex.selector = event.detail.selector;
    reflex.morph = event.detail.stimulusReflex.morph;
    reflex.operation = event.type.split(":")[1].split("-").slice(1).join("_");
    Log.success(reflex);
    if (reflex.completedOperations < reflex.totalOperations) return;
    if (stimulusReflex.resolveLate) setTimeout((() => reflex.promise.resolve({
      element: reflex.element,
      event: event,
      data: reflex.data,
      payload: reflex.payload,
      id: reflex.id,
      toString: () => ""
    })));
    setTimeout((() => dispatchLifecycleEvent(reflex, "finalize")));
    if (reflex.piggybackOperations.length) CableReady.perform(reflex.piggybackOperations);
  };
  const routeReflexEvent = event => {
    const {stimulusReflex: stimulusReflex, name: name} = event.detail || {};
    const eventType = name.split("-")[2];
    const eventTypes = {
      nothing: nothing,
      halted: halted,
      forbidden: forbidden,
      error: error
    };
    if (!stimulusReflex || !Object.keys(eventTypes).includes(eventType)) return;
    const reflex = reflexes[stimulusReflex.id];
    reflex.completedOperations++;
    reflex.pendingOperations--;
    reflex.selector = event.detail.selector;
    reflex.morph = event.detail.stimulusReflex.morph;
    reflex.operation = event.type.split(":")[1].split("-").slice(1).join("_");
    if (eventType === "error") reflex.error = event.detail.error;
    eventTypes[eventType](reflex, event);
    setTimeout((() => dispatchLifecycleEvent(reflex, eventType)));
    if (reflex.piggybackOperations.length) CableReady.perform(reflex.piggybackOperations);
  };
  const nothing = (reflex, event) => {
    Log.success(reflex);
    setTimeout((() => reflex.promise.resolve({
      data: reflex.data,
      element: reflex.element,
      event: event,
      payload: reflex.payload,
      id: reflex.id,
      toString: () => ""
    })));
  };
  const halted = (reflex, event) => {
    Log.halted(reflex, event);
    setTimeout((() => reflex.promise.resolve({
      data: reflex.data,
      element: reflex.element,
      event: event,
      payload: reflex.payload,
      id: reflex.id,
      toString: () => ""
    })));
  };
  const forbidden = (reflex, event) => {
    Log.forbidden(reflex, event);
    setTimeout((() => reflex.promise.resolve({
      data: reflex.data,
      element: reflex.element,
      event: event,
      payload: reflex.payload,
      id: reflex.id,
      toString: () => ""
    })));
  };
  const error = (reflex, event) => {
    Log.error(reflex, event);
    setTimeout((() => reflex.promise.reject({
      data: reflex.data,
      element: reflex.element,
      event: event,
      payload: reflex.payload,
      id: reflex.id,
      error: reflex.error,
      toString: () => reflex.error
    })));
  };
  const localReflexControllers = element => {
    const potentialIdentifiers = attributeValues(element.getAttribute(Schema.controller));
    const potentialControllers = potentialIdentifiers.map((identifier => App.app.getControllerForElementAndIdentifier(element, identifier)));
    return potentialControllers.filter((controller => controller && controller.StimulusReflex));
  };
  const allReflexControllers = element => {
    let controllers = [];
    while (element) {
      controllers = controllers.concat(localReflexControllers(element));
      element = element.parentElement;
    }
    return controllers;
  };
  const findControllerByReflexName = (reflexName, controllers) => {
    const controller = controllers.find((controller => {
      if (!controller || !controller.identifier) return;
      const identifier = reflexNameToControllerIdentifier(extractReflexName(reflexName));
      return identifier === controller.identifier;
    }));
    return controller;
  };
  const scanForReflexes = debounce((() => {
    const reflexElements = document.querySelectorAll(`[${Schema.reflex}]`);
    reflexElements.forEach((element => scanForReflexesOnElement(element)));
  }), 20);
  const scanForReflexesOnElement = (element, controller = null) => {
    const controllerAttribute = element.getAttribute(Schema.controller);
    const controllers = attributeValues(controllerAttribute).filter((controller => controller !== "stimulus-reflex"));
    const reflexAttribute = element.getAttribute(Schema.reflex);
    const reflexAttributeNames = attributeValues(reflexAttribute);
    const actionAttribute = element.getAttribute(Schema.action);
    const actions = attributeValues(actionAttribute).filter((action => !action.includes("#__perform")));
    reflexAttributeNames.forEach((reflexName => {
      const potentialControllers = [ controller ].concat(allReflexControllers(element));
      controller = findControllerByReflexName(reflexName, potentialControllers);
      const controllerName = controller ? controller.identifier : "stimulus-reflex";
      actions.push(`${reflexName.split("->")[0]}->${controllerName}#__perform`);
      const parentControllerElement = element.closest(`[data-controller~=${controllerName}]`);
      const elementPreviouslyHadStimulusReflexController = element === parentControllerElement && controllerName === "stimulus-reflex";
      if (!parentControllerElement || elementPreviouslyHadStimulusReflexController) {
        controllers.push(controllerName);
      }
    }));
    const controllerValue = attributeValue(controllers);
    const actionValue = attributeValue(actions);
    let emitReadyEvent = false;
    if (controllerValue && element.getAttribute(Schema.controller) != controllerValue) {
      element.setAttribute(Schema.controller, controllerValue);
      emitReadyEvent = true;
    }
    if (actionValue && element.getAttribute(Schema.action) != actionValue) {
      element.setAttribute(Schema.action, actionValue);
      emitReadyEvent = true;
    }
    if (emitReadyEvent) {
      dispatch(element, "stimulus-reflex:ready", {
        reflex: reflexAttribute,
        controller: controllerValue,
        action: actionValue,
        element: element
      });
    }
  };
  class StimulusReflexController extends stimulus.Controller {
    constructor(...args) {
      super(...args);
      register(this);
    }
  }
  const tabId = uuidv4();
  const initialize = (application, {controller: controller, consumer: consumer, debug: debug, params: params, isolate: isolate, deprecate: deprecate, transport: transport} = {}) => {
    Transport.set(transport || ActionCableTransport);
    Transport.plugin.initialize(consumer, params);
    IsolationMode.set(!!isolate);
    App.set(application);
    Schema.set(application);
    App.app.register("stimulus-reflex", controller || StimulusReflexController);
    Debug$1.set(!!debug);
    if (typeof deprecate !== "undefined") Deprecate.set(deprecate);
    const observer = new MutationObserver(scanForReflexes);
    observer.observe(document.documentElement, {
      attributeFilter: [ Schema.reflex, Schema.action ],
      childList: true,
      subtree: true
    });
    emitEvent("stimulus-reflex:initialized");
  };
  const register = (controller, options = {}) => {
    const channel = "StimulusReflex::Channel";
    controller.StimulusReflex = {
      ...options,
      channel: channel
    };
    Transport.plugin.subscribe(controller);
    Object.assign(controller, {
      stimulate() {
        const url = location.href;
        const controllerElement = this.element;
        const args = Array.from(arguments);
        const target = args.shift() || "StimulusReflex::Reflex#default_reflex";
        const reflexElement = getReflexElement(args, controllerElement);
        if (elementInvalid(reflexElement)) {
          if (Debug$1.enabled) console.warn("Reflex aborted: invalid numeric input");
          return;
        }
        const options = getReflexOptions(args);
        const reflexData = new ReflexData(options, reflexElement, controllerElement, this.identifier, Schema.reflexPermanent, target, args, url, tabId);
        const id = reflexData.id;
        controllerElement.reflexController = controllerElement.reflexController || {};
        controllerElement.reflexData = controllerElement.reflexData || {};
        controllerElement.reflexError = controllerElement.reflexError || {};
        controllerElement.reflexController[id] = this;
        controllerElement.reflexData[id] = reflexData.valueOf();
        const reflex = new Reflex(reflexData, this);
        reflexes[id] = reflex;
        this.lastReflex = reflex;
        dispatchLifecycleEvent(reflex, "before");
        setTimeout((() => {
          const {params: params} = controllerElement.reflexData[id] || {};
          const check = reflexElement.attributes[Schema.reflexSerializeForm];
          if (check) {
            options["serializeForm"] = check.value !== "false";
          }
          const form = reflexElement.closest(reflexData.formSelector) || document.querySelector(reflexData.formSelector) || reflexElement.closest("form");
          if (Deprecate.enabled && options["serializeForm"] === undefined && form) console.warn(`Deprecation warning: the next version of StimulusReflex will not serialize forms by default.\nPlease set ${Schema.reflexSerializeForm}="true" on your Reflex Controller Element or pass { serializeForm: true } as an option to stimulate.`);
          const formData = options["serializeForm"] === false ? "" : serializeForm(form, {
            element: reflexElement
          });
          reflex.data = {
            ...reflexData.valueOf(),
            params: params,
            formData: formData
          };
          controllerElement.reflexData[id] = reflex.data;
          Transport.plugin.deliver(reflex);
        }));
        Log.request(reflex);
        return reflex.getPromise;
      },
      __perform(event) {
        let element = event.target;
        let reflex;
        while (element && !reflex) {
          reflex = element.getAttribute(Schema.reflex);
          if (!reflex || !reflex.trim().length) element = element.parentElement;
        }
        const match = attributeValues(reflex).find((reflex => reflex.split("->")[0] === event.type));
        if (match) {
          event.preventDefault();
          event.stopPropagation();
          this.stimulate(match.split("->")[1], element);
        }
      }
    });
    if (!controller.reflexes) Object.defineProperty(controller, "reflexes", {
      get() {
        return new Proxy(reflexes, {
          get: function(target, prop) {
            if (prop === "last") return this.lastReflex;
            return Object.fromEntries(Object.entries(target[prop]).filter((([_, reflex]) => reflex.controller === this)));
          }.bind(this)
        });
      }
    });
    scanForReflexesOnElement(controller.element, controller);
    emitEvent("stimulus-reflex:controller-registered", {
      detail: {
        controller: controller
      }
    });
  };
  const useReflex = (controller, options = {}) => {
    register(controller, options);
  };
  document.addEventListener("cable-ready:after-dispatch-event", routeReflexEvent);
  document.addEventListener("cable-ready:before-inner-html", beforeDOMUpdate);
  document.addEventListener("cable-ready:before-morph", beforeDOMUpdate);
  document.addEventListener("cable-ready:after-inner-html", afterDOMUpdate);
  document.addEventListener("cable-ready:after-morph", afterDOMUpdate);
  document.addEventListener("readystatechange", (() => {
    if (document.readyState === "complete") {
      scanForReflexes();
    }
  }));
  var StimulusReflex = Object.freeze({
    __proto__: null,
    StimulusReflexController: StimulusReflexController,
    initialize: initialize,
    reflexes: reflexes,
    register: register,
    scanForReflexes: scanForReflexes,
    scanForReflexesOnElement: scanForReflexesOnElement,
    useReflex: useReflex
  });
  const global = {
    version: packageInfo.version,
    ...StimulusReflex,
    get debug() {
      return Debug$1.value;
    },
    set debug(value) {
      Debug$1.set(!!value);
    },
    get deprecate() {
      return Deprecate.value;
    },
    set deprecate(value) {
      Deprecate.set(!!value);
    }
  };
  window.StimulusReflex = global;
  exports.StimulusReflexController = StimulusReflexController;
  exports.default = global;
  exports.initialize = initialize;
  exports.reflexes = reflexes;
  exports.register = register;
  exports.scanForReflexes = scanForReflexes;
  exports.scanForReflexesOnElement = scanForReflexesOnElement;
  exports.useReflex = useReflex;
  Object.defineProperty(exports, "__esModule", {
    value: true
  });
}));
