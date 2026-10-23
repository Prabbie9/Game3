#!/usr/bin/env python3
"""Bakes the Port Solano world: coastline, district layout, road graph, lots, heightmap, terrain splat and the
painted map. Deterministic. Writes assets/world/{height.bin, splat.png, world.json, map.png}.

Coordinates: metres, X east, Z south (north = -Z), ground of the flat city at y = 0, sea level SEA.
Run: python3 tools/world/gen_world.py   (≈1 min; needs numpy + Pillow)
"""
import json
import math
import os
import sys
import time

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from noise import fbm, smoothstep  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, "assets", "world")
HALF = 2048.0          # world spans [-HALF, HALF] on X and Z
STEP = 2.0             # heightmap spacing (m)
N = int(HALF * 2 / STEP) + 1  # 2049 samples per side
SEA = -2.0
H_MIN, H_MAX = -64.0, 192.0   # uint16 height encoding range
SIDEWALK = 4.0

T0 = time.time()


def log(msg):
    print(f"[gen_world {time.time() - T0:5.1f}s] {msg}", flush=True)


# ----------------------------------------------------------------------------------------- geometry helpers

def catmull(points, closed=False, sub=8):
    """Catmull-Rom spline through points -> dense polyline."""
    p = [np.array(q, dtype=float) for q in points]
    n = len(p)
    out = []
    rng = range(n) if closed else range(n - 1)
    for i in rng:
        p0 = p[(i - 1) % n] if closed or i > 0 else p[0]
        p1 = p[i]
        p2 = p[(i + 1) % n]
        p3 = p[(i + 2) % n] if closed or i + 2 < n else p[-1]
        for k in range(sub):
            t = k / sub
            t2, t3 = t * t, t * t * t
            out.append(0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2 + (-p0 + 3 * p1 - 3 * p2 + p3) * t3))
    if not closed:
        out.append(p[-1])
    return [tuple(q) for q in out]


def resample(poly, spacing):
    """Polyline -> points every `spacing` metres (keeps the end points)."""
    pts = [np.array(poly[0], dtype=float)]
    carry = 0.0
    for a, b in zip(poly[:-1], poly[1:]):
        a = np.array(a, dtype=float)
        b = np.array(b, dtype=float)
        seg = np.linalg.norm(b - a)
        if seg < 1e-6:
            continue
        d = spacing - carry
        while d < seg:
            pts.append(a + (b - a) * (d / seg))
            d += spacing
        carry = seg - (d - spacing)
    if np.linalg.norm(pts[-1] - np.array(poly[-1], dtype=float)) > spacing * 0.3:
        pts.append(np.array(poly[-1], dtype=float))
    else:
        pts[-1] = np.array(poly[-1], dtype=float)
    return [tuple(p) for p in pts]


def rounded_rect(x0, z0, x1, z1, r, sub=10):
    """Closed polyline (clockwise seen from above with north up) of a rectangle with rounded corners."""
    pts = []
    corners = [((x1 - r, z0 + r), -math.pi / 2, 0.0), ((x1 - r, z1 - r), 0.0, math.pi / 2),
               ((x0 + r, z1 - r), math.pi / 2, math.pi), ((x0 + r, z0 + r), math.pi, 1.5 * math.pi)]
    for (cx, cz), a0, a1 in corners:
        for k in range(sub + 1):
            a = a0 + (a1 - a0) * k / sub
            pts.append((cx + math.cos(a) * r, cz + math.sin(a) * r))
    return pts


def seg_dist(px, pz, ax, az, bx, bz):
    """Distance from points (arrays) to segment a-b, and the segment parameter t."""
    dx, dz = bx - ax, bz - az
    L2 = dx * dx + dz * dz
    t = np.clip(((px - ax) * dx + (pz - az) * dz) / max(L2, 1e-9), 0.0, 1.0)
    qx = ax + t * dx
    qz = az + t * dz
    return np.hypot(px - qx, pz - qz), t


# ----------------------------------------------------------------------------------------- layout: coastline

# Waterline (sea level) polygon, clockwise starting north-west. Docks form a straight quay with two piers.
COAST_CTRL = [
    (-930, -1120), (-760, -1260), (-380, -1300), (20, -1320), (420, -1340), (780, -1300), (1060, -1170),
    (1210, -880), (1250, -460), (1235, -40), (1205, 380), (1150, 700),
]
QUAY = [  # straight segments (no smoothing): east end of the port -> piers -> west end
    (1090, 850), (760, 850), (760, 1010), (680, 1010), (680, 850), (360, 850), (360, 1010), (280, 1010), (280, 850), (-60, 850),
]
COAST_TAIL = [(-200, 895), (-520, 885), (-760, 820), (-870, 620), (-905, 260), (-915, -160), (-920, -620)]


def coastline():
    north = catmull(COAST_CTRL + [QUAY[0]], sub=10)[:-1]
    tail = catmull([QUAY[-1]] + COAST_TAIL + [COAST_CTRL[0]], sub=10)[1:-1]
    poly = north + QUAY + tail
    # natural shores get a little irregularity; quay and beaches stay clean
    out = []
    for i, (x, z) in enumerate(poly):
        kind = coast_kind(x, z)
        if kind in ("natural", "cliff"):
            amp = 14.0 if kind == "cliff" else 8.0
            x += amp * math.sin(z * 0.031 + i * 0.7) * math.sin(x * 0.017 + 1.3)
            z += amp * math.sin(x * 0.029 + i * 0.3) * math.cos(z * 0.021)
        out.append((x, z))
    return out


def coast_kind(x, z):
    if z > 780 and x > -80:
        return "quay"
    if x < -800 or (z > 780 and x < -80):
        return "beach"
    if x > 1080 or (z < -1150 and x > 250):
        return "cliff"
    return "natural"


