// Slowly drifting star field behind the menus (StarfieldBackground in SwiftUI).
export class MenuBackground {
  constructor(canvas) {
    this.canvas = canvas;
    this.ctx = canvas.getContext('2d');
    let seed = 3;
    const rnd = () => { seed = (seed * 16807) % 2147483647; return seed / 2147483647; };
    this.stars = Array.from({ length: 150 }, () => ({ x: rnd(), y: rnd(), r: 0.5 + rnd() * 1.4, speed: 0.008 + rnd() * 0.042, alpha: 0.25 + rnd() * 0.7 }));
    this.active = false;
    this.resize = () => this.layout();
    window.addEventListener('resize', this.resize);
    this.layout();
  }

  layout() {
    this.dpr = Math.min(window.devicePixelRatio || 1, 2);
    this.w = window.innerWidth;
    this.h = window.innerHeight;
    this.canvas.width = Math.round(this.w * this.dpr);
    this.canvas.height = Math.round(this.h * this.dpr);
  }

  setActive(on) {
    if (on === this.active) return;
    this.active = on;
    this.canvas.style.display = on ? 'block' : 'none';
    if (on) {
      const frame = (ts) => {
        if (!this.active) return;
        this.draw(ts / 1000);
        this.raf = requestAnimationFrame(frame);
      };
      this.raf = requestAnimationFrame(frame);
    } else {
      cancelAnimationFrame(this.raf);
    }
  }

  draw(t) {
    const { ctx, w, h } = this;
    ctx.setTransform(this.dpr, 0, 0, this.dpr, 0, 0);
    const g = ctx.createLinearGradient(0, 0, 0, h);
    g.addColorStop(0, '#040714');
    g.addColorStop(1, '#0C1A3A');
    ctx.fillStyle = g;
    ctx.fillRect(0, 0, w, h);
    ctx.fillStyle = '#FFFFFF';
    for (const s of this.stars) {
      const y = ((s.y + t * s.speed) % 1) * h;
      ctx.globalAlpha = s.alpha;
      ctx.beginPath();
      ctx.arc(s.x * w, y, s.r, 0, Math.PI * 2);
      ctx.fill();
    }
    ctx.globalAlpha = 1;
  }
}
