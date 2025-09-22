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
  sendDotnetCommand("ShowSaveDialog", { SuggestedFilename: suggestedFilename })
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
            title: "Success",
            message: `Manifest saved to:<br><code>${resp.Payload.Path}</code>`,
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
