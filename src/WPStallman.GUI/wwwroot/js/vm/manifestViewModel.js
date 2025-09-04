// js/vm/manifestViewModel.js
function ManifestViewModel(parent) {
  var self = this;

  self.parent = parent;

  // --- Settings and state ---
  self.connectionString = ko.observable("server=localhost;uid=root;pwd=;database=wp_my_plugin");
  self.dbPrefix = ko.observable("wp_");
  self.installerClassName = ko.observable("MyPlugin_Installer");
  self.includeSeedData = ko.observable(true);
  self.manifestStatus = ko.observable("");
  // Badge state
  self.manifestCopied = self.manifestCopied || ko.observable(false);
  self.manifestCopiedFading = self.manifestCopiedFading || ko.observable(false);
  self._copiedFadeTimer && clearTimeout(self._copiedFadeTimer);
  self._copiedHideTimer && clearTimeout(self._copiedHideTimer);
  self._copiedFadeTimer = null;
  self._copiedHideTimer = null;

  // Show "Copied!" then fade it out before hiding
  self.flashCopied = function (visibleMs = 1200, fadeMs = 600) {
    // reset any in-flight timers
    if (self._copiedFadeTimer) clearTimeout(self._copiedFadeTimer);
    if (self._copiedHideTimer) clearTimeout(self._copiedHideTimer);
    self.manifestCopiedFading(false);

    self.manifestCopied(true);

    // start fade after visibleMs
    self._copiedFadeTimer = setTimeout(function () {
      self.manifestCopiedFading(true);
      // fully hide after fadeMs
      self._copiedHideTimer = setTimeout(function () {
        self.manifestCopied(false);
        self.manifestCopiedFading(false);
      }, fadeMs);
    }, visibleMs);
  };

  self.initialized = ko.observable(false);

  // Holds all fetched manifest data
  self.fullManifest = ko.observable(null);
  // Holds UI selection wrappers
  self.entities = ko.observableArray([]);

  // Categorized by type
  self.entitiesByType = {
    table: ko.pureComputed(function () {
      return ko.utils.arrayFilter(self.entities(), function (e) { return e.type === 'table'; });
    }),
    view: ko.pureComputed(function () {
      return ko.utils.arrayFilter(self.entities(), function (e) { return e.type === 'view'; });
    }),
    'stored procedure': ko.pureComputed(function () {
      return ko.utils.arrayFilter(self.entities(), function (e) { return e.type === 'stored procedure'; });
    }),
    trigger: ko.pureComputed(function () {
      return ko.utils.arrayFilter(self.entities(), function (e) { return e.type === 'trigger'; });
    })
  };

  // --- "Select All" controls ---
  self.allTablesSelected = ko.observable(true);
  self.allTablesSelected.subscribe(function (newValue) {
    self.toggleEntitySelected('table', newValue);
  });

  self.anyTablesSelected = ko.pureComputed(function () {
    var selected = ko.utils.arrayFilter(self.entities(), function (e) {
      return e.type === 'table' && e.include();
    });
    return selected.length > 0;
  });

  self.allTableSeedsSelected = ko.observable(true);
  self.allTableSeedsSelected.subscribe(function (newValue) {
    self.toggleTablesSeeded(newValue);
  });

  self.allViewsSelected = ko.observable(true);
  self.allViewsSelected.subscribe(function (newValue) {
    self.toggleEntitySelected('view', newValue);
  });

  self.allStoredProceduresSelected = ko.observable(true);
  self.allStoredProceduresSelected.subscribe(function (newValue) {
    self.toggleEntitySelected('stored procedure', newValue);
  });

  self.allTriggersSelected = ko.observable(true);
  self.allTriggersSelected.subscribe(function (newValue) {
    self.toggleEntitySelected('trigger', newValue);
  });

  // --- Entity wrapper constructor ---
  function EntityWrapper(type, raw, include, includeSeed) {
    this.type = type;
    this.raw = raw;
    this.include = ko.observable(include);
    this.includeSeed = ko.observable(includeSeed);
  }

  // --- Load manifest data ---
  self.loadManifest = function (manifestData) {
    self.fullManifest(manifestData);
    var wrappers = [];
    var tbls = manifestData.Tables || manifestData.tables || [];
    for (var i = 0; i < tbls.length; i++) {
      wrappers.push(new EntityWrapper('table', tbls[i], true, true));
    }
    var vws = manifestData.Views || manifestData.views || [];
    for (var j = 0; j < vws.length; j++) {
      wrappers.push(new EntityWrapper('view', vws[j], true, false));
    }
    var sps = manifestData.StoredProcedures || manifestData.storedProcedures || [];
    for (var k = 0; k < sps.length; k++) {
      wrappers.push(new EntityWrapper('stored procedure', sps[k], true, false));
    }
    var trg = manifestData.Triggers || manifestData.triggers || [];
    for (var m = 0; m < trg.length; m++) {
      wrappers.push(new EntityWrapper('trigger', trg[m], true, false));
    }
    self.entities(wrappers);
  };

  // --- Computeds for "select all" UI states ---
  self.allIncludeChecked = {
    table: ko.pureComputed({
      read: function () {
        var arr = self.entitiesByType.table();
        return arr.length && ko.utils.arrayEvery(arr, function (e) { return e.include(); });
      },
      write: function (val) {
        ko.utils.arrayForEach(self.entitiesByType.table(), function (e) { e.include(val); });
      }
    }),
    view: ko.pureComputed({
      read: function () {
        var arr = self.entitiesByType.view();
        return arr.length && ko.utils.arrayEvery(arr, function (e) { return e.include(); });
      },
      write: function (val) {
        ko.utils.arrayForEach(self.entitiesByType.view(), function (e) { e.include(val); });
      }
    }),
    'stored procedure': ko.pureComputed({
      read: function () {
        var arr = self.entitiesByType['stored procedure']();
        return arr.length && ko.utils.arrayEvery(arr, function (e) { return e.include(); });
      },
      write: function (val) {
        ko.utils.arrayForEach(self.entitiesByType['stored procedure'](), function (e) { e.include(val); });
      }
    }),
    trigger: ko.pureComputed({
      read: function () {
        var arr = self.entitiesByType.trigger();
        return arr.length && ko.utils.arrayEvery(arr, function (e) { return e.include(); });
      },
      write: function (val) {
        ko.utils.arrayForEach(self.entitiesByType.trigger(), function (e) { e.include(val); });
      }
    })
  };

  // For table seed toggles
  self.allSeedChecked = {
    table: ko.pureComputed({
      read: function () {
        var arr = self.entitiesByType.table();
        return arr.length && ko.utils.arrayEvery(arr, function (e) { return e.includeSeed(); });
      },
      write: function (val) {
        ko.utils.arrayForEach(self.entitiesByType.table(), function (e) { e.includeSeed(val); });
      }
    })
  };

  self.toggleEntitySelected = function (entityType, selected) {
    ko.utils.arrayForEach(self.entities(), function (entity) {
      if (entity.type === entityType) {
        entity.include(selected);
      }
    });
  };

  self.toggleTablesSeeded = function (includeSeed) {
    ko.utils.arrayForEach(self.entities(), function (entity) {
      if (entity.type === 'table') {
        entity.includeSeed(includeSeed);
      }
    });
  };

  // --- Manifest JSON Preview ---
  self.manifestPreview = ko.pureComputed(function () {
    var full = self.fullManifest();
    if (!full) {
      return "";
    }
    function filterEntities(srcArr, arrType) {
      var sel = ko.utils.arrayFilter(self.entitiesByType[arrType](), function (e) { return e.include(); });
      if (arrType === 'table') {
        return ko.utils.arrayMap(sel, function (e) {
          var clone = {};
          for (var key in e.raw) {
            if (key.toLowerCase() === 'name') {
              clone.name = e.raw[key];
            } else if (key.toLowerCase() !== 'seed') {
              clone[key.charAt(0).toLowerCase() + key.slice(1)] = e.raw[key];
            }
          }
          clone.seed = e.includeSeed();
          return clone;
        });
      }
      return ko.utils.arrayMap(sel, function (e) {
        var clone = {};
        for (var key in e.raw) {
          if (key.toLowerCase() === 'name') {
            clone.name = e.raw[key];
          } else {
            clone[key.charAt(0).toLowerCase() + key.slice(1)] = e.raw[key];
          }
        }
        return clone;
      });
    }
    var result = {
      database: full.database || full.Database,
      generatedAt: full.generatedAt || full.GeneratedAt,
      defaultPrefix: full.defaultPrefix || full.DefaultPrefix,
      installerClass: self.installerClassName(),
      includeSeedData: self.includeSeedData(),
      tables: filterEntities(full.tables ||
        full.Tables, 'table'),
      views: filterEntities(full.views || full.Views, 'view'),
      storedProcedures: filterEntities(full.storedProcedures || full.StoredProcedures, 'stored procedure'),
      triggers: filterEntities(full.triggers || full.Triggers, 'trigger')
    };
    return JSON.stringify(result, null, 2);
  });

  // --- DB Introspection ---
  self.introspectDatabase = function () {
    parent.showGlobalModal({
      title: 'Connecting to Database',
      message: 'Inspecting database and generating manifest. Please wait...',
      showButton: false,
      closeable: false,
      isError: false
    });

    setTimeout(function () {
      // after
      sendDotnetCommand("IntrospectDatabase", {
        ConnectionString: self.connectionString(),
        DbPrefix: self.dbPrefix(),
        InstallerClassName: self.installerClassName(),
        IncludeSeedData: self.includeSeedData()
      })
        .then(function (resp) {
          parent.hideModal();
          if (resp.Success && resp.Payload) {
            self.loadManifest(JSON.parse(resp.Payload));
            self.manifestStatus("Manifest generated.");
          } else {
            self.manifestStatus("Error: " + (resp.Error || "Failed to introspect database."));

            parent.showGlobalModal({
              title: "Error",
              message: resp.Error || "Failed to introspect database.",
              isError: true,
              showButton: true,
              closeable: true,
              buttonText: "OK"
            });
          }
        });
    }, 150);
  };

  // --- Save & Copy ---
  // --- Save Manifest to disk ---
  /*   self.saveManifest = function () {
      const content = self.manifestPreview && self.manifestPreview();
      if (!content || !content.trim?.()) {
        self.parent.showGlobalModal({
          title: "Nothing to Save",
          message: "Generate a manifest first.",
          isError: true,
          showButton: true,
          closeable: true,
          buttonText: "OK"
        });
        return;
      }
  
      const filename = generateTimestampFileName("manifest", "json");
      saveManifestWithDialog(content, filename, self.parent);
    }; */

  // Helper: build the manifest JSON text safely
  function buildManifestJsonSafely(self) {
    try {
      if (typeof self.buildManifestJson === "function") {
        return self.buildManifestJson();
      }
      if (typeof self.manifestJson === "function") {
        return self.manifestJson();
      }
      if (typeof self.manifest === "function" && self.manifest()) {
        return JSON.stringify(ko.toJS(self.manifest()), null, 2);
      }
      return null;
    } catch (err) {
      return { __error: err };
    }
  }

  self.saveManifest = async function () {
    // 1) Get JSON
    /*     const jsonOrErr = buildManifestJsonSafely(self);
        if (!jsonOrErr || jsonOrErr.__error) {
          (self.parent.showGlobalModalError || self.parent.showGlobalModal)({
            title: "Cannot save manifest",
            message: jsonOrErr && jsonOrErr.__error ? String(jsonOrErr.__error) : "No manifest data available.",
            closeable: true
          });
          return;
        } */

    const content = self.manifestPreview && self.manifestPreview();
    if (!content || !content.trim?.()) {
      self.parent.showGlobalModal({
        title: "Nothing to Save",
        message: "Generate a manifest first.",
        isError: true,
        showButton: true,
        closeable: true,
        buttonText: "OK"
      });
      return;
    }

    // 2) Ask where to save
    const suggested =
      (typeof self.manifest === "function" && self.manifest() && self.manifest().installerClass)
        ? (self.manifest().installerClass + "-manifest.json")
        : "manifest.json";

    let dlg;
    try {
      dlg = await sendDotnetCommand("ShowSaveDialog", {
        SuggestedFilename: suggested,
        Filter: "JSON (*.json)|*.json"
      });
    } catch (e) {
      (self.parent.showGlobalModalError || self.parent.showGlobalModal)({
        title: "Save dialog failed",
        message: String(e && e.message || e || "Unknown error"),
        closeable: true
      });
      return;
    }
    if (!dlg || !dlg.Success || !dlg.Payload || !dlg.Payload.Path) {
      // user cancelled
      return;
    }

    const path = dlg.Payload.Path;
    const fileName = dlg.Payload.FileName || path.split(/[\\/]/).pop();

    // 3) Check if file exists
    let check;
    try {
      check = await sendDotnetCommand("CheckIfFileAlreadyExists", { Path: path });
    } catch (e) {
      (self.parent.showGlobalModalError || self.parent.showGlobalModal)({
        title: "Path check failed",
        message: String(e && e.message || e || "Unknown error"),
        closeable: true
      });
      return;
    }
    if (!check || !check.Success) {
      (self.parent.showGlobalModalError || self.parent.showGlobalModal)({
        title: "Invalid path",
        message: (check && check.Error) || "Could not validate the destination path.",
        closeable: true
      });
      return;
    }
    if (check.Payload && check.Payload.DirectoryExists === false) {
      (self.parent.showGlobalModalError || self.parent.showGlobalModal)({
        title: "Folder not found",
        message: `The folder "${check.Payload.Directory}" does not exist.`,
        closeable: true
      });
      return;
    }

    const doWrite = async () => {
      try {
        const write = await sendDotnetCommand("WriteFile", { Path: path, Data: content });
        if (!write || !write.Success) {
          (self.parent.showGlobalModalError || self.parent.showGlobalModal)({
            title: "Could not save manifest",
            message: (write && write.Error) || "Unknown error",
            closeable: true
          });
          return;
        }
          self.parent.showGlobalModal({
            title: "Manifest Saved",
            message: "Saved to:\n" + path,
            showButton: true,
            closeable: true,
            buttonText: "OK"
          });
      } catch (e) {
        (self.parent.showGlobalModalError || self.parent.showGlobalModal)({
          title: "Write failed",
          message: String(e && e.message || e || "Unknown error"),
          closeable: true
        });
      }
    };

    // 4) If exists → confirm overwrite; else write immediately
    if (check.Payload && check.Payload.Exists) {
      self.parent.showGlobalModalConfirm({
        title: 'Overwrite Existing File?',
        message: `A file named "${fileName}" already exists. Overwrite it?`,
        confirmYesText: 'Overwrite',
        confirmCancelText: 'Cancel',
        onOk: doWrite
      });
      /*       self.parent.showGlobalModal({
              title: "Replace existing file?",
              message: `A file named "${fileName}" already exists. Overwrite it?`,
              variant: "warning",
              okText: "Overwrite",
              cancelText: "Cancel",
              isConfirm: true,
              closeable: true,
              onOk: doWrite
            }); */
    } else {
      await doWrite();
    }
  };


  self.copyManifest = function () {
    const content = self.manifestPreview && self.manifestPreview();
    if (!content) return;


    // Prefer native host clipboard
    try {
      if (typeof sendDotnetCommand === "function") {
        Promise.resolve(sendDotnetCommand("CopyText", { text: content }))
          .then(function (resp) {
            if (resp && resp.Success) {
              self.flashCopied();
            } else {
              browserFallback();
            }
          })
          .catch(browserFallback);
        return;
      }
    } catch (e) {
      // fall through to browser
    }

    browserFallback();

    function browserFallback() {
      if (navigator.clipboard && navigator.clipboard.writeText) {
        navigator.clipboard.writeText(content)
          .then(flashCopied)
          .catch(domExecFallback);
      } else {
        domExecFallback();
      }
    }

    function domExecFallback() {
      try {
        const ta = document.createElement("textarea");
        ta.value = content;
        ta.style.position = "fixed";
        ta.style.opacity = "0";
        document.body.appendChild(ta);
        ta.select();
        const ok = document.execCommand("copy");
        document.body.removeChild(ta);
        if (ok) flashCopied();
      } catch (_) {
        // Silent failure: keep UI unchanged
      }
    }
  };


  // --- Restore settings on startup ---
  self.restoreSettings = function (connDef, prefixDef, instClassDef, includeDef) {
    if (self.initialized()) { return; }
    self.connectionString(connDef);
    self.dbPrefix(prefixDef);
    self.installerClassName(instClassDef);
    self.includeSeedData(includeDef);
    self.initialized(true);
  };

  // In ManifestViewModel constructor
  self.includeAll = function (typeKey) {
    var arr = self.entitiesByType[typeKey] ? self.entitiesByType[typeKey]() : [];
    arr.forEach(function (row) { if (ko.isObservable(row.include)) row.include(true); });
  };
  self.excludeAll = function (typeKey) {
    var arr = self.entitiesByType[typeKey] ? self.entitiesByType[typeKey]() : [];
    arr.forEach(function (row) { if (ko.isObservable(row.include)) row.include(false); });
  };

  // --- Seed helpers (tables only) ---

  // Generic: set includeSeed(true) on rows that have it.
  // opts.onlyIncluded === true → only seed rows whose include() is true.
  self.seedAll = function (typeKey, opts) {
    var arr = self.entitiesByType[typeKey] ? self.entitiesByType[typeKey]() : [];
    var onlyIncluded = !!(opts && opts.onlyIncluded);
    arr.forEach(function (row) {
      var canSeed = ko.isObservable(row.includeSeed);
      if (!canSeed) return;
      if (onlyIncluded) {
        var isIncluded = ko.isObservable(row.include) ? !!row.include() : !!row.include;
        if (!isIncluded) return;
      }
      row.includeSeed(true);
    });
  };

  // Generic: set includeSeed(false) on rows that have it.
  self.seedNone = function (typeKey) {
    var arr = self.entitiesByType[typeKey] ? self.entitiesByType[typeKey]() : [];
    arr.forEach(function (row) {
      if (ko.isObservable(row.includeSeed)) row.includeSeed(false);
    });
  };

  // Convenience wrappers for tables (keeps bindings clean)
  self.seedAllTables = function () { self.seedAll('table', { onlyIncluded: true }); }; // seeds included tables
  self.seedNoneTables = function () { self.seedNone('table'); };

}
