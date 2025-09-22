// js/app/app.js

window.VERBOSE_LOGGING = true;

// Simple dynamic image modal (no Bootstrap chrome)
window.showImageModal = function ({ src, alt = "Image" } = {}) {
  if (!src) return;

  const backdrop = document.createElement('div');
  backdrop.className = 'img-modal-backdrop';

  const wrapper = document.createElement('div');
  wrapper.className = 'img-modal-content';

  const img = document.createElement('img');
  img.className = 'img-modal-img';
  img.alt = alt;
  img.src = src;

  wrapper.appendChild(img);
  backdrop.appendChild(wrapper);
  document.body.appendChild(backdrop);

  // lock scroll
  document.body.classList.add('img-modal-open');

  // fade in
  requestAnimationFrame(() => backdrop.classList.add('visible'));

  // close handlers (backdrop click, ESC)
  function close() {
    backdrop.classList.remove('visible');
    // allow fade-out
    setTimeout(() => {
      document.body.classList.remove('img-modal-open');
      window.removeEventListener('keydown', onKey);
      backdrop.remove();
    }, 150);
  }
  function onKey(e) { if (e.key === 'Escape') close(); }

  backdrop.addEventListener('click', (e) => {
    // only close if clicked backdrop (not while dragging the image)
    if (e.target === backdrop) close();
  });
  window.addEventListener('keydown', onKey);

  // Optional: clicking the image also closes
  img.addEventListener('click', close);
};


// ---- helpers (app.js) ----
function pad2(n) { return n.toString().padStart(2, "0"); }

/**
 * generateTimestampFileName("manifest", "json")
 * -> "manifest-YYYY-MM-DD_HH-mm-ss.json"
 */
function generateTimestampFileName(prefix, ext) {
  const d = new Date();
  const stamp = [
    d.getFullYear(),
    pad2(d.getMonth() + 1),
    pad2(d.getDate())
  ].join("-") + "_" + [pad2(d.getHours()), pad2(d.getMinutes()), pad2(d.getSeconds())].join("-");
  const safePrefix = (prefix || "file").replace(/[^\w.-]+/g, "_");
  const safeExt = (ext || "").replace(/^\.+/, ""); // strip leading dots
  return `${safePrefix}-${stamp}${safeExt ? "." + safeExt : ""}`;
}


// A map from RequestId ⇒ resolver function
const pendingDotnetRequests = {};

/**
 * Installs a single global receiver callback for all .NET messages.
 * Dispatches each incoming message to the correct Promise resolver
 * based on its RequestId.
 */
function setupGlobalReceive() {
  // only call this once!
  window.external.receiveMessage((raw) => {
    let msg;
    try {
      msg = JSON.parse(raw);
    } catch (e) {
      console.error("Invalid JSON from .NET:", raw);
      return;
    }
    const { RequestId, Success, Payload, Error } = msg;
    const resolver = pendingDotnetRequests[RequestId];
    if (resolver) {
      delete pendingDotnetRequests[RequestId];
      resolver({ Success, Payload, Error });
    } else {
      console.warn("No handler for .NET response:", msg);
    }
  });
}

/**
 * Sends a command to the .NET backend and returns a Promise
 * that resolves when the matching response arrives.
 */
function sendDotnetCommand(command, details) {
  const RequestId = crypto.randomUUID();
  const envelope = { Command: command, Details: details, RequestId };
  window.external.sendMessage(JSON.stringify(envelope));
  return new Promise((resolve) => {
    pendingDotnetRequests[RequestId] = resolve;
  });
}

/**
 * Helper to save manifests via a Save File dialog.
 */
function saveManifestWithDialog(manifestContent, suggestedFilename, parentVm) {
  // 1. Prompt the user
  sendDotnetCommand("ShowSaveDialog", { SuggestedFilename: suggestedFilename, Filter: "*.json" })
    .then(resp => {
      if (!resp.Success || !resp.Payload?.Path) {
        // user canceled or error
        return;
      }
      // 2. Show "Saving..." modal now that we have a path
      parentVm.showGlobalModal({
        title: "Saving Manifest",
        message: "Saving to disk…",
        showButton: false,
        closeable: false
      });

      // 3. Actually write the file
      return sendDotnetCommand("WriteFile", {
        Path: resp.Payload.Path,
        Data: manifestContent
      }).then(writeResp => {
        parentVm.hideModal();
        if (writeResp.Success) {
          parentVm.showGlobalModal({
            title: "Manifest Saved",
            message: "Saved to:\n" + resp.Payload.Path,
            showButton: true,
            closeable: true,
            buttonText: "OK"
          });
        } else {
          parentVm.showGlobalModal({
            title: "Error Saving",
            message: writeResp.Error || "Unknown error",
            isError: true,
            showButton: true,
            closeable: true,
            buttonText: "OK"
          });
        }
      });
    });
}

function parseBool(val) {
  if (typeof val === "boolean") { return val; }
  if (typeof val === "string") {
    var v = val.trim().toLowerCase();
    if (v === "true" || v === "1" || v === "yes" || v === "on") { return true; }
    return false;
  }
  return !!val;
};

