(() => {
  if (window.__ocvApi && typeof window.__ocvApi.ensure === "function") {
    window.__ocvApi.ensure();
    return window.__ocvApi.count();
  }
  const ACTION = "__OCV_ACTION__:toggle";
  const MIC_SVG =
    '<path d="M10 2.8c-1.55 0-2.8 1.25-2.8 2.8v4.4c0 1.55 1.25 2.8 2.8 2.8s2.8-1.25 2.8-2.8V5.6c0-1.55-1.25-2.8-2.8-2.8Z" stroke="currentColor" stroke-width="1.5" fill="none"/><path d="M4.9 9.4v.6c0 2.8 2.3 5.1 5.1 5.1s5.1-2.3 5.1-5.1v-.6" stroke="currentColor" stroke-width="1.5" fill="none" stroke-linecap="round"/><path d="M10 15.1v2.1" stroke="currentColor" stroke-width="1.5" fill="none" stroke-linecap="round"/><path d="M7.6 17.2h4.8" stroke="currentColor" stroke-width="1.5" fill="none" stroke-linecap="round"/>';
  const STRIP_ATTRS = [
    "data-icon",
    "data-state",
    "data-closed",
    "data-expanded",
    "data-highlighted",
    "data-selected",
    "data-disabled",
    "icon",
    "id",
    "aria-haspopup",
    "aria-expanded",
    "aria-controls",
    "aria-disabled",
    "disabled",
    "tabindex",
    "style",
  ];
  const buttons = new Set();
  let state = "idle";
  let animation = null;
  let lastHealth = "";
  let reportCount = 0;
  let chip = null;

  function ensureStyle() {
    if (document.getElementById("ocv-style")) return;
    const s = document.createElement("style");
    s.id = "ocv-style";
    s.textContent =
      "@keyframes ocv-pulse{0%,100%{opacity:1;transform:scale(1)}50%{opacity:.3;transform:scale(.7)}}";
    document.head.appendChild(s);
  }

  function leftGroupOf(attach, send) {
    if (!attach || !send) return null;
    let el = attach;
    while (el && el.parentElement && !el.parentElement.contains(send)) el = el.parentElement;
    return el && !el.contains(send) ? el : null;
  }

  function applyChipTheme(el) {
    const model = document.querySelector('[data-action="prompt-model"]');
    if (!model) return false;
    const cls = (model.getAttribute("class") || "")
      .split(/\s+/)
      .filter((c) => c && !/animate-in|fade-in|^group$|group\//.test(c));
    if (cls.length) el.setAttribute("class", cls.join(" "));
    for (const name of ["data-component", "data-size", "data-variant"]) {
      if (model.hasAttribute(name)) el.setAttribute(name, model.getAttribute(name));
    }
    return true;
  }

  function buildChip() {
    const el = document.createElement("span");
    el.setAttribute("data-ocv-chip", "1");
    const base = "height:28px;display:none;pointer-events:none;flex:0 0 auto;align-items:center;gap:6px;font-size:13px;min-width:0;";
    el.style.cssText = applyChipTheme(el) ? base : base + "padding:0 8px;border-radius:6px;";
    const dot = document.createElement("span");
    dot.style.cssText = "width:8px;height:8px;border-radius:50%;background:#f43f5e;flex:0 0 8px;";
    const label = document.createElement("span");
    label.style.cssText = "white-space:nowrap;line-height:1;";
    el.appendChild(dot);
    el.appendChild(label);
    el.__dot = dot;
    el.__label = label;
    return el;
  }

  function updateChip() {
    if (!chip) return;
    if (state === "listening") {
      chip.__dot.style.background = "#f43f5e";
      chip.__dot.style.animation = "ocv-pulse 1.2s ease-in-out infinite";
      chip.__label.textContent = "正在聆听";
      chip.style.display = "";
    } else if (state === "transcribing") {
      chip.__dot.style.background = "#f59e0b";
      chip.__dot.style.animation = "ocv-pulse 0.8s ease-in-out infinite";
      chip.__label.textContent = "识别中…";
      chip.style.display = "";
    } else {
      chip.style.display = "none";
    }
  }

  function ensureChip(send) {
    const attach = document.querySelector('[data-action="prompt-attach"]');
    const group = leftGroupOf(attach, send);
    if (!group) return;
    ensureStyle();
    if (!chip) chip = buildChip();
    else if (!chip.hasAttribute("data-component") && document.querySelector('[data-action="prompt-model"]')) {
      const fresh = buildChip();
      try {
        chip.replaceWith(fresh);
      } catch {}
      chip = fresh;
    }
    if (chip.parentElement !== group || group.lastElementChild !== chip) group.appendChild(chip);
    updateChip();
  }

  function report(tag, data) {
    if (reportCount > 200) return;
    reportCount++;
    try {
      console.log("__OCV_LOG__:" + JSON.stringify({ tag, ...(data || {}) }));
    } catch {}
  }

  function healthOf(btn) {
    if (!btn) return { found: false };
    const svg = btn.querySelector("svg");
    const cs = getComputedStyle(btn);
    const scs = svg ? getComputedStyle(svg) : null;
    const r = btn.getBoundingClientRect();
    return {
      found: true,
      hasMic: hasMicIcon(btn),
      svgCount: btn.querySelectorAll("svg").length,
      svgLen: svg ? svg.innerHTML.length : 0,
      svgDisplay: scs ? scs.display : null,
      svgVisibility: scs ? scs.visibility : null,
      color: cs.color,
      bg: cs.backgroundColor,
      bgImage: cs.backgroundImage === "none" ? null : cs.backgroundImage.slice(0, 60),
      rect: [Math.round(r.x), Math.round(r.y), Math.round(r.width), Math.round(r.height)],
      submitIcon: (() => {
        const s = document.querySelector('[data-action="prompt-submit"]');
        return s ? s.getAttribute("data-icon") : null;
      })(),
    };
  }

  function deco(btn) {
    btn.style.borderRadius = "8px";
    btn.style.marginRight = "10px";
    if (state === "listening") {
      btn.style.color = "#f43f5e";
      btn.style.boxShadow = "0 0 0 2px rgba(244,63,94,0.35)";
      if (!animation && btn.animate) {
        try {
          animation = btn.animate([{ opacity: 1 }, { opacity: 0.45 }, { opacity: 1 }], {
            duration: 1100,
            iterations: Infinity,
          });
        } catch {}
      }
    } else if (state === "transcribing") {
      btn.style.color = "#f59e0b";
      btn.style.boxShadow = "";
      if (animation) {
        try {
          animation.cancel();
        } catch {}
        animation = null;
      }
    } else {
      btn.style.color = "";
      btn.style.boxShadow = "none";
      if (animation) {
        try {
          animation.cancel();
        } catch {}
        animation = null;
      }
    }
  }

  function hasMicIcon(btn) {
    return !!btn.querySelector('svg path[d^="M10 2.8"]');
  }

  function paintIcon(btn, ref) {
    let svg = btn.querySelector("svg");
    if (!svg) {
      svg = document.createElementNS("http://www.w3.org/2000/svg", "svg");
      const refSvg = ref && ref.querySelector("svg");
      if (refSvg) {
        const cls = refSvg.getAttribute("class");
        if (cls) svg.setAttribute("class", cls);
      }
      btn.appendChild(svg);
    }
    svg.setAttribute("viewBox", "0 0 20 20");
    svg.setAttribute("fill", "none");
    svg.removeAttribute("data-slot");
    svg.removeAttribute("style");
    svg.innerHTML = MIC_SVG;
  }

  function build(attach, send) {
    const src = attach || send;
    const btn = src.cloneNode(true);
    for (const name of STRIP_ATTRS) btn.removeAttribute(name);
    btn.setAttribute("type", "button");
    btn.setAttribute("data-action", "ocv-voice");
    btn.setAttribute("aria-label", "语音输入");
    btn.setAttribute("title", "语音输入 (Ctrl+Alt+Space)");
    btn.dataset.ocv = "1";
    if (!attach) btn.style.background = "transparent";
    paintIcon(btn, src);
    btn.addEventListener("mousedown", (event) => {
      event.preventDefault();
      event.stopPropagation();
    });
    btn.addEventListener("click", (event) => {
      event.preventDefault();
      event.stopPropagation();
      try {
        console.log(ACTION);
      } catch {}
    });
    return btn;
  }

  function ensure() {
    const sends = Array.from(document.querySelectorAll('[data-action="prompt-submit"]'));
    const send = sends.find((el) => el.offsetParent !== null) || sends[0] || null;
    const all = Array.from(document.querySelectorAll('[data-action="ocv-voice"]'));
    const keep =
      all.find((el) => el.dataset && el.dataset.ocv === "1" && hasMicIcon(el)) ||
      all.find((el) => el.dataset && el.dataset.ocv === "1") ||
      all[0] ||
      null;
    for (const el of all) {
      if (el === keep) continue;
      try {
        el.remove();
      } catch {}
    }
    buttons.clear();
    if (!send || !send.parentElement) {
      if (keep) buttons.add(keep);
      return buttons.size;
    }
    const parent = send.parentElement;
    let btn = keep;
    let rebuilt = false;
    if (!btn) {
      btn = build(parent.querySelector('[data-action="prompt-attach"]'), send);
      rebuilt = true;
    }
    if (!hasMicIcon(btn)) paintIcon(btn, parent.querySelector('[data-action="prompt-attach"]') || send);
    btn.classList.remove("shadow-[var(--v2-elevation-button-contrast)]");
    btn.setAttribute("data-action", "ocv-voice");
    btn.dataset.ocv = "1";
    if (send.previousElementSibling !== btn) parent.insertBefore(btn, send);
    buttons.add(btn);
    deco(btn);
    ensureChip(send);
    const health = healthOf(btn);
    const sig = JSON.stringify(health);
    if (rebuilt) {
      report("rebuild", {
        health,
        fromAttach: !!parent.querySelector('[data-action="prompt-attach"]'),
      });
    }
    if (sig !== lastHealth) {
      report("health-change", { health });
      lastHealth = sig;
    }
    return buttons.size;
  }

  function setState(next) {
    state = next || "idle";
    for (const btn of buttons) deco(btn);
    updateChip();
    return state;
  }

  let scheduled = false;
  function scheduleEnsure() {
    if (scheduled) return;
    scheduled = true;
    setTimeout(() => {
      scheduled = false;
      try {
        ensure();
      } catch {}
    }, 80);
  }

  try {
    const observer = new MutationObserver(scheduleEnsure);
    observer.observe(document.documentElement, {
      childList: true,
      subtree: true,
      attributes: true,
      attributeFilter: ["data-action", "data-icon", "icon"],
    });
  } catch {}

  window.__ocvSetState = setState;
  window.__ocvApi = {
    ensure,
    setState,
    count: () => buttons.size,
    state: () => state,
  };
  setInterval(() => {
    try {
      ensure();
    } catch {}
  }, 1500);
  return ensure();
})();