# ----------------------------------------------------------------------------------------- layout: roads

GRID = [-400 + 80 * i for i in range(11)]  # downtown street lines (x and z)
AVENUES = {-240, 0, 240}
RING = (-560, -500, 560, 500, 140)          # freeway: rounded rectangle x0, z0, x1, z1, corner radius
OCEAN_DRIVE_X = -740
HARBOR = [(-740, 700), (-260, 700), (-120, 640), (40, 610), (1080, 610)]
FRINGE_KINDS = ["parking", "mall", "midrise", "park", "midrise", "gas_station", "midrise", "parking"]
SUBURB_X = [-640, -520, -400, -280, -160, -40, 80, 200]
SUBURB_Z = [-560, -660, -760, -860, -960, -1060, -1160]
INDUSTRIAL_X = [700, 840, 980]
BEACH_STREETS_Z = [-360, -240, -120, 0, 120, 240, 360]
CANYON = [(360, -500), (372, -590), (450, -650), (560, -640), (660, -690), (640, -790), (700, -880), (790, -900), (840, -850)]
LOOKOUT = (840, -850)


class Graph:
    def split_long(self, max_len=160.0, piece=110.0):
        """Cut long (already profiled, [x, y, z]) roads into pieces with extra degree-2 nodes so each piece
        streams with its own cell; the new nodes take the profile's height."""
        out = []
        for rd in self.roads:
            pts = rd["pts"]
            L = sum(math.hypot(b[0] - a[0], b[2] - a[2]) for a, b in zip(pts[:-1], pts[1:]))
            if L <= max_len:
                out.append(rd)
                continue
            dense = _resample3(pts, 10.0) if len(pts) < 6 else [list(p) for p in pts]
            n = max(int(round(L / piece)), 2)
            target = L / n
            seg = [dense[0]]
            acc = 0.0
            for i in range(1, len(dense)):
                a, b = dense[i - 1], dense[i]
                acc += math.hypot(b[0] - a[0], b[2] - a[2])
                seg.append(b)
                if acc >= target and i < len(dense) - 1:
                    out.append(self._piece(rd, seg))
                    seg = [b]
                    acc = 0.0
            if len(seg) > 1:
                out.append(self._piece(rd, seg))
        self.roads = out

    def _piece(self, rd, seg):
        a = self.node(seg[0][0], seg[0][2])
        b = self.node(seg[-1][0], seg[-1][2])
        for idx, p in ((a, seg[0]), (b, seg[-1])):
            if len(self.nodes[idx]) < 3:
                self.nodes[idx].append(float(p[1]))
        return {**rd, "a": a, "b": b, "pts": [list(map(float, p)) for p in seg]}

    def __init__(self):
        self.nodes = []      # [x, z]
        self.index = {}
        self.roads = []      # dicts

    def node(self, x, z):
        key = (round(x, 1), round(z, 1))
        if key not in self.index:
            self.index[key] = len(self.nodes)
            self.nodes.append([float(x), float(z)])
        return self.index[key]

    def road(self, pts, w, lanes, kind, walk, name, spacing=None):
        """Polyline between two graph nodes (first/last points). Optionally resampled."""
        if spacing:
            pts = resample(pts, spacing)
        a = self.node(*pts[0])
        b = self.node(*pts[-1])
        self.roads.append({"a": a, "b": b, "pts": [list(map(float, p)) for p in pts], "w": w, "lanes": lanes,
                           "kind": kind, "walk": walk, "name": name})


STREET_NAMES = ["Alvarado", "Bayview", "Cabrillo", "Del Mar", "Encina", "Figueroa", "Grand", "Harbor View", "Isla",
                "Juniper", "Kestrel", "Laguna", "Marina", "Naranja", "Olivera", "Pacifica", "Quintana", "Ramona",
                "Serrano", "Toyon", "Ventura", "Willow", "Yucca", "Zuma"]


