import QtQuick
import Quickshell
import Quickshell.Services.Pam

// Authentication state shared by all the WlSessionLockSurfaces (one per
// monitor). Separate from the UI so every monitor sees the same text/error
// at the same time.
Scope {
    id: root

    signal unlocked()

    property string currentText: ""
    property bool unlockInProgress: false
    property bool showFailure: false
    // PAM couldn't even start: what the field says instead of "Wrong password"
    // ("" = nothing wrong).
    property string error: ""

    onCurrentTextChanged: showFailure = false

    // A lock that starts: nothing typed, no error from the last one.
    function reset(): void {
        currentText = ""
        showFailure = false
        error = ""
    }

    function tryUnlock() {
        if (currentText === "") return
        unlockInProgress = true
        if (pam.start()) {
            error = ""
            return
        }
        // Without its config (no /etc/pam.d/swaylock, say), PAM doesn't start:
        // the field used to stay on "Checking…" for good, with no way to unlock.
        console.error("Lock: PAM couldn't start with " + pam.configDirectory + "/" + pam.config)
        currentText = ""
        unlockInProgress = false
        error = "Can't check passwords: no PAM “" + pam.config + "”"
    }

    PamContext {
        id: pam

        // We reuse the "swaylock" pam.d that NixOS ships by default (auth-only
        // against pam_unix, no extra session/account) instead of declaring our own
        // PAM service -- one less piece to maintain on the system side.
        config: "swaylock"

        onPamMessage: {
            if (responseRequired) respond(root.currentText)
        }

        // What was typed goes, right or wrong. Kept after a success, it was still
        // here on the next lock: the field looked empty, and Enter (or Unlock)
        // sent it to PAM again and unlocked.
        onCompleted: result => {
            const success = result === PamResult.Success
            root.currentText = ""
            root.showFailure = !success
            root.unlockInProgress = false
            if (success) root.unlocked()
        }
    }
}
