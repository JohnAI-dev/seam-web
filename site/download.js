(function () {
  var DESKTOP_API = "https://api.github.com/repos/JohnAI-dev/seam-desktop/releases/latest";
  var ANDROID_API = "https://api.github.com/repos/JohnAI-dev/seam-android/releases/latest";

  var HERO_LABEL = {
    mac: "Download for Mac",
    windows: "Download for Windows",
    linux: "Download for Linux",
    android: "Download for Android"
  };

  var HERO_LINK = {
    mac: "link-dmg",
    windows: "link-exe",
    linux: "link-appimage",
    android: "link-apk"
  };

  function onReady(fn) {
    if (document.readyState === "loading") {
      document.addEventListener("DOMContentLoaded", fn);
    } else {
      fn();
    }
  }

  function detectPlatform() {
    var ua = navigator.userAgent || "";
    if (/Android|iPhone|iPod|Mobile/i.test(ua)) return "android";
    if (/Windows/i.test(ua)) return "windows";
    if (/Macintosh|Mac OS X/i.test(ua)) return "mac";
    if (/Linux/i.test(ua)) return "linux";
    return "";
  }

  function highlight(platform) {
    var cards = document.querySelectorAll("[data-platform]");
    var i;
    for (i = 0; i < cards.length; i++) {
      cards[i].classList.toggle("is-current", cards[i].getAttribute("data-platform") === platform);
    }
  }

  function applyHero(platform) {
    var hero = document.getElementById("hero-download");
    var link;
    if (!hero || !HERO_LABEL[platform]) return;
    hero.textContent = HERO_LABEL[platform];
    link = document.getElementById(HERO_LINK[platform]);
    if (link && link.href) hero.href = link.href;
  }

  function isArray(value) {
    return Object.prototype.toString.call(value) === "[object Array]";
  }

  function nameEndsWith(name, suffix) {
    if (typeof name !== "string" || name.length < suffix.length) return false;
    return name.slice(name.length - suffix.length).toLowerCase() === suffix.toLowerCase();
  }

  function findAsset(assets, suffix, hint) {
    var match = null;
    var hinted = null;
    var i;
    var asset;
    var name;
    if (!isArray(assets)) return null;
    for (i = 0; i < assets.length; i++) {
      asset = assets[i];
      if (!asset || !nameEndsWith(asset.name, suffix)) continue;
      if (typeof asset.browser_download_url !== "string") continue;
      if (asset.browser_download_url.indexOf("https://") !== 0) continue;
      name = asset.name;
      if (!match) match = asset;
      if (hint && name.toLowerCase().indexOf(hint.toLowerCase()) !== -1) {
        hinted = asset;
        break;
      }
    }
    return hinted || match;
  }

  function setHref(id, asset) {
    var el;
    if (!asset) return;
    el = document.getElementById(id);
    if (!el) return;
    el.href = asset.browser_download_url;
  }

  function setVersion(id, version) {
    var el = document.getElementById(id);
    var label;
    if (!el || !version) return;
    label = document.createElement("span");
    label.textContent = "Version " + version;
    while (el.firstChild) el.removeChild(el.firstChild);
    el.appendChild(label);
  }

  function versionOf(release) {
    var tag = release && (release.tag_name || release.name);
    if (typeof tag !== "string" || !tag) return "";
    if (tag.charAt(0) === "v" || tag.charAt(0) === "V") return tag.slice(1);
    return tag;
  }

  function loadJson(url) {
    return fetch(url, { headers: { Accept: "application/vnd.github+json" } }).then(function (res) {
      if (!res.ok) throw new Error("release unavailable");
      return res.json();
    });
  }

  function applyDesktop(release) {
    var assets = release && release.assets;
    var version = versionOf(release);
    setHref("link-dmg", findAsset(assets, ".dmg", "aarch64"));
    setHref("link-exe", findAsset(assets, "-setup.exe", "x64"));
    setHref("link-appimage", findAsset(assets, ".AppImage", "amd64"));
    setHref("link-deb", findAsset(assets, ".deb", "amd64"));
    setVersion("version-mac", version);
    setVersion("version-windows", version);
    setVersion("version-linux", version);
  }

  function applyAndroid(release) {
    setHref("link-apk", findAsset(release && release.assets, ".apk", ""));
    setVersion("version-android", versionOf(release));
  }

  onReady(function () {
    var platform = detectPlatform();
    highlight(platform);
    applyHero(platform);
    if (typeof fetch !== "function") return;
    loadJson(DESKTOP_API).then(function (release) {
      applyDesktop(release);
      applyHero(platform);
    }).catch(function () {});
    loadJson(ANDROID_API).then(function (release) {
      applyAndroid(release);
      applyHero(platform);
    }).catch(function () {});
  });
})();
