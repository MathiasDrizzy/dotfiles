#!/usr/bin/env python3
"""Harness de comportamiento (ORD-dotfiles-001 C5).

Arranca un herdr REAL y aislado (HOME temporal, socket propio, config del repo
con las rutas apuntando al HOME temporal), le teclea los atajos por un pty y
observa el efecto: procesos, foco y geometría de los cuadros por la API de herdr.
No toca el herdr ni el HOME reales.

Casos:
  a) prefix+h abre el cheatsheet; `q` lo cierra; prefix+h otra vez y `Esc` lo cierra.
  b) prefix+t abre el popup de terminal; `Esc` lo cierra.
  c) prefix+m cambia el ancho del sidebar.
  d) prefix+flechas mueven el foco; prefix+Shift+flechas intercambian cuadros.
  e) prefix+shift+r ejecuta el comando del repo (pisa a reload_config).

Uso: scripts/harness-behavior.py [-v]
"""
import fcntl
import json
import os
import pty
import re
import select
import shutil
import signal
import struct
import subprocess
import sys
import tempfile
import termios
import time

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MAC = os.path.join(REPO, "mac")
VERBOSE = "-v" in sys.argv

CTRL_B = b"\x02"
KEYS = {
    "left": b"\x1b[D", "right": b"\x1b[C", "up": b"\x1b[A", "down": b"\x1b[B",
    "shift+left": b"\x1b[1;2D", "shift+right": b"\x1b[1;2C",
    "shift+up": b"\x1b[1;2A", "shift+down": b"\x1b[1;2B",
    "esc": b"\x1b",
}


def log(*a):
    if VERBOSE:
        print("   ", *a, flush=True)


