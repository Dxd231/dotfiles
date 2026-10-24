pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// One place that says which of the shell's outside dependencies are up: the mpv socket, AnkiConnect,
// the Yomitan API, the lexicon worker, the OCR engines, the Texthooker relay, AniList and the Jimaku
// key. Nothing is probed here; every check reads a status the owning service already keeps. `idle`
// marks something that is simply not in use (no mpv open, an OCR engine unloaded), which is not a
// problem. There is no UI: `qs ipc call health report` prints a readable list, `check` the same as JSON.
Singleton {
    id: health

    readonly property var checks: [
        { id: "mpv", label: "mpv socket", ok: Mpv.connected, idle: !Mpv.connected, detail: Mpv.connected ? "Linked" : "No player open" },
        { id: "anki", label: "AnkiConnect", ok: Anki.online, idle: false, detail: Anki.online ? "Online" : "Anki is closed or AnkiConnect is off" },
        { id: "yomitan", label: "Yomitan API", ok: Lexicon.yomitanUp, idle: false, detail: Lexicon.yomitanUp ? "Online" : "LibreWolf is closed or the API is off" },
        { id: "lexicon", label: "Lexicon worker", ok: Lexicon.ready, idle: false, detail: Lexicon.ready ? "Ready" : "Not started" },
        { id: "ocr", label: "OCR engines", ok: Ocr.mangaReady || Ocr.paddleReady, idle: !(Ocr.mangaReady || Ocr.paddleReady),
          detail: Ocr.mangaReady && Ocr.paddleReady ? "Manga and Paddle loaded" : Ocr.mangaReady ? "Manga loaded" : Ocr.paddleReady ? "Paddle loaded" : "Unloaded until used" },
        { id: "relay", label: "Texthooker relay", ok: Ocr.relayUp, idle: false, detail: Ocr.relayUp ? "Connected" : "Relay is not answering" },
        { id: "anilist", label: "AniList", ok: AniList.connected, idle: !AniList.connected, detail: AniList.connected ? "Signed in" : "Not signed in" },
        { id: "jimaku", label: "Jimaku key", ok: Jimaku.hasKey && Jimaku.keyError === "", idle: false,
          detail: !Jimaku.hasKey ? "No key saved" : Jimaku.keyError !== "" ? Jimaku.keyError : "Key saved" }
    ]

    // checks that are neither fine nor merely unused
    readonly property int problems: checks.filter(c => !c.ok && !c.idle).length

    function refresh() {
        Lexicon.request({ op: "status" }, r => { Lexicon.yomitanUp = r.yomitan === true; Lexicon.knownWords = r.words || 0; });
        Anki.refresh();
    }

    IpcHandler {
        target: "health"
        function check(): string {
            return JSON.stringify({ problems: health.problems, checks: health.checks });
        }
        function report(): string {
            const rows = health.checks.map(c => (c.ok ? "ok    " : c.idle ? "idle  " : "DOWN  ") + c.label.padEnd(18) + c.detail);
            rows.push("", health.problems === 0 ? "All good" : health.problems + (health.problems === 1 ? " problem" : " problems"));
            return rows.join("\n");
        }
        function refresh(): void { health.refresh(); }
    }
}
