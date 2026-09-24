/**
 * PixelDiffEngine
 * Implements the 'Measure' part of the Render-Measure-Refine loop.
 * Captures WebGL output and computes deltas against a target layout.
 */
export class PixelDiffEngine {
  constructor(renderer) {
    this.renderer = renderer;
    this.captureCanvas = document.createElement('canvas');
    this.ctx = this.captureCanvas.getContext('2d', { willReadFrequently: true });
  }

  /**
   * Captures the current frame from the WebGL renderer.
   * @returns {ImageData}
   */
  capture() {
    const element = this.renderer.renderer.domElement;
    const width = element.width;
    const height = element.height;

    this.captureCanvas.width = width;
    this.captureCanvas.height = height;

    // Copy WebGL buffer to 2D canvas
    this.ctx.drawImage(element, 0, 0);
    return this.ctx.getImageData(0, 0, width, height);
  }

  /**
   * Compares two frames and returns a concrete delta.
   * @param {ImageData} current
   * @param {ImageData} target
   * @returns {Object} { ratio, rmse, diffCount }
   */
  compare(current, target) {
    if (current.width !== target.width || current.height !== target.height) {
      return { ratio: 1.0, rmse: 1.0, diffCount: -1, error: "dimension_mismatch" };
    }

    const data1 = current.data;
    const data2 = target.data;
    let diffCount = 0;
    let totalSqDiff = 0;

    for (let i = 0; i < data1.length; i += 4) {
      const rDiff = data1[i] - data2[i];
      const gDiff = data1[i + 1] - data2[i + 1];
      const bDiff = data1[i + 2] - data2[i + 2];
      const distSq = rDiff * rDiff + gDiff * gDiff + bDiff * bDiff;

      // Threshold of 16 (4^2) to ignore sub-perceptual noise/compression
      if (distSq > 16) {
        diffCount++;
        totalSqDiff += distSq;
      }
    }

    const pixelCount = current.width * current.height;
    return {
      ratio: diffCount / pixelCount,
      rmse: Math.sqrt(totalSqDiff / pixelCount),
      diffCount
    };
  }
}
