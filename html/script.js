/* =============================================================================
   COREX :: Skill Tree NUI
   Server is authoritative. We render whatever state arrives via postMessage.
   ============================================================================= */

(function () {
  "use strict";

  // ---------- NUI plumbing ----------
  function getResourceName() {
    if (getResourceName._cached) return getResourceName._cached;
    if (window.location && window.location.hostname &&
        window.location.hostname.indexOf("cfx-nui-") === 0) {
      getResourceName._cached = window.location.hostname.replace("cfx-nui-", "");
    } else {
      getResourceName._cached = "corex-skills";
    }
    return getResourceName._cached;
  }

  function nuiFetch(endpoint, payload) {
    return fetch("https://" + getResourceName() + "/" + endpoint, {
      method: "POST",
      headers: { "Content-Type": "application/json; charset=UTF-8" },
      body: JSON.stringify(payload || {})
    }).catch(function () {});
  }

  // ---------- defaults (overridden by Lua payload) ----------
  var DEFAULT_COLORS = {
    combat:    { primary: "#DC2626", icon: "#FCA5A5" },
    survivor:  { primary: "#10B981", icon: "#6EE7B7" },
    craftsman: { primary: "#F59E0B", icon: "#FCD34D" },
    core:      { primary: "#FFFFFF", icon: "#FFFFFF" }
  };

  var DEFAULT_LAYOUT = {
    VBW: 1360, VBH: 620,
    BRANCH_OFFSET: 90,
    PATH_X: { combat: 340, survivor: 680, craftsman: 1020 },
    TIER_Y: { root: 555, 1: 465, 2: 375, 3: 285, 4: 195, cap: 105 }
  };

  // ---------- runtime state ----------
  var state = {
    skills: [],
    byId: {},
    unlocked: new Set(),
    points: 0,
    xp: 0,
    xpTotal: 0,
    xpPerPoint: 100,
    modifiers: null,
    selected: null,
    colors: DEFAULT_COLORS,
    layout: DEFAULT_LAYOUT,
    player: { name: "Survivor", level: 1 },
    config: { allowRespec: true }
  };

  // ---------- DOM ----------
  var rootEl       = document.getElementById("skills-root");
  var svgEl        = document.getElementById("tree");
  var detailEl     = document.getElementById("detail");
  var pointsEl     = document.getElementById("pointsNum");
  var playerNameEl = document.getElementById("playerName");
  var playerLvlEl  = document.getElementById("playerLevel");
  var avatarLetter = document.getElementById("avatarLetter");
  var closeBtn     = document.getElementById("closeBtn");
  var respecBtn    = document.getElementById("respecBtn");
  var xpFillEl     = document.getElementById("xpFill");
  var xpTextEl     = document.getElementById("xpText");
  var xpToastsEl   = document.getElementById("xpToasts");

  // ---------- helpers ----------
  function pathColor(node) {
    return state.colors[node.path] || state.colors.core || { primary: "#fff", icon: "#fff" };
  }

  function statusOf(node) {
    if (state.unlocked.has(node.id)) return "unlocked";
    if (!node.parents || node.parents.length === 0) return "available";
    var ok = node.parents.every(function (p) { return state.unlocked.has(p); });
    return ok ? "available" : "locked";
  }

  function hexPoints(r) {
    var pts = [];
    for (var i = 0; i < 6; i++) {
      var a = (Math.PI / 3) * i;
      pts.push((r * Math.cos(a)).toFixed(2) + "," + (r * Math.sin(a)).toFixed(2));
    }
    return pts.join(" ");
  }

  function escapeAttr(value) {
    return String(value).replace(/&/g, "&amp;").replace(/"/g, "&quot;")
      .replace(/</g, "&lt;").replace(/>/g, "&gt;");
  }

  function escapeText(value) {
    return String(value).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
  }

  // ---------- icon library (1:1 with mockup) ----------
  function iconPath(id, color, strokeW) {
    var w  = strokeW != null ? strokeW : 2.0;
    var S  = 'stroke="' + color + '" stroke-width="' + w + '" stroke-linecap="round" stroke-linejoin="round" fill="none"';
    var Sb = 'stroke="' + color + '" stroke-width="' + (w + 0.4) + '" stroke-linecap="round" stroke-linejoin="round" fill="none"';
    var F  = 'fill="' + color + '" fill-opacity="0.22" stroke="' + color + '" stroke-width="' + w + '" stroke-linecap="round" stroke-linejoin="round"';
    var Fs = 'fill="' + color + '" fill-opacity="0.14" stroke="' + color + '" stroke-width="' + w + '" stroke-linecap="round" stroke-linejoin="round"';

    switch (id) {
      case "root":
        return '<g>' +
          '<circle cx="0" cy="0" r="7" ' + F + '/>' +
          '<circle cx="0" cy="0" r="2.5" fill="' + color + '" fill-opacity="0.55"/>' +
          '<g ' + S + '><path d="M0 -11 L0 -8 M0 11 L0 8 M-11 0 L-8 0 M11 0 L8 0"/></g>' +
        '</g>';

      case "crosshair":
        return '<g>' +
          '<circle cx="0" cy="0" r="7" ' + Fs + '/>' +
          '<circle cx="0" cy="0" r="3.2" ' + S + '/>' +
          '<g ' + S + '><path d="M0 -11 L0 -8 M0 11 L0 8 M-11 0 L-8 0 M11 0 L8 0"/></g>' +
          '<circle cx="0" cy="0" r="1.3" fill="' + color + '"/>' +
        '</g>';

      case "reload":
        return '<g>' +
          '<g ' + S + '><path d="M7 -1 A7 7 0 1 1 -3 -7"/></g>' +
          '<path d="M5 -8 L8 -1 L1 -3 Z" ' + F + '/>' +
          '<circle cx="0" cy="0" r="1.4" fill="' + color + '"/>' +
        '</g>';

      case "iron":
        return '<g>' +
          '<path d="M-9 5 L-4 -4 L1 5 Z" ' + F + '/>' +
          '<path d="M0 5 L5 -2 L9 5 Z" ' + F + '/>' +
          '<g ' + S + '><path d="M-10 5 L10 5"/></g>' +
        '</g>';

      case "head":
        return '<g>' +
          '<circle cx="0" cy="-1" r="6.5" ' + F + '/>' +
          '<circle cx="0" cy="-1" r="2.4" fill="' + color + '" fill-opacity="0.55"/>' +
          '<g ' + S + '>' +
            '<path d="M0 -10 L0 -8 M0 6 L0 7 M-10 -1 L-8 -1 M8 -1 L10 -1"/>' +
            '<path d="M-5 8 L5 8"/>' +
          '</g>' +
        '</g>';

      case "recoil":
        return '<g>' +
          '<path d="M-8 5 L-3 5 L-3 -1 L4 -1 L4 5 L8 5 L8 7 L-8 7 Z" ' + F + '/>' +
          '<g ' + Sb + '><path d="M0 -10 L0 -3 M-3.2 -6.6 L0 -10 L3.2 -6.6"/></g>' +
        '</g>';

      case "akimbo":
        return '<g>' +
          '<path d="M-9 -3 L-2 -3 L-2 1 L-9 1 Z M-9 1 L-9 5 L-6 5 L-6 1" ' + F + '/>' +
          '<path d="M9 -3 L2 -3 L2 1 L9 1 Z M9 1 L9 5 L6 5 L6 1" ' + F + '/>' +
          '<g ' + S + '><path d="M-9 -3 L-2 -3 L-2 1 L-9 1 Z M-9 1 L-9 5 L-6 5"/></g>' +
          '<g ' + S + '><path d="M9 -3 L2 -3 L2 1 L9 1 Z M9 1 L9 5 L6 5"/></g>' +
        '</g>';

      case "exec":
        return '<g>' +
          '<path d="M-6 -8 C-7 -8 -8 -6 -8 -3 L-8 1 L-5 4 L-5 8 L-3 8 L-3 5 L3 5 L3 8 L5 8 L5 4 L8 1 L8 -3 C8 -6 7 -8 6 -8 Z" ' + F + '/>' +
          '<circle cx="-3" cy="-2" r="1.6" fill="' + color + '"/>' +
          '<circle cx="3" cy="-2" r="1.6" fill="' + color + '"/>' +
          '<g ' + S + '><path d="M-1.5 2 L1.5 2"/></g>' +
        '</g>';

      case "shield":
        return '<g>' +
          '<path d="M0 -9 L7 -6 L7 1 C7 5 4 8 0 9.5 C-4 8 -7 5 -7 1 L-7 -6 Z" ' + F + '/>' +
          '<g ' + Sb + '><path d="M-3 0 L-1 2 L3 -2"/></g>' +
        '</g>';

      case "lightning":
        return '<g>' +
          '<path d="M2 -9 L-5 2 L-1 2 L-2 9 L5 -2 L1 -2 Z" ' + F + '/>' +
          '<g ' + S + '><path d="M2 -9 L-5 2 L-1 2 L-2 9 L5 -2 L1 -2 Z"/></g>' +
        '</g>';

      case "heart":
        return '<g>' +
          '<path d="M0 8 C-7 3 -8 -2 -5 -5 C-3 -7 -1 -6 0 -3 C1 -6 3 -7 5 -5 C8 -2 7 3 0 8 Z" ' + F + '/>' +
          '<g ' + S + '><path d="M-3 -2 L-1 -2 M-2 -3 L-2 -1"/></g>' +
        '</g>';

      case "snow":
        return '<g ' + S + '>' +
          '<path d="M0 -9 L0 9"/>' +
          '<path d="M-7.8 -4.5 L7.8 4.5"/>' +
          '<path d="M-7.8 4.5 L7.8 -4.5"/>' +
          '<path d="M-2 -7 L0 -9 L2 -7 M-2 7 L0 9 L2 7"/>' +
          '<path d="M-6 -5.5 L-7.8 -4.5 L-7 -2.7 M5 5.5 L7.8 4.5 L7 2.7"/>' +
          '<path d="M5 -5.5 L7.8 -4.5 L7 -2.7 M-6 5.5 L-7.8 4.5 L-7 2.7"/>' +
          '<circle cx="0" cy="0" r="1.4" fill="' + color + '"/>' +
        '</g>';

      case "drop":
        return '<g>' +
          '<path d="M0 -8 C-5 -2 -6 3 -3 6 C0 9 4 8 5 4 C6 0 4 -3 0 -8 Z" ' + F + '/>' +
          '<g ' + S + '><path d="M-2 3 C-1 5 1 5 2 3"/></g>' +
        '</g>';

      case "virus":
        return '<g>' +
          '<circle cx="0" cy="0" r="4.2" ' + F + '/>' +
          '<g ' + S + '>' +
            '<path d="M0 -4.2 L0 -8 M0 4.2 L0 8 M-4.2 0 L-8 0 M4.2 0 L8 0"/>' +
            '<path d="M-3 -3 L-5.8 -5.8 M3 -3 L5.8 -5.8 M-3 3 L-5.8 5.8 M3 3 L5.8 5.8"/>' +
          '</g>' +
          '<circle cx="0" cy="-8" r="1.4" fill="' + color + '"/>' +
          '<circle cx="0" cy="8" r="1.4" fill="' + color + '"/>' +
          '<circle cx="-8" cy="0" r="1.4" fill="' + color + '"/>' +
          '<circle cx="8" cy="0" r="1.4" fill="' + color + '"/>' +
        '</g>';

      case "immune":
        return '<g>' +
          '<path d="M0 -9 L7.5 -5.5 L7.5 1 C7.5 6 4 9 0 10 C-4 9 -7.5 6 -7.5 1 L-7.5 -5.5 Z" ' + F + '/>' +
          '<g ' + Sb + '><path d="M-4 0 L-2 2 L4 -3"/></g>' +
          '<g ' + S + '><path d="M-3 -8 L-3 -10 M3 -8 L3 -10"/></g>' +
        '</g>';

      case "hammer":
        return '<g>' +
          '<path d="M-8 -7 L8 -7 L8 -3 L-8 -3 Z" ' + F + '/>' +
          '<path d="M-1 -3 L-1 8 L1 8 L1 -3 Z" ' + F + '/>' +
          '<g ' + S + '><path d="M-3 8.4 L3 8.4"/></g>' +
        '</g>';

      case "stack":
        return '<g>' +
          '<path d="M-7 -5 L0 -8 L7 -5 L0 -2 Z" ' + F + '/>' +
          '<path d="M-7 -1 L0 2 L7 -1 L0 -4 Z" ' + Fs + '/>' +
          '<path d="M-7 3 L0 6 L7 3 L0 0 Z" ' + Fs + '/>' +
        '</g>';

      case "wall":
        return '<g>' +
          '<path d="M-8 -6 L8 -6 L8 6 L-8 6 Z" ' + F + '/>' +
          '<g ' + S + '>' +
            '<path d="M-8 -2 L8 -2 M-8 2 L8 2"/>' +
            '<path d="M-3 -6 L-3 -2 M3 -2 L3 2 M-3 2 L-3 6 M3 -6 L3 -2"/>' +
          '</g>' +
        '</g>';

      case "anvil":
        return '<g>' +
          '<path d="M-9 -3 L8 -3 L5 1 L-2 1 L-2 5 L4 5 L0 9 L-6 9 L-2 5 Z" ' + F + '/>' +
          '<g ' + S + '><path d="M5 -3 L5 -7 L9 -7"/></g>' +
        '</g>';

      case "lock":
        return '<g>' +
          '<rect x="-6" y="-1" width="12" height="10" rx="1.5" ' + F + '/>' +
          '<g ' + S + '><path d="M-4 -1 L-4 -5 A4 4 0 0 1 4 -5 L4 -1"/></g>' +
          '<circle cx="0" cy="3.5" r="1.4" fill="' + color + '"/>' +
        '</g>';

      case "wrench":
        return '<g>' +
          '<path d="M5 -7 A4 4 0 1 0 1 -3 L-7 5 L-3 9 L5 1 A4 4 0 0 0 5 -7 Z" ' + F + '/>' +
          '<circle cx="3" cy="-5" r="1.1" fill="' + color + '"/>' +
        '</g>';

      case "spark":
        return '<g>' +
          '<path d="M0 -9 L1.6 -2 L9 0 L1.6 2 L0 9 L-1.6 2 L-9 0 L-1.6 -2 Z" ' + F + '/>' +
          '<g ' + S + '><path d="M0 -9 L1.6 -2 L9 0 L1.6 2 L0 9 L-1.6 2 L-9 0 L-1.6 -2 Z"/></g>' +
          '<circle cx="0" cy="0" r="1.5" fill="' + color + '"/>' +
        '</g>';

      case "padlock":
        return '<g>' +
          '<rect x="-4.5" y="-0.5" width="9" height="8" rx="1" fill="' + color + '" fill-opacity="0.06" stroke="' + color + '" stroke-width="' + w + '" stroke-linejoin="round"/>' +
          '<g ' + S + '><path d="M-3 -0.5 L-3 -3.5 A3 3 0 0 1 3 -3.5 L3 -0.5"/></g>' +
          '<circle cx="0" cy="3.5" r="1.05" fill="' + color + '"/>' +
        '</g>';

      default:
        return '<circle cx="0" cy="0" r="5" fill="none" stroke="' + color + '" stroke-width="' + w + '"/>';
    }
  }

  // ---------- bezier between two nodes ----------
  function curve(x1, y1, x2, y2) {
    var dx = x2 - x1, dy = y2 - y1, c1x, c1y, c2x, c2y;
    if (Math.abs(dx) > 130) {
      c1x = x1 + dx * 0.32; c1y = y1 + dy * 0.18;
      c2x = x2 - dx * 0.32; c2y = y2 - dy * 0.18;
    } else {
      c1x = x1; c1y = y1 + dy * 0.5;
      c2x = x2; c2y = y2 - dy * 0.5;
    }
    return "M " + x1 + " " + y1 + " C " + c1x + " " + c1y + ", " + c2x + " " + c2y + ", " + x2 + " " + y2;
  }

  // ---------- background atmosphere ----------
  function atmosphereLayer() {
    var L = state.layout;
    var C = state.colors;
    var region = L.VBW / 3;

    var tints = "";

    var starCoords = [
      [88,78],[210,168],[132,300],[72,398],[160,500],[108,574],
      [420,78],[382,168],[468,300],[418,410],[388,505],[452,574],
      [572,70],[626,190],[552,318],[602,430],[548,540],
      [808,68],[772,192],[856,300],[818,420],[776,530],
      [1120,78],[1216,168],[1100,294],[1240,404],[1132,508],[1280,575]
    ];
    var stars = starCoords.map(function (sc) {
      return '<circle cx="' + sc[0] + '" cy="' + sc[1] + '" r="' + (0.5 + Math.random() * 0.25).toFixed(2) +
             '" fill="#fff" fill-opacity="0.05"/>';
    }).join("");

    function ambHex(cx, cy, r, op) {
      var pts = hexPoints(r).split(" ").map(function (p, idx) {
        return p.split(",").map(function (n, i) { return (+n) + (i === 0 ? cx : cy); }).join(",");
      }).join(" ");
      return '<polygon points="' + pts + '" fill="none" stroke="#fff" stroke-opacity="' + op + '" stroke-width="0.5"/>';
    }
    var ambient =
      ambHex(42, 92, 14, 0.02) +
      ambHex(1316, 220, 18, 0.02) +
      ambHex(54, 548, 16, 0.02) +
      ambHex(1306, 560, 12, 0.02);

    return tints + ambient + stars;
  }

  // ---------- subtle tactical network grid ----------
  function networkGuides() {
    var L = state.layout, C = state.colors;
    var TIER_Y = L.TIER_Y, PATH_X = L.PATH_X;

    var tierLines = [TIER_Y.cap, TIER_Y[4], TIER_Y[3], TIER_Y[2], TIER_Y[1], TIER_Y.root]
      .map(function (y) {
        return '<line x1="72" y1="' + y + '" x2="' + (L.VBW - 72) + '" y2="' + y +
               '" stroke="#fff" stroke-opacity="0.015" stroke-width="0.5" stroke-dasharray="2 12"/>';
      }).join("");

    var axes = [
      { x: PATH_X.combat,    color: C.combat.primary    },
      { x: PATH_X.survivor,  color: C.survivor.primary  },
      { x: PATH_X.craftsman, color: C.craftsman.primary }
    ].map(function (a) {
      var dotPts = hexPoints(4).split(" ").map(function (p) {
        return p.split(",").map(function (n, i) { return (+n) + (i === 0 ? a.x : (TIER_Y.root + 18)); }).join(",");
      }).join(" ");
      return '<line x1="' + a.x + '" y1="72" x2="' + a.x + '" y2="' + (TIER_Y.root + 8) +
             '" stroke="' + a.color + '" stroke-opacity="0.04" stroke-width="0.6" stroke-dasharray="1 14"/>' +
             '<polygon points="' + dotPts + '" fill="' + a.color + '" fill-opacity="0.08"/>';
    }).join("");

    return '<g class="network-guide">' + tierLines + axes + '</g>';
  }

  // ---------- tier markers ----------
  function tierMarkers() {
    var TIER_Y = state.layout.TIER_Y;
    var tiers = [
      { y: TIER_Y[1],  label: "TIER I"   },
      { y: TIER_Y[2],  label: "TIER II"  },
      { y: TIER_Y[3],  label: "TIER III" },
      { y: TIER_Y[4],  label: "TIER IV"  },
      { y: TIER_Y.cap, label: "CAPSTONE" }
    ];
    return tiers.map(function (t) {
      return '<g transform="translate(36 ' + t.y + ')">' +
        '<polygon points="' + hexPoints(5.5) + '" fill="none" stroke="rgba(255,255,255,0.3)" stroke-width="1.2"/>' +
        '<polygon points="' + hexPoints(2)   + '" fill="rgba(255,255,255,0.4)"/>' +
        '<text class="tier-marker-label" x="18" y="3.5">' + t.label + '</text>' +
      '</g>';
    }).join("");
  }

  // ---------- top path titles ----------
  function pathTitles() {
    var L = state.layout, C = state.colors;
    var labels = [
      { x: L.PATH_X.combat,    label: "COMBAT",    color: C.combat.primary    },
      { x: L.PATH_X.survivor,  label: "SURVIVOR",  color: C.survivor.primary  },
      { x: L.PATH_X.craftsman, label: "CRAFTSMAN", color: C.craftsman.primary }
    ];
    return labels.map(function (l) {
      return '<g transform="translate(' + l.x + ' 50)">' +
        '<text class="path-title" x="0" y="3.5" text-anchor="middle" fill="' + l.color + '">' + l.label + '</text>' +
      '</g>';
    }).join("");
  }

  // ---------- connections ----------
  function connections() {
    var out = [];
    for (var i = 0; i < state.skills.length; i++) {
      var node = state.skills[i];
      if (!node.parents || node.parents.length === 0) continue;
      for (var j = 0; j < node.parents.length; j++) {
        var pid = node.parents[j];
        var a = state.byId[pid], b = node;
        if (!a) continue;

        var aU = state.unlocked.has(a.id);
        var aOk = (a.id === "root") || (a.parents || []).every(function (p) { return state.unlocked.has(p); });
        var bOk = (b.parents || []).every(function (p) { return state.unlocked.has(p); });
        var bU = state.unlocked.has(b.id);
        var col = pathColor(b).primary;
        var d = curve(a.x, a.y, b.x, b.y);

        if (aU && (bU || bOk)) {
          out.push('<path d="' + d + '" fill="none" stroke="' + col + '" stroke-opacity="0.22" stroke-width="6" stroke-linecap="round"/>');
          out.push('<path d="' + d + '" fill="none" stroke="' + col + '" stroke-opacity="0.95" stroke-width="2.4" stroke-linecap="round"/>');
        } else if (aOk && bOk) {
          out.push('<path class="conn-flow" d="' + d + '" fill="none" stroke="' + col + '" stroke-opacity="0.55" stroke-width="1.7" stroke-dasharray="5 4" stroke-linecap="round"/>');
        } else {
          out.push('<path d="' + d + '" fill="none" stroke="#fff" stroke-opacity="0.07" stroke-width="1.2" stroke-dasharray="3 5" stroke-linecap="round"/>');
        }
      }
    }
    return out.join("");
  }

  // ---------- node renderer ----------
  function renderNode(node) {
    var status = statusOf(node);
    var sel = state.selected === node.id;
    var r = node.capstone ? 30 : 24;
    var innerR = node.capstone ? 18 : 11;
    var col = pathColor(node);
    var isCore = node.path === "core";

    var parts = [];

    if (node.capstone) {
      parts.push('<polygon points="' + hexPoints(42) + '" fill="none" stroke="' + col.primary + '" stroke-opacity="0.18" stroke-width="0.8" stroke-dasharray="3 3"/>');
      parts.push('<polygon points="' + hexPoints(36) + '" fill="none" stroke="' + col.primary + '" stroke-opacity="0.32" stroke-width="0.8" stroke-dasharray="2 2"/>');
      var dots = [[-32,-22],[32,-22],[-32,22],[32,22]];
      for (var d = 0; d < dots.length; d++) {
        parts.push('<circle cx="' + dots[d][0] + '" cy="' + dots[d][1] + '" r="1.6" fill="' + col.primary + '" fill-opacity="0.5"/>');
      }
      parts.push('<polygon points="-3.5,-46 3.5,-46 0,-40" fill="' + col.primary + '" fill-opacity="0.55"/>');
      parts.push('<polygon points="-3.5,46 3.5,46 0,40" fill="' + col.primary + '" fill-opacity="0.55"/>');
    }

    var hoverCol = isCore ? "rgba(255,255,255,0.8)" : col.primary;
    parts.push('<polygon class="node-hover-ring" points="' + hexPoints(r + 7) + '" fill="none" stroke="' + hoverCol + '" stroke-width="0.8" stroke-dasharray="2 3"/>');

    if (status === "available") {
      parts.push('<polygon class="halo-pulse" points="' + hexPoints(r + 5) + '" fill="none" stroke="' + col.primary + '" stroke-opacity="0.45" stroke-width="1" stroke-dasharray="3 2"/>');
    }

    if (sel) {
      parts.push('<polygon class="selection-plate" points="' + hexPoints(r + 6) + '" fill="' + (isCore ? '#fff' : col.primary) + '" fill-opacity="0.055" stroke="none"/>');
      parts.push('<polygon class="selection-ring" points="' + hexPoints(r + 4) + '" fill="none" stroke="' + (isCore ? 'rgba(255,255,255,0.72)' : col.icon) + '" stroke-opacity="0.86" stroke-width="1.05"/>');
    }

    var socketId = isCore ? "socketCore" :
      (node.path === "combat"   ? "socketCombat"   :
       node.path === "survivor" ? "socketSurvivor" : "socketCraftsman");

    if (status === "locked") {
      parts.push('<polygon points="' + hexPoints(r) + '" fill="rgba(10,12,16,0.88)" stroke="rgba(255,255,255,0.16)" stroke-width="1.1"/>');
      parts.push('<polygon points="' + hexPoints(innerR) + '" fill="rgba(0,0,0,0.45)" stroke="rgba(255,255,255,0.07)" stroke-width="0.7"/>');
      parts.push('<g class="node-icon-wrap">' + iconPath("padlock", "rgba(255,255,255,0.4)", 1.7) + '</g>');
    } else {
      parts.push('<polygon points="' + hexPoints(r) + '" fill="rgba(6,8,12,0.9)"/>');
      var tintOp = status === "unlocked" ? 0.22 : 0.06;
      var strokeOp = status === "unlocked" ? 0.92 : 0.55;
      var fill = isCore ? "rgba(255,255,255,0.8)" : col.primary;
      parts.push('<polygon points="' + hexPoints(r) + '" fill="' + fill + '" fill-opacity="' +
        (isCore ? 0.1 : tintOp) + '" stroke="' + (isCore ? '#fff' : col.primary) +
        '" stroke-opacity="' + (isCore ? 0.42 : strokeOp) + '" stroke-width="1.75"/>');

      if (!isCore || node.id === "root") {
        parts.push('<polygon points="' + hexPoints(innerR) + '" fill="rgba(0,0,0,0.55)"/>');
        var socketOp = status === "unlocked" ? 0.85 : 0.35;
        parts.push('<polygon points="' + hexPoints(innerR) + '" fill="url(#' + socketId + ')" fill-opacity="' + socketOp + '"/>');
        var rim = isCore ? "#fff" : col.primary;
        var rimOp = isCore ? 0.28 : (status === "unlocked" ? 0.6 : 0.32);
        parts.push('<polygon points="' + hexPoints(innerR) + '" fill="none" stroke="' + rim + '" stroke-opacity="' + rimOp + '" stroke-width="0.9"/>');
      }

      var iconSw = node.capstone ? 2.15 : 2.0;
      var iconColor = isCore ? "rgba(255,255,255,0.96)" : col.icon;
      var iconFilter = status === "unlocked" ? ' filter="url(#iconGlow)"' : "";
      parts.push('<g class="node-icon-wrap"' + iconFilter + '>' + iconPath(node.icon || "root", iconColor, iconSw) + '</g>');
    }

    if (!node.isRoot) {
      var labelY = node.capstone ? r + 28 : r + 16;
      var labelClass = "node-label";
      if (status === "locked") labelClass += " node-label-locked";
      if (sel) labelClass += " node-label-selected";

      if (node.capstone) {
        parts.push('<text class="node-label-capstone" x="0" y="' + labelY + '" fill="' + col.primary + '" fill-opacity="' + (sel ? 1 : 0.6) + '">' + escapeText(node.name) + '</text>');
      } else {
        var selStyle = sel ? ' style="fill:' + col.icon + ';"' : "";
        parts.push('<text class="' + labelClass + '" x="0" y="' + labelY + '"' + selStyle + '>' + escapeText(node.name) + '</text>');
      }
    } else {
      parts.push('<text class="node-label" x="0" y="' + (r + 16) + '" fill="rgba(255,255,255,0.55)" letter-spacing="2">ROOT</text>');
    }

    var cls = "node-group" + (status === "locked" ? " is-locked" : "");
    return '<g class="' + cls + '" data-id="' + escapeAttr(node.id) + '" transform="translate(' + node.x + ' ' + node.y + ')">' + parts.join("") + '</g>';
  }

  // ---------- svg defs ----------
  function defs() {
    var C = state.colors;
    return '' +
      '<defs>' +
        '<filter id="iconGlow" x="-60%" y="-60%" width="220%" height="220%">' +
          '<feGaussianBlur stdDeviation="0.65" result="b1"/>' +
          '<feMerge><feMergeNode in="b1"/><feMergeNode in="SourceGraphic"/></feMerge>' +
        '</filter>' +
        '<filter id="hexGlow" x="-50%" y="-50%" width="200%" height="200%">' +
          '<feGaussianBlur stdDeviation="2.4" result="b2"/>' +
          '<feMerge><feMergeNode in="b2"/><feMergeNode in="SourceGraphic"/></feMerge>' +
        '</filter>' +
        '<radialGradient id="socketCombat" cx="50%" cy="42%" r="62%">' +
          '<stop offset="0%"  stop-color="' + C.combat.icon    + '" stop-opacity="0.42"/>' +
          '<stop offset="55%" stop-color="' + C.combat.primary + '" stop-opacity="0.18"/>' +
          '<stop offset="100%" stop-color="#000" stop-opacity="0.55"/>' +
        '</radialGradient>' +
        '<radialGradient id="socketSurvivor" cx="50%" cy="42%" r="62%">' +
          '<stop offset="0%"  stop-color="' + C.survivor.icon    + '" stop-opacity="0.42"/>' +
          '<stop offset="55%" stop-color="' + C.survivor.primary + '" stop-opacity="0.18"/>' +
          '<stop offset="100%" stop-color="#000" stop-opacity="0.55"/>' +
        '</radialGradient>' +
        '<radialGradient id="socketCraftsman" cx="50%" cy="42%" r="62%">' +
          '<stop offset="0%"  stop-color="' + C.craftsman.icon    + '" stop-opacity="0.42"/>' +
          '<stop offset="55%" stop-color="' + C.craftsman.primary + '" stop-opacity="0.18"/>' +
          '<stop offset="100%" stop-color="#000" stop-opacity="0.55"/>' +
        '</radialGradient>' +
        '<radialGradient id="socketCore" cx="50%" cy="42%" r="62%">' +
          '<stop offset="0%"  stop-color="#fff" stop-opacity="0.32"/>' +
          '<stop offset="55%" stop-color="#fff" stop-opacity="0.10"/>' +
          '<stop offset="100%" stop-color="#000" stop-opacity="0.55"/>' +
        '</radialGradient>' +
      '</defs>';
  }

  // ---------- main render ----------
  function render() {
    if (!svgEl) return;

    var L = state.layout;
    svgEl.setAttribute("viewBox", "0 0 " + L.VBW + " " + L.VBH);

    svgEl.innerHTML =
      defs() +
      atmosphereLayer() +
      networkGuides() +
      tierMarkers() +
      pathTitles() +
      "<g>" + connections() + "</g>" +
      "<g>" + state.skills.map(renderNode).join("") + "</g>";

    var groups = svgEl.querySelectorAll(".node-group");
    for (var i = 0; i < groups.length; i++) {
      groups[i].addEventListener("click", onNodeClick);
    }

    if (pointsEl) pointsEl.textContent = state.points;
    renderXp();
  }

  // Update the XP bar fill + label based on current state.xp / xpPerPoint.
  function renderXp() {
    if (!xpFillEl || !xpTextEl) return;
    var per = Math.max(1, state.xpPerPoint || 100);
    var pct = Math.max(0, Math.min(100, (state.xp / per) * 100));
    xpFillEl.style.width = pct.toFixed(1) + "%";
    xpTextEl.textContent = state.xp + " / " + per + " XP";
  }

  // Show a small floating toast like "+50 XP — zombie kill". Auto-removes
  // after the CSS animation finishes (~3s).
  var REASON_LABELS = {
    playtime:           "Playtime",
    zombie_kill:        "Zombie Kill",
    event_complete:     "Event Done",
    event_participate:  "Event Joined",
    redzone_loot:       "Loot",
    infection_cured:    "Infection Cured",
    admin:              "Admin Grant"
  };
  function reasonLabel(reason) {
    if (!reason) return "";
    var base = String(reason).split(":")[0];
    return REASON_LABELS[base] || base.replace(/_/g, " ");
  }
  function showXpToast(payload) {
    if (!xpToastsEl || !payload) return;
    var div = document.createElement("div");
    div.className = "xp-toast" + (payload.gainedPoint ? " xp-toast-point" : "");
    var label = reasonLabel(payload.reason);
    div.innerHTML =
      '<span class="xp-amt">+' + (payload.amount || 0) + ' XP</span>' +
      escapeText(label) +
      (payload.gainedPoint ? '<span class="xp-amt" style="margin-left:10px">+1 PT</span>' : '');
    xpToastsEl.appendChild(div);
    // Self-remove after the CSS exit animation finishes (~3s total).
    setTimeout(function () {
      if (div.parentNode === xpToastsEl) xpToastsEl.removeChild(div);
    }, 3200);
  }

  function onNodeClick(ev) {
    var id = ev.currentTarget.getAttribute("data-id");
    if (!id) return;
    state.selected = id;
    render();
    renderDetail();
  }

  // ---------- detail panel ----------
  function renderDetail() {
    if (!detailEl) return;
    var node = state.byId[state.selected];
    if (!node) {
      // fall back to root or first available skill
      node = state.byId.root || state.skills[0];
      if (!node) { detailEl.innerHTML = ""; return; }
      state.selected = node.id;
    }

    var status = statusOf(node);
    var col = pathColor(node);
    var isCore = node.path === "core";
    var romanArr = ["I", "II", "III", "IV"];
    var tierLabel = node.capstone ? "CAPSTONE" : ("TIER " + (romanArr[node.tier - 1] || ""));
    var pathName = isCore ? "NEXUS" : String(node.path).toUpperCase();
    var tierGlyph = node.capstone ? "★" : (romanArr[node.tier - 1] || "·");

    var iconBoxColor = isCore ? "rgba(255,255,255,0.82)" : col.primary;
    var tagColor     = isCore ? "rgba(255,255,255,0.55)" : col.primary;

    var btnHtml, costLine;
    if (status === "unlocked") {
      btnHtml  = '<button class="btn btn-unlocked" disabled>Unlocked</button>';
      costLine = '<div class="detail-cost">Acquired</div>';
    } else if (status === "available") {
      var canAfford = state.points >= (node.cost || 0);
      btnHtml = canAfford
        ? '<button class="btn btn-unlock" id="unlockBtn">Unlock</button>'
        : '<button class="btn btn-locked" disabled>Insufficient</button>';
      costLine = '<div class="detail-cost"><strong>' + (node.cost || 0) + '</strong>pts</div>';
    } else {
      btnHtml  = '<button class="btn btn-locked" disabled>Locked</button>';
      costLine = '<div class="detail-cost">Prereqs needed</div>';
    }

    detailEl.innerHTML =
      '<div class="detail-icon" style="background:' + col.primary + '21; border:0.5px solid ' + col.primary + '52; color:' + iconBoxColor + ';">' +
        tierGlyph +
      '</div>' +
      '<div class="detail-info">' +
        '<div class="detail-tag" style="color:' + tagColor + ';">' + escapeText(pathName) + ' · ' + tierLabel + '</div>' +
        '<div class="detail-name">' + escapeText(node.name) + '</div>' +
        '<div class="detail-desc">' + escapeText(node.desc || "") + '</div>' +
      '</div>' +
      '<div class="detail-action">' +
        costLine +
        btnHtml +
      '</div>';

    var ub = document.getElementById("unlockBtn");
    if (ub) {
      ub.addEventListener("click", function () {
        if (state.points < (node.cost || 0)) return;
        ub.classList.add("btn-locked");
        ub.classList.remove("btn-unlock");
        ub.textContent = "Requesting...";
        nuiFetch("unlock", { skillId: node.id });
      });
    }
  }

  // ---------- state intake ----------
  function ingestUnlocked(list) {
    state.unlocked = new Set();
    if (Array.isArray(list)) {
      for (var i = 0; i < list.length; i++) {
        if (typeof list[i] === "string") state.unlocked.add(list[i]);
      }
    }
  }

  function rebuildIndex() {
    state.byId = {};
    for (var i = 0; i < state.skills.length; i++) {
      state.byId[state.skills[i].id] = state.skills[i];
    }
  }

  function applyOpenPayload(data) {
    if (!data || typeof data !== "object") return;

    if (Array.isArray(data.skills) && data.skills.length > 0) {
      state.skills = data.skills;
      rebuildIndex();
    }
    if (data.colors) state.colors = Object.assign({}, DEFAULT_COLORS, data.colors);
    if (data.layout) state.layout = Object.assign({}, DEFAULT_LAYOUT, data.layout);
    if (data.player) state.player = Object.assign({}, state.player, data.player);
    if (data.config) state.config = Object.assign({}, state.config, data.config);

    ingestUnlocked(data.unlocked);
    if (typeof data.points === "number")     state.points     = data.points;
    if (typeof data.xp === "number")         state.xp         = data.xp;
    if (typeof data.xpTotal === "number")    state.xpTotal    = data.xpTotal;
    if (typeof data.xpPerPoint === "number") state.xpPerPoint = data.xpPerPoint;
    if (data.modifiers && typeof data.modifiers === "object") state.modifiers = data.modifiers;

    if (!state.selected) {
      // pick first available, otherwise the root.
      var firstAvail = state.skills.find(function (n) { return statusOf(n) === "available" && n.id !== "root"; });
      state.selected = firstAvail ? firstAvail.id : (state.byId.root ? "root" : (state.skills[0] && state.skills[0].id));
    }

    if (playerNameEl) playerNameEl.textContent = state.player.name || "Survivor";
    if (playerLvlEl)  playerLvlEl.textContent = "·\u00A0LVL\u00A0" + (state.player.level || 1);
    if (avatarLetter) avatarLetter.textContent = (state.player.name || "S").charAt(0).toUpperCase();

    if (respecBtn) {
      if (state.config.allowRespec) respecBtn.classList.remove("is-hidden");
      else respecBtn.classList.add("is-hidden");
    }
  }

  function applyStateUpdate(data) {
    if (!data) return;
    if (Array.isArray(data.unlocked))     ingestUnlocked(data.unlocked);
    if (typeof data.points === "number")  state.points  = data.points;
    if (typeof data.xp === "number")      state.xp      = data.xp;
    if (typeof data.xpTotal === "number") state.xpTotal = data.xpTotal;
    if (data.modifiers && typeof data.modifiers === "object") state.modifiers = data.modifiers;
  }

  // ---------- open / close ----------
  function open() {
    if (!rootEl) return;
    rootEl.classList.remove("hidden");
    render();
    renderDetail();
  }
  function close() {
    if (!rootEl) return;
    rootEl.classList.add("hidden");
  }

  // ---------- listeners ----------
  window.addEventListener("message", function (event) {
    var msg = event.data || {};
    switch (msg.action) {
      case "open":
        applyOpenPayload(msg.data);
        open();
        break;
      case "close":
        close();
        break;
      case "updateState":
        applyStateUpdate(msg.data);
        render();
        renderDetail();
        break;
      case "xpToast":
        // Toast fires regardless of panel visibility so players see XP gain
        // pop on the screen even with the menu closed.
        showXpToast(msg.data);
        break;
      case "lockpickStart":
        startLockpick(msg.data);
        break;
      case "lockpickStop":
        stopLockpick(false);
        break;
    }
  });

  // ---------------------------------------------------------------------------
  // Lockpick minigame
  // ---------------------------------------------------------------------------
  // 3-pin minigame: a cursor sweeps left↔right inside a track. The player has
  // to hit SPACE while the cursor is inside the green zone. Hit 3 = success.
  // The skill modifier `lockpickSpeed` widens the zone (easier).
  //
  // Server triggers via SendNUIMessage({action:'lockpickStart', data:{
  //   pins: 3, cursorMs: 1400, zoneFraction: 0.18
  // }}); on success/failure we POST the result back via nuiFetch('lockpickResult').
  var lpState = null;

  function startLockpick(opts) {
    opts = opts || {};
    var lpEl = document.getElementById("lockpick");
    if (!lpEl) return;
    lpEl.classList.remove("hidden");

    var pinsTotal = Math.max(1, parseInt(opts.pins || 3, 10));
    // Cursor period in ms. Skill widens zone, NOT cursor speed, so the
    // baseline cursor motion is kept fair across players.
    var cursorMs    = opts.cursorMs    || 1400;
    var zoneFrac    = opts.zoneFraction || 0.18;

    // Reset pin pip visuals
    for (var i = 1; i <= 3; i++) {
      var p = document.getElementById("lp-pin" + i);
      if (p) p.className = "lp-pin";
    }
    var statusEl = document.getElementById("lp-status");
    if (statusEl) statusEl.textContent = "Pin 1 / " + pinsTotal;

    lpState = {
      pinsDone:   0,
      pinsTotal:  pinsTotal,
      cursorMs:   cursorMs,
      zoneFrac:   zoneFrac,
      startedAt:  performance.now(),
      pinFailed:  false,
      raf:        0
    };
    placeRandomZone();
    lpState.raf = requestAnimationFrame(lockpickFrame);

    // Listen for SPACE
    document.addEventListener("keydown", lockpickKey);
  }

  function placeRandomZone() {
    if (!lpState) return;
    var zone = document.getElementById("lp-zone");
    if (!zone) return;
    var widthPct = lpState.zoneFrac * 100;
    var maxLeft = 100 - widthPct;
    var leftPct = Math.random() * maxLeft;
    zone.style.width = widthPct.toFixed(2) + "%";
    zone.style.left  = leftPct.toFixed(2) + "%";
    lpState.zoneLeft  = leftPct / 100;
    lpState.zoneWidth = widthPct / 100;
  }

  function lockpickFrame(t) {
    if (!lpState) return;
    var cur = document.getElementById("lp-cursor");
    if (cur) {
      // Triangle wave 0..1..0 over cursorMs.
      var phase = ((t - lpState.startedAt) % lpState.cursorMs) / lpState.cursorMs;
      var pos = phase < 0.5 ? phase * 2 : (1 - phase) * 2;
      cur.style.left = (pos * 100).toFixed(2) + "%";
      lpState.cursorPos = pos;
    }
    lpState.raf = requestAnimationFrame(lockpickFrame);
  }

  function lockpickKey(e) {
    if (!lpState || e.key !== " ") return;
    e.preventDefault();
    var pos = lpState.cursorPos || 0;
    if (pos >= lpState.zoneLeft && pos <= (lpState.zoneLeft + lpState.zoneWidth)) {
      // hit — advance pin
      lpState.pinsDone++;
      var p = document.getElementById("lp-pin" + lpState.pinsDone);
      if (p) p.className = "lp-pin set";
      if (lpState.pinsDone >= lpState.pinsTotal) {
        return finishLockpick(true);
      }
      var statusEl = document.getElementById("lp-status");
      if (statusEl) statusEl.textContent = "Pin " + (lpState.pinsDone + 1) + " / " + lpState.pinsTotal;
      placeRandomZone();
    } else {
      // miss — flash pin red and fail
      var pf = document.getElementById("lp-pin" + (lpState.pinsDone + 1));
      if (pf) pf.className = "lp-pin fail";
      finishLockpick(false);
    }
  }

  function finishLockpick(success) {
    if (!lpState) return;
    cancelAnimationFrame(lpState.raf);
    document.removeEventListener("keydown", lockpickKey);
    var statusEl = document.getElementById("lp-status");
    if (statusEl) statusEl.textContent = success ? "Unlocked" : "Broken Pick";
    var lpEl = document.getElementById("lockpick");
    setTimeout(function () {
      if (lpEl) lpEl.classList.add("hidden");
      lpState = null;
    }, 600);
    nuiFetch("lockpickResult", { success: success === true });
  }

  function stopLockpick(silent) {
    var lpEl = document.getElementById("lockpick");
    if (lpEl) lpEl.classList.add("hidden");
    if (lpState) {
      cancelAnimationFrame(lpState.raf);
      document.removeEventListener("keydown", lockpickKey);
      lpState = null;
    }
    if (!silent) nuiFetch("lockpickResult", { success: false, cancelled: true });
  }

  document.addEventListener("keydown", function (e) {
    if (rootEl && rootEl.classList.contains("hidden")) return;
    if (e.key === "Escape") {
      e.preventDefault();
      nuiFetch("close");
    }
  });

  if (closeBtn)  closeBtn.addEventListener("click", function () { nuiFetch("close"); });
  if (respecBtn) respecBtn.addEventListener("click", function () {
    if (!state.config.allowRespec) return;
    nuiFetch("respec");
  });

})();
