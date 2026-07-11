// @stimulus-components/content-loader@5.0.0 downloaded from https://unpkg.com/@stimulus-components/content-loader@5.0.0/dist/stimulus-content-loader.mjs

import { Controller } from "@hotwired/stimulus";
const _ContentLoader = class _ContentLoader extends Controller {
  connect() {
    if (!this.hasUrlValue) {
      console.error("[stimulus-content-loader] You need to pass an url to fetch the remote content.");
      return;
    }
    this.hasLazyLoadingValue ? this.lazyLoad() : this.load();
  }
  disconnect() {
    this.stopRefreshing();
  }
  load() {
    this.fetch(), this.hasRefreshIntervalValue && this.startRefreshing();
  }
  lazyLoad() {
    const options = {
      threshold: this.lazyLoadingThresholdValue,
      rootMargin: this.lazyLoadingRootMarginValue
    };
    new IntersectionObserver(
      (entries, observer2) => {
        entries.forEach((entry) => {
          entry.isIntersecting && (this.load(), observer2.unobserve(entry.target));
        });
      },
      options
    ).observe(this.element);
  }
  fetch() {
    fetch(this.urlValue).then((response) => {
      if (!response.ok)
        throw new Error(response.statusText);
      return response.text();
    }).then((html) => {
      this.element.innerHTML = html, this.loadScriptsValue && this.loadScripts(), this.dispatch("success");
    }).catch((error) => {
      this.dispatch("error", { detail: { error } });
    });
  }
  startRefreshing() {
    this.refreshTimer = setInterval(() => {
      this.fetch();
    }, this.refreshIntervalValue);
  }
  stopRefreshing() {
    this.refreshTimer && clearInterval(this.refreshTimer);
  }
  loadScripts() {
    this.element.querySelectorAll("script").forEach((content) => {
      const script = document.createElement("script");
      script.innerHTML = content.innerHTML, document.head.appendChild(script).parentNode.removeChild(script);
    });
  }
};
_ContentLoader.values = {
  url: String,
  lazyLoading: Boolean,
  lazyLoadingThreshold: Number,
  lazyLoadingRootMargin: {
    type: String,
    default: "0px"
  },
  refreshInterval: Number,
  loadScripts: Boolean
};
let ContentLoader = _ContentLoader;
export {
  ContentLoader as default
};