// ---- Main App ViewModel ----
function AppViewModel() {
  const self = this;

  // set up our one global receiver
  setupGlobalReceive();

  // child VMs
  self.manifestVM = new ManifestViewModel(self);
  self.installerVM = new InstallerViewModel(self);
  self.aboutVM = new AboutViewModel(self);
  self.donateVM = new DonateViewModel(self);

  // modal state
  self.showModal = ko.observable(false);
  self.modalData = ko.observable({ title: "", message: "", isError: false, showButton: true, closeable: true, buttonText: "Close", isConfirm: false, confirmYesText: "Ok", confirmCancelText: "Cancel", confirmUserAnswer: null });

  self.showGlobalModal = ({ title, message, showButton, closeable, buttonText, isError } = {}) => {
    self.modalData({ title, message, isError, showButton, closeable, buttonText, isConfirm: false });
    self.showModal(true);
  };

  self.showGlobalModalConfirm = ({ title, message, confirmYesText, confirmCancelText, onOk, onCancel } = {}) => {
    self.modalData({ title, message, showButton: false, closeable: false, confirmYesText, confirmCancelText, isConfirm: true, isError: false, onOk, onCancel });
    self.showModal(true);
  };

  self.showGlobalModalError = ({ title, message } = {}) => {
    self.modalData({ title, message, showButton: true, closeable: true, isConfirm: false, isError: true, buttonText: 'OK' });
    self.showModal(true);
  };

  self.hideModal = () => self.showModal(false);

  self.userHideModal = function () {
    if (self.modalData().closeable) {
      self.hideModal();
    }
  };

  self.userConfirmModalOk = function () {
    self.modalData().userAnswer = true;
    self.hideModal();
    if (self.modalData().onOk) {
      self.modalData().onOk();
    }
  };

  self.userConfirmModalCancel = function () {
    self.modalData().userAnswer = false;
    self.hideModal();
    if (self.modalData().onCancel) {
      self.modalData().onCancel();
    }
  };

  // Toast-like notice inside the modal (not part of message)
  self.modalNoticeVisible = ko.observable(false);
  self.modalNoticeText = ko.observable("");
  self.modalNoticeKind = ko.observable("success"); // 'success' | 'error'
  self.modalNoticeFading = ko.observable(false);

  // Show a notice that auto-fades and doesn’t alter the message content
  self.showModalNotice = function (kind, text, { visibleMs = 1800, fadeMs = 600 } = {}) {
    self.modalNoticeKind(kind);
    self.modalNoticeText(text);
    self.modalNoticeFading(false);
    self.modalNoticeVisible(true);

    // trigger fade after visibleMs
    setTimeout(() => {
      self.modalNoticeFading(true);
      // hide after fade completes
      setTimeout(() => {
        self.modalNoticeVisible(false);
        self.modalNoticeFading(false);
      }, fadeMs);
    }, visibleMs);
  };

  // Hide any active notice immediately (optional utility)
  self.hideModalNotice = function () {
    self.modalNoticeVisible(false);
    self.modalNoticeFading(false);
  };

  self.copyModalMessage = async function () {
    try {
      const md = self.modalData && self.modalData();
      const html = (md && md.message) || "";

      // Convert HTML → plain text (keeps UI clean)
      const tmp = document.createElement("div");
      tmp.innerHTML = html;
      const text = tmp.innerText;

      if (window.VERBOSE_LOGGING) {
        console.log("[GlobalModal] Copying text length:", text.length);
      }

      // Prefer native host clipboard (Photino)
      try {
        const resp = await sendDotnetCommand("CopyText", { text });
        if (resp && resp.Success) {
          self.showModalNotice("success", "Copied.");
          return;
        }
      } catch (e) {
        // fall through to browser
      }

      // Browser fallback
      if (navigator.clipboard?.writeText) {
        await navigator.clipboard.writeText(text);
        self.showModalNotice("success", "Copied.");
      } else {
        const ta = document.createElement("textarea");
        ta.value = text;
        ta.style.position = "fixed";
        ta.style.opacity = "0";
        document.body.appendChild(ta);
        ta.focus();
        ta.select();
        try {
          const ok = document.execCommand("copy");
          document.body.removeChild(ta);
          if (ok) {
            self.showModalNotice("success", "Copied.");
          } else {
            self.showModalNotice("error", "Copy failed.");
          }
        } catch (err) {
          document.body.removeChild(ta);
          self.showModalNotice("error", "Copy failed.");
        }
      }
    } catch (err) {
      console.error("[GlobalModal] copy failed:", err);
      self.showModalNotice("error", "Copy failed.");
    }
  };

  // wire up global save
  self.saveManifest = () => {
    const json = self.manifestVM.manifestPreview();
    saveManifestWithDialog(json, "manifest.json", self);
  };

  // Introspect DB
  self.introspectDatabase = () => self.manifestVM.introspectDatabase();

  // initial load of settings & maximize
  self.init = () => {
    sendDotnetCommand("GetStartupSettings", {})
      .then(resp => {
        console.log(resp);
        if (resp.Success) {
          const p = resp.Payload;
          self.manifestVM.restoreSettings(p.ConnectionString, p.DbPrefix, p.InstallerClassName, parseBool(p.IncludeSeedData));
        }
      });
    sendDotnetCommand("MaximizeWindow", {});
  };
}

const appVM = new AppViewModel();
ko.applyBindings(appVM);
appVM.init();
