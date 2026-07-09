import CableReady from "cable_ready";

const debounceEvents = (callback, delay = 20) => {
  let timeoutId;
  let events = [];
  return (...args) => {
    clearTimeout(timeoutId);
    events = [ ...events, ...args ];
    timeoutId = setTimeout((() => {
      timeoutId = null;
      callback(events);
      events = [];
    }), delay);
  };
};

const createSubscription = consumer => {
  consumer.subscriptions.create("Futurism::Channel", {
    connected() {
      window.Futurism = {
        subscription: this
      };
      document.addEventListener("futurism:appear", debounceEvents((events => {
        this.send({
          signed_params: events.map((e => e.target.dataset.signedParams)),
          sgids: events.map((e => e.target.dataset.sgid)),
          signed_controllers: events.map((e => e.target.dataset.signedController)),
          urls: events.map((_ => window.location.href)),
          broadcast_each: events.map((e => e.target.dataset.broadcastEach))
        });
      })));
    },
    received(data) {
      if (data.cableReady) {
        CableReady.perform(data.operations, {
          emitMissingElementWarnings: false
        });
        document.dispatchEvent(new CustomEvent("futurism:appeared", {
          bubbles: true,
          cancelable: true
        }));
      }
    }
  });
};

const dispatchAppearEvent = (entry, observer = null) => {
  if (!window.Futurism?.subscription) {
    return () => {
      setTimeout((() => dispatchAppearEvent(entry, observer)()), 1);
    };
  }
  const target = entry.target ? entry.target : entry;
  const evt = new CustomEvent("futurism:appear", {
    bubbles: true,
    detail: {
      target: target,
      observer: observer
    }
  });
  return () => {
    target.dispatchEvent(evt);
  };
};

const wait = ms => new Promise((resolve => setTimeout(resolve, ms)));

const callWithRetry = async (fn, depth = 0) => {
  try {
    return await fn();
  } catch (e) {
    if (depth > 10) {
      throw e;
    }
    await wait(1.15 ** depth * 2e3);
    return callWithRetry(fn, depth + 1);
  }
};

const observerCallback = (entries, observer) => {
  entries.forEach((async entry => {
    if (!entry.isIntersecting) return;
    await callWithRetry(dispatchAppearEvent(entry, observer));
  }));
};

const extendElementWithIntersectionObserver = element => {
  Object.assign(element, {
    observer: new IntersectionObserver(observerCallback.bind(element), {})
  });
  if (!element.hasAttribute("keep")) {
    element.observer.observe(element);
  }
};

const extendElementWithEagerLoading = element => {
  if (element.dataset.eager === "true") {
    if (element.observer) element.observer.disconnect();
    callWithRetry(dispatchAppearEvent(element));
  }
};

class FuturismElement extends HTMLElement {
  connectedCallback() {
    extendElementWithIntersectionObserver(this);
    extendElementWithEagerLoading(this);
  }
}

class FuturismTableRow extends HTMLTableRowElement {
  connectedCallback() {
    extendElementWithIntersectionObserver(this);
    extendElementWithEagerLoading(this);
  }
}

class FuturismLI extends HTMLLIElement {
  connectedCallback() {
    extendElementWithIntersectionObserver(this);
    extendElementWithEagerLoading(this);
  }
}

async function sha256(message) {
  const msgBuffer = new TextEncoder("utf-8").encode(message);
  const hashBuffer = await crypto.subtle.digest("SHA-256", msgBuffer);
  const hashArray = Array.from(new Uint8Array(hashBuffer));
  const hashHex = hashArray.map((b => ("00" + b.toString(16)).slice(-2))).join("");
  return hashHex;
}

const polyfillCustomElements = () => {
  const isSafari = /^((?!chrome|android).)*safari/i.test(navigator.userAgent);
  if (customElements) {
    if (isSafari) {
      document.write('<script src="//unpkg.com/@ungap/custom-elements-builtin"><\/script>');
    } else {
      try {
        customElements.define("built-in", document.createElement("tr").constructor, {
          extends: "tr"
        });
      } catch (_) {
        document.write('<script src="//unpkg.com/@ungap/custom-elements-builtin"><\/script>');
      }
    }
  } else {
    document.write('<script src="//unpkg.com/document-register-element"><\/script>');
  }
};

const defineElements = e => {
  if (!customElements.get("futurism-element")) {
    customElements.define("futurism-element", FuturismElement);
    customElements.define("futurism-table-row", FuturismTableRow, {
      extends: "tr"
    });
    customElements.define("futurism-li", FuturismLI, {
      extends: "li"
    });
  }
};

const cachePlaceholders = e => {
  sha256(e.detail.element.outerHTML).then((hashedContent => {
    e.detail.element.setAttribute("keep", "");
    sessionStorage.setItem(`futurism-${hashedContent}`, e.detail.element.outerHTML);
    e.target.dataset.futurismHash = hashedContent;
  }));
};

const restorePlaceholders = e => {
  if (sessionStorage.getItem("requested-turbo-frame")) {
    delete sessionStorage.removeItem("requested-turbo-frame");
    return;
  }
  const inNamespace = ([key, _payload]) => key.startsWith("futurism-");
  Object.entries(sessionStorage).filter(inNamespace).forEach((([key, payload]) => {
    const match = /^futurism-(.*)/.exec(key);
    const targetElement = document.querySelector(`[data-futurism-hash="${match[1]}"]`);
    if (targetElement) {
      targetElement.outerHTML = payload;
      sessionStorage.removeItem(key);
    }
  }));
};

const storeRequestedTurboFrame = e => {
  const {headers: headers} = e.detail.fetchOptions;
  if (!headers["Turbo-Frame"] || headers["X-Sec-Purpose"] === "prefetch") return;
  sessionStorage.setItem("requested-turbo-frame", headers["Turbo-Frame"]);
};

const initializeElements = () => {
  polyfillCustomElements();
  document.addEventListener("DOMContentLoaded", defineElements);
  document.addEventListener("turbo:load", defineElements);
  document.addEventListener("turbo:before-cache", restorePlaceholders);
  document.addEventListener("turbolinks:load", defineElements);
  document.addEventListener("turbolinks:before-cache", restorePlaceholders);
  document.addEventListener("cable-ready:after-outer-html", cachePlaceholders);
  document.addEventListener("turbo:before-fetch-request", storeRequestedTurboFrame);
};

export { createSubscription, initializeElements };
