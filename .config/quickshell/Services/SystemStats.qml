pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io

// Shared CPU / memory / thermal / disk readings, read straight from /proc and /sys.
// Core stats poll continuously (cheap file reads, no process spawning); the detail set
// (temperature, clock, package power, disks, uptime) only polls while something holds
// a `detailUsers` reference, e.g. the system status popup.
Singleton {
    id: stats

    // ---- core ----
    property real cpuPercent: 0
    property real memTotalKb: 0
    property real memAvailKb: 0
    property real memCacheKb: 0
    property real swapTotalKb: 0
    property real swapFreeKb: 0
    readonly property real memUsedKb: memTotalKb - memAvailKb
    readonly property real memPercent: memTotalKb > 0 ? memUsedKb / memTotalKb * 100 : 0
    readonly property real swapUsedKb: swapTotalKb - swapFreeKb
    readonly property real swapPercent: swapTotalKb > 0 ? swapUsedKb / swapTotalKb * 100 : 0

    // ---- details ----
    property int detailUsers: 0
    readonly property bool detailed: detailUsers > 0
    property real cpuTemp: 0
    property real cpuFreqMhz: 0
    property real cpuPowerW: -1
    property real uptimeSec: 0
    property string cpuModel: ""
    // [{ mount, used, size, avail, percent }]
    property var disks: []

    // the last minute of one-second samples, for the status panel's graph
    readonly property int historyLength: 60
    property var cpuHistory: []
    property var memHistory: []
    function _pushHistory() {
        const c = cpuHistory.concat([cpuPercent]);
        const m = memHistory.concat([memPercent]);
        cpuHistory = c.length > historyLength ? c.slice(c.length - historyLength) : c;
        memHistory = m.length > historyLength ? m.slice(m.length - historyLength) : m;
    }

    function gb(kb) {
        return (kb / 1048576).toFixed(1);
    }

    // CPU usage from successive /proc/stat samples
    property real _prevIdle: 0
    property real _prevTotal: 0
    FileView {
        id: procStat
        path: "/proc/stat"
        onLoaded: {
            const f = text().slice(0, text().indexOf("\n")).trim().split(/\s+/).slice(1, 9).map(Number);
            const idle = f[3] + f[4];
            const total = f.reduce((a, b) => a + b, 0);
            const dt = total - stats._prevTotal;
            if (stats._prevTotal > 0 && dt > 0)
                stats.cpuPercent = 100 * (1 - (idle - stats._prevIdle) / dt);
            stats._prevIdle = idle;
            stats._prevTotal = total;
        }
    }

    FileView {
        id: meminfo
        path: "/proc/meminfo"
        onLoaded: {
            const v = {};
            for (const line of text().split("\n")) {
                const m = line.match(/^(\w+):\s+(\d+)/);
                if (m)
                    v[m[1]] = Number(m[2]);
            }
            stats.memTotalKb = v.MemTotal || 0;
            stats.memAvailKb = v.MemAvailable || 0;
            stats.memCacheKb = (v.Buffers || 0) + (v.Cached || 0) + (v.SReclaimable || 0);
            stats.swapTotalKb = v.SwapTotal || 0;
            stats.swapFreeKb = v.SwapFree || 0;
        }
    }

    Timer {
        interval: 1000
        running: true
        repeat: true
        triggeredOnStart: true
        property int tick: 0
        onTriggered: {
            stats._pushHistory();
            procStat.reload();
            if (tick++ % 2 === 0 || stats.detailed)
                meminfo.reload();
            if (stats.detailed) {
                temp.reload();
                cpuinfo.reload();
                rapl.reload();
                uptime.reload();
            }
        }
    }

    // ---- details ----
    property string _tempPath: ""
    Process {
        running: true
        command: ["sh", "-c", "for h in /sys/class/hwmon/hwmon*; do case $(cat $h/name) in coretemp|k10temp|zenpower) echo $h/temp1_input; break;; esac; done; lscpu | sed -n 's/^Model name:[ \\t]*//p'"]
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = text.trim().split("\n");
                if (lines[0].startsWith("/sys/"))
                    stats._tempPath = lines.shift();
                stats.cpuModel = (lines[0] || "").replace(/\((R|TM)\)| CPU|@.*$/g, "").trim();
            }
        }
    }

    FileView {
        id: temp
        path: stats._tempPath
        onLoaded: stats.cpuTemp = Number(text()) / 1000
    }

    FileView {
        id: cpuinfo
        path: "/proc/cpuinfo"
        onLoaded: {
            const mhz = text().match(/cpu MHz\s*:\s*[\d.]+/g) || [];
            stats.cpuFreqMhz = mhz.length ? mhz.reduce((a, s) => a + Number(s.split(":")[1]), 0) / mhz.length : 0;
        }
    }

    // package power from RAPL energy deltas
    property real _prevEnergy: -1
    property real _prevEnergyTime: 0
    FileView {
        id: rapl
        path: "/sys/class/powercap/intel-rapl:0/energy_uj"
        printErrors: false
        onLoaded: {
            const e = Number(text());
            const now = Date.now();
            if (stats._prevEnergy >= 0 && e >= stats._prevEnergy && now > stats._prevEnergyTime)
                stats.cpuPowerW = (e - stats._prevEnergy) / ((now - stats._prevEnergyTime) * 1000);
            stats._prevEnergy = e;
            stats._prevEnergyTime = now;
        }
    }

    FileView {
        id: uptime
        path: "/proc/uptime"
        onLoaded: stats.uptimeSec = Number(text().split(" ")[0])
    }

    Process {
        id: df
        command: ["df", "-k", "--output=target,used,size,avail,pcent", "/", "/home", "/mnt/GAME_DISK"]
        stdout: StdioCollector {
            onStreamFinished: {
                const seen = {};
                const out = [];
                for (const line of text.trim().split("\n").slice(1)) {
                    const p = line.trim().split(/\s+/);
                    if (p.length < 5 || seen[p[0]])
                        continue;
                    seen[p[0]] = true;
                    out.push({ mount: p[0], usedKb: Number(p[1]), sizeKb: Number(p[2]), availKb: Number(p[3]), percent: parseFloat(p[4]) });
                }
                stats.disks = out;
            }
        }
    }
    Timer {
        interval: 15000
        running: stats.detailed
        repeat: true
        triggeredOnStart: true
        onTriggered: df.running = true
    }
}