class Lab:
    def __init__(self):
        # /tmp y no $TMPDIR: el socket de herdr debe caber en sun_path (104 bytes en macOS).
        self.tmp = tempfile.mkdtemp(prefix="dfh-", dir="/tmp")
        self.home = os.path.join(self.tmp, "home")
        os.makedirs(self.home)
        self.env = {k: v for k, v in os.environ.items() if not k.startswith("HERDR_") and k not in ("TERM_PROGRAM", "SSH_AUTH_SOCK")}
        self.env.update(HOME=self.home, TERM="xterm-256color", HERDR_CONFIG_PATH=os.path.join(self.tmp, "herdr.toml"))
        self.fd = None
        self.pid = None
        self.out = b""
        self.marker = os.path.join(self.tmp, "marker-shift-r")

    # ---------- preparación ----------
    def sh(self, *cmd, check=True, **kw):
        r = subprocess.run(cmd, env=self.env, capture_output=True, text=True, **kw)
        if check and r.returncode != 0:
            raise RuntimeError(f"{' '.join(cmd)} -> {r.returncode}\n{r.stdout}\n{r.stderr}")
        return r

    def prepare(self):
        # C6 también: los enlaces salen de install.sh --links-only en el HOME temporal.
        self.sh(os.path.join(MAC, "install.sh"), "--links-only")
        bindir = os.path.join(self.home, ".local", "bin")
        # herdr-ctl recién compilado del árbol, no el instalado.
        # Reusa el caché de Go real: con HOME temporal Go recrearía (y dejaría de solo lectura) uno nuevo.
        genv = dict(self.env)
        for var in ("GOMODCACHE", "GOCACHE", "GOPATH"):
            genv[var] = subprocess.run(["go", "env", var], capture_output=True, text=True).stdout.strip()
        subprocess.run(["go", "build", "-o", os.path.join(bindir, "herdr-ctl"), "."], cwd=os.path.join(MAC, "tools", "herdr-ctl"),
                       env=genv, check=True, capture_output=True, text=True)
        cfg = open(os.path.join(MAC, "config", "herdr", "config.toml")).read()
        cfg = cfg.replace("/Users/drizzy/.local/bin", bindir)
        # Sonda de que el popup de terminal arrancó (exec conserva el PID).
        probe = os.path.join(self.tmp, "popup-probe.sh")
        with open(probe, "w") as f:
            f.write(f'#!/usr/bin/env bash\necho $$ > "{self.tmp}/popup.pid"\nexec "{bindir}/terminal-popup"\n')
        os.chmod(probe, 0o755)
        cfg = cfg.replace(f"{bindir}/terminal-popup", probe)
        open(self.env["HERDR_CONFIG_PATH"], "w").write(cfg)
        self.bindir = bindir
        self.cfg = cfg

    # ---------- cliente ----------
    def start_client(self, rows=40, cols=140):
        self.pid, self.fd = pty.fork()
        if self.pid == 0:
            os.execvpe("herdr", ["herdr"], self.env)
        fcntl.ioctl(self.fd, termios.TIOCSWINSZ, struct.pack("HHHH", rows, cols, 0, 0))
        self.pump(4)

    def pump(self, secs):
        end = time.time() + secs
        while time.time() < end:
            r, _, _ = select.select([self.fd], [], [], 0.1)
            if r:
                try:
                    self.out += os.read(self.fd, 65536)
                except OSError:
                    return

    def send(self, *chunks, pause=0.4):
        for c in chunks:
            os.write(self.fd, c if isinstance(c, bytes) else c.encode())
            self.pump(pause)

    def prefix(self, key):
        """prefix + tecla; `key` es un nombre de KEYS o un carácter."""
        self.send(CTRL_B, pause=0.3)
        self.send(KEYS.get(key, key.encode() if isinstance(key, str) else key), pause=0.6)

    def wait_for(self, pred, timeout=10.0):
        end = time.time() + timeout
        while time.time() < end:
            self.pump(0.2)
            v = pred()
            if v:
                return v
        return False

    # ---------- observación ----------
    def procs(self):
        ps = subprocess.run(["ps", "-axo", "pid=,command="], capture_output=True, text=True).stdout
        return [l.strip() for l in ps.splitlines() if self.tmp in l]

    def cheatsheet_running(self):
        return any("herdr-ctl cheatsheet" in l for l in self.procs())

    def popup_pid(self):
        try:
            return int(open(os.path.join(self.tmp, "popup.pid")).read())
        except (OSError, ValueError):
            return None

    def popup_alive(self):
        pid = self.popup_pid()
        if not pid:
            return False
        try:
            os.kill(pid, 0)
        except OSError:
            return False
        return subprocess.run(["ps", "-p", str(pid), "-o", "stat="], capture_output=True, text=True).stdout.strip() not in ("", )

    def api(self, *args):
        r = self.sh("herdr", *args)
        try:
            return json.loads(r.stdout)
        except ValueError:
            return r.stdout

    def panes(self):
        return self.api("pane", "list")["result"]["panes"]

    def layout(self, pane_id):
        return self.api("pane", "layout", "--pane", pane_id)["result"]["layout"]

    def stop(self):
        # Primero el cliente (si no, `server stop` puede quedarse esperando), luego el servidor aislado.
        if self.pid:
            try:
                os.kill(self.pid, signal.SIGKILL)
                os.waitpid(self.pid, 0)
            except OSError:
                pass
        try:
            subprocess.run(["herdr", "server", "stop"], env=self.env, capture_output=True, timeout=10)
        except Exception:  # noqa: BLE001
            pass
        for root, dirs, files in os.walk(self.tmp):  # el caché de Go deja archivos de solo lectura
            for n in dirs + files:
                try:
                    os.chmod(os.path.join(root, n), 0o700 if n in dirs else 0o600)
                except OSError:
                    pass
        shutil.rmtree(self.tmp, ignore_errors=True)


RESULTS = []


def case(name):
    def deco(fn):
        def run(lab):
            try:
                ok, detail = fn(lab)
            except Exception as e:  # noqa: BLE001
                ok, detail = False, f"excepción: {e}"
            RESULTS.append((name, ok, detail))
            print(f"{'PASS' if ok else 'FAIL'}  {name}: {detail}", flush=True)
        run.__name__ = fn.__name__
        return run
    return deco


@case("a1 prefix+h abre el cheatsheet y q lo cierra")
def a1(lab):
    lab.prefix("h")
    opened = lab.wait_for(lab.cheatsheet_running, 8)
    if not opened:
        return False, "el proceso `herdr-ctl cheatsheet` no apareció"
    lab.send("q", pause=0.5)
    closed = lab.wait_for(lambda: not lab.cheatsheet_running(), 6)
    return bool(closed), "abrió y cerró con q" if closed else "q no cerró el cheatsheet"


@case("a2 prefix+h abre el cheatsheet y Esc lo cierra")
def a2(lab):
    lab.prefix("h")
    if not lab.wait_for(lab.cheatsheet_running, 8):
        return False, "el proceso `herdr-ctl cheatsheet` no apareció"
    lab.send(KEYS["esc"], pause=0.5)
    closed = lab.wait_for(lambda: not lab.cheatsheet_running(), 6)
    return bool(closed), "abrió y cerró con Esc" if closed else "Esc no cerró el cheatsheet"


