// Sound effects (the same WAV files as the iPhone app) and vibration.

const EFFECTS = ['star', 'fuel', 'key', 'door', 'crash', 'land', 'click', 'bump', 'lowfuel'];

class SoundManager {
  constructor() {
    this.enabled = true;
    this.ctx = null;
    this.buffers = new Map();
    this.thrustSource = null;
    this.thrustGain = null;
    this.thrustOn = false;
    this.loading = null;
  }

  /** Browsers only allow audio after a tap, so this is called from the first one. */
  unlock() {
    const AC = globalThis.AudioContext || globalThis.webkitAudioContext;
    if (!AC) return;
    if (!this.ctx) {
      this.ctx = new AC();
      this.master = this.ctx.createGain();
      this.master.connect(this.ctx.destination);
      this.loading = Promise.all([...EFFECTS, 'thrust'].map((name) => this.load(name)));
    }
    if (this.ctx.state === 'suspended') this.ctx.resume().catch(() => {});
  }

  async load(name) {
    try {
      const res = await fetch(`sounds/${name}.wav`);
      const data = await res.arrayBuffer();
      const buffer = await new Promise((resolve, reject) => this.ctx.decodeAudioData(data, resolve, reject));
      this.buffers.set(name, buffer);
    } catch {
      // A missing sound must never break the game.
    }
  }

  play(name, volume = 1) {
    if (!this.enabled || !this.ctx || this.ctx.state !== 'running') return;
    const buffer = this.buffers.get(name);
    if (!buffer) return;
    const src = this.ctx.createBufferSource();
    src.buffer = buffer;
    const gain = this.ctx.createGain();
    gain.gain.value = Math.max(0, Math.min(1, volume));
    src.connect(gain).connect(this.master);
    src.start();
  }

  setThrust(on) {
    const wanted = on && this.enabled && !!this.ctx;
    if (wanted === this.thrustOn) return;
    this.thrustOn = wanted;
    if (!this.ctx) return;
    const buffer = this.buffers.get('thrust');
    if (!buffer) return;
    const now = this.ctx.currentTime;
    if (wanted) {
      if (!this.thrustSource) {
        this.thrustGain = this.ctx.createGain();
        this.thrustGain.gain.value = 0;
        this.thrustGain.connect(this.master);
        this.thrustSource = this.ctx.createBufferSource();
        this.thrustSource.buffer = buffer;
        this.thrustSource.loop = true;
        this.thrustSource.connect(this.thrustGain);
        this.thrustSource.start();
      }
      this.thrustGain.gain.cancelScheduledValues(now);
      this.thrustGain.gain.setTargetAtTime(0.5, now, 0.02);
    } else if (this.thrustGain) {
      this.thrustGain.gain.cancelScheduledValues(now);
      this.thrustGain.gain.setTargetAtTime(0, now, 0.04);
    }
  }

  stopAll() {
    this.setThrust(false);
  }
}

export const sound = new SoundManager();

export const haptics = {
  enabled: true,
  buzz(ms) {
    if (this.enabled && navigator.vibrate) {
      try { navigator.vibrate(ms); } catch { /* not supported */ }
    }
  },
  light() { this.buzz(8); },
  medium() { this.buzz(15); },
  heavy() { this.buzz(35); },
  impact(v) { this.buzz(Math.round(8 + 25 * Math.max(0.2, Math.min(1, v)))); },
  success() { this.buzz([12, 60, 18]); },
  failure() { this.buzz([30, 50, 30]); },
};
