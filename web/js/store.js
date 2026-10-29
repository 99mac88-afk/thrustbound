// Saved progress and settings (localStorage, guarded: private mode may refuse it).

export const storage = {
  get(key, fallback = null) {
    try {
      const v = localStorage.getItem(key);
      return v === null ? fallback : JSON.parse(v);
    } catch {
      return fallback;
    }
  },
  set(key, value) {
    try {
      localStorage.setItem(key, JSON.stringify(value));
      return true;
    } catch {
      return false;
    }
  },
  remove(key) {
    try { localStorage.removeItem(key); } catch { /* ignore */ }
  },
};

const SETTINGS = 'tb.settings.v1';
const RECORDS = 'tb.records.v1';

const defaults = { sound: true, haptics: true, swap: false, unlockAll: false, language: 'system' };

export class Progress {
  constructor(levels) {
    this.levels = levels;
    this.settings = { ...defaults, ...(storage.get(SETTINGS, {}) || {}) };
    this.records = storage.get(RECORDS, {}) || {};
  }

  saveSettings() { storage.set(SETTINGS, this.settings); }

  record(index) {
    const l = this.levels[index];
    return l ? this.records[l.id] || null : null;
  }

  isUnlocked(index) {
    if (index < 0 || index >= this.levels.length) return false;
    if (this.settings.unlockAll || index === 0) return true;
    if (this.records[this.levels[index].id]) return true;
    return !!this.records[this.levels[index - 1].id];
  }

  get totalStars() { return Object.values(this.records).reduce((s, r) => s + r.stars, 0); }
  get maxStars() { return this.levels.length * 3; }
  get completedCount() { return Object.keys(this.records).length; }
  get hasProgress() { return Object.keys(this.records).length > 0; }

  get continueIndex() {
    for (let i = 0; i < this.levels.length; i++) if (!this.record(i) && this.isUnlocked(i)) return i;
    return Math.max(0, this.levels.length - 1);
  }

  recordWin(index, stars, time) {
    const l = this.levels[index];
    if (!l) return { newBestStars: false, newBestTime: false, firstClear: false };
    const old = this.records[l.id] || null;
    const rec = old ? { ...old } : { stars, bestTime: time };
    const newStars = !old || stars > rec.stars;
    const newTime = !old || time < rec.bestTime;
    if (newStars) rec.stars = stars;
    if (newTime) rec.bestTime = time;
    this.records[l.id] = rec;
    storage.set(RECORDS, this.records);
    return { newBestStars: newStars && !!old, newBestTime: newTime && !!old, firstClear: !old };
  }

  reset() {
    this.records = {};
    storage.set(RECORDS, this.records);
  }
}