@case("b prefix+t abre el popup de terminal y Esc lo cierra")
def b(lab):
    try:
        os.remove(os.path.join(lab.tmp, "popup.pid"))
    except OSError:
        pass
    lab.prefix("t")
    if not lab.wait_for(lab.popup_alive, 10):
        return False, "el popup de terminal no arrancó"
    time.sleep(4)  # zsh -l tarda en llegar al prompt (zshrc completo); Esc con buffer vacío sale
    lab.send(KEYS["esc"], pause=0.5)
    closed = lab.wait_for(lambda: not lab.popup_alive(), 8)
    return bool(closed), "abrió y cerró con Esc" if closed else "Esc no cerró el popup"


def prepare_sidebar_layout(lab):
    """Un tab con 2 cuadros; el de la izquierda se llama 'Sidebar' (lo que busca herdr-ctl adapt)."""
    first = lab.panes()[0]["pane_id"]
    lab.api("pane", "split", first, "--direction", "right", "--focus")
    lab.sh("herdr", "pane", "rename", first, "Sidebar")
    lab.pump(1)
    return first


def sidebar_ratio(lab, pane_id):
    lay = lab.layout(pane_id)
    return [round(s["ratio"], 3) for s in lay["splits"] if s["rect"]["x"] == 0 and s["direction"] == "right"]


def focused(lab):
    return [p["pane_id"] for p in lab.panes() if p.get("focused")]


def xs(lab, pane_id):
    return {p["pane_id"]: p["rect"]["x"] for p in lab.layout(pane_id)["panes"]}


@case("c prefix+m cambia el ancho del sidebar")
def c(lab):
    sb = prepare_sidebar_layout(lab)
    before = sidebar_ratio(lab, sb)
    lab.prefix("m")
    lab.pump(2)
    after = sidebar_ratio(lab, sb)
    return bool(before) and bool(after) and before != after, f"ratio del sidebar {before} -> {after}"


def pair(lab):
    ps = lab.panes()
    sb = next(p["pane_id"] for p in ps if p.get("label") == "Sidebar")
    tab = next(p["tab_id"] for p in ps if p["pane_id"] == sb)
    other = next(p["pane_id"] for p in ps if p["tab_id"] == tab and p["pane_id"] != sb)
    return sb, other


@case("d1 prefix+flechas mueven el foco")
def d1(lab):
    sb, other = pair(lab)
    lab.api("pane", "focus", "--direction", "right", "--pane", sb)  # punto de partida conocido: cuadro derecho
    lab.pump(0.5)
    start = focused(lab)
    lab.prefix("left")
    left = focused(lab)
    lab.prefix("right")
    right = focused(lab)
    return left == [sb] and right == [other], f"inicio {start}; tras prefix+← {left}; tras prefix+→ {right} (sidebar={sb}, otro={other})"


@case("d2 prefix+Shift+flechas intercambian cuadros")
def d2(lab):
    sb, other = pair(lab)
    lab.api("pane", "focus", "--direction", "left", "--pane", other)  # foco al cuadro izquierdo (sidebar)
    lab.pump(0.5)
    before = xs(lab, sb)
    lab.prefix("shift+right")
    lab.pump(1)
    after = xs(lab, sb)
    swapped = before[sb] < before[other] and after[sb] > after[other]
    return swapped, f"x antes {before} -> después {after}"


@case("e prefix+shift+r ejecuta el comando del repo (no reload_config)")
def e(lab):
    # El config de prueba añade un comando shell en prefix+shift+r que deja una marca.
    # Si herdr priorizara reload_config, la marca no aparecería.
    lab.prefix("R")
    ok = lab.wait_for(lambda: os.path.exists(lab.marker), 5)
    return bool(ok), "el comando del repo corrió" if ok else "prefix+shift+r no ejecutó el comando personalizado"


def main():
    if shutil.which("herdr") is None:
        print("SKIP herdr no está instalado")
        return 0
    lab = Lab()
    try:
        lab.prepare()
        # Caso e: cambia el binding de prefix+shift+r por un comando shell de prueba.
        cfg = lab.cfg
        cfg = re.sub(r'(key = "prefix\+shift\+r"\n)type = "plugin_action"\ncommand = "herdr-agent-usage.refresh"',
                     r'\1type = "shell"\ncommand = "touch ' + lab.marker + '"', cfg)
        open(lab.env["HERDR_CONFIG_PATH"], "w").write(cfg)
        lab.start_client()
        for fn in (a1, a2, b, c, d1, d2, e):
            fn(lab)
    finally:
        lab.stop()
    bad = [r for r in RESULTS if not r[1]]
    print(f"\nharness-behavior: {len(RESULTS) - len(bad)}/{len(RESULTS)} en PASS")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
