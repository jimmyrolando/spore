import QtQuick
import Quickshell
import Quickshell.Io

// Pairing a Bluetooth device with an agent: while it's under way, bluetoothctl
// runs as BlueZ's default agent (it can show a code and ask yes or no), and
// what it shows or asks goes to the Control Center's Bluetooth page: the code
// to type on a keyboard, or the one to compare with a phone's. With no agent,
// BlueZ only paired what asks nothing (headphones, mice), and a keyboard
// failed. bluetoothctl only runs during a pairing; then it quits, and BlueZ
// drops the agent.
//
// Here, not in the page: the Control Center can close while the person types
// the code. The device becomes trusted once it's paired (so it reconnects by
// itself), not before: a device that failed to pair would stay trusted,
// allowed to connect and use services without asking.
Scope {
    id: root

    // The device being paired (a BluetoothDevice), or null.
    property var device: null
    // What the pairing needs from the person: "" (nothing, yet), "type" (type
    // `code` on the device, a keyboard, then Enter), "confirm" (does the device
    // show `code` too?) or "accept" (pair with it?).
    property string request: ""
    property string code: ""

    // bluetoothctl registered as the default agent.
    property bool agentReady: false
    // The device was seen paired (and made trusted).
    property bool done: false
    // bluetoothctl runs started for this pairing: one more if it ends on its
    // own, not a loop (it starts but can't reach BlueZ).
    property int starts: 0

    function pair(target: var): void {
        if (device) cancel()
        device = target
        request = ""
        code = ""
        output = ""
        agentReady = false
        done = false
        starts = 0
        // bluetoothctl isn't there, or doesn't answer: it pairs without.
        noAgent.restart()
        // The last one may still be quitting: a new one starts once it's gone.
        if (agent.running) agent.running = false
        else startAgent()
    }

    function cancel(): void {
        if (device && device.pairing) device.cancelPair()
        finish()
    }

    // The answer to "confirm" or "accept".
    function answer(yes: bool): void {
        if (request !== "confirm" && request !== "accept") return
        agent.write(yes ? "yes\n" : "no\n")
        request = ""
        code = ""
    }

    function finish(): void {
        noAgent.stop()
        linger.stop()
        settle.stop()
        if (agent.running) {
            agent.write("quit\n")
            quitTimeout.restart()
        }
        device = null
        request = ""
        code = ""
        agentReady = false
    }

    function startAgent(): void {
        starts++
        agent.began = false
        agent.running = true
    }

    // The agent is ready, or there won't be one: pairing starts.
    function startPairing(): void {
        noAgent.stop()
        if (device && !device.paired && !device.pairing) device.pair()
    }

    Timer {
        id: noAgent
        interval: 3000
        onTriggered: {
            console.warn("Bluetooth: bluetoothctl didn't register an agent: pairing without one")
            root.startPairing()
        }
    }

    // Once paired, the device may still ask to use a service (a keyboard's
    // input, right after) before it's trusted: the agent stays a moment.
    Timer {
        id: linger
        interval: 5000
        onTriggered: root.finish()
    }

    // Pairing stopped without the device paired: BlueZ may report it paired
    // an instant later, so it waits a moment before giving up.
    Timer {
        id: settle
        interval: 2000
        onTriggered: if (root.device && !root.device.paired) root.finish()
    }

    Timer {
        id: quitTimeout
        interval: 2000
        onTriggered: agent.running = false
    }

    Connections {
        target: root.device
        ignoreUnknownSignals: true
        function onPairedChanged(): void {
            if (!root.device.paired || root.done) return
            root.done = true
            settle.stop()
            root.device.trusted = true
            root.request = ""
            root.code = ""
            linger.restart()
        }
        function onPairingChanged(): void {
            if (!root.device.pairing && !root.device.paired) settle.restart()
        }
    }

    // What bluetoothctl printed and isn't a whole line yet: its questions
    // ("… (yes/no): ") don't end in one until they're answered.
    property string output: ""

    function heard(data: string): void {
        output += data.replace(/\x1b\[[0-9;?]*[A-Za-z]|[\r\x01\x02]/g, "")
        const lines = output.split("\n")
        output = lines.pop()
        for (const line of lines) {
            if (line.includes("Default agent request successful")) {
                agentReady = true
                startPairing()
            } else if (/Failed to (register agent|request default agent)|No agent is registered/.test(line)) {
                console.warn("Bluetooth: " + line.trim())
                startPairing()
            }
            const shown = line.match(/\[agent\] (?:Passkey|PIN code): (\d+)/)
            if (shown) {
                request = "type"
                code = shown[1]
            }
            if (line.includes("Request canceled")) {
                request = ""
                code = ""
            }
        }
        // The question it's waiting on, if any.
        const confirm = output.match(/Confirm passkey (\d+) \(yes\/no\):\s*$/)
        if (confirm) {
            request = "confirm"
            code = confirm[1]
        } else if (/Accept pairing \(yes\/no\):\s*$/.test(output)) {
            request = "accept"
            code = ""
        } else if (/Authorize service \S+ \(yes\/no\):\s*$/.test(output)) {
            // The device being paired, connecting right after (a keyboard's
            // input): bluetoothctl only runs during a pairing.
            agent.write("yes\n")
        } else if (/Enter PIN code:\s*$/.test(output)) {
            // An old device with a fixed PIN (old keyboards get a PIN code
            // shown instead, above): the usual one.
            agent.write("0000\n")
        } else if (/Enter passkey .*:\s*$/.test(output)) {
            console.warn("Bluetooth: the device wants a code typed here, which Spore doesn't do")
            cancel()
        }
    }

    Process {
        id: agent
        // Whether this run started: one that can't (no bluetoothctl) only
        // turns `running` off.
        property bool began: false
        command: ["bluetoothctl"]
        stdinEnabled: true
        stdout: SplitParser {
            // As it comes: a question doesn't end in a newline.
            splitMarker: ""
            onRead: (data) => root.heard(data)
        }
        onStarted: {
            began = true
            // A display and a keyboard: a keyboard pairs by typing a code
            // shown here, a phone by comparing one.
            write("agent KeyboardDisplay\ndefault-agent\n")
        }
        onRunningChanged: {
            if (running) return
            quitTimeout.stop()
            if (!root.device) return
            // It couldn't start: pairing goes on without it. Or the last one
            // just ended (or this one did, on its own): another one.
            if (!began) Qt.callLater(root.startPairing)
            else if (!root.done && root.starts < 2) Qt.callLater(root.startAgent)
        }
    }
}