def build_roads():
    g = Graph()
    # downtown grid: avenues 14 m (2 lanes each way), streets 12 m
    for i, x in enumerate(GRID):
        w = 14.0 if x in AVENUES else 12.0
        for j in range(len(GRID) - 1):
            g.road([(x, GRID[j]), (x, GRID[j + 1])], w, 2 if w > 13 else 1, "avenue" if w > 13 else "street", True,
                   f"{STREET_NAMES[i]} {'Ave' if w > 13 else 'St'}")
    for j, z in enumerate(GRID):
        w = 14.0 if z in AVENUES else 12.0
        for i in range(len(GRID) - 1):
            g.road([(GRID[i], z), (GRID[i + 1], z)], w, 2 if w > 13 else 1, "avenue" if w > 13 else "street", True,
                   f"{j + 1}{'st' if j == 0 else 'nd' if j == 1 else 'rd' if j == 2 else 'th'} {'Ave' if w > 13 else 'St'}")
    # freeway ring, split at the junctions
    x0, z0, x1, z1, r = RING
    ring = rounded_rect(x0, z0, x1, z1, r, sub=12)
    ring.append(ring[0])
    ring = resample(ring, 10.0)
    junctions = []
    for a in AVENUES:
        junctions += [(a, z0), (a, z1), (x0, a), (x1, a)]
    junctions += [(x, z0) for x in (360,)]                     # canyon road
    junctions += [(x0, z) for z in BEACH_STREETS_Z if z not in AVENUES]
    junctions += [(x1, z) for z in (-120, 120, 360) if True]   # industrial streets
    _split_loop(g, ring, junctions, 24.0, 3, "freeway", False, "Solano Fwy")
    # avenues out to the ring (and beyond)
    for a in sorted(AVENUES):
        g.road([(a, -400), (a, z0)], 14.0, 2, "avenue", True, "")
        g.road([(a, 400), (a, z1)], 14.0, 2, "avenue", True, "")
        g.road([(-400, a), (x0, a)], 14.0, 2, "avenue", True, "")
        g.road([(400, a), (x1, a)], 14.0, 2, "avenue", True, "")
    # Ocean Drive (beach) N-S with the beach streets
    od = [(OCEAN_DRIVE_X, -1060), (OCEAN_DRIVE_X, -560)] + [(OCEAN_DRIVE_X, z) for z in BEACH_STREETS_Z] + [(OCEAN_DRIVE_X, 560), (OCEAN_DRIVE_X, 700)]
    od = sorted(set(od), key=lambda p: p[1])
    for a, b in zip(od[:-1], od[1:]):
        g.road([a, b], 16.0, 2, "drive", True, "Ocean Dr")
    for z in BEACH_STREETS_Z:
        g.road([(OCEAN_DRIVE_X, z), (x0, z)], 12.0 if z not in AVENUES else 14.0, 1 if z not in AVENUES else 2,
               "street" if z not in AVENUES else "avenue", True, "")
    # Harbor Blvd along the port, avenues down to it
    hb_nodes = [(OCEAN_DRIVE_X, 700), (-260, 700), (-240, 690)]
    harbor = catmull(HARBOR, sub=6)
    _split_line(g, harbor, [(-240, None), (0, None), (240, None)] + [(x, None) for x in INDUSTRIAL_X], 16.0, 2, "drive", True, "Harbor Blvd")
    for a in sorted(AVENUES):
        hz = _line_z_at(harbor, a)
        g.road([(a, z1), (a, hz)], 14.0, 2, "avenue", True, "")
    # industrial east: N-S streets from the avenue z=-240 down to Harbor Blvd, E-W streets from the ring
    for x in INDUSTRIAL_X:
        hz = _line_z_at(harbor, x)
        stops = sorted(set([-240, -120, 0, 120, 240, 360, hz]))
        for a, b in zip(stops[:-1], stops[1:]):
            g.road([(x, a), (x, b)], 14.0, 2, "street", True, "")
    hz = _line_z_at(harbor, 1100)
    stops = [-240, -120, 0, 120, 240, 360, 600]
    for a, b in zip(stops[:-1], stops[1:]):
        g.road([(1100, a), (1100, b)] if b != 600 else [(1100, a), (1100, 560), (1080, 610)], 12.0, 1, "street", True, "Eastside Rd")
    for z in (-240, -120, 0, 120, 240, 360):
        xs = [x1] + INDUSTRIAL_X + [1100]
        for a, b in zip(xs[:-1], xs[1:]):
            g.road([(a, z), (b, z)], 14.0 if z in AVENUES else 12.0, 2 if z in AVENUES else 1, "street", True, "")
    # suburbs: wavy streets north of the ring
    for zi, z in enumerate(SUBURB_Z):
        xs = [OCEAN_DRIVE_X] + SUBURB_X
        for a, b in zip(xs[:-1], xs[1:]):
            pts = [(a + (b - a) * k / 6.0, z + 6.0 * math.sin((a + (b - a) * k / 6.0) / 70.0 + zi)) for k in range(7)]
            pts[0] = (a, z)
            pts[-1] = (b, z)
            g.road(pts, 10.0, 1, "residential", True, "")
    for xi, x in enumerate(SUBURB_X):
        for a, b in zip(SUBURB_Z[:-1], SUBURB_Z[1:]):
            pts = [(x + 7.0 * math.sin((a + (b - a) * k / 5.0) / 60.0 + xi * 1.7), a + (b - a) * k / 5.0) for k in range(6)]
            pts[0] = (x, a)
            pts[-1] = (x, b)
            g.road(pts, 10.0, 1, "residential", True, "")
    for x in (-240, 0, 240):
        if any(abs(x - sx) < 1 for sx in SUBURB_X):
            continue
    for x in (-280, -40, 200):  # connectors ring -> Sunset Ave (z=-560)
        g.road([(x, -560), (x, z0)] if x != -280 else [(-280, -560), (-280, z0 + 20), (-240, z0)], 12.0, 1, "street", True, "")
    # canyon road up the hills
    g.road(catmull(CANYON, sub=8), 9.0, 1, "hill", False, "Canyon Rd", spacing=6.0)
    return g


def _split_loop(g, loop, junctions, w, lanes, kind, walk, name):
    """Closed polyline -> road edges between the loop points nearest to each junction."""
    pts = [np.array(p) for p in loop[:-1]]
    idx = []
    for jx, jz in junctions:
        d = [np.hypot(p[0] - jx, p[1] - jz) for p in pts]
        k = int(np.argmin(d))
        pts[k] = np.array([jx, jz], dtype=float) if d[k] < 12 else pts[k]
        idx.append(k)
    idx = sorted(set(idx))
    for a, b in zip(idx, idx[1:] + [idx[0] + len(pts)]):
        seg = [tuple(pts[k % len(pts)]) for k in range(a, b + 1)]
        g.road(seg, w, lanes, kind, walk, name)


def _line_z_at(line, x):
    for (ax, az), (bx, bz) in zip(line[:-1], line[1:]):
        if min(ax, bx) <= x <= max(ax, bx) and abs(bx - ax) > 1e-6:
            return az + (bz - az) * (x - ax) / (bx - ax)
    return line[-1][1]


