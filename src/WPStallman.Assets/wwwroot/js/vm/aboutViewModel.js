// js/vm/aboutViewModel.js
var AboutViewModel = function (app, params) {
  var self = this;
  self.app = app || {};
  params = params || {};

  // ---- Public fields already used by index.html ----
  self.imageSrc = params.imageSrc || 'img/portrait.jpg';
  self.imageAlt = params.imageAlt || 'Our mascot, W. P. Stallman';
  self.aboutHtml = ko.observable(
    `<p>W.P. Stallman came about as a home-grown solution to a very annoying problem - having to package all of your database objects for a WordPress plugin. Before the concept, there was the character... What if you combined Richard Stallman, one of the pioneers of Free Software, with W. C. Fields, a curmudgeonly stalwart of classic comedy? The result is this application. If you find it useful, please donate below.</p>`
  );

  self.manualText = ko.observable(
    `W.P. Stallman User Manual

• Load a manifest JSON or introspect a database to generate one.
• Set DB prefix and Installer class name.
• Choose entities to include, then click "Build Installer".`
  );

  self.manualHtml = ko.observable('');

  self.loadManualHtml = async function () {
  
      // Ask the host to read from wwwroot
      const res = await sendDotnetCommand("ReadContentText", { RelativePath: "manual.html" });

      if (!res || !res.Success || !res.Payload || !res.Payload.Text) {
        throw new Error((res && res.Error) || "Could not load manual text.");
      }

      const text = res.Payload.Text;

      self.manualHtml(text);
  };


  self.openLicenseModal = async function () {
    try {
      // Ask the host to read from wwwroot
      const res = await sendDotnetCommand("ReadContentText", { RelativePath: "LICENSE.txt" });

      if (!res || !res.Success || !res.Payload || !res.Payload.Text) {
        throw new Error((res && res.Error) || "Could not load license text.");
      }

      const text = res.Payload.Text;

      self.app.showGlobalModal({
        title: "MIT License",
        message:
          `<div class="text-start">
           <pre class="license-pre mb-0">${escapeHtml(text)}</pre>
         </div>`,
        okText: "Close",
        variant: "secondary",
        closeable: true
      });
    } catch (err) {
      // Optional fallback to your inline observable if you kept it:
      if (typeof self.licenseText === "function" && self.licenseText()) {
        self.app.showGlobalModal({
          title: "MIT License",
          html:
            `<div class="text-start">
             <pre class="license-pre mb-0">${escapeHtml(self.licenseText())}</pre>
           </div>`,
          okText: "Close",
          variant: "secondary",
          closeable: true
        });
        return;
      }

      if (self.app && typeof self.app.showGlobalModalError === "function") {
        self.app.showGlobalModalError({
          title: "Unable to show license",
          message: String((err && err.message) || err || "Unknown error"),
          closeable: true
        });
      }
    }
  };


  // small helper to avoid HTML injection in the <pre>
  function escapeHtml(s) {
    return String(s)
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;');
  };

  // Optional status (if you want to bind a "Ready/Playing…" somewhere later)
  self.audioStatus = ko.observable('');

  // preferred sources (override with params if you like)
  var audioSources = {
    webm: params.audioWebm || 'audio/founder.webm',
    ogg: params.audioOgg || 'audio/founder.ogg',
    mp3: params.audioMp3 || 'audio/founder.mp3'
  };

  // expose a single `audioSrc` observable for your HTML binding
  self.audioStatus = ko.observable('');
  self.audioSrc = ko.observable('audio/founder.mp3'); // default

  var audioSources = {
    webm: 'audio/founder.webm',
    ogg: 'audio/founder.ogg',
    mp3: 'audio/founder.mp3'
  };

  function chooseSource() {
    const testEl = document.createElement('audio');
    if (testEl.canPlayType('audio/webm; codecs=opus')) return audioSources.webm;
    if (testEl.canPlayType('audio/ogg; codecs=vorbis')) return audioSources.ogg;
    return audioSources.mp3;
  }

  self.audioStatus = ko.observable('');

  // Internal
  var audioEl = null;
  var ready = false;
  var unlocked = false;
  var attached = false;

  // ----- Helpers -----
  function ensureAudioElement() {
    if (audioEl && attached) return audioEl;
    audioEl = document.getElementById('founder-audio');
    if (!audioEl) return null;

    // Pick best playable type
    var candidates = [
      { url: audioSources.webm, type: 'audio/webm; codecs=opus' },
      { url: audioSources.ogg, type: 'audio/ogg; codecs=vorbis' },
      { url: audioSources.mp3, type: 'audio/mpeg' }
    ];
    var supported = candidates.find(c => audioEl.canPlayType && audioEl.canPlayType(c.type) !== '');
    var chosen = (supported ? supported.url : audioSources.mp3);

    // reflect into element and KO observable
    audioEl.src = chosen;
    if (ko.isObservable(self.audioSrc)) self.audioSrc(chosen); else self.audioSrc = chosen;

    try { audioEl.load(); } catch (_) { }

    // status/debug
    audioEl.addEventListener('canplaythrough', () => { ready = true; self.audioStatus('Ready'); }, { once: true });
    audioEl.addEventListener('playing', () => self.audioStatus('Playing…'));
    audioEl.addEventListener('waiting', () => self.audioStatus('Buffering…'));
    audioEl.addEventListener('stalled', () => self.audioStatus('Stalled'));
    audioEl.addEventListener('error', () => self.audioStatus('Error ' + (audioEl.error && audioEl.error.code)));

    // unlock on first gesture
    const unlock = async () => {
      if (unlocked) return;
      try {
        await audioEl.play();
        audioEl.pause();
        audioEl.currentTime = 0;
        unlocked = true;
      } catch (_) { /* try again on next gesture */ }
      window.removeEventListener('pointerdown', unlock);
      window.removeEventListener('keydown', unlock);
    };
    window.addEventListener('pointerdown', unlock, { once: true });
    window.addEventListener('keydown', unlock, { once: true });

    attached = true;
    return audioEl;
  }



  // ----- UI actions -----
  // in AboutViewModel

  const sources = [
    { url: 'audio/founder.webm', type: 'audio/webm; codecs=opus' },
    { url: 'audio/founder.ogg', type: 'audio/ogg; codecs=vorbis' },
    { url: 'audio/founder.mp3', type: 'audio/mpeg' }
  ];

  async function selectPlayable(el) {
    for (const s of sources) {
      try {
        el.pause(); el.muted = true; el.src = s.url; el.load();
        // wait briefly for metadata or error
        const ok = await new Promise(res => {
          let done = false;
          const t = setTimeout(() => !done && (done = true, res(false)), 1200);
          el.addEventListener('loadeddata', () => { if (!done) { done = true; clearTimeout(t); res(true); } }, { once: true });
          el.addEventListener('error', () => { if (!done) { done = true; clearTimeout(t); res(false); } }, { once: true });
        });
        if (!ok) continue;
        await el.play(); el.pause(); el.currentTime = 0; el.muted = false;
        self.audioSrc(s.url); // reflect to KO
        console.log('[AboutVM] Selected playable source:', s.url);
        self.audioStatus('Ready');
        return s.url;
      } catch (e) {
        // try next codec
      }
    }
    self.audioStatus('Audio not supported on this system');
    throw new Error('No playable audio source');
  }

  setTimeout(async () => {
    const el = document.getElementById('founder-audio');
    if (!el) return;
    // listeners to see what’s happening
    el.addEventListener('error', () => console.error('[AboutVM] MediaError code:', el.error && el.error.code, 'src:', el.currentSrc));
    el.addEventListener('canplaythrough', () => console.log('[AboutVM] canplaythrough'));
    try { await selectPlayable(el); } catch (_) { }
  }, 0);

  self.playFounderMessage = async function () {
    const el = document.getElementById('founder-audio');
    if (!el) return;
    try {
      el.currentTime = 0;
      await el.play();
      self.audioStatus('Playing…');
    } catch (err) {
      // If play fails, re-probe and retry once
      try {
        await selectPlayable(el);
        el.currentTime = 0;
        await el.play();
        self.audioStatus('Playing…');
      } catch (e) {
        self.audioStatus('Audio not supported (install codecs?)');
      }
    }
  };


  self.openImageModal = function () {
    const src = typeof self.imageSrc === 'function' ? self.imageSrc() : self.imageSrc;
    const alt = typeof self.imageAlt === 'function' ? self.imageAlt() : self.imageAlt || 'Image';
    window.showImageModal({ src, alt });
  };



  // Initialize once DOM is available (tab content gets inserted after KO apply)
  // A short defer ensures #founder-audio exists.
  setTimeout(ensureAudioElement, 0);

  self.loadManualHtml();
};
