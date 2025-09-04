/* global ko, sendDotnetCommand, VERBOSE_LOGGING */

window.InstallerViewModel = function InstallerViewModel(parent) {
  const self = this;
  self.parent = parent;

  // Raw manifest as received (camelCase from backend ParseInstallerManifest)
  self.manifest = ko.observable(null);

  // UI fields/overrides
  self.connectionString = ko.observable("");
  self.dbPrefixOverride = ko.observable("");
  self.classNameOverride = ko.observable("");
  self.includeInstallerStub = ko.observable(true);

  // Optional global seed toggle
  self.includeSeedDataOverride = ko.observable(false);

  // Grids
  self.tableRows = ko.observableArray([]);     // { type:'table', name, included, includeSeed, ref }
  self.viewRows = ko.observableArray([]);      // { type:'view', name, included, ref }
  self.procRows = ko.observableArray([]);      // { type:'storedProcedure', name, included, ref }
  self.triggerRows = ko.observableArray([]);   // { type:'trigger', name, included, ref }

  self.selectedFilePath = ko.observable("");

  // ---------- File chooser / Parse manifest ----------
  self.chooseManifestFile = async function () {
    try {
      const resp = await sendDotnetCommand("ShowOpenFileDialog", { Filter: "*.json" });
      if (!resp.Success || !resp.Payload?.FileToOpen) {
        if (window.VERBOSE_LOGGING) console.warn("[InstallerVM] No file selected or dialog canceled.");
        return;
      }

      self.selectedFilePath(resp.Payload.FileToOpen);

      const parseResp = await sendDotnetCommand("ParseInstallerManifest", {
        filePath: resp.Payload.FileToOpen
      });

      if (window.VERBOSE_LOGGING) console.log("[InstallerVM] ParseInstallerManifest raw resp:", parseResp);

      if (!parseResp.Success) {
        parent.showGlobalModal({
          title: "Error",
          message: parseResp.Error || "Failed to parse manifest.",
          isError: true, showButton: true, closeable: true, buttonText: "OK"
        });
        return;
      }

      // Backend now returns: { manifest: {...camelCase...}, defaultClassName, defaultDbPrefix, defaultConnectionString }
      const payload = parseResp.Payload || {};
      const manifest = payload.manifest;

      const defaultClassName = (payload.manifest && payload.manifest.installerClass) || "MyPluginInstaller";
      const defaultDbPrefix = (payload.manifest && payload.manifest.defaultPrefix) || "wp_";
      const defaultConnectionString = payload.defaultConnectionString || "";

      if (window.VERBOSE_LOGGING) {
        console.log("[InstallerVM] Extracted manifest object:", manifest);
        console.log("[InstallerVM] Defaults -> class:", defaultClassName, "prefix:", defaultDbPrefix, "connStr:", defaultConnectionString);
      }

      if (!manifest) {
        console.error("[InstallerVM] No manifest object found in payload.");
        return;
      }

      self.loadManifest(manifest);

      if (window.VERBOSE_LOGGING) {
        console.log(`[InstallerVM] After loadManifest: tables=${self.tableRows().length}, views=${self.viewRows().length}, procs=${self.procRows().length}, triggers=${self.triggerRows().length}`);
      }

      // Apply defaults
      self.classNameOverride(defaultClassName);
      self.dbPrefixOverride(defaultDbPrefix);
      self.connectionString(defaultConnectionString);
    } catch (err) {
      console.error("[InstallerVM] chooseManifestFile error:", err);
    }
  };

  // ---------- Load manifest into grids ----------
  self.loadManifest = function (manifest) {
    self.manifest(null);
    self.tableRows.removeAll();
    self.viewRows.removeAll();
    self.procRows.removeAll();
    self.triggerRows.removeAll();

    if (window.VERBOSE_LOGGING) console.log("[InstallerVM] Loading manifest (camelCase expected):", manifest);

    // Tables
    (manifest.tables || []).forEach(t => {
      const hasSeedRows = Array.isArray(t.seedData) && t.seedData.length > 0;
      const seedFlag = ko.observable(hasSeedRows);

      // Keep per-table seed flag in sync with global override
      self.includeSeedDataOverride.subscribe(globalVal => {
        seedFlag(globalVal && hasSeedRows);
      });

      self.tableRows.push({
        type: "table",
        name: t.name,
        included: ko.observable(true),
        includeSeed: seedFlag,
        ref: t
      });
    });

    // Views
    (manifest.views || []).forEach(v => {
      self.viewRows.push({
        type: "view",
        name: v.name,
        included: ko.observable(true),
        ref: v
      });
    });

    // Stored Procedures
    (manifest.storedProcedures || []).forEach(p => {
      self.procRows.push({
        type: "storedProcedure",
        name: p.name,
        included: ko.observable(true),
        ref: p
      });
    });

    // Triggers
    (manifest.triggers || []).forEach(tr => {
      self.triggerRows.push({
        type: "trigger",
        name: tr.name,
        included: ko.observable(true),
        ref: tr
      });
    });

    self.manifest(manifest);

    if (window.VERBOSE_LOGGING) {
      console.log(`[InstallerVM] Loaded counts: ${self.tableRows().length} tables, ${self.viewRows().length} views, ${self.procRows().length} procs, ${self.triggerRows().length} triggers.`);
      if (self.tableRows().length) console.log("[InstallerVM] Table names:", self.tableRows().map(r => r.name));
      if (self.viewRows().length) console.log("[InstallerVM] View names:", self.viewRows().map(r => r.name));
      if (self.procRows().length) console.log("[InstallerVM] Stored procedure names:", self.procRows().map(r => r.name));
      if (self.triggerRows().length) console.log("[InstallerVM] Trigger names:", self.triggerRows().map(r => r.name));
    }
  };

  // ---------- Build CreateInstallerDetails envelope ----------
  function buildCreateInstallerDetails(destinationZipFilePath /* optional */) {
    const original = self.manifest() || {};

    // Deep-ish clone with filtered selections; keep camelCase (server is case-insensitive)
    const filteredManifest = {
      database: original.database || "",
      generatedAt: original.generatedAt || new Date().toISOString(),
      defaultPrefix: self.dbPrefixOverride() || original.defaultPrefix || "wp_",
      installerClass: self.classNameOverride() || original.installerClass || "MyPluginInstaller",
      tables: [],
      views: [],
      storedProcedures: [],
      triggers: []
    };

    // Tables
    self.tableRows().forEach(r => {
      if (r.included()) {
        const t = { ...r.ref, includeSeedData: r.includeSeed() };
        filteredManifest.tables.push(t);
      }
    });

    // Views
    self.viewRows().forEach(r => {
      if (r.included()) filteredManifest.views.push({ ...r.ref });
    });

    // Procedures
    self.procRows().forEach(r => {
      if (r.included()) filteredManifest.storedProcedures.push({ ...r.ref });
    });

    // Triggers
    self.triggerRows().forEach(r => {
      if (r.included()) filteredManifest.triggers.push({ ...r.ref });
    });

    const details = {
      ConnectionString: self.connectionString() || "",
      DbPrefixOverride: self.dbPrefixOverride() || "",
      InstallerClassNameOverride: self.classNameOverride() || "",
      IncludeSeedDataOverride: !!self.includeSeedDataOverride(),
      DestinationZipFilePath: destinationZipFilePath || null,
      Manifest: filteredManifest
    };

    if (window.VERBOSE_LOGGING) {
      console.log("[InstallerVM] CreateInstallerFiles REQUEST details:", JSON.parse(JSON.stringify(details)));
      console.log("[InstallerVM] Selected manifest counts:", {
        tables: filteredManifest.tables.length,
        views: filteredManifest.views.length,
        procs: filteredManifest.storedProcedures.length,
        triggers: filteredManifest.triggers.length
      });
    }

    return details;
  }

  // ---------- Generate Preview (uses new files array: [{Name,Content,Type}]) ----------
  self.previewFiles = ko.observableArray([]); // [{ fileName, content, type }]
  self.selectedPreviewFile = ko.observable(null);

  self.generatePreview = async function () {
    try {
      if (!self.manifest()) {
        self.parent.showGlobalModal({
          title: "Load a Manifest",
          message: "Please choose a manifest JSON first.",
          isError: false, showButton: true, closeable: true, buttonText: "OK"
        });
        return;
      }

      const details = buildCreateInstallerDetails(null);

      self.parent.showGlobalModal({
        title: "Generating Preview",
        message: "Creating installer preview files…",
        showButton: false, closeable: false
      });

      const resp = await sendDotnetCommand("CreateInstallerFiles", details);

      self.parent.hideModal();

      if (window.VERBOSE_LOGGING) console.log("[InstallerVM] CreateInstallerFiles RESPONSE:", resp);

      if (!resp.Success) {
        self.parent.showGlobalModal({
          title: "Preview Failed",
          message: resp.Error || "Unknown error while generating preview.",
          isError: true, showButton: true, closeable: true, buttonText: "OK"
        });
        return;
      }

      const serverFiles = (resp.Payload && resp.Payload.files) || [];

      // Filter out stub if user unchecked "Include Installer Stub"
      const filtered = serverFiles
        .filter(f => !!f && !!f.Name)
        .filter(f => self.includeInstallerStub() || (f.Type !== "InstallerStub" && f.Type !== "MainPlugin"))
        .map(f => ({ fileName: f.Name, content: f.Content || "", type: f.Type || "" }));

      self.previewFiles(filtered);
      self.selectedPreviewFile(filtered[0] || null);

      if (window.VERBOSE_LOGGING) {
        console.log("[InstallerVM] Preview files:", filtered.map(f => f.fileName));
      }

      if (!filtered.length) {
        self.parent.showGlobalModal({
          title: "No Preview Files",
          message: "No files were returned from the generator.",
          isError: false, showButton: true, closeable: true, buttonText: "OK"
        });
      }
    } catch (err) {
      self.parent.hideModal();
      console.error("[InstallerVM] generatePreview error:", err);
      self.parent.showGlobalModal({
        title: "Error",
        message: (err && err.message) || String(err),
        isError: true, showButton: true, closeable: true, buttonText: "OK"
      });
    }
  };

  // ---------- Preview actions ----------
  // ---------- Preview actions ----------
  self.copyPreviewToClipboard = async function () {
    const f = self.selectedPreviewFile();
    if (!f) return;

    // Host clipboard first
    try {
      const resp = await sendDotnetCommand("CopyText", { text: f.content });
      if (resp && resp.Success) {
        self.parent.showModalNotice("success", "Copied to clipboard.");
        return;
      }
    } catch (_) { /* fall through */ }

    // Browser fallback
    if (navigator.clipboard?.writeText) {
      navigator.clipboard.writeText(f.content)
        .then(() => self.parent.showModalNotice("success", "Copied to clipboard."))
        .catch(() => self.parent.showModalNotice("error", "Copy failed."));
    } else {
      try {
        const ta = document.createElement("textarea");
        ta.value = f.content;
        ta.style.position = "fixed";
        ta.style.opacity = "0";
        document.body.appendChild(ta);
        ta.select();
        const ok = document.execCommand("copy");
        document.body.removeChild(ta);
        self.parent.showModalNotice(ok ? "success" : "error", ok ? "Copied to clipboard." : "Copy failed.");
      } catch (e) {
        self.parent.showModalNotice("error", "Copy failed.");
      }
    }
  };

  self.savePreviewToDisk = async function () {
    const f = self.selectedPreviewFile();
    if (!f) return;
    const saveResp = await sendDotnetCommand("ShowSaveDialog", {
      SuggestedFilename: f.fileName,
      Filter: "*.*"
    });
    if (!saveResp.Success || !saveResp.Payload?.Path) return;

    const writeResp = await sendDotnetCommand("WriteFile", {
      Path: saveResp.Payload.Path,
      Data: f.content
    });

    if (window.VERBOSE_LOGGING) console.log("[InstallerVM] savePreviewToDisk WriteFile resp:", writeResp);

    if (writeResp.Success) {
      self.parent.showGlobalModal({
        title: "Saved",
        message: `File saved to:<br><code>${saveResp.Payload.Path}</code>`,
        showButton: true, closeable: true, buttonText: "OK"
      });
    } else {
      self.parent.showGlobalModal({
        title: "Error Saving",
        message: writeResp.Error || "Unknown error",
        isError: true, showButton: true, closeable: true, buttonText: "OK"
      });
    }
  };

  self.createZipOverwrite = function (path, files) {
    var details = {};
    details.DestinationZipFilePath = path;
    details.PreviewFiles = files;
    details.AllowOverwrite = true;
    let resp = sendDotnetCommand("CreateInstallerZip", details).then(function (result) {
      if (result && result.Success) {
        self.parent.showGlobalModal({
          title: "ZIP created",
          message: "Saved to:\n" + path,
          variant: "success",
          closeable: true
        });
      }
    });

  };

  // ---------- ZIP (server zips; we just send details + chosen path) ----------
  self.createZip = async function () {
    const files = (self.previewFiles && self.previewFiles()) || [];
    if (!files.length) {
      self.parent.showGlobalModal({
        title: "No preview yet",
        message: "Please generate a preview (Create Installer Files) before creating a ZIP.",
        variant: "danger",
        closeable: true
      });
      return;
    }

    // Ask where to save
    const suggested = (self.manifest && typeof self.manifest === "function" && self.manifest()
      && self.manifest().installerClass)
      ? (self.manifest().installerClass + ".zip")
      : "wp-plugin.zip";

    const saveResp = await sendDotnetCommand("ShowSaveDialog", {
      SuggestedFilename: suggested,
      Filter: "Zip Archive (*.zip)|*.zip"
    });
    if (!saveResp || !saveResp.Success || !saveResp.Payload || !saveResp.Payload.Path) return;

    const path = saveResp.Payload.Path;
    const fileName = saveResp.Payload.FileName || (path.split(/[\\/]/).pop() || suggested);

    const fileExistsCheck = await sendDotnetCommand("CheckIfFileAlreadyExists", { Path: path });

    if (!fileExistsCheck || !fileExistsCheck.Success) {
      self.parent.showGlobalModal({
        title: "Path error",
        message: (fileExistsCheck && fileExistsCheck.Error) || "Could not validate the destination path.",
        variant: "danger",
        closeable: true
      });
      return;
    }

    if (fileExistsCheck.Payload && fileExistsCheck.Payload.Exists) {
      self.parent.showGlobalModalConfirm({
        title: 'Overwrite Existing File?',
        message: 'The file ' + fileName + ' already exists. Overwrite?',
        confirmYesText: 'Overwrite',
        confirmCancelText: 'Cancel',
        onOk: function () { self.createZipOverwrite(path, files); }
      });
      return;
    } else {
      self.createZipOverwrite(path, files);
      return;
    }
  };


  // ---------- Include/Exclude helpers ----------
  self.includeAll = function (type) {
    const map = { table: self.tableRows, view: self.viewRows, procedure: self.procRows, trigger: self.triggerRows };
    const arr = map[type]?.();
    if (!arr) return;
    arr.forEach(r => r.included(true));
  };
  self.excludeAll = function (type) {
    const map = { table: self.tableRows, view: self.viewRows, procedure: self.procRows, trigger: self.triggerRows };
    const arr = map[type]?.();
    if (!arr) return;
    arr.forEach(r => r.included(false));
  };
};
