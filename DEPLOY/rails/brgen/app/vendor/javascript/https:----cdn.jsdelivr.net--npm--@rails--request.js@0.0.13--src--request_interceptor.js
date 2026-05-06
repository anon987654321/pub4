// https://cdn.jsdelivr.net/npm/@rails/request.js@0.0.13/src/request_interceptor@0.0.13 downloaded from https://cdn.jsdelivr.net/npm/@rails/request.js@0.0.13/src/request_interceptor.js

export class RequestInterceptor {
  static register (interceptor) {
    this.interceptor = interceptor
  }

  static get () {
    return this.interceptor
  }

  static reset () {
    this.interceptor = undefined
  }
}
