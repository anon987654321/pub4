(function(global, factory) {
  typeof exports === "object" && typeof module !== "undefined" ? factory(exports, require("morphdom")) : typeof define === "function" && define.amd ? define([ "exports", "morphdom" ], factory) : (global = typeof globalThis !== "undefined" ? globalThis : global || self, 
  factory(global.CableReady = {}, global.morphdom));
})(this, (function(exports, morphdom) {
  "use strict";
  var name = "cable_ready";
  var version = "5.0.6";
  var description = "CableReady helps you create great real-time user experiences by making it simple to trigger client-side DOM changes from server-side Ruby.";
  var keywords = [ "ruby", "rails", "websockets", "actioncable", "cable", "ssr", "stimulus_reflex", "client-side", "dom" ];
  var homepage = "https://cableready.stimulusreflex.com";
  var bugs = "https://github.com/stimulusreflex/cable_ready/issues";
  var repository = "https://github.com/stimulusreflex/cable_ready";
  var license = "MIT";
  var author = "Nathan Hopkins <natehop@gmail.com>";
  var contributors = [ "Andrew Mason <andrewmcodes@protonmail.com>", "Julian Rubisch <julian@julianrubisch.at>", "Marco Roth <marco.roth@intergga.ch>", "Nathan Hopkins <natehop@gmail.com>" ];
  var main = "./dist/cable_ready.js";
  var module = "./dist/cable_ready.js";
  var browser = "./dist/cable_ready.js";
  var unpkg = "./dist/cable_ready.umd.js";
  var umd = "./dist/cable_ready.umd.js";
  var files = [ "dist/*", "javascript/*" ];
  var scripts = {
    lint: "yarn run format --check",
    format: "yarn run prettier-standard ./javascript/**/*.js rollup.config.mjs",
    build: "yarn rollup -c",
    watch: "yarn rollup -wc",
    test: "web-test-runner javascript/test/**/*.test.js",
    "docs:dev": "vitepress dev docs",
    "docs:build": "vitepress build docs && cp ./docs/_redirects ./docs/.vitepress/dist",
    "docs:preview": "vitepress preview docs"
  };
  var dependencies = {
    morphdom: "2.6.1"
  };
  var devDependencies = {
    "@open-wc/testing": "^4.0.0",
    "@rollup/plugin-json": "^6.1.0",
    "@rollup/plugin-node-resolve": "^15.3.0",
    "@rollup/plugin-terser": "^0.4.4",
    "@web/dev-server-esbuild": "^1.0.3",
    "@web/dev-server-rollup": "^0.6.4",
    "@web/test-runner": "^0.19.0",
    "prettier-standard": "^16.4.1",
    rollup: "^4.25.0",
    sinon: "^19.0.2",
    vite: "^5.4.10",
    vitepress: "^1.5.0",
    "vitepress-plugin-search": "^1.0.4-alpha.22"
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
    import: "./dist/cable_ready.js",
    unpkg: unpkg,
    umd: umd,
    files: files,
    scripts: scripts,
    dependencies: dependencies,
    devDependencies: devDependencies
  };
  const inputTags = {
    INPUT: true,
    TEXTAREA: true,
    SELECT: true
  };
  const mutableTags = {
    INPUT: true,
    TEXTAREA: true,
    OPTION: true
  };
  const textInputTypes = {
    "datetime-local": true,
    "select-multiple": true,
    "select-one": true,
    color: true,
    date: true,
    datetime: true,
    email: true,
    month: true,
    number: true,
    password: true,
    range: true,
    search: true,
    tel: true,
    text: true,
    textarea: true,
    time: true,
    url: true,
    week: true
  };
  let activeElement;
  var ActiveElement = {
    get element() {
      return activeElement;
    },
    set(element) {
      activeElement = element;
    }
  };
  // Indicates if the passed element is considered a text input.
  
    const isTextInput = element => inputTags[element.tagName] && textInputTypes[element.type];
  // Assigns focus to the appropriate element... preferring the explicitly passed selector
  
  // * selector - a CSS selector for the element that should have focus
  
    const assignFocus = selector => {
    const element = selector && selector.nodeType === Node.ELEMENT_NODE ? selector : document.querySelector(selector);
    const focusElement = element || ActiveElement.element;
    if (focusElement && focusElement.focus) focusElement.focus();
  };
  // Dispatches an event on the passed element
  
  // * element - the element
  // * name - the name of the event
  // * detail - the event detail
  
    const dispatch = (element, name, detail = {}) => {
    const init = {
      bubbles: true,
      cancelable: true,
      detail: detail
    };
    const event = new CustomEvent(name, init);
    element.dispatchEvent(event);
    if (window.jQuery) window.jQuery(element).trigger(name, detail);
  };
  // Accepts an xPath query and returns the element found at that position in the DOM
  
    const xpathToElement = xpath => document.evaluate(xpath, document, null, XPathResult.FIRST_ORDERED_NODE_TYPE, null).singleNodeValue;
  // Accepts an xPath query and returns all matching elements in the DOM
  
    const xpathToElementArray = (xpath, reverse = false) => {
    const snapshotList = document.evaluate(xpath, document, null, XPathResult.ORDERED_NODE_SNAPSHOT_TYPE, null);
    const snapshots = [];
    for (let i = 0; i < snapshotList.snapshotLength; i++) {
      snapshots.push(snapshotList.snapshotItem(i));
    }
    return reverse ? snapshots.reverse() : snapshots;
  };
  // Return an array with the class names to be used
  
  // * names - could be a string or an array of strings for multiple classes.
  
    const getClassNames = names => Array.from(names).flat()
  // Perform operation for either the first or all of the elements returned by CSS selector
  
  // * operation - the instruction payload from perform
  // * callback - the operation function to run for each element
  
  ;
  const processElements = (operation, callback) => {
    Array.from(operation.selectAll ? operation.element : [ operation.element ]).forEach(callback);
  };
  // convert string to kebab-case
  // most other implementations (lodash) are focused on camelCase to kebab-case
  // instead, this uses word token boundaries to produce readable URL slugs and keys
  // this implementation will not support Emoji or other non-ASCII characters
  
    const kebabize = createCompounder((function(result, word, index) {
    return result + (index ? "-" : "") + word.toLowerCase();
  }));
  function createCompounder(callback) {
    return function(str) {
      return words(str).reduce(callback, "");
    };
  }
  const words = str => {
    str = str == null ? "" : str;
    return str.match(/([A-Z]{2,}|[0-9]+|[A-Z]?[a-z]+|[A-Z])/g) || [];
  };
  // Provide a standardized pipeline of checks and modifications to all operations based on provided options
  // Currently skips execution if cancelled and implements an optional delay
  
    const operate = (operation, callback) => {
    if (!operation.cancel) {
      operation.delay ? setTimeout(callback, operation.delay) : callback();
      return true;
    }
    return false;
  };
  // Dispatch life-cycle events with standardized naming
    const before = (target, operation) => dispatch(target, `cable-ready:before-${kebabize(operation.operation)}`, operation);
  const after = (target, operation) => dispatch(target, `cable-ready:after-${kebabize(operation.operation)}`, operation);
  function debounce(fn, delay = 250) {
    let timer;
    return (...args) => {
      const callback = () => fn.apply(this, args);
      if (timer) clearTimeout(timer);
      timer = setTimeout(callback, delay);
    };
  }
  function handleErrors(response) {
    if (!response.ok) throw Error(response.statusText);
    return response;
  }
  function safeScalar(val) {
    if (val !== undefined && ![ "string", "number", "boolean" ].includes(typeof val)) console.warn(`Operation expects a string, number or boolean, but got ${val} (${typeof val})`);
    return val != null ? val : "";
  }
  function safeString(str) {
    if (str !== undefined && typeof str !== "string") console.warn(`Operation expects a string, but got ${str} (${typeof str})`);
    return str != null ? String(str) : "";
  }
  function safeArray(arr) {
    if (arr !== undefined && !Array.isArray(arr)) console.warn(`Operation expects an array, but got ${arr} (${typeof arr})`);
    return arr != null ? Array.from(arr) : [];
  }
  function safeObject(obj) {
    if (obj !== undefined && typeof obj !== "object") console.warn(`Operation expects an object, but got ${obj} (${typeof obj})`);
    return obj != null ? Object(obj) : {};
  }
  function safeStringOrArray(elem) {
    if (elem !== undefined && !Array.isArray(elem) && typeof elem !== "string") console.warn(`Operation expects an Array or a String, but got ${elem} (${typeof elem})`);
    return elem == null ? "" : Array.isArray(elem) ? Array.from(elem) : String(elem);
  }
  function fragmentToString(fragment) {
    return (new XMLSerializer).serializeToString(fragment);
  }
  // A proxy method to wrap a fetch call in error handling
  
  // * url - the URL to fetch
  // * additionalHeaders - an object of additional headers passed to fetch
  
    async function graciouslyFetch(url, additionalHeaders) {
    try {
      const response = await fetch(url, {
        headers: {
          "X-REQUESTED-WITH": "XmlHttpRequest",
          ...additionalHeaders
        }
      });
      if (response == undefined) return;
      handleErrors(response);
      return response;
    } catch (e) {
      console.error(`Could not fetch ${url}`);
    }
  }
  class BoundedQueue {
    constructor(maxSize) {
      this.maxSize = maxSize;
      this.queue = [];
    }
    push(item) {
      if (this.isFull()) {
        // Remove the oldest item to make space for the new one
        this.shift();
      }
      this.queue.push(item);
    }
    shift() {
      return this.queue.shift();
    }
    isFull() {
      return this.queue.length === this.maxSize;
    }
  }
  var utils =  Object.freeze({
    __proto__: null,
    BoundedQueue: BoundedQueue,
    after: after,
    assignFocus: assignFocus,
    before: before,
    debounce: debounce,
    dispatch: dispatch,
    fragmentToString: fragmentToString,
    getClassNames: getClassNames,
    graciouslyFetch: graciouslyFetch,
    handleErrors: handleErrors,
    isTextInput: isTextInput,
    kebabize: kebabize,
    operate: operate,
    processElements: processElements,
    safeArray: safeArray,
    safeObject: safeObject,
    safeScalar: safeScalar,
    safeString: safeString,
    safeStringOrArray: safeStringOrArray,
    xpathToElement: xpathToElement,
    xpathToElementArray: xpathToElementArray
  });
  // Indicates whether or not we should morph an element via onBeforeElUpdated callback
  // SEE: https://github.com/patrick-steele-idem/morphdom#morphdomfromnode-tonode-options--node
  
    const shouldMorph = operation => (fromEl, toEl) => !shouldMorphCallbacks.map((callback => typeof callback === "function" ? callback(operation, fromEl, toEl) : true)).includes(false)
  // Execute any pluggable functions that modify elements after morphing via onElUpdated callback
  
  ;
  const didMorph = operation => el => {
    didMorphCallbacks.forEach((callback => {
      if (typeof callback === "function") callback(operation, el);
    }));
  };
  const verifyNotMutable = (detail, fromEl, toEl) => {
    // Skip nodes that are equal:
    // https://github.com/patrick-steele-idem/morphdom#can-i-make-morphdom-blaze-through-the-dom-tree-even-faster-yes
    if (!mutableTags[fromEl.tagName] && fromEl.isEqualNode(toEl)) return false;
    return true;
  };
  const verifyNotContentEditable = (detail, fromEl, toEl) => {
    if (fromEl === ActiveElement.element && fromEl.isContentEditable) return false;
    return true;
  };
  const verifyNotPermanent = (detail, fromEl, toEl) => {
    const {permanentAttributeName: permanentAttributeName} = detail;
    if (!permanentAttributeName) return true;
    const permanent = fromEl.closest(`[${permanentAttributeName}]`);
    // only morph attributes on the active non-permanent text input
        if (!permanent && fromEl === ActiveElement.element && isTextInput(fromEl)) {
      const ignore = {
        value: true
      };
      Array.from(toEl.attributes).forEach((attribute => {
        if (!ignore[attribute.name]) fromEl.setAttribute(attribute.name, attribute.value);
      }));
      return false;
    }
    return !permanent;
  };
  const shouldMorphCallbacks = [ verifyNotMutable, verifyNotPermanent, verifyNotContentEditable ];
  const didMorphCallbacks = [];
  var morph_callbacks =  Object.freeze({
    __proto__: null,
    didMorph: didMorph,
    didMorphCallbacks: didMorphCallbacks,
    shouldMorph: shouldMorph,
    shouldMorphCallbacks: shouldMorphCallbacks,
    verifyNotContentEditable: verifyNotContentEditable,
    verifyNotMutable: verifyNotMutable,
    verifyNotPermanent: verifyNotPermanent
  });
  var Operations = {
    // DOM Mutations
    append: operation => {
      processElements(operation, (element => {
        before(element, operation);
        operate(operation, (() => {
          const {html: html, focusSelector: focusSelector} = operation;
          element.insertAdjacentHTML("beforeend", safeScalar(html));
          assignFocus(focusSelector);
        }));
        after(element, operation);
      }));
    },
    graft: operation => {
      processElements(operation, (element => {
        before(element, operation);
        operate(operation, (() => {
          const {parent: parent, focusSelector: focusSelector} = operation;
          const parentElement = document.querySelector(parent);
          if (parentElement) {
            parentElement.appendChild(element);
            assignFocus(focusSelector);
          }
        }));
        after(element, operation);
      }));
    },
    innerHtml: operation => {
      processElements(operation, (element => {
        before(element, operation);
        operate(operation, (() => {
          const {html: html, focusSelector: focusSelector} = operation;
          element.innerHTML = safeScalar(html);
          assignFocus(focusSelector);
        }));
        after(element, operation);
      }));
    },
    insertAdjacentHtml: operation => {
      processElements(operation, (element => {
        before(element, operation);
        operate(operation, (() => {
          const {html: html, position: position, focusSelector: focusSelector} = operation;
          element.insertAdjacentHTML(position || "beforeend", safeScalar(html));
          assignFocus(focusSelector);
        }));
        after(element, operation);
      }));
    },
    insertAdjacentText: operation => {
      processElements(operation, (element => {
        before(element, operation);
        operate(operation, (() => {
          const {text: text, position: position, focusSelector: focusSelector} = operation;
          element.insertAdjacentText(position || "beforeend", safeScalar(text));
          assignFocus(focusSelector);
        }));
        after(element, operation);
      }));
    },
    outerHtml: operation => {
      processElements(operation, (element => {
        const parent = element.parentElement;
        const idx = parent && Array.from(parent.children).indexOf(element);
        before(element, operation);
        operate(operation, (() => {
          const {html: html, focusSelector: focusSelector} = operation;
          element.outerHTML = safeScalar(html);
          assignFocus(focusSelector);
        }));
        after(parent ? parent.children[idx] : document.documentElement, operation);
      }));
    },
    prepend: operation => {
      processElements(operation, (element => {
        before(element, operation);
        operate(operation, (() => {
          const {html: html, focusSelector: focusSelector} = operation;
          element.insertAdjacentHTML("afterbegin", safeScalar(html));
          assignFocus(focusSelector);
        }));
        after(element, operation);
      }));
    },
    remove: operation => {
      processElements(operation, (element => {
        before(element, operation);
        operate(operation, (() => {
          const {focusSelector: focusSelector} = operation;
          element.remove();
          assignFocus(focusSelector);
        }));
        after(document, operation);
      }));
    },
    replace: operation => {
      processElements(operation, (element => {
        const parent = element.parentElement;
        const idx = parent && Array.from(parent.children).indexOf(element);
        before(element, operation);
        operate(operation, (() => {
          const {html: html, focusSelector: focusSelector} = operation;
          element.outerHTML = safeScalar(html);
          assignFocus(focusSelector);
        }));
        after(parent ? parent.children[idx] : document.documentElement, operation);
      }));
    },
    textContent: operation => {
      processElements(operation, (element => {
        before(element, operation);
        operate(operation, (() => {
          const {text: text, focusSelector: focusSelector} = operation;
          element.textContent = safeScalar(text);
          assignFocus(focusSelector);
        }));
        after(element, operation);
      }));
    },
    // Element Property Mutations
    addCssClass: operation => {
      processElements(operation, (element => {
        before(element, operation);
        operate(operation, (() => {
          const {name: name} = operation;
          element.classList.add(...getClassNames([ safeStringOrArray(name) ]));
        }));
        after(element, operation);
      }));
    },
    removeAttribute: operation => {
      processElements(operation, (element => {
        before(element, operation);
        operate(operation, (() => {
          const {name: name} = operation;
          element.removeAttribute(safeString(name));
        }));
        after(element, operation);
      }));
    },
    removeCssClass: operation => {
      processElements(operation, (element => {
        before(element, operation);
        operate(operation, (() => {
          const {name: name} = operation;
          element.classList.remove(...getClassNames([ safeStringOrArray(name) ]));
          if (element.classList.length === 0) element.removeAttribute("class");
        }));
        after(element, operation);
      }));
    },
    setAttribute: operation => {
      processElements(operation, (element => {
        before(element, operation);
        operate(operation, (() => {
          const {name: name, value: value} = operation;
          element.setAttribute(safeString(name), safeScalar(value));
        }));
        after(element, operation);
      }));
    },
    setDatasetProperty: operation => {
      processElements(operation, (element => {
        before(element, operation);
        operate(operation, (() => {
          const {name: name, value: value} = operation;
          element.dataset[safeString(name)] = safeScalar(value);
        }));
        after(element, operation);
      }));
    },
    setProperty: operation => {
      processElements(operation, (element => {
        before(element, operation);
        operate(operation, (() => {
          const {name: name, value: value} = operation;
          if (name in element) element[safeString(name)] = safeScalar(value);
        }));
        after(element, operation);
      }));
    },
    setStyle: operation => {
      processElements(operation, (element => {
        before(element, operation);
        operate(operation, (() => {
          const {name: name, value: value} = operation;
          element.style[safeString(name)] = safeScalar(value);
        }));
        after(element, operation);
      }));
    },
    setStyles: operation => {
      processElements(operation, (element => {
        before(element, operation);
        operate(operation, (() => {
          const {styles: styles} = operation;
          for (let [name, value] of Object.entries(styles)) element.style[safeString(name)] = safeScalar(value);
        }));
        after(element, operation);
      }));
    },
    setValue: operation => {
      processElements(operation, (element => {
        before(element, operation);
        operate(operation, (() => {
          const {value: value} = operation;
          element.value = safeScalar(value);
        }));
        after(element, operation);
      }));
    },
    // DOM Events and Meta-Operations
    dispatchEvent: operation => {
      processElements(operation, (element => {
        before(element, operation);
        operate(operation, (() => {
          const {name: name, detail: detail} = operation;
          dispatch(element, safeString(name), safeObject(detail));
        }));
        after(element, operation);
      }));
    },
    setMeta: operation => {
      before(document, operation);
      operate(operation, (() => {
        const {name: name, content: content} = operation;
        let meta = document.head.querySelector(`meta[name='${name}']`);
        if (!meta) {
          meta = document.createElement("meta");
          meta.name = safeString(name);
          document.head.appendChild(meta);
        }
        meta.content = safeScalar(content);
      }));
      after(document, operation);
    },
    setTitle: operation => {
      before(document, operation);
      operate(operation, (() => {
        const {title: title} = operation;
        document.title = safeScalar(title);
      }));
      after(document, operation);
    },
    // Browser Manipulations
    clearStorage: operation => {
      before(document, operation);
      operate(operation, (() => {
        const {type: type} = operation;
        const storage = type === "session" ? sessionStorage : localStorage;
        storage.clear();
      }));
      after(document, operation);
    },
    go: operation => {
      before(window, operation);
      operate(operation, (() => {
        const {delta: delta} = operation;
        history.go(delta);
      }));
      after(window, operation);
    },
    pushState: operation => {
      before(window, operation);
      operate(operation, (() => {
        const {state: state, title: title, url: url} = operation;
        history.pushState(safeObject(state), safeString(title), safeString(url));
      }));
      after(window, operation);
    },
    redirectTo: operation => {
      before(window, operation);
      operate(operation, (() => {
        let {url: url, action: action, turbo: turbo} = operation;
        action = action || "advance";
        url = safeString(url);
        if (turbo === undefined) turbo = true;
        if (turbo) {
          if (window.Turbo) window.Turbo.visit(url, {
            action: action
          });
          if (window.Turbolinks) window.Turbolinks.visit(url, {
            action: action
          });
          if (!window.Turbo && !window.Turbolinks) window.location.href = url;
        } else {
          window.location.href = url;
        }
      }));
      after(window, operation);
    },
    reload: operation => {
      before(window, operation);
      operate(operation, (() => {
        window.location.reload();
      }));
      after(window, operation);
    },
    removeStorageItem: operation => {
      before(document, operation);
      operate(operation, (() => {
        const {key: key, type: type} = operation;
        const storage = type === "session" ? sessionStorage : localStorage;
        storage.removeItem(safeString(key));
      }));
      after(document, operation);
    },
    replaceState: operation => {
      before(window, operation);
      operate(operation, (() => {
        const {state: state, title: title, url: url} = operation;
        history.replaceState(safeObject(state), safeString(title), safeString(url));
      }));
      after(window, operation);
    },
    scrollIntoView: operation => {
      const {element: element} = operation;
      before(element, operation);
      operate(operation, (() => {
        element.scrollIntoView(operation);
      }));
      after(element, operation);
    },
    setCookie: operation => {
      before(document, operation);
      operate(operation, (() => {
        const {cookie: cookie} = operation;
        document.cookie = safeScalar(cookie);
      }));
      after(document, operation);
    },
    setFocus: operation => {
      const {element: element} = operation;
      before(element, operation);
      operate(operation, (() => {
        assignFocus(element);
      }));
      after(element, operation);
    },
    setStorageItem: operation => {
      before(document, operation);
      operate(operation, (() => {
        const {key: key, value: value, type: type} = operation;
        const storage = type === "session" ? sessionStorage : localStorage;
        storage.setItem(safeString(key), safeScalar(value));
      }));
      after(document, operation);
    },
    // Notifications
    consoleLog: operation => {
      before(document, operation);
      operate(operation, (() => {
        const {message: message, level: level} = operation;
        level && [ "warn", "info", "error" ].includes(level) ? console[level](message) : console.log(message);
      }));
      after(document, operation);
    },
    consoleTable: operation => {
      before(document, operation);
      operate(operation, (() => {
        const {data: data, columns: columns} = operation;
        console.table(data, safeArray(columns));
      }));
      after(document, operation);
    },
    notification: operation => {
      before(document, operation);
      operate(operation, (() => {
        const {title: title, options: options} = operation;
        Notification.requestPermission().then((result => {
          operation.permission = result;
          if (result === "granted") new Notification(safeString(title), safeObject(options));
        }));
      }));
      after(document, operation);
    },
    // Morph operations
    morph: operation => {
      processElements(operation, (element => {
        const {html: html} = operation;
        const template = document.createElement("template");
        template.innerHTML = String(safeScalar(html)).trim();
        operation.content = template.content;
        const parent = element.parentElement;
        const idx = parent && Array.from(parent.children).indexOf(element);
        before(element, operation);
        operate(operation, (() => {
          const {childrenOnly: childrenOnly, focusSelector: focusSelector} = operation;
          morphdom(element, childrenOnly ? template.content : template.innerHTML, {
            childrenOnly: !!childrenOnly,
            onBeforeElUpdated: shouldMorph(operation),
            onElUpdated: didMorph(operation)
          });
          assignFocus(focusSelector);
        }));
        after(parent ? parent.children[idx] : document.documentElement, operation);
      }));
    }
  };
  let operations = Operations;
  const add = newOperations => {
    operations = {
      ...operations,
      ...newOperations
    };
  };
  const addOperations = operations => {
    add(operations);
  };
  const addOperation = (name, operation) => {
    const operations = {};
    operations[name] = operation;
    add(operations);
  };
  var OperationStore = {
    get all() {
      return operations;
    }
  };
  let missingElement = "warn";
  var MissingElement = {
    get behavior() {
      return missingElement;
    },
    set(value) {
      if ([ "warn", "ignore", "event", "exception" ].includes(value)) missingElement = value; else console.warn("Invalid 'onMissingElement' option. Defaulting to 'warn'.");
    }
  };
  const perform = (operations, options = {
    onMissingElement: MissingElement.behavior
  }) => {
    const batches = {};
    operations.forEach((operation => {
      if (!!operation.batch) batches[operation.batch] = batches[operation.batch] ? ++batches[operation.batch] : 1;
    }));
    operations.forEach((operation => {
      const name = operation.operation;
      try {
        if (operation.selector) {
          if (operation.xpath) {
            operation.element = operation.selectAll ? xpathToElementArray(operation.selector) : xpathToElement(operation.selector);
          } else {
            operation.element = operation.selectAll ? document.querySelectorAll(operation.selector) : document.querySelector(operation.selector);
          }
        } else {
          operation.element = document;
        }
        if (operation.element || options.onMissingElement !== "ignore") {
          ActiveElement.set(document.activeElement);
          const cableReadyOperation = OperationStore.all[name];
          if (cableReadyOperation) {
            cableReadyOperation(operation);
            if (!!operation.batch && --batches[operation.batch] === 0) dispatch(document, "cable-ready:batch-complete", {
              batch: operation.batch
            });
          } else {
            console.error(`CableReady couldn't find the "${name}" operation. Make sure you use the camelized form when calling an operation method.`);
          }
        }
      } catch (e) {
        if (operation.element) {
          console.error(`CableReady detected an error in ${name || "operation"}: ${e.message}. If you need to support older browsers make sure you've included the corresponding polyfills. https://docs.stimulusreflex.com/setup#polyfills-for-ie11.`);
          console.error(e);
        } else {
          const warning = `CableReady ${name || ""} operation failed due to missing DOM element for selector: '${operation.selector}'`;
          switch (options.onMissingElement) {
           case "ignore":
            break;

           case "event":
            dispatch(document, "cable-ready:missing-element", {
              warning: warning,
              operation: operation
            });
            break;

           case "exception":
            throw warning;

           default:
            console.warn(warning);
          }
        }
      }
    }));
  };
  const performAsync = (operations, options = {
    onMissingElement: MissingElement.behavior
  }) => new Promise(((resolve, reject) => {
    try {
      resolve(perform(operations, options));
    } catch (err) {
      reject(err);
    }
  }));
  class SubscribingElement extends HTMLElement {
    static get tagName() {
      throw new Error("Implement the tagName() getter in the inheriting class");
    }
    static define() {
      if (!customElements.get(this.tagName)) {
        customElements.define(this.tagName, this);
      }
    }
    disconnectedCallback() {
      if (this.channel) this.channel.unsubscribe();
    }
    createSubscription(consumer, channel, receivedCallback) {
      this.channel = consumer.subscriptions.create({
        channel: channel,
        identifier: this.identifier
      }, {
        received: receivedCallback
      });
    }
    get preview() {
      return document.documentElement.hasAttribute("data-turbolinks-preview") || document.documentElement.hasAttribute("data-turbo-preview");
    }
    get identifier() {
      return this.getAttribute("identifier");
    }
  }
  let consumer;
  const BACKOFF = [ 25, 50, 75, 100, 200, 250, 500, 800, 1e3, 2e3 ];
  const wait = ms => new Promise((resolve => setTimeout(resolve, ms)));
  const getConsumerWithRetry = async (retry = 0) => {
    if (consumer) return consumer;
    if (retry >= BACKOFF.length) {
      throw new Error("Couldn't obtain a Action Cable consumer within 5s");
    }
    await wait(BACKOFF[retry]);
    return await getConsumerWithRetry(retry + 1);
  };
  var CableConsumer = {
    setConsumer(value) {
      consumer = value;
    },
    get consumer() {
      return consumer;
    },
    async getConsumer() {
      return await getConsumerWithRetry();
    }
  };
  class StreamFromElement extends SubscribingElement {
    static get tagName() {
      return "cable-ready-stream-from";
    }
    async connectedCallback() {
      if (this.preview) return;
      const consumer = await CableConsumer.getConsumer();
      if (consumer) {
        this.createSubscription(consumer, "CableReady::Stream", this.performOperations.bind(this));
      } else {
        console.error("The `cable_ready_stream_from` helper cannot connect. You must initialize CableReady with an Action Cable consumer.");
      }
    }
    performOperations(data) {
      if (data.cableReady) perform(data.operations, {
        onMissingElement: this.onMissingElement
      });
    }
    get onMissingElement() {
      const value = this.getAttribute("missing") || MissingElement.behavior;
      // stream_from does not support raising exceptions on missing elements because there's no way to catch them
            if ([ "warn", "ignore", "event" ].includes(value)) return value; else {
        console.warn("Invalid 'missing' attribute. Defaulting to 'warn'.");
        return "warn";
      }
    }
  }
  let debugging = false;
  var Debug = {
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
  const request = (data, blocks) => {
    if (Debug.disabled) return;
    const message = `↑ Updatable request affecting ${blocks.length} element(s): `;
    console.log(message, {
      elements: blocks.map((b => b.element)),
      identifiers: blocks.map((b => b.element.getAttribute("identifier"))),
      data: data
    });
    return message;
  };
  const cancel = (timestamp, reason) => {
    if (Debug.disabled) return;
    const duration = new Date - timestamp;
    const message = `❌ Updatable request canceled after ${duration}ms: ${reason}`;
    console.log(message);
    return message;
  };
  const response = (timestamp, element, urls) => {
    if (Debug.disabled) return;
    const duration = new Date - timestamp;
    const message = `↓ Updatable response: All URLs fetched in ${duration}ms`;
    console.log(message, {
      element: element,
      urls: urls
    });
    return message;
  };
  const morphStart = (timestamp, element) => {
    if (Debug.disabled) return;
    const duration = new Date - timestamp;
    const message = `↻ Updatable morph: starting after ${duration}ms`;
    console.log(message, {
      element: element
    });
    return message;
  };
  const morphEnd = (timestamp, element) => {
    if (Debug.disabled) return;
    const duration = new Date - timestamp;
    const message = `↺ Updatable morph: completed after ${duration}ms`;
    console.log(message, {
      element: element
    });
    return message;
  };
  var Log = {
    request: request,
    cancel: cancel,
    response: response,
    morphStart: morphStart,
    morphEnd: morphEnd
  };
  class AppearanceObserver {
    constructor(delegate, element = null) {
      this.delegate = delegate;
      this.element = element || delegate;
      this.started = false;
      this.intersecting = false;
      this.intersectionObserver = new IntersectionObserver(this.intersect);
    }
    start() {
      if (!this.started) {
        this.started = true;
        this.intersectionObserver.observe(this.element);
        this.observeVisibility();
      }
    }
    stop() {
      if (this.started) {
        this.started = false;
        this.intersectionObserver.unobserve(this.element);
        this.unobserveVisibility();
      }
    }
    observeVisibility=() => {
      document.addEventListener("visibilitychange", this.handleVisibilityChange);
    };
    unobserveVisibility=() => {
      document.removeEventListener("visibilitychange", this.handleVisibilityChange);
    };
    intersect=entries => {
      entries.forEach((entry => {
        if (entry.target === this.element) {
          if (entry.isIntersecting && document.visibilityState === "visible") {
            this.intersecting = true;
            this.delegate.appearedInViewport();
          } else {
            this.intersecting = false;
            this.delegate.disappearedFromViewport();
          }
        }
      }));
    };
    handleVisibilityChange=event => {
      if (document.visibilityState === "visible" && this.intersecting) {
        this.delegate.appearedInViewport();
      } else {
        this.delegate.disappearedFromViewport();
      }
    };
  }
  const template = `\n<style>\n  :host {\n    display: block;\n  }\n</style>\n<slot></slot>\n`;
  class UpdatesForElement extends SubscribingElement {
    static get tagName() {
      return "cable-ready-updates-for";
    }
    constructor() {
      super();
      const shadowRoot = this.attachShadow({
        mode: "open"
      });
      shadowRoot.innerHTML = template;
      this.triggerElementLog = new BoundedQueue(10);
      this.targetElementLog = new BoundedQueue(10);
      this.appearanceObserver = new AppearanceObserver(this);
      this.visible = false;
      this.didTransitionToVisible = false;
    }
    async connectedCallback() {
      if (this.preview) return;
      this.update = debounce(this.update.bind(this), this.debounce);
      const consumer = await CableConsumer.getConsumer();
      if (consumer) {
        this.createSubscription(consumer, "CableReady::Stream", this.update);
      } else {
        console.error("The `cable_ready_updates_for` helper cannot connect. You must initialize CableReady with an Action Cable consumer.");
      }
      if (this.observeAppearance) {
        this.appearanceObserver.start();
      }
    }
    disconnectedCallback() {
      super.disconnectedCallback();
      if (this.observeAppearance) {
        this.appearanceObserver.stop();
      }
    }
    async update(data) {
      this.lastUpdateTimestamp = new Date;
      const blocks = Array.from(document.querySelectorAll(this.query), (element => new Block(element))).filter((block => block.shouldUpdate(data)));
      this.triggerElementLog.push(`${(new Date).toLocaleString()}: ${Log.request(data, blocks)}`);
      if (blocks.length === 0) {
        this.triggerElementLog.push(`${(new Date).toLocaleString()}: ${Log.cancel(this.lastUpdateTimestamp, "All elements filtered out")}`);
        return;
      }
      // first <cable-ready-updates-for> element in the DOM *at any given moment* updates all of the others
      // if the element becomes visible though, we have to overrule and load it
            if (blocks[0].element !== this && !this.didTransitionToVisible) {
        this.triggerElementLog.push(`${(new Date).toLocaleString()}: ${Log.cancel(this.lastUpdateTimestamp, "Update already requested")}`);
        return;
      }
      // hold a reference to the active element so that it can be restored after the morph
            ActiveElement.set(document.activeElement);
      // store all retrieved HTML in an object keyed by URL to minimize fetch calls
            this.html = {};
      const uniqueUrls = [ ...new Set(blocks.map((block => block.url))) ];
      await Promise.all(uniqueUrls.map((async url => {
        if (!this.html.hasOwnProperty(url)) {
          const response = await graciouslyFetch(url, {
            "X-Cable-Ready": "update"
          });
          this.html[url] = await response.text();
        }
      })));
      this.triggerElementLog.push(`${(new Date).toLocaleString()}: ${Log.response(this.lastUpdateTimestamp, this, uniqueUrls)}`);
      // track current block index for each URL; referred to as fragments
            this.index = {};
      blocks.forEach((block => {
        // if the block's URL is not in the index, initialize it to 0; otherwise, increment it
        this.index.hasOwnProperty(block.url) ? this.index[block.url]++ : this.index[block.url] = 0;
        block.process(data, this.html, this.index, this.lastUpdateTimestamp);
      }));
    }
    appearedInViewport() {
      if (!this.visible) {
        // transition from invisible to visible forces update
        this.didTransitionToVisible = true;
        this.update({});
      }
      this.visible = true;
    }
    disappearedFromViewport() {
      this.visible = false;
    }
    get query() {
      return `${this.tagName}[identifier="${this.identifier}"]`;
    }
    get identifier() {
      return this.getAttribute("identifier");
    }
    get debounce() {
      return this.hasAttribute("debounce") ? parseInt(this.getAttribute("debounce")) : 20;
    }
    get observeAppearance() {
      return this.hasAttribute("observe-appearance");
    }
  }
  class Block {
    constructor(element) {
      this.element = element;
    }
    async process(data, html, fragmentsIndex, startTimestamp) {
      const blockIndex = fragmentsIndex[this.url];
      const template = document.createElement("template");
      this.element.setAttribute("updating", "updating");
      template.innerHTML = String(html[this.url]).trim();
      await this.resolveTurboFrames(template.content);
      const fragments = template.content.querySelectorAll(this.query);
      if (fragments.length <= blockIndex) {
        console.warn(`Update aborted due to insufficient number of elements. The offending url is ${this.url}, the offending element is:`, this.element);
        return;
      }
      const operation = {
        element: this.element,
        html: fragments[blockIndex],
        permanentAttributeName: "data-ignore-updates"
      };
      dispatch(this.element, "cable-ready:before-update", operation);
      this.element.targetElementLog.push(`${(new Date).toLocaleString()}: ${Log.morphStart(startTimestamp, this.element)}`);
      morphdom(this.element, fragments[blockIndex], {
        childrenOnly: true,
        onBeforeElUpdated: shouldMorph(operation),
        onElUpdated: _ => {
          this.element.removeAttribute("updating");
          this.element.didTransitionToVisible = false;
          dispatch(this.element, "cable-ready:after-update", operation);
          assignFocus(operation.focusSelector);
        }
      });
      this.element.targetElementLog.push(`${(new Date).toLocaleString()}: ${Log.morphEnd(startTimestamp, this.element)}`);
    }
    async resolveTurboFrames(documentFragment) {
      const reloadingTurboFrames = [ ...documentFragment.querySelectorAll('turbo-frame[src]:not([loading="lazy"])') ];
      return Promise.all(reloadingTurboFrames.map((frame => new Promise((async resolve => {
        const frameResponse = await graciouslyFetch(frame.getAttribute("src"), {
          "Turbo-Frame": frame.id,
          "X-Cable-Ready": "update"
        });
        const frameTemplate = document.createElement("template");
        frameTemplate.innerHTML = await frameResponse.text();
        // recurse here to get all nested eager loaded frames
                await this.resolveTurboFrames(frameTemplate.content);
        const selector = `turbo-frame#${frame.id}`;
        const frameContent = frameTemplate.content.querySelector(selector);
        const content = frameContent ? frameContent.innerHTML.trim() : "";
        documentFragment.querySelector(selector).innerHTML = content;
        resolve();
      })))));
    }
    shouldUpdate(data) {
      // if everything that could prevent an update is false, update this block
      return !this.ignoresInnerUpdates && this.hasChangesSelectedForUpdate(data) && (!this.observeAppearance || this.visible);
    }
    hasChangesSelectedForUpdate(data) {
      // if there's an only attribute, only update if at least one of the attributes changed is in the allow list
      const only = this.element.getAttribute("only");
      return !(only && data.changed && !only.split(" ").some((attribute => data.changed.includes(attribute))));
    }
    get ignoresInnerUpdates() {
      // don't update during a Reflex or Turbolinks redraw
      return this.element.hasAttribute("ignore-inner-updates") && this.element.hasAttribute("performing-inner-update");
    }
    get url() {
      return this.element.hasAttribute("url") ? this.element.getAttribute("url") : location.href;
    }
    get identifier() {
      return this.element.identifier;
    }
    get query() {
      return this.element.query;
    }
    get visible() {
      return this.element.visible;
    }
    get observeAppearance() {
      return this.element.observeAppearance;
    }
  }
  const registerInnerUpdates = () => {
    document.addEventListener("stimulus-reflex:before", (event => {
      recursiveMarkUpdatesForElements(event.detail.element);
    }));
    document.addEventListener("stimulus-reflex:after", (event => {
      setTimeout((() => {
        recursiveUnmarkUpdatesForElements(event.detail.element);
      }));
    }));
    document.addEventListener("turbo:submit-start", (event => {
      recursiveMarkUpdatesForElements(event.target);
    }));
    document.addEventListener("turbo:submit-end", (event => {
      setTimeout((() => {
        recursiveUnmarkUpdatesForElements(event.target);
      }));
    }));
    document.addEventListener("turbo-boost:command:start", (event => {
      recursiveMarkUpdatesForElements(event.target);
    }));
    document.addEventListener("turbo-boost:command:finish", (event => {
      setTimeout((() => {
        recursiveUnmarkUpdatesForElements(event.target);
      }));
    }));
    document.addEventListener("turbo-boost:command:error", (event => {
      setTimeout((() => {
        recursiveUnmarkUpdatesForElements(event.target);
      }));
    }));
  };
  const recursiveMarkUpdatesForElements = leaf => {
    const closestUpdatesFor = leaf && leaf.parentElement && leaf.parentElement.closest("cable-ready-updates-for");
    if (closestUpdatesFor) {
      closestUpdatesFor.setAttribute("performing-inner-update", "");
      recursiveMarkUpdatesForElements(closestUpdatesFor);
    }
  };
  const recursiveUnmarkUpdatesForElements = leaf => {
    const closestUpdatesFor = leaf && leaf.parentElement && leaf.parentElement.closest("cable-ready-updates-for");
    if (closestUpdatesFor) {
      closestUpdatesFor.removeAttribute("performing-inner-update");
      recursiveUnmarkUpdatesForElements(closestUpdatesFor);
    }
  };
  const defineElements = () => {
    registerInnerUpdates();
    StreamFromElement.define();
    UpdatesForElement.define();
  };
  const initialize = (initializeOptions = {}) => {
    const {consumer: consumer, onMissingElement: onMissingElement, debug: debug} = initializeOptions;
    Debug.set(!!debug);
    if (consumer) {
      CableConsumer.setConsumer(consumer);
    } else {
      console.error("CableReady requires a reference to your Action Cable `consumer` for its helpers to function.\nEnsure that you have imported the `CableReady` package as well as `consumer` from your `channels` folder, then call `CableReady.initialize({ consumer })`.");
    }
    if (onMissingElement) {
      MissingElement.set(onMissingElement);
    }
    defineElements();
  };
  const global = {
    perform: perform,
    performAsync: performAsync,
    shouldMorphCallbacks: shouldMorphCallbacks,
    didMorphCallbacks: didMorphCallbacks,
    initialize: initialize,
    addOperation: addOperation,
    addOperations: addOperations,
    version: packageInfo.version,
    cable: CableConsumer,
    get DOMOperations() {
      console.warn("DEPRECATED: Please use `CableReady.operations` instead of `CableReady.DOMOperations`");
      return OperationStore.all;
    },
    get operations() {
      return OperationStore.all;
    },
    get consumer() {
      return CableConsumer.consumer;
    }
  };
  window.CableReady = global;
  exports.MorphCallbacks = morph_callbacks;
  exports.StreamFromElement = StreamFromElement;
  exports.SubscribingElement = SubscribingElement;
  exports.UpdatesForElement = UpdatesForElement;
  exports.Utils = utils;
  exports.default = global;
  Object.defineProperty(exports, "__esModule", {
    value: true
  });
}));