def _split_line(g, line, cuts, w, lanes, kind, walk, name):
    """Open polyline split where it crosses x = cut (cuts given as (x, None))."""
    pts = list(line)
    out = []
    for (cx, _) in cuts:
        z = _line_z_at(pts, cx)
        out.append((cx, z))
    full = []
    for a, b in zip(pts[:-1], pts[1:]):
        full.append(a)
        for c in sorted([c for c in out if min(a[0], b[0]) < c[0] < max(a[0], b[0])], key=lambda c: abs(c[0] - a[0])):
            full.append(c)
    full.append(pts[-1])
    cut_set = {(round(c[0], 3), round(c[1], 3)) for c in out}
    seg = [full[0]]
    for p in full[1:]:
        seg.append(p)
        if (round(p[0], 3), round(p[1], 3)) in cut_set:
            g.road(seg, w, lanes, kind, walk, name)
            seg = [p]
    if len(seg) > 1:
        g.road(seg, w, lanes, kind, walk, name)


# ----------------------------------------------------------------------------------------- terrain

def _resample3(pts, spacing):
    """[x, y, z] polyline resampled every `spacing` metres (y interpolated)."""
    out = [list(pts[0])]
    for a, b in zip(pts[:-1], pts[1:]):
        L = math.hypot(b[0] - a[0], b[2] - a[2])
        k = max(int(L // spacing), 1)
        for j in range(1, k + 1):
            t = j / k
            out.append([a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t])
    return out


def rect_mask(X, Z, x0, z0, x1, z1, fall):
    return (smoothstep(x0 - fall, x0, X) * (1 - smoothstep(x1, x1 + fall, X)) *
            smoothstep(z0 - fall, z0, Z) * (1 - smoothstep(z1, z1 + fall, Z)))


def signed_coast_distance(poly, res=8.0):
    """Signed distance to the waterline (+ inland), computed on a coarse grid and upsampled."""
    n = int(HALF * 2 / res) + 1
    xs = np.linspace(-HALF, HALF, n)
    X, Z = np.meshgrid(xs, xs)
    P = np.array(poly + [poly[0]])
    dist = np.full(X.shape, 1e9)
    inside = np.zeros(X.shape, dtype=bool)
    for (ax, az), (bx, bz) in zip(P[:-1], P[1:]):
        d, _ = seg_dist(X, Z, ax, az, bx, bz)
        np.minimum(dist, d, out=dist)
        # crossing test (ray towards +x)
        cond = ((az > Z) != (bz > Z)) & (X < (bx - ax) * (Z - az) / (bz - az + 1e-12) + ax)
        inside ^= cond
    sd = np.where(inside, dist, -dist)
    # upsample to the heightmap grid
    img = Image.fromarray(sd.astype(np.float32), mode="F").resize((N, N), Image.BILINEAR)
    return np.asarray(img, dtype=np.float64)


def pool_rect():
    """The public pool in the palm plaza (block x -80..0, z 0..80, south-east quarter): x0, z0, x1, z1."""
    bx0, bx1 = -80 + 6 + SIDEWALK, 0 - 7 - SIDEWALK
    bz0, bz1 = 0 + 7 + SIDEWALK, 80 - 6 - SIDEWALK
    hw, hd = (bx1 - bx0) / 2, (bz1 - bz0) / 2
    cx = bx0 + hw + 2.5 + (hw - 2.5) / 2
    cz = bz0 + hd + 2.5 + (hd - 2.5) / 2
    return (cx - 6.0, cz - 3.25, cx + 6.0, cz + 3.25)


def build_terrain(coast, graph):
    xs = np.linspace(-HALF, HALF, N)
    X, Z = np.meshgrid(xs, xs)
    log("coast distance")
    d = signed_coast_distance(coast)
    # coast type masks
    beach = np.clip(smoothstep(-780, -820, X) * smoothstep(-1180, -1080, Z) + smoothstep(760, 800, Z) * smoothstep(-40, -120, X), 0, 1)
    quay = smoothstep(760, 800, Z) * smoothstep(-120, -40, X)
    cliff = np.clip(smoothstep(1040, 1100, X) + smoothstep(-1120, -1180, Z) * smoothstep(200, 300, X), 0, 1) * (1 - quay)
    natural = np.clip(1 - beach - quay - cliff, 0, 1)
    # shore profiles (land side) and seabed (water side)
    land_beach = SEA + 2.4 * smoothstep(0, 100, d)
    land_quay = np.where(d > 0, 0.0, SEA - 10.0)
    land_nat = SEA + 3.5 * smoothstep(0, 40, d)
    land_cliff = SEA + 30.0 * smoothstep(0, 32, d)
    sea_beach = SEA - np.minimum(-d * 0.045, 28.0)
    sea_quay = SEA - 10.0 - np.minimum(-d * 0.02, 18.0)
    sea_nat = SEA - np.minimum(1.0 - d * 0.12, 30.0)
    sea_cliff = SEA - np.minimum(6.0 - d * 0.3, 40.0)
    landp = beach * land_beach + quay * land_quay + natural * land_nat + cliff * land_cliff
    seap = beach * sea_beach + quay * sea_quay + natural * sea_nat + cliff * sea_cliff
    h = np.where(d >= 0, landp, seap)
    # relief: the NE hills, a gentle rise to the north, small undulation everywhere inland
    log("relief")
    hill_mask = smoothstep(-430, -680, Z) * smoothstep(330, 560, X)
    r2 = (X - 820) ** 2 + (Z + 860) ** 2
    hills = 120.0 * np.exp(-r2 / (2 * 290.0 ** 2)) + 55.0 * np.exp(-((X - 1050) ** 2 + (Z + 420) ** 2) / (2 * 190.0 ** 2))
    hills += 18.0 * fbm(X, Z, 1 / 260.0, 5, seed=7, ridged=True) * smoothstep(0, 60, hills)
    north = 9.0 * smoothstep(-560, -1100, Z) * (1 - hill_mask) + 2.5 * fbm(X, Z, 1 / 180.0, 3, seed=3)
    relief = hills * hill_mask + north * smoothstep(-470, -620, Z)
    relief += 1.2 * fbm(X, Z, 1 / 90.0, 3, seed=5)
    inland = smoothstep(0, 140, d)
    h = h + np.maximum(relief, 0) * inland * (1 - quay)
    # flat districts (ground at 0): downtown + freeway ring, port, industrial east, beachfront behind the sand
    log("flatten districts")
    flat = np.maximum.reduce([
        rect_mask(X, Z, -600, -540, 600, 540, 50),
        rect_mask(X, Z, -110, 560, 1100, 850, 30),
        rect_mask(X, Z, 560, -280, 1120, 640, 40),
        rect_mask(X, Z, -772, -1080, -560, 760, 25),
        rect_mask(X, Z, -760, 560, 0, 740, 40),
    ]) * (d > -2)
    h = h * (1 - flat) + 0.0 * flat
    # roads: profile heights along each road, then carve/fill the terrain under them
    log("roads")
    hmap = h.copy()
    for rd in graph.roads:
        _road_profile(rd, h, graph)
    for rd in graph.roads:
        _carve_road(rd, hmap)
    # the plaza pool's pit (its basin walls are city meshes; the terrain must not cover the water)
    px0, pz0, px1, pz1 = pool_rect()
    pit = (X > px0 - 0.6) & (X < px1 + 0.6) & (Z > pz0 - 0.6) & (Z < pz1 + 0.6)
    hmap[pit] = -2.3
    # lookout plateau
    lx, lz = LOOKOUT
    m = smoothstep(46, 30, np.hypot(X - lx, Z - lz))
    hmap = hmap * (1 - m) + m * _sample(hmap, lx, lz)
    return hmap, d, beach, X, Z


def _sample(h, x, z):
    fx = (x + HALF) / STEP
    fz = (z + HALF) / STEP
    i = int(np.clip(math.floor(fx), 0, N - 2))
    j = int(np.clip(math.floor(fz), 0, N - 2))
    tx = fx - i
    tz = fz - j
    return float(h[j, i] * (1 - tx) * (1 - tz) + h[j, i + 1] * tx * (1 - tz) + h[j + 1, i] * (1 - tx) * tz + h[j + 1, i + 1] * tx * tz)


def _road_profile(rd, h, graph):
    """Heights along a road: terrain under it smoothed, grade limited; end points pinned to node heights."""
    pts = rd["pts"]
    raw = np.array([max(_sample(h, p[0], p[1]), SEA + 1.0) for p in pts])
    if rd["kind"] in ("hill",):
        k = 7
        pad = np.pad(raw, k, mode="edge")
        sm = np.convolve(pad, np.ones(2 * k + 1) / (2 * k + 1), mode="same")[k:-k]
    else:
        sm = raw
    if graph is not None:
        for end, idx in ((0, rd["a"]), (len(pts) - 1, rd["b"])):
            node = graph.nodes[idx]
            if len(node) < 3:
                node.append(float(raw[end]))
            sm[end] = node[2]
    # grade limit (12 %, mountain roads 16 %) both directions
    grade = 0.16 if rd["kind"] == "hill" else 0.12
    dist = np.concatenate([[0], np.cumsum(np.hypot(np.diff([p[0] for p in pts]), np.diff([p[1] for p in pts])))])
    for _ in range(3):
        for i in range(1, len(sm)):
            lim = grade * (dist[i] - dist[i - 1])
            sm[i] = np.clip(sm[i], sm[i - 1] - lim, sm[i - 1] + lim)
        for i in range(len(sm) - 2, -1, -1):
            lim = grade * (dist[i + 1] - dist[i])
            sm[i] = np.clip(sm[i], sm[i + 1] - lim, sm[i + 1] + lim)
    rd["pts"] = [[p[0], float(y), p[1]] for p, y in zip(pts, sm)]   # -> [x, y, z]


def _carve_road(rd, h):
    """Flatten terrain across the road (plus sidewalks/shoulders) and blend embankments over 10 m."""
    half = rd["w"] * 0.5 + (SIDEWALK if rd["walk"] else 2.5)
    bank = 60.0 if rd["kind"] == "hill" else 10.0
    pts = rd["pts"]
    for p, q in zip(pts[:-1], pts[1:]):
        ax, ay, az = p
        bx, by, bz = q
        x0 = min(ax, bx) - half - bank
        x1 = max(ax, bx) + half + bank
        z0 = min(az, bz) - half - bank
        z1 = max(az, bz) + half + bank
        i0 = max(int((x0 + HALF) / STEP), 0)
        i1 = min(int((x1 + HALF) / STEP) + 2, N)
        j0 = max(int((z0 + HALF) / STEP), 0)
        j1 = min(int((z1 + HALF) / STEP) + 2, N)
        if i0 >= i1 or j0 >= j1:
            continue
        xs = -HALF + np.arange(i0, i1) * STEP
        zs = -HALF + np.arange(j0, j1) * STEP
        PX, PZ = np.meshgrid(xs, zs)
        dist, t = seg_dist(PX, PZ, ax, az, bx, bz)
        y = ay + (by - ay) * t  # terrain at the road surface (the road shader draws a hair in front)
        w = 1 - smoothstep(half, half + bank, dist)
        sub = h[j0:j1, i0:i1]
        h[j0:j1, i0:i1] = np.where(w > 0, sub * (1 - w) + y * w, sub)


# ----------------------------------------------------------------------------------------- lots

def build_lots(graph):
    """Building plots per district. Each lot: {kind, x0, z0, x1, z1, floors, yaw, seed} (rect in world x/z)."""
    lots = []
    rnd = np.random.default_rng(42)
    wmap = {}
    for x in GRID:
        wmap[x] = 14.0 if x in AVENUES else 12.0
    # downtown blocks
    for i in range(len(GRID) - 1):
        for j in range(len(GRID) - 1):
            xa, xb = GRID[i], GRID[i + 1]
            za, zb = GRID[j], GRID[j + 1]
            bx0 = xa + wmap[xa] / 2 + SIDEWALK
            bx1 = xb - wmap[xb] / 2 - SIDEWALK
            bz0 = za + wmap[za] / 2 + SIDEWALK
            bz1 = zb - wmap[zb] / 2 - SIDEWALK
            cx, cz = (xa + xb) / 2, (za + zb) / 2
            r = max(abs(cx), abs(cz))
            kind = "block"
            if (i, j) in ((6, 3), (2, 7), (7, 8)):
                kind = "park"
            elif (i, j) == (4, 5):
                kind = "plaza"
            lots.append({"kind": kind, "x0": bx0, "z0": bz0, "x1": bx1, "z1": bz1, "core": r < 170, "ring": int(r // 80),
                         "seed": int(rnd.integers(1 << 30))})
    # fringe between the downtown grid and the freeway: strips cut by the avenues -> big-footprint uses
    x0r, z0r, x1r, z1r, _ = RING
    edge = 400 + 6 + SIDEWALK
    cuts = [-560, -240, 0, 240, 560]
    k = 0
    for a, b in zip(cuts[:-1], cuts[1:]):
        for side in (-1, 1):
            # north/south strips (between z = +-edge and the ring), and west/east strips
            za, zb = (z0r + 12 + 4, -edge) if side < 0 else (edge, z1r - 12 - 4)
            lots.append({"kind": FRINGE_KINDS[k % len(FRINGE_KINDS)], "x0": max(a, -edge) + 7 + SIDEWALK, "z0": za,
                         "x1": min(b, edge) - 7 - SIDEWALK, "z1": zb, "seed": int(rnd.integers(1 << 30))})
            k += 1
            xa, xb = (x0r + 12 + 4, -edge) if side < 0 else (edge, x1r - 12 - 4)
            lots.append({"kind": FRINGE_KINDS[(k + 3) % len(FRINGE_KINDS)], "x0": xa, "z0": max(a, -edge) + 7 + SIDEWALK,
                         "x1": xb, "z1": min(b, edge) - 7 - SIDEWALK, "seed": int(rnd.integers(1 << 30))})
            k += 1
    # between the freeway's south leg and Harbor Blvd: warehouses and yards cut by the avenues
    for xa, xb in ((-520, -240), (-240, 0), (0, 240), (240, 540)):
        lots.append({"kind": "industrial", "x0": xa + 8 + SIDEWALK, "z0": z1r + 12 + 6, "x1": xb - 8 - SIDEWALK, "z1": 590,
                     "seed": int(rnd.integers(1 << 30))})
    # south-west: low-rise beach town between Ocean Drive's south end, Harbor Blvd and the ring
    for xa, xb in ((-740, -560), (-560, -400), (-400, -240)):
        lots.append({"kind": "beachfront", "x0": xa + 10 + SIDEWALK, "z0": 560 + 6 + SIDEWALK, "x1": xb - 8 - SIDEWALK,
                     "z1": 700 - 8 - SIDEWALK, "seed": int(rnd.integers(1 << 30))})
    # beachfront: blocks between Ocean Drive and the ring, cut by the beach streets
    zs = [-560] + BEACH_STREETS_Z + [560]
    for a, b in zip(zs[:-1], zs[1:]):
        lots.append({"kind": "beachfront", "x0": OCEAN_DRIVE_X + 8 + SIDEWALK, "z0": a + 6 + SIDEWALK, "x1": RING[0] - 12 - 6,
                     "z1": b - 6 - SIDEWALK, "seed": int(rnd.integers(1 << 30))})
    # industrial east
    xs = [RING[2]] + INDUSTRIAL_X + [1100]
    zs = [-240, -120, 0, 120, 240, 360, 560]
    for a, b in zip(xs[:-1], xs[1:]):
        for c, d in zip(zs[:-1], zs[1:]):
            lots.append({"kind": "industrial", "x0": a + 12 + 3, "z0": c + 7 + 3, "x1": b - 7 - 3, "z1": d - 7 - 3,
                         "seed": int(rnd.integers(1 << 30))})
    # port: container yard + sheds between Harbor Blvd and the quay; cranes on the quay
    for xa in range(-40, 1060, 220):  # in pieces so each streams with its own cell
        lots.append({"kind": "port_sheds", "x0": xa, "z0": 640, "x1": min(xa + 210, 1060), "z1": 700, "seed": 7 + xa})
        lots.append({"kind": "container_yard", "x0": xa, "z0": 712, "x1": min(xa + 210, 1060), "z1": 812, "seed": 8 + xa})
    for x in (100, 200, 450, 550, 850, 950):
        lots.append({"kind": "crane", "x0": x - 10, "z0": 822, "x1": x + 10, "z1": 846, "seed": x})
    # suburbs: house plots along every E-W street, both sides
    for zi, z in enumerate(SUBURB_Z):
        xs = [OCEAN_DRIVE_X] + SUBURB_X
        for a, b in zip(xs[:-1], xs[1:]):
            x = a + 16
            while x < b - 16:
                for side in (-1, 1):
                    if (z == SUBURB_Z[0] and side > 0) or (z == SUBURB_Z[-1] and side < 0):
                        continue
                    zc = z + 6.0 * math.sin(x / 70.0 + zi) + side * 22.0
                    lots.append({"kind": "house", "x0": x - 9, "z0": zc - 9, "x1": x + 9, "z1": zc + 9,
                                 "yaw": 0.0 if side > 0 else math.pi, "seed": int(rnd.integers(1 << 30))})
                x += 22.0 + float(rnd.uniform(0, 6))
    # beach: boardwalk along Ocean Drive's sand side, a pier at the end of the main avenue, lifeguard towers
    for za in range(-1040, 680, 200):  # in pieces so each streams with its own cell
        lots.append({"kind": "boardwalk", "x0": OCEAN_DRIVE_X - 8 - SIDEWALK - 8, "z0": za, "x1": OCEAN_DRIVE_X - 8 - SIDEWALK,
                     "z1": min(za + 200, 680), "seed": 3 + za})
    lots.append({"kind": "pier", "x0": -1060, "z0": -6, "x1": OCEAN_DRIVE_X - 8 - SIDEWALK - 8, "z1": 6, "seed": 4})
    for z in range(-900, 640, 190):
        if abs(z) < 40:
            continue
        lots.append({"kind": "lifeguard", "x0": -858, "z0": z - 2, "x1": -854, "z1": z + 2, "seed": 100 + z})
    lx, lz = LOOKOUT
    lots.append({"kind": "lookout", "x0": lx - 18, "z0": lz - 18, "x1": lx + 18, "z1": lz + 18, "seed": 5})
    # mansions along the canyon road
    for (x, z, yaw) in ((520, -700, 0.3), (610, -735, 2.6), (735, -830, 1.2), (690, -950, 0.1)):
        lots.append({"kind": "mansion", "x0": x - 16, "z0": z - 14, "x1": x + 16, "z1": z + 14, "yaw": yaw, "seed": int(x)})
    return lots


# ----------------------------------------------------------------------------------------- splat + map

def build_nature(h, d, X, Z, graph, lots):
    """Where wild vegetation may grow (L8, 4 m/px): inland, away from roads, lots and the flat districts;
    clumped with noise and densest on the hills."""
    k = 2  # 2 m samples -> 4 m pixels
    hs = h[::k, ::k]
    ds = d[::k, ::k]
    Xs = X[::k, ::k]
    Zs = Z[::k, ::k]
    dens = smoothstep(20, 60, ds) * (hs > 0.5)
    hill = smoothstep(-430, -680, Zs) * smoothstep(330, 560, Xs)
    dens *= 0.35 + 0.65 * hill
    dens *= np.clip(0.4 + 0.9 * fbm(Xs, Zs, 1 / 120.0, 3, seed=21), 0, 1)
    flat = np.maximum.reduce([rect_mask(Xs, Zs, -600, -540, 600, 540, 10), rect_mask(Xs, Zs, -110, 560, 1100, 850, 10),
                              rect_mask(Xs, Zs, 560, -280, 1120, 640, 10), rect_mask(Xs, Zs, -772, -1080, -560, 760, 10),
                              rect_mask(Xs, Zs, -760, 560, 0, 740, 10), rect_mask(Xs, Zs, -760, -1180, 220, -540, 10)])
    dens *= 1 - flat
    step = STEP * k
    n = dens.shape[0]
    for rd in graph.roads:
        half = rd["w"] * 0.5 + 6.0
        for p, q in zip(rd["pts"][:-1], rd["pts"][1:]):
            x0 = int((min(p[0], q[0]) - half + HALF) / step)
            x1 = int((max(p[0], q[0]) + half + HALF) / step) + 2
            z0 = int((min(p[2], q[2]) - half + HALF) / step)
            z1 = int((max(p[2], q[2]) + half + HALF) / step) + 2
            x0, z0 = max(x0, 0), max(z0, 0)
            x1, z1 = min(x1, n), min(z1, n)
            if x0 >= x1 or z0 >= z1:
                continue
            dist, _ = seg_dist(Xs[z0:z1, x0:x1], Zs[z0:z1, x0:x1], p[0], p[2], q[0], q[2])
            dens[z0:z1, x0:x1] *= smoothstep(half, half + 4, dist)
    for l in lots:
        x0 = max(int((l["x0"] - 4 + HALF) / step), 0)
        x1 = min(int((l["x1"] + 4 + HALF) / step) + 1, n)
        z0 = max(int((l["z0"] - 4 + HALF) / step), 0)
        z1 = min(int((l["z1"] + 4 + HALF) / step) + 1, n)
        dens[z0:z1, x0:x1] = 0
    lx, lz = LOOKOUT
    dens *= smoothstep(50, 70, np.hypot(Xs - lx, Zs - lz))
    return (np.clip(dens, 0, 1) * 255).astype(np.uint8)


def build_splat(h, d, beach, X, Z, graph):
    """RGBA weights: R sand, G dry grass (hills), B rock, A green grass (lowlands, verges).
    Urban ground is drawn by the city meshes on top."""
    gy, gx = np.gradient(h, STEP)
    slope = np.hypot(gx, gy)
    sand = np.clip(beach * smoothstep(150, 90, d) * (d > -60), 0, 1)
    sand = np.maximum(sand, smoothstep(2.5, 0.5, h - SEA) * (d > -40) * (1 - smoothstep(780, 800, Z) * smoothstep(-120, -40, X)))
    rock = np.clip(smoothstep(0.7, 1.05, slope) + (h < SEA - 1.0) * 0.6, 0, 1)
    rest = np.clip(1 - sand - rock, 0, 1)
    low = smoothstep(16.0, 5.0, h) * smoothstep(0.35, 0.15, slope)
    lush = rest * np.clip(low * (0.75 + 0.5 * fbm(X, Z, 1 / 70.0, 3, seed=11)), 0, 1)
    dry = rest - lush
    s = np.stack([sand, dry, rock, lush], axis=-1)
    s = s / np.maximum(s.sum(axis=-1, keepdims=True), 1e-6)
    return (s * 255).astype(np.uint8)


def paint_map(coast, graph, lots, h, splat, size=2048):
    """GTA-style map image (north up) for the minimap/full map: water, land, parks, roads, buildings."""
    img = Image.new("RGB", (size, size), (34, 72, 96))
    k = size / (HALF * 2)

    def P(x, z):
        return ((x + HALF) * k, (z + HALF) * k)

    dr = ImageDraw.Draw(img)
    dr.polygon([P(*p) for p in coast], fill=(64, 70, 66))
    # terrain shading on land
    hs = np.asarray(Image.fromarray(h.astype(np.float32), mode="F").resize((size, size), Image.BILINEAR))
    gy, gx = np.gradient(hs)
    shade = np.clip(0.5 + (gx * -0.6 + gy * -0.6) * 0.05, 0.25, 1.0)
    base = np.asarray(img).astype(np.float32)
    land = (base[..., 0] == 64) & (base[..., 1] == 70)
    hill = np.clip(hs / 160.0, 0, 1)
    col = np.stack([64 + hill * 30, 70 + hill * 36, 66 + hill * 10], axis=-1) * shade[..., None] * 1.6
    base[land] = np.clip(col[land], 0, 255)
    sand = np.asarray(Image.fromarray(splat[..., 0]).resize((size, size), Image.BILINEAR)).astype(np.float32) / 255.0
    sand = np.where(land, sand, 0.0)[..., None]
    base = base * (1 - sand) + np.array([196, 180, 136], dtype=np.float32) * sand
    img = Image.fromarray(base.astype(np.uint8))
    dr = ImageDraw.Draw(img)
    for lot in lots:
        if lot["kind"] == "park":
            dr.rectangle([P(lot["x0"], lot["z0"]), P(lot["x1"], lot["z1"])], fill=(58, 92, 62))
    # beach sand band
    for rd in graph.roads:
        pts = [P(p[0], p[2]) for p in rd["pts"]]
        w = max(1, int(rd["w"] * k + (2 if rd["kind"] == "freeway" else 1)))
        dr.line(pts, fill=(28, 30, 33), width=w + 2, joint="curve")
    for rd in graph.roads:
        pts = [P(p[0], p[2]) for p in rd["pts"]]
        w = max(1, int(rd["w"] * k))
        col = (231, 196, 106) if rd["kind"] == "freeway" else (200, 200, 196) if rd["kind"] in ("avenue", "drive") else (168, 170, 168)
        dr.line(pts, fill=col, width=w, joint="curve")
    for lot in lots:
        if lot["kind"] in ("block", "beachfront", "industrial", "port_sheds", "house", "mansion", "mall", "midrise", "gas_station"):
            dr.rectangle([P(lot["x0"], lot["z0"]), P(lot["x1"], lot["z1"])], fill=(86, 90, 96))
        elif lot["kind"] in ("boardwalk", "pier"):
            dr.rectangle([P(lot["x0"], lot["z0"]), P(lot["x1"], lot["z1"])], fill=(150, 120, 90))
        elif lot["kind"] == "parking":
            dr.rectangle([P(lot["x0"], lot["z0"]), P(lot["x1"], lot["z1"])], fill=(74, 76, 80))
        elif lot["kind"] == "container_yard":
            dr.rectangle([P(lot["x0"], lot["z0"]), P(lot["x1"], lot["z1"])], fill=(98, 84, 74))
    return img


# ----------------------------------------------------------------------------------------- main

def main():
    os.makedirs(OUT, exist_ok=True)
    coast = coastline()
    log(f"coastline {len(coast)} pts")
    graph = build_roads()
    log(f"roads {len(graph.roads)} edges, {len(graph.nodes)} nodes")
    h, d, beach, X, Z = build_terrain(coast, graph)
    graph.split_long()
    log(f"roads split: {len(graph.roads)} edges")
    lots = build_lots(graph)
    log(f"lots {len(lots)}")
    # heights
    q = np.clip((h - H_MIN) / (H_MAX - H_MIN) * 65535.0, 0, 65535).astype("<u2")
    q.tofile(os.path.join(OUT, "height.bin"))
    splat = build_splat(h, d, beach, X, Z, graph)
    Image.fromarray(splat[:-1, :-1], mode="RGBA").save(os.path.join(OUT, "splat.png"), optimize=True)
    Image.fromarray(build_nature(h, d, X, Z, graph, lots)[:-1, :-1], mode="L").save(os.path.join(OUT, "nature.png"), optimize=True)
    paint_map(coast, graph, lots, h, splat).save(os.path.join(OUT, "map.png"), optimize=True)
    for n in graph.nodes:
        if len(n) < 3:
            n.append(round(_sample(h, n[0], n[1]), 3))
    world = {
        "half": HALF, "step": STEP, "n": N, "sea": SEA, "h_min": H_MIN, "h_max": H_MAX,
        "coast": [[round(x, 2), round(z, 2)] for x, z in coast],
        "nodes": [[round(v, 3) for v in n] for n in graph.nodes],
        "roads": [{**r, "pts": [[round(v, 3) for v in p] for p in r["pts"]]} for r in graph.roads],
        "lots": lots,
        "districts": [
            {"name": "Downtown", "x": 0, "z": 0}, {"name": "Playa Solano", "x": -820, "z": -100},
            {"name": "Port of Solano", "x": 500, "z": 760}, {"name": "Eastside", "x": 840, "z": 80},
            {"name": "Las Lomas", "x": -260, "z": -820}, {"name": "Mirador Hills", "x": 800, "z": -760},
        ],
        "lookout": list(LOOKOUT) + [round(_sample(h, *LOOKOUT), 2)],
        "pool": list(pool_rect()),
    }
    with open(os.path.join(OUT, "world.json"), "w") as f:
        json.dump(world, f, separators=(",", ":"))
    log("done: " + ", ".join(f"{n} {os.path.getsize(os.path.join(OUT, n)) / 1e6:.1f} MB" for n in ("height.bin", "splat.png", "nature.png", "map.png", "world.json")))


if __name__ == "__main__":
    main()
